#requires -Version 7.0
<#
.SYNOPSIS
    Fast targeted tests for S0041 (robot pass model and cost):

      1. -ModelPolicy shape routes an ungraded ticket (no line, no spec file wording, unrecognised
         value) to the default model - sonnet - and a declared level to its configured model;
         always-strong and cheap statuses keep their answers.
      2. Both readers of the `**Complexity:**` line agree on the same inputs, including the capture
         placeholder (recognised medium, still the capture default).
      3. The child's effort comes from runner.effortByModel (haiku xhigh, sonnet xhigh, opus medium),
         with the agent record's own effort winning over the map and an instance map overriding the
         shared one; a model outside the map launches with no --effort.
      4. The S0041 context trial (SZA_PQ_TRIAL_CONTEXT=1) adds --strict-mcp-config (+ the repository's
         .mcp.json), --disallowedTools and FORCE_PROMPT_CACHING_5M=1 to a Claude-shaped child only;
         disabled, it adds nothing.
      5. pq doctor lists the workable tickets with no recognised level and excludes closed, blocked
         and declared tickets, without changing any ticket.

    Scratch projects are built with the scaffold, the runner is launched against a fake CLI whose
    --help lists the flags the real one does, and every assertion reads the run journal or the args
    the fake child recorded. Nothing here talks to a real model.
#>
[CmdletBinding()]
param([switch]$KeepScratch)

$ErrorActionPreference = 'Stop'
$SourceRoot = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent)
$harness = Join-Path $SourceRoot 'tools/harness'
$batch = Join-Path $harness 'batch/run-spec-queue.ps1'
$pq = Join-Path $harness 'portfolio/pq.ps1'

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

$scratch = Join-Path ([System.IO.Path]::GetTempPath()) ('s0041-test-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $scratch | Out-Null
$savedRoot = $env:SZA_PROJECT_ROOT
$savedProfile = $env:SZA_PROFILE_PATH
$env:SZA_PROFILE_PATH = $null

# The fake CLI answers --help with the flags the real Claude CLI lists for the mechanisms under test,
# then runs the recording child with the vector it was given.
$fakeCli = @'
@echo off
if "%~1"=="--help" (
  echo   --session-id ^<uuid^>                 Use a specific session ID
  echo   --strict-mcp-config                 Only use MCP servers from --mcp-config
  echo   --disallowedTools, --disallowed-tools ^<tools...^>
  exit /b 0
)
pwsh -NoProfile -File "%~dp0fake-child.ps1" %*
exit /b %ERRORLEVEL%
'@

# The fake child records the vector and the trial environment, then exits. It moves nothing: the
# routing assertions read the journal row, not the ticket's progress.
$fakeChild = @'
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSCommandPath
$env:SZA_PROJECT_ROOT = $root
$text = $args -join ' '
$id = [regex]::Match($text, 'S\d{4}').Value
Add-Content (Join-Path $root 'children.log') ("$id|args=$text|caching=$env:FORCE_PROMPT_CACHING_5M")
exit 0
'@

# The shipped default template shape, as the profile ships it since HARNESS-PROFILE 0.16.
$defaultTemplate = @('-p', '{prompt}', '--permission-mode', '{permissionMode}', '--model', '{model}', '--effort', '{effort}')

function New-TestProject([string]$Name, [switch]$WithMcp) {
    $root = Join-Path $scratch $Name
    New-Item -ItemType Directory -Path $root | Out-Null
    $env:SZA_PROJECT_ROOT = $root
    & pwsh -NoProfile -File (Join-Path $harness 'scaffold/init-task-flow.ps1') -Root $root | Out-Null
    # The doctor refuses a repository with no stamp before it reaches the ledger checks, so a
    # fixture carries the same minimal stamp the scaffold's consumers write (rule 42 of REPO-STAMP:
    # carrier dispatch reads it as a legacy 1.0 stamp, the doctor reads canon.version/coreDigest/model).
    @{
        canon       = @{ version = '2026.11.11.1'; coreDigest = 'sha256:fixture'; model = 'reference' }
        overlay     = @()
        ledgerShape = 'none'
        role        = 'canon-home'
    } | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $root '.sza-canon.json') -Encoding utf8
    $fakeChild.Replace('__ROOT__', $root) | Set-Content (Join-Path $root 'fake-child.ps1') -Encoding utf8
    $fakeCli | Set-Content (Join-Path $root 'claude.cmd') -Encoding ascii
    if ($WithMcp) {
        # The repository's own MCP declaration - the one configuration the trial must keep usable.
        @{ mcpServers = @{ maestro = @{ type = 'stdio'; command = 'cmd'; args = @('/c', 'maestro.bat', 'mcp') } } } |
            ConvertTo-Json -Depth 6 | Set-Content (Join-Path $root '.mcp.json') -Encoding utf8
    }
    $profilePath = Join-Path $root '.sza-profile.json'
    $doc = Get-Content $profilePath -Raw | ConvertFrom-Json -AsHashtable
    $doc.runner = @{
        command        = (Join-Path $root 'claude.cmd')
        argsTemplate   = $defaultTemplate
        promptTemplate = '/sza:spec-to-audit {id}'
        headlessMatch  = '\s-p\s'
    }
    $doc.locks = @{ agentProcessNames = @('pwsh.exe', 'pwsh') }
    $doc | ConvertTo-Json -Depth 8 | Set-Content $profilePath -Encoding utf8
    return $root
}

