<#
contract-lag.ps1 - which product is synchronized with which version of a shared contract, and the spec that
brings a lagging one up to date.

The ledger is the catalog's own registry (_meta/REGISTRY.md, section 2 "Adoption"); nothing is stored here.
For every adoption row the program compares the version the product is synchronized with - `Implements`,
or `Reads` for a pure consumer - against the contract's current version (section 1), and reports one state:

  current    the product is on the contract's version
  behind     lower than the contract's version
  ahead      higher than the contract's version (a typo, or a version not yet published)
  partial    the cell says `partial <version>`
  pending    `Verified` is `pending` - nobody has confirmed the row since the catalog took this shape
  n/a        `Implements` and `Reads` are both `-`
  unparsed   the cell is not one version; the owning project normalizes it (REGISTRY section 2)

With -Product <text> -EmitSpec the program writes the synchronization spec for every product whose name
contains <text>: per contract, the document-log entries between the product's version and the current one,
each with its kind and what it obliges, and the definition of done. The spec is handed to that product's own
session; this program never edits a registry row or another repository.

Exit codes: 0 = report written; 1 = -FailOnLag and at least one row is behind; 2 = internal error.

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
    if ($EmitSpec -and -not $Product) { throw '-EmitSpec needs -Product <name or part of it>' }

    $registryPath = Join-Path $CatalogRoot '_meta\REGISTRY.md'
    if (-not (Test-Path -LiteralPath $registryPath)) { throw "no registry at '$registryPath'" }

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
    $section = ''
    $lines = Get-Content -LiteralPath $registryPath
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($line -match '^##\s+(\d+)\.\s*(.+)$') { $section = $Matches[2].Trim(); continue }
        if ($line -notmatch '^\|') { continue }
        $cells = @($line.Trim('|') -split '\|' | ForEach-Object { $_.Trim() })
        if ($cells.Count -lt 3 -or $cells[0] -match '^-+$') { continue }

        if ($section -like 'Contracts*') {
            if ($cells[0] -notmatch '^`([A-Z][A-Z0-9-]*)`$') { continue }
            $id = $Matches[1]
            $folder = ''
            if ($cells[1] -match '\[`([^`]+)`\]') { $folder = $Matches[1].Trim('/') }
            $contracts[$id] = [pscustomobject]@{
                version = $cells[2]; status = $cells[3]; folder = $folder
            }
        }
        elseif ($section -like 'Adoption*') {
            $ids = @([regex]::Matches($cells[0], '`([A-Z][A-Z0-9-]*)`') | ForEach-Object { $_.Groups[1].Value })
            if ($ids.Count -eq 0 -or $cells.Count -lt 6) { continue }
            for ($k = 0; $k -lt $ids.Count; $k++) {
                $rows.Add([pscustomobject]@{
                    contract = $ids[$k]; product = $cells[1]; role = $cells[2]
                    implCell = (Get-CellFor $cells[3] $ids.Count $k)
                    readsCell = (Get-CellFor $cells[4] $ids.Count $k)
                    verified = $cells[5]; multiId = ($ids.Count -gt 1); line = $i + 1
                })
            }
        }
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
                 elseif ($isPartial) { 'partial' }
                 elseif ($implNone -and $readsNone) { 'n/a' }
                 elseif (-not $synced) { 'unparsed' }
                 elseif ($synced -lt $curVer) { 'behind' }
                 elseif ($synced -gt $curVer) { 'ahead' }
                 else { 'current' }

        [pscustomobject]@{
            contract = $r.contract; product = $r.product; role = $r.role
            synced = if ($synced) { $synced.ToString() } else { '' }
            current = if ($curVer) { $curVer.ToString() } else { '' }
            state = $state; verified = $r.verified; multiId = $r.multiId; line = $r.line
            raw = if ($implNone) { $r.readsCell } else { $r.implCell }
        }
    }
    $result = @($result)
    if ($Product) { $result = @($result | Where-Object { $_.product -like "*$Product*" }) }

    # ------------------------------------------------------------------ the spec

    function Get-DocLog {
        param([string]$Folder)
        $readme = Join-Path (Join-Path $CatalogRoot $Folder) 'README.md'
        $entries = New-Object System.Collections.Generic.List[object]
        if (-not (Test-Path -LiteralPath $readme)) { return @() }
        $inLog = $false
        foreach ($l in (Get-Content -LiteralPath $readme)) {
            if ($l -match '^\|\s*Date\s*\|\s*Version\s*\|\s*Kind\s*\|') { $inLog = $true; continue }
            if (-not $inLog) { continue }
            if ($l -notmatch '^\|') { $inLog = $false; continue }
            if ($l -match '^\|\s*-+') { continue }
            if ($l -match '^\|\s*(\d{4}-\d{2}-\d{2})\s*\|\s*([^|]*?)\s*\|\s*([^|]*?)\s*\|\s*(.*?)\s*\|?\s*$') {
                $entries.Add([pscustomobject]@{
                    date = $Matches[1]; version = $Matches[2]; kind = $Matches[3]; what = $Matches[4]
                })
            }
        }
        return $entries.ToArray()
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

    function Get-Owed {
        param([string]$Kind)
        switch -Regex ($Kind.Trim().ToLower()) {
            '^breaking'                                  { return 'MUST adapt - an implementation on the older shape does something wrong against this one' }
            '^(additive|amendment|artifact|adoption)'    { return 'Review - adopt it, or record a dated exception saying why not' }
            default                                      { return 'Read - code changes only if it relied on the older wording' }
        }
    }

    function Limit-Text {
        param([string]$Text, [int]$Max = 480)
        if ($Text.Length -le $Max) { return $Text }
        return $Text.Substring(0, $Max).TrimEnd() + ' ..'
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
        $null = $sb.AppendLine()
        $null = $sb.AppendLine('The log entries below are matched by version and by the contract ids a row names; a row that names none is')
        $null = $sb.AppendLine('shown for every contract in its domain. Treat each list as a map, not as the whole change.')
        $null = $sb.AppendLine()

        $behind = @($Rows | Where-Object { $_.state -in 'behind', 'partial' })
        $pending = @($Rows | Where-Object { $_.state -eq 'pending' })
        $unparsed = @($Rows | Where-Object { $_.state -eq 'unparsed' })

        $null = $sb.AppendLine('## What is owed')
        $null = $sb.AppendLine()
        if ($behind.Count -eq 0) {
            $null = $sb.AppendLine('Nothing is behind. Every readable row is on the contract''s current version.')
        }
        else {
            $null = $sb.AppendLine('| Contract | Surface | Synchronized with | Current | State | Verified |')
            $null = $sb.AppendLine('| --- | --- | --- | --- | --- | --- |')
            foreach ($b in ($behind | Sort-Object contract, product)) {
                $null = $sb.AppendLine(('| `{0}` | {1} | {2} | {3} | {4} | {5} |' -f $b.contract, $b.product, $b.synced, $b.current, $b.state, $b.verified))
            }
        }
        $null = $sb.AppendLine()

        foreach ($b in ($behind | Sort-Object contract, product)) {
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

        $null = $sb.AppendLine('## Definition of done')
        $null = $sb.AppendLine()
        $null = $sb.AppendLine('1. Each contract above is read at its current version and cited by id and section, never by catalog path.')
        $null = $sb.AppendLine('2. The implementation matches it, or a dated exception (reason, `until` date) is in REGISTRY section 3.')
        $null = $sb.AppendLine('3. The product''s own suite runs the catalog''s conformance vectors at the current version; the command and')
        $null = $sb.AppendLine('   its exit code are cited.')
        $null = $sb.AppendLine('4. The product''s own rows in REGISTRY section 2 carry `Implements`, `Reads`, `Verified` (today) and a one-line')
        $null = $sb.AppendLine('   note, in the cell format of that section, one contract id per row.')
        $null = $sb.AppendLine('5. Each `docs/contracts/<ID>.md` pointer names the current version.')
        $null = $sb.AppendLine('6. No other product''s row and no contract document is edited. A needed contract change is a proposal beside')
        $null = $sb.AppendLine('   the contract (CONTRACTS.md, `PROPOSAL-<date>-<topic>.md`), and the catalog moves before the code.')
        return $sb.ToString()
    }

    # ------------------------------------------------------------------ output

    $counts = [ordered]@{}
    foreach ($s in 'current', 'behind', 'partial', 'pending', 'ahead', 'n/a', 'unparsed') {
        $counts[$s] = @($result | Where-Object { $_.state -eq $s }).Count
    }

    if ($EmitSpec) {
        $spec = New-Spec $result
        if ($OutFile) {
            $full = [System.IO.Path]::GetFullPath($OutFile, (Get-Location).Path)
            $dir = Split-Path -Parent $full
            if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
            [System.IO.File]::WriteAllText($full, $spec, (New-Object System.Text.UTF8Encoding($false)))
            Write-Output "spec written: $OutFile ($($counts['behind']) behind, $($counts['partial']) partial, $($counts['pending']) pending, $($counts['unparsed']) unparsed)"
        }
        else { Write-Output $spec }
    }
    elseif ($Json) {
        [pscustomobject]@{ catalog = $CatalogRoot; counts = $counts; rows = $result } | ConvertTo-Json -Depth 4
    }
    else {
        "catalog: $CatalogRoot"
        'rows: {0}  ({1})' -f $result.Count, (($counts.GetEnumerator() | ForEach-Object { '{0} {1}' -f $_.Key, $_.Value }) -join ', ')
        ''
        $lag = @($result | Where-Object { $_.state -in 'behind', 'partial' } | Sort-Object product, contract)
        if ($lag.Count -gt 0) {
            $lag | Format-Table product, contract, state, synced, current, verified -AutoSize | Out-String -Width 220
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
