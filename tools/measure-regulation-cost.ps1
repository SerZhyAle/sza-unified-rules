#requires -Version 7.0
<#
.SYNOPSIS
    What the regulations cost one agent pass: the text a pass is handed, the text it writes, what the run log says.
.DESCRIPTION
    Read-only: prints three sections and writes nothing. Token figures are estimates (characters / 4, no tokenizer).
      1 FIXED   - the default runner prompt, the session-start injection, the agent-rules files, the skill listing,
                  the lifecycle skill whole and by section, its references.
      2 WRITTEN - the sections agents write into closed tickets (the newest -Tickets files of -DoneDir), the
                  evidence lines, and the status notes of the ledger beside that folder.
      3 RUNS    - from <PortfolioRoot>/runs.jsonl: passes and minutes per closed ticket by closing model and
                  complexity, and the share of cached input the fixed text can account for - a ceiling: the whole
                  fixed text of THIS repository is assumed to sit in context on every request of every pass.
    -PluginRoot measures another copy of the canon text (an installed plugin cache folder, a lean variant).
    Exit codes: 0 printed; 1 error; 2 could not verify (no repository folder, or no lifecycle skill under -PluginRoot).
#>
[CmdletBinding()]
param(
    [string] $RepoRoot = (Get-Location).Path,
    [string] $PluginRoot = (Split-Path -Parent $PSScriptRoot),
    [string] $PortfolioRoot = $(if ($env:SZA_PORTFOLIO_ROOT) { $env:SZA_PORTFOLIO_ROOT } else { Join-Path $HOME '.sza/portfolio' }),
    [string] $DoneDir = 'PLAN/DONE',
    [ValidateRange(1, 5000)][int] $Tickets = 200
)
$ErrorActionPreference = 'Stop'
$skill = Join-Path $PluginRoot 'skills/spec-to-audit/SKILL.md'
if (-not (Test-Path -LiteralPath $RepoRoot -PathType Container) -or -not (Test-Path -LiteralPath $skill -PathType Leaf)) {
    Write-Host "measure-regulation-cost: COULD NOT VERIFY (no folder '$RepoRoot' or no lifecycle skill under '$PluginRoot')"; exit 2
}
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path.TrimEnd('\', '/')
function Read-Text([string]$Path) { if (Test-Path -LiteralPath $Path -PathType Leaf) { [IO.File]::ReadAllText($Path) } else { '' } }
function Read-SharedLines([string]$Path) {
    # FileShare ReadWrite, read whole and closed at once: live workers append to the run log and do not retry.
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }
    $stream = [IO.File]::Open((Resolve-Path -LiteralPath $Path).Path, 'Open', 'Read', 'ReadWrite')
    try { return ([IO.StreamReader]::new($stream).ReadToEnd() -split "`r?`n") } finally { $stream.Dispose() }
}
function Get-Median($Values) { $s = @($Values | Sort-Object); if ($s.Count -eq 0) { return 0 }; return $s[[int][Math]::Floor(($s.Count - 1) / 2)] }
function Write-Row([string]$Item, [string]$Who, [int]$Chars) {
    '{0,-50} {1,-9} {2,7} {3,6}' -f $Item.Substring(0, [Math]::Min(50, $Item.Length)), $Who, $Chars, [int][Math]::Round($Chars / 4)
}
function Write-Group([string]$Name, $Values, [long]$All) {
    $v = @($Values | Sort-Object); if ($v.Count -eq 0) { return }
    $total = ($v | Measure-Object -Sum).Sum
    '{0,-22} {1,5} {2,7} {3,7} {4,8} {5,5:P0}' -f $Name, $v.Count, (Get-Median $v), $v[[int][Math]::Floor(($v.Count - 1) * 0.9)], $total, ($total / [Math]::Max(1L, $All))
}
'== 1 FIXED: item | who loads it | chars | est tokens =='
$prompt = if ((Read-Text (Join-Path $PluginRoot 'tools/harness/_profile.ps1')) -match "(?m)^\s*promptTemplate\s*=\s*'((?:[^']|'')*)'") { $Matches[1].Replace("''", "'") } else { '' }
$header = if ((Read-Text (Join-Path $PluginRoot 'hooks/session-start.ps1')) -match '(?s)\$header = @"\r?\n(.*?)\r?\n"@') { $Matches[1] } else { '' }
$inject = if (Test-Path -LiteralPath (Join-Path $RepoRoot '.sza-canon.json')) { $header.Length + (Read-Text (Join-Path $PluginRoot 'rules/INVARIANTS.md')).Length } else { 0 }
$claudeHome = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME '.claude' }
$listing = 0
foreach ($s in (Get-ChildItem -LiteralPath (Join-Path $PluginRoot 'skills') -Directory)) {
    if ((Read-Text (Join-Path $s.FullName 'SKILL.md')) -match '(?m)^description:\s*(.+)$') { $listing += $s.Name.Length + $Matches[1].Trim().Length }
}
$skillText = Read-Text $skill
$claudeOnly = [ordered]@{
    'session-start injection (header + INVARIANTS.md)' = $inject
    'repository CLAUDE.md'                             = (Read-Text (Join-Path $RepoRoot 'CLAUDE.md')).Length
    'user CLAUDE.md'                                   = (Read-Text (Join-Path $claudeHome 'CLAUDE.md')).Length
    'auto-memory index MEMORY.md'                      = (Read-Text (Join-Path $claudeHome ('projects/{0}/memory/MEMORY.md' -f ($RepoRoot -replace '[^A-Za-z0-9]', '-')))).Length
    'skill listing (names + descriptions)'             = $listing
}
$agentsMd = (Read-Text (Join-Path $RepoRoot 'AGENTS.md')).Length
Write-Row 'runner default prompt' 'all' $prompt.Length
foreach ($k in $claudeOnly.Keys) { Write-Row $k 'claude' $claudeOnly[$k] }
Write-Row 'repository AGENTS.md' 'codex' $agentsMd
Write-Row 'lifecycle skill SKILL.md (whole)' 'all' $skillText.Length
foreach ($part in [regex]::Split($skillText, '(?m)^(?=## )')) {
    $head = ($part -split "`n")[0].Trim()
    Write-Row ('  ' + $(if ($head -match '^## ') { $head } else { '(front matter and introduction)' })) 'part' $part.Length
}
foreach ($f in (Get-ChildItem -LiteralPath (Join-Path $PluginRoot 'skills/spec-to-audit/references') -File -ErrorAction Ignore | Sort-Object Name)) {
    Write-Row ('reference ' + $f.Name) 'on demand' (Read-Text $f.FullName).Length
}
$fixedClaude = $prompt.Length + $skillText.Length + ($claudeOnly.Values | Measure-Object -Sum).Sum
$fixedOther = $prompt.Length + $skillText.Length + $agentsMd
Write-Row 'TOTAL fixed, a Claude pass' 'sum' $fixedClaude
Write-Row 'TOTAL fixed, a pass of another provider' 'sum' $fixedOther
"== 2 WRITTEN: group | tickets | median chars | p90 chars | total chars | share (newest $Tickets files of $DoneDir) =="
$done = Join-Path $RepoRoot $DoneDir
$files = @(if (Test-Path -LiteralPath $done -PathType Container) { Get-ChildItem -LiteralPath $done -File -Filter '*.md' | Sort-Object LastWriteTime -Descending | Select-Object -First $Tickets })
$groups = [ordered]@{ owner = @(); spec = @(); assumed = @(); questions = @(); audit = @(); other = @() }
$evidence = @(); $allChars = 0L
foreach ($f in $files) {
    $acc = @{}; $g = 'other'; $ev = 0
    foreach ($line in [IO.File]::ReadAllLines($f.FullName)) {
        if ($line -match '^#{2,3} ') {
            $g = if ($line -match '^## Last Audit') { 'audit' }
            elseif ($line -match '^### Assumed') { 'assumed' }
            elseif ($line -match '^### (Questions|Quiz)') { 'questions' }
            elseif ($line -match '^## 0\.') { 'owner' }
            elseif ($line -match '^(## [123]\.|### 3\.)') { 'spec' }
            elseif ($line -match '^### ' -and $g -eq 'audit') { 'audit' }
            else { 'other' }
        }
        $acc[$g] = [int]$acc[$g] + $line.Length + 1
        if ($line -match 'expected: .+\| actual:') { $ev += $line.Length + 1 }
    }
    foreach ($k in $acc.Keys) { $groups[$k] += $acc[$k]; $allChars += $acc[$k] }
    if ($ev -gt 0) { $evidence += $ev }
}
foreach ($k in $groups.Keys) { Write-Group $k $groups[$k] $allChars }
Write-Group 'evidence lines' $evidence $allChars
$ledger = Join-Path (Split-Path -Parent $done) 'spec-catalog.jsonl'
$notes = @(foreach ($l in (Read-SharedLines $ledger)) { if ($l.Trim()) { try { $n = [string]($l | ConvertFrom-Json).statusNote; if ($n) { $n.Length } } catch { } } })
Write-Group 'ledger status notes' $notes $allChars
$runsFile = Join-Path $PortfolioRoot 'runs.jsonl'
"== 3 RUNS: $runsFile =="
$rows = @(foreach ($l in (Read-SharedLines $runsFile)) { if ($l.Trim()) { try { $l | ConvertFrom-Json } catch { } } })
$closing = 'Implemented', 'Verified', 'BlockNeedUserTest'
$stat = @{}; $closed = 0; $onePass = 0
foreach ($grp in ($rows | Group-Object { '{0}:{1}' -f $_.repo, $_.id })) {
    $n = 0; $minutes = 0.0; $hit = $null
    foreach ($r in $grp.Group) { $n++; $minutes += [double]$r.minutes; if ($closing -contains $r.statusAfter) { $hit = $r; break } }
    if (-not $hit) { continue }
    $closed++; if ($n -eq 1) { $onePass++ }
    $key = '{0}/{1} {2}' -f $hit.agent, $hit.model, $(if ($hit.complexity) { $hit.complexity } else { '-' })
    if (-not $stat.ContainsKey($key)) { $stat[$key] = [Collections.Generic.List[object]]::new() }
    $stat[$key].Add([pscustomobject]@{ n = $n; minutes = $minutes })
}
'closing agent/model complexity | tickets | one-pass | median passes | mean passes | median minutes (groups of 5 or more)'
foreach ($key in ($stat.Keys | Sort-Object)) {
    $v = $stat[$key]; if ($v.Count -lt 5) { continue }
    '{0,-40} {1,5} {2,5:P0} {3,3} {4,5:N2} {5,7:N1}' -f $key, $v.Count, (@($v | Where-Object { $_.n -eq 1 }).Count / $v.Count), (Get-Median @($v.n)), (@($v.n) | Measure-Object -Average).Average, (Get-Median @($v.minutes))
}
'ALL closed tickets={0} one-pass={1:P0} direct Draft-to-Implemented passes={2}' -f $closed, ($onePass / [Math]::Max(1, $closed)), @($rows | Where-Object { $_.statusBefore -eq 'Draft' -and $_.statusAfter -eq 'Implemented' }).Count
$fixedTokens = [Math]::Round($fixedClaude / 4)
$priceText = Read-Text (Join-Path $PluginRoot 'tools/harness/batch/claude-prices.json')
$models = if ($priceText) { ($priceText | ConvertFrom-Json).models.PSObject.Properties } else { @() }
'usage model | passes | median requests | context per request | fixed-text share of cached input | est USD of fixed text per pass (read on every request + one cache write; the long-prompt rate where the mean context is past the model threshold) | mean USD per pass'
foreach ($grp in ($rows | Where-Object { $_.usage -and $_.usage.complete } | Group-Object { [string]$_.usage.model } | Sort-Object Name)) {
    $requests = 0L; $read = 0L
    foreach ($r in $grp.Group) { $requests += [long]$r.usage.requests; $read += [long]$r.usage.cacheRead }
    $context = $read / [Math]::Max(1L, $requests)
    $price = ($models | Where-Object { $grp.Name.StartsWith($_.Name) } | Sort-Object { $_.Name.Length } -Descending | Select-Object -First 1).Value
    if ($price -and $null -ne $price.longPromptOver -and $context -gt [double]$price.longPromptOver) { $price = $price.long }
    $medianRequests = Get-Median @($grp.Group | ForEach-Object { [int]$_.usage.requests })
    $cost = @($grp.Group | Where-Object { $null -ne $_.costUsd } | ForEach-Object { [double]$_.costUsd })
    '{0,-22} {1,5} {2,4} {3,9:N0} {4,6:P1} {5,7:N3} {6,7:N2}' -f $grp.Name, $grp.Count, $medianRequests, $context, ($fixedTokens * $requests / [Math]::Max(1L, $read)), ($fixedTokens * ($medianRequests * [double]$price.cacheRead + [double]$price.cacheWrite5m) / 1e6), ($cost | Measure-Object -Average).Average
}
'measure-regulation-cost: DONE (fixedClaudeTokens={0} fixedOtherTokens={1} tickets={2} runs={3})' -f $fixedTokens, [Math]::Round($fixedOther / 4), $files.Count, $rows.Count
exit 0
