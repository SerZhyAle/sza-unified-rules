# The ledger watch of the portfolio: what a repository's ticket ledger holds, what changed between two looks at it,
# and who moved a ticket (TASK-FLOW rules 3 and 59, the companion EVENTS.md 3.5 and 3.9; S0015 R43).
#
# Dot-source this file; it defines functions, sets no preference and prints nothing: every function returns its
# value. It keeps no state. It reads repositories, never the portfolio root, so it does not load paths.ps1. It does
# loads tools/harness/_profile.ps1 in an isolated module for its defaults only: that script caches one project root
# and one merged profile, and the dispatcher serves many repositories. No project is resolved in that module;
# profiles are read directly below, without duplicating defaults or changing the caller's profile state.
#
#   Get-PqRepoPaths -RepoPath <dir>
#       -> [pscustomobject] Root, EnvPrefix, Ledger, Archive, Queue, Ready, Done, LeasesDir, RunsDir, SpecsDir,
#          TempDir, CommandsDir. Each path is the profile's paths.<key> (journal, journalArchive, releaseQueue,
#          releaseReady, releaseQueueDone, leasesDir, queueRunsDir, specsDir, tempDir, commandsDir) over the shipped
#          default, resolved as Get-SzaPath resolves it: a relative value joined onto Root with the OS separator, an
#          absolute one as given. LeasesDir follows Get-LeaseStoreDir of batch/run-spec-queue.ps1: when the variable
#          <envPrefix>_TICKET_LEASE_ROOT is set it replaces Root as the base of the relative leasesDir. Profile keys
#          are matched case-insensitively, as _profile.ps1 merges them. A missing directory throws
#          'RepoPathMissing: <path>'; a profile that does not parse, is not a JSON object, has a paths that is not an
#          object (an array included), a paths.<key> or an envPrefix that is an array or an object, or an empty
#          paths.<key> throws 'ProfileUnreadable: <profile path> - <why>'. Creates nothing.
#   Get-PqLedgerSnapshot -RepoPath <dir> [-Key <registry key>] [-At <DateTimeOffset>] [-Paths <Get-PqRepoPaths>]
#       -> [pscustomobject] repo (the key, $null without one), root, at (UTC; the system clock without -At),
#          tickets (id -> [pscustomobject] id, status, updated, created, priority, file; ordinal ids, the ledger's
#          rows in file order, then the archive's), bad, ledgerRead, archiveRead, complete, errors.
#          The ledger and the archive are read line by line, never written and never locked (FileShare.ReadWrite and
#          Delete). A BOM and CR before LF are tolerated, a blank line is skipped. A line that is not a JSON object
#          with a non-empty string id and status counts in bad (a half-written last line included; never thrown;
#          an array is never its element). An updated, created or file that is no scalar reads as $null; a priority
#          that is an array or an object is kept as its compact JSON text, so an unchanged row compares equal.
#          An archive row reads status Archived. A duplicate id keeps the first row (the ledger's over the
#          archive's) and counts in bad. ledgerRead / archiveRead: the file existed and was read. An absent file is
#          an empty one. A file that exists but cannot be read makes complete false and adds a line to errors; such
#          a snapshot lacks rows, so a caller keeps its previous snapshot and looks again (Compare-PqLedgerSnapshot
#          reports nothing for it).
#   Compare-PqLedgerSnapshot -Previous <snapshot|$null> -Current <snapshot>
#       -> [pscustomobject] created (the current records of new ids), transitions (id, from, to, updatedFrom,
#          updatedTo, created, priority: the status differs), touched (id, status, updatedFrom, updatedTo,
#          priorityFrom, priorityTo: same status, a different updated, priority or file), removed (id, status,
#          updated of the previous record: the id is in neither file now), incomplete, baseline. Lists in the order
#          of the current snapshot (removed: of the previous one). incomplete: either snapshot is not complete, and
#          every list is empty. baseline: there is no previous observation (Previous $null or its at $null).
#   Resolve-PqActor -Transition <t> -Repo <key> -LivePasses <list> -RepoRunnerRows <list|$null>
#                   -WindowStart <DateTimeOffset> -WindowEnd <DateTimeOffset>
#       -> robot | repo-runner | manual | unknown (rule 59, below).
#   Get-PqLedgerEvents -Previous <snapshot|$null> -Current <snapshot> -LivePasses <list> -RepoRunnerRows <list|$null>
#                      [-EmitBaseline] [-EnteredAt <map>]
#       -> the events of one interval as [ordered] @{ Ev; Repo; Id; Pass; D } (callers wrap the call in @()); no
#          I/O. Per transition ticket.transition, d = from, to, actor, viaPass (the pass id when a live pass made it
#          robot, else null), inStatus (seconds spent in from, EVENTS.md 3.5: from the entry -EnteredAt holds for
#          the id to updatedTo; without an entry from updatedFrom, which a same-status edit moves, so a lower
#          bound), leadSoFar (seconds from the local
#          start of the created day to updatedTo, or to the observation when updatedTo does not parse); both whole
#          seconds, never negative, null when a time does not parse. The envelope pass is viaPass. Per created id
#          ticket.created, d = source, status, priority; source is robot when a live pass of the repository overlaps
#          the window, else owner (import and capture are not derivable from a ledger: Phase 08's). A baseline
#          interval yields created events only with -EmitBaseline (Phase 08 marks such imports). Then one
#          ingest.ledgerDiff, d = repo, transitions, created (the ticket.created events yielded), unattributed (the
#          unknown actors). An interval with neither a transition nor a created event yields nothing (rule 58: no
#          change, no line); a touched or removed ticket has no event of its own. Order: the transitions, the created
#          tickets, the diff.
#   Update-PqEnteredAt -EnteredAt <map> -Previous <snapshot|$null> -Current <snapshot>
#       the caller's map (a hashtable or an ordered dictionary, one per repository, id -> the local updated of the
#       entry into the current status), moved after Get-PqLedgerEvents of the same interval (below). Returns nothing.
#       The library keeps no state: the dispatcher holds the map.
#
# Actor attribution (TASK-FLOW rule 59). The window is [WindowStart, WindowEnd], the two observations that bracket
# the change, widened by one minute on each side (the resolution of the ledger's updated).
#   1. A live pass @{ repo; id; pass; startedAt; endedAt } (UTC DateTimeOffset, endedAt $null while it runs) of the
#      same repository and id whose [startedAt, endedAt] meets the window -> robot. robot wins over everything below.
#   2. RepoRunnerRows $null means the runner journal could not be read: unknown (the caller counts it).
#   3. A runner row (rule 23 plus instance, the <instance> of runs-<instance>.jsonl) covers the transition when it is
#      the same id and either finished inside the window, or made exactly this move (statusBefore = from,
#      statusAfter = to) and finished after the window opened (its row may land after the observation; a row of the
#      same move that finished before the window is an earlier run, because the observation at the window start
#      still saw from). A covering row of an instance matching ^pq\d+$ (case-sensitive) -> robot; of any other
#      instance -> repo-runner. A row whose finishedAt does not parse covers only by the move.
#   4. Otherwise manual.
# Times: updated (yyyy-MM-dd HH:mm), created (yyyy-MM-dd) and finishedAt (yyyy-MM-ddTHH:mm:ss) are LOCAL wall-clock
# times; they are parsed with DateTimeStyles.AssumeLocal in this process's time zone and converted to UTC. DST limit:
# a local time that is ambiguous (the hour repeated when clocks go back) or does not exist (the hour skipped when they
# go forward) is resolved by .NET's own rule and not corrected, so an attribution or a duration across a DST change
# can be off by that hour.