function Add-Ticket([string]$Project, [string]$Slug, [string]$Complexity = '') {
    $env:SZA_PROJECT_ROOT = $Project
    $args_ = @('-Slug', $Slug, '-Text', "the owner's words for $Slug")
    if ($Complexity) { $args_ += @('-Complexity', $Complexity) }
    $before = @(Get-Content (Join-Path $Project 'PLAN/spec-catalog.jsonl') -ErrorAction SilentlyContinue).Count
    & pwsh -NoProfile -File (Join-Path $harness 'spec_catalog/capture-draft.ps1') @args_ | Out-Null
    $rows = @(Get-Content (Join-Path $Project 'PLAN/spec-catalog.jsonl') | ForEach-Object { $_ | ConvertFrom-Json })
    Assert-That ($rows.Count -eq $before + 1) "capture-draft for $Slug did not add one row ($before -> $($rows.Count))"
    # The ticket just captured is the last row: ids are allocated sequentially in this process.
    return [string]($rows | Select-Object -Last 1).id
}

function Remove-ComplexityLine([string]$Project, [string]$Id) {
    $row = @(Get-Content (Join-Path $Project 'PLAN/spec-catalog.jsonl') | ForEach-Object { $_ | ConvertFrom-Json }) |
        Where-Object { $_.id -eq $Id } | Select-Object -First 1
    $spec = Join-Path $Project $row.file
    $text = [IO.File]::ReadAllText($spec)
    $stripped = ($text -replace '(?m)^\*\*Complexity:\*\*[^\r\n]*\r?\n', '')
    Assert-That ($stripped -ne $text) "$Id still carries a Complexity line after the strip"
    [IO.File]::WriteAllText($spec, $stripped, [Text.UTF8Encoding]::new($false))
}

function Set-ComplexityLine([string]$Project, [string]$Id, [string]$Value) {
    $row = @(Get-Content (Join-Path $Project 'PLAN/spec-catalog.jsonl') | ForEach-Object { $_ | ConvertFrom-Json }) |
        Where-Object { $_.id -eq $Id } | Select-Object -First 1
    $spec = Join-Path $Project $row.file
    $text = [IO.File]::ReadAllText($spec)
    [IO.File]::WriteAllText($spec, ($text -replace '(?m)^\*\*Complexity:\*\*[^\r\n]*', "**Complexity:** $Value"), [Text.UTF8Encoding]::new($false))
}

