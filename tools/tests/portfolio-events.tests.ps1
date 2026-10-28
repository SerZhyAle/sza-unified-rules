#requires -Version 7.0
<#
    The suite of S0015 Phase 01: the three libraries every portfolio phase stands on, under
    tools/harness/portfolio/lib - paths.ps1 (the portfolio root of TASK-FLOW rule 41 and the names under it),
    events.ps1 (the event log of rules 53-59) and ledger-watch.ps1 (the ledger snapshot, the diff and actor
    attribution of rule 59).

    What this proves: each library's documented behaviour, case by case, against throwaway portfolio roots under
    the system temp directory. Every case points SZA_PORTFOLIO_ROOT and USERPROFILE at scratch directories before
    its body runs and restores both afterwards, so no case can read or write the owner's %USERPROFILE%\.sza.

    What it does not prove: anything the dispatcher does with these libraries (later phases), or anything a real
    agent does. No agent is started.

    A case that needs the shared contracts catalog is skipped (SKIP, counted in skipped, not in run) unless
    -CatalogRoot is given. A library that does not exist yet makes its cases FAIL with "library missing: lib/<file>";
    it never aborts the run.

    Exit codes: 0 every case that ran passed; 1 an assertion failed; 2 could not verify (setup failed, or the
    -Case filter matched no case to run).
#>
[CmdletBinding()]
param(
    [string]$SourceRoot = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent),
    # The library directory under test; a negative control points it at a mutated copy.
    [string]$LibRoot,
    # The shared contracts catalog (the directory that holds task-flow\); cases that read it are skipped without it.
    [string]$CatalogRoot,
    # Run only the cases whose name matches this regular expression.
    [Alias('Filter')][string]$Case,
    [switch]$KeepScratch
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $LibRoot) { $LibRoot = Join-Path $SourceRoot 'tools\harness\portfolio\lib' }

# The factors of the perf group, set from measured runs recorded, with the machine, the command and the condition
# of each run, in PLAN/S0015_portfolio-queue-runner/evidence/perf-baseline.json: PerfFactor = ceil(1.5 * max ratio),
# PerfTailFactor = ceil(1.5 * max tailRatio), the maximum over every recorded run of the current method (five quiet
# runs, two whole-suite runs, three whole suites at once). A relative margin, because ceil(max) + 1 left about 4
# percent over a ratio near 30 and flaked (review finding 8). A ratio is against a baseline measured in the same run
# on the same machine; no absolute time appears anywhere. A change to either factor needs a new measurement recorded
# in that file. Setting the environment variable PORTFOLIO_EVENTS_PERF_RECORD to a file path appends each run's
# measurement to that file as one JSON line (how the evidence was taken; PORTFOLIO_EVENTS_PERF_LABEL names the
# condition).
$PerfFactor = 45        # 2026-10-27: ceil(1.5 * 29.463), the max ratio of ten interleaved runs
$PerfTailFactor = 2     # 2026-10-27: ceil(1.5 * 1.022), the max tailRatio of the same ten runs

$run = 0
$failed = 0
$skipped = 0
$gaps = 0
$setupFailed = $false
$scratch = $null
$savedPortfolioRoot = $env:SZA_PORTFOLIO_ROOT
$savedUserProfile = $env:USERPROFILE

function Assert-That([bool]$Condition, [string]$Reason) { if (-not $Condition) { throw $Reason } }

# A fresh directory under the suite's scratch root.
function New-Scratch([string]$Name = 'case') {
    $dir = Join-Path $script:scratch ($Name + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $dir | Out-Null
    return $dir
}

# The libraries keep their state in $script: variables named Pq*; dot-sourced from a case they land in this
# suite's script scope and would outlive the case. Every case starts and ends with none: open log streams are
# disposed (so a failed case cannot hold a file another case or the scratch removal needs) and the variables go.
function Reset-LibState {
    $logs = Get-Variable -Name PqLogs -Scope Script -ValueOnly -ErrorAction Ignore
    if ($null -ne $logs) {
        foreach ($h in @($logs.Values)) {
            try { $h.Stream.Dispose() } catch { }
        }
    }
    Get-Variable -Name 'Pq*' -Scope Script -ErrorAction Ignore | ForEach-Object {
        Remove-Variable -Name $_.Name -Scope Script -Force -ErrorAction Ignore
    }
}

# Every case runs with SZA_PORTFOLIO_ROOT and USERPROFILE pointing into scratch (a body may point them elsewhere
# in scratch) and gets both back afterwards, whatever it did.
function Test-Case([string]$Name, [scriptblock]$Body) {
    if ($Case -and $Name -notmatch $Case) { return }
    $script:run++
    $guard = New-Scratch 'guard'
    $env:SZA_PORTFOLIO_ROOT = Join-Path $guard 'portfolio'
    $env:USERPROFILE = Join-Path $guard 'home'
    Reset-LibState
    try {
        $null = & $Body
        "OK $Name"
    }
    catch { $script:failed++; "FAIL $Name - $($_.Exception.Message)" }
    finally {
        Reset-LibState
        $env:SZA_PORTFOLIO_ROOT = $savedPortfolioRoot
        $env:USERPROFILE = $savedUserProfile
    }
}

function Skip-Case([string]$Name, [string]$Reason) {
    if ($Case -and $Name -notmatch $Case) { return }
    $script:skipped++
    "SKIP $Name - $Reason"
}

function Get-LibPath([string]$File) {
    $path = Join-Path $LibRoot $File
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "library missing: lib/$File" }
    return $path
}

