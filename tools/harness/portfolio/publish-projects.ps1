#requires -Version 7.0
<#
.SYNOPSIS
    Publish the registered project keys into the phone's ticket inbox as projects.json (S0045).

.DESCRIPTION
    The format half of the phone-ticket transport freezes the picker input: the phone app (the
    fms-a implementation ticket filed by S0045) shows the registered projects to file a ticket
    against, and it learns the list from `projects.json` in the inbox root - never from the
    registry file, which the phone cannot reach.

      - the keys come from the portfolio registry (repos.json, TASK-FLOW rules 41/42/60), the
        machine output `pq list -Json` reads from; the display name is the leaf folder name of
        the registry path;
      - the shape is frozen in docs/INBOX-PACKET.md section 3:
          { "schemaVersion": 1, "generatedAt": "<RFC 3339 UTC>", "projects": [ { "key", "name" } ] }
        in the registry's project order (rule 44);
      - the file lands in the inbox root beside the spool folders (new/, processing/, done/,
        failed/), which are created here when missing - idempotent, safe to re-run;
      - a missing registry is a named error (exit 2); an empty registry publishes an empty list -
        the phone then falls back to free text with project: null, by design.

    The inbox root: -InboxRoot, else SZA_INBOX_ROOT, else C:\GD\SZA\ticket-inbox (the visible
    shared Drive folder Drive for desktop keeps on this machine).

    Scheduled refresh (docs/INBOX-PACKET.md section 3): any repeating task that runs this
    script keeps the list current, for example a logon task with a 1-hour repetition:
        Register-ScheduledTask -TaskName 'SZA publish-projects' -Trigger @((New-ScheduledTaskTrigger -AtLogOn),
            (New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Hours 1))) `
            -Action (New-ScheduledTaskAction -Execute 'pwsh' -Argument '-NoProfile -File <this script>')

    Exit codes: 0 published; 2 bad invocation or a named registry error.

    The last line is the machine-readable result:
        published <n> project(s) to <inbox root>\projects.json
#>
[CmdletBinding(PositionalBinding = $false)]
param(
    [string] $InboxRoot = '',
    [string] $RegistryPath = '',
    [switch] $Help
)

if ($Help) {
    Get-Help -Name $PSCommandPath -Detailed | Out-String -Width 120 | Write-Host
    exit 0
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib/registry.ps1')

function Stop-Publish([int] $Code, [string] $Name, [string] $Message) {
    [Console]::Error.WriteLine("publish-projects: ${Name}: $Message")
    exit $Code
}

if (-not $InboxRoot) { $InboxRoot = $env:SZA_INBOX_ROOT }
if (-not $InboxRoot) { $InboxRoot = 'C:\GD\SZA\ticket-inbox' }
if (-not [IO.Path]::IsPathFullyQualified($InboxRoot)) {
    Stop-Publish 2 'ArgumentInvalid' "the inbox root '$InboxRoot' is not an absolute path"
}

$read = Read-PqRegistry -Path $RegistryPath
if (-not $read.ok) {
    $first = @($read.errors)[0]
    Stop-Publish 2 $first.name $first.message
}

$projects = @(foreach ($repo in @($read.document.repos)) {
    $path = [string]$repo.path
    $leaf = if ($path) { [IO.Path]::GetFullPath($path) } else { '' }
    [ordered]@{ key = [string]$repo.key; name = if ($leaf) { Split-Path -Leaf $leaf } else { [string]$repo.key } }
})

$doc = [ordered]@{
    schemaVersion = 1
    generatedAt   = ([DateTimeOffset]::UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'"))
    projects      = $projects
}

foreach ($dir in @('', 'new', 'processing', 'done', 'failed')) {
    $p = if ($dir) { Join-Path $InboxRoot $dir } else { $InboxRoot }
    if (-not [IO.Directory]::Exists($p)) { $null = [IO.Directory]::CreateDirectory($p) }
}

$jsonPath = Join-Path $InboxRoot 'projects.json'
$json = (ConvertTo-Json -InputObject $doc -Depth 64).Replace("`r`n", "`n") + "`n"
$bytes = [Text.UTF8Encoding]::new($false).GetBytes($json)
$temp = "$jsonPath.tmp"
try {
    [IO.File]::WriteAllBytes($temp, $bytes)
    [IO.File]::Move($temp, $jsonPath, $true)
}
catch {
    if ([IO.File]::Exists($temp)) { try { [IO.File]::Delete($temp) } catch { } }
    Stop-Publish 2 'WriteFailed' "cannot write $jsonPath - $($_.Exception.Message)"
}

"published $(@($projects).Count) project(s) to $jsonPath"
exit 0
