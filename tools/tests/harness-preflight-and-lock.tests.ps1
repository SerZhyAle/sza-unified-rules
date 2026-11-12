#requires -Version 7.0
<#
.SYNOPSIS
    Cases for two harness fixes that the FMS_A tickets S4397 and S2761 parked on the canon.

.DESCRIPTION
    Direct calls of the shipped scripts against an empty scratch root; no ledger, no queue, nothing is pushed.

      1. S4397: spec-next-preflight.ps1 refuses a dash-led token it does not declare (exit 2, the error names it,
         nothing is ranked or claimed) instead of swallowing it into the exclude set.
      2. S4397: ids after -Exclude are still bound as ids - they never reach the unknown-option refusal.
      3. S2761: a caller NAMED by an explicit agent id leaves another session's live legacy pid- code lock in place.
      4. S2761: a caller named by nothing releases that legacy lock (the compatibility the ticket keeps).
      5. S2761: a caller releases a code lock it owns.

    Cases 3-5 clear the identity variables for the child processes and restore them afterwards.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$harness = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\harness'))
$preflight = Join-Path $harness 'spec_catalog\spec-next-preflight.ps1'

$run = 0; $passed = 0; $failed = 0
function Assert-That([bool] $Condition, [string] $Message) { if (-not $Condition) { throw $Message } }
function Run-Case([string] $Name, [scriptblock] $Body) {
    $script:run++
    Write-Host -NoNewline "CASE  $Name ... "
    try { & $Body; $script:passed++; Write-Host 'PASS' -ForegroundColor Green }
    catch { $script:failed++; Write-Host 'FAIL' -ForegroundColor Red; Write-Host "      $($_.Exception.Message)" -ForegroundColor DarkRed }
}
function Invoke-Pwsh([string] $Script, [string[]] $ScriptArgs = @()) {
    $out = & pwsh -NoProfile -File $Script @ScriptArgs 2>&1 | Out-String
    [pscustomobject]@{ code = $LASTEXITCODE; output = $out.Trim() }
}

$scratch = Join-Path ([IO.Path]::GetTempPath()) ('harness-pl-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $scratch | Out-Null
$saved = @{}
foreach ($name in 'SZA_PROJECT_ROOT', 'SZA_PROFILE_PATH', 'CLAUDE_CODE_SESSION_ID', 'SZA_AGENT_ID', 'FMS_AGENT_ID') {
    $saved[$name] = [Environment]::GetEnvironmentVariable($name)
}

function Get-CodeLockFile { Get-ChildItem -LiteralPath $scratch -Recurse -Filter 'CODE.SCRIPTS.LOCK' -ErrorAction SilentlyContinue | Select-Object -First 1 }

try {
    $env:SZA_PROJECT_ROOT = $scratch
    $env:SZA_PROFILE_PATH = $null

    Run-Case 'S4397: an undeclared option is refused loudly, not swallowed as an exclude id' {
        $r = Invoke-Pwsh $preflight @('-Bogus')
        Assert-That ($r.code -eq 2) "-Bogus exited $($r.code), expected 2: $($r.output)"
        Assert-That ($r.output -match 'unknown option\(s\): -Bogus') "the error does not name -Bogus: $($r.output)"
        Assert-That ($r.output -notmatch 'excluded_ids') 'the run went on to print a ranking'
    }

    Run-Case 'S4397: ids after -Exclude still bind as ids and never reach the refusal' {
        # -ClaimAs without -Claim is the next usage error, so reaching it proves the ids passed the new check.
        $r = Invoke-Pwsh $preflight @('-Exclude', 'S0001', 'S0002', '-ClaimAs', 'x')
        Assert-That ($r.code -eq 2) "exit $($r.code), expected 2: $($r.output)"
        Assert-That ($r.output -match 'means nothing without -Claim') "the usage error was not the -ClaimAs one: $($r.output)"
        Assert-That ($r.output -notmatch 'unknown option') "an id was refused as an option: $($r.output)"
    }

    $enter = Join-Path $harness 'locks\enter-code-lock.ps1'
    $exit = Join-Path $harness 'locks\exit-code-lock.ps1'
    # Neither a session id nor an explicit agent id, so the owner and the unnamed caller resolve below the env vars.
    $env:CLAUDE_CODE_SESSION_ID = $null; $env:SZA_AGENT_ID = $null; $env:FMS_AGENT_ID = $null

    function New-LegacyPidLock {
        $e = Invoke-Pwsh $enter @('-Domain', 'Code.Scripts', '-Reason', 'probe')
        Assert-That ($e.code -eq 0) "enter-code-lock exited $($e.code): $($e.output)"
        $f = Get-CodeLockFile
        Assert-That ($null -ne $f) 'the lock file was not written'
        # The shape written before the identity chain existed: a pid- owner. This shell is alive, so the lock is live.
        $raw = Get-Content -LiteralPath $f.FullName -Raw
        Set-Content -LiteralPath $f.FullName -Value ($raw -replace '"sessionId"\s*:\s*"[^"]*"', ('"sessionId":"pid-' + $PID + '"')) -NoNewline
    }

    Run-Case 'S2761: a caller named by an explicit agent id leaves a live legacy pid- lock in place' {
        New-LegacyPidLock
        $env:SZA_AGENT_ID = 'codex-probe'
        try { $r = Invoke-Pwsh $exit @('-Name', 'Code.Scripts') } finally { $env:SZA_AGENT_ID = $null }
        Assert-That ($r.code -eq 0) "exit-code-lock exited $($r.code): $($r.output)"
        Assert-That ($null -ne (Get-CodeLockFile)) "the named caller released another session's lock: $($r.output)"
        Assert-That ($r.output -match 'left in place|leaving it in place') "the lock was kept but not reported: $($r.output)"
    }

    Run-Case 'S2761: a caller named by nothing releases that legacy pid- lock' {
        # The lock left by the previous case is still there.
        Assert-That ($null -ne (Get-CodeLockFile)) 'precondition: the legacy lock is missing'
        $r = Invoke-Pwsh $exit @('-Name', 'Code.Scripts')
        Assert-That ($r.code -eq 0) "exit-code-lock exited $($r.code): $($r.output)"
        Assert-That ($null -eq (Get-CodeLockFile)) "the unnamed caller did not release the legacy lock: $($r.output)"
    }

    Run-Case 'S2761: a named caller still releases its own code lock' {
        $env:SZA_AGENT_ID = 'codex-probe'
        try {
            $e = Invoke-Pwsh $enter @('-Domain', 'Code.Scripts', '-Reason', 'probe')
            Assert-That ($e.code -eq 0) "enter-code-lock exited $($e.code): $($e.output)"
            Assert-That ($null -ne (Get-CodeLockFile)) 'the lock file was not written'
            $r = Invoke-Pwsh $exit @('-Name', 'Code.Scripts')
        } finally { $env:SZA_AGENT_ID = $null }
        Assert-That ($r.code -eq 0) "exit-code-lock exited $($r.code): $($r.output)"
        Assert-That ($null -eq (Get-CodeLockFile)) "the named caller kept its own lock: $($r.output)"
    }
}
finally {
    foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name]) }
    Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host ("{0} cases: {1} passed, {2} failed" -f $run, $passed, $failed)
exit $(if ($failed -eq 0) { 0 } else { 1 })
