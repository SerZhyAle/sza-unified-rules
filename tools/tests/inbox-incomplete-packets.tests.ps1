#requires -Version 7.0
<#
.SYNOPSIS
    Cases for S0085: the removal of abandoned packet folders from the phone-ticket inbox, and the retry of a packet
    whose check hits an I/O error. lib/inbox-spool.ps1 (Remove-InboxIncompletePackets, Release-InboxClaimOwner),
    lib/inbox-ingest.ps1 (Invoke-InboxIngestPacket), watch-inbox.ps1 (one -Once pass).

.DESCRIPTION
    Everything runs in throwaway scratch roots under the temp folder: a spool per case, a portfolio root for the
    event log, and -Once child run of watch-inbox.ps1 against a scratch inbox. The real inbox
    (C:\GD\SZA\ticket-inbox), the owner's registry and every project of the portfolio are never touched. The
    functions are called directly; the ages are set by writing file times, so no case waits.

    The removal (INBOX-PACKET section 2.3, DEVICE-EXCHANGE item FD):
      removes-an-abandoned-folder-and-its-sidecar      8 days idle, no manifest.json: folder and sidecar gone
      keeps-a-folder-inside-the-window                 6 days idle: kept with its sidecar; -MaxAgeSeconds is honoured
      age-is-the-newest-write-of-anything-in-it        a slow upload: old folder time, one fresh file (also nested)
      age-counts-creation-time                         a file synced with an old write time is new on this disk
      never-touches-a-folder-with-a-manifest           a parsable, an unparsable and an empty manifest.json, 8 days old
      reads-only-new                                   processing/, done/ and failed/ are left alone
      reports-a-folder-it-cannot-remove                a locked file: failed, no throw, folder and sidecar stay
      survives-a-missing-spool                         no new/ or no root: an empty record
      the-watcher-pass-removes-and-keeps               watch-inbox.ps1 -Once: prints the removal, exits 0
    The packet check (S0085 section 3.1):
      a-locked-payload-is-a-retry-not-a-throw          a payload another process holds open: Invoke-InboxIngestPacket
                                                       returns, the packet is held by the stale window and recovery
                                                       re-queues it
      an-unreadable-payload-is-requeued                the move works: back in new/ with attempts 1 and the error text

    Run:  pwsh -NoProfile -File tools/tests/inbox-incomplete-packets.tests.ps1 [-KeepScratch]
#>
[CmdletBinding()]
param([switch]$KeepScratch)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$SourceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
. (Join-Path $SourceRoot 'tools\harness\portfolio\lib\inbox-ingest.ps1')   # loads the spool, the packet reader, paths, events
$watchScript = Join-Path $SourceRoot 'tools\harness\portfolio\watch-inbox.ps1'
$pwshExe = (Get-Command pwsh -CommandType Application | Select-Object -First 1).Source

