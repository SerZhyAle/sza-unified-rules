#requires -Version 7.0
<#
.SYNOPSIS
    Cases for the skill frontmatter and SessionStart budget checks in tools/check-rules.ps1.

.DESCRIPTION
    A copy of the gate runs over two scratch trees, one holding only skills that must be refused and one holding only
    skills that must pass, so the whole file starts two child processes. Nothing outside the scratch folder is written.

      1. The refused tree exits 1.
      2. One case per refused skill: the gate names the file, the line and the reason.
      3. The refused tree also detects a SessionStart UTF-8 payload over budget.
      4. The accepted tree exits 0 and counts every skill: plain, quoted and block values, exactly 400 characters,
         CRLF endings, a byte order mark, extra keys, comments, and a SessionStart payload within budget.

    -KeepScratch leaves the two trees on disk and prints their folder.
#>
[CmdletBinding()]
param([switch] $KeepScratch)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$gate = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\check-rules.ps1'))

$run = 0; $passed = 0; $failed = 0
function Assert-That([bool] $Condition, [string] $Message) { if (-not $Condition) { throw $Message } }
function Run-Case([string] $Name, [scriptblock] $Body) {
    $script:run++
    Write-Host -NoNewline "CASE  $Name ... "
    try { & $Body; $script:passed++; Write-Host 'PASS' -ForegroundColor Green }
    catch { $script:failed++; Write-Host 'FAIL' -ForegroundColor Red; Write-Host "      $($_.Exception.Message)" -ForegroundColor DarkRed }
}

$scratch = Join-Path ([IO.Path]::GetTempPath()) ('skill-frontmatter-' + [guid]::NewGuid().ToString('N').Substring(0, 8))

function Invoke-Tree([string] $Tree, [Collections.IDictionary] $Skills, [switch] $OversizedPayload) {
    $root = Join-Path $scratch $Tree
    foreach ($dir in 'tools', 'rules', 'hooks', 'templates') {
        New-Item -ItemType Directory -Path (Join-Path $root $dir) -Force | Out-Null
    }
    $repoRoot = Split-Path (Split-Path $gate)
    Copy-Item -LiteralPath $gate -Destination (Join-Path $root 'tools')
    Copy-Item -LiteralPath (Join-Path $repoRoot 'hooks/session-start.ps1') -Destination (Join-Path $root 'hooks')
    Copy-Item -LiteralPath (Join-Path $repoRoot 'templates/.sza-canon.json') -Destination (Join-Path $root 'templates')
    $invariants = if ($OversizedPayload) { [string]::new([char]0x0416, 3900) } else { "# Invariants`n" }
    [IO.File]::WriteAllText((Join-Path $root 'rules' 'INVARIANTS.md'), $invariants)
    foreach ($name in $Skills.Keys) {
        $dir = Join-Path $root 'skills' $name
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $dir 'SKILL.md'), $Skills[$name])
    }
    $out = @(& pwsh -NoProfile -File (Join-Path $root 'tools' 'check-rules.ps1') 2>&1 | ForEach-Object { "$_" })
    return [pscustomobject]@{ code = $LASTEXITCODE; out = $out; text = ($out -join "`n") }
}

# A good skill file around the given frontmatter lines.
function New-Skill([string[]] $Front, [string] $Eol = "`n") { return ((@('---') + $Front + @('---', '', '# Body', '')) -join $Eol) }
function New-Described([string] $Description) { return (New-Skill 'name: case', "description: $Description") }