# ---- the shipped defaults, read without resolving or caching a project ----

$script:PqRepoDefaults = New-Module -ArgumentList (Join-Path $PSScriptRoot '..\..\_profile.ps1') -ReturnResult -ScriptBlock {
    param($ProfileScript)
    . $ProfileScript
    $script:SzaProfileDefaults
}

$script:PqRepoPathMap = [ordered]@{
    Ledger      = 'journal'
    Archive     = 'journalArchive'
    Queue       = 'releaseQueue'
    Ready       = 'releaseReady'
    Done        = 'releaseQueueDone'
    LeasesDir   = 'leasesDir'
    RunsDir     = 'queueRunsDir'
    SpecsDir    = 'specsDir'
    TempDir     = 'tempDir'
    CommandsDir = 'commandsDir'
}

# ---- helpers ----

# A member of a dictionary or an object by name (PowerShell's case-insensitive lookup), $null when absent; safe
# under Set-StrictMode. The value comes back as it is: the comma keeps PowerShell from unrolling an array (a
# one-element array to its element, an empty one to $null).
function Get-PqLwField($Object, [string]$Name) {
    if ($null -eq $Object) { return $null }
    if ($Object -is [Collections.IDictionary]) {
        if ($Object.Contains($Name)) { return , $Object[$Name] }
        return $null
    }
    $p = $Object.PSObject.Properties[$Name]
    if ($null -eq $p) { return $null }
    return , $p.Value
}

