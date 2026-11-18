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

<# RULES.md section 4: the header block in the domain README is the one writer of a contract's version and status.
   One object per block that carries a well-formed id, in folder order and then in block order. A block inside a
   long document beside the README is not read: it binds nothing. #>
function Read-SzaContractBlocks {
    param([string]$CatalogRoot)
    $domains = @(Get-ChildItem -LiteralPath $CatalogRoot -Directory |
                 Where-Object { $_.Name -ne '_meta' -and -not $_.Name.StartsWith('.') } | Sort-Object Name)
    foreach ($domain in $domains) {
        $readme = Join-Path $domain.FullName 'README.md'
        if (-not (Test-Path -LiteralPath $readme)) { continue }
        $text = Get-Content -LiteralPath $readme -Raw
        if (-not $text) { continue }
        $title = if ($text -match '(?m)^#\s+(.+?)\s*$') { $Matches[1] } else { $domain.Name }
        foreach ($block in [regex]::Matches($text, '(?ms)^```contract\r?\n(.*?)^```')) {
            $kv = @{}
            foreach ($row in ($block.Groups[1].Value -split "`r?`n")) {
                if ($row -match '^\s*([a-z]+)\s*:\s*(.+?)\s*$') { $kv[$Matches[1]] = $Matches[2] }
            }
            if ($kv['id'] -notmatch '^[A-Z][A-Z0-9-]*$') { continue }
            [pscustomobject]@{
                id = $kv['id']; version = [string]$kv['version']; status = [string]$kv['status']
                consumers = [string]$kv['consumers']; domain = $domain.Name; title = $title
            }
        }
    }
}