# [IO.File]::ReadAllLines, but with FileShare.ReadWrite as a reader opens a log, so a file whose writer is still
# open (in this or another process) can be read too; the lines split as ReadAllLines splits them (StreamReader).
function Read-Lines([string]$Path) {
    $fs = [IO.FileStream]::new($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    try {
        $sr = [IO.StreamReader]::new($fs, [Text.UTF8Encoding]::new($false), $true)
        $lines = [Collections.Generic.List[string]]::new()
        while ($null -ne ($line = $sr.ReadLine())) { $lines.Add($line) }
        return , $lines.ToArray()
    }
    finally { $fs.Dispose() }
}

# Start `pwsh -NoProfile -File <script> @Arguments` without waiting; -Environment applies to the child only ($null
# removes a name). Wait-Child collects it; Stop-Children kills what is still running (a failed case must not leave
# a child holding a file).
function Start-Child([string]$Script, [string[]]$Arguments = @(), [hashtable]$Environment = @{}) {
    $psi = [System.Diagnostics.ProcessStartInfo]::new((Get-Command pwsh -CommandType Application | Select-Object -First 1).Source)
    foreach ($a in (@('-NoProfile', '-File', $Script) + $Arguments)) { $psi.ArgumentList.Add($a) }
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    foreach ($k in $Environment.Keys) {
        if ($null -eq $Environment[$k]) { [void]$psi.Environment.Remove($k) } else { $psi.Environment[$k] = [string]$Environment[$k] }
    }
    $proc = [System.Diagnostics.Process]::Start($psi)
    return @{ proc = $proc; out = $proc.StandardOutput.ReadToEndAsync(); err = $proc.StandardError.ReadToEndAsync(); script = $Script }
}

function Wait-Child($Child, [int]$TimeoutSeconds = 120) {
    $proc = $Child.proc
    if (-not $proc.WaitForExit($TimeoutSeconds * 1000)) {
        try { $proc.Kill($true) } catch { }
        throw "child timed out after $TimeoutSeconds s: $($Child.script)"
    }
    $proc.WaitForExit()
    $text = ($Child.out.Result + $Child.err.Result).Trim()
    return @{ code = $proc.ExitCode; output = $text; stdout = $Child.out.Result; stderr = $Child.err.Result; pid = $proc.Id }
}

function Stop-Children($Children) {
    foreach ($c in @($Children)) {
        if ($null -eq $c) { continue }
        try { if (-not $c.proc.HasExited) { $c.proc.Kill($true); $null = $c.proc.WaitForExit(10000) } } catch { }
    }
}

# Run `pwsh -NoProfile -File <script> @Arguments` and wait for it.
function Invoke-Child([string]$Script, [string[]]$Arguments = @(), [hashtable]$Environment = @{}, [int]$TimeoutSeconds = 120) {
    return (Wait-Child (Start-Child $Script $Arguments $Environment) $TimeoutSeconds)
}

# Polls (20 ms) until the condition holds; throws after the timeout, naming what it waited for.
function Wait-Until([scriptblock]$Condition, [int]$TimeoutSeconds, [string]$What) {
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while (-not (& $Condition)) {
        if ([DateTime]::UtcNow -gt $deadline) { throw "timed out after $TimeoutSeconds s waiting for $What" }
        Start-Sleep -Milliseconds 20
    }
}

# A recursive listing of a directory: relative path, kind, size and last write time, one string per entry.
function Get-Listing([string]$Dir) {
    if (-not (Test-Path -LiteralPath $Dir)) { return , @() }
    $base = (Get-Item -LiteralPath $Dir).FullName.TrimEnd('\', '/')
    $rows = @(Get-ChildItem -LiteralPath $Dir -Recurse -Force | Sort-Object FullName | ForEach-Object {
            $rel = $_.FullName.Substring($base.Length).TrimStart('\', '/')
            $len = if ($_.PSIsContainer) { 'dir' } else { [string]$_.Length }
            "$rel|$len|$($_.LastWriteTimeUtc.Ticks)"
        })
    return , $rows
}

function Assert-Throws([scriptblock]$Action, [string]$Prefix, [string]$What) {
    $message = $null
    try { $null = & $Action } catch { $message = $_.Exception.Message }
    Assert-That ($null -ne $message) "$What did not throw"
    Assert-That ($message.StartsWith($Prefix, [StringComparison]::Ordinal)) "$What threw '$message', expected a message starting '$Prefix'"
}

# Pins the library clock (Set-PqClock) to a mutable holder; a case moves time with $holder.now = <DateTimeOffset>.
function New-TestClock([DateTimeOffset]$At) {
    $holder = @{ now = $At }
    Set-PqClock -Now ({ $holder.now }.GetNewClosure())
    return $holder
}

# The complete (LF-terminated) lines of an event file, parsed the way a reader parses them (ts stays a string).
# Read with FileShare.ReadWrite, as a reader does, so a file whose writer is still open can be read too.
function Get-FileEvents([string]$Path) {
    $fs = [IO.FileStream]::new($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    try { $ms = [IO.MemoryStream]::new(); $fs.CopyTo($ms) } finally { $fs.Dispose() }
    $text = [Text.Encoding]::UTF8.GetString($ms.ToArray())
    $parts = $text.Split("`n")
    $events = @(for ($i = 0; $i -lt $parts.Length - 1; $i++) { ConvertFrom-Json -InputObject $parts[$i] -DateKind String })
    return , $events
}

# Get-Listing with the write time of directories dropped (NTFS updates it lazily after a file inside is written).
function Get-FileListing([string[]]$Listing) { return , @($Listing | ForEach-Object { $_ -replace '\|dir\|\d+$', '|dir' }) }

# The property names of a parsed JSON object in document order, compared ordinally by the callers.
function Get-Keys($Object) { return (@($Object.PSObject.Properties | ForEach-Object { $_.Name }) -join ' ') }

# A hand-built envelope line (not written by the library), for reader fixtures.
function New-EventLine([long]$Seq, [string]$Ev = 'poll.change', [string]$Wr = 'pq', [string]$Ts = '2026-10-27T10:00:00.000Z', $D = $null) {
    if ($null -eq $D) { $D = [ordered]@{} }
    $o = [ordered]@{ v = 1; ts = $Ts; seq = $Seq; wr = $Wr; run = $null; ev = $Ev; repo = $null; id = $null; pass = $null
        worker = $null; agent = $null; model = $null; cx = $null; d = $D }
    return (ConvertTo-Json -InputObject $o -Compress -Depth 8)
}

# Writes lines as UTF-8 without a BOM, each LF-terminated unless -NoFinalLf leaves the last one open.
function Write-RawFile([string]$Path, [string[]]$Lines, [switch]$NoFinalLf, [switch]$Append) {
    $text = ($Lines -join "`n")
    if (-not $NoFinalLf) { $text += "`n" }
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($text)
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $mode = if ($Append) { [IO.FileMode]::Append } else { [IO.FileMode]::Create }
    $fs = [IO.FileStream]::new($Path, $mode, [IO.FileAccess]::Write, [IO.FileShare]::ReadWrite)
    try { $fs.Write($bytes, 0, $bytes.Length) } finally { $fs.Dispose() }
}

# Every ev written under <root>\log is a name of Get-PqEventNames (the library's registry, which the reader group
# proves equal to the catalog): a case that emits a name the catalog does not know fails here.
function Assert-KnownEvents([string]$Root) {
    $known = [Collections.Generic.HashSet[string]]::new([string[]]@(Get-PqEventNames), [StringComparer]::Ordinal)
    $dir = Join-Path $Root 'log'
    $files = @(if (Test-Path -LiteralPath $dir) { Get-ChildItem -LiteralPath $dir -File -Filter 'events-*.jsonl' })
    Assert-That ($files.Count -gt 0) "no event file under $dir"
    foreach ($f in $files) {
        foreach ($e in (Get-FileEvents $f.FullName)) {
            Assert-That ($known.Contains([string]$e.ev)) "$($f.Name) seq $($e.seq): '$($e.ev)' is not a name of Get-PqEventNames"
        }
    }
}

# The child writer of the concurrent group, written once into the suite scratch (never into the repository):
#   child-writer.ps1 -LibRoot <dir> -Root <portfolio root> -Writer <wr> -Count <n> -GoFile <path>
#                    [-ReadyFile <path>] [-HoldFile <path>] [-ShiftTicks <n>]
# It points SZA_PORTFOLIO_ROOT at -Root, dot-sources events.ps1, opens the log, creates -ReadyFile (so a ready
# child holds its log open), waits (20 ms polls) for -GoFile, writes -Count poll.change events with d.n 1..Count,
# and with -HoldFile keeps the log open until that file disappears. -ShiftTicks moves the clock seam by a fixed
# amount from the system clock, so every process of a case shares one real timeline on a pinned day (no case can
# straddle a UTC midnight). It prints one line, 'CHILD wr=<wr> pid=<pid> token=<token> state=<state after the
# writes> written=<writes that returned true>', and exits 0 only when every write returned true on an open log.
function Get-ChildWriter {
    $path = Join-Path $script:scratch 'child-writer.ps1'
    if (Test-Path -LiteralPath $path) { return $path }
    [IO.File]::WriteAllText($path, @'
param([string]$LibRoot, [string]$Root, [string]$Writer, [int]$Count, [string]$GoFile, [string]$ReadyFile, [string]$HoldFile,
    [long]$ShiftTicks = 0, [int]$TimeoutSeconds = 90)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$env:SZA_PORTFOLIO_ROOT = $Root
. (Join-Path $LibRoot 'events.ps1')
if ($ShiftTicks -ne 0) { Set-PqClock -Now ({ [DateTimeOffset]::UtcNow.AddTicks($ShiftTicks) }.GetNewClosure()) }
$h = Open-PqLog -Writer $Writer
if ($ReadyFile) { [IO.File]::WriteAllText($ReadyFile, [string]$PID) }
$deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
while (-not [IO.File]::Exists($GoFile)) {
    if ([DateTime]::UtcNow -gt $deadline) { [Console]::Out.Write("CHILD wr=$Writer pid=$PID timed out waiting for the go file"); exit 4 }
    Start-Sleep -Milliseconds 20
}
$ok = 0
for ($n = 1; $n -le $Count; $n++) {
    if ((Write-PqEvent -Log $h -Ev 'poll.change' -D @{ n = $n }) -eq $true) { $ok++ }
}
$state = $h.State
if ($HoldFile) {
    while ([IO.File]::Exists($HoldFile)) {
        if ([DateTime]::UtcNow -gt $deadline) { break }
        Start-Sleep -Milliseconds 20
    }
}
Close-PqLog -Log $h
[Console]::Out.Write("CHILD wr=$Writer pid=$PID token=$($h.Token) state=$state written=$ok")
if ($ok -ne $Count -or $state -ne 'open') { exit 3 }
exit 0
'@)
    return $path
}

# The instant every process of a concurrent case reads as "now" is the system clock moved onto 2026-10-27 10:00Z.
function Get-ConcurrentShift { return ([DateTimeOffset]::new(2026, 10, 27, 10, 0, 0, [TimeSpan]::Zero) - [DateTimeOffset]::UtcNow).Ticks }

# Starts one child writer per name behind one barrier: every child has opened its log (ready file) before the go
# file exists. Returns @{ root; date; kids = @(@{ wr; child; result }) } after every child has exited.
function Invoke-WriterGroup([string[]]$Writers, [int]$Count, [string]$Name) {
    $s = New-Scratch $Name
    $root = Join-Path $s 'portfolio'
    $go = Join-Path $s 'go'
    $shift = Get-ConcurrentShift
    $lib = [IO.Path]::GetFullPath($LibRoot)
    $child = Get-ChildWriter
    $kids = [Collections.Generic.List[object]]::new()
    try {
        foreach ($wr in $Writers) {
            $ready = Join-Path $s "ready-$wr-$($kids.Count)"
            $c = Start-Child $child @('-LibRoot', $lib, '-Root', $root, '-Writer', $wr, '-Count', [string]$Count, '-GoFile', $go,
                '-ReadyFile', $ready, '-ShiftTicks', [string]$shift)
            $kids.Add(@{ wr = $wr; ready = $ready; child = $c; result = $null })
        }
        $readyFiles = @($kids | ForEach-Object { $_.ready })
        Wait-Until ({ @($readyFiles | Where-Object { -not (Test-Path -LiteralPath $_) }).Count -eq 0 }.GetNewClosure()) 60 "the ready files of $($Writers -join ', ')"
        [IO.File]::WriteAllText($go, 'go')
        foreach ($k in $kids) { $k.result = Wait-Child $k.child 120 }
    }
    finally { Stop-Children @($kids | ForEach-Object { $_.child }) }
    return @{ root = $root; date = '2026-10-27'; kids = $kids.ToArray() }
}

# Concurrent cases 1 and 2 read the same five-writer run; it is made once, by whichever of them runs first.
$FiveWriterRun = $null
function Get-FiveWriterRun {
    if ($null -eq $script:FiveWriterRun) { $script:FiveWriterRun = Invoke-WriterGroup @('w1', 'w2', 'w3', 'w4', 'w5') 400 'five' }
    return $script:FiveWriterRun
}

# The perf run, measured on scratch files in this run (events.ps1 must be loaded). Both sides of the ratio are timed
# in the same block structure and interleaved, so a burst of load from another process hits both alike (review
# finding 8: one 4 s event window against one 130 ms baseline window flaked 4 of 6 whole-suite runs):
#   lineBytes  the average length, LF included, of the lines of 200 real Write-PqEvent calls of the typical event
#   ioMs[i]    appending 1000 lines of lineBytes through one FileStream, with a flush per line
#   jsonMs[i]  1000 ConvertTo-Json -Compress calls over a 14-key envelope-shaped object
#   blocksMs[i] 1000 typical events through Write-PqEvent on one handle
# for i = 1..10, in the order io, json, events. ratio = min(blocksMs) / min(ioMs[i] + jsonMs[i]): the minimum of
# each side drops the blocks a transient spike slowed down. tailRatio = min(the last two blocksMs) / min(the first
# two). Every timed loop is preceded by an untimed warm-up of the same work (Write-PqEvent 3000 more calls on the
# sample handle, 1000 appends, 150000 ConvertTo-Json calls), so the ratio is one of steady states and does not
# depend on what ran earlier in the process: ConvertTo-Json reaches its steady speed only after about 100000 calls
# on this machine (.NET tiered and profile-guided compilation; probed 2026-10-27: 10000 calls took 190, 157, 183,
# 240, 254, 243, 138, 96, 83, 63, 55, 53 ms in turn), hence the long warm-up of that loop. The event loop stops
# early only when a block takes more than twice PerfTailFactor times the first block (the cost per event has
# already grown past the tail bound; without the stop an O(n) scan per write would run for minutes). Both perf
# cases read the same run, made once by whichever runs first. PORTFOLIO_EVENTS_PERF_LABEL, when set, is written
# into the recorded line as label (the condition of the run).
$PerfRun = $null
function Get-PerfRun([int]$Blocks = 10, [int]$BlockSize = 1000) {
    if ($null -ne $script:PerfRun) { return $script:PerfRun }
    $s = New-Scratch 'perf'
    $env:SZA_PORTFOLIO_ROOT = Join-Path $s 'portfolio'
    $h = Open-PqLog -Writer w9
    for ($i = 1; $i -le 3200; $i++) {
        $null = Write-PqEvent -Log $h -Ev 'poll.change' -Repo 'fms-web' -Id 'S0028' -Pass 'R20261027T100000-0a0b.3' -Worker 2 -Agent 'claude' -Model 'claude-opus-4' -Cx 'M' -Run 'R20261027T100000-0a0b' -D @{ n = $i; why = 'the queue row moved'; rows = 3 }
    }
    Close-PqLog -Log $h
    $all = Read-Lines $h.Path
    Assert-That ($all.Count -eq 3200) "the baseline sample holds $($all.Count) lines, expected 3200"
    $bytes = 0
    for ($i = 0; $i -lt 200; $i++) { $bytes += [Text.Encoding]::UTF8.GetByteCount($all[$i]) + 1 }
    $lineBytes = [int][Math]::Round($bytes / 200)
    $line = [Text.Encoding]::UTF8.GetBytes(('x' * ($lineBytes - 1)) + "`n")
    $o = [ordered]@{ v = 1; ts = '2026-10-27T10:00:00.000Z'; seq = 1; wr = 'w1'; run = 'R20261027T100000-0a0b'; ev = 'poll.change'
        repo = 'fms-web'; id = 'S0028'; pass = 'R20261027T100000-0a0b.3'; worker = 2; agent = 'claude'; model = 'claude-opus-4'; cx = 'M'
        d = [ordered]@{ n = 1; why = 'the queue row moved'; rows = 3 } }
    for ($i = 0; $i -lt 150000; $i++) { $null = ConvertTo-Json -InputObject $o -Compress -Depth 8 -WarningAction Ignore }
    $io = [Collections.Generic.List[double]]::new()
    $json = [Collections.Generic.List[double]]::new()
    $ev = [Collections.Generic.List[double]]::new()
    $written = 0
    $stoppedAt = $null
    $n = 0
    $fs = [IO.FileStream]::new((Join-Path $s 'io.jsonl'), [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::Read)
    $w = Open-PqLog -Writer w1
    try {
        for ($i = 0; $i -lt 1000; $i++) { $fs.Write($line, 0, $line.Length); $fs.Flush() }
        for ($b = 0; $b -lt $Blocks; $b++) {
            $sw = [Diagnostics.Stopwatch]::StartNew()
            for ($i = 0; $i -lt $BlockSize; $i++) { $fs.Write($line, 0, $line.Length); $fs.Flush() }
            $io.Add($sw.Elapsed.TotalMilliseconds)
            $sw = [Diagnostics.Stopwatch]::StartNew()
            for ($i = 0; $i -lt $BlockSize; $i++) { $null = ConvertTo-Json -InputObject $o -Compress -Depth 8 -WarningAction Ignore }
            $json.Add($sw.Elapsed.TotalMilliseconds)
            $sw = [Diagnostics.Stopwatch]::StartNew()
            for ($i = 0; $i -lt $BlockSize; $i++) {
                $n++
                if ((Write-PqEvent -Log $w -Ev 'poll.change' -Repo 'fms-web' -Id 'S0028' -Pass 'R20261027T100000-0a0b.3' -Worker 2 -Agent 'claude' -Model 'claude-opus-4' -Cx 'M' -Run 'R20261027T100000-0a0b' -D @{ n = $n; why = 'the queue row moved'; rows = 3 }) -eq $true) { $written++ }
            }
            $ev.Add($sw.Elapsed.TotalMilliseconds)
            if ($script:PerfTailFactor -gt 0 -and $ev.Count -gt 1 -and $ev[$ev.Count - 1] -gt 2 * $script:PerfTailFactor * $ev[0]) { $stoppedAt = $n; break }
        }
    }
    finally { $fs.Dispose(); Close-PqLog -Log $w }
    $baseBlocks = [double[]]::new($io.Count)
    for ($i = 0; $i -lt $io.Count; $i++) { $baseBlocks[$i] = $io[$i] + $json[$i] }
    $e = $ev.ToArray()
    $minEvent = ($e | Measure-Object -Minimum).Minimum
    $minBase = ($baseBlocks | Measure-Object -Minimum).Minimum
    $k = [Math]::Min(2, [int][Math]::Floor($e.Length / 2))
    $tail = if ($k -gt 0) { ($e[($e.Length - $k)..($e.Length - 1)] | Measure-Object -Minimum).Minimum / ($e[0..($k - 1)] | Measure-Object -Minimum).Minimum } else { [double]1 }
    $run = [ordered]@{
        label        = $(if ($env:PORTFOLIO_EVENTS_PERF_LABEL) { [string]$env:PORTFOLIO_EVENTS_PERF_LABEL } else { $null })
        count        = $Blocks * $BlockSize
        lineBytes    = $lineBytes
        minEventMs   = [Math]::Round($minEvent, 1)
        minBaseMs    = [Math]::Round($minBase, 1)
        ratio        = [Math]::Round($minEvent / $minBase, 3)
        tailRatio    = [Math]::Round($tail, 3)
        eventsMs     = [Math]::Round(($e | Measure-Object -Sum).Sum, 1)
        baselineMs   = [Math]::Round(($baseBlocks | Measure-Object -Sum).Sum, 1)
        blocksMs     = [double[]]@($e | ForEach-Object { [Math]::Round($_, 1) })
        ioBlocksMs   = [double[]]@($io | ForEach-Object { [Math]::Round($_, 1) })
        jsonBlocksMs = [double[]]@($json | ForEach-Object { [Math]::Round($_, 1) })
        written      = $written
        stoppedAt    = $stoppedAt
    }
    $record = $env:PORTFOLIO_EVENTS_PERF_RECORD
    if ($record) { [IO.File]::AppendAllText($record, (ConvertTo-Json -InputObject $run -Compress -Depth 4) + "`n", [Text.UTF8Encoding]::new($false)) }
    $script:PerfRun = $run
    return $run
}

$EnvelopeKeys = 'v ts seq wr run ev repo id pass worker agent model cx d'

# ---- ledger-watch fixtures (S0015 Phase 01 steps 01.14-01.15) ----
# Every time a ledger (updated, created) or a runner row (finishedAt) holds is LOCAL wall-clock time. A fixture is
# always built from a UTC instant through ToLocalTime(), so the suite passes in any time zone: the library parses the
# string back with the same zone. The instants sit on 2026-10-27, away from any DST change of the common zones.
$LedgerT0 = [DateTimeOffset]::new(2026, 10, 27, 12, 0, 0, [TimeSpan]::Zero)

function ConvertTo-LocalStamp([DateTimeOffset]$At, [string]$Format = 'yyyy-MM-dd HH:mm') {
    return $At.ToLocalTime().ToString($Format, [Globalization.CultureInfo]::InvariantCulture)
}

# The UTC instant of the local start of a yyyy-MM-dd day (the oracle of leadSoFar).
function Get-LocalDayStartUtc([string]$Day) {
    $local = [DateTime]::SpecifyKind([DateTime]::ParseExact($Day, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture), [DateTimeKind]::Local)
    return ([DateTimeOffset]$local).ToUniversalTime()
}

# One ledger row of TASK-FLOW rule 3, as the ticket tool writes it (one JSON object per line).
function New-LedgerRow([string]$Id, [string]$Status, [DateTimeOffset]$Updated, [string]$Created = '2026-10-20', [int]$Priority = 50, [string]$Name = 'x', $Extra = $null) {
    $o = [ordered]@{ id = $Id; name = $Name; status = $Status; priority = $Priority; file = "PLAN/${Id}_$Name.md"; created = $Created
        updated = (ConvertTo-LocalStamp $Updated) }
    if ($null -ne $Extra) { foreach ($k in $Extra.Keys) { $o[$k] = $Extra[$k] } }
    return (ConvertTo-Json -InputObject $o -Compress)
}

# Writes the ledger (or with -Archive the archive) of a repository at the default paths; no line writes an empty file.
function Write-Ledger([string]$Repo, [string[]]$Lines = @(), [switch]$Archive) {
    $name = if ($Archive) { 'spec-catalog-archive.jsonl' } else { 'spec-catalog.jsonl' }
    $path = Join-Path $Repo "PLAN${sep}$name"
    if ($Lines.Count -eq 0) {
        New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
        [IO.File]::WriteAllBytes($path, [byte[]]@())
        return $path
    }
    Write-RawFile $path $Lines
    return $path
}

# A live pass as the dispatcher knows it: @{ repo; id; pass; startedAt; endedAt } (UTC; endedAt $null while running).
function New-LivePass([string]$Repo, [string]$Id, [string]$Pass, [DateTimeOffset]$Start, $End = $null) {
    return @{ repo = $Repo; id = $Id; pass = $Pass; startedAt = $Start; endedAt = $(if ($null -eq $End) { $null } else { [DateTimeOffset]$End }) }
}

# A repository runner row of rule 23 as a reader parses it (finishedAt a local string), plus the instance taken from
# the file name runs-<instance>.jsonl.
function New-RunRow([string]$Id, [string]$Before, [string]$After, [DateTimeOffset]$Finished, [string]$Instance = 'a') {
    $o = [ordered]@{ id = $Id; statusBefore = $Before; statusAfter = $After; moved = ($Before -cne $After); outcome = 'ok'; exitCode = 0
        minutes = 3; finishedAt = (ConvertTo-LocalStamp $Finished "yyyy-MM-dd'T'HH:mm:ss") }
    $row = ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $o -Compress) -DateKind String
    $row | Add-Member -NotePropertyName instance -NotePropertyValue $Instance
    return $row
}

# A transition of the shape Compare-PqLedgerSnapshot returns, for the actor cases: S0001 Draft -> Approved, in Draft
# since T0-60 min, moved at T0+2 min.
function New-TestTransition([string]$Id = 'S0001', [string]$From = 'Draft', [string]$To = 'Approved') {
    return [pscustomobject][ordered]@{ id = $Id; from = $From; to = $To; updatedFrom = (ConvertTo-LocalStamp $LedgerT0.AddMinutes(-60))
        updatedTo = (ConvertTo-LocalStamp $LedgerT0.AddMinutes(2)); created = '2026-10-20'; priority = 50 }
}

# The actor of New-TestTransition in the window [T0, T0+5 min] of repository fms.
function Get-TestActor($LivePasses, $Rows, $Transition = $null) {
    if ($null -eq $Transition) { $Transition = New-TestTransition }
    return (Resolve-PqActor -Transition $Transition -Repo 'fms' -LivePasses $LivePasses -RepoRunnerRows $Rows -WindowStart $LedgerT0 -WindowEnd $LedgerT0.AddMinutes(5))
}

# The eleven profile path keys Get-PqRepoPaths answers, each with the property that holds it. The eight of the 01.14
# drift guard (journal journalArchive releaseQueue releaseReady releaseQueueDone leasesDir queueRunsDir specsDir) plus
# tempDir and commandsDir, which Phase 06 names in the same result, and queueStopFile, the repository stop the rank
# honours (TASK-FLOW rule 26).
$RepoPathKeys = [ordered]@{ journal = 'Ledger'; journalArchive = 'Archive'; releaseQueue = 'Queue'; releaseReady = 'Ready'
    releaseQueueDone = 'Done'; leasesDir = 'LeasesDir'; queueRunsDir = 'RunsDir'; specsDir = 'SpecsDir'; tempDir = 'TempDir'
    commandsDir = 'CommandsDir'; queueStopFile = 'StopFile' }

# The drift-guard child, written once into the suite scratch: it dot-sources the REAL tools/harness/_profile.ps1 under
# SZA_PROJECT_ROOT and prints, as one JSON object, Get-SzaPath of every key, envPrefix, the project root and the lease
# store exactly as Get-LeaseStoreDir of batch/run-spec-queue.ps1 computes it.
function Get-ProfileProbe {
    $path = Join-Path $script:scratch 'profile-probe.ps1'
    if (Test-Path -LiteralPath $path) { return $path }
    $text = @'
param([string]$Harness, [string]$Keys)
$ErrorActionPreference = 'Stop'
. (Join-Path $Harness '_profile.ps1')
$o = [ordered]@{}
foreach ($k in ($Keys -split ',')) { $o[$k] = Get-SzaPath $k }
$o['envPrefix'] = [string](Get-SzaProfileValue 'envPrefix')
$o['root'] = Get-SzaProjectRoot
$leaseRoot = (Get-SzaEnv 'TICKET_LEASE_ROOT')
if ([string]::IsNullOrWhiteSpace($leaseRoot)) { $leaseRoot = Get-SzaProjectRoot }
$o['leaseStore'] = (Join-Path $leaseRoot (Get-SzaPath 'leasesDir' -Relative))
ConvertTo-Json -InputObject $o -Compress
'@
    [IO.File]::WriteAllText($path, $text.Replace("`r`n", "`n"), [Text.UTF8Encoding]::new($false))
    return $path
}

try {
    $scratch = Join-Path ([System.IO.Path]::GetTempPath()) ('s0015-events-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $scratch | Out-Null
    $sep = [IO.Path]::DirectorySeparatorChar

    # ---- paths: tools/harness/portfolio/lib/paths.ps1 (TASK-FLOW rule 41, S0015 D8) ----

    Test-Case 'paths: the default root is %USERPROFILE%\.sza\portfolio when SZA_PORTFOLIO_ROOT is unset' {
        . (Get-LibPath 'paths.ps1')
        $s = New-Scratch 'default'
        $home_ = Join-Path $s 'home'
        New-Item -ItemType Directory -Path $home_ | Out-Null
        $env:USERPROFILE = $home_
        Remove-Item Env:\SZA_PORTFOLIO_ROOT -ErrorAction SilentlyContinue
        $before = Get-Listing $s
        $root = Get-PqRoot
        Assert-That ($root -is [string]) "Get-PqRoot returned $($root.GetType().FullName), expected one string"
        $expected = Join-Path $home_ ".sza${sep}portfolio"
        Assert-That ($root -eq $expected) "Get-PqRoot returned '$root', expected '$expected'"
        $after = Get-Listing $s
        Assert-That (($before -join "`n") -eq ($after -join "`n")) "Get-PqRoot created something: $(($after | Where-Object { $_ -notin $before }) -join ', ')"
        Assert-That (-not (Test-Path -LiteralPath (Join-Path $home_ '.sza'))) 'Get-PqRoot created the .sza directory'
    }

    Test-Case 'paths: SZA_PORTFOLIO_ROOT wins and is returned normalised' {
        . (Get-LibPath 'paths.ps1')
        $s = New-Scratch 'explicit'
        $env:USERPROFILE = Join-Path $s 'home'
        $fwd = $s.Replace('\', '/')
        $env:SZA_PORTFOLIO_ROOT = "$fwd/state\\pq/portfolio/"
        $expected = Join-Path $s "state${sep}pq${sep}portfolio"
        $root = Get-PqRoot
        Assert-That ($root -eq $expected) "mixed, doubled and trailing separators: Get-PqRoot returned '$root', expected '$expected'"
        $env:SZA_PORTFOLIO_ROOT = "$s\other\portfolio\"
        $root = Get-PqRoot
        Assert-That ($root -eq (Join-Path $s "other${sep}portfolio")) "trailing separator: Get-PqRoot returned '$root'"
        Assert-That (-not $root.StartsWith($env:USERPROFILE, [StringComparison]::OrdinalIgnoreCase)) 'the USERPROFILE default won over SZA_PORTFOLIO_ROOT'
        Assert-That (@(Get-ChildItem -LiteralPath $s -Force).Count -eq 0) 'Get-PqRoot created something under the scratch directory'
    }

    Test-Case 'paths: ConvertTo-PqFullPath spells the drive letter in upper case and leaves the rest of the path alone' {
        . (Get-LibPath 'paths.ps1')
        if ($sep -ne '\') { return }   # a drive letter exists on Windows only
        Assert-That ((ConvertTo-PqFullPath 'p:\web\Some Repo\') -ceq 'P:\web\Some Repo') 'lowercase drive letter, mixed case below it and a trailing separator'
        Assert-That ((ConvertTo-PqFullPath 'p:/web/repo') -ceq 'P:\web\repo') 'lowercase drive letter with forward slashes'
        Assert-That ((ConvertTo-PqFullPath 'P:\web\repo') -ceq 'P:\web\repo') 'an upper-case drive letter is unchanged'
        Assert-That ((ConvertTo-PqFullPath 'c:\') -ceq 'C:\') 'a bare drive root keeps its separator'
    }

    Test-Case 'paths: a relative SZA_PORTFOLIO_ROOT is refused with PortfolioRootNotAbsolute' {
        . (Get-LibPath 'paths.ps1')
        $s = New-Scratch 'relative'
        Push-Location -LiteralPath $s
        try {
            foreach ($value in @('rel\portfolio', '.\portfolio', '..\portfolio', '\rooted-without-drive\portfolio', 'C:drive-relative')) {
                $env:SZA_PORTFOLIO_ROOT = $value
                Assert-Throws { Get-PqRoot } "PortfolioRootNotAbsolute: $value" "Get-PqRoot with SZA_PORTFOLIO_ROOT='$value'"
            }
        }
        finally { Pop-Location }
        Assert-That (@(Get-ChildItem -LiteralPath $s -Force).Count -eq 0) 'a refused root still created something'
    }

    Test-Case 'paths: a root inside a git working tree is refused with PortfolioRootInsideRepository' {
        . (Get-LibPath 'paths.ps1')
        $s = New-Scratch 'git'
        # Pass 1: a .git directory two levels above the root.
        $repo = Join-Path $s 'repo-dir'
        New-Item -ItemType Directory -Path (Join-Path $repo '.git') -Force | Out-Null
        $env:SZA_PORTFOLIO_ROOT = Join-Path $repo "state${sep}nested${sep}portfolio"
        Assert-Throws { Get-PqRoot } 'PortfolioRootInsideRepository: ' 'a root under a .git directory'
        # Pass 2: a .git file, as a worktree has, above the root.
        $wt = Join-Path $s 'repo-worktree'
        New-Item -ItemType Directory -Path $wt | Out-Null
        [IO.File]::WriteAllText((Join-Path $wt '.git'), "gitdir: C:/elsewhere/.git/worktrees/x`n")
        $env:SZA_PORTFOLIO_ROOT = Join-Path $wt "portfolio"
        Assert-Throws { Get-PqRoot } 'PortfolioRootInsideRepository: ' 'a root under a .git file'
        # Pass 3: the default root, when the profile directory itself is a working tree.
        $homeRepo = Join-Path $s 'home-repo'
        New-Item -ItemType Directory -Path (Join-Path $homeRepo '.git') -Force | Out-Null
        $env:USERPROFILE = $homeRepo
        Remove-Item Env:\SZA_PORTFOLIO_ROOT -ErrorAction SilentlyContinue
        Assert-Throws { Get-PqRoot } 'PortfolioRootInsideRepository: ' 'the default root under a profile that is a working tree'
        # A sibling of a repository is not inside it.
        $env:SZA_PORTFOLIO_ROOT = Join-Path $s "outside${sep}portfolio"
        $root = Get-PqRoot
        Assert-That ($root -eq (Join-Path $s "outside${sep}portfolio")) "a root beside the repositories was refused or changed: '$root'"
        Assert-That (-not (Test-Path -LiteralPath (Join-Path $s 'outside'))) 'Get-PqRoot created the root'
    }

    Test-Case 'paths: Initialize-PqRoot creates the root and log/ once and a second call changes nothing' {
        . (Get-LibPath 'paths.ps1')
        $s = New-Scratch 'init'
        $expected = Join-Path $s "a${sep}portfolio"
        $env:SZA_PORTFOLIO_ROOT = $expected
        $first = Initialize-PqRoot
        Assert-That ($first -eq $expected) "Initialize-PqRoot returned '$first', expected '$expected'"
        Assert-That (Test-Path -LiteralPath (Join-Path $expected 'log') -PathType Container) 'log/ was not created'
        $listing1 = Get-Listing $expected
        Assert-That (($listing1 -join ';') -match '^log\|dir\|\d+$') "the root holds more than log/: $($listing1 -join '; ')"
        $whole1 = Get-Listing $s
        Start-Sleep -Milliseconds 30
        $second = Initialize-PqRoot
        Assert-That ($second -eq $expected) "the second Initialize-PqRoot returned '$second'"
        $whole2 = Get-Listing $s
        Assert-That (($whole1 -join "`n") -eq ($whole2 -join "`n")) "the second call changed the tree: before [$($whole1 -join '; ')] after [$($whole2 -join '; ')]"
    }

    Test-Case 'paths: Get-PqPath returns the documented name for every kind and refuses an unknown kind with PqPathUnknownKind' {
        . (Get-LibPath 'paths.ps1')
        $s = New-Scratch 'kinds'
        $root = Join-Path $s 'portfolio'
        $env:SZA_PORTFOLIO_ROOT = $root
        $override = Join-Path $s "elsewhere${sep}MY_QUEUE.md"
        $rows = @(
            @{ Args = @{ Kind = 'registry' }; Rel = 'repos.json' }
            @{ Args = @{ Kind = 'queue' }; Rel = 'PORTFOLIO_QUEUE.md' }
            @{ Args = @{ Kind = 'queue'; Override = $override.Replace('\', '/') }; Abs = $override }
            @{ Args = @{ Kind = 'queue'; Override = "queues${sep}Q.md" }; Rel = "queues${sep}Q.md" }
            @{ Args = @{ Kind = 'runs' }; Rel = 'runs.jsonl' }
            @{ Args = @{ Kind = 'stop' }; Rel = 'STOP' }
            @{ Args = @{ Kind = 'stopTarget'; StopKind = 'worker'; Target = '3' }; Rel = 'STOP-worker__3' }
            @{ Args = @{ Kind = 'stopTarget'; StopKind = 'repo'; Target = 'fms-web' }; Rel = 'STOP-repo__fms-web' }
            @{ Args = @{ Kind = 'stopTarget'; StopKind = 'agent'; Target = 'codex' }; Rel = 'STOP-agent__codex' }
            @{ Args = @{ Kind = 'stopTarget'; StopKind = 'ticket'; Target = 'fms-web__S0028' }; Rel = 'STOP-ticket__fms-web__S0028' }
            @{ Args = @{ Kind = 'holds' }; Rel = 'holds' }
            @{ Args = @{ Kind = 'hold'; Agent = 'claude' }; Rel = "holds${sep}claude.json" }
            @{ Args = @{ Kind = 'run' }; Rel = 'run' }
            @{ Args = @{ Kind = 'runState' }; Rel = "run${sep}current.json" }
            @{ Args = @{ Kind = 'beat' }; Rel = "run${sep}beat" }
            @{ Args = @{ Kind = 'log' }; Rel = 'log' }
            @{ Args = @{ Kind = 'live' }; Rel = "log${sep}live" }
            @{ Args = @{ Kind = 'livePass'; Pass = 'R20261027T101500-ab12.3' }; Rel = "log${sep}live${sep}R20261027T101500-ab12.3.log" }
            @{ Args = @{ Kind = 'events'; Date = '2026-10-27'; Token = 'pq' }; Rel = "log${sep}events-2026-10-27.pq.jsonl" }
            @{ Args = @{ Kind = 'events'; Date = '2026-10-27'; Token = 'cli-4242' }; Rel = "log${sep}events-2026-10-27.cli-4242.jsonl" }
            @{ Args = @{ Kind = 'resources' }; Rel = 'resources' }
            @{ Args = @{ Kind = 'resourceToken'; Token = 'build'; Repo = 'fms-web'; Id = 'S0028' }; Rel = "resources${sep}build${sep}fms-web__S0028.json" }
            @{ Args = @{ Kind = 'resourceToken'; Token = 'emulator'; Repo = 'fms-a'; Id = 'S0101' }; Rel = "resources${sep}emulator${sep}fms-a__S0101.json" }
            @{ Args = @{ Kind = 'monitor' }; Rel = "monitor${sep}index.html" }
            @{ Args = @{ Kind = 'reports' }; Rel = 'reports' }
        )
        foreach ($row in $rows) {
            $a = $row.Args
            $label = ($a.GetEnumerator() | Sort-Object Key | ForEach-Object { "-$($_.Key) $($_.Value)" }) -join ' '
            $got = Get-PqPath @a
            $want = if ($row.ContainsKey('Abs')) { $row.Abs } else { Join-Path $root $row.Rel }
            Assert-That ($got -is [string]) "Get-PqPath $label returned $(if ($null -eq $got) { 'null' } else { $got.GetType().FullName }), expected one string"
            Assert-That ($got -eq $want) "Get-PqPath $label returned '$got', expected '$want'"
        }
        Assert-Throws { Get-PqPath -Kind 'nosuchkind' } 'PqPathUnknownKind: nosuchkind' 'an unknown kind'
        # Arguments that would leave their directory, or a malformed date, are refused, not built.
        $bad = @(
            @{ Kind = 'hold'; Agent = "..${sep}x" }
            @{ Kind = 'hold'; Agent = 'a/b' }
            @{ Kind = 'livePass'; Pass = 'a\b' }
            @{ Kind = 'events'; Date = '2026-10-27'; Token = '..' }
            @{ Kind = 'events'; Date = '27.10.2026'; Token = 'pq' }
            @{ Kind = 'stopTarget'; StopKind = 'repo'; Target = "..${sep}..${sep}x" }
            @{ Kind = 'stopTarget'; StopKind = 'nosuch'; Target = 'x' }
            @{ Kind = 'resourceToken'; Token = 'device'; Repo = 'fms-a'; Id = 'S0001' }
            @{ Kind = 'resourceToken'; Token = 'build'; Repo = 'a/b'; Id = 'S0001' }
            @{ Kind = 'hold' }
        )
        foreach ($a in $bad) {
            $label = ($a.GetEnumerator() | Sort-Object Key | ForEach-Object { "-$($_.Key) $($_.Value)" }) -join ' '
            Assert-Throws { Get-PqPath @a } 'PqPathArgumentInvalid: ' "Get-PqPath $label"
        }
        Assert-That (-not (Test-Path -LiteralPath $root)) 'Get-PqPath created the root'
    }

    Test-Case 'paths: nothing outside the root is created' {
        . (Get-LibPath 'paths.ps1')
        $s = New-Scratch 'outside'
        $parent = Join-Path $s 'parent'
        New-Item -ItemType Directory -Path $parent | Out-Null
        [IO.File]::WriteAllText((Join-Path $parent 'sibling.txt'), 'x')
        $root = Join-Path $parent 'portfolio'
        $env:SZA_PORTFOLIO_ROOT = $root
        $before = Get-Listing $parent
        $null = Get-PqRoot
        $null = Initialize-PqRoot
        $null = Initialize-PqRoot
        foreach ($k in 'registry', 'queue', 'runs', 'stop', 'holds', 'run', 'runState', 'beat', 'log', 'live', 'resources', 'monitor', 'reports') { $null = Get-PqPath -Kind $k }
        $null = Get-PqPath -Kind hold -Agent claude
        $null = Get-PqPath -Kind livePass -Pass 'p.1'
        $null = Get-PqPath -Kind events -Date '2026-10-27' -Token pq
        $null = Get-PqPath -Kind stopTarget -StopKind ticket -Target 'k__S0001'
        $null = Get-PqPath -Kind resourceToken -Token build -Repo k -Id S0001
        $all = Get-Listing $parent
        $after = @($all | Where-Object { -not ($_.StartsWith('portfolio|') -or $_.StartsWith("portfolio$sep")) })
        Assert-That ((@($before) -join "`n") -eq ($after -join "`n")) "something outside the root changed: before [$(@($before) -join '; ')] after [$($after -join '; ')]"
        $inside = @(Get-ChildItem -LiteralPath $root -Recurse -Force | ForEach-Object { $_.FullName.Substring($root.Length + 1) })
        Assert-That (($inside -join ',') -eq 'log') "the root holds more than log/: $($inside -join ', ')"
        Assert-That (@(Get-ChildItem -LiteralPath $s -Force).Count -eq 1) "the case directory gained an entry beside parent/: $((Get-ChildItem -LiteralPath $s -Force).Name -join ', ')"
    }

    Test-Case 'paths: the library loads under Set-StrictMode -Version Latest and prints nothing' {
        $lib = Get-LibPath 'paths.ps1'
        # In this process (the suite runs under StrictMode Latest): dot-sourcing and the calls yield only their values.
        $loaded = @(. $lib)
        Assert-That ($loaded.Count -eq 0) "dot-sourcing paths.ps1 wrote $($loaded.Count) object(s) to the output stream: $($loaded -join ' | ')"
        $s = New-Scratch 'strict'
        $env:SZA_PORTFOLIO_ROOT = Join-Path $s 'portfolio'
        $r = @(Get-PqRoot)
        Assert-That ($r.Count -eq 1) "Get-PqRoot wrote $($r.Count) objects"
        $p = @(Get-PqPath -Kind registry)
        Assert-That ($p.Count -eq 1) "Get-PqPath wrote $($p.Count) objects"
        $i = @(Initialize-PqRoot)
        Assert-That ($i.Count -eq 1) "Initialize-PqRoot wrote $($i.Count) objects"
        # In a fresh process: nothing on any stream, no preference changed.
        $child = Join-Path $s 'load-strict.ps1'
        [IO.File]::WriteAllText($child, @'
param([string]$Lib)
Set-StrictMode -Version Latest
$prefs = { @($ErrorActionPreference, $WarningPreference, $VerbosePreference, $DebugPreference, $InformationPreference, $ProgressPreference, $ConfirmPreference) -join ',' }
$before = & $prefs
$out = @(. $Lib)
$root = Get-PqRoot
$path = Get-PqPath -Kind runState
$init = Initialize-PqRoot
$after = & $prefs
[Console]::Out.Write("LOADED out=$($out.Count) prefs=$(if ($before -eq $after) { 'same' } else { "changed:$before->$after" })")
'@)
        $res = Invoke-Child -Script $child -Arguments @($lib) -Environment @{ SZA_PORTFOLIO_ROOT = (Join-Path $s 'child-portfolio') }
        Assert-That ($res.code -eq 0) "the child exited $($res.code): $($res.output)"
        Assert-That ($res.stderr.Trim() -eq '') "the child wrote to stderr: $($res.stderr.Trim())"
        Assert-That ($res.stdout -eq 'LOADED out=0 prefs=same') "the child printed '$($res.stdout)', expected only 'LOADED out=0 prefs=same'"
    }

    # ---- writer: tools/harness/portfolio/lib/events.ps1, the writer core (TASK-FLOW rules 53-54) ----

    Test-Case 'writer: the envelope has exactly the 14 keys in the documented order, nulls explicit' {
        . (Get-LibPath 'events.ps1')
        $s = New-Scratch 'envelope'
        $env:SZA_PORTFOLIO_ROOT = Join-Path $s 'portfolio'
        $null = New-TestClock ([DateTimeOffset]::new(2026, 10, 27, 10, 15, 30, 123, [TimeSpan]::Zero))
        $h = Open-PqLog -Writer pq -Run 'R20261027T101530-ab12'
        Assert-That ((Write-PqEvent -Ev 'run.heartbeat') -eq $true) 'an event with no correlation keys was not written'
        Assert-That ((Write-PqEvent -Ev 'pass.launch' -Repo 'fms-web' -Id 'S0001' -Pass 'R20261027T101530-ab12.1' -Worker 2 -Agent 'claude' -Model 'claude-opus-4' -Cx 'C3' -D @{ pid = 4100 }) -eq $true) 'an event with every key was not written'
        Assert-That ((Write-PqEvent -Ev 'run.heartbeat' -Run 'R20261027T101531-cd34') -eq $true) 'an event with -Run was not written'
        $w = Open-PqLog -Writer w1
        Assert-That ((Write-PqEvent -Log $w -Ev 'pass.beat') -eq $true) 'an event of a log with no run was not written'
        Close-PqLog -Log $h
        Close-PqLog -Log $w
        $raw = Read-Lines $h.Path
        Assert-That ($raw.Count -eq 3) "the pq file holds $($raw.Count) lines, expected 3"
        $parsed = Get-FileEvents $h.Path
        foreach ($o in $parsed) {
            $k = Get-Keys $o
            Assert-That ($k -ceq $EnvelopeKeys) "seq $($o.seq): keys '$k', expected '$EnvelopeKeys'"
        }
        foreach ($k in 'repo', 'id', 'pass', 'worker', 'agent', 'model', 'cx') {
            Assert-That ($raw[0].Contains("`"${k}`":null")) "the bare event does not carry an explicit `"${k}`":null: $($raw[0])"
            Assert-That ($null -eq $parsed[0].$k) "the bare event has $k = '$($parsed[0].$k)'"
        }
        Assert-That ($parsed[0].run -ceq 'R20261027T101530-ab12') "run '$($parsed[0].run)' is not the handle's run"
        $full = $parsed[1]
        $want = [ordered]@{ ev = 'pass.launch'; repo = 'fms-web'; id = 'S0001'; pass = 'R20261027T101530-ab12.1'; worker = 2; agent = 'claude'; model = 'claude-opus-4'; cx = 'C3'; wr = 'pq' }
        foreach ($k in $want.Keys) { Assert-That ($full.$k -eq $want[$k]) "the full event has $k = '$($full.$k)', expected '$($want[$k])'" }
        Assert-That ($full.d.pid -eq 4100) "d.pid is '$($full.d.pid)'"
        Assert-That ($parsed[2].run -ceq 'R20261027T101531-cd34') "-Run did not win over the handle's run: '$($parsed[2].run)'"
        $wraw = Read-Lines $w.Path
        Assert-That ($wraw.Count -eq 1 -and $wraw[0].Contains('"run":null')) "a log opened without -Run did not write an explicit run null: $($wraw -join ' | ')"
        Assert-That ((Get-Keys (Get-FileEvents $w.Path)[0]) -ceq $EnvelopeKeys) 'the w1 line has another key order'
    }

    Test-Case 'writer: v is the integer 1, seq and worker are integers, d is an object even when empty' {
        . (Get-LibPath 'events.ps1')
        $s = New-Scratch 'types'
        $env:SZA_PORTFOLIO_ROOT = Join-Path $s 'portfolio'
        $null = New-TestClock ([DateTimeOffset]::new(2026, 10, 27, 10, 0, 0, 0, [TimeSpan]::Zero))
        $h = Open-PqLog -Writer w3
        $null = Write-PqEvent -Log $h -Ev 'pass.beat' -Worker 3
        $null = Write-PqEvent -Log $h -Ev 'pass.beat' -Worker '4' -D @{}
        $null = Write-PqEvent -Log $h -Ev 'run.heartbeat'
        Close-PqLog -Log $h
        $raw = Read-Lines $h.Path
        $parsed = Get-FileEvents $h.Path
        Assert-That ($parsed.Count -eq 3) "expected 3 events, found $($parsed.Count)"
        foreach ($o in $parsed) {
            Assert-That (($o.v -is [long] -or $o.v -is [int]) -and $o.v -eq 1) "v is $($o.v) of type $($o.v.GetType().Name), expected the integer 1"
            Assert-That ($o.seq -is [long] -or $o.seq -is [int]) "seq is of type $($o.seq.GetType().Name)"
            Assert-That ($o.d -is [System.Management.Automation.PSCustomObject]) "d is $(if ($null -eq $o.d) { 'null' } else { $o.d.GetType().Name }), expected an object"
        }
        Assert-That (($parsed[0].worker -is [long] -or $parsed[0].worker -is [int]) -and $parsed[0].worker -eq 3) "worker is '$($parsed[0].worker)' of type $($parsed[0].worker.GetType().Name)"
        Assert-That (($parsed[1].worker -is [long] -or $parsed[1].worker -is [int]) -and $parsed[1].worker -eq 4) "a string -Worker '4' was not written as the integer 4: $($raw[1])"
        Assert-That ($null -eq $parsed[2].worker) 'an event without -Worker has a worker'
        Assert-That ($raw[0].Contains('"v":1,') -and $raw[0].Contains('"seq":1,') -and $raw[0].Contains('"worker":3,')) "the integers are not bare JSON numbers: $($raw[0])"
        foreach ($i in 1, 2) { Assert-That ($raw[$i].EndsWith('"d":{}}')) "line $($i + 1) does not end with an empty d object: $($raw[$i])" }
    }

    Test-Case 'writer: ts is UTC with milliseconds and a trailing Z' {
        . (Get-LibPath 'events.ps1')
        $s = New-Scratch 'ts'
        $env:SZA_PORTFOLIO_ROOT = Join-Path $s 'portfolio'
        # 01:05:07.009 at +02:00 is 23:05:07.009Z of the day before: both the text and the file date must be UTC.
        $null = New-TestClock ([DateTimeOffset]::new(2026, 10, 27, 1, 5, 7, 9, [TimeSpan]::FromHours(2)))
        $h = Open-PqLog -Writer pq
        $null = Write-PqEvent -Ev 'run.heartbeat'
        Close-PqLog -Log $h
        $o = (Get-FileEvents $h.Path)[0]
        Assert-That ($o.ts -is [string]) 'ts did not stay a string'
        Assert-That ($o.ts -ceq '2026-10-26T23:05:07.009Z') "ts is '$($o.ts)', expected '2026-10-26T23:05:07.009Z'"
        Assert-That ((Split-Path -Leaf $h.Path) -ceq 'events-2026-10-26.pq.jsonl') "the file is $(Split-Path -Leaf $h.Path), expected the UTC date 2026-10-26"
        Assert-That ($h.Date -ceq '2026-10-26') "the handle date is '$($h.Date)'"
    }

    Test-Case 'writer: the file is UTF-8 without a BOM, LF-terminated, one object per line, Russian text round-trips' {
        . (Get-LibPath 'events.ps1')
        $s = New-Scratch 'bytes'
        $env:SZA_PORTFOLIO_ROOT = Join-Path $s 'portfolio'
        $null = New-TestClock ([DateTimeOffset]::new(2026, 10, 27, 12, 0, 0, 0, [TimeSpan]::Zero))
        $why = 'Очередь пуста'
        $h = Open-PqLog -Writer pq
        $null = Write-PqEvent -Ev 'wait.enter' -D @{ why = $why }
        $null = Write-PqEvent -Ev 'inbox.add' -D @{ why = "two`nlines`r`nand a tab`t"; kind = 'finding' }
        $null = Write-PqEvent -Ev 'run.heartbeat'
        Close-PqLog -Log $h
        $bytes = [IO.File]::ReadAllBytes($h.Path)
        Assert-That (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)) 'the file starts with a UTF-8 BOM'
        Assert-That ($bytes -notcontains [byte]13) 'the file contains a CR byte'
        Assert-That ($bytes[-1] -eq 10) 'the file does not end with LF'
        $lf = @($bytes | Where-Object { $_ -eq 10 }).Count
        Assert-That ($lf -eq 3) "the file holds $lf LF bytes for 3 events (a raw LF inside a value?)"
        $text = [Text.Encoding]::UTF8.GetString($bytes)
        Assert-That ($text.Contains($why)) 'the Russian text is not in the file as UTF-8 (escaped away?)'
        $parsed = Get-FileEvents $h.Path
        Assert-That ($parsed.Count -eq 3) "expected 3 objects, parsed $($parsed.Count)"
        Assert-That ($parsed[0].d.why -ceq $why) "d.why read back as '$($parsed[0].d.why)'"
        Assert-That ($parsed[1].d.why -ceq "two`nlines`r`nand a tab`t") 'a value with LF, CR and TAB did not round-trip'
    }

    Test-Case 'writer: the file is log/events-<UTC date>.<wr>.jsonl and nothing else is created' {
        . (Get-LibPath 'events.ps1')
        $s = New-Scratch 'name'
        $root = Join-Path $s 'portfolio'
        $env:SZA_PORTFOLIO_ROOT = $root
        $null = New-TestClock ([DateTimeOffset]::new(2026, 10, 27, 8, 30, 0, 0, [TimeSpan]::Zero))
        $h = Open-PqLog -Writer pq
        $null = Write-PqEvent -Ev 'run.start'
        $null = Write-PqEvent -Ev 'run.end'
        $expected = Join-Path $root "log${sep}events-2026-10-27.pq.jsonl"
        Assert-That ($h.Path -eq $expected) "the handle path is '$($h.Path)', expected '$expected'"
        foreach ($p in @{ Writer = 'pq'; Token = 'pq'; Date = '2026-10-27'; State = 'open'; Seq = 2 }.GetEnumerator()) {
            Assert-That ($h.($p.Key) -eq $p.Value) "the handle has $($p.Key) = '$($h.($p.Key))', expected '$($p.Value)'"
        }
        Close-PqLog -Log $h
        $listing = Get-Listing $root
        $names = @($listing | ForEach-Object { $_.Split('|')[0] })
        $want = @('log', "log${sep}events-2026-10-27.pq.jsonl")
        Assert-That (($names -join ',') -ceq ($want -join ',')) "the root holds [$($names -join ', ')], expected [$($want -join ', ')]"
        $outside = @(Get-ChildItem -LiteralPath $s -Force | ForEach-Object { $_.Name })
        Assert-That (($outside -join ',') -ceq 'portfolio') "the case directory holds [$($outside -join ', ')] beside the root"
    }

    Test-Case 'writer: seq starts at 1 and rises by 1 per event' {
        . (Get-LibPath 'events.ps1')
        $s = New-Scratch 'seq'
        $env:SZA_PORTFOLIO_ROOT = Join-Path $s 'portfolio'
        $null = New-TestClock ([DateTimeOffset]::new(2026, 10, 27, 9, 0, 0, 0, [TimeSpan]::Zero))
        $h = Open-PqLog -Writer pq
        Assert-That ($h.Seq -eq 0) "a new handle has Seq $($h.Seq), expected 0 (none used)"
        for ($i = 1; $i -le 7; $i++) {
            $null = Write-PqEvent -Ev 'poll.change' -D @{ n = $i }
            Assert-That ($h.Seq -eq $i) "after $i events the handle Seq is $($h.Seq)"
        }
        Close-PqLog -Log $h
        $seqs = @((Get-FileEvents $h.Path) | ForEach-Object { $_.seq })
        Assert-That (($seqs -join ',') -eq '1,2,3,4,5,6,7') "seq in the file is [$($seqs -join ',')], expected 1..7"
    }

    Test-Case 'writer: Set-PqClock drives ts and the file date and Reset-PqClock restores the system clock' {
        . (Get-LibPath 'events.ps1')
        $s = New-Scratch 'clock'
        $env:SZA_PORTFOLIO_ROOT = Join-Path $s 'portfolio'
        $clock = New-TestClock ([DateTimeOffset]::new(2031, 1, 2, 3, 4, 5, 678, [TimeSpan]::Zero))
        $n = Get-PqNow
        Assert-That ($n -is [DateTimeOffset]) "Get-PqNow returned $($n.GetType().FullName)"
        Assert-That ($n.UtcDateTime -eq [datetime]::new(2031, 1, 2, 3, 4, 5, 678, [DateTimeKind]::Utc) -and $n.Offset -eq [TimeSpan]::Zero) "Get-PqNow returned $($n.ToString('o')) under the seam"
        $h = Open-PqLog -Writer pq
        $null = Write-PqEvent -Ev 'run.start'
        $clock.now = [DateTimeOffset]::new(2031, 1, 2, 3, 4, 6, 1, [TimeSpan]::FromHours(-5))
        Assert-That ((Get-PqNow).Offset -eq [TimeSpan]::Zero) 'Get-PqNow did not convert a -05:00 seam value to UTC'
        $null = Write-PqEvent -Ev 'run.end'
        Close-PqLog -Log $h
        Assert-That ((Split-Path -Leaf $h.Path) -ceq 'events-2031-01-02.pq.jsonl') "the file date did not follow the seam: $(Split-Path -Leaf $h.Path)"
        $ts = @((Get-FileEvents $h.Path) | ForEach-Object { $_.ts })
        Assert-That (($ts -join ',') -ceq '2031-01-02T03:04:05.678Z,2031-01-02T08:04:06.001Z') "ts followed the seam as [$($ts -join ',')]"
        Reset-PqClock
        $a = [DateTimeOffset]::UtcNow
        $now = Get-PqNow
        $b = [DateTimeOffset]::UtcNow
        Assert-That ($now -ge $a -and $now -le $b) "after Reset-PqClock Get-PqNow returned $($now.ToString('o')), outside [$($a.ToString('o')), $($b.ToString('o'))]"
        Assert-That ($now.Offset -eq [TimeSpan]::Zero) "after Reset-PqClock Get-PqNow has offset $($now.Offset)"
    }

    Test-Case 'writer: an unknown event name throws under -Strict' {
        . (Get-LibPath 'events.ps1')
        $s = New-Scratch 'strict'
        $env:SZA_PORTFOLIO_ROOT = Join-Path $s 'portfolio'
        $null = New-TestClock ([DateTimeOffset]::new(2026, 10, 27, 9, 0, 0, 0, [TimeSpan]::Zero))
        $names = @(Get-PqEventNames)
        Assert-That ($names -ccontains 'run.start' -and $names -ccontains 'log.error' -and $names -notcontains 'no.suchEvent') 'Get-PqEventNames does not look like the catalog'
        $h = Open-PqLog -Writer pq -Strict
        Assert-That ($h.Strict -eq $true) 'the handle opened with -Strict does not say so'
        Assert-Throws { Write-PqEvent -Ev 'no.suchEvent' } 'UnknownEventName: no.suchEvent' 'an unknown name under -Strict'
        Assert-Throws { Write-PqEvent -Ev 'run.Start' } 'UnknownEventName: run.Start' 'a name differing only in case under -Strict'
        Assert-That ($h.Seq -eq 0) "a refused name consumed seq $($h.Seq)"
        Assert-That ((Write-PqEvent -Ev 'run.start') -eq $true) 'a known name under -Strict was not written'
        Close-PqLog -Log $h
        $seqs = @((Get-FileEvents $h.Path) | ForEach-Object { "$($_.seq):$($_.ev)" })
        Assert-That (($seqs -join ',') -ceq '1:run.start') "the file holds [$($seqs -join ',')], expected only 1:run.start"
    }

    Test-Case 'writer: several writers open in one process write to files of their own' {
        . (Get-LibPath 'events.ps1')
        $s = New-Scratch 'many'
        $root = Join-Path $s 'portfolio'
        $env:SZA_PORTFOLIO_ROOT = $root
        $null = New-TestClock ([DateTimeOffset]::new(2026, 10, 27, 9, 0, 0, 0, [TimeSpan]::Zero))
        foreach ($bad in 'PQ', 'w0', 'w', 'x', 'w1a', 'cli-1') {
            Assert-Throws { Open-PqLog -Writer $bad } "WriterNameInvalid: $bad" "Open-PqLog -Writer '$bad'"
        }
        $pq = Open-PqLog -Writer pq
        $w1 = Open-PqLog -Writer w1
        $w2 = Open-PqLog -Writer w2
        $plan = @('pq', 'w1', 'pq', 'w2', 'w1', 'pq', 'w2', 'w2', 'w2')
        foreach ($wr in $plan) { Assert-That ((Write-PqEvent -Writer $wr -Ev 'poll.change') -eq $true) "a write to $wr failed" }
        foreach ($h in $pq, $w1, $w2) { Close-PqLog -Log $h }
        $paths = @($pq.Path, $w1.Path, $w2.Path | Sort-Object -Unique)
        Assert-That ($paths.Count -eq 3) 'two writers share a file'
        foreach ($h in $pq, $w1, $w2) {
            $want = @($plan | Where-Object { $_ -ceq $h.Writer }).Count
            $parsed = Get-FileEvents $h.Path
            $seqs = @($parsed | ForEach-Object { $_.seq }) -join ','
            Assert-That ($seqs -eq ((1..$want) -join ',')) "$($h.Writer): seq [$seqs], expected 1..$want"
            Assert-That (@($parsed | Where-Object { $_.wr -cne $h.Writer }).Count -eq 0) "$($h.Writer): a line carries another writer"
            Assert-That ((Split-Path -Leaf $h.Path) -ceq "events-2026-10-27.$($h.Writer).jsonl") "$($h.Writer): file $(Split-Path -Leaf $h.Path)"
        }
    }

    Test-Case 'writer: without -Log or -Writer the first opened log is used; with none open the call returns false and throws nothing' {
        . (Get-LibPath 'events.ps1')
        $s = New-Scratch 'default'
        $env:SZA_PORTFOLIO_ROOT = Join-Path $s 'portfolio'
        $null = New-TestClock ([DateTimeOffset]::new(2026, 10, 27, 9, 0, 0, 0, [TimeSpan]::Zero))
        $r = @(Write-PqEvent -Ev 'run.heartbeat')
        Assert-That ($r.Count -eq 1 -and $r[0] -is [bool] -and $r[0] -eq $false) "with no log open the call returned [$($r -join ',')], expected one false"
        Assert-That (@(Write-PqEvent -Writer 'w9' -Ev 'run.heartbeat')[0] -eq $false) 'a write to a writer that is not open did not return false'
        $w1 = Open-PqLog -Writer w1
        $pq = Open-PqLog -Writer pq
        $again = Open-PqLog -Writer w1
        Assert-That ([object]::ReferenceEquals($again, $w1)) 'opening an open writer again did not return its handle'
        $r = @(Write-PqEvent -Ev 'pass.beat')
        Assert-That ($r.Count -eq 1 -and $r[0] -is [bool] -and $r[0] -eq $true) "a default write returned [$($r -join ',')], expected one true"
        $null = Write-PqEvent -Writer pq -Ev 'run.heartbeat'
        $null = Write-PqEvent -Log $pq -Ev 'run.heartbeat'
        Assert-That ($w1.Seq -eq 1 -and $pq.Seq -eq 2) "the default went elsewhere: w1 Seq $($w1.Seq), pq Seq $($pq.Seq)"
        Close-PqLog -Writer w1
        Assert-That ($w1.State -ne 'open') "a closed handle has State '$($w1.State)'"
        $null = Write-PqEvent -Ev 'run.heartbeat'
        Assert-That ($pq.Seq -eq 3) "after w1 closed the default did not move to pq: pq Seq $($pq.Seq)"
        Assert-That (@(Write-PqEvent -Log $w1 -Ev 'pass.beat')[0] -eq $false) 'a write to a closed handle did not return false'
        Close-PqLog
        $r = @(Write-PqEvent -Ev 'run.heartbeat')
        Assert-That ($r.Count -eq 1 -and $r[0] -eq $false) 'after every log closed a write did not return false'
        $w1lines = @((Get-FileEvents $w1.Path) | ForEach-Object { $_.ev })
        $pqlines = @((Get-FileEvents $pq.Path) | ForEach-Object { $_.ev })
        Assert-That (($w1lines -join ',') -ceq 'pass.beat') "w1 holds [$($w1lines -join ',')]"
        Assert-That (($pqlines -join ',') -ceq 'run.heartbeat,run.heartbeat,run.heartbeat') "pq holds [$($pqlines -join ',')]"
    }

    # ---- reader: events.ps1 continuation, Read-PqDay, Merge-PqDay, Test-PqEnvelope, the name registry (rules 53-57) ----

    Test-Case 'reader: reopening the same day file continues after its last seq' {
        . (Get-LibPath 'events.ps1')
        $s = New-Scratch 'reopen'
        $env:SZA_PORTFOLIO_ROOT = Join-Path $s 'portfolio'
        $null = New-TestClock ([DateTimeOffset]::new(2026, 10, 27, 9, 0, 0, 0, [TimeSpan]::Zero))
        $h = Open-PqLog -Writer pq
        foreach ($i in 1..3) { $null = Write-PqEvent -Ev 'poll.change' }
        Close-PqLog -Log $h
        $h2 = Open-PqLog -Writer pq
        Assert-That ($h2.Path -eq $h.Path) 'the reopened handle names another file'
        Assert-That ($h2.Seq -eq 3) "the reopened handle has Seq $($h2.Seq), expected 3"
        Assert-That ((Write-PqEvent -Ev 'poll.change') -eq $true) 'the write after the reopen failed'
        Close-PqLog -Log $h2
        $seqs = @((Get-FileEvents $h.Path) | ForEach-Object { $_.seq }) -join ','
        Assert-That ($seqs -eq '1,2,3,4') "seq in the file is [$seqs], expected 1,2,3,4"
        # A file whose last complete line carries no seq continues from the last line that does. An array-wrapped seq
        # is no seq (review finding 7: a one-element array must not unroll to its element).
        $w1Path = Get-PqPath -Kind events -Date '2026-10-27' -Token w1
        Write-RawFile $w1Path @(@(1..41 | ForEach-Object { New-EventLine $_ -Wr w1 }) + '{"v":1,"seq":[500]}' + 'not json, cut by a crash')
        $w = Open-PqLog -Writer w1
        Assert-That ($w.Seq -eq 41) "a file ending in an unparsable line reopened at Seq $($w.Seq), expected 41"
        $null = Write-PqEvent -Log $w -Ev 'pass.beat'
        Close-PqLog -Log $w
        $last = ConvertFrom-Json -InputObject (Read-Lines $w1Path)[-1] -DateKind String
        Assert-That ($last.seq -eq 42 -and $last.ev -ceq 'pass.beat') "the next event has seq $($last.seq), expected 42"
    }

    Test-Case 'reader: reopening a file whose last line is partial starts the next event on a new line' {
        . (Get-LibPath 'events.ps1')
        $s = New-Scratch 'partial'
        $env:SZA_PORTFOLIO_ROOT = Join-Path $s 'portfolio'
        $null = New-TestClock ([DateTimeOffset]::new(2026, 10, 27, 9, 0, 0, 0, [TimeSpan]::Zero))
        $h = Open-PqLog -Writer pq
        $null = Write-PqEvent -Ev 'run.start'
        $null = Write-PqEvent -Ev 'poll.change'
        Close-PqLog -Log $h
        Write-RawFile $h.Path @('{"v":1,') -NoFinalLf -Append
        $h2 = Open-PqLog -Writer pq
        Assert-That ($h2.Seq -eq 2) "the reopened handle has Seq $($h2.Seq), expected 2 (the partial line has none)"
        Assert-That ((Write-PqEvent -Ev 'run.end') -eq $true) 'the write after the partial line failed'
        Close-PqLog -Log $h2
        $parts = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($h.Path)).Split("`n")
        Assert-That ($parts.Count -eq 5 -and $parts[4] -eq '') "the file splits into $($parts.Count) segments, expected 4 LF-terminated lines"
        Assert-That ($parts[2] -ceq '{"v":1,') "the partial line is not alone on its line: '$($parts[2])'"
        $o = ConvertFrom-Json -InputObject $parts[3] -DateKind String
        Assert-That ($o.seq -eq 3 -and $o.ev -ceq 'run.end') "the line after the partial one is '$($parts[3])'"
        $r = Read-PqDay -Path $h.Path
        Assert-That ($r.events.Count -eq 3) "Read-PqDay returned $($r.events.Count) events, expected 3"
        Assert-That ($r.bad -eq 1) "Read-PqDay counted $($r.bad) bad lines, expected 1"
        Assert-That ($null -eq $r.partial) "Read-PqDay reports a partial tail '$($r.partial)'"
        Assert-That (@($r.gaps).Count -eq 0) "Read-PqDay reports $(@($r.gaps).Count) gaps"
    }

    # Review finding 9: a seq ConvertFrom-Json reads as a BigInteger above Int64 made every reopen throw, so the writer
    # stayed degraded for the rest of the day; such a seq is no seq, for the writer, the validator and the gap walk.
    Test-Case 'reader: a seq beyond Int64 or wrapped in an array is no seq - the writer opens and continues from the last valid seq' {
        . (Get-LibPath 'events.ps1')
        $s = New-Scratch 'hugeseq'
        $root = Join-Path $s 'portfolio'
        $env:SZA_PORTFOLIO_ROOT = $root
        $null = New-TestClock ([DateTimeOffset]::new(2026, 10, 27, 9, 0, 0, 0, [TimeSpan]::Zero))
        $path = Get-PqPath -Kind events -Date '2026-10-27' -Token pq
        $huge = (New-EventLine 4 -Ev 'run.heartbeat').Replace('"seq":4,', '"seq":99999999999999999999,')
        Write-RawFile $path @((New-EventLine 1 -Ev 'run.start'), (New-EventLine 2), (New-EventLine 3), $huge, '{"seq":[500]}')
        $h = Open-PqLog -Writer pq
        Assert-That ($h.State -ceq 'open') "a file ending in a huge seq opened '$($h.State)' (PendingError '$($h.PendingError)'), expected open"
        Assert-That ($h.Seq -eq 3) "the handle continues at Seq $($h.Seq), expected 3 (the last valid seq)"
        foreach ($i in 1..2) { Assert-That ((Write-PqEvent -Ev 'run.heartbeat' -D @{ n = $i }) -eq $true) "write $i after the huge seq failed" }
        Close-PqLog -Log $h
        $lines = Read-Lines $path
        $tail = @($lines[-2], $lines[-1] | ForEach-Object { $o = ConvertFrom-Json -InputObject $_ -DateKind String; "$($o.seq):$($o.ev)" }) -join ','
        Assert-That ($tail -ceq '4:run.heartbeat,5:run.heartbeat') "the writer appended [$tail], expected [4:run.heartbeat,5:run.heartbeat]"
        Assert-That (@(Test-PqEnvelope -Line $huge) -ccontains 'seq-not-positive-int') "Test-PqEnvelope of the huge seq gave [$(@(Test-PqEnvelope -Line $huge) -join ',')]"
        $r = Read-PqDay -Path $path
        # The huge line is v 1 with a bad seq (bad); the array line has no v (unsupported); neither enters the walk.
        Assert-That ($r.events.Count -eq 5 -and $r.bad -eq 1 -and $r.unsupported -eq 1 -and @($r.gaps).Count -eq 0) "Read-PqDay reads events $($r.events.Count) bad $($r.bad) unsupported $($r.unsupported) gaps $(@($r.gaps).Count), expected 5, 1, 1, 0"
    }

    Test-Case 'reader: Read-PqDay reports a gap with the missing numbers, and a file that starts above 1 reports 1..first-1' {
        . (Get-LibPath 'events.ps1')
        $s = New-Scratch 'gap'
        $a = Join-Path $s 'a.jsonl'
        Write-RawFile $a @((New-EventLine 1), (New-EventLine 2), (New-EventLine 5))
        $r = Read-PqDay -Path $a
        Assert-That ($r.events.Count -eq 3) "file a: $($r.events.Count) events"
        $g = @($r.gaps)
        Assert-That ($g.Count -eq 1) "file a: $($g.Count) gaps, expected 1"
        Assert-That ($g[0].after -eq 2 -and (@($g[0].missing) -join ',') -eq '3,4' -and $g[0].explained -eq $false) "file a: gap after $($g[0].after) missing [$(@($g[0].missing) -join ',')] explained $($g[0].explained)"
        $b = Join-Path $s 'b.jsonl'
        Write-RawFile $b @((New-EventLine 3), (New-EventLine 4))
        $g = @((Read-PqDay -Path $b).gaps)
        Assert-That ($g.Count -eq 1) "file b: $($g.Count) gaps, expected 1"
        Assert-That ($g[0].after -eq 0 -and (@($g[0].missing) -join ',') -eq '1,2' -and $g[0].explained -eq $false) "file b: gap after $($g[0].after) missing [$(@($g[0].missing) -join ',')]"
        $c = Join-Path $s 'c.jsonl'
        Write-RawFile $c @((New-EventLine 1), (New-EventLine 2), (New-EventLine 3))
        Assert-That (@((Read-PqDay -Path $c).gaps).Count -eq 0) 'a file without a gap reports one'
    }

    Test-Case 'reader: a gap followed by log.error whose dropped equals the gap size is explained, any other gap is not' {
        . (Get-LibPath 'events.ps1')
        $s = New-Scratch 'explained'
        $a = Join-Path $s 'a.jsonl'
        Write-RawFile $a @(
            (New-EventLine 1), (New-EventLine 2),
            (New-EventLine 5 -Ev 'log.error' -D ([ordered]@{ err = 'disk full'; dropped = 2 })),
            (New-EventLine 6),
            (New-EventLine 9 -Ev 'log.error' -D ([ordered]@{ err = 'disk full'; dropped = 1 })),
            (New-EventLine 10),
            (New-EventLine 12),
            (New-EventLine 14 -Ev 'log.rotate' -D ([ordered]@{ dropped = 1 })),
            (New-EventLine 16 -Ev 'log.error' -D ([ordered]@{ err = 'no dropped key' }))
        )
        $g = @((Read-PqDay -Path $a).gaps)
        $got = @($g | ForEach-Object { "$($_.after):$(@($_.missing) -join '+'):$($_.explained)" }) -join ' '
        $want = '2:3+4:True 6:7+8:False 10:11:False 12:13:False 14:15:False'
        Assert-That ($got -ceq $want) "gaps [$got], expected [$want]"
        $b = Join-Path $s 'b.jsonl'
        Write-RawFile $b @((New-EventLine 3 -Ev 'log.error' -D ([ordered]@{ err = 'x'; dropped = 2 })), (New-EventLine 4))
        $g = @((Read-PqDay -Path $b).gaps)
        Assert-That ($g.Count -eq 1 -and $g[0].after -eq 0 -and $g[0].explained -eq $true) "a file starting at a log.error with dropped 2 at seq 3: gaps [$(@($g | ForEach-Object { "$($_.after):$($_.explained)" }) -join ' ')]"
    }

    Test-Case 'reader: an unparsable line is skipped and counted in bad' {
        . (Get-LibPath 'events.ps1')
        $s = New-Scratch 'bad'
        $a = Join-Path $s 'a.jsonl'
        Write-RawFile $a @((New-EventLine 1), 'this is not json', '[1,2,3]', '"a string"', 'null', '{"v":1,"ts":', '', (New-EventLine 2))
        $r = Read-PqDay -Path $a
        foreach ($k in 'events', 'bad', 'unsupported', 'partial', 'gaps') { Assert-That ($r.ContainsKey($k)) "the result has no key '$k'" }
        Assert-That ($r.bad -eq 6) "bad is $($r.bad), expected 6"
        Assert-That ($r.unsupported -eq 0) "unsupported is $($r.unsupported)"
        $seqs = @($r.events | ForEach-Object { $_.seq }) -join ','
        Assert-That ($seqs -eq '1,2') "the events are [$seqs], expected 1,2"
        Assert-That (@($r.gaps).Count -eq 0) 'the bad lines made a gap'
    }

    Test-Case 'reader: a line with an unknown v is skipped and counted in unsupported' {
        . (Get-LibPath 'events.ps1')
        $s = New-Scratch 'version'
        $a = Join-Path $s 'a.jsonl'
        Write-RawFile $a @(
            (New-EventLine 1),
            (New-EventLine 2).Replace('"v":1,', '"v":2,'),
            (New-EventLine 3).Replace('"v":1,', '"v":"1",'),
            (New-EventLine 4).Replace('"v":1,', ''),
            (New-EventLine 5)
        )
        $r = Read-PqDay -Path $a
        Assert-That ($r.unsupported -eq 3) "unsupported is $($r.unsupported), expected 3 (v 2, v as a string, no v)"
        Assert-That ($r.bad -eq 0) "bad is $($r.bad)"
        $seqs = @($r.events | ForEach-Object { $_.seq }) -join ','
        Assert-That ($seqs -eq '1,5') "the events are [$seqs], expected 1,5"
        Assert-That (@($r.gaps).Count -eq 0) 'lines that were written but are of another version were reported as lost (a gap)'
    }

    Test-Case 'reader: a trailing line without LF is not returned and not counted until it is complete' {
        . (Get-LibPath 'events.ps1')
        $s = New-Scratch 'tail'
        $a = Join-Path $s 'a.jsonl'
        $l2 = New-EventLine 2
        Write-RawFile $a @((New-EventLine 1), $l2) -NoFinalLf
        $r = Read-PqDay -Path $a
        Assert-That ($r.events.Count -eq 1 -and $r.bad -eq 0) "a complete object without LF: $($r.events.Count) events, $($r.bad) bad, expected 1 and 0"
        Assert-That ($r.partial -ceq $l2) "partial is '$($r.partial)', expected the held-back line"
        Write-RawFile $a @('') -NoFinalLf:$false -Append
        $r = Read-PqDay -Path $a
        Assert-That ($r.events.Count -eq 2 -and $null -eq $r.partial) "after its LF: $($r.events.Count) events, partial '$($r.partial)'"
        $l3 = New-EventLine 3
        $cut = [int]($l3.Length / 2)
        Write-RawFile $a @($l3.Substring(0, $cut)) -NoFinalLf -Append
        $r = Read-PqDay -Path $a
        Assert-That ($r.events.Count -eq 2 -and $r.bad -eq 0) "a half-written line was counted: $($r.events.Count) events, $($r.bad) bad"
        Assert-That ($r.partial -ceq $l3.Substring(0, $cut)) "partial is '$($r.partial)'"
        Write-RawFile $a @($l3.Substring($cut)) -Append
        $r = Read-PqDay -Path $a
        Assert-That ($r.events.Count -eq 3 -and $r.bad -eq 0 -and $null -eq $r.partial) "the completed line: $($r.events.Count) events, $($r.bad) bad, partial '$($r.partial)'"
    }

    Test-Case 'reader: a file read while its writer holds it open returns every complete line' {
        . (Get-LibPath 'events.ps1')
        $s = New-Scratch 'live'
        $env:SZA_PORTFOLIO_ROOT = Join-Path $s 'portfolio'
        $null = New-TestClock ([DateTimeOffset]::new(2026, 10, 27, 9, 0, 0, 0, [TimeSpan]::Zero))
        $h = Open-PqLog -Writer pq
        foreach ($i in 1..5) { $null = Write-PqEvent -Ev 'poll.change' -D @{ n = $i } }
        $r = Read-PqDay -Path $h.Path
        Assert-That ($r.events.Count -eq 5 -and $r.bad -eq 0 -and $null -eq $r.partial) "while open: $($r.events.Count) events, $($r.bad) bad"
        foreach ($i in 6..7) { Assert-That ((Write-PqEvent -Ev 'poll.change' -D @{ n = $i }) -eq $true) "the write of event $i after a read failed" }
        $r = Read-PqDay -Path $h.Path
        Assert-That ($r.events.Count -eq 7) "the second read returned $($r.events.Count) events, expected 7"
        Assert-That ($h.State -eq 'open') "the reads disturbed the writer: State '$($h.State)'"
        Close-PqLog -Log $h
        Assert-That ((Read-PqDay -Path $h.Path).events.Count -eq 7) 'the read after the close lost events'
    }

    Test-Case 'reader: Merge-PqDay orders several writers by ts, then wr, then seq' {
        . (Get-LibPath 'events.ps1')
        $s = New-Scratch 'merge'
        $root = Join-Path $s 'portfolio'
        $log = Join-Path $root 'log'
        $t0 = '2026-10-27T10:00:00.000Z'; $t1 = '2026-10-27T10:00:00.500Z'; $t2 = '2026-10-27T10:00:01.000Z'; $t3 = '2026-10-27T10:00:02.000Z'
        $f = { param($tok) Join-Path $log "events-2026-10-27.$tok.jsonl" }
        Write-RawFile (& $f 'w2') @((New-EventLine 1 -Wr w2 -Ts $t1), 'oops', (New-EventLine 2 -Wr w2 -Ts $t3))
        Write-RawFile (& $f 'w1') @((New-EventLine 1 -Wr w1 -Ts $t0), (New-EventLine 2 -Wr w1 -Ts $t0), (New-EventLine 3 -Wr w1 -Ts $t2), (New-EventLine 5 -Wr w1 -Ts $t3))
        Write-RawFile (& $f 'pq') @((New-EventLine 1 -Wr pq -Ts $t0), (New-EventLine 2 -Wr pq -Ts $t1))
        Write-RawFile (& $f 'imp-4242') @((New-EventLine 1 -Wr imp -Ts $t1))
        Write-RawFile (& $f 'w10') @((New-EventLine 1 -Wr w10 -Ts $t0))
        # Two processes of one multi-process writer: the file read first holds the higher seq.
        Write-RawFile (& $f 'cli-100') @((New-EventLine 2 -Wr cli -Ts $t2))
        Write-RawFile (& $f 'cli-300') @((New-EventLine 1 -Wr cli -Ts $t2))
        # Not of this day, or not an event file: never merged.
        Write-RawFile (Join-Path $log 'events-2026-10-26.pq.jsonl') @((New-EventLine 1 -Wr pq -Ts '2026-10-26T10:00:00.000Z'))
        Write-RawFile (Join-Path $log 'events-2026-10-27.pq.jsonl.bak') @((New-EventLine 1 -Wr pq -Ts $t0))
        Write-RawFile (Join-Path $log 'notes.txt') @('not an event')
        $m = Merge-PqDay -Root $root -Date '2026-10-27'
        $got = @($m.events | ForEach-Object { "$($_.wr):$($_.seq)" }) -join ','
        $want = 'pq:1,w1:1,w1:2,w10:1,imp:1,pq:2,w2:1,cli:1,cli:2,w1:3,w1:5,w2:2'
        Assert-That ($got -ceq $want) "merged order [$got], expected [$want]"
        Assert-That ($m.bad -eq 1) "bad is $($m.bad), expected 1"
        $gaps = @($m.gaps | ForEach-Object { "$($_.file):$($_.after):$(@($_.missing) -join '+')" } | Sort-Object) -join ' '
        $wantGaps = 'events-2026-10-27.cli-100.jsonl:0:1 events-2026-10-27.w1.jsonl:3:4'
        Assert-That ($gaps -ceq $wantGaps) "gaps [$gaps], expected [$wantGaps]"
        $empty = Merge-PqDay -Root $root -Date '2026-10-25'
        Assert-That ($empty.events.Count -eq 0 -and $empty.bad -eq 0) 'a day without files returned events'
    }

    Test-Case 'reader: Test-PqEnvelope accepts a valid line and ignores unknown fields and unknown d keys' {
        . (Get-LibPath 'events.ps1')
        $line = New-EventLine 1 -Ev 'run.start' -D ([ordered]@{ mode = 'mono'; slots = 1 })
        $c = @(Test-PqEnvelope -Line $line)
        Assert-That ($c.Count -eq 0) "a valid line produced [$($c -join ',')]"
        $extra = $line.Replace('"v":1,', '"v":1,"zz":1,"future":{"x":[1,2]},').Replace('"mode":"mono"', '"mode":"mono","unknownKey":{"deep":true}')
        $c = @(Test-PqEnvelope -Line $extra)
        Assert-That ($c.Count -eq 0) "unknown fields or d keys produced [$($c -join ',')]"
        $c = @(Test-PqEnvelope -Line (New-EventLine 2 -Ev 'some.futureEvent'))
        Assert-That ($c.Count -eq 0) "an event name the registry does not know produced [$($c -join ',')]"
        $c = @(Test-PqEnvelope -Line (ConvertFrom-Json -InputObject $extra -DateKind String))
        Assert-That ($c.Count -eq 0) "an already-parsed object produced [$($c -join ',')]"
    }

    Test-Case 'reader: Test-PqEnvelope names each violation with its rule code' {
        . (Get-LibPath 'events.ps1')
        $base = New-EventLine 7 -Ev 'run.heartbeat'
        $rows = @(
            @{ Line = $base.Substring(0, 40); Want = 'not-json' }
            @{ Line = $base.Replace('"v":1,', '"v":2,'); Want = 'v-not-1' }
            @{ Line = $base.Replace('10:00:00.000Z', '10:00:00Z'); Want = 'ts-format' }
            @{ Line = $base.Replace('"seq":7,', '"seq":0,'); Want = 'seq-not-positive-int' }
            @{ Line = $base.Replace('"ev":"run.heartbeat",', ''); Want = 'missing-key:ev' }
            @{ Line = $base.Replace('"run.heartbeat"', '"runheartbeat"'); Want = 'ev-not-dotted' }
            @{ Line = $base.Replace('"d":{}', '"d":[]'); Want = 'd-not-object' }
            # Beyond the seven of the vector: more spellings of the same codes, and the order of precedence.
            @{ Line = '[1,2]'; Want = 'not-json' }
            @{ Line = ''; Want = 'not-json' }
            @{ Line = $base.Replace('"v":1,', '"v":true,'); Want = 'v-not-1' }
            @{ Line = $base.Replace('2026-10-27T', '2026-13-45T'); Want = 'ts-format' }
            @{ Line = $base.Replace('"seq":7,', '"seq":1.5,'); Want = 'seq-not-positive-int' }
            @{ Line = $base.Replace('"seq":7,', '"seq":"7",'); Want = 'seq-not-positive-int' }
            @{ Line = $base.Replace(',"d":{}', ''); Want = 'missing-key:d' }
            @{ Line = $base.Replace('"d":{}', '"d":null'); Want = 'd-not-object' }
            @{ Line = $base.Replace('"ev":"run.heartbeat"', '"ev":null'); Want = 'ev-not-dotted' }
            @{ Line = $base.Replace('"v":1,', '"v":2,').Replace('"d":{}', '"d":[]'); Want = 'v-not-1,d-not-object' }
            # Array-wrapped scalars are not the scalar (review finding 7), and a seq beyond Int64 is no positive
            # integer seq (review finding 9).
            @{ Line = $base.Replace('"v":1,', '"v":[1],'); Want = 'v-not-1' }
            @{ Line = $base.Replace('"v":1,', '"v":[],'); Want = 'v-not-1' }
            @{ Line = $base.Replace('"ts":"2026-10-27T10:00:00.000Z"', '"ts":["2026-10-27T10:00:00.000Z"]'); Want = 'ts-format' }
            @{ Line = $base.Replace('"seq":7,', '"seq":[7],'); Want = 'seq-not-positive-int' }
            @{ Line = $base.Replace('"seq":7,', '"seq":99999999999999999999,'); Want = 'seq-not-positive-int' }
            @{ Line = $base.Replace('"ev":"run.heartbeat"', '"ev":["run.heartbeat"]'); Want = 'ev-not-dotted' }
        )
        foreach ($row in $rows) {
            $got = @(Test-PqEnvelope -Line $row.Line) -join ','
            Assert-That ($got -ceq $row.Want) "line '$($row.Line)' produced [$got], expected [$($row.Want)]"
        }
        $parsed = ConvertFrom-Json -InputObject $base.Replace('"d":{}', '"d":[]') -DateKind String -NoEnumerate
        $got = @(Test-PqEnvelope -Line $parsed) -join ','
        Assert-That ($got -ceq 'd-not-object') "the parsed d-not-object line produced [$got]"
    }

    $namesCase = 'reader: Get-PqEventNames equals the distinct names of the catalog EVENTS.md'
    if (-not $CatalogRoot) { Skip-Case $namesCase 'no -CatalogRoot given' }
    else {
        Test-Case $namesCase {
            . (Get-LibPath 'events.ps1')
            $file = Join-Path $CatalogRoot "task-flow${sep}EVENTS.md"
            Assert-That (Test-Path -LiteralPath $file -PathType Leaf) "the catalog has no $file"
            # The expression of Phase 00 step 00.7: first-column cells, a cell may hold several names separated by ' / '.
            $catalog = @(Get-Content -LiteralPath $file | Where-Object { $_ -match '^\| `[a-z]+\.[A-Za-z]+`' } |
                    ForEach-Object { [regex]::Matches(($_ -split '\|')[1], '`([a-z]+\.[A-Za-z]+)`') } |
                    ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
            Assert-That ($catalog.Count -gt 0) 'no event name was extracted from the catalog'
            $names = @(Get-PqEventNames)
            $distinct = @($names | Sort-Object -Unique -CaseSensitive)
            Assert-That ($distinct.Count -eq $names.Count) "Get-PqEventNames holds duplicates: $($names.Count) names, $($distinct.Count) distinct"
            $sorted = [string[]]$names.Clone()
            [Array]::Sort($sorted, [StringComparer]::Ordinal)
            Assert-That (($sorted -join ',') -ceq ($names -join ',')) 'Get-PqEventNames is not sorted ordinally'
            $diff = @(Compare-Object -ReferenceObject $catalog -DifferenceObject $names -CaseSensitive)
            $only = @($diff | ForEach-Object { "$($_.SideIndicator) $($_.InputObject)" }) -join ', '
            Assert-That ($diff.Count -eq 0) "the registry and the catalog differ (<= catalog only, => registry only): $only"
            Assert-That ($names.Count -eq $catalog.Count) "Get-PqEventNames holds $($names.Count) names, the catalog $($catalog.Count)"
        }
    }

    # ---- failopen: events.ps1 fail-open and the gaps that explain themselves (TASK-FLOW rule 55) ----
    # A write is made to fail by a directory with the name of the day file; removing it lets the writer recover.

    Test-Case 'failopen: a failing write returns false and throws nothing' {
        . (Get-LibPath 'events.ps1')
        $s = New-Scratch 'failwrite'
        $env:SZA_PORTFOLIO_ROOT = Join-Path $s 'portfolio'
        $null = New-TestClock ([DateTimeOffset]::new(2026, 10, 27, 10, 0, 0, 0, [TimeSpan]::Zero))
        $block = Get-PqPath -Kind events -Date '2026-10-27' -Token pq
        New-Item -ItemType Directory -Path $block -Force | Out-Null
        $opened = @(Open-PqLog -Writer pq)
        Assert-That ($opened.Count -eq 1) "Open-PqLog of an unopenable file wrote $($opened.Count) objects, expected one handle"
        $h = $opened[0]
        Assert-That ($h.State -ceq 'degraded') "the handle of an unopenable file has State '$($h.State)', expected 'degraded'"
        foreach ($call in @({ Write-PqEvent -Ev 'run.heartbeat' }, { Write-PqEvent -Log $h -Ev 'pass.beat' }, { Write-PqEvent -Writer pq -Ev 'poll.change' -D @{ n = 1 } })) {
            $r = @(& $call)
            Assert-That ($r.Count -eq 1 -and $r[0] -is [bool] -and $r[0] -eq $false) "a failing write returned [$($r -join ',')], expected one false"
        }
        Assert-That ($h.State -ceq 'degraded') "after failing writes the handle has State '$($h.State)'"
        # A write that fails on an open stream (the stream is gone under the writer) is swallowed the same way.
        Remove-Item -LiteralPath $block -Force
        Assert-That ((Write-PqEvent -Ev 'run.heartbeat') -eq $true) 'the write after the block was removed failed'
        Assert-That ($h.State -ceq 'open') "the recovered handle has State '$($h.State)'"
        $h.Stream.Dispose()
        $r = @(Write-PqEvent -Ev 'run.heartbeat')
        Assert-That ($r.Count -eq 1 -and $r[0] -eq $false) "a write on a broken stream returned [$($r -join ',')], expected one false"
        Assert-That ($h.State -ceq 'degraded') "after a write on a broken stream the handle has State '$($h.State)'"
        Assert-That ((Write-PqEvent -Ev 'run.heartbeat') -eq $true) 'the write after the broken stream did not recover'
        # Closing a degraded handle throws nothing either.
        $wBlock = Get-PqPath -Kind events -Date '2026-10-27' -Token w1
        New-Item -ItemType Directory -Path $wBlock -Force | Out-Null
        $w = Open-PqLog -Writer w1
        Assert-That ($w.State -ceq 'degraded') "the w1 handle has State '$($w.State)'"
        Close-PqLog -Log $w
        Assert-That ($w.State -ceq 'closed') "a closed degraded handle has State '$($w.State)'"
        Close-PqLog -Log $h
        Assert-KnownEvents (Join-Path $s 'portfolio')
    }

    Test-Case 'failopen: the next good write is preceded by log.error carrying err and dropped' {
        . (Get-LibPath 'events.ps1')
        $s = New-Scratch 'report'
        # The portfolio root lies under the profile, so the error text names the profile directory and must not.
        $env:USERPROFILE = $s
        $env:SZA_PORTFOLIO_ROOT = Join-Path $s 'portfolio'
        $null = New-TestClock ([DateTimeOffset]::new(2026, 10, 27, 10, 0, 0, 0, [TimeSpan]::Zero))
        $block = Get-PqPath -Kind events -Date '2026-10-27' -Token pq
        New-Item -ItemType Directory -Path $block -Force | Out-Null
        $h = Open-PqLog -Writer pq
        $null = Write-PqEvent -Ev 'pass.beat'
        Remove-Item -LiteralPath $block -Force
        Assert-That ((Write-PqEvent -Ev 'run.heartbeat' -D @{ n = 1 }) -eq $true) 'the good write failed'
        Close-PqLog -Log $h
        $e = Get-FileEvents $h.Path
        Assert-That ($e.Count -eq 2) "the file holds $($e.Count) events, expected log.error and the event"
        Assert-That ($e[0].ev -ceq 'log.error' -and $e[1].ev -ceq 'run.heartbeat' -and $e[1].d.n -eq 1) "the file holds [$(@($e | ForEach-Object { $_.ev }) -join ',')], expected log.error then run.heartbeat"
        $err = $e[0].d.err
        Assert-That ($err -is [string] -and $err.Trim().Length -gt 0) "log.error d.err is '$err', expected a non-empty message"
        Assert-That ($e[0].d.dropped -eq 1) "log.error d.dropped is '$($e[0].d.dropped)', expected 1"
        $profileForms = @($s, $s.Replace('\', '/'))
        foreach ($p in $profileForms) { Assert-That ($err.IndexOf($p, [StringComparison]::OrdinalIgnoreCase) -lt 0) "d.err names the profile directory: $err" }
        Assert-That ($err.Contains('~')) "d.err does not show the profile as ~: $err"
        # Three lost on another writer: one report of all three.
        $wBlock = Get-PqPath -Kind events -Date '2026-10-27' -Token w1
        New-Item -ItemType Directory -Path $wBlock -Force | Out-Null
        $w = Open-PqLog -Writer w1
        foreach ($i in 1..3) { Assert-That ((Write-PqEvent -Log $w -Ev 'pass.beat') -eq $false) "lost write $i returned true" }
        Remove-Item -LiteralPath $wBlock -Force
        Assert-That ((Write-PqEvent -Log $w -Ev 'pass.end') -eq $true) 'the good w1 write failed'
        Close-PqLog -Log $w
        $e = Get-FileEvents $w.Path
        $got = @($e | ForEach-Object { "$($_.seq):$($_.ev)" }) -join ','
        Assert-That ($got -ceq '4:log.error,5:pass.end') "w1 holds [$got], expected 4:log.error,5:pass.end"
        Assert-That ($e[0].d.dropped -eq 3) "w1 log.error d.dropped is '$($e[0].d.dropped)', expected 3"
        Assert-KnownEvents (Join-Path $s 'portfolio')
    }

    Test-Case 'failopen: a dropped event still consumes its seq, and log.error dropped equals the gap' {
        . (Get-LibPath 'events.ps1')
        $s = New-Scratch 'gapseq'
        $env:SZA_PORTFOLIO_ROOT = Join-Path $s 'portfolio'
        $null = New-TestClock ([DateTimeOffset]::new(2026, 10, 27, 10, 0, 0, 0, [TimeSpan]::Zero))
        $block = Get-PqPath -Kind events -Date '2026-10-27' -Token pq
        New-Item -ItemType Directory -Path $block -Force | Out-Null
        $h = Open-PqLog -Writer pq
        Assert-That ($h.Seq -eq 0 -and $h.Dropped -eq 0) "the degraded handle starts at Seq $($h.Seq), Dropped $($h.Dropped)"
        foreach ($i in 1..2) {
            $null = Write-PqEvent -Ev 'poll.change' -D @{ n = $i }
            Assert-That ($h.Seq -eq $i -and $h.Dropped -eq $i) "after lost write $i the handle has Seq $($h.Seq), Dropped $($h.Dropped), expected $i and $i"
        }
        Remove-Item -LiteralPath $block -Force
        Assert-That ((Write-PqEvent -Ev 'poll.change' -D @{ n = 3 }) -eq $true) 'the recovering write failed'
        Assert-That ($h.Seq -eq 4 -and $h.Dropped -eq 0) "after recovery the handle has Seq $($h.Seq), Dropped $($h.Dropped), expected 4 and 0"
        $e = Get-FileEvents $h.Path
        $got = @($e | ForEach-Object { "$($_.seq):$($_.ev)" }) -join ','
        Assert-That ($got -ceq '3:log.error,4:poll.change') "the file holds [$got], expected 3:log.error,4:poll.change"
        Assert-That ($e[0].d.dropped -eq 2 -and $e[1].d.n -eq 3) "log.error dropped $($e[0].d.dropped), the event n $($e[1].d.n)"
        $r = Read-PqDay -Path $h.Path
        $g = @($r.gaps)
        Assert-That ($g.Count -eq 1 -and $g[0].after -eq 0 -and (@($g[0].missing) -join ',') -eq '1,2' -and $g[0].explained -eq $true) "Read-PqDay gaps [$(@($g | ForEach-Object { "$($_.after):$(@($_.missing) -join '+'):$($_.explained)" }) -join ' ')], expected [0:1+2:True]"
        # A loss on an open stream, then a reopen of the partly lost file: the greater of the file's last seq (4)
        # and the handle's (5) wins, so the lost number stays lost and the gap stays explained.
        $h.Stream.Dispose()
        Assert-That ((Write-PqEvent -Ev 'poll.change' -D @{ n = 4 }) -eq $false) 'the write on a broken stream returned true'
        Assert-That ($h.Seq -eq 5) "the lost write on a broken stream left Seq $($h.Seq), expected 5"
        Assert-That ((Write-PqEvent -Ev 'poll.change' -D @{ n = 5 }) -eq $true) 'the write after the broken stream failed'
        Close-PqLog -Log $h
        $e = Get-FileEvents $h.Path
        $got = @($e | ForEach-Object { "$($_.seq):$($_.ev)" }) -join ','
        Assert-That ($got -ceq '3:log.error,4:poll.change,6:log.error,7:poll.change') "the file holds [$got], expected 3:log.error,4:poll.change,6:log.error,7:poll.change"
        $g = @((Read-PqDay -Path $h.Path).gaps)
        $gotGaps = @($g | ForEach-Object { "$($_.after):$(@($_.missing) -join '+'):$($_.explained)" }) -join ' '
        Assert-That ($gotGaps -ceq '0:1+2:True 4:5:True') "Read-PqDay gaps [$gotGaps], expected [0:1+2:True 4:5:True]"
        Assert-KnownEvents (Join-Path $s 'portfolio')
    }

    Test-Case 'failopen: dropped resets to zero after it is reported' {
        . (Get-LibPath 'events.ps1')
        $s = New-Scratch 'reset'
        $env:SZA_PORTFOLIO_ROOT = Join-Path $s 'portfolio'
        $null = New-TestClock ([DateTimeOffset]::new(2026, 10, 27, 10, 0, 0, 0, [TimeSpan]::Zero))
        $block = Get-PqPath -Kind events -Date '2026-10-27' -Token pq
        New-Item -ItemType Directory -Path $block -Force | Out-Null
        $h = Open-PqLog -Writer pq
        $null = Write-PqEvent -Ev 'poll.change'
        $null = Write-PqEvent -Ev 'poll.change'
        Remove-Item -LiteralPath $block -Force
        $null = Write-PqEvent -Ev 'poll.change'
        Assert-That ($h.Dropped -eq 0) "after the report the handle has Dropped $($h.Dropped), expected 0"
        $null = Write-PqEvent -Ev 'poll.change'
        $h.Stream.Dispose()
        $null = Write-PqEvent -Ev 'poll.change'
        Assert-That ($h.Dropped -eq 1) "after one more loss the handle has Dropped $($h.Dropped), expected 1 (not 3)"
        $null = Write-PqEvent -Ev 'poll.change'
        $null = Write-PqEvent -Ev 'poll.change'
        Close-PqLog -Log $h
        $e = Get-FileEvents $h.Path
        $got = @($e | ForEach-Object { if ($_.ev -ceq 'log.error') { "$($_.seq):log.error($($_.d.dropped))" } else { "$($_.seq):$($_.ev)" } }) -join ','
        $want = '3:log.error(2),4:poll.change,5:poll.change,7:log.error(1),8:poll.change,9:poll.change'
        Assert-That ($got -ceq $want) "the file holds [$got], expected [$want]"
        Assert-KnownEvents (Join-Path $s 'portfolio')
    }

    # Review finding 2: log.error means a failed write (rule 55, EVENTS.md 3.9) and rule 57 forbids giving a name
    # another meaning, so a well-formed name the catalog does not know is written as given and reported by nothing.
    Test-Case 'failopen: an unknown event name outside -Strict is written as given and adds no log.error' {
        . (Get-LibPath 'events.ps1')
        $s = New-Scratch 'unknown'
        $env:SZA_PORTFOLIO_ROOT = Join-Path $s 'portfolio'
        $null = New-TestClock ([DateTimeOffset]::new(2026, 10, 27, 10, 0, 0, 0, [TimeSpan]::Zero))
        $h = Open-PqLog -Writer pq
        Assert-That ((Write-PqEvent -Ev 'no.suchEvent' -D @{ n = 1 }) -eq $true) 'an unknown name outside -Strict was not written'
        Assert-That ((Write-PqEvent -Ev 'no.suchEvent' -D @{ n = 2 }) -eq $true) 'the second use of the unknown name was not written'
        Assert-That ((Write-PqEvent -Ev 'other.typo') -eq $true) 'a second unknown name was not written'
        Assert-That ((Write-PqEvent -Ev 'run.heartbeat') -eq $true) 'a known name was not written'
        $w = Open-PqLog -Writer w1
        $null = Write-PqEvent -Log $w -Ev 'no.suchEvent'
        Close-PqLog -Log $h
        Close-PqLog -Log $w
        $e = Get-FileEvents $h.Path
        $got = @($e | ForEach-Object { "$($_.seq):$($_.ev)" }) -join ','
        $want = '1:no.suchEvent,2:no.suchEvent,3:other.typo,4:run.heartbeat'
        Assert-That ($got -ceq $want) "the pq file holds [$got], expected [$want] (no log.error: an unknown name is not a failed write)"
        Assert-That ($e[0].d.n -eq 1 -and $e[1].d.n -eq 2) 'the unknown-name events lost their data'
        $we = @((Get-FileEvents $w.Path) | ForEach-Object { "$($_.seq):$($_.ev)" }) -join ','
        Assert-That ($we -ceq '1:no.suchEvent') "the w1 file holds [$we], expected [1:no.suchEvent]"
        $r = Read-PqDay -Path $h.Path
        Assert-That ($r.bad -eq 0 -and @($r.gaps).Count -eq 0 -and $r.events.Count -eq 4) "Read-PqDay reads bad $($r.bad), gaps $(@($r.gaps).Count), events $($r.events.Count), expected 0, 0, 4"
        Assert-That ($h.Errors -eq 0 -and $null -eq $h.PendingError) "an unknown name counted as a failure: Errors $($h.Errors), PendingError '$($h.PendingError)'"
    }

    # Review finding 11: a name the validator rejects (rule 53, ev-not-dotted) is never written; outside -Strict it is a
    # lost event, numbered and reported like any other loss.
    Test-Case 'failopen: a malformed event name outside -Strict is a lost event whose gap the next log.error explains' {
        . (Get-LibPath 'events.ps1')
        $s = New-Scratch 'badname'
        $root = Join-Path $s 'portfolio'
        $env:SZA_PORTFOLIO_ROOT = $root
        $null = New-TestClock ([DateTimeOffset]::new(2026, 10, 27, 10, 0, 0, 0, [TimeSpan]::Zero))
        $h = Open-PqLog -Writer pq
        Assert-That ((Write-PqEvent -Ev 'run.start') -eq $true) 'the first write failed'
        foreach ($call in @({ Write-PqEvent -Ev 'foo' }, { Write-PqEvent -Ev '' }, { Write-PqEvent -Ev $null }, { Write-PqEvent -D @{ n = 1 } }, { Write-PqEvent -Ev 'Run.start' })) {
            $r = @(& $call)
            Assert-That ($r.Count -eq 1 -and $r[0] -is [bool] -and $r[0] -eq $false) "the malformed call { $call } returned [$($r -join ',')], expected one false"
        }
        Assert-That ($h.State -ceq 'open') "a malformed name changed the handle State to '$($h.State)'"
        Assert-That ($h.Seq -eq 6 -and $h.Dropped -eq 5) "after five malformed names the handle has Seq $($h.Seq), Dropped $($h.Dropped), expected 6 and 5"
        Assert-That ((Write-PqEvent -Ev 'run.heartbeat') -eq $true) 'the good write after the malformed names failed'
        Close-PqLog -Log $h
        $e = Get-FileEvents $h.Path
        $got = @($e | ForEach-Object { "$($_.seq):$($_.ev)" }) -join ','
        Assert-That ($got -ceq '1:run.start,7:log.error,8:run.heartbeat') "the file holds [$got], expected [1:run.start,7:log.error,8:run.heartbeat]"
        Assert-That ($e[1].d.dropped -eq 5) "log.error dropped is $($e[1].d.dropped), expected 5"
        Assert-That (([string]$e[1].d.err).StartsWith('invalid event name: ', [StringComparison]::Ordinal)) "log.error err is '$($e[1].d.err)', expected 'invalid event name: ..'"
        $day = Read-PqDay -Path $h.Path
        $gotGaps = @($day.gaps | ForEach-Object { "$($_.after):$(@($_.missing) -join '+'):$($_.explained)" }) -join ' '
        Assert-That ($day.bad -eq 0 -and $gotGaps -ceq '1:2+3+4+5+6:True') "Read-PqDay reads bad $($day.bad) gaps [$gotGaps], expected 0 and [1:2+3+4+5+6:True]"
        foreach ($line in (Read-Lines $h.Path)) {
            $codes = @(Test-PqEnvelope -Line $line)
            Assert-That ($codes.Count -eq 0) "the writer wrote a line its own validator rejects [$($codes -join ',')]: $line"
        }
        # Under -Strict a malformed name throws, as an unknown one does, and consumes nothing.
        $w = Open-PqLog -Writer w1 -Strict
        Assert-Throws { Write-PqEvent -Log $w -Ev 'foo' } 'UnknownEventName: foo' 'a malformed name under -Strict'
        Assert-Throws { Write-PqEvent -Log $w -Ev '' } 'UnknownEventName: ' 'an empty name under -Strict'
        Assert-That ($w.Seq -eq 0 -and $w.Dropped -eq 0) "a refused malformed name under -Strict left Seq $($w.Seq), Dropped $($w.Dropped)"
        Close-PqLog -Log $w
        Assert-KnownEvents $root
    }

    # Review finding 5: a reader that opens the day file with FileShare.Read (File.ReadAllText, an indexer, an AV scan)
    # is not a second writer. Refused is only for a holder with write access; a reopen of a file this handle has
    # already held is never refused.
    Test-Case 'failopen: a FileShare.Read reader during Open-PqLog leaves the handle degraded, and the first write after the reader closes is preceded by log.error with the loss' {
        . (Get-LibPath 'events.ps1')
        $s = New-Scratch 'reader-open'
        $root = Join-Path $s 'portfolio'
        $env:SZA_PORTFOLIO_ROOT = $root
        $null = New-TestClock ([DateTimeOffset]::new(2026, 10, 27, 10, 0, 0, 0, [TimeSpan]::Zero))
        $path = Get-PqPath -Kind events -Date '2026-10-27' -Token pq
        Write-RawFile $path @((New-EventLine 1 -Ev 'run.start'), (New-EventLine 2 -Ev 'run.heartbeat'))
        $reader = [IO.File]::OpenRead($path)
        try {
            $h = Open-PqLog -Writer pq
            Assert-That ($h.State -ceq 'degraded') "a FileShare.Read reader made the opener '$($h.State)', expected degraded"
            foreach ($i in 1..2) { Assert-That ((Write-PqEvent -Log $h -Ev 'poll.change' -D @{ n = $i }) -eq $false) "write $i while the reader holds the file returned true" }
            Assert-That ($h.State -ceq 'degraded') "the handle is '$($h.State)' while the reader holds the file, expected degraded"
        }
        finally { $reader.Dispose() }
        Assert-That ((Write-PqEvent -Log $h -Ev 'poll.change' -D @{ n = 3 }) -eq $true) 'the first write after the reader closed failed'
        Assert-That ($h.State -ceq 'open') "after the reader closed the handle is '$($h.State)'"
        Close-PqLog -Log $h
        $e = Get-FileEvents $path
        $got = @($e | ForEach-Object { "$($_.seq):$($_.ev)" }) -join ','
        Assert-That ($got -ceq '1:run.start,2:run.heartbeat,5:log.error,6:poll.change') "the file holds [$got], expected [1:run.start,2:run.heartbeat,5:log.error,6:poll.change] (the lost writes own 3 and 4)"
        Assert-That ($e[2].d.dropped -eq 2) "log.error dropped is $($e[2].d.dropped), expected 2"
        $gotGaps = @((Read-PqDay -Path $path).gaps | ForEach-Object { "$($_.after):$(@($_.missing) -join '+'):$($_.explained)" }) -join ' '
        Assert-That ($gotGaps -ceq '2:3+4:True') "Read-PqDay gaps [$gotGaps], expected [2:3+4:True]"
        # A holder that keeps write access, or keeps the file to itself, at the first open is another writer: refused.
        $wPath = Get-PqPath -Kind events -Date '2026-10-27' -Token w1
        Write-RawFile $wPath @((New-EventLine 1 -Ev 'pass.beat' -Wr w1))
        foreach ($holder in @(@{ Access = [IO.FileAccess]::Write; Share = [IO.FileShare]::Read; What = 'a writer sharing Read' }, @{ Access = [IO.FileAccess]::Read; Share = [IO.FileShare]::None; What = 'an exclusive reader' })) {
            $other = [IO.FileStream]::new($wPath, [IO.FileMode]::Open, $holder.Access, $holder.Share)
            try { $w = Open-PqLog -Writer w1 } finally { $other.Dispose() }
            Assert-That ($w.State -ceq 'refused') "$($holder.What) made the opener '$($w.State)', expected refused"
            Close-PqLog -Log $w
        }
        Assert-KnownEvents $root
    }

    Test-Case 'failopen: a reader holding the file during a degraded reopen never makes the handle refused' {
        . (Get-LibPath 'events.ps1')
        $s = New-Scratch 'reader-reopen'
        $root = Join-Path $s 'portfolio'
        $env:SZA_PORTFOLIO_ROOT = $root
        $null = New-TestClock ([DateTimeOffset]::new(2026, 10, 27, 10, 0, 0, 0, [TimeSpan]::Zero))
        $h = Open-PqLog -Writer w1
        Assert-That ((Write-PqEvent -Log $h -Ev 'pass.beat') -eq $true) 'the first write failed'
        $h.Stream.Dispose()
        Assert-That ((Write-PqEvent -Log $h -Ev 'pass.beat') -eq $false) 'the write on a broken stream returned true'
        Assert-That ($h.State -ceq 'degraded') "after a broken stream the handle is '$($h.State)'"
        # A FileShare.Read reader, then an exclusive one (which a first open would take for another writer): each
        # reopen fails, and the handle stays degraded.
        foreach ($holder in @(@{ Share = [IO.FileShare]::Read; What = 'a FileShare.Read reader' }, @{ Share = [IO.FileShare]::None; What = 'an exclusive reader' })) {
            $other = [IO.FileStream]::new($h.Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, $holder.Share)
            try {
                Assert-That ((Write-PqEvent -Log $h -Ev 'pass.beat') -eq $false) "a write while $($holder.What) holds the file returned true"
                Assert-That ($h.State -ceq 'degraded') "$($holder.What) during the reopen made the handle '$($h.State)', expected degraded"
            }
            finally { $other.Dispose() }
        }
        Assert-That ((Write-PqEvent -Log $h -Ev 'pass.end') -eq $true) 'the write after the readers had gone failed'
        Assert-That ($h.State -ceq 'open') "after the readers had gone the handle is '$($h.State)'"
        Close-PqLog -Log $h
        $e = Get-FileEvents $h.Path
        $got = @($e | ForEach-Object { "$($_.seq):$($_.ev)" }) -join ','
        Assert-That ($got -ceq '1:pass.beat,5:log.error,6:pass.end') "the file holds [$got], expected [1:pass.beat,5:log.error,6:pass.end]"
        Assert-That ($e[1].d.dropped -eq 3) "log.error dropped is $($e[1].d.dropped), expected 3"
        $gotGaps = @((Read-PqDay -Path $h.Path).gaps | ForEach-Object { "$($_.after):$(@($_.missing) -join '+'):$($_.explained)" }) -join ' '
        Assert-That ($gotGaps -ceq '1:2+3+4:True') "Read-PqDay gaps [$gotGaps], expected [1:2+3+4:True]"
        Assert-KnownEvents $root
    }

    # ---- redact: events.ps1 redaction of d (TASK-FLOW rule 56) ----

    Test-Case 'redact: d.err is cut at 300 characters after the profile path is replaced' {
        . (Get-LibPath 'events.ps1')
        $s = New-Scratch 'cut'
        $env:SZA_PORTFOLIO_ROOT = Join-Path $s 'portfolio'
        $null = New-TestClock ([DateTimeOffset]::new(2026, 10, 27, 10, 0, 0, 0, [TimeSpan]::Zero))
        $prof = $env:USERPROFILE
        $long = $prof + '\' + ('x' * (600 - $prof.Length - 1))
        Assert-That ($long.Length -eq 600) "the fixture is $($long.Length) characters"
        # Longer than 300 with the profile spelled out, shorter once it is ~: never cut.
        $short = $prof + '\' + ('y' * 250)
        Assert-That ($short.Length -gt 300) "the second fixture is only $($short.Length) characters (profile too short)"
        $h = Open-PqLog -Writer pq
        $null = Write-PqEvent -Ev 'log.error' -D @{ err = $long; dropped = 0 }
        $null = Write-PqEvent -Ev 'log.error' -D @{ err = $short; dropped = 0 }
        $null = Write-PqEvent -Ev 'log.error' -D @{ err = 'short and plain'; dropped = 0 }
        Close-PqLog -Log $h
        $e = Get-FileEvents $h.Path
        $err = $e[0].d.err
        Assert-That ($err.Length -eq 300) "d.err is $($err.Length) characters, expected 300"
        Assert-That ($err[0] -eq '~') "d.err starts '$($err.Substring(0, [Math]::Min(20, $err.Length)))', expected '~'"
        Assert-That ($err -ceq ('~\' + ('x' * 298))) 'd.err is not the ~ form of the first 300 characters'
        Assert-That ($e[1].d.err -ceq ('~\' + ('y' * 250))) "an error that fits once the profile is ~ was cut: $($e[1].d.err.Length) characters"
        Assert-That ($e[2].d.err -ceq 'short and plain') "a short error changed: '$($e[2].d.err)'"
        Assert-That ($e[0].d.dropped -eq 0) 'the other keys of d were lost'
    }

    Test-Case 'redact: the cut never splits a surrogate pair' {
        . (Get-LibPath 'events.ps1')
        $s = New-Scratch 'surrogate'
        $env:SZA_PORTFOLIO_ROOT = Join-Path $s 'portfolio'
        $null = New-TestClock ([DateTimeOffset]::new(2026, 10, 27, 10, 0, 0, 0, [TimeSpan]::Zero))
        $emoji = [char]::ConvertFromUtf32(0x1F600)
        Assert-That ($emoji.Length -eq 2) 'the emoji is not a surrogate pair'
        $straddle = ('a' * 299) + $emoji + ('b' * 50)     # the pair is at 299-300: the cut at 300 would split it
        $inside = ('a' * 298) + $emoji + ('b' * 50)       # the pair is at 298-299: it ends exactly at the cut
        $h = Open-PqLog -Writer pq
        $null = Write-PqEvent -Ev 'log.error' -D @{ err = $straddle; dropped = 0 }
        $null = Write-PqEvent -Ev 'log.error' -D @{ err = $inside; dropped = 0 }
        Close-PqLog -Log $h
        $raw = Read-Lines $h.Path
        Assert-That (-not ($raw -join "`n").Contains('\ud83d')) 'a lone high surrogate was serialised'
        $e = Get-FileEvents $h.Path
        Assert-That ($e[0].d.err -ceq ('a' * 299)) "the straddling pair was not removed whole: $($e[0].d.err.Length) characters ending '$($e[0].d.err.Substring($e[0].d.err.Length - 3))'"
        Assert-That ($e[1].d.err -ceq (('a' * 298) + $emoji)) "a pair ending at the cut was not kept whole: $($e[1].d.err.Length) characters"
        foreach ($x in $e) {
            $t = [string]$x.d.err
            for ($i = 0; $i -lt $t.Length; $i++) {
                if ([char]::IsHighSurrogate($t[$i])) { Assert-That ($i + 1 -lt $t.Length -and [char]::IsLowSurrogate($t[$i + 1])) "a lone high surrogate at $i" ; $i++ }
                else { Assert-That (-not [char]::IsLowSurrogate($t[$i])) "a lone low surrogate at $i" }
            }
        }
    }

    Test-Case 'redact: the profile directory becomes ~ in every string value, both separators, any case' {
        . (Get-LibPath 'events.ps1')
        $s = New-Scratch 'tilde'
        $env:SZA_PORTFOLIO_ROOT = Join-Path $s 'portfolio'
        $null = New-TestClock ([DateTimeOffset]::new(2026, 10, 27, 10, 0, 0, 0, [TimeSpan]::Zero))
        $prof = $env:USERPROFILE
        $fwd = $prof.Replace('\', '/')
        $i = $prof.LastIndexOf('\')
        $mixed = $prof.Substring(0, $i) + '/' + $prof.Substring($i + 1)
        $d = [ordered]@{
            back    = "$prof\x\y.txt"
            fwd     = "$fwd/z"
            upper   = "$($prof.ToUpperInvariant())\q"
            lower   = "$($fwd.ToLowerInvariant())/r"
            mixed   = "$mixed\m"
            alone   = $prof
            twice   = "see $prof\log and $fwd/other"
            nested  = [ordered]@{ deep = [ordered]@{ p = "$prof\deep" } }
            list    = @("$prof\l1", 5, $true)
            n       = 42
            flag    = $false
            sibling = "${prof}X\keep"
            plain   = 'no path here'
        }
        $h = Open-PqLog -Writer pq
        $null = Write-PqEvent -Ev 'repo.discovered' -D $d
        Close-PqLog -Log $h
        $o = (Get-FileEvents $h.Path)[0].d
        $want = [ordered]@{ back = '~\x\y.txt'; fwd = '~/z'; upper = '~\q'; lower = '~/r'; mixed = '~\m'; alone = '~'; twice = 'see ~\log and ~/other'; sibling = "${prof}X\keep"; plain = 'no path here' }
        foreach ($k in $want.Keys) { Assert-That ($o.$k -ceq $want[$k]) "d.$k is '$($o.$k)', expected '$($want[$k])'" }
        Assert-That ($o.nested.deep.p -ceq '~\deep') "d.nested.deep.p is '$($o.nested.deep.p)'"
        Assert-That ($o.list[0] -ceq '~\l1' -and $o.list[1] -eq 5 -and $o.list[2] -eq $true) "d.list is [$($o.list -join ',')]"
        Assert-That ($o.n -eq 42 -and $o.flag -eq $false) 'a non-string value changed'
    }

    Test-Case 'redact: a key whose name suggests a secret is never serialised and is named in d.redacted' {
        . (Get-LibPath 'events.ps1')
        $s = New-Scratch 'secret'
        $env:SZA_PORTFOLIO_ROOT = Join-Path $s 'portfolio'
        $null = New-TestClock ([DateTimeOffset]::new(2026, 10, 27, 10, 0, 0, 0, [TimeSpan]::Zero))
        $secretKeys = @('token', 'secret', 'password', 'passwd', 'apikey', 'privatekey', 'authorization', 'credential', 'credentials',
            'cookie', 'bearer', 'API_KEY', 'api-key', 'Private_Key', 'githubToken', 'sessionCookie', 'X-Authorization', 'dbPassword', 'USER_PASSWD')
        $d = [ordered]@{ keep = 'visible' }
        $n = 0
        foreach ($k in $secretKeys) { $n++; $d[$k] = ('SECRET-VALUE-{0:D2}' -f $n) }
        $d['count'] = 3
        $h = Open-PqLog -Writer pq
        $null = Write-PqEvent -Ev 'agent.probe' -D $d
        $null = Write-PqEvent -Ev 'agent.probe' -D @{ password = 'SECRET-VALUE-99'; ok = 1 }
        Close-PqLog -Log $h
        $raw = Read-Lines $h.Path
        Assert-That (-not ($raw -join "`n").Contains('SECRET-VALUE')) "a secret value was serialised: $($raw -join ' | ')"
        $e = Get-FileEvents $h.Path
        $o = $e[0].d
        Assert-That ((Get-Keys $o) -ceq 'keep count redacted') "d keeps the keys [$(Get-Keys $o)], expected [keep count redacted]"
        Assert-That ((@($o.redacted) -join ',') -ceq ($secretKeys -join ',')) "d.redacted is [$(@($o.redacted) -join ',')], expected [$($secretKeys -join ',')]"
        Assert-That ($raw[1].Contains('"redacted":["password"]')) "one redacted name is not a JSON array: $($raw[1])"
        Assert-That ($e[1].d.ok -eq 1) 'the other keys of d were lost'
        # No function of the library takes prompt text: the API has no parameter for it.
        foreach ($fn in 'Write-PqEvent', 'Open-PqLog') {
            $p = @((Get-Command $fn).Parameters.Keys | Where-Object { $_ -match 'prompt' })
            Assert-That ($p.Count -eq 0) "$fn has a parameter for prompt text: $($p -join ',')"
        }
    }

    Test-Case 'redact: tokens survives while authToken, client_secret and Authorization are dropped' {
        . (Get-LibPath 'events.ps1')
        $s = New-Scratch 'tokens'
        $env:SZA_PORTFOLIO_ROOT = Join-Path $s 'portfolio'
        $null = New-TestClock ([DateTimeOffset]::new(2026, 10, 27, 10, 0, 0, 0, [TimeSpan]::Zero))
        $h = Open-PqLog -Writer pq
        $null = Write-PqEvent -Ev 'pass.end' -D ([ordered]@{ tokens = 1234; authToken = 'S1'; client_secret = 'S2'; Authorization = 'S3'; tokenCount = 7; tokenizer = 'bpe' })
        Close-PqLog -Log $h
        $o = (Get-FileEvents $h.Path)[0].d
        Assert-That ($null -ne $o.PSObject.Properties['tokens']) "d.tokens was dropped (tokens does not end in token): d keeps [$(Get-Keys $o)]"
        Assert-That ($o.tokens -eq 1234) "d.tokens is '$($o.tokens)', expected 1234 (tokens does not end in token)"
        Assert-That ($o.tokenCount -eq 7 -and $o.tokenizer -ceq 'bpe') 'a key that only begins with token was dropped'
        Assert-That ((Get-Keys $o) -ceq 'tokens tokenCount tokenizer redacted') "d keeps [$(Get-Keys $o)], expected [tokens tokenCount tokenizer redacted]"
        Assert-That ((@($o.redacted) -join ',') -ceq 'authToken,client_secret,Authorization') "d.redacted is [$(@($o.redacted) -join ',')]"
    }

    Test-Case 'redact: nested objects and arrays are redacted too' {
        . (Get-LibPath 'events.ps1')
        $s = New-Scratch 'nested'
        $env:SZA_PORTFOLIO_ROOT = Join-Path $s 'portfolio'
        $null = New-TestClock ([DateTimeOffset]::new(2026, 10, 27, 10, 0, 0, 0, [TimeSpan]::Zero))
        $prof = $env:USERPROFILE
        $d = [ordered]@{
            outer = [ordered]@{ inner = [ordered]@{ password = 'SECRET-1'; keep = 1 } }
            list  = @("$prof\a.txt", [ordered]@{ apiKey = 'SECRET-2'; path = "$prof/b" }, @("$prof\c", [ordered]@{ cookie = 'SECRET-3'; c = 3 }))
            obj   = [pscustomobject]@{ bearer = 'SECRET-4'; ok = 2; where = "$prof\obj" }
        }
        $h = Open-PqLog -Writer pq
        $null = Write-PqEvent -Ev 'ingest.transcript' -D $d
        Close-PqLog -Log $h
        $raw = Read-Lines $h.Path
        Assert-That (-not $raw[0].Contains('SECRET-')) "a nested secret was serialised: $($raw[0])"
        $o = (Get-FileEvents $h.Path)[0].d
        Assert-That ((Get-Keys $o.outer.inner) -ceq 'keep') "d.outer.inner keeps [$(Get-Keys $o.outer.inner)], expected [keep]"
        Assert-That ($o.list[0] -ceq '~\a.txt') "d.list[0] is '$($o.list[0])'"
        Assert-That ((Get-Keys $o.list[1]) -ceq 'path' -and $o.list[1].path -ceq '~/b') "d.list[1] is $(ConvertTo-Json $o.list[1] -Compress)"
        Assert-That ($o.list[2][0] -ceq '~\c' -and (Get-Keys $o.list[2][1]) -ceq 'c') "d.list[2] is $(ConvertTo-Json $o.list[2] -Compress)"
        Assert-That ((Get-Keys $o.obj) -ceq 'ok where' -and $o.obj.where -ceq '~\obj') "d.obj is $(ConvertTo-Json $o.obj -Compress)"
        $red = @($o.redacted | Sort-Object) -join ','
        Assert-That ($red -ceq 'apiKey,bearer,cookie,password') "d.redacted is [$red], expected apiKey,bearer,cookie,password"
    }

    # Review finding 3: rule 56 says every string value, and agent and model are free-form (a local model path).
    Test-Case 'redact: the profile directory becomes ~ in the string fields of the envelope too' {
        . (Get-LibPath 'events.ps1')
        $s = New-Scratch 'tilde-env'
        $env:SZA_PORTFOLIO_ROOT = Join-Path $s 'portfolio'
        $null = New-TestClock ([DateTimeOffset]::new(2026, 10, 27, 10, 0, 0, 0, [TimeSpan]::Zero))
        $prof = $env:USERPROFILE
        $fwd = $prof.Replace('\', '/')
        $h = Open-PqLog -Writer pq -Run "$prof\runs\R1"
        $null = Write-PqEvent -Ev 'pass.launch' -Repo "$prof\src\fms" -Id "$fwd/S0001" -Pass "$prof\p.1" -Agent "$prof\bin\agent.exe" -Model "$prof\models\local.gguf" -Cx "$fwd/cx" -D @{ liveLog = "$prof\models\local.gguf" }
        $null = Write-PqEvent -Ev 'pass.launch' -Run "$($prof.ToUpperInvariant())\R2"
        Close-PqLog -Log $h
        $raw = (Read-Lines $h.Path) -join "`n"
        foreach ($form in @($prof.Replace('\', '\\'), $fwd)) {
            Assert-That ($raw.IndexOf($form, [StringComparison]::OrdinalIgnoreCase) -lt 0) "the profile directory ($form) is in a line: $raw"
        }
        $e = Get-FileEvents $h.Path
        $want = [ordered]@{ run = '~\runs\R1'; repo = '~\src\fms'; id = '~/S0001'; pass = '~\p.1'; agent = '~\bin\agent.exe'; model = '~\models\local.gguf'; cx = '~/cx' }
        foreach ($k in $want.Keys) { Assert-That ($e[0].$k -ceq $want[$k]) "the envelope $k is '$($e[0].$k)', expected '$($want[$k])'" }
        Assert-That ($e[0].d.liveLog -ceq '~\models\local.gguf') "d.liveLog is '$($e[0].d.liveLog)'"
        Assert-That ($e[1].run -ceq '~\R2') "an upper-case profile in -Run gave run '$($e[1].run)', expected '~\R2'"
        Assert-That ($e[0].wr -ceq 'pq' -and $e[0].v -eq 1 -and $e[0].seq -eq 1) 'a fixed envelope field changed'
    }

    # Review finding 6: only strings, numbers and booleans go into d as they are; an error becomes its message, any
    # other object its text, and both pass the string rules (the profile as ~, err cut at 300).
    Test-Case 'redact: an ErrorRecord or an Exception in d becomes its message, with the profile as ~ and err cut at 300' {
        . (Get-LibPath 'events.ps1')
        $s = New-Scratch 'errobj'
        $env:SZA_PORTFOLIO_ROOT = Join-Path $s 'portfolio'
        $null = New-TestClock ([DateTimeOffset]::new(2026, 10, 27, 10, 0, 0, 0, [TimeSpan]::Zero))
        $prof = $env:USERPROFILE
        $msg = "boom at $prof\home\secret-place\file.txt " + ('y' * 400)
        $rec = $null
        try { throw $msg } catch { $rec = $_ }
        $ex = [InvalidOperationException]::new($msg)
        $wrapped = [Management.Automation.MethodInvocationException]::new('Exception calling "Open" with "1" argument(s): wrapper', $ex)
        $h = Open-PqLog -Writer pq
        foreach ($v in @($rec, $ex, $wrapped)) { Assert-That ((Write-PqEvent -Ev 'pass.halt' -D @{ err = $v }) -eq $true) "the write of a $($v.GetType().Name) failed" }
        $null = Write-PqEvent -Ev 'pass.halt' -D ([ordered]@{ why = $rec; list = @($ex) })
        Close-PqLog -Log $h
        $raw = Read-Lines $h.Path
        $e = Get-FileEvents $h.Path
        $want = '~\home\secret-place\file.txt ' + ('y' * 400)
        for ($i = 0; $i -lt 3; $i++) {
            $err = $e[$i].d.err
            Assert-That ($err -is [string]) "line $($i + 1): d.err is a $(if ($null -eq $err) { 'null' } else { $err.GetType().Name }), expected a string: $($raw[$i].Substring(0, [Math]::Min(200, $raw[$i].Length)))"
            Assert-That ($err.Length -eq 300 -and $err -ceq ('boom at ' + $want).Substring(0, 300)) "line $($i + 1): d.err is $($err.Length) characters '$($err.Substring(0, [Math]::Min(40, $err.Length)))..', expected the ~ form cut at 300"
            Assert-That ($raw[$i].Length -lt 600) "line $($i + 1) is $($raw[$i].Length) characters: the object graph was serialised"
        }
        $o = $e[3].d
        Assert-That ($o.why -is [string] -and $o.why -ceq ('boom at ' + $want)) "d.why is '$($o.why)', expected the whole ~ message (not err: not cut)"
        Assert-That (@($o.list).Count -eq 1 -and $o.list[0] -ceq ('boom at ' + $want)) "d.list is $(ConvertTo-Json $o.list -Compress)"
        foreach ($form in @($prof.Replace('\', '\\'), $prof.Replace('\', '/'))) {
            Assert-That (($raw -join "`n").IndexOf($form, [StringComparison]::OrdinalIgnoreCase) -lt 0) "the profile directory ($form) is in a line"
        }
    }

    Test-Case 'redact: any other object in d is written as its text, never its property graph' {
        . (Get-LibPath 'events.ps1')
        $s = New-Scratch 'objtext'
        $env:SZA_PORTFOLIO_ROOT = Join-Path $s 'portfolio'
        $null = New-TestClock ([DateTimeOffset]::new(2026, 10, 27, 10, 0, 0, 0, [TimeSpan]::Zero))
        $file = Join-Path $env:USERPROFILE "docs${sep}a.txt"
        New-Item -ItemType Directory -Path (Split-Path -Parent $file) -Force | Out-Null
        [IO.File]::WriteAllText($file, 'x')
        $d = [ordered]@{
            file  = Get-Item -LiteralPath $file
            dir   = Get-Item -LiteralPath $env:USERPROFILE
            dto   = [DateTimeOffset]::new(2026, 10, 27, 12, 0, 0, 5, [TimeSpan]::FromHours(2))
            dt    = [DateTime]::new(2026, 10, 27, 10, 0, 0, 7, [DateTimeKind]::Utc)
            enum  = [IO.FileAttributes]::Archive
            guid  = [guid]'0a0b0c0d-0000-4000-8000-000000000001'
            char  = [char]'x'
            i16   = [int16]-5
            u64   = [uint64]7
            dec   = [decimal]1.5
            dbl   = 2.25
            yes   = $true
            type  = [string]
            sb    = { 'code' }
        }
        $h = Open-PqLog -Writer pq
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $ok = Write-PqEvent -Ev 'repo.discovered' -D $d
        $ms = $sw.Elapsed.TotalMilliseconds
        Close-PqLog -Log $h
        Assert-That ($ok -eq $true) "the write of a FileInfo in d returned '$ok' (PendingError '$($h.PendingError)')"
        # A liveness bound, not a performance one: the property graph of a FileInfo took 24 s and ran out of memory.
        Assert-That ($ms -lt 2000) "the write took $([Math]::Round($ms)) ms"
        $raw = Read-Lines $h.Path
        Assert-That ($raw.Count -eq 1 -and $raw[0].Length -lt 1000) "the line is $($raw[0].Length) characters: an object graph was serialised"
        $o = (Get-FileEvents $h.Path)[0].d
        $want = [ordered]@{ file = "~${sep}docs${sep}a.txt"; dir = '~'; dto = '2026-10-27T10:00:00.005Z'; dt = '2026-10-27T10:00:00.007Z'; enum = 'Archive'
            guid = '0a0b0c0d-0000-4000-8000-000000000001'; char = 'x'; type = 'string'; sb = " 'code' " }
        foreach ($k in $want.Keys) { Assert-That ($o.$k -is [string] -and $o.$k -ceq $want[$k]) "d.$k is '$($o.$k)', expected the string '$($want[$k])'" }
        Assert-That ($o.i16 -eq -5 -and $o.u64 -eq 7 -and $o.dec -eq 1.5 -and $o.dbl -eq 2.25 -and $o.yes -eq $true) "a number or a boolean changed: $($raw[0])"
        Assert-That ($o.i16 -isnot [string] -and $o.yes -is [bool]) 'a number or a boolean became a string'
    }

    Test-Case 'redact: Convert-PqRelativePath returns repository-relative paths with forward slashes and ~ form outside the repository' {
        . (Get-LibPath 'events.ps1')
        $s = New-Scratch 'relpath'
        $prof = Join-Path $s 'home'
        $env:USERPROFILE = $prof
        $repo = Join-Path $prof "src${sep}fms"
        New-Item -ItemType Directory -Path $repo -Force | Out-Null
        $rows = @(
            @{ Repo = $repo; Path = Join-Path $repo "src${sep}a${sep}b.txt"; Want = 'src/a/b.txt' }
            @{ Repo = $repo; Path = $repo.Replace('\', '/') + '/src/c.txt'; Want = 'src/c.txt' }
            @{ Repo = $repo + $sep; Path = Join-Path $repo 'x.txt'; Want = 'x.txt' }
            @{ Repo = $repo; Path = "src${sep}rel.txt"; Want = 'src/rel.txt' }
            @{ Repo = $repo; Path = $repo; Want = '.' }
            @{ Repo = $repo; Path = Join-Path $prof "src${sep}fms-web${sep}y.txt"; Want = '~/src/fms-web/y.txt' }
            @{ Repo = $repo; Path = Join-Path $prof "other${sep}x.txt"; Want = '~/other/x.txt' }
            @{ Repo = $repo; Path = "..${sep}up.txt"; Want = '~/src/up.txt' }
            @{ Repo = $repo; Path = Join-Path $s "elsewhere${sep}z.txt"; Want = $s.Replace('\', '/') + '/elsewhere/z.txt' }
        )
        if ($IsWindows) { $rows += @{ Repo = $repo; Path = Join-Path $repo.ToUpperInvariant() 'D.txt'; Want = 'D.txt' } }
        foreach ($row in $rows) {
            $got = Convert-PqRelativePath -RepoPath $row.Repo -Path $row.Path
            Assert-That ($got -is [string] -and $got -ceq $row.Want) "Convert-PqRelativePath -RepoPath '$($row.Repo)' -Path '$($row.Path)' returned '$got', expected '$($row.Want)'"
        }
        # A path that cannot be made relative is returned with the profile replaced, never dropped.
        $broken = "$prof${sep}bad$([char]0)name"
        $got = Convert-PqRelativePath -RepoPath $repo -Path $broken
        Assert-That ($got -ceq "~${sep}bad$([char]0)name") "a path that cannot be made relative returned '$got'"
    }

    # ---- rotate: events.ps1 rotation at UTC midnight (TASK-FLOW rule 54) ----

    Test-Case 'rotate: the first write after UTC midnight opens the next day''s file and starts at seq 1' {
        . (Get-LibPath 'events.ps1')
        $s = New-Scratch 'rotate1'
        $root = Join-Path $s 'portfolio'
        $env:SZA_PORTFOLIO_ROOT = $root
        $clock = New-TestClock ([DateTimeOffset]::new(2026, 10, 27, 23, 59, 0, 0, [TimeSpan]::Zero))
        $h = Open-PqLog -Writer pq
        $null = Write-PqEvent -Ev 'poll.change'
        $null = Write-PqEvent -Ev 'poll.change'
        $old = $h.Path
        $clock.now = [DateTimeOffset]::new(2026, 10, 28, 0, 0, 1, 0, [TimeSpan]::Zero)
        Assert-That ((Write-PqEvent -Ev 'run.heartbeat') -eq $true) 'the first write after midnight failed'
        $new = Get-PqPath -Kind events -Date '2026-10-28' -Token pq
        Assert-That ($h.Path -eq $new) "the handle path is '$($h.Path)', expected '$new'"
        Assert-That ($h.Date -ceq '2026-10-28') "the handle date is '$($h.Date)', expected 2026-10-28"
        Assert-That ($h.State -ceq 'open') "the rotated handle has State '$($h.State)'"
        $null = Write-PqEvent -Ev 'run.heartbeat'
        Close-PqLog -Log $h
        $oldSeqs = @((Get-FileEvents $old) | ForEach-Object { $_.seq }) -join ','
        Assert-That ($oldSeqs -eq '1,2') "the old file holds seq [$oldSeqs], expected 1,2"
        $e = Get-FileEvents $new
        $newSeqs = @($e | ForEach-Object { $_.seq }) -join ','
        Assert-That ($newSeqs -eq '1,2,3') "the new file holds seq [$newSeqs], expected 1,2,3"
        Assert-That ($e[1].ev -ceq 'run.heartbeat' -and $e[1].ts -ceq '2026-10-28T00:00:01.000Z') "the event after midnight is '$($e[1].ev)' at '$($e[1].ts)'"
        Assert-That ($h.Seq -eq 3) "the handle Seq is $($h.Seq), expected 3"
        Assert-KnownEvents $root
    }

    Test-Case 'rotate: the new file begins with log.rotate carrying from, to and the event count of the old file' {
        . (Get-LibPath 'events.ps1')
        $s = New-Scratch 'rotate2'
        $root = Join-Path $s 'portfolio'
        $env:SZA_PORTFOLIO_ROOT = $root
        $clock = New-TestClock ([DateTimeOffset]::new(2026, 10, 27, 22, 0, 0, 0, [TimeSpan]::Zero))
        $h = Open-PqLog -Writer w2 -Run 'R20261027T220000-0a0b'
        foreach ($i in 1..3) { $null = Write-PqEvent -Log $h -Ev 'pass.beat' -D @{ n = $i } }
        $old = $h.Path
        $clock.now = [DateTimeOffset]::new(2026, 10, 28, 0, 0, 0, 250, [TimeSpan]::Zero)
        $null = Write-PqEvent -Log $h -Ev 'pass.end' -Repo 'fms-web' -Id 'S0001'
        $clock.now = [DateTimeOffset]::new(2026, 10, 28, 9, 0, 0, 0, [TimeSpan]::Zero)
        $null = Write-PqEvent -Log $h -Ev 'pass.beat'
        Close-PqLog -Log $h
        $oe = Get-FileEvents $old
        Assert-That ($oe.Count -eq 3) "the old file holds $($oe.Count) events, expected 3"
        Assert-That (@($oe | Where-Object { $_.ev -ceq 'log.rotate' }).Count -eq 0) "the old file holds a log.rotate: [$(@($oe | ForEach-Object { $_.ev }) -join ',')]"
        $ne = Get-FileEvents $h.Path
        $got = @($ne | ForEach-Object { "$($_.seq):$($_.ev)" }) -join ','
        Assert-That ($got -ceq '1:log.rotate,2:pass.end,3:pass.beat') "the new file holds [$got], expected 1:log.rotate,2:pass.end,3:pass.beat"
        $r = $ne[0]
        Assert-That ((Get-Keys $r.d) -ceq 'from to events') "log.rotate d keys [$(Get-Keys $r.d)], expected [from to events]"
        Assert-That ($r.d.from -ceq '2026-10-27' -and $r.d.to -ceq '2026-10-28') "log.rotate from '$($r.d.from)' to '$($r.d.to)'"
        Assert-That ($r.d.events -eq 3 -and $r.d.events -eq $oe[-1].seq) "log.rotate events is $($r.d.events), expected the last seq of the old file ($($oe[-1].seq))"
        Assert-That ($r.ts -ceq '2026-10-28T00:00:00.250Z' -and $r.wr -ceq 'w2' -and $r.run -ceq 'R20261027T220000-0a0b') "log.rotate ts '$($r.ts)' wr '$($r.wr)' run '$($r.run)'"
        Assert-That ($null -eq $r.repo -and $null -eq $r.id) 'log.rotate took the correlation keys of the event that caused it'
        Assert-That ($ne[1].repo -ceq 'fms-web' -and $ne[1].id -ceq 'S0001') 'the event after log.rotate lost its correlation keys'
        Assert-KnownEvents $root
    }

    Test-Case 'rotate: a skipped day makes no empty file' {
        . (Get-LibPath 'events.ps1')
        $s = New-Scratch 'rotate3'
        $root = Join-Path $s 'portfolio'
        $env:SZA_PORTFOLIO_ROOT = $root
        $clock = New-TestClock ([DateTimeOffset]::new(2026, 10, 27, 12, 0, 0, 0, [TimeSpan]::Zero))
        $h = Open-PqLog -Writer pq
        $null = Write-PqEvent -Ev 'run.start'
        $clock.now = [DateTimeOffset]::new(2026, 10, 30, 8, 0, 0, 0, [TimeSpan]::Zero)
        $null = Write-PqEvent -Ev 'run.heartbeat'
        Close-PqLog -Log $h
        $names = @(Get-ChildItem -LiteralPath (Join-Path $root 'log') -Force | ForEach-Object { $_.Name } | Sort-Object)
        Assert-That (($names -join ',') -ceq 'events-2026-10-27.pq.jsonl,events-2026-10-30.pq.jsonl') "the log holds [$($names -join ', ')], expected the files of day 1 and day 4 only"
        $r = (Get-FileEvents $h.Path)[0]
        Assert-That ($r.ev -ceq 'log.rotate' -and $r.d.from -ceq '2026-10-27' -and $r.d.to -ceq '2026-10-30' -and $r.d.events -eq 1) "the first line of day 4 is $(ConvertTo-Json $r -Compress -Depth 4)"
        Assert-KnownEvents $root
    }

    Test-Case 'rotate: a clock that steps backwards never rotates back' {
        . (Get-LibPath 'events.ps1')
        $s = New-Scratch 'rotate4'
        $root = Join-Path $s 'portfolio'
        $env:SZA_PORTFOLIO_ROOT = $root
        $clock = New-TestClock ([DateTimeOffset]::new(2026, 10, 28, 0, 0, 5, 0, [TimeSpan]::Zero))
        $h = Open-PqLog -Writer pq
        $null = Write-PqEvent -Ev 'poll.change' -D @{ n = 1 }
        $clock.now = [DateTimeOffset]::new(2026, 10, 27, 23, 59, 59, 500, [TimeSpan]::Zero)
        Assert-That ((Write-PqEvent -Ev 'poll.change' -D @{ n = 2 }) -eq $true) 'the write with the stepped-back clock failed'
        Assert-That ($h.Date -ceq '2026-10-28') "the stepped-back clock moved the handle to '$($h.Date)'"
        $clock.now = [DateTimeOffset]::new(2026, 10, 28, 0, 0, 6, 0, [TimeSpan]::Zero)
        $null = Write-PqEvent -Ev 'poll.change' -D @{ n = 3 }
        # Forward to the next day rotates; a step back after that rotation still stays in the new file.
        $clock.now = [DateTimeOffset]::new(2026, 10, 29, 0, 0, 0, 0, [TimeSpan]::Zero)
        $null = Write-PqEvent -Ev 'poll.change' -D @{ n = 4 }
        $clock.now = [DateTimeOffset]::new(2026, 10, 28, 23, 0, 0, 0, [TimeSpan]::Zero)
        $null = Write-PqEvent -Ev 'poll.change' -D @{ n = 5 }
        Close-PqLog -Log $h
        $log = Join-Path $root 'log'
        $names = @(Get-ChildItem -LiteralPath $log -Force | ForEach-Object { $_.Name } | Sort-Object)
        Assert-That (($names -join ',') -ceq 'events-2026-10-28.pq.jsonl,events-2026-10-29.pq.jsonl') "the log holds [$($names -join ', ')]"
        $d28 = Get-FileEvents (Join-Path $log 'events-2026-10-28.pq.jsonl')
        $got = @($d28 | ForEach-Object { "$($_.seq):$($_.ev):$($_.d.PSObject.Properties['n'].Value)" }) -join ','
        Assert-That ($got -ceq '1:poll.change:1,2:poll.change:2,3:poll.change:3') "day 28 holds [$got]"
        Assert-That ($d28[1].ts -ceq '2026-10-27T23:59:59.500Z') "the stepped-back event has ts '$($d28[1].ts)', expected the stepped-back instant"
        $d29 = Get-FileEvents (Join-Path $log 'events-2026-10-29.pq.jsonl')
        $got = @($d29 | ForEach-Object { "$($_.seq):$($_.ev)" }) -join ','
        Assert-That ($got -ceq '1:log.rotate,2:poll.change,3:poll.change') "day 29 holds [$got], expected 1:log.rotate,2:poll.change,3:poll.change"
        Assert-That ($d29[0].d.from -ceq '2026-10-28' -and $d29[0].d.events -eq 3) "log.rotate from '$($d29[0].d.from)' events $($d29[0].d.events)"
        Assert-That ($d29[2].ts -ceq '2026-10-28T23:00:00.000Z' -and $d29[2].d.n -eq 5) "the event stepped back after the rotation is '$($d29[2].ts)' n $($d29[2].d.n)"
        Assert-KnownEvents $root
    }

    Test-Case 'rotate: events at 23:59:59.999Z and 00:00:00.000Z land in different files' {
        . (Get-LibPath 'events.ps1')
        $s = New-Scratch 'rotate5'
        $root = Join-Path $s 'portfolio'
        $env:SZA_PORTFOLIO_ROOT = $root
        $log = Join-Path $root 'log'
        $plus2 = [TimeSpan]::FromHours(2)
        # The UTC midnight, given to the seam at +02:00 (01:59:59.999 and 02:00:00.000 local of the same day).
        $clock = New-TestClock ([DateTimeOffset]::new(2026, 10, 28, 1, 59, 59, 999, $plus2))
        $h = Open-PqLog -Writer pq
        $null = Write-PqEvent -Log $h -Ev 'poll.change'
        $clock.now = [DateTimeOffset]::new(2026, 10, 28, 2, 0, 0, 0, $plus2)
        $null = Write-PqEvent -Log $h -Ev 'poll.change'
        Close-PqLog -Log $h
        $pqNames = @(Get-ChildItem -LiteralPath $log -Filter 'events-*.pq.jsonl' | ForEach-Object { $_.Name } | Sort-Object)
        Assert-That (($pqNames -join ',') -ceq 'events-2026-10-27.pq.jsonl,events-2026-10-28.pq.jsonl') "the UTC midnight gave the files [$($pqNames -join ', ')], expected the files of day 27 and day 28"
        $a = Get-FileEvents (Join-Path $log 'events-2026-10-27.pq.jsonl')
        Assert-That ($a.Count -eq 1 -and $a[0].ts -ceq '2026-10-27T23:59:59.999Z') "day 27 holds [$(@($a | ForEach-Object { $_.ts }) -join ',')], expected 23:59:59.999Z only"
        $bPath = Join-Path $log 'events-2026-10-28.pq.jsonl'
        Assert-That (Test-Path -LiteralPath $bPath) 'the event at 00:00:00.000Z did not open the file of day 28'
        $b = Get-FileEvents $bPath
        $got = @($b | ForEach-Object { "$($_.ev)@$($_.ts)" }) -join ','
        Assert-That ($got -ceq 'log.rotate@2026-10-28T00:00:00.000Z,poll.change@2026-10-28T00:00:00.000Z') "day 28 holds [$got]"
        # A local midnight at +02:00 is 22:00Z: the UTC date does not change, so nothing rotates.
        $clock.now = [DateTimeOffset]::new(2026, 10, 28, 23, 59, 59, 999, $plus2)
        $w = Open-PqLog -Writer w1
        $null = Write-PqEvent -Log $w -Ev 'pass.beat'
        $clock.now = [DateTimeOffset]::new(2026, 10, 29, 0, 0, 0, 0, $plus2)
        $null = Write-PqEvent -Log $w -Ev 'pass.beat'
        Close-PqLog -Log $w
        $wNames = @(Get-ChildItem -LiteralPath $log -Filter 'events-*.w1.jsonl' | ForEach-Object { $_.Name })
        Assert-That (($wNames -join ',') -ceq 'events-2026-10-28.w1.jsonl') "a local midnight at +02:00 rotated: [$($wNames -join ', ')]"
        $we = @((Get-FileEvents $w.Path) | ForEach-Object { "$($_.seq):$($_.ev)" }) -join ','
        Assert-That ($we -ceq '1:pass.beat,2:pass.beat') "w1 holds [$we], expected two events and no log.rotate"
        # The same at this machine's own local midnight, whatever its zone (nothing to prove at offset 0).
        $localMidnight = [datetime]::new(2026, 11, 2, 0, 0, 0, [DateTimeKind]::Unspecified)
        $offset = [TimeZoneInfo]::Local.GetUtcOffset($localMidnight)
        if ($offset -ne [TimeSpan]::Zero) {
            $lm = [DateTimeOffset]::new($localMidnight, $offset)
            $clock.now = $lm.AddMilliseconds(-1)
            $w2 = Open-PqLog -Writer w2
            $null = Write-PqEvent -Log $w2 -Ev 'pass.beat'
            $clock.now = $lm
            $null = Write-PqEvent -Log $w2 -Ev 'pass.beat'
            Close-PqLog -Log $w2
            $w2Names = @(Get-ChildItem -LiteralPath $log -Filter 'events-*.w2.jsonl' | ForEach-Object { $_.Name })
            Assert-That ($w2Names.Count -eq 1) "the machine's local midnight (offset $offset) rotated: [$($w2Names -join ', ')]"
        }
        Assert-KnownEvents $root
    }

    # Review findings 1, 10 and 13: rule 54 makes log.rotate seq 1 of the new file and rule 55 explains a gap only by
    # the log.error right after it, so a loss at the moment of rotation must leave 1 log.rotate, the gap, log.error.
    Test-Case 'rotate: an open that fails at the first write after UTC midnight keeps seq 1 for log.rotate and the gap it leaves is explained' {
        . (Get-LibPath 'events.ps1')
        $s = New-Scratch 'rotate-fail'
        $root = Join-Path $s 'portfolio'
        $env:SZA_PORTFOLIO_ROOT = $root
        $clock = New-TestClock ([DateTimeOffset]::new(2026, 10, 27, 23, 0, 0, 0, [TimeSpan]::Zero))
        $h = Open-PqLog -Writer pq
        foreach ($i in 1..2) { $null = Write-PqEvent -Log $h -Ev 'poll.change' -D @{ n = $i } }
        $old = $h.Path
        $new = Get-PqPath -Kind events -Date '2026-10-28' -Token pq
        New-Item -ItemType Directory -Path $new -Force | Out-Null
        $clock.now = [DateTimeOffset]::new(2026, 10, 28, 0, 0, 1, 0, [TimeSpan]::Zero)
        foreach ($i in 1..2) { Assert-That ((Write-PqEvent -Log $h -Ev 'run.heartbeat') -eq $false) "lost write $i after midnight returned true" }
        Assert-That ($h.Date -ceq '2026-10-28' -and $h.Seq -eq 3 -and $h.Dropped -eq 2) "after two lost writes of the new day the handle has Date $($h.Date), Seq $($h.Seq), Dropped $($h.Dropped), expected 2026-10-28, 3 (1 held for log.rotate) and 2"
        Remove-Item -LiteralPath $new -Force
        Assert-That ((Write-PqEvent -Log $h -Ev 'run.heartbeat' -D @{ n = 9 }) -eq $true) 'the write after the block was removed failed'
        Assert-That ((Write-PqEvent -Log $h -Ev 'run.heartbeat' -D @{ n = 10 }) -eq $true) 'the second write of the new file failed'
        Close-PqLog -Log $h
        Assert-That ((@((Get-FileEvents $old) | ForEach-Object { $_.seq }) -join ',') -ceq '1,2') 'the old file changed'
        $e = Get-FileEvents $new
        $got = @($e | ForEach-Object { "$($_.seq):$($_.ev)" }) -join ','
        Assert-That ($got -ceq '1:log.rotate,4:log.error,5:run.heartbeat,6:run.heartbeat') "the new file holds [$got], expected [1:log.rotate,4:log.error,5:run.heartbeat,6:run.heartbeat]"
        Assert-That ($e[0].d.from -ceq '2026-10-27' -and $e[0].d.to -ceq '2026-10-28' -and $e[0].d.events -eq 2) "log.rotate d is $(ConvertTo-Json $e[0].d -Compress)"
        Assert-That ($e[1].d.dropped -eq 2 -and $e[2].d.n -eq 9) "log.error dropped $($e[1].d.dropped), the event n $($e[2].d.n), expected 2 and 9"
        $day = Read-PqDay -Path $new
        $gotGaps = @($day.gaps | ForEach-Object { "$($_.after):$(@($_.missing) -join '+'):$($_.explained)" }) -join ' '
        Assert-That ($day.bad -eq 0 -and $gotGaps -ceq '1:2+3:True') "Read-PqDay of the new file reads bad $($day.bad) gaps [$gotGaps], expected 0 and [1:2+3:True]"
        # One lost write, on another writer and the next day (the repro of the review): 1 log.rotate, 2 lost, 3 log.error.
        $w = Open-PqLog -Writer w1
        foreach ($i in 1..3) { $null = Write-PqEvent -Log $w -Ev 'pass.beat' }
        $next = Get-PqPath -Kind events -Date '2026-10-29' -Token w1
        New-Item -ItemType Directory -Path $next -Force | Out-Null
        $clock.now = [DateTimeOffset]::new(2026, 10, 29, 0, 0, 0, 0, [TimeSpan]::Zero)
        Assert-That ((Write-PqEvent -Log $w -Ev 'pass.beat') -eq $false) 'the lost write after the second midnight returned true'
        Remove-Item -LiteralPath $next -Force
        Assert-That ((Write-PqEvent -Log $w -Ev 'pass.end') -eq $true) 'the recovering w1 write failed'
        Close-PqLog -Log $w
        $got = @((Get-FileEvents $next) | ForEach-Object { "$($_.seq):$($_.ev)" }) -join ','
        Assert-That ($got -ceq '1:log.rotate,3:log.error,4:pass.end') "the w1 file of day 29 holds [$got], expected [1:log.rotate,3:log.error,4:pass.end]"
        $gotGaps = @((Read-PqDay -Path $next).gaps | ForEach-Object { "$($_.after):$(@($_.missing) -join '+'):$($_.explained)" }) -join ' '
        Assert-That ($gotGaps -ceq '1:2:True') "Read-PqDay of the w1 file reads gaps [$gotGaps], expected [1:2:True]"
        # A failure of the write itself on the new file (the open succeeded) keeps seq 1 for log.rotate too.
        $x = Open-PqLog -Writer w2
        $null = Write-PqEvent -Log $x -Ev 'pass.beat'
        $clock.now = [DateTimeOffset]::new(2026, 10, 30, 0, 0, 0, 0, [TimeSpan]::Zero)
        $null = Write-PqEvent -Log $x -Ev 'pass.beat'
        Assert-That ((@((Get-FileEvents $x.Path) | ForEach-Object { "$($_.seq):$($_.ev)" }) -join ',') -ceq '1:log.rotate,2:pass.beat') 'the plain rotation of w2 is not 1:log.rotate,2:pass.beat'
        Assert-KnownEvents $root
    }

    Test-Case 'rotate: losses are never carried into the next day''s log.error - a tail loss of the old day is counted by log.rotate events, a loss across two rotations by the file it belongs to' {
        . (Get-LibPath 'events.ps1')
        $s = New-Scratch 'rotate-carry'
        $root = Join-Path $s 'portfolio'
        $env:SZA_PORTFOLIO_ROOT = $root
        $clock = New-TestClock ([DateTimeOffset]::new(2026, 10, 27, 22, 0, 0, 0, [TimeSpan]::Zero))
        # The old day ends with a lost write (seq 3, never written): the new file has no gap for it, so its log.error
        # says dropped 0, and log.rotate events (3) is above the last seq of the old file (2).
        $h = Open-PqLog -Writer pq
        foreach ($i in 1..2) { $null = Write-PqEvent -Log $h -Ev 'poll.change' }
        $h.Stream.Dispose()
        Assert-That ((Write-PqEvent -Log $h -Ev 'poll.change') -eq $false) 'the write on a broken stream returned true'
        $clock.now = [DateTimeOffset]::new(2026, 10, 28, 0, 0, 1, 0, [TimeSpan]::Zero)
        Assert-That ((Write-PqEvent -Log $h -Ev 'run.heartbeat') -eq $true) 'the first write of the new day failed'
        Close-PqLog -Log $h
        $last = @((Get-FileEvents (Get-PqPath -Kind events -Date '2026-10-27' -Token pq)) | ForEach-Object { $_.seq })[-1]
        $e = Get-FileEvents $h.Path
        $got = @($e | ForEach-Object { if ($_.ev -ceq 'log.error') { "$($_.seq):log.error($($_.d.dropped))" } else { "$($_.seq):$($_.ev)" } }) -join ','
        Assert-That ($got -ceq '1:log.rotate,2:log.error(0),3:run.heartbeat') "the new file holds [$got], expected [1:log.rotate,2:log.error(0),3:run.heartbeat]"
        Assert-That ($last -eq 2 -and $e[0].d.events -eq 3) "the old file ends at seq $last and log.rotate events is $($e[0].d.events), expected 2 and 3 (the lost tail is counted there)"
        $day = Read-PqDay -Path $h.Path
        Assert-That (@($day.gaps).Count -eq 0 -and $day.bad -eq 0) "Read-PqDay of the new file reads gaps $(@($day.gaps).Count) bad $($day.bad), expected 0 and 0"
        # The open fails across two rotations: the losses of day 28 (no file ever opened) are not added to the
        # log.error of day 29, whose dropped equals the gap of its own file.
        $clock.now = [DateTimeOffset]::new(2026, 10, 27, 12, 0, 0, 0, [TimeSpan]::Zero)
        $w = Open-PqLog -Writer w1
        $null = Write-PqEvent -Log $w -Ev 'pass.beat'
        $d28 = Get-PqPath -Kind events -Date '2026-10-28' -Token w1
        $d29 = Get-PqPath -Kind events -Date '2026-10-29' -Token w1
        New-Item -ItemType Directory -Path $d28, $d29 -Force | Out-Null
        $clock.now = [DateTimeOffset]::new(2026, 10, 28, 9, 0, 0, 0, [TimeSpan]::Zero)
        foreach ($i in 1..2) { Assert-That ((Write-PqEvent -Log $w -Ev 'pass.beat') -eq $false) "lost write $i of day 28 returned true" }
        $clock.now = [DateTimeOffset]::new(2026, 10, 29, 9, 0, 0, 0, [TimeSpan]::Zero)
        Assert-That ((Write-PqEvent -Log $w -Ev 'pass.beat') -eq $false) 'the lost write of day 29 returned true'
        Remove-Item -LiteralPath $d28, $d29 -Force
        Assert-That ((Write-PqEvent -Log $w -Ev 'pass.end') -eq $true) 'the recovering write of day 29 failed'
        Close-PqLog -Log $w
        Assert-That (-not (Test-Path -LiteralPath $d28)) 'a file of day 28 exists, though it was never opened'
        $e = Get-FileEvents $d29
        $got = @($e | ForEach-Object { if ($_.ev -ceq 'log.error') { "$($_.seq):log.error($($_.d.dropped))" } else { "$($_.seq):$($_.ev)" } }) -join ','
        Assert-That ($got -ceq '1:log.rotate,3:log.error(1),4:pass.end') "the day-29 file holds [$got], expected [1:log.rotate,3:log.error(1),4:pass.end]"
        Assert-That ($e[0].d.from -ceq '2026-10-27' -and $e[0].d.to -ceq '2026-10-29' -and $e[0].d.events -eq 1) "log.rotate d is $(ConvertTo-Json $e[0].d -Compress), expected from 2026-10-27 to 2026-10-29 events 1"
        $gotGaps = @((Read-PqDay -Path $d29).gaps | ForEach-Object { "$($_.after):$(@($_.missing) -join '+'):$($_.explained)" }) -join ' '
        Assert-That ($gotGaps -ceq '1:2:True') "Read-PqDay of day 29 reads gaps [$gotGaps], expected [1:2:True]"
        Assert-KnownEvents $root
    }

    # ---- poll: events.ps1 the hourly poll.summary aggregator (TASK-FLOW rule 58, S0015 R50) ----

    Test-Case 'poll: Add-PqPollStat accumulates counters and writes nothing until the hour ends' {
        . (Get-LibPath 'events.ps1')
        $s = New-Scratch 'poll1'
        $root = Join-Path $s 'portfolio'
        $env:SZA_PORTFOLIO_ROOT = $root
        $clock = New-TestClock ([DateTimeOffset]::new(2026, 10, 27, 10, 0, 0, 0, [TimeSpan]::Zero))
        $h = Open-PqLog -Writer pq
        $st = New-PqPollStats
        Assert-That ($null -eq $st.Hour) "a new stats object has Hour '$($st.Hour)'"
        foreach ($k in 'Polls', 'Changes', 'Reranks', 'HeartbeatReranks', 'PickerCalls', 'PickerMsSum', 'PickerMsMax', 'SkippedUnchanged') {
            Assert-That ($st.$k -eq 0) "a new stats object has $k = $($st.$k)"
        }
        $out = @(Add-PqPollStat -Stats $st -Log $h -Change -PickerMs 12.5, 7.5)
        Assert-That ($out.Count -eq 0) "Add-PqPollStat wrote $($out.Count) objects to the output stream"
        $clock.now = [DateTimeOffset]::new(2026, 10, 27, 10, 10, 0, 0, [TimeSpan]::Zero)
        Add-PqPollStat -Stats $st -Log $h -Rerank
        $clock.now = [DateTimeOffset]::new(2026, 10, 27, 10, 20, 0, 0, [TimeSpan]::Zero)
        Add-PqPollStat -Stats $st -Log $h -HeartbeatRerank -SkippedUnchanged
        $clock.now = [DateTimeOffset]::new(2026, 10, 27, 10, 59, 59, 999, [TimeSpan]::Zero)
        Add-PqPollStat -Stats $st -Log $h -Change -Rerank -PickerMs 3
        $want = [ordered]@{ Hour = '2026-10-27T10'; Polls = 4; Changes = 2; Reranks = 2; HeartbeatReranks = 1; PickerCalls = 3; PickerMsSum = 23; PickerMsMax = 12.5; SkippedUnchanged = 1 }
        foreach ($k in $want.Keys) { Assert-That ($st.$k -eq $want[$k]) "after four polls $k = '$($st.$k)', expected '$($want[$k])'" }
        $e = Get-FileEvents $h.Path
        Assert-That ($e.Count -eq 0) "the log holds $($e.Count) events before the hour ended: [$(@($e | ForEach-Object { $_.ev }) -join ',')]"
        Close-PqLog -Log $h
    }

    Test-Case 'poll: the first sample of the next UTC hour flushes poll.summary for the previous hour with hour and the documented keys' {
        . (Get-LibPath 'events.ps1')
        $s = New-Scratch 'poll2'
        $root = Join-Path $s 'portfolio'
        $env:SZA_PORTFOLIO_ROOT = $root
        $plus2 = [TimeSpan]::FromHours(2)
        # 12:15 and 12:45 at +02:00 are 10:15Z and 10:45Z: the hour is UTC.
        $clock = New-TestClock ([DateTimeOffset]::new(2026, 10, 27, 12, 15, 0, 0, $plus2))
        $h = Open-PqLog -Writer pq
        $st = New-PqPollStats
        Add-PqPollStat -Stats $st -Log $h -Change -PickerMs 4
        Assert-That ($st.Hour -ceq '2026-10-27T10') "the stats hour is '$($st.Hour)', expected the UTC hour 2026-10-27T10"
        $clock.now = [DateTimeOffset]::new(2026, 10, 27, 12, 45, 0, 0, $plus2)
        Add-PqPollStat -Stats $st -Log $h -SkippedUnchanged
        Add-PqPollStat -Stats $st -Log $h -Rerank
        Assert-That ((Get-FileEvents $h.Path).Count -eq 0) 'a summary was written inside the hour'
        $clock.now = [DateTimeOffset]::new(2026, 10, 27, 11, 0, 0, 0, [TimeSpan]::Zero)
        Add-PqPollStat -Stats $st -Log $h -Change
        $e = Get-FileEvents $h.Path
        Assert-That ($e.Count -eq 1 -and $e[0].ev -ceq 'poll.summary') "the log holds [$(@($e | ForEach-Object { $_.ev }) -join ',')], expected one poll.summary"
        $d = $e[0].d
        $keys = 'hour polls changes reranks heartbeatReranks pickerCalls pickerMsAvg pickerMsMax skippedUnchanged'
        Assert-That ((Get-Keys $d) -ceq $keys) "poll.summary d keys [$(Get-Keys $d)], expected [$keys]"
        $want = [ordered]@{ hour = '2026-10-27T10'; polls = 3; changes = 1; reranks = 1; heartbeatReranks = 0; pickerCalls = 1; pickerMsAvg = 4; pickerMsMax = 4; skippedUnchanged = 1 }
        foreach ($k in $want.Keys) { Assert-That ($d.$k -eq $want[$k]) "poll.summary d.$k = '$($d.$k)', expected '$($want[$k])'" }
        Assert-That ($e[0].ts -ceq '2026-10-27T11:00:00.000Z') "poll.summary ts is '$($e[0].ts)'"
        Assert-That ($st.Hour -ceq '2026-10-27T11' -and $st.Polls -eq 1 -and $st.Changes -eq 1 -and $st.PickerCalls -eq 0) "after the flush the stats hold Hour '$($st.Hour)' Polls $($st.Polls) Changes $($st.Changes) PickerCalls $($st.PickerCalls)"
        Close-PqLog -Log $h
        Assert-KnownEvents $root
    }

    Test-Case 'poll: pickerMsAvg and pickerMsMax are computed over pickerCalls only' {
        . (Get-LibPath 'events.ps1')
        $s = New-Scratch 'poll3'
        $root = Join-Path $s 'portfolio'
        $env:SZA_PORTFOLIO_ROOT = $root
        $clock = New-TestClock ([DateTimeOffset]::new(2026, 10, 27, 10, 0, 0, 0, [TimeSpan]::Zero))
        $h = Open-PqLog -Writer pq
        $st = New-PqPollStats
        # Four polls, three picker calls: the average is over the calls (33.333 / 3), not over the polls.
        Add-PqPollStat -Stats $st -Log $h -PickerMs 10, 20
        Add-PqPollStat -Stats $st -Log $h
        Add-PqPollStat -Stats $st -Log $h -PickerMs 3.333
        Add-PqPollStat -Stats $st -Log $h
        # The next hour: two polls without a picker call.
        $clock.now = [DateTimeOffset]::new(2026, 10, 27, 11, 5, 0, 0, [TimeSpan]::Zero)
        Add-PqPollStat -Stats $st -Log $h
        Add-PqPollStat -Stats $st -Log $h -SkippedUnchanged
        $null = Write-PqPollSummary -Stats $st -Log $h
        Close-PqLog -Log $h
        $e = @((Get-FileEvents $h.Path) | Where-Object { $_.ev -ceq 'poll.summary' })
        Assert-That ($e.Count -eq 2) "the log holds $($e.Count) poll.summary lines, expected 2"
        $a = $e[0].d
        Assert-That ($a.polls -eq 4 -and $a.pickerCalls -eq 3) "hour 10: polls $($a.polls) pickerCalls $($a.pickerCalls), expected 4 and 3"
        Assert-That ($a.pickerMsAvg -eq 11.1) "hour 10: pickerMsAvg is $($a.pickerMsAvg), expected 11.1 (33.333 over 3 calls, one decimal)"
        Assert-That ($a.pickerMsMax -eq 20) "hour 10: pickerMsMax is $($a.pickerMsMax), expected 20"
        $b = $e[1].d
        Assert-That ($b.hour -ceq '2026-10-27T11' -and $b.polls -eq 2 -and $b.pickerCalls -eq 0) "hour 11: hour '$($b.hour)' polls $($b.polls) pickerCalls $($b.pickerCalls)"
        Assert-That ($b.pickerMsAvg -eq 0 -and $b.pickerMsMax -eq 0) "hour 11 had no picker call: pickerMsAvg $($b.pickerMsAvg) pickerMsMax $($b.pickerMsMax), expected 0 and 0"
        Assert-KnownEvents $root
    }

    Test-Case 'poll: an hour with no polls emits nothing' {
        . (Get-LibPath 'events.ps1')
        $s = New-Scratch 'poll4'
        $root = Join-Path $s 'portfolio'
        $env:SZA_PORTFOLIO_ROOT = $root
        $clock = New-TestClock ([DateTimeOffset]::new(2026, 10, 27, 10, 30, 0, 0, [TimeSpan]::Zero))
        $h = Open-PqLog -Writer pq
        $st = New-PqPollStats
        $r = @(Write-PqPollSummary -Stats $st -Log $h)
        Assert-That ($r.Count -eq 1 -and $r[0] -is [bool] -and $r[0] -eq $false) "Write-PqPollSummary of an empty stats object returned [$($r -join ',')], expected one false"
        Assert-That ((Get-FileEvents $h.Path).Count -eq 0) 'an empty stats object wrote a summary'
        Add-PqPollStat -Stats $st -Log $h -Change
        # Hour 11 passes without a poll; the next sample is in hour 12.
        $clock.now = [DateTimeOffset]::new(2026, 10, 27, 12, 1, 0, 0, [TimeSpan]::Zero)
        Add-PqPollStat -Stats $st -Log $h
        $null = Write-PqPollSummary -Stats $st -Log $h
        $null = Write-PqPollSummary -Stats $st -Log $h
        Close-PqLog -Log $h
        $hours = @((Get-FileEvents $h.Path) | ForEach-Object { "$($_.ev):$($_.d.hour):$($_.d.polls)" }) -join ','
        Assert-That ($hours -ceq 'poll.summary:2026-10-27T10:1,poll.summary:2026-10-27T12:1') "the log holds [$hours], expected the summaries of hours 10 and 12 only"
        Assert-KnownEvents $root
    }

    Test-Case 'poll: Write-PqPollSummary at the end of a run emits the pending partial hour once and a second call emits nothing' {
        . (Get-LibPath 'events.ps1')
        $s = New-Scratch 'poll5'
        $root = Join-Path $s 'portfolio'
        $env:SZA_PORTFOLIO_ROOT = $root
        $clock = New-TestClock ([DateTimeOffset]::new(2026, 10, 27, 10, 5, 0, 0, [TimeSpan]::Zero))
        $h = Open-PqLog -Writer pq
        $st = New-PqPollStats
        Add-PqPollStat -Stats $st -Log $h -Change
        $clock.now = [DateTimeOffset]::new(2026, 10, 27, 10, 6, 0, 0, [TimeSpan]::Zero)
        Add-PqPollStat -Stats $st -Log $h -Rerank
        $r1 = @(Write-PqPollSummary -Stats $st -Log $h)
        $r2 = @(Write-PqPollSummary -Stats $st -Log $h)
        Assert-That ($r1.Count -eq 1 -and $r1[0] -eq $true) "the first Write-PqPollSummary returned [$($r1 -join ',')], expected one true"
        Assert-That ($r2.Count -eq 1 -and $r2[0] -eq $false) "the second Write-PqPollSummary returned [$($r2 -join ',')], expected one false"
        Assert-That ($null -eq $st.Hour -and $st.Polls -eq 0 -and $st.Changes -eq 0 -and $st.Reranks -eq 0) "after the summary the stats hold Hour '$($st.Hour)' Polls $($st.Polls)"
        $e = Get-FileEvents $h.Path
        $got = @($e | ForEach-Object { "$($_.ev):$($_.d.hour):$($_.d.polls):$($_.d.changes):$($_.d.reranks)" }) -join ','
        Assert-That ($got -ceq 'poll.summary:2026-10-27T10:2:1:1') "the log holds [$got], expected one summary of the partial hour 10"
        Assert-That ($e[0].ts -ceq '2026-10-27T10:06:00.000Z') "the end-of-run summary has ts '$($e[0].ts)'"
        Close-PqLog -Log $h
        Assert-KnownEvents $root
    }

    Test-Case 'poll: 5000 samples in one hour produce exactly one poll.summary line' {
        . (Get-LibPath 'events.ps1')
        $s = New-Scratch 'poll6'
        $root = Join-Path $s 'portfolio'
        $env:SZA_PORTFOLIO_ROOT = $root
        $start = [DateTimeOffset]::new(2026, 10, 27, 10, 0, 0, 0, [TimeSpan]::Zero)
        $clock = New-TestClock $start
        $h = Open-PqLog -Writer pq
        $st = New-PqPollStats
        for ($i = 0; $i -lt 5000; $i++) {
            $clock.now = $start.AddMilliseconds($i * 719)
            if ($i % 10 -eq 0) { Add-PqPollStat -Stats $st -Log $h -Change -PickerMs 1 } else { Add-PqPollStat -Stats $st -Log $h -SkippedUnchanged }
        }
        Assert-That ($clock.now.Hour -eq 10) "the samples left the hour: $($clock.now.ToString('o'))"
        Assert-That ((Get-FileEvents $h.Path).Count -eq 0) 'a summary was written inside the hour'
        $null = Write-PqPollSummary -Stats $st -Log $h
        Close-PqLog -Log $h
        $raw = Read-Lines $h.Path
        Assert-That ($raw.Count -eq 1) "5000 samples produced $($raw.Count) lines, expected 1"
        $d = (Get-FileEvents $h.Path)[0].d
        Assert-That ($d.polls -eq 5000 -and $d.changes -eq 500 -and $d.skippedUnchanged -eq 4500 -and $d.pickerCalls -eq 500) "the summary counts polls $($d.polls) changes $($d.changes) skippedUnchanged $($d.skippedUnchanged) pickerCalls $($d.pickerCalls)"
        Assert-KnownEvents $root
    }

    # ---- concurrent: events.ps1 across processes (TASK-FLOW rule 54: one writer per file, a second opener refused) ----

    Test-Case 'concurrent: five processes as w1..w5 write 400 events each, five files, 2000 lines, every line parses, seq is 1..400 in each' {
        . (Get-LibPath 'events.ps1')
        $f = Get-FiveWriterRun
        foreach ($k in $f.kids) {
            $r = $k.result
            Assert-That ($r.code -eq 0) "$($k.wr) exited $($r.code): $($r.output)"
            $want = "CHILD wr=$($k.wr) pid=$($r.pid) token=$($k.wr) state=open written=400"
            Assert-That ($r.stdout -ceq $want) "$($k.wr) printed '$($r.stdout)', expected '$want'"
            Assert-That ($r.stderr.Trim() -eq '') "$($k.wr) wrote to stderr: $($r.stderr.Trim())"
        }
        $log = Join-Path $f.root 'log'
        $names = @(Get-ChildItem -LiteralPath $log -Force | ForEach-Object { $_.Name } | Sort-Object)
        $wantNames = @(1..5 | ForEach-Object { "events-$($f.date).w$_.jsonl" })
        Assert-That (($names -join ',') -ceq ($wantNames -join ',')) "the log holds [$($names -join ', ')], expected [$($wantNames -join ', ')]"
        $total = 0
        foreach ($n in 1..5) {
            $path = Join-Path $log "events-$($f.date).w$n.jsonl"
            $bytes = [IO.File]::ReadAllBytes($path)
            Assert-That ($bytes.Length -gt 0 -and $bytes[-1] -eq 10) "w$n does not end with LF"
            Assert-That ([Array]::IndexOf($bytes, [byte]13) -lt 0) "w$n holds a CR byte"
            $parts = [Text.Encoding]::UTF8.GetString($bytes).Split("`n")
            $lines = $parts[0..($parts.Length - 2)]
            Assert-That ($lines.Count -eq 400) "w$n holds $($lines.Count) lines, expected 400"
            for ($i = 0; $i -lt $lines.Count; $i++) {
                $codes = @(Test-PqEnvelope -Line $lines[$i])
                Assert-That ($codes.Count -eq 0) "w$n line $($i + 1) breaks the envelope [$($codes -join ',')]: $($lines[$i])"
                $o = ConvertFrom-Json -InputObject $lines[$i] -DateKind String
                Assert-That ($o.seq -eq $i + 1 -and $o.d.n -eq $i + 1) "w$n line $($i + 1) has seq $($o.seq) and d.n $($o.d.n), expected $($i + 1)"
                Assert-That ($o.wr -ceq "w$n" -and $o.ev -ceq 'poll.change') "w$n line $($i + 1) has wr '$($o.wr)' ev '$($o.ev)'"
            }
            $day = Read-PqDay -Path $path
            Assert-That ($day.bad -eq 0 -and $day.unsupported -eq 0 -and $null -eq $day.partial -and $day.gaps.Count -eq 0) "Read-PqDay of w$n reports bad $($day.bad) unsupported $($day.unsupported) gaps $($day.gaps.Count)"
            $total += $lines.Count
        }
        Assert-That ($total -eq 2000) "the five files hold $total lines, expected 2000"
        Assert-KnownEvents $f.root
    }

    Test-Case 'concurrent: Merge-PqDay of the day returns 2000 events in ts, wr, seq order with no gap and no bad line' {
        . (Get-LibPath 'events.ps1')
        $f = Get-FiveWriterRun
        $bad = @($f.kids | Where-Object { $_.result.code -ne 0 } | ForEach-Object { "$($_.wr):$($_.result.code)" })
        Assert-That ($bad.Count -eq 0) "the five writers did not all exit 0: [$($bad -join ', ')]"
        $m = Merge-PqDay -Root $f.root -Date $f.date
        Assert-That ($m.events.Count -eq 2000) "Merge-PqDay returned $($m.events.Count) events, expected 2000"
        Assert-That ($m.bad -eq 0 -and $m.unsupported -eq 0) "Merge-PqDay counts bad $($m.bad) unsupported $($m.unsupported)"
        Assert-That ($m.gaps.Count -eq 0) "Merge-PqDay reports $($m.gaps.Count) gaps"
        Assert-That ($m.partial.Count -eq 0) "Merge-PqDay reports $($m.partial.Count) partial tails"
        Assert-That ($m.files.Count -eq 5) "Merge-PqDay read $($m.files.Count) files, expected 5"
        $next = @{}
        $switches = 0
        for ($i = 0; $i -lt $m.events.Count; $i++) {
            $e = $m.events[$i]
            if ($i -gt 0) {
                $p = $m.events[$i - 1]
                $c = [string]::CompareOrdinal([string]$p.ts, [string]$e.ts)
                if ($c -eq 0) { $c = [string]::CompareOrdinal([string]$p.wr, [string]$e.wr) }
                if ($c -eq 0) { $c = [long]$p.seq - [long]$e.seq }
                Assert-That ($c -lt 0) "event $i ($($e.ts) $($e.wr) $($e.seq)) does not follow event $($i - 1) ($($p.ts) $($p.wr) $($p.seq)) in ts, wr, seq order"
                if ($p.wr -cne $e.wr) { $switches++ }
            }
            $want = 1 + [int]$next[[string]$e.wr]
            Assert-That ($e.seq -eq $want) "$($e.wr) seq $($e.seq) comes where seq $want was expected"
            $next[[string]$e.wr] = $want
        }
        foreach ($n in 1..5) { Assert-That ($next["w$n"] -eq 400) "the merge holds $($next["w$n"]) events of w$n, expected 400" }
        # Five blocks one after another would be 4 changes of writer: the five really wrote at the same time.
        Assert-That ($switches -gt 4) "the merge changes writer $switches times: the five processes did not overlap"
    }

    Test-Case 'concurrent: a second opener of a writer name already open in another process is refused and corrupts nothing' {
        . (Get-LibPath 'events.ps1')
        $s = New-Scratch 'refuse'
        $root = Join-Path $s 'portfolio'
        $env:SZA_PORTFOLIO_ROOT = $root
        $shift = Get-ConcurrentShift
        Set-PqClock -Now ({ [DateTimeOffset]::UtcNow.AddTicks($shift) }.GetNewClosure())
        $go = Join-Path $s 'go'
        $ready = Join-Path $s 'ready'
        $hold = Join-Path $s 'hold'
        [IO.File]::WriteAllText($hold, 'hold')
        $a = $null
        try {
            $a = Start-Child (Get-ChildWriter) @('-LibRoot', [IO.Path]::GetFullPath($LibRoot), '-Root', $root, '-Writer', 'pq', '-Count', '10',
                '-GoFile', $go, '-ReadyFile', $ready, '-HoldFile', $hold, '-ShiftTicks', [string]$shift)
            Wait-Until { Test-Path -LiteralPath $ready } 60 'child A to open pq'
            $path = Get-PqPath -Kind events -Date '2026-10-27' -Token pq
            $h = Open-PqLog -Writer pq
            Assert-That ($h.State -ceq 'refused') "the second opener of pq has State '$($h.State)', expected refused"
            Assert-That ($h.Path -eq $path) "the refused handle names '$($h.Path)', expected '$path'"
            $out = @(Write-PqEvent -Log $h -Ev 'run.start')
            Assert-That ($out.Count -eq 1 -and $out[0] -is [bool] -and $out[0] -eq $false) "a write to the refused handle returned [$($out -join ',')], expected one false"
            Assert-That ((Write-PqEvent -Writer pq -Ev 'run.start') -eq $false) 'a write by -Writer pq to the refused handle did not return false'
            Assert-That ((Write-PqEvent -Ev 'run.start') -eq $false) 'a write to the refused default log did not return false'
            # A writes its 10 while the parent keeps trying.
            [IO.File]::WriteAllText($go, 'go')
            foreach ($i in 1..5) { Assert-That ((Write-PqEvent -Log $h -Ev 'run.heartbeat') -eq $false) "write $i to the refused handle while A writes did not return false" }
            Wait-Until { (Read-PqDay -Path $path).events.Count -ge 10 } 60 'the 10 events of child A'
            Assert-That ((Write-PqEvent -Log $h -Ev 'run.heartbeat') -eq $false) 'a write to the refused handle after A wrote did not return false'
            $lines = Read-Lines $path
            Assert-That ($lines.Count -eq 10) "the pq file holds $($lines.Count) lines, expected the 10 of A"
            for ($i = 0; $i -lt 10; $i++) {
                $codes = @(Test-PqEnvelope -Line $lines[$i])
                Assert-That ($codes.Count -eq 0) "line $($i + 1) breaks the envelope [$($codes -join ',')]: $($lines[$i])"
                $o = ConvertFrom-Json -InputObject $lines[$i] -DateKind String
                Assert-That ($o.seq -eq $i + 1 -and $o.ev -ceq 'poll.change' -and $o.d.n -eq $i + 1) "line $($i + 1) is seq $($o.seq) ev '$($o.ev)' n $($o.d.n): not a line of A"
            }
            $day = Read-PqDay -Path $path
            Assert-That ($day.bad -eq 0 -and $null -eq $day.partial -and $day.gaps.Count -eq 0) "Read-PqDay reports bad $($day.bad) gaps $($day.gaps.Count) partial '$($day.partial)'"
            # A crashes while holding the file: the OS releases it. The refused handle still never retries.
            Stop-Children @($a)
            Assert-That ($a.proc.HasExited) 'child A did not stop'
            Assert-That ((Write-PqEvent -Log $h -Ev 'run.heartbeat') -eq $false) 'the refused handle wrote after A had gone (a refused handle must never retry)'
            Assert-That ($h.State -ceq 'refused') "after A had gone the refused handle has State '$($h.State)'"
            Assert-That ((Read-Lines $path).Count -eq 10) 'the refused handle changed the file after A had gone'
            # The next opener, after a close, continues from the last seq of the file.
            Close-PqLog -Log $h
            $h2 = Open-PqLog -Writer pq
            Assert-That ($h2.State -ceq 'open' -and $h2.Seq -eq 10) "the opener after A has State '$($h2.State)' and Seq $($h2.Seq), expected open and 10"
            Assert-That ((Write-PqEvent -Log $h2 -Ev 'run.start') -eq $true) 'the opener after A could not write'
            Close-PqLog -Log $h2
            $e = Get-FileEvents $path
            $got = @($e | ForEach-Object { "$($_.seq):$($_.ev)" }) -join ','
            Assert-That ($e.Count -eq 11 -and $e[10].seq -eq 11 -and $e[10].ev -ceq 'run.start') "after A and one more write the file holds [$got]"
        }
        finally { Stop-Children @($a) }
        Assert-KnownEvents $root
    }

    Test-Case 'concurrent: three cli processes started together each get a file of their own and the wr field stays bare' {
        . (Get-LibPath 'events.ps1')
        $f = Invoke-WriterGroup @('cli', 'cli', 'cli') 20 'cli3'
        $pids = [Collections.Generic.List[int]]::new()
        foreach ($k in $f.kids) {
            $r = $k.result
            Assert-That ($r.code -eq 0) "a cli child exited $($r.code): $($r.output)"
            $want = "CHILD wr=cli pid=$($r.pid) token=cli-$($r.pid) state=open written=20"
            Assert-That ($r.stdout -ceq $want) "a cli child printed '$($r.stdout)', expected '$want'"
            $pids.Add($r.pid)
        }
        Assert-That (@($pids | Sort-Object -Unique).Count -eq 3) "the three children share process ids: [$($pids -join ',')]"
        $log = Join-Path $f.root 'log'
        $names = @(Get-ChildItem -LiteralPath $log -Force | ForEach-Object { $_.Name } | Sort-Object)
        $wantNames = @($pids | ForEach-Object { "events-$($f.date).cli-$_.jsonl" } | Sort-Object)
        Assert-That (($names -join ',') -ceq ($wantNames -join ',')) "the log holds [$($names -join ', ')], expected [$($wantNames -join ', ')]"
        foreach ($p in $pids) {
            $path = Join-Path $log "events-$($f.date).cli-$p.jsonl"
            $e = Get-FileEvents $path
            $got = @($e | ForEach-Object { "$($_.seq):$($_.wr)" }) -join ','
            $want = @(1..20 | ForEach-Object { "${_}:cli" }) -join ','
            Assert-That ($got -ceq $want) "cli-$p holds [$got], expected seq 1..20 with wr cli"
        }
        $m = Merge-PqDay -Root $f.root -Date $f.date
        Assert-That ($m.events.Count -eq 60) "Merge-PqDay returned $($m.events.Count) events, expected 60"
        Assert-That ($m.bad -eq 0 -and $m.gaps.Count -eq 0 -and $m.files.Count -eq 3) "Merge-PqDay counts bad $($m.bad) gaps $($m.gaps.Count) files $($m.files.Count)"
        Assert-That (@($m.events | Where-Object { $_.wr -cne 'cli' }).Count -eq 0) 'a merged event has a wr other than the bare cli'
        # In this process: imp and an take the process id in the file token too; pq and w<n> never do.
        $env:SZA_PORTFOLIO_ROOT = Join-Path (New-Scratch 'tokens') 'portfolio'
        $null = New-TestClock ([DateTimeOffset]::new(2026, 10, 27, 10, 0, 0, 0, [TimeSpan]::Zero))
        foreach ($row in @(@{ Wr = 'imp'; Token = "imp-$PID" }, @{ Wr = 'an'; Token = "an-$PID" }, @{ Wr = 'cli'; Token = "cli-$PID" }, @{ Wr = 'pq'; Token = 'pq' }, @{ Wr = 'w3'; Token = 'w3' })) {
            $h = Open-PqLog -Writer $row.Wr
            Assert-That ($h.Token -ceq $row.Token) "$($row.Wr) has the file token '$($h.Token)', expected '$($row.Token)'"
            $leaf = "events-2026-10-27.$($row.Token).jsonl"
            Assert-That ([IO.Path]::GetFileName([string]$h.Path) -ceq $leaf) "$($row.Wr) writes to '$($h.Path)', expected a file named $leaf"
            Assert-That ((Write-PqEvent -Log $h -Ev 'run.heartbeat') -eq $true) "$($row.Wr) could not write"
            Close-PqLog -Log $h
            $one = Get-FileEvents $h.Path
            Assert-That ($one.Count -eq 1 -and $one[0].wr -ceq $row.Wr) "the $($row.Wr) line has wr '$($one[0].wr)', expected the bare '$($row.Wr)'"
        }
        Assert-KnownEvents $f.root
        Assert-KnownEvents $env:SZA_PORTFOLIO_ROOT
    }

    # ---- perf: events.ps1 against a baseline measured in the same run (S0015 measurement rule; factors at the top) ----

    Test-Case 'perf: 10000 events through Write-PqEvent take no more than PerfFactor times the in-run baseline of the same bytes' {
        . (Get-LibPath 'events.ps1')
        $p = Get-PerfRun
        Assert-That ($PerfFactor -gt 0) 'PerfFactor is not set (see evidence/perf-baseline.json)'
        Assert-That ($null -eq $p.stoppedAt) "the loop stopped at event $($p.stoppedAt): a block of 1000 took more than $(2 * $PerfTailFactor) times the first, so 10000 events were not measured (blocks ms [$($p.blocksMs -join ', ')])"
        Assert-That ($p.written -eq $p.count) "$($p.written) of $($p.count) writes returned true"
        Assert-That ($p.ratio -le $PerfFactor) "the fastest block of 1000 events took $($p.minEventMs) ms, ratio $($p.ratio), more than PerfFactor $PerfFactor times the fastest baseline block $($p.minBaseMs) ms ($($p.lineBytes) bytes a line; blocks ms [$($p.blocksMs -join ', ')])"
    }

    Test-Case 'perf: the cost per event does not grow - the last 1000 of 10000 take no more than PerfTailFactor times the first 1000' {
        . (Get-LibPath 'events.ps1')
        $p = Get-PerfRun
        Assert-That ($PerfTailFactor -gt 0) 'PerfTailFactor is not set (see evidence/perf-baseline.json)'
        $b = $p.blocksMs
        Assert-That ($null -eq $p.stoppedAt) "block $($b.Count) of 1000 took $($b[-1]) ms, more than $(2 * $PerfTailFactor) times the first 1000 ($($b[0]) ms); the loop stopped at event $($p.stoppedAt) (blocks ms [$($b -join ', ')])"
        Assert-That ($b.Count -eq 10) "the run has $($b.Count) blocks of 1000, expected 10"
        Assert-That ($p.tailRatio -le $PerfTailFactor) "the faster of the last two blocks of 1000 is tailRatio $($p.tailRatio) times the faster of the first two, more than PerfTailFactor $PerfTailFactor (blocks ms [$($b -join ', ')])"
    }

    # ---- ledger and actor: tools/harness/portfolio/lib/ledger-watch.ps1 (TASK-FLOW rules 3 and 59, EVENTS.md 3.5) ----
    # Hand-written ledgers at the default paths of a repository without a profile; every time is local and built from
    # a UTC instant (the fixtures above), so no case depends on the zone of the machine.

    Test-Case 'ledger: a snapshot reads id, status and updated from the ledger and treats archive rows as Archived' {
        . (Get-LibPath 'ledger-watch.ps1')
        $repo = New-Scratch 'repo'
        $u1 = $LedgerT0.AddMinutes(-30); $u2 = $LedgerT0.AddMinutes(-90); $u3 = $LedgerT0.AddDays(-3)
        Write-Ledger $repo @(
            (New-LedgerRow 'S0001' 'Draft' $u1)
            (New-LedgerRow 'S0002' 'In Progress' $u2 -Created '2026-10-21' -Priority 70 -Name 'second' -Extra ([ordered]@{ tier = 3; futureField = @{ x = 1 } }))
        ) | Out-Null
        Write-Ledger $repo @((New-LedgerRow 'S0003' 'Verified' $u3 -Name 'old')) -Archive | Out-Null
        $before = Get-Listing $repo
        $at = [DateTimeOffset]::new(2026, 10, 27, 14, 0, 0, [TimeSpan]::FromHours(2))
        $s = Get-PqLedgerSnapshot -RepoPath $repo -Key 'fms' -At $at
        $after = Get-Listing $repo
        # A directory's own write time is updated lazily by NTFS after a file in it was written, so directories are
        # compared by name only; every file by name, size and write time.
        $before = Get-FileListing $before; $after = Get-FileListing $after
        Assert-That (($before -join ';') -ceq ($after -join ';')) "the snapshot changed the repository: before [$($before -join ';')] after [$($after -join ';')]"
        Assert-That ($s.repo -ceq 'fms') "repo is '$($s.repo)', expected fms"
        Assert-That ($s.at -is [DateTimeOffset] -and $s.at.Offset -eq [TimeSpan]::Zero -and $s.at -eq $at) "at is '$($s.at)', expected $at as UTC"
        Assert-That ($s.bad -eq 0) "bad is $($s.bad), expected 0"
        Assert-That ($s.ledgerRead -eq $true -and $s.archiveRead -eq $true) "ledgerRead $($s.ledgerRead), archiveRead $($s.archiveRead), expected both true"
        $ids = @($s.tickets.Keys) -join ','
        Assert-That ($ids -ceq 'S0001,S0002,S0003') "the snapshot holds [$ids], expected [S0001,S0002,S0003] (ledger order, then the archive)"
        $t = $s.tickets['S0001']
        Assert-That ((Get-Keys $t) -ceq 'id status updated created priority file') "a ticket has the keys [$(Get-Keys $t)], expected [id status updated created priority file]"
        Assert-That ($t.id -ceq 'S0001' -and $t.status -ceq 'Draft' -and $t.updated -ceq (ConvertTo-LocalStamp $u1)) "S0001 reads id '$($t.id)' status '$($t.status)' updated '$($t.updated)'"
        Assert-That ($t.created -ceq '2026-10-20' -and $t.priority -eq 50 -and $t.file -ceq 'PLAN/S0001_x.md') "S0001 reads created '$($t.created)' priority '$($t.priority)' file '$($t.file)'"
        $t = $s.tickets['S0002']
        Assert-That ($t.status -ceq 'In Progress' -and $t.priority -eq 70 -and $t.created -ceq '2026-10-21' -and $t.updated -ceq (ConvertTo-LocalStamp $u2)) "S0002 reads status '$($t.status)' priority $($t.priority) created '$($t.created)' updated '$($t.updated)'"
        $t = $s.tickets['S0003']
        Assert-That ($t.status -ceq 'Archived') "the archive row reads status '$($t.status)', expected Archived"
        Assert-That ($t.updated -ceq (ConvertTo-LocalStamp $u3) -and $t.file -ceq 'PLAN/S0003_old.md') "the archive row reads updated '$($t.updated)' file '$($t.file)'"
        Assert-That (-not $s.tickets.Contains('s0001')) 'ids are not compared ordinally: s0001 was found'
    }

    Test-Case 'ledger: an absent ledger or archive reads as empty and a malformed line is counted in bad, never thrown' {
        . (Get-LibPath 'ledger-watch.ps1')
        $repo = New-Scratch 'repo'
        $before = Get-Listing $repo
        $s = Get-PqLedgerSnapshot -RepoPath $repo -Key 'fms' -At $LedgerT0
        Assert-That ($s.tickets.Count -eq 0 -and $s.bad -eq 0) "a repository without a ledger holds $($s.tickets.Count) tickets and $($s.bad) bad lines"
        Assert-That ($s.ledgerRead -eq $false -and $s.archiveRead -eq $false -and $s.complete -eq $true) "absent files read ledgerRead $($s.ledgerRead) archiveRead $($s.archiveRead) complete $($s.complete), expected false false true"
        Assert-That (((Get-Listing $repo) -join ';') -ceq ($before -join ';')) 'reading an absent ledger created something'
        $u = $LedgerT0.AddMinutes(-10)
        $ledger = Write-Ledger $repo @(
            'this is prose, not JSON'
            '[1,2]'
            '"a string"'
            'null'
            '{"id":"S0009","name":"x"}'
            '{"status":"Draft","name":"x"}'
            '{"id":5,"status":"Draft"}'
            '{"id":"S0008","status":""}'
            '{"id":"S0010","sta'
            '{"id":["S0011"],"status":"Draft"}'
            '{"id":"S0012","status":["Draft"]}'
            ''
            '   '
            (New-LedgerRow 'S0001' 'Draft' $u)
            (New-LedgerRow 'S0001' 'Approved' $u)
            (New-LedgerRow 'S0002' 'Tactical' $u)
            '{"id":"S0013","status":"Draft","updated":["2026-10-27 10:00"],"created":["2026-10-20"],"file":["PLAN/x.md"]}'
        )
        $s = Get-PqLedgerSnapshot -RepoPath $repo -Key 'fms' -At $LedgerT0
        # prose, array, string, null, no status, no id, an id that is not a string, an empty status, a cut object, an
        # array id, an array status (review finding 7: a one-element array is not its element) and the duplicate
        # S0001: 12. Blank lines are not rows and are not counted.
        Assert-That ($s.bad -eq 12) "the ledger has $($s.bad) bad lines, expected 12"
        Assert-That ((@($s.tickets.Keys) -join ',') -ceq 'S0001,S0002,S0013') "the snapshot holds [$(@($s.tickets.Keys) -join ',')], expected [S0001,S0002,S0013]"
        $t13 = $s.tickets['S0013']
        Assert-That ($null -eq $t13.updated -and $null -eq $t13.created -and $null -eq $t13.file) "array updated, created and file read as '$($t13.updated)' '$($t13.created)' '$($t13.file)', expected null (not a time, not a path)"
        Assert-That ($s.tickets['S0001'].status -ceq 'Draft') "a duplicate id kept '$($s.tickets['S0001'].status)', expected the first row (Draft)"
        Assert-That ($s.ledgerRead -eq $true -and $s.archiveRead -eq $false -and $s.complete -eq $true) "ledgerRead $($s.ledgerRead) archiveRead $($s.archiveRead) complete $($s.complete), expected true false true"
        # The archive: a duplicate of a ledger id (the ledger row wins, counted bad), a complete row, and a half-written
        # last line without LF (bad, not an error).
        Write-RawFile (Join-Path $repo "PLAN${sep}spec-catalog-archive.jsonl") @((New-LedgerRow 'S0002' 'Verified' $u), (New-LedgerRow 'S0020' 'Verified' $u), '{"id":"S0021","status":"Ver') -NoFinalLf
        $s = Get-PqLedgerSnapshot -RepoPath $repo -Key 'fms' -At $LedgerT0
        Assert-That ($s.bad -eq 14) "with the archive $($s.bad) bad lines, expected 14 (12, the duplicate S0002, the half-written S0021)"
        Assert-That ($s.tickets['S0002'].status -ceq 'Tactical') "S0002 is in both files and reads '$($s.tickets['S0002'].status)', expected the ledger row (Tactical)"
        Assert-That ($s.tickets.Contains('S0020') -and $s.tickets['S0020'].status -ceq 'Archived') 'the complete archive row S0020 is missing or not Archived'
        Assert-That (-not $s.tickets.Contains('S0021')) 'the half-written S0021 was read as a ticket'
        # A complete last line without LF is a row.
        Write-RawFile (Join-Path $repo "PLAN${sep}spec-catalog-archive.jsonl") @((New-LedgerRow 'S0020' 'Verified' $u)) -NoFinalLf
        $s = Get-PqLedgerSnapshot -RepoPath $repo -Key 'fms' -At $LedgerT0
        Assert-That ($s.bad -eq 12 -and $s.tickets.Contains('S0020')) "a complete archive row without LF: bad $($s.bad), S0020 present $($s.tickets.Contains('S0020')), expected 12 and true"
        # A ledger another process holds without sharing: no throw, the snapshot says it is incomplete.
        if ($IsWindows) {
            $lock = [IO.FileStream]::new($ledger, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
            try { $s = Get-PqLedgerSnapshot -RepoPath $repo -Key 'fms' -At $LedgerT0 }
            finally { $lock.Dispose() }
            Assert-That ($s.complete -eq $false -and $s.ledgerRead -eq $false -and $s.archiveRead -eq $true) "a locked ledger reads complete $($s.complete) ledgerRead $($s.ledgerRead) archiveRead $($s.archiveRead), expected false false true"
            Assert-That ($s.errors.Count -eq 1) "a locked ledger left $($s.errors.Count) errors, expected 1"
        }
    }

    Test-Case 'ledger: a UTF-8 BOM and CRLF are tolerated' {
        . (Get-LibPath 'ledger-watch.ps1')
        $repo = New-Scratch 'repo'
        $u = $LedgerT0.AddMinutes(-10)
        New-Item -ItemType Directory -Path (Join-Path $repo 'PLAN') | Out-Null
        $ledger = Join-Path $repo "PLAN${sep}spec-catalog.jsonl"
        $archive = Join-Path $repo "PLAN${sep}spec-catalog-archive.jsonl"
        $text = "$([char]0xFEFF)" + (@((New-LedgerRow 'S0001' 'Draft' $u), (New-LedgerRow 'S0002' 'In Progress' $u)) -join "`r`n") + "`r`n"
        [IO.File]::WriteAllText($ledger, $text, [Text.UTF8Encoding]::new($false))
        $text = "$([char]0xFEFF)" + (@((New-LedgerRow 'S0003' 'Verified' $u), (New-LedgerRow 'S0004' 'Broken' $u)) -join "`r`n")
        [IO.File]::WriteAllText($archive, $text, [Text.UTF8Encoding]::new($false))
        foreach ($f in $ledger, $archive) {
            $b = [IO.File]::ReadAllBytes($f)
            Assert-That ($b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) "the fixture $f does not start with a BOM"
            Assert-That ([Array]::IndexOf($b, [byte]13) -gt 0) "the fixture $f has no CR"
        }
        $s = Get-PqLedgerSnapshot -RepoPath $repo -Key 'fms' -At $LedgerT0
        Assert-That ($s.bad -eq 0) "BOM and CRLF gave $($s.bad) bad lines, expected 0"
        Assert-That ((@($s.tickets.Keys) -join ',') -ceq 'S0001,S0002,S0003,S0004') "the snapshot holds [$(@($s.tickets.Keys) -join ',')], expected [S0001,S0002,S0003,S0004] (no BOM in the first id)"
        Assert-That ($s.tickets['S0002'].status -ceq 'In Progress') "a CRLF row reads status '$($s.tickets['S0002'].status)'"
        $stamp = ConvertTo-LocalStamp $u
        foreach ($id in 'S0001', 'S0002', 'S0003', 'S0004') {
            Assert-That ($s.tickets[$id].updated -ceq $stamp) "$id reads updated '$($s.tickets[$id].updated)', expected '$stamp' (no CR)"
        }
        Assert-That ($s.tickets['S0004'].status -ceq 'Archived') "the last archive row without a line end reads '$($s.tickets['S0004'].status)'"
    }

    Test-Case 'ledger: no change gives an empty diff' {
        . (Get-LibPath 'ledger-watch.ps1')
        $repo = New-Scratch 'repo'
        $u = $LedgerT0.AddMinutes(-10)
        Write-Ledger $repo @((New-LedgerRow 'S0001' 'Draft' $u), (New-LedgerRow 'S0002' 'Approved' $u)) | Out-Null
        Write-Ledger $repo @((New-LedgerRow 'S0003' 'Verified' $u)) -Archive | Out-Null
        $a = Get-PqLedgerSnapshot -RepoPath $repo -Key 'fms' -At $LedgerT0
        $b = Get-PqLedgerSnapshot -RepoPath $repo -Key 'fms' -At $LedgerT0.AddMinutes(5)
        foreach ($pair in @(@($a, $b), @($a, $a))) {
            $d = Compare-PqLedgerSnapshot -Previous $pair[0] -Current $pair[1]
            Assert-That ((Get-Keys $d) -cmatch '^created transitions touched removed') "the diff has the keys [$(Get-Keys $d)], expected created transitions touched removed first"
            $counts = "$($d.created.Count) $($d.transitions.Count) $($d.touched.Count) $($d.removed.Count)"
            Assert-That ($counts -ceq '0 0 0 0') "no change gave created/transitions/touched/removed $counts, expected 0 0 0 0"
        }
        $events = @(Get-PqLedgerEvents -Previous $a -Current $b -LivePasses @() -RepoRunnerRows @())
        Assert-That ($events.Count -eq 0) "no change yielded $($events.Count) events, expected none (rule 58: nothing changed, nothing logged)"
    }

    Test-Case 'ledger: a new id is created and a changed status is one transition with from, to and updated' {
        . (Get-LibPath 'ledger-watch.ps1')
        $repo = New-Scratch 'repo'
        $u1 = $LedgerT0.AddMinutes(-40); $u2 = $LedgerT0.AddMinutes(2)
        Write-Ledger $repo @((New-LedgerRow 'S0001' 'Draft' $u1)) | Out-Null
        $a = Get-PqLedgerSnapshot -RepoPath $repo -Key 'fms' -At $LedgerT0
        Write-Ledger $repo @((New-LedgerRow 'S0001' 'Approved' $u2), (New-LedgerRow 'S0002' 'Draft' $u2 -Priority 40 -Created '2026-10-27')) | Out-Null
        $b = Get-PqLedgerSnapshot -RepoPath $repo -Key 'fms' -At $LedgerT0.AddMinutes(5)
        $d = Compare-PqLedgerSnapshot -Previous $a -Current $b
        Assert-That ($d.created.Count -eq 1 -and $d.created[0].id -ceq 'S0002') "created [$(@($d.created | ForEach-Object { $_.id }) -join ',')], expected [S0002]"
        Assert-That ($d.created[0].status -ceq 'Draft' -and $d.created[0].priority -eq 40) "the created record reads status '$($d.created[0].status)' priority '$($d.created[0].priority)'"
        Assert-That ($d.transitions.Count -eq 1) "$($d.transitions.Count) transitions, expected 1"
        $t = $d.transitions[0]
        Assert-That ((Get-Keys $t) -cmatch '^id from to updatedFrom updatedTo') "a transition has the keys [$(Get-Keys $t)], expected id from to updatedFrom updatedTo first"
        Assert-That ($t.id -ceq 'S0001' -and $t.from -ceq 'Draft' -and $t.to -ceq 'Approved') "the transition is $($t.id) '$($t.from)' -> '$($t.to)', expected S0001 Draft -> Approved"
        Assert-That ($t.updatedFrom -ceq (ConvertTo-LocalStamp $u1) -and $t.updatedTo -ceq (ConvertTo-LocalStamp $u2)) "the transition carries updated '$($t.updatedFrom)' -> '$($t.updatedTo)'"
        Assert-That ($d.touched.Count -eq 0 -and $d.removed.Count -eq 0) "touched $($d.touched.Count) removed $($d.removed.Count), expected 0 and 0"
    }

    Test-Case 'ledger: a status change plus a priority edit in one interval is one transition, a priority-only edit is touched and not a transition' {
        . (Get-LibPath 'ledger-watch.ps1')
        $repo = New-Scratch 'repo'
        $u1 = $LedgerT0.AddMinutes(-40); $u2 = $LedgerT0.AddMinutes(2)
        Write-Ledger $repo @((New-LedgerRow 'S0001' 'Draft' $u1), (New-LedgerRow 'S0002' 'Draft' $u1), (New-LedgerRow 'S0003' 'Draft' $u1)) | Out-Null
        $a = Get-PqLedgerSnapshot -RepoPath $repo -Key 'fms' -At $LedgerT0
        # S0001: status and priority in one interval; S0002: priority only (the tool moves updated); S0003: priority
        # only within the same minute (updated unchanged).
        Write-Ledger $repo @((New-LedgerRow 'S0001' 'Approved' $u2 -Priority 80), (New-LedgerRow 'S0002' 'Draft' $u2 -Priority 80), (New-LedgerRow 'S0003' 'Draft' $u1 -Priority 60)) | Out-Null
        $b = Get-PqLedgerSnapshot -RepoPath $repo -Key 'fms' -At $LedgerT0.AddMinutes(5)
        $d = Compare-PqLedgerSnapshot -Previous $a -Current $b
        $tr = @($d.transitions | ForEach-Object { $_.id }) -join ','
        $to = @($d.touched | ForEach-Object { $_.id }) -join ','
        Assert-That ($tr -ceq 'S0001') "transitions [$tr], expected [S0001]"
        Assert-That ($to -ceq 'S0002,S0003') "touched [$to], expected [S0002,S0003] (a status change is never also touched)"
        Assert-That ($d.transitions[0].from -ceq 'Draft' -and $d.transitions[0].to -ceq 'Approved') "the transition is '$($d.transitions[0].from)' -> '$($d.transitions[0].to)'"
        $t = $d.touched[0]
        Assert-That ($t.status -ceq 'Draft' -and $t.updatedFrom -ceq (ConvertTo-LocalStamp $u1) -and $t.updatedTo -ceq (ConvertTo-LocalStamp $u2)) "S0002 touched reads status '$($t.status)' updated '$($t.updatedFrom)' -> '$($t.updatedTo)'"
        $events = @(Get-PqLedgerEvents -Previous $a -Current $b -LivePasses @() -RepoRunnerRows @())
        $names = @($events | ForEach-Object { "$($_.Ev):$($_.Id)" }) -join ','
        Assert-That ($names -ceq 'ticket.transition:S0001,ingest.ledgerDiff:') "the events are [$names], expected one transition and the diff (a touched ticket is no event)"
    }

    Test-Case 'ledger: a ticket moved from the ledger to the archive is a transition to Archived, not removed' {
        . (Get-LibPath 'ledger-watch.ps1')
        $repo = New-Scratch 'repo'
        $u1 = $LedgerT0.AddMinutes(-40); $u2 = $LedgerT0.AddMinutes(2); $u3 = $LedgerT0.AddMinutes(12)
        Write-Ledger $repo @((New-LedgerRow 'S0001' 'Verified' $u1), (New-LedgerRow 'S0002' 'Draft' $u1)) | Out-Null
        Write-Ledger $repo @() -Archive | Out-Null
        $a = Get-PqLedgerSnapshot -RepoPath $repo -Key 'fms' -At $LedgerT0
        Write-Ledger $repo @((New-LedgerRow 'S0002' 'Draft' $u1)) | Out-Null
        Write-Ledger $repo @((New-LedgerRow 'S0001' 'Verified' $u2)) -Archive | Out-Null
        $b = Get-PqLedgerSnapshot -RepoPath $repo -Key 'fms' -At $LedgerT0.AddMinutes(5)
        $d = Compare-PqLedgerSnapshot -Previous $a -Current $b
        Assert-That ($d.removed.Count -eq 0 -and $d.created.Count -eq 0) "archiving gave removed $($d.removed.Count) created $($d.created.Count), expected 0 and 0"
        Assert-That ($d.transitions.Count -eq 1 -and $d.transitions[0].id -ceq 'S0001' -and $d.transitions[0].from -ceq 'Verified' -and $d.transitions[0].to -ceq 'Archived') "archiving gave the transitions [$(@($d.transitions | ForEach-Object { "$($_.id) $($_.from)->$($_.to)" }) -join ',')], expected [S0001 Verified->Archived]"
        # Revived: back from the archive into the ledger is a transition out of Archived.
        Write-Ledger $repo @((New-LedgerRow 'S0001' 'Draft' $u3), (New-LedgerRow 'S0002' 'Draft' $u1)) | Out-Null
        Write-Ledger $repo @() -Archive | Out-Null
        $c = Get-PqLedgerSnapshot -RepoPath $repo -Key 'fms' -At $LedgerT0.AddMinutes(15)
        $d = Compare-PqLedgerSnapshot -Previous $b -Current $c
        Assert-That ($d.transitions.Count -eq 1 -and $d.transitions[0].from -ceq 'Archived' -and $d.transitions[0].to -ceq 'Draft' -and $d.removed.Count -eq 0 -and $d.created.Count -eq 0) "reviving gave transitions [$(@($d.transitions | ForEach-Object { "$($_.id) $($_.from)->$($_.to)" }) -join ',')] removed $($d.removed.Count) created $($d.created.Count)"
    }

    Test-Case 'ledger: an id gone from both files is removed and reported once' {
        . (Get-LibPath 'ledger-watch.ps1')
        $repo = New-Scratch 'repo'
        $u = $LedgerT0.AddMinutes(-40)
        Write-Ledger $repo @((New-LedgerRow 'S0001' 'Draft' $u), (New-LedgerRow 'S0002' 'Approved' $u)) | Out-Null
        Write-Ledger $repo @((New-LedgerRow 'S0003' 'Verified' $u)) -Archive | Out-Null
        $a = Get-PqLedgerSnapshot -RepoPath $repo -Key 'fms' -At $LedgerT0
        Write-Ledger $repo @((New-LedgerRow 'S0002' 'Approved' $u)) | Out-Null
        Write-Ledger $repo @() -Archive | Out-Null
        $b = Get-PqLedgerSnapshot -RepoPath $repo -Key 'fms' -At $LedgerT0.AddMinutes(5)
        $c = Get-PqLedgerSnapshot -RepoPath $repo -Key 'fms' -At $LedgerT0.AddMinutes(10)
        $d = Compare-PqLedgerSnapshot -Previous $a -Current $b
        $gone = @($d.removed | ForEach-Object { "$($_.id):$($_.status)" }) -join ','
        Assert-That ($gone -ceq 'S0001:Draft,S0003:Archived') "removed [$gone], expected [S0001:Draft,S0003:Archived] (the last status known)"
        Assert-That ($d.transitions.Count -eq 0 -and $d.created.Count -eq 0 -and $d.touched.Count -eq 0) "a removal also gave transitions $($d.transitions.Count) created $($d.created.Count) touched $($d.touched.Count)"
        $d = Compare-PqLedgerSnapshot -Previous $b -Current $c
        Assert-That ($d.removed.Count -eq 0) "the next interval reported the removal again: [$(@($d.removed | ForEach-Object { $_.id }) -join ',')]"
        $events = @(Get-PqLedgerEvents -Previous $a -Current $b -LivePasses @() -RepoRunnerRows @())
        Assert-That ($events.Count -eq 0) "a removal yielded $($events.Count) events, expected none (no event name says removed)"
    }

    Test-Case 'ledger: inStatus and leadSoFar are computed in seconds from updated and created' {
        . (Get-LibPath 'ledger-watch.ps1')
        $repo = New-Scratch 'repo'
        $ua = $LedgerT0.AddHours(-3).AddMinutes(-25); $ub = $LedgerT0.AddMinutes(2)
        $created = ConvertTo-LocalStamp $ua.AddDays(-2) 'yyyy-MM-dd'
        $future = ConvertTo-LocalStamp $LedgerT0.AddDays(3) 'yyyy-MM-dd'
        Write-Ledger $repo @(
            (New-LedgerRow 'S0001' 'Draft' $ua -Created $created)
            (New-LedgerRow 'S0002' 'Draft' $LedgerT0.AddMinutes(1) -Created $created)
            (New-LedgerRow 'S0003' 'Draft' $ua -Created $created -Extra ([ordered]@{ updated = 'yesterday' }))
            (New-LedgerRow 'S0004' 'Draft' $ua -Created $future)
        ) | Out-Null
        $a = Get-PqLedgerSnapshot -RepoPath $repo -Key 'fms' -At $LedgerT0
        Write-Ledger $repo @(
            (New-LedgerRow 'S0001' 'Approved' $ub -Created $created)
            (New-LedgerRow 'S0002' 'Tactical' $LedgerT0.AddMinutes(-10) -Created $created)
            (New-LedgerRow 'S0003' 'Approved' $ub -Created $created)
            (New-LedgerRow 'S0004' 'Approved' $ub -Created $future)
        ) | Out-Null
        $b = Get-PqLedgerSnapshot -RepoPath $repo -Key 'fms' -At $LedgerT0.AddMinutes(5)
        $events = @(Get-PqLedgerEvents -Previous $a -Current $b -LivePasses @() -RepoRunnerRows @())
        $byId = @{}
        foreach ($e in $events) { if ($e.Ev -ceq 'ticket.transition') { $byId[$e.Id] = $e.D } }
        Assert-That ($byId.Count -eq 4) "$($byId.Count) ticket.transition events, expected 4"
        $lead = [long](($ub - (Get-LocalDayStartUtc $created)).TotalSeconds)
        $d = $byId['S0001']
        Assert-That ($d.inStatus -is [long] -and $d.inStatus -eq 12420) "S0001 inStatus is '$($d.inStatus)' ($(if ($null -ne $d.inStatus) { $d.inStatus.GetType().Name } else { 'null' })), expected the integer 12420 (3 h 27 min between the two updated)"
        Assert-That ($d.leadSoFar -is [long] -and $d.leadSoFar -eq $lead) "S0001 leadSoFar is '$($d.leadSoFar)', expected $lead (from the local start of $created to the move)"
        Assert-That ($byId['S0002'].inStatus -eq 0) "an updated that went backwards gave inStatus '$($byId['S0002'].inStatus)', expected 0 (never negative)"
        Assert-That ($null -eq $byId['S0003'].inStatus -and $byId['S0003'].leadSoFar -eq $lead) "an unparsable updated gave inStatus '$($byId['S0003'].inStatus)' leadSoFar '$($byId['S0003'].leadSoFar)', expected null and $lead"
        Assert-That ($byId['S0004'].leadSoFar -eq 0) "a created day after the move gave leadSoFar '$($byId['S0004'].leadSoFar)', expected 0 (never negative)"
    }

    # Review finding 4: EVENTS.md 3.5 defines inStatus as the seconds spent in from; a same-status edit moves updated,
    # so updatedFrom alone understates it. The caller keeps the entry instants (-EnteredAt, Update-PqEnteredAt).
    Test-Case 'ledger: with -EnteredAt, inStatus runs from the entry into from, so a same-status edit does not shorten it' {
        . (Get-LibPath 'ledger-watch.ps1')
        $repo = New-Scratch 'repo'
        $t10 = $LedgerT0.AddHours(-2); $t11 = $LedgerT0.AddHours(-1); $t12 = $LedgerT0
        Write-Ledger $repo @((New-LedgerRow 'S0001' 'Spec' $t10), (New-LedgerRow 'S0003' 'Draft' $t10)) | Out-Null
        $a = Get-PqLedgerSnapshot -RepoPath $repo -Key 'fms' -At $t10.AddMinutes(1)
        $map = @{}
        Update-PqEnteredAt -EnteredAt $map -Previous $null -Current $a
        Assert-That ((@($map.Keys | Sort-Object) -join ',') -ceq 'S0001,S0003' -and $map['S0001'] -ceq (ConvertTo-LocalStamp $t10)) "the baseline map is [$(@($map.Keys | Sort-Object) -join ',')] S0001 '$($map['S0001'])'"
        # 11:00 a priority edit of S0001 (status unchanged, updated moves) and a new S0002.
        Write-Ledger $repo @((New-LedgerRow 'S0001' 'Spec' $t11 -Priority 60), (New-LedgerRow 'S0002' 'Draft' $t11), (New-LedgerRow 'S0003' 'Draft' $t10)) | Out-Null
        $b = Get-PqLedgerSnapshot -RepoPath $repo -Key 'fms' -At $t11.AddMinutes(1)
        $ev1 = @(Get-PqLedgerEvents -Previous $a -Current $b -LivePasses @() -RepoRunnerRows @() -EnteredAt $map)
        Assert-That ((@($ev1 | ForEach-Object { "$($_.Ev):$($_.Id)" }) -join ',') -ceq 'ticket.created:S0002,ingest.ledgerDiff:') "the 11:00 interval yielded [$(@($ev1 | ForEach-Object { "$($_.Ev):$($_.Id)" }) -join ',')]"
        Update-PqEnteredAt -EnteredAt $map -Previous $a -Current $b
        Assert-That ($map['S0001'] -ceq (ConvertTo-LocalStamp $t10)) "a same-status edit moved the entry of S0001 to '$($map['S0001'])'"
        Assert-That ($map['S0002'] -ceq (ConvertTo-LocalStamp $t11)) "the created S0002 entered at '$($map['S0002'])'"
        # 12:00 S0001 moves to Ready; S0002 is gone; S0003 moves, but the map has lost it (fallback: updatedFrom).
        Write-Ledger $repo @((New-LedgerRow 'S0001' 'Ready' $t12 -Priority 60), (New-LedgerRow 'S0003' 'Approved' $t12)) | Out-Null
        $map.Remove('S0003')
        $c = Get-PqLedgerSnapshot -RepoPath $repo -Key 'fms' -At $t12.AddMinutes(1)
        $byId = @{}
        foreach ($e in @(Get-PqLedgerEvents -Previous $b -Current $c -LivePasses @() -RepoRunnerRows @() -EnteredAt $map)) { if ($e.Ev -ceq 'ticket.transition') { $byId[$e.Id] = $e.D } }
        Assert-That ($byId['S0001'].inStatus -is [long] -and $byId['S0001'].inStatus -eq 7200) "S0001 inStatus is '$($byId['S0001'].inStatus)', expected 7200 (10:00 to 12:00 in Spec)"
        Assert-That ($byId['S0003'].inStatus -eq 7200) "S0003 (not in the map) inStatus is '$($byId['S0003'].inStatus)', expected 7200 from updatedFrom"
        $plain = @{}
        foreach ($e in @(Get-PqLedgerEvents -Previous $b -Current $c -LivePasses @() -RepoRunnerRows @())) { if ($e.Ev -ceq 'ticket.transition') { $plain[$e.Id] = $e.D } }
        Assert-That ($plain['S0001'].inStatus -eq 3600) "without -EnteredAt S0001 inStatus is '$($plain['S0001'].inStatus)', expected 3600 (the lower bound from updatedFrom)"
        Update-PqEnteredAt -EnteredAt $map -Previous $b -Current $c
        Assert-That ((@($map.Keys | Sort-Object) -join ',') -ceq 'S0001,S0003') "after the 12:00 interval the map holds [$(@($map.Keys | Sort-Object) -join ',')], expected [S0001,S0003] (S0002 is gone)"
        Assert-That ($map['S0001'] -ceq (ConvertTo-LocalStamp $t12) -and $map['S0003'] -ceq (ConvertTo-LocalStamp $t12)) "the moves entered at '$($map['S0001'])' and '$($map['S0003'])'"
        # An incomplete snapshot changes nothing.
        $before = ($map.Keys | Sort-Object | ForEach-Object { "$_=$($map[$_])" }) -join ','
        $broken = Get-PqLedgerSnapshot -RepoPath $repo -Key 'fms' -At $t12.AddMinutes(2)
        $broken.complete = $false
        Update-PqEnteredAt -EnteredAt $map -Previous $c -Current $broken
        Assert-That ((($map.Keys | Sort-Object | ForEach-Object { "$_=$($map[$_])" }) -join ',') -ceq $before) 'an incomplete snapshot changed the map'
    }

    # Review finding 12: a JSON array or object priority compared by reference made an unchanged ticket touched.
    Test-Case 'ledger: an array or object priority is compared by value, so an unchanged ledger is not touched' {
        . (Get-LibPath 'ledger-watch.ps1')
        $repo = New-Scratch 'repo'
        $u = $LedgerT0.AddMinutes(-10)
        $rows = @((New-LedgerRow 'S0001' 'Draft' $u -Extra ([ordered]@{ priority = @(1, 2) })), (New-LedgerRow 'S0002' 'Draft' $u -Extra ([ordered]@{ priority = [ordered]@{ a = 1 } })), (New-LedgerRow 'S0003' 'Draft' $u))
        Write-Ledger $repo $rows | Out-Null
        $a = Get-PqLedgerSnapshot -RepoPath $repo -Key 'fms' -At $LedgerT0
        $b = Get-PqLedgerSnapshot -RepoPath $repo -Key 'fms' -At $LedgerT0.AddMinutes(5)
        Assert-That ($a.bad -eq 0 -and $a.tickets.Count -eq 3) "the ledger reads bad $($a.bad) tickets $($a.tickets.Count), expected 0 and 3 (a malformed priority keeps its row)"
        Assert-That ($a.tickets['S0001'].priority -ceq '[1,2]' -and $a.tickets['S0002'].priority -ceq '{"a":1}') "the priorities read '$($a.tickets['S0001'].priority)' and '$($a.tickets['S0002'].priority)', expected their compact JSON"
        $d = Compare-PqLedgerSnapshot -Previous $a -Current $b
        Assert-That ($d.touched.Count -eq 0 -and $d.transitions.Count -eq 0) "an unchanged ledger gave touched [$(@($d.touched | ForEach-Object { $_.id }) -join ',')], expected none"
        $rows[0] = New-LedgerRow 'S0001' 'Draft' $u -Extra ([ordered]@{ priority = @(1, 3) })
        Write-Ledger $repo $rows | Out-Null
        $c = Get-PqLedgerSnapshot -RepoPath $repo -Key 'fms' -At $LedgerT0.AddMinutes(10)
        $d = Compare-PqLedgerSnapshot -Previous $b -Current $c
        Assert-That ((@($d.touched | ForEach-Object { $_.id }) -join ',') -ceq 'S0001') "a priority [1,2] -> [1,3] gave touched [$(@($d.touched | ForEach-Object { $_.id }) -join ',')], expected [S0001]"
        Assert-That ($d.touched[0].priorityFrom -ceq '[1,2]' -and $d.touched[0].priorityTo -ceq '[1,3]') "the touched record reads '$($d.touched[0].priorityFrom)' -> '$($d.touched[0].priorityTo)'"
    }

    Test-Case 'actor: a pass live on the ticket in the window is robot' {
        . (Get-LibPath 'ledger-watch.ps1')
        $p = 'R20261027T115500-0a0b.1'
        $rows = @()
        $cases = @(
            @{ Want = 'robot'; Passes = @((New-LivePass 'fms' 'S0001' $p $LedgerT0.AddMinutes(1) $LedgerT0.AddMinutes(3))); What = 'a pass inside the window' }
            @{ Want = 'robot'; Passes = @((New-LivePass 'fms' 'S0001' $p $LedgerT0.AddMinutes(-30) $null)); What = 'a running pass that started before the window' }
            @{ Want = 'robot'; Passes = @((New-LivePass 'fms' 'S0001' $p $LedgerT0.AddMinutes(-30) $LedgerT0.AddMinutes(30))); What = 'a pass spanning the whole window' }
            @{ Want = 'manual'; Passes = @((New-LivePass 'fms' 'S0002' $p $LedgerT0.AddMinutes(1) $LedgerT0.AddMinutes(3))); What = 'a pass on another ticket' }
            @{ Want = 'manual'; Passes = @((New-LivePass 'web' 'S0001' $p $LedgerT0.AddMinutes(1) $LedgerT0.AddMinutes(3))); What = 'a pass on the same id in another repository' }
            @{ Want = 'manual'; Passes = @((New-LivePass 'fms' 'S0001' $p $LedgerT0.AddMinutes(-30) $LedgerT0.AddMinutes(-20))); What = 'a pass that ended before the window' }
            @{ Want = 'manual'; Passes = @((New-LivePass 'fms' 'S0001' $p $LedgerT0.AddMinutes(10) $null)); What = 'a pass that started after the window' }
            @{ Want = 'robot'; Passes = @((New-LivePass 'web' 'S0001' 'x.1' $LedgerT0 $null), (New-LivePass 'fms' 'S0002' 'x.2' $LedgerT0 $null), (New-LivePass 'fms' 'S0001' $p $LedgerT0.AddMinutes(1) $null)); What = 'the matching pass third in a list' }
            @{ Want = 'manual'; Passes = @(); What = 'no live pass' }
        )
        foreach ($c in $cases) {
            $got = Get-TestActor $c.Passes $rows
            Assert-That ($got -ceq $c.Want) "$($c.What) gave '$got', expected $($c.Want)"
        }
    }

    Test-Case 'actor: the window is widened by one minute, the resolution of updated' {
        . (Get-LibPath 'ledger-watch.ps1')
        $p = 'R20261027T115500-0a0b.1'
        $end = $LedgerT0.AddMinutes(5)
        $cases = @(
            @{ Want = 'robot'; Passes = @((New-LivePass 'fms' 'S0001' $p $LedgerT0.AddMinutes(-30) $LedgerT0.AddSeconds(-45))); Rows = @(); What = 'a pass that ended 45 s before the window start' }
            @{ Want = 'manual'; Passes = @((New-LivePass 'fms' 'S0001' $p $LedgerT0.AddMinutes(-30) $LedgerT0.AddSeconds(-90))); Rows = @(); What = 'a pass that ended 90 s before the window start' }
            @{ Want = 'robot'; Passes = @((New-LivePass 'fms' 'S0001' $p $end.AddSeconds(45) $null)); Rows = @(); What = 'a pass that started 45 s after the window end' }
            @{ Want = 'manual'; Passes = @((New-LivePass 'fms' 'S0001' $p $end.AddSeconds(90) $null)); Rows = @(); What = 'a pass that started 90 s after the window end' }
            # Rows whose statuses do not match the move are covered by their finishedAt alone.
            @{ Want = 'repo-runner'; Passes = @(); Rows = @((New-RunRow 'S0001' 'Tactical' 'In Progress' $LedgerT0.AddSeconds(-45))); What = 'a row that finished 45 s before the window start' }
            @{ Want = 'manual'; Passes = @(); Rows = @((New-RunRow 'S0001' 'Tactical' 'In Progress' $LedgerT0.AddSeconds(-90))); What = 'a row that finished 90 s before the window start' }
            @{ Want = 'repo-runner'; Passes = @(); Rows = @((New-RunRow 'S0001' 'Tactical' 'In Progress' $end.AddSeconds(45))); What = 'a row that finished 45 s after the window end' }
            @{ Want = 'manual'; Passes = @(); Rows = @((New-RunRow 'S0001' 'Tactical' 'In Progress' $end.AddSeconds(90))); What = 'a row that finished 90 s after the window end' }
        )
        foreach ($c in $cases) {
            $got = Get-TestActor $c.Passes $c.Rows
            Assert-That ($got -ceq $c.Want) "$($c.What) gave '$got', expected $($c.Want)"
        }
    }

    Test-Case 'actor: a repository runner row matching id, from and to is repo-runner, and an instance named pq<k> is robot' {
        . (Get-LibPath 'ledger-watch.ps1')
        $in = $LedgerT0.AddMinutes(2).AddSeconds(30)
        $cases = @(
            @{ Want = 'repo-runner'; Rows = @((New-RunRow 'S0001' 'Draft' 'Approved' $in 'a')); What = 'a row of instance a' }
            @{ Want = 'robot'; Rows = @((New-RunRow 'S0001' 'Draft' 'Approved' $in 'pq1')); What = 'a row of instance pq1' }
            @{ Want = 'robot'; Rows = @((New-RunRow 'S0001' 'Draft' 'Approved' $in 'pq12')); What = 'a row of instance pq12' }
            @{ Want = 'repo-runner'; Rows = @((New-RunRow 'S0001' 'Draft' 'Approved' $in 'pq')); What = 'a row of instance pq (no number)' }
            @{ Want = 'repo-runner'; Rows = @((New-RunRow 'S0001' 'Draft' 'Approved' $in 'pqx')); What = 'a row of instance pqx' }
            @{ Want = 'repo-runner'; Rows = @((New-RunRow 'S0001' 'Draft' 'Approved' $in 'PQ1')); What = 'a row of instance PQ1 (the name is case-sensitive)' }
            @{ Want = 'repo-runner'; Rows = @((New-RunRow 'S0001' 'Draft' 'Approved' $in 'xpq1')); What = 'a row of instance xpq1' }
            @{ Want = 'manual'; Rows = @((New-RunRow 'S0002' 'Draft' 'Approved' $in 'a')); What = 'a row of another ticket' }
            # The same move, its row landed after the observation: still the run that made it.
            @{ Want = 'repo-runner'; Rows = @((New-RunRow 'S0001' 'Draft' 'Approved' $LedgerT0.AddMinutes(20) 'a')); What = 'a row of the same move that finished after the window' }
            # The same move made by an earlier run: the observation at the window start still saw Draft, so not this one.
            @{ Want = 'manual'; Rows = @((New-RunRow 'S0001' 'Draft' 'Approved' $LedgerT0.AddMinutes(-30) 'a')); What = 'a row of the same move that finished before the window' }
            @{ Want = 'manual'; Rows = @((New-RunRow 'S0001' 'Approved' 'Tactical' $LedgerT0.AddMinutes(20) 'a')); What = 'a row of another move that finished after the window' }
            @{ Want = 'repo-runner'; Rows = @((New-RunRow 'S0001' 'Approved' 'Tactical' $in 'a')); What = 'a row of another move that finished in the window' }
            # Review finding 7: an array id, or an array instance, is not the scalar it wraps.
            @{ Want = 'manual'; Rows = @((New-RunRow 'S0001' 'Draft' 'Approved' $in 'a' | ForEach-Object { $_.id = @('S0001'); $_ })); What = 'a row whose id is the array ["S0001"]' }
            @{ Want = 'repo-runner'; Rows = @((New-RunRow 'S0001' 'Draft' 'Approved' $in 'a' | ForEach-Object { $_.instance = @('pq1'); $_ })); What = 'a row whose instance is the array ["pq1"]' }
        )
        foreach ($c in $cases) {
            $got = Get-TestActor @() $c.Rows
            Assert-That ($got -ceq $c.Want) "$($c.What) gave '$got', expected $($c.Want)"
        }
    }

    Test-Case 'actor: robot wins when a live pass and a row of another instance both cover the transition' {
        . (Get-LibPath 'ledger-watch.ps1')
        $p = 'R20261027T115500-0a0b.1'
        $in = $LedgerT0.AddMinutes(2).AddSeconds(30)
        $live = @((New-LivePass 'fms' 'S0001' $p $LedgerT0.AddMinutes(1) $LedgerT0.AddMinutes(3)))
        $rowA = New-RunRow 'S0001' 'Draft' 'Approved' $in 'a'
        $rowPq = New-RunRow 'S0001' 'Draft' 'Approved' $in 'pq2'
        $got = Get-TestActor $live @($rowA)
        Assert-That ($got -ceq 'robot') "a live pass and a row of instance a gave '$got', expected robot"
        $got = Get-TestActor @() @($rowA, $rowPq)
        Assert-That ($got -ceq 'robot') "a row of a then a row of pq2 gave '$got', expected robot"
        $got = Get-TestActor @() @($rowPq, $rowA)
        Assert-That ($got -ceq 'robot') "a row of pq2 then a row of a gave '$got', expected robot"
        # Through Get-PqLedgerEvents the live pass is named in viaPass and in the envelope's pass.
        $repo = New-Scratch 'repo'
        Write-Ledger $repo @((New-LedgerRow 'S0001' 'Draft' $LedgerT0.AddMinutes(-60))) | Out-Null
        $a = Get-PqLedgerSnapshot -RepoPath $repo -Key 'fms' -At $LedgerT0
        Write-Ledger $repo @((New-LedgerRow 'S0001' 'Approved' $LedgerT0.AddMinutes(2))) | Out-Null
        $b = Get-PqLedgerSnapshot -RepoPath $repo -Key 'fms' -At $LedgerT0.AddMinutes(5)
        $e = @(Get-PqLedgerEvents -Previous $a -Current $b -LivePasses $live -RepoRunnerRows @($rowA))[0]
        Assert-That ($e.Ev -ceq 'ticket.transition' -and $e.D.actor -ceq 'robot' -and $e.D.viaPass -ceq $p -and $e.Pass -ceq $p) "the event is $($e.Ev) actor '$($e.D.actor)' viaPass '$($e.D.viaPass)' pass '$($e.Pass)', expected robot via $p"
    }

    Test-Case 'actor: neither is manual; an unreadable journal (null) with no live pass is unknown and counted' {
        . (Get-LibPath 'ledger-watch.ps1')
        $p = 'R20261027T115500-0a0b.1'
        $got = Get-TestActor @() @()
        Assert-That ($got -ceq 'manual') "no live pass and a readable empty journal gave '$got', expected manual"
        $got = Get-TestActor @() $null
        Assert-That ($got -ceq 'unknown') "no live pass and an unreadable journal gave '$got', expected unknown"
        $got = Get-TestActor @((New-LivePass 'fms' 'S0001' $p $LedgerT0.AddMinutes(1) $null)) $null
        Assert-That ($got -ceq 'robot') "a live pass and an unreadable journal gave '$got', expected robot (the pass is evidence enough)"
        $got = Get-TestActor @((New-LivePass 'fms' 'S0002' $p $LedgerT0.AddMinutes(1) $null)) $null
        Assert-That ($got -ceq 'unknown') "a pass on another ticket and an unreadable journal gave '$got', expected unknown"
        $repo = New-Scratch 'repo'
        $u = $LedgerT0.AddMinutes(-60)
        Write-Ledger $repo @((New-LedgerRow 'S0001' 'Draft' $u), (New-LedgerRow 'S0002' 'Approved' $u)) | Out-Null
        $a = Get-PqLedgerSnapshot -RepoPath $repo -Key 'fms' -At $LedgerT0
        Write-Ledger $repo @((New-LedgerRow 'S0001' 'Approved' $LedgerT0.AddMinutes(2)), (New-LedgerRow 'S0002' 'Tactical' $LedgerT0.AddMinutes(3))) | Out-Null
        $b = Get-PqLedgerSnapshot -RepoPath $repo -Key 'fms' -At $LedgerT0.AddMinutes(5)
        $events = @(Get-PqLedgerEvents -Previous $a -Current $b -LivePasses @() -RepoRunnerRows $null)
        $actors = @($events | Where-Object { $_.Ev -ceq 'ticket.transition' } | ForEach-Object { $_.D.actor }) -join ','
        Assert-That ($actors -ceq 'unknown,unknown') "an unreadable journal gave the actors [$actors], expected [unknown,unknown]"
        $diff = @($events | Where-Object { $_.Ev -ceq 'ingest.ledgerDiff' })
        Assert-That ($diff.Count -eq 1 -and $diff[0].D.unattributed -eq 2) "ingest.ledgerDiff unattributed is '$(if ($diff.Count) { $diff[0].D.unattributed })', expected 2"
        $events = @(Get-PqLedgerEvents -Previous $a -Current $b -LivePasses @() -RepoRunnerRows @())
        $diff = @($events | Where-Object { $_.Ev -ceq 'ingest.ledgerDiff' })
        Assert-That ($diff.Count -eq 1 -and $diff[0].D.unattributed -eq 0) "a readable journal left unattributed '$(if ($diff.Count) { $diff[0].D.unattributed })', expected 0"
    }

    Test-Case 'ledger: Get-PqLedgerEvents yields ticket.transition, ticket.created and one ingest.ledgerDiff with transitions, created and unattributed' {
        . (Get-LibPath 'ledger-watch.ps1')
        $p = 'R20261027T115500-0a0b.1'
        $repo = New-Scratch 'repo'
        $u = $LedgerT0.AddMinutes(-60)
        Write-Ledger $repo @((New-LedgerRow 'S0001' 'Draft' $u), (New-LedgerRow 'S0002' 'Approved' $u)) | Out-Null
        $a = Get-PqLedgerSnapshot -RepoPath $repo -Key 'fms' -At $LedgerT0
        Write-Ledger $repo @(
            (New-LedgerRow 'S0001' 'Approved' $LedgerT0.AddMinutes(2))
            (New-LedgerRow 'S0002' 'Tactical' $LedgerT0.AddMinutes(3))
            (New-LedgerRow 'S0003' 'Draft' $LedgerT0.AddMinutes(4) -Priority 40 -Created (ConvertTo-LocalStamp $LedgerT0 'yyyy-MM-dd'))
        ) | Out-Null
        $b = Get-PqLedgerSnapshot -RepoPath $repo -Key 'fms' -At $LedgerT0.AddMinutes(5)
        $live = @((New-LivePass 'fms' 'S0001' $p $LedgerT0.AddMinutes(1) $LedgerT0.AddMinutes(4)))
        $events = @(Get-PqLedgerEvents -Previous $a -Current $b -LivePasses $live -RepoRunnerRows @())
        $names = @($events | ForEach-Object { "$($_.Ev):$($_.Id)" }) -join ','
        Assert-That ($names -ceq 'ticket.transition:S0001,ticket.transition:S0002,ticket.created:S0003,ingest.ledgerDiff:') "the events are [$names], expected the two transitions, the created ticket, then one ingest.ledgerDiff"
        foreach ($e in $events) {
            Assert-That ((@($e.Keys) -join ' ') -ceq 'Ev Repo Id Pass D') "an event has the keys [$(@($e.Keys) -join ' ')], expected [Ev Repo Id Pass D]"
            Assert-That ($e.Repo -ceq 'fms') "$($e.Ev) carries repo '$($e.Repo)', expected fms"
        }
        $t1 = $events[0]; $t2 = $events[1]; $cr = $events[2]; $df = $events[3]
        Assert-That ((@($t1.D.Keys) -join ' ') -ceq 'from to actor viaPass inStatus leadSoFar') "ticket.transition d has the keys [$(@($t1.D.Keys) -join ' ')]"
        Assert-That ($t1.D.from -ceq 'Draft' -and $t1.D.to -ceq 'Approved' -and $t1.D.actor -ceq 'robot' -and $t1.D.viaPass -ceq $p -and $t1.Pass -ceq $p) "S0001 reads '$($t1.D.from)' -> '$($t1.D.to)' actor '$($t1.D.actor)' viaPass '$($t1.D.viaPass)' pass '$($t1.Pass)'"
        Assert-That ($t1.D.inStatus -eq 3720) "S0001 inStatus is '$($t1.D.inStatus)', expected 3720"
        Assert-That ($t2.D.actor -ceq 'manual' -and $null -eq $t2.D.viaPass -and $null -eq $t2.Pass -and $t2.D.Contains('viaPass')) "S0002 reads actor '$($t2.D.actor)' viaPass '$($t2.D.viaPass)' pass '$($t2.Pass)', expected manual with an explicit null viaPass"
        Assert-That ((@($cr.D.Keys) -join ' ') -ceq 'source status priority') "ticket.created d has the keys [$(@($cr.D.Keys) -join ' ')]"
        Assert-That ($cr.D.source -ceq 'robot' -and $cr.D.status -ceq 'Draft' -and $cr.D.priority -eq 40) "S0003 reads source '$($cr.D.source)' status '$($cr.D.status)' priority '$($cr.D.priority)', expected robot Draft 40 (a pass of fms was live in the window)"
        Assert-That ($null -eq $df.Id -and $null -eq $df.Pass) "ingest.ledgerDiff carries id '$($df.Id)' pass '$($df.Pass)', expected none"
        Assert-That ((@($df.D.Keys) -join ' ') -ceq 'repo transitions created unattributed') "ingest.ledgerDiff d has the keys [$(@($df.D.Keys) -join ' ')]"
        Assert-That ($df.D.repo -ceq 'fms' -and $df.D.transitions -eq 2 -and $df.D.created -eq 1 -and $df.D.unattributed -eq 0) "ingest.ledgerDiff reads repo '$($df.D.repo)' transitions $($df.D.transitions) created $($df.D.created) unattributed $($df.D.unattributed)"
        # No live pass of the repository: the owner created it. A pass of another repository changes nothing.
        foreach ($other in @(@(), @((New-LivePass 'web' 'S0003' 'x.1' $LedgerT0 $null)))) {
            $events = @(Get-PqLedgerEvents -Previous $a -Current $b -LivePasses $other -RepoRunnerRows @())
            $cr = @($events | Where-Object { $_.Ev -ceq 'ticket.created' })[0]
            Assert-That ($cr.D.source -ceq 'owner') "without a live pass of fms the created ticket reads source '$($cr.D.source)', expected owner"
        }
        # The first snapshot: no previous. Without -EmitBaseline nothing is yielded; with it every ticket is created.
        foreach ($first in @($null, [pscustomobject]@{ repo = 'fms'; at = $null; tickets = @{}; bad = 0; complete = $true })) {
            $events = @(Get-PqLedgerEvents -Previous $first -Current $b -LivePasses @() -RepoRunnerRows @())
            Assert-That ($events.Count -eq 0) "a first snapshot without -EmitBaseline yielded $($events.Count) events, expected none"
            $events = @(Get-PqLedgerEvents -Previous $first -Current $b -LivePasses @() -RepoRunnerRows @() -EmitBaseline)
            $names = @($events | ForEach-Object { "$($_.Ev):$($_.Id)" }) -join ','
            Assert-That ($names -ceq 'ticket.created:S0001,ticket.created:S0002,ticket.created:S0003,ingest.ledgerDiff:') "a first snapshot with -EmitBaseline yielded [$names]"
            Assert-That ($events[3].D.created -eq 3 -and $events[3].D.transitions -eq 0) "the baseline diff reads created $($events[3].D.created) transitions $($events[3].D.transitions)"
        }
        # A real previous snapshot of an empty ledger is not a first snapshot: its new tickets are created.
        $empty = New-Scratch 'empty'
        $e0 = Get-PqLedgerSnapshot -RepoPath $empty -Key 'fms' -At $LedgerT0
        $events = @(Get-PqLedgerEvents -Previous $e0 -Current $b -LivePasses @() -RepoRunnerRows @())
        Assert-That (@($events | Where-Object { $_.Ev -ceq 'ticket.created' }).Count -eq 3) "after an observed empty ledger $(@($events | Where-Object { $_.Ev -ceq 'ticket.created' }).Count) tickets were created, expected 3"
    }

    Test-Case 'ledger: every event it yields passes Test-PqEnvelope once written and uses a name from Get-PqEventNames' {
        . (Get-LibPath 'ledger-watch.ps1')
        . (Get-LibPath 'events.ps1')
        $p = 'R20261027T115500-0a0b.1'
        $repo = New-Scratch 'repo'
        $u = $LedgerT0.AddMinutes(-60)
        Write-Ledger $repo @((New-LedgerRow 'S0001' 'Draft' $u), (New-LedgerRow 'S0002' 'Approved' $u)) | Out-Null
        $a = Get-PqLedgerSnapshot -RepoPath $repo -Key 'fms' -At $LedgerT0
        Write-Ledger $repo @(
            (New-LedgerRow 'S0001' 'Approved' $LedgerT0.AddMinutes(2))
            (New-LedgerRow 'S0002' 'Tactical' $LedgerT0.AddMinutes(3) -Extra ([ordered]@{ updated = 'not a time' }))
            (New-LedgerRow 'S0003' 'Draft' $LedgerT0.AddMinutes(4) -Priority 40)
        ) | Out-Null
        $b = Get-PqLedgerSnapshot -RepoPath $repo -Key 'fms' -At $LedgerT0.AddMinutes(5)
        $live = @((New-LivePass 'fms' 'S0001' $p $LedgerT0.AddMinutes(1) $LedgerT0.AddMinutes(4)))
        $all = @(Get-PqLedgerEvents -Previous $a -Current $b -LivePasses $live -RepoRunnerRows @()) + @(Get-PqLedgerEvents -Previous $a -Current $b -LivePasses @() -RepoRunnerRows $null) + @(Get-PqLedgerEvents -Previous $null -Current $b -LivePasses @() -RepoRunnerRows @() -EmitBaseline)
        Assert-That ($all.Count -eq 12) "$($all.Count) events were yielded, expected 12 (4 + 4 + 4)"
        $known = [Collections.Generic.HashSet[string]]::new([string[]]@(Get-PqEventNames), [StringComparer]::Ordinal)
        $null = New-TestClock $LedgerT0.AddMinutes(6)
        $h = Open-PqLog -Writer imp -Strict
        foreach ($e in $all) {
            Assert-That ($known.Contains([string]$e.Ev)) "'$($e.Ev)' is not a name of Get-PqEventNames"
            $ok = Write-PqEvent -Log $h -Ev $e.Ev -Repo $e.Repo -Id $e.Id -Pass $e.Pass -D $e.D
            Assert-That ($ok -eq $true) "writing $($e.Ev) returned '$ok'"
        }
        Close-PqLog -Log $h
        $lines = Read-Lines $h.Path
        Assert-That ($lines.Count -eq 12) "the imp file holds $($lines.Count) lines, expected 12 (no log.error)"
        foreach ($l in $lines) {
            $codes = @(Test-PqEnvelope -Line $l) -join ','
            Assert-That ($codes.Length -eq 0) "a written line violates [$codes]: $l"
        }
        $day = Read-PqDay -Path $h.Path
        Assert-That ($day.events.Count -eq 12 -and $day.bad -eq 0 -and $day.unsupported -eq 0 -and $day.gaps.Count -eq 0) "Read-PqDay: $($day.events.Count) events, $($day.bad) bad, $($day.unsupported) unsupported, $($day.gaps.Count) gaps"
        $tr = @($day.events | Where-Object { $_.ev -ceq 'ticket.transition' -and $_.id -ceq 'S0002' })[0]
        Assert-That ((Get-Keys $tr.d) -ceq 'from to actor viaPass inStatus leadSoFar') "a written ticket.transition d has the keys [$(Get-Keys $tr.d)]"
        Assert-That ($null -eq $tr.d.inStatus -and $null -eq $tr.d.viaPass) 'the null inStatus and viaPass did not survive as explicit nulls'
        Assert-KnownEvents $env:SZA_PORTFOLIO_ROOT
    }

    # ---- repopaths: Get-PqRepoPaths, the profile's paths without tools/harness/_profile.ps1 (HARNESS-PROFILE) ----

    Test-Case 'repopaths: a repository without a profile gets the default ledger, archive, queue, ready, done, leases and runs paths' {
        . (Get-LibPath 'ledger-watch.ps1')
        $saved = $env:SZA_TICKET_LEASE_ROOT
        try {
            Remove-Item Env:\SZA_TICKET_LEASE_ROOT -ErrorAction SilentlyContinue
            $repo = New-Scratch 'repo'
            $before = Get-Listing $repo
            $p = Get-PqRepoPaths -RepoPath $repo
            Assert-That (((Get-Listing $repo) -join ';') -ceq ($before -join ';')) 'Get-PqRepoPaths created something'
            Assert-That ((Get-Keys $p) -ceq 'Root EnvPrefix Ledger Archive Queue Ready Done LeasesDir RunsDir SpecsDir TempDir CommandsDir StopFile') "the result has the keys [$(Get-Keys $p)]"
            Assert-That ($p.Root -ceq $repo -and $p.EnvPrefix -ceq 'SZA') "Root '$($p.Root)' EnvPrefix '$($p.EnvPrefix)', expected '$repo' and SZA"
            $want = [ordered]@{ Ledger = 'PLAN/spec-catalog.jsonl'; Archive = 'PLAN/spec-catalog-archive.jsonl'; Queue = 'PLAN/RELEASE_QUEUE.md'
                Ready = 'PLAN/RELEASE_READY.md'; Done = 'PLAN/RELEASE_QUEUE_DONE.md'; LeasesDir = 'temp/SPEC-TICKET.LEASES'; RunsDir = 'temp/spec-queue'
                SpecsDir = 'PLAN'; TempDir = 'temp'; CommandsDir = '.claude/commands'; StopFile = 'temp/STOP-SPEC-QUEUE' }
            foreach ($k in $want.Keys) {
                $expected = $repo + $sep + $want[$k].Replace('/', $sep)
                Assert-That ($p.$k -ceq $expected) "$k is '$($p.$k)', expected '$expected'"
                Assert-That ([IO.Path]::IsPathFullyQualified($p.$k)) "$k '$($p.$k)' is not absolute"
            }
            foreach ($spelling in @(($repo + $sep), $repo.Replace('\', '/'))) {
                $q = Get-PqRepoPaths -RepoPath $spelling
                Assert-That ($q.Root -ceq $repo -and $q.Ledger -ceq $p.Ledger) "-RepoPath '$spelling' gave Root '$($q.Root)' Ledger '$($q.Ledger)'"
            }
            Assert-Throws { Get-PqRepoPaths -RepoPath (Join-Path $repo 'no-such-dir') } 'RepoPathMissing: ' 'a missing repository'
        }
        finally { $env:SZA_TICKET_LEASE_ROOT = $saved }
    }

    Test-Case 'repopaths: paths.journal and friends from .sza-profile.json win, and <envPrefix>_TICKET_LEASE_ROOT moves the leases directory' {
        . (Get-LibPath 'ledger-watch.ps1')
        $savedSza = $env:SZA_TICKET_LEASE_ROOT; $savedFms = $env:FMS_TICKET_LEASE_ROOT
        try {
            Remove-Item Env:\SZA_TICKET_LEASE_ROOT, Env:\FMS_TICKET_LEASE_ROOT -ErrorAction SilentlyContinue
            $repo = New-Scratch 'repo'
            $other = New-Scratch 'other'
            $absDone = (Join-Path $other 'done.md').Replace('\', '/')
            $profileFile = Join-Path $repo '.sza-profile.json'
            $json = [ordered]@{ version = '1'; envPrefix = 'FMS'; paths = [ordered]@{ journal = 'data/ledger.jsonl'; journalArchive = 'data/ledger-archive.jsonl'
                    releaseQueue = 'plan/QUEUE.md'; releaseReady = 'plan/READY.md'; releaseQueueDone = $absDone; leasesDir = 'state/leases'
                    queueRunsDir = 'state/runs'; specsDir = 'specs'; unknownKey = 'x' } } | ConvertTo-Json -Depth 4
            [IO.File]::WriteAllText($profileFile, $json, [Text.UTF8Encoding]::new($true))
            $hash = (Get-FileHash -LiteralPath $profileFile).Hash
            $p = Get-PqRepoPaths -RepoPath $repo
            $want = [ordered]@{ Ledger = 'data/ledger.jsonl'; Archive = 'data/ledger-archive.jsonl'; Queue = 'plan/QUEUE.md'; Ready = 'plan/READY.md'
                LeasesDir = 'state/leases'; RunsDir = 'state/runs'; SpecsDir = 'specs'; TempDir = 'temp'; CommandsDir = '.claude/commands' }
            foreach ($k in $want.Keys) {
                $expected = $repo + $sep + $want[$k].Replace('/', $sep)
                Assert-That ($p.$k -ceq $expected) "$k is '$($p.$k)', expected '$expected'"
            }
            Assert-That ($p.Done -ceq $absDone) "an absolute paths.releaseQueueDone came back as '$($p.Done)', expected '$absDone' as given"
            Assert-That ($p.EnvPrefix -ceq 'FMS') "EnvPrefix is '$($p.EnvPrefix)', expected FMS"
            $lr1 = New-Scratch 'lease-sza'; $lr2 = New-Scratch 'lease-fms'
            $env:SZA_TICKET_LEASE_ROOT = $lr1
            $q = Get-PqRepoPaths -RepoPath $repo
            Assert-That ($q.LeasesDir -ceq $p.LeasesDir) "SZA_TICKET_LEASE_ROOT moved the leases of an FMS-prefixed repository to '$($q.LeasesDir)'"
            $env:FMS_TICKET_LEASE_ROOT = $lr2
            $q = Get-PqRepoPaths -RepoPath $repo
            Assert-That ($q.LeasesDir -ceq ($lr2 + $sep + 'state' + $sep + 'leases')) "FMS_TICKET_LEASE_ROOT gave LeasesDir '$($q.LeasesDir)', expected under '$lr2'"
            Assert-That ($q.Ledger -ceq $p.Ledger -and $q.RunsDir -ceq $p.RunsDir -and $q.Root -ceq $repo) 'the lease root moved more than the leases directory'
            Assert-That ((Get-FileHash -LiteralPath $profileFile).Hash -ceq $hash) 'Get-PqRepoPaths changed the profile'
            # Without envPrefix the prefix is SZA.
            [IO.File]::WriteAllText($profileFile, '{"version":"1","paths":{"leasesDir":"state/leases"}}', [Text.UTF8Encoding]::new($false))
            $q = Get-PqRepoPaths -RepoPath $repo
            Assert-That ($q.EnvPrefix -ceq 'SZA' -and $q.LeasesDir -ceq ($lr1 + $sep + 'state' + $sep + 'leases')) "a profile without envPrefix gave EnvPrefix '$($q.EnvPrefix)' LeasesDir '$($q.LeasesDir)'"
            Assert-That ($q.Ledger -ceq ($repo + $sep + 'PLAN' + $sep + 'spec-catalog.jsonl')) "a profile without paths.journal gave Ledger '$($q.Ledger)'"
            # The last four: an array paths, empty or wrapping an object, is not an object (review finding 7: a one-element
            # array must not unroll to its element, an empty one not to null), and an array value is not a string.
            foreach ($bad in @('{"version":"1",', '[1,2]', '"text"', '{"version":"1","paths":"nope"}', '{"version":"1","paths":{"journal":""}}',
                    '{"version":"1","paths":[]}', '{"version":"1","paths":[{"journal":"other.jsonl"}]}', '{"version":"1","paths":{"journal":["a.jsonl"]}}',
                    '{"version":"1","envPrefix":["FMS"]}')) {
                [IO.File]::WriteAllText($profileFile, $bad, [Text.UTF8Encoding]::new($false))
                Assert-Throws { Get-PqRepoPaths -RepoPath $repo } "ProfileUnreadable: $profileFile" "the profile '$bad'"
            }
        }
        finally { $env:SZA_TICKET_LEASE_ROOT = $savedSza; $env:FMS_TICKET_LEASE_ROOT = $savedFms }
    }

    Test-Case 'repopaths: the answers equal Get-SzaPath of the real profile reader for the same project' {
        . (Get-LibPath 'ledger-watch.ps1')
        $savedSza = $env:SZA_TICKET_LEASE_ROOT; $savedFms = $env:FMS_TICKET_LEASE_ROOT
        try {
            Remove-Item Env:\SZA_TICKET_LEASE_ROOT, Env:\FMS_TICKET_LEASE_ROOT -ErrorAction SilentlyContinue
            $proj = New-Scratch 'proj'
            $scaffold = Join-Path $SourceRoot "tools${sep}harness${sep}scaffold${sep}init-task-flow.ps1"
            $r = Invoke-Child $scaffold @('-Root', $proj) @{ SZA_PROJECT_ROOT = $null; SZA_PROFILE_PATH = $null }
            Assert-That ($r.code -eq 0) "init-task-flow.ps1 exited $($r.code): $($r.output)"
            Assert-That (Test-Path -LiteralPath (Join-Path $proj '.sza-profile.json') -PathType Leaf) 'the scaffold wrote no .sza-profile.json'
            $probe = Get-ProfileProbe
            $harness = Join-Path $SourceRoot "tools${sep}harness"
            $keys = @($RepoPathKeys.Keys) -join ','
            $lr = New-Scratch 'lease-root'
            $other = New-Scratch 'other'
            $passes = @(
                @{ Label = 'the scaffolded profile'; Profile = $null; Lease = $null }
                @{ Label = 'a profile overriding every key'; Lease = $null; Profile = ([ordered]@{ version = '1'; projectName = 'proj'; envPrefix = 'FMS'
                            paths = [ordered]@{ Journal = 'data/ledger.jsonl'; journalArchive = 'data/ledger-archive.jsonl'; releaseQueue = 'plan/QUEUE.md'
                                releaseReady = 'plan/READY.md'; releaseQueueDone = (Join-Path $other 'done.md').Replace('\', '/'); leasesDir = 'state/leases'
                                queueRunsDir = 'state/runs'; specsDir = 'specs'; tempDir = 'tmp'; commandsDir = 'cmds' } } | ConvertTo-Json -Depth 4) }
                @{ Label = 'the same profile with FMS_TICKET_LEASE_ROOT'; Profile = $null; Lease = $lr }
            )
            foreach ($pass in $passes) {
                if ($null -ne $pass.Profile) { [IO.File]::WriteAllText((Join-Path $proj '.sza-profile.json'), $pass.Profile, [Text.UTF8Encoding]::new($false)) }
                $childEnv = @{ SZA_PROJECT_ROOT = $proj; SZA_PROFILE_PATH = $null; SZA_TICKET_LEASE_ROOT = $null; FMS_TICKET_LEASE_ROOT = $pass.Lease }
                $c = Invoke-Child $probe @('-Harness', $harness, '-Keys', $keys) $childEnv
                Assert-That ($c.code -eq 0 -and $c.stderr.Trim().Length -eq 0) "$($pass.Label): the profile probe exited $($c.code): $($c.output)"
                $real = ConvertFrom-Json -InputObject $c.stdout.Trim()
                $env:FMS_TICKET_LEASE_ROOT = $pass.Lease
                $mine = Get-PqRepoPaths -RepoPath $proj
                foreach ($k in $RepoPathKeys.Keys) {
                    if ($k -ceq 'leasesDir' -and $null -ne $pass.Lease) { continue }
                    $prop = $RepoPathKeys[$k]
                    Assert-That ($mine.$prop -ceq $real.$k) "$($pass.Label): $prop is '$($mine.$prop)', Get-SzaPath '$k' is '$($real.$k)'"
                }
                Assert-That ([IO.Path]::GetFullPath($mine.LeasesDir) -ceq [IO.Path]::GetFullPath($real.leaseStore)) "$($pass.Label): LeasesDir is '$($mine.LeasesDir)', the lease store of Get-LeaseStoreDir is '$($real.leaseStore)'"
                Assert-That ($mine.EnvPrefix -ceq $real.envPrefix -and $mine.Root -ceq $real.root) "$($pass.Label): EnvPrefix '$($mine.EnvPrefix)' Root '$($mine.Root)', the profile reader says '$($real.envPrefix)' '$($real.root)'"
            }
            Assert-That ($mine.LeasesDir.StartsWith($lr, [StringComparison]::OrdinalIgnoreCase)) "the last pass did not move the leases under the lease root: '$($mine.LeasesDir)'"
        }
        finally { $env:SZA_TICKET_LEASE_ROOT = $savedSza; $env:FMS_TICKET_LEASE_ROOT = $savedFms }
    }

    # ---- vectors: the catalog's portfolio event vectors (TASK-FLOW rules 53-55, S0015 Phase 00 rungs 1 and 2) ----
    # Read from <CatalogRoot>\task-flow\vectors\portfolio; every case is skipped without -CatalogRoot. The expect
    # files are read by their own key names: the negative one maps a 1-based line number to its rule code, the gap
    # one lists records whose every key must equal the same key of the gap Read-PqDay reports.

    $vectorCases = @(
        'vectors: every line of portfolio-events-sample.jsonl passes Test-PqEnvelope and every ev is in Get-PqEventNames'
        'vectors: each line of portfolio-events-negative.jsonl is rejected with the rule code in portfolio-events-negative.expect.json'
        'vectors: portfolio-events-gap.jsonl reports the gaps of portfolio-events-gap.expect.json, one explained and one not'
    )
    if (-not $CatalogRoot) { foreach ($vc in $vectorCases) { Skip-Case $vc 'no -CatalogRoot given' } }
    else {
        $vectorDir = Join-Path $CatalogRoot "task-flow${sep}vectors${sep}portfolio"

        Test-Case $vectorCases[0] {
            . (Get-LibPath 'events.ps1')
            $file = Join-Path $vectorDir 'portfolio-events-sample.jsonl'
            Assert-That (Test-Path -LiteralPath $file -PathType Leaf) "the catalog has no $file"
            $lines = Read-Lines $file
            Assert-That ($lines.Count -gt 0) 'the sample vector holds no line'
            $known = [Collections.Generic.HashSet[string]]::new([string[]]@(Get-PqEventNames), [StringComparer]::Ordinal)
            $byWriter = [ordered]@{}
            $want = [Collections.Generic.List[string]]::new()
            for ($i = 0; $i -lt $lines.Count; $i++) {
                $codes = @(Test-PqEnvelope -Line $lines[$i])
                Assert-That ($codes.Count -eq 0) "sample line $($i + 1) was rejected with [$($codes -join ',')]"
                $o = ConvertFrom-Json -InputObject $lines[$i] -DateKind String
                Assert-That ($known.Contains([string]$o.ev)) "sample line $($i + 1) has ev '$($o.ev)', which is not a name of Get-PqEventNames"
                $wr = [string]$o.wr
                if (-not $byWriter.Contains($wr)) { $byWriter[$wr] = [Collections.Generic.List[string]]::new() }
                $byWriter[$wr].Add($lines[$i])
                $want.Add(('{0}{1}{2}{1}{3:D20}' -f $o.ts, [char]0, $wr, [long]$o.seq))
            }
            # The sample is one day of several writers: split into one file per writer (cli takes a pid token, rule 54),
            # the merge returns every line, ordered by ts, then wr, then seq, with no bad line, unsupported line or gap.
            $s = New-Scratch 'vector-sample'
            $root = Join-Path $s 'portfolio'
            foreach ($wr in $byWriter.Keys) {
                $token = if ($wr -cin 'cli', 'imp', 'an') { "$wr-1" } else { $wr }
                Write-RawFile (Join-Path $root "log${sep}events-2026-10-27.$token.jsonl") ([string[]]$byWriter[$wr].ToArray())
            }
            $m = Merge-PqDay -Root $root -Date '2026-10-27'
            Assert-That ($m.events.Count -eq $lines.Count) "Merge-PqDay of the split sample returned $($m.events.Count) events, expected $($lines.Count)"
            Assert-That ($m.bad -eq 0 -and $m.unsupported -eq 0 -and $m.gaps.Count -eq 0 -and $m.partial.Count -eq 0) "the split sample has bad $($m.bad), unsupported $($m.unsupported), gaps $($m.gaps.Count), partial $($m.partial.Count), expected none"
            $wantSorted = $want.ToArray()
            [Array]::Sort($wantSorted, [StringComparer]::Ordinal)
            $got = @($m.events | ForEach-Object { '{0}{1}{2}{1}{3:D20}' -f $_.ts, [char]0, $_.wr, [long]$_.seq })
            Assert-That (($got -join "`n") -ceq ($wantSorted -join "`n")) 'Merge-PqDay of the split sample is not in ts, wr, seq order'
            Assert-KnownEvents $root
        }

        Test-Case $vectorCases[1] {
            . (Get-LibPath 'events.ps1')
            $file = Join-Path $vectorDir 'portfolio-events-negative.jsonl'
            $expectFile = Join-Path $vectorDir 'portfolio-events-negative.expect.json'
            Assert-That (Test-Path -LiteralPath $file -PathType Leaf) "the catalog has no $file"
            Assert-That (Test-Path -LiteralPath $expectFile -PathType Leaf) "the catalog has no $expectFile"
            $lines = Read-Lines $file
            $expect = ConvertFrom-Json -InputObject (Get-Content -Raw -LiteralPath $expectFile) -DateKind String
            $keys = @($expect.PSObject.Properties | ForEach-Object { $_.Name })
            Assert-That ($keys.Count -gt 0) 'the negative expect file names no line'
            Assert-That ($keys.Count -eq $lines.Count) "the negative vector has $($lines.Count) lines, its expect file names $($keys.Count)"
            foreach ($k in $keys) {
                Assert-That ($k -cmatch '^[1-9][0-9]*$' -and [int]$k -le $lines.Count) "the negative expect file names line '$k', which the vector does not have"
                $want = [string]$expect.$k
                $got = @(Test-PqEnvelope -Line $lines[[int]$k - 1])
                # Exactly the one code: a line that also broke another rule would no longer test the rule it names.
                Assert-That (($got -join ',') -ceq $want) "negative line ${k}: Test-PqEnvelope gave [$($got -join ',')], expected [$want]"
            }
            # Read as a day file, no negative line is returned: v 2 is unsupported, every other line is bad.
            $day = Read-PqDay -Path $file
            $unsupported = @($keys | Where-Object { [string]$expect.$_ -ceq 'v-not-1' }).Count
            Assert-That ($day.events.Count -eq 0) "Read-PqDay returned $($day.events.Count) events of the negative vector, expected none"
            Assert-That ($day.unsupported -eq $unsupported -and $day.bad -eq $lines.Count - $unsupported) "Read-PqDay counted bad $($day.bad), unsupported $($day.unsupported), expected $($lines.Count - $unsupported) and $unsupported"
        }

        Test-Case $vectorCases[2] {
            . (Get-LibPath 'events.ps1')
            $file = Join-Path $vectorDir 'portfolio-events-gap.jsonl'
            $expectFile = Join-Path $vectorDir 'portfolio-events-gap.expect.json'
            Assert-That (Test-Path -LiteralPath $file -PathType Leaf) "the catalog has no $file"
            Assert-That (Test-Path -LiteralPath $expectFile -PathType Leaf) "the catalog has no $expectFile"
            $expect = @(ConvertFrom-Json -InputObject (Get-Content -Raw -LiteralPath $expectFile) -DateKind String -NoEnumerate)
            if ($expect.Count -eq 1 -and $expect[0] -is [array]) { $expect = @($expect[0]) }
            Assert-That ($expect.Count -gt 0) 'the gap expect file lists no gap'
            $day = Read-PqDay -Path $file
            $lineCount = (Read-Lines $file).Count
            Assert-That ($day.bad -eq 0 -and $day.unsupported -eq 0 -and $null -eq $day.partial) "the gap vector read with bad $($day.bad), unsupported $($day.unsupported), partial '$($day.partial)', expected none"
            Assert-That ($day.events.Count -eq $lineCount) "Read-PqDay returned $($day.events.Count) of the $lineCount lines of the gap vector"
            $gapsList = @($day.gaps)
            $show = { param($g) (@($g.Keys | ForEach-Object { "$_=$(@($g[$_]) -join '+')" }) -join ' ') }
            Assert-That ($gapsList.Count -eq $expect.Count) "Read-PqDay reported $($gapsList.Count) gaps [$(@($gapsList | ForEach-Object { & $show $_ }) -join '; ')], the expect file $($expect.Count)"
            for ($i = 0; $i -lt $expect.Count; $i++) {
                $e = $expect[$i]
                $g = $gapsList[$i]
                $names = @($e.PSObject.Properties | ForEach-Object { $_.Name })
                Assert-That ($names.Count -gt 0) "gap expect record $($i + 1) has no key"
                foreach ($n in $names) {
                    Assert-That ($g.Contains($n)) "gap $($i + 1): Read-PqDay's record has no key '$n' (it has $(@($g.Keys) -join ' '))"
                    $wantValue = @($e.$n) -join ','
                    $gotValue = @($g[$n]) -join ','
                    Assert-That ($gotValue -ceq $wantValue) "gap $($i + 1): $n is [$gotValue], the expect file says [$wantValue]"
                }
            }
            $explained = @($gapsList | Where-Object { $_.explained -eq $true }).Count
            Assert-That ($explained -eq 1 -and $gapsList.Count - $explained -eq 1) "the gap vector has $explained explained and $($gapsList.Count - $explained) unexplained gaps, expected one of each"
        }
    }

    if ($run -eq 0) { throw 'No test cases executed' }
}
catch {
    if ($_.Exception.Message -eq 'No test cases executed') { 'No test cases executed' }
    else { "FAIL setup - $($_.Exception.Message)" }
    $setupFailed = $true
}
finally {
    $env:SZA_PORTFOLIO_ROOT = $savedPortfolioRoot
    $env:USERPROFILE = $savedUserProfile
    if ($scratch -and -not $KeepScratch -and (Test-Path -LiteralPath $scratch)) {
        Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($setupFailed) { "portfolio-events-tests: COULD NOT VERIFY (run=$run skipped=$skipped gaps=$gaps)"; exit 2 }
if ($failed -gt 0) { "portfolio-events-tests: FAIL (run=$run skipped=$skipped gaps=$gaps)"; exit 1 }
"portfolio-events-tests: PASS (run=$run skipped=$skipped gaps=$gaps)"
exit 0