# A value that is no scalar: an array (or any list), a dictionary or a parsed JSON object.
function Test-PqLwComposite($Value) {
    return ($Value -is [array] -or $Value -is [Collections.IList] -or $Value -is [Collections.IDictionary] -or
        $Value -is [Management.Automation.PSCustomObject])
}

# The text of a scalar member, $null when it is absent or not a scalar ([string] of an array would join it).
function Get-PqLwText($Object, [string]$Name) {
    $v = Get-PqLwField $Object $Name
    if ($null -eq $v -or (Test-PqLwComposite $v)) { return $null }
    return [string]$v
}

function Test-PqLwHasField($Object, [string]$Name) {
    if ($null -eq $Object) { return $false }
    if ($Object -is [Collections.IDictionary]) { return $Object.Contains($Name) }
    return ($null -ne $Object.PSObject.Properties[$Name])
}

# A path value the way Get-SzaPath resolves it.
function Resolve-PqRepoPathValue([string]$Base, [string]$Value) {
    if ([IO.Path]::IsPathRooted($Value)) { return $Value }
    return (Join-Path $Base $Value).Replace('/', [IO.Path]::DirectorySeparatorChar)
}

# A local wall-clock time of the ledger or a runner row as a UTC DateTimeOffset, $null when it does not parse.
function ConvertFrom-PqLocalTime($Value) {
    if ($null -eq $Value) { return $null }
    if ($Value -is [DateTimeOffset]) { return $Value.ToUniversalTime() }
    if ($Value -is [DateTime]) {
        $dt = $Value
        if ($dt.Kind -eq [DateTimeKind]::Unspecified) { $dt = [DateTime]::SpecifyKind($dt, [DateTimeKind]::Local) }
        return ([DateTimeOffset]$dt).ToUniversalTime()
    }
    if (Test-PqLwComposite $Value) { return $null }
    $text = ([string]$Value).Trim()
    if ($text.Length -eq 0) { return $null }
    $inv = [Globalization.CultureInfo]::InvariantCulture
    $local = [string[]]@('yyyy-MM-dd HH:mm', "yyyy-MM-dd'T'HH:mm:ss", 'yyyy-MM-dd HH:mm:ss', "yyyy-MM-dd'T'HH:mm", 'yyyy-MM-dd',
        "yyyy-MM-dd'T'HH:mm:ss.FFFFFFF")
    $dt = [DateTime]::MinValue
    if ([DateTime]::TryParseExact($text, $local, $inv, [Globalization.DateTimeStyles]::AssumeLocal, [ref]$dt)) {
        return ([DateTimeOffset]$dt).ToUniversalTime()
    }
    # A value that names its own offset (Z or +hh:mm) is taken as it says.
    $dto = [DateTimeOffset]::MinValue
    $zoned = [string[]]@("yyyy-MM-dd'T'HH:mm:ssK", "yyyy-MM-dd'T'HH:mm:ss.FFFFFFFK")
    if ([DateTimeOffset]::TryParseExact($text, $zoned, $inv, [Globalization.DateTimeStyles]::None, [ref]$dto)) {
        return $dto.ToUniversalTime()
    }
    return $null
}

# An instant of a live pass (UTC DateTimeOffset, a DateTime or an ISO string), $null when absent or unparsable.
function ConvertTo-PqInstant($Value) {
    if ($null -eq $Value) { return $null }
    if ($Value -is [DateTimeOffset]) { return $Value.ToUniversalTime() }
    try { return ([DateTimeOffset]$Value).ToUniversalTime() } catch { return $null }
}

# Whole seconds from one instant to another, never negative; $null when either is $null.
function Get-PqSeconds($From, $To) {
    if ($null -eq $From -or $null -eq $To) { return $null }
    return [long][Math]::Max(0, [Math]::Floor(($To - $From).TotalSeconds))
}

