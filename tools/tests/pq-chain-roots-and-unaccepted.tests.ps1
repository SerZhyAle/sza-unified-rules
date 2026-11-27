#requires -Version 7.0
<#
.SYNOPSIS
    Fast regression suite for CANONR-0243:
      1. Chain-root walk reads the same local blocker channels as the picker (Get-BlockerLinks: **Depends on:**,
         ## 10. and statusNote, ignoring backtick/angle-bracket quoted examples and prose in other sections).
      2. pq inbox (text and -Json) and block-links.ps1 (-Sweep and -Check) list tickets held ONLY by unaccepted
         Implemented blockers whose tactical plans are complete, each with the exact `**Accepts Implemented:**` line,
         without altering inbox status counts or auto-accepting anything.

.DESCRIPTION
    Builds throwaway repositories and a throwaway portfolio root under the system temp directory. Exercises the
    in-process functions (Get-BlockerLinks, Get-PqInboxLocalHold, Get-PqInboxChainRoot, Get-PqUnacceptedImplementedHold,
    Get-PqInbox) plus direct CLI calls of pq.ps1 inbox (-Json and text) and block-links.ps1 (-Sweep -DryRun and -Check).
    -KeepScratch leaves the scratch directory for inspection.
#>
[CmdletBinding()]
param([switch] $KeepScratch)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$SourceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$Harness = Join-Path $SourceRoot 'tools\harness'
$Lib = Join-Path $Harness 'portfolio\lib'
$pqScript = Join-Path $Harness 'portfolio\pq.ps1'
$blockLinksScript = Join-Path $Harness 'spec_catalog\block-links.ps1'
$pwshExe = (Get-Command pwsh -CommandType Application | Select-Object -First 1).Source

. (Join-Path $Lib 'inbox.ps1')
. (Join-Path $Lib 'xrepo.ps1')

$run = 0; $passed = 0; $failed = 0
function Assert-That([bool] $Condition, [string] $Message) { if (-not $Condition) { throw $Message } }
function Assert-Equal($Actual, $Expected, [string] $What) {
    if ("$Actual" -cne "$Expected") { throw "$What - expected '$Expected', got '$Actual'" }
}
function Run-Case([string] $Name, [scriptblock] $Body) {
    $script:run++
    Write-Host -NoNewline "CASE  $Name ... "
    try { & $Body; $script:passed++; Write-Host 'PASS' -ForegroundColor Green }
    catch { $script:failed++; Write-Host 'FAIL' -ForegroundColor Red; Write-Host "      $($_.Exception.Message)" -ForegroundColor DarkRed }
}

$scratch = Join-Path ([IO.Path]::GetTempPath()) ('pq-c243-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$portfolio = Join-Path $scratch 'portfolio'
New-Item -ItemType Directory -Path $portfolio -Force | Out-Null

function Write-Utf8([string] $Path, [string] $Text) {
    $dir = [IO.Path]::GetDirectoryName($Path)
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false))
}
function New-Row([string] $Id, [string] $Status, [string] $Note = '', [int] $Priority = 50, [string] $Updated = '2026-11-20 10:00') {
    $o = [ordered]@{ id = $Id; name = "t-$Id"; status = $Status; priority = $Priority; file = "PLAN/${Id}_t.md"; created = '2026-11-10'; updated = $Updated }
    if ($Note) { $o.statusNote = $Note }
    return (ConvertTo-Json -InputObject $o -Compress)
}
function New-Repo([string] $Key, [string] $ProfileJson, [string[]] $Rows, [hashtable] $Specs, [hashtable] $ExtraFiles = @{}) {
    $root = Join-Path $scratch $Key
    Write-Utf8 (Join-Path $root '.sza-profile.json') $ProfileJson
    Write-Utf8 (Join-Path $root 'PLAN\spec-catalog.jsonl') (($Rows -join "`n") + "`n")
    foreach ($k in $Specs.Keys) { Write-Utf8 (Join-Path $root ("PLAN\$k")) $Specs[$k] }
    foreach ($k in $ExtraFiles.Keys) { Write-Utf8 (Join-Path $root $k) $ExtraFiles[$k] }
    return [pscustomobject]@{ key = $Key; path = $root; enabled = $true; maxWorkers = 1; concurrent = $false; role = 'product'; permissionMode = 'bypassPermissions'; rank = 10 }
}

