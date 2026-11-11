#requires -Version 7.0
<#
.SYNOPSIS
    Build a project and deliver the artifacts where the owner can test them remotely (S0048):
    <Drive root>\<key>\<version>\, with .sha256 sidecars and a LATEST pointer.

.DESCRIPTION
    The outcome half of the phone-filed workflow. After a pass changed a project (S0047), this script builds a
    fresh version and copies it into the synced Drive folder the owner's phone can reach:
    C:\GD\tc\SZA\_APP\<key>\<version>\ by default, one delivery record, one build.delivered event.

    The build command is discovered, never hardcoded: -BuildCommand, else the project's optional
    profile member delivery.buildCommand (its own record), else the repository root's build.ps1. A repo's
    release.ps1 and its STORE_PUBLISHING.md / DEV/RELEASE.md runbooks are never auto-invoked here - a release
    is the owner's own (paid, one-way) path. The version is read, not guessed: -Version, else the profile's
    optional delivery.versionCommand, else the stamp the build put into the artifact, else the newest tag of
    versionShape.tagRegex; a build with no resolvable version is refused.

    The build runs under the resources/build token of the portfolio (TASK-FLOW rule 62) with the ticket id
    (or 'build-deliver' without -Ticket), so it never races a PQ pass building the same repository; a token
    that is not free is waited out for -TokenWaitSeconds. The store leg stays what CHANNEL_MATRIX says it is:
    one-way [PUBLIC], manual in Partner Center - stage-store-publish.ps1 stages, stops at the human gate
    (BlockExternal) and no code path ever uploads.

    Delivery does not move the ticket unless -Ticket is given: then the delivery is also a note on that
    ticket's ledger row, written through the project's own status tooling (never by this script directly).

.PARAMETER Project
    The registry key of the project (exact, case-sensitive, the pq list spelling).

.PARAMETER Ticket
    The ticket the build belongs to: a bare id or <key>:<id>. Tokens, the event and the ledger note carry it.

.PARAMETER BuildOnly
    Build and resolve version and artifacts; nothing is copied, no event is written.

.PARAMETER DeliverOnly
    Copy the artifacts named by -Artifact (no build); the version comes from -Version or the artifacts.

.PARAMETER Artifact
    The artifact(s) to deliver with -DeliverOnly.

.PARAMETER BuildCommand
    The build command line, overriding discovery.

.PARAMETER Version
    The version stamp, overriding resolution.

.PARAMETER DeliveryRoot
    The delivery root; default SZA_DELIVERY_ROOT, else C:\GD\tc\SZA\_APP.

.PARAMETER TokenWaitSeconds
    How long to wait for the resources/build token (default 900).

.PARAMETER TimeoutSeconds
    The build child's ceiling (default 1800).

.PARAMETER Json
    Print the delivery record as one JSON object and nothing else.

.EXAMPLE
    pwsh -NoProfile -File tools/harness/portfolio/build-deliver.ps1 -Project oneclickrunner
    pwsh -NoProfile -File tools/harness/portfolio/build-deliver.ps1 -Project cyrflip -Ticket C123 -Json

.Exit codes
    0 built and delivered (or built, with -BuildOnly)
    2 invalid invocation: unknown project, no build command, missing -Artifact, bad -Version shape
    3 the build failed (non-zero exit, timeout) or produced no artifacts, or the build token never freed
    4 the version did not resolve - refused, not guessed
