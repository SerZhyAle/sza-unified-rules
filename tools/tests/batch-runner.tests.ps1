#requires -Version 7.0
<#
    Exercise the three queue runners of TASK-FLOW (rules 21-27, 30-31) against throwaway projects, with FAKE
    children: the full batch runner (tools/harness/batch/run-spec-queue.ps1), the launcher the day-0 scaffold
    renders (r0.ps1) and, when -CatalogRoot is given, the catalog's reference R0.

    What this proves: how each runner drives a child it can start - the argument vector, the journal row, the
    drop rule, the timeout kill of the whole process tree, the stop files, the exit codes, R0's start step.
    What it does not prove: anything a real agent does. No `claude` process is ever started, no model is
    billed, so this is not the live rung of TASK-FLOW section 4 and does not certify the lifecycle.

    Rule 24 in the batch runner and the section 5 gaps G1, G3 and G6 of the harness were recorded here as
    `GAP` lines (a place where a shipped tool differs from the contract's text) until the tools changed;
    they are ordinary cases now, and a regression in any of them fails the run. The `GAP` mechanism stays
    for the next difference found: such a line never fails the run and the case flips to PASS the day the
    tool changes, so the claim cannot go stale in either direction.

    Windows only: the batch runner terminates trees with taskkill and lists agent processes through CIM.
    Takes about two minutes, almost all of it three one-minute timeouts running side by side.

    Exit codes: 0 all cases passed; 1 an assertion failed; 2 prerequisites/setup unavailable.
#>
[CmdletBinding()]
param(
    [string]$SourceRoot = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent),
    [string]$CatalogRoot,
    [switch]$KeepScratch
)

$ErrorActionPreference = 'Stop'
$run = 0
$failed = 0
$gaps = 0
$savedRoot = $env:SZA_PROJECT_ROOT
$savedProfile = $env:SZA_PROFILE_PATH
$scratch = $null
$background = [System.Collections.Generic.List[object]]::new()

function Assert-That([bool]$Condition, [string]$Reason) { if (-not $Condition) { throw $Reason } }
function Test-Case([string]$Name, [scriptblock]$Body) {
    $script:run++
    try {
        $lines = @(& $Body)
        $gap = @($lines | Where-Object { "$_".StartsWith('GAP ') })
        if ($gap.Count -gt 0) { $script:gaps++; $gap }
        else { "OK $Name" }
    }
    catch { $script:failed++; "FAIL $Name - $($_.Exception.Message)" }
}
function Write-Gap([string]$Text) { "GAP $Text" }

function Invoke-Tool([string]$Project, [string]$Script, [string[]]$ToolArgs = @()) {
    $env:SZA_PROJECT_ROOT = $Project
    $output = & pwsh -NoProfile -File (Join-Path $harness $Script) @ToolArgs 2>&1 | Out-String
    [pscustomobject]@{ code = $LASTEXITCODE; output = $output.Trim() }
}

# Start pwsh -File <script> <args> without waiting; stdout and stderr are drained so a full pipe cannot
# stall the runner. Environment is set on the child only, so concurrent projects cannot see each other.
function Start-Proc([string]$Project, [string[]]$Arguments) {
    $psi = [System.Diagnostics.ProcessStartInfo]::new((Get-Command pwsh -CommandType Application | Select-Object -First 1).Source)
    foreach ($a in (@('-NoProfile', '-File') + $Arguments)) { $psi.ArgumentList.Add($a) }
    $psi.WorkingDirectory = $Project
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.Environment['SZA_PROJECT_ROOT'] = $Project
    $proc = [System.Diagnostics.Process]::Start($psi)
    $handle = [pscustomobject]@{
        process = $proc
        out     = $proc.StandardOutput.ReadToEndAsync()
        err     = $proc.StandardError.ReadToEndAsync()
        started = Get-Date
    }
    $script:background.Add($handle)
    return $handle
}
function Wait-Proc($Handle, [int]$Seconds = 300) {
    if (-not $Handle.process.WaitForExit($Seconds * 1000)) {
        & taskkill.exe /PID $Handle.process.Id /T /F 2>&1 | Out-Null
        throw "process $($Handle.process.Id) did not finish in $Seconds s"
    }
    # A grandchild that survived a failed tree kill would hold the pipe open; do not hang on it.
    [void]$Handle.out.Wait(15000)
    [void]$Handle.err.Wait(15000)
    $text = ''
    if ($Handle.out.IsCompleted) { $text += $Handle.out.Result }
    if ($Handle.err.IsCompleted) { $text += $Handle.err.Result }
    [pscustomobject]@{ code = $Handle.process.ExitCode; output = $text; seconds = ((Get-Date) - $Handle.started).TotalSeconds }
}
function Invoke-Proc([string]$Project, [string[]]$Arguments, [int]$Seconds = 300) {
    Wait-Proc (Start-Proc $Project $Arguments) $Seconds
}

