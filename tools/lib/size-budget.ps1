# size-budget.ps1 - one budget line judged against its file (CANONR-0221). Dot-sourced by check-rules.ps1
# (the rule docs, tools/rules-size-budget.json) and check-contracts.ps1 (the catalog, _meta/SIZE_BUDGET.md).
#
# Growth needs an equal deletion in the same edit, or the budget line raised with the date and the reason.

# Bytes on disk without carriage returns, so a line-ending conversion never moves a file over its budget.
function Get-SzaBudgetSize {
    param([Parameter(Mandatory)][string]$Path)
    $text = [System.Text.Encoding]::Latin1.GetString([System.IO.File]::ReadAllBytes($Path))
    return $text.Replace("`r", '').Length
}

# Emits one string per problem of one budget line and nothing for a line its file keeps.
function Test-SzaSizeBudget {
    param(
        [Parameter(Mandatory)][string]$Path,
        [AllowEmptyString()][string]$Budget,
        [AllowEmptyString()][string]$Date,
        [AllowEmptyString()][string]$Reason,
        [Parameter(Mandatory)][string]$BudgetFile
    )
    $limit = 0L
    if (-not [long]::TryParse($Budget, [ref]$limit) -or $limit -le 0) { "budget '$Budget' is not a positive byte count" }
    $day = [datetime]::MinValue
    if (-not [datetime]::TryParseExact($Date, 'yyyy-MM-dd', [cultureinfo]::InvariantCulture, 'None', [ref]$day)) {
        "the budget line has no date (YYYY-MM-DD): '$Date'"
    }
    if (-not "$Reason".Trim()) { 'the budget line has no reason' }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { "the budget line names a file that does not exist"; return }
    if ($limit -le 0) { return }
    $size = Get-SzaBudgetSize $Path
    if ($size -gt $limit) {
        "$size bytes, budget $limit (+$($size - $limit)) - delete as much in the same edit, or raise its line in $BudgetFile with today's date and the reason"
    }
}
