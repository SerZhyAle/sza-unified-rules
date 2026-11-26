<#
    Exercises the managed robot prompt and pre/post bookkeeping with a fixture catalog,
    a real ticket lease, a development log, and a post-close hook.
#>
[CmdletBinding()]
param([switch]$KeepScratch)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$harness = Join-Path $repo 'tools/harness'
$scratchRoot = [IO.Path]::GetFullPath((Join-Path $repo 'temp/CANONR-0205'))
$fixture = Join-Path $scratchRoot ([guid]::NewGuid().ToString('N'))
$id = 'S0001'
$spec = 'PLAN/S0001_fixture.md'
$catalog = 'PLAN/spec-catalog.jsonl'
$session = [guid]::NewGuid().ToString()

function Assert-That([bool]$Condition, [string]$Expectation) {
    if (-not $Condition) { throw $Expectation }
}

$priorRoot = $env:SZA_PROJECT_ROOT
$priorAgent = $env:SZA_AGENT_ID
[void][IO.Directory]::CreateDirectory((Join-Path $fixture 'PLAN'))
Push-Location -LiteralPath $fixture
try {
    $env:SZA_PROJECT_ROOT = $fixture
    $env:SZA_AGENT_ID = $session
    . (Join-Path $harness '_profile.ps1')
    . (Join-Path $harness 'batch/_pass-bookkeeping.ps1')
    git init -q
    if ($LASTEXITCODE -ne 0) { throw 'Could not initialize fixture repository.' }
    @'
{"hooks":{"postClose":[{"script":"hook.ps1"}]}}
'@ | Set-Content -LiteralPath '.sza-profile.json'
    'Add-Content -LiteralPath hook-runs.txt -Value ran' | Set-Content -LiteralPath 'hook.ps1'
    "# $id fixture`n`n**Status:** In Progress" | Set-Content -LiteralPath $spec
    $row = [ordered]@{
        id = $id; name = 'fixture'; status = 'In Progress'; priority = 50
        file = $spec; created = '2026-11-26'; updated = '2026-11-26 00:00'
    }
    $row | ConvertTo-Json -Compress | Set-Content -LiteralPath $catalog
    $leaseScript = Get-SzaHarnessScript 'locks/ticket-lease.ps1'
    $claim = & $leaseScript -Verb Claim -Id $id -Reason 'run-spec-queue fixture' -Json | ConvertFrom-Json
    Assert-That ($LASTEXITCODE -eq 0 -and $claim.sessionId -eq $session) 'Expected the lease to be owned by the child identity.'
    $reservation = @{ session_id = $session; handoff_path = $claim.handoffPath }

    $template = (Resolve-SzaPromptTemplate -Template '').template
    $skill = Get-ManagedPassSkill $template
    Assert-That ($skill -eq 'spec-to-audit') 'Expected the default to use managed bookkeeping.'
    $filePrompt = 'You have no slash commands. Open the file skills/spec-to-audit/SKILL.md and follow its instructions exactly, as the command /sza:spec-to-audit would, with this argument string: S0001'
    Assert-That ((Get-ManagedPassSkill $filePrompt) -eq $skill) 'Expected the no-slash prompt to use the same workflow.'
    Assert-That (-not (Get-ManagedPassSkill '/spec-all -m {id}')) 'Expected a custom command to retain its own workflow.'
    $pass = Initialize-PassBookkeeping -Id $id -Root $fixture -TempDir (Join-Path $fixture 'temp')
    $context = Get-Content -Raw -LiteralPath $pass.preamble
    Assert-That ($context -match 'status:\s+In Progress' -and $context.Contains($spec)) 'Expected a prepared status and spec path.'
    Assert-That ($context -match 'lease:\s+not requested' -and $context -notmatch 'registry -') 'Expected no redundant claim or registry call.'
    $prompt = Add-PassBookkeepingPrompt -Prompt $template -Skill $skill -Pass $pass
    Assert-That ($prompt.Contains($pass.preamble) -and $prompt.Contains($pass.result) -and
        $prompt -match 'only if the ticket changes files under docs/' -and
        $prompt -notmatch 'ticket-lease|spec-preamble|close-and-log|ListVocabulary|document-registry skill') 'Expected handoff paths and only a conditional registry instruction.'
    Write-Host 'PASS prepared context, claim ownership, and robot prompt'

    $result = Join-Path $fixture $pass.result
    Assert-That ((Complete-PassBookkeeping -Id $id -StatusBefore 'In Progress' -Record $row -ResultPath $result) -eq 0) 'Expected a no-op for equal statuses.'
    Assert-That (-not (Test-Path -LiteralPath 'hook-runs.txt')) 'Expected no closure hook on an unchanged status.'
    $row.status = 'Partial'
    $row.file = 'PLAN/S0001_relocated.md'
    Move-Item -LiteralPath $spec -Destination $row.file
    "# $id fixture`n`n**Status:** Partial" | Set-Content -LiteralPath $row.file
    $row | ConvertTo-Json -Compress | Set-Content -LiteralPath $catalog
    @{ summary = 'Preserve the changed file context'; files = @('src/fixture.ps1', 'src/second.ps1') } | ConvertTo-Json | Set-Content -LiteralPath $result
    $before = Get-Content -LiteralPath $catalog -Raw
    Assert-That ((Complete-PassBookkeeping -Id $id -StatusBefore 'In Progress' -Record $row -ResultPath $result) -eq 0) 'Expected post-status bookkeeping to succeed.'
    Assert-That ((Get-Content -LiteralPath $catalog -Raw) -ceq $before) 'Expected post-status work to leave catalog bytes unchanged.'
    $log = Get-Content -LiteralPath 'dev/CHANGELOG.md' -Raw
    Assert-That ($log.Contains('src/fixture.ps1') -and $log.Contains('src/second.ps1') -and $log.Contains($row.file)) 'Expected both changed paths and the relocated ticket in the log.'
    Assert-That (@(Get-Content -LiteralPath 'hook-runs.txt').Count -eq 1) 'Expected exactly one post-close hook call.'
    Write-Host 'PASS post-status logging, relocated spec, and unchanged-status skip'

    '{"summary":"Bad path","files":["../outside"]}' | Set-Content -LiteralPath $result
    Assert-That ((Complete-PassBookkeeping -Id $id -StatusBefore 'In Progress' -Record $row -ResultPath $result) -eq 1) 'Expected an invalid result to be reported.'
    Assert-That (-not (Get-Content -LiteralPath 'dev/CHANGELOG.md' -Raw).Contains('Bad path')) 'Expected invalid result content to stay out of the log.'
    $leasePath = Join-Path (Get-SzaPath 'leasesDir') "$id.json"
    & $leaseScript -Verb Release -Id $id -Force -ExpectedSessionId ([guid]::NewGuid().ToString())
    Assert-That ($LASTEXITCODE -eq 4 -and (Test-Path -LiteralPath $leasePath)) 'Expected cleanup to refuse a different owner.'
    Release-PassLease -Id $id -LeaseScript $leaseScript -Reservation $reservation
    Assert-That (-not (Test-Path -LiteralPath $leasePath)) 'Expected cleanup to release the reservation after the error.'
    Write-Host 'PASS invalid result warning and owner-checked lease cleanup'
} finally {
    Pop-Location
    $env:SZA_PROJECT_ROOT = $priorRoot
    $env:SZA_AGENT_ID = $priorAgent
    if (-not $KeepScratch -and [IO.Directory]::Exists($fixture)) {
        $resolved = (Resolve-Path -LiteralPath $fixture).Path
        $prefix = $scratchRoot + [IO.Path]::DirectorySeparatorChar
        if ($resolved.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolved -Recurse -Force
        }
    }
}
