#requires -Version 7.0
<#
.SYNOPSIS
    Cases for the dispatcher reading device leases (TASK-FLOW 0.41 section 19): Get-PqDeviceLeases and the emulator count of
    Request-PqResources in tools/harness/portfolio/lib/resources.ps1, and the Device leases of `pq status`.
.DESCRIPTION
    A scratch folder under the system temp directory holds the portfolio root and the user profile; the leases are files a
    foreign session wrote, as device-lease.ps1 writes them, and the judgement of who is alive is the real lease tool's, run as
    the dispatcher runs it (one child process, only when a lease file exists). No adb, no device, no agent. Cases: 1 no lease
    file answers at once; 2 a live emulator lease is read, a stale one and a physical target are not; 3 an emulator request
    at the cap is refused by a lease and takes nothing; 4 build and device read no lease; 5 the larger count is taken, not the
    sum, and the ticket's own re-request is never refused by its own lease; 6 a lease that cannot be read is no lease;
    7 `pq status -Json` carries deviceLeases, a physical target included.
#>
[CmdletBinding()]
param([switch]$KeepScratch)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$harness = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\harness'))
$lib = Join-Path $harness 'portfolio\lib'
$run = 0; $passed = 0; $failed = 0
function Assert-That([bool] $Condition, [string] $Message) { if (-not $Condition) { throw $Message } }
function Run-Case([string] $Name, [scriptblock] $Body) {
    $script:run++
    Write-Host -NoNewline "CASE  $Name ... "
    try { & $Body; $script:passed++; Write-Host 'PASS' -ForegroundColor Green }
    catch { $script:failed++; Write-Host 'FAIL' -ForegroundColor Red; Write-Host "      $($_.Exception.Message)" -ForegroundColor DarkRed }
}
$clock = [Diagnostics.Stopwatch]::StartNew()
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('pq-device-leases-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$portfolio = Join-Path $scratch 'portfolio'
$profileDir = Join-Path $scratch 'home'
$transcripts = Join-Path $profileDir '.claude\projects\p'
New-Item -ItemType Directory -Path $portfolio, $transcripts | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)
$saved = @{}
foreach ($name in 'SZA_PORTFOLIO_ROOT', 'USERPROFILE') { $saved[$name] = [Environment]::GetEnvironmentVariable($name) }

