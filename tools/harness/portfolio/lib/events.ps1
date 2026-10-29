# The event log of the portfolio (TASK-FLOW rules 53-59 and the companion EVENTS.md; S0015 R40-R42, R50).
#
# Dot-source this file; it defines functions, sets no preference and prints nothing: every function returns its
# value. State lives only in $script: variables named Pq*. A second dot-source in the same script scope keeps the
# state of the first (the open logs and the clock seam are not reset).
#
#   Set-PqClock -Now <scriptblock>  the clock seam: the scriptblock returns a [DateTimeOffset] (or a [DateTime]).
#   Reset-PqClock                   back to the system clock.
#   Get-PqNow                       the current instant, always UTC. Nothing else in this file reads the clock.
#   Get-PqEventNames                the event names of the catalog EVENTS.md, a sorted (ordinal) string array.
#   Open-PqLog -Writer <wr>         opens the writer's day file and returns its handle (below). Writer names:
#              [-Run <id>]          pq, w<n>, imp, an, cli; any other throws 'WriterNameInvalid: <name>'. Opening
#              [-Strict]            a writer that is open in this process returns its handle. The first handle
#                                   opened is the default of Write-PqEvent. The file is
#                                   log\events-<UTC date>.<token>.jsonl; the token is the writer name, and for
#                                   cli, imp and an '<wr>-<pid>' (rule 54: in the file name only, wr stays bare).
#                                   A file another writer holds gives a handle whose State is refused (below).
#   Write-PqEvent [-Log <h>] [-Writer <wr>] -Ev <name> [-Repo] [-Id] [-Pass] [-Worker <int>] [-Agent] [-Model]
#                 [-Cx] [-Run] [-D <hashtable>]
#                                   appends one envelope (rule 53) to the log named by -Log, else -Writer, else
#                                   the default; returns $true when written, $false when no such log is open or the
#                                   write failed (fail-open, below). Under -Strict a name that is not in the
#                                   catalog throws 'UnknownEventName: <name>' and consumes nothing. Without it a
#                                   malformed name (not dotted, empty or absent: what Test-PqEnvelope calls
#                                   ev-not-dotted) is never written: it is a lost event (fail-open, below, with err
#                                   'invalid event name: <name>'); a well-formed name the catalog does not know is
#                                   written as given and reported by nothing (log.error means a failed write, rule
#                                   55, and rule 57 forbids giving it another meaning; a reader finds such a name
#                                   with Get-PqEventNames). d and the string fields of the envelope are redacted
#                                   (below) before they are serialised. A simple function on purpose: an advanced
#                                   one cannot declare -Ev (the alias of -ErrorVariable). No parameter takes prompt
#                                   text (rule 56).
#   Close-PqLog [-Log <h>] [-Writer <wr>]
#                                   flushes and closes the handle (default: the default log) and moves the default
#                                   to the next open handle.
#   New-PqPollStats                 the counters of one hour of polls: Hour (UTC yyyy-MM-ddTHH of the first sample,
#                                   $null before it), Polls, Changes, Reranks, HeartbeatReranks, PickerCalls,
#                                   PickerMsSum, PickerMsMax, SkippedUnchanged.
#   Add-PqPollStat -Stats <s> -Log <h> [-Change] [-Rerank] [-HeartbeatRerank] [-SkippedUnchanged] [-PickerMs <double[]>]
#                                   counts one poll (each -PickerMs element is one picker call); a sample of another
#                                   UTC hour first flushes the counted hour. Returns nothing.
#   Write-PqPollSummary -Stats <s> -Log <h>
#                                   poll.summary for the counted hour (d: hour, polls, changes, reranks,
#                                   heartbeatReranks, pickerCalls, pickerMsAvg over the calls to one decimal,
#                                   pickerMsMax, skippedUnchanged; both ms 0 without a call), then resets; no poll
#                                   counted, no line. Returns $true when a line was written. Rule 58: an hour is one
#                                   line however many polls it had, and an hour with no poll has none.
#   Convert-PqRelativePath -RepoPath <dir> -Path <path>
#                                   a path inside the repository as a repository-relative path with forward slashes
#                                   ('.' for the repository itself; a relative -Path is taken from the repository);
#                                   any other path in full with the profile directory as ~ and forward slashes; a
#                                   path that cannot be resolved comes back with the profile replaced, never dropped.
#
# Fail-open (rule 55). Opening and writing never throw and never print. A day file that cannot be opened gives a
# handle whose State is degraded; a write that fails degrades the handle too. A write to a degraded handle first
# tries to open the file again; while that fails the event is lost: Dropped rises by one and Seq still advances by
# one (the lost event owns its number, so the gap marks the loss). The first write that gets through is preceded
# by log.error with d = { err = <the last failure, redacted and cut>, dropped = <events lost since the last good
# write> }, then Dropped is 0 again. A failed open with no event lost is still reported, with dropped 0. Reopening
# a partly lost file continues from the greater of the file's last seq and the handle's Seq; an open that fails
# still reads the file's last seq when it can, so the events lost before the first good open are numbered after
# the lines already in the file. A last seq that is not a positive integer within Int64 (a BigInteger, an array)
# is no seq: the scan goes on backwards. A scan that fails all the same opens the file with Seq unchanged and
# reports the failure by log.error. There is no retry inside one call: a failed write is a lost event.
#
# Rotation (rule 54). Every write compares the UTC date of Get-PqNow with the handle's Date. A later date closes
# the old file and moves the handle to the new day's (same token), and seq 1 of that file is held for log.rotate,
# d = { from = <the date of the last file opened>, to = <new date>, events = <the last seq of that file, lost ones
# included> }: the first line written there is log.rotate at seq 1, then the event. An open of the new file that
# fails loses events from seq 2 on, so the file reads 1 log.rotate, the gap, log.error with dropped equal to it,
# the event (rule 55: the line after a gap explains it). A loss of the old day (its tail, after its last line, or
# a day whose file never opened) is not carried into the new file's log.error, whose dropped counts only the gap
# of its own file: the tail of the last opened file is counted by log.rotate events, above that file's last seq;
# a day whose file never opened is reported by nothing (a gap of the catalog, S0015 Phase 01 Step Log, Review
# fixes). The failure text itself is still reported, with dropped 0. If the new day's file already holds lines,
# log.rotate follows them. An earlier date (a clock stepped back) keeps the open file and the event keeps its own
# ts. A day with no write makes no file. Only the UTC date is ever used.
#
# Redaction (rule 56), run on d of every event, recursively over dictionaries, objects and arrays: (1) the profile
# directory ($env:USERPROFILE, else the OS profile folder; either separator, any case, only where the next
# character cannot continue a file name) becomes ~ in every string value, of d and of the envelope (run, repo, id,
# pass, agent, model, cx); (2) the value of a key named err is then cut at 300 UTF-16 units, one unit earlier when
# the cut would split a surrogate pair; (3) a key whose name, lower-cased with - and _ removed, equals or ends with
# token, secret, password, passwd, apikey, privatekey, authorization, credential, credentials, cookie or bearer is
# dropped, at any depth, and its name (never its value) is listed in the array d.redacted. tokens does not end in
# token and survives. Only strings, booleans and numbers (the integer types, single, double, decimal) are kept as
# they are; DateTime and DateTimeOffset become UTC yyyy-MM-ddTHH:mm:ss.fffZ, an ErrorRecord or an Exception its
# message (as log.error reports a failure), any other object (an enum, a FileInfo, a type) its text, never its
# property graph; every string made so passes (1) and (2).
#   Read-PqDay -Path <file>         one event file -> @{ events; bad; unsupported; partial; gaps } (below).
#   Merge-PqDay -Root <root> -Date <yyyy-MM-dd>
#                                   every events-<date>.*.jsonl under <root>\log, read with Read-PqDay, events
#                                   ordered by ts, then wr, then seq (ordinal) -> the same shape plus files;
#                                   partial is then a list of @{ file; text } and every gap names its file.
#   Test-PqEnvelope -Line <string|object>
#                                   the rule codes a line violates, in this order; none means valid: not-json (also
#                                   JSON that is not an object), v-not-1, ts-format, seq-not-positive-int,
#                                   missing-key:<name> (envelope order), ev-not-dotted, d-not-object. Unknown
#                                   fields and unknown d keys never produce a code. Callers wrap it in @().
#
# One writer per file (rule 54). The writer holds its file with FileShare.Read, so a second writer of the same
# file, in another process, is refused: its handle's State is refused, every write returns $false, nothing is
# counted and the open is never retried (a double-started pq must not interleave with the first). Refused needs
# evidence of another writer: when the first open of a day file meets a sharing violation, a probe opens the file
# for reading with FileShare.Read; it fails only against a holder with write access (or one that keeps the file
# to itself), and only then is the handle refused. A probe that succeeds means only readers hold the file (one
# with FileShare.Read, as File.ReadAllText, an indexer or a scanner opens it): the handle is degraded and the next
# write tries again. A reopen of a day file this handle has already held (Owned) is never refused. Close-PqLog
# releases the file at once; the OS releases it when a process dies; either way the next opener continues from
# the file's last seq.
#
# A handle: Writer, Token (the file token), Path, Date (UTC yyyy-MM-dd), Seq (the last seq used, lost ones
# included), Dropped (events lost from the file of Date and not yet reported), State (open | degraded | refused |
# closed), Run, Strict, PendingLf (the file ended in a partial line: the next write starts with LF), Stream ($null
# while degraded), PendingError (the failure the next log.error reports, $null when none), PendingRotate (the d of
# a log.rotate not yet written, $null when none), RotateSeq (the seq held for that log.rotate, $null when none),
# Owned (this handle has held the file of Date open), Errors (failures since the open).
#
# Read-PqDay opens the file with FileShare.ReadWrite, so a live writer is never disturbed, and splits it on LF. A
# final segment without LF is held back as partial (its text, else $null): neither returned nor counted until it
# is complete. A complete line that is not a JSON object is bad; an object whose v is absent or not 1 is
# unsupported (rule 53: skipped and counted); a v1 object that violates another envelope rule is bad; every other
# line is returned as parsed by ConvertFrom-Json -DateKind String (ts stays a string, unknown fields kept).
# gaps: the seq of every line that carries a positive integer seq (returned, unsupported or bad: such a line was
# written, so its number was not lost) is walked in file order; each break is @{ wr; file; after; missing; count;
# explained }, a first seq above 1 is a break after 0, missing lists the lost numbers (at most 10000 of them,
# count is exact), and explained is true only when the line after the break is log.error whose d.dropped equals
# count (rule 55).