function Move-Ticket([string]$Project, [string]$Id, [string]$Status, [string]$Note = '') {
    $env:SZA_PROJECT_ROOT = $Project
    $args_ = @('-Id', $Id, '-Status', $Status)
    if ($Note) { $args_ += @('-StatusNote', $Note) }
    $r = & pwsh -NoProfile -File (Join-Path $harness 'spec_catalog/update.ps1') @args_ 2>&1 | Out-String
    Assert-That ($LASTEXITCODE -eq 0) "update $Id -> $Status exited $($LASTEXITCODE): $r"
}

function Invoke-Runner([string]$Project, [string[]]$Ids, [string[]]$RunnerArgs = @(), [hashtable]$Environment = @{}) {
    $psi = [System.Diagnostics.ProcessStartInfo]::new((Get-Command pwsh -CommandType Application | Select-Object -First 1).Source)
    foreach ($a in (@('-NoProfile', '-File', $batch, '-RepoRoot', $Project, '-Ids', ($Ids -join ','), '-MaxTickets', $Ids.Count,
            '-TimeoutMinutes', '2', '-ClaimGraceSeconds', '0') + $RunnerArgs)) { $psi.ArgumentList.Add($a) }
    $psi.WorkingDirectory = $Project
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.Environment['SZA_PROJECT_ROOT'] = $Project
    foreach ($k in $Environment.Keys) { $psi.Environment[$k] = $Environment[$k] }
    $proc = [System.Diagnostics.Process]::Start($psi)
    $out = $proc.StandardOutput.ReadToEndAsync()
    $err = $proc.StandardError.ReadToEndAsync()
    if (-not $proc.WaitForExit(180000)) { & taskkill.exe /PID $proc.Id /T /F 2>&1 | Out-Null; throw 'the runner did not finish in 180 s' }
    [void]$out.Wait(15000); [void]$err.Wait(15000)
    [pscustomobject]@{ code = $proc.ExitCode; output = ($out.Result + $err.Result) }
}

function Get-RunRows([string]$Project, [string]$Instance = 'a') {
    $file = Join-Path $Project "temp/spec-queue/runs-$Instance.jsonl"
    Assert-That (Test-Path -LiteralPath $file) "runs-$Instance.jsonl was not written in $Project"
    @(Get-Content -LiteralPath $file | ForEach-Object { $_ | ConvertFrom-Json })
}

function Get-ChildArgs([string]$Project, [string]$Id) {
    $log = Join-Path $Project 'children.log'
    Assert-That (Test-Path -LiteralPath $log) "children.log was not written in $Project"
    $rows = @(Get-Content -LiteralPath $log | Where-Object { $_ -like "$id|*" })
    Assert-That ($rows.Count -ge 1) "no child record for ${Id}: $($rows.Count)"
    $f = $rows[0].Split('|', 3)
    [pscustomobject]@{ id = $f[0]; args = $f[1].Substring('args='.Length); caching = $f[2].Substring('caching='.Length) }
}

