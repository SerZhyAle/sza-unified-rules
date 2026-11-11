#requires -Version 7.0
<#
.SYNOPSIS
    Stage a Microsoft Store submission (S0048 done criterion 4): build the unsigned MSIX, assert the frozen
    anchors, parse the WACK verdict, name the listing merge - and stop. The Partner Center upload never runs.

.DESCRIPTION
    The agent-side half of a filed "опубликуй <project> in MS Store" (recognized at ingest, worked by the
    store-publish skill). Everything an agent can do before the one-way step is staged; the upload itself is
    the [PUBLIC] manual step of CHANNEL_MATRIX and belongs to the owner: the Partner Center upload stays manual
    for this individual MSA account (the msstore CLI needs a service principal an individual MSD does not
    have), and no code path in the canon ever performs it automatically.

    Probes, never assumes (skills/store-publish/SKILL.md):
      - msix/build-msix.ps1 or publishing/msix/build-msix.ps1;
      - the reserved identity out of STORE_PUBLISHING.md (`Package/Identity/Name`, `Package/Identity/Publisher`,
        `Package/Properties/PublisherDisplayName`), the Publisher asserted against the account-wide frozen
        anchor CN=F98ACEDB-1E22-4C39-AF63-F9FCFE807DCD / SZA - IdentityName is per product, always read;
      - the identity values are passed to the build only where that script's own parameters accept them,
        never bare (the bare-build trap: two repos default to a self-sign placeholder Publisher);
      - the packed <Identity> element is read back out of the produced package and asserted;
      - the WACK verdict comes from a staged report's OVERALL_RESULT (the kit run itself is elevated and
        manual; the exact command is staged in WACK-COMMAND.txt; an exit code is never the verdict);
      - the listing leg is export-then-merge: a fresh Partner Center export is interactive by nature, so the
        step is named, and a repo-side merge script is named, never run against live data here.

    The outcome is <OutDir>\STAGE-REPORT.md (plus the staged package and its .sha256): the staged paths, every
    verdict, the exact manual Partner Center step, and the ticket command that stops it at BlockExternal.
    Nothing is uploaded, pushed, tagged or submitted by this script at any point.

.PARAMETER Project
    The registry key of the project (exact, case-sensitive).

.PARAMETER Version
    The 4-part Store version (Major.Minor.Build.Revision, revision 0). Defaults to a date-derived
    yy.(MM*100+DD).HHmm.0 - verify it exceeds the published version before any real submission.

.PARAMETER OutDir
    Where to stage; default <repo>\temp\store-stage\<version>.

.PARAMETER IdentityName
    Override the reserved Identity Name (when STORE_PUBLISHING.md does not name it).

.PARAMETER Ticket
    With -SetStatus: the ticket to stop at BlockExternal (a bare id, or <key>:<id>).

.PARAMETER SetStatus
    Also move the ticket (with -Ticket) to BlockExternal through the project's own update tooling, the note
    naming the staged paths and the manual step. Without -Ticket nothing is set.

.PARAMETER Json
    Print the staging record as one JSON object and nothing else.

.EXAMPLE
    pwsh -NoProfile -File tools/harness/portfolio/stage-store-publish.ps1 -Project streams-win -Json

.Exit codes
    0 the staging produced its artifact set and the report
    2 invalid invocation: unknown project, no MSIX build script, no resolvable identity (fail closed, never guessed)
    3 a step failed: the MSIX build, or the frozen-anchor read-back assert