. (Join-Path $PSScriptRoot 'paths.ps1')

if ($null -eq (Get-Variable -Name PqLogs -Scope Script -ErrorAction Ignore)) { $script:PqLogs = [ordered]@{} }
if ($null -eq (Get-Variable -Name PqDefaultLog -Scope Script -ErrorAction Ignore)) { $script:PqDefaultLog = $null }
if ($null -eq (Get-Variable -Name PqClock -Scope Script -ErrorAction Ignore)) { $script:PqClock = $null }
if ($null -eq (Get-Variable -Name PqProfileRegexCache -Scope Script -ErrorAction Ignore)) { $script:PqProfileRegexCache = $null }
# The values redaction keeps as they are (rule 56): booleans and numbers. A constant, not state.
$script:PqPlainTypes = [Collections.Generic.HashSet[type]]::new([type[]]@([bool], [int], [long], [double], [decimal], [single],
        [sbyte], [byte], [int16], [uint16], [uint32], [uint64]))

# ---- the clock seam ----

function Set-PqClock([scriptblock]$Now) { $script:PqClock = $Now }

function Reset-PqClock { $script:PqClock = $null }

function Get-PqNow {
    if ($null -eq $script:PqClock) { return [DateTimeOffset]::UtcNow }
    $value = @(& $script:PqClock)
    return ([DateTimeOffset]$value[-1]).ToUniversalTime()
}

# The UTC date of an instant, yyyy-MM-dd: the only date the log knows (rule 54). Never the local date.
function Get-PqUtcDate([DateTimeOffset]$Now) {
    return $Now.UtcDateTime.ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
}

# ---- the event-name registry: every name of the catalog EVENTS.md (TASK-FLOW rule 57), 76 on 2026-10-27 ----

