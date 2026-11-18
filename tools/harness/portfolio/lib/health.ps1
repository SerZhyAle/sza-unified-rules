# Read-only health facts the operator views print (S0044): which projects a queue line holds, which hold lines
# state a reason that no longer holds, whether an adoption stamp is behind the canon, and whether Claude Code
# trusts a repository's workspace.
#
# Dot-source this file after queue-file.ps1; it defines functions only, sets no preference and prints nothing.
# Nothing here writes: not the queue file, not a stamp, not ~/.claude.json.
#
#   Get-PqQueueHeldRepos -Queue <Read-PqQueueFile result>
#       [string[]] the keys held as a whole project - a '<key>' or '<key>:*' row under the hold heading. A
#       '<key>:<id>' row holds one ticket and is not listed.
#   Format-PqHoldFlag -RegistryHold <bool> -QueueHold <bool>
#       'false', 'true' (the registry's hold flag), 'queue' (a hold line of the queue file) or 'true+queue'.
#   Get-PqStaleHoldLines -Queue <Read-PqQueueFile result> -Registry <registry>
#       @(@{ repo; line; reason; queuePath }) - a whole-project hold row whose comment says the project has no
#       ticket queue while Get-PqTicketQueuePath now finds one. A ticket row, a row without that reason and a key
#       the registry does not name are not reported.
#   Get-PqCanonDigestInfo -CanonRoot <dir>
#       @{ ok; digest; version; error } - the core digest check-compliance.ps1 computes (rules/*.md without
#       README.md and SPREAD_BACK_PROMPT.md, LF-normalised, name + LF + text, SHA-256) and CANON_VERSION.
#   Get-PqStampFreshness -Stamp <parsed .sza-canon.json> -Canon <Get-PqCanonDigestInfo result>
#       @{ state = current|stale|unknown; version; detail }. unknown when either digest is missing - never current.
#   Read-PqClaudeTrust [-Path <file>]
#       @{ ok; projects (key -> bool); error; path } from ~/.claude.json, or the given file (pq doctor passes
#       SZA_CLAUDE_CONFIG, so a fixture never reads the real one).
#   ConvertTo-PqTrustKey -Path <dir>
#       the key Claude Code writes: full path, forward slashes, upper-case drive letter, no trailing slash.
#   Test-PqTrustNeeded -Path <dir>
#       $true when the repository carries .claude/settings.json or a .claude/hooks folder.
#   Get-PqSessionHarnessRoot [-EnvRoot <dir>] [-CacheDir <dir>]
#       the harness folder a repository's forwarder resolves: SZA_HARNESS_ROOT when set, else tools/harness of the
#       newest installed plugin version (compared as versions), else $null.
#   Get-PqHarnessDiffCount -Own <dir> -Other <dir>
#       @{ differ; total } over the *.ps1 files of Own, compared as text with CR removed; a script missing or
#       unreadable in Other counts as differing.
#   Format-PqHarnessLine -Own <dir> -Session <dir or ''>
#       the one `harness` line of pq doctor: PASS for one copy or equal scripts, NOTE otherwise.

$script:PqStaleHoldPattern = '(?i)\bno\s+ticket\s+queue\b'

function Get-PqQueueHeldRepos($Queue) {
    $keys = [Collections.Generic.List[string]]::new()
    foreach ($h in @($Queue.held)) {
        if ($null -eq $h -or [string]$h.kind -cne 'head') { continue }
        $k = [string]$h.repo
        if (-not $keys.Contains($k)) { $keys.Add($k) }
    }
    return [string[]]$keys.ToArray()
}

function Format-PqHoldFlag([bool]$RegistryHold, [bool]$QueueHold) {
    if ($RegistryHold -and $QueueHold) { return 'true+queue' }
    if ($QueueHold) { return 'queue' }
    if ($RegistryHold) { return 'true' }
    return 'false'
}

function Get-PqHoldComment([string]$Text) {
    $i = $Text.IndexOf('#')
    if ($i -lt 0) { return '' }
    return $Text.Substring($i + 1).Trim()
}

