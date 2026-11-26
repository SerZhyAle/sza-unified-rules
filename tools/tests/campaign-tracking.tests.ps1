# Tracking checklist rendering, recheck results, and stale-write protection.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '../harness/portfolio/lib/campaign-tracking.ps1')

$file = [IO.Path]::GetTempFileName()
try {
    $original = "# Ticket`r`n`r`nOwner's words.`r`n"
    [IO.File]::WriteAllText($file, $original, [Text.UTF8Encoding]::new($true))
    $rows = @(
        [pscustomobject]@{key = 'alpha'; work = 'unknown'; check = 'pending'; done = 'no'}
        [pscustomobject]@{key = 'bravo'; work = 'yes'; check = 'pending'; done = 'no (bravo:S0001)'}
        [pscustomobject]@{key = 'charlie'; work = 'unknown'; check = 'pending'; done = 'no'}
    )
    Write-CampaignTable $file $rows -Create
    [IO.File]::AppendAllText($file, "`r`n## Notes`r`n`r`nKeep this.`r`n")
    $before = [IO.File]::ReadAllText($file)
    $rows = @(Read-CampaignTable $before)
    if ($rows.Count -ne 3) { throw "expected three rows, got $($rows.Count)" }
    Set-CampaignCheckResult $rows[0] 0
    Set-CampaignCheckResult $rows[1] 1
    Set-CampaignCheckResult $rows[2] 124
    Write-CampaignTable $file $rows -ExpectedBody $before
    $after = [IO.File]::ReadAllText($file)
    $rows = @(Read-CampaignTable $after)
    if ($rows[0].done -cne 'yes' -or $rows[0].check -cne 'PASS' -or $rows[0].work -cne 'no' -or
        $rows[1].done -cne 'no (bravo:S0001)' -or $rows[1].check -cne 'FAIL' -or
        $rows[2].work -cne 'unknown' -or $rows[2].check -cne 'FAIL' -or $rows[2].done -cne 'no') {
        throw "unexpected checklist:`n$after"
    }
    if (-not $after.StartsWith($original) -or -not $after.EndsWith("## Notes`r`n`r`nKeep this.`r`n") -or
        [Convert]::ToHexString([IO.File]::ReadAllBytes($file), 0, 3) -cne 'EFBBBF') {
        throw 'the update changed prose, line endings, or the BOM'
    }
    Set-CampaignCheckResult $rows[1] 0
    try { Write-CampaignTable $file $rows -ExpectedBody $before }
    catch { if ($_.Exception.Message -notlike 'The spec changed while checks ran.*') { throw } }
    if ([IO.File]::ReadAllText($file) -cne $after) { throw 'a stale recheck overwrote current rows' }
    Write-CampaignTable $file $rows -ExpectedBody $after
    $updated = @(Read-CampaignTable ([IO.File]::ReadAllText($file)))
    if ($updated[1].done -cne 'yes (bravo:S0001)') { throw 'a passing recheck lost the child reference' }
    Write-Host 'PASS: checklist round trip, PASS/FAIL/timeout, preserved prose and child, stale-write refusal'
}
finally { [IO.File]::Delete($file) }
