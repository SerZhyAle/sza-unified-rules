#requires -Version 7.0
<#
.SYNOPSIS
    pq - work the portfolio queue, inspect its logs and manage its repositories.

.DESCRIPTION
    pq register -Path <dir> [-Key <k>] [-Enable]   add a repository to the registry (repos.json in the portfolio
                                                   root); it joins disabled, with maxWorkers 1 and concurrent false
    pq list [-Json]                                 the registered repositories
    pq dry-run [-Slots <n>] [-Json]                 the global order and the slot plan; launches and writes nothing
    pq queue [-Init] [-NoOpen]                      open PORTFOLIO_QUEUE.md; -Init writes a first one when none exists
    pq pin <repo:id>                                put a ticket at the top of the first numbered package
    pq hold <repo[:id]>                             move a row under the hold heading
    pq release <repo[:id]>                          remove a row from under hold; a bare key also clears the
                                                    registry hold of that repository (TASK-FLOW rule 41)
    pq doctor [-All]                                check the enabled repositories (all with -All); writes nothing
    pq start [-Drain] [-MaxTickets <n>]             run one worker; wait when empty, or exit with -Drain
    pq stop [-Kill]                                 stop after current passes; -Kill terminates runner children
    pq status [-Json]                              workers, today's pass outcomes, next ticket and STOP
    pq log [-Last <n>] [-Repo <key>] [-Ev <name>] [-Json]  recent events across all writers (default 40)

    start uses registry pollSeconds (60 by default); -PollSeconds overrides it. Each repository needs an
    explicit permissionMode, in its own record or inherited from the registry, before unattended work starts.

    The portfolio root is SZA_PORTFOLIO_ROOT, else %USERPROFILE%\.sza\portfolio.

    Exit codes: 0 done; 1 doctor found a failure; 2 invalid invocation or a named error ('pq: <Name> - <message>'
    on stderr); 3 start -Drain ran no pass, or a previous STOP is still draining live workers.
