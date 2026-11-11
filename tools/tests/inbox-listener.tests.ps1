#requires -Version 7.0
<#
.SYNOPSIS
    Cases for the S0046 inbox listener and ingest: lib/inbox-spool.ps1, lib/inbox-ingest.ps1, ingest-inbox.ps1,
    watch-inbox.ps1, and the additive 'ingest.packet' event name.

.DESCRIPTION
    Everything runs in throwaway scratch roots: the spool, the portfolio root (the registry and the event log)
    and the capture entry point are pointed at scratch before any case runs; the real inbox
    (C:\GD\SZA\ticket-inbox), the owner's registry and any project of the portfolio are never touched.

    The capture is a stub spec-draft.ps1 (SZA_SPEC_DRAFT,SZA_STUB_MODE): it prints the same machine line the real
    one prints, records its invocation to a log (project, text file, attachments, dedup query, the ticket text
    itself) and can be told to exit 1/2 (a transient refusal), exit 3 (the closed dedup hit) or exit 0 with no
    line. What the cases prove about the ingest is therefore its behaviour around the capture - targets, notes,
    cross-links, retries, refusals, the result and the events - not spec-draft's own contract (its suite owns that).

    Coverage, one case per sentence of S0046's done criteria 1-6: the spool layout, the atomic claim (a second
    claim loses), the complete-manifest gate, the re-queue of a stale claim, the resume of a finished result,
    the live claim left alone, the retry ceiling and its backoff times, the retry-ready gate of the pending
    scan, the ingest success (result.json, the parsed drafted pair, the event), the refusal matrix through the
    reader (a hash mismatch, a textless packet), the exit-3 dedup refusal, the multi-project fan-out with its
    cross-links, the unknown-project routing to canon, the idempotency (done/failed, and the provenance pre-scan
    that reuses a ticket a crash already filed), the spool-age reader behind pq status/problems, the additive
    event name (Get-PqEventNames, and a line the oldest consumer can still read: Read-PqDay returns it,
    Test-PqEnvelope reports nothing against it), and the two-instance lock of watch-inbox.ps1: a second watcher
    against a held single-instance mutex exits 3. One watcher -Once run drains a dropped packet end to end
    through the real watch-inbox.ps1 (the resident loop is above the 5 s line; its pieces are the in-process
    cases).

    The whole file is a few seconds: the child processes (the watcher runs) are started in parallel, and every
    stub capture is a 10-line script.
#>
[CmdletBinding()]
param([switch]$KeepScratch)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$SourceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$libDir = Join-Path $SourceRoot 'tools\harness\portfolio\lib'
. (Join-Path $libDir 'inbox-ingest.ps1')      # loads the spool, the packet reader, paths, events, registry
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

