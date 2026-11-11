#requires -Version 7.0
# Kill a watcher while its capture child is running, then recover its abandoned claim.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$scratch = Join-Path $root ('temp/S0046_inbox-listener-ingest/crash-' + [guid]::NewGuid().ToString('N'))
$inbox = Join-Path $scratch 'inbox'
$portfolio = Join-Path ([IO.Path]::GetTempPath()) ('sza-inbox-crash-portfolio-' + [guid]::NewGuid().ToString('N'))
$project = Join-Path $scratch 'project'
$watch = Join-Path $root 'tools/harness/portfolio/watch-inbox.ps1'
. (Join-Path $root 'tools/harness/portfolio/lib/inbox-spool.ps1')
$child = $null
try {
    foreach ($dir in @($scratch, $portfolio, (Join-Path $project 'PLAN'))) { $null = [IO.Directory]::CreateDirectory($dir) }
    $null = Initialize-InboxSpool $inbox
    $repo = @{ key = 'canon'; path = $project; enabled = $true; maxWorkers = 1; concurrent = $false; role = 'product'; permissionMode = 'bypassPermissions'; rank = 10 }
    [IO.File]::WriteAllText((Join-Path $portfolio 'repos.json'), (ConvertTo-Json -Depth 5 @{ schemaVersion = '1.0'; repos = @($repo) }))
    $packet = Join-Path $inbox 'new/pk-crash'
    $null = [IO.Directory]::CreateDirectory($packet)
    $manifest = @{ schemaVersion = 2; payloadKind = 'TICKET'; packetId = 'pk-crash'; createdAtEpochMs = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds(); senderDeviceName = 'test'; ttlSeconds = 604800; fileNames = @(); totalSizeBytes = 0; files = @(); text = 'Crash recovery test' }
    [IO.File]::WriteAllText((Join-Path $packet 'manifest.json'), (ConvertTo-Json -Depth 5 $manifest))
    $stub = Join-Path $scratch 'capture.ps1'
    [IO.File]::WriteAllText($stub, 'param($Project,$TextFile,$Attach,$DedupQuery) [IO.File]::WriteAllText($env:SZA_CRASH_SIGNAL,"started"); Start-Sleep -Seconds 30')
    $signal = Join-Path $scratch 'started'
    $psi = [Diagnostics.ProcessStartInfo]::new((Get-Process -Id $PID).Path)
    foreach ($arg in @('-NoProfile', '-File', $watch, '-Once', '-InboxRoot', $inbox, '-SpecDraft', $stub)) { $psi.ArgumentList.Add($arg) }
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.Environment['SZA_PORTFOLIO_ROOT'] = $portfolio
    $psi.Environment['SZA_CRASH_SIGNAL'] = $signal
    $child = [Diagnostics.Process]::Start($psi)
    $output = $child.StandardOutput.ReadToEndAsync()
    $errors = $child.StandardError.ReadToEndAsync()
    $deadline = [DateTime]::UtcNow.AddSeconds(3)
    while (-not [IO.File]::Exists($signal) -and -not $child.HasExited -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 20 }
    if (-not [IO.File]::Exists($signal)) {
        if ($child.HasExited) { throw "capture did not start: $($output.Result) $($errors.Result)" }
        throw 'capture did not start before the test deadline'
    }
    $child.Kill($true)
    $child.WaitForExit()
    $claim = Read-InboxClaim -Root $inbox -PacketId 'pk-crash'
    if ($null -eq $claim) { throw 'watcher died without a claim' }
    # Advance the claim's clock instead of waiting for the real 45-minute lease window.
    $claim.updatedAtEpochMs = 1
    Write-InboxClaimFile -Path (Get-InboxClaimPath -StageDir (Join-Path $inbox 'processing') -PacketId 'pk-crash') -Claim $claim
    $recovery = Invoke-InboxRecovery -Root $inbox
    if (@($recovery.requeued) -cnotcontains 'pk-crash' -or -not [IO.Directory]::Exists($packet)) { throw 'abandoned packet was not requeued' }
    Write-Host 'PASS: killed watcher during capture; stale claim requeued'
}
finally {
    if ($null -ne $child) { if (-not $child.HasExited) { $child.Kill($true); $child.WaitForExit() }; $child.Dispose() }
    if ([IO.Directory]::Exists($scratch)) { Remove-Item -LiteralPath $scratch -Recurse -Force }
    if ([IO.Directory]::Exists($portfolio)) { Remove-Item -LiteralPath $portfolio -Recurse -Force }
}