#>
[CmdletBinding(PositionalBinding = $false)]
param(
    [Parameter(Mandatory)][string]$Project,
    [string]$Ticket = '',
    [string]$BuildCommand = '',
    [string]$Version = '',
    [string]$DeliveryRoot = '',
    [string[]]$Artifact = @(),
    [switch]$BuildOnly,
    [switch]$DeliverOnly,
    [int]$TokenWaitSeconds = 900,
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
. (Join-Path $lib 'events.ps1')
. (Join-Path $lib 'resources.ps1')
. (Join-Path $lib 'delivery.ps1')

function Write-DeliveryError([string]$Message) { [Console]::Error.WriteLine("build-deliver: $Message") }

# load the log lazily: a refused invocation writes no line at all
$log = $null
function Get-DeliveryLog {
    if ($null -eq $script:log) { $script:log = Open-PqLog -Writer cli }
    return $script:log
}

$pairPattern = '^(?<repo>[A-Za-z0-9_.\-]+):(?<id>[A-Za-z0-9_.\-]+)$|^(?<id>[A-Za-z0-9_.\-]+)$'
function Resolve-DeliveryTicket {
    if (-not $Ticket) { return @{ id = $null; repo = $null } }
    $m = [regex]::Match($Ticket, $pairPattern)
    if (-not $m.Success) { throw "TicketInvalid: '$Ticket' is neither an id nor <key>:<id>" }
    $id = $m.Groups['id'].Value
    $repo = $m.Groups['repo'].Value
    if ($repo -and $repo -cne $Project) { throw "TicketInvalid: ticket '$id' belongs to '$repo', not '$Project'" }
    return @{ id = $id; repo = $repo }
}

# One child process; stdout echoed line by line (a build runs long), stderr collected after the exit.
function Invoke-DeliveryChild {
    param([string]$File, [string[]]$Arguments, [string]$WorkingDirectory, [int]$CeilingSeconds)
    $exe = (Get-Process -Id $PID).Path
    $argv = [string[]]@()
    $ext = [IO.Path]::GetExtension($File).ToLowerInvariant()
    if ($ext -ceq '.ps1') { $argv = @('-NoProfile', '-File', $File) + @($Arguments) }
    elseif ($ext -ceq '.bat' -or $ext -ceq '.cmd') { $exe = "$env:ComSpec"; $argv = @('/d', '/c', $File) + @($Arguments) }
    else { throw "UnsupportedBuildCommand: $File" }
    $psi = [Diagnostics.ProcessStartInfo]::new($exe)
    foreach ($a in $argv) { $psi.ArgumentList.Add([string]$a) }
    $psi.WorkingDirectory = $WorkingDirectory
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $proc = [Diagnostics.Process]::Start($psi)
    try {
        $err = $proc.StandardError.ReadToEndAsync()
        $lines = [Collections.Generic.List[string]]::new()
        while ($null -ne ($line = $proc.StandardOutput.ReadLine())) {
            $lines.Add($line)
            if (-not $Json) { Write-Host "  | $line" }
        }
        if (-not $proc.WaitForExit($CeilingSeconds * 1000)) {
            try { $proc.Kill($true) } catch { }
            $null = $proc.WaitForExit(5000)
            return @{ code = 124; lines = @($lines); timedOut = $true }
        }
        foreach ($l in @(([string]$err.Result) -split '\r?\n' | Where-Object { $_ })) {
            $lines.Add($l)
            if (-not $Json) { Write-Host "  ! $l" }
        }
        return @{ code = $proc.ExitCode; lines = @($lines); timedOut = $false }
    }
    finally { $proc.Dispose() }
}

try {
    if ($BuildOnly -and $DeliverOnly) { throw 'DeliverOnlyAndBuildOnly: pick one' }
    if ($DeliverOnly -and @($Artifact).Count -eq 0) { throw 'ArtifactMissing: -DeliverOnly needs -Artifact <files>' }
    if (-not $DeliverOnly -and @($Artifact).Count -gt 0) { throw 'ArtifactNeedsDeliverOnly: -Artifact goes with -DeliverOnly' }
    if ($Version -and $Version -cnotmatch '^\d+(?:\.\d+){1,3}$') { throw "VersionInvalid: '$Version' is not a valid stamp" }
    $ticketRef = Resolve-DeliveryTicket
    $ticketId = $ticketRef.id

    $repo = Resolve-PqDeliveryRepo -Project $Project
    if ($null -eq $repo) { throw "ProjectUnknown: '$Project' is not a registered project with an existing path" }
    $profile = Read-PqProjectProfile -RepoPath $repo.path
    $stamp = Read-PqProjectStamp -RepoPath $repo.path

    if (-not $Json) { "build-deliver: project $Project -> $($repo.path)" }

    $artifacts = [string[]]@()
    $buildInfo = $null
    $tokenWaited = [int]0
    if ($DeliverOnly) {
        foreach ($a in @($Artifact)) { if (-not [IO.File]::Exists($a)) { throw "ArtifactMissing: $a" } }
        $artifacts = [string[]]@($Artifact | ForEach-Object { [IO.Path]::GetFullPath($_) })
    }
    else {
        $command = Resolve-PqBuildCommand -RepoPath $repo.path -BuildCommand $BuildCommand -Profile $profile
        if ($null -eq $command) { throw "BuildCommandMissing: no build command for '$Project' (probe: profile delivery.buildCommand, root build.ps1)" }

        $registry = Read-PqRegistry -Path (Get-PqPath -Kind registry)
        if (-not $registry.ok) { throw "RegistryUnreadable: $($registry.errors | Select-Object -First 1)" }
        $token = Request-PqBuildToken -Registry $registry.registry -RepoKey $Project -TicketId $(if ($ticketId) { $ticketId } else { 'build-deliver' }) -WaitSeconds $TokenWaitSeconds
        if (-not $token.ok) { throw "BuildTokenNotObtained: the build token of '$Project' never freed within ${TokenWaitSeconds}s" }
        $tokenWaited = [Math]::Round([double]$token.waited, 1)
        if (-not $Json -and $tokenWaited -gt 0) { "build-deliver: waited $tokenWaited s for the build token" }

        if (-not $Json) { "build-deliver: build via $($command.source): $($command.file) $($command.args -join ' ')" }
        $since = [DateTime]::UtcNow
        $build = $null
        try {
            $build = Invoke-DeliveryChild -File $command.file -Arguments $command.args -WorkingDirectory $repo.path -CeilingSeconds $TimeoutSeconds
        }
        finally {
            $null = Remove-PqResources -RepoKey $Project -TicketId $token.ticketId
        }
        if ($build.timedOut) { throw "BuildFailed: the build exceeded ${TimeoutSeconds}s and was stopped" }
        if ($build.code -ne 0) { throw "BuildFailed: exit code $($build.code)" }
        $buildInfo = @{ command = $command.file; args = $command.args; source = $command.source }
        $artifacts = Find-PqNewArtifacts -RepoPath $repo.path -SinceUtc $since -Profile $profile
        if (@($artifacts).Count -eq 0) { throw "BuildFailed: the build exited 0 but no fresh artifact was found (searched the repo for $($script:PqArtifactExtensions -join ' '))" }
    }

    $resolved = Resolve-PqDeliveryVersion -RepoPath $repo.path -Artifacts $artifacts -Override $Version -Stamp $stamp -Profile $profile
    if ($null -eq $resolved) { throw "VersionUnresolved: no -Version, no artifact stamp, no versionShape tag - a version is refused, never guessed" }
    $version = [string]$resolved.version

    if ($BuildOnly) {
        $record = [ordered]@{
            project = $Project; version = $version; versionSource = $resolved.source
            artifacts = $artifacts; sha256 = [string[]]@(); at = [DateTimeOffset]::UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
            delivered = $false; root = $null; ticket = $ticketId; build = $buildInfo; tokenWaited = $tokenWaited
        }
        if ($Json) { ConvertTo-Json -InputObject $record -Depth 10 -Compress; exit 0 }
        "build-deliver: built $Project $version (via $($resolved.source)); $($artifacts.Count) artifact(s), nothing delivered (-BuildOnly)"
        foreach ($a in $artifacts) { "  $a" }
        exit 0
    }

    $root = Get-PqDeliveryRoot $DeliveryRoot
    $copy = Copy-PqDeliveryArtifacts -Artifacts $artifacts -Root $root -Key $Project -Version $version
    Set-PqDeliveryLatest -Root $root -Key $Project -Version $version

    $record = [ordered]@{
        project = $Project; version = $version; versionSource = $resolved.source
        artifacts = [string[]]$copy.files; sha256 = [string[]]$copy.sha256
        at = [DateTimeOffset]::UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
        delivered = $true; root = $root; dir = $copy.dir; ticket = $ticketId; build = $buildInfo; tokenWaited = $tokenWaited
    }
    $null = New-PqDeliveryEvent -Log (Get-DeliveryLog) -Record $record
    if ($ticketId) {
        $note = "build $version delivered to $($copy.dir) (artifacts + .sha256 sidecars)"
        $noted = Set-PqTicketDeliveryNote -RepoPath $repo.path -TicketId $ticketId -Note $note
        if (-not $noted.ok) { Write-DeliveryError "the ticket note failed: $($noted.error)" }
    }

    if ($Json) { ConvertTo-Json -InputObject $record -Depth 10 -Compress; exit 0 }
    "build-deliver: delivered $Project $version -> $($copy.dir)"
    foreach ($f in $copy.files) { "  $(Split-Path -Leaf $f)  sha256.." }
    "build-deliver: LATEST -> $version"
    exit 0
}
catch {
    $message = $_.Exception.Message
    # Refusals are the vocabulary: exit 2 says what was asked, 3 says the tools failed, 4 says the version.
    $code = switch -Regex ($message) {
        '^(DeliverOnlyAndBuildOnly|ArtifactMissing|ArtifactNeedsDeliverOnly|VersionInvalid|TicketInvalid|ProjectUnknown|BuildCommandMissing|UnsupportedBuildCommand)' { 2; break }
        '^(BuildFailed|BuildTokenNotObtained)' { 3; break }
        '^VersionUnresolved' { 4; break }
        '^(ArtifactMissing)' { 2; break }
        default { 2 }
    }
    if (-not $Json) {
        Write-DeliveryError $message
        exit $code
    }
    [Console]::Error.WriteLine((ConvertTo-Json -InputObject ([ordered]@{ ok = $false; error = $message; code = $code }) -Compress))
    exit $code
}