#>
[CmdletBinding(PositionalBinding = $false)]
param(
    [Parameter(Mandatory)][string]$Project,
    [string]$Version = '',
    [string]$OutDir = '',
    [string]$IdentityName = '',
    [string]$Ticket = '',
    [switch]$SetStatus,
    [int]$TimeoutSeconds = 1800,
    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$lib = Join-Path $PSScriptRoot 'lib'
. (Join-Path $lib 'paths.ps1')
. (Join-Path $lib 'loop.ps1')
. (Join-Path $lib 'registry.ps1')
. (Join-Path $lib 'ledger-watch.ps1')
. (Join-Path $lib 'delivery.ps1')

function Write-StageError([string]$Message) { [Console]::Error.WriteLine("stage-store-publish: $Message") }

function New-StageVersion {
    if ($Version) {
        if ($Version -cnotmatch '^\d+\.\d+\.\d+\.0$') { throw "VersionInvalid: '$Version' is not Major.Minor.Build.0 (the Store reserves the revision)" }
        return $Version
    }
    $now = [DateTime]::UtcNow
    return '{0}.{1:d2}{2:d2}.{3:d4}.0' -f ($now.Year % 100), $now.Month, $now.Day, ($now.Hour * 100 + $now.Minute)
}

try {
    $repo = Resolve-PqDeliveryRepo -Project $Project
    if ($null -eq $repo) { throw "ProjectUnknown: '$Project' is not a registered project with an existing path" }
    $plan = Get-PqStoreStagePlan -RepoPath $repo.path
    if (-not $plan.msixScript) { throw "MsixBuildMissing: no msix/build-msix.ps1 under '$Project' - nothing to stage" }
    $identityName = $IdentityName
    if (-not $identityName) { $identityName = [string]$plan.identityName }
    if (-not $identityName) { throw 'IdentityUnresolved: no IdentityName (STORE_PUBLISHING.md `Package/Identity/Name` or -IdentityName) - fail closed, never guessed' }
    if ($plan.publisherAssert -eq $false) {
        throw "PublisherAnchorMismatch: STORE_PUBLISHING.md names Publisher '$($plan.publisher)' - the account-wide frozen anchor is $(Get-PqStoreFrozenPublisher)"
    }
    $version = New-StageVersion
    $stageDir = $OutDir
    if (-not $stageDir) { $stageDir = Join-Path $repo.path (Join-Path 'temp' (Join-Path 'store-stage' $version)) }
    $stageDir = ConvertTo-PqFullPath $stageDir
    if (-not [IO.Directory]::Exists($stageDir)) { $null = [IO.Directory]::CreateDirectory($stageDir) }

    $steps = [Collections.Generic.List[object]]::new()
    # Every row carries why (null for an ok step): a reader that prints the report never meets a missing key.
    $stepOk = { param([string]$Name, [string]$Why) $steps.Add([ordered]@{ step = $Name; outcome = 'ok'; why = $Why }) }
    $stepNote = { param([string]$Name, [string]$Why) $steps.Add([ordered]@{ step = $Name; outcome = 'manual'; why = $Why }) }
    $stepFail = { param([string]$Name, [string]$Why) $steps.Add([ordered]@{ step = $Name; outcome = 'failed'; why = $Why }) }

    # ---- 1. the unsigned MSIX, through the repo's own script, identity values only where it accepts them
    $args = [Collections.Generic.List[string]]::new()
    foreach ($pair in @(@('IdentityName', $identityName), @('Publisher', (Get-PqStoreFrozenPublisher)), @('PublisherDisplayName', (Get-PqStoreFrozenPublisherDisplayName)))) {
        if ($plan.msixParameters -ccontains "-$($pair[0])") { $args.Add("-$($pair[0])"); $args.Add([string]$pair[1]) }
    }
    if (-not $Json) { "stage-store-publish: building via $($plan.msixScript) $($args -join ' ')" }
    $psi = [Diagnostics.ProcessStartInfo]::new((Get-Process -Id $PID).Path)
    $psi.ArgumentList.Add('-NoProfile')
    $psi.ArgumentList.Add('-File')
    $psi.ArgumentList.Add($plan.msixScript)
    foreach ($a in $args) { $psi.ArgumentList.Add([string]$a) }
    $psi.WorkingDirectory = $repo.path
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $proc = [Diagnostics.Process]::Start($psi)
    $buildLines = [Collections.Generic.List[string]]::new()
    $buildCode = 0
    try {
        $errTask = $proc.StandardError.ReadToEndAsync()
        while ($null -ne ($line = $proc.StandardOutput.ReadLine())) { $buildLines.Add($line); if (-not $Json) { Write-Host "  | $line" } }
        if (-not $proc.WaitForExit($TimeoutSeconds * 1000)) {
            try { $proc.Kill($true) } catch { }
            $buildCode = 124
        }
        else { $buildCode = $proc.ExitCode }
        foreach ($l in @(([string]$errTask.Result) -split '\r?\n' | Where-Object { $_ })) { $buildLines.Add($l); if (-not $Json) { Write-Host "  ! $l" } }
    }
    finally { $proc.Dispose() }
    if ($buildCode -ne 0) { throw "MsixBuildFailed: exit code $buildCode" }
    & $stepOk 'msix-build' $null

    # ---- 2. the fresh package, read back and asserted
    $candidates = @(Find-PqNewArtifacts -RepoPath $repo.path -SinceUtc ([DateTime]::UtcNow.AddSeconds(-180)) |
        Where-Object { [IO.Path]::GetExtension([string]$_) -cmatch '^\.(msix|appx)$' })
    if (@($candidates).Count -eq 0) { throw 'MsixBuildFailed: the build exited 0 but no fresh .msix was found' }
    $msixLocal = [string]$candidates[0]
    $msixStaged = Join-Path $stageDir (Split-Path -Leaf $msixLocal)
    [IO.File]::Copy($msixLocal, $msixStaged, $true)
    $msixHash = Get-PqFileSha256 $msixStaged
    [IO.File]::WriteAllText("$msixStaged.sha256", "$msixHash  $(Split-Path -Leaf $msixStaged)", [Text.ASCIIEncoding]::new())
    & $stepOk 'msix-stage' $null

    $identity = Read-PqMsixIdentity $msixStaged
    $anchorsOk = $true
    if ($null -eq $identity) { & $stepFail 'identity-readback' 'no <Identity> element in AppxManifest.xml'; $anchorsOk = $false }
    else {
        if ($identity.name -cne $identityName) { & $stepFail 'identity-readback' "Name '$($identity.name)' != reserved '$identityName'"; $anchorsOk = $false }
        if ($identity.publisher -cne (Get-PqStoreFrozenPublisher)) { & $stepFail 'identity-readback' "Publisher '$($identity.publisher)' != frozen anchor"; $anchorsOk = $false }
        if ($anchorsOk) { & $stepOk 'identity-readback' $null }
    }
    $why = (@($steps | Where-Object { $_['outcome'] -ceq 'failed' } | ForEach-Object { "$($_['step']): $($_['why'])" }) -join '; ')
    if (-not $anchorsOk) { throw "FrozenAnchorAssertFailed: $why" }

    # ---- 3. WACK: the kit run is elevated and manual; the verdict is read from a staged report, never an exit code
    $wackReportName = 'WACKReport.xml'
    $wackReport = Join-Path $stageDir $wackReportName
    $wackVerdict = $null
    if ([IO.File]::Exists($wackReport)) {
        $wackVerdict = Read-PqWackVerdict $wackReport
        if ($null -eq $wackVerdict) { & $stepNote 'wack' 'a report is staged but OVERALL_RESULT did not parse - not a pass' }
        elseif ($wackVerdict -eq 'PASS') { & $stepOk 'wack' 'OVERALL_RESULT=PASS' }
        else { & $stepFail 'wack' "OVERALL_RESULT=$wackVerdict" }
    }
    else {
        $appcert = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\App Certification Kit\appcert.exe'
        & $stepNote 'wack' 'no staged report: run the kit elevated, then stage its XML as WACKReport.xml'
        [IO.File]::WriteAllText((Join-Path $stageDir 'WACK-COMMAND.txt'),
            "Elevated shell:`r`n  ""$appcert"" test -app ""$msixStaged"" -output ""$stageDir""`r`n`r`nThe exit code is never the verdict: read OVERALL_RESULT of the XML report it wrote (msix-store.md WACK).`r`nCopy the report here as $wackReportName and re-run this staging for the verdict row.`r`n",
            [Text.UTF8Encoding]::new($false))
    }

    # ---- 4. the listing: export-then-merge, never authored, never merged against live data here
    if (@($plan.listingSources).Count -eq 0) {
        & $stepNote 'listing' 'no listing source found by the probe - resolve with the owner before any submission (fail closed on ambiguity)'
    }
    else {
        $merge = @($plan.listingSources | Where-Object { $_ -cmatch 'merge-listing-export\.ps1$' } | Select-Object -First 1)
        $why = "fresh Partner Center export first (re-taken every attempt, UTF-8 no BOM, all fields quoted, CRLF), then merge from: $(@($plan.listingSources) -join ', ')"
        if ($merge) { & $stepNote 'listing' "$why; repo merge helper: $merge" }
        else { & $stepNote 'listing' $why }
    }

    $manualStep = @(
        'MANUAL STEP (one-way [PUBLIC], the owner only): Partner Center > Apps and games > product > Create new submission:',
        '  1. Packages: upload the unsigned staged MSIX (the Store re-signs at certification):',
        "     $msixStaged",
        '  2. Store listings: add/confirm every language FIRST, export the listing CSV, merge the language columns from the content source, import (UTF-8 no BOM, quoted, CRLF)',
        "  3. Refresh `"What's new`" (CHANGELOG dated section) and Properties; Pricing and availability as before",
        '  4. Submit for certification (the WACK verdict recorded above must be PASS, never an advisory)',
        'The GitHub Release must exist before any winget leg; winget goes last (skills/store-publish ordering).'
    ) -join "`r`n"
    $statusNote = "store submission staged: $msixStaged (sha256 $msixHash) - awaiting the owner's manual Partner Center upload; report: $stageDir"

    $report = (@(
        "# Store staging report - $Project $version",
        "",
        "Produced by stage-store-publish.ps1 (S0048). NOTHING WAS UPLOADED: the Partner Center upload is the",
        "one-way manual step and belongs to the owner alone; no code path in the canon performs it.",
        "",
        "## Frozen anchors",
        "Identity Name: $identityName (read from $(if ($plan.identityFile) { $plan.identityFile } else { '-IdentityName override' }))",
        "Publisher: $(Get-PqStoreFrozenPublisher) (account-wide constant; STORE_PUBLISHING assert: $(if ($plan.publisherAssert) { 'PASS' } else { 'n/a' }))",
        "PublisherDisplayName: $(Get-PqStoreFrozenPublisherDisplayName)",
        "THIRD-PARTY-NOTICES.txt at the repo root: $(if ($plan.thirdPartyNotices) { 'present' } else { 'ABSENT - check the payload before any submission' })",
        "",
        "## Steps",
        (@($steps | ForEach-Object { "  $($_.outcome): $($_.step)$(if ($_.why) { " - $($_.why)" })" }) -join "`r`n"),
        "",
        "## Staged artifacts",
        "  $msixStaged",
        "  $msixStaged.sha256 ($msixHash)",
        "",
        "## $manualStep",
        "",
        "## Stop the ticket here",
        $(if ($Ticket) { "  update.ps1 -Id $Ticket -Status BlockExternal -StatusNote `"store submission staged: $msixStaged - awaiting the owner's manual Partner Center upload`"" } else { "  (no -Ticket given; the ticket command line is the BlockExternal step of the agent)" }),
        ""
    )) -join "`r`n"
    $reportPath = Join-Path $stageDir 'STAGE-REPORT.md'
    [IO.File]::WriteAllText($reportPath, "$report`r`n", [Text.UTF8Encoding]::new($false))

    $noted = $null
    if ($SetStatus) {
        if (-not $Ticket) { throw 'TicketMissing: -SetStatus needs -Ticket <id>' }
        $ticketId = $Ticket
        if ($Ticket -cmatch '^[A-Za-z0-9_.\-]+:(?<id>[A-Za-z0-9_.\-]+)$') { $ticketId = $Matches['id'] }
        $noted = Set-PqTicketDeliveryNote -RepoPath $repo.path -TicketId $ticketId -Note $statusNote -Status 'BlockExternal'
        if (-not $noted.ok) { Write-StageError "the BlockExternal status set failed: $($noted.error)" }
    }

    $record = [ordered]@{
        project     = $Project
        version     = $version
        staged      = [string[]]@($msixStaged, "$msixStaged.sha256")
        sha256      = $msixHash
        identityName = $identityName
        publisher   = (Get-PqStoreFrozenPublisher)
        wack        = $wackVerdict
        outDir      = $stageDir
        report      = $reportPath
        steps       = $steps
        uploaded    = $false
        ticket      = $Ticket
        statusSet   = $(if ($null -ne $noted) { [bool]$noted.ok } else { $false })
    }
    if ($Json) { ConvertTo-Json -InputObject $record -Depth 8; exit 0 }
    "stage-store-publish: staged $Project $version -> $stageDir"
    "stage-store-publish: report $reportPath"
    "stage-store-publish: NO upload was performed - the Partner Center upload is the owner's manual [PUBLIC] step"
    exit 0
}
catch {
    $message = $_.Exception.Message
    $code = switch -Regex ($message) {
        '^(ProjectUnknown|MsixBuildMissing|IdentityUnresolved|PublisherAnchorMismatch|VersionInvalid|TicketMissing)' { 2; break }
        '^(MsixBuildFailed|FrozenAnchorAssertFailed)' { 3; break }
        default { 2 }
    }
    if (-not $Json) {
        Write-StageError $message
        exit $code
    }
    [Console]::Error.WriteLine((ConvertTo-Json -InputObject ([ordered]@{ ok = $false; error = $message; code = $code }) -Compress))
    exit $code
}