function Get-PqEventNames {
    $names = [string[]]@(
        'agent.fallback', 'agent.hold', 'agent.probe', 'agent.resume', 'agent.unproven',
        'analyze.run',
        'claim.lost', 'claim.ok', 'claim.try',
        'dispatch.noSlot', 'dispatch.pick', 'dispatch.skip',
        'finding.close', 'finding.escalate', 'finding.open',
        'improve.ticket',
        'inbox.add', 'inbox.clear',
        'ingest.ledgerDiff', 'ingest.repoRun', 'ingest.transcript',
        'intake.robotDraft',
        'lease.observed', 'lock.observed',
        'log.error', 'log.rotate',
        'owner.action',
        'pass.beat', 'pass.end', 'pass.firstOutput', 'pass.halt', 'pass.kill', 'pass.launch', 'pass.limit',
        'pass.stall', 'pass.timeout',
        'poll.change', 'poll.summary',
        'queue.edited', 'queue.row',
        'race.suspect',
        'rank.result',
        'registry.changed',
        'repo.disabled', 'repo.discovered', 'repo.enabled', 'repo.free', 'repo.notready', 'repo.occupied',
        'repo.ready', 'repo.scaffolded', 'repo.skipped',
        'res.sample',
        'resource.acquire', 'resource.release', 'resource.wait',
        'run.end', 'run.error', 'run.heartbeat', 'run.pause', 'run.resume', 'run.start', 'run.stop',
        'ticket.blocked', 'ticket.complexity', 'ticket.created', 'ticket.dropLifted', 'ticket.dropped',
        'ticket.thrash', 'ticket.transition', 'ticket.unblocked',
        'tripwire.check', 'tripwire.trip',
        'wait.enter', 'wait.exit',
        'xrepo.cycle', 'xrepo.resolve'
    )
    [Array]::Sort($names, [StringComparer]::Ordinal)
    return $names
}

function Test-PqEventName([string]$Name) {
    if ($null -eq (Get-Variable -Name PqEventNameSet -Scope Script -ErrorAction Ignore)) {
        $script:PqEventNameSet = [Collections.Generic.HashSet[string]]::new([string[]]@(Get-PqEventNames), [StringComparer]::Ordinal)
    }
    return $script:PqEventNameSet.Contains($Name)
}

# ---- the writer ----

function Resolve-PqLog($Log, [string]$Writer) {
    if ($null -ne $Log) { return $Log }
    if (-not [string]::IsNullOrEmpty($Writer)) { return $script:PqLogs[$Writer] }
    return $script:PqDefaultLog
}

function ConvertTo-PqNullable($Value) {
    if ($null -eq $Value) { return $null }
    $text = [string]$Value
    if ($text.Length -eq 0) { return $null }
    return $text
}

# An integer the log can use: int or long, or a BigInteger within Int64 (ConvertFrom-Json reads a number beyond
# Int64 as a BigInteger, which no [long] cast survives). One check for the writer, the validator and the gap walk.
function Test-PqInteger($Value) {
    if ($Value -is [int] -or $Value -is [long]) { return $true }
    if ($Value -is [System.Numerics.BigInteger]) { return ($Value -ge [long]::MinValue -and $Value -le [long]::MaxValue) }
    return $false
}

# A dotted event name (rule 53, the ev-not-dotted code of Test-PqEnvelope); the writer checks with the same test.
function Test-PqDottedName($Name) {
    return (($Name -is [string]) -and ($Name -cmatch '^[a-z][A-Za-z0-9]*(\.[a-z][A-Za-z0-9]*)+$'))
}

# A member of a parsed JSON object by its exact (ordinal) name, $null when absent. The value comes back as it is:
# the comma keeps PowerShell from unrolling an array (a one-element array to its element, an empty one to $null).
function Get-PqMember($Object, [string]$Name) {
    if ($null -eq $Object -or $Object -isnot [System.Management.Automation.PSCustomObject]) { return $null }
    $p = $Object.PSObject.Properties[$Name]
    if ($null -eq $p -or $p.Name -cne $Name) { return $null }
    return , $p.Value
}

# The positive integer seq of one line (bytes, UTF-8), 0 when the line carries none it can use. Never throws.
function Get-PqLineSeq([byte[]]$Buffer, [int]$Offset, [int]$Count) {
    if ($Count -le 0) { return 0 }
    try {
        $text = [Text.Encoding]::UTF8.GetString($Buffer, $Offset, $Count).TrimEnd([char]13)
        $o = ConvertFrom-Json -InputObject $text -DateKind String -NoEnumerate -ErrorAction Stop
        $seq = Get-PqMember $o 'seq'
        if ((Test-PqInteger $seq) -and $seq -gt 0) { return [long]$seq }
    }
    catch { }
    return 0
}