# ---- the scratch world: spool, portfolio root (registry + log), sandbox projects, stub capture ----
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('inbox-listener-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$null = [IO.Directory]::CreateDirectory($scratch)
$script:spoolRoot = Join-Path $scratch 'inbox'
$script:portfolio = Join-Path $scratch 'portfolio'
$projectsRoot = Join-Path $scratch 'projects'
$stubDir = Join-Path $scratch 'stub'
foreach ($d in @($script:portfolio, $projectsRoot, $stubDir, (Join-Path $script:portfolio 'log'))) {
    $null = [IO.Directory]::CreateDirectory($d)
}
$script:stubLog = Join-Path $scratch 'stub-calls.jsonl'
$script:stubCounter = Join-Path $scratch 'stub-counter.json'

$savedPortfolioRoot = $env:SZA_PORTFOLIO_ROOT
$savedInboxRoot = $env:SZA_INBOX_ROOT
$savedSpecDraft = $env:SZA_SPEC_DRAFT
$savedStubMode = $env:SZA_STUB_MODE
$env:SZA_PORTFOLIO_ROOT = $script:portfolio
$env:SZA_INBOX_ROOT = $script:spoolRoot

# Three sandbox projects, one spec file each pre-existing in PLAN/ (the pre-scan looks there).
$script:projects = [ordered]@{}
foreach ($key in @('proj-a', 'proj-b', 'chon')) {
    $dir = Join-Path $projectsRoot $key
    $null = [IO.Directory]::CreateDirectory((Join-Path $dir 'PLAN'))
    [IO.File]::WriteAllText((Join-Path $dir ('PLAN\' + "S0001_old-$key.md")), "# S0001`n`nAn old closed ticket.`n", [Text.UTF8Encoding]::new($false))
    $script:projects[$key] = $dir
}
# 'canon' as a real registered key: unknown projects route to it (owner choice 3(b)).
$canonDir = Join-Path $projectsRoot 'canon-p'
$null = [IO.Directory]::CreateDirectory((Join-Path $canonDir 'PLAN'))
$script:projects['canon'] = $canonDir
$repos = foreach ($key in @($script:projects.Keys)) {
    [ordered]@{ key = $key; path = $script:projects[$key]; enabled = $true; maxWorkers = 1; concurrent = $false; role = 'product'; permissionMode = 'bypassPermissions'; rank = 10 }
}
[IO.File]::WriteAllText((Join-Path $script:portfolio 'repos.json'),
    (ConvertTo-Json -InputObject ([ordered]@{ schemaVersion = '1.0'; repos = @($repos) }) -Depth 5), [Text.UTF8Encoding]::new($false))

# The stub capture: the real spec-draft's contract is its last line; this one prints it, records how it was
# called, and fails the way the ingest's decisions are coded against.
$stub = Join-Path $stubDir 'spec-draft.ps1'
[IO.File]::WriteAllText($stub, @'
param(
    [string]$Project, [string]$TextFile, [string]$Attach, [string]$DedupQuery,
    [string]$Slug, [string]$Complexity, [int]$Priority, [switch]$AllowClosedDuplicate
)
$ErrorActionPreference = 'Stop'
$mode = "$env:SZA_STUB_MODE"
if ($mode -ceq 'exit2') { Write-Host "stub: bad invocation for ${Project}"; exit 2 }
if ($mode -ceq 'exit3') { Write-Host 'stub: dedup: S0001 is already Verified - the defect is dealt with'; exit 3 }
if ($mode -ceq 'noline') { Write-Host "stub: captured but the machine line went missing"; exit 0 }
$text = ''
if (Test-Path -LiteralPath $TextFile) { $text = [IO.File]::ReadAllText($TextFile, [Text.Encoding]::UTF8) }
$state = @{}
if (Test-Path -LiteralPath $env:SZA_STUB_COUNTER) { $state = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($env:SZA_STUB_COUNTER)) -AsHashtable }
$n = 1
if ($state.ContainsKey($Project)) { $n = [int]$state[$Project] + 1 }
$state[$Project] = $n
[IO.File]::WriteAllText($env:SZA_STUB_COUNTER, (ConvertTo-Json -InputObject $state -Compress))
$attach = @()
if ($Attach) { $attach = @($Attach -split ';') }
[ordered]@{ project = $Project; textFile = $TextFile; attach = $attach; dedup = $DedupQuery; text = $text } |
    ConvertTo-Json -Depth 4 -Compress | Add-Content -LiteralPath $env:SZA_STUB_LOG
$id = 'S{0:d4}' -f $n
Write-Host "spec-draft(stub): captured ${Project}, Draft, priority 50"
Write-Host "drafted ${Project}:$id file=PLAN/${Project}_$id.md priority=50 pq=dispatchable position=1/1"
exit 0
'@, [Text.UTF8Encoding]::new($false))
$env:SZA_SPEC_DRAFT = $stub
$env:SZA_STUB_MODE = ''
$env:SZA_STUB_LOG = $script:stubLog
$env:SZA_STUB_COUNTER = $script:stubCounter

# ---- helpers ----
$script:packetSeq = 0
function New-TestManifest ([string]$PacketId, [string]$Text, $Projects) {
    if (-not $PacketId) { $script:packetSeq++; $PacketId = 'pk-' + $script:packetSeq }
    $doc = [ordered]@{
        schemaVersion      = 2
        payloadKind        = 'TICKET'
        packetId           = $PacketId
        createdAtEpochMs   = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        senderDeviceName   = 'Pixel 8 (test)'
        senderDeviceId     = 'dev-test-000'
        targetDeviceName   = 'SZA-PC (test)'
        status             = 'PENDING'
        fileNames          = @('text.md')
        totalSizeBytes     = [long]0
        ttlSeconds         = 604800
        files              = @([ordered]@{ name = 'text.md'; size = [long]0; sha256 = ('0' * 64); mimeType = 'text/markdown'; role = 'text' })
        project            = $null
        text               = $Text
    }
    if ($null -ne $Projects) { $doc['projects'] = @($Projects) }
    return $doc
}
function ConvertTo-TextFile ([string]$Text) {
    $f = Join-Path $script:spoolRoot ('text-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.txt')
    [IO.File]::WriteAllText($f, $Text, [Text.UTF8Encoding]::new($false))
    return $f
}
function Publish-TestPacket ($Manifest) {
    $newDir = Join-Path (Initialize-InboxSpool $script:spoolRoot) 'new'
    $dir = Join-Path $newDir ([string]$Manifest.packetId)
    $null = [IO.Directory]::CreateDirectory($dir)
    if (@($Manifest.files).Count -gt 0) {
        $body = "$($Manifest.text)`n"
        $file = Join-Path $dir ([string]$Manifest.files[0].name)
        [IO.File]::WriteAllText($file, $body, [Text.UTF8Encoding]::new($false))
        $bytes = [IO.File]::ReadAllBytes($file)
        $Manifest.files[0].size = [long]$bytes.Length
        $Manifest.files[0].sha256 = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
        $Manifest.totalSizeBytes = [long]$bytes.Length
    }
    $null = Write-InboxPacketManifest -Manifest $Manifest -Path (Join-Path $dir 'manifest.json')
    return $dir
}
function Get-StubCalls {
    if (-not [IO.File]::Exists($script:stubLog)) { return @() }
    $calls = @()
    foreach ($line in [IO.File]::ReadAllLines($script:stubLog)) {
        if (-not $line) { continue }
        $calls += (ConvertFrom-Json -InputObject $line -DateKind String -AsHashtable)
    }
    return $calls
}
function Get-SpoolEvents {
    $events = @()
    foreach ($f in [IO.Directory]::GetFiles((Join-Path $script:portfolio 'log'), 'events-*.imp-*.jsonl')) {
        $read = Read-PqDay -Path $f
        foreach ($e in @($read.events)) { $events += $e }
    }
    return $events
}
function Open-TestLog { return (Open-PqLog -Writer imp) }
function Read-Json([string]$Path) {
    return (ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($Path)) -DateKind String -AsHashtable)
}

Write-Host 'the spool'

Run-Case 'spool-init-layout' {
    $root = Initialize-InboxSpool $script:spoolRoot
    Assert-That ([string]$root -ceq $script:spoolRoot) 'Initialize-InboxSpool rewrote the root'
    foreach ($stage in @('new', 'processing', 'done', 'failed')) {
        Assert-That ([IO.Directory]::Exists((Join-Path $root $stage))) "the $stage/ stage folder was not created"
    }
}
Run-Case 'claim-atomic-second-loses' {
    $m = New-TestManifest '' 'Claim me exactly once.'
    $null = Publish-TestPacket $m
    $id = [string]$m.packetId
    $first = Claim-InboxPacket -Root $script:spoolRoot -PacketId $id
    Assert-That $first.ok "the first claim failed: $($first.error): $($first.message)"
    $second = Claim-InboxPacket -Root $script:spoolRoot -PacketId $id
    Assert-That (-not $second.ok -and $second.error -ceq 'ClaimLost') "the second claim did not lose cleanly: $($second.error)"
    Assert-That ([IO.Directory]::Exists((Join-Path (Join-Path $script:spoolRoot 'processing') $id))) 'the packet is not in processing/'
    Assert-That (-not [IO.Directory]::Exists((Join-Path (Join-Path $script:spoolRoot 'new') $id))) 'the packet is still in new/'
    $claim = Read-InboxClaim -Root $script:spoolRoot -PacketId $id
    Assert-That ($null -ne $claim) 'claim.json was not written'
    Assert-That ([int]$claim.pid -eq $PID -and [string]$claim.host -ceq $env:COMPUTERNAME) 'the claim does not name this process and host'
    Assert-That ($null -ne $claim.startedAtEpochMs -and $claim.startedAtEpochMs -gt 0) 'the claim has no heartbeat start'
    Assert-That ([int]$claim.attempts -eq 0) 'a fresh claim must start at attempts 0'
}
Run-Case 'claim-needs-a-complete-manifest' {
    $dir = Join-Path (Join-Path $script:spoolRoot 'new') 'pk-halfwritten'
    $null = [IO.Directory]::CreateDirectory($dir)
    [IO.File]::WriteAllText((Join-Path $dir 'text.md'), 'arriving', [Text.UTF8Encoding]::new($false))
    $listed = @(Get-InboxNewPackets -Root $script:spoolRoot)
    $mine = @($listed | Where-Object { $_.packetId -ceq 'pk-halfwritten' })
    Assert-That ($mine.Count -eq 1 -and -not $mine[0].manifestReady) 'a folder without manifest.json must be listed as not ready'
    $claim = Claim-InboxPacket -Root $script:spoolRoot -PacketId 'pk-halfwritten'
    Assert-That (-not $claim.ok -and $claim.error -ceq 'ManifestIncomplete') "the claim was refused with $($claim.error), not ManifestIncomplete"
}

Write-Host 'crash recovery'

Run-Case 'recovery-requeues-a-stale-claim' {
    $m = New-TestManifest '' 'A crashed watcher left me claimed.'
    $null = Publish-TestPacket $m
    $id = [string]$m.packetId
    $first = Claim-InboxPacket -Root $script:spoolRoot -PacketId $id
    Assert-That $first.ok "claim failed: $($first.error)"
    # The crash: a dead pid and a heartbeat older than the lease window.
    $claimPath = Get-InboxClaimPath -StageDir (Join-Path $script:spoolRoot 'processing') -PacketId $id
    $claim = Read-InboxClaim -Root $script:spoolRoot -PacketId $id
    $claim.pid = 999999
    $claim.updatedAtEpochMs = [DateTimeOffset]::UtcNow.AddHours(-2).ToUnixTimeMilliseconds()
    Write-InboxClaimFile -Path $claimPath -Claim $claim
    $recovery = Invoke-InboxRecovery -Root $script:spoolRoot -StaleMinutes 45
    Assert-That (@($recovery.requeued) -contains $id) "the stale claim was not re-queued (requeued: $($recovery.requeued -join ', '))"
    Assert-That ([IO.Directory]::Exists((Join-Path (Join-Path $script:spoolRoot 'new') $id))) 'the packet is not back in new/'
    Assert-That ([IO.File]::Exists((Join-Path (Join-Path $script:spoolRoot 'new') "$id\manifest.json"))) 'the payload did not travel back whole'
    Assert-That (-not [IO.File]::Exists($claimPath)) 'the stale claim sidecar is still there'
}
Run-Case 'recovery-resumes-a-result-that-exists' {
    $id = 'pk-crashedlate'
    $dir = Join-Path (Join-Path $script:spoolRoot 'processing') $id
    $null = [IO.Directory]::CreateDirectory($dir)
    [IO.File]::WriteAllText((Join-Path $dir 'manifest.json'), '{}', [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $dir 'result.json'), '{"packetId":"' + $id + '"}', [Text.UTF8Encoding]::new($false))
    $recovery = Invoke-InboxRecovery -Root $script:spoolRoot -StaleMinutes 45
    Assert-That (@($recovery.completed) -contains $id) "the finished packet was not completed (completed: $($recovery.completed -join ', '))"
    Assert-That ([IO.File]::Exists((Join-Path (Join-Path (Join-Path $script:spoolRoot 'done') $id) 'result.json'))) 'result.json did not reach done/'
}
Run-Case 'recovery-leaves-a-live-claim-alone' {
    $id = 'pk-liveworker'
    $dir = Join-Path (Join-Path $script:spoolRoot 'processing') $id
    $null = [IO.Directory]::CreateDirectory($dir)
    [IO.File]::WriteAllText((Join-Path $dir 'manifest.json'), '{}', [Text.UTF8Encoding]::new($false))
    $claim = [pscustomobject]@{
        packetId = $id; pid = $PID; host = $env:COMPUTERNAME
        startedAtEpochMs = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        updatedAtEpochMs = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds(); attempts = 0
    }
    Write-InboxClaimFile -Path (Get-InboxClaimPath -StageDir (Join-Path $script:spoolRoot 'processing') -PacketId $id) -Claim $claim
    $recovery = Invoke-InboxRecovery -Root $script:spoolRoot -StaleMinutes 45
    Assert-That (@($recovery.left) -contains "$id (claim live)") 'a live claim was touched'
    Assert-That ([IO.Directory]::Exists($dir)) 'the live claim was moved'
}
Run-Case 'retry-ceiling-and-backoff-times' {
    $id = 'pk-transient'
    $dir = Join-Path (Join-Path $script:spoolRoot 'processing') $id
    $null = [IO.Directory]::CreateDirectory($dir)
    [IO.File]::WriteAllText((Join-Path $dir 'manifest.json'), '{}', [Text.UTF8Encoding]::new($false))
    $r1 = Requeue-InboxPacket -Root $script:spoolRoot -PacketId $id -LastError 'spec-draft exited 2' -RetryCeiling 2 -BackoffSeconds ([int[]]@(60, 300))
    Assert-That ($r1.outcome -ceq 'requeued' -and [int]$r1.attempts -eq 1) "the first re-queue was $($r1.outcome)/$($r1.attempts)"
    $attempts = Read-InboxAttempts -Path (Get-InboxAttemptsPath -StageDir (Join-Path $script:spoolRoot 'new') -PacketId $id)
    Assert-That ($null -ne $attempts -and [int]$attempts.attempts -eq 1) 'the attempts record was not written'
    Assert-That ($attempts.nextRetryAtEpochMs -gt [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) 'the 1-minute backoff was not applied'
    # A claim moves the folder (and its attempts record) back into processing/; two more transient failures:
    [IO.Directory]::Move((Join-Path (Join-Path $script:spoolRoot 'new') $id), (Join-Path (Join-Path $script:spoolRoot 'processing') $id))
    [IO.File]::Move((Get-InboxAttemptsPath -StageDir (Join-Path $script:spoolRoot 'new') -PacketId $id),
        (Get-InboxAttemptsPath -StageDir (Join-Path $script:spoolRoot 'processing') -PacketId $id))
    $r2 = Requeue-InboxPacket -Root $script:spoolRoot -PacketId $id -LastError 'again' -RetryCeiling 2 -BackoffSeconds ([int[]]@(60, 300)) 2>$null
    Assert-That ($r2.outcome -ceq 'requeued' -and [int]$r2.attempts -eq 2) "the second re-queue was $($r2.outcome)/$($r2.attempts)"
    [IO.Directory]::Move((Join-Path (Join-Path $script:spoolRoot 'new') $id), (Join-Path (Join-Path $script:spoolRoot 'processing') $id))
    [IO.File]::Move((Get-InboxAttemptsPath -StageDir (Join-Path $script:spoolRoot 'new') -PacketId $id),
        (Get-InboxAttemptsPath -StageDir (Join-Path $script:spoolRoot 'processing') -PacketId $id))
    $r3 = Requeue-InboxPacket -Root $script:spoolRoot -PacketId $id -LastError 'third' -RetryCeiling 2 -BackoffSeconds ([int[]]@(60, 300)) 2>$null
    Assert-That ($r3.outcome -ceq 'ceiling' -and [int]$r3.attempts -eq 3) "the ceiling was not judged (outcome $($r3.outcome), attempts $($r3.attempts))"
    Assert-That ([IO.Directory]::Exists((Join-Path (Join-Path $script:spoolRoot 'processing') $id))) 'the ceiling must leave the packet in processing/ for the caller to fail it'
    Assert-That (-not [IO.Directory]::Exists((Join-Path (Join-Path $script:spoolRoot 'new') $id))) 'the ceiling must not re-queue'
}
Run-Case 'pending-scan-respects-the-retry-wait' {
    $m = New-TestManifest 'pk-waiting' 'I must wait for my backoff.'
    $null = Publish-TestPacket $m
    Write-InboxAttempts -Path (Get-InboxAttemptsPath -StageDir (Join-Path $script:spoolRoot 'new') -PacketId 'pk-waiting') `
        -Attempts ([pscustomobject]@{ attempts = 1; nextRetryAtEpochMs = [DateTimeOffset]::UtcNow.AddMinutes(5).ToUnixTimeMilliseconds(); lastError = 'spec-draft exited 2' })
    $listed = @(Get-InboxNewPackets -Root $script:spoolRoot | Where-Object { $_.packetId -ceq 'pk-waiting' })
    Assert-That ($listed.Count -eq 1) 'the packet was not listed'
    Assert-That (-not $listed[0].retryReady) 'a packet inside its backoff window was listed retry-ready'
    Assert-That ([int]$listed[0].attempts -eq 1) 'the attempts count was not read back'
}

Write-Host 'the ingest'

Run-Case 'ingest-files-one-ticket-and-writes-the-result' {
    $m = New-TestManifest '' @'
Add a picture-in-picture button to the player.

The button must be reachable one-handed.
'@
    $m.project = 'proj-a'
    $null = Publish-TestPacket $m
    $id = [string]$m.packetId
    $log = Open-TestLog
    $claim = Claim-InboxPacket -Root $script:spoolRoot -PacketId $id
    try {
        $r = Invoke-InboxIngestPacket -Root $script:spoolRoot -PacketPath $claim.path -Log $log
        Assert-That ($r.outcome -ceq 'processed') "the ingest outcome was $($r.outcome): $($r.reason) $($r.detail)"
        Assert-That (@($r.tickets) -contains 'proj-a:S0001') 'the drafted pair was not parsed: ' + (@($r.tickets) -join ',')
        $resultPath = Join-Path (Join-Path (Join-Path $script:spoolRoot 'done') $id) 'result.json'
        Assert-That ([IO.File]::Exists($resultPath)) 'result.json is not beside the manifest in done/'
        $result = Read-Json $resultPath
        Assert-That ([string]$result['packetId'] -ceq $id) 'result.json lost the packet id'
        Assert-That (@($result['tickets'])[0] -ceq 'proj-a:S0001') 'result.json lost the ticket pair'
        Assert-That ([string]$result['verdict'] -ceq 'dispatchable') 'result.json lost the pq verdict'
        Assert-That ([string]$result['at'] -cmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$') 'result.json has no RFC 3339 UTC at'
        $calls = @(Get-StubCalls)
        $mine = @($calls | Where-Object { $_.dedup -cmatch [regex]::Escape($id) })
        Assert-That ($mine.Count -eq 1) 'the capture was not called exactly once with the packet dedup query'
        Assert-That ([string]$mine[0].project -ceq 'proj-a') 'the capture was not pointed at the named project'
        Assert-That ("$($mine[0].text)".IndexOf('Add a picture-in-picture button') -ge 0) 'the owner words did not reach the capture verbatim'
        Assert-That ("$($mine[0].text)".IndexOf("Filed from phone packet $id") -ge 0) 'the provenance marker did not reach the ticket (the re-run guard would miss it)'
        $events = @(Get-SpoolEvents | Where-Object { $_.ev -ceq 'ingest.packet' -and $_.d.packetId -ceq $id })
        $processed = @($events | Where-Object { $_.d.outcome -ceq 'processed' })
        Assert-That ($processed.Count -eq 1) "the processed event is missing (events: $($events.Count))"
        Assert-That (@($processed[0].d.tickets) -contains 'proj-a:S0001') 'the event lost the ticket pair'
        Assert-That ([string]$processed[0].d.project -ceq 'proj-a') 'the event lost the project'
    }
    finally { $null = Close-PqLog -Log $log }
}
Run-Case 'ingest-refuses-a-hash-mismatch-without-capturing' {
    $m = New-TestManifest '' 'Ooops.'
    $null = Publish-TestPacket $m
    $id = [string]$m.packetId
    $payload = Join-Path $script:spoolRoot "new\$id\text.md"
    $bytes = [IO.File]::ReadAllBytes($payload)
    $bytes[0] = if ($bytes[0] -eq 65) { [byte]66 } else { [byte]65 }
    [IO.File]::WriteAllBytes($payload, $bytes)
    $log = Open-TestLog
    $claim = Claim-InboxPacket -Root $script:spoolRoot -PacketId $id
    try {
        $r = Invoke-InboxIngestPacket -Root $script:spoolRoot -PacketPath $claim.path -Log $log
        Assert-That ($r.outcome -ceq 'failed' -and $r.reason -ceq 'FileHashMismatch') "a corrupt payload was $($r.outcome)/$($r.reason)"
        $reasonPath = Join-Path (Join-Path (Join-Path $script:spoolRoot 'failed') $id) 'reason.json'
        Assert-That ([IO.File]::Exists($reasonPath)) 'reason.json is not beside the manifest in failed/'
        $reason = Read-Json $reasonPath
        Assert-That ([string]$reason['error'] -ceq 'FileHashMismatch') 'reason.json lost the reason name'
        Assert-That (@(Get-StubCalls | Where-Object { $_.dedup -cmatch [regex]::Escape($id) }).Count -eq 0) 'a refused packet reached the capture'
        $refused = @(Get-SpoolEvents | Where-Object { $_.ev -ceq 'ingest.packet' -and $_.d.packetId -ceq $id -and $_.d.outcome -ceq 'refused' })
        Assert-That ($refused.Count -eq 1) 'the refused event is missing'
        Assert-That ([string]$refused[0].d.reason -ceq 'FileHashMismatch') 'the refused event lost the reason'
    }
    finally { $null = Close-PqLog -Log $log }
}
Run-Case 'ingest-refuses-a-textless-packet' {
    $m = [ordered]@{
        schemaVersion      = 2
        payloadKind        = 'TICKET'
        packetId           = 'pk-voice-only'
        createdAtEpochMs   = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        senderDeviceName   = 'Pixel 8 (test)'
        fileNames          = @('voice.m4a')
        totalSizeBytes     = [long]0
        ttlSeconds         = 604800
        files              = @()
        project            = $null
    }
    $dir = Join-Path (Join-Path $script:spoolRoot 'new') 'pk-voice-only'
    $null = [IO.Directory]::CreateDirectory($dir)
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes('fake aac bytes')
    [IO.File]::WriteAllBytes((Join-Path $dir 'voice.m4a'), $bytes)
    $m.files = @([ordered]@{ name = 'voice.m4a'; size = [long]$bytes.Length; sha256 = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant(); mimeType = 'audio/mp4'; role = 'voice' })
    $m.totalSizeBytes = [long]$bytes.Length
    $null = Write-InboxPacketManifest -Manifest $m -Path (Join-Path $dir 'manifest.json')
    $log = Open-TestLog
    $claim = Claim-InboxPacket -Root $script:spoolRoot -PacketId 'pk-voice-only'
    try {
        $r = Invoke-InboxIngestPacket -Root $script:spoolRoot -PacketPath $claim.path -Log $log
        Assert-That ($r.outcome -ceq 'failed' -and $r.reason -ceq 'TextInvalid') "a textless packet was $($r.outcome)/$($r.reason)"
        $reason = Read-Json (Join-Path (Join-Path (Join-Path $script:spoolRoot 'failed') 'pk-voice-only') 'reason.json')
        Assert-That ([string]$reason['error'] -ceq 'TextInvalid') 'reason.json is not the reader reason name TextInvalid'
    }
    finally { $null = Close-PqLog -Log $log }
}
Run-Case 'ingest-dedup-hit-refuses-the-packet' {
    $env:SZA_STUB_MODE = 'exit3'
    $m = New-TestManifest '' 'The same crash again.'
    $m.project = 'proj-a'
    $null = Publish-TestPacket $m
    $id = [string]$m.packetId
    $log = Open-TestLog
    $claim = Claim-InboxPacket -Root $script:spoolRoot -PacketId $id
    try {
        $r = Invoke-InboxIngestPacket -Root $script:spoolRoot -PacketPath $claim.path -Log $log -RetryCeiling 1
        Assert-That ($r.outcome -ceq 'failed' -and $r.reason -ceq 'DedupHit') "the closed dedup hit was $($r.outcome)/$($r.reason)"
        Assert-That ([IO.Directory]::Exists((Join-Path (Join-Path $script:spoolRoot 'failed') $id))) 'the packet did not land in failed/'
    }
    finally {
        $env:SZA_STUB_MODE = ''
        $null = Close-PqLog -Log $log
    }
}
Run-Case 'ingest-transient-failure-requeues-to-the-ceiling' {
    $env:SZA_STUB_MODE = 'exit2'
    $m = New-TestManifest '' 'Retry me.'
    $m.project = 'proj-a'
    $null = Publish-TestPacket $m
    $id = [string]$m.packetId
    $log = Open-TestLog
    try {
        $claim = Claim-InboxPacket -Root $script:spoolRoot -PacketId $id
        $r1 = Invoke-InboxIngestPacket -Root $script:spoolRoot -PacketPath $claim.path -Log $log -RetryCeiling 1 -BackoffSeconds ([int[]]@(0, 60))
        Assert-That ($r1.outcome -ceq 'requeued' -and [int]$r1.attempts -eq 1) "the first transient failure was $($r1.outcome)/$($r1.attempts)"
        $claim2 = Claim-InboxPacket -Root $script:spoolRoot -PacketId $id -Attempts 1
        Assert-That $claim2.ok 'the re-queued packet was not claimable again'
        $r2 = Invoke-InboxIngestPacket -Root $script:spoolRoot -PacketPath $claim2.path -Log $log -RetryCeiling 1 -BackoffSeconds ([int[]]@(0, 60))
        Assert-That ($r2.outcome -ceq 'failed' -and $r2.reason -ceq 'RetryCeiling') "the ceiling was $($r2.outcome)/$($r2.reason)"
        $reason = Read-Json (Join-Path (Join-Path (Join-Path $script:spoolRoot 'failed') $id) 'reason.json')
        Assert-That ([string]$reason['error'] -ceq 'RetryCeiling') 'reason.json is not RetryCeiling'
    }
    finally {
        $env:SZA_STUB_MODE = ''
        $null = Close-PqLog -Log $log
    }
}
Run-Case 'ingest-multi-project-cross-links' {
    $m = New-TestManifest '' 'Do the same fix in both apps.'
    $m.projects = @('proj-a', 'proj-b')
    $null = Publish-TestPacket $m
    $id = [string]$m.packetId
    $log = Open-TestLog
    $claim = Claim-InboxPacket -Root $script:spoolRoot -PacketId $id
    try {
        $r = Invoke-InboxIngestPacket -Root $script:spoolRoot -PacketPath $claim.path -Log $log
        Assert-That ($r.outcome -ceq 'processed') "the multi-project ingest was $($r.outcome): $($r.reason) $($r.detail)"
        $pairs = @($r.tickets)
        Assert-That ($pairs.Count -eq 2 -and $pairs[0] -cmatch '^proj-a:S\d{4,}$' -and $pairs[1] -cmatch '^proj-b:S\d{4,}$') "both pairs were not filed: $($pairs -join ',')"
        $calls = @(Get-StubCalls | Where-Object { $_.dedup -cmatch [regex]::Escape($id) })
        Assert-That ($calls.Count -eq 2 -and [string]$calls[0].project -ceq 'proj-a' -and [string]$calls[1].project -ceq 'proj-b') 'the fan-out order or count is wrong'
        Assert-That ("$($calls[1].text)".IndexOf("Filed together with the same packet as $($pairs[0])") -ge 0) "the second ticket was not cross-linked with the first"
        Assert-That ("$($calls[0].text)".IndexOf('Filed together') -lt 0) 'the first ticket must not link forward'
        $events = @(Get-SpoolEvents | Where-Object { $_.ev -ceq 'ingest.packet' -and $_.d.packetId -ceq $id -and $_.d.outcome -ceq 'processed' })
        Assert-That ($events.Count -eq 1 -and [string]$events[0].d.project -ceq 'proj-a,proj-b') 'the event lost the project list'
    }
    finally { $null = Close-PqLog -Log $log }
}
Run-Case 'ingest-unknown-project-files-in-canon-with-the-key-quoted' {
    $m = New-TestManifest '' 'A ticket for the mystery app.'
    $m.project = 'ghost-app'
    $null = Publish-TestPacket $m
    $id = [string]$m.packetId
    $log = Open-TestLog
    $claim = Claim-InboxPacket -Root $script:spoolRoot -PacketId $id
    try {
        $r = Invoke-InboxIngestPacket -Root $script:spoolRoot -PacketPath $claim.path -Log $log
        Assert-That ($r.outcome -ceq 'processed') "the unknown-project ingest was $($r.outcome): $($r.reason) $($r.detail)"
        Assert-That (@($r.tickets) -ccontains 'canon:S0001') 'the ticket was not filed in canon'
        $call = @(Get-StubCalls | Where-Object { $_.dedup -cmatch [regex]::Escape($id) })
        Assert-That ($call.Count -eq 1 -and [string]$call[0].project -ceq 'canon') 'the capture was not pointed at canon'
        Assert-That ("$($call[0].text)".IndexOf("project 'ghost-app'") -ge 0) 'the named key was not quoted below the owner words'
        Assert-That ("$($call[0].text)".IndexOf('A ticket for the mystery app.') -lt ("$($call[0].text)".IndexOf('project ' + "'ghost-app'"))) 'the note landed above the owner words'
    }
    finally { $null = Close-PqLog -Log $log }
}
Run-Case 'ingest-reuses-what-a-crash-already-filed' {
    $m = New-TestManifest '' 'Filed once, crashed, requeued.'
    $m.project = 'proj-a'
    $null = Publish-TestPacket $m
    $id = [string]$m.packetId
    # What a crash between the capture and the result write leaves: a spec with the provenance marker.
    $plan = Join-Path $script:projects['proj-a'] 'PLAN'
    [IO.File]::WriteAllText((Join-Path $plan 'S0007_crashed.md'),
        "# S0007`n`n----`nFiled from phone packet $id by the PC inbox watcher (S0046).`n", [Text.UTF8Encoding]::new($false))
    $before = @(Get-StubCalls).Count
    $log = Open-TestLog
    $claim = Claim-InboxPacket -Root $script:spoolRoot -PacketId $id
    try {
        $r = Invoke-InboxIngestPacket -Root $script:spoolRoot -PacketPath $claim.path -Log $log
        Assert-That ($r.outcome -ceq 'processed') "the re-ingest was $($r.outcome): $($r.reason) $($r.detail)"
        Assert-That (@($r.tickets) -ccontains 'proj-a:S0007') 'the already-filed ticket was not reused'
        Assert-That (@(Get-StubCalls).Count -eq $before) 'the pre-scan missed and the capture filed a duplicate'
    }
    finally { $null = Close-PqLog -Log $log }
}
Run-Case 'ingest-refuses-to-cross-the-idempotency-line' {
    $id = 'pk-twice'
    $null = [IO.Directory]::CreateDirectory((Join-Path (Join-Path $script:spoolRoot 'done') $id))
    $dir = Join-Path (Join-Path $script:spoolRoot 'processing') $id
    $null = [IO.Directory]::CreateDirectory($dir)
    [IO.File]::WriteAllText((Join-Path $dir 'manifest.json'), '{}', [Text.UTF8Encoding]::new($false))
    $before = @(Get-StubCalls).Count
    $r = Invoke-InboxIngestPacket -Root $script:spoolRoot -PacketPath $dir
    Assert-That ($r.outcome -ceq 'already') "a processed packet was re-ingested: $($r.outcome)"
    Assert-That (@(Get-StubCalls).Count -eq $before) 'already/ still captured'
}

Write-Host 'the event name'

Run-Case 'event-name-added-additively' {
    $names = @(Get-PqEventNames)
    Assert-That ($names -ccontains 'ingest.packet') 'ingest.packet is not in the catalog names'
    Assert-That (@(Get-PqEventNames | Where-Object { $_ -cmatch '^ingest\.' }).Count -eq 5) 'the ingest family is not the five names (S0047 added ingest.drain)'
    $log = Open-TestLog
    try {
        $null = Write-PqEvent -Log $log -Ev 'ingest.packet' -D ([ordered]@{ packetId = 'pk-oldest'; outcome = 'processed' })
        $line = @(Get-SpoolEvents | Where-Object { $_.ev -ceq 'ingest.packet' -and $_.d.packetId -ceq 'pk-oldest' })
        Assert-That ($line.Count -eq 1) 'the written event did not read back'
        $envelope = Test-PqEnvelope -Line ($line[0] | ConvertTo-Json -Depth 8 -Compress)
        Assert-That (@($envelope).Count -eq 0) "an old reader's envelope validator flags the event: $(@($envelope) -join ',')"
    }
    finally { $null = Close-PqLog -Log $log }
}

Write-Host 'the surfaces'

Run-Case 'spool-age-reader' {
    $age = Get-InboxSpoolAge -Root (Join-Path $scratch 'inbox-absent')
    Assert-That (-not $age.present) 'a missing root must read as not present'
    $age = Get-InboxSpoolAge -Root $script:spoolRoot -ThresholdSeconds 900
    $waiting = [int]$age.waiting; $processing = [int]$age.processing
    Assert-That (($waiting -gt 0 -or $processing -gt 0)) 'no unprocessed packets were counted (fixtures missing)'
    Assert-That ($age.packets.Count -eq ($waiting + $processing)) 'the packet list does not match the counts'
    $stale = Get-InboxSpoolAge -Root $script:spoolRoot -ThresholdSeconds -1
    Assert-That ([int]$stale.stale -eq $stale.packets.Count) 'a -1 threshold must mark every packet stale (a folder writes its own age)'
    Assert-That ($null -ne $stale.oldestPacketId -and $stale.oldestAge) 'the oldest packet was not named'
}

Write-Host 'the watcher'

# The two child runs overlap: the drain watcher starts first (it takes the single-instance lock itself),
# then - once its claim sidecar proves it holds the mutex - a second watcher must refuse with exit 3. Both
# children are alive with the same latency one alone would have needed.
$drainId = 'pk-drain-me'
$exitRefused = $null
$exitDrain = $null
$script:run++
Write-Host -NoNewline 'CASE  watcher (single-instance lock + one -Once drain) ... '
# The lock is per inbox root (a scratch root is not the real inbox), so the REAL resident watcher of
# C:\GD\SZA\ticket-inbox never interferes with this case. First half: against a mutex THIS process holds, a
# watcher of the same root must refuse (exit 3). Second half: released, it drains one real packet end to end.
$m = New-TestManifest $drainId 'A live packet for the one-shot watcher.'
$m.project = 'proj-b'
$null = Publish-TestPacket $m
$exitRefused = $null
$exitDrain = $null
$instanceLock = [Threading.Mutex]::new($true, (Get-InboxWatcherLockName -Root $script:spoolRoot))
try {
    $pRefused = [Diagnostics.Process]::Start([Diagnostics.ProcessStartInfo]::new($pwshExe, "-NoProfile -File `"$watchScript`" -Once"))
    if (-not $pRefused.WaitForExit(30000)) { try { $pRefused.Kill($true) } catch { } }
    $exitRefused = $pRefused.ExitCode
}
finally {
    $null = $instanceLock.Dispose()
}
$pDrain = [Diagnostics.Process]::Start([Diagnostics.ProcessStartInfo]::new($pwshExe, "-NoProfile -File `"$watchScript`" -Once"))
if (-not $pDrain.WaitForExit(60000)) { try { $pDrain.Kill($true) } catch { } }
$exitDrain = $pDrain.ExitCode
$ok = $true
$why = @()
if ($exitRefused -ne 3) { $ok = $false; $why += "the second watcher exited $exitRefused, expected 3" }
if ($exitDrain -ne 0) { $ok = $false; $why += "the drain watcher exited $exitDrain, expected 0" }
if ($ok) { $script:passed++; Write-Host 'PASS' -ForegroundColor Green }
else {
    $script:failed++; Write-Host 'FAIL' -ForegroundColor Red
    Write-Host "      $($why -join '; ')" -ForegroundColor DarkRed
}

Run-Case 'watcher-once-moved-the-packet-to-done' {
    $done = Join-Path (Join-Path $script:spoolRoot 'done') $drainId
    Assert-That ([IO.Directory]::Exists($done)) 'the drained packet is not in done/'
    Assert-That ([IO.File]::Exists((Join-Path $done 'result.json'))) 'result.json was not written by the watcher'
    $result = Read-Json (Join-Path $done 'result.json')
    Assert-That ("$(@($result['tickets'])[0])" -cmatch '^proj-b:S\d{4,}$') "the watcher result lost the ticket pair: $(@($result['tickets']) -join ',')"
    $events = @(Get-SpoolEvents | Where-Object { $_.ev -ceq 'ingest.packet' -and $_.d.packetId -ceq $drainId } | ForEach-Object { $_.d.outcome })
    Assert-That ($events -ccontains 'accepted' -and $events -ccontains 'processed') "the watcher event pair accepted+processed is missing (got: $($events -join ','))"
    Assert-That (-not [IO.Directory]::Exists((Join-Path (Join-Path $script:spoolRoot 'processing') $drainId))) 'the packet is still in processing/'
}

if (-not $KeepScratch) { try { Remove-Item -Recurse -Force $scratch } catch { } }
if ($null -ne $savedPortfolioRoot) { $env:SZA_PORTFOLIO_ROOT = $savedPortfolioRoot } else { Remove-Item Env:SZA_PORTFOLIO_ROOT -ErrorAction SilentlyContinue }
if ($null -ne $savedInboxRoot) { $env:SZA_INBOX_ROOT = $savedInboxRoot } else { Remove-Item Env:SZA_INBOX_ROOT -ErrorAction SilentlyContinue }
if ($null -ne $savedSpecDraft) { $env:SZA_SPEC_DRAFT = $savedSpecDraft } else { Remove-Item Env:SZA_SPEC_DRAFT -ErrorAction SilentlyContinue }
if ($null -ne $savedStubMode) { $env:SZA_STUB_MODE = $savedStubMode } else { Remove-Item Env:SZA_STUB_MODE -ErrorAction SilentlyContinue }

Write-Host ''
Write-Host "pass $passed of $run, failed $failed"
exit ([int]($failed -gt 0))
