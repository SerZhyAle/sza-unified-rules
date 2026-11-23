# Machine-wide exclusive resources of the robots (TASK-FLOW rule 62; S0016 R65, decision D17 of 2026-11-10: build 3,
# emulator 1; device takes no token and, since TASK-FLOW 0.21, is offered to a robot like any other level).
#
# Dot-source this file after paths.ps1, ledger-watch.ps1 and loop.ps1; it defines functions only, sets no preference and
# prints nothing.
#
#   Get-PqTicketVerify -RepoPath <dir> -TicketId <id>
#       edit | build | emulator | device from the spec's `**Verify:** <level> - <reason>` line within its first 40 lines.
#       No line, an unreadable spec or a value outside the table is `build` (rule 62: in doubt, the higher level).
#   Get-PqVerifyTokens -Verify <level>
#       the tokens that level takes: edit none, build `build`, emulator `build` and `emulator`; device none (the pass does the work and parks the ticket in BlockNeedUserTest).
#   Get-PqResourceHeld -Token <build|emulator> [-ClearStale]
#       the live token files (and, with -ClearStale, the dead owners' files removed first, returned in .stale).
#   Request-PqResources -Registry -RepoKey -TicketId -Verify -PassId
#       @{ ok; held = @(tokens taken); why; resource; heldCount; cap; stale; counts } - all tokens or none: a token is a file
#       <root>\resources\<token>\<repo>__<id>.json with token, repo, id, pid, procStart, pass, at; the count of files is
#       the number held; the check and the writes are one state transaction, so two workers cannot both take the last one.
#       counts is @{ <token> = @{ held; cap } } for every token looked at - after the take on success - so an event of one
#       token reports that token's own count (rule 62).
#   Remove-PqResources -RepoKey -TicketId
#       release every token that ticket holds (also the dispatcher's own, whenever it ends).
#
# Device leases (TASK-FLOW 0.41 section 19; canon TESTING_AND_QA section 4). A session of any project that drives a phone,
# a watch or an emulator holds a lease in <root>\devices, written by tools/harness/devices/device-lease.ps1. The dispatcher
# only reads them, through that tool, so the judgement of who is alive stays in one place:
#   Get-PqDeviceLeaseDir
#       <root>\devices; never created here, nothing is written there.
#   Test-PqEmulatorLeaseKey <key>
#       avd:<name> or emulator-<port>: the keys that name an emulator.
#   Get-PqDeviceLeases [-EmulatorOnly] [-TimeoutSeconds 20]
#       @{ ok; why; leases } - the live leases: id, project, sessionId, reason, ageMinutes, lastSeenMinutes, liveness
#       (the tool's `Status -Json`, which also sweeps the stale ones, as every verb of that tool does). A store with no lease
#       file is answered from the directory listing, with no child process. A tool that is missing, fails or is silent past
#       the timeout answers ok false and no leases: the lease is advisory, and a dispatcher that cannot read it goes on.
#   An `emulator` request counts the larger of its token files and the live emulator leases as held: a robot's own lease
#   and its own token are one emulator. `build` and `device` read no lease.

$script:PqVerifyLevels = @('edit', 'build', 'emulator', 'device')

function Get-PqTicketVerify {
    param([Parameter(Mandatory)][string]$RepoPath, [Parameter(Mandatory)][string]$TicketId)
    try {
        $snap = Get-PqLedgerSnapshot -RepoPath $RepoPath
        if (-not $snap.tickets.Contains($TicketId)) { return 'build' }
        $file = [string]$snap.tickets[$TicketId].file
        if (-not $file) { return 'build' }
        $spec = Resolve-PqRepoPathValue $snap.root $file
        if (-not [IO.File]::Exists($spec)) { return 'build' }
        foreach ($line in (Get-Content -LiteralPath $spec -TotalCount 40 -Encoding UTF8)) {
            if ($line -match '^\*\*Verify:\*\*\s*([A-Za-z]+)') {
                $level = $Matches[1].ToLowerInvariant()
                if ($script:PqVerifyLevels -ccontains $level) { return $level }
                return 'build'
            }
        }
    }
    catch { }
    return 'build'
}

function Get-PqVerifyTokens([string]$Verify) {
    switch ($Verify) {
        'edit' { return [string[]]@() }
        'emulator' { return [string[]]@('build', 'emulator') }
        'device' { return [string[]]@() }
        default { return [string[]]@('build') }
    }
}

function Get-PqResourceTokenDir([string]$Token) { return (Join-Path (Get-PqPath -Kind resources) $Token) }

