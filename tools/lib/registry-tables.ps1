# VERSIONING section 4 rule 1: table order is never part of the reader interface.
function Read-SzaRegistryTables {
    param([string]$Path)
    $section = ''
    $headers = @()
    $lineNumber = 0
    foreach ($line in Get-Content -LiteralPath $Path) {
        $lineNumber++
        if ($line -match '^##\s+(?:\d+\.\s*)?(.+)$') {
            $section = $Matches[1].Trim()
            $headers = @()
            continue
        }
        # The catalog has continuation rows separated by prose within the same section.
        if ($line -notmatch '^\s*\|') { continue }
        $cells = @($line.Trim().Trim('|') -split '(?<!\\)\|' | ForEach-Object { $_.Trim() })
        if ($cells.Count -gt 0 -and $cells[0] -match '^:?-{3,}:?$') { continue }
        if ($headers.Count -eq 0 -or ($cells -contains 'Contract' -and $cells -contains 'Product') -or
                ($cells -contains 'Id' -and $cells -contains 'Folder')) {
            $headers = @($cells | ForEach-Object { ($_ -replace '[*`]', '').Trim() })
            if (@($headers | Sort-Object -Unique).Count -ne $headers.Count) {
                throw "registry: duplicate column header at line $lineNumber"
            }
            $required = switch -Regex ($section) {
                '^Contracts' { @('Id', 'Folder', 'Version', 'Status') }
                '^Adoption' { @('Contract', 'Product', 'Role', 'Implements', 'Reads', 'Verified') }
                '^Exceptions' { @('Contract', 'Product', 'Until') }
            }
            foreach ($name in $required) {
                if ($headers -notcontains $name) { throw "registry: missing '$name' column at line $lineNumber" }
            }
            continue
        }
        # Legacy Notes cells contain unescaped pipes. Required fields precede that prose in those rows;
        # tolerate surplus cells without treating the prose as another declaration.
        $values = @{}
        for ($i = 0; $i -lt $headers.Count; $i++) {
            $values[$headers[$i]] = if ($i -lt $cells.Count) { $cells[$i] } else { '' }
        }
        [pscustomobject]@{ section = $section; line = $lineNumber; cells = $values }
    }
}
