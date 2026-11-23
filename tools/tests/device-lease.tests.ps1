#requires -Version 7.0
<#
.SYNOPSIS
    Cases for the machine-wide device lease (canon TESTING_AND_QA section 4, skill device-lease):
    tools/harness/devices/_device-lease.ps1 and its CLI device-lease.ps1.
.DESCRIPTION
    Everything runs against a scratch folder under the system temp directory: the portfolio root, the user profile (so no
    real transcript is read), two scratch projects. No adb, no device, no git, no agent. Sessions are told apart by the
    SZA_AGENT_ID variable the harness identity chain reads first. Cases: 1 a claim writes one lease outside the project, with
    its session and project; 2 a re-claim by the owner is "already mine" and keeps the claim time; 3 a second session of
    another project loses the claim, is told who holds it and the holder is untouched; 4 release is owner-checked, an absent
    lease is not an error; 5 -Any takes the first free key and exits 3 when every one is held; 6 several keys are all or
    nothing; 7 a quiet owner and an abandoned lease are swept, a live foreign one is not; 8 -All gives back this session's
    leases and no other; 9 a key that is not a plain name is refused and nothing is written; 10 a portfolio root inside a
    working tree is refused; 11 the CLI answers exit 3 with JSON and lists the live keys.
#>
[CmdletBinding()]
param([switch]$KeepScratch)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$harness = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\harness'))
$run = 0; $passed = 0; $failed = 0
function Assert-That([bool] $Condition, [string] $Message) { if (-not $Condition) { throw $Message } }
function Run-Case([string] $Name, [scriptblock] $Body) {
    $script:run++
    Write-Host -NoNewline "CASE  $Name ... "
    try { & $Body; $script:passed++; Write-Host 'PASS' -ForegroundColor Green }
    catch { $script:failed++; Write-Host 'FAIL' -ForegroundColor Red; Write-Host "      $($_.Exception.Message)" -ForegroundColor DarkRed }
}
$clock = [Diagnostics.Stopwatch]::StartNew()
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('device-lease-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$portfolio = Join-Path $scratch 'portfolio'
$profileDir = Join-Path $scratch 'home'
$projA = Join-Path $scratch 'proj-a'
$projB = Join-Path $scratch 'proj-b'
$transcripts = Join-Path $profileDir '.claude\projects\p'
New-Item -ItemType Directory -Path $portfolio, $projA, $projB, $transcripts | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)
$saved = @{}
foreach ($name in 'SZA_PORTFOLIO_ROOT', 'SZA_PROJECT_ROOT', 'SZA_AGENT_ID', 'USERPROFILE') { $saved[$name] = [Environment]::GetEnvironmentVariable($name) }

