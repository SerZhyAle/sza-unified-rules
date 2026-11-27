#requires -Version 7.0
<#
.SYNOPSIS
    Fast fixture tests for REPO-LAYOUT 0.12 rule 8 (public vs local repository contents boundary,
    SZA-LAY07, disk-mode checks in tools/check-compliance.ps1, and tools/check-public-repo-contents.ps1).

.DESCRIPTION
    Builds minimal scratch Git repositories under temp/CANONR-0244/ and invokes check-compliance.ps1
    in-process for speed. Covers:
      1. Clean public product repo: all local-class files exist on disk and are gitignored while public
         deliverables (including kit/CLAUDE.md, docs/guide.md, docs/DOCS_MAP.md, CHANGELOG.md) are tracked
         -> 0 findings across SZA-LAY07, SZA-RULES01/02/07/08/09, SZA-CTR01/03, SZA-MEM01.
      2. Disk-mode enforcement on gitignored files: bad gitignored CLAUDE.md, oversized gitignored
         docs/contracts/COPY.md, oversized gitignored memory/MEMORY.md and missing catalog mention fire
         SZA-RULES02, SZA-CTR01, SZA-CTR03, SZA-MEM01.
      3. Tracked local-class files fire grouped SZA-LAY07 errors across agent instructions, agent config,
         memory, workflow, local engineering, and all six portfolio-glue categories while never flagging
         tracked public files (kit/CLAUDE.md, docs/guide.md, docs/DOCS_MAP.md, CHANGELOG.md).
      4. Role exemptions: role canon-home and role internal with tracked agent/glue files emit 0 SZA-LAY07.
      5. Dated SZA-LAY07 exemption in .sza-canon.json with a path wildcard suppresses only the matched bucket.
      6. Custom profile paths (paths.specsDir, paths.releasesDir, paths.documentRegistry) tracked in Git
         fire SZA-LAY07, and tools/check-public-repo-contents.ps1 exits 1 on violation and 0 on clean.

    Exit codes: 0 all cases passed; 1 assertion failed.
#>
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$gate = Join-Path $repoRoot 'tools/check-compliance.ps1'
$wrapper = Join-Path $repoRoot 'tools/check-public-repo-contents.ps1'
$utf8 = [System.Text.UTF8Encoding]::new($false)

$scratch = Join-Path ([IO.Path]::GetTempPath()) ('sza-public-contents-' + [guid]::NewGuid().ToString('N'))
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
    $null = & git -C $Dir add -f -- @TrackPaths 2>&1
    $null = & git -C $Dir -c user.email=test@example.invalid -c user.name=Test commit -q -m 'init' 2>&1
}

