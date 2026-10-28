#requires -Version 7.0
<#
.SYNOPSIS
    Put the portfolio queue shortcuts (PQ ...) on the Desktop, or take them off again.

.DESCRIPTION
    One shortcut per everyday pq command. Every shortcut opens a PowerShell 7 window that stays open
    (-NoExit), the same way the repository launchers' shortcuts do, and runs this folder's pq.ps1, so
    the shortcuts follow the checkout they were made from. Run this script from the canon working tree,
    not from the plugin cache: the cache path changes with every plugin version.

      PQ Start            pq start                  one worker; waits a minute when nothing is ranked
      PQ Start 1 ticket   pq start -MaxTickets 1    one pass, then the window stays open (the attended first run)
      PQ Status           pq status                 workers, today's passes, the next ticket, STOP
      PQ Log              pq log -Last 60           the last events across all writers
      PQ Stop             pq stop                   workers end after the pass they are on
      PQ Stop Kill        pq stop -Kill             also ends the runner children now (the ticket in flight is lost)
      PQ Dry-run          pq dry-run                the order the loop would take; launches nothing
      PQ Queue            pq queue                  open PORTFOLIO_QUEUE.md in the editor (pq queue -Init writes the first one)
      PQ Doctor           pq doctor                 check the enabled repositories and the queue file
      PQ Repos            pq list                   the registered repositories
      PQ Guide            README.md of this folder  the operator's instruction

    A shortcut is replaced only when the file already there is one of ours (its target runs pq.ps1, or it is
    the guide). Any other file with the same name is reported and left alone. -Remove takes off the same
    set under the same test. Nothing is written outside the Desktop folder.

    Exit codes: 0 done; 2 invalid invocation (no such folder, no pq.ps1 beside this script, no COM shell).

.PARAMETER Desktop
    The folder to write into. Default: the user's Desktop (a OneDrive-redirected one is honoured).

.PARAMETER Remove
    Delete the PQ shortcuts instead of writing them.

.PARAMETER DryRun
    Print what would happen and write nothing.

.EXAMPLE
    pwsh -NoProfile -File tools/harness/portfolio/install-shortcuts.ps1

.EXAMPLE
    pwsh -NoProfile -File tools/harness/portfolio/install-shortcuts.ps1 -Remove