function Read-Jsonl([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    # -DateKind String: finishedAt is a contract string, and the default would turn it into a DateTime.
    @(Get-Content -LiteralPath $Path | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json -DateKind String })
}
function Get-Ledger([string]$Project) { Read-Jsonl (Join-Path $Project 'PLAN/spec-catalog.jsonl') }
function Get-Launches([string]$Project, [string]$Id) {
    $log = Join-Path $Project 'children.log'
    if (-not (Test-Path -LiteralPath $log)) { return 0 }
    @(Get-Content -LiteralPath $log | Where-Object { $_ -like "$Id *" }).Count
}

$promptShape = '{id} with spaces and "quotes" and ''apostrophes'''

# One fake child for every project; behavior.json maps a ticket id to what the child does. It records each
# launch, the argument vector it received and, once, the state of the temp directory at its first start.
$fakeChild = @'
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSCommandPath
$env:SZA_PROJECT_ROOT = $root
$arg0 = [string]$args[0]
$id = [regex]::Match($arg0, 'S\d{4}').Value
$cfg = Get-Content (Join-Path $root 'behavior.json') -Raw | ConvertFrom-Json
$act = [string]$cfg.$id
$ledger = Join-Path $root 'PLAN/spec-catalog.jsonl'
$st = [string](Get-Content $ledger | ForEach-Object { $_ | ConvertFrom-Json } | Where-Object id -eq $id).status
Add-Content (Join-Path $root 'children.log') "$id $st"
([ordered]@{ id = $id; count = $args.Count; first = $arg0 } | ConvertTo-Json -Compress) | Add-Content (Join-Path $root 'args.jsonl')
$snap = Join-Path $root 'startstate.json'
if (-not (Test-Path $snap)) {
    $t = Join-Path $root 'temp'
    ([ordered]@{
        stopFiles = @(Get-ChildItem $t -Filter 'STOP-SPEC-QUEUE*' -ErrorAction SilentlyContinue).Count
        leases    = @(Get-ChildItem (Join-Path $t 'SPEC-TICKET.LEASES') -File -ErrorAction SilentlyContinue).Count
        locks     = @(Get-ChildItem $t -Recurse -File -Filter '*.LOCK' -ErrorAction SilentlyContinue).Count
        chat      = @(Get-ChildItem (Join-Path $t 'AGENT-CHAT') -File -ErrorAction SilentlyContinue).Count
    } | ConvertTo-Json -Compress) | Set-Content $snap
}
function Step([string]$to) { & pwsh -NoProfile -File '__HARNESS__/spec_catalog/update.ps1' -Id $id -Status $to | Out-Null }
function Advance { switch ($st) { 'Draft' { Step 'In Progress' } 'In Progress' { Step 'Implemented' } } }
switch ($act) {
    'advance'      { Advance }
    'advance-fail' { Advance; exit 1 }
    'idle'         { }
    'hang' {
        if ($st -eq 'Draft') {
            Advance
            $gc = Start-Process pwsh -ArgumentList '-NoProfile', '-Command', 'Start-Sleep 600' -PassThru -WindowStyle Hidden
            "$($gc.Id)|$($gc.StartTime.Ticks)" | Set-Content (Join-Path $root 'grandchild.pid')
            Start-Sleep 600
        }
    }
    'stop-all'     { Set-Content (Join-Path $root 'temp/STOP-SPEC-QUEUE') 'stop' }
    'stop-mine'    { Set-Content (Join-Path $root ('temp/STOP-SPEC-QUEUE-' + $cfg._instance)) 'stop' }
}
exit 0
'@

function New-Project([string]$Name, [hashtable]$Behavior, [string]$Instance = 'a', [string[]]$Slugs = @('one', 'two', 'three', 'four')) {
    $root = Join-Path $scratch $Name
    New-Item -ItemType Directory -Path $root | Out-Null
    $r = Invoke-Tool $root 'scaffold/init-task-flow.ps1' @('-Root', $root)
    Assert-That ($r.code -eq 0) "scaffold failed for ${Name}: $($r.output)"
    foreach ($slug in $Slugs) {
        $c = Invoke-Tool $root 'spec_catalog/capture-draft.ps1' @('-Slug', "task-$slug", '-Text', "the owner's words for $slug")
        Assert-That ($c.code -eq 0) "capture-draft failed for ${Name}/${slug}: $($c.output)"
    }
    $Behavior['_instance'] = $Instance
    $Behavior | ConvertTo-Json | Set-Content (Join-Path $root 'behavior.json') -Encoding utf8
    $fakeChild.Replace('__HARNESS__', ($harness -replace '\\', '/')) | Set-Content (Join-Path $root 'fake-child.ps1') -Encoding utf8
    return $root
}

# The batch runner takes its child from the profile: command, argument template, prompt template, and a
# pattern that tells the project's own children from any other process - unique per project, so one
# project's -Stop -Kill cannot reach another's child.
function Set-BatchProfile([string]$Project, [string]$Command = 'pwsh') {
    $profilePath = Join-Path $Project '.sza-profile.json'
    $doc = Get-Content $profilePath -Raw | ConvertFrom-Json -AsHashtable
    $doc.runner = @{
        command        = $Command
        argsTemplate   = @('-NoProfile', '-File', (Join-Path $Project 'fake-child.ps1'), '{prompt}')
        promptTemplate = $promptShape.Replace('{id}', '{Id}')
        headlessMatch  = [regex]::Escape((Split-Path $Project -Leaf))
    }
    # -Stop, -Kill and the draining check list processes by name; the fake child is a pwsh.
    $doc.locks = @{ agentProcessNames = @('pwsh.exe', 'pwsh') }
    $doc | ConvertTo-Json -Depth 8 | Set-Content $profilePath -Encoding utf8
}

