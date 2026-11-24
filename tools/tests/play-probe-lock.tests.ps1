#requires -Version 7.0
<#
    Fast tests for the Play probe's per-application lock (tools/harness/releases/_play-lock.ps1 and Invoke-RlProbePlay in
    _probes.ps1; GOOGLE-PLAY 0.4 rule 19, canon ticket CANONR-0174).
     1. The lock path is <repo>/temp/play-lock/<applicationId>.lock by default and only an application id is accepted,
        because the id becomes a file name.
     2. The lock is the one the product publishers hold, in both directions: a handle opened the way they open theirs
        (OpenOrCreate, ReadWrite, FileShare.None) stops Enter-RlPlayAppLock, the probe's held lock stops such an open, and
        Exit frees it.
     3. With the lock free the probe reads the lifecycle, opens one edit, reads the track and deletes the edit, and the
        lock is free again afterwards.
     4. With the lock held, reached through Invoke-RlProbe (which must hand the repository root on), the probe still reads
        the lifecycle, opens NO edit and prints the track configuration as a gap that names the lock; with the lifecycle
        read also failing the result is not ok and its reason names the lock.
     5. The lock is freed when the track read throws, and the edit is still deleted.
     6. An id that is not an application id opens nothing and creates no lock folder.
     7. A repository profile that moves paths.tempDir moves the lock folder with it; an unreadable profile keeps the default.
    No network and no credential: Invoke-RestMethod and Get-RlGoogleAccessToken are replaced by functions of the same name
    in this script's scope, and SZA_PLAY_SERVICE_ACCOUNT_JSON names a dummy file. A throwaway folder; -KeepScratch leaves it. #>
[CmdletBinding()]
param([switch]$KeepScratch)
$ErrorActionPreference = 'Stop'
$SourceRoot = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent)
$releases = Join-Path $SourceRoot 'tools/harness/releases'
. (Join-Path $releases '_lib.ps1')
. (Join-Path $releases '_probes.ps1')

$clock = [Diagnostics.Stopwatch]::StartNew()
$run = 0; $passed = 0; $failed = 0
function Assert-That([bool]$Condition, [string]$Reason) { if (-not $Condition) { throw $Reason } }
function Test-Case([string]$Name, [scriptblock]$Body) {
    $script:run++
    Write-Host -NoNewline "CASE  $Name ... "
    try { & $Body; $script:passed++; Write-Host 'PASS' -ForegroundColor Green }
    catch { $script:failed++; Write-Host 'FAIL' -ForegroundColor Red; Write-Host "      $($_.Exception.Message)" -ForegroundColor DarkRed }
}

# --- the replaced network layer -----------------------------------------------------------------------------------------
$script:calls = [Collections.Generic.List[string]]::new()
$script:failLifecycle = $false
$script:failTrack = $false
function Get-RlGoogleAccessToken { param($KeyFile, $Scope) return 'test-token' }
function Invoke-RestMethod {
    param([string]$Method, [string]$Uri, $Headers, $ContentType, $Body, $TimeoutSec)
    $script:calls.Add(("$Method $Uri" -replace '^(\S+) \S*/applications/[^/]+', '$1 ').ToLowerInvariant())
    switch -Regex ("$Method $Uri") {
        '(?i)^Get .*/tracks/[^/]+/releases$' { if ($script:failLifecycle) { throw 'the lifecycle read is down' }; return [pscustomobject]@{} }
        '(?i)^Post .*/edits$' { return [pscustomobject]@{ id = 'edit-1' } }
        '(?i)^Get .*/edits/edit-1/tracks/' { if ($script:failTrack) { throw 'the track read is down' }; return [pscustomobject]@{} }
        '(?i)^Delete .*/edits/edit-1$' { return $null }
    }
    throw "unexpected call: $Method $Uri"
}
function Reset-Stubs { $script:calls.Clear(); $script:failLifecycle = $false; $script:failTrack = $false }
function Open-LikeAPublisher([string]$Path) {
    # The call both product publishers make, verbatim in its arguments.
    return [IO.File]::Open($Path, 'OpenOrCreate', 'ReadWrite', 'None')
}
function Test-LockFree([string]$Repo, [string]$App) {
    $l = Enter-RlPlayAppLock -RepoRoot $Repo -AppId $App
    $free = $l.held
    Exit-RlPlayAppLock $l
    return $free
}