# A lease some other session wrote: quiet for $QuietMinutes, with a transcript (written that long ago) or none.
function Seed-Lease([string] $Key, [string] $Session, [int] $QuietMinutes, [bool] $WithTranscript, [string] $Project = 'other-project') {
    $dir = Join-Path $portfolio 'devices'
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
    $transcript = $null
    if ($WithTranscript) {
        $transcript = Join-Path $transcripts "$Session.jsonl"
        [IO.File]::WriteAllText($transcript, "{}`n", $utf8)
        (Get-Item -LiteralPath $transcript).LastWriteTime = (Get-Date).AddMinutes(-$QuietMinutes)
    }
    $then = [DateTimeOffset]::UtcNow.AddMinutes(-$QuietMinutes).ToUnixTimeMilliseconds()
    $record = [ordered]@{
        schema = 1; id = $Key; sessionId = $Session; project = $Project; host = 'TESTHOST'; pid = 1; reason = 'seeded scenario'
        claimedAt = $then; lastSeenAt = $then; transcriptPath = $transcript
    }
    [IO.File]::WriteAllText((Join-Path $dir (($Key -replace ':', '_') + '.json')), ($record | ConvertTo-Json -Compress), $utf8)
}
function Clear-Leases { $d = Join-Path $portfolio 'devices'; if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force } }
function Clear-Tokens { $d = Join-Path $portfolio 'resources'; if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force } }
try {
    $env:SZA_PORTFOLIO_ROOT = $portfolio
    $env:USERPROFILE = $profileDir
    . (Join-Path $lib 'paths.ps1')
    . (Join-Path $lib 'events.ps1')
    . (Join-Path $lib 'registry.ps1')
    . (Join-Path $lib 'ledger-watch.ps1')
    . (Join-Path $lib 'loop.ps1')
    . (Join-Path $lib 'picker.ps1')
    . (Join-Path $lib 'occupancy.ps1')
    . (Join-Path $lib 'resources.ps1')
    $reg = [ordered]@{ resources = @{ build = 3; emulator = 1 } }
    $reg2 = [ordered]@{ resources = @{ build = 3; emulator = 2 } }

    Run-Case '1. no lease file answers at once, with no leases' {
        $r = Get-PqDeviceLeases
        Assert-That ($r.ok -and @($r.leases).Count -eq 0 -and $null -eq $r.why) "no store: $($r | ConvertTo-Json -Compress)"
        $null = New-Item -ItemType Directory -Path (Join-Path $portfolio 'devices')
        $r = Get-PqDeviceLeases
        Assert-That ($r.ok -and @($r.leases).Count -eq 0) 'an empty store is no lease either'
    }
    Run-Case '2. a live emulator lease is read; a stale one and a physical target are not' {
        Seed-Lease 'avd:Pixel_9' 'sess-X' 2 $true 'streams-mob'
        Seed-Lease 'RFCR110NBQJ' 'sess-Y' 2 $true
        Seed-Lease 'avd:Old' 'sess-Z' 60 $false
        $e = Get-PqDeviceLeases -EmulatorOnly
        Assert-That ($e.ok -and @($e.leases).Count -eq 1 -and @($e.leases)[0].id -ceq 'avd:Pixel_9') "emulator only: $($e | ConvertTo-Json -Compress -Depth 4)"
        Assert-That (@($e.leases)[0].project -ceq 'streams-mob' -and @($e.leases)[0].reason -ceq 'seeded scenario') 'the record names project and reason'
        Assert-That ((Test-PqEmulatorLeaseKey 'emulator-5554') -and (Test-PqEmulatorLeaseKey 'avd:Pixel_9') -and -not (Test-PqEmulatorLeaseKey '192.168.1.5:5555') -and -not (Test-PqEmulatorLeaseKey 'Xavd:a')) 'the keys that name an emulator'
    }
    Run-Case '3. an emulator request at the cap is refused by a lease and takes nothing' {
        Clear-Leases; Clear-Tokens
        Seed-Lease 'avd:Pixel_9' 'sess-X' 2 $true 'streams-mob'
        $r = Request-PqResources -Registry $reg -RepoKey 'demo' -TicketId 'S0001' -Verify 'emulator' -PassId 'p1'
        Assert-That (-not $r.ok -and $r.why -ceq 'resource' -and $r.resource -ceq 'emulator' -and $r.heldCount -eq 1 -and $r.cap -eq 1) "refused: $($r | ConvertTo-Json -Compress -Depth 4)"
        Assert-That (@($r.leases) -contains 'avd:Pixel_9') 'the result names the lease that holds the slot'
        Assert-That (-not [IO.File]::Exists((Get-PqPath -Kind resourceToken -Token 'build' -Repo 'demo' -Id 'S0001')) -and -not [IO.File]::Exists((Get-PqPath -Kind resourceToken -Token 'emulator' -Repo 'demo' -Id 'S0001'))) 'all or nothing: neither token is taken'
    }
    Run-Case '4. build and device read no lease' {
        $b = Request-PqResources -Registry $reg -RepoKey 'demo' -TicketId 'S0003' -Verify 'build' -PassId 'p3'
        Assert-That ($b.ok -and (@($b.held) -join ',') -ceq 'build') 'build is not held back by an emulator lease'
        $d = Request-PqResources -Registry $reg -RepoKey 'demo' -TicketId 'S0004' -Verify 'device' -PassId 'p4'
        Assert-That ($d.ok -and @($d.held).Count -eq 0) 'device takes no token and reads no lease'
    }
    Run-Case '5. the larger count is taken, not the sum; the ticket own re-request is never refused by its own lease' {
        Clear-Leases; Clear-Tokens
        $first = Request-PqResources -Registry $reg2 -RepoKey 'demo' -TicketId 'S0005' -Verify 'emulator' -PassId 'p5'
        Assert-That ($first.ok) 'the first emulator ticket takes its tokens'
        Seed-Lease 'avd:Pixel_9' 'sess-X' 1 $true
        $again = Request-PqResources -Registry $reg2 -RepoKey 'demo' -TicketId 'S0005' -Verify 'emulator' -PassId 'p5'
        Assert-That ($again.ok) "the same ticket and pass asking again, with a lease standing: $($again | ConvertTo-Json -Compress -Depth 4)"
        $second = Request-PqResources -Registry $reg2 -RepoKey 'demo' -TicketId 'S0006' -Verify 'emulator' -PassId 'p6'
        Assert-That ($second.ok -and $second.counts['emulator'].held -eq 2) "one token and one lease are one emulator up, so a cap of 2 admits a second: $($second | ConvertTo-Json -Compress -Depth 4)"
    }
    Run-Case '6. a lease that cannot be read is no lease' {
        Clear-Tokens
        $slow = Get-PqDeviceLeases -TimeoutSeconds 0
        Assert-That (-not $slow.ok -and $slow.why -ceq 'timeout' -and @($slow.leases).Count -eq 0) "a silent tool: $($slow | ConvertTo-Json -Compress)"
        function Get-PqDeviceLeases { throw 'the reader failed' }
        try {
            $r = Request-PqResources -Registry $reg -RepoKey 'demo' -TicketId 'S0008' -Verify 'emulator' -PassId 'p8'
            Assert-That ($r.ok) "a reader that throws must not stop the dispatcher: $($r | ConvertTo-Json -Compress -Depth 4)"
        }
        finally { Remove-Item Function:\Get-PqDeviceLeases; . (Join-Path $lib 'resources.ps1') }
    }
    Run-Case '7. pq status -Json carries deviceLeases, a physical target included' {
        Clear-Leases
        Seed-Lease 'avd:Pixel_9' 'sess-X' 2 $true 'streams-mob'
        Seed-Lease 'RFCR110NBQJ' 'sess-Y' 2 $true
        $json = & pwsh -NoProfile -File (Join-Path $harness 'portfolio\pq.ps1') status -Json
        Assert-That ($LASTEXITCODE -eq 0) "pq status exited $LASTEXITCODE"
        $leases = @((($json -join "`n") | ConvertFrom-Json).deviceLeases)
        Assert-That ($leases.Count -eq 2 -and (@($leases | ForEach-Object { $_.id }) -contains 'RFCR110NBQJ') -and (@($leases | ForEach-Object { $_.project }) -contains 'streams-mob')) "deviceLeases: $($leases | ConvertTo-Json -Compress)"
    }
}
finally {
    foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name]) }
    if (-not $KeepScratch) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
    else { Write-Host "scratch kept: $scratch" }
}
Write-Host ("{0} cases, {1} passed, {2} failed, {3:N1} s" -f $run, $passed, $failed, $clock.Elapsed.TotalSeconds)
if ($failed -gt 0) { exit 1 }
exit 0