# R0 takes its child as an array, which `pwsh -File` cannot carry, so each project gets a wrapper that
# calls the launcher in-process with the fake child's vector.
function Set-R0Wrapper([string]$Project, [string]$Launcher) {
    @"
param([switch]`$DryRun, [int]`$MaxTickets = 0, [int]`$TimeoutMinutes = 1, [string]`$Command = 'pwsh', [string]`$Journal = '')
`$a = @{
    Root           = `$PSScriptRoot
    Command        = `$Command
    ChildArgs      = @('-NoProfile', '-File', (Join-Path `$PSScriptRoot 'fake-child.ps1'), '$($promptShape.Replace("'", "''"))')
    TimeoutMinutes = `$TimeoutMinutes
    MaxTickets     = `$MaxTickets
}
if (`$DryRun) { `$a.DryRun = `$true }
if (`$Journal) { `$a.Journal = `$Journal }
& '$Launcher' @a
exit `$LASTEXITCODE
"@ | Set-Content (Join-Path $Project 'invoke-r0.ps1') -Encoding utf8
}

function Set-AllParked([string]$Project) {
    foreach ($r in (Get-Ledger $Project)) {
        $u = Invoke-Tool $Project 'spec_catalog/update.ps1' @('-Id', $r.id, '-Status', 'BlockQuestions', '-StatusNote', 'parked for the fixture')
        Assert-That ($u.code -eq 0) "could not park $($r.id): $($u.output)"
    }
}

function Test-Alive([string]$PidFile) {
    if (-not (Test-Path -LiteralPath $PidFile)) { throw "grandchild pid file missing: $PidFile" }
    $parts = (Get-Content -LiteralPath $PidFile -Raw).Trim().Split('|')
    $p = Get-Process -Id ([int]$parts[0]) -ErrorAction SilentlyContinue
    return [bool]($p -and $p.StartTime.Ticks -eq [int64]$parts[1])
}

# The row contract of TASK-FLOW rule 23, read by field name.
function Assert-RunRow($Row) {
    foreach ($field in @('id', 'statusBefore', 'statusAfter', 'moved', 'outcome', 'exitCode', 'minutes', 'finishedAt')) {
        Assert-That ($Row.PSObject.Properties.Name -contains $field) "run row $($Row.id) lacks '$field'"
    }
    Assert-That ($Row.moved -is [bool]) "run row $($Row.id): moved is not a boolean"
    Assert-That ([string]$Row.finishedAt -match '^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d$') "run row $($Row.id): finishedAt '$($Row.finishedAt)' is not yyyy-MM-ddTHH:mm:ss"
}

try {
    if (-not $IsWindows) { throw 'Windows only: the runners use taskkill and CIM process listing' }
    foreach ($required in @('tools/harness/batch/run-spec-queue.ps1', 'tools/harness/scaffold/init-task-flow.ps1',
            'tools/harness/spec_catalog/capture-draft.ps1', 'tools/harness/spec_catalog/update.ps1')) {
        if (-not (Test-Path -LiteralPath (Join-Path $SourceRoot $required))) { throw "Missing prerequisite: $required" }
    }
    $harness = (Resolve-Path (Join-Path $SourceRoot 'tools/harness')).Path
    $batch = Join-Path $harness 'batch/run-spec-queue.ps1'
    $reference = $null
    if ($CatalogRoot) {
        $reference = Join-Path $CatalogRoot 'task-flow/reference/r0-runner.ps1'
        if (-not (Test-Path -LiteralPath $reference)) { throw "Missing prerequisite: $reference" }
    }
    $env:SZA_PROFILE_PATH = $null
    $scratch = Join-Path ([System.IO.Path]::GetTempPath()) ('s0012-queue-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $scratch | Out-Null

    # --- the three one-minute timeouts start first and run while the quick cases below execute --------------
    $mainBehavior = @{ S0001 = 'advance'; S0002 = 'advance-fail'; S0003 = 'idle'; S0004 = 'hang' }

    $bMain = New-Project 'b-main' $mainBehavior 'a'
    Set-BatchProfile $bMain
    $bMainRun = Start-Proc $bMain @($batch, '-TimeoutMinutes', '1', '-ClaimGraceSeconds', '3')

    $rMain = New-Project 'r-main' $mainBehavior 'mono'
    Set-R0Wrapper $rMain (Join-Path $rMain 'r0.ps1')
    # Stale state a previous run left behind: the start step must drop it before the first child (rule 31).
    New-Item -ItemType Directory -Path (Join-Path $rMain 'temp/SPEC-TICKET.LEASES') -Force | Out-Null
    Set-Content (Join-Path $rMain 'temp/SPEC-TICKET.LEASES/S0001.json') '{}'
    Set-Content (Join-Path $rMain 'temp/STOP-SPEC-QUEUE') 'stale'
    Set-Content (Join-Path $rMain 'temp/STOP-SPEC-QUEUE-mono') 'stale'
    $rDry = Invoke-Proc $rMain @((Join-Path $rMain 'invoke-r0.ps1'), '-DryRun')
    $rDryOpen = @(Get-ChildItem (Join-Path $rMain 'temp') -Filter 'STOP-SPEC-QUEUE*').Count
    $rDryLease = Test-Path (Join-Path $rMain 'temp/SPEC-TICKET.LEASES/S0001.json')
    $rMainRun = Start-Proc $rMain @((Join-Path $rMain 'invoke-r0.ps1'))

    $refRun = $null
    if ($reference) {
        $ref = New-Project 'ref-main' $mainBehavior 'mono'
        Set-R0Wrapper $ref $reference
        $refRun = Start-Proc $ref @((Join-Path $ref 'invoke-r0.ps1'))
    }

    # The kill case needs the child alive when -Stop -Kill arrives, so it is started and driven here.
    $bKill = New-Project 'b-kill' @{ S0001 = 'hang' } 'a' @('only')
    Set-BatchProfile $bKill
    $bKillRun = Start-Proc $bKill @($batch, '-TimeoutMinutes', '30', '-ClaimGraceSeconds', '3')
    $killPid = Join-Path $bKill 'grandchild.pid'
    $deadline = (Get-Date).AddSeconds(90)
    while (-not (Test-Path $killPid) -and (Get-Date) -lt $deadline -and -not $bKillRun.process.HasExited) { Start-Sleep -Milliseconds 500 }
    $killStop = $null
    if (Test-Path $killPid) { $killStop = Invoke-Proc $bKill @($batch, '-Stop', '-Kill') 120 }
    $killResult = Wait-Proc $bKillRun 120

    # --- quick cases -----------------------------------------------------------------------------------------

    Test-Case 'batch: a dry run launches nothing, writes no journal row and leaves the ledger as it was' {
        $p = New-Project 'b-dry' @{ S0001 = 'advance' } 'a' @('only')
        Set-BatchProfile $p
        $before = (Get-FileHash (Join-Path $p 'PLAN/spec-catalog.jsonl')).Hash
        $r = Invoke-Proc $p @($batch, '-DryRun')
        Assert-That ($r.code -eq 0) "dry run exit $($r.code): $($r.output)"
        Assert-That ($r.output -match 'next up: S0001') 'dry run did not name the head of the queue'
        Assert-That (-not (Test-Path (Join-Path $p 'children.log'))) 'dry run launched a child'
        Assert-That (-not (Test-Path (Join-Path $p 'temp/spec-queue/runs-a.jsonl'))) 'dry run wrote a journal row'
        Assert-That ((Get-FileHash (Join-Path $p 'PLAN/spec-catalog.jsonl')).Hash -eq $before) 'dry run changed the ledger'
    }

    Test-Case 'batch: nothing eligible at the first ranking is exit 3 and starts no child' {
        $p = New-Project 'b-none' @{ S0001 = 'advance' } 'a' @('only')
        Set-BatchProfile $p
        Set-AllParked $p
        $r = Invoke-Proc $p @($batch)
        Assert-That ($r.code -eq 3) "expected exit 3, got $($r.code): $($r.output)"
        Assert-That (-not (Test-Path (Join-Path $p 'children.log'))) 'a child was started with nothing to pick'
    }

    Test-Case 'batch: an agent command that does not exist is exit 2 and names the instance and the command' {
        $p = New-Project 'b-nocmd' @{ S0001 = 'advance' } 'a' @('only')
        Set-BatchProfile $p 'no-such-agent-cli-s0012'
        $r = Invoke-Proc $p @($batch)
        Assert-That ($r.code -eq 2) "expected exit 2, got $($r.code): $($r.output)"
        Assert-That ($r.output -match "instance 'a'" -and $r.output -match 'no-such-agent-cli-s0012') 'the refusal does not name the instance and the command'
    }

    Test-Case 'batch: a shared stop file written during a ticket ends the loop after it, stays for the siblings, and the next start clears it' {
        $p = New-Project 'b-stop' @{ S0001 = 'stop-all'; S0002 = 'idle' } 'a' @('one', 'two')
        Set-BatchProfile $p
        $first = Invoke-Proc $p @($batch, '-ClaimGraceSeconds', '3')
        Assert-That ($first.code -eq 0) "expected exit 0, got $($first.code): $($first.output)"
        Assert-That ((Get-Launches $p 'S0001') -eq 1 -and (Get-Launches $p 'S0002') -eq 0) 'the loop did not end after the ticket in hand'
        Assert-That (Test-Path (Join-Path $p 'temp/STOP-SPEC-QUEUE')) 'the shared stop file was consumed; the siblings could not see it'
        # The same child would write the stop again, so the second start gets one that only works.
        @{ S0001 = 'idle'; S0002 = 'idle'; _instance = 'a' } | ConvertTo-Json | Set-Content (Join-Path $p 'behavior.json') -Encoding utf8
        $second = Invoke-Proc $p @($batch, '-ClaimGraceSeconds', '3')
        Assert-That ($second.code -eq 0) "second start exit $($second.code): $($second.output)"
        Assert-That ($second.output -match 'clearing a stop flag left over') 'a start with no live child did not clear the stale shared stop file'
        Assert-That ((Get-Launches $p 'S0002') -eq 1) 'after the stale stop was cleared the queue did not run'
    }

    Test-Case 'batch: an instance stop file ends only that instance and is consumed' {
        $p = New-Project 'b-stop-mine' @{ S0001 = 'stop-mine'; S0002 = 'idle' } 'a' @('one', 'two')
        Set-BatchProfile $p
        $r = Invoke-Proc $p @($batch, '-ClaimGraceSeconds', '3')
        Assert-That ($r.code -eq 0) "expected exit 0, got $($r.code): $($r.output)"
        Assert-That ((Get-Launches $p 'S0001') -eq 1 -and (Get-Launches $p 'S0002') -eq 0) 'the loop did not end after the ticket in hand'
        Assert-That (-not (Test-Path (Join-Path $p 'temp/STOP-SPEC-QUEUE-a'))) 'the instance stop file was not consumed'
    }

    Test-Case 'batch: a start while a stop is still draining (a live child, the shared stop file set) is exit 3 and keeps the stop' {
        $p = New-Project 'b-drain' @{ S0001 = 'advance' } 'a' @('only')
        Set-BatchProfile $p
        $marker = Split-Path $p -Leaf
        $drainer = Start-Process pwsh -ArgumentList '-NoProfile', '-Command', "Start-Sleep 120 # $marker" -PassThru -WindowStyle Hidden
        try {
            Set-Content (Join-Path $p 'temp/STOP-SPEC-QUEUE') 'stop'
            $r = Invoke-Proc $p @($batch)
            Assert-That ($r.code -eq 3) "expected exit 3, got $($r.code): $($r.output)"
            Assert-That ($r.output -match 'a stop is in progress') 'the refusal does not say a stop is draining'
            Assert-That (Test-Path (Join-Path $p 'temp/STOP-SPEC-QUEUE')) 'the draining stop was cancelled'
            Assert-That (-not (Test-Path (Join-Path $p 'children.log'))) 'a child was started during a drain'
        } finally {
            & taskkill.exe /PID $drainer.Id /T /F 2>&1 | Out-Null
        }
    }

    Test-Case 'batch: -Stop -Kill terminates the running child with its whole tree and the runner ends exit 0' {
        Assert-That ($null -ne $killStop) 'the child never started, so -Stop -Kill had nothing to kill'
        Assert-That ($killStop.code -eq 0) "-Stop -Kill exit $($killStop.code): $($killStop.output)"
        Assert-That ($killStop.output -match '-Kill: terminating pid') '-Kill reported no victim'
        Assert-That ($killResult.code -eq 0) "runner exit $($killResult.code) after the kill: $($killResult.output)"
        Assert-That (-not (Test-Alive $killPid)) 'the grandchild survived -Stop -Kill'
        Assert-That ($killResult.seconds -lt 150) "the runner needed $([int]$killResult.seconds) s to end after the kill"
    }

    Test-Case 'R0 rendered: a dry run launches nothing and does not run the start step' {
        Assert-That ($rDry.code -eq 0) "dry run exit $($rDry.code): $($rDry.output)"
        Assert-That ($rDry.output -match 'dry run') 'dry run did not say so'
        Assert-That ($rDryOpen -eq 2 -and $rDryLease) 'the start step ran in a dry run: stale state was removed'
    }

    Test-Case 'R0 rendered: a ledger that does not exist is exit 2, a missing command is exit 2, an empty queue is exit 3' {
        $p = New-Project 'r-codes' @{ S0001 = 'advance' } 'mono' @('only')
        Set-R0Wrapper $p (Join-Path $p 'r0.ps1')
        $noLedger = Invoke-Proc $p @((Join-Path $p 'invoke-r0.ps1'), '-Journal', 'PLAN/absent.jsonl')
        Assert-That ($noLedger.code -eq 2) "no ledger: expected exit 2, got $($noLedger.code)"
        $noCmd = Invoke-Proc $p @((Join-Path $p 'invoke-r0.ps1'), '-Command', 'no-such-agent-cli-s0012')
        Assert-That ($noCmd.code -eq 2) "no command: expected exit 2, got $($noCmd.code)"
        Set-AllParked $p
        $empty = Invoke-Proc $p @((Join-Path $p 'invoke-r0.ps1'))
        Assert-That ($empty.code -eq 3) "no open ticket: expected exit 3, got $($empty.code)"
        Assert-That (-not (Test-Path (Join-Path $p 'children.log'))) 'a child was started with nothing to pick'
    }

    # --- section 5 of TASK-FLOW: the gaps found on 2026-10-07 and closed in the harness, kept as regression cases.

    Test-Case 'G1 (rule 35): the bare insert in a project with no PLAN/ directory creates its own store' {
        $bare = Join-Path $scratch 'bare-insert'
        New-Item -ItemType Directory -Path $bare | Out-Null
        '{ "version": "1", "projectName": "bare" }' | Set-Content (Join-Path $bare '.sza-profile.json') -Encoding utf8
        $r = Invoke-Tool $bare 'spec_catalog/insert.ps1' @('-Name', 'probe', '-Slug', 'probe')
        Assert-That ($r.code -eq 0) "the bare insert.ps1 exited $($r.code): $($r.output)"
        Assert-That (@(Get-Ledger $bare).Count -eq 1) 'the bare insert wrote no ledger row'
    }
    Test-Case 'G3 (rule 15): the bare queue listing in a project with no plan files lists nothing and exits 0' {
        $bare = Join-Path $scratch 'bare-list'
        New-Item -ItemType Directory -Path $bare | Out-Null
        '{ "version": "1", "projectName": "bare" }' | Set-Content (Join-Path $bare '.sza-profile.json') -Encoding utf8
        $r = Invoke-Tool $bare 'spec_catalog/release-queue.ps1' @('-List')
        Assert-That ($r.code -eq 0) "release-queue.ps1 -List exited $($r.code): $($r.output)"
        Assert-That ($r.output -match '--- 0 ticket') "the listing was not empty: $($r.output)"
        $v = Invoke-Tool $bare 'spec_catalog/release-queue.ps1' @('-Validate')
        Assert-That ($v.code -eq 2) "-Validate of a missing queue must stay 'cannot verify' (2), got $($v.code)"
    }
    Test-Case 'G6 (rule 31): a lock file and a lock-wait entry a dead session left behind are gone at R0''s start' {
        $p = New-Project 'r-locks' @{ S0001 = 'idle' } 'mono' @('only')
        Set-R0Wrapper $p (Join-Path $p 'r0.ps1')
        Set-Content (Join-Path $p 'temp/CODE.LOCK') 'left by a dead session'
        New-Item -ItemType Directory -Path (Join-Path $p 'temp/CODE.QUEUE') -Force | Out-Null
        Set-Content (Join-Path $p 'temp/CODE.QUEUE/0001__dead.json') '{}'
        $r = Invoke-Proc $p @((Join-Path $p 'invoke-r0.ps1'), '-MaxTickets', '1')
        Assert-That ($r.code -eq 0) "expected exit 0, got $($r.code): $($r.output)"
        $snap = Get-Content (Join-Path $p 'startstate.json') -Raw | ConvertFrom-Json
        Assert-That ($snap.locks -eq 0) "$($snap.locks) leftover lock file(s) were still there at the first child"
        Assert-That (-not (Test-Path (Join-Path $p 'temp/CODE.QUEUE/0001__dead.json'))) 'the lock-wait entry survived the start step'
        Assert-That ($r.output -match 'leftover lock was removed') 'the start step did not say it removed a lock'
    }

    # --- the long cases, now that their runs have had time ----------------------------------------------------

    $bResult = Wait-Proc $bMainRun
    Test-Case 'batch: the loop ends exit 0 and each journal row carries the contract fields' {
        Assert-That ($bResult.code -eq 0) "expected exit 0, got $($bResult.code): $($bResult.output)"
        $rows = Read-Jsonl (Join-Path $bMain 'temp/spec-queue/runs-a.jsonl')
        Assert-That ($rows.Count -ge 4) "only $($rows.Count) journal rows"
        $rows | ForEach-Object { Assert-RunRow $_ }
        $first = @($rows | Group-Object id | Sort-Object Name | ForEach-Object { $_.Group[0].id }) -join ','
        Assert-That ($first -eq 'S0001,S0002,S0003,S0004') "tickets journalled: $first"
    }
    Test-Case 'batch: outcomes by ticket - ok, child-failed that still moved, no progress, timeout' {
        $rows = Read-Jsonl (Join-Path $bMain 'temp/spec-queue/runs-a.jsonl')
        $by = @{}; foreach ($r in $rows) { if (-not $by.ContainsKey($r.id)) { $by[$r.id] = $r } }
        Assert-That ($by['S0001'].outcome -eq 'ok' -and $by['S0001'].moved) "S0001: $($by['S0001'].outcome) moved=$($by['S0001'].moved)"
        Assert-That ($by['S0002'].outcome -eq 'child-failed' -and $by['S0002'].moved -and $by['S0002'].exitCode -eq 1) "S0002: $($by['S0002'].outcome) moved=$($by['S0002'].moved) exit=$($by['S0002'].exitCode)"
        Assert-That ($by['S0003'].outcome -in @('no-progress', 'no-progress-or-claim-lost') -and -not $by['S0003'].moved) "S0003: $($by['S0003'].outcome) moved=$($by['S0003'].moved)"
        Assert-That ($by['S0004'].outcome -eq 'timeout') "S0004: $($by['S0004'].outcome)"
    }
    Test-Case 'batch: the queue is worked in the plan''s order and an unmoved ticket is dropped for the rest of the run' {
        $order = @(Get-Content (Join-Path $bMain 'children.log') | ForEach-Object { $_.Split(' ')[0] })
        # A ticket that moved is offered again at once, so the first launches are compared by distinct id.
        $firstSeen = @($order | Select-Object -Unique) -join ','
        Assert-That ($firstSeen -eq 'S0001,S0002,S0003,S0004') "launch order: $($order -join ',')"
        Assert-That ((Get-Launches $bMain 'S0003') -eq 1) 'an unmoved ticket was launched again in the same run'
    }
    Test-Case 'batch: the prompt reaches the child as one argument with spaces and quotes intact (rule 22)' {
        $received = Read-Jsonl (Join-Path $bMain 'args.jsonl')
        Assert-That ($received.Count -ge 4) 'the children recorded no arguments'
        foreach ($a in $received) {
            Assert-That ($a.count -eq 1) "$($a.id): the child received $($a.count) arguments"
            Assert-That ($a.first -ceq $promptShape.Replace('{id}', $a.id)) "$($a.id): the child received '$($a.first)'"
        }
    }
    Test-Case 'batch: on a timeout the child dies with its whole tree, is journalled timeout, and its partial work stays' {
        $row = Read-Jsonl (Join-Path $bMain 'temp/spec-queue/runs-a.jsonl') | Where-Object { $_.id -eq 'S0004' } | Select-Object -First 1
        Assert-That ($row.minutes -ge 1) "timeout row says $($row.minutes) min"
        Assert-That (-not (Test-Alive (Join-Path $bMain 'grandchild.pid'))) 'the grandchild survived the timeout kill'
        $status = (Get-Ledger $bMain | Where-Object { $_.id -eq 'S0004' }).status
        Assert-That ($status -eq 'In Progress') "the status the child wrote before it was killed was lost: $status"
        Assert-That ($bResult.seconds -lt 200) "the run took $([int]$bResult.seconds) s; the kill did not fire near the ceiling"
    }
    Test-Case 'batch: a child that failed but moved is offered again; the run that no longer moves it drops it (rule 24)' {
        $rows = Read-Jsonl (Join-Path $bMain 'temp/spec-queue/runs-a.jsonl')
        Assert-That ((Get-Launches $bMain 'S0001') -ge 2) 'S0001 moved (Draft to In Progress) and was not offered again'
        Assert-That ((Get-Launches $bMain 'S0002') -ge 2) 'S0002 failed but moved and was not offered again'
        $lastS2 = @($rows | Where-Object { $_.id -eq 'S0002' })[-1]
        Assert-That (-not $lastS2.moved) 'the last S0002 run still moved, so the loop ended before it was dropped'
        Assert-That ((Get-Launches $bMain 'S0003') -eq 1) 'S0003 did not move and was launched again'
    }
    Test-Case 'batch: -MaxTickets counts finished picks, a moved ticket offered again included (rule 24)' {
        $max = New-Project 'b-max' @{ S0001 = 'advance'; S0002 = 'idle' } 'a' @('one', 'two')
        Set-BatchProfile $max
        $m = Invoke-Proc $max @($batch, '-TimeoutMinutes', '1', '-ClaimGraceSeconds', '3', '-MaxTickets', '1')
        Assert-That ($m.code -eq 0) "expected exit 0, got $($m.code): $($m.output)"
        Assert-That ((Get-Launches $max 'S0001') -eq 1 -and (Get-Launches $max 'S0002') -eq 0) "-MaxTickets 1 launched S0001 $((Get-Launches $max 'S0001'))x and S0002 $((Get-Launches $max 'S0002'))x"
        Assert-That ($m.output -match 'reached -MaxTickets 1') 'the run did not say it reached -MaxTickets'
    }

    $rResult = Wait-Proc $rMainRun
    Test-Case 'R0 rendered: the loop ends exit 0 and every row carries the contract fields' {
        Assert-That ($rResult.code -eq 0) "expected exit 0, got $($rResult.code): $($rResult.output)"
        $rows = Read-Jsonl (Join-Path $rMain 'temp/spec-queue/runs-mono.jsonl')
        Assert-That ($rows.Count -ge 5) "only $($rows.Count) journal rows"
        $rows | ForEach-Object { Assert-RunRow $_ }
    }
    Test-Case 'R0 rendered: a child that failed but moved is offered again; an unmoved one is dropped (rule 24)' {
        $rows = Read-Jsonl (Join-Path $rMain 'temp/spec-queue/runs-mono.jsonl')
        Assert-That ((Get-Launches $rMain 'S0002') -ge 2) 'S0002 failed but moved and was not offered again'
        Assert-That ((Get-Launches $rMain 'S0003') -eq 1) 'S0003 did not move and was launched again'
        $lastS2 = @($rows | Where-Object { $_.id -eq 'S0002' })[-1]
        Assert-That (-not $lastS2.moved) 'the last S0002 run still moved, so the loop ended before it was dropped'
    }
    Test-Case 'R0 rendered: on a timeout the child dies with its whole tree, the row says timeout, and the loop goes on' {
        $rows = Read-Jsonl (Join-Path $rMain 'temp/spec-queue/runs-mono.jsonl')
        $t = @($rows | Where-Object { $_.outcome -eq 'timeout' })
        Assert-That ($t.Count -eq 1 -and $t[0].id -eq 'S0004') "timeout rows: $($t.Count)"
        Assert-That ($t[0].exitCode -eq -1) "timeout exit code $($t[0].exitCode)"
        Assert-That (-not (Test-Alive (Join-Path $rMain 'grandchild.pid'))) 'the grandchild survived the timeout kill'
        Assert-That ((Get-Ledger $rMain | Where-Object { $_.id -eq 'S0004' }).status -eq 'In Progress') 'the partial work was lost'
        $at = [array]::IndexOf(@($rows | ForEach-Object { $_.outcome }), 'timeout')
        Assert-That ($rows.Count -gt $at + 1) 'nothing ran after the timeout'
    }
    Test-Case 'R0 rendered: the prompt reaches the child as one argument with spaces and quotes intact (rule 22)' {
        $received = Read-Jsonl (Join-Path $rMain 'args.jsonl')
        Assert-That ($received.Count -ge 5) 'the children recorded no arguments'
        foreach ($a in $received) {
            Assert-That ($a.count -eq 1 -and $a.first -ceq $promptShape.Replace('{id}', $a.id)) "$($a.id): count $($a.count), '$($a.first)'"
        }
    }
    Test-Case 'R0 rendered: the start step drops stale stop files and leases before the first child and makes no coordination call (rules 30, 31)' {
        $snap = Get-Content (Join-Path $rMain 'startstate.json') -Raw | ConvertFrom-Json
        Assert-That ($snap.stopFiles -eq 0) "$($snap.stopFiles) stale stop file(s) were still there at the first child"
        Assert-That ($snap.leases -eq 0) "$($snap.leases) stale lease(s) were still there at the first child"
        Assert-That ($snap.locks -eq 0 -and $snap.chat -eq 0) 'R0 left a lock or chat entry before the first child'
        Assert-That ($rResult.output -match 'stale stop file') 'the start step did not say it removed a stale stop file'
    }

    if ($refRun) {
        $refResult = Wait-Proc $refRun
        Test-Case 'R0 reference: exit 0, the contract row, one-argument prompt, and a timeout that kills the whole tree' {
            Assert-That ($refResult.code -eq 0) "expected exit 0, got $($refResult.code): $($refResult.output)"
            $rows = Read-Jsonl (Join-Path $ref 'temp/spec-queue/runs-mono.jsonl')
            $rows | ForEach-Object { Assert-RunRow $_ }
            $t = @($rows | Where-Object { $_.outcome -eq 'timeout' })
            Assert-That ($t.Count -eq 1 -and $t[0].id -eq 'S0004') "timeout rows: $($t.Count)"
            Assert-That (-not (Test-Alive (Join-Path $ref 'grandchild.pid'))) 'the grandchild survived the timeout kill'
            foreach ($a in (Read-Jsonl (Join-Path $ref 'args.jsonl'))) {
                Assert-That ($a.count -eq 1 -and $a.first -ceq $promptShape.Replace('{id}', $a.id)) "$($a.id): count $($a.count), '$($a.first)'"
            }
            Assert-That ((Get-Launches $ref 'S0002') -ge 2 -and (Get-Launches $ref 'S0003') -eq 1) 'rule 24 differs from the rendered launcher'
        }
    }

    if ($run -eq 0) { throw 'No test cases executed' }
    $verdict = if ($failed) { 'FAIL' } else { 'PASS' }
    Write-Output "batch-runner-tests: $verdict (run=$run skipped=0 gaps=$gaps)"
    exit $(if ($failed) { 1 } else { 0 })
} catch {
    Write-Output $_.Exception.Message
    Write-Output "batch-runner-tests: COULD NOT VERIFY (run=$run skipped=0 gaps=$gaps)"
    exit 2
} finally {
    # A survivor of a failed run must not outlive the test: end every tree still started here.
    foreach ($h in $background) {
        if ($h.process -and -not $h.process.HasExited) { & taskkill.exe /PID $h.process.Id /T /F 2>&1 | Out-Null }
    }
    if ($scratch -and (Test-Path -LiteralPath $scratch)) {
        foreach ($pidFile in (Get-ChildItem -LiteralPath $scratch -Recurse -Filter 'grandchild.pid' -ErrorAction SilentlyContinue)) {
            try {
                $parts = (Get-Content -LiteralPath $pidFile.FullName -Raw).Trim().Split('|')
                $p = Get-Process -Id ([int]$parts[0]) -ErrorAction SilentlyContinue
                if ($p -and $p.StartTime.Ticks -eq [int64]$parts[1]) { & taskkill.exe /PID $p.Id /T /F 2>&1 | Out-Null }
            } catch { }
        }
        if (-not $KeepScratch) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
        else { Write-Output "scratch kept: $scratch" }
    }
    $env:SZA_PROJECT_ROOT = $savedRoot
    $env:SZA_PROFILE_PATH = $savedProfile
}
