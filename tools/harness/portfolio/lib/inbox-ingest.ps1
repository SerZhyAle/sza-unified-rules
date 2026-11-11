#requires -Version 7.0
# The inbox ingest (S0046): a claimed packet -> a real Draft ticket through the shared capture path, the result
# written beside the manifest, the packet moved to done/ or failed/, and one event line per decision.
#
# Dot-source this file; it defines functions only, sets no preference and prints nothing. State: none. It loads
# the spool and the packet reader itself, plus the portfolio paths, the event log and the registry;
# watch-inbox.ps1, ingest-inbox.ps1 and the tests all reach the capture through the one function here, so a ticket
# in another repository is never written by hand (TASK-FLOW 4/5/12 hold by construction: every write goes through
# spec-draft.ps1, which itself runs the project-owned or the canon capture script).
#
#   Invoke-InboxIngestPacket -Root <spool> -PacketPath <processing\<id>> [-SpecDraft <script>] [-Log <handle>]
#                            [-MaxPacketBytes <n>] [-MaxFiles <n>] [-RetryCeiling <n>] [-BackoffSeconds <int[]>]
#                            [-CaptureTimeoutSeconds <n>] -> @{ outcome; ok; tickets; reason; detail; attempts }
#     outcome:
#       processed  the packet is in done/; result.json holds @{ packetId; tickets; verdict; at }; tickets is the
#                  '<key>:<id>' list of what the captures printed - the `drafted` line is parsed, never guessed
#       requeued    a retryable capture failure (spec-draft exit 1 or 2 - bad invocation, an unknown or half-set
#                  project, a locked repo; a launch failure; a timeout): the packet is back in new/ with
#                  attempts+1 and the backoff (1, 5, 15 min), or at the ceiling left in processing/ for the caller
#                  to fail
#       failed      the packet is in failed/ with reason.json: a refusal by the reader's reason names (the whole
#                  INBOX-PACKET section 4 matrix), 'DedupHit' (spec-draft exit 3: a closed ticket already deals
#                  with this symptom), 'RetryCeiling' or 'CaptureFailed'
#       already    the packet is in done/ or failed/ already (the idempotency line; nothing was done)
#     -Log: an open PqLog handle; every decision writes one `ingest.packet` event. outcome is refused (the reader
#     refused the packet), failed (a capture failure) or processed; a re-queue is failed with reason RetryQueued;
#     the 'accepted' line is the claimer's (watch-inbox.ps1), not the ingest's. $null -Log writes none.
#     d = { packetId, outcome, project, tickets, reason }.
#
#   Get-InboxIngestTargets -Manifest [-Registry]  project + projects[] as a union in the order named; none ->
#                            canon. -> @{ targets; unknown }: a key the registry does not know comes back in
#                            targets as 'canon' (owner choice 3(b): nothing is lost, the phone's stale
#                            projects.json must not eat a ticket) and in unknown (what the ticket's tail quotes).
#   Test-InboxProjectAcceptsAttach -RepoPath   whether the project's capture path (its own
#                            scripts/utils/capture-draft.ps1, else the canon's spec_catalog one) takes -Attach -
#                            the same test spec-draft.ps1 runs; until S0028 lands everywhere, attachments are
#                            passed only where they are accepted and the refusal is quoted in the ticket.
#   Find-InboxPacketTickets -RootPath -Key -PacketId  the tickets an earlier ingest of this packet filed (the
#                            provenance marker in the project's PLAN/), so a re-run after a crash mid-ingest
#                            -> @{ pair; file } per hit; an unreadable root or spec fails the scan closed.
#   Resolve-InboxSpecDraft [-SpecDraft <script>]  the capture entry point: -SpecDraft, else SZA_SPEC_DRAFT, else
#                            a spec-draft.ps1 on PATH, else the one beside the portfolio tools.
#   Invoke-InboxIngestCli  the CLI body of ingest-inbox.ps1 (a single -Packet resumed, the -All drain).
#
# The ticket text. The owner's words verbatim - the text member or a text-role payload file - passed on to
# spec-draft's -TextFile. Machine lines are appended only BELOW a separator line, so the owner's words stay byte
# for byte above it: the provenance marker (what the pre-scan and the dedup query find: "phone packet <id>"), the
# unknown-project note, the attachment refusal and the cross-links of a multi-project packet (every ticket after
# the first names the earlier ones - the capture assigns ids one by one, so a forward reference is the only honest
# cross-link; the first ticket is named by the later ones and names the packet's other targets in its tail).

. (Join-Path $PSScriptRoot 'inbox-spool.ps1')
. (Join-Path $PSScriptRoot 'paths.ps1')
. (Join-Path $PSScriptRoot 'events.ps1')
. (Join-Path $PSScriptRoot 'registry.ps1')

$script:InboxProvenanceMark = 'phone packet'   # the marker every filed ticket carries: find it, never re-file

