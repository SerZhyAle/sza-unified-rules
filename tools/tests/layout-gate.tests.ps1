#requires -Version 7.0
<#
    Fixtures for REPO-LAYOUT: the names a program addresses, judged by the compliance gate on throwaway
    repositories built here. Rules 1, 2, 4 and 5 are exercised through the gate's LAY, RULES and CTR groups,
    each with a passing and a failing fixture; rule 6 (an archive is frozen) is checked by nothing in the
    gate, so what is exercised is the one writer that moves a record into an archive - the harness archive
    step - and that it moves the text unchanged, apart from the status line the ledger owns, and brings it back the same. Rule 3 (the type prefix)
    is checked by nothing and is not exercised here, as the adoption row says.

    What this proves: the gate names each violation by its finding id and stays silent on the conforming
    fixture. What it does not prove: the gate against a real repository (the portfolio run is
    `check-compliance` in each repo), or any rule the gate does not read.

    The FLOW cases (S0015 R39) exercise the gate's task-flow group, which runs only behind -CheckTaskFlow.

    -Case is a regular expression; a case whose name does not match it is not run and not counted.

    Exit codes: 0 all cases passed; 1 an assertion failed; 2 prerequisites unavailable.
#>
[CmdletBinding()]
param(
    [string]$SourceRoot = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent),
    [string]$Case,
    [switch]$KeepScratch
)

$ErrorActionPreference = 'Stop'
$run = 0
$failed = 0
$scratch = $null
$savedRoot = $env:SZA_PROJECT_ROOT

function Assert-That([bool]$Condition, [string]$Reason) { if (-not $Condition) { throw $Reason } }
function Test-Case([string]$Name, [scriptblock]$Body) {
    if ($Case -and $Name -notmatch $Case) { return }
    $script:run++
    try { & $Body; "OK $Name" }
    catch { $script:failed++; "FAIL $Name - $($_.Exception.Message)" }
}

# A conforming fixture: README, LICENSE and a stamp that declares no ledger shape. `Files` adds or replaces
# files (relative path -> text); a value of $null leaves that file out. -NoStamp leaves the stamp out.
function New-Fixture([string]$Name, [hashtable]$Stamp = @{}, [hashtable]$Files = @{}, [switch]$NoStamp) {
    $root = Join-Path $scratch $Name
    New-Item -ItemType Directory -Path $root | Out-Null
    & git -C $root init -q 2>&1 | Out-Null
    $doc = @{ schemaVersion = '1.0'; role = 'product' }
    foreach ($k in $Stamp.Keys) { $doc[$k] = $Stamp[$k] }
    $all = [ordered]@{ 'README.md' = '# fixture'; 'LICENSE' = 'MIT'; 'CLAUDE.md' = '# fixture rules' }
    foreach ($k in $Files.Keys) { $all[$k] = $Files[$k] }
    if (-not $NoStamp) { $doc | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $root '.sza-canon.json') -Encoding utf8 }
    foreach ($rel in $all.Keys) {
        if ($null -eq $all[$rel]) { continue }
        $path = Join-Path $root $rel
        New-Item -ItemType Directory -Path (Split-Path $path -Parent) -Force | Out-Null
        Set-Content -LiteralPath $path -Value $all[$rel] -Encoding utf8
    }
    return $root
}

# The finding ids the gate reports for one group of a fixture, as 'ID:severity'. The whole gate runs and the
# group is read by id prefix: -Only matches one exact id, and `pwsh -File` would bind a second id to the
# next positional parameter.
# `Extra` is appended to the gate's arguments (the FLOW cases pass -CheckTaskFlow).
$groupPrefix = @{ LAY = 'SZA-LAY'; RULES = 'SZA-RULES'; CTR = 'SZA-CTR'; FLOW = 'SZA-FLOW'; CANON = 'SZA-CANON' }
function Invoke-Gate([string]$Root, [string[]]$Extra = @()) {
    $output = & pwsh -NoProfile -File (Join-Path $SourceRoot 'tools/check-compliance.ps1') -RepoRoot $Root -Json @Extra 2>&1 | Out-String
    $code = $LASTEXITCODE
    $start = $output.IndexOf('{')
    if ($start -lt 0) { throw "the gate printed no report (exit $code): $($output.Trim())" }
    [pscustomobject]@{ Exit = $code; Report = ($output.Substring($start) | ConvertFrom-Json) }
}
function Get-Findings([string]$Root, [string]$Group, [string[]]$Extra = @()) {
    $report = (Invoke-Gate $Root $Extra).Report
    @($report.findings | Where-Object { $_.id -like "$($groupPrefix[$Group])*" } | ForEach-Object { "$($_.id):$($_.severity)" })
}
function Assert-Finding([string]$Root, [string]$Group, [string]$Expected, [string[]]$Extra = @()) {
    $found = Get-Findings $Root $Group $Extra
    Assert-That ($found -contains $Expected) "expected $Expected, the gate said: $($found -join ', ')"
}
function Assert-NoFinding([string]$Root, [string]$Group, [string]$IdPrefix, [string[]]$Extra = @()) {
    $found = @(Get-Findings $Root $Group $Extra | Where-Object { $_ -like "$IdPrefix*" })
    Assert-That ($found.Count -eq 0) "expected no $IdPrefix, the gate said: $($found -join ', ')"
}

