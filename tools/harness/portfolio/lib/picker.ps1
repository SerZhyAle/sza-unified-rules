# The picker adapter: asks one repository's own authority for its head (TASK-FLOW rules 18, 22, 29 and 43; S0015 R2).
#
# Dot-source this file; it defines functions only, sets no preference and prints nothing. State: none.
# Everything here is read-only: the shipped picker runs with -NoDrift and never with its claim switch (a dispatcher
# worker claims through the repository's own runner), in a child process whose environment alone carries
# SZA_PROJECT_ROOT and from which every <NAME>_AGENT_ID and the starting agent's session variables are removed
# (Remove-PqAgentSessionEnv; rule 29: a dispatcher started from an agent session must not make that session's leases
# look like its own).
#
#   Invoke-PqPicker -RepoPath <dir> [-Exclude <string[]>] [-TimeoutSeconds <int>] [-HarnessRoot <dir>]
#                   [-ScriptPath <file>]
#       @{ ok; payload; code; error; ms }: error PickerFailed (non-zero exit, nothing parseable; message holds the
#       first 300 characters of stderr) or PickerTimeout (the child and its tree are killed). Never throws.
#   Get-PqPickerHead -RepoPath [-Exclude] [-ForceId <id>] [-HarnessRoot] [-TimeoutSeconds] [-Cache <hashtable>]
#       @{ ok; head; payload; why; error; ms }. Without -ForceId head is payload.selected. With it, head is that
#       ticket when the picker would offer it once the ids ranked above it are excluded, else $null and why is
#       leased, excluded, notRanked, malformed or the picker's auto-skip reason. From a complete-scan payload
#       (scan_complete, Resolve-PqHeadFromPayload) a head that is not the picker's own selected ticket is its ranked
#       entry - id, name, status, priority, updated - not the full preview payload.
#   Get-PqTicketRecord -RepoPath -Id [-HarnessRoot]
#       the ledger record (archive included) through select.ps1, or $null.
#   Get-PqLedgerStatuses -RepoPath [-HarnessRoot] [-TimeoutSeconds]
#       @{ id = status } for the whole ledger (archive included) from one select.ps1 run, or $null when it cannot be read.
#
# Cost: one child process per call, two for a -ForceId that is not the head (S0015 Phase 02 evidence,
# picker-latency.json) - unless the picker's payload is a complete scan (SZA_PQ_PICKER=1 asks for one): then -ForceId
# costs no second child, and with -Cache every later question about the same repository in the rank costs none.

