<#
check-contracts.ps1 - gate for the shared contracts catalog.

check-rules.ps1 validates the canon's own text; check-compliance.ps1 validates a project against the
canon; this one validates the CATALOG - the contracts every project is bound by.

Checks:
  CTR-META    the governance pages exist under _meta/
  CTR-BLOCK   every domain folder has a README.md with at least one well-formed `contract` header block
  CTR-KEY     every block carries every required key, with a valid value
  CTR-REG     every block id has a registry row, with the same version and status
  CTR-FOLDER  every registry row points at a folder that exists
  CTR-LINK    relative markdown links inside the catalog resolve
  CTR-PATH    no Windows path inside markdown link parentheses (the backslashes vanish silently)
  CTR-EXPIRE  no exception row past its `until` date
  CTR-STALE   how many adoption rows are still unverified (informational)

Exit codes: 0 = clean; 1 = violations found; 2 = internal error.

Usage:
  pwsh -File tools/check-contracts.ps1
  pwsh -File tools/check-contracts.ps1 -CatalogRoot P:\Contracts -Strict
  pwsh -File tools/check-contracts.ps1 -Json | ConvertFrom-Json
#>
[CmdletBinding()]
param(
    [string]$CatalogRoot,
    [switch]$Strict,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'

try {
    if (-not $CatalogRoot) {
        $CatalogRoot = if ($env:SZA_CONTRACTS_ROOT) { $env:SZA_CONTRACTS_ROOT } else { 'P:\Contracts' }
    }
    if (-not (Test-Path -LiteralPath $CatalogRoot)) {
        throw "contracts catalog not found at '$CatalogRoot' (set -CatalogRoot or SZA_CONTRACTS_ROOT)"
    }
    $CatalogRoot = (Resolve-Path -LiteralPath $CatalogRoot).Path

    $findings = New-Object System.Collections.Generic.List[object]
    function Add-Finding {
        param(
            [Parameter(Mandatory)][string]$Id,
            [Parameter(Mandatory)][string]$Severity,
            [string]$Path = '',
            [int]$Line = 0,
            [Parameter(Mandatory)][string]$Message
        )
        $sev = if ($Strict -and $Severity -eq 'warn') { 'error' } else { $Severity }
        $findings.Add([pscustomobject]@{
            id = $Id; severity = $sev; path = $Path; line = $Line; message = $Message
        })
    }

    function Get-RelativePath {
        param([string]$Full)
        return $Full.Substring($CatalogRoot.Length).TrimStart('\', '/')
    }

    # ------------------------------------------------------------------ CTR-META

    $metaDir = Join-Path $CatalogRoot '_meta'
    $required = @('RULES.md', 'VERSIONING.md', 'REGISTRY.md', 'CONTRACT_TEMPLATE.md', 'PROJECT_PROMPT.md')
    foreach ($name in $required) {
        if (-not (Test-Path -LiteralPath (Join-Path $metaDir $name))) {
            Add-Finding -Id 'CTR-META' -Severity 'error' -Path "_meta/$name" -Message 'missing governance page'
        }
    }

    # ------------------------------------------------------------------ registry

    $registryPath = Join-Path $metaDir 'REGISTRY.md'
    $registry = @{}          # id -> @{ version; status; folder; line }
    $adoptionPending = 0
    $adoptionRows = 0
    if (Test-Path -LiteralPath $registryPath) {
        $lines = Get-Content -LiteralPath $registryPath
        $section = ''
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $line = $lines[$i]
            if ($line -match '^##\s+(\d+)\.\s*(.+)$') { $section = $Matches[2].Trim(); continue }
            if ($line -notmatch '^\|') { continue }
            $cells = @($line.Trim('|') -split '\|' | ForEach-Object { $_.Trim() })
            if ($cells.Count -lt 3) { continue }
            if ($cells[0] -match '^-+$') { continue }

            switch -Regex ($section) {
                '^Contracts' {
                    if ($cells[0] -notmatch '^`([A-Z][A-Z0-9-]*)`$') { break }
                    $id = $Matches[1]
                    $folder = ''
                    if ($cells[1] -match '\[`([^`]+)`\]') { $folder = $Matches[1].Trim('/') }
                    $registry[$id] = [pscustomobject]@{
                        version = $cells[2]; status = $cells[3]; folder = $folder; line = $i + 1
                    }
                }
                '^Adoption' {
                    if ($cells[0] -notmatch '^`([A-Z][A-Z0-9-]*)`$') { break }
                    $adoptionRows++
                    if ($cells.Count -ge 6 -and $cells[5] -eq 'pending') { $adoptionPending++ }
                    if (-not $registry.ContainsKey($Matches[1])) {
                        Add-Finding -Id 'CTR-REG' -Severity 'error' -Path '_meta/REGISTRY.md' -Line ($i + 1) `
                            -Message "adoption row for '$($Matches[1])', which has no contract row"
                    }
                }
                '^Exceptions' {
                    if ($cells.Count -lt 5) { break }
                    $until = $cells[4]
                    $parsed = [datetime]::MinValue
                    if ([datetime]::TryParse($until, [ref]$parsed) -and (Get-Date) -gt $parsed) {
                        Add-Finding -Id 'CTR-EXPIRE' -Severity 'error' -Path '_meta/REGISTRY.md' -Line ($i + 1) `
                            -Message "exception expired on $until - $($cells[0]) / $($cells[1])"
                    }
                }
            }
        }
    }

    foreach ($id in $registry.Keys) {
        $folder = $registry[$id].folder
        if (-not $folder) { continue }
        if (-not (Test-Path -LiteralPath (Join-Path $CatalogRoot $folder))) {
            Add-Finding -Id 'CTR-FOLDER' -Severity 'error' -Path '_meta/REGISTRY.md' -Line $registry[$id].line `
                -Message "contract '$id' points at '$folder', which does not exist"
        }
    }

    # ------------------------------------------------------- CTR-BLOCK / CTR-KEY

    $requiredKeys = @('id', 'version', 'status', 'owner', 'since', 'wire', 'consumers', 'artifacts')
    $validStatus = @('draft', 'active', 'deprecated', 'retired', 'record')
    $seenIds = @{}

    $domains = @(Get-ChildItem -LiteralPath $CatalogRoot -Directory |
                 Where-Object { $_.Name -ne '_meta' -and -not $_.Name.StartsWith('.') })
    foreach ($domain in $domains) {
        $readme = Join-Path $domain.FullName 'README.md'
        if (-not (Test-Path -LiteralPath $readme)) {
            Add-Finding -Id 'CTR-BLOCK' -Severity 'error' -Path "$($domain.Name)/README.md" `
                -Message 'domain folder has no README - nothing in it binds anyone'
            continue
        }
        $text = Get-Content -LiteralPath $readme -Raw
        $blocks = [regex]::Matches($text, '(?ms)^```contract\r?\n(.*?)^```')
        if ($blocks.Count -eq 0) {
            Add-Finding -Id 'CTR-BLOCK' -Severity 'error' -Path "$($domain.Name)/README.md" `
                -Message 'no contract header block (see _meta/CONTRACT_TEMPLATE.md)'
            continue
        }
        foreach ($block in $blocks) {
            $lineNo = ($text.Substring(0, $block.Index) -split "`n").Count
            $kv = @{}
            foreach ($row in ($block.Groups[1].Value -split "`r?`n")) {
                if ($row -match '^\s*([a-z]+)\s*:\s*(.+?)\s*$') { $kv[$Matches[1]] = $Matches[2] }
            }
            foreach ($key in $requiredKeys) {
                if (-not $kv.ContainsKey($key)) {
                    Add-Finding -Id 'CTR-KEY' -Severity 'error' -Path "$($domain.Name)/README.md" -Line $lineNo `
                        -Message "header block is missing '$key'"
                }
            }
            $id = $kv['id']
            if (-not $id) { continue }
            if ($id -notmatch '^[A-Z][A-Z0-9-]*$') {
                Add-Finding -Id 'CTR-KEY' -Severity 'error' -Path "$($domain.Name)/README.md" -Line $lineNo `
                    -Message "id '$id' is not UPPER-KEBAB-CASE"
            }
            if ($seenIds.ContainsKey($id)) {
                Add-Finding -Id 'CTR-KEY' -Severity 'error' -Path "$($domain.Name)/README.md" -Line $lineNo `
                    -Message "id '$id' is already used in $($seenIds[$id])"
            }
            else { $seenIds[$id] = "$($domain.Name)/README.md" }

            if ($kv['version'] -and $kv['version'] -notmatch '^\d+\.\d+$') {
                Add-Finding -Id 'CTR-KEY' -Severity 'error' -Path "$($domain.Name)/README.md" -Line $lineNo `
                    -Message "version '$($kv['version'])' is not MAJOR.MINOR"
            }
            if ($kv['status'] -and $validStatus -notcontains $kv['status']) {
                Add-Finding -Id 'CTR-KEY' -Severity 'error' -Path "$($domain.Name)/README.md" -Line $lineNo `
                    -Message "status '$($kv['status'])' is not one of: $($validStatus -join ', ')"
            }
            if ($kv['since'] -and $kv['since'] -notmatch '^\d{4}-\d{2}-\d{2}$') {
                Add-Finding -Id 'CTR-KEY' -Severity 'error' -Path "$($domain.Name)/README.md" -Line $lineNo `
                    -Message "since '$($kv['since'])' is not YYYY-MM-DD"
            }

            if (-not $registry.ContainsKey($id)) {
                Add-Finding -Id 'CTR-REG' -Severity 'error' -Path "$($domain.Name)/README.md" -Line $lineNo `
                    -Message "contract '$id' has no row in _meta/REGISTRY.md"
            }
            else {
                $row = $registry[$id]
                if ($kv['version'] -and $row.version -ne $kv['version']) {
                    Add-Finding -Id 'CTR-REG' -Severity 'error' -Path "$($domain.Name)/README.md" -Line $lineNo `
                        -Message "version $($kv['version']) here, $($row.version) in the registry"
                }
                if ($kv['status'] -and $row.status -ne $kv['status']) {
                    Add-Finding -Id 'CTR-REG' -Severity 'error' -Path "$($domain.Name)/README.md" -Line $lineNo `
                        -Message "status $($kv['status']) here, $($row.status) in the registry"
                }
            }
        }
    }

    # A registry row is declared either by a header block, or - for a supporting document that lives under
    # a domain contract - by being named in that domain's README. Anything else is a row nobody owns.
    foreach ($id in $registry.Keys) {
        if ($seenIds.ContainsKey($id)) { continue }
        $folder = $registry[$id].folder
        $named = $false
        if ($folder) {
            $readme = Join-Path (Join-Path $CatalogRoot $folder) 'README.md'
            if (Test-Path -LiteralPath $readme) {
                $named = (Get-Content -LiteralPath $readme -Raw) -match [regex]::Escape($id)
            }
        }
        if (-not $named) {
            Add-Finding -Id 'CTR-REG' -Severity 'error' -Path '_meta/REGISTRY.md' -Line $registry[$id].line `
                -Message "contract '$id' is in the registry but no domain README declares or names it"
        }
    }

    # ------------------------------------------------------- CTR-LINK / CTR-PATH

    $docs = @(Get-ChildItem -LiteralPath $CatalogRoot -Filter *.md -File -Recurse)
    foreach ($doc in $docs) {
        $rel = Get-RelativePath $doc.FullName
        $lineNo = 0
        foreach ($line in (Get-Content -LiteralPath $doc.FullName)) {
            $lineNo++
            foreach ($m in [regex]::Matches($line, '\[[^\]]*\]\(([^)\s]+)\)')) {
                $target = $m.Groups[1].Value
                if ($target -match '^(https?|mailto):' -or $target.StartsWith('#')) { continue }
                if ($target -match '^[A-Za-z]:[\\/]' -or $target -match '^[A-Za-z]:[A-Za-z]') {
                    Add-Finding -Id 'CTR-PATH' -Severity 'error' -Path $rel -Line $lineNo `
                        -Message "Windows path inside link parentheses -> $target (cite it in a code span instead)"
                    continue
                }
                $file = ($target -split '#')[0]
                if (-not $file) { continue }
                $resolved = Join-Path $doc.DirectoryName $file
                if (Test-Path -LiteralPath $resolved) { continue }
                # A link that leaves the catalog is debt the document's owner carries (RULES.md section 5
                # wants a URL or a code span instead); a broken link INSIDE the catalog is this gate's job.
                $full = ''
                try { $full = [IO.Path]::GetFullPath($resolved) } catch { $full = $resolved }
                $escapes = -not $full.StartsWith($CatalogRoot, [StringComparison]::OrdinalIgnoreCase)
                $isDoc = $file.EndsWith('/') -or $file.EndsWith('\') -or ($file -match '\.(md|json|txt|csv)$')
                if ($escapes -or -not $isDoc) {
                    Add-Finding -Id 'CTR-LINK' -Severity 'warn' -Path $rel -Line $lineNo `
                        -Message "link into a product tree -> $target (cite it in a code span or a URL)"
                }
                else {
                    Add-Finding -Id 'CTR-LINK' -Severity 'error' -Path $rel -Line $lineNo `
                        -Message "broken link -> $target"
                }
            }
        }
    }

    # ------------------------------------------------------------------ report

    if ($adoptionRows -gt 0 -and $adoptionPending -gt 0) {
        Add-Finding -Id 'CTR-STALE' -Severity 'warn' -Path '_meta/REGISTRY.md' `
            -Message "$adoptionPending of $adoptionRows adoption rows are still unverified"
    }

    if ($Json) {
        $findings | ConvertTo-Json -Depth 4
    }
    else {
        $errors = @($findings | Where-Object severity -eq 'error')
        $warns = @($findings | Where-Object severity -eq 'warn')
        foreach ($f in ($findings | Sort-Object severity, path, line)) {
            $where = if ($f.line -gt 0) { "$($f.path):$($f.line)" } else { $f.path }
            "{0,-5} {1,-11} {2} - {3}" -f $f.severity, $f.id, $where, $f.message
        }
        ''
        "catalog: $CatalogRoot"
        "contracts: $($registry.Count) in the registry, $($seenIds.Count) declared by a domain README"
        "result: $($errors.Count) error(s), $($warns.Count) warning(s)"
    }

    if (@($findings | Where-Object severity -eq 'error').Count -gt 0) { exit 1 }
    exit 0
}
catch {
    Write-Error "check-contracts: $_"
    exit 2
}
