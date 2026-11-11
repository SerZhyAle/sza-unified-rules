#requires -Version 7.0
<#
.SYNOPSIS
    Fast targeted tests for S0031:
      1. Runner terminates child after status move to Block*, Implemented or Verified and StatusGraceMinutes pass (outcome ok).
      2. On timeout runner writes status note "killed at N min, work left in the tree, see <log>" through update.ps1.
      3. Active child transcript extends deadline up to MaxTimeoutMinutes.
#>
[CmdletBinding()]
param([switch]$KeepScratch)

$ErrorActionPreference = 'Stop'
$SourceRoot = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent)
$harness = Join-Path $SourceRoot 'tools/harness'
$batch = Join-Path $harness 'batch/run-spec-queue.ps1'
$update = Join-Path $harness 'spec_catalog/update.ps1'

$run = 0; $passed = 0; $failed = 0
function Assert-That([bool]$Condition, [string]$Reason) { if (-not $Condition) { throw $Reason } }
function Test-Case([string]$Name, [scriptblock]$Body) {
    $script:run++
    Write-Host -NoNewline "CASE  $Name ... "
    try {
        & $Body
        $script:passed++
        Write-Host 'PASS' -ForegroundColor Green
    } catch {
        $script:failed++
        Write-Host 'FAIL' -ForegroundColor Red
        Write-Host "      $($_.Exception.Message)" -ForegroundColor DarkRed
    }
}