function Get-PqHarnessRoot([string]$HarnessRoot) {
    if ($HarnessRoot) { return $HarnessRoot }
    return [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
}

# Session and runtime variables of the agent that started the dispatcher. A child that inherits them speaks as that
# agent (rule 29): a pass child takes its leases, locks and chat lines, a nested agent CLI takes itself for a
# sub-session, and the read-only picker keeps that agent's own leases in the ranking (spec-next-preflight.ps1 skips
# only leases that are not "mine"), so it offers the ticket the agent is on. The owner's desktop shortcut carries none
# of them, an agent's shell carries all. Credentials and provider settings (CLAUDE_CODE_OAUTH_TOKEN, CLAUDE_CODE_USE_*,
# CLAUDE_CODE_GIT_BASH_PATH, ANTHROPIC_*) are not session state and stay.
$script:PqAgentSessionEnvPattern = '^(CLAUDECODE|CLAUDE_PID|CLAUDE_AGENT_SDK_[A-Z0-9_]+|CLAUDE_CODE_(SESSION_[A-Z0-9_]+|CHILD_SESSION|ENTRYPOINT|MESSAGING_[A-Z0-9_]+|SSE_PORT|ENABLE_SDK_FILE_CHECKPOINTING|ENABLE_TASKS|EMIT_STARTUP_TIMING|QUESTION_PREVIEW_FORMAT|IDE_[A-Z0-9_]+))$'

function Remove-PqAgentSessionEnv {
    param([Parameter(Mandatory)]$Environment)
    foreach ($name in @($Environment.Keys)) {
        if ($name -cmatch '^[A-Z0-9]+_AGENT_ID$' -or $name -match $script:PqAgentSessionEnvPattern) { [void]$Environment.Remove($name) }
    }
}

# Runs `pwsh -NoProfile -File <Script> @Arguments` for one repository. Returns @{ code; stdout; stderr; timedOut; ms }.
function Invoke-PqRepoChild {
    param([string]$RepoPath, [string]$Script, [string[]]$Arguments, [int]$TimeoutSeconds = 300, [hashtable]$ExtraEnv = $null)
    $pwsh = (Get-Command pwsh -CommandType Application | Select-Object -First 1).Source
    $psi = [Diagnostics.ProcessStartInfo]::new($pwsh)
    foreach ($a in (@('-NoProfile', '-File', $Script) + @($Arguments))) { $psi.ArgumentList.Add([string]$a) }
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.WorkingDirectory = $RepoPath
    $psi.Environment['SZA_PROJECT_ROOT'] = $RepoPath
    [void]$psi.Environment.Remove('SZA_PROFILE_PATH')
    Remove-PqAgentSessionEnv $psi.Environment
    if ($null -ne $ExtraEnv) {
        foreach ($k in $ExtraEnv.Keys) { $psi.Environment[[string]$k] = [string]$ExtraEnv[$k] }
    }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $proc = [Diagnostics.Process]::Start($psi)
    $out = $proc.StandardOutput.ReadToEndAsync()
    $err = $proc.StandardError.ReadToEndAsync()
    if (-not $proc.WaitForExit($TimeoutSeconds * 1000)) {
        $null = & taskkill.exe /PID $proc.Id /T /F 2>&1
        $null = $proc.WaitForExit(10000)
        $sw.Stop()
        return @{ code = $null; stdout = ''; stderr = ''; timedOut = $true; ms = [int]$sw.ElapsedMilliseconds }
    }
    $proc.WaitForExit()
    $sw.Stop()
    return @{ code = $proc.ExitCode; stdout = $out.Result; stderr = $err.Result; timedOut = $false; ms = [int]$sw.ElapsedMilliseconds }
}

function ConvertFrom-PqLastJsonLine([string]$Text, [switch]$Array) {
    $start = if ($Array) { '[' } else { '{' }
    $lines = @($Text -split '\r?\n' | Where-Object { $_.Trim().Length -gt 0 })
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        $l = $lines[$i].Trim()
        if (-not $l.StartsWith($start)) { continue }
        try { return @{ ok = $true; value = (ConvertFrom-Json -InputObject $l -DateKind String -NoEnumerate) } } catch { }
    }
    return @{ ok = $false; value = $null }
}