try {
    if (-not (Test-Path -LiteralPath (Join-Path $SourceRoot 'tools/check-compliance.ps1'))) { throw 'Missing prerequisite: tools/check-compliance.ps1' }
    $scratch = Join-Path ([System.IO.Path]::GetTempPath()) ('s0013-layout-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $scratch | Out-Null

    # --- rule 4: README.md and LICENSE at the root -------------------------------------------------------
    Test-Case 'rule 4: a repository with README.md and LICENSE has no LAY01' {
        Assert-NoFinding (New-Fixture 'r4-ok') 'LAY' 'SZA-LAY01'
    }
    Test-Case 'rule 4: no README.md is an error' {
        Assert-Finding (New-Fixture 'r4-readme' -Files @{ 'README.md' = $null }) 'LAY' 'SZA-LAY01:error'
    }
    Test-Case 'rule 4: no LICENSE is an error, and LICENSE.md and LICENSE.txt both count' {
        Assert-Finding (New-Fixture 'r4-license' -Files @{ 'LICENSE' = $null }) 'LAY' 'SZA-LAY01:error'
        Assert-NoFinding (New-Fixture 'r4-license-md' -Files @{ 'LICENSE' = $null; 'LICENSE.md' = 'MIT' }) 'LAY' 'SZA-LAY01'
        Assert-NoFinding (New-Fixture 'r4-license-txt' -Files @{ 'LICENSE' = $null; 'LICENSE.txt' = 'MIT' }) 'LAY' 'SZA-LAY01'
    }

    # --- rule 5: a ledger exists where the stamp says it does ---------------------------------------------
    Test-Case 'rule 5: no declared shape asks for no ledger' {
        Assert-NoFinding (New-Fixture 'r5-none') 'LAY' 'SZA-LAY02'
    }
    Test-Case 'rule 5, shape 1: a root Keep-a-Changelog passes; a missing file and a file without [Unreleased] fail' {
        $keep = "# Changelog`n`n## [Unreleased]`n`n- nothing yet`n"
        Assert-NoFinding (New-Fixture 's1-ok' @{ ledgerShape = 1 } @{ 'CHANGELOG.md' = $keep }) 'LAY' 'SZA-LAY02'
        Assert-Finding (New-Fixture 's1-missing' @{ ledgerShape = 1 }) 'LAY' 'SZA-LAY02:error'
        Assert-Finding (New-Fixture 's1-shape' @{ ledgerShape = 1 } @{ 'CHANGELOG.md' = "# Changelog`n`n## 1.0.0`n" }) 'LAY' 'SZA-LAY02:error'
    }
    Test-Case 'rule 5, shape 2: DEV/CHANGELOG.md passes; its absence fails' {
        Assert-NoFinding (New-Fixture 's2-ok' @{ ledgerShape = 2 } @{ 'DEV/CHANGELOG.md' = '# dev log' }) 'LAY' 'SZA-LAY02'
        Assert-Finding (New-Fixture 's2-missing' @{ ledgerShape = 2 }) 'LAY' 'SZA-LAY02:error'
    }
    Test-Case 'rule 5, shape 3: ledgerFile must name a file that exists' {
        Assert-NoFinding (New-Fixture 's3-ok' @{ ledgerShape = 3; ledgerFile = 'docs/INVENTORY.md' } @{ 'docs/INVENTORY.md' = '# inventory' }) 'LAY' 'SZA-LAY02'
        Assert-Finding (New-Fixture 's3-missing' @{ ledgerShape = 3; ledgerFile = 'docs/INVENTORY.md' }) 'LAY' 'SZA-LAY02:error'
        Assert-Finding (New-Fixture 's3-unnamed' @{ ledgerShape = 3 }) 'LAY' 'SZA-LAY02:error'
    }
    Test-Case 'rule 5, shape 4: no root CHANGELOG.md, and a workflow that generates the release notes' {
        $wf = "name: release`njobs:`n  r:`n    steps:`n      - run: gh release create --generate_release_notes`n"
        Assert-NoFinding (New-Fixture 's4-ok' @{ ledgerShape = 4 } @{ '.github/workflows/release.yml' = $wf }) 'LAY' 'SZA-LAY02'
        Assert-Finding (New-Fixture 's4-two-ledgers' @{ ledgerShape = 4 } @{ 'CHANGELOG.md' = '# c'; '.github/workflows/release.yml' = $wf }) 'LAY' 'SZA-LAY02:error'
        Assert-Finding (New-Fixture 's4-no-proof' @{ ledgerShape = 4 }) 'LAY' 'SZA-LAY02:warn'
    }
    Test-Case 'docs index: three or more documents under docs/ with no docs/README.md is a warning' {
        $three = @{ 'docs/A.md' = '# a'; 'docs/B.md' = '# b'; 'docs/C.md' = '# c' }
        Assert-Finding (New-Fixture 'docs-noindex' -Files $three) 'LAY' 'SZA-LAY03:warn'
        $three['docs/README.md'] = '# index'
        Assert-NoFinding (New-Fixture 'docs-index' -Files $three) 'LAY' 'SZA-LAY03'
    }

    # --- rule 1: the agent-rules file is at the root and only the root counts -------------------------------
    Test-Case 'rule 1: a root CLAUDE.md, AGENTS.md or GEMINI.md is the agent-rules file' {
        foreach ($name in 'CLAUDE.md', 'AGENTS.md', 'GEMINI.md') {
            $files = @{ 'CLAUDE.md' = $null }
            $files[$name] = '# rules'
            Assert-NoFinding (New-Fixture "r1-$($name.Replace('.md', ''))" -Files $files) 'RULES' 'SZA-RULES01'
        }
    }
    Test-Case 'rule 1: a same-named file below the root is content, not rules' {
        $root = New-Fixture 'r1-nested' -Files @{ 'CLAUDE.md' = $null; 'templates/payload/CLAUDE.md' = '# a template payload'; 'AGENTS.md.bak' = 'x' }
        Assert-Finding $root 'RULES' 'SZA-RULES01:error'
    }

    # --- rule 2: docs/contracts/<ID>.md is a pointer, never a copy ------------------------------------------
    $pointer = "# STREAM-BANK - pointer`n`n| Field | Value |`n| --- | --- |`n| Contract | ``STREAM-BANK`` |`n| Version | 1.0 |`n"
    $longCopy = (1..60 | ForEach-Object { "line $_ of a restated contract" }) -join "`n"
    Test-Case 'rule 2: a short file that names its contract id is a pointer' {
        Assert-NoFinding (New-Fixture 'r2-pointer' -Files @{ 'docs/contracts/STREAM-BANK.md' = $pointer }) 'CTR' 'SZA-CTR01'
    }
    Test-Case 'rule 2: the older CONTRACT_<ID>.md spelling is read the same way' {
        Assert-NoFinding (New-Fixture 'r2-old-name' -Files @{ 'docs/contracts/CONTRACT_STREAM-BANK.md' = $pointer }) 'CTR' 'SZA-CTR01'
    }
    Test-Case 'rule 2: a long file with no contract id reads as a copy, and the index is exempt' {
        Assert-Finding (New-Fixture 'r2-copy' -Files @{ 'docs/contracts/STREAM-BANK.md' = $longCopy }) 'CTR' 'SZA-CTR01:warn'
        Assert-NoFinding (New-Fixture 'r2-index' -Files @{ 'docs/contracts/README.md' = $longCopy }) 'CTR' 'SZA-CTR01'
    }

    # --- rule 6: an archive is frozen -------------------------------------------------------------------------
    Test-Case 'rule 6: the harness archive step moves a spec file with its text unchanged beyond the status line, and a revival keeps it readable at the path its row names' {
        $harness = Join-Path $SourceRoot 'tools/harness'
        $project = Join-Path $scratch 'r6-archive'
        New-Item -ItemType Directory -Path $project | Out-Null
        $env:SZA_PROJECT_ROOT = $project
        & pwsh -NoProfile -File (Join-Path $harness 'scaffold/init-task-flow.ps1') -Root $project 2>&1 | Out-Null
        Assert-That ($LASTEXITCODE -eq 0) 'the scaffold failed'
        # Text the house style would "fix": `...`, an em dash and trailing spaces. A tool that tidied an archive would change them.
        $words = "an old note... with an em dash - and  trailing spaces   "
        & pwsh -NoProfile -File (Join-Path $harness 'spec_catalog/capture-draft.ps1') -Slug 'frozen' -Text $words 2>&1 | Out-Null
        Assert-That ($LASTEXITCODE -eq 0) 'capture-draft failed'
        $spec = Join-Path $project 'PLAN/S0001_frozen.md'
        function Get-Body([string]$Path) { (Get-Content -LiteralPath $Path -Raw) -replace '(?m)^\*\*Status:\*\*[^
]*', '**Status:** <any>' }
        $beforeBody = Get-Body $spec
        & pwsh -NoProfile -File (Join-Path $harness 'spec_catalog/archive.ps1') -Id S0001 2>&1 | Out-Null
        Assert-That ($LASTEXITCODE -eq 0) 'archive failed'
        $archived = Join-Path $project 'PLAN/archive/S0001_frozen.md'
        Assert-That (Test-Path -LiteralPath $archived) 'the spec file is not under PLAN/archive'
        Assert-That (-not (Test-Path -LiteralPath $spec)) 'the spec file is still under PLAN'
        # The tool keeps the header equal to the ledger (TASK-FLOW rule 4), so the status line is the one thing that may move.
        Assert-That ((Get-Body $archived) -eq $beforeBody) 'archiving changed the text of the spec file beyond its status line'
        & pwsh -NoProfile -File (Join-Path $harness 'spec_catalog/update.ps1') -Id S0001 -Status Draft 2>&1 | Out-Null
        Assert-That ($LASTEXITCODE -eq 0) 'revival failed'
        # A revival changes the row's status; the file stays where the row says it is and the ledger still validates.
        $row = Get-Content -LiteralPath (Join-Path $project 'PLAN/spec-catalog.jsonl') | ForEach-Object { $_ | ConvertFrom-Json } | Where-Object id -eq 'S0001'
        Assert-That ($row.status -eq 'Draft') "the revived row says $($row.status)"
        $revived = Join-Path $project $row.file
        Assert-That (Test-Path -LiteralPath $revived) "the revived row points at $($row.file), which does not exist"
        Assert-That ((Get-Body $revived) -eq $beforeBody) 'a revival changed the text of the spec file beyond its status line'
        & pwsh -NoProfile -File (Join-Path $harness 'spec_catalog/validate.ps1') 2>&1 | Out-Null
        Assert-That ($LASTEXITCODE -eq 0) 'the ledger does not validate after a revival'
    }

    # --- S0015 R39: stamped repositories need the task flow --------------------------------------------------
    # The group is advisory and off unless -CheckTaskFlow; Phase 09 of S0015 turns it on by default.
    $flowOn = @('-CheckTaskFlow')
    function Get-FlowFinding($Gate) { @($Gate.Report.findings | Where-Object { $_.id -like 'SZA-FLOW*' }) }
    Test-Case 'flow: the check is off by default' {
        Assert-NoFinding (New-Fixture 'f1-off') 'FLOW' 'SZA-FLOW'
    }
    Test-Case 'flow: with -CheckTaskFlow a stamped repository with no profile, no ledger and no launcher gets FLOW01, FLOW02 and FLOW03 as warnings' {
        $root = New-Fixture 'f2-bare'
        $off = Invoke-Gate $root
        $on = Invoke-Gate $root $flowOn
        $flow = @(Get-FlowFinding $on)
        $said = ($flow | ForEach-Object { "$($_.id):$($_.severity)@$($_.path)" }) -join ', '
        foreach ($want in 'SZA-FLOW01:warn@.sza-profile.json', 'SZA-FLOW02:warn@PLAN/spec-catalog.jsonl', 'SZA-FLOW03:warn@r0.ps1') {
            Assert-That (($said -split ', ') -contains $want) "expected $want, the gate said: $said"
        }
        Assert-That ($flow.Count -eq 3) "expected exactly three FLOW findings, the gate said: $said"
        # Warnings only: the switch moves neither the error count nor the exit code.
        Assert-That ($on.Report.errors -eq $off.Report.errors) "the switch changed the error count: $($off.Report.errors) -> $($on.Report.errors)"
        Assert-That ($on.Exit -eq $off.Exit) "the switch changed the exit code: $($off.Exit) -> $($on.Exit)"
    }
    Test-Case 'flow: a repository scaffolded by init-task-flow has no FLOW finding' {
        $root = New-Fixture 'f3-scaffolded'
        & pwsh -NoProfile -File (Join-Path $SourceRoot 'tools/harness/scaffold/init-task-flow.ps1') -Root $root 2>&1 | Out-Null
        Assert-That ($LASTEXITCODE -eq 0) 'the scaffold failed'
        Assert-That (Test-Path -LiteralPath (Join-Path $root 'r0.ps1')) 'the scaffold wrote no r0.ps1'
        Assert-NoFinding $root 'FLOW' 'SZA-FLOW' $flowOn
    }
    Test-Case 'flow: a ledger moved by the profile''s paths.journal counts, and an a.ps1 with an r0 target counts as a launcher' {
        $moved = @{ version = '1'; paths = @{ journal = 'LEDGER/rows.jsonl' } } | ConvertTo-Json -Depth 4
        $aWithR0 = @'
$targets = [ordered]@{
    'r0'        = @{ Path = 'scripts\utils\run-mono-queue.ps1'; Args = @{} }
}
'@
        $root = New-Fixture 'f4-moved' -Files @{ '.sza-profile.json' = $moved; 'LEDGER/rows.jsonl' = ''; 'a.ps1' = $aWithR0 }
        Assert-NoFinding $root 'FLOW' 'SZA-FLOW' $flowOn
        # The other way round: the default file does not stand in for a moved ledger, and an a.ps1 without an r0 target is no launcher.
        $root = New-Fixture 'f4-moved-missing' -Files @{ '.sza-profile.json' = $moved; 'PLAN/spec-catalog.jsonl' = ''; 'a.ps1' = "'build' = @{ Path = 'x.ps1' }" }
        $said = (Get-FlowFinding (Invoke-Gate $root $flowOn) | ForEach-Object { "$($_.id)@$($_.path)" }) -join ', '
        Assert-That (($said -split ', ') -contains 'SZA-FLOW02@LEDGER/rows.jsonl') "expected SZA-FLOW02 at LEDGER/rows.jsonl, the gate said: $said"
        Assert-That (($said -split ', ') -contains 'SZA-FLOW03@r0.ps1') "expected SZA-FLOW03, the gate said: $said"
    }
    Test-Case 'flow: a dated exemption in the stamp suppresses the finding' {
        $live = @{ exemptions = @(@{ id = 'SZA-FLOW01'; reason = 'own scheme until the migration ticket'; until = '2099-01-01' }) }
        $root = New-Fixture 'f5-exempt' $live
        Assert-NoFinding $root 'FLOW' 'SZA-FLOW01' $flowOn
        Assert-Finding $root 'FLOW' 'SZA-FLOW02:warn' $flowOn
        $expired = @{ exemptions = @(@{ id = 'SZA-FLOW01'; reason = 'own scheme until the migration ticket'; until = '2000-01-01' }) }
        Assert-Finding (New-Fixture 'f5-expired' $expired) 'FLOW' 'SZA-FLOW01:warn' $flowOn
    }
    Test-Case 'flow: an unstamped directory gets CANON01 and no FLOW finding' {
        $root = New-Fixture 'f6-unstamped' -NoStamp
        $gate = Invoke-Gate $root $flowOn
        $canon = @($gate.Report.findings | Where-Object { $_.id -eq 'SZA-CANON01' })
        Assert-That ($canon.Count -eq 1) "expected SZA-CANON01, the gate said: $(($gate.Report.findings | ForEach-Object id) -join ', ')"
        $flow = @(Get-FlowFinding $gate)
        Assert-That ($flow.Count -eq 0) "expected no SZA-FLOW, the gate said: $(($flow | ForEach-Object id) -join ', ')"
    }
}
catch {
    "FAIL setup - $($_.Exception.Message)"
    $failed++
    $run++
    $setupFailed = $true
}
finally {
    $env:SZA_PROJECT_ROOT = $savedRoot
    if ($scratch -and -not $KeepScratch -and (Test-Path -LiteralPath $scratch)) {
        Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($setupFailed) { "layout-gate-tests: COULD NOT VERIFY (run=$run skipped=0)"; exit 2 }
if ($failed -gt 0) { "layout-gate-tests: FAIL (run=$run skipped=0)"; exit 1 }
"layout-gate-tests: PASS (run=$run skipped=0)"
exit 0