function Invoke-Gate([string]$Dir, [string]$Only) {
    $raw = (& $gate -RepoRoot $Dir -Only $Only -Json 2>&1 | Out-String)
    return [pscustomobject]@{ code = $LASTEXITCODE; report = ($raw | ConvertFrom-Json) }
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

$localGitignore = @"
CLAUDE.md
AGENTS.md
GEMINI.md
.claude/
.agents/
.codex/
.gemini/
memory/
.sza-canon.json
.sza-profile.json
docs/contracts/
docs/DOCUMENT_REGISTRY.jsonl
docs/releases/
r0.ps1
r1.ps1
tools/harness.ps1
PLAN/
dev/
temp/
"@

$stampBase = '{"schemaVersion":"1.0","role":"product","canon":{"version":"2026.11.27.1","coreDigest":"0","model":"reference"},"overlay":["A"],"ledgerShape":"none"}'
$validClaude = "# Rules`nCanon: sza-unified-rules (reference). Contracts catalog: P:\Contracts.`n"
$validAgents = "Read CLAUDE.md in full; it is the authoritative agent contract. Area rules live in .claude/rules/*.md.`n"
$validPointer = "# REPO-LAYOUT - pointer`n`n| Field | Value |`n| --- | --- |`n| Contract | ``REPO-LAYOUT`` |`n| Version | 0.12 |`n"

try {
    Test-Case '1. clean public product repo with gitignored local files passes LAY07 and disk-mode checks' {
        $d = Join-Path $scratch 'r1'
        Write-Utf8 (Join-Path $d '.gitignore') $localGitignore
        Write-Utf8 (Join-Path $d 'README.md') "# Product`n"
        Write-Utf8 (Join-Path $d 'LICENSE') "MIT`n"
        Write-Utf8 (Join-Path $d 'CHANGELOG.md') "# Changelog`n"
        Write-Utf8 (Join-Path $d 'docs/guide.md') "# User Guide`n"
        Write-Utf8 (Join-Path $d 'docs/DOCS_MAP.md') "# Map`n"
        Write-Utf8 (Join-Path $d 'src/app.ps1') "Write-Output 'ok'`n"
        Write-Utf8 (Join-Path $d 'kit/CLAUDE.md') "# Product deliverable template`n"
        Init-GitRepo $d @('.gitignore', 'README.md', 'LICENSE', 'CHANGELOG.md', 'docs/guide.md', 'docs/DOCS_MAP.md', 'src/app.ps1', 'kit/CLAUDE.md')

        # Create every local-only file on disk (gitignored)
        Write-Utf8 (Join-Path $d '.sza-canon.json') $stampBase
        Write-Utf8 (Join-Path $d '.sza-profile.json') '{"version":"1"}'
        Write-Utf8 (Join-Path $d 'CLAUDE.md') $validClaude
        Write-Utf8 (Join-Path $d 'AGENTS.md') $validAgents
        Write-Utf8 (Join-Path $d '.claude/rules/area.md') "---`npaths:`n  - `"src/**`"`n---`n# Area`n"
        Write-Utf8 (Join-Path $d 'memory/MEMORY.md') "# Index`n- note`n"
        Write-Utf8 (Join-Path $d 'docs/contracts/REPO-LAYOUT.md') $validPointer
        Write-Utf8 (Join-Path $d 'docs/DOCUMENT_REGISTRY.jsonl') '{"path":"README.md"}'
        Write-Utf8 (Join-Path $d 'docs/releases/RELEASES.md') "# Releases`n"
        Write-Utf8 (Join-Path $d 'r0.ps1') "# launcher`n"
        Write-Utf8 (Join-Path $d 'tools/harness.ps1') "# forwarder`n"
        Write-Utf8 (Join-Path $d 'PLAN/S0001_x.md') "# ticket`n"
        Write-Utf8 (Join-Path $d 'dev/note.md') "# note`n"

        $res = Invoke-Gate $d 'SZA-LAY07,SZA-RULES01,SZA-RULES02,SZA-RULES07,SZA-RULES08,SZA-RULES09,SZA-CTR01,SZA-CTR03,SZA-MEM01'
        Assert ($res.code -eq 0 -and $res.report.findings.Count -eq 0) "expected 0 findings, got exit $($res.code): $($res.report.findings | ConvertTo-Json -Compress)"
    }

    Test-Case '2. disk-mode checks still catch defects in gitignored agent, contract and memory files' {
        $d = Join-Path $scratch 'r2'
        Write-Utf8 (Join-Path $d '.gitignore') $localGitignore
        Write-Utf8 (Join-Path $d 'README.md') "# Product`n"
        Write-Utf8 (Join-Path $d 'LICENSE') "MIT`n"
        Init-GitRepo $d @('.gitignore', 'README.md', 'LICENSE')

        Write-Utf8 (Join-Path $d '.sza-canon.json') $stampBase
        Write-Utf8 (Join-Path $d 'CLAUDE.md') "# Local rules without canon pointer or catalog path`n"
        Write-Utf8 (Join-Path $d 'docs/contracts/COPY.md') ((1..50 | ForEach-Object { "line $_ of copied prose" }) -join "`n")
        Write-Utf8 (Join-Path $d 'memory/MEMORY.md') ((1..60 | ForEach-Object { "- item $_ " + ('x' * 160) }) -join "`n")

        $res = Invoke-Gate $d 'SZA-LAY07,SZA-RULES02,SZA-CTR01,SZA-CTR03,SZA-MEM01'
        $ids = @($res.report.findings | ForEach-Object id)
        Assert ($ids -notcontains 'SZA-LAY07') "unexpected SZA-LAY07 when local files are gitignored: $($ids -join ', ')"
        foreach ($want in 'SZA-RULES02', 'SZA-CTR01', 'SZA-CTR03', 'SZA-MEM01') {
            Assert ($ids -contains $want) "expected $want from gitignored disk files; got: $($ids -join ', ')"
        }
    }

    Test-Case '3. tracked local-class files fire grouped SZA-LAY07 errors while public files stay clean' {
        $d = Join-Path $scratch 'r3'
        $files = [ordered]@{
            'README.md'                     = "# Product`n"
            'LICENSE'                       = "MIT`n"
            'CHANGELOG.md'                  = "# Changelog`n"
            'docs/guide.md'                 = "# Guide`n"
            'docs/DOCS_MAP.md'              = "# Map`n"
            'kit/CLAUDE.md'                 = "# Public kit deliverable`n"
            'CLAUDE.md'                     = $validClaude
            'AGENTS.md'                     = $validAgents
            '.claude/settings.json'         = '{}'
            '.claude/rules/a.md'            = '# a'
            'memory/MEMORY.md'              = '# mem'
            '.sza-canon.json'               = $stampBase
            '.sza-profile.json'             = '{"version":"1"}'
            'docs/contracts/REPO-LAYOUT.md' = $validPointer
            'docs/contracts/README.md'      = '# idx'
            'docs/DOCUMENT_REGISTRY.jsonl'  = '{"path":"README.md"}'
            'docs/releases/RELEASES.md'     = '# rel'
            'r0.ps1'                        = '# r0'
            'tools/harness.ps1'             = '# fwd'
            'PLAN/S0001_a.md'               = '# spec'
            'dev/notes.md'                  = '# dev'
        }
        foreach ($k in $files.Keys) { Write-Utf8 (Join-Path $d $k) $files[$k] }
        Init-GitRepo $d @($files.Keys)

        $res = Invoke-Gate $d 'SZA-LAY07'
        Assert ($res.code -eq 1) "expected exit 1 for tracked local files, got $($res.code)"
        $paths = @($res.report.findings | Where-Object { $_.id -eq 'SZA-LAY07' -and $_.severity -eq 'error' } | ForEach-Object path)
        $expectedBuckets = @('CLAUDE.md', 'AGENTS.md', '.claude/', 'memory/', '.sza-canon.json', '.sza-profile.json',
            'docs/contracts/', 'docs/DOCUMENT_REGISTRY.jsonl', 'docs/releases/', 'r0.ps1', 'tools/harness.ps1', 'PLAN/', 'dev/')
        foreach ($b in $expectedBuckets) {
            Assert ($paths -contains $b) "expected SZA-LAY07 bucket '$b'; got: $($paths -join ', ')"
        }
        foreach ($pub in 'README.md', 'LICENSE', 'CHANGELOG.md', 'docs/guide.md', 'docs/DOCS_MAP.md', 'kit/CLAUDE.md') {
            Assert ($paths -notcontains $pub) "public file '$pub' was falsely flagged by SZA-LAY07"
        }
    }

    Test-Case '4. canon-home and internal roles are exempt from SZA-LAY07' {
        foreach ($role in 'canon-home', 'internal') {
            $d = Join-Path $scratch "r4-$role"
            $st = $stampBase.Replace('"role":"product"', "`"role`":`"$role`"")
            Write-Utf8 (Join-Path $d '.sza-canon.json') $st
            Write-Utf8 (Join-Path $d 'CLAUDE.md') $validClaude
            Write-Utf8 (Join-Path $d '.claude/rules/a.md') '# a'
            Write-Utf8 (Join-Path $d 'docs/contracts/REPO-LAYOUT.md') $validPointer
            Write-Utf8 (Join-Path $d 'docs/releases/RELEASES.md') '# rel'
            Init-GitRepo $d @('.sza-canon.json', 'CLAUDE.md', '.claude/rules/a.md', 'docs/contracts/REPO-LAYOUT.md', 'docs/releases/RELEASES.md')

            $res = Invoke-Gate $d 'SZA-LAY07'
            Assert ($res.code -eq 0 -and $res.report.findings.Count -eq 0) "role '$role' must be exempt from SZA-LAY07; got $($res.report.findings | ConvertTo-Json -Compress)"
        }
    }

    Test-Case '5. dated SZA-LAY07 path exemption suppresses only the matched bucket' {
        $d = Join-Path $scratch 'r5'
        $st = '{"schemaVersion":"1.0","role":"product","canon":{"version":"2026.11.27.1","coreDigest":"0","model":"reference"},"overlay":["A"],"ledgerShape":"none","exemptions":[{"id":"SZA-LAY07","path":"docs/releases/*","reason":"temporary migration debt"}]}'
        Write-Utf8 (Join-Path $d '.sza-canon.json') $st
        Write-Utf8 (Join-Path $d 'docs/releases/RELEASES.md') '# rel'
        Write-Utf8 (Join-Path $d 'CLAUDE.md') $validClaude
        Init-GitRepo $d @('docs/releases/RELEASES.md', 'CLAUDE.md')

        $res = Invoke-Gate $d 'SZA-LAY07'
        $paths = @($res.report.findings | ForEach-Object path)
        Assert ($paths -notcontains 'docs/releases/') "exempted docs/releases/ should be suppressed; got $($paths -join ', ')"
        Assert ($paths -contains 'CLAUDE.md') "non-exempted CLAUDE.md must still be flagged; got $($paths -join ', ')"
    }

    Test-Case '6. custom profile paths are caught and check-public-repo-contents.ps1 returns 1 then 0' {
        $d = Join-Path $scratch 'r6'
        Write-Utf8 (Join-Path $d '.gitignore') ".sza-canon.json`n.sza-profile.json`n"
        Write-Utf8 (Join-Path $d '.sza-canon.json') $stampBase
        Write-Utf8 (Join-Path $d '.sza-profile.json') '{"version":"1","paths":{"specsDir":"custom_specs","releasesDir":"releases","documentRegistry":"custom/REG.jsonl"}}'
        Write-Utf8 (Join-Path $d 'custom_specs/S0001_a.md') '# spec'
        Write-Utf8 (Join-Path $d 'releases/RELEASES.md') '# rel'
        Write-Utf8 (Join-Path $d 'custom/REG.jsonl') '{}'
        Write-Utf8 (Join-Path $d 'README.md') '# r'
        Init-GitRepo $d @('.gitignore', 'README.md', 'custom_specs/S0001_a.md', 'releases/RELEASES.md', 'custom/REG.jsonl')

        $res = Invoke-Gate $d 'SZA-LAY07'
        $paths = @($res.report.findings | ForEach-Object path)
        foreach ($want in 'custom_specs/', 'releases/', 'custom/REG.jsonl') {
            Assert ($paths -contains $want) "expected custom profile path '$want' in SZA-LAY07; got $($paths -join ', ')"
        }
        $null = & $wrapper -RepoRoot $d 2>&1
        Assert ($LASTEXITCODE -eq 1) "wrapper expected exit 1 on violation, got $LASTEXITCODE"

        $null = & git -C $d rm --cached -q -r custom_specs releases custom/REG.jsonl 2>&1
        Write-Utf8 (Join-Path $d '.gitignore') ".sza-canon.json`n.sza-profile.json`ncustom_specs/`nreleases/`ncustom/REG.jsonl`n"
        $null = & git -C $d add .gitignore 2>&1
        $null = & git -C $d commit -q -m 'untrack local paths' 2>&1
        $null = & $wrapper -RepoRoot $d 2>&1
        Assert ($LASTEXITCODE -eq 0) "wrapper expected exit 0 after git rm --cached, got $LASTEXITCODE"
    }
}
finally {
    if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
}

if ($script:failed -gt 0) {
    Write-Host "public-repo-contents.tests: FAILED ($($script:failed) failed, $($script:passed) passed)" -ForegroundColor Red
    exit 1
}
Write-Host "public-repo-contents.tests: OK ($($script:passed) cases)" -ForegroundColor Green
exit 0