function Invoke-PqPicker {
    param(
        [Parameter(Mandatory)][string]$RepoPath,
        [string[]]$Exclude,
        [int]$TimeoutSeconds = 300,
        [string]$HarnessRoot,
        [string]$ScriptPath
    )
    $HarnessRoot = Get-PqHarnessRoot $HarnessRoot
    if (-not $ScriptPath) { $ScriptPath = Join-Path $HarnessRoot 'spec_catalog\spec-next-preflight.ps1' }
    # Read-only: -NoDrift, and never the picker's claim switch (R2).
    $arguments = @('-NoDrift', '-Format', 'json')
    $ids = @(@($Exclude) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($ids.Count -gt 0) { $arguments += @('-Exclude', ($ids -join ',')) }
    try { $r = Invoke-PqRepoChild -RepoPath $RepoPath -Script $ScriptPath -Arguments $arguments -TimeoutSeconds $TimeoutSeconds -ExtraEnv @{ SZA_PQ_PICKER = '1' } }
    catch { return @{ ok = $false; payload = $null; code = $null; error = 'PickerFailed'; message = $_.Exception.Message; ms = 0 } }
    if ($r.timedOut) { return @{ ok = $false; payload = $null; code = $null; error = 'PickerTimeout'; message = "the picker outlived $TimeoutSeconds s and was killed"; ms = $r.ms } }
    $stderr = [string]$r.stderr
    if ($stderr.Length -gt 300) { $stderr = $stderr.Substring(0, 300) }
    $parsed = ConvertFrom-PqLastJsonLine $r.stdout
    if ($r.code -ne 0 -or -not $parsed.ok) {
        return @{ ok = $false; payload = $null; code = $r.code; error = 'PickerFailed'; message = $stderr; ms = $r.ms }
    }
    return @{ ok = $true; payload = $parsed.value; code = $r.code; error = $null; message = $null; ms = $r.ms }
}

function Get-PqPayloadIds($Items) {
    return @(foreach ($x in @($Items)) {
            if ($null -eq $x) { continue }
            if ($x -is [string]) { $x } elseif ($null -ne $x.PSObject.Properties['id']) { [string]$x.id }
        })
}

function Get-PqAutoSkipReason($Payload, [string]$Id) {
    foreach ($s in @($Payload.auto_skipped)) {
        if ($null -ne $s -and [string]$s.id -ceq $Id) { return [string]$s.reason }
    }
    return $null
}

function Get-PqPayloadList($Payload, [string]$Name) {
    if ($null -eq $Payload) { return @() }
    $p = $Payload.PSObject.Properties[$Name]
    if ($null -eq $p -or $null -eq $p.Value) { return @() }
    return @($p.Value)
}

# True when the picker judged every ranked candidate (spec-next-preflight.ps1 scan_complete, which SZA_PQ_PICKER=1 turns
# on), not only those above its selected ticket. Absent in a payload of an older harness: such a payload answers only
# for the walk down to its head.
function Test-PqPayloadScanComplete($Payload) {
    if ($null -eq $Payload) { return $false }
    $p = $Payload.PSObject.Properties['scan_complete']
    return ($null -ne $p -and $p.Value -eq $true)
}

# The exclusion of a request as the picker normalises it: comma-joined elements split, blanks dropped, ids compared
# without case (the picker's exclude set is a hashtable).
function Get-PqExcludeSet([string[]]$Exclude) {
    $set = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($e in @($Exclude)) { foreach ($id in ([string]$e -split ',')) { if ($id.Trim()) { $null = $set.Add($id.Trim()) } } }
    return , $set
}

# Answers a head question from a payload already in hand, without a picker run, when that payload can answer it exactly:
# it must be a complete scan, and it must not have hidden what the question asks about. Returns the Get-PqPickerHead
# shape with ms 0, or $null when the payload cannot answer (the caller then runs the picker).
#
#   -ForceId X: the payload must not have excluded X itself (it then holds X's verdict, which no exclusion changes - an
#   idle hold, an unreleased blocker, an owner gate, a lease are all about X alone). X ranked and in none of auto_skipped,
#   malformed and claim_lost is offered: the picker run with every id above X excluded - what this used to cost - would
#   select it. head is then X's ranked entry (id, name, status, priority: what the rank reads of a head).
#   No -ForceId: the payload's exclusion must be a subset of the question's (an id it excluded has no verdict in it).
#   The head is the first ranked id the question does not exclude and the payload did not refuse - the walk the picker
#   would make - and the payload's own selected ticket when that is the one.
function Resolve-PqHeadFromPayload {
    param($Payload, [string[]]$Exclude, [string]$ForceId)
    if (-not (Test-PqPayloadScanComplete $Payload)) { return $null }
    $want = Get-PqExcludeSet $Exclude
    $had = Get-PqExcludeSet ([string[]]@(Get-PqPayloadIds (Get-PqPayloadList $Payload 'excluded_ids')))
    $refused = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($id in @(Get-PqPayloadIds (Get-PqPayloadList $Payload 'auto_skipped')) + @(Get-PqPayloadIds (Get-PqPayloadList $Payload 'malformed')) +
        @(Get-PqPayloadIds (Get-PqPayloadList $Payload 'claim_lost'))) { $null = $refused.Add([string]$id) }
    $ranked = @(Get-PqPayloadList $Payload 'ranked' | Where-Object { $null -ne $_ })
    $selected = $Payload.selected
    $selectedId = if ($null -ne $selected) { [string]$selected.id } else { '' }

    if ($ForceId) {
        if ($had.Contains($ForceId)) { return $null }
        $answer = { param($head, $why) @{ ok = $true; head = $head; payload = $Payload; why = $why; error = $null; ms = 0 } }
        if ($want.Contains($ForceId)) { return (& $answer $null 'excluded') }
        if ($selectedId -ceq $ForceId) { return (& $answer $selected $null) }
        if (@(Get-PqPayloadIds (Get-PqPayloadList $Payload 'leased_ids')) -ccontains $ForceId) { return (& $answer $null 'leased') }
        $entry = $null
        foreach ($r in $ranked) { if ([string](Get-PqPayloadIds @($r)) -ceq $ForceId) { $entry = $r; break } }
        if ($null -eq $entry) {
            $why = if (@(Get-PqPayloadIds (Get-PqPayloadList $Payload 'malformed')) -ccontains $ForceId) { 'malformed' } else { 'notRanked' }
            return (& $answer $null $why)
        }
        $why = Get-PqAutoSkipReason $Payload $ForceId
        if ($why) { return (& $answer $null $why) }
        if (@(Get-PqPayloadIds (Get-PqPayloadList $Payload 'malformed')) -ccontains $ForceId) { return (& $answer $null 'malformed') }
        if (@(Get-PqPayloadIds (Get-PqPayloadList $Payload 'claim_lost')) -ccontains $ForceId) { return (& $answer $null 'leased') }
        return (& $answer $entry $null)
    }

    foreach ($id in $had) { if (-not $want.Contains($id)) { return $null } }
    $head = $null
    $live = 0
    foreach ($r in $ranked) {
        $id = [string](Get-PqPayloadIds @($r))
        if ($want.Contains($id)) { continue }
        $live++
        if ($null -ne $head -or $refused.Contains($id)) { continue }
        $head = if ($id -ceq $selectedId) { $selected } else { $r }
    }
    $copy = $Payload.PSObject.Copy()
    $copy.selected = $head
    if ($null -ne $copy.PSObject.Properties['selected_none_reason']) {
        $leasedLeft = @(Get-PqPayloadIds (Get-PqPayloadList $Payload 'leased_ids') | Where-Object { -not $want.Contains([string]$_) }).Count
        $lostLeft = @(Get-PqPayloadIds (Get-PqPayloadList $Payload 'claim_lost') | Where-Object { -not $want.Contains([string]$_) }).Count
        $copy.selected_none_reason = if ($null -ne $head) { $null }
        elseif ([int]$Payload.eligible_count -eq 0) { 'queue-exhausted' }
        elseif ($live -eq $lostLeft -and ($leasedLeft + $lostLeft) -gt 0) { 'all-leased' }
        else { 'no-candidate' }
    }
    return @{ ok = $true; head = $head; payload = $copy; why = $null; error = $null; ms = 0 }
}

function Get-PqPickerHead {
    param(
        [Parameter(Mandatory)][string]$RepoPath,
        [string[]]$Exclude,
        [string]$ForceId,
        [string]$HarnessRoot,
        [int]$TimeoutSeconds = 300,
        [hashtable]$Cache
    )
    # -Cache keeps the unforced run per (repository, exclusion) for one rank: every ticket row of a repository asks the
    # same first question, and a queue whose blocked rows pile up above the head paid one child per row (a night of
    # 2026-10-29 spent 15 minutes a pass ranking 58 such rows).
    $ck = "$RepoPath|$(@($Exclude) -join ',')"
    # A complete-scan payload (Resolve-PqHeadFromPayload) judged every ranked ticket of the repository, so any earlier one
    # of this rank answers a later question - another row's ticket, or the head under a grown exclusion - without a new
    # child. One picker run per repository per rank is then the whole cost; before 2026-11-13 a rank of the portfolio
    # queue made 167-190 of them (100-170 s), most of them a second run per row with every id above the row excluded.
    $completeKey = "$RepoPath|<complete>"
    if ($null -ne $Cache -and -not $Cache.ContainsKey($ck) -and $Cache.ContainsKey($completeKey)) {
        foreach ($known in @($Cache[$completeKey])) {
            $answer = Resolve-PqHeadFromPayload -Payload $known -Exclude $Exclude -ForceId $ForceId
            if ($null -ne $answer) { return $answer }
        }
    }
    # A forced row asks whether ONE ticket is offerable. Whether it is ranked at all, auto-skipped (idle hold, unreleased
    # blocker, owner gate), leased or malformed does not depend on what else is excluded, so any earlier run of this
    # repository in the same rank answers a "no" without a new child. Measured 2026-11-13: every refused head grew the
    # exclusion, and each growth re-ran the picker for every later row of that repository (2-5 s a row). This is the
    # path of a payload that is not a complete scan; a complete one has answered above.
    $anyKey = "$RepoPath|<any>"
    if ($ForceId -and $null -ne $Cache -and -not $Cache.ContainsKey($ck) -and $Cache.ContainsKey($anyKey)) {
        $known = $Cache[$anyKey].payload
        if ($null -ne $known) {
            $kRanked = @(Get-PqPayloadIds $known.ranked)
            $kWhy = $null
            if ((Get-PqPayloadIds $known.leased_ids) -ccontains $ForceId) { $kWhy = 'leased' }
            elseif ($kRanked -cnotcontains $ForceId) { $kWhy = if ((Get-PqPayloadIds $known.malformed) -ccontains $ForceId) { 'malformed' } else { 'notRanked' } }
            else { $kWhy = Get-PqAutoSkipReason $known $ForceId }
            if ($kWhy) { return @{ ok = $true; head = $null; payload = $known; why = $kWhy; error = $null; ms = 0 } }
        }
    }
    if ($null -ne $Cache -and $Cache.ContainsKey($ck)) { $first = $Cache[$ck] }
    else {
        $first = Invoke-PqPicker -RepoPath $RepoPath -Exclude $Exclude -HarnessRoot $HarnessRoot -TimeoutSeconds $TimeoutSeconds
        if ($null -ne $Cache -and $first.ok) {
            $Cache[$ck] = $first
            $Cache[$anyKey] = $first
            if (Test-PqPayloadScanComplete $first.payload) {
                $Cache[$completeKey] = @(@($Cache[$completeKey]) + @($first.payload) | Where-Object { $null -ne $_ })
            }
        }
    }
    if (-not $first.ok) { return @{ ok = $false; head = $null; payload = $null; why = 'pickerFailed'; error = $first.error; ms = $first.ms } }
    $payload = $first.payload
    if (-not $ForceId) { return @{ ok = $true; head = $payload.selected; payload = $payload; why = $null; error = $null; ms = $first.ms } }
    $ms = $first.ms
    if ($null -ne $payload.selected -and [string]$payload.selected.id -ceq $ForceId) {
        return @{ ok = $true; head = $payload.selected; payload = $payload; why = $null; error = $null; ms = $ms }
    }
    if ((Get-PqPayloadIds $payload.leased_ids) -ccontains $ForceId) { return @{ ok = $true; head = $null; payload = $payload; why = 'leased'; error = $null; ms = $ms } }
    if ((Get-PqPayloadIds $payload.excluded_ids) -ccontains $ForceId) { return @{ ok = $true; head = $null; payload = $payload; why = 'excluded'; error = $null; ms = $ms } }
    $ranked = @(Get-PqPayloadIds $payload.ranked)
    $at = [array]::IndexOf([string[]]$ranked, $ForceId)
    if ($at -lt 0) {
        $why = if ((Get-PqPayloadIds $payload.malformed) -ccontains $ForceId) { 'malformed' } else { 'notRanked' }
        return @{ ok = $true; head = $null; payload = $payload; why = $why; error = $null; ms = $ms }
    }
    $why = Get-PqAutoSkipReason $payload $ForceId
    if ($why) {
        return @{ ok = $true; head = $null; payload = $payload; why = $why; error = $null; ms = $ms }
    }
    # A complete scan already holds this ticket's verdict: the second run below would only repeat it.
    $answer = Resolve-PqHeadFromPayload -Payload $payload -Exclude $Exclude -ForceId $ForceId
    if ($null -ne $answer) { $answer.ms = $ms; return $answer }
    $above = if ($at -gt 0) { $ranked[0..($at - 1)] } else { @() }
    $second = Invoke-PqPicker -RepoPath $RepoPath -Exclude (@($Exclude) + @($above)) -HarnessRoot $HarnessRoot -TimeoutSeconds $TimeoutSeconds
    $ms += $second.ms
    if (-not $second.ok) { return @{ ok = $false; head = $null; payload = $payload; why = 'pickerFailed'; error = $second.error; ms = $ms } }
    $p2 = $second.payload
    if ($null -ne $p2.selected -and [string]$p2.selected.id -ceq $ForceId) {
        return @{ ok = $true; head = $p2.selected; payload = $payload; why = $null; error = $null; ms = $ms }
    }
    $why = Get-PqAutoSkipReason $p2 $ForceId
    if (-not $why) { $why = Get-PqAutoSkipReason $payload $ForceId }
    if (-not $why) { $why = if ((Get-PqPayloadIds $p2.malformed) -ccontains $ForceId) { 'malformed' } else { 'notOffered' } }
    return @{ ok = $true; head = $null; payload = $payload; why = $why; error = $null; ms = $ms }
}

# Every ticket of one repository's ledger, archive included: @{ id = status }, ids compared ordinally - read in process
# when ledger-watch.ps1 is loaded, else from a single child process. $null when the ledger cannot be read in bulk
# (timeout, non-zero exit, unparsable output) - the caller then asks ticket by ticket through Get-PqTicketRecord. One
# child per queue row costs minutes on a queue of a hundred rows.
function Get-PqLedgerStatuses {
    param([Parameter(Mandatory)][string]$RepoPath, [string]$HarnessRoot, [int]$TimeoutSeconds = 120)
    # In process first: the ledger snapshot of ledger-watch.ps1 reads the same two files the profile names, in
    # milliseconds, where the child below costs a pwsh start per repository (about 8 s of every rank over 19 of them).
    # Archive rows read as Archived, which is what the queue reader asks (exists, closed). A snapshot that could not
    # read a file, or a process without ledger-watch.ps1, falls back to the child.
    if (Get-Command Get-PqLedgerSnapshot -ErrorAction SilentlyContinue) {
        try {
            $snap = Get-PqLedgerSnapshot -RepoPath $RepoPath
            if ($snap.complete -and $snap.ledgerRead) {
                $map = [hashtable]::new([StringComparer]::Ordinal)
                foreach ($id in @($snap.tickets.Keys)) { $map[[string]$id] = [string]$snap.tickets[$id].status }
                return $map
            }
        }
        catch { }
    }
    $HarnessRoot = Get-PqHarnessRoot $HarnessRoot
    $script = Join-Path $HarnessRoot 'spec_catalog\select.ps1'
    try { $r = Invoke-PqRepoChild -RepoPath $RepoPath -Script $script -Arguments @('-IncludeArchived', '-Format', 'json') -TimeoutSeconds $TimeoutSeconds }
    catch { return $null }
    if ($r.timedOut -or $r.code -ne 0) { return $null }
    $text = ([string]$r.stdout).Trim()
    if ($text.Length -eq 0) { return $null }
    try { $value = ConvertFrom-Json -InputObject $text -DateKind String -NoEnumerate } catch { return $null }
    $map = [hashtable]::new([StringComparer]::Ordinal)
    foreach ($x in @($value)) {
        if ($null -ne $x -and $null -ne $x.PSObject.Properties['id']) { $map[[string]$x.id] = [string]$x.status }
    }
    return $map
}

function Get-PqTicketRecord {
    param([Parameter(Mandatory)][string]$RepoPath, [Parameter(Mandatory)][string]$Id, [string]$HarnessRoot, [int]$TimeoutSeconds = 120)
    $HarnessRoot = Get-PqHarnessRoot $HarnessRoot
    $script = Join-Path $HarnessRoot 'spec_catalog\select.ps1'
    try { $r = Invoke-PqRepoChild -RepoPath $RepoPath -Script $script -Arguments @('-Id', $Id, '-IncludeArchived', '-Format', 'json') -TimeoutSeconds $TimeoutSeconds }
    catch { return $null }
    if ($r.timedOut -or $r.code -ne 0) { return $null }
    $text = ([string]$r.stdout).Trim()
    if ($text.Length -eq 0) { return $null }
    try { $value = ConvertFrom-Json -InputObject $text -DateKind String -NoEnumerate } catch { return $null }
    foreach ($x in @($value)) { if ($null -ne $x -and [string]$x.id -ceq $Id) { return $x } }
    return $null
}
