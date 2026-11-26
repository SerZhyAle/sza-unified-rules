# _archive-reason.ps1 - the reason an archived ticket carries (TASK-FLOW rule 17, amended 0.52).
#
# Dot-sourced by _lib.ps1. Every path that archives a ticket through the catalog - archive.ps1, update.ps1, close.ps1,
# complete.ps1, close-and-log.ps1, bulk-update.ps1 and delete.ps1 - refuses an entry into `Archived` without one line,
# kept in `statusNote`:
#
#   duplicate of <id>                  the same task is recorded on another ticket (a local id or <repoKey>:<id>)
#   not needed: <why>                  the task is dropped
#   done in <id>                       the work landed under another ticket
#   shipped in v<version> (release N)  only while the row's own shipment history records that shipment
#
# A row already `Archived` keeps what it holds: rows written before the rule carry no reason and stay valid.

function Get-ArchiveReasonForms {
    return '`duplicate of <id>`, `not needed: <why>` or `done in <id>` (a ticket the ledger records as shipped may also say `shipped in v<version> (release <N>)`)'
}

function Test-ArchiveReason {
    # $null when the reason is acceptable for this record, else the sentence that says why not.
    param([Parameter(Mandatory)] $Record, [AllowEmptyString()][AllowNull()][string] $Reason)
    $text = "$Reason"
    if ([string]::IsNullOrWhiteSpace($text)) { return "no reason given - pass one line: $(Get-ArchiveReasonForms)" }
    if ($text -match '[\x00-\x1f]') { return 'the reason is one line, with no line break or other control character' }
    if ($text.Length -gt 300) { return "the reason is $($text.Length) characters, 300 at most" }
    if ($text -cmatch '^not needed: \S.*$') { return $null }
    if ($text -cmatch '^(?:duplicate of|done in) (?<ref>(?:[A-Za-z0-9][A-Za-z0-9_.-]*:)?[A-Za-z]{1,12}-?\d{1,9})$') {
        $ref = $Matches['ref']
        if ($ref -ieq [string]$Record.id) { return "the reason names the ticket itself ($ref)" }
        return $null
    }
    if ($text -cmatch '^shipped in v(?<version>\S+) \(release (?<release>\d+|--)\)$') {
        $version = $Matches['version']
        $release = $Matches['release']
        $proof = @(Get-RecordShipments -Record $Record | Where-Object {
                [string](Get-PlanProp $_ 'version') -ceq $version -and [string]$_.release -ceq $release })
        if ($proof.Count -gt 0) { return $null }
        return "the ledger records no shipment of this ticket in v$version (release $release)"
    }
    return "'$text' is not an archive reason - use $(Get-ArchiveReasonForms)"
}

function Assert-ArchiveReason {
    # Throw when a write into `Archived` carries no acceptable reason. An entry needs one in this call; a re-write of an
    # Archived row is judged only when it supplies a note, so a historical row without a reason is never refused.
    param(
        [Parameter(Mandatory)][string] $Id,
        [AllowEmptyString()][string] $OldStatus,
        [AllowEmptyString()][AllowNull()][string] $Reason,
        [bool] $Supplied
    )
    if ($OldStatus -eq 'Archived' -and -not $Supplied) { return }
    $record = Find-Record -Id $Id
    if ($null -eq $record) { throw "Record '$Id' not found." }
    $problem = Test-ArchiveReason -Record $record -Reason $(if ($Supplied) { $Reason })
    if ($null -ne $problem) { throw "Cannot archive '$Id': $problem." }
}
