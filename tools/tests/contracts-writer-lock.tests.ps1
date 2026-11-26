#requires -Version 7.0
<#
    Fast tests for tools/contracts-writer-lock.ps1 (CANONR-0225, CANONR-0240): the holder whose owner is a session
    guid is judged by the host process recorded beside it.
     1. An -Acquire by a session-guid owner records hostId, and -Status prints the holder.
     2. A guid holder whose hostId process is gone is stale: -Status says free (stale), another session acquires.
     3. A guid holder whose hostId process is alive stays held: another session gets exit 4.
     4. A guid holder without hostId keeps the clock rule: fresh is busy, older than -StaleHours is taken over.
    Each case runs the script in a child pwsh with its own CLAUDE_CODE_SESSION_ID against a lock file in a throwaway
    folder; -KeepScratch leaves it. #>
[CmdletBinding()]
param([switch]$KeepScratch)
$ErrorActionPreference = 'Stop'
$SourceRoot = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent)
$script = Join-Path $SourceRoot 'tools/contracts-writer-lock.ps1'
. (Join-Path $SourceRoot 'tools/harness/locks/agent-identity.ps1')

$scratch = Join-Path ([IO.Path]::GetTempPath()) ("cwlock-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $scratch -Force | Out-Null
$lock = Join-Path $scratch 'contracts-writer.lock'

# Child processes must answer with the session id set here, under a fixed name, writing no nickname file.
$idVar = Get-SzaEnvName 'AGENT_ID'
$nameVar = Get-SzaEnvName 'AGENT_NAME'
$savedId = [Environment]::GetEnvironmentVariable($idVar)
$savedName = [Environment]::GetEnvironmentVariable($nameVar)
$savedSession = $env:CLAUDE_CODE_SESSION_ID
[Environment]::SetEnvironmentVariable($idVar, $null)
[Environment]::SetEnvironmentVariable($nameVar, 'lock-test')

$clock = [Diagnostics.Stopwatch]::StartNew()
$run = 0; $passed = 0; $failed = 0
function Assert-That([bool]$Condition, [string]$Reason) { if (-not $Condition) { throw $Reason } }
function Test-Case([string]$Name, [scriptblock]$Body) {
    $script:run++
    Remove-Item -LiteralPath $lock -Force -ErrorAction SilentlyContinue
    Write-Host -NoNewline "CASE  $Name ... "
    try { & $Body; $script:passed++; Write-Host 'PASS' -ForegroundColor Green }
    catch { $script:failed++; Write-Host 'FAIL' -ForegroundColor Red; Write-Host "      $($_.Exception.Message)" -ForegroundColor DarkRed }
}
function Invoke-Lock([string]$Session, [string[]]$LockArgs) {
    $env:CLAUDE_CODE_SESSION_ID = $Session
    $out = & pwsh -NoProfile -File $script @LockArgs -LockPath $lock 2>&1
    return [pscustomobject]@{ Exit = $LASTEXITCODE; Out = (@($out) -join "`n") }
}
function Write-Holder([string]$Owner, [datetime]$Since, [string]$HostId) {
    $rec = [ordered]@{ owner = $Owner; name = 'old-pass'; ticket = 'CANONR-0000'; since = $Since.ToString('o') }
    if ($HostId) { $rec.hostId = $HostId }
    Set-Content -LiteralPath $lock -Value ($rec | ConvertTo-Json -Compress) -NoNewline
}

$liveHost = Format-AgentHostIdentityId -Process (Get-Process -Id $PID)
$deadHost = 'host-claude-999999-1'
$sessionA = [guid]::NewGuid().ToString()
$sessionB = [guid]::NewGuid().ToString()

try {
    Test-Case 'acquire by a session guid records hostId' {
        $r = Invoke-Lock $sessionA @('-Acquire', '-Ticket', 'CANONR-0240')
        Assert-That ($r.Exit -eq 0) "acquire exit $($r.Exit): $($r.Out)"
        $rec = Get-Content -LiteralPath $lock -Raw | ConvertFrom-Json
        Assert-That ($rec.owner -eq $sessionA) "owner $($rec.owner)"
        Assert-That ([string]$rec.hostId -match '^(host|pid)-') "hostId '$($rec.hostId)'"
        $s = Invoke-Lock $sessionB @('-Status')
        Assert-That ($s.Out -match '^held by ') "status: $($s.Out)"
    }
    Test-Case 'a dead host frees a fresh guid holder' {
        Write-Holder $sessionA (Get-Date) $deadHost
        $s = Invoke-Lock $sessionB @('-Status')
        Assert-That ($s.Out -match '^free \(stale') "status: $($s.Out)"
        $r = Invoke-Lock $sessionB @('-Acquire', '-Ticket', 'CANONR-0240')
        Assert-That ($r.Exit -eq 0) "acquire exit $($r.Exit): $($r.Out)"
        Assert-That ((Get-Content -LiteralPath $lock -Raw | ConvertFrom-Json).owner -eq $sessionB) 'owner not replaced'
    }
    Test-Case 'a live host keeps a guid holder' {
        Write-Holder $sessionA (Get-Date) $liveHost
        $r = Invoke-Lock $sessionB @('-Acquire', '-Ticket', 'CANONR-0240')
        Assert-That ($r.Exit -eq 4) "acquire exit $($r.Exit): $($r.Out)"
    }
    Test-Case 'no hostId keeps the clock rule' {
        Write-Holder $sessionA (Get-Date) ''
        $r = Invoke-Lock $sessionB @('-Acquire', '-Ticket', 'CANONR-0240')
        Assert-That ($r.Exit -eq 4) "fresh: acquire exit $($r.Exit): $($r.Out)"
        Write-Holder $sessionA (Get-Date).AddHours(-3) ''
        $r = Invoke-Lock $sessionB @('-Acquire', '-Ticket', 'CANONR-0240')
        Assert-That ($r.Exit -eq 0) "old: acquire exit $($r.Exit): $($r.Out)"
    }
}
finally {
    $env:CLAUDE_CODE_SESSION_ID = $savedSession
    [Environment]::SetEnvironmentVariable($idVar, $savedId)
    [Environment]::SetEnvironmentVariable($nameVar, $savedName)
    if (-not $KeepScratch) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host ("{0} cases, {1} passed, {2} failed, {3:N2} s" -f $run, $passed, $failed, $clock.Elapsed.TotalSeconds)
if ($failed -gt 0) { exit 1 }
exit 0
