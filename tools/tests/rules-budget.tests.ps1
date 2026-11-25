#requires -Version 7.0
<#
.SYNOPSIS
    Fast fixture tests for check-compliance.ps1 agent-rules budget and memory-index checks
    (SZA-RULES07, SZA-RULES08, SZA-RULES09, SZA-MEM01).

.DESCRIPTION
    Creates minimal scratch repositories under the temp directory and runs check-compliance.ps1 with
    -Only SZA-RULES07,SZA-RULES08,SZA-RULES09,SZA-MEM01 -Json. Covers:
      1. Clean git repo: CLAUDE.md <= 20k, AGENTS.md with .claude/rules paragraph, untracked non-ignored
         path-scoped .claude/rules/*.md, committed memory/MEMORY.md <= 8k -> 0 findings.
      2. Untracked non-ignored .claude/rules/*.md in git repo: unscoped file summed into SZA-RULES07 warn,
         > 40k path-scoped file triggers SZA-RULES08 warn (not RULES07), missing AGENTS.md mention triggers
         SZA-RULES09 warn, committed memory/MEMORY.md > 8k chars (< 200 lines) triggers SZA-MEM01 warn.
      3. Non-git repo: GEMINI.md > 40k triggers SZA-RULES07 error; .claude/rules scanned on disk.
      4. Gitignored .claude/ with AGENTS.md-as-core: gitignored area files skipped by RULES07/08/09,
         clean AGENTS.md-as-core passes.
      5. Delegated read and @import: CLAUDE.md @import summed into RULES07; AGENTS.md delegating to CLAUDE.md
         summed cleanly.

    Exit codes: 0 all passed; 1 assertion failed.
#>
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$gate = Join-Path $repoRoot 'tools/check-compliance.ps1'
$utf8 = [System.Text.UTF8Encoding]::new($false)

$scratch = Join-Path ([IO.Path]::GetTempPath()) ('sza-rules-budget-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $scratch -Force
$script:passed = 0
$script:failed = 0

function Write-Utf8([string]$Path, [string]$Text) {
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent)) { $null = New-Item -ItemType Directory -Path $parent -Force }
    [IO.File]::WriteAllText($Path, $Text, $utf8)
}

function Init-GitRepo([string]$Dir, [string[]]$TrackPaths) {
    $null = & git -C $Dir init -q 2>&1
    $null = & git -C $Dir config user.email 'test@example.invalid' 2>&1
    $null = & git -C $Dir config user.name 'Test' 2>&1
    foreach ($p in $TrackPaths) { $null = & git -C $Dir add -- $p 2>&1 }
    $null = & git -C $Dir commit -q -m 'init' 2>&1
}

function Run-Gate([string]$Dir) {
    $raw = (& pwsh -NoProfile -File $gate -RepoRoot $Dir -Only SZA-RULES07,SZA-RULES08,SZA-RULES09,SZA-MEM01 -Json 2>&1) -join "`n"
    return ($raw | ConvertFrom-Json)
}

function Test-Case([string]$Name, [scriptblock]$Body) {
    try {
        & $Body
        $script:passed++
        Write-Host "PASS  $Name"
    }
    catch {
        $script:failed++
        Write-Host "FAIL  $Name - $_" -ForegroundColor Red
    }
}

function Assert([bool]$Cond, [string]$Msg) {
    if (-not $Cond) { throw $Msg }
}

$stampJson = '{"schemaVersion":"1.0","canon":{"version":"2026.11.25.5","coreDigest":"0","model":"reference"},"overlay":["none"],"ledgerShape":"none"}'
$coreHeader = "# Rules`nCanon: sza-unified-rules (reference).`n"
$delegStubWithArea = "Read CLAUDE.md in full; it is the authoritative agent contract.`nArea rules live in .claude/rules/*.md.`n"
$delegStubNoArea = "Read CLAUDE.md in full; it is the authoritative agent contract.`n"

try {
    Test-Case '1. clean git repo with untracked path-scoped area rule and small memory index' {
        $d = Join-Path $scratch 'r1'
        Write-Utf8 (Join-Path $d '.sza-canon.json') $stampJson
        Write-Utf8 (Join-Path $d 'CLAUDE.md') ($coreHeader + ('a' * 5000))
        Write-Utf8 (Join-Path $d 'AGENTS.md') $delegStubWithArea
        Write-Utf8 (Join-Path $d 'memory/MEMORY.md') ("# Index`n" + ('- item' * 50))
        Init-GitRepo $d @('.sza-canon.json', 'CLAUDE.md', 'AGENTS.md', 'memory/MEMORY.md')
        # Untracked, non-ignored path-scoped rule file
        Write-Utf8 (Join-Path $d '.claude/rules/area.md') ("---`npaths:`n  - `"src/**`"`n---`n" + ('r' * 5000))

        $res = Run-Gate $d
        Assert ($res.findings.Count -eq 0) "expected 0 findings, got $($res.findings.Count): $(($res.findings | ForEach-Object { $_.id + ':' + $_.severity }) -join ', ')"
    }

    Test-Case '2. untracked non-ignored .claude/rules triggers RULES07/08/09 and >8k MEMORY.md triggers MEM01' {
        $d = Join-Path $scratch 'r2'
        Write-Utf8 (Join-Path $d '.sza-canon.json') $stampJson
        Write-Utf8 (Join-Path $d 'CLAUDE.md') ($coreHeader + ('a' * 15000))
        Write-Utf8 (Join-Path $d 'AGENTS.md') $delegStubNoArea
        # 50 lines (< 200 lines) but > 8,000 characters
        Write-Utf8 (Join-Path $d 'memory/MEMORY.md') ((1..50 | ForEach-Object { "- entry $_ " + ('m' * 170) }) -join "`n")
        Init-GitRepo $d @('.sza-canon.json', 'CLAUDE.md', 'AGENTS.md', 'memory/MEMORY.md')
        # Untracked non-ignored unscoped rule (10k) + huge path-scoped rule (42k)
        # No paths: key in the frontmatter; the word in the body and a later --- line must not scope the file
        Write-Utf8 (Join-Path $d '.claude/rules/unscoped.md') ("---`ndescription: x`n---`nUse paths: here.`n`n---`n" + ('u' * 10000))
        Write-Utf8 (Join-Path $d '.claude/rules/huge.md') ("---`npaths:`n  - `"app/**`"`n---`n" + ('h' * 42000))

        $res = Run-Gate $d
        $byId = @{}
        foreach ($f in $res.findings) { $byId[$f.id] = $f }
        Assert ($byId.ContainsKey('SZA-RULES07') -and $byId['SZA-RULES07'].severity -eq 'warn') "expected SZA-RULES07 warn (unscoped 10k + core 15k = 25k, huge 42k excluded); got $($res.findings | ConvertTo-Json -Compress)"
        Assert ($byId['SZA-RULES07'].message -match 'unscoped\.md' -and $byId['SZA-RULES07'].message -notmatch 'huge\.md') "RULES07 detail wrong: $($byId['SZA-RULES07'].message)"
        Assert ($byId.ContainsKey('SZA-RULES08') -and $byId['SZA-RULES08'].severity -eq 'warn' -and $byId['SZA-RULES08'].path -eq '.claude/rules/huge.md') "expected SZA-RULES08 warn on huge.md"
        Assert ($byId.ContainsKey('SZA-RULES09') -and $byId['SZA-RULES09'].severity -eq 'warn') "expected SZA-RULES09 warn on AGENTS.md"
        Assert ($byId.ContainsKey('SZA-MEM01') -and $byId['SZA-MEM01'].severity -eq 'warn' -and $byId['SZA-MEM01'].message -match 'characters') "expected SZA-MEM01 char-budget warn"
    }

    Test-Case '3. non-git repo evaluates GEMINI.md > 40k hard limit and disk .claude/rules' {
        $d = Join-Path $scratch 'r3'
        Write-Utf8 (Join-Path $d '.sza-canon.json') $stampJson
        Write-Utf8 (Join-Path $d 'CLAUDE.md') ($coreHeader + ('a' * 5000))
        Write-Utf8 (Join-Path $d 'AGENTS.md') $delegStubNoArea
        Write-Utf8 (Join-Path $d 'GEMINI.md') ($coreHeader + ('g' * 41000))
        Write-Utf8 (Join-Path $d '.claude/rules/local.md') ("---`npaths:`n  - `"x/**`"`n---`n" + ('k' * 1000))

        $res = Run-Gate $d
        $byId = @{}
        foreach ($f in $res.findings) { $byId[$f.id] = $f }
        Assert ($byId.ContainsKey('SZA-RULES07') -and $byId['SZA-RULES07'].severity -eq 'error' -and $byId['SZA-RULES07'].path -eq 'GEMINI.md') "expected SZA-RULES07 error on GEMINI.md; got $($res.findings | ConvertTo-Json -Compress)"
        Assert ($byId.ContainsKey('SZA-RULES09')) "expected SZA-RULES09 from disk .claude/rules in non-git repo"
    }

    Test-Case '4. gitignored .claude/ is skipped and AGENTS.md-as-core passes cleanly' {
        $d = Join-Path $scratch 'r4'
        Write-Utf8 (Join-Path $d '.sza-canon.json') $stampJson
        Write-Utf8 (Join-Path $d '.gitignore') ".claude/`n"
        Write-Utf8 (Join-Path $d 'AGENTS.md') ($coreHeader + ('a' * 10000))
        Init-GitRepo $d @('.sza-canon.json', '.gitignore', 'AGENTS.md')
        # Gitignored giant unscoped rule must be skipped completely
        Write-Utf8 (Join-Path $d '.claude/rules/ignored.md') ('z' * 50000)

        $res = Run-Gate $d
        Assert ($res.findings.Count -eq 0) "expected 0 findings for AGENTS.md-as-core with gitignored .claude/, got: $($res.findings | ConvertTo-Json -Compress)"
    }

    Test-Case '5. @import and delegated root file are summed in SZA-RULES07' {
        $d = Join-Path $scratch 'r5'
        Write-Utf8 (Join-Path $d '.sza-canon.json') $stampJson
        Write-Utf8 (Join-Path $d 'extra.md') ('e' * 14000)
        Write-Utf8 (Join-Path $d 'CLAUDE.md') ($coreHeader + "@extra.md`n" + ('c' * 10000))
        Write-Utf8 (Join-Path $d 'AGENTS.md') ($delegStubWithArea + ('d' * 10500))

        $res = Run-Gate $d
        $r7 = @($res.findings | Where-Object id -eq 'SZA-RULES07')
        Assert ($r7.Count -eq 1 -and $r7[0].severity -eq 'warn' -and $r7[0].path -eq 'CLAUDE.md' -and $r7[0].message -match 'extra\.md') "expected SZA-RULES07 warn summing @extra.md; got $($res.findings | ConvertTo-Json -Compress)"
    }
}
finally {
    if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
}

if ($script:failed -gt 0) {
    Write-Host "rules-budget.tests: FAILED ($($script:failed) failed, $($script:passed) passed)" -ForegroundColor Red
    exit 1
}
Write-Host "rules-budget.tests: OK ($($script:passed) cases)" -ForegroundColor Green
exit 0
