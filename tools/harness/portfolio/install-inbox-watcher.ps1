#requires -Version 7.0
<#
.SYNOPSIS
    Install (or remove) the inbox watcher and the periodic inbox drain.

.DESCRIPTION
    The always-on half of the phone-ticket inbox (S0046): a scheduled task that
      - starts watch-inbox.ps1 at the owner's logon (resident: a FileSystemWatcher plus the 60 s poll), and
      - repeats the same start every 5 minutes as a backstop: while a live watcher holds the inbox, the
        single-instance lock sends the extra start home with `exit 3`; a watcher that died is replaced.
    The task runs as the installing user, only when that user is logged on - the same trust boundary the
    rest of the PQ family uses.

    The inbox root is whatever watch-inbox.ps1 resolves (SZA_INBOX_ROOT, else C:\GD\SZA\ticket-inbox); pass
    -InboxRoot to pin it into the task's command line. The spool folders are created by watch-inbox.ps1 itself
    on first start, the same way publish-projects.ps1 creates them.

    The manual form stays supported: pwsh -NoProfile -File watch-inbox.ps1 (a second start exits 3).
    A separate task runs drain-inbox.ps1 every 10 minutes and dispatches filed tickets through PQ.

.PARAMETER TaskName
    The name of the scheduled task ('SZA inbox watcher' by default).

.PARAMETER DrainTaskName
    The name of the periodic drain task ('SZA inbox drain' by default).

.PARAMETER InboxRoot
    Pinned into the task's command line; left out, the watcher uses SZA_INBOX_ROOT or the default root.

.PARAMETER RepeatMinutes
    The backstop interval (5 minutes).

.PARAMETER Uninstall
    Remove the task instead of registering it.

.PARAMETER DryRun
    Print what would run; write nothing.

.EXAMPLE
    pwsh -NoProfile -File install-inbox-watcher.ps1                # install
    pwsh -NoProfile -File install-inbox-watcher.ps1 -Uninstall     # remove

.Exit codes
    0 the task was registered (or removed), or -DryRun printed the plan
    1 the registration failed
    2 the task to remove was not found
#>
[CmdletBinding(PositionalBinding = $false)]
param(
    [string]$TaskName = 'SZA inbox watcher',
    [string]$DrainTaskName = 'SZA inbox drain',
    [string]$InboxRoot = '',
    [int]$RepeatMinutes = 5,
    [switch]$Uninstall,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$watchScript = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'watch-inbox.ps1'))
$drainScript = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'drain-inbox.ps1'))
if ($RepeatMinutes -lt 1 -or $TaskName -eq $DrainTaskName -or -not [IO.File]::Exists($drainScript)) {
    [Console]::Error.WriteLine('install-inbox-watcher: invalid interval or task names, or drain-inbox.ps1 is missing')
    exit 2
}
if (-not [IO.File]::Exists($watchScript)) {
    [Console]::Error.WriteLine("install-inbox-watcher: watch-inbox.ps1 is not beside this script ($watchScript)")
    exit 1
}
$pwshExe = (Get-Command pwsh -CommandType Application | Select-Object -First 1).Source

if ($Uninstall) {
    if ($DryRun) { Write-Host "install-inbox-watcher: -DryRun - would unregister '$TaskName' and '$DrainTaskName'"; exit 0 }
    try {
        $found = @(@($TaskName, $DrainTaskName) | Where-Object { Get-ScheduledTask -TaskName $_ -ErrorAction SilentlyContinue })
        if ($found.Count -eq 0) {
            [Console]::Error.WriteLine('install-inbox-watcher: neither task exists')
            exit 2
        }
        foreach ($name in $found) { $null = Unregister-ScheduledTask -TaskName $name -Confirm:$false; Write-Host "install-inbox-watcher: task '$name' removed" }
        exit 0
    }
    catch {
        [Console]::Error.WriteLine("install-inbox-watcher: removing '$TaskName' failed: $($_.Exception.Message)")
        exit 1
    }
}

# The command line: the watcher, hidden, its window never stealing focus at logon.
$argument = "-NoProfile -WindowStyle Hidden -File `"$watchScript`""
if ($InboxRoot) { $argument += " -InboxRoot `"$InboxRoot`"" }
$display = "at logon, and the same resident start every $RepeatMinutes min as the backstop: pwsh $argument"
$drainArgument = "-NoProfile -WindowStyle Hidden -File `"$drainScript`""
if ($InboxRoot) { $drainArgument += " -InboxRoot `"$InboxRoot`"" }

if ($DryRun) {
    Write-Host "install-inbox-watcher: -DryRun - would register the task '$TaskName', $display"
    Write-Host "install-inbox-watcher: -DryRun - would register '$DrainTaskName' every 10 min: pwsh $drainArgument"
    exit 0
}

$action = New-ScheduledTaskAction -Execute $pwshExe -Argument $argument
$atLogon = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
# The repetition duration must be bounded: [TimeSpan]::MaxValue writes P99999999D.., which the task schema
# rejects ("out of range"). Ten years of backstops, renewed by the next run of this installer.
$backstop = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes $RepeatMinutes) -RepetitionDuration (New-TimeSpan -Days 3650)
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew
# No execution time limit: the resident instance IS the listener (a default 3-day limit would end it; the
# The task holds ONE action, the resident start; the repeating trigger serves as the backstop through the
# single-instance lock - a redundant start exits 3, a dead watcher is replaced in full.
try { $settings.ExecutionTimeLimit = 'PT0S' } catch { }

try {
    $null = Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger @($atLogon, $backstop) -Settings $settings -Description `
        "S0046: watches the phone-ticket inbox and files each packet as a Draft ticket through spec-draft. Resident at logon; the repeating trigger re-arms it every $RepeatMinutes minutes."
    $drainAction = New-ScheduledTaskAction -Execute $pwshExe -Argument $drainArgument
    $drainTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 10) -RepetitionDuration (New-TimeSpan -Days 3650)
    $null = Register-ScheduledTask -TaskName $DrainTaskName -Action $drainAction -Trigger $drainTrigger -Settings $settings -Description 'S0047: ingests and dispatches incoming tickets through named PQ starts every 10 minutes.'
    Write-Host "install-inbox-watcher: task '$DrainTaskName' registered - every 10 min"
    $manual = "pwsh -NoProfile -File `"$watchScript`""
    if ($InboxRoot) { $manual += " -InboxRoot `"$InboxRoot`"" }
    Write-Host "install-inbox-watcher: task '$TaskName' registered - $display"
    Write-Host "install-inbox-watcher: the listener starts at the next logon; start it now with:"
    Write-Host "  $manual"
    exit 0
}
catch {
    [Console]::Error.WriteLine("install-inbox-watcher: registering '$TaskName' failed: $($_.Exception.Message)")
    [Console]::Error.WriteLine("The manual form works without a task: pwsh -NoProfile -File `"$watchScript`"")
    exit 1
}
