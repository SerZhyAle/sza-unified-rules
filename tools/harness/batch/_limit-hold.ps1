# The usage limit as the queue runner sees it (S4265): the signal a child leaves behind, and the
# one shared hold every instance waits on.
#
# Dot-sourced, never invoked. Defines functions and two process-scope variables, nothing else.
#
# WHY THE SIGNAL IS A TRANSCRIPT RECORD AND NOT TEXT. When the account's usage limit is reached the
# CLI ends the child with a synthetic assistant record in the session transcript: apiError
# `usage_limit_reached`, error `rate_limit`, apiErrorStatus 429, and quotaLimits.resetsAt in unix
# seconds beside the limit's rateLimitType. The console text carries the same fact in prose ("You've
# hit your weekly limit - resets 2pm"), but a runner without -Quiet never holds that text, and prose
# is a worse thing to match than three named fields. The runner passes `--session-id <guid>` to every
# child, so the transcript is found by name and never by guessing the project directory.
#
# WHY THE HOLD IS A FILE. Parallel instances and the watchdog's restarts all hit the same account
# limit, and a restarted runner has no memory of the one that fell. One file under the run directory,
# read before every launch, is the only state they can all see. It needs no cleanup: it expires by
# its own timestamp, and it only ever moves forward.
#
# Compatible with PowerShell 7+, and safe to load under Set-StrictMode Latest.

. (Join-Path $PSScriptRoot '..\_profile.ps1')

$script:LimitHoldFileName = 'limit-hold.json'

# The newest hold this process knows that the file could not carry (a write that failed). Without
# it a runner that cannot write the file would also forget the limit, and launch straight into it.
$script:LimitHoldLocal = $null

# The largest value DateTimeOffset.FromUnixTimeSeconds accepts. A reset time past it is garbage and
# is dropped rather than thrown on, because a throw here would stop the wait that protects the queue.
$script:LimitMaxUnixSeconds = 253402300799

function Get-LimitPolicy {
    <#
    .SYNOPSIS
        The project's limit policy: the margin past the reset time, and the poll wait used when the
        limit carried no reset time. Both come from the profile, whose defaults the harness declares.
    #>
    # No fallback literals: the defaults are declared in _profile.ps1, and a key that is somehow
    # absent should say so (Get-SzaProfileValue throws) rather than be quietly replaced here.
    $margin = [int](Get-SzaProfileValue 'runner.limitResumeMarginSeconds')
    $poll = [int](Get-SzaProfileValue 'runner.limitPollMinutes')
    if ($margin -lt 0) { $margin = 0 }
    if ($poll -lt 1) { $poll = 1 }
    return [pscustomobject]@{ MarginSeconds = $margin; PollMinutes = $poll }
}

function Get-LimitHoldPath {
    <#
    .SYNOPSIS
        Where the hold lives: the run directory the journals are in, one file. Taking the repository
        root as an argument keeps the runner and the monitor on the same path whatever the process
        was started from.
    #>
    param([Parameter(Mandatory)][string] $RepoRoot)
    $runDir = Join-Path $RepoRoot (Get-SzaPath 'queueRunsDir' -Relative)
    return (Join-Path $runDir $script:LimitHoldFileName)
}

function ConvertTo-LimitOffset {
    # A timestamp in whatever shape ConvertFrom-Json left it: a DateTime for an ISO string, or the
    # string itself. $null for anything unreadable.
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [DateTimeOffset]) { return $Value }
    if ($Value -is [datetime]) {
        return [DateTimeOffset]::new($Value.ToUniversalTime(), [TimeSpan]::Zero)
    }
    $parsed = [DateTimeOffset]::MinValue
    $styles = [System.Globalization.DateTimeStyles]::AssumeUniversal
    if ([DateTimeOffset]::TryParse([string]$Value, [System.Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$parsed)) {
        return $parsed
    }
    return $null
}

function ConvertTo-LimitUnixSeconds {
    <#
    .SYNOPSIS
        A reset time as unix SECONDS, or $null. A value in milliseconds is brought down to seconds,
        and anything not positive, not numeric or past the representable range is no value at all:
        the wait has no cap, so a garbage number must never reach it.
    #>
    param($Value)
    if ($null -eq $Value) { return $null }
    $number = [int64]0
    if (-not [int64]::TryParse([string]$Value, [ref]$number)) { return $null }
    if ($number -gt 100000000000) { $number = [int64][Math]::Floor($number / 1000) }
    if ($number -le 0 -or $number -gt $script:LimitMaxUnixSeconds) { return $null }
    return $number
}