function Get-PqDeviceLeaseDir { return (Join-Path (Get-PqRoot) 'devices') }

function Test-PqEmulatorLeaseKey([string]$Id) { return ($Id -cmatch '^(avd:|emulator-)') }

function Get-PqDeviceLeases {
    param([switch]$EmulatorOnly, [int]$TimeoutSeconds = 20)
    try {
        $dir = Get-PqDeviceLeaseDir
        if (-not [IO.Directory]::Exists($dir) -or [IO.Directory]::GetFiles($dir, '*.json').Count -eq 0) {
            return @{ ok = $true; why = $null; leases = @() }
        }
        $tool = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\devices\device-lease.ps1'))
        if (-not [IO.File]::Exists($tool)) { return @{ ok = $false; why = 'tool-missing'; leases = @() } }
        # The picker's child runner starts the tool with the agent session variables removed (rule 29), so the reader never
        # speaks as the session that started the dispatcher and never refreshes that session's own leases by reading.
        if (-not (Get-Command Invoke-PqRepoChild -ErrorAction SilentlyContinue)) { . (Join-Path $PSScriptRoot 'picker.ps1') }
        $child = Invoke-PqRepoChild -RepoPath (Get-PqHarnessRoot '') -Script $tool -Arguments @('-Verb', 'Status', '-Json') -TimeoutSeconds $TimeoutSeconds
        if ($child.timedOut) { return @{ ok = $false; why = 'timeout'; leases = @() } }
        if ($child.code -ne 0) { return @{ ok = $false; why = "exit-$($child.code)"; leases = @() } }
        $parsed = ConvertFrom-PqLastJsonLine ([string]$child.stdout) -Array
        if (-not $parsed.ok) { return @{ ok = $false; why = 'unreadable'; leases = @() } }
        # 'foreign-stale' is a lease whose session went quiet; anything the tool could not judge is kept, as the tool keeps it.
        $live = @(@($parsed.value) | Where-Object { $null -ne $_ -and [string]$_.liveness -cne 'foreign-stale' })
        if ($EmulatorOnly) { $live = @($live | Where-Object { Test-PqEmulatorLeaseKey ([string]$_.id) }) }
        return @{ ok = $true; why = $null; leases = $live }
    }
    catch { return @{ ok = $false; why = 'error'; leases = @() } }
}

# Callers hold the state lock when they clear, so a stale file is removed once.
function Get-PqResourceHeld {
    param([Parameter(Mandatory)][string]$Token, [switch]$ClearStale)
    $dir = Get-PqResourceTokenDir $Token
    $live = [Collections.Generic.List[object]]::new()
    $stale = [Collections.Generic.List[string]]::new()
    if ([IO.Directory]::Exists($dir)) {
        foreach ($f in [IO.Directory]::GetFiles($dir, '*.json')) {
            $s = Read-PqState $f
            $alive = ($null -ne $s) -and (Test-PqProcessAlive ([int](Get-PqValue $s 'pid' 0)) (Get-PqValue $s 'procStart'))
            if ($alive) { $live.Add($s); continue }
            if ($ClearStale) {
                Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue
                $stale.Add([IO.Path]::GetFileNameWithoutExtension($f))
            }
            elseif ($null -ne $s) { $live.Add($s) }
        }
    }
    return @{ live = @($live); stale = @($stale) }
}

