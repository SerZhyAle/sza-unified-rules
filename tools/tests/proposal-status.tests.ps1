<#
.SYNOPSIS
    Fast tests for CTR-PROP of tools/check-contracts.ps1 (S0121), the status line of a PROPOSAL-*.md:
    an open proposal is named in one warning; a decided line above the title passes; a missing line, a word
    in capitals, a decided word without a date and `proposed` over a dated Decision heading are errors; a
    file that is not a proposal is not read. One throwaway catalog under the system temp folder and ONE
    call of the gate with -Json; its findings about the rest of that bare catalog are ignored.
    Takes -KeepScratch. #>
[CmdletBinding()]
param([switch]$KeepScratch)
$ErrorActionPreference = 'Stop'
$gate = Join-Path (Split-Path $PSScriptRoot -Parent) 'check-contracts.ps1'
$run = 0; $failed = 0
function Assert-That([bool]$Condition, [string]$Reason) { if (-not $Condition) { throw $Reason } }
function Test-Case([string]$Name, [scriptblock]$Body) {
    $script:run++
    try { & $Body; "PASS  $Name" } catch { $script:failed++; "FAIL  $Name - $($_.Exception.Message)" }
}
$scratch = Join-Path ([System.IO.Path]::GetTempPath()) ('ctr-prop-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path (Join-Path $scratch '_meta'), (Join-Path $scratch 'dom') | Out-Null
$files = [ordered]@{
    'PROPOSAL-2026-01-01-open.md'    = "# T`n`n**Status:** proposed`n`n## Finding`n`ntext"
    'PROPOSAL-2026-01-02-decided.md' = "**Status:** accepted 2026-01-03 (X 0.2)`n`n# T`n`n## Decision (2026-01-03)`n`nFolded."
    'PROPOSAL-2026-01-03-missing.md' = "# T`n`nStatus: proposed`n`n## Finding`n`n**Status:** accepted 2026-01-04"
    'PROPOSAL-2026-01-04-word.md'    = "# T`n`n**Status:** Accepted 2026-01-03"
    'PROPOSAL-2026-01-05-nodate.md'  = "# T`n`n**Status:** rejected by the owner"
    'PROPOSAL-2026-01-06-stale.md'   = "# T`n`n**Status:** proposed`n`n## Decision (2026-01-07)`n`nFolded."
    'NOTES.md'                       = "# T`n`n**Status:** nonsense"
}
foreach ($name in $files.Keys) { Set-Content -LiteralPath (Join-Path $scratch "dom/$name") -Value $files[$name] -Encoding utf8 }
try {
    $raw = & pwsh -NoProfile -File $gate -CatalogRoot $scratch -Json | Out-String
    $prop = @($raw | ConvertFrom-Json | Where-Object id -eq 'CTR-PROP')
    $errorsFor = { param($Name) @($prop | Where-Object { $_.severity -eq 'error' -and $_.path -like "*$Name" }).Count }
    Test-Case 'an open proposal is named in one warning and is no error' {
        $warn = @($prop | Where-Object severity -eq 'warn')
        Assert-That ($warn.Count -eq 1 -and $warn[0].message -match '^1 open proposal' -and $warn[0].message -match 'PROPOSAL-2026-01-01-open\.md') $raw
        Assert-That ((& $errorsFor 'open.md') -eq 0) 'the open proposal is an error'
    }
    Test-Case 'a decided line above the title passes' { Assert-That ((& $errorsFor 'decided.md') -eq 0) $raw }
    Test-Case 'no status line above the first heading is an error' { Assert-That ((& $errorsFor 'missing.md') -eq 1) $raw }
    Test-Case 'a word in capitals is an error' { Assert-That ((& $errorsFor 'word.md') -eq 1) $raw }
    Test-Case 'a decided word without a date is an error' { Assert-That ((& $errorsFor 'nodate.md') -eq 1) $raw }
    Test-Case 'proposed over a dated Decision heading is an error' { Assert-That ((& $errorsFor 'stale.md') -eq 1) $raw }
    Test-Case 'a file that is not a proposal is not read' { Assert-That ((& $errorsFor 'NOTES.md') -eq 0) $raw }
}
finally { if (-not $KeepScratch) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue } }
"proposal-status: $run case(s), $failed failed"
if ($failed -gt 0) { exit 1 }
exit 0