function Get-LimitJsonProperty {
    # One property of a parsed JSON object, $null when the object or the property is absent. Written
    # as a function so every reader below is safe under Set-StrictMode Latest.
    param($Object, [Parameter(Mandatory)][string] $Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

# ---------------------------------------------------------------------------------------------
# The signal
# ---------------------------------------------------------------------------------------------

function Find-ChildTranscript {
    <#
    .SYNOPSIS
        The transcript a child wrote under the session id it was launched with, or $null.
    .DESCRIPTION
        The CLI keeps transcripts at <config>/projects/<slug>/<session-id>.jsonl, where the slug is
        derived from the child's working directory by the CLI's own rule. That rule is not repeated
        here: every project directory is probed for the one file name the runner chose, which is
        exact and survives a change of the rule.
    #>
    param([Parameter(Mandatory)][string] $SessionId)
    $configDir = $env:CLAUDE_CONFIG_DIR
    if ([string]::IsNullOrWhiteSpace($configDir)) {
        $homeDir = if ($env:USERPROFILE) { $env:USERPROFILE } else { $env:HOME }
        if ([string]::IsNullOrWhiteSpace($homeDir)) { return $null }
        $configDir = Join-Path $homeDir '.claude'
    }
    $projects = Join-Path $configDir 'projects'
    if (-not (Test-Path -LiteralPath $projects -PathType Container)) { return $null }
    foreach ($dir in @(Get-ChildItem -LiteralPath $projects -Directory -ErrorAction SilentlyContinue)) {
        $candidate = Join-Path $dir.FullName ("{0}.jsonl" -f $SessionId)
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    return $null
}

function Read-TranscriptLastAssistant {
    <#
    .SYNOPSIS
        The last assistant record of a transcript, read from the tail of the file.
    .DESCRIPTION
        The file of a long run is tens of megabytes, so only a window at its end is read, and the
        window grows by a factor of four until a record is found or the whole file is covered.

        Two things are NOT assistant work and are skipped: records of a sidechain (a subagent's
        turns), and every non-assistant record (the transcript ends with `last-prompt` and
        `cost-state` lines, so "the last line" is never the answer).

        An assistant-looking line that does not parse is a record this reader cannot judge, and it
        returns $null rather than reaching past it to an older record: stepping over a half-written
        last record could resurrect a limit record the child had already moved on from.
    #>
    param([Parameter(Mandatory)][string] $Path)

    $stream = $null
    try {
        $stream = [System.IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite')
        $length = $stream.Length
        $window = [int64]262144
        while ($true) {
            $start = [Math]::Max([int64]0, $length - $window)
            [void]$stream.Seek($start, [System.IO.SeekOrigin]::Begin)
            $size = [int]($length - $start)
            $buffer = New-Object byte[] $size
            $read = 0
            while ($read -lt $size) {
                $n = $stream.Read($buffer, $read, $size - $read)
                if ($n -le 0) { break }
                $read += $n
            }
            $lines = @([System.Text.Encoding]::UTF8.GetString($buffer, 0, $read) -split "`r?`n")
            # A window that starts mid-file starts mid-line; that first line is never trusted.
            if ($start -gt 0 -and $lines.Count -gt 0) { $lines = @($lines | Select-Object -Skip 1) }

            for ($i = $lines.Count - 1; $i -ge 0; $i--) {
                $line = $lines[$i]
                if ($line -notmatch '"type"\s*:\s*"assistant"') { continue }
                $record = $null
                try { $record = $line | ConvertFrom-Json -ErrorAction Stop } catch { return $null }
                if ($null -eq $record) { return $null }
                if ([string](Get-LimitJsonProperty $record 'type') -ne 'assistant') { continue }
                if ([bool](Get-LimitJsonProperty $record 'isSidechain')) { continue }
                return $record
            }
            if ($start -eq 0) { return $null }
            $window = $window * 4
            # A record that does not fit in half a gigabyte is not one this reader will chase.
            if ($window -gt 536870912) { return $null }
        }
    } catch {
        return $null
    } finally {
        if ($null -ne $stream) { $stream.Dispose() }
    }
}

function Get-LimitSignal {
    <#
    .SYNOPSIS
        The limit a finished child ended on, or $null when it did not end on one.
    .DESCRIPTION
        With a transcript, the transcript decides and the log is never consulted: the last assistant
        record is a limit hit when its apiError is `usage_limit_reached`, or its error is
        `rate_limit` with apiErrorStatus 429. A limit record FOLLOWED by ordinary assistant work is a
        past event the child survived, so only the last record counts.

        Without a transcript, and only for a child that did not exit 0, the tail of the captured log
        is matched for `hit your .{1,40} limit`. The tail and the exit code are what keep a child
        that merely wrote ABOUT limits (this very mechanism's tickets) from being read as one.

        With neither, $null: the run stays whatever it was.
    .OUTPUTS
        Source ('transcript' or 'log'), ResetsAt (unix seconds or $null), RateLimitType.
    #>
    param(
        [string] $TranscriptPath = '',
        [string] $LogBody = '',
        $ExitCode = $null
    )

    if (-not [string]::IsNullOrWhiteSpace($TranscriptPath) -and (Test-Path -LiteralPath $TranscriptPath -PathType Leaf)) {
        $record = Read-TranscriptLastAssistant -Path $TranscriptPath
        if ($null -eq $record) { return $null }

        $apiError = [string](Get-LimitJsonProperty $record 'apiError')
        $error_ = [string](Get-LimitJsonProperty $record 'error')
        $status = [string](Get-LimitJsonProperty $record 'apiErrorStatus')
        $isLimit = ($apiError -eq 'usage_limit_reached') -or ($error_ -eq 'rate_limit' -and $status -eq '429')
        if (-not $isLimit) { return $null }

        # The same facts repeat under apiErrorParams.rate_limit_info, so either spelling is enough.
        $quota = Get-LimitJsonProperty $record 'quotaLimits'
        $info = Get-LimitJsonProperty (Get-LimitJsonProperty $record 'apiErrorParams') 'rate_limit_info'
        $resetsAt = ConvertTo-LimitUnixSeconds (Get-LimitJsonProperty $quota 'resetsAt')
        if ($null -eq $resetsAt) { $resetsAt = ConvertTo-LimitUnixSeconds (Get-LimitJsonProperty $info 'resetsAt') }
        $type = [string](Get-LimitJsonProperty $quota 'rateLimitType')
        if ([string]::IsNullOrWhiteSpace($type)) { $type = [string](Get-LimitJsonProperty $info 'rateLimitType') }
        if ([string]::IsNullOrWhiteSpace($type)) { $type = 'unknown' }
        return [pscustomobject]@{ Source = 'transcript'; ResetsAt = $resetsAt; RateLimitType = $type }
    }

    if (-not [string]::IsNullOrWhiteSpace($LogBody) -and ($null -eq $ExitCode -or [int64]$ExitCode -ne 0)) {
        $tail = if ($LogBody.Length -gt 4000) { $LogBody.Substring($LogBody.Length - 4000) } else { $LogBody }
        if ($tail -match 'hit your (.{1,40}?) limit') {
            return [pscustomobject]@{ Source = 'log'; ResetsAt = $null; RateLimitType = $Matches[1].Trim() }
        }
    }
    return $null
}

# ---------------------------------------------------------------------------------------------
# The hold
# ---------------------------------------------------------------------------------------------

function Read-LimitHold {
    <#
    .SYNOPSIS
        The hold record in the file, or $null when there is none or it cannot be read.
    .DESCRIPTION
        An unreadable file is no hold: a wait that could not be read must not become a wait that
        cannot end. The file is replaced atomically by its writer, so a reader sees the old record
        or the new one and never half of one.
    #>
    param([Parameter(Mandatory)][string] $Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    $data = $null
    try { $data = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop } catch { return $null }
    if ($null -eq $data) { return $null }

    $resetsAt = ConvertTo-LimitUnixSeconds (Get-LimitJsonProperty $data 'resetsAt')
    if ($null -eq $resetsAt) {
        # A hold written by hand may carry only the ISO form.
        $iso = ConvertTo-LimitOffset (Get-LimitJsonProperty $data 'resetsAtIso')
        if ($null -ne $iso) { $resetsAt = ConvertTo-LimitUnixSeconds $iso.ToUnixTimeSeconds() }
    }
    return [pscustomobject]@{
        ResetsAt      = $resetsAt
        RateLimitType = [string](Get-LimitJsonProperty $data 'rateLimitType')
        WrittenAt     = ConvertTo-LimitOffset (Get-LimitJsonProperty $data 'writtenAt')
        Instance      = [string](Get-LimitJsonProperty $data 'instance')
        Ticket        = [string](Get-LimitJsonProperty $data 'ticket')
    }
}

function Get-LimitHoldUntil {
    <#
    .SYNOPSIS
        The moment a hold stops holding, as a DateTimeOffset, or $null for a hold that names no time.
    .DESCRIPTION
        Known reset: that time plus the margin. No reset: the moment it was written plus the poll
        wait, after which one child is launched as the probe.
    #>
    param($Hold, [Parameter(Mandatory)] $Policy)
    if ($null -eq $Hold) { return $null }
    if ($null -ne $Hold.ResetsAt) {
        return [DateTimeOffset]::FromUnixTimeSeconds([int64]$Hold.ResetsAt).AddSeconds($Policy.MarginSeconds)
    }
    if ($null -ne $Hold.WrittenAt) { return $Hold.WrittenAt.AddMinutes($Policy.PollMinutes) }
    return $null
}

function Get-LimitHoldState {
    <#
    .SYNOPSIS
        What the runner has to know before a launch: whether a hold is active, until when, and why.
    .DESCRIPTION
        Reads only. The file and this process's own memory of a hold it failed to write are both
        consulted and the one that holds longer wins, so a runner whose disk is unwritable still
        stops launching into a limit it has just seen.
    #>
    param([Parameter(Mandatory)][string] $Path)

    $policy = Get-LimitPolicy
    $hold = Read-LimitHold -Path $Path
    $local = $script:LimitHoldLocal
    if ($null -ne $local) {
        $fileUntil = Get-LimitHoldUntil -Hold $hold -Policy $policy
        $localUntil = Get-LimitHoldUntil -Hold $local -Policy $policy
        if ($null -eq $fileUntil -or ($null -ne $localUntil -and $localUntil -gt $fileUntil)) { $hold = $local }
    }

    $until = Get-LimitHoldUntil -Hold $hold -Policy $policy
    $now = [DateTimeOffset]::UtcNow
    $active = ($null -ne $until -and $until -gt $now)
    return [pscustomobject]@{
        Active        = $active
        Until         = $until
        Mode          = if ($null -eq $hold) { 'none' } elseif ($null -ne $hold.ResetsAt) { 'resetsAt' } else { 'poll' }
        ResetsAt      = if ($null -eq $hold) { $null } else { $hold.ResetsAt }
        RateLimitType = if ($null -eq $hold) { '' } else { $hold.RateLimitType }
        WrittenAt     = if ($null -eq $hold) { $null } else { $hold.WrittenAt }
        Instance      = if ($null -eq $hold) { '' } else { $hold.Instance }
        Ticket        = if ($null -eq $hold) { '' } else { $hold.Ticket }
    }
}

function Write-LimitHold {
    <#
    .SYNOPSIS
        Record a limit hit in the shared hold, raising the reset time and never lowering it.
    .DESCRIPTION
        The rules, in the order they are applied to what is already on disk:

          - A reset time not greater than the one on disk is not written. The same limit seen by
            three instances writes once, and a stale reading cannot pull a wait back in. This holds
            whether or not the record on disk has expired.
          - A hit with no reset time never replaces a hold that is still running.
          - A known reset time replaces a hold that was only a poll wait: information beats a guess.
          - Otherwise the record is written.

        The read-compare-write runs under a named mutex, because three children failing within
        seconds of each other is the case this exists for, and an unguarded compare lets a smaller
        value written second overwrite a larger one written first. The replace itself is a move of
        a finished temp file, so a reader never meets a partial record.

        Returns the hold state as it stands after the call.
    #>
    param(
        [Parameter(Mandatory)][string] $Path,
        $ResetsAt = $null,
        [string] $RateLimitType = '',
        [string] $Instance = '',
        [string] $Ticket = ''
    )

    $policy = Get-LimitPolicy
    $resets = ConvertTo-LimitUnixSeconds $ResetsAt
    $now = [DateTimeOffset]::UtcNow

    $mutex = $null
    $owned = $false
    try {
        $sha = [System.Security.Cryptography.SHA1]::Create()
        $key = ([System.BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Path.ToLowerInvariant())))).Replace('-', '')
        $mutex = [System.Threading.Mutex]::new($false, "Global\sza-limit-hold-$key")
        try { $owned = $mutex.WaitOne(5000) } catch [System.Threading.AbandonedMutexException] { $owned = $true }
    } catch {
        $mutex = $null
        $owned = $false
    }

    try {
        $existing = Read-LimitHold -Path $Path
        $existingUntil = Get-LimitHoldUntil -Hold $existing -Policy $policy
        $live = ($null -ne $existingUntil -and $existingUntil -gt $now)

        $write = $true
        if ($null -ne $existing -and $null -ne $existing.ResetsAt -and $null -ne $resets -and $resets -le $existing.ResetsAt) {
            $write = $false
        } elseif ($null -eq $resets -and $live) {
            $write = $false
        }

        if ($write) {
            $record = [ordered]@{
                resetsAt      = $resets
                resetsAtIso   = if ($null -ne $resets) { [DateTimeOffset]::FromUnixTimeSeconds($resets).UtcDateTime.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'") } else { $null }
                rateLimitType = $RateLimitType
                writtenAt     = $now.UtcDateTime.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
                instance      = $Instance
                ticket        = $Ticket
            }
            $written = $false
            $temp = $null
            try {
                $dir = Split-Path -Parent $Path
                if (-not (Test-Path -LiteralPath $dir -PathType Container)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
                $temp = "{0}.{1}.tmp" -f $Path, $PID
                [System.IO.File]::WriteAllText($temp, ($record | ConvertTo-Json -Compress), (New-Object System.Text.UTF8Encoding($false)))
                [System.IO.File]::Move($temp, $Path, $true)
                $written = $true
            } catch {
                if ($null -ne $temp) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
            }
            if (-not $written) {
                $script:LimitHoldLocal = [pscustomobject]@{
                    ResetsAt = $resets; RateLimitType = $RateLimitType; WrittenAt = $now
                    Instance = $Instance; Ticket = $Ticket
                }
            }
        }
    } finally {
        if ($owned) { try { $mutex.ReleaseMutex() } catch { } }
        if ($null -ne $mutex) { $mutex.Dispose() }
    }
    return (Get-LimitHoldState -Path $Path)
}

function Wait-LimitHold {
    <#
    .SYNOPSIS
        Block while a hold is active. $true when the caller may launch, $false when a stop file
        appeared first.
    .DESCRIPTION
        Sleeps in slices of at most -SliceSeconds (15 by default) and re-reads the hold and the
        stop files on every slice: the operator's stop still
        works during a wait of days, a hold another instance raised is followed, and a hold the
        operator deleted ends the wait within one slice.

        One line when the wait starts and one when it ends, none per slice. There is no cap: a
        weekly limit is a wait of days and a sleeping runner costs nothing.
    #>
    param(
        [Parameter(Mandatory)][string] $Path,
        [string[]] $StopFile = @(),
        [string] $Instance = '',
        [int] $SliceSeconds = 15
    )

    if ($SliceSeconds -lt 1) { $SliceSeconds = 1 }
    $announced = $false
    while ($true) {
        $state = Get-LimitHoldState -Path $Path
        if (-not $state.Active) {
            if ($announced) {
                Write-Host ("run-spec-queue: instance '{0}' - the limit wait is over, resuming." -f $Instance) -ForegroundColor Cyan
            }
            return $true
        }
        foreach ($stop in $StopFile) {
            if (-not [string]::IsNullOrWhiteSpace($stop) -and (Test-Path -LiteralPath $stop)) { return $false }
        }
        if (-not $announced) {
            $announced = $true
            $kind = if ([string]::IsNullOrWhiteSpace($state.RateLimitType)) { 'usage' } else { $state.RateLimitType }
            $how = if ($state.Mode -eq 'resetsAt') { 'reported reset plus margin' } else { 'no reset time reported, polling' }
            Write-Host ("run-spec-queue: instance '{0}' is waiting for the {1} limit - no child starts until {2} ({3}); a stop file ends the wait." -f `
                    $Instance, $kind, $state.Until.LocalDateTime.ToString('yyyy-MM-dd HH:mm:ss'), $how) -ForegroundColor Yellow
        }
        $remaining = [Math]::Ceiling(($state.Until - [DateTimeOffset]::UtcNow).TotalSeconds)
        $sleep = [int][Math]::Max(1, [Math]::Min($SliceSeconds, $remaining))
        Start-Sleep -Seconds $sleep
    }
}