# ---- repository paths ----

function Get-PqRepoPaths {
    param([string]$RepoPath)
    if ([string]::IsNullOrWhiteSpace($RepoPath) -or -not (Test-Path -LiteralPath $RepoPath -PathType Container)) {
        throw "RepoPathMissing: $RepoPath"
    }
    $root = (Resolve-Path -LiteralPath $RepoPath).Path
    $trimmed = $root.TrimEnd([char[]]@('\', '/'))
    if ($trimmed.Length -gt 0 -and $trimmed -notmatch '^[A-Za-z]:$') { $root = $trimmed }
    $profileFile = Join-Path $root '.sza-profile.json'
    $profile_ = $null
    if (Test-Path -LiteralPath $profileFile -PathType Leaf) {
        try {
            $text = [IO.File]::ReadAllText($profileFile, [Text.Encoding]::UTF8)
            $profile_ = ConvertFrom-Json -InputObject $text -DateKind String -NoEnumerate
        }
        catch { throw "ProfileUnreadable: $profileFile - $($_.Exception.Message)" }
        if ($profile_ -isnot [Management.Automation.PSCustomObject]) { throw "ProfileUnreadable: $profileFile - not a JSON object" }
    }
    $paths = Get-PqLwField $profile_ 'paths'
    if ($null -ne $paths -and $paths -isnot [Management.Automation.PSCustomObject]) { throw "ProfileUnreadable: $profileFile - paths is not an object" }
    $prefix = $script:PqRepoDefaults.envPrefix
    if (Test-PqLwHasField $profile_ 'envPrefix') {
        if (Test-PqLwComposite (Get-PqLwField $profile_ 'envPrefix')) { throw "ProfileUnreadable: $profileFile - envPrefix is not a string" }
        $prefix = [string](Get-PqLwField $profile_ 'envPrefix')
    }
    $values = [ordered]@{}
    foreach ($prop in $script:PqRepoPathMap.Keys) {
        $key = $script:PqRepoPathMap[$prop]
        $value = $script:PqRepoDefaults.paths[$key]
        if (Test-PqLwHasField $paths $key) {
            if (Test-PqLwComposite (Get-PqLwField $paths $key)) { throw "ProfileUnreadable: $profileFile - paths.$key is not a string" }
            $value = [string](Get-PqLwField $paths $key)
            if ([string]::IsNullOrWhiteSpace($value)) { throw "ProfileUnreadable: $profileFile - paths.$key is empty" }
        }
        $values[$prop] = $value
    }
    $result = [ordered]@{ Root = $root; EnvPrefix = $prefix }
    foreach ($prop in $values.Keys) { $result[$prop] = Resolve-PqRepoPathValue $root $values[$prop] }
    # The lease store of Get-LeaseStoreDir (batch/run-spec-queue.ps1) and locks/ticket-lease.ps1: the override
    # replaces the repository root as the base of the relative leasesDir.
    $leaseRoot = [Environment]::GetEnvironmentVariable("${prefix}_TICKET_LEASE_ROOT")
    if (-not [string]::IsNullOrWhiteSpace($leaseRoot) -and -not [IO.Path]::IsPathRooted($values['LeasesDir'])) {
        $result['LeasesDir'] = Resolve-PqRepoPathValue $leaseRoot $values['LeasesDir']
    }
    return [pscustomobject]$result
}

# ---- the snapshot ----

function Read-PqLedgerFile($Snap, [string]$Path, [bool]$IsArchive) {
    if (-not [IO.File]::Exists($Path)) { return }
    $bytes = $null
    try {
        $fs = [IO.FileStream]::new($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
        try {
            $ms = [IO.MemoryStream]::new()
            $fs.CopyTo($ms)
            $bytes = $ms.ToArray()
        }
        finally { $fs.Dispose() }
    }
    catch {
        $Snap.complete = $false
        $Snap.errors.Add("$Path - $($_.Exception.Message)")
        return
    }
    if ($IsArchive) { $Snap.archiveRead = $true } else { $Snap.ledgerRead = $true }
    $text = [Text.UTF8Encoding]::new($false).GetString($bytes)
    if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) { $text = $text.Substring(1) }
    foreach ($raw in $text.Split("`n")) {
        $line = $raw.TrimEnd("`r")
        if ($line.Trim().Length -eq 0) { continue }
        $row = $null
        try { $row = ConvertFrom-Json -InputObject $line -DateKind String -NoEnumerate }
        catch { $Snap.bad++; continue }
        if ($row -isnot [Management.Automation.PSCustomObject]) { $Snap.bad++; continue }
        $id = Get-PqLwField $row 'id'
        $status = Get-PqLwField $row 'status'
        if ($id -isnot [string] -or $id.Length -eq 0 -or $status -isnot [string] -or $status.Length -eq 0) { $Snap.bad++; continue }
        if ($Snap.tickets.Contains($id)) { $Snap.bad++; continue }
        # A priority that is an array or an object is kept as its compact JSON, so two looks at an unchanged row
        # compare equal (a reference compare would make it touched every time); ranking judges such a value, the
        # reader only keeps it. updated, created and file that are no scalar read as $null.
        $priority = Get-PqLwField $row 'priority'
        if (Test-PqLwComposite $priority) { $priority = ConvertTo-Json -InputObject $priority -Compress -Depth 20 -WarningAction Ignore }
        $Snap.tickets[$id] = [pscustomobject][ordered]@{
            id       = $id
            status   = $(if ($IsArchive) { 'Archived' } else { $status })
            updated  = Get-PqLwText $row 'updated'
            created  = Get-PqLwText $row 'created'
            priority = $priority
            file     = Get-PqLwText $row 'file'
        }
    }
}

function Get-PqLedgerSnapshot {
    param([string]$RepoPath, [string]$Key, $At, $Paths)
    if ($null -eq $Paths) { $Paths = Get-PqRepoPaths -RepoPath $RepoPath }
    $when = if ($null -eq $At) { [DateTimeOffset]::UtcNow } else { ([DateTimeOffset]$At).ToUniversalTime() }
    $snap = [pscustomobject][ordered]@{
        repo        = $(if ([string]::IsNullOrEmpty($Key)) { $null } else { $Key })
        root        = $Paths.Root
        at          = $when
        tickets     = [Collections.Specialized.OrderedDictionary]::new([StringComparer]::Ordinal)
        bad         = 0
        ledgerRead  = $false
        archiveRead = $false
        complete    = $true
        errors      = [Collections.Generic.List[string]]::new()
    }
    Read-PqLedgerFile $snap $Paths.Ledger $false
    Read-PqLedgerFile $snap $Paths.Archive $true
    return $snap
}

# ---- the diff ----

function Compare-PqLedgerSnapshot {
    param($Previous, $Current)
    $result = [pscustomobject][ordered]@{
        created     = [Collections.Generic.List[object]]::new()
        transitions = [Collections.Generic.List[object]]::new()
        touched     = [Collections.Generic.List[object]]::new()
        removed     = [Collections.Generic.List[object]]::new()
        incomplete  = $false
        baseline    = ($null -eq $Previous -or $null -eq (Get-PqLwField $Previous 'at'))
    }
    if ($null -eq $Current) { throw 'PqLedgerArgumentInvalid: -Current is required' }
    if ((Get-PqLwField $Current 'complete') -eq $false -or ($null -ne $Previous -and (Get-PqLwField $Previous 'complete') -eq $false)) {
        $result.incomplete = $true
        return $result
    }
    $now = Get-PqLwField $Current 'tickets'
    $before = Get-PqLwField $Previous 'tickets'
    if ($null -eq $before) { $before = @{} }
    foreach ($id in @($now.Keys)) {
        $c = $now[$id]
        if (-not $before.Contains($id)) { $result.created.Add($c); continue }
        $p = $before[$id]
        if ($p.status -cne $c.status) {
            $result.transitions.Add([pscustomobject][ordered]@{
                    id = $id; from = $p.status; to = $c.status; updatedFrom = $p.updated; updatedTo = $c.updated
                    created = $c.created; priority = $c.priority
                })
        }
        elseif ($p.updated -cne $c.updated -or $p.priority -ne $c.priority -or $p.file -cne $c.file) {
            $result.touched.Add([pscustomobject][ordered]@{
                    id = $id; status = $c.status; updatedFrom = $p.updated; updatedTo = $c.updated; priorityFrom = $p.priority
                    priorityTo = $c.priority
                })
        }
    }
    foreach ($id in @($before.Keys)) {
        if (-not $now.Contains($id)) {
            $p = $before[$id]
            $result.removed.Add([pscustomobject][ordered]@{ id = $id; status = $p.status; updated = $p.updated })
        }
    }
    return $result
}

# ---- actor attribution (TASK-FLOW rule 59) ----

# The first live pass of the repository (and of the ticket, when -Id is given) whose interval meets [Start, End].
function Find-PqLivePass($LivePasses, [string]$Repo, [string]$Id, [DateTimeOffset]$Start, [DateTimeOffset]$End) {
    foreach ($p in @($LivePasses)) {
        if ($null -eq $p) { continue }
        if ([string](Get-PqLwText $p 'repo') -cne $Repo) { continue }
        if ($Id -and [string](Get-PqLwText $p 'id') -cne $Id) { continue }
        $s = ConvertTo-PqInstant (Get-PqLwField $p 'startedAt')
        if ($null -eq $s) { continue }
        $e = ConvertTo-PqInstant (Get-PqLwField $p 'endedAt')
        if ($s -le $End -and ($null -eq $e -or $e -ge $Start)) { return $p }
    }
    return $null
}

# robot / repo-runner / manual from the runner rows alone, with the instance that decided.
function Get-PqRowActor($Rows, [string]$Id, [string]$From, [string]$To, [DateTimeOffset]$Start, [DateTimeOffset]$End) {
    $runner = $null
    foreach ($r in @($Rows)) {
        if ($null -eq $r) { continue }
        # Scalars only: [string] of an array would join it (["S0001"] would read as S0001).
        if ([string](Get-PqLwText $r 'id') -cne $Id) { continue }
        $fin = ConvertFrom-PqLocalTime (Get-PqLwField $r 'finishedAt')
        $sameMove = ([string](Get-PqLwText $r 'statusBefore') -ceq $From) -and ([string](Get-PqLwText $r 'statusAfter') -ceq $To)
        $covers = if ($null -eq $fin) { $sameMove } else { ($fin -ge $Start) -and (($fin -le $End) -or $sameMove) }
        if (-not $covers) { continue }
        $instance = [string](Get-PqLwText $r 'instance')
        if ($instance -cmatch '^pq\d+$') { return @{ actor = 'robot'; instance = $instance } }
        if ($null -eq $runner) { $runner = $instance }
    }
    if ($null -ne $runner) { return @{ actor = 'repo-runner'; instance = $runner } }
    return @{ actor = 'manual'; instance = $null }
}

# The actor of one transition and its evidence: @{ actor; pass (the live pass id, robot only); instance }.
function Get-PqActorEvidence($Transition, [string]$Repo, $LivePasses, $RepoRunnerRows, $WindowStart, $WindowEnd) {
    $widen = [TimeSpan]::FromMinutes(1)
    $ws = ([DateTimeOffset]$WindowStart).ToUniversalTime() - $widen
    $we = ([DateTimeOffset]$WindowEnd).ToUniversalTime() + $widen
    $id = [string](Get-PqLwField $Transition 'id')
    $live = Find-PqLivePass $LivePasses $Repo $id $ws $we
    if ($null -eq $RepoRunnerRows) { $byRows = @{ actor = 'unknown'; instance = $null } }
    else { $byRows = Get-PqRowActor $RepoRunnerRows $id ([string](Get-PqLwField $Transition 'from')) ([string](Get-PqLwField $Transition 'to')) $ws $we }
    if ($null -ne $live) {
        $pass = Get-PqLwField $live 'pass'
        return @{ actor = 'robot'; pass = $(if ($null -eq $pass) { $null } else { [string]$pass }); instance = $null }
    }
    return @{ actor = $byRows.actor; pass = $null; instance = $byRows.instance }
}

function Resolve-PqActor {
    param($Transition, [string]$Repo, $LivePasses, $RepoRunnerRows, $WindowStart, $WindowEnd)
    return (Get-PqActorEvidence $Transition $Repo $LivePasses $RepoRunnerRows $WindowStart $WindowEnd).actor
}

# ---- the events of one interval ----

function Get-PqLedgerEvents {
    param($Previous, $Current, $LivePasses, $RepoRunnerRows, [switch]$EmitBaseline, $EnteredAt)
    $diff = Compare-PqLedgerSnapshot -Previous $Previous -Current $Current
    if ($diff.incomplete) { return }
    $repo = Get-PqLwField $Current 'repo'
    $end = ConvertTo-PqInstant (Get-PqLwField $Current 'at')
    $start = ConvertTo-PqInstant (Get-PqLwField $Previous 'at')
    if ($null -eq $start) { $start = $end }
    $events = [Collections.Generic.List[object]]::new()
    $unknown = 0
    foreach ($t in $diff.transitions) {
        $who = Get-PqActorEvidence $t $repo $LivePasses $RepoRunnerRows $start $end
        if ($who.actor -ceq 'unknown') { $unknown++ }
        # The entry into from as the caller observed it, else the updated of the previous look (a lower bound).
        $since = $t.updatedFrom
        if ($null -ne $EnteredAt -and $EnteredAt.Contains($t.id) -and $null -ne $EnteredAt[$t.id]) { $since = $EnteredAt[$t.id] }
        $from = ConvertFrom-PqLocalTime $since
        $to = ConvertFrom-PqLocalTime $t.updatedTo
        $createdAt = ConvertFrom-PqLocalTime $t.created
        $leadEnd = if ($null -ne $to) { $to } else { $end }
        $d = [ordered]@{
            from      = $t.from
            to        = $t.to
            actor     = $who.actor
            viaPass   = $who.pass
            inStatus  = Get-PqSeconds $from $to
            leadSoFar = Get-PqSeconds $createdAt $leadEnd
        }
        $events.Add([ordered]@{ Ev = 'ticket.transition'; Repo = $repo; Id = $t.id; Pass = $who.pass; D = $d })
    }
    $created = 0
    if (-not $diff.baseline -or $EmitBaseline) {
        $widen = [TimeSpan]::FromMinutes(1)
        $robot = $null -ne (Find-PqLivePass $LivePasses ([string]$repo) $null ($start - $widen) ($end + $widen))
        foreach ($c in $diff.created) {
            $d = [ordered]@{ source = $(if ($robot) { 'robot' } else { 'owner' }); status = $c.status; priority = $c.priority }
            $events.Add([ordered]@{ Ev = 'ticket.created'; Repo = $repo; Id = $c.id; Pass = $null; D = $d })
            $created++
        }
    }
    if ($diff.transitions.Count + $created -gt 0) {
        $d = [ordered]@{ repo = $repo; transitions = $diff.transitions.Count; created = $created; unattributed = $unknown }
        $events.Add([ordered]@{ Ev = 'ingest.ledgerDiff'; Repo = $repo; Id = $null; Pass = $null; D = $d })
    }
    return $events.ToArray()
}

# The caller's record of when each ticket entered its current status (one IDictionary per repository, id -> the
# local updated string of the entry), moved after Get-PqLedgerEvents of the same interval. A new id, a status
# change or a first look (-Previous $null) records the current updated; an unchanged status keeps the entry (a
# same-status edit moves updated, not the entry), or records the previous updated when the map lacks the id; an id
# gone from the snapshot leaves the map. An incomplete snapshot changes nothing. An entry first seen at a look is a
# lower bound of the true entry (the ticket may have been in that status before the dispatcher looked).
function Update-PqEnteredAt {
    param($EnteredAt, $Previous, $Current)
    if ($null -eq $EnteredAt -or $null -eq $Current) { return }
    if ((Get-PqLwField $Current 'complete') -eq $false -or ($null -ne $Previous -and (Get-PqLwField $Previous 'complete') -eq $false)) { return }
    $now = Get-PqLwField $Current 'tickets'
    $before = Get-PqLwField $Previous 'tickets'
    foreach ($id in @($now.Keys)) {
        $c = $now[$id]
        $p = $(if ($null -ne $before -and $before.Contains($id)) { $before[$id] } else { $null })
        if ($null -eq $p -or $p.status -cne $c.status) { $EnteredAt[$id] = $c.updated }
        elseif (-not $EnteredAt.Contains($id)) { $EnteredAt[$id] = $p.updated }
    }
    foreach ($id in @($EnteredAt.Keys)) { if (-not $now.Contains($id)) { $EnteredAt.Remove($id) } }
}
