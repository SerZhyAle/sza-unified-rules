<# _portfolio-order.ps1 - the order of this repository's tickets in the portfolio queue file (TASK-FLOW rules 18 and 44).
   Dot-source it: one function, nothing printed or written, no portfolio library loaded (the picker runs many times per
   portfolio rank; block-links.ps1 reads the registry the same plain way).
   Get-PortfolioQueueOrder -ProjectRoot <path> [-PortfolioRoot <path>]  ->  @{ key; file; ids }
   ids: the ids of this repository's '<key>:<id>' rows above 'hold', in the reader's order of rule 44 (rows before
   the first heading, numbered packages ascending as integers, then '--'; inside a package, line order; a repeated
   id counts once, at its first line in the file, as Read-PqQueueFile counts it). Empty when the repository is not
   registered, a file is missing or unreadable, or the file names the repository by a bare key only. Nothing is
   excluded from a pick here.
   The row grammar is a copy of portfolio/lib/queue-file.ps1 ($script:PqQueueRowPattern, Get-PqQueueLine), as is
   RowPattern of the panel's PortfolioState.vb: change them together. #>
function Get-PortfolioQueueOrder {
    param([Parameter(Mandatory)][string] $ProjectRoot, [string] $PortfolioRoot = '')
    $out = @{ key = $null; file = $null; ids = [string[]]@() }
    try {
        $root = $PortfolioRoot
        if ([string]::IsNullOrWhiteSpace($root)) { $root = [string]$env:SZA_PORTFOLIO_ROOT }
        if ([string]::IsNullOrWhiteSpace($root)) { $root = Join-Path (Join-Path $env:USERPROFILE '.sza') 'portfolio' }
        $registryFile = Join-Path $root 'repos.json'
        if (-not [IO.File]::Exists($registryFile)) { return $out }
        $registry = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($registryFile))
        $reposProp = $registry.PSObject.Properties['repos']
        if ($null -eq $reposProp) { return $out }
        $want = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\', '/')
        foreach ($r in @($reposProp.Value)) {
            $k = $r.PSObject.Properties['key']; $p = $r.PSObject.Properties['path']
            if ($null -eq $k -or $null -eq $p -or -not $k.Value -or -not $p.Value) { continue }
            if ([IO.Path]::GetFullPath([string]$p.Value).TrimEnd('\', '/') -ieq $want) { $out.key = [string]$k.Value; break }
        }
        if (-not $out.key) { return $out }
        $out.file = Join-Path $root 'PORTFOLIO_QUEUE.md'
        $pathsProp = $registry.PSObject.Properties['paths']
        $override = if ($null -ne $pathsProp -and $null -ne $pathsProp.Value) { $pathsProp.Value.PSObject.Properties['portfolioQueue'] } else { $null }
        if ($null -ne $override -and $override.Value) {
            $out.file = if ([IO.Path]::IsPathFullyQualified([string]$override.Value)) { [string]$override.Value } else { Join-Path $root ([string]$override.Value) }
        }
        if (-not [IO.File]::Exists($out.file)) { return $out }
        # Opened shared for write and delete, as the portfolio's own reader does: a sync renaming the file is never blocked.
        $fs = [IO.FileStream]::new($out.file, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete)
        try { $text = [IO.StreamReader]::new($fs, [Text.UTF8Encoding]::new($false), $true).ReadToEnd() } finally { $fs.Dispose() }
        $rows = [Collections.Generic.List[object]]::new()
        $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $package = [long]-1; $inHold = $false; $lineNo = 0
        foreach ($line in [regex]::Split($text, '\r?\n')) {
            $lineNo++
            $body = ($line -split '#', 2)[0].Trim()
            if ($body.Length -eq 0) { continue }
            if ($body -match '^\d+$') {
                $value = [long]0
                if (-not [long]::TryParse($body, [ref]$value) -or $value -eq [long]::MaxValue) { $value = [long]::MaxValue - 1 }
                $package = $value; $inHold = $false; continue
            }
            if ($body -ceq '--') { $package = [long]::MaxValue; $inHold = $false; continue }
            if ($body -ieq 'hold') { $inHold = $true; continue }
            if ($inHold) { continue }
            $m = [regex]::Match(($body -split '\s+', 2)[0], '^(?<repo>[a-z][a-z0-9-]*):(?<id>[^\s:#_*]+)(?:_[^\s#]*)?$')
            # A repeated id is dropped here, in file order and before the sort: its first line in the file is its place.
            if ($m.Success -and $m.Groups['repo'].Value -ceq $out.key -and $seen.Add($m.Groups['id'].Value)) {
                $rows.Add([pscustomobject]@{ package = $package; line = $lineNo; id = $m.Groups['id'].Value })
            }
        }
        $out.ids = [string[]]@($rows | Sort-Object -Stable -Property package, line | ForEach-Object { [string]$_.id })
    } catch {
        $out.ids = [string[]]@()   # any doubt reads as "the queue file gives no order": the caller keeps the repository's own plan
    }
    return $out
}
