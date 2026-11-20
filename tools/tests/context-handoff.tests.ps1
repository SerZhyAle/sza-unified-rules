#requires -Version 7.0
<#
.SYNOPSIS
    Cases for the context-handoff claim: batch/_context-handoff.ps1 and its wiring in run-spec-queue.ps1.
.DESCRIPTION
    Pure functions plus text reads. No runner, no child process, no git, no scratch directory; nothing is written.
    Cases: 1 ConvertTo-HandoffTokens reads numbers and the shapes an agent writes by hand and refuses the rest;
    2 a marker with no figure, a zero or a figure under the minimum is no handoff, one at or above it is (the
    FMSWIN-0377 markers of 2026-11-20 are the fixtures); 3 the runner dot-sources the library, judges the marker
    before it can set the outcome, and prints why it refused; 4 the spec-to-audit skill names the same minimum.
#>
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\harness'))
$run = 0; $passed = 0; $failed = 0
function Assert-That([bool] $Condition, [string] $Message) { if (-not $Condition) { throw $Message } }
function Run-Case([string] $Name, [scriptblock] $Body) {
    $script:run++
    Write-Host -NoNewline "CASE  $Name ... "
    try { & $Body; $script:passed++; Write-Host 'PASS' -ForegroundColor Green }
    catch { $script:failed++; Write-Host 'FAIL' -ForegroundColor Red; Write-Host "      $($_.Exception.Message)" -ForegroundColor DarkRed }
}
$clock = [Diagnostics.Stopwatch]::StartNew()
. (Join-Path $root 'batch\_context-handoff.ps1')
$min = $script:ContextHandoffMinTokens

Run-Case '1. ConvertTo-HandoffTokens reads figures and refuses the rest' {
    Assert-That ((ConvertTo-HandoffTokens 0) -eq 0) 'zero is a figure'
    Assert-That ((ConvertTo-HandoffTokens 51710) -eq 51710) 'a JSON number must pass through'
    Assert-That ((ConvertTo-HandoffTokens 51710.9) -eq 51710) 'a fraction is cut, not rounded up past the line'
    Assert-That ((ConvertTo-HandoffTokens '51,710') -eq 51710) 'a comma-grouped string'
    Assert-That ((ConvertTo-HandoffTokens '51 710') -eq 51710) 'a space-grouped string'
    Assert-That ((ConvertTo-HandoffTokens '180k') -eq 180000) 'a k suffix'
    Assert-That ((ConvertTo-HandoffTokens '1.2M') -eq 1200000) 'an M suffix with a fraction'
    Assert-That ($null -eq (ConvertTo-HandoffTokens $null)) 'an absent value is no figure'
    Assert-That ($null -eq (ConvertTo-HandoffTokens -5)) 'a negative number is no figure'
    Assert-That ($null -eq (ConvertTo-HandoffTokens 'a lot')) 'text is no figure'
    Assert-That ($null -eq (ConvertTo-HandoffTokens '')) 'an empty string is no figure'
}
Run-Case '2. a handoff is valid only with a figure at or above the minimum' {
    Assert-That ($min -eq 150000) 'the minimum is 150000; change the skill text with it'
    $zero = '{"id":"FMSWIN-0377","tokens":0,"boundary":"Preliminary inventory and plan recorded."}' | ConvertFrom-Json
    $verdict = Test-ContextHandoffClaim -Handoff $zero
    Assert-That (-not $verdict.Valid -and $verdict.Tokens -eq 0 -and $verdict.Reason -match 'below') 'tokens 0 (the 2026-11-20 markers) must be refused with a reason'
    $absent = '{"id":"S1","boundary":"x"}' | ConvertFrom-Json
    $verdict = Test-ContextHandoffClaim -Handoff $absent
    Assert-That (-not $verdict.Valid -and $null -eq $verdict.Tokens -and $verdict.Reason -match 'no token figure') 'a marker without tokens must be refused under Set-StrictMode'
    $text = '{"id":"S1","tokens":"a lot"}' | ConvertFrom-Json
    Assert-That (-not (Test-ContextHandoffClaim -Handoff $text).Valid) 'a non-numeric tokens must be refused'
    $just = '{"id":"S1","tokens":149999}' | ConvertFrom-Json
    Assert-That (-not (Test-ContextHandoffClaim -Handoff $just).Valid) 'one under the minimum must be refused'
    $edge = '{"id":"S1","tokens":150000}' | ConvertFrom-Json
    Assert-That ((Test-ContextHandoffClaim -Handoff $edge).Valid) 'exactly the minimum must pass'
    $big = '{"id":"S1","tokens":"310,000","boundary":"x"}' | ConvertFrom-Json
    $verdict = Test-ContextHandoffClaim -Handoff $big
    Assert-That ($verdict.Valid -and $verdict.Tokens -eq 310000 -and $verdict.Reason -eq '') 'a large figure written as text must pass'
    Assert-That (-not (Test-ContextHandoffClaim -Handoff $null).Valid) 'a $null marker must be refused'
    Assert-That ((Test-ContextHandoffClaim -Handoff $zero -MinTokens 0).Valid) 'the minimum is a parameter'
}
Run-Case '3. the runner loads the library, judges the marker before the outcome and says why it refused' {
    $runner = Get-Content -LiteralPath (Join-Path $root 'batch\run-spec-queue.ps1') -Raw
    Assert-That ($runner -match '(?m)^\. \(Join-Path \$PSScriptRoot ''_context-handoff\.ps1''\)') 'the runner does not dot-source _context-handoff.ps1'
    $judged = $runner.IndexOf('Test-ContextHandoffClaim -Handoff $handoff')
    $outcomeSet = $runner.IndexOf("`$outcome = 'context-handoff'")
    Assert-That ($judged -gt 0 -and $outcomeSet -gt $judged) 'the marker must be judged before it can set the outcome'
    Assert-That ($runner -match 'not a handoff: no relaunch') 'a refused marker is not reported on the console'
}
Run-Case '4. the spec-to-audit skill names the same minimum' {
    $skill = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\..\skills\spec-to-audit\SKILL.md') -Raw
    Assert-That ($skill -match "(?s)Context handoff for in-progress work.*?$min tokens") "the skill does not state $min tokens"
    Assert-That ($skill -notmatch 'upon approaching turn or context limits') 'the skill still lets a pass hand off at a turn limit'
}
Write-Host ''
Write-Host ("context-handoff: {0} case(s), {1} passed, {2} failed, {3} s" -f $run, $passed, $failed, [math]::Round($clock.Elapsed.TotalSeconds, 1))
if ($failed -gt 0) { exit 1 }
exit 0
