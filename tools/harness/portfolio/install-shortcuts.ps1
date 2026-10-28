#requires -Version 7.0
<#
.SYNOPSIS
    Put the portfolio queue shortcuts (PQ ...) on the Desktop and in the canon working tree root, or take them off again.

.DESCRIPTION
    One shortcut per everyday pq command. Every shortcut opens a PowerShell 7 window that stays open
    (-NoExit), the same way the repository launchers' shortcuts do, and runs this folder's pq.ps1, so
    the shortcuts follow the checkout they were made from. Run this script from the canon working tree,
    not from the plugin cache: the cache path changes with every plugin version.

    The two text files the owner steers by:

      PQ Projects         pq queue                  open PORTFOLIO_QUEUE.md, synced first: every ticket of every
                                                    registered project, one row each, new ones at the bottom; the
                                                    order of the rows is the order of the work; `hold` pauses
      PQ Tickets <key>    pq tickets <key>          open that repository's own ticket queue file, where its plan tool
                                                    adds new tickets (one shortcut per enabled repository; run this
                                                    script again after a repository is enabled, disabled or removed)

    The rest:

      PQ Dry-run          pq dry-run                the order the loop would take; launches nothing
      PQ Start            pq start                  one worker; waits a minute when nothing is ranked
      PQ Start 1 ticket   pq start -MaxTickets 1    one pass, then the window stays open (the attended first run)
      PQ Start Drain      pq start -Drain           work until nothing is ranked, then end
      PQ Status           pq status                 workers, today's passes, the next ticket, STOP
      PQ Log              pq log -Last 60           the last events across all writers
      PQ Stop             pq stop                   workers end after the pass they are on
      PQ Stop Kill        pq stop -Kill             also ends the runner children now (the ticket in flight is lost)
      PQ Doctor           pq doctor                 check the enabled repositories and the queue file
      PQ Repos            pq list                   the registered repositories
      PQ Guide            README.md of this folder  the operator's instruction

    The set goes into the Desktop and into the root of the canon working tree (the root copies are ignored by git:
    deploy.ps1 stages everything else). A shortcut is replaced only when the file already there is one of ours (its
    target runs pq.ps1, or it is the guide). Any other file with the same name is reported and left alone. A refresh
    also drops our own shortcut of the former name `PQ Queue` and our `PQ Tickets` shortcuts of repositories that are
    no longer registered or enabled. -Remove takes off the same set under the same test. Nothing is written outside the two
    folders.

    Exit codes: 0 done; 2 invalid invocation (no such folder, no pq.ps1 beside this script, no COM shell).

.PARAMETER Where
    Both (default), Desktop or Root.

.PARAMETER Desktop
    The folder that stands for the Desktop. Default: the user's Desktop (a OneDrive-redirected one is honoured).

.PARAMETER RootDir
    The folder that stands for the canon working tree root. Default: the root of the checkout this script sits in.

.PARAMETER Remove
    Delete the PQ shortcuts instead of writing them.

.PARAMETER DryRun
    Print what would happen and write nothing.

.EXAMPLE
    pwsh -NoProfile -File tools/harness/portfolio/install-shortcuts.ps1

.EXAMPLE
    pwsh -NoProfile -File tools/harness/portfolio/install-shortcuts.ps1 -Where Desktop -Remove