$run = 0; $passed = 0; $failed = 0
function Assert-That([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Run-Case([string]$Name, [scriptblock]$Body) {
    $script:run++
    Write-Host -NoNewline "CASE  $Name ... "
    try { & $Body; $script:passed++; Write-Host 'PASS' -ForegroundColor Green }
    catch { $script:failed++; Write-Host 'FAIL' -ForegroundColor Red; Write-Host "      $($_.Exception.Message)" -ForegroundColor DarkRed }
}

$scratch = Join-Path ([IO.Path]::GetTempPath()) ('inbox-incomplete-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$null = [IO.Directory]::CreateDirectory($scratch)
$portfolio = Join-Path $scratch 'portfolio'
$null = [IO.Directory]::CreateDirectory((Join-Path $portfolio 'log'))
$savedPortfolioRoot = $env:SZA_PORTFOLIO_ROOT
$savedInboxRoot = $env:SZA_INBOX_ROOT
$env:SZA_PORTFOLIO_ROOT = $portfolio
$script:spoolSeq = 0

# ---- helpers ----
function New-Spool {
    $script:spoolSeq++
    return (Initialize-InboxSpool (Join-Path $scratch ('inbox-' + $script:spoolSeq)))
}
# Every entry under (and including) the folder gets the same write and creation time, the folder last.
function Set-TreeAge([string]$Dir, [double]$Days) {
    $t = [DateTime]::UtcNow.AddDays(-$Days)
    foreach ($e in [IO.Directory]::GetFileSystemEntries($Dir, '*', [IO.SearchOption]::AllDirectories) | Sort-Object -Property Length -Descending) {
        if ([IO.Directory]::Exists($e)) { [IO.Directory]::SetCreationTimeUtc($e, $t); [IO.Directory]::SetLastWriteTimeUtc($e, $t) }
        else { [IO.File]::SetCreationTimeUtc($e, $t); [IO.File]::SetLastWriteTimeUtc($e, $t) }
    }
    [IO.Directory]::SetCreationTimeUtc($Dir, $t)
    [IO.Directory]::SetLastWriteTimeUtc($Dir, $t)
}
# A folder in new/ (or another stage) holding the named files, idle for $Days, with an optional attempts sidecar.
function New-Folder([string]$Spool, [string]$Id, [hashtable]$Files, [double]$Days, [string]$Stage = 'new', [switch]$Sidecar) {
    $dir = Join-Path (Join-Path $Spool $Stage) $Id
    $null = [IO.Directory]::CreateDirectory($dir)
    foreach ($name in $Files.Keys) { [IO.File]::WriteAllText((Join-Path $dir $name), [string]$Files[$name], [Text.UTF8Encoding]::new($false)) }
    Set-TreeAge $dir $Days
    if ($Sidecar) {
        Write-InboxAttempts -Path (Get-InboxAttemptsPath -StageDir (Join-Path $Spool $Stage) -PacketId $Id) `
            -Attempts ([pscustomobject]@{ attempts = 1; nextRetryAtEpochMs = [long]0; lastError = 'old try' })
    }
    return $dir
}
function Test-Sidecar([string]$Spool, [string]$Id) { return [IO.File]::Exists((Get-InboxAttemptsPath -StageDir (Join-Path $Spool 'new') -PacketId $Id)) }
function Test-Folder([string]$Spool, [string]$Id, [string]$Stage = 'new') { return [IO.Directory]::Exists((Join-Path (Join-Path $Spool $Stage) $Id)) }
function New-ValidPacket([string]$Spool, [string]$Id) {
    $dir = Join-Path (Join-Path $Spool 'new') $Id
    $null = [IO.Directory]::CreateDirectory($dir)
    $body = [Text.UTF8Encoding]::new($false).GetBytes("a ticket`n")
    [IO.File]::WriteAllBytes((Join-Path $dir 'text.md'), $body)
    $manifest = [ordered]@{
        schemaVersion = 2; payloadKind = 'TICKET'; packetId = $Id; createdAtEpochMs = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        senderDeviceName = 'Pixel 8 (test)'; senderDeviceId = 'dev-test-000'; targetDeviceName = 'SZA-PC (test)'; status = 'PENDING'
        fileNames = @('text.md'); totalSizeBytes = [long]$body.Length; ttlSeconds = 604800
        files = @([ordered]@{ name = 'text.md'; size = [long]$body.Length; sha256 = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($body)).ToLowerInvariant(); mimeType = 'text/markdown'; role = 'text' })
        project = $null; text = 'a ticket'
    }
    $null = Write-InboxPacketManifest -Manifest $manifest -Path (Join-Path $dir 'manifest.json')
    return $dir
}
# The spec-draft path is resolved before the check runs; the check throws before it is ever executed.
$specDraft = Join-Path $SourceRoot 'tools\harness\portfolio\spec-draft.ps1'

try {
    Write-Host 'the removal of abandoned folders'

    Run-Case 'removes-an-abandoned-folder-and-its-sidecar' {
        $spool = New-Spool
        $null = New-Folder $spool 'pk-old' @{ 'text.md' = 'half an upload' } 8 -Sidecar
        $r = Remove-InboxIncompletePackets -Root $spool
        Assert-That (@($r.removed).Count -eq 1 -and $r.removed[0].packetId -ceq 'pk-old') "removed: $(@($r.removed | ForEach-Object { $_.packetId }) -join ',')"
        Assert-That (@($r.failed).Count -eq 0) "failed: $(@($r.failed | ForEach-Object { $_.message }) -join ' | ')"
        Assert-That (-not (Test-Folder $spool 'pk-old')) 'the folder is still in new/'
        Assert-That (-not (Test-Sidecar $spool 'pk-old')) 'the attempts sidecar is still in new/'
        Assert-That ($r.removed[0].ageSeconds -ge (8 * 86400 - 60) -and $r.removed[0].age -ceq '8d') "the age was reported as $($r.removed[0].age) ($($r.removed[0].ageSeconds) s)"
    }

    Run-Case 'keeps-a-folder-inside-the-window' {
        $spool = New-Spool
        $null = New-Folder $spool 'pk-young' @{ 'text.md' = 'arriving' } 6 -Sidecar
        $r = Remove-InboxIncompletePackets -Root $spool
        Assert-That (@($r.removed).Count -eq 0 -and @($r.failed).Count -eq 0) 'a 6-day-old folder was touched'
        Assert-That ((Test-Folder $spool 'pk-young') -and (Test-Sidecar $spool 'pk-young')) 'the folder or its sidecar is gone'
        $null = New-Folder $spool 'pk-8d' @{ 'text.md' = 'x' } 8
        $r = Remove-InboxIncompletePackets -Root $spool -MaxAgeSeconds (9 * 86400)
        Assert-That (@($r.removed).Count -eq 0 -and (Test-Folder $spool 'pk-8d')) '-MaxAgeSeconds 9 days did not keep an 8-day-old folder'
        $r = Remove-InboxIncompletePackets -Root $spool -MaxAgeSeconds (7 * 86400)
        Assert-That (@($r.removed).Count -eq 1 -and $r.removed[0].packetId -ceq 'pk-8d' -and (Test-Folder $spool 'pk-young')) 'a 7-day window did not take exactly the 8-day-old folder'
    }

    Run-Case 'age-is-the-newest-write-of-anything-in-it' {
        $spool = New-Spool
        # A slow upload: the folder's own time is 9 days old, one payload file was written just now.
        $dir = New-Folder $spool 'pk-slow' @{ 'a.bin' = 'old'; 'b.bin' = 'old' } 9
        [IO.File]::WriteAllText((Join-Path $dir 'b.bin'), 'grew just now')
        [IO.Directory]::SetLastWriteTimeUtc($dir, [DateTime]::UtcNow.AddDays(-9))
        Assert-That ((Get-InboxFolderAgeSeconds $dir) -gt (8 * 86400)) 'setup: the folder time did not stay old'
        # A fresh file nested in an old subfolder counts too.
        $deep = New-Folder $spool 'pk-deep' @{ 'a.bin' = 'old' } 9
        $sub = Join-Path $deep 'sub'
        $null = [IO.Directory]::CreateDirectory($sub)
        [IO.File]::WriteAllText((Join-Path $sub 'c.bin'), 'fresh')
        [IO.Directory]::SetLastWriteTimeUtc($sub, [DateTime]::UtcNow.AddDays(-9)); [IO.Directory]::SetCreationTimeUtc($sub, [DateTime]::UtcNow.AddDays(-9))
        [IO.Directory]::SetLastWriteTimeUtc($deep, [DateTime]::UtcNow.AddDays(-9)); [IO.Directory]::SetCreationTimeUtc($deep, [DateTime]::UtcNow.AddDays(-9))
        $r = Remove-InboxIncompletePackets -Root $spool
        Assert-That (@($r.removed).Count -eq 0) "a folder with a fresh file was removed: $(@($r.removed | ForEach-Object { $_.packetId }) -join ',')"
        Assert-That ((Test-Folder $spool 'pk-slow') -and (Test-Folder $spool 'pk-deep')) 'a folder with a fresh file is gone'
    }

    Run-Case 'age-counts-creation-time' {
        $spool = New-Spool
        # A file carried over with its source's old write time was still created here just now.
        $dir = New-Folder $spool 'pk-copied' @{ 'a.bin' = 'x' } 9
        $file = Join-Path $dir 'a.bin'
        [IO.File]::SetCreationTimeUtc($file, [DateTime]::UtcNow)
        [IO.File]::SetLastWriteTimeUtc($file, [DateTime]::UtcNow.AddDays(-9))
        $r = Remove-InboxIncompletePackets -Root $spool
        Assert-That (@($r.removed).Count -eq 0 -and (Test-Folder $spool 'pk-copied')) 'a file created just now did not keep the folder'
    }

    Run-Case 'never-touches-a-folder-with-a-manifest' {
        $spool = New-Spool
        $null = New-Folder $spool 'pk-parsable' @{ 'manifest.json' = '{"packetId":"pk-parsable"}'; 'text.md' = 'x' } 30 -Sidecar
        $null = New-Folder $spool 'pk-garbage' @{ 'manifest.json' = '{ this is not json'; 'text.md' = 'x' } 30
        $null = New-Folder $spool 'pk-empty' @{ 'manifest.json' = '' } 30
        $r = Remove-InboxIncompletePackets -Root $spool
        Assert-That (@($r.removed).Count -eq 0 -and @($r.failed).Count -eq 0) "removed: $(@($r.removed | ForEach-Object { $_.packetId }) -join ',')"
        foreach ($id in @('pk-parsable', 'pk-garbage', 'pk-empty')) { Assert-That (Test-Folder $spool $id) "$id was removed" }
        Assert-That (Test-Sidecar $spool 'pk-parsable') 'the sidecar of a kept folder was removed'
        $mixed = New-Folder $spool 'pk-late-manifest' @{ 'text.md' = 'x' } 30
        $r = Remove-InboxIncompletePackets -Root $spool
        Assert-That (@($r.removed).Count -eq 1 -and $r.removed[0].packetId -ceq 'pk-late-manifest') 'the manifest-less neighbour was not the only one removed'
    }

    Run-Case 'reads-only-new' {
        $spool = New-Spool
        foreach ($stage in @('processing', 'done', 'failed')) { $null = New-Folder $spool "pk-$stage" @{ 'text.md' = 'x' } 30 $stage }
        $stray = Join-Path (Join-Path $spool 'new') 'pk-stray.attempts.json'
        [IO.File]::WriteAllText($stray, '{}')
        $r = Remove-InboxIncompletePackets -Root $spool
        Assert-That (@($r.removed).Count -eq 0 -and @($r.failed).Count -eq 0) 'something outside new/ was reported'
        foreach ($stage in @('processing', 'done', 'failed')) { Assert-That (Test-Folder $spool "pk-$stage" $stage) "pk-$stage was removed from $stage/" }
        Assert-That ([IO.File]::Exists($stray)) 'a stray file in new/ was removed'
    }

    Run-Case 'reports-a-folder-it-cannot-remove' {
        $spool = New-Spool
        $dir = New-Folder $spool 'pk-locked' @{ 'a.bin' = 'held open' } 9 -Sidecar
        $null = New-Folder $spool 'pk-free' @{ 'a.bin' = 'x' } 9
        $lock = [IO.File]::Open((Join-Path $dir 'a.bin'), 'Open', 'Read', 'None')
        try { $r = Remove-InboxIncompletePackets -Root $spool }   # an escaping exception fails the case
        finally { $lock.Dispose() }
        Assert-That (@($r.failed).Count -eq 1 -and $r.failed[0].packetId -ceq 'pk-locked' -and $r.failed[0].message) "failed: $(@($r.failed | ForEach-Object { $_.packetId }) -join ',')"
        Assert-That (@($r.removed).Count -eq 1 -and $r.removed[0].packetId -ceq 'pk-free') 'the free neighbour was not removed past the failure'
        Assert-That ((Test-Folder $spool 'pk-locked') -and (Test-Sidecar $spool 'pk-locked')) 'the folder that could not be removed lost its sidecar or was half-reported as removed'
    }

    Run-Case 'survives-a-missing-spool' {
        $r = Remove-InboxIncompletePackets -Root (Join-Path $scratch 'no-such-root')
        Assert-That (@($r.removed).Count -eq 0 -and @($r.failed).Count -eq 0) 'a missing root produced a record'
        $empty = Join-Path $scratch 'empty-root'
        $null = [IO.Directory]::CreateDirectory($empty)
        $r = Remove-InboxIncompletePackets -Root $empty
        Assert-That (@($r.removed).Count -eq 0 -and @($r.failed).Count -eq 0) 'a root with no new/ produced a record'
    }

    Run-Case 'the-watcher-pass-removes-and-keeps' {
        $spool = New-Spool
        $null = New-Folder $spool 'pk-abandoned' @{ 'text.md' = 'never finished' } 8 -Sidecar
        $null = New-Folder $spool 'pk-arriving' @{ 'text.md' = 'still arriving' } 1
        $env:SZA_INBOX_ROOT = $spool
        try { $out = @(& $pwshExe -NoProfile -File $watchScript -Once -InboxRoot $spool 2>&1); $code = $LASTEXITCODE }
        finally { $env:SZA_INBOX_ROOT = $savedInboxRoot }
        $text = ($out | ForEach-Object { "$_" }) -join "`n"
        Assert-That ($code -eq 0) "watch-inbox -Once exited $code`: $text"
        Assert-That ($text -match 'removed incomplete packet pk-abandoned - no manifest\.json and idle for 8d') "no removal line: $text"
        Assert-That (-not (Test-Folder $spool 'pk-abandoned') -and -not (Test-Sidecar $spool 'pk-abandoned')) 'the abandoned folder or its sidecar is still there'
        Assert-That (Test-Folder $spool 'pk-arriving') 'the folder still arriving was removed'
    }

    Write-Host 'the packet check'

    Run-Case 'a-locked-payload-is-a-retry-not-a-throw' {
        $spool = New-Spool
        $id = 'pk-locked'
        $null = New-ValidPacket $spool $id
        $claim = Claim-InboxPacket -Root $spool -PacketId $id
        Assert-That $claim.ok "claim failed: $($claim.error)"
        $lock = [IO.File]::Open((Join-Path $claim.path 'text.md'), 'Open', 'Read', 'None')
        try {
            $r = Invoke-InboxIngestPacket -Root $spool -PacketPath $claim.path -SpecDraft $specDraft   # a throw fails the case
        }
        finally { $lock.Dispose() }
        # The lock also blocks the move back to new/: the retry path's own answer, the packet kept in processing/.
        Assert-That ($r.outcome -ceq 'pending' -and $r.reason -ceq 'MoveFailed') "outcome $($r.outcome) / $($r.reason)"
        Assert-That ($r.detail -match 'packet check failed \(IOException\)') "the cause was not kept: $($r.detail)"
        Assert-That ((Test-Folder $spool $id 'processing') -and -not (Test-Folder $spool $id)) 'the packet left processing/ or reached new/ despite the lock'
        $held = Read-InboxClaim -Root $spool -PacketId $id
        Assert-That ($null -ne $held -and [int]$held.pid -eq 0) 'the claim still names this process: a resident watcher would keep it live for good'
        Assert-That ((Test-InboxClaimLiveness -Claim $held) -ceq 'live') 'a claim released just now must still be live inside the stale window'
        $recovered = Invoke-InboxRecovery -Root $spool
        Assert-That (@($recovered.requeued).Count -eq 0) 'recovery re-queued a claim inside its window'
        # The window spent and the lock gone: recovery brings it back to new/ with the attempt counted.
        $held.updatedAtEpochMs = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() - 46 * 60 * 1000
        Write-InboxClaimFile -Path (Get-InboxClaimPath -StageDir (Join-Path $spool 'processing') -PacketId $id) -Claim $held
        $recovered = Invoke-InboxRecovery -Root $spool
        Assert-That (@($recovered.requeued) -contains $id) "recovery did not re-queue: left=$(@($recovered.left) -join ';')"
        $back = @(Get-InboxNewPackets -Root $spool | Where-Object { $_.packetId -ceq $id })
        Assert-That ($back.Count -eq 1 -and $back[0].attempts -eq 1 -and $back[0].lastError -match 'packet check failed') "back in new/ with attempts $($back[0].attempts)"
    }

    Run-Case 'an-unreadable-payload-is-requeued' {
        $spool = New-Spool
        $id = 'pk-unreadable'
        $null = New-ValidPacket $spool $id
        $claim = Claim-InboxPacket -Root $spool -PacketId $id
        Assert-That $claim.ok "claim failed: $($claim.error)"
        $file = Join-Path $claim.path 'text.md'
        $who = "$env:USERDOMAIN\$env:USERNAME"
        $null = & icacls $file /deny "${who}:(R)" 2>&1
        try {
            $r = Invoke-InboxIngestPacket -Root $spool -PacketPath $claim.path -SpecDraft $specDraft
        }
        finally { $null = & icacls (Join-Path (Join-Path $spool 'new') "$id\text.md") /remove:d $who 2>&1; $null = & icacls $file /remove:d $who 2>&1 }
        Assert-That ($r.outcome -ceq 'requeued' -and $r.attempts -eq 1) "outcome $($r.outcome) attempts $($r.attempts) detail $($r.detail)"
        Assert-That ((Test-Folder $spool $id) -and -not (Test-Folder $spool $id 'processing')) 'the packet is not back in new/'
        $sidecar = Read-InboxAttempts -Path (Get-InboxAttemptsPath -StageDir (Join-Path $spool 'new') -PacketId $id)
        Assert-That ($null -ne $sidecar -and [int]$sidecar.attempts -eq 1 -and [string]$sidecar.lastError -match 'packet check failed \(UnauthorizedAccessException\)') "the sidecar: $($sidecar | ConvertTo-Json -Compress)"
        Assert-That ($sidecar.nextRetryAtEpochMs -gt [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) 'no backoff was set'
        Assert-That (-not [IO.File]::Exists((Get-InboxClaimPath -StageDir (Join-Path $spool 'processing') -PacketId $id))) 'the claim sidecar is still in processing/'
    }
}
finally {
    $env:SZA_PORTFOLIO_ROOT = $savedPortfolioRoot
    $env:SZA_INBOX_ROOT = $savedInboxRoot
    if ($KeepScratch) { Write-Host "scratch kept: $scratch" }
    else { try { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction Stop } catch { Write-Host "scratch not removed: $scratch ($($_.Exception.Message))" } }
}

Write-Host ''
Write-Host "RESULT  run=$run  passed=$passed  failed=$failed"
if ($failed -gt 0) { exit 1 }
exit 0
