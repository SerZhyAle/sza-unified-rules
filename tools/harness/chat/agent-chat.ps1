#requires -Version 7.0
<#
.SYNOPSIS
    Agent chat - post to or read the descriptive coordination layer from any runtime (S2372).

.DESCRIPTION
    The one mandatory interface to the agent chat: files under temp/AGENT-CHAT plus this script.
    Claude Code hooks and the coordination scripts write most messages on their own; a model or a
    runtime without hooks reaches the same store through these verbs.

      Post    - one progress message (-Kind from the closed list), or with -Finding one result
                record with -Topic, a -Scope (paths whose change invalidates it) and/or -TtlMinutes.
      Read    - newest-first messages, filtered by -AgentId, -Kind, -Ticket, -Domain, -SinceMinutes.
      Find    - alive findings for -Topic (wildcards allowed) and how many were judged dead.
      Status  - one row per agent seen in the retention window: nickname, id, last message, silent or not.
      Whoami  - this agent's identity: the nickname it speaks under, its id, runtime and model.
      Sweep   - run the retention/expiry/cap sweep alone (every Post and Read runs it anyway).

    Trust rule: this script reports and never decides. No lock, queue or lease consults the chat
    to grant anything, and no verdict that reaches a spec or a gate may rest on a finding someone
    else wrote. A finding relieves you of repeating cheap idempotent WORK - a measurement whose
    scope is intact, a device probe, a search already made - never of reporting.

    Kinds: session, phase, lock, wait, ticket, status, verdict, check, build, device, abandon,
    heartbeat, note.

.PARAMETER Verb
    Post | Read | Find | Status | Whoami | Sweep. Default Read.

.PARAMETER Query
    Substring or wildcard search term for -Verb Find (synonym for -Topic). Bare words are automatically wrapped in wildcards.

.PARAMETER Json
    One JSON document instead of text - the same content.

.EXAMPLE
    pwsh -NoProfile -File scripts/utils/agent-chat.ps1 -Verb Post -Kind phase -Ticket S2372 -Phase 02 -Note "writers"
.EXAMPLE
    pwsh -NoProfile -File scripts/utils/agent-chat.ps1 -Verb Post -Finding -Kind device -Topic "device:ready:com.sza.fastmediasorter.debug" -Scope app_v2/src -Note "device ready" -EvidenceCommand "device-ready.ps1" -EvidenceExit 0
.EXAMPLE
    pwsh -NoProfile -File scripts/utils/agent-chat.ps1 -Verb Read -AgentId <id> -Last 5
.EXAMPLE
    pwsh -NoProfile -File scripts/utils/agent-chat.ps1 -Verb Find -Topic "device:*"
.EXAMPLE
    pwsh -NoProfile -File scripts/utils/agent-chat.ps1 -Verb Find -Query "device"

.NOTES
    Exit codes:
      0 - done.
      1 - refused input: unknown kind, a finding without scope or TTL, a scope over the cap.
      2 - usage error, or the store could not be reached.
#>
[CmdletBinding(PositionalBinding = $false)]
param(
    [string]$Verb = 'Read',
    [string]$Kind = 'note',
    [string]$Note = '',
    [string]$Ticket = '',
    [string]$Phase = '',
    [string[]]$Domains = @(),
    [switch]$Finding,
    [string]$Topic = '',
    [string]$Query = '',
    [string[]]$Scope = @(),
    [Nullable[int]]$TtlMinutes = $null,
    [string]$Device = '',
    [string]$EvidenceCommand = '',
    [Nullable[int]]$EvidenceExit = $null,
    [string]$EvidenceArtifact = '',
    [string]$AgentId = '',
    [string]$Domain = '',
    [int]$SinceMinutes = 0,
    [int]$Last = 20,
    [string]$Stream = 'progress',
    [switch]$Json,
    [switch]$Help,
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest = @()
)

. (Join-Path $PSScriptRoot '..\_profile.ps1')

$ErrorActionPreference = 'Stop'