# S0048: the packet's own words can name a publish channel or ask for a build. The recognition only READS - the
# drafted ticket stays a normal Draft (the agent, not the transport, interprets the text) and the fields the
# result carries are additive so an older reader skips them. ms-store first: the owner's phrasing for THE store.
$script:InboxPublishIntentPatterns = [ordered]@{
    'ms-store' = '(?i)ms[- ]?store|microsoft\s+store|\bв\s+стор\b|\bв\s+сторе\b|\bмс\s*стор'
    'github'   = '(?i)github|гитхаб'
    'winget'   = '(?i)winget|вингет'
}
$script:InboxBuildIntentPattern = '(?i)\bсобери\w*\b|\bсобрать\b|\bсборк\w*\b|\bbuild a (new )?version\b|\bmake (me )?a build\b'

function Get-InboxIntentText {
    param([Parameter(Mandatory)]$Source)
    try {
        if ($Source.kind -ceq 'payload') { return [IO.File]::ReadAllText($Source.path, [Text.Encoding]::UTF8) }
        return [string]$Source.text
    }
    catch { return '' }
}

# -> 'ms-store' | 'github' | 'winget' | $null ("publish <project> in MS Store", "выложи в стор", "вингет").
function Get-InboxPublishIntent {
    param([Parameter(Mandatory)][string]$Text)
    foreach ($k in @($script:InboxPublishIntentPatterns.Keys)) {
        if ($Text -cmatch $script:InboxPublishIntentPatterns[$k]) { return [string]$k }
    }
    return $null
}

function Test-InboxBuildIntent {
    param([Parameter(Mandatory)][string]$Text)
    return ($Text -cmatch $script:InboxBuildIntentPattern)
}

function Write-InboxIngestEvent {
    param($Log, [string]$Outcome, [string]$PacketId, [string]$Project, $Tickets, [string]$Reason)
    if ($null -eq $Log) { return }
    $d = [ordered]@{ packetId = $PacketId; outcome = $Outcome }
    if ($Project) { $d['project'] = $Project }
    if ($null -ne $Tickets) { $d['tickets'] = @($Tickets) }
    if ($Reason) { $d['reason'] = $Reason }
    $null = Write-PqEvent -Log $Log -Ev 'ingest.packet' -D $d
}

function Resolve-InboxSpecDraft {
    param([string]$SpecDraft)
    if ([string]::IsNullOrWhiteSpace($SpecDraft)) { $SpecDraft = $env:SZA_SPEC_DRAFT }
    if (-not [string]::IsNullOrWhiteSpace($SpecDraft)) {
        if (-not [IO.File]::Exists($SpecDraft)) { throw "SpecDraftMissing: $SpecDraft" }
        return [IO.Path]::GetFullPath($SpecDraft)
    }
    $onPath = Get-Command -Name 'spec-draft.ps1' -CommandType ExternalScript -ErrorAction Ignore
    if ($null -ne $onPath) { return $onPath.Path }
    $beside = Join-Path (Split-Path -Parent $PSScriptRoot) 'spec-draft.ps1'
    if ([IO.File]::Exists($beside)) { return $beside }
    throw 'SpecDraftMissing: no spec-draft.ps1 (-SpecDraft, SZA_SPEC_DRAFT, PATH or beside the harness)'
}

# The capture path spec-draft.ps1 would run for this project, and whether it takes -Attach: the same lookup and
# the same parameter check, run BEFORE the call, so a project that cannot hold attachments is not asked to (a
# refused -Attach costs a whole stopped capture otherwise).
function Test-InboxProjectAcceptsAttach {
    param([string]$RepoPath)
    if ([string]::IsNullOrWhiteSpace($RepoPath) -or -not [IO.Directory]::Exists($RepoPath)) { return $false }
    $own = Join-Path $RepoPath (Join-Path 'scripts' (Join-Path 'utils' 'capture-draft.ps1'))
    $capture = if ([IO.File]::Exists($own)) { $own } else { Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) (Join-Path 'spec_catalog' 'capture-draft.ps1') }
    if (-not [IO.File]::Exists($capture)) { return $false }
    try { return (Get-Command -Name $capture -CommandType ExternalScript).Parameters.ContainsKey('Attach') }
    catch { return $false }
}