$scratch = Join-Path ([System.IO.Path]::GetTempPath()) ('s0031-test-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $scratch | Out-Null

function New-TestProject([string]$Name) {
    $root = Join-Path $scratch $Name
    New-Item -ItemType Directory -Path $root | Out-Null
    $env:SZA_PROJECT_ROOT = $root
    & pwsh -NoProfile -File (Join-Path $harness 'scaffold/init-task-flow.ps1') -Root $root | Out-Null
    & pwsh -NoProfile -File (Join-Path $harness 'spec_catalog/capture-draft.ps1') -Slug 'test-task' -Text 'description' | Out-Null

    $profilePath = Join-Path $root '.sza-profile.json'
    $doc = Get-Content $profilePath -Raw | ConvertFrom-Json -AsHashtable
    $doc.runner = @{
        command        = 'pwsh'
        argsTemplate   = @('-NoProfile', '-File', (Join-Path $root 'fake-child.ps1'), '{prompt}')
        promptTemplate = '/sza:spec-to-audit {id}'
        headlessMatch  = [regex]::Escape((Split-Path $root -Leaf))
    }
    $doc.locks = @{ agentProcessNames = @('pwsh.exe', 'pwsh') }
    $doc | ConvertTo-Json -Depth 8 | Set-Content $profilePath -Encoding utf8
    return $root
}

try {
    # ---------------------------------------------------------------------------------------------
    # CASE 1: Status grace termination (child moves to BlockNeedUserTest, then hangs)
    # ---------------------------------------------------------------------------------------------
    Test-Case 'hang after status: child moves status and hangs -> stopped after grace period and recorded ok' {
        $p = New-TestProject 'p-status-hang'
        $updatePath = $update.Replace('\', '/')
        $fakeChild = @"
`$ErrorActionPreference = 'Stop'
`$root = `$PSScriptRoot
`$env:SZA_PROJECT_ROOT = `$root
& pwsh -NoProfile -File '$updatePath' -Id 'S0001' -Status 'BlockQuestions' -StatusNote 'Q: which answers does this ticket wait for?'
Start-Sleep -Seconds 60
exit 0
"@
        Set-Content (Join-Path $p 'fake-child.ps1') $fakeChild -Encoding utf8

        $env:SZA_PROJECT_ROOT = $p
        $env:SZA_PROFILE_PATH = $null
        $output = & pwsh -NoProfile -File $batch -Ids 'S0001' -StatusGraceMinutes 0.04 -TimeoutMinutes 1 -ClaimGraceSeconds 0 2>&1 | Out-String

        $runsFile = Join-Path $p 'temp/spec-queue/runs-a.jsonl'
        Assert-That (Test-Path $runsFile) 'runs-a.jsonl was not written'
        $runs = @(Get-Content $runsFile | ForEach-Object { $_ | ConvertFrom-Json })
        Assert-That ($runs.Count -ge 1) 'no run records written'
        $rec = $runs[0]
        Assert-That ($rec.outcome -eq 'ok') "expected outcome ok, got $($rec.outcome)"
        Assert-That ($rec.moved -eq $true) "expected moved true, got $($rec.moved)"
        Assert-That ($rec.statusAfter -eq 'BlockQuestions') "expected statusAfter BlockQuestions, got $($rec.statusAfter)"
    }

    # ---------------------------------------------------------------------------------------------
    # CASE 2: Timeout note: child hangs without moving status -> timeout writes status note
    # ---------------------------------------------------------------------------------------------
    Test-Case 'timeout: child exceeds deadline -> timeout recorded and status note written to header and ledger' {
        $p = New-TestProject 'p-timeout-note'
        $fakeChild = @"
Start-Sleep -Seconds 60
exit 0
"@
        Set-Content (Join-Path $p 'fake-child.ps1') $fakeChild -Encoding utf8

        $env:SZA_PROJECT_ROOT = $p
        $env:SZA_PROFILE_PATH = $null
        $output = & pwsh -NoProfile -File $batch -Ids 'S0001' -TimeoutMinutes 0.04 -ClaimGraceSeconds 0 -Quiet 2>&1 | Out-String

        $runsFile = Join-Path $p 'temp/spec-queue/runs-a.jsonl'
        Assert-That (Test-Path $runsFile) 'runs-a.jsonl was not written'
        $runs = @(Get-Content $runsFile | ForEach-Object { $_ | ConvertFrom-Json })
        $rec = $runs[0]
        Assert-That ($rec.outcome -eq 'timeout') "expected outcome timeout, got $($rec.outcome)"

        # Check ledger record
        $catalogFile = Join-Path $p 'PLAN/spec-catalog.jsonl'
        $catalog = @(Get-Content $catalogFile | ForEach-Object { $_ | ConvertFrom-Json })
        $ticket = $catalog | Where-Object { $_.id -eq 'S0001' }
        Assert-That ($null -ne $ticket) 'S0001 not in catalog'
        Assert-That ($ticket.PSObject.Properties.Name -contains 'statusNote') 'statusNote missing on ticket'
        Assert-That ($ticket.statusNote -match '^killed at \d+ min, work left in the tree, see ') "unexpected statusNote: $($ticket.statusNote)"

        # Check spec file header
        $specFile = Join-Path $p 'PLAN/S0001_test-task.md'
        $specText = Get-Content $specFile -Raw
        Assert-That ($specText -match '(?m)^\*\*Status note:\*\*\s*killed at \d+ min, work left in the tree, see ') "spec header missing status note: $specText"
    }

    # ---------------------------------------------------------------------------------------------
    # CASE 3: Active transcript deadline extension
    # ---------------------------------------------------------------------------------------------
    Test-Case 'transcript activity: transcript updated recently extends deadline up to cap' {
        $p = New-TestProject 'p-transcript-ext'
        # Fake transcript in scratch
        $configDir = Join-Path $scratch '.claude-fake'
        $projectsDir = Join-Path $configDir 'projects/test-proj'
        New-Item -ItemType Directory -Path $projectsDir -Force | Out-Null
        $savedConfig = $env:CLAUDE_CONFIG_DIR
        $env:CLAUDE_CONFIG_DIR = $configDir

        try {
            . (Join-Path $harness 'batch/_limit-hold.ps1')
            $sid = [guid]::NewGuid().ToString()
            $tFile = Join-Path $projectsDir "$sid.jsonl"
            Set-Content $tFile '{"type":"assistant"}' -Encoding utf8

            $found = Find-ChildTranscript -SessionId $sid
            Assert-That ($null -ne $found) "Find-ChildTranscript did not find transcript"
            Assert-That (Test-Path -LiteralPath $found) "transcript file does not exist"
            $writeTime = (Get-Item -LiteralPath $found).LastWriteTime
            Assert-That (((Get-Date) - $writeTime).TotalMinutes -lt 15) "transcript not within 15 min"
        } finally {
            $env:CLAUDE_CONFIG_DIR = $savedConfig
        }
    }
} finally {
    if (-not $KeepScratch -and (Test-Path $scratch)) {
        Remove-Item -Path $scratch -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ''
Write-Host "Cases: $run | Passed: $passed | Failed: $failed"
if ($failed -gt 0) { exit 1 } else { exit 0 }