function Use-Session([string] $Session, [string] $Project) {
    $env:SZA_AGENT_ID = $Session
    $env:SZA_PROJECT_ROOT = $Project
}
function Get-LeaseFile([string] $Key) { return (Join-Path $portfolio ('devices\' + ($Key -replace ':', '_') + '.json')) }
function Read-LeaseFile([string] $Key) { return (Get-Content -LiteralPath (Get-LeaseFile $Key) -Raw | ConvertFrom-Json) }
# A lease some other session wrote: quiet for $QuietMinutes, claimed $ClaimedMinutesAgo ago, with a transcript or none.
function Seed-Lease([string] $Key, [string] $Session, [int] $ClaimedMinutesAgo, [int] $QuietMinutes, [bool] $WithTranscript) {
    $dir = Join-Path $portfolio 'devices'
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
    $transcript = $null
    if ($WithTranscript) {
        $transcript = Join-Path $transcripts "$Session.jsonl"
        [IO.File]::WriteAllText($transcript, "{}`n", $utf8)
        (Get-Item -LiteralPath $transcript).LastWriteTime = (Get-Date).AddMinutes(-$QuietMinutes)
    }
    $claimed = [DateTimeOffset]::UtcNow.AddMinutes(-$ClaimedMinutesAgo).ToUnixTimeMilliseconds()
    $seen = [DateTimeOffset]::UtcNow.AddMinutes(-$QuietMinutes).ToUnixTimeMilliseconds()
    $record = [ordered]@{
        schema = 1; id = $Key; sessionId = $Session; project = 'seeded'; host = 'TESTHOST'; pid = 1; reason = 'seeded'
        claimedAt = $claimed; lastSeenAt = $seen; transcriptPath = $transcript
    }
    [IO.File]::WriteAllText((Get-LeaseFile $Key), ($record | ConvertTo-Json -Compress), $utf8)
}
try {
    # The libraries resolve the project root and the identity from the environment, so it is set before they load.
    $env:SZA_PORTFOLIO_ROOT = $portfolio
    $env:USERPROFILE = $profileDir
    Use-Session 'sess-A' $projA
    . (Join-Path $harness 'devices\_device-lease.ps1')
    Assert-That ((Get-AgentSessionId) -ceq 'sess-A') 'the identity chain must answer the SZA_AGENT_ID variable first'

    Run-Case '1. a claim writes one lease outside the project, with its session and project' {
        $r = Invoke-DeviceLease -Verb Claim -Id 'emulator-5554' -Reason 'ticket one'
        Assert-That ($r.Exit -eq 0 -and $r.Outcome -ceq 'claimed') "first claim: $($r.Exit) $($r.Outcome) $($r.Text)"
        $rec = Read-LeaseFile 'emulator-5554'
        Assert-That ($rec.sessionId -ceq 'sess-A' -and $rec.project -ceq 'proj-a' -and $rec.reason -ceq 'ticket one') 'the lease must name session, project and reason'
        Assert-That ((Get-LeaseFile 'emulator-5554').StartsWith($portfolio)) 'the store must be the portfolio root'
        Assert-That (@(Get-ChildItem -LiteralPath $projA -Recurse -Force).Count -eq 0) 'nothing may be written inside the project'
        $r2 = Invoke-DeviceLease -Verb Claim -Id '192.168.1.5:5555'
        Assert-That ($r2.Exit -eq 0 -and (Test-Path -LiteralPath (Join-Path $portfolio 'devices\192.168.1.5_5555.json'))) 'a wireless serial keeps its port, the colon is written as an underscore'
    }
    Run-Case '2. a re-claim by the owner is already-mine and keeps the claim time' {
        $before = (Read-LeaseFile 'emulator-5554').claimedAt
        $r = Invoke-DeviceLease -Verb Claim -Id 'emulator-5554'
        Assert-That ($r.Exit -eq 0 -and $r.Outcome -ceq 'already-mine') "re-claim: $($r.Exit) $($r.Outcome)"
        Assert-That ((Read-LeaseFile 'emulator-5554').claimedAt -eq $before) 'the claim time must stay frozen'
    }
    Run-Case '3. a second session of another project loses the claim and is told who holds it' {
        Use-Session 'sess-B' $projB
        $r = Invoke-DeviceLease -Verb Claim -Id 'emulator-5554'
        Assert-That ($r.Exit -eq 3 -and $r.Outcome -ceq 'claim-lost') "claim of a held target: $($r.Exit) $($r.Outcome)"
        Assert-That ($r.Text -like '*proj-a*' -and $r.Text -like '*ticket one*') "the message must name the holder's project and reason: $($r.Text)"
        Assert-That ($r.Text -like '*do not wait*') 'the message must say what to do instead'
        Assert-That ($r.Data.heldBy -ceq 'sess-A' -and $r.Data.project -ceq 'proj-a') 'the data must name the holder'
        Assert-That ((Read-LeaseFile 'emulator-5554').sessionId -ceq 'sess-A') 'the holder must be untouched'
    }
    Run-Case '4. release is owner-checked; an absent lease is not an error' {
        $r = Invoke-DeviceLease -Verb Release -Id 'emulator-5554'
        Assert-That ($r.Exit -eq 4 -and $r.Outcome -ceq 'release-refused') "foreign release: $($r.Exit) $($r.Outcome)"
        Assert-That (Test-Path -LiteralPath (Get-LeaseFile 'emulator-5554')) 'the lease must survive a refused release'
        Use-Session 'sess-A' $projA
        $r = Invoke-DeviceLease -Verb Release -Id 'emulator-5554'
        Assert-That ($r.Exit -eq 0 -and $r.Outcome -ceq 'released' -and -not (Test-Path -LiteralPath (Get-LeaseFile 'emulator-5554'))) 'the owner releases'
        $r = Invoke-DeviceLease -Verb Release -Id 'emulator-5554'
        Assert-That ($r.Exit -eq 0 -and $r.Outcome -ceq 'absent') 'releasing a lease nobody holds is exit 0'
    }
    Run-Case '5. -Any takes the first free key and exits 3 when every one is held' {
        $null = Invoke-DeviceLease -Verb Claim -Id 'avd:Pixel_9'
        Use-Session 'sess-B' $projB
        $r = Invoke-DeviceLease -Verb Claim -Id 'avd:Pixel_9,avd:Pixel_6' -Any
        Assert-That ($r.Exit -eq 0 -and $r.Data.id -ceq 'avd:Pixel_6') "the free key must be taken: $($r.Exit) $($r.Text)"
        Use-Session 'sess-C' $projB
        $r = Invoke-DeviceLease -Verb Claim -Id 'avd:Pixel_9,avd:Pixel_6' -Any
        Assert-That ($r.Exit -eq 3) 'every key held must be exit 3'
        Assert-That ($r.Data.ids.Count -eq 2) 'both held keys must be reported'
    }
    Run-Case '6. several keys are all or nothing' {
        Use-Session 'sess-B' $projB
        $r = Invoke-DeviceLease -Verb Claim -Id 'watch-usb,avd:Pixel_9'
        Assert-That ($r.Exit -eq 3) 'one held key must lose the whole claim'
        Assert-That (-not (Test-Path -LiteralPath (Get-LeaseFile 'watch-usb'))) 'a key taken before the loss must be given back'
        $r = Invoke-DeviceLease -Verb Claim -Id 'watch-usb,watch-wifi'
        Assert-That ($r.Exit -eq 0 -and (Test-Path -LiteralPath (Get-LeaseFile 'watch-usb')) -and (Test-Path -LiteralPath (Get-LeaseFile 'watch-wifi'))) 'two free keys are both taken'
    }
    Run-Case '7. a quiet owner and an abandoned lease are swept, a live foreign one is not' {
        Use-Session 'sess-A' $projA
        Seed-Lease 'quiet-1' 'sess-D' 60 60 $false
        $r = Invoke-DeviceLease -Verb Claim -Id 'quiet-1'
        Assert-That ($r.Exit -eq 0 -and $r.Outcome -ceq 'claimed') "a lease quiet for an hour must be taken over: $($r.Exit) $($r.Text)"
        Seed-Lease 'old-1' 'sess-E' 150 1 $true
        $r = Invoke-DeviceLease -Verb Claim -Id 'old-1'
        Assert-That ($r.Exit -eq 0 -and $r.Outcome -ceq 'claimed') 'a lease past the ceiling must be swept even with a live transcript'
        Seed-Lease 'live-1' 'sess-F' 10 1 $true
        $r = Invoke-DeviceLease -Verb Claim -Id 'live-1'
        Assert-That ($r.Exit -eq 3) 'a live foreign lease must be respected'
        Assert-That ((Read-LeaseFile 'live-1').sessionId -ceq 'sess-F') 'a live foreign lease must not be removed'
        Seed-Lease 'quiet-2' 'sess-G' 60 60 $false
        $r = Invoke-DeviceLease -Verb Sweep
        Assert-That ($r.Exit -eq 0 -and @($r.Data.removed) -contains 'quiet-2' -and (Test-Path -LiteralPath (Get-LeaseFile 'live-1'))) 'Sweep drops the stale and keeps the live'
    }
    Run-Case '8. -All gives back this session leases and no other' {
        Use-Session 'sess-A' $projA
        $mineBefore = @((Invoke-DeviceLease -Verb Status).Data | Where-Object { $_.mine }).Count
        Assert-That ($mineBefore -ge 2) 'the session must hold several leases by now'
        $r = Invoke-DeviceLease -Verb Release -All
        Assert-That ($r.Exit -eq 0 -and $r.Outcome -ceq 'released') "release all: $($r.Exit) $($r.Outcome)"
        Assert-That (@((Invoke-DeviceLease -Verb Status).Data | Where-Object { $_.mine }).Count -eq 0) 'nothing of this session may remain'
        Assert-That ((Test-Path -LiteralPath (Get-LeaseFile 'avd:Pixel_6')) -and (Test-Path -LiteralPath (Get-LeaseFile 'live-1'))) 'the leases of other sessions must remain'
        $r = Invoke-DeviceLease -Verb Release -All
        Assert-That ($r.Exit -eq 0 -and $r.Outcome -ceq 'absent') 'nothing held is exit 0'
    }
    Run-Case '9. a key that is not a plain name is refused and nothing is written' {
        $count = @(Get-ChildItem -LiteralPath (Join-Path $portfolio 'devices') -Filter '*.json').Count
        foreach ($bad in '../x', 'a b', 'x/y', '.hidden', 'a\b') {
            $r = Invoke-DeviceLease -Verb Claim -Id $bad
            Assert-That ($r.Exit -eq 1 -and $r.Outcome -ceq 'bad-id') "'$bad' must be refused: $($r.Exit) $($r.Outcome)"
        }
        Assert-That ((Invoke-DeviceLease -Verb Claim).Exit -eq 1) 'a claim with no key is an error'
        Assert-That (@(Get-ChildItem -LiteralPath (Join-Path $portfolio 'devices') -Filter '*.json').Count -eq $count) 'a refused key must write nothing'
    }
    Run-Case '10. a portfolio root inside a working tree is refused' {
        $repo = Join-Path $scratch 'repo'
        New-Item -ItemType Directory -Path (Join-Path $repo '.git'), (Join-Path $repo 'state') | Out-Null
        $env:SZA_PORTFOLIO_ROOT = Join-Path $repo 'state'
        try {
            $threw = $false
            try { $null = Invoke-DeviceLease -Verb Claim -Id 'emulator-5554' } catch { $threw = ($_.Exception.Message -like '*PortfolioRootInsideRepository*') }
            Assert-That $threw 'the store must never enter version control'
            Assert-That (-not (Test-Path -LiteralPath (Join-Path $repo 'state\devices'))) 'nothing may be created there'
        }
        finally { $env:SZA_PORTFOLIO_ROOT = $portfolio }
    }
    Run-Case '11. the CLI answers exit 3 with JSON and lists the live keys' {
        Use-Session 'sess-B' $projB
        $cli = Join-Path $harness 'devices\device-lease.ps1'
        $json = & pwsh -NoProfile -File $cli -Verb Claim -Id 'live-1' -Json
        $code = $LASTEXITCODE
        Assert-That ($code -eq 3) "the CLI must exit 3 for a lost claim, got $code"
        $obj = ($json -join '') | ConvertFrom-Json
        Assert-That ($obj.outcome -ceq 'claim-lost' -and $obj.heldBy -ceq 'sess-F') 'the JSON must carry the outcome and the holder'
        $list = @(& pwsh -NoProfile -File $cli -Verb List)
        Assert-That ($LASTEXITCODE -eq 0 -and $list -contains 'live-1' -and $list -contains 'avd:Pixel_6') "the list must name the live keys: $($list -join ',')"
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