# The tickets of this packet an earlier ingest already filed: the provenance marker in the project's own spec
# files - a crash between the capture and the result write leaves exactly those, and the pre-scan below turns them
# into the idempotency guard for a re-queued packet ("plus the dedup query against the spec catalog", done
# criterion 4: this scan catches the OPEN duplicate a re-file would create; spec-draft's -DedupQuery catches a
# closed one with exit 3). The marker can follow a long owner request in any spec.
function Find-InboxPacketTickets {
    param(
        [string]$RootPath,
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$PacketId
    )
    if ([string]::IsNullOrWhiteSpace($RootPath) -or -not [IO.Directory]::Exists($RootPath)) { throw "InboxDedupRootMissing: $RootPath" }
    $specsDir = 'PLAN'
    $archiveDir = ''
    $profilePath = Join-Path $RootPath '.sza-profile.json'
    if ([IO.File]::Exists($profilePath)) {
        try {
            $profile = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($profilePath)) -AsHashtable -DateKind String
            if ($profile -isnot [Collections.IDictionary]) { throw 'profile is not an object' }
            $paths = $profile['paths']
            if ($paths -is [Collections.IDictionary] -and $paths['specsDir']) { $specsDir = [string]$paths['specsDir'] }
            if ($paths -is [Collections.IDictionary] -and $paths['specArchiveDir']) { $archiveDir = [string]$paths['specArchiveDir'] }
        }
        catch { throw "InboxDedupProfileUnreadable: $profilePath" }
    }
    $planDir = [IO.Path]::GetFullPath((Join-Path $RootPath $specsDir))
    if (-not [IO.Directory]::Exists($planDir)) { throw "InboxDedupPlanMissing: $planDir" }
    $scanRoots = @($planDir)
    if ($archiveDir) {
        $archivePath = [IO.Path]::GetFullPath((Join-Path $RootPath $archiveDir))
        $planPrefix = $planDir.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
        if ([IO.Directory]::Exists($archivePath) -and $archivePath -ine $planDir -and -not $archivePath.StartsWith($planPrefix, [StringComparison]::OrdinalIgnoreCase)) { $scanRoots += $archivePath }
    }
    $marker = 'Filed from phone packet ' + [regex]::Escape($PacketId) + '(?:, sent from [^\r\n]*)? by the PC inbox watcher \(S0046\)\.'
    $hits = [Collections.Generic.List[object]]::new()
    foreach ($f in @(Get-ChildItem -LiteralPath $scanRoots -Recurse -Filter '*.md' -File -ErrorAction Stop)) {
        try {
            $head = [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8)
            if ($head -cnotmatch $marker) { continue }
        }
        catch { throw "InboxDedupReadFailed: $($f.FullName): $($_.Exception.Message)" }
        $m = [regex]::Match($f.Name, '^(?<id>[A-Za-z]+-?[0-9]+)')
        if (-not $m.Success) { continue }
        $hits.Add([pscustomobject]@{ pair = "${Key}:$($m.Groups['id'].Value)"; file = $f.FullName })
    }
    return @($hits)
}

# project + projects[] as one ordered set; none -> canon. Unknown keys are routed to canon (kept in `unknown` so
# the ticket's tail can quote them) - never refused: the phone's projects.json can be stale, and a refused packet
# would silently eat a ticket (owner choice 3(b)).
function Get-InboxIngestTargets {
    param(
        [Parameter(Mandatory)]$Manifest,
        $Registry
    )
    $ordered = [Collections.Generic.List[string]]::new()
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $project = Get-InboxMember $Manifest 'project'
    $projectKey = $null
    if ($project.value -is [string] -and -not [string]::IsNullOrWhiteSpace($project.value)) {
        $projectKey = [string]$project.value
        if ($seen.Add($projectKey)) { $ordered.Add($projectKey) }
    }
    foreach ($k in @(Get-InboxArrayValue $Manifest 'projects')) {
        if ($k -isnot [string] -or [string]::IsNullOrWhiteSpace($k)) { continue }
        if ($seen.Add($k)) { $ordered.Add($k) }
    }
    if ($ordered.Count -eq 0) { return @{ targets = @('canon'); unknown = @() } }
    if ($null -eq $Registry) { return @{ targets = @($ordered); unknown = @() } }
    $known = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($r in @($Registry.repos)) { $null = $known.Add([string]$r.key) }
    $targets = [Collections.Generic.List[string]]::new()
    $unknown = [Collections.Generic.List[string]]::new()
    foreach ($k in $ordered) {
        if ($known.Contains($k)) { if (-not $targets.Contains($k)) { $targets.Add($k) }; continue }
        $unknown.Add($k)
        if (-not $targets.Contains('canon')) { $targets.Add('canon') }
    }
    return @{ targets = @($targets); unknown = @($unknown) }
}

# The owner's words: a text-role payload file, else the text member, else a .md/.txt payload. kind none = the
# packet carries nothing a ticket could be written from (the reader accepts such a manifest; the ingest refuses
# it with the reader's own reason name TextInvalid).
function Get-InboxTextSource {
    param(
        [Parameter(Mandatory)]$Manifest,
        [Parameter(Mandatory)][string]$PacketPath,
        [Parameter(Mandatory)]$Files
    )
    foreach ($f in @($Files)) {
        if ([string]$f.role -ceq 'text') { return @{ kind = 'payload'; name = [string]$f.name; path = (Join-Path $PacketPath ([string]$f.name)) } }
    }
    $text = Get-InboxMember $Manifest 'text'
    if ($text.has -and $text.value -is [string] -and -not [string]::IsNullOrWhiteSpace($text.value)) {
        return @{ kind = 'member'; name = $null; path = $null; text = $text.value }
    }
    foreach ($f in @($Files)) {
        if ([string]$f.name -cmatch '\.(md|txt)$' -and [string]$f.role -cne 'log') { return @{ kind = 'payload'; name = [string]$f.name; path = (Join-Path $PacketPath ([string]$f.name)) } }
    }
    return @{ kind = 'none'; name = $null; path = $null; text = $null }
}