#>
[CmdletBinding()]
param(
    [ValidateSet('Both', 'Desktop', 'Root')][string]$Where = 'Both',
    [string]$Desktop,
    [string]$RootDir,
    [switch]$Remove,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$pq = Join-Path $PSScriptRoot 'pq.ps1'
$guide = Join-Path $PSScriptRoot 'README.md'
$workDir = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$pwshExe = Join-Path $PSHOME 'pwsh.exe'

if (-not [IO.File]::Exists($pq)) {
    [Console]::Error.WriteLine("install-shortcuts: pq.ps1 not found beside this script ($pq)")
    exit 2
}

$folders = [Collections.Generic.List[object]]::new()
if ($Where -ne 'Root') {
    if (-not $Desktop) { $Desktop = [Environment]::GetFolderPath('Desktop') }
    if (-not $Desktop -or -not [IO.Directory]::Exists($Desktop)) {
        [Console]::Error.WriteLine("install-shortcuts: no such folder '$Desktop'")
        exit 2
    }
    $folders.Add(@{ Label = 'Desktop'; Path = $Desktop })
}
if ($Where -ne 'Desktop') {
    if (-not $RootDir) { $RootDir = $workDir }
    if (-not [IO.Directory]::Exists($RootDir)) {
        [Console]::Error.WriteLine("install-shortcuts: no such folder '$RootDir'")
        exit 2
    }
    $folders.Add(@{ Label = 'Root'; Path = $RootDir })
}

# The enabled repositories, for the PQ Tickets shortcuts. A missing or unreadable registry means none.
$portfolioRoot = if ($env:SZA_PORTFOLIO_ROOT) { $env:SZA_PORTFOLIO_ROOT } else { Join-Path $env:USERPROFILE '.sza\portfolio' }
$keys = [Collections.Generic.List[string]]::new()
$registryFile = Join-Path $portfolioRoot 'repos.json'
if ([IO.File]::Exists($registryFile)) {
    try {
        $reg = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($registryFile)) -DateKind String
        foreach ($r in @($reg.repos)) {
            $k = [string]$r.key
            $on = $null -ne $r.PSObject.Properties['enabled'] -and $r.enabled -eq $true
            if ($on -and $k -match '^[A-Za-z0-9._-]+$') { $keys.Add($k) }
        }
    }
    catch { }
}

# The set, as data. Pq is the argument string after pq.ps1; Guide marks the one shortcut that opens a document.
$set = [Collections.Generic.List[hashtable]]::new()
$set.Add(@{ Name = 'PQ Projects'; Pq = 'queue'; Text = 'Portfolio queue: open PORTFOLIO_QUEUE.md, every ticket of every project in the order of the work (new ones at the bottom; hold pauses)' })
foreach ($k in $keys) {
    $set.Add(@{ Name = "PQ Tickets $k"; Pq = "tickets $k"; Text = "Portfolio queue: open the ticket queue file of $k, the order of its tickets" })
}
$set.Add(@{ Name = 'PQ Dry-run'; Pq = 'dry-run'; Text = 'Portfolio queue: the order the loop would take; launches nothing' })
$set.Add(@{ Name = 'PQ Start'; Pq = 'start'; Text = 'Portfolio queue: one worker over the registered repositories; waits when nothing is ranked' })
$set.Add(@{ Name = 'PQ Start 1 ticket'; Pq = 'start -MaxTickets 1'; Text = 'Portfolio queue: one pass on the first ranked ticket, then stop (attended first run)' })
$set.Add(@{ Name = 'PQ Start Drain'; Pq = 'start -Drain'; Text = 'Portfolio queue: work until nothing is ranked, then end' })
$set.Add(@{ Name = 'PQ Status'; Pq = 'status'; Text = 'Portfolio queue: workers, passes today, the next ticket, STOP' })
$set.Add(@{ Name = 'PQ Log'; Pq = 'log -Last 60'; Text = 'Portfolio queue: the last 60 events across all writers' })
$set.Add(@{ Name = 'PQ Stop'; Pq = 'stop'; Text = 'Portfolio queue: workers end after the pass they are on' })
$set.Add(@{ Name = 'PQ Stop Kill'; Pq = 'stop -Kill'; Text = 'Portfolio queue: stop now - the runner children are terminated and the ticket in flight is abandoned' })
$set.Add(@{ Name = 'PQ Doctor'; Pq = 'doctor'; Text = 'Portfolio queue: check the enabled repositories and the queue file' })
$set.Add(@{ Name = 'PQ Repos'; Pq = 'list'; Text = 'Portfolio queue: the registered repositories' })
$set.Add(@{ Name = 'PQ Guide'; Guide = $true; Text = 'Portfolio queue: the operator''s instruction' })

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