$scratch = Join-Path ([IO.Path]::GetTempPath()) ('play-probe-lock-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $scratch -Force | Out-Null
$keyFile = Join-Path $scratch 'key.json'
Set-Content -LiteralPath $keyFile -Value '{}' -Encoding utf8
$savedKey = $env:SZA_PLAY_SERVICE_ACCOUNT_JSON
$savedStub = $env:SZA_RELEASES_PROBE_STUB
$env:SZA_PLAY_SERVICE_ACCOUNT_JSON = $keyFile
$env:SZA_RELEASES_PROBE_STUB = $null
function New-Repo([string]$Name) { $d = Join-Path $scratch $Name; New-Item -ItemType Directory -Path $d -Force | Out-Null; return $d }
$app = 'com.example.app'
$spec = [pscustomobject]@{ id = $app; track = 'production' }
try {
    Test-Case 'the lock path is <repo>/temp/play-lock/<applicationId>.lock and only an application id is accepted' {
        $r = New-Repo 'c1'
        Assert-That ((Get-RlPlayLockPath -RepoRoot $r -AppId $app) -ceq [IO.Path]::GetFullPath("$r\temp\play-lock\$app.lock")) "the path is '$(Get-RlPlayLockPath -RepoRoot $r -AppId $app)'"
        foreach ($ok in 'com.example.app', 'a.b', 'com.example_1.app2') { Assert-That (Test-RlApplicationId $ok) "'$ok' was refused" }
        foreach ($bad in '', 'com', 'com..x', '..\x', 'com.example/x', 'com.1x.y', 'C:\x.y', 'com.x.', ' com.x', 'com.x ') { Assert-That (-not (Test-RlApplicationId $bad)) "'$bad' was accepted" }
        $none = Enter-RlPlayAppLock -RepoRoot $r -AppId '..\evil'
        Assert-That (-not $none.held -and $none.reason -match 'not an application id') "a bad id gave held=$($none.held), '$($none.reason)'"
        Assert-That (-not (Test-Path -LiteralPath (Join-Path $r 'temp'))) 'a refused id still created the lock folder'
    }

    Test-Case 'the lock is the publishers'' lock in both directions, and Exit frees it' {
        $r = New-Repo 'c2'
        $path = Get-RlPlayLockPath -RepoRoot $r -AppId $app
        New-Item -ItemType Directory -Force -Path (Split-Path $path) | Out-Null
        $theirs = Open-LikeAPublisher $path
        try {
            $blocked = Enter-RlPlayAppLock -RepoRoot $r -AppId $app
            Assert-That (-not $blocked.held -and $null -eq $blocked.stream) 'a lock held by a publisher did not stop the probe'
            Assert-That ($blocked.reason -match 'another publisher or probe holds it' -and $blocked.path -ceq $path) "the refusal reads '$($blocked.reason)' at '$($blocked.path)'"
        } finally { $theirs.Dispose() }
        $ours = Enter-RlPlayAppLock -RepoRoot $r -AppId $app
        try {
            Assert-That ($ours.held -and $ours.path -ceq $path) 'the lock was not taken once the publisher let go'
            $threw = $false
            try { $x = Open-LikeAPublisher $path; $x.Dispose() } catch [System.IO.IOException] { $threw = $true }
            Assert-That $threw 'the probe''s held lock did not stop a publisher-style open'
        } finally { Exit-RlPlayAppLock $ours }
        Assert-That ($null -eq $ours.stream) 'Exit left the stream set'
        Exit-RlPlayAppLock $ours
        Assert-That (Test-LockFree $r $app) 'the lock stayed held after Exit'
        Assert-That ((Get-Content -LiteralPath $path -Raw) -match '^pid \d+ since \S+ \(release-ledger probe\)$') 'the holder note is not in the file'
    }

    Test-Case 'with the lock free the probe reads the lifecycle, opens one edit, reads the track and deletes it' {
        Reset-Stubs
        $r = New-Repo 'c3'
        $res = Invoke-RlProbePlay -Spec $spec -RepoRoot $r
        Assert-That $res.ok "the probe was not ok: $($res.reason)"
        $want = 'get /tracks/production/releases|post /edits|get /edits/edit-1/tracks/production|delete /edits/edit-1'
        Assert-That (($script:calls -join '|') -ceq $want) "the calls were '$($script:calls -join '|')'"
        Assert-That (Test-LockFree $r $app) 'the lock stayed held after the probe'
    }

    Test-Case 'with the lock held the probe opens no edit, keeps the lifecycle read and names the lock' {
        Reset-Stubs
        $r = New-Repo 'c4'
        $path = Get-RlPlayLockPath -RepoRoot $r -AppId $app
        New-Item -ItemType Directory -Force -Path (Split-Path $path) | Out-Null
        $channel = [pscustomobject]@{ key = 'play'; kind = 'play'; spec = $spec }
        $theirs = Open-LikeAPublisher $path
        try {
            $res = Invoke-RlProbe -Channel $channel -RepoRoot $r
            Assert-That ($res.ok) "the probe was not ok although the lifecycle answered: $($res.reason)"
            Assert-That (($script:calls -join '|') -ceq 'get /tracks/production/releases') "the calls were '$($script:calls -join '|')', not the lifecycle read alone"
            $gap = @($res.diagnostics | Where-Object { $_.kind -ceq 'play-gap' -and $_.what -ceq 'track configuration' })
            Assert-That ($gap.Count -eq 1) "expected one track-configuration gap, got $($gap.Count)"
            Assert-That ($gap[0].reason -match "Play lock temp/play-lock/$([regex]::Escape($app))\.lock is not ours \(another publisher or probe holds it\)") "the gap reads '$($gap[0].reason)'"
            Assert-That ((Format-RlProbeDiagnostic -Key 'play' -Diagnostic $gap[0]) -match 'lock') 'the printed line does not mention the lock'
            Reset-Stubs
            $script:failLifecycle = $true
            $down = Invoke-RlProbe -Channel $channel -RepoRoot $r
            Assert-That (-not $down.ok -and $down.reason -match 'Play lock') "with both reads out the result was ok=$($down.ok), '$($down.reason)'"
            Assert-That (@($script:calls | Where-Object { $_ -match '^post ' }).Count -eq 0) 'an edit was opened while the lock was held'
        } finally { $theirs.Dispose() }
    }

    Test-Case 'the lock is freed when the track read throws, and the edit is still deleted' {
        Reset-Stubs
        $script:failTrack = $true
        $r = New-Repo 'c5'
        $res = Invoke-RlProbePlay -Spec $spec -RepoRoot $r
        Assert-That ($res.ok) "the lifecycle answered and the probe was not ok: $($res.reason)"
        Assert-That (@($script:calls | Where-Object { $_ -match '^delete /edits/edit-1' }).Count -eq 1) "the edit was not deleted: $($script:calls -join '|')"
        Assert-That (Test-LockFree $r $app) 'the lock stayed held after a failed track read'
    }

    Test-Case 'an id that is not an application id opens nothing and creates no lock folder' {
        Reset-Stubs
        $r = New-Repo 'c6'
        $res = Invoke-RlProbePlay -Spec ([pscustomobject]@{ id = '..\evil'; track = 'production' }) -RepoRoot $r
        Assert-That (-not $res.ok -and $res.reason -match 'not an application id') "the result was ok=$($res.ok), '$($res.reason)'"
        Assert-That ($script:calls.Count -eq 0) "a call was made: $($script:calls -join '|')"
        Assert-That (-not (Test-Path -LiteralPath (Join-Path $r 'temp'))) 'a lock folder was created'
    }

    Test-Case 'a profile that moves paths.tempDir moves the lock, and an unreadable profile keeps the default' {
        $r = New-Repo 'c7'
        Set-Content -LiteralPath (Join-Path $r '.sza-profile.json') -Value '{"paths":{"tempDir":"scratch-x"}}' -Encoding utf8
        $moved = Get-RlPlayLockPath -RepoRoot $r -AppId $app
        Assert-That ($moved -ceq [IO.Path]::GetFullPath("$r\scratch-x\play-lock\$app.lock")) "the moved path is '$moved'"
        $l = Enter-RlPlayAppLock -RepoRoot $r -AppId $app
        try { Assert-That ($l.held -and (Test-Path -LiteralPath $moved)) 'the lock is not under the moved folder' } finally { Exit-RlPlayAppLock $l }
        Assert-That (-not (Test-Path -LiteralPath (Join-Path $r 'temp'))) 'the default folder was created as well'
        $b = New-Repo 'c7b'
        Set-Content -LiteralPath (Join-Path $b '.sza-profile.json') -Value '{ not json' -Encoding utf8
        Assert-That ((Get-RlPlayLockPath -RepoRoot $b -AppId $app) -ceq [IO.Path]::GetFullPath("$b\temp\play-lock\$app.lock")) 'an unreadable profile did not keep the default'
    }
} finally {
    $env:SZA_PLAY_SERVICE_ACCOUNT_JSON = $savedKey
    $env:SZA_RELEASES_PROBE_STUB = $savedStub
    if (-not $KeepScratch) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
}
Write-Host ("RESULT  run={0}  passed={1}  failed={2}  {3} s" -f $run, $passed, $failed, [math]::Round($clock.Elapsed.TotalSeconds, 1))
if ($failed -gt 0) { exit 1 } else { exit 0 }