# The -TextFile for one capture: the owner's words, then a separator and the machine lines below it. The
# marker line is ALWAYS written - "phone packet <id>" is what the pre-scan finds in the project's PLAN/ (the
# open-duplicate guard of a re-run after a crash) and what spec-draft's -DedupQuery is handed for the
# closed-ticket hit (exit 3); passing a payload file byte for byte would file a ticket no later ingest could
# recognize as this packet's. The owner's words stay byte for byte above the separator.
function New-InboxTicketText {
    param(
        [Parameter(Mandatory)]$Source,
        [Parameter(Mandatory)][string]$PacketId,
        [string[]]$Notes = @(),
        [string]$SenderName = ''
    )
    $notes = @($Notes | Where-Object { $_ })
    $owner = if ($Source.kind -ceq 'payload') { [IO.File]::ReadAllText($Source.path, [Text.Encoding]::UTF8) } else { [string]$Source.text }
    $lines = [Collections.Generic.List[string]]::new()
    $lines.Add('----')
    $marks = "$($script:InboxProvenanceMark) $PacketId"
    $from = if ($SenderName) { ", sent from $SenderName" } else { '' }
    $lines.Add("Filed from $marks$from by the PC inbox watcher (S0046).")
    foreach ($n in $notes) { $lines.Add($n) }
    $body = $owner + "`n`n" + (($lines | ForEach-Object { $_ }) -join "`n") + "`n"
    $temp = [IO.Path]::GetTempFileName()
    [IO.File]::WriteAllText($temp, $body, [Text.UTF8Encoding]::new($false))
    return @{ path = $temp; temp = $true }
}

# One capture call. spec-draft prints its machine line last; a missing or malformed line is a failure even at
# exit 0 - the pair is parsed from the `drafted` line, never inferred from the exit code alone (done criterion 2).
function Invoke-InboxCapture {
    param(
        [Parameter(Mandatory)][string]$SpecDraft,
        [Parameter(Mandatory)][string]$Project,
        [Parameter(Mandatory)][string]$TextFile,
        [string]$Attach = '',
        [string]$DedupQuery = '',
        [int]$TimeoutSeconds = 300
    )
    $psi = [Diagnostics.ProcessStartInfo]::new((Get-Process -Id $PID).Path)
    $psi.ArgumentList.Add('-NoProfile')
    $psi.ArgumentList.Add('-File')
    $psi.ArgumentList.Add($SpecDraft)
    $psi.ArgumentList.Add('-Project')
    $psi.ArgumentList.Add($Project)
    $psi.ArgumentList.Add('-TextFile')
    $psi.ArgumentList.Add($TextFile)
    if ($Attach) { $psi.ArgumentList.Add('-Attach'); $psi.ArgumentList.Add($Attach) }
    if ($DedupQuery) { $psi.ArgumentList.Add('-DedupQuery'); $psi.ArgumentList.Add($DedupQuery) }
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $proc = [Diagnostics.Process]::new()
    $proc.StartInfo = $psi
    try {
        $null = $proc.Start()
        $out = $proc.StandardOutput.ReadToEndAsync()
        $err = $proc.StandardError.ReadToEndAsync()
        $timedOut = $false
        if (-not $proc.WaitForExit($TimeoutSeconds * 1000)) {
            $timedOut = $true
            try { $proc.Kill($true) } catch { }
            $null = $proc.WaitForExit(5000)
        }
        if ($timedOut) { return @{ code = 124; lines = @(); timedOut = $true; message = "the capture timed out after ${TimeoutSeconds}s and was killed" } }
        $exit = $proc.ExitCode
        # ReadToEndAsync hands back the WHOLE stream as one string; split it, or the drafted line at the bottom
        # stays glued to the rest and no regex anchored to a line ever sees it.
        $raw = (@($out.Result, $err.Result) | Where-Object { $_ }) -join "`n"
        $lines = @($raw -split '\r?\n' | ForEach-Object { $_.TrimEnd() } | Where-Object { $_ })
        return @{ code = $exit; lines = $lines; timedOut = $false; message = $null }
    }
    catch { return @{ code = -1; lines = @(); timedOut = $false; message = $_.Exception.Message } }
    finally { $proc.Dispose() }
}

