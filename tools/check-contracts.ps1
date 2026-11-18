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
  CTR-PROP    every PROPOSAL-*.md carries the status line of RULES.md section 7; the open ones are listed
  CTR-STALE   how many adoption rows are still unverified (informational)
  CTR-LAG     how many adoption rows are behind their contract, from tools/contract-lag.ps1 (informational)
  CTR-NOTE    how many adoption rows carry a Notes cell above the size the registry states (informational)

Exit codes: 0 = clean; 1 = violations found; 2 = internal error.

Usage:
  pwsh -File tools/check-contracts.ps1
  pwsh -File tools/check-contracts.ps1 -CatalogRoot P:\Contracts -Strict
  pwsh -File tools/check-contracts.ps1 -Json | ConvertFrom-Json
  pwsh -File tools/check-contracts.ps1 -Render

-Render writes instead of checking: the version and the status of every README header block go into REGISTRY.md
section 1 (two cells per row, in place, never a lower version) and the root README table gets the Id cell of each
row and one new row per domain that has none. Exit 0, or 1 when a row was refused. Copy REGISTRY.md aside first.
#>
[CmdletBinding()]
param(
    [string]$CatalogRoot,
    [switch]$Strict,
    [switch]$Json,
    [switch]$Render
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

    # ------------------------------------------------------------------ -Render

    # The header block in a domain README is the one writer of a contract's version and status (RULES.md
    # section 4). -Render copies both into REGISTRY.md section 1 and keeps the root README table complete,
    # then exits without running the checks. The registry is patched cell by cell: no line is added, removed
    # or reordered, a version is never lowered, and a row whose id has no README block is left alone.
    if ($Render) {
        . (Join-Path $PSScriptRoot 'lib/registry-tables.ps1')
        $utf8 = New-Object System.Text.UTF8Encoding($false)
        $blocks = @(Read-SzaContractBlocks $CatalogRoot)
        $byId = @{}
        foreach ($b in $blocks) {
            if ($b.version -match '^\d+\.\d+$' -and $b.status -and -not $byId.ContainsKey($b.id)) { $byId[$b.id] = $b }
        }

        $regFile = Join-Path $metaDir 'REGISTRY.md'
        $regLines = [System.IO.File]::ReadAllText($regFile) -split "`n"
        $inSection = $false; $col = $null; $regChanged = 0; $refused = 0
        $extraIds = @{}      # folder -> ids with a registry row and no README block, in registry order
        for ($i = 0; $i -lt $regLines.Count; $i++) {
            $line = $regLines[$i]
            if ($line -match '^##\s') { $inSection = $line -match '^##\s+(?:\d+\.\s*)?Contracts'; $col = $null; continue }
            if (-not $inSection -or $line -notmatch '^\s*\|') { continue }
            $raw = $line -split '(?<!\\)\|'
            $names = @($raw | ForEach-Object { ($_ -replace '[*`]', '').Trim() })
            if ($names -contains 'Id' -and $names -contains 'Folder') {
                $col = @{}
                foreach ($n in 'Id', 'Folder', 'Version', 'Status') {
                    $col[$n] = [array]::IndexOf($names, $n)
                    if ($col[$n] -lt 0) { throw "registry: missing '$n' column at line $($i + 1)" }
                }
                continue
            }
            if (-not $col -or $names[$col.Id] -notmatch '^[A-Z][A-Z0-9-]*$') { continue }
            $id = $names[$col.Id]
            if (-not $byId.ContainsKey($id)) {
                if ($raw[$col.Folder] -match '\[`([^`/]+)/`\]') {
                    $f = $Matches[1]
                    if (-not $extraIds.ContainsKey($f)) { $extraIds[$f] = New-Object System.Collections.Generic.List[string] }
                    $extraIds[$f].Add($id)
                }
                continue
            }
            $b = $byId[$id]
            $old = $raw[$col.Version].Trim()
            if ($old -match '^\d+\.\d+$' -and [version]$old -gt [version]$b.version) {
                "refused ${id}: the registry says $old, the block in $($b.domain)/README.md says $($b.version) - a render never lowers a version; correct the block"
                $refused++
                continue
            }
            if ($old -ne $b.version) { $raw[$col.Version] = " $($b.version) "; $regChanged++ }
            if ($raw[$col.Status].Trim() -ne $b.status) { $raw[$col.Status] = " $($b.status) "; $regChanged++ }
            $regLines[$i] = $raw -join '|'
        }
        if ($regChanged -gt 0) { [System.IO.File]::WriteAllText($regFile, ($regLines -join "`n"), $utf8) }

        # Root README, section "The catalog": the Id cell of every row, and one new row per domain that has none.
        # The other cells of an existing row are hand prose and are never touched.
        $rootFile = Join-Path $CatalogRoot 'README.md'
        $rootLines = [System.IO.File]::ReadAllText($rootFile) -split "`n"
        $cr = if ($rootLines[0].EndsWith("`r")) { "`r" } else { '' }
        $inSection = $false; $col = $null; $canAdd = $false; $idChanged = 0; $added = 0; $lastRow = -1; $have = @{}
        for ($i = 0; $i -lt $rootLines.Count; $i++) {
            $line = $rootLines[$i]
            if ($line -match '^##\s') { $inSection = $line -match '^##\s+The catalog\s*$'; continue }
            if (-not $inSection -or $line -notmatch '^\s*\|') { continue }
            $raw = $line -split '(?<!\\)\|'
            $names = @($raw | ForEach-Object { ($_ -replace '[*`]', '').Trim() })
            if ($names -contains 'Function' -and $names -contains 'Folder' -and $names -contains 'Id') {
                $col = @{ Folder = [array]::IndexOf($names, 'Folder'); Id = [array]::IndexOf($names, 'Id') }
                $canAdd = ($names -join '|') -eq '|Function|Folder|Id|What it decides|Who is bound|'
                continue
            }
            if (-not $col -or $raw[$col.Folder] -notmatch '\[`([^`/]+)/`\]') { continue }
            $folder = $Matches[1]; $have[$folder] = $true; $lastRow = $i
            $ids = @(@($blocks | Where-Object { $_.domain -eq $folder } | ForEach-Object id) + @($extraIds[$folder] | Where-Object { $_ }))
            if ($ids.Count -eq 0) { continue }
            $cell = ' ' + (($ids | ForEach-Object { '`' + $_ + '`' }) -join ', ') + ' '
            if ($raw[$col.Id] -ne $cell) { $raw[$col.Id] = $cell; $rootLines[$i] = $raw -join '|'; $idChanged++ }
        }
        if ($canAdd -and $lastRow -ge 0) {
            $new = foreach ($domain in @($blocks | ForEach-Object domain | Select-Object -Unique)) {
                if ($have.ContainsKey($domain)) { continue }
                $own = @($blocks | Where-Object { $_.domain -eq $domain })
                $fn, $decides = $own[0].title -split '\s+-\s+', 2
                if (-not $decides) { $decides = 'see the domain README' }
                $who = @($own | ForEach-Object consumers | Where-Object { $_ } | Select-Object -Unique) -join '; '
                $ids = (@(@($own | ForEach-Object id) + @($extraIds[$domain] | Where-Object { $_ })) | ForEach-Object { '`' + $_ + '`' }) -join ', '
                $added++
                '| **{0}** | [`{1}/`]({1}/README.md) | {2} | {3} | {4} |{5}' -f $fn, $domain, $ids, ($decides -replace '\|', '/'), ($who -replace '\|', '/'), $cr
            }
            if ($added -gt 0) {
                $tail = if ($lastRow + 1 -lt $rootLines.Count) { @($rootLines[($lastRow + 1)..($rootLines.Count - 1)]) } else { @() }
                $rootLines = @($rootLines[0..$lastRow]) + @($new) + $tail
            }
        }
        if ($idChanged -gt 0 -or $added -gt 0) { [System.IO.File]::WriteAllText($rootFile, ($rootLines -join "`n"), $utf8) }

        "render: REGISTRY.md section 1 - $regChanged cell(s) rewritten, $refused row(s) refused"
        "render: README.md catalog table - $idChanged id cell(s) rewritten, $added row(s) added"
        if ($refused -gt 0) { exit 1 }
        exit 0
    }

    # ------------------------------------------------------------------ registry

    $registryPath = Join-Path $metaDir 'REGISTRY.md'
    $registry = @{}          # id -> @{ version; status; folder; line }
    $adoptionPending = 0
    $adoptionRows = 0
    $noteCap = 300           # the size REGISTRY.md section 2 states for a Notes cell; its one copy in code
    $noteRows = 0
    $noteOver = 0
    $noteMax = 0
    $noteMaxRow = ''
    if (Test-Path -LiteralPath $registryPath) {
        . (Join-Path $PSScriptRoot 'lib/registry-tables.ps1')
        foreach ($row in Read-SzaRegistryTables $registryPath) {
            $cells = $row.cells
            switch -Regex ($row.section) {
                '^Contracts' {
                    if ($cells['Id'] -notmatch '^`([A-Z][A-Z0-9-]*)`$') { break }
                    $id = $Matches[1]
                    $folder = ''
                    if ($cells['Folder'] -match '\[`([^`]+)`\]') { $folder = $Matches[1].Trim('/') }
                    $registry[$id] = [pscustomobject]@{
                        version = $cells['Version']; status = $cells['Status']; folder = $folder; line = $row.line
                    }
                }
                '^Adoption' {
                    # CTR-NOTE: the cell is found by its header name, never by position. A legacy note with an
                    # unescaped pipe is measured up to that pipe.
                    if ($cells.ContainsKey('Notes')) {
                        $noteRows++
                        $noteLength = ([string]$cells['Notes']).Length
                        if ($noteLength -gt $noteCap) { $noteOver++ }
                        if ($noteLength -gt $noteMax) {
                            $noteMax = $noteLength
                            $noteMaxRow = "$($cells['Contract']) / $($cells['Product']), line $($row.line)"
                        }
                    }
                    $ids = @([regex]::Matches($cells['Contract'], '`([A-Z][A-Z0-9-]*)`') |
                        ForEach-Object { $_.Groups[1].Value })
                    foreach ($id in $ids) {
                        $adoptionRows++
                        if ($cells['Verified'] -eq 'pending') { $adoptionPending++ }
                        if (-not $registry.ContainsKey($id)) {
                            Add-Finding -Id 'CTR-REG' -Severity 'error' -Path '_meta/REGISTRY.md' -Line $row.line `
                                -Message "adoption row for '$id', which has no contract row"
                        }
                    }
                }
            }
            # No expiry check: nothing in the catalog expires (owner decision, 2026-11-16, RULES.md section 7).
            # The exceptions table keeps its Until column only for the readers in products that still parse it.
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
                        -Message "version $($kv['version']) here, $($row.version) in the registry - the block is the writer: run check-contracts.ps1 -Render, or correct the block if the registry is right"
                }
                if ($kv['status'] -and $row.status -ne $kv['status']) {
                    Add-Finding -Id 'CTR-REG' -Severity 'error' -Path "$($domain.Name)/README.md" -Line $lineNo `
                        -Message "status $($kv['status']) here, $($row.status) in the registry - the block is the writer: run check-contracts.ps1 -Render, or correct the block if the registry is right"
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
    $proposals = New-Object System.Collections.Generic.List[object]   # CTR-PROP: one record per PROPOSAL-*.md
    $openProposals = New-Object System.Collections.Generic.List[string]
    foreach ($doc in $docs) {
        $rel = Get-RelativePath $doc.FullName
        # CTR-PROP rides on this loop: each file is read once, for its links and for its status line.
        $prop = $null
        if ($doc.Name -like 'PROPOSAL-*.md') {
            $prop = [pscustomobject]@{ rel = $rel; status = ''; line = 0; decided = $false; aboveH2 = $true }
            $proposals.Add($prop)
        }
        $lineNo = 0
        foreach ($line in (Get-Content -LiteralPath $doc.FullName)) {
            $lineNo++
            if ($prop) {
                if ($line.StartsWith('## ', [StringComparison]::Ordinal)) {
                    $prop.aboveH2 = $false
                    if ($line -match '^## Decision \(?\d{4}-\d{2}-\d{2}') { $prop.decided = $true }
                }
                elseif ($prop.aboveH2 -and -not $prop.status -and $line.StartsWith('**Status:** ', [StringComparison]::Ordinal)) {
                    $prop.status = $line; $prop.line = $lineNo
                }
                elseif ($line.StartsWith('> **Current decision:', [StringComparison]::Ordinal)) { $prop.decided = $true }
            }
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

    # ------------------------------------------------------------------ CTR-PROP

    foreach ($prop in $proposals) {
        if (-not $prop.status) {
            Add-Finding -Id 'CTR-PROP' -Severity 'error' -Path $prop.rel -Message "no status line - a line beginning '**Status:** ' must stand above the first '## ' heading, e.g. '**Status:** proposed' under the title (_meta/RULES.md section 7)"
        }
        elseif ($prop.status -cmatch '^\*\*Status:\*\* (proposed|accepted|partly accepted|answered|rejected|withdrawn)\b') {
            $word = $Matches[1]
            if ($word -eq 'proposed') {
                if ($prop.decided) {
                    Add-Finding -Id 'CTR-PROP' -Severity 'error' -Path $prop.rel -Line $prop.line -Message "status line reads 'proposed' but the file records a decision - put the decided status line above it"
                }
                else { $openProposals.Add($prop.rel) }
            }
            elseif ($prop.status -notmatch '\d{4}-\d{2}-\d{2}') {
                Add-Finding -Id 'CTR-PROP' -Severity 'error' -Path $prop.rel -Line $prop.line -Message "status '$word' carries no date (YYYY-MM-DD) on its line"
            }
        }
        else {
            Add-Finding -Id 'CTR-PROP' -Severity 'error' -Path $prop.rel -Line $prop.line -Message 'status line does not open with one of (lower case): proposed, accepted, partly accepted, answered, rejected, withdrawn'
        }
    }
    if ($openProposals.Count -gt 0) {
        Add-Finding -Id 'CTR-PROP' -Severity 'warn' -Path '_meta/RULES.md' -Message ("$($openProposals.Count) open proposal(s) await a decision: " + ($openProposals -join ', '))
    }

    # ------------------------------------------------------------------ report

    if ($adoptionRows -gt 0 -and $adoptionPending -gt 0) {
        Add-Finding -Id 'CTR-STALE' -Severity 'warn' -Path '_meta/REGISTRY.md' `
            -Message "$adoptionPending of $adoptionRows adoption rows are still unverified"
    }

    # CTR-NOTE is informational like CTR-STALE: one line for the whole table, never one per row.
    if ($noteOver -gt 0) {
        Add-Finding -Id 'CTR-NOTE' -Severity 'warn' -Path '_meta/REGISTRY.md' `
            -Message ("$noteOver of $noteRows adoption rows carry a Notes cell above $noteCap characters " +
                      "(largest: $noteMaxRow, $noteMax characters) - a row carries a one-line note, the evidence belongs in the product's own records")
    }

    # CTR-LAG is informational like CTR-STALE: a product behind a contract is a spec to write, not a broken
    # catalog. The numbers come from contract-lag.ps1, the one program that reads the adoption cells.
    $lagScript = Join-Path $PSScriptRoot 'contract-lag.ps1'
    if (Test-Path -LiteralPath $lagScript) {
        $lagJson = & pwsh -NoProfile -File $lagScript -CatalogRoot $CatalogRoot -Json 2>$null
        if ($LASTEXITCODE -eq 0 -and $lagJson) {
            $lag = ($lagJson -join "`n") | ConvertFrom-Json
            # A row is behind when its version is below the contract's: the plain `behind` rows and the `partial`
            # rows that name an older version. A `partial` row at the current version is a gap inside the current
            # contract, not a lag, and is counted on its own: on 2026-11-18 the old sum read 325, of which 183 rows named an
            # older version and 142 were partial at the current one.
            $lagRows = @($lag.rows | Where-Object { $_.state -eq 'behind' -or ($_.state -eq 'partial' -and $_.synced -ne $_.current) })
            $partialAtCurrent = @($lag.rows | Where-Object { $_.state -eq 'partial' -and $_.synced -eq $_.current }).Count
            $behindCount = $lagRows.Count
            # `unread` rows (clarifications only) are informational: they are named, and alone they raise nothing.
            $breakingCount = @($lagRows | Where-Object { $_.lag -eq 'breaking' }).Count
            $unreadCount = @($lag.rows | Where-Object { $_.state -eq 'unread' }).Count
            if ($behindCount -gt 0 -or $partialAtCurrent -gt 0 -or [int]$lag.counts.unparsed -gt 0) {
                $products = @($lagRows | ForEach-Object { if ($_.key) { $_.key } else { $_.product -replace '\s*\(.*$', '' } } | Sort-Object -Unique).Count
                $noKey = if ($lag.keysKnown) { @($lag.rows | Where-Object { -not $_.key }).Count } else { 0 }
                $noKeyText = if ($noKey -gt 0) { "; $noKey rows name no repository key" } else { '' }
                Add-Finding -Id 'CTR-LAG' -Severity 'warn' -Path '_meta/REGISTRY.md' `
                    -Message ("$behindCount adoption rows are behind their contract ($breakingCount by a breaking change; $products products), $unreadCount unread (clarifications only, nothing owed), $partialAtCurrent partial at the current version, $($lag.counts.unparsed) unreadable - " +
                              "run tools/contract-lag.ps1; -Product <repository key> -EmitSpec writes the sync spec$noKeyText")
            }
        }
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
        "proposals: $($proposals.Count) file(s), $($openProposals.Count) open"
        "result: $($errors.Count) error(s), $($warns.Count) warning(s)"
    }

    if (@($findings | Where-Object severity -eq 'error').Count -gt 0) { exit 1 }
    exit 0
}
catch {
    Write-Error "check-contracts: $_" -ErrorAction Continue
    exit 2
}