function Get-PqStaleHoldLines($Queue, $Registry) {
    $out = [Collections.Generic.List[object]]::new()
    $byKey = @{}
    foreach ($r in @($Registry.repos)) { if ($null -ne $r) { $byKey[[string]$r.key] = $r } }
    foreach ($h in @($Queue.held)) {
        if ($null -eq $h -or [string]$h.kind -cne 'head') { continue }
        $reason = Get-PqHoldComment ([string]$h.text)
        if ($reason -notmatch $script:PqStaleHoldPattern) { continue }
        $rec = $byKey[[string]$h.repo]
        if ($null -eq $rec -or -not [IO.Directory]::Exists([string]$rec.path)) { continue }
        $qp = $null
        try { $qp = Get-PqTicketQueuePath $rec } catch { $qp = $null }
        if ($qp -and [IO.File]::Exists($qp)) {
            $out.Add([ordered]@{ repo = [string]$h.repo; line = [int]$h.line; reason = $reason; queuePath = [string]$qp })
        }
    }
    return @($out.ToArray())
}

. (Join-Path $PSScriptRoot '..\..\..\lib\canon-digest.ps1')   # the digest itself: one implementation, shared with check-compliance.ps1

function Get-PqCanonDigestInfo([string]$CanonRoot) {
    $res = @{ ok = $false; digest = $null; version = 'unknown'; error = $null }
    $rulesDir = Join-Path $CanonRoot 'rules'
    if (-not [IO.Directory]::Exists($rulesDir)) { $res.error = "no rules/ under $CanonRoot"; return $res }
    $vf = Join-Path $CanonRoot 'CANON_VERSION'
    if ([IO.File]::Exists($vf)) { $res.version = ([IO.File]::ReadAllText($vf)).Trim() }
    # The algorithm lives in tools/lib/canon-digest.ps1, the one copy check-compliance.ps1 uses too.
    if (@(Get-SzaCanonRuleDocs $rulesDir).Count -eq 0) { $res.error = "no rule documents in $rulesDir"; return $res }
    try { $res.digest = Get-SzaCanonCoreDigest $rulesDir; $res.ok = $true }
    catch { $res.error = $_.Exception.Message }
    return $res
}

function Get-PqStampFreshness($Stamp, $Canon) {
    $version = ''
    $digest = ''
    $c = $null
    if ($null -ne $Stamp -and $null -ne $Stamp.PSObject.Properties['canon']) { $c = $Stamp.canon }
    if ($null -ne $c) {
        if ($null -ne $c.PSObject.Properties['version']) { $version = [string]$c.version }
        if ($null -ne $c.PSObject.Properties['coreDigest']) { $digest = [string]$c.coreDigest }
    }
    if ($null -eq $Canon -or -not $Canon.ok) {
        $why = if ($null -ne $Canon -and $Canon.error) { [string]$Canon.error } else { 'canon digest unavailable' }
        return @{ state = 'unknown'; version = $version; detail = "digest not compared - $why" }
    }
    if ([string]::IsNullOrWhiteSpace($digest)) { return @{ state = 'unknown'; version = $version; detail = 'digest not compared - the stamp has no canon.coreDigest' } }
    if ($digest -ceq [string]$Canon.digest) { return @{ state = 'current'; version = $version; detail = "canon $version, digest current" } }
    return @{ state = 'stale'; version = $version; detail = "stale since $version - stamp digest differs from canon $($Canon.version)" }
}

function Read-PqClaudeTrust([string]$Path) {
    if (-not $Path) { $Path = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.claude.json' }
    $res = @{ ok = $false; projects = @{}; error = $null; path = $Path }
    if (-not [IO.File]::Exists($Path)) { $res.error = "no $Path"; return $res }
    try {
        $j = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($Path)) -AsHashtable
        $map = [Collections.Generic.Dictionary[string, bool]]::new([StringComparer]::Ordinal)
        $projects = if ($j -is [Collections.IDictionary] -and $j.ContainsKey('projects')) { $j['projects'] } else { $null }
        if ($projects -is [Collections.IDictionary]) {
            foreach ($k in $projects.Keys) {
                $v = $projects[$k]
                $map[[string]$k] = ($v -is [Collections.IDictionary] -and $v.ContainsKey('hasTrustDialogAccepted') -and $v['hasTrustDialogAccepted'] -eq $true)
            }
        }
        $res.projects = $map
        $res.ok = $true
    }
    catch { $res.error = "$Path does not parse - $($_.Exception.Message)" }
    return $res
}

