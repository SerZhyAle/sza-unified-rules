<#  The `source` field of a ledger row (TASK-FLOW rule 3 and its amendment "how a ticket was born"): the path that
    created the ticket. Dot-sourced, never invoked: sets no preference, holds no state, reads no profile and
    dot-sources nothing. Consumers: insert.ps1 (the one writer of the field) and validate.ps1 (the WARN on a value
    outside the list). Safe under Set-StrictMode Latest. #>
function Get-TicketSourceValues { return @('owner', 'robot', 'import', 'inbox', 'campaign') }
function Test-TicketSourceValue([string] $Value) { return (@(Get-TicketSourceValues) -ccontains $Value) }
function Resolve-TicketSource {
    <#  Strongest first: the caller's -Source; `import` for the queue sync's own child (rule 65 sets SZA_PQ_IN_SYNC for
        it, and a variable inherited from a pass must not relabel that registration); the variable SZA_TICKET_SOURCE
        that a runner or a capture path set for its child; else `owner`. A value outside the list throws, and the
        caller's trap turns that into its documented exit code. #>
    param([string] $Explicit = '')
    $value = $Explicit
    $from = '-Source'
    if (-not $value) {
        if ($env:SZA_PQ_IN_SYNC -eq '1') { return 'import' }
        $value = [string]$env:SZA_TICKET_SOURCE
        $from = 'the variable SZA_TICKET_SOURCE'
    }
    if (-not $value) { return 'owner' }
    if (-not (Test-TicketSourceValue $value)) {
        throw ("Unknown ticket source '{0}' (from {1}). Allowed: {2}." -f $value, $from, (@(Get-TicketSourceValues) -join ', '))
    }
    return $value
}