function Request-PqResources {
    param(
        [Parameter(Mandatory)]$Registry, [Parameter(Mandatory)][string]$RepoKey, [Parameter(Mandatory)][string]$TicketId,
        [Parameter(Mandatory)][string]$Verify, [string]$PassId = ''
    )
    $tokens = @(Get-PqVerifyTokens $Verify)
    if ($tokens.Count -eq 0) { return @{ ok = $true; held = @(); why = $null; resource = $null; heldCount = 0; cap = 0; stale = @() } }
    $res = Get-PqValue $Registry 'resources'
    # 0.41 section 19: read before the state transaction, never inside it (a child process under the lock would hold every
    # other worker), and only for an `emulator` request. A lease that cannot be read is no lease.
    $leaseRead = @{ ok = $true; why = $null; leases = @() }
    if ($tokens -ccontains 'emulator') {
        try { $leaseRead = Get-PqDeviceLeases -EmulatorOnly } catch { $leaseRead = @{ ok = $false; why = 'error'; leases = @() } }
    }
    $leaseKeys = @(@($leaseRead.leases) | ForEach-Object { [string]$_.id })
    $resourceRepo = $RepoKey
    $resourceId = $TicketId
    $resourcePass = $PassId
    $startedAt = (Get-Process -Id $PID).StartTime.ToUniversalTime().ToString('o')
    return (Invoke-PqStateLock {
            $stale = [Collections.Generic.List[string]]::new()
            $counts = [ordered]@{}
            foreach ($t in $tokens) {
                $cap = [int](Get-PqValue $res $t $(if ($t -ceq 'build') { 3 } else { 1 }))
                $h = Get-PqResourceHeld -Token $t -ClearStale
                foreach ($s in @($h.stale)) { $stale.Add("$t/$s") }
                # The larger of the token files and the live emulator leases: a robot's own lease and its own token are one emulator.
                $heldNow = @($h.live).Count
                if ($t -ceq 'emulator' -and $leaseKeys.Count -gt $heldNow) { $heldNow = $leaseKeys.Count }
                $counts[$t] = @{ held = $heldNow; cap = $cap }
                $sameTicket = @($h.live | Where-Object { (Get-PqValue $_ 'repo') -ceq $resourceRepo -and (Get-PqValue $_ 'id') -ceq $resourceId })
                $mine = @($sameTicket | Where-Object { [int](Get-PqValue $_ 'pid' 0) -eq $PID -and (Get-PqValue $_ 'pass') -ceq $resourcePass }).Count
                if ($sameTicket.Count -gt $mine) {
                    return @{ ok = $false; held = @(); why = 'resource'; resource = $t; heldCount = $heldNow; cap = $cap; stale = @($stale); counts = $counts; leases = $leaseKeys }
                }
                if ($mine -eq 0 -and $heldNow -ge $cap) {
                    return @{ ok = $false; held = @(); why = 'resource'; resource = $t; heldCount = $heldNow; cap = $cap; stale = @($stale); counts = $counts; leases = $leaseKeys }
                }
            }
            foreach ($t in $tokens) {
                $file = Get-PqPath -Kind resourceToken -Token $t -Repo $resourceRepo -Id $resourceId
                $dir = Split-Path -Parent $file
                if (-not [IO.Directory]::Exists($dir)) { $null = [IO.Directory]::CreateDirectory($dir) }
                $obj = [ordered]@{
                    token = $t; repo = $resourceRepo; id = $resourceId; pid = $PID; procStart = $startedAt; pass = $resourcePass
                    at = [DateTimeOffset]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
                }
                $tmp = "$file.$PID.tmp"
                [IO.File]::WriteAllText($tmp, ($obj | ConvertTo-Json -Compress), [Text.UTF8Encoding]::new($false))
                [IO.File]::Move($tmp, $file, $true)
            }
            foreach ($t in $tokens) {
                $afterTake = @((Get-PqResourceHeld -Token $t).live).Count
                if ($t -ceq 'emulator' -and $leaseKeys.Count -gt $afterTake) { $afterTake = $leaseKeys.Count }
                $counts[$t].held = $afterTake
            }
            $first = $tokens[-1]
            return @{ ok = $true; held = $tokens; why = $null; resource = $first; heldCount = $counts[$first].held; cap = $counts[$first].cap; stale = @($stale); counts = $counts; leases = $leaseKeys }
        })
}

# The `d` of a resource event for one token (EVENTS.md): resource, verify, and that token's own held and cap from a
# Request-PqResources result; a stale clear adds `stale` (the dead owner's file name).
function Get-PqResourceEventData($Request, [string]$Token, [string]$Verify, [string]$Stale = '') {
    $c = $null
    $counts = Get-PqValue $Request 'counts'
    if ($null -ne $counts -and $counts.Contains($Token)) { $c = $counts[$Token] }
    $d = [ordered]@{ resource = $Token; verify = $Verify; held = $(if ($c) { [int]$c.held } else { 0 }); cap = $(if ($c) { [int]$c.cap } else { 0 }) }
    if ($Stale) { $d.stale = $Stale }
    return $d
}

function Remove-PqResources {
    param([Parameter(Mandatory)][string]$RepoKey, [Parameter(Mandatory)][string]$TicketId)
    return (Invoke-PqStateLock {
        $released = [Collections.Generic.List[string]]::new()
        try {
            foreach ($t in @('build', 'emulator')) {
                $file = Get-PqPath -Kind resourceToken -Token $t -Repo $RepoKey -Id $TicketId
                $state = Read-PqState $file
                if ($null -ne $state -and [int](Get-PqValue $state 'pid' 0) -eq $PID -and (Test-PqProcessAlive $PID (Get-PqValue $state 'procStart'))) {
                    Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
                    $released.Add($t)
                }
            }
        }
        catch { }
        return @($released)
    })
}