try {
    # --- Fixture repositories ---
    # mob: custom prefix MOBS-####. MOBS-0047 is BlockExternal with quoted alternative `Blocker: MOBS-0170`
    #      and angle-bracket <Blocker: MOBS-0170> in prose (item 1 case 1).
    $mob = New-Repo 'mob' '{"grammar":{"ticketIdPattern":"^MOBS-\\d{4}$"}}' @(
        (New-Row 'MOBS-0047' 'BlockExternal' 'Waiting on store review'),
        (New-Row 'MOBS-0170' 'Implemented' 'Done and audited')
    ) @{
        'MOBS-0047_t.md' = "# MOBS-0047`n`n**Status:** BlockExternal`n`n### Assumed`nAlternative: ``Blocker: MOBS-0170`` and ``BlockByOtherTask``; form <Blocker: MOBS-0170>.`n"
        'MOBS-0170_t.md' = "# MOBS-0170`n`n**Status:** Implemented`n"
    }

    # dev: custom prefix DEVI-####. DEVI-0014 has quiz-decision prose mentioning Blocker: DEVI-0029 outside ## 10.
    $dev = New-Repo 'dev' '{"grammar":{"ticketIdPattern":"^DEVI-\\d{4}$"}}' @(
        (New-Row 'DEVI-0014' 'Approved'),
        (New-Row 'DEVI-0029' 'Implemented'),
        (New-Row 'DEVI-0030' 'BlockByOtherTask' 'waits on DEVI-0014')
    ) @{
        'DEVI-0014_t.md' = "# DEVI-0014`n`n**Status:** Approved`n`n### Questions (v1, 2026-11-15) - answered 2026-11-15`n- Decision: old Blocker: DEVI-0029 was released on 2026-11-15.`n"
        'DEVI-0029_t.md' = "# DEVI-0029`n`n**Status:** Implemented`n"
        'DEVI-0030_t.md' = "# DEVI-0030`n`n**Depends on:** DEVI-0014`n"
    }

    # app: default S#### grammar + legacy OLD-####. Exercises real local channels AND all unaccepted-Implemented cases.
    $app = New-Repo 'app' '{"grammar":{"ticketIdPattern":"^S\\d{4}$","legacyTicketIdPatterns":["^OLD-\\d{4}$"]}}' @(
        # Refuses mob:MOBS-0047 and dev:DEVI-0014 to test chain roots
        (New-Row 'S0001' 'BlockByOtherTask' 'Blocker: mob:MOBS-0047'),
        (New-Row 'S0002' 'BlockByOtherTask' 'Blocker: dev:DEVI-0014'),
        # Implemented blockers: S0100 (plan complete / no INDEX), S0101 (plan 1/2 incomplete), S0102 (already accepted + at: Implemented), S0103 (In Progress), S0104 (Verified)
        (New-Row 'S0100' 'Implemented'),
        (New-Row 'S0101' 'Implemented'),
        (New-Row 'S0102' 'Implemented'),
        (New-Row 'S0103' 'In Progress'),
        (New-Row 'S0104' 'Verified'),
        # S0201: BlockByOtherTask held ONLY by local unaccepted Implemented S0100 (+ released S0104) -> LISTED
        (New-Row 'S0201' 'BlockByOtherTask' 'Blocker: S0100 Blocker: S0104'),
        # S0202: Draft held ONLY by two unaccepted Implemented blockers (local S0100 + qualified mob:MOBS-0170) -> LISTED
        (New-Row 'S0202' 'Draft' 'Blocker: S0100'),
        # S0203: BlockByOtherTask held by S0100 (Implemented) AND S0103 (In Progress) -> NOT listed (another blocker holds)
        (New-Row 'S0203' 'BlockByOtherTask' 'Blocker: S0100 Blocker: S0103'),
        # S0204: BlockByOtherTask held by S0101 (Implemented, plan 1/2 incomplete) -> NOT listed
        (New-Row 'S0204' 'BlockByOtherTask' 'Blocker: S0101'),
        # S0205: BlockByOtherTask with **Accepts Implemented:** S0102, held only by local `| at: Implemented` -> NOT listed
        (New-Row 'S0205' 'BlockByOtherTask' 'Blocker: S0102'),
        # S0206: BlockByOtherTask held by legacy local token in ## 10. with bold formatting -> real local hold
        (New-Row 'S0206' 'BlockByOtherTask' 'local hold in section 10'),
        (New-Row 'OLD-0007' 'Draft')
    ) @{
        'S0001_t.md'    = "# S0001`n`nBlocker: mob:MOBS-0047`n"
        'S0002_t.md'    = "# S0002`n`nBlocker: dev:DEVI-0014`n"
        'S0100_t.md'    = "# S0100`n`n**Status:** Implemented`n"
        'S0101_t.md'    = "# S0101`n`n**Status:** Implemented`n"
        'S0102_t.md'    = "# S0102`n`n**Status:** Implemented`n`n## Blocked tickets`n`n- Blocks: S0205 | was: Draft | since: 2026-11-26 | at: Implemented`n"
        'S0103_t.md'    = "# S0103`n`n**Status:** In Progress`n"
        'S0104_t.md'    = "# S0104`n`n**Status:** Verified`n"
        'S0201_t.md'    = "# S0201`n`n**Status:** BlockByOtherTask`n"
        'S0202_t.md'    = "# S0202`n`n**Status:** Draft`n`nBlocker: mob:MOBS-0170`n"
        'S0203_t.md'    = "# S0203`n`n**Status:** BlockByOtherTask`n"
        'S0204_t.md'    = "# S0204`n`n**Status:** BlockByOtherTask`n"
        'S0205_t.md'    = "# S0205`n`n**Status:** BlockByOtherTask`n**Accepts Implemented:** S0102`n"
        'S0206_t.md'    = "# S0206`n`n## 10. Links`n`n``Blocker: S0103`` and <Blocker: S0103>`nBlocker: S0103suffix`nБлокер: **OLD-0007**`n"
        'OLD-0007_t.md' = "# OLD-0007`n`n**Status:** Draft`n"
    } @{
        'PLAN\S0101_t\INDEX.md' = "# S0101 Plan`n`n**Phases:** 1 / 2 done`n"
    }

    $registry = [pscustomobject]@{ schemaVersion = '1.0'; repos = @($mob, $dev, $app) }
    $byKey = @{ mob = $mob; dev = $dev; app = $app }
    Write-Utf8 (Join-Path $portfolio 'repos.json') (ConvertTo-Json -InputObject $registry -Depth 6)

    # --- Case 1: Item 1 - quoted examples and non-section-10 prose are never followed ---
    Run-Case '1 item 1: quoted examples and non-section-10 quiz prose do not create false chain roots' {
        Assert-Equal (Get-PqInboxLocalHold $byKey @{} 'mob' 'MOBS-0047') $null 'backtick/angle-bracket examples ignored'
        Assert-Equal (Get-PqInboxChainRoot $registry $byKey @{} 'app' 'S0001').pair 'mob:MOBS-0047' 'root stops at real BlockExternal root'

        Assert-Equal (Get-PqInboxLocalHold $byKey @{} 'dev' 'DEVI-0014') $null 'quiz-decision prose outside ## 10. ignored'
        Assert-Equal (Get-PqInboxChainRoot $registry $byKey @{} 'app' 'S0002').pair 'dev:DEVI-0014' 'root stops at DEVI-0014, not DEVI-0029'
    }

    # --- Case 2: Item 1 - real picker channels still hold, quoted/partial inside ## 10. ignored ---
    Run-Case '2 item 1: Depends on, ## 10. and statusNote tokens hold while quoted and partial ids inside ## 10. do not' {
        Assert-Equal (Get-PqInboxLocalHold $byKey @{} 'dev' 'DEVI-0030') 'dev:DEVI-0014' '**Depends on:** holds'
        Assert-Equal (Get-PqInboxLocalHold $byKey @{} 'app' 'S0206') 'app:OLD-0007' 'legacy bold token in ## 10. holds; quoted/partial skipped'
        # Direct Get-BlockerLinks check on quoted examples inside ## 10. and statusNote
        $ids = @(Get-BlockerLinks -SpecText "## 10. Links`n`n``Blocker: S0001`` <Blocker: S0002> Blocker: S0003suffix`n" -StatusNote '``Blocker: S0004``' -SelfId 'S0099' -TicketIdFragment 'S\d{4}')
        Assert-Equal $ids.Count 0 "expected no matches, got: $($ids -join ',')"
    }

    # --- Case 3: Item 2 - Get-PqInbox unaccepted section matches ONLY unaccepted Implemented holds ---
    Run-Case '3 item 2: Get-PqInbox unaccepted lists only tickets held solely by unaccepted Implemented blockers with valid acceptLine' {
        $inbox = Get-PqInbox -Registry $registry -Held $null
        Assert-Equal $inbox.unaccepted.count 2 "unaccepted count ($($inbox.unaccepted.tickets | ConvertTo-Json -Compress))"
        $byId = @{}; foreach ($t in @($inbox.unaccepted.tickets)) { $byId["$($t.repo):$($t.id)"] = $t }
        Assert-That ($byId.ContainsKey('app:S0201')) 'BlockByOtherTask S0201 missing'
        Assert-That ($byId.ContainsKey('app:S0202')) 'Draft S0202 missing'
        Assert-Equal $byId['app:S0201'].acceptLine '**Accepts Implemented:** S0100' 'S0201 acceptLine (released S0104 excluded)'
        Assert-Equal $byId['app:S0202'].acceptLine '**Accepts Implemented:** S0100, mob:MOBS-0170' 'S0202 acceptLine (local + qualified)'
        foreach ($excluded in @('app:S0203', 'app:S0204', 'app:S0205', 'app:S0206', 'app:S0001', 'app:S0002')) {
            Assert-That (-not $byId.ContainsKey($excluded)) "$excluded must not be in unaccepted"
        }
        # Five status counts and total remain strictly unchanged (unaccepted is additive, like stalled)
        Assert-Equal $inbox.counts.outside 1 'outside count'
        Assert-Equal $inbox.counts.chain 8 'chain count'
        Assert-Equal $inbox.counts.unbuilt 5 'unbuilt count'
        Assert-Equal $inbox.total 14 'total equals sum of five status kinds only'
        # Applying acceptLine to S0202 releases both blockers under Test-BlockerReleased
        $acceptedSpec = "# S0202`n`n$($byId['app:S0202'].acceptLine)`nBlocker: mob:MOBS-0170`n"
        $rLocal = & $script:PqStatusSets { param($t) Test-BlockerReleased -Status 'Implemented' -Id 'S0100' -File '' -DependentSpec $t } $acceptedSpec
        $rCross = & $script:PqStatusSets { param($t) Test-BlockerReleased -Status 'Implemented' -Id 'MOBS-0170' -File '' -DependentSpec $t -BlockerRef 'mob:MOBS-0170' } $acceptedSpec
        Assert-That ($rLocal -and $rCross) 'generated acceptLine did not release both blockers'
    }

    # --- Case 4: Direct CLI calls (pq.ps1 inbox / -Json and block-links.ps1 -Sweep -DryRun / -Check) in parallel ---
    Run-Case '4 direct CLI: pq inbox (-Json and text) and block-links -Sweep -DryRun / -Check print accept lines without mutating' {
        $ledgerBefore = (Get-FileHash -LiteralPath (Join-Path $app.path 'PLAN\spec-catalog.jsonl')).Hash
        $runner = Join-Path $scratch 'cli-probe.ps1'
        Write-Utf8 $runner @'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$mode = $args[0]
if ($mode -eq 'pq') {
    $t = (& $env:PQ_SCRIPT inbox *>&1 | Out-String)
    $tc = $LASTEXITCODE
    $j = (& $env:PQ_SCRIPT inbox -Json 2>&1 | Out-String)
    $jc = $LASTEXITCODE
    [pscustomobject]@{ textCode = $tc; text = $t; jsonCode = $jc; json = $j } | ConvertTo-Json -Compress -Depth 4
} else {
    $s = (& $env:BL_SCRIPT -Sweep -DryRun *>&1 | Out-String)
    $sc = $LASTEXITCODE
    $c = (& $env:BL_SCRIPT -Check -Id S0201 -DryRun *>&1 | Out-String)
    $cc = $LASTEXITCODE
    [pscustomobject]@{ sweepCode = $sc; sweep = $s; checkCode = $cc; check = $c } | ConvertTo-Json -Compress -Depth 4
}
'@
        $out = @('pq', 'bl') | ForEach-Object -ThrottleLimit 2 -Parallel {
            $psi = [Diagnostics.ProcessStartInfo]::new($using:pwshExe)
            foreach ($a in @('-NoProfile', '-File', $using:runner, $_)) { $psi.ArgumentList.Add($a) }
            $psi.UseShellExecute = $false
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true
            $psi.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
            $psi.Environment['SZA_PORTFOLIO_ROOT'] = $using:portfolio
            $psi.Environment['SZA_PROJECT_ROOT'] = $using:app.path
            $psi.Environment['PQ_SCRIPT'] = $using:pqScript
            $psi.Environment['BL_SCRIPT'] = $using:blockLinksScript
            $p = [Diagnostics.Process]::Start($psi)
            $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
            if (-not $p.WaitForExit(30000)) { $p.Kill($true); throw "$_ probe timed out" }
            $p.WaitForExit()
            [pscustomobject]@{ mode = $_; code = $p.ExitCode; out = $o.Result; err = $e.Result }
        }
        $byMode = @{}; foreach ($r in $out) { $byMode[$r.mode] = ($r.out | ConvertFrom-Json) }

        $pqRes = $byMode['pq']
        Assert-Equal $pqRes.textCode 0 "pq inbox exit $($pqRes.textCode): $($pqRes.text)"
        Assert-Equal $pqRes.jsonCode 0 "pq inbox -Json exit $($pqRes.jsonCode)"
        Assert-That ($pqRes.text -match '(?m)^unaccepted\s+2\s+oldest ') "pq inbox missing unaccepted header: $($pqRes.text)"
        Assert-That ($pqRes.text -match 'app:S0201\s+\(BlockByOtherTask\).*\*\*Accepts Implemented:\*\* S0100') "pq inbox missing S0201 line: $($pqRes.text)"
        Assert-That ($pqRes.text -match 'app:S0202\s+\(Draft\).*\*\*Accepts Implemented:\*\* S0100, mob:MOBS-0170') "pq inbox missing S0202 line: $($pqRes.text)"
        Assert-That ($pqRes.text -match 'mob:MOBS-0047 .* frees 1') "pq inbox did not show real root mob:MOBS-0047: $($pqRes.text)"
        Assert-That ($pqRes.text -notmatch 'mob:MOBS-0170 .* frees') "pq inbox showed false root mob:MOBS-0170: $($pqRes.text)"
        $j = $pqRes.json | ConvertFrom-Json
        Assert-Equal $j.unaccepted.count 2 'pq inbox -Json unaccepted count'

        $blRes = $byMode['bl']
        Assert-Equal $blRes.sweepCode 0 "block-links -Sweep -DryRun exit $($blRes.sweepCode): $($blRes.sweep)"
        Assert-Equal $blRes.checkCode 0 "block-links -Check -DryRun exit $($blRes.checkCode): $($blRes.check)"
        Assert-That ($blRes.sweep -match 'held only by unaccepted Implemented blocker\(s\) \(1;') "sweep summary missing: $($blRes.sweep)"
        Assert-That ($blRes.sweep -match 'S0201: \*\*Accepts Implemented:\*\* S0100') "sweep S0201 accept line missing: $($blRes.sweep)"
        Assert-That ($blRes.sweep -notmatch 'S0203: \*\*Accepts Implemented:\*\*') "sweep must not list S0203: $($blRes.sweep)"
        Assert-That ($blRes.sweep -notmatch 'S0204: \*\*Accepts Implemented:\*\*') "sweep must not list S0204: $($blRes.sweep)"
        Assert-That ($blRes.sweep -notmatch 'S0205: \*\*Accepts Implemented:\*\*') "sweep must not list S0205: $($blRes.sweep)"
        Assert-That ($blRes.check -match 'S0100 is Implemented \(not accepted\)' -and $blRes.check -match 'accept with: \*\*Accepts Implemented:\*\* S0100') "check output: $($blRes.check)"

        Assert-Equal (Get-FileHash -LiteralPath (Join-Path $app.path 'PLAN\spec-catalog.jsonl')).Hash $ledgerBefore 'dry-run / inbox must write nothing'
    }
}
finally {
    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()
    if (-not $KeepScratch) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
    else { Write-Host "scratch kept: $scratch" }
}

Write-Host ''
Write-Host ("pq-chain-roots-and-unaccepted: run={0} passed={1} failed={2}" -f $run, $passed, $failed)
exit $(if ($failed -eq 0) { 0 } else { 1 })