#>
[CmdletBinding()]
param(
    [string]$Desktop,
    [switch]$Remove,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$pq = Join-Path $PSScriptRoot 'pq.ps1'
$guide = Join-Path $PSScriptRoot 'README.md'
$workDir = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$pwshExe = Join-Path $PSHOME 'pwsh.exe'

if (-not $Desktop) { $Desktop = [Environment]::GetFolderPath('Desktop') }
if (-not $Desktop -or -not [IO.Directory]::Exists($Desktop)) {
    [Console]::Error.WriteLine("install-shortcuts: no such folder '$Desktop'")
    exit 2
}
if (-not [IO.File]::Exists($pq)) {
    [Console]::Error.WriteLine("install-shortcuts: pq.ps1 not found beside this script ($pq)")
    exit 2
}

# The set, as data. Pq is the argument string after pq.ps1; Guide marks the one shortcut that opens a document.
$set = @(
    @{ Name = 'PQ Start';          Pq = 'start';              Text = 'Portfolio queue: one worker over the registered repositories; waits when nothing is ranked' }
    @{ Name = 'PQ Start 1 ticket'; Pq = 'start -MaxTickets 1'; Text = 'Portfolio queue: one pass on the first ranked ticket, then stop (attended first run)' }
    @{ Name = 'PQ Status';        Pq = 'status';             Text = 'Portfolio queue: workers, passes today, the next ticket, STOP' }
    @{ Name = 'PQ Log';           Pq = 'log -Last 60';       Text = 'Portfolio queue: the last 60 events across all writers' }
    @{ Name = 'PQ Stop';          Pq = 'stop';               Text = 'Portfolio queue: workers end after the pass they are on' }
    @{ Name = 'PQ Stop Kill';     Pq = 'stop -Kill';         Text = 'Portfolio queue: stop now - the runner children are terminated and the ticket in flight is abandoned' }
    @{ Name = 'PQ Dry-run';       Pq = 'dry-run';            Text = 'Portfolio queue: the order the loop would take; launches nothing' }
    @{ Name = 'PQ Queue';         Pq = 'queue';              Text = 'Portfolio queue: open PORTFOLIO_QUEUE.md, the owner''s order of projects and tickets' }
    @{ Name = 'PQ Doctor';        Pq = 'doctor';             Text = 'Portfolio queue: check the enabled repositories and the queue file' }
    @{ Name = 'PQ Repos';         Pq = 'list';               Text = 'Portfolio queue: the registered repositories' }
    @{ Name = 'PQ Guide';         Guide = $true;             Text = 'Portfolio queue: the operator''s instruction' }
)

try { $shell = New-Object -ComObject WScript.Shell }
catch {
    [Console]::Error.WriteLine("install-shortcuts: the Windows shell COM object is unavailable ($($_.Exception.Message))")
    exit 2
}

# A shortcut already on disk is ours when it runs this pq.ps1 or opens the guide.
function Test-Ours([string]$LnkPath) {
    $l = $shell.CreateShortcut($LnkPath)
    $arg = [string]$l.Arguments
    $tgt = [string]$l.TargetPath
    return ($arg -match '(?i)portfolio[\\/]pq\.ps1') -or ($tgt -ieq $guide)
}

$counts = [ordered]@{ created = 0; updated = 0; removed = 0; foreign = 0; unchanged = 0 }

foreach ($s in $set) {
    $lnk = Join-Path $Desktop ($s.Name + '.lnk')
    $exists = [IO.File]::Exists($lnk)

    if ($exists -and -not (Test-Ours $lnk)) {
        "skipped      $($s.Name).lnk - a shortcut of that name exists and is not a PQ one; left alone"
        $counts.foreign++
        continue
    }

    if ($Remove) {
        if (-not $exists) { continue }
        if ($DryRun) { "would remove $($s.Name).lnk" }
        else { Remove-Item -LiteralPath $lnk -Force; "removed      $($s.Name).lnk" }
        $counts.removed++
        continue
    }

    $isGuide = $s.ContainsKey('Guide') -and $s.Guide
    $target = if ($isGuide) { $guide } else { $pwshExe }
    $arguments = if ($isGuide) { '' } else { "-NoExit -NoProfile -File `"$pq`" $($s.Pq)" }
    $icon = if ($isGuide) { '' } else { "$pwshExe,0" }
    $dir = if ($isGuide) { $PSScriptRoot } else { $workDir }

    if ($DryRun) {
        "would $(if ($exists) { 'update' } else { 'create' }) $($s.Name).lnk -> $(if ($isGuide) { $guide } else { 'pq.ps1 ' + $s.Pq })"
        if ($exists) { $counts.updated++ } else { $counts.created++ }
        continue
    }

    $l = $shell.CreateShortcut($lnk)
    $same = $exists -and ([string]$l.TargetPath -ieq $target) -and ([string]$l.Arguments -ceq $arguments) -and
            ([string]$l.WorkingDirectory -ieq $dir) -and ([string]$l.Description -ceq $s.Text)
    if ($same) { "unchanged    $($s.Name).lnk"; $counts.unchanged++; continue }
    $l.TargetPath = $target
    $l.Arguments = $arguments
    $l.WorkingDirectory = $dir
    $l.Description = $s.Text
    $l.WindowStyle = 1
    if ($icon) { $l.IconLocation = $icon }
    $l.Save()
    if ($exists) { "updated      $($s.Name).lnk"; $counts.updated++ } else { "created      $($s.Name).lnk"; $counts.created++ }
}

"install-shortcuts: $($counts.created) created, $($counts.updated) updated, $($counts.unchanged) unchanged, $($counts.removed) removed, $($counts.foreign) foreign in $Desktop$(if ($DryRun) { ' (dry run)' })"
exit 0