foreach ($folder in $folders) {
    $dir0 = $folder.Path
    $counts = [ordered]@{ created = 0; updated = 0; removed = 0; foreign = 0; unchanged = 0 }

    foreach ($s in $set) {
        $lnk = Join-Path $dir0 ($s.Name + '.lnk')
        $exists = [IO.File]::Exists($lnk)

        if ($exists -and -not (Test-Ours $lnk)) {
            "skipped      $($s.Name).lnk ($($folder.Label)) - a shortcut of that name exists and is not a PQ one; left alone"
            $counts.foreign++
            continue
        }

        if ($Remove) {
            if (-not $exists) { continue }
            if ($DryRun) { "would remove $($s.Name).lnk ($($folder.Label))" }
            else { Remove-Item -LiteralPath $lnk -Force; "removed      $($s.Name).lnk ($($folder.Label))" }
            $counts.removed++
            continue
        }

        $isGuide = $s.ContainsKey('Guide') -and $s.Guide
        $target = if ($isGuide) { $guide } else { $pwshExe }
        $arguments = if ($isGuide) { '' } else { "-NoExit -NoProfile -File `"$pq`" $($s.Pq)" }
        $icon = if ($isGuide) { '' } else { "$pwshExe,0" }
        $dir = if ($isGuide) { $PSScriptRoot } else { $workDir }

        if ($DryRun) {
            "would $(if ($exists) { 'update' } else { 'create' }) $($s.Name).lnk ($($folder.Label)) -> $(if ($isGuide) { $guide } else { 'pq.ps1 ' + $s.Pq })"
            if ($exists) { $counts.updated++ } else { $counts.created++ }
            continue
        }

        $l = $shell.CreateShortcut($lnk)
        $same = $exists -and ([string]$l.TargetPath -ieq $target) -and ([string]$l.Arguments -ceq $arguments) -and
                ([string]$l.WorkingDirectory -ieq $dir) -and ([string]$l.Description -ceq $s.Text)
        if ($same) { "unchanged    $($s.Name).lnk ($($folder.Label))"; $counts.unchanged++; continue }
        $l.TargetPath = $target
        $l.Arguments = $arguments
        $l.WorkingDirectory = $dir
        $l.Description = $s.Text
        $l.WindowStyle = 1
        if ($icon) { $l.IconLocation = $icon }
        $l.Save()
        if ($exists) { "updated      $($s.Name).lnk ($($folder.Label))"; $counts.updated++ } else { "created      $($s.Name).lnk ($($folder.Label))"; $counts.created++ }
    }

    # Ours that no longer belong: the former name of the projects shortcut, and a PQ Tickets one whose repository is gone.
    # On -Remove every PQ Tickets shortcut of ours goes, registered or not.
    $current = @($set | ForEach-Object { $_.Name })
    $candidates = @('PQ Queue') + @(Get-ChildItem -LiteralPath $dir0 -Filter 'PQ Tickets *.lnk' -File -ErrorAction SilentlyContinue |
            ForEach-Object { [IO.Path]::GetFileNameWithoutExtension($_.Name) })
    foreach ($name in ($candidates | Sort-Object -Unique)) {
        if (-not $Remove -and $current -contains $name) { continue }
        $lnk = Join-Path $dir0 ($name + '.lnk')
        if (-not [IO.File]::Exists($lnk) -or -not (Test-Ours $lnk)) { continue }
        if ($DryRun) { "would remove $name.lnk ($($folder.Label)) - no longer part of the set" }
        else { Remove-Item -LiteralPath $lnk -Force; "removed      $name.lnk ($($folder.Label)) - no longer part of the set" }
        $counts.removed++
    }

    "install-shortcuts: $($counts.created) created, $($counts.updated) updated, $($counts.unchanged) unchanged, $($counts.removed) removed, $($counts.foreign) foreign in $dir0$(if ($DryRun) { ' (dry run)' })"
}
exit 0