try {
    # =============================================================================================
    # A. Shape routing with absent, unrecognised, placeholder and declared complexity, and the
    #    effort each launch carries (one runner run over the whole fixture set).
    # =============================================================================================
    $script:routingProject = ''
    $script:fixtures = $null
    Test-Case 'shape routes ungraded tickets to the default and declared levels to their model' {
        $script:routingProject = New-TestProject 'p-routing'
        $ids = @{}
        $ids.noLine = Add-Ticket $script:routingProject 'task-noline'
        $ids.unrecognised = Add-Ticket $script:routingProject 'task-unrecognised'
        $ids.light = Add-Ticket $script:routingProject 'task-light' -Complexity 'light - one string'
        $ids.hard = Add-Ticket $script:routingProject 'task-hard' -Complexity 'hard - a new subsystem'
        $ids.cheap = Add-Ticket $script:routingProject 'task-cheap'
        $ids.alwaysStrong = Add-Ticket $script:routingProject 'task-blockq'
        $ids.placeholder = Add-Ticket $script:routingProject 'task-placeholder'
        Remove-ComplexityLine $script:routingProject $ids.noLine
        Set-ComplexityLine $script:routingProject $ids.unrecognised 'Complex (a Stage 0 rung)'
        Remove-ComplexityLine $script:routingProject $ids.cheap
        Remove-ComplexityLine $script:routingProject $ids.alwaysStrong
        Move-Ticket $script:routingProject $ids.cheap 'Implemented'
        Move-Ticket $script:routingProject $ids.alwaysStrong 'BlockQuestions' -Note 'Q: which answers does this ticket wait for?'
        $script:fixtures = $ids

        $r = Invoke-Runner $script:routingProject @($ids.Values) @('-ModelPolicy', 'shape')
        Assert-That ($r.code -eq 0) "the runner exited $($r.code): $($r.output)"

        $rows = Get-RunRows $script:routingProject
        $byId = @{}
        foreach ($row in $rows) { $byId[[string]$row.id] = $row }
        Assert-That ($byId[$ids.noLine].model -eq 'sonnet') "no line -> '$($byId[$ids.noLine].model)', not the default sonnet"
        Assert-That ($byId[$ids.noLine].complexity -eq '') "no line recorded complexity '$($byId[$ids.noLine].complexity)'"
        Assert-That ($byId[$ids.unrecognised].model -eq 'sonnet') "unrecognised value -> '$($byId[$ids.unrecognised].model)', not the default sonnet"
        Assert-That ($byId[$ids.unrecognised].complexity -eq '') 'an unrecognised value was recorded as a level'
        Assert-That ($byId[$ids.placeholder].model -eq 'sonnet') 'the capture placeholder routed away from medium'
        Assert-That ($byId[$ids.placeholder].complexity -eq 'medium') "the placeholder was read as '$($byId[$ids.placeholder].complexity)'"
        Assert-That ($byId[$ids.light].model -eq 'haiku') "light -> '$($byId[$ids.light].model)'"
        Assert-That ($byId[$ids.hard].model -eq 'opus') "hard -> '$($byId[$ids.hard].model)'"
        Assert-That ($byId[$ids.cheap].model -eq 'sonnet') "Implemented with no line -> '$($byId[$ids.cheap].model)', not the cheap model"
        Assert-That ($byId[$ids.alwaysStrong].model -eq 'opus') "BlockQuestions with no line -> '$($byId[$ids.alwaysStrong].model)', not the always-strong model"
        foreach ($row in @($rows)) { Assert-That ($row.policy -eq 'shape') "row $($row.id) names policy '$($row.policy)'" }
    }

    Test-Case 'the child vector carries the model and the map effort, and the args match the journal' {
        Assert-That ($null -ne $script:fixtures) 'the routing fixture did not run'
        $byArgs = @{}
        foreach ($id in @($script:fixtures.Values)) { $byArgs[$id] = Get-ChildArgs $script:routingProject $id }
        $expected = @(
            @{ id = $script:fixtures.noLine; model = 'sonnet'; effort = 'xhigh' },
            @{ id = $script:fixtures.unrecognised; model = 'sonnet'; effort = 'xhigh' },
            @{ id = $script:fixtures.placeholder; model = 'sonnet'; effort = 'xhigh' },
            @{ id = $script:fixtures.light; model = 'haiku'; effort = 'xhigh' },
            @{ id = $script:fixtures.hard; model = 'opus'; effort = 'medium' },
            @{ id = $script:fixtures.cheap; model = 'sonnet'; effort = 'xhigh' },
            @{ id = $script:fixtures.alwaysStrong; model = 'opus'; effort = 'medium' }
        )
        foreach ($e in $expected) {
            $a = $byArgs[$e.id]
            Assert-That ($a.args -match "--model $($e.model) ") "$($e.id) launched without --model $($e.model): $($a.args)"
            Assert-That ($a.args -match "--effort $($e.effort)(\s|$)") "$($e.id) launched without --effort $($e.effort): $($a.args)"
            Assert-That ($a.caching -eq '') "$($e.id) got FORCE_PROMPT_CACHING_5M with the trial off"
        }
        $noLine = $byArgs[$script:fixtures.noLine]
        Assert-That ($noLine.args -match 'Before other ticket work, research the ticket') 'the ungraded pass was not asked to assess complexity first'
        Assert-That ($byArgs[$script:fixtures.unrecognised].args -match 'Before other ticket work, research the ticket') 'the unrecognised pass was not asked to assess complexity first'
        Assert-That ($byArgs[$script:fixtures.light].args -notmatch 'Before other ticket work, research the ticket') 'a declared ticket was asked for an initial assessment'
        Assert-That ($noLine.args -notmatch '--strict-mcp-config') 'the trial flag appeared with the trial off'
        Assert-That ($noLine.args -notmatch '--disallowedTools') 'the disallowed tools appeared with the trial off'
        Assert-That ($noLine.args -notmatch '--mcp-config') 'an MCP flag appeared with the trial off'
    }

    # =============================================================================================
    # B. The two readers agree, and the capture placeholder keeps its separate answer.
    # =============================================================================================
    Test-Case 'both complexity readers agree on the same recognised, missing and unrecognised inputs' {
        Assert-That ($null -ne $script:routingProject) 'the routing fixture did not run'
        . (Join-Path $harness 'portfolio/lib/paths.ps1')
        . (Join-Path $harness 'portfolio/lib/registry.ps1')
        . (Join-Path $harness 'portfolio/lib/ledger-watch.ps1')
        . (Join-Path $harness 'portfolio/lib/agents.ps1')

        $rows = Get-RunRows $script:routingProject
        $expected = @{}
        foreach ($row in $rows) { $expected[[string]$row.id] = [string]$row.complexity }
        foreach ($id in @($script:fixtures.noLine, $script:fixtures.unrecognised, $script:fixtures.placeholder, $script:fixtures.light, $script:fixtures.hard, $script:fixtures.cheap)) {
            $info = Get-PqTicketLevelInfo -RepoPath $script:routingProject -TicketId $id
            Assert-That ($info.level -eq $expected[$id]) "the readers disagree on ${id}: portfolio '$($info.level)' vs journal '$($expected[$id])'"
        }
        $none = Get-PqTicketLevelInfo -RepoPath $script:routingProject -TicketId $script:fixtures.noLine
        Assert-That ($none.why -eq 'noLine' -and -not $none.captureDefault) "no line answered why=$($none.why)"
        $unrec = Get-PqTicketLevelInfo -RepoPath $script:routingProject -TicketId $script:fixtures.unrecognised
        Assert-That ($unrec.why -eq 'unrecognised') "an unrecognised value answered why=$($unrec.why)"
        $ph = Get-PqTicketLevelInfo -RepoPath $script:routingProject -TicketId $script:fixtures.placeholder
        Assert-That ($ph.level -eq 'medium' -and $ph.captureDefault) 'the capture placeholder is not reported as the capture default'
        $light = Get-PqTicketLevelInfo -RepoPath $script:routingProject -TicketId $script:fixtures.light
        Assert-That ($light.why -eq 'declared' -and -not $light.captureDefault) "a declared level answered why=$($light.why)"
        $missing = Get-PqTicketLevelInfo -RepoPath $script:routingProject -TicketId 'S9999'
        Assert-That ($missing.level -eq '' -and $missing.why -eq 'noFile') "an unknown ticket answered level=$($missing.level) why=$($missing.why)"
    }

    # =============================================================================================
    # C. The effort overrides: an agent record's own effort wins, an instance map overrides the map.
    # =============================================================================================
    Test-Case 'an explicit agent-record effort wins over the map, and an instance map overrides the shared one' {
        $p = New-TestProject 'p-effort'
        $id = Add-Ticket $p 'task-effort'
        $id2 = Add-Ticket $p 'task-effort-instance'
        Remove-ComplexityLine $p $id
        Remove-ComplexityLine $p $id2
        $docPath = Join-Path $p '.sza-profile.json'
        $doc = Get-Content $docPath -Raw | ConvertFrom-Json -AsHashtable
        $doc.runner.instances = @{ b = @{ effortByModel = @{ sonnet = 'low' } } }
        $doc | ConvertTo-Json -Depth 8 | Set-Content $docPath -Encoding utf8

        # The record names its own effort (rule 42): the map is never consulted.
        $record = [ordered]@{ name = 'claude'; command = (Join-Path $p 'claude.cmd'); argsTemplate = $defaultTemplate; effort = 'low' }
        $r = Invoke-Runner $p @($id) @('-ModelPolicy', 'fixed', '-Model', 'sonnet', '-AgentJson', ($record | ConvertTo-Json -Compress -Depth 8))
        Assert-That ($r.code -eq 0) "the record run exited $($r.code): $($r.output)"
        $a = Get-ChildArgs $p $id
        Assert-That ($a.args -match '--effort low') "the record's effort did not win: $($a.args)"
        Assert-That ($a.args -match '--model sonnet') "the fixed model did not reach the vector: $($a.args)"

        # Instance b's own map overrides the shipped one for the same model; instance a still gets xhigh.
        # Instance b's own map overrides the shipped one for the same model; the policy is the
        # portfolio's shape, so the ungraded fixture launches sonnet there.
        $r = Invoke-Runner $p @($id2) @('-Instance', 'b', '-ModelPolicy', 'shape')
        Assert-That ($r.code -eq 0) "the instance run exited $($r.code): $($r.output)"
        $rows = Get-RunRows $p 'b'
        Assert-That ($rows.Count -ge 1 -and $rows[0].model -eq 'sonnet') "instance b launched '$($rows[0].model)'"
        $b = @(Get-Content (Join-Path $p 'children.log') | Where-Object { $_ -like "$id2|*" })[-1].Split('|', 3)
        Assert-That ($b[1].Substring('args='.Length) -match '--effort low') "the instance map did not win: $($b[1])"
    }

    # =============================================================================================
    # D. The context trial: on, the three controls land on the Claude-shaped child; off, none do.
    # =============================================================================================
    Test-Case 'trial on: strict MCP with the repository .mcp.json, the disallowed tools and the caching env' {
        $p = New-TestProject 'p-trial-on' -WithMcp
        $id = Add-Ticket $p 'task-trial'
        Remove-ComplexityLine $p $id
        $r = Invoke-Runner $p @($id) @('-ModelPolicy', 'shape') @{ SZA_PQ_TRIAL_CONTEXT = '1' }
        Assert-That ($r.code -eq 0) "the runner exited $($r.code): $($r.output)"
        $a = Get-ChildArgs $p $id
        Assert-That ($a.args -match '--strict-mcp-config') "no --strict-mcp-config: $($a.args)"
        $mcpPath = [regex]::Escape((Join-Path $p '.mcp.json'))
        Assert-That ($a.args -match "--mcp-config $mcpPath") "the repository's .mcp.json was not passed: $($a.args)"
        Assert-That ($a.args -match '--disallowedTools Workflow ScheduleWakeup ReportFindings') "the named tools are missing: $($a.args)"
        Assert-That ($a.caching -eq '1') "FORCE_PROMPT_CACHING_5M did not reach the child's environment: '$($a.caching)'"
        Assert-That ($a.args -match '--model sonnet --effort xhigh') "the permanent routing changed with the trial: $($a.args)"
    }

    Test-Case 'trial off: the launch carries none of the three controls' {
        $p = New-TestProject 'p-trial-off'
        $id = Add-Ticket $p 'task-notrial'
        Remove-ComplexityLine $p $id
        $r = Invoke-Runner $p @($id) @('-ModelPolicy', 'shape')
        Assert-That ($r.code -eq 0) "the runner exited $($r.code): $($r.output)"
        $a = Get-ChildArgs $p $id
        foreach ($flag in '--strict-mcp-config', '--mcp-config', '--disallowedTools') {
            Assert-That ($a.args -notmatch [regex]::Escape($flag)) "$flag appeared with the trial off: $($a.args)"
        }
        Assert-That ($a.caching -eq '') "the caching variable reached the child with the trial off: '$($a.caching)'"
    }

    Test-Case 'trial on does not alter another provider using the Claude CLI' {
        $p = New-TestProject 'p-trial-other-provider' -WithMcp
        $id = Add-Ticket $p 'task-other-provider'
        $record = [ordered]@{ name = 'zai'; command = (Join-Path $p 'claude.cmd'); argsTemplate = $defaultTemplate; effort = 'low' }
        $r = Invoke-Runner $p @($id) @('-ModelPolicy', 'fixed', '-Model', 'sonnet', '-AgentJson', ($record | ConvertTo-Json -Compress -Depth 8)) @{ SZA_PQ_TRIAL_CONTEXT = '1' }
        Assert-That ($r.code -eq 0) "the runner exited $($r.code): $($r.output)"
        $a = Get-ChildArgs $p $id
        Assert-That ($a.args -notmatch '--strict-mcp-config|--disallowedTools|--mcp-config') "trial flags reached another provider: $($a.args)"
        Assert-That ($a.caching -eq '') 'trial caching reached another provider'
        Assert-That ($a.args -match '--effort low') "the provider's effort changed: $($a.args)"
    }

    Test-Case 'the default and tiered policies keep their meanings' {
        $p = New-TestProject 'p-policies'
        $id = Add-Ticket $p 'task-policy'
        $dry = Invoke-Runner $p @($id) @('-DryRun', '-ModelPolicy', 'default')
        Assert-That ($dry.code -eq 0) "the default-policy dry run exited $($dry.code): $($dry.output)"
        Assert-That ($dry.output -match '-> model\s*[\r\n]') "the default policy chose a model: $($dry.output)"
        $dry = Invoke-Runner $p @($id) @('-DryRun', '-ModelPolicy', 'tiered')
        Assert-That ($dry.code -eq 0) "the tiered dry run exited $($dry.code): $($dry.output)"
        Assert-That ($dry.output -match '-> model opus\s*[\r\n]') "the tiered policy did not keep opus for a decision status: $($dry.output)"
    }

    # =============================================================================================
    # E. The doctor: names the workable tickets with no recognised level, excludes the rest,
    #    and changes nothing.
    # =============================================================================================
    Test-Case 'the doctor lists the ungraded workable tickets and excludes closed, blocked and declared ones' {
        Assert-That ($null -ne $script:routingProject) 'the routing fixture did not run'
        # The archive fixture: one closed ticket the check must exclude.
        $archived = Add-Ticket $script:routingProject 'task-archived'
        Remove-ComplexityLine $script:routingProject $archived
        $env:SZA_PROJECT_ROOT = $script:routingProject
        $ar = & pwsh -NoProfile -File (Join-Path $harness 'spec_catalog/archive.ps1') -Id $archived -AllowMissingArtefact 2>&1 | Out-String
        Assert-That ($LASTEXITCODE -eq 0) "archive $archived exited $($LASTEXITCODE): $ar"
        $extra = @()
        foreach ($n in 1..9) {
            $extraId = Add-Ticket $script:routingProject "task-extra-$n"
            Remove-ComplexityLine $script:routingProject $extraId
            $extra += $extraId
        }

        $ledgerBefore = (Get-Content (Join-Path $script:routingProject 'PLAN/spec-catalog.jsonl') -Raw) +
            (Get-Content (Join-Path $script:routingProject 'PLAN/spec-catalog-archive.jsonl') -Raw)

        $portfolioRoot = Join-Path $scratch 'portfolio-root'
        New-Item -ItemType Directory (Join-Path $portfolioRoot 'log') -Force | Out-Null
        @{ repos = @(@{ key = 'fixture'; path = $script:routingProject; enabled = $true }) } |
            ConvertTo-Json -Depth 6 | Set-Content (Join-Path $portfolioRoot 'repos.json') -Encoding utf8

        $psi = [System.Diagnostics.ProcessStartInfo]::new((Get-Command pwsh -CommandType Application | Select-Object -First 1).Source)
        foreach ($a in @('-NoProfile', '-File', $pq, 'doctor')) { $psi.ArgumentList.Add($a) }
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.Environment['SZA_PORTFOLIO_ROOT'] = $portfolioRoot
        $proc = [System.Diagnostics.Process]::Start($psi)
        $out = $proc.StandardOutput.ReadToEndAsync(); $err = $proc.StandardError.ReadToEndAsync()
        if (-not $proc.WaitForExit(180000)) { & taskkill.exe /PID $proc.Id /T /F 2>&1 | Out-Null; throw 'the doctor did not finish in 180 s' }
        [void]$out.Wait(15000); [void]$err.Wait(15000)
        $doctorOutput = $out.Result + $err.Result
        Assert-That ($proc.ExitCode -eq 0) "the doctor exited $($proc.ExitCode): $doctorOutput"

        $line = @($doctorOutput -split '\r?\n' | Where-Object { $_ -match ' complexity - ' })
        Assert-That ($line.Count -eq 1) "expected one complexity line, got $($line.Count): $($line -join ' | ')"
        Assert-That ($line[0] -match '^WARN fixture complexity - no recognised level: ') "the line is not a warning with the list: $($line[0])"
        Assert-That ($line[0] -like "*$($script:fixtures.noLine) (noLine)*") "the no-line ticket is not named: $($line[0])"
        Assert-That ($line[0] -like "*$($script:fixtures.unrecognised) (unrecognised)*") "the unrecognised ticket is not named: $($line[0])"
        Assert-That ($line[0] -like "*$($script:fixtures.cheap) (noLine)*") "the Implemented ticket is not named: $($line[0])"
        foreach ($extraId in $extra) { Assert-That ($line[0] -like "*$extraId (noLine)*") "$extraId is missing from the full list" }
        # BlockQuestions is blocked and never reaches a routing decision (always-strong outranks the
        # level), so it is excluded like every other Block* status - the runner still launches it on
        # opus, which is what the always-strong test above verifies.
        Assert-That ($line[0] -notlike "*$($script:fixtures.alwaysStrong)*") 'a blocked ticket is named'
        Assert-That ($line[0] -notlike "*$($script:fixtures.light)*") 'a declared ticket is named'
        Assert-That ($line[0] -notlike "*$($script:fixtures.hard)*") 'a declared ticket is named'
        Assert-That ($line[0] -notlike "*$archived*") 'an archived ticket is named'
        Assert-That ($line[0] -notlike "*$($script:fixtures.placeholder)*") 'the capture-default ticket is in the list, not beside it'
        Assert-That ($line[0] -match '; 1 at the capture default') 'the capture-default count is missing'
        Assert-That ($line[0] -match '- 12 of 15 workable') "the counts are wrong: $($line[0])"

        $ledgerAfter = (Get-Content (Join-Path $script:routingProject 'PLAN/spec-catalog.jsonl') -Raw) +
            (Get-Content (Join-Path $script:routingProject 'PLAN/spec-catalog-archive.jsonl') -Raw)
        Assert-That ($ledgerBefore -ceq $ledgerAfter) 'the doctor changed a ticket'
    }
} finally {
    $env:SZA_PROJECT_ROOT = $savedRoot
    $env:SZA_PROFILE_PATH = $savedProfile
    if (-not $KeepScratch -and (Test-Path $scratch)) {
        Remove-Item -Path $scratch -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ''
Write-Host "Cases: $run | Passed: $passed | Failed: $failed"
if ($failed -gt 0) { exit 1 } else { exit 0 }
