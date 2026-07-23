<#
check-rules.ps1 - self-check gate for the Unified_Rules folder.

Checks (core docs = Unified_Rules/*.md; contrib/ gets link-check only, it is a historical record):
  1. Relative markdown links resolve to existing files.
  2. Numbered "## N." headings in each core doc are unique and gapless.
  3. Section references ("DOC.md §N", "DOC §N-M", bare "§N") point at existing headings.
  4. House text style: no em/en-dash, no "..." or ellipsis in prose (outside code spans/fences).

Exit codes: 0 = clean; 1 = violations found; 2 = internal error.
Usage: pwsh -File tools/check-rules.ps1
#>
$ErrorActionPreference = 'Stop'
try {
    $root = Split-Path $PSScriptRoot -Parent
    $coreDocs = @(Get-ChildItem -Path $root -Filter *.md -File)
    $contribDir = Join-Path $root 'contrib'
    $contribDocs = @()
    if (Test-Path -LiteralPath $contribDir) {
        $contribDocs = @(Get-ChildItem -Path $contribDir -Filter *.md -File)
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
    foreach ($doc in (@($coreDocs) + $contribDocs)) {
        $lineNo = 0
        foreach ($line in (Get-Content -LiteralPath $doc.FullName)) {
            $lineNo++
            foreach ($m in [regex]::Matches($line, '\[[^\]]*\]\(([^)\s]+)\)')) {
                $target = $m.Groups[1].Value
                if ($target -match '^(https?|mailto):' -or $target.StartsWith('#')) { continue }
                $file = ($target -split '#')[0]
                if (-not (Test-Path -LiteralPath (Join-Path $doc.DirectoryName $file))) {
                    $violations.Add("$($doc.Name):$($lineNo): broken link -> $target")
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

    if ($violations.Count -gt 0) {
        $violations | ForEach-Object { Write-Host "FAIL $_" }
        Write-Error "check-rules: $($violations.Count) violation(s)" -ErrorAction Continue
        exit 1
    }
    Write-Host "check-rules: OK ($($coreDocs.Count) core docs, $($contribDocs.Count) contrib docs)"
    exit 0
}
catch {
    Write-Error "check-rules: internal error: $_" -ErrorAction Continue
    exit 2
}
