#requires -Version 7.0
<#
.SYNOPSIS
    TASK-FLOW rule 69: the back-link a blocked ticket leaves in its blockers, and the release of the tickets a blocker
    holds - inside one repository and across two registered repositories.

.DESCRIPTION
    Two throwaway repositories (keys ra and rb) and a throwaway portfolio root; the real update.ps1 and block-links.ps1
    of this tree, nothing else. Cases:

      1. Entering BlockByOtherTask writes `- Blocks:` lines with `was:` into a local and a cross-repository blocker.
      2. Entering the block again refreshes the open line instead of adding a second one.
      3. Archiving the local blocker releases the ticket it alone held (to its `was`) and closes that line; a ticket a
         second, unreleased blocker still holds stays blocked and its line stays open.
      4. Archiving the cross-repository blocker releases the last waiting ticket in the other repository.
      5. -Check releases a ticket whose Blocker: token was removed by hand.
      6. The fixed `**Depends on:**` reader stops at the end of its line and does not read a following bullet list.

    Spawns about ten pwsh processes, so it is above the 5-second line: release tier, run by name.
    -KeepScratch leaves the repositories for inspection.
#>
[CmdletBinding()]
param([switch] $KeepScratch)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$harness = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\harness'))
$update = Join-Path $harness 'spec_catalog\update.ps1'
$links = Join-Path $harness 'spec_catalog\block-links.ps1'

$run = 0; $passed = 0; $failed = 0
function Assert-That([bool] $Condition, [string] $Message) { if (-not $Condition) { throw $Message } }
function Run-Case([string] $Name, [scriptblock] $Body) {
    $script:run++
    Write-Host -NoNewline "CASE  $Name ... "
    try { & $Body; $script:passed++; Write-Host 'PASS' -ForegroundColor Green }
    catch { $script:failed++; Write-Host 'FAIL' -ForegroundColor Red; Write-Host "      $($_.Exception.Message)" -ForegroundColor DarkRed }
}

