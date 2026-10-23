# REPO-STAMP / HARNESS-PROFILE amendment 2026-10-23: absence always selects legacy 1.0.
function Assert-SzaSchemaCarrier {
    param($Document, [string]$Key, [string]$Contract)
    $message = "${Contract}: unsupported or malformed '$Key'; update the tooling before reading this declaration."
    if ($null -eq $Document -or ($Document -isnot [System.Collections.IDictionary] -and
            $Document.GetType() -ne [System.Management.Automation.PSCustomObject])) {
        throw $message
    }
    $present = if ($Document -is [System.Collections.IDictionary]) {
        $Document.Contains($Key)
    } else { $null -ne $Document.PSObject.Properties[$Key] }
    if (-not $present) { return }
    $value = $Document.$Key
    if ($value -isnot [string] -or $value -cnotmatch '^(0|[1-9][0-9]*)(\.(0|[1-9][0-9]*))?$') {
        throw $message
    }
    # Compare the declared major as text: arbitrarily large future components must refuse cleanly.
    if (($value -split '\.')[0] -ne '1') { throw $message }
}