# name -> content, the line the gate must name, a part of the reason it must give
$refused = [ordered]@{
    'no-block'          = @("# Title`n", 1, 'no frontmatter')
    'empty-file'        = @('', 1, 'no frontmatter')
    'not-closed'        = @("---`nname: case`ndescription: text`n", 1, 'is not closed')
    'colon-space'       = @((New-Described 'Run a task through the lifecycle: triage, spec'), 3, 'colon before a space')
    'colon-end'         = @((New-Described 'Use when the owner says:'), 3, 'colon before a space')
    'hash-comment'      = @((New-Described 'Work the queue #1 first'), 3, "' #' in a plain value")
    'reserved-start'    = @((New-Described '[draft] text'), 3, 'reads as syntax')
    'open-single'       = @((New-Described "'never closed"), 3, 'single-quoted')
    'lone-apostrophe'   = @((New-Described "'the owner's words'"), 3, 'single-quoted')
    'open-double'       = @((New-Described '"never closed'), 3, 'double-quoted')
    'bad-escape'        = @((New-Described '"a path C:\Users"'), 3, 'valid escapes')
    'repeated-key'      = @((New-Skill 'name: case', 'description: one', 'description: two'), 4, 'is repeated')
    'tab-indent'        = @((New-Skill 'name: case', 'description: >', "`ttext"), 4, "not a 'key: value' line")
    'continuation'      = @((New-Skill 'name: case', 'description: first line', '  second line'), 4, "not a 'key: value' line")
    'no-space'          = @((New-Skill 'name: case', 'description:text'), 3, "not a 'key: value' line")
    'nested'            = @((New-Skill 'name: case', 'description: text', 'allowed-tools:'), 4, 'no value on its line')
    'control-char'      = @((New-Described "bell $([char]7) here"), 3, 'control character')
    'line-separator'    = @((New-Described "one $([char]0x2028) two"), 3, 'Unicode line break')
    'tab-in-plain'      = @((New-Described "one`ttwo"), 3, 'a tab inside a plain value')
    'value-indicator'   = @((New-Described '='), 3, 'reads as syntax')
    'missing-name'      = @((New-Skill 'description: text'), 1, "'name' is missing")
    'missing-text'      = @((New-Skill 'name: case'), 1, "'description' is missing")
    'empty-plain'       = @((New-Skill 'name: case', 'description:'), 3, "'description' is empty")
    'empty-quoted'      = @((New-Skill "name: ''", 'description: text'), 2, "'name' is empty")
    'empty-block'       = @((New-Skill 'name: case', 'description: >'), 3, "'description' is empty")
    'long-plain'        = @((New-Described ('a' * 401)), 3, '401 characters')
    'long-quoted'       = @((New-Described ('"' + ('a' * 401) + '"')), 3, '401 characters')
    'long-block'        = @((New-Skill 'name: case', 'description: |', ('  ' + ('a' * 400))), 3, '401 characters')
    'long-block-space'  = @((New-Skill 'name: case', 'description: |-', '  a', (' ' * 401)), 3, '401 characters')
}

$accepted = [ordered]@{
    'plain'          = (New-Described "Use on /sa, `"take S0123`", the owner's C# app, host:80 and a - dash")
    'exact-limit'    = (New-Described ('a' * 400))
    'quoted-limit'   = (New-Described ("'" + ('a' * 400) + "'"))
    'single'         = (New-Described "'Gates: spec, plan # and the owner''s call'")
    'double'         = (New-Described '"Gates: spec \"plan\" \\ \u0041 # done" # a comment')
    'folded'         = (New-Skill 'name: case', 'description: >-', '  Gates: spec', '', '    # indented text', '  and plan')
    'literal'        = (New-Skill 'name: case', 'description: |', '  Gates: spec')
    'extra-keys'     = (New-Skill '# a comment', 'name: case', '', 'description: text', 'allowed-tools: Read, Grep')
    'crlf'           = (New-Skill -Front 'name: case', 'description: text' -Eol "`r`n")
    'byte-order'     = ([string][char]0xFEFF + (New-Described 'text'))
    'cyrillic'       = (New-Described "Use on `"$([string]::new([char]0x0442, 8))`" too")
}

try {
    $bad = [ordered]@{}
    foreach ($name in $refused.Keys) { $bad[$name] = $refused[$name][0] }
    $r = Invoke-Tree 'refused' $bad -OversizedPayload

    Run-Case '1 the refused tree exits 1' {
        Assert-That ($r.code -eq 1) "exit $($r.code): $($r.text)"
    }
    # $skill, not $name: the case body runs inside Run-Case, whose $Name would shadow it.
    foreach ($skill in $refused.Keys) {
        $line = $refused[$skill][1]; $reason = $refused[$skill][2]
        Run-Case "2 refused: $skill" {
            $prefix = "FAIL skills/$skill/SKILL.md:${line}: "
            $hits = @($r.out | Where-Object { $_.StartsWith($prefix) -and $_.Contains($reason) })
            Assert-That ($hits.Count -ge 1) "expected '$prefix..$reason' | actual: $((@($r.out | Where-Object { $_.Contains("skills/$skill/") })) -join ' / ')"
        }
    }
    Run-Case '3 the UTF-8 payload exceeds the byte budget' {
        $other = @($r.out | Where-Object { $_.StartsWith('FAIL ') -and -not $_.StartsWith('FAIL skills/') })
        Assert-That ($other.Count -eq 1 -and $other[0] -match '^FAIL hooks/session-start\.ps1: payload \d+ UTF-8 bytes exceeds budget 7435$') $r.text
    }
    Run-Case '4 the accepted tree exits 0 and counts every skill' {
        $ok = Invoke-Tree 'accepted' $accepted
        Assert-That ($ok.code -eq 0) "exit $($ok.code): $($ok.text)"
        Assert-That ($ok.text.Contains("$($accepted.Count) skills")) $ok.text
        Assert-That ($ok.text -match 'SessionStart \d+/7435 UTF-8 bytes') $ok.text
    }
}
finally {
    if ($KeepScratch) { Write-Host "scratch kept: $scratch" }
    else { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host ''
Write-Host "skill-frontmatter: run=$run passed=$passed failed=$failed"
if ($failed -gt 0) { exit 1 }
exit 0