# The `drafted <key>:<id> file=.. priority=.. pq=.. position=p/total` line, parsed bottom-up.
function Resolve-InboxDraftedPair {
    param([Parameter(Mandatory)]$Lines)
    $lines = @($Lines)
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        $m = [regex]::Match([string]$lines[$i], '^drafted\s+(?<pair>[A-Za-z0-9_.\-]+:[A-Za-z0-9_\-]+)\s+file=\S+\s+priority=\S+\s+pq=(?<pq>\S+)\s+position=\S+\s*$')
        if ($m.Success) { return @{ pair = $m.Groups['pair'].Value; pq = $m.Groups['pq'].Value } }
    }
    return $null
}

function Invoke-InboxIngestPacket {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$PacketPath,
        [string]$SpecDraft = '',
        $Log = $null,
        [long]$MaxPacketBytes = 209715200,
        [int]$MaxFiles = 50,
        [int]$RetryCeiling = $script:InboxRetryCeiling,
        [int[]]$BackoffSeconds = $script:InboxRetryBackoffSeconds,
        [int]$CaptureTimeoutSeconds = 300
    )
    $packetId = Split-Path -Leaf $PacketPath
    # Scriptblocks invoked with & read this function's own variables (Root, Log, packetId, the retry knobs)
    # through PowerShell's scope chain: the decision helpers below write reason.json, re-queue or fail the
    # packet, and return the record this function hands on - one place per terminal failure shape.
    $fail = {
        param([string]$Reason, [string]$Detail, [string]$Outcome)
        $move = Fail-InboxPacket -Root $Root -PacketId $packetId -Error $Reason -Detail $Detail
        Write-InboxIngestEvent -Log $Log -Outcome $Outcome -PacketId $packetId -Reason $Reason
        return @{ outcome = 'failed'; ok = ([bool]$move.ok); tickets = @(); reason = $Reason; detail = $Detail; attempts = 0; moveError = $move.error }
    }
    $retry = {
        param([string]$Why, [string]$Detail)
        $r = Requeue-InboxPacket -Root $Root -PacketId $packetId -LastError $Why -RetryCeiling $RetryCeiling -BackoffSeconds $BackoffSeconds
        if ($r.outcome -ceq 'requeued') {
            Write-InboxIngestEvent -Log $Log -Outcome 'failed' -PacketId $packetId -Reason 'RetryQueued'
            return @{ outcome = 'requeued'; ok = $false; tickets = @(); reason = 'RetryQueued'; detail = $Why; attempts = [int]$r.attempts; retryAt = $r.nextRetryAtEpochMs }
        }
        if ($r.outcome -ceq 'error') {
            Write-InboxIngestEvent -Log $Log -Outcome 'failed' -PacketId $packetId -Reason $r.error
            return @{ outcome = 'pending'; ok = $false; tickets = @(); reason = $r.error; detail = $Detail; attempts = [int]$r.attempts }
        }
        $move = Fail-InboxPacket -Root $Root -PacketId $packetId -Error 'RetryCeiling' -Detail $Detail
        Write-InboxIngestEvent -Log $Log -Outcome 'failed' -PacketId $packetId -Reason 'RetryCeiling'
        return @{ outcome = 'failed'; ok = ([bool]$move.ok); tickets = @(); reason = 'RetryCeiling'; detail = $Why; attempts = [int]$r.attempts; moveError = $move.error }
    }

    if (Test-InboxProcessedPacket -Root $Root -PacketId $packetId) {
        return @{ outcome = 'already'; ok = $true; tickets = @(); reason = $null; detail = $null; attempts = 0 }
    }
    $specDraft = Resolve-InboxSpecDraft $SpecDraft

    # ---- the reader's matrix, whole (INBOX-PACKET section 4): a refused packet is never partially trusted ----
    $check = Test-InboxPacketFolder -Path $PacketPath -MaxPacketBytes $MaxPacketBytes -MaxFiles $MaxFiles
    if (-not $check.ok) {
        $names = @($check.errors | ForEach-Object { $_.name } | Select-Object -Unique)
        $detail = (@($check.errors) | ForEach-Object { "$($_.name): $($_.message)" }) -join ' | '
        return (& $fail ([string]$names[0]) ([string]$detail) 'refused')
    }

    # ---- the registry: which keys exist and where they live; unreadable reads route to canon ----
    $registry = $null
    try {
        $read = Read-PqRegistry -Path (Get-PqPath -Kind registry)
        if ($read.ok) { $registry = $read.registry }
    }
    catch { $registry = $null }
    if ($null -eq $registry) { return (& $retry 'the project registry is unavailable' 'Cannot safely deduplicate without the project registry') }

    $targets = Get-InboxIngestTargets -Manifest $check.packet -Registry $registry
    $sender = (Get-InboxMember $check.packet 'senderDeviceName').value
    $source = Get-InboxTextSource -Manifest $check.packet -PacketPath $PacketPath -Files $check.files
    if ($source.kind -ceq 'none') {
        return (& $fail 'TextInvalid' 'no ticket text: neither the text member nor a payload file carries words' 'refused')
    }

    # S0048: what the owner's own words ask for beyond the ticket itself. Read once, recorded in result.json and
    # as a note in every ticket this packet drafts; the recognition changes no routing and files no separate type.
    $intentText = Get-InboxIntentText $source
    $publishIntent = Get-InboxPublishIntent $intentText
    $buildIntent = Test-InboxBuildIntent $intentText

    $attachFiles = @(foreach ($f in @($check.files)) {
        if ($source.kind -ceq 'payload' -and [string]$f.name -ceq [string]$source.name) { continue }
        Join-Path $PacketPath ([string]$f.name)
    })

    $tickets = [Collections.Generic.List[string]]::new()
    $verdicts = [Collections.Generic.List[string]]::new()
    $projectField = (@($targets.targets) -join ',')
    $dedup = "$($script:InboxProvenanceMark) $packetId"

    foreach ($key in @($targets.targets)) {
        $repoPath = $null
        if ($null -ne $registry) {
            $rec = @($registry.repos | Where-Object { [string]$_.key -ieq $key }) | Select-Object -First 1
            if ($null -ne $rec) { $repoPath = [string]$rec.path }
        }

        # The pre-scan: this packet already filed a ticket here (a crash between the capture and the result write)
        # - reused, never re-filed. The dedup query below catches the closed ticket; this catches the open one.
        if ($repoPath) {
            try { $hits = Find-InboxPacketTickets -RootPath $repoPath -Key $key -PacketId $packetId }
            catch { return (& $retry "the dedup scan of $key failed" $_.Exception.Message) }
            foreach ($h in @($hits)) { $tickets.Add($h.pair); $verdicts.Add('already-filed') }
            if (@($hits).Count -gt 0) { continue }
        }
        else { return (& $retry "the registry has no path for $key" 'Cannot safely deduplicate without the project path') }

        $notes = [Collections.Generic.List[string]]::new()
        if (@($targets.unknown).Count -gt 0) {
            $quoted = (@($targets.unknown) | ForEach-Object { "'$_'" }) -join ', '
            $one = (@($targets.unknown).Count -eq 1)
            $notes.Add("The phone asked for $(if ($one) { 'project' } else { 'projects' }) $quoted; $(if ($one) { 'that key is' } else { 'those keys are' }) not registered on this PC, so the ticket is filed here for triage (pq problems reports it).")
        }
        if ($publishIntent) {
            $notes.Add("The packet asks for a publish ($publishIntent): work it by skills/store-publish (channel order - GitHub Release, Store in parallel, winget last); the store/winget legs are one-way [PUBLIC] - stage everything and stop at the manual owner step (BlockExternal/BlockNeedUserTest).")
        }
        if ($buildIntent) {
            $notes.Add("The packet asks for a new build: when the work lands Implemented/BlockNeedUserTest, the drain produces it with -After <key>:<id> or build-deliver -Project <key> -Ticket <id>, and the fresh version is delivered to the Drive folder the phone can reach.")
        }
        if (@($targets.targets).Count -gt 1) {
            # The ids do not exist when the first capture runs. All tickets point to the same durable result,
            # which lists every assigned key:id once the fan-out succeeds, including after a resumed ingest.
            $resultPath = Join-Path (Join-Path (Join-Path $Root 'done') $packetId) 'result.json'
            $resultUri = ([Uri]::new([IO.Path]::GetFullPath($resultPath))).AbsoluteUri
            $notes.Add("Sibling tickets for this packet ($(@($targets.targets) -join ', ')): [packet result]($resultUri). The result lists every assigned ticket id after filing finishes.")
        }
        if ($tickets.Count -gt 0) {
            $notes.Add("Filed together with the same packet as $(@($tickets) -join ', ').")
        }
        $attachArg = ''
        if (@($attachFiles).Count -gt 0) {
            if ($repoPath -and (Test-InboxProjectAcceptsAttach -RepoPath $repoPath)) {
                $attachArg = @($attachFiles) -join ';'
            }
            else {
                $names = @($attachFiles | ForEach-Object { Split-Path -Leaf $_ })
                $one = (@($names).Count -eq 1)
                $notes.Add("The packet carries $(if ($one) { 'an attachment' } else { "$(@($names).Count) attachments" }) this project's capture script cannot attach (S0028): $(@($names) -join ', '). The payload stays in the packet's done/ spool folder.")
            }
        }
        $text = New-InboxTicketText -Source $source -PacketId $packetId -Notes @($notes) -SenderName ([string]$sender)
        $capture = Invoke-InboxCapture -SpecDraft $specDraft -Project $key -TextFile $text.path -Attach $attachArg `
            -DedupQuery $dedup -TimeoutSeconds $CaptureTimeoutSeconds
        if ($text.temp) { try { [IO.File]::Delete($text.path) } catch { } }

        if ($capture.timedOut) {
            return (& $retry "the capture of ${key} timed out" $capture.message)
        }
        if ($capture.code -eq -1) {
            return (& $retry "the capture of ${key} could not be launched" $capture.message)
        }
        if ($capture.code -eq 3) {
            return (& $fail 'DedupHit' "spec-draft exited 3 for ${key}: the dedup query hit a closed ticket that already deals with this symptom (pass -AllowClosedDuplicate by hand for a genuine regression)" 'failed')
        }
        # The catalog refuses an insert whose NAME is already taken by an active record (a re-dropped identical
        # wording with a new packet id): deterministic, nothing was created, retrying would refuse again. The
        # pre-scan handles the same packetId; this is the second arrival of the same WORDS.
        $dupLine = @($capture.lines | Where-Object { $_ -match 'already exists' -and $_ -match 'record with name' } | Select-Object -First 1)
        if ($dupLine) {
            return (& $fail 'DuplicateActiveRecord' "the capture of ${key} was refused: $dupLine - a ticket with these words is already active there; re-dropped text needs a new wording or -AllowClosedDuplicate by hand" 'failed')
        }
        if ($capture.code -ne 0) {
            $tail = (@($capture.lines) | Select-Object -Last 3) -join ' | '
            return (& $retry "spec-draft exited $($capture.code) for $key" $tail)
        }
        $drafted = Resolve-InboxDraftedPair -Lines $capture.lines
        if ($null -eq $drafted) {
            return (& $fail 'CaptureFailed' "the capture of $key exited 0 but printed no 'drafted <key>:<id>' line (an exit code alone is never success)" 'failed')
        }
        $tickets.Add($drafted.pair)
        $verdicts.Add($drafted.pq)
    }

    $verdict = (@($verdicts) | Select-Object -Unique) -join ','
    $result = [ordered]@{
        packetId = $packetId
        tickets  = [string[]]$tickets.ToArray()
        verdict  = $verdict
        at       = [DateTimeOffset]::UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
    }
    if (@($targets.unknown).Count -gt 0) { $result['unknownProjects'] = [string[]]@($targets.unknown) }
    # S0048, additive: what the owner's words asked for (absent when the text names no channel / no build).
    if ($publishIntent) { $result['publishIntent'] = $publishIntent }
    if ($buildIntent) { $result['buildIntent'] = $true }
    $move = Complete-InboxPacket -Root $Root -PacketId $packetId -Result $result
    if (-not $move.ok) {
        if ($move.error -ceq 'ResultWriteFailed') { return (& $retry 'the result could not be written' $move.message) }
        # A committed result must stay in processing/ for recovery; re-queueing it makes it an unexpected file.
        return @{ outcome = 'pending'; ok = $false; tickets = $result.tickets; reason = $move.error; detail = $move.message; attempts = 0 }
    }
    Write-InboxIngestEvent -Log $Log -Outcome 'processed' -PacketId $packetId -Project $projectField -Tickets $result.tickets
    return @{ outcome = 'processed'; ok = $true; tickets = $result.tickets; reason = $null; detail = $null; attempts = 0; verdict = $verdict; result = $result }
}

# The CLI body of ingest-inbox.ps1. One packet (-Packet, claimed right here when it sits in new/) or the whole
# drain of new/ (-All, what S0047's periodic execution calls). Prints one line per decision; returns the process
# exit code: 0 every packet decided (done/ or failed/, a re-queue with its wait included), 1 a packet left
# undecided in processing/, 2 a bad invocation, 3 -All found nothing pending.
function Invoke-InboxIngestCli {
    param(
        [string]$Packet = '',
        [switch]$All,
        [string]$InboxRoot = '',
        $Log = $null,
        [int]$StaleMinutes = $script:InboxClaimStaleMinutes,
        [int]$RetryCeiling = $script:InboxRetryCeiling,
        [int[]]$BackoffSeconds = $script:InboxRetryBackoffSeconds,
        [long]$MaxPacketBytes = 209715200,
        [int]$MaxFiles = 50,
        [string]$SpecDraft = '',
        [switch]$NoRecover
    )
    if (-not $Packet -and -not $All) { [Console]::Error.WriteLine('ingest-inbox: pass -Packet <dir> or -All'); return 2 }
    if ($Packet -and $All) { [Console]::Error.WriteLine('ingest-inbox: -Packet and -All are exclusive'); return 2 }
    try { $root = Resolve-InboxSpoolRoot $InboxRoot }
    catch {
        [Console]::Error.WriteLine("ingest-inbox: $($_.Exception.Message)")
        return 2
    }
    $null = Initialize-InboxSpool $root

    $ownsLog = $false
    if ($null -eq $Log) { $Log = Open-PqLog -Writer imp; $ownsLog = $true }
    $openedLog = $Log
    try {
        if (-not $NoRecover) {
            $recovery = Invoke-InboxRecovery -Root $root -StaleMinutes $StaleMinutes
            foreach ($id in @($recovery.completed)) { Write-Host "ingest-inbox: finished $id (its result.json was there; moved to done/)" }
            foreach ($id in @($recovery.requeued)) { Write-Host "ingest-inbox: re-queued $id (stale claim)" }
            foreach ($id in @($recovery.left)) { Write-Host "ingest-inbox: left $id in processing/ (claim live)" }
        }

        # The claim list: -Packet names one (claimed here when it waits in new/), -All takes every claimable.
        $work = [Collections.Generic.List[string]]::new()
        if ($Packet) {
            $full = [IO.Path]::GetFullPath($Packet)
            $stage = Split-Path -Leaf (Split-Path -Parent $full)
            $packetId = Split-Path -Leaf $full
            if ($stage -ceq 'new') {
                $claimed = Claim-InboxPacket -Root $root -PacketId $packetId
                if (-not $claimed.ok) {
                    [Console]::Error.WriteLine("ingest-inbox: the claim of $packetId was refused - $($claimed.error): $($claimed.message)")
                    return 2
                }
                Write-Host "ingest-inbox: claimed $packetId"
                $work.Add($packetId)
            }
            elseif ($stage -ceq 'processing') { $work.Add($packetId) }
            else {
                [Console]::Error.WriteLine("ingest-inbox: -Packet must sit in new\\ or processing\\ of $root (found '$stage')")
                return 2
            }
        }
        else {
            while ($true) {
                $pending = @(Get-InboxNewPackets -Root $root | Where-Object { $_.manifestReady -and $_.retryReady })
                $claimedNow = 0
                foreach ($p in $pending) {
                    $claimed = Claim-InboxPacket -Root $root -PacketId $p.packetId -Attempts $p.attempts
                    if (-not $claimed.ok) { Write-Host "ingest-inbox: the claim of $($p.packetId) was refused - $($claimed.error)"; continue }
                    Write-Host "ingest-inbox: claimed $($p.packetId)$(if ($p.attempts -gt 0) { " (retry $($p.attempts)$(if ($p.lastError) { ": $($p.lastError)" }))" })"
                    $work.Add($p.packetId)
                    $claimedNow++
                }
                if ($claimedNow -eq 0) { break }
            }
        }
        if (@($work).Count -eq 0) {
            if ($All) { Write-Host 'ingest-inbox: nothing pending'; return 3 }
            [Console]::Error.WriteLine('ingest-inbox: no packet to ingest')
            return 2
        }

        $undecided = 0
        $selfClaimed = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($packetId in @($work)) { $null = $selfClaimed.Add($packetId) }
        if ($Packet -and ((Split-Path -Leaf (Split-Path -Parent ([IO.Path]::GetFullPath($Packet)))) -ceq 'processing')) {
            # A -Packet handed in processing\ is not this run's claim: never removed, whatever the outcome.
            $null = $selfClaimed.Remove((Split-Path -Leaf ([IO.Path]::GetFullPath($Packet))))
        }
        foreach ($packetId in @($work)) {
            Write-InboxIngestEvent -Log $Log -Outcome 'accepted' -PacketId $packetId
            $path = Join-Path (Join-Path $root 'processing') $packetId
            $r = Invoke-InboxIngestPacket -Root $root -PacketPath $path -SpecDraft $SpecDraft -Log $Log `
                -MaxPacketBytes $MaxPacketBytes -MaxFiles $MaxFiles -RetryCeiling $RetryCeiling -BackoffSeconds $BackoffSeconds
            switch ($r.outcome) {
                'processed' { Write-Host "ingest-inbox: processed $packetId -> $(@($r.tickets) -join ', ') (verdict $($r.verdict))" }
                'requeued' {
                    $undecided++
                    $when = if ($r.retryAt) { [DateTimeOffset]::FromUnixTimeMilliseconds([long]$r.retryAt).LocalDateTime.ToString('HH:mm') } else { 'its backoff' }
                    Write-Host "ingest-inbox: re-queued $packetId (attempt $($r.attempts), next try after $when) - $($r.detail)"
                }
                'already' {
                    # A duplicate claim this run made itself: the done/ or failed/ copy holds the same packetId
                    # and is the audit trail, so our claim (not a caller's handed-in packet) is removed.
                    if ($selfClaimed.Contains($packetId)) {
                        $null = Remove-InboxDuplicateClaim -Root $root -PacketId $packetId
                        Write-Host "ingest-inbox: $packetId is already processed; the duplicate claim was removed"
                    }
                    else { Write-Host "ingest-inbox: $packetId is already processed; nothing done" }
                }
                default {
                    $undecided++
                    Write-Host "ingest-inbox: failed $packetId - $($r.reason): $($r.detail)"
                }
            }
        }
        if ($undecided -gt 0) { return 1 }
        return 0
    }
    finally {
        if ($ownsLog -and $null -ne $openedLog) { $null = Close-PqLog -Log $openedLog }
    }
}