# Continuation on open (rule 55): the seq of the last complete line that carries one, read backwards from the end
# of the file (one block in the normal case, never the whole file unless no line has a seq), and whether the
# file ends without LF, so the next write starts on a new line and the partial line stays alone. A short-lived
# reader with FileShare.ReadWrite; the writer's own handle is opened after it.
function Get-PqFileTail([string]$Path) {
    $tail = @{ Seq = [long]0; NeedsLf = $false }
    if (-not [IO.File]::Exists($Path)) { return $tail }
    $fs = [IO.FileStream]::new($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    try {
        $pos = $fs.Length
        if ($pos -eq 0) { return $tail }
        $fs.Position = $pos - 1
        $tail.NeedsLf = ($fs.ReadByte() -ne 10)
        $carry = [byte[]]::new(0)
        $beforeAnyLf = $true    # the segment after the last LF of the file is never a complete line
        while ($true) {
            $size = [int][Math]::Min([long]4096, $pos)
            $start = $pos - $size
            $buf = [byte[]]::new($size + $carry.Length)
            $fs.Position = $start
            $read = 0
            while ($read -lt $size) {
                $n = $fs.Read($buf, $read, $size - $read)
                if ($n -le 0) { break }
                $read += $n
            }
            [Array]::Copy($carry, 0, $buf, $size, $carry.Length)
            $end = $buf.Length
            $i = $buf.Length - 1
            while ($i -ge 0) {
                $i = [Array]::LastIndexOf($buf, [byte]10, $i)
                if ($i -lt 0) { break }
                if (-not $beforeAnyLf) {
                    $seq = Get-PqLineSeq $buf ($i + 1) ($end - $i - 1)
                    if ($seq -gt 0) { $tail.Seq = $seq; return $tail }
                }
                $beforeAnyLf = $false
                $end = $i
                $i--
            }
            if ($start -eq 0) {
                if (-not $beforeAnyLf) {
                    $seq = Get-PqLineSeq $buf 0 $end
                    if ($seq -gt 0) { $tail.Seq = $seq }
                }
                return $tail
            }
            $carry = [byte[]]::new($end)
            [Array]::Copy($buf, 0, $carry, 0, $end)
            $pos = $start
        }
    }
    finally { $fs.Dispose() }
}

# ---- redaction (rule 56) ----

# The profile directory as a pattern: either separator between its segments, any case, and only where the next
# character cannot continue a file name (C:\Users\a must not eat C:\Users\ab). Cached per profile value.
function Get-PqProfileRegex {
    $raw = $env:USERPROFILE
    $cache = $script:PqProfileRegexCache
    if ($null -ne $cache -and $cache.Raw -ceq $raw) { return $cache.Regex }
    $prof = $raw
    if ([string]::IsNullOrEmpty($prof)) { $prof = [Environment]::GetFolderPath('UserProfile') }
    $regex = $null
    if (-not [string]::IsNullOrEmpty($prof)) { $prof = $prof.TrimEnd('\', '/') }
    if (-not [string]::IsNullOrEmpty($prof)) {
        $pattern = (@($prof -split '[\\/]+' | ForEach-Object { [regex]::Escape($_) }) -join '[\\/]+') + '(?![\w.\-])'
        $regex = [regex]::new($pattern, [Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [Text.RegularExpressions.RegexOptions]::CultureInvariant)
    }
    $script:PqProfileRegexCache = @{ Raw = $raw; Regex = $regex }
    return $regex
}

function ConvertTo-PqTilde([string]$Text) {
    if ([string]::IsNullOrEmpty($Text)) { return $Text }
    $regex = Get-PqProfileRegex
    if ($null -eq $regex) { return $Text }
    return $regex.Replace($Text, '~')
}

# At most $Max UTF-16 units, one fewer when the last one kept would be the first half of a surrogate pair.
function ConvertTo-PqCut([string]$Text, [int]$Max) {
    if ($null -eq $Text -or $Text.Length -le $Max) { return $Text }
    $cut = $Max
    if ([char]::IsHighSurrogate($Text[$cut - 1])) { $cut-- }
    return $Text.Substring(0, $cut)
}

function Test-PqSecretKey([string]$Name) {
    $k = $Name.ToLowerInvariant().Replace('-', '').Replace('_', '')
    foreach ($suffix in 'token', 'secret', 'password', 'passwd', 'apikey', 'privatekey', 'authorization', 'credential', 'credentials', 'cookie', 'bearer') {
        if ($k.EndsWith($suffix, [StringComparison]::Ordinal)) { return $true }
    }
    return $false
}

# One value of d, redacted; $Redacted collects the names of the dropped keys. Strings pass the string rules;
# booleans and numbers come back unchanged; a date becomes its UTC text, an error its message; dictionaries come
# back as ordinal ordered dictionaries, PSCustomObjects as the same, other enumerables as arrays; anything else
# becomes its text (never its property graph, which ConvertTo-Json would walk: a FileInfo ran out of memory).
function ConvertTo-PqRedactedValue($Value, [string]$Key, $Redacted, [int]$Depth) {
    if ($null -eq $Value) { return $null }
    if ($Value -is [string]) {
        $text = ConvertTo-PqTilde $Value
        if ($Key -ceq 'err') { $text = ConvertTo-PqCut $text 300 }
        return $text
    }
    if ($Value -is [int] -or $Value -is [long] -or $Value -is [bool] -or $Value -is [double]) { return $Value }
    $text = $null
    if ($Value -is [ValueType]) {
        # The other numbers as they are; a date as its UTC text; any other value type (an enum, a char, a Guid, a
        # TimeSpan) as its text.
        if ($script:PqPlainTypes.Contains($Value.GetType())) { return $Value }
        if ($Value -is [DateTimeOffset]) {
            $text = $Value.UtcDateTime.ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'", [Globalization.CultureInfo]::InvariantCulture)
        }
        elseif ($Value -is [DateTime]) {
            $text = $Value.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'", [Globalization.CultureInfo]::InvariantCulture)
        }
        else { $text = [string]$Value }
    }
    elseif ($Value -is [System.Management.Automation.ErrorRecord]) { $text = Get-PqErrorText $Value }
    elseif ($Value -is [Exception]) { $text = Get-PqExceptionText $Value }
    elseif ($Depth -ge 16) { $text = [string]$Value }
    if ($null -ne $text) { return (ConvertTo-PqRedactedValue ([string]$text) $Key $Redacted $Depth) }
    $pairs = $null
    if ($Value -is [Collections.IDictionary]) {
        $pairs = @(foreach ($k in $Value.Keys) { , @([string]$k, $Value[$k]) })
    }
    elseif ($Value -is [System.Management.Automation.PSCustomObject]) {
        $pairs = @(foreach ($p in $Value.PSObject.Properties) { , @([string]$p.Name, $p.Value) })
    }
    if ($null -ne $pairs) {
        $out = [Collections.Specialized.OrderedDictionary]::new([StringComparer]::Ordinal)
        foreach ($pair in $pairs) {
            $name = $pair[0]
            if (Test-PqSecretKey $name) {
                if (-not $Redacted.Contains($name)) { $Redacted.Add($name) }
                continue
            }
            $out[$name] = ConvertTo-PqRedactedValue $pair[1] $name $Redacted ($Depth + 1)
        }
        return $out
    }
    if ($Value -is [Collections.IEnumerable]) {
        $items = [Collections.Generic.List[object]]::new()
        foreach ($x in $Value) { $items.Add((ConvertTo-PqRedactedValue $x $null $Redacted ($Depth + 1))) }
        return , $items.ToArray()
    }
    return (ConvertTo-PqRedactedValue ([string]$Value) $Key $Redacted $Depth)
}

# The d of an event: always a dictionary (a value that is not one is kept under 'value'), redacted, with
# d.redacted naming the dropped keys when there are any.
function ConvertTo-PqData($D) {
    $redacted = [Collections.Generic.List[string]]::new()
    $out = ConvertTo-PqRedactedValue $D $null $redacted 0
    if ($null -eq $out) { $out = [Collections.Specialized.OrderedDictionary]::new([StringComparer]::Ordinal) }
    elseif ($out -isnot [Collections.IDictionary]) {
        $wrap = [Collections.Specialized.OrderedDictionary]::new([StringComparer]::Ordinal)
        $wrap['value'] = $out
        $out = $wrap
    }
    if ($redacted.Count -gt 0) { $out['redacted'] = [string[]]$redacted.ToArray() }
    return $out
}

function Convert-PqRelativePath {
    param([string]$RepoPath, [string]$Path)
    if ([string]::IsNullOrEmpty($Path)) { return $Path }
    try {
        $base = [IO.Path]::GetFullPath($RepoPath)
        $full = [IO.Path]::GetFullPath($Path, $base)
        $rel = [IO.Path]::GetRelativePath($base, $full)
        $sep = [string][IO.Path]::DirectorySeparatorChar
        $outside = [IO.Path]::IsPathRooted($rel) -or $rel -eq '..' -or $rel.StartsWith('..' + $sep, [StringComparison]::Ordinal) -or
            $rel.StartsWith('../', [StringComparison]::Ordinal)
        if (-not $outside) { return $rel.Replace('\', '/') }
        return (ConvertTo-PqTilde $full).Replace('\', '/')
    }
    catch { return (ConvertTo-PqTilde $Path) }
}

# ---- fail-open (rule 55) ----

# The message of an exception, without the PowerShell method-call wrapper.
function Get-PqExceptionText($Exception) {
    $ex = $Exception
    if ($null -eq $ex) { return 'unknown failure' }
    while ($ex -is [System.Management.Automation.MethodInvocationException] -and $null -ne $ex.InnerException) { $ex = $ex.InnerException }
    $text = [string]$ex.Message
    if ([string]::IsNullOrWhiteSpace($text)) { $text = $ex.GetType().FullName }
    return $text
}

# The message of a failure (an ErrorRecord, as a catch block holds it in $_).
function Get-PqErrorText($ErrorRecord) { return (Get-PqExceptionText $ErrorRecord.Exception) }

function Set-PqFailure($h, [string]$Text) {
    if ($null -ne $h.Stream) { try { $h.Stream.Dispose() } catch { } }
    $h.Stream = $null
    $h.State = 'degraded'
    $h.PendingError = $Text
    $h.Errors++
}

# A sharing violation (ERROR_SHARING_VIOLATION 32, ERROR_LOCK_VIOLATION 33): another process holds the file.
function Test-PqSharingViolation($ErrorRecord) {
    $ex = $ErrorRecord.Exception
    while ($ex -is [System.Management.Automation.MethodInvocationException] -and $null -ne $ex.InnerException) { $ex = $ex.InnerException }
    if ($ex -isnot [IO.IOException] -or $ex -is [IO.FileNotFoundException] -or $ex -is [IO.DirectoryNotFoundException]) { return $false }
    $code = $ex.HResult -band 0xFFFF
    return ($code -eq 32 -or $code -eq 33)
}

# Another writer holds the file: a reader with FileShare.Read can open it only when no holder has write access and
# none keeps it to itself, so a sharing violation of this probe is the evidence. Readers alone let it open.
function Test-PqOtherWriter([string]$Path) {
    try {
        $probe = [IO.FileStream]::new($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        $probe.Dispose()
        return $false
    }
    catch { return (Test-PqSharingViolation $_) }
}

# The handle's Seq after the file's last seq is known: the greater of the two. A file that already holds lines
# takes back the seq held for log.rotate, which then follows those lines.
function Sync-PqTailSeq($h, [long]$TailSeq) {
    if ($TailSeq -gt 0 -and $null -ne $h.RotateSeq) { $h.RotateSeq = $null }
    if ($TailSeq -gt $h.Seq) { $h.Seq = $TailSeq }
}

# Opens (or reopens) the handle's day file for writing at its end; $true when open. One writer per file (rule 54):
# the writer handle is FileMode.OpenOrCreate, FileAccess.Write, FileShare.Read, so readers (FileShare.ReadWrite)
# never disturb it and a second writer, in this process or another, gets a sharing violation. That violation, at
# the first open of a day file and confirmed by Test-PqOtherWriter, makes the handle refused: it never writes and
# is never retried (a double-started pq must not interleave). A violation without that evidence (only readers
# hold the file), any violation on a reopen of a file this handle has held (Owned), and any other failure make it
# degraded (fail-open); a failed open still reads the file's last seq when it can, so the events it loses are
# numbered after the file's lines. The writer handle is taken first and the continuation scan after it, through a
# short-lived reader, so no other writer can append between the scan and the open; a scan that fails opens the
# file with Seq unchanged and the failure pending for log.error. The OS releases the handle of a process that
# dies, so the next opener continues from the file's last seq. On Windows only: .NET does not enforce FileShare
# between processes elsewhere.
function Open-PqStream($h) {
    try {
        $null = Initialize-PqRoot
        $h.Path = Get-PqPath -Kind events -Date $h.Date -Token $h.Token
        try {
            $stream = [IO.FileStream]::new($h.Path, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::Write, [IO.FileShare]::Read)
        }
        catch {
            if (-not $h.Owned -and (Test-PqSharingViolation $_) -and (Test-PqOtherWriter $h.Path)) {
                $h.Stream = $null
                $h.State = 'refused'
                return $false
            }
            throw
        }
        $tail = $null
        try { $tail = Get-PqFileTail $h.Path }
        catch {
            $h.PendingError = Get-PqErrorText $_
            $h.Errors++
            $tail = @{ Seq = [long]0; NeedsLf = ($stream.Length -gt 0) }
        }
        try { $null = $stream.Seek(0, [IO.SeekOrigin]::End) }
        catch { $stream.Dispose(); throw }
        $h.Stream = $stream
        $h.Owned = $true
        Sync-PqTailSeq $h $tail.Seq
        $h.PendingLf = $tail.NeedsLf
        $h.State = 'open'
        return $true
    }
    catch {
        Set-PqFailure $h (Get-PqErrorText $_)
        # Only the file of the handle's Date: a Path left from the day before (Get-PqPath failed) is not this file.
        if (-not [string]::IsNullOrEmpty($h.Path) -and [IO.Path]::GetFileName($h.Path) -ceq "events-$($h.Date).$($h.Token).jsonl") {
            try { Sync-PqTailSeq $h (Get-PqFileTail $h.Path).Seq } catch { }
        }
        return $false
    }
}

function Open-PqLog {
    param([string]$Writer, [string]$Run, [switch]$Strict)
    if ($Writer -cnotmatch '^(pq|w[1-9][0-9]*|imp|an|cli)$') { throw "WriterNameInvalid: $Writer" }
    if ($script:PqLogs.Contains($Writer)) { return $script:PqLogs[$Writer] }
    # cli, imp and an can run in several processes at once: the process id goes in the file token only (rule 54).
    $token = if ($Writer -cin 'cli', 'imp', 'an') { "$Writer-$PID" } else { $Writer }
    $handle = [pscustomobject]@{
        Writer       = $Writer
        Token        = $token
        Path         = $null
        Date         = Get-PqUtcDate (Get-PqNow)
        Seq          = [long]0
        Dropped      = 0
        State        = 'degraded'
        Run          = $(if ([string]::IsNullOrEmpty($Run)) { $null } else { $Run })
        Strict       = [bool]$Strict
        PendingLf    = $false
        Stream       = $null
        PendingError = $null
        PendingRotate = $null
        RotateSeq    = $null
        Owned        = $false
        Errors       = 0
    }
    $null = Open-PqStream $handle
    $script:PqLogs[$Writer] = $handle
    if ($null -eq $script:PqDefaultLog) { $script:PqDefaultLog = $handle }
    return $handle
}

# A string field of the envelope: $null when absent or empty, else its text with the profile as ~ (rule 56).
function ConvertTo-PqEnvelopeText($Value, $Regex) {
    if ($null -eq $Value) { return $null }
    $text = [string]$Value
    if ($text.Length -eq 0) { return $null }
    if ($null -eq $Regex) { return $text }
    return $Regex.Replace($text, '~')
}

# One envelope line (rule 53), without its LF. The fixed fields (v, ts, seq, wr, ev, worker) are the library's own.
function New-PqEnvelopeLine($h, [long]$Seq, [DateTimeOffset]$Now, [string]$Name, $Corr, $Data) {
    $regex = Get-PqProfileRegex
    $runId = ConvertTo-PqNullable $Corr['Run']
    if ($null -eq $runId) { $runId = $h.Run }
    $envelope = [ordered]@{
        v      = 1
        ts     = $Now.UtcDateTime.ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'", [Globalization.CultureInfo]::InvariantCulture)
        seq    = $Seq
        wr     = $h.Writer
        run    = ConvertTo-PqEnvelopeText $runId $regex
        ev     = $Name
        repo   = ConvertTo-PqEnvelopeText $Corr['Repo'] $regex
        id     = ConvertTo-PqEnvelopeText $Corr['Id'] $regex
        pass   = ConvertTo-PqEnvelopeText $Corr['Pass'] $regex
        worker = $(if ($null -eq (ConvertTo-PqNullable $Corr['Worker'])) { $null } else { [int]$Corr['Worker'] })
        agent  = ConvertTo-PqEnvelopeText $Corr['Agent'] $regex
        model  = ConvertTo-PqEnvelopeText $Corr['Model'] $regex
        cx     = ConvertTo-PqEnvelopeText $Corr['Cx'] $regex
        d      = ConvertTo-PqData $Data
    }
    return (ConvertTo-Json -InputObject $envelope -Compress -Depth 8 -WarningAction Ignore)
}

function Write-PqEvent {
    param($Log, $Writer, $Ev, $Repo, $Id, $Pass, $Worker, $Agent, $Model, $Cx, $Run, $D)
    $h = Resolve-PqLog $Log ([string]$Writer)
    if ($null -eq $h -or ($h.State -ne 'open' -and $h.State -ne 'degraded')) { return $false }
    $name = [string]$Ev
    if ($h.Strict -and -not (Test-PqEventName $name)) { throw "UnknownEventName: $name" }
    try {
        $now = Get-PqNow
        $date = Get-PqUtcDate $now
        if ([string]::CompareOrdinal($date, $h.Date) -gt 0) {
            # Rotation (rule 54): the first write of a later UTC day closes the old file and moves to the new day's,
            # whose seq 1 is held for log.rotate. A loss of the old day stays with the old day (log.rotate events
            # counts the tail of the last file opened); Dropped counts only the gaps of the new file. The failure
            # text stays pending and is reported with dropped 0. An earlier date (a clock stepped back) keeps the
            # open file.
            if ($null -ne $h.Stream) {
                try { $h.Stream.Flush() } catch { }
                try { $h.Stream.Dispose() } catch { }
            }
            $h.Stream = $null
            if ($null -eq $h.PendingRotate) { $h.PendingRotate = [ordered]@{ from = $h.Date; to = $date; events = $h.Seq } }
            else { $h.PendingRotate.to = $date }
            $h.Date = $date
            $h.Seq = [long]1
            $h.RotateSeq = [long]1
            $h.Dropped = 0
            $h.Owned = $false
            $h.PendingLf = $false
        }
        if (-not (Test-PqDottedName $name)) {
            # A name the validator rejects (ev-not-dotted) is never written: the event is lost and owns its number.
            $h.Seq++
            $h.Dropped++
            $h.PendingError = ConvertTo-PqCut (ConvertTo-PqTilde "invalid event name: $name") 300
            $h.Errors++
            return $false
        }
        if ($null -eq $h.Stream -and -not (Open-PqStream $h)) {
            # Another writer holds the file: refused, nothing written and nothing counted (the file is not ours).
            if ($h.State -ceq 'refused') { return $false }
            # Still unopenable: the event is lost and owns its number.
            $h.Seq++
            $h.Dropped++
            return $false
        }
        $none = @{}
        $records = [Collections.Generic.List[object]]::new()
        if ($null -ne $h.PendingRotate) {
            $records.Add(@{ Name = 'log.rotate'; Corr = $none; Data = $h.PendingRotate; Held = ($null -ne $h.RotateSeq) })
        }
        if ($null -ne $h.PendingError) {
            $records.Add(@{ Name = 'log.error'; Corr = $none; Data = [ordered]@{ err = $h.PendingError; dropped = $h.Dropped }; Held = $false })
        }
        $corr = @{ Repo = $Repo; Id = $Id; Pass = $Pass; Worker = $Worker; Agent = $Agent; Model = $Model; Cx = $Cx; Run = $Run }
        $records.Add(@{ Name = $name; Corr = $corr; Data = $D; Held = $false })
        $text = [Text.StringBuilder]::new()
        if ($h.PendingLf) { $null = $text.Append("`n") }
        # The held log.rotate takes the seq kept for it (1); every other record the next after the handle's Seq, so
        # the events lost while the new file could not be opened leave their gap between log.rotate and log.error.
        $seq = $h.Seq
        $numbered = 0
        foreach ($r in $records) {
            if ($r.Held) { $n = [long]$h.RotateSeq }
            else { $seq++; $numbered++; $n = $seq }
            $null = $text.Append((New-PqEnvelopeLine $h $n $now $r.Name $r.Corr $r.Data)).Append("`n")
        }
    }
    catch {
        # The event could not even be built: lost, numbered, reported by the next write.
        $h.Seq++
        $h.Dropped++
        $h.PendingError = Get-PqErrorText $_
        $h.Errors++
        return $false
    }
    $bytes = [Text.Encoding]::UTF8.GetBytes($text.ToString())
    try {
        # One write of every line of this call, flushed: a crash leaves at most one partial line.
        $h.Stream.Write($bytes, 0, $bytes.Length)
        $h.Stream.Flush()
    }
    catch {
        # Every numbered record is lost and owns its number; a held log.rotate stays pending with its seq.
        $h.Seq = $seq
        $h.Dropped += $numbered
        Set-PqFailure $h (Get-PqErrorText $_)
        return $false
    }
    $h.Seq = $seq
    $h.Dropped = 0
    $h.PendingError = $null
    $h.PendingRotate = $null
    $h.RotateSeq = $null
    $h.PendingLf = $false
    return $true
}

function Close-PqLog {
    param($Log, [string]$Writer)
    $h = Resolve-PqLog $Log $Writer
    if ($null -eq $h) { return }
    if ($null -ne $h.Stream) {
        try { $h.Stream.Flush() } catch { }
        try { $h.Stream.Dispose() } catch { }
    }
    $h.Stream = $null
    $h.State = 'closed'
    if ($script:PqLogs.Contains($h.Writer) -and [object]::ReferenceEquals($script:PqLogs[$h.Writer], $h)) {
        $script:PqLogs.Remove($h.Writer)
    }
    if ([object]::ReferenceEquals($script:PqDefaultLog, $h)) {
        $script:PqDefaultLog = $null
        foreach ($next in $script:PqLogs.Values) { $script:PqDefaultLog = $next; break }
    }
}

# ---- the poll aggregator (rule 58, S0015 R50): one poll.summary per UTC hour, never one line per poll ----

function New-PqPollStats {
    return [pscustomobject]@{
        Hour             = $null
        Polls            = 0
        Changes          = 0
        Reranks          = 0
        HeartbeatReranks = 0
        PickerCalls      = 0
        PickerMsSum      = [double]0
        PickerMsMax      = [double]0
        SkippedUnchanged = 0
    }
}

function Reset-PqPollStats($Stats) {
    $Stats.Hour = $null
    $Stats.Polls = 0
    $Stats.Changes = 0
    $Stats.Reranks = 0
    $Stats.HeartbeatReranks = 0
    $Stats.PickerCalls = 0
    $Stats.PickerMsSum = [double]0
    $Stats.PickerMsMax = [double]0
    $Stats.SkippedUnchanged = 0
}

# One poll. A sample of another UTC hour than the counted one first flushes that hour's summary. Returns nothing.
function Add-PqPollStat {
    param($Stats, $Log, [switch]$Change, [switch]$Rerank, [switch]$HeartbeatRerank, [switch]$SkippedUnchanged, [double[]]$PickerMs)
    $hour = (Get-PqNow).UtcDateTime.ToString("yyyy-MM-dd'T'HH", [Globalization.CultureInfo]::InvariantCulture)
    if ($null -ne $Stats.Hour -and $Stats.Hour -cne $hour -and $Stats.Polls -gt 0) {
        $null = Write-PqPollSummary -Stats $Stats -Log $Log
    }
    $Stats.Hour = $hour
    $Stats.Polls++
    if ($Change) { $Stats.Changes++ }
    if ($Rerank) { $Stats.Reranks++ }
    if ($HeartbeatRerank) { $Stats.HeartbeatReranks++ }
    if ($SkippedUnchanged) { $Stats.SkippedUnchanged++ }
    if ($null -ne $PickerMs) {
        foreach ($ms in $PickerMs) {
            $Stats.PickerCalls++
            $Stats.PickerMsSum += $ms
            if ($ms -gt $Stats.PickerMsMax) { $Stats.PickerMsMax = $ms }
        }
    }
}

# Emits poll.summary for the counted hour and resets the counters; nothing when no poll was counted. Returns
# $true when a summary was written, $false otherwise (the run's end calls it for the partial hour).
function Write-PqPollSummary {
    param($Stats, $Log)
    if ($null -eq $Stats -or $Stats.Polls -le 0) { return $false }
    $calls = $Stats.PickerCalls
    $d = [ordered]@{
        hour             = $Stats.Hour
        polls            = $Stats.Polls
        changes          = $Stats.Changes
        reranks          = $Stats.Reranks
        heartbeatReranks = $Stats.HeartbeatReranks
        pickerCalls      = $calls
        pickerMsAvg      = $(if ($calls -gt 0) { [Math]::Round($Stats.PickerMsSum / $calls, 1, [MidpointRounding]::AwayFromZero) } else { [double]0 })
        pickerMsMax      = $(if ($calls -gt 0) { $Stats.PickerMsMax } else { [double]0 })
        skippedUnchanged = $Stats.SkippedUnchanged
    }
    $written = Write-PqEvent -Log $Log -Ev 'poll.summary' -D $d
    Reset-PqPollStats $Stats
    return [bool]$written
}

# ---- the validator (rule 53; the vocabulary of the catalog vector portfolio-events-negative) ----

# @{ Object = <the parsed object, $null when the line is not a JSON object>; Codes = <string[]> }.
function Get-PqEnvelopeCheck($Line) {
    $o = $null
    if ($Line -is [System.Management.Automation.PSCustomObject]) { $o = $Line }
    else {
        $text = if ($null -eq $Line) { '' } elseif ($Line -is [string]) { $Line } else { ConvertTo-Json -InputObject $Line -Compress -Depth 16 -WarningAction Ignore }
        if (-not [string]::IsNullOrWhiteSpace($text)) {
            try { $o = ConvertFrom-Json -InputObject $text -DateKind String -NoEnumerate -ErrorAction Stop } catch { $o = $null }
        }
    }
    if ($o -isnot [System.Management.Automation.PSCustomObject]) { return @{ Object = $null; Codes = [string[]]@('not-json') } }
    $present = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($p in $o.PSObject.Properties) { $null = $present.Add($p.Name) }
    $codes = [Collections.Generic.List[string]]::new()
    if ($present.Contains('v')) {
        $v = Get-PqMember $o 'v'
        if (-not ((Test-PqInteger $v) -and $v -eq 1)) { $codes.Add('v-not-1') }
    }
    if ($present.Contains('ts')) {
        $ts = Get-PqMember $o 'ts'
        $parsed = [datetime]::MinValue
        $ok = ($ts -is [string]) -and ($ts -cmatch '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}Z$') -and
            [datetime]::TryParseExact($ts, "yyyy-MM-dd'T'HH:mm:ss.fff'Z'", [Globalization.CultureInfo]::InvariantCulture,
                [Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal, [ref]$parsed)
        if (-not $ok) { $codes.Add('ts-format') }
    }
    if ($present.Contains('seq')) {
        $seq = Get-PqMember $o 'seq'
        if (-not ((Test-PqInteger $seq) -and $seq -gt 0)) { $codes.Add('seq-not-positive-int') }
    }
    foreach ($k in 'v', 'ts', 'seq', 'wr', 'run', 'ev', 'repo', 'id', 'pass', 'worker', 'agent', 'model', 'cx', 'd') {
        if (-not $present.Contains($k)) { $codes.Add("missing-key:$k") }
    }
    if ($present.Contains('ev')) {
        if (-not (Test-PqDottedName (Get-PqMember $o 'ev'))) { $codes.Add('ev-not-dotted') }
    }
    if ($present.Contains('d')) {
        $d = $o.PSObject.Properties['d'].Value
        if ($d -isnot [System.Management.Automation.PSCustomObject]) { $codes.Add('d-not-object') }
    }
    return @{ Object = $o; Codes = $codes.ToArray() }
}

function Test-PqEnvelope {
    param($Line)
    return (Get-PqEnvelopeCheck $Line).Codes
}

# ---- the reader (rules 53-55) ----

function Read-PqDay {
    param([string]$Path)
    $result = @{ events = [object[]]@(); bad = 0; unsupported = 0; partial = $null; gaps = [object[]]@() }
    if (-not [IO.File]::Exists($Path)) { return $result }
    $fs = [IO.FileStream]::new($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete)
    try {
        $ms = [IO.MemoryStream]::new()
        $fs.CopyTo($ms)
        $bytes = $ms.ToArray()
    }
    finally { $fs.Dispose() }
    $offset = 0
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { $offset = 3 }
    $parts = [Text.Encoding]::UTF8.GetString($bytes, $offset, $bytes.Length - $offset).Split("`n")
    $last = $parts.Length - 1
    if ($parts[$last].Length -gt 0) { $result.partial = $parts[$last] }
    $file = [IO.Path]::GetFileName($Path)
    $events = [Collections.Generic.List[object]]::new()
    $walk = [Collections.Generic.List[object]]::new()
    for ($i = 0; $i -lt $last; $i++) {
        $check = Get-PqEnvelopeCheck ($parts[$i].TrimEnd([char]13))
        $o = $check.Object
        if ($null -eq $o) { $result.bad++; continue }
        $seq = Get-PqMember $o 'seq'
        if ((Test-PqInteger $seq) -and $seq -gt 0) { $walk.Add(@{ Seq = [long]$seq; Object = $o }) }
        $codes = $check.Codes
        if ($codes -ccontains 'missing-key:v' -or $codes -ccontains 'v-not-1') { $result.unsupported++; continue }
        if ($codes.Length -gt 0) { $result.bad++; continue }
        $events.Add($o)
    }
    $gaps = [Collections.Generic.List[object]]::new()
    $prev = [long]0
    foreach ($w in $walk) {
        if ($w.Seq -gt $prev + 1) {
            $count = $w.Seq - $prev - 1
            $take = [Math]::Min($count, [long]10000)
            $missing = [long[]]::new($take)
            for ($k = 0; $k -lt $take; $k++) { $missing[$k] = $prev + 1 + $k }
            $explained = $false
            $ev = Get-PqMember $w.Object 'ev'
            if ($ev -is [string] -and $ev -ceq 'log.error') {
                $dropped = Get-PqMember (Get-PqMember $w.Object 'd') 'dropped'
                $explained = (Test-PqInteger $dropped) -and $dropped -eq $count
            }
            $gaps.Add([ordered]@{ wr = (Get-PqMember $w.Object 'wr'); file = $file; after = $prev; missing = $missing; count = $count; explained = $explained })
        }
        if ($w.Seq -gt $prev) { $prev = $w.Seq }
    }
    $result.events = $events.ToArray()
    $result.gaps = $gaps.ToArray()
    return $result
}

function Merge-PqDay {
    param([string]$Root, [string]$Date)
    $parsed = [datetime]::MinValue
    if (-not $Date -or -not [datetime]::TryParseExact($Date, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::None, [ref]$parsed)) {
        throw "PqPathArgumentInvalid: -Date '$Date' is not yyyy-MM-dd"
    }
    $result = @{ events = [object[]]@(); bad = 0; unsupported = 0; partial = [object[]]@(); gaps = [object[]]@(); files = [string[]]@() }
    $logDir = Join-Path $Root 'log'
    if (-not [IO.Directory]::Exists($logDir)) { return $result }
    $pattern = '^events-' + [regex]::Escape($Date) + '\.[^.\\/]+\.jsonl$'
    $files = [string[]]@([IO.Directory]::GetFiles($logDir) | Where-Object { [IO.Path]::GetFileName($_) -cmatch $pattern })
    [Array]::Sort($files, [StringComparer]::Ordinal)
    $keys = [Collections.Generic.List[string]]::new()
    $items = [Collections.Generic.List[object]]::new()
    $partial = [Collections.Generic.List[object]]::new()
    $gaps = [Collections.Generic.List[object]]::new()
    foreach ($f in $files) {
        $name = [IO.Path]::GetFileName($f)
        $day = Read-PqDay -Path $f
        $result.bad += $day.bad
        $result.unsupported += $day.unsupported
        if ($null -ne $day.partial) { $partial.Add([ordered]@{ file = $name; text = $day.partial }) }
        foreach ($g in $day.gaps) { $gaps.Add($g) }
        $n = 0
        foreach ($e in $day.events) {
            # ts, then wr, then seq; the file name and the line order only make equal keys deterministic.
            $keys.Add(('{0}{1}{2}{1}{3:D20}{1}{4}{1}{5:D10}' -f $e.ts, [char]0, $e.wr, [long]$e.seq, $name, $n))
            $items.Add($e)
            $n++
        }
    }
    # Sort a permutation, not the objects: PowerShell binds the generic overload and would sort a converted copy
    # of an object[] items array, leaving the original in file order (probed on 7.6.9, 2026-10-27).
    $keyArray = $keys.ToArray()
    $order = [int[]]::new($keyArray.Length)
    for ($i = 0; $i -lt $order.Length; $i++) { $order[$i] = $i }
    [Array]::Sort($keyArray, $order, [StringComparer]::Ordinal)
    $sorted = [object[]]::new($order.Length)
    for ($i = 0; $i -lt $order.Length; $i++) { $sorted[$i] = $items[$order[$i]] }
    $result.events = $sorted
    $result.partial = $partial.ToArray()
    $result.gaps = $gaps.ToArray()
    $result.files = [string[]]@($files | ForEach-Object { [IO.Path]::GetFileName($_) })
    return $result
}
