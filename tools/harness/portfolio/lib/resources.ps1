# Machine-wide exclusive resources of the robots (TASK-FLOW rule 62; S0016 R65, decision D17 of 2026-11-10: build 3,
# emulator 1, device never).
#
# Dot-source this file after paths.ps1, ledger-watch.ps1 and loop.ps1; it defines functions only, sets no preference and
# prints nothing.
#
#   Get-PqTicketVerify -RepoPath <dir> -TicketId <id>
#       edit | build | emulator | device from the spec's `**Verify:** <level> - <reason>` line within its first 40 lines.
#       No line, an unreadable spec or a value outside the table is `build` (rule 62: in doubt, the higher level).
#   Get-PqVerifyTokens -Verify <level>
#       the tokens that level takes: edit none, build `build`, emulator `build` and `emulator`; device is not offered.
#   Get-PqResourceHeld -Token <build|emulator> [-ClearStale]
#       the live token files (and, with -ClearStale, the dead owners' files removed first, returned in .stale).
#   Request-PqResources -Registry -RepoKey -TicketId -Verify -PassId
#       @{ ok; held = @(tokens taken); why; resource; heldCount; cap; stale } - all tokens or none: a token is a file
#       <root>\resources\<token>\<repo>__<id>.json with token, repo, id, pid, procStart, pass, at; the count of files is
#       the number held; the check and the writes are one state transaction, so two workers cannot both take the last one.
#   Remove-PqResources -RepoKey -TicketId
#       release every token that ticket holds (also the dispatcher's own, whenever it ends).

$script:PqVerifyLevels = @('edit', 'build', 'emulator', 'device')

function Get-PqTicketVerify {
    param([Parameter(Mandatory)][string]$RepoPath, [Parameter(Mandatory)][string]$TicketId)
    try {
        $snap = Get-PqLedgerSnapshot -RepoPath $RepoPath
        if (-not $snap.tickets.Contains($TicketId)) { return 'build' }
        $file = [string]$snap.tickets[$TicketId].file
        if (-not $file) { return 'build' }
        $spec = Resolve-PqRepoPathValue $snap.root $file
        if (-not [IO.File]::Exists($spec)) { return 'build' }
        foreach ($line in (Get-Content -LiteralPath $spec -TotalCount 40 -Encoding UTF8)) {
            if ($line -match '^\*\*Verify:\*\*\s*([A-Za-z]+)') {
                $level = $Matches[1].ToLowerInvariant()
                if ($script:PqVerifyLevels -ccontains $level) { return $level }
                return 'build'
            }
        }
    }
    catch { }
    return 'build'
}

function Get-PqVerifyTokens([string]$Verify) {
    switch ($Verify) {
        'edit' { return [string[]]@() }
        'emulator' { return [string[]]@('build', 'emulator') }
        'device' { return [string[]]@() }
        default { return [string[]]@('build') }
    }
}

function Get-PqResourceTokenDir([string]$Token) { return (Join-Path (Get-PqPath -Kind resources) $Token) }

# Callers hold the state lock when they clear, so a stale file is removed once.
function Get-PqResourceHeld {
    param([Parameter(Mandatory)][string]$Token, [switch]$ClearStale)
    $dir = Get-PqResourceTokenDir $Token
    $live = [Collections.Generic.List[object]]::new()
    $stale = [Collections.Generic.List[string]]::new()
    if ([IO.Directory]::Exists($dir)) {
        foreach ($f in [IO.Directory]::GetFiles($dir, '*.json')) {
            $s = Read-PqState $f
            $alive = ($null -ne $s) -and (Test-PqProcessAlive ([int](Get-PqValue $s 'pid' 0)) (Get-PqValue $s 'procStart'))
            if ($alive) { $live.Add($s); continue }
            if ($ClearStale) {
                Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue
                $stale.Add([IO.Path]::GetFileNameWithoutExtension($f))
            }
            elseif ($null -ne $s) { $live.Add($s) }
        }
    }
    return @{ live = @($live); stale = @($stale) }
}

function Request-PqResources {
    param(
        [Parameter(Mandatory)]$Registry, [Parameter(Mandatory)][string]$RepoKey, [Parameter(Mandatory)][string]$TicketId,
        [Parameter(Mandatory)][string]$Verify, [string]$PassId = ''
    )
    if ($Verify -ceq 'device') { return @{ ok = $false; held = @(); why = 'deviceLevel'; resource = $null; heldCount = 0; cap = 0; stale = @() } }
    $tokens = @(Get-PqVerifyTokens $Verify)
    if ($tokens.Count -eq 0) { return @{ ok = $true; held = @(); why = $null; resource = $null; heldCount = 0; cap = 0; stale = @() } }
    $res = Get-PqValue $Registry 'resources'
    $resourceRepo = $RepoKey
    $resourceId = $TicketId
    $resourcePass = $PassId
    $startedAt = (Get-Process -Id $PID).StartTime.ToUniversalTime().ToString('o')
    return (Invoke-PqStateLock {
            $stale = [Collections.Generic.List[string]]::new()
            $counts = [ordered]@{}
            foreach ($t in $tokens) {
                $cap = [int](Get-PqValue $res $t $(if ($t -ceq 'build') { 3 } else { 1 }))
                $h = Get-PqResourceHeld -Token $t -ClearStale
                foreach ($s in @($h.stale)) { $stale.Add("$t/$s") }
                $mine = @($h.live | Where-Object { (Get-PqValue $_ 'repo') -ceq $resourceRepo -and (Get-PqValue $_ 'id') -ceq $resourceId }).Count
                if ($mine -eq 0 -and @($h.live).Count -ge $cap) {
                    return @{ ok = $false; held = @(); why = 'resource'; resource = $t; heldCount = @($h.live).Count; cap = $cap; stale = @($stale) }
                }
                $counts[$t] = @{ held = @($h.live).Count; cap = $cap }
            }
            foreach ($t in $tokens) {
                $file = Get-PqPath -Kind resourceToken -Token $t -Repo $resourceRepo -Id $resourceId
                $dir = Split-Path -Parent $file
                if (-not [IO.Directory]::Exists($dir)) { $null = [IO.Directory]::CreateDirectory($dir) }
                $obj = [ordered]@{
                    token = $t; repo = $resourceRepo; id = $resourceId; pid = $PID; procStart = $startedAt; pass = $resourcePass
                    at = [DateTimeOffset]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
                }
                $tmp = "$file.$PID.tmp"
                [IO.File]::WriteAllText($tmp, ($obj | ConvertTo-Json -Compress), [Text.UTF8Encoding]::new($false))
                [IO.File]::Move($tmp, $file, $true)
            }
            $first = $tokens[-1]
            return @{ ok = $true; held = $tokens; why = $null; resource = $first; heldCount = ($counts[$first].held + 1); cap = $counts[$first].cap; stale = @($stale) }
        })
}

function Remove-PqResources {
    param([Parameter(Mandatory)][string]$RepoKey, [Parameter(Mandatory)][string]$TicketId)
    $released = [Collections.Generic.List[string]]::new()
    try {
        foreach ($t in @('build', 'emulator')) {
            $file = Get-PqPath -Kind resourceToken -Token $t -Repo $RepoKey -Id $TicketId
            if ([IO.File]::Exists($file)) {
                Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
                $released.Add($t)
            }
        }
    }
    catch { }
    return @($released)
}