function Get-PqSessionHarnessRoot([string]$EnvRoot = $env:SZA_HARNESS_ROOT, [string]$CacheDir = '') {
    if ($EnvRoot) { return [IO.Path]::GetFullPath($EnvRoot) }
    if (-not $CacheDir) {
        $userHome = if ($env:USERPROFILE) { $env:USERPROFILE } else { $env:HOME }
        if (-not $userHome) { return $null }
        $CacheDir = Join-Path $userHome '.claude/plugins/cache/sza-unified-rules/sza'
    }
    if (-not [IO.Directory]::Exists($CacheDir)) { return $null }
    $best = $null
    $bestVersion = $null
    foreach ($d in [IO.Directory]::GetDirectories($CacheDir)) {
        $v = $null
        if (-not [version]::TryParse([IO.Path]::GetFileName($d), [ref]$v)) { continue }
        if (-not [IO.Directory]::Exists((Join-Path $d 'tools/harness'))) { continue }
        if ($null -eq $bestVersion -or $v -gt $bestVersion) { $bestVersion = $v; $best = $d }
    }
    if ($null -eq $best) { return $null }
    return [IO.Path]::GetFullPath((Join-Path $best 'tools/harness'))
}

function Get-PqHarnessDiffCount([string]$Own, [string]$Other) {
    $res = @{ differ = 0; total = 0 }
    $ownFull = [IO.Path]::GetFullPath($Own).TrimEnd('\', '/')
    foreach ($f in [IO.Directory]::GetFiles($ownFull, '*.ps1', [IO.SearchOption]::AllDirectories)) {
        $res.total++
        $twin = Join-Path $Other $f.Substring($ownFull.Length + 1)
        try {
            if (-not [IO.File]::Exists($twin)) { $res.differ++; continue }
            $a = [IO.File]::ReadAllText($f).Replace("`r", '')
            $b = [IO.File]::ReadAllText($twin).Replace("`r", '')
            if ($a -cne $b) { $res.differ++ }
        }
        catch { $res.differ++ }
    }
    return $res
}

function Format-PqHarnessLine([string]$Own, [string]$Session) {
    $ownFull = [IO.Path]::GetFullPath($Own).TrimEnd('\', '/')
    if (-not $Session) { return "NOTE harness - robots run $ownFull; no installed plugin copy was found for attended sessions" }
    $sessionFull = [IO.Path]::GetFullPath($Session).TrimEnd('\', '/')
    if ([string]::Equals($ownFull, $sessionFull, [StringComparison]::OrdinalIgnoreCase)) { return "PASS harness - one copy: $ownFull" }
    $diff = Get-PqHarnessDiffCount -Own $ownFull -Other $sessionFull
    if ($diff.differ -eq 0) { return "PASS harness - robots run $ownFull; attended sessions run $sessionFull; all $($diff.total) scripts are the same" }
    return "NOTE harness - robots run $ownFull; attended sessions run $sessionFull; $($diff.differ) of $($diff.total) scripts differ (a robot pass is given the first copy)"
}

function ConvertTo-PqTrustKey([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path).Replace('\', '/').TrimEnd('/')
    if ($full.Length -ge 2 -and $full[1] -eq ':') { $full = $full.Substring(0, 1).ToUpperInvariant() + $full.Substring(1) }
    return $full
}

function Test-PqTrustNeeded([string]$Path) {
    return ([IO.File]::Exists((Join-Path $Path '.claude/settings.json')) -or [IO.Directory]::Exists((Join-Path $Path '.claude/hooks')))
}
