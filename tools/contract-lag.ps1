<#
contract-lag.ps1 - which product is synchronized with which version of a shared contract, and the spec that
brings a lagging one up to date.

The ledger is the catalog's own registry (_meta/REGISTRY.md, section 2 "Adoption"); nothing is stored here.
For every adoption row the program compares the version the product is synchronized with - `Implements`,
or `Reads` for a pure consumer - against the contract's current version (the header block in the domain README, or registry section 1 for an id that has no block), and reports one state:

  current    the product is on the contract's version
  behind     lower than the contract's version, and a breaking or an additive log entry lies in between
             (the row's `lag` field says which: breaking, additive)
  unread     lower than the contract's version, and only clarifications or corrections lie in between -
             informational: no spec section, no ticket; the row may advance on a read (lag: clarification)
  ahead      higher than the contract's version (a typo, or a version not yet published)
  partial    the cell says `partial <version>`
  pending    `Verified` is `pending` - nobody has confirmed the row since the catalog took this shape
  n/a        `Implements` and `Reads` are both `-`
  unparsed   the cell is not one version; the owning project normalizes it (REGISTRY section 2)

With -Product <key> -EmitSpec the program writes the synchronization spec for the repository whose Product cells
start with that key (REGISTRY section 2). A value that no row carries as its key is matched by text against the
rows that carry no key yet, as before, and the output says so. Per contract, the spec lists
the document-log entries between the product's version and the current one,
each with its kind and what it obliges, and the definition of done. The spec is handed to that product's own
session; this program never edits a registry row or another repository.

Exit codes: 0 = report written; 1 = -FailOnLag and at least one row is behind; 2 = internal error, or -Product matched no row.

Usage:
  pwsh -File tools/contract-lag.ps1
  pwsh -File tools/contract-lag.ps1 -Product FileDO
  pwsh -File tools/contract-lag.ps1 -Product FileDO -EmitSpec -OutFile temp/FileDO-contract-sync.md
  pwsh -File tools/contract-lag.ps1 -Json | ConvertFrom-Json
#>
[CmdletBinding()]
param(
    [string]$CatalogRoot,
    [string]$Product,
    [string]$PortfolioRoot,
    [switch]$EmitSpec,
    [string]$OutFile,
    [switch]$Json,
    [switch]$FailOnLag
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
    if ($EmitSpec -and -not $Product) { throw '-EmitSpec needs -Product <repository key>' }

    $registryPath = Join-Path $CatalogRoot '_meta\REGISTRY.md'
    if (-not (Test-Path -LiteralPath $registryPath)) { throw "no registry at '$registryPath'" }

    # The Product cell starts with a repository key (REGISTRY section 2): a key of the portfolio registry
    # (repos.json in the portfolio root, TASK-FLOW rule 41) or the reserved `all`. That registry is machine-local;
    # where it cannot be read no cell is taken as keyed and -Product matches by text, as it always did.
    $knownKeys = @()
    try {
        if (-not $PortfolioRoot) { $PortfolioRoot = $env:SZA_PORTFOLIO_ROOT }
        if (-not $PortfolioRoot) { $PortfolioRoot = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.sza\portfolio' }
        $reposFile = Join-Path $PortfolioRoot 'repos.json'
        if (Test-Path -LiteralPath $reposFile) {
            $knownKeys = @(@((Get-Content -LiteralPath $reposFile -Raw | ConvertFrom-Json).repos) |
                ForEach-Object { [string]$_.key } | Where-Object { $_ }) + @('all')
        }
    }
    catch { $knownKeys = @() }

    # -cmatch and -ccontains on purpose: a product name such as 'FileDO' must not be read as the key 'filedo'.
    function Get-ProductKey {
        param([string]$Cell)
        if ($Cell -cmatch '^([a-z][a-z0-9-]*)(?:\s+\(.*\))?$' -and $knownKeys -ccontains $Matches[1]) { return $Matches[1] }
        return ''
    }

    function ConvertTo-Ver {
        param([string]$Text)
        $t = ($Text -replace '[*`]', '').Trim()
        if ($t -match '^\d+\.\d+(\.\d+)?$') { return [version]$t }
        return $null
    }

    # One cell of a multi-id row: a list "a / b / c" as long as the id list is read positionally, a single
    # value applies to every id. Anything else is unreadable.
    function Get-CellFor {
        param([string]$Cell, [int]$IdCount, [int]$Index)
        if ($IdCount -le 1) { return $Cell.Trim() }
        $parts = @($Cell -split '/' | ForEach-Object { $_.Trim() })
        if ($parts.Count -eq $IdCount) { return $parts[$Index] }
        if ($parts.Count -eq 1) { return $parts[0] }
        return '?'
    }

    # ------------------------------------------------------------------ registry

    $contracts = @{}
    $rows = New-Object System.Collections.Generic.List[object]
    . (Join-Path $PSScriptRoot 'lib/registry-tables.ps1')
    foreach ($row in Read-SzaRegistryTables $registryPath) {
        $cells = $row.cells
        if ($row.section -like 'Contracts*') {
            if ($cells['Id'] -notmatch '^`([A-Z][A-Z0-9-]*)`$') { continue }
            $id = $Matches[1]
            $folder = ''
            if ($cells['Folder'] -match '\[`([^`]+)`\]') { $folder = $Matches[1].Trim('/') }
            $contracts[$id] = [pscustomobject]@{
                version = $cells['Version']; status = $cells['Status']; folder = $folder
            }
        }
        elseif ($row.section -like 'Adoption*') {
            $ids = @([regex]::Matches($cells['Contract'], '`([A-Z][A-Z0-9-]*)`') |
                ForEach-Object { $_.Groups[1].Value })
            for ($k = 0; $k -lt $ids.Count; $k++) {
                $rows.Add([pscustomobject]@{
                    contract = $ids[$k]; product = $cells['Product']; role = $cells['Role']
                    implCell = (Get-CellFor $cells['Implements'] $ids.Count $k)
                    readsCell = (Get-CellFor $cells['Reads'] $ids.Count $k)
                    verified = $cells['Verified']; multiId = ($ids.Count -gt 1); line = $row.line
                })
            }
        }
    }

    # The header block in the domain README is the one writer of a contract's version and status (RULES.md
    # section 4); registry section 1 is its mirror and may lag. A block wins over the registry row, and the
    # row is kept only for an id that has no README block.
    foreach ($b in Read-SzaContractBlocks $CatalogRoot) {
        if ($b.version -notmatch '^\d+\.\d+$') { continue }
        $contracts[$b.id] = [pscustomobject]@{ version = $b.version; status = $b.status; folder = $b.domain }
    }

    # ------------------------------------------------------------------ states

    $result = foreach ($r in $rows) {
        $c = $contracts[$r.contract]
        $curVer = if ($c) { ConvertTo-Ver $c.version } else { $null }
        $isPartial = $r.implCell -match '^partial\s+(.+)$'
        $implVer = if ($isPartial) { ConvertTo-Ver $Matches[1] } else { ConvertTo-Ver $r.implCell }
        $readsVer = ConvertTo-Ver $r.readsCell
        $implNone = $r.implCell -in @('', '-')
        $readsNone = $r.readsCell -in @('', '-')
        $synced = if ($implVer) { $implVer } elseif ($implNone) { $readsVer } else { $null }

        $state = if (-not $c -or -not $curVer) { 'unparsed' }
                 elseif ($r.verified -eq 'pending') { 'pending' }
                 elseif ($isPartial -and $implVer) { 'partial' }
                 elseif ($implNone -and $readsNone) { 'n/a' }
                 elseif (-not $synced) { 'unparsed' }
                 elseif ($synced -lt $curVer) { 'behind' }
                 elseif ($synced -gt $curVer) { 'ahead' }
                 else { 'current' }

        [pscustomobject]@{
            contract = $r.contract; product = $r.product; key = (Get-ProductKey $r.product); role = $r.role
            synced = if ($synced) { $synced.ToString() } else { '' }
            current = if ($curVer) { $curVer.ToString() } else { '' }
            state = $state; lag = ''; verified = $r.verified; multiId = $r.multiId; line = $r.line
            raw = if ($implNone) { $r.readsCell } else { $r.implCell }
        }
    }
    $result = @($result)
    $matchedBy = 'all'
    if ($Product) {
        $carried = @($result | ForEach-Object key | Where-Object { $_ } | Sort-Object -Unique)
        $byKey = @($result | Where-Object { $_.key -and $_.key -ceq $Product })
        if ($byKey.Count -gt 0) { $result = $byKey; $matchedBy = 'key' }
        else {
            # Not a key any row carries: the text match this program always had, over the rows that carry no key
            # yet, so a caller that still passes a product's name gets the rows it always got.
            $result = @($result | Where-Object { -not $_.key -and $_.product -like "*$Product*" })
            $matchedBy = 'text'
        }
        if ($result.Count -eq 0) {
            throw ("no adoption row matches -Product '$Product'. Pass the repository key its rows start with (REGISTRY " +
                "section 2), or the product's name while its rows still carry the name. Keys the rows carry: " +
                $(if ($carried) { $carried -join ', ' } else { 'none' }))
        }
    }
    $textNote = ($matchedBy -eq 'text' -and $knownKeys.Count -gt 0)

    # ------------------------------------------------------------------ the spec

    function Get-DocLog {
        param([string]$Folder)
        if (-not $script:docLogCache) { $script:docLogCache = @{} }
        if ($script:docLogCache.ContainsKey($Folder)) { return $script:docLogCache[$Folder] }
        $readme = Join-Path (Join-Path $CatalogRoot $Folder) 'README.md'
        $entries = New-Object System.Collections.Generic.List[object]
        if (-not (Test-Path -LiteralPath $readme)) { return @() }
        $inLog = $false
        foreach ($l in (Get-Content -LiteralPath $readme)) {
            if ($l -match '^\|\s*Date\s*\|\s*Version\s*\|\s*Kind\s*\|') { $inLog = $true; continue }
            if (-not $inLog) { continue }
            if ($l -notmatch '^\|') { $inLog = $false; continue }
            if ($l -match '^\|\s*-+') { continue }
            # The date cell may carry a suffix after the date ('2026-11-15, owner order'): 61 of 499 log rows did on
            # 2026-11-18, and a reader that wanted a bare date dropped them, so the spec said "no entry between these
            # versions" for the fastest-moving contracts. Log rows are append-only, so the reader tolerates the cell.
            if ($l -match '^\|\s*(\d{4}-\d{2}-\d{2})[^|]*\|\s*([^|]*?)\s*\|\s*([^|]*?)\s*\|\s*(.*?)\s*\|?\s*$') {
                $entries.Add([pscustomobject]@{
                    date = $Matches[1]; version = $Matches[2]; kind = $Matches[3]; what = $Matches[4]
                })
            }
        }
        $script:docLogCache[$Folder] = $entries.ToArray()
        return $script:docLogCache[$Folder]
    }

    function Test-EntryFor {
        param($Entry, [string]$Id, [version]$From, [version]$To)
        $tokens = @([regex]::Matches($Entry.version, '\d+\.\d+(\.\d+)?') | ForEach-Object { [version]$_.Value })
        if ($tokens.Count -eq 0) { return $false }
        $named = @([regex]::Matches($Entry.version, '\b[A-Z][A-Z0-9-]{2,}\b') |
                   ForEach-Object Value | Where-Object { $contracts.ContainsKey($_) })
        if ($named.Count -gt 0 -and $named -notcontains $Id) { return $false }
        foreach ($t in $tokens) { if ($t -gt $From -and $t -le $To) { return $true } }
        return $false
    }

    function Get-KindClass {
        param([string]$Kind)
        # The Kind cell is free text in practice (49 distinct spellings on 2026-11-18: 'additive + breaking (draft)',
        # 'minor (clarification)', 'format (draft move; major ..)'), so each word is looked for anywhere in the cell and
        # the strictest reading wins. Only a kind that names a clarification, a correction, an editorial change or a
        # consolidation is read-only; a bare 'minor', '-' and any other spelling has unknown content and is reviewed.
        $k = $Kind.Trim().ToLower()
        if ($k -match '(?<!non-|not |no )breaking|(?<!no )\bmajor\b|^format\b') { return 'breaking' }
        if ($k -match 'additive|addition|amendment|artifact|adoption') { return 'additive' }
        if ($k -match 'clarification|correcti|editorial|consolidation') { return 'clarification' }
        return 'additive'
    }

    function Get-Owed {
        param([string]$Kind)
        switch (Get-KindClass $Kind) {
            'breaking' { return 'MUST adapt or declare a justified scoped exception - the older implementation disagrees with this contract' }
            'additive' { return 'Review - adopt it, or record a dated exception saying why not' }
            default { return 'Read - code changes only if it relied on the older wording' }
        }
    }

    function Limit-Text {
        param([string]$Text, [int]$Max = 480)
        if ($Text.Length -le $Max) { return $Text }
        return $Text.Substring(0, $Max).TrimEnd() + ' ..'
    }

    # ------------------------------------------------------------------ lag by kind
    # A row below its contract's version is `behind` only when the change in between can bind the product: a MAJOR
    # step or a breaking entry (lag breaking), an addition, an unrecognised kind or a step the log does not explain
    # (lag additive). When every entry in between is a clarification or a correction the row is `unread`, which is
    # informational (catalog RULES section 14). A `partial` row keeps its state and gets the same `lag`.
    foreach ($row in $result) {
        if ($row.state -notin @('behind', 'partial') -or -not $row.synced) { continue }
        $from = [version]$row.synced
        $to = [version]$row.current
        if ($from -ge $to) { continue }
        $folder = $contracts[$row.contract].folder
        $classes = @()
        if ($folder) {
            $classes = @(Get-DocLog $folder | Where-Object { Test-EntryFor $_ $row.contract $from $to } |
                ForEach-Object { Get-KindClass $_.kind })
        }
        $row.lag = if ($from.Major -lt $to.Major -or $classes -contains 'breaking') { 'breaking' }
                   elseif ($classes.Count -eq 0 -or $classes -contains 'additive') { 'additive' }
                   else { 'clarification' }
        if ($row.state -eq 'behind' -and $row.lag -eq 'clarification') { $row.state = 'unread' }
    }

    function New-Spec {
        param($Rows)
        $today = Get-Date -Format 'yyyy-MM-dd'
        $names = @($Rows | ForEach-Object product | Sort-Object -Unique)
        $sb = New-Object System.Text.StringBuilder
        $null = $sb.AppendLine("# Contract synchronization spec - $Product")
        $null = $sb.AppendLine()
        $null = $sb.AppendLine("Generated $today by tools/contract-lag.ps1 from the registry and the contracts' document logs.")
        $null = $sb.AppendLine('For the project session that owns the product: it files this as its own ticket, edits its own registry')
        $null = $sb.AppendLine('rows and its own code, and nobody does either on its behalf. Surfaces covered: ' + ($names -join '; ') + '.')
        if ($textNote) {
            $null = $sb.AppendLine()
            $null = $sb.AppendLine("Selected by text: '$Product' is not a repository key that any row carries, so a row of this product")
            $null = $sb.AppendLine('spelled differently is not here. REGISTRY section 2 states the key the Product cell starts with.')
        }
        $null = $sb.AppendLine()
        $null = $sb.AppendLine('The log entries below are matched by version and by the contract ids a row names; a row that names none is')
        $null = $sb.AppendLine('shown for every contract in its domain. Treat each list as a map, not as the whole change.')
        $null = $sb.AppendLine()

        $behind = @($Rows | Where-Object { $_.state -in 'behind', 'partial' })
        $pending = @($Rows | Where-Object { $_.state -eq 'pending' })
        $unparsed = @($Rows | Where-Object { $_.state -eq 'unparsed' })
        $unread = @($Rows | Where-Object { $_.state -eq 'unread' })

        $null = $sb.AppendLine('## What is owed')
        $null = $sb.AppendLine()
        if ($behind.Count -eq 0) {
            $null = $sb.AppendLine('No behind or partial rows were found. Pending, unreadable, ahead and not-applicable rows still require the inventory below.')
        }
        else {
            $null = $sb.AppendLine('| Contract | Surface | Synchronized with | Current | State | Verified |')
            $null = $sb.AppendLine('| --- | --- | --- | --- | --- | --- |')
            foreach ($b in ($behind | Sort-Object contract, product)) {
                $stateText = if ($b.lag) { '{0} ({1})' -f $b.state, $b.lag } else { $b.state }
                $null = $sb.AppendLine(('| `{0}` | {1} | {2} | {3} | {4} | {5} |' -f $b.contract, $b.product, $b.synced, $b.current, $stateText, $b.verified))
            }
        }
        $null = $sb.AppendLine()

        # A partial row already at the current version has no log range to show: it gets one line in the list below
        # instead of an empty 'X to X' section with a "no entry" notice (142 of 245 partial rows on 2026-11-18).
        $partialAtCurrent = @($behind | Where-Object { $_.state -eq 'partial' -and $_.synced -and $_.synced -eq $_.current })
        foreach ($b in ($behind | Sort-Object contract, product)) {
            if ($partialAtCurrent -contains $b) { continue }
            $c = $contracts[$b.contract]
            $null = $sb.AppendLine(('## `{0}` - {1} to {2}  ({3})' -f $b.contract, $b.synced, $b.current, $b.product))
            $null = $sb.AppendLine()
            $null = $sb.AppendLine(('Home: domain `{0}/`, status {1}. Read the domain README at the current version, then the documents it names.' -f $c.folder, $c.status))
            $null = $sb.AppendLine()
            $from = [version]$b.synced
            $to = [version]$b.current
            $hits = @(Get-DocLog $c.folder | Where-Object { Test-EntryFor $_ $b.contract $from $to })
            if ($hits.Count -eq 0) {
                $null = $sb.AppendLine('The document log has no entry between these versions that names this contract; read the contract against')
                $null = $sb.AppendLine('the product and say so in the registry note. The log is the only history the program can read.')
            }
            else {
                $null = $sb.AppendLine('| Date | Version | Kind | What changed | Owed |')
                $null = $sb.AppendLine('| --- | --- | --- | --- | --- |')
                foreach ($h in $hits) {
                    $what = (Limit-Text $h.what) -replace '\|', '/'
                    $null = $sb.AppendLine(('| {0} | {1} | {2} | {3} | {4} |' -f $h.date, $h.version, $h.kind, $what, (Get-Owed $h.kind)))
                }
            }
            if ($b.state -eq 'partial') {
                $null = $sb.AppendLine()
                $null = $sb.AppendLine('The row says `partial`: close the gap, or list each missing rule as a dated exception.')
            }
            $null = $sb.AppendLine()
        }

        if ($partialAtCurrent.Count -gt 0) {
            $null = $sb.AppendLine('## Partial at the current version')
            $null = $sb.AppendLine()
            $null = $sb.AppendLine('These rows say `partial` at the contract''s current version, so no log range applies: close the gap, or list')
            $null = $sb.AppendLine('each missing rule as a dated exception.')
            $null = $sb.AppendLine()
            foreach ($p in ($partialAtCurrent | Sort-Object contract, product)) {
                $null = $sb.AppendLine(('- `{0}` ({1}), partial {2}' -f $p.contract, $p.product, $p.current))
            }
            $null = $sb.AppendLine()
        }

        if ($unread.Count -gt 0) {
            $null = $sb.AppendLine('## Unread clarifications (informational)')
            $null = $sb.AppendLine()
            $null = $sb.AppendLine('Only clarifications and corrections lie between these versions. Nothing is owed and no ticket is opened:')
            $null = $sb.AppendLine('read the log entries when convenient; the row may then move to the current version with a fresh date.')
            $null = $sb.AppendLine()
            foreach ($u in ($unread | Sort-Object contract, product)) {
                $null = $sb.AppendLine(('- `{0}` ({1}), {2} to {3}' -f $u.contract, $u.product, $u.synced, $u.current))
            }
            $null = $sb.AppendLine()
        }

        if ($pending.Count -gt 0) {
            $null = $sb.AppendLine('## Never verified (`pending`)')
            $null = $sb.AppendLine()
            $null = $sb.AppendLine('Nobody has read these contracts against the product since the catalog took its shape. Read each at its')
            $null = $sb.AppendLine('current version and fill the row; there is no log range to show because no starting version is recorded.')
            $null = $sb.AppendLine()
            foreach ($p in ($pending | Sort-Object contract, product)) {
                $null = $sb.AppendLine(('- `{0}` ({1}), current {2}' -f $p.contract, $p.product, $p.current))
            }
            $null = $sb.AppendLine()
        }

        if ($unparsed.Count -gt 0) {
            $null = $sb.AppendLine('## Rows the program cannot read')
            $null = $sb.AppendLine()
            $null = $sb.AppendLine('`Implements` / `Reads` must be one version, `partial <version>` or `-` (REGISTRY section 2). Move the')
            $null = $sb.AppendLine('detail into `Notes` and split multi-contract rows:')
            $null = $sb.AppendLine()
            foreach ($u in ($unparsed | Sort-Object contract, product)) {
                $null = $sb.AppendLine(('- `{0}` ({1}), registry line {2}: `{3}`' -f $u.contract, $u.product, $u.line, (Limit-Text $u.raw 60)))
            }
            $null = $sb.AppendLine()
        }

        $null = $sb.AppendLine('## Complete adoption inventory')
        $null = $sb.AppendLine()
        $null = $sb.AppendLine('Read every pointer and own adoption/exception row, including current, pending, partial, unreadable, ahead and not-applicable entries.')
        $null = $sb.AppendLine('Determine newly applicable contracts from actual surfaces; a missing row is not proof of conformity or non-applicability.')
        $null = $sb.AppendLine('Correlate existing tickets before implementation. Do not edit another product''s tree or registry claims.')
        $null = $sb.AppendLine()
        $null = $sb.AppendLine('| Contract | Surface | State | Recorded version | Current | Verified |')
        $null = $sb.AppendLine('| --- | --- | --- | --- | --- | --- |')
        foreach ($r in ($Rows | Sort-Object contract, product)) {
            $null = $sb.AppendLine(('| `{0}` | {1} | {2} | {3} | {4} | {5} |' -f $r.contract, $r.product, $r.state, $r.raw, $r.current, $r.verified))
        }
        $null = $sb.AppendLine()
        $null = $sb.AppendLine('## Definition of done')
        $null = $sb.AppendLine()
        $null = $sb.AppendLine('1. Each contract with a row owed above is read at its current version and cited by id and section, never by catalog path; an `unread` row owes nothing.')
        $null = $sb.AppendLine('2. The implementation matches it, or the project declares a justified exception in its own REGISTRY section 3 row')
        $null = $sb.AppendLine('   without prior owner approval: clause, scope, evidence, impact, compensating behavior and review condition.')
        $null = $sb.AppendLine('   Name the responsible project. These rights apply to mandatory, active and draft contracts; no unconditional compliance claim is required.')
        $null = $sb.AppendLine('   Temporary debt has a remediation ticket and no end date; a permanent supported variant has a linked design record.')
        $null = $sb.AppendLine('3. The product''s own suite runs the catalog''s conformance vectors at the current version; the command and')
        $null = $sb.AppendLine('   its exit code are cited.')
        $null = $sb.AppendLine('4. The product''s own rows in REGISTRY section 2 carry `Implements`, `Reads`, `Verified` (today) and a one-line')
        $null = $sb.AppendLine('   note, in the cell format of that section, one contract id per row.')
        $null = $sb.AppendLine('5. Each `docs/contracts/<ID>.md` pointer names the current version.')
        $null = $sb.AppendLine('6. The project may recommend corrections and additions at any point. It amends contracts it owns; for another owner,')
        $null = $sb.AppendLine('   it files `PROPOSAL-<date>-<topic>.md` with evidence and compatibility consequences, retaining an exception where needed.')
        $null = $sb.AppendLine('   Only its own implementation rows advance after fresh proof; another product''s rows remain untouched.')
        $null = $sb.AppendLine('7. The final audit distinguishes proven conformance, exceptions, recommendations and unverified work.')
        $null = $sb.AppendLine('   Record missing vectors or runtime evidence explicitly; retain partial claims for unresolved gaps.')
        $null = $sb.AppendLine('   An exception does not waive independent legal, store, security or data-safety release blockers.')
        return $sb.ToString()
    }

    # ------------------------------------------------------------------ output

    $counts = [ordered]@{}
    foreach ($s in 'current', 'behind', 'unread', 'partial', 'pending', 'ahead', 'n/a', 'unparsed') {
        $counts[$s] = @($result | Where-Object { $_.state -eq $s }).Count
    }

    if ($EmitSpec) {
        $spec = New-Spec $result
        if ($OutFile) {
            $full = [System.IO.Path]::GetFullPath($OutFile, (Get-Location).Path)
            $dir = Split-Path -Parent $full
            if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
            [System.IO.File]::WriteAllText($full, $spec, (New-Object System.Text.UTF8Encoding($false)))
            Write-Output "spec written: $OutFile ($($counts['behind']) behind, $($counts['unread']) unread, $($counts['partial']) partial, $($counts['pending']) pending, $($counts['unparsed']) unparsed)"
        }
        else { Write-Output $spec }
    }
    elseif ($Json) {
        [pscustomobject]@{ catalog = $CatalogRoot; matchedBy = $matchedBy; keysKnown = ($knownKeys.Count -gt 0); counts = $counts; rows = $result } | ConvertTo-Json -Depth 4
    }
    else {
        "catalog: $CatalogRoot"
        'rows: {0}  ({1})' -f $result.Count, (($counts.GetEnumerator() | ForEach-Object { '{0} {1}' -f $_.Key, $_.Value }) -join ', ')
        ''
        $lag = @($result | Where-Object { $_.state -in 'behind', 'partial' } | Sort-Object product, contract)
        if ($lag.Count -gt 0) {
            $lag | Format-Table product, contract, state, lag, synced, current, verified -AutoSize | Out-String -Width 220
        }
        if ($textNote) { "matched by text: '$Product' is not a repository key that any row carries (REGISTRY section 2)"; '' }
        $unkeyed = @($result | Where-Object { -not $_.key })
        if ($knownKeys.Count -gt 0 -and $unkeyed.Count -gt 0) {
            "product cells that name no repository key: $(@($unkeyed | ForEach-Object product | Sort-Object -Unique).Count) cells, $($unkeyed.Count) rows"
            $unkeyed | Group-Object product | Sort-Object Name | ForEach-Object { '  {0,4}  {1}' -f $_.Count, $_.Name }
            ''
        }
        $bad = @($result | Where-Object { $_.state -eq 'unparsed' })
        if ($bad.Count -gt 0) {
            "unparsed rows (normalize in the registry): $($bad.Count)"
            $bad | Sort-Object product, contract | Select-Object -First 15 |
                Format-Table product, contract, @{ n = 'cell'; e = { Limit-Text $_.raw 40 } } -AutoSize | Out-String -Width 220
            if ($bad.Count -gt 15) { "  .. and $($bad.Count - 15) more (use -Json)" }
        }
    }

    if ($FailOnLag -and $counts['behind'] -gt 0) { exit 1 }
    exit 0
}
catch {
    [Console]::Error.WriteLine("contract-lag: $($_.Exception.Message)")
    exit 2
}