$scratch = Join-Path ([IO.Path]::GetTempPath()) ('block-links-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$repoA = Join-Path $scratch 'ra'; $repoB = Join-Path $scratch 'rb'; $pf = Join-Path $scratch 'portfolio'
$saved = @{}
foreach ($n in 'SZA_PROJECT_ROOT', 'SZA_PROFILE_PATH', 'SZA_PORTFOLIO_ROOT', 'SZA_BLOCK_LINKS') { $saved[$n] = [Environment]::GetEnvironmentVariable($n) }

function New-Repo([string] $Root, [hashtable[]] $Tickets) {
    New-Item -ItemType Directory -Path (Join-Path $Root 'PLAN') -Force | Out-Null
    $rows = foreach ($t in $Tickets) {
        $file = "PLAN/$($t.id)_t.md"
        $body = "# Spec: $($t.id) - t`n`n**Status:** $($t.status)`n`n## 1. Problem`n`nText.`n"
        if ($t.ContainsKey('extra')) { $body += $t.extra }
        [IO.File]::WriteAllText((Join-Path $Root ($file -replace '/', '\')), $body)
        (@{ id = $t.id; name = 't'; status = $t.status; priority = 50; file = $file; created = '2026-11-13'; updated = '2026-11-13 10:00' } | ConvertTo-Json -Compress)
    }
    [IO.File]::WriteAllText((Join-Path $Root 'PLAN\spec-catalog.jsonl'), (($rows -join "`n") + "`n"))
}
function Invoke-In([string] $Root, [string] $Script, [string[]] $ScriptArgs) {
    $env:SZA_PROJECT_ROOT = $Root
    $out = & pwsh -NoProfile -File $Script @ScriptArgs 2>&1 | Out-String
    [pscustomobject]@{ code = $LASTEXITCODE; output = $out.Trim() }
}
function Get-Status([string] $Root, [string] $Id) {
    foreach ($l in [IO.File]::ReadAllLines((Join-Path $Root 'PLAN\spec-catalog.jsonl'))) {
        if (-not $l.Trim()) { continue }
        $r = $l | ConvertFrom-Json
        if ($r.id -ceq $Id) { return $r.status }
    }
    $arch = Join-Path $Root 'PLAN\spec-catalog-archive.jsonl'
    if (Test-Path $arch) { foreach ($l in [IO.File]::ReadAllLines($arch)) { if ($l.Trim() -and ($l | ConvertFrom-Json).id -ceq $Id) { return 'Archived' } } }
    return $null
}
function Get-Spec([string] $Root, [string] $Id) { [IO.File]::ReadAllText((Join-Path $Root "PLAN\${Id}_t.md")) }

try {
    New-Item -ItemType Directory -Path $pf -Force | Out-Null
    $env:SZA_PORTFOLIO_ROOT = $pf; $env:SZA_PROFILE_PATH = $null; $env:SZA_BLOCK_LINKS = $null
    @{ schemaVersion = 1; repos = @(@{ key = 'ra'; path = $repoA }, @{ key = 'rb'; path = $repoB }) } | ConvertTo-Json -Depth 4 |
        Set-Content -LiteralPath (Join-Path $pf 'repos.json')
    New-Repo $repoA @(
        @{ id = 'S0001'; status = 'Draft' },
        @{ id = 'S0002'; status = 'Approved'; extra = "`n### 3.3 Owner inputs (Approval gate)`n`n- **Related tickets:** S0001`n" },
        @{ id = 'S0003'; status = 'Tactical' },
        @{ id = 'S0004'; status = 'Draft' }
    )
    New-Repo $repoB @(@{ id = 'S0001'; status = 'Draft' })

    Run-Case 'entry into BlockByOtherTask writes a local and a cross-repository back-link with was' {
        $r = Invoke-In $repoA $update @('-Id', 'S0002', '-Status', 'BlockByOtherTask', '-StatusNote', 'Blocker: S0001 Blocker: rb:S0001 - waits for both')
        Assert-That ($r.code -eq 0) "update exited $($r.code): $($r.output)"
        Assert-That ((Get-Spec $repoA 'S0001') -match '(?m)^## Blocked tickets\r?$') 'no section in the local blocker'
        Assert-That ((Get-Spec $repoA 'S0001') -match '(?m)^- Blocks: S0002 \| was: Approved \| since: \d{4}-\d{2}-\d{2}\r?$') "local line missing: $(Get-Spec $repoA 'S0001')"
        Assert-That ((Get-Spec $repoB 'S0001') -match '(?m)^- Blocks: ra:S0002 \| was: Approved \| since: ') "cross line missing: $(Get-Spec $repoB 'S0001')"
    }

    Run-Case 'a second entry refreshes the open line instead of adding one' {
        $r = Invoke-In $repoA $update @('-Id', 'S0003', '-Status', 'BlockByOtherTask', '-StatusNote', 'Blocker: S0001 - first reason')
        Assert-That ($r.code -eq 0) "update exited $($r.code): $($r.output)"
        $r = Invoke-In $repoA $update @('-Id', 'S0003', '-Status', 'BlockByOtherTask', '-StatusNote', 'Blocker: S0001 - second reason')
        Assert-That ($r.code -eq 0) "update exited $($r.code): $($r.output)"
        $n = ([regex]::Matches((Get-Spec $repoA 'S0001'), '(?m)^- Blocks: S0003 ')).Count
        Assert-That ($n -eq 1) "S0003 has $n lines"
        Assert-That ((Get-Spec $repoA 'S0001') -match '(?m)^- Blocks: S0003 \| was: Tactical ') 'the refresh lost was'
    }

    Run-Case 'archiving the local blocker frees the ticket it alone held and keeps the other blocked' {
        $r = Invoke-In $repoA $update @('-Id', 'S0001', '-Status', 'Archived')
        Assert-That ($r.code -eq 0) "update exited $($r.code): $($r.output)"
        Assert-That ((Get-Status $repoA 'S0003') -ceq 'Tactical') "S0003 is $(Get-Status $repoA 'S0003'): $($r.output)"
        Assert-That ((Get-Status $repoA 'S0002') -ceq 'BlockByOtherTask') "S0002 is $(Get-Status $repoA 'S0002')"
        $spec = [IO.File]::ReadAllText((Get-ChildItem -LiteralPath $repoA -Recurse -Filter 'S0001_t.md' | Select-Object -First 1).FullName)
        Assert-That ($spec -match '(?m)^- Blocks: S0003 [^\r\n]*\| released: \d{4}-\d{2}-\d{2} -> Tactical\r?$') "S0003 line not closed: $spec"
        Assert-That ($spec -match '(?m)^- Blocks: S0002 \| was: Approved \| since: [\d-]+\r?$') "S0002 line not left open: $spec"
    }

    Run-Case 'archiving the cross-repository blocker frees the last waiting ticket in the other repository' {
        $r = Invoke-In $repoB $update @('-Id', 'S0001', '-Status', 'Archived')
        Assert-That ($r.code -eq 0) "update exited $($r.code): $($r.output)"
        Assert-That ((Get-Status $repoA 'S0002') -ceq 'Approved') "S0002 is $(Get-Status $repoA 'S0002'): $($r.output)"
        $spec = [IO.File]::ReadAllText((Get-ChildItem -LiteralPath $repoB -Recurse -Filter 'S0001_t.md' | Select-Object -First 1).FullName)
        Assert-That ($spec -match '(?m)^- Blocks: ra:S0002 [^\r\n]*\| released: [\d-]+ -> Approved\r?$') "cross line not closed: $spec"
    }

    Run-Case '-Check frees a ticket whose Blocker: token was removed by hand' {
        $r = Invoke-In $repoA $update @('-Id', 'S0004', '-Status', 'BlockByOtherTask', '-StatusNote', 'Blocker: S0003 - waits')
        Assert-That ($r.code -eq 0) "update exited $($r.code): $($r.output)"
        # The owner drops the dependency: the token goes from the note (update with a note that names no blocker
        # is refused by the entry gate, so the ledger row is edited the way a person would).
        $ledger = Join-Path $repoA 'PLAN\spec-catalog.jsonl'
        [IO.File]::WriteAllText($ledger, ([IO.File]::ReadAllText($ledger) -replace 'Blocker: S0003 - waits', 'dependency dropped'))
        $r = Invoke-In $repoA $links @('-Check', '-Id', 'S0004', '-Was', 'Approved')
        Assert-That ($r.code -eq 0) "check exited $($r.code): $($r.output)"
        # Its spec has no Owner inputs section, so the Approved gate refuses and the release falls to Draft.
        Assert-That ((Get-Status $repoA 'S0004') -ceq 'Draft') "S0004 is $(Get-Status $repoA 'S0004'): $($r.output)"
        Assert-That ($r.output -match 'Approved was refused') "the fallback was not reported: $($r.output)"
    }

    Run-Case 'the Depends on reader stops at the end of its line' {
        $probe = @'
. (Join-Path $env:H '_profile.ps1'); . (Join-Path $env:H 'spec_catalog\_blocker-links.ps1')
$t = "**Depends on:** S0026, S0029`n`n### 3.3 Owner inputs`n`n- **Related tickets:** S0025, S0028`n"
$l = "**Depends on:**`n`n- S0291 one`n- S0292 two`n`n**Blocks:** S0240`n"
(@(Get-BlockerLinks -SpecText $t) -join ',') + '|' + (@(Get-BlockerLinks -SpecText $l) -join ',')
'@
        $env:H = $harness; $env:SZA_PROJECT_ROOT = $repoA
        $o = (& pwsh -NoProfile -Command $probe 2>&1 | Out-String).Trim()
        Assert-That ($o -ceq 'S0026,S0029|S0291,S0292') "read: $o"
    }
}
finally {
    foreach ($n in $saved.Keys) { [Environment]::SetEnvironmentVariable($n, $saved[$n]) }
    $env:H = $null
    if ($KeepScratch) { Write-Host "scratch kept: $scratch" } else { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host ''
Write-Host ("{0} cases: {1} passed, {2} failed" -f $run, $passed, $failed)
exit $(if ($failed -eq 0) { 0 } else { 1 })