if ($Rest.Count -gt 0) {
    $common = @('Verbose', 'Debug', 'ErrorAction', 'WarningAction', 'InformationAction', 'ErrorVariable', 'WarningVariable', 'InformationVariable', 'OutVariable', 'OutBuffer', 'PipelineVariable')
    $accepted = @($MyInvocation.MyCommand.Parameters.Keys | Where-Object { $_ -ne 'Rest' -and $_ -notin $common } | Sort-Object)
    Write-Error ("agent-chat: unrecognised parameter '{0}'. Accepted parameters: {1}." -f $Rest[0], ($accepted -join ', ')) -ErrorAction Continue
    exit 2
}

if ($Help) { Get-Help -Detailed $PSCommandPath; exit 0 }

$verbs = @('Post', 'Read', 'Find', 'Status', 'Sweep', 'Whoami')
if ($verbs -notcontains $Verb) {
    Write-Error "agent-chat: unknown verb '$Verb' - accepted: $($verbs -join ', ')." -ErrorAction Continue
    exit 2
}
if (@('progress', 'finding', 'all') -notcontains $Stream) {
    Write-Error "agent-chat: -Stream must be progress, finding or all." -ErrorAction Continue
    exit 2
}

# `pwsh -File` hands a list parameter ONE token, so `-Scope a,b` arrives as the string "a,b":
# split every list on commas here rather than asking callers for a syntax -File cannot carry.
$Scope = @($Scope | ForEach-Object { "$_" -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$Domains = @($Domains | ForEach-Object { "$_" -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })

try {
    . (Get-SzaHarnessScript 'locks/agent-lock.ps1')
}
catch {
    Write-Error "agent-chat: could not load the lock library - $($_.Exception.Message)" -ErrorAction Continue
    exit 2
}

function Out-Result {
    param($Object, [string[]]$Lines)
    if ($Json) { $Object | ConvertTo-Json -Depth 8 -Compress }
    else { foreach ($l in $Lines) { Write-Host $l } }
}

switch ($Verb) {
    'Post' {
        try {
            # Never $args: PowerShell's automatic variable, and a hashtable assigned to it splats nothing.
            $postArgs = @{ Kind = $Kind; Ticket = $Ticket; Phase = $Phase; Domains = $Domains; Note = $Note }
            if ($Finding) {
                $postArgs.Stream = 'finding'
                $postArgs.Topic = $Topic
                $postArgs.Scope = $Scope
                $postArgs.TtlMinutes = $TtlMinutes
                $postArgs.Device = $Device
                $postArgs.EvidenceCommand = $EvidenceCommand
                $postArgs.EvidenceExit = $EvidenceExit
                $postArgs.EvidenceArtifact = $EvidenceArtifact
            }
            $msg = New-AgentChatMessage @postArgs
        }
        catch {
            Write-Error "agent-chat: $($_.Exception.Message)" -ErrorAction Continue
            exit 1
        }
        Out-Result -Object $msg -Lines @(('agent-chat: posted {0}' -f (Format-AgentChatLine $msg)), ('  file: {0}' -f $msg.path))
        exit 0
    }
    'Read' {
        # -Kind defaults to 'note' for Post; for Read it filters only when the caller named one.
        $kindFilter = if ($PSBoundParameters.ContainsKey('Kind')) { $Kind } else { '' }
        $msgs = @(Get-AgentChatMessages -Stream $Stream -AgentId $AgentId -Kind $kindFilter -Ticket $Ticket -Domain $Domain -SinceMinutes $SinceMinutes -Last $Last)
        $lines = @()
        if ($msgs.Count -eq 0) { $lines += 'agent-chat: no messages match.' }
        else { $lines += @($msgs | ForEach-Object { Format-AgentChatLine $_ }) }
        Out-Result -Object $msgs -Lines $lines
        exit 0
    }
    'Find' {
        $hasTopic = [bool]$Topic
        $hasQuery = [bool]$Query
        if ($hasTopic -and $hasQuery) {
            Write-Error 'agent-chat: Find accepts -Topic or -Query, not both.' -ErrorAction Continue
            exit 2
        }
        if (-not $hasTopic -and -not $hasQuery) {
            Write-Error 'agent-chat: Find needs -Topic or -Query (wildcards allowed).' -ErrorAction Continue
            exit 2
        }
        $effectiveTopic = if ($hasTopic) {
            $Topic
        } else {
            if ($Query -like '*[*?]*') { $Query } else { "*$Query*" }
        }
        $found = Find-AgentChatFindings -Topic $effectiveTopic -Last $Last
        $lines = @()
        foreach ($f in $found.Alive) {
            $lines += (Format-AgentChatLine $f)
            $ev = Get-AgentChatProp $f 'evidence'
            $lines += ('         evidence: {0} (exit {1}){2}  scope: {3}  expires in {4}' -f `
                [string](Get-AgentChatProp $ev 'command' '-'), [string](Get-AgentChatProp $ev 'exitCode' '-'), `
                $(if ([string](Get-AgentChatProp $ev 'artifact' '')) { ' ' + [string](Get-AgentChatProp $ev 'artifact' '') } else { '' }), `
                (@(Get-AgentChatProp $f 'scope' @()) -join ', '), `
                (Format-AgentChatAge ((([DateTime]::Parse([string](Get-AgentChatProp $f 'expiresAt' ''), [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal)) - [DateTime]::UtcNow).TotalMinutes)))
        }
        if ($found.Alive.Count -eq 0) { $lines += ('agent-chat: no alive finding for {0}' -f $effectiveTopic) }
        $deadParts = @()
        if ($found.DeadFindings) {
            [int]$exp = 0; [int]$scope = 0; [int]$dev = 0; [int]$unreadable = 0
            foreach ($df in $found.DeadFindings) {
                $reason = [string]$df.Reason
                if ($reason -eq 'expired' -or $reason -like 'unreadable*') { $exp++ }
                elseif ($reason -like 'scope changed*' -or $reason -like 'scope path gone*') { $scope++ }
                elseif ($reason -like 'device not listed*' -or $reason -like 'adb not found*') { $dev++ }
                else { $unreadable++ }
            }
            if ($exp -gt 0) { $deadParts += "expired: $exp" }
            if ($scope -gt 0) { $deadParts += "scope changed: $scope" }
            if ($dev -gt 0) { $deadParts += "device gone: $dev" }
            if ($unreadable -gt 0) { $deadParts += "unreadable: $unreadable" }
        }
        $deadBreakdown = if ($deadParts.Count -gt 0) { " (" + ($deadParts -join ', ') + ")" } else { "" }
        $lines += ('agent-chat: {0} alive, {1} dead{2}' -f $found.Alive.Count, $found.Dead, $deadBreakdown)
        Out-Result -Object $found -Lines $lines
        exit 0
    }
    'Status' {
        $rows = @(Get-AgentChatStatus)
        $w = Get-AgentChatWindows
        $lines = @()
        if ($rows.Count -eq 0) { $lines += ('agent-chat: nobody has written in the last {0} min.' -f $w.ProgressRetentionMinutes) }
        foreach ($r in $rows) {
            $flag = if ($r.silent) { 'SILENT' } else { 'live' }
            $where = if ($r.ticket -and $r.phase) { "$($r.ticket)/$($r.phase)" } elseif ($r.ticket) { $r.ticket } else { '-' }
            $lines += ('{0,-6} {1,5}  {2,-22} {3}  {4}/{5} instance {6}  {7,-9} {8,-12} {9}' -f $flag, (Format-AgentChatAge $r.ageMinutes), $r.name, $r.id, $r.runtime, $r.model, $r.instance, $r.kind, $where, $r.note)
        }
        Out-Result -Object $rows -Lines $lines
        exit 0
    }
    'Whoami' {
        $me = Get-AgentIdentity
        Out-Result -Object $me -Lines @(('agent-chat: you are {0}' -f (Format-AgentIdentity $me)))
        exit 0
    }
    'Sweep' {
        $removed = Invoke-AgentChatSweep
        Out-Result -Object ([pscustomobject]@{ removed = $removed }) -Lines @(('agent-chat: sweep removed {0} file(s).' -f $removed))
        exit 0
    }
}
