<#
check-rules.ps1 - self-check gate for the canon's own text.

Validates the canon; check-compliance.ps1 validates a project against it.

Checks (core docs = rules/*.md; contrib/ and contrib/history/ get link-check only - a facts record and its dated history):
  1. Relative markdown links resolve to existing files.
  2. Numbered "## N." headings in each core doc are unique and gapless.
  3. Section references ("DOC.md §N", "DOC §N-M", bare "§N") point at existing headings.
  4. House text style: no em/en-dash, no "..." or ellipsis in prose (outside code spans/fences).
  5. Every skills/<name>/SKILL.md carries a frontmatter block its host can read: closed, YAML-safe, with a
     non-empty name and description, the description 1024 characters at most.

Exit codes: 0 = clean; 1 = violations found; 2 = internal error.
Usage: pwsh -File tools/check-rules.ps1
#>
$ErrorActionPreference = 'Stop'

# One skill's frontmatter, judged as the host's YAML reader would judge it: a block that does not parse loads as
# empty metadata and the skill is not listed, and a host drops a description over the limit. PowerShell ships no
# YAML reader, so only a stated subset is read - 'key: value' on one line (plain, 'single' or "double" quoted) and
# a block value ('>' or '|') - and every other form is reported, valid YAML included. A new form is taught here
# before it ships. Emits one '<line>: <reason>' string per problem and nothing for a good file.
function Test-SkillFrontmatter {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    $maxDescription = 1024

    $lines = @($Text -split "\r?\n")
    if ($lines[0] -notmatch '^--- *$') { return "1: no frontmatter - the first line is not '---'" }
    $end = 0
    for ($i = 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^--- *$') { $end = $i; break }
    }
    if (-not $end) { return "1: the frontmatter is not closed - there is no second '---' line" }
    for ($i = 1; $i -lt $end; $i++) {
        # U+0085, U+2028 and U+2029 are line breaks to a YAML 1.1 reader, a byte order mark belongs to the file start
        if ($lines[$i] -cmatch '[^\t\x20-\x7E -‧‪-﻾＀-�]') { "$($i + 1): a control character or a Unicode line break" }
    }

    $values = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
    $lineOf = @{}
    $i = 1
    while ($i -lt $end) {
        $line = $lines[$i]
        $no = $i + 1
        $i++
        if ($line -match '^ *(#.*)?$') { continue }
        $pair = [regex]::Match($line, '^([A-Za-z0-9_][A-Za-z0-9_.-]*):(?: +(.*))?$')
        if (-not $pair.Success) {
            "$($no): not a 'key: value' line (a space follows the colon; continuation and nested lines are not read)"
            continue
        }
        $key = $pair.Groups[1].Value
        $raw = $pair.Groups[2].Value.TrimEnd(' ')
        $value = $raw
        if ($values.ContainsKey($key)) { "$($no): the key '$key' is repeated" }

        if ($raw -cmatch '^[>|][+-]?$') {
            $block = [System.Collections.Generic.List[string]]::new()
            $indent = 0
            while ($i -lt $end) {
                $next = $lines[$i]
                if ($next -match '^ *$') { $block.Add(''); $i++; continue }
                $lead = $next.Length - $next.TrimStart(' ').Length
                if ($lead -eq 0 -or $lead -lt $indent) { break }
                if (-not $indent) { $indent = $lead }
                $block.Add($next.Substring($indent))
                $i++
            }
            $value = ($block -join ' ').Trim()
        }
        elseif ($raw.StartsWith("'")) {
            $quoted = [regex]::Match($raw, "^'((?:[^']|'')*)'(?: +#.*)?$")
            if ($quoted.Success) { $value = $quoted.Groups[1].Value.Replace("''", "'") }
            else { "$($no): $key - the single-quoted value is not one closed string (write an apostrophe inside it twice)" }
        }
        elseif ($raw.StartsWith('"')) {
            $escape = '\\(?:[0abtnvfre "/\\N_LP\t]|x[0-9A-Fa-f]{2}|u[0-9A-Fa-f]{4}|U[0-9A-Fa-f]{8})'
            $quoted = [regex]::Match($raw, ('^"((?:[^"\\]|' + $escape + ')*)"(?: +#.*)?$'))
            # one character per escape: only emptiness and length are judged
            if ($quoted.Success) { $value = [regex]::Replace($quoted.Groups[1].Value, $escape, '_') }
            else { "$($no): $key - the double-quoted value is not one closed string with valid escapes" }
        }
        elseif (-not $raw) {
            if ($key -cnotin 'name', 'description') { "$($no): $key - no value on its line (nested forms are not read)" }
        }
        elseif ($raw -match '^(?:[\[\]{},#&*!|>%@`]|[-?:](?: |$)|(?:=|<<)$)') {
            "$($no): $key - a plain value starts with a character YAML reads as syntax; quote the value"
        }
        elseif ($raw.Contains("`t")) {
            "$($no): $key - a tab inside a plain value; use spaces"
        }
        elseif ($raw -match ':(?:[ \t]|$)') {
            "$($no): $key - a colon before a space or at the end of a plain value is read as a nested key; quote the value or use ' - '"
        }
        elseif ($raw -match '[ \t]#') {
            "$($no): $key - YAML reads ' #' in a plain value as a comment and drops the rest; quote the value"
        }
        $values[$key] = $value
        $lineOf[$key] = $no
    }

    foreach ($key in 'name', 'description') {
        if (-not $values.ContainsKey($key)) { "1: '$key' is missing" }
        elseif (-not $values[$key].Trim()) { "$($lineOf[$key]): '$key' is empty" }
    }
    if ($values.ContainsKey('description') -and $values['description'].Length -gt $maxDescription) {
        "$($lineOf['description']): the description is $($values['description'].Length) characters, the limit is $maxDescription (a host drops a longer skill)"
    }
}

try {
    $root = Join-Path (Split-Path $PSScriptRoot -Parent) 'rules'
    $coreDocs = @(Get-ChildItem -Path $root -Filter *.md -File)
    $contribDir = Join-Path $root 'contrib'
    $contribDocs = @()
    if (Test-Path -LiteralPath $contribDir) {
        $contribDocs = @(Get-ChildItem -Path $contribDir -Filter *.md -File)
    }
    # The dated history of each record sits one folder down (rules/contrib/history/<project>.md), is appended
    # to and is read by no skill. It gets the same link check: a section moved there keeps a link only when
    # the link gained one more '../'.
    $historyDir = Join-Path $contribDir 'history'
    $historyDocs = @()
    if (Test-Path -LiteralPath $historyDir) {
        $historyDocs = @(Get-ChildItem -Path $historyDir -Filter *.md -File)
    }
    $violations = New-Object System.Collections.Generic.List[string]

    # Heading map per core doc: the numbers of "## N." sections, in file order.
    $headings = @{}
    foreach ($doc in $coreDocs) {
        $nums = @()
        foreach ($line in (Get-Content -LiteralPath $doc.FullName)) {
            if ($line -match '^## (\d+)\.') { $nums += [int]$Matches[1] }
        }
        $headings[$doc.Name] = $nums
    }

    # Check 2: unique + gapless numbering.
    foreach ($doc in $coreDocs) {
        $nums = $headings[$doc.Name]
        if ($nums.Count -eq 0) { continue }
        foreach ($d in ($nums | Group-Object | Where-Object Count -gt 1)) {
            $violations.Add("$($doc.Name): duplicate section number $($d.Name)")
        }
        $min = ($nums | Measure-Object -Minimum).Minimum
        $max = ($nums | Measure-Object -Maximum).Maximum
        for ($i = $min; $i -le $max; $i++) {
            if ($nums -notcontains $i) { $violations.Add("$($doc.Name): numbering gap - no section $i") }
        }
    }

    # Check 1: relative markdown links resolve.
    foreach ($doc in (@($coreDocs) + $contribDocs + $historyDocs)) {
        $label = if ($doc.Directory.Name -eq 'history') { "history/$($doc.Name)" } else { $doc.Name }
        $lineNo = 0
        foreach ($line in (Get-Content -LiteralPath $doc.FullName)) {
            $lineNo++
            foreach ($m in [regex]::Matches($line, '\[[^\]]*\]\(([^)\s]+)\)')) {
                $target = $m.Groups[1].Value
                if ($target -match '^(https?|mailto):' -or $target.StartsWith('#')) { continue }
                $file = ($target -split '#')[0]
                if (-not (Test-Path -LiteralPath (Join-Path $doc.DirectoryName $file))) {
                    $violations.Add("$($label):$($lineNo): broken link -> $target")
                }
            }
        }
    }

    # Check 3: § references. Lookback window may cross a line break (wrapped prose).
    foreach ($doc in $coreDocs) {
        $text = Get-Content -LiteralPath $doc.FullName -Raw
        foreach ($m in [regex]::Matches($text, '§(\d+)(?:-(\d+))?')) {
            $from = [int]$m.Groups[1].Value
            $to = if ($m.Groups[2].Success) { [int]$m.Groups[2].Value } else { $from }
            $start = [Math]::Max(0, $m.Index - 120)
            $window = $text.Substring($start, $m.Index - $start)
            $targetDoc = $doc.Name
            $tokens = [regex]::Matches($window, '([A-Z][A-Z_]{3,})(?:\.md)?')
            for ($t = $tokens.Count - 1; $t -ge 0; $t--) {
                $cand = $tokens[$t].Groups[1].Value + '.md'
                if ($cand -ne 'README.md' -and $headings.ContainsKey($cand)) { $targetDoc = $cand; break }
            }
            $lineNo = ($text.Substring(0, $m.Index) -split "`n").Count
            for ($n = $from; $n -le $to; $n++) {
                if ($headings[$targetDoc] -notcontains $n) {
                    $violations.Add("$($doc.Name):$($lineNo): reference to $targetDoc §$n but no '## $n.' heading exists there")
                }
            }
        }
    }

    # Check 4: house text style in core-doc prose.
    foreach ($doc in $coreDocs) {
        $inFence = $false
        $lineNo = 0
        foreach ($line in (Get-Content -LiteralPath $doc.FullName)) {
            $lineNo++
            if ($line -match '^\s*```') { $inFence = -not $inFence; continue }
            if ($inFence) { continue }
            $prose = [regex]::Replace($line, '`[^`]*`', '')
            if ($prose -match '[–—―]') {
                $violations.Add("$($doc.Name):$($lineNo): em/en-dash in prose (house style: plain '-')")
            }
            if ($prose -match '\.{3,}' -or $prose -match '…') {
                $violations.Add("$($doc.Name):$($lineNo): '...' in prose (house style: '..')")
            }
        }
    }

    # Check 5: every shipped skill has frontmatter its host can read.
    $skillGlob = Join-Path (Split-Path $PSScriptRoot -Parent) 'skills' '*' 'SKILL.md'
    $skillDocs = @(Get-ChildItem -Path $skillGlob -File -ErrorAction SilentlyContinue)
    foreach ($doc in $skillDocs) {
        $text = [System.IO.File]::ReadAllText($doc.FullName)
        foreach ($problem in @(Test-SkillFrontmatter -Text $text)) {
            $violations.Add("skills/$($doc.Directory.Name)/SKILL.md:$problem")
        }
    }

    if ($violations.Count -gt 0) {
        $violations | ForEach-Object { Write-Host "FAIL $_" }
        Write-Error "check-rules: $($violations.Count) violation(s)" -ErrorAction Continue
        exit 1
    }
    Write-Host "check-rules: OK ($($coreDocs.Count) core docs, $($contribDocs.Count) contrib docs, $($historyDocs.Count) history docs, $($skillDocs.Count) skills)"
    exit 0
}
catch {
    Write-Error "check-rules: internal error: $_" -ErrorAction Continue
    exit 2
}