#>
param(
    [string]$Verb,
    [string]$Target,
    [string]$Path,
    [string]$Key,
    [int]$Slots = -1,
    [switch]$Enable,
    [switch]$All,
    [switch]$Init,
    [switch]$Json,
    [switch]$NoOpen,
    [switch]$Drain,
    [ValidateRange(0, [int]::MaxValue)][int]$MaxTickets = 0,
    [ValidateRange(0, [int]::MaxValue)][int]$PollSeconds = 0,
    [string]$RunnerScript,
    [switch]$Kill,
    [int]$Last = 40,
    [string]$Repo,
    [string]$Ev,
    [switch]$Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$lib = Join-Path $PSScriptRoot 'lib'
. (Join-Path $lib 'paths.ps1')
. (Join-Path $lib 'events.ps1')
. (Join-Path $lib 'registry.ps1')
. (Join-Path $lib 'queue-file.ps1')
. (Join-Path $lib 'picker.ps1')
. (Join-Path $lib 'rank.ps1')
. (Join-Path $lib 'ledger-watch.ps1')
. (Join-Path $lib 'loop.ps1')

function Write-PqError([string]$Name, [string]$Message) {
    [Console]::Error.WriteLine("pq: $Name - $Message")
}

# owner.action after a successful write: the verb and the NAMES of the parameters used, never their values.
# Fail-open: a failed event write never changes the exit code.
function Write-PqOwnerAction([string]$VerbName) {
    try {
        $opened = $false
        $cliLog = $null
        if ($null -eq $script:PqDefaultLog) {
            $cliLog = Open-PqLog -Writer cli
            $opened = $true
        }
        $names = @($script:PqBound | Where-Object { $_ -cne 'Verb' })
        $null = Write-PqEvent -Ev 'owner.action' -D ([ordered]@{ verb = $VerbName; args = $names })
        if ($opened -and $null -ne $cliLog) { $null = Close-PqLog -Log $cliLog }
    }
    catch { }
}

function Get-PqRegistryOrFail {
    $read = Read-PqRegistry
    if (-not $read.ok) {
        foreach ($e in @($read.errors)) {
            if ($e.name -ceq 'RegistryMissing') { Write-PqError 'RegistryMissing' "no registry at $($read.path); run 'pq register'" }
            else { Write-PqError $e.name "$($e.where) - $($e.message)" }
        }
        return $null
    }
    return $read
}

function Get-PqQueuePath($Registry) {
    $override = $null
    if ($null -ne $Registry) {
        $paths = Get-PqValue $Registry 'paths'
        if ($null -ne $paths) { $override = Get-PqValue $paths 'portfolioQueue' }
    }
    if ($override) { return (Get-PqPath -Kind queue -Override $override) }
    return (Get-PqPath -Kind queue)
}

function Get-PqKnownKeys($Registry) { return [string[]]@(@($Registry.repos) | ForEach-Object { [string]$_.key }) }

# The registry when one exists (for -KnownRepos and paths.portfolioQueue), else $null.
function Read-PqRegistryIfAny {
    $p = Get-PqPath -Kind registry
    if (-not [IO.File]::Exists($p)) { return $null }
    $read = Read-PqRegistry -Path $p
    if (-not $read.ok) { return $null }
    return $read.registry
}

# ---- verbs ----

function Invoke-PqRegister {
    if (-not $Path) { Write-PqError 'ArgumentMissing' 'register needs -Path <dir>'; return 2 }
    $full = if ([IO.Path]::IsPathFullyQualified($Path)) { $Path } else { [IO.Path]::GetFullPath((Join-Path (Get-Location).Path $Path)) }
    $a = @{ Path = $full; Enable = $Enable; Log = $true }
    if ($Key) { $a.Key = $Key }
    $null = Initialize-PqRoot
    $r = Add-PqRepo @a
    if (-not $r.ok) { Write-PqError $r.error $r.message; return 2 }
    if ($r.status -ceq 'already') { "already registered $($r.key)" }
    else { "registered $($r.key)"; Write-PqOwnerAction 'register' }
    return 0
}

function Invoke-PqList {
    $read = Get-PqRegistryOrFail
    if ($null -eq $read) { return 2 }
    if ($Json) { ConvertTo-Json -InputObject $read.document -Depth 64; return 0 }
    foreach ($r in @($read.registry.repos)) {
        '{0}  enabled={1}  hold={2}  rank={3}  maxWorkers={4}  {5}' -f $r.key, $r.enabled.ToString().ToLowerInvariant(),
        $r.hold.ToString().ToLowerInvariant(), $r.rank, $r.maxWorkers, $r.path
    }
    if (@($read.registry.repos).Count -eq 0) { 'no repositories registered' }
    return 0
}

function Invoke-PqQueueWriter([string]$Which) {
    if (-not $Target) { Write-PqError 'ArgumentMissing' "$Which needs a target"; return 2 }
    $read = Get-PqRegistryOrFail
    if ($null -eq $read) { return 2 }
    $known = Get-PqKnownKeys $read.registry
    $qp = Get-PqQueuePath $read.registry
    $null = Open-PqLog -Writer cli
    $r = switch ($Which) {
        'pin' { Add-PqQueuePin -Path $qp -Ticket $Target -KnownRepos $known -Log }
        'hold' { Set-PqQueueHold -Path $qp -Target $Target -KnownRepos $known -Log }
        'release' {
            $t = ConvertTo-PqQueueTarget $Target
            if ($null -ne $t -and -not ($known -ccontains $t.repo)) { @{ ok = $false; changed = $false; error = 'UnknownRepoKey'; message = "no repository '$($t.repo)' in the registry" } }
            else {
                $q = Remove-PqQueueHold -Path $qp -Target $Target -Log
                # A bare key also clears the registry hold (rule 41).
                if ($null -ne $t -and $null -eq $t.id) {
                    $h = Set-PqRepoHold -Key $t.repo -Hold $false -Log
                    if ($h.ok -and $h.changed) { $q = @{ ok = $true; changed = $true; error = $null; message = 'registry hold cleared' } }
                }
                $q
            }
        }
    }
    if (-not $r.ok) {
        $message = if ($r.message) { $r.message } else { $r.error }
        Write-PqError $r.error $message
        return 2
    }
    if ($r.error -ceq 'NotHeld') { "$Target is not held" }
    elseif ($r.changed) { "$Which $Target" }
    else { "$Which $Target - no change" }
    Write-PqOwnerAction $Which
    return 0
}

function Invoke-PqQueue {
    $registry = Read-PqRegistryIfAny
    $qp = Get-PqQueuePath $registry
    if ($Init) {
        if ($null -eq $registry) {
            $read = Get-PqRegistryOrFail
            if ($null -eq $read) { return 2 }
            $registry = $read.registry
        }
        $null = Open-PqLog -Writer cli
        $r = Initialize-PqQueueFile -Path $qp -Registry $registry -Log
        if (-not $r.ok) { Write-PqError $r.error $r.message; return 2 }
        if ($r.status -ceq 'exists') { "exists $qp - not changed" } else { "written $qp"; Write-PqOwnerAction 'queue' }
        if (-not $NoOpen -and $r.status -ceq 'written') { Open-PqEditor $qp }
        return 0
    }
    if (-not [IO.File]::Exists($qp)) { Write-PqError 'QueueFileMissing' "run 'pq queue -Init'"; return 2 }
    if ($NoOpen) { $qp; return 0 }
    Open-PqEditor $qp
    return 0
}

function Open-PqEditor([string]$File) {
    $editor = if ($env:EDITOR) { $env:EDITOR } else { 'notepad' }
    Start-Process -FilePath $editor -ArgumentList @("`"$File`"") | Out-Null
}

function Invoke-PqDryRun {
    # Read-only: no log, no root, no registry write, no temp file; the picker runs -NoDrift without its claim switch.
    $read = Get-PqRegistryOrFail
    if ($null -eq $read) { return 2 }
    $registry = $read.registry
    $enabled = @(@($registry.repos) | Where-Object { $_.enabled -eq $true })
    $n = if ($Slots -ge 0) { $Slots } else { [int]$registry.maxWorkers }
    if ($enabled.Count -eq 0) {
        if ($Json) { ConvertTo-Json -InputObject ([ordered]@{ candidates = @(); plan = @(); skipped = @(); excluded = [ordered]@{}; fill = $registry.fill }) -Depth 16 }
        else { "pq dry-run: fill=$($registry.fill) slots=$n enabled=0 candidates=0"; 'no enabled repositories' }
        return 0
    }
    $harness = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
    $rank = Get-PqNextRank -Registry $registry -HarnessRoot $harness -Slots $n
    if ($Json) {
        ConvertTo-Json -InputObject ([ordered]@{ candidates = $rank.candidates; plan = $rank.plan; skipped = $rank.skipped; excluded = $rank.excluded
                autoSkipReasons = $rank.autoSkipReasons; fill = $rank.fill; heads = $rank.heads; ms = $rank.ms; queueRows = $rank.queueRows; queueBad = $rank.queueBad }) -Depth 16
        return 0
    }
    "pq dry-run: fill=$($rank.fill) slots=$n enabled=$($enabled.Count) candidates=$(@($rank.candidates).Count)"
    $i = 0
    foreach ($c in @($rank.candidates)) {
        $i++
        '{0,2}. {1}:{2}  rule={3}  pri={4}  {5}  {6}' -f $i, $c.repo, $c.id, $c.rule, $c.priority, $c.status, (ConvertTo-PqCut ([string]$c.title) 80)
        if ($i -le 3) { foreach ($a in @($c.alt)) { "      alt $($a.repo):$($a.id) - $($a.why)" } }
    }
    foreach ($p in @($rank.plan)) { "slot $($p.slot): $($p.repo):$($p.id)" }
    foreach ($s in @($rank.skipped)) { "skip $($s.repo) - $($s.why)" }
    foreach ($e in @($rank.events | Where-Object { $_.ev -ceq 'queue.row' })) { "queue row $($e.d.line) - $($e.d.kind): $($e.d.text)" }
    return 0
}

function Test-PqDoctorRepo($Repo, $Out) {
    $k = [string]$Repo.key
    $p = [string]$Repo.path
    $add = { param($v, $check, $detail) $Out.Add("$v $k $check - $detail") }
    if (-not [IO.Directory]::Exists($p)) { & $add 'FAIL' 'path' "$p does not exist"; return }
    & $add 'PASS' 'path' $p
    # stamp: the checks of check-compliance.ps1 that need no canon digest.
    $stampFile = Join-Path $p '.sza-canon.json'
    if (-not [IO.File]::Exists($stampFile)) { & $add 'FAIL' 'stamp' 'no .sza-canon.json' }
    else {
        $stamp = $null
        try { $stamp = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($stampFile)) -DateKind String } catch { }
        if (-not (Test-PqObjectValue $stamp)) { & $add 'FAIL' 'stamp' '.sza-canon.json does not parse as an object' }
        else {
            $missing = @(foreach ($n in @('canon', 'overlay', 'ledgerShape')) { if (-not (Test-PqHasKey $stamp $n)) { $n } })
            $canon = Get-PqValue $stamp 'canon'
            if (Test-PqObjectValue $canon) {
                $missing += @(foreach ($n in @('version', 'coreDigest', 'model')) { if (-not (Test-PqHasKey $canon $n) -or [string]::IsNullOrWhiteSpace([string]$canon.$n)) { "canon.$n" } })
            }
            $carrier = $null
            try { Assert-SzaSchemaCarrier $stamp 'schemaVersion' 'REPO-STAMP' } catch { $carrier = $_.Exception.Message }
            if ($missing.Count -gt 0) { & $add 'FAIL' 'stamp' "missing $($missing -join ', ')" }
            elseif ($carrier) { & $add 'FAIL' 'stamp' $carrier }
            else { & $add 'PASS' 'stamp' "canon $($canon.version)" }
        }
    }
    # profile: R37, ready needs a profile. Read with ConvertFrom-Json, never through _profile.ps1 (one project per process).
    $profileFile = Join-Path $p '.sza-profile.json'
    if (-not [IO.File]::Exists($profileFile)) { & $add 'FAIL' 'profile' 'no .sza-profile.json' }
    else {
        $prof = $null
        try { $prof = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($profileFile)) -DateKind String } catch { }
        if (-not (Test-PqObjectValue $prof)) { & $add 'FAIL' 'profile' '.sza-profile.json does not parse as an object' }
        else {
            $carrier = $null
            try { Assert-SzaSchemaCarrier $prof 'version' 'HARNESS-PROFILE' } catch { $carrier = $_.Exception.Message }
            if ($carrier) { & $add 'FAIL' 'profile' $carrier } else { & $add 'PASS' 'profile' "version $(Get-PqValue $prof 'version' '1.0')" }
        }
    }
    $harness = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
    $v = Invoke-PqRepoChild -RepoPath $p -Script (Join-Path $harness 'spec_catalog\validate.ps1') -Arguments @() -TimeoutSeconds 300
    if ($v.timedOut) { & $add 'FAIL' 'ledger' 'validate.ps1 timed out' }
    elseif ($v.code -ne 0) {
        $last = @(([string]$v.stdout + [string]$v.stderr) -split '\r?\n' | Where-Object { $_ -match 'FAIL' } | Select-Object -First 1)
        & $add 'FAIL' 'ledger' "validate.ps1 exit $($v.code)$(if ($last.Count) { ': ' + $last[0].Trim() })"
    }
    else { & $add 'PASS' 'ledger' 'validate.ps1 exit 0' }
    if ([IO.File]::Exists((Join-Path $p 'r0.ps1'))) { & $add 'PASS' 'launcher' 'r0.ps1' }
    else { & $add 'WARN' 'launcher' 'no r0.ps1 (the uniform launcher names arrive in S0015 Phase 03)' }
}

function Invoke-PqDoctor {
    $out = [Collections.Generic.List[string]]::new()
    $read = Read-PqRegistry
    $repos = @()
    if (-not $read.ok) {
        foreach ($e in @($read.errors)) { $out.Add("FAIL registry - $($e.name): $($e.where) $($e.message)") }
    }
    else {
        $out.Add("PASS registry - $(@($read.registry.repos).Count) repositories")
        $repos = @(@($read.registry.repos) | Where-Object { $All -or $_.enabled -eq $true })
    }
    foreach ($r in $repos) { Test-PqDoctorRepo $r $out }
    $registry = if ($read.ok) { $read.registry } else { $null }
    $qp = Get-PqQueuePath $registry
    if (-not [IO.File]::Exists($qp)) { $out.Add("WARN queue - no $qp; run 'pq queue -Init'") }
    else {
        $a = @{ Path = $qp }
        if ($null -ne $registry) { $a.KnownRepos = Get-PqKnownKeys $registry }
        $q = Read-PqQueueFile @a
        if (@($q.bad).Count -gt 0) { $out.Add("WARN queue - $(@($q.bad).Count) bad rows") }
        else { $out.Add("PASS queue - $(@($q.rows).Count) rows, $(@($q.held).Count) held") }
    }
    $out
    $fails = @($out | Where-Object { $_.StartsWith('FAIL ') }).Count
    $warns = @($out | Where-Object { $_.StartsWith('WARN ') }).Count
    "pq doctor: $($repos.Count) repositories, $fails FAIL, $warns WARN"
    if ($fails -gt 0) { return 1 }
    return 0
}

function Invoke-PqStart {
    $read = Get-PqRegistryOrFail
    if ($null -eq $read) { return 2 }
    $a = @{
        Registry = $read.registry
        Drain = $Drain
        MaxTickets = $MaxTickets
        PollSeconds = $PollSeconds
    }
    if ($RunnerScript) { $a.RunnerScript = $RunnerScript }
    return (Start-PqLoop @a)
}

function Invoke-PqStop {
    $root = Initialize-PqRoot
    $stopFile = Join-Path $root 'STOP'
    $level = if ($Kill) { 'kill' } else { 'pass' }
    $stopObj = [ordered]@{
        level = $level
        by = 'cli'
        at = [DateTimeOffset]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
        reason = 'owner'
    }
    $workers = @(Invoke-PqStateLock {
        $runDir = Join-Path $root 'run'
        if ($Kill -and [IO.Directory]::Exists($runDir)) {
            foreach ($wf in [IO.Directory]::GetFiles($runDir, 'worker-*.json')) {
                $worker = Read-PqState $wf
                if ((Get-PqValue $worker 'repository') -and (Test-PqStateOwner $worker)) {
                    @{ slot = [IO.Path]::GetFileNameWithoutExtension($wf).Substring('worker-'.Length); repository = $worker.repository }
                }
            }
        }
        # Capture targets before publishing STOP: workers may exit and remove their state immediately.
        [IO.File]::WriteAllText($stopFile, (($stopObj | ConvertTo-Json)), [Text.Encoding]::UTF8)
    })
    $failed = $false

    if ($Kill) {
        $harness = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
        foreach ($worker in $workers) {
            try {
                $k = $worker.slot
                $reg = Read-PqRegistryIfAny
                $repoRec = if ($null -ne $reg) { @($reg.repos) | Where-Object key -CEQ $worker.repository | Select-Object -First 1 } else { $null }
                if ($null -eq $repoRec) { throw 'worker repository is no longer registered' }
                $rPath = [string]$repoRec.path
                $runner = Join-Path $harness 'batch\run-spec-queue.ps1'
                $result = Invoke-PqRepoChild -RepoPath $rPath -Script $runner -Arguments @('-Stop', '-Kill', '-Instance', "pq$k") -TimeoutSeconds 30
                if ($result.timedOut -or $result.code -ne 0) {
                    $failed = $true
                    Write-PqError 'KillFailed' "runner stop failed for worker $k"
                }
            }
            catch {
                $failed = $true
                Write-PqError 'KillFailed' "cannot stop worker $($worker.slot)"
            }
        }
    }
    Write-PqOwnerAction 'stop'
    "stop requested ($level)"
    if ($failed) { return 2 }
    return 0
}

function Invoke-PqStatus {
    $root = Get-PqRoot
    $stopFile = Join-Path $root 'STOP'
    $stopPresent = [IO.File]::Exists($stopFile)
    $stopLevel = $null
    if ($stopPresent) {
        try {
            $stopObj = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($stopFile, [Text.Encoding]::UTF8)) -DateKind String
            $stopLevel = [string]$stopObj.level
        }
        catch { $stopLevel = 'pass' }
    }

    $workers = [Collections.Generic.List[object]]::new()
    $runDir = Join-Path $root 'run'
    if ([IO.Directory]::Exists($runDir)) {
        $wFiles = [IO.Directory]::GetFiles($runDir, 'worker-*.json')
        [Array]::Sort($wFiles, [StringComparer]::Ordinal)
        foreach ($wf in $wFiles) {
            $fn = [IO.Path]::GetFileNameWithoutExtension($wf)
            $k = [int]($fn.Substring('worker-'.Length))
            try {
                $wObj = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($wf, [Text.Encoding]::UTF8)) -DateKind String
                $p = [int]$wObj.pid
                $alive = Test-PqStateOwner $wObj
                $target = if ($wObj.repository -and $wObj.ticket) { "$($wObj.repository):$($wObj.ticket)" } else { '-' }
                $workers.Add([ordered]@{
                    slot = $k
                    pid = $p
                    alive = $alive
                    target = $target
                    since = [string]$wObj.since
                })
            }
            catch { }
        }
    }

    $passesToday = [ordered]@{}
    foreach ($e in @(Read-PqCliEvents -Today | Where-Object { $_.ev -ceq 'pass.end' })) {
        $oc = [string]$e.d.outcome
        if ($passesToday.Contains($oc)) { $passesToday[$oc]++ } else { $passesToday[$oc] = 1 }
    }

    $nextCandidate = $null
    $reg = Read-PqRegistryIfAny
    if ($null -ne $reg) {
        try {
            $harness = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
            $rank = Get-PqNextRank -Registry $reg -HarnessRoot $harness -Slots 1
            if (@($rank.candidates).Count -gt 0) {
                $nextCandidate = [ordered]@{
                    repo = [string]$rank.candidates[0].repo
                    id = [string]$rank.candidates[0].id
                    status = [string]$rank.candidates[0].status
                    title = [string]$rank.candidates[0].title
                }
            }
        }
        catch { }
    }

    if ($Json) {
        $res = [ordered]@{
            stop = if ($stopPresent) { @{ present = $true; level = $stopLevel } } else { @{ present = $false } }
            workers = $workers
            passesToday = $passesToday
            next = $nextCandidate
        }
        ConvertTo-Json -InputObject $res -Depth 16
        return 0
    }

    "STOP: $(if ($stopPresent) { "present (level=$stopLevel)" } else { 'none' })"
    if ($workers.Count -eq 0) {
        "Workers: none active"
    }
    else {
        "Workers:"
        foreach ($w in $workers) {
            "  slot {0}  pid={1}  alive={2}  target={3}  since={4}" -f $w.slot, $w.pid, $w.alive.ToString().ToLowerInvariant(), $w.target, $w.since
        }
    }
    if ($passesToday.Count -eq 0) {
        "Passes today: none"
    }
    else {
        $parts = foreach ($k in $passesToday.Keys) { "$k`: $($passesToday[$k])" }
        "Passes today: $($parts -join ', ')"
    }
    if ($null -ne $nextCandidate) {
        "Next: $($nextCandidate.repo):$($nextCandidate.id) ($($nextCandidate.status)) $($nextCandidate.title)"
    }
    else {
        "Next: none"
    }
    return 0
}

function Read-PqCliEvents([switch]$Today) {
    $root = Get-PqRoot
    $logDir = Join-Path $root 'log'
    $events = [Collections.Generic.List[object]]::new()
    if ([IO.Directory]::Exists($logDir)) {
        $pattern = if ($Today) { 'events-' + [DateTimeOffset]::UtcNow.ToString('yyyy-MM-dd') + '.*.jsonl' } else { 'events-*.jsonl' }
        $files = [IO.Directory]::GetFiles($logDir, $pattern)
        foreach ($f in $files) {
            foreach ($e in (Read-PqDay -Path $f).events) { $events.Add($e) }
        }
    }
    # Files are grouped by writer. Last N means chronological order across every writer.
    return @($events | Sort-Object ts, wr, seq)
}

function Invoke-PqLog {
    $events = @(Read-PqCliEvents | Where-Object {
        (-not $Repo -or $_.repo -ceq $Repo) -and (-not $Ev -or $_.ev -ceq $Ev)
    })

    $n = if ($Last -gt 0) { $Last } else { 40 }
    $selected = if ($events.Count -gt $n) { $events[($events.Count - $n)..($events.Count - 1)] } else { $events }

    if ($Json) {
        ConvertTo-Json -InputObject @($selected) -Depth 16
        return 0
    }

    foreach ($e in $selected) {
        $target = if ($e.repo) { "$($e.repo):$($e.id) " } else { '' }
        $dStr = if ($null -ne $e.d) { ConvertTo-Json -InputObject $e.d -Compress } else { '{}' }
        '{0}  {1,-15}  wr={2}  {3}{4}' -f $e.ts, $e.ev, $e.wr, $target, $dStr
    }
    return 0
}

# ---- router ----

# Every verb of the INDEX code map; $null marks a verb whose handler a later phase adds.
$verbs = [ordered]@{
    start = { Invoke-PqStart }; stop = { Invoke-PqStop }; status = { Invoke-PqStatus }; log = { Invoke-PqLog }
    watch = $null; tail = $null; page = $null; pause = $null; resume = $null
    hold = { Invoke-PqQueueWriter 'hold' }; release = { Invoke-PqQueueWriter 'release' }; pin = { Invoke-PqQueueWriter 'pin' }
    queue = { Invoke-PqQueue }; register = { Invoke-PqRegister }; list = { Invoke-PqList }; 'dry-run' = { Invoke-PqDryRun }
    report = $null; trace = $null; problems = $null; export = $null; compare = $null; analyze = $null; improve = $null
    doctor = { Invoke-PqDoctor }
}

if ($Help -or -not $Verb) {
    Get-Help $PSCommandPath -Detailed | Out-String
    if (-not $Help) { exit 2 }
    exit 0
}
if (-not $verbs.Contains($Verb)) {
    [Console]::Error.WriteLine("pq: unknown verb '$Verb'. Verbs: $(@($verbs.Keys) -join ' ')")
    exit 2
}
$handler = $verbs[$Verb]
if ($null -eq $handler) {
    [Console]::Error.WriteLine("pq: verb '$Verb' is not available in this build")
    exit 2
}
$script:PqBound = @($PSBoundParameters.Keys)
$code = 2
try {
    $output = @(& $handler)
    $code = $output[-1]
    if ($output.Count -gt 1) { $output[0..($output.Count - 2)] }
}
catch {
    $m = $_.Exception.Message
    $name = if ($m -match '^([A-Za-z]+): ') { $Matches[1] } else { 'Failed' }
    Write-PqError $name $m
    $code = 2
}
finally {
    try { foreach ($h in @($script:PqLogs.Values)) { $null = Close-PqLog -Log $h } } catch { }
}
exit ([int]$code)
