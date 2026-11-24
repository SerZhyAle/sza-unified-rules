#requires -Version 7.0
<#
    Fast tests for the Play probe's per-application lock (tools/harness/releases/_play-lock.ps1 and Invoke-RlProbePlay in
    _probes.ps1, GOOGLE-PLAY 0.5 section 9).
     1. The default path uses the shared Play state directory, tests can override it, and only an application id is
        accepted as the file name.
     2. A no-sharing open stops Enter-RlPlayAppLock, the probe's held lock stops a second no-sharing open, and Exit
        frees it.
     3. With the lock free the probe reads the lifecycle, opens one edit, reads the track and deletes the edit, and the
        lock is free again afterwards.
     4. With the lock held or its file inaccessible, Invoke-RlProbe keeps the lifecycle read and reports the track
        configuration gap with the lock path. If the lifecycle read also fails it reports an unsuccessful probe.
     5. The lock is freed when the track read throws, and the edit is still deleted.
     6. An id that is not an application id opens nothing and creates no lock folder.
     7. Checkouts with a moved scratch folder or an unreadable profile resolve the same default lock path.
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
    $script:RlPlayLockDirOverride = Join-Path $scratch "case-$script:run"
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
function Open-Exclusive([string]$Path) {
    return [IO.File]::Open($Path, 'OpenOrCreate', 'ReadWrite', 'None')
}
function Test-LockFree([string]$App) {
    $l = Enter-RlPlayAppLock -AppId $App
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
$channel = [pscustomobject]@{ key = 'play'; kind = 'play'; spec = $spec }
$defaultPath = if ($IsWindows) { Join-Path $env:LOCALAPPDATA "sza/play-publishing/$app.lock" }
    else { Join-Path $HOME ".local/state/sza/play-publishing/$app.lock" }
$defaultPath = [IO.Path]::GetFullPath($defaultPath)
try {
    Test-Case 'the lock path uses the shared Play state directory and supports a test override' {
        $override = $script:RlPlayLockDirOverride
        $path = Get-RlPlayLockPath -AppId $app
        Assert-That ($path -ceq (Join-Path $override "$app.lock")) "the override resolved to '$path'"
        $script:RlPlayLockDirOverride = $null
        try {
            $path = Get-RlPlayLockPath -AppId $app
            Assert-That ($path -ceq $defaultPath) "the default resolved to '$path' instead of '$defaultPath'"
        } finally { $script:RlPlayLockDirOverride = $override }
        foreach ($ok in 'com.example.app', 'a.b', 'com.example_1.app2') { Assert-That (Test-RlApplicationId $ok) "'$ok' was refused" }
        foreach ($bad in '', 'com', 'com..x', '..\x', 'com.example/x', 'com.1x.y', 'C:\x.y', 'com.x.', ' com.x', 'com.x ', "com.x`n") { Assert-That (-not (Test-RlApplicationId $bad)) "'$bad' was accepted" }
        $none = Enter-RlPlayAppLock -AppId '..\evil'
        Assert-That (-not $none.held -and $none.reason -match 'not an application id') "a bad id gave held=$($none.held), '$($none.reason)'"
        Assert-That (-not (Test-Path -LiteralPath $override)) 'a refused id still created the lock folder'
    }

    Test-Case 'exclusive opens contend in both directions, and Exit frees the lock' {
        $path = Get-RlPlayLockPath -AppId $app
        New-Item -ItemType Directory -Force -Path (Split-Path $path) | Out-Null
        $theirs = Open-Exclusive $path
        try {
            $blocked = Enter-RlPlayAppLock -AppId $app
            Assert-That (-not $blocked.held -and $null -eq $blocked.stream) 'a lock held by a publisher did not stop the probe'
            Assert-That ($blocked.reason -and $blocked.path -ceq $path) "the refusal reads '$($blocked.reason)' at '$($blocked.path)'"
            if ($IsWindows) {
                Assert-That ($blocked.reason -ceq 'another publisher or probe holds it') "the sharing violation was reported as '$($blocked.reason)'"
            }
        } finally { $theirs.Dispose() }
        $ours = Enter-RlPlayAppLock -AppId $app
        try {
            Assert-That ($ours.held -and $ours.path -ceq $path) 'the lock was not taken once the publisher let go'
            $threw = $false
            try { $x = Open-Exclusive $path; $x.Dispose() } catch [System.IO.IOException] { $threw = $true }
            Assert-That $threw 'the probe''s held lock did not stop a second exclusive open'
        } finally { Exit-RlPlayAppLock $ours }
        Assert-That ($null -eq $ours.stream) 'Exit left the stream set'
        Exit-RlPlayAppLock $ours
        Assert-That (Test-LockFree $app) 'the lock stayed held after Exit'
        Assert-That ((Get-Content -LiteralPath $path -Raw) -match '^pid \d+ since \S+ \(release-ledger probe\)$') 'the holder note is not in the file'
    }

    Test-Case 'with the lock free the probe reads the lifecycle, opens one edit, reads the track and deletes it' {
        Reset-Stubs
        $res = Invoke-RlProbePlay -Spec $spec
        Assert-That $res.ok "the probe was not ok: $($res.reason)"
        $want = 'get /tracks/production/releases|post /edits|get /edits/edit-1/tracks/production|delete /edits/edit-1'
        Assert-That (($script:calls -join '|') -ceq $want) "the calls were '$($script:calls -join '|')'"
        Assert-That (Test-LockFree $app) 'the lock stayed held after the probe'
    }

    Test-Case 'when the lock cannot be taken, the probe keeps the lifecycle read and names the lock' {
        Reset-Stubs
        $r = New-Repo 'c4'
        $path = Get-RlPlayLockPath -AppId $app
        New-Item -ItemType Directory -Force -Path (Split-Path $path) | Out-Null
        $theirs = Open-Exclusive $path
        try {
            $res = Invoke-RlProbe -Channel $channel -RepoRoot $r
            Assert-That ($res.ok) "the probe was not ok although the lifecycle answered: $($res.reason)"
            Assert-That (($script:calls -join '|') -ceq 'get /tracks/production/releases') "the calls were '$($script:calls -join '|')', not the lifecycle read alone"
            $gap = @($res.diagnostics | Where-Object { $_.kind -ceq 'play-gap' -and $_.what -ceq 'track configuration' })
            Assert-That ($gap.Count -eq 1) "expected one track-configuration gap, got $($gap.Count)"
            Assert-That ($gap[0].reason.Contains("Play lock $path is not ours (")) "the gap reads '$($gap[0].reason)'"
            Assert-That ((Format-RlProbeDiagnostic -Key 'play' -Diagnostic $gap[0]) -match 'lock') 'the printed line does not mention the lock'
            Reset-Stubs
            $script:failLifecycle = $true
            $down = Invoke-RlProbe -Channel $channel -RepoRoot $r
            Assert-That (-not $down.ok -and $down.reason -match 'Play lock') "with both reads out the result was ok=$($down.ok), '$($down.reason)'"
            Assert-That (@($script:calls | Where-Object { $_ -match '^post ' }).Count -eq 0) 'an edit was opened while the lock was held'
        } finally { $theirs.Dispose() }

        Reset-Stubs
        $script:RlPlayLockDirOverride = Join-Path $scratch 'unopenable'
        $path = Get-RlPlayLockPath -AppId $app
        [void][IO.Directory]::CreateDirectory($path)
        $res = Invoke-RlProbe -Channel $channel -RepoRoot $r
        Assert-That ($res.ok -and ($script:calls -join '|') -ceq 'get /tracks/production/releases') 'an unopenable lock file did not leave only the lifecycle read'
        $gap = @($res.diagnostics | Where-Object { $_.kind -ceq 'play-gap' -and $_.what -ceq 'track configuration' })
        Assert-That ($gap.Count -eq 1 -and $gap[0].reason.Contains($path)) 'the open failure did not name the lock file'
    }

    Test-Case 'the lock is freed when the track read throws, and the edit is still deleted' {
        Reset-Stubs
        $script:failTrack = $true
        $res = Invoke-RlProbePlay -Spec $spec
        Assert-That ($res.ok) "the lifecycle answered and the probe was not ok: $($res.reason)"
        Assert-That (@($script:calls | Where-Object { $_ -match '^delete /edits/edit-1' }).Count -eq 1) "the edit was not deleted: $($script:calls -join '|')"
        Assert-That (Test-LockFree $app) 'the lock stayed held after a failed track read'
    }

    Test-Case 'an id that is not an application id opens nothing and creates no lock folder' {
        Reset-Stubs
        $res = Invoke-RlProbePlay -Spec ([pscustomobject]@{ id = '..\evil'; track = 'production' })
        Assert-That (-not $res.ok -and $res.reason -match 'not an application id') "the result was ok=$($res.ok), '$($res.reason)'"
        Assert-That ($script:calls.Count -eq 0) "a call was made: $($script:calls -join '|')"
        Assert-That (-not (Test-Path -LiteralPath $script:RlPlayLockDirOverride)) 'a lock folder was created'
    }

    Test-Case 'a moved scratch directory and an unreadable profile both keep the shared lock path' {
        $r = New-Repo 'c7'
        Set-Content -LiteralPath (Join-Path $r '.sza-profile.json') -Value '{"paths":{"tempDir":"scratch-x"}}' -Encoding utf8
        $b = New-Repo 'c7b'
        Set-Content -LiteralPath (Join-Path $b '.sza-profile.json') -Value '{ not json' -Encoding utf8
        $script:RlPlayLockDirOverride = $null
        foreach ($repo in $r, $b) {
            Push-Location -LiteralPath $repo
            try {
                $path = Get-RlPlayLockPath -AppId $app
                Assert-That ($path -ceq $defaultPath) "the path from '$repo' resolved to '$path' instead of '$defaultPath'"
            } finally { Pop-Location }
        }
    }
} finally {
    $script:RlPlayLockDirOverride = $null
    $env:SZA_PLAY_SERVICE_ACCOUNT_JSON = $savedKey
    $env:SZA_RELEASES_PROBE_STUB = $savedStub
    if (-not $KeepScratch) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
}
Write-Host ("RESULT  run={0}  passed={1}  failed={2}  {3} s" -f $run, $passed, $failed, [math]::Round($clock.Elapsed.TotalSeconds, 1))
if ($failed -gt 0) { exit 1 } else { exit 0 }
