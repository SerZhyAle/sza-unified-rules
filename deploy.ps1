<#
deploy.ps1 - stage everything in this repo, commit, push, then update this machine's plugin.

Operator tool: the owner runs it. An agent does not run it on its own initiative - committing and
pushing happen only when asked (INVARIANTS 18).

The repo's own gate runs first and there is no flag to skip it: `git add .` would otherwise sweep a
broken rules edit past tools/check-rules.ps1, which is the one thing CLAUDE.md requires before
anything under rules/ is committed. -Yes skips the confirmation prompt, never the gate
(INVARIANTS 9).

Right after it, the other three fast gates run and every one of the four is named with its exit code
(check-rules, check-contracts, check-documents, assert-portable); a gate that cannot run is named
'unavailable' with the reason. Those three are advisory - they never block and never change the exit code.

The version pair is raised here, not by hand. A commit carrying anything consumers run is shipped by
the plugin version and nothing else, so tools/bump-canon-version.ps1 writes CANON_VERSION and
.claude-plugin/plugin.json before staging. The rule used to live in prose in three canon documents and
was missed anyway - on 2026-09-03 with the harness lock fix, and again on 2026-09-07 with three
spec_catalog files - each time leaving every consumer on the cached copy of the previous version while
this script and `claude plugin update` both reported success. -NoVersionBump is for a commit that ships
nothing to a consumer.

  pwsh -File deploy.ps1                      # gate, bump, stage, confirm, commit, push
  pwsh -File deploy.ps1 "Fix the digest"     # same, with an explicit commit message
  pwsh -File deploy.ps1 -DryRun              # gate + show what would be committed and bumped, change nothing
  pwsh -File deploy.ps1 -Yes                 # no prompt (for a scheduled or piped run)
  pwsh -File deploy.ps1 -NoVersionBump       # commit without raising the version
  pwsh -File deploy.ps1 -NoPluginUpdate      # push, but leave this machine's plugin where it is

After the push, on main and when this machine's plugin cache is behind the pushed version, it runs
`claude plugin marketplace update sza-unified-rules` and `claude plugin update sza@sza-unified-rules`
and checks that the cache reached the version. A failure there only warns and prints the commands to
run by hand; it never changes the exit code, because the commit is already on the remote. Open Claude
sessions keep what they loaded - restart them.

Exit codes: 0 = pushed, or nothing to push; 1 = gate failed, the version bump failed, or a git step
failed; 2 = cannot verify (not a repo, gate script missing, no remote, version files unreadable).
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)][string]$Message,
    [switch]$DryRun,
    [switch]$Yes,
    [switch]$NoVersionBump,
    [switch]$NoPluginUpdate
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

function Fail([string]$text, [int]$code) {
    Write-Host "deploy: $text" -ForegroundColor Red
    exit $code
}

# A porcelain line is 'XY path', and a rename is 'XY old -> new'; the new path is the one that ships.
function Get-PendingPath([string]$line) {
    $path = $line.Substring(3).Trim()
    $arrow = $path.IndexOf(' -> ')
    if ($arrow -ge 0) { $path = $path.Substring($arrow + 4) }
    return $path.Trim('"')
}

# Everything in this repo reaches a consumer through the plugin payload except the files below, so the
# question is which paths do NOT ship rather than which do: a new shipped directory then defaults to
# being shipped, and forgetting to list it costs a harmless bump instead of an undelivered canon.
function Test-ShipsToConsumers([string[]]$paths) {
    $exempt = @('README.md', 'LICENSE', 'CANON_VERSION', '.claude-plugin/plugin.json', '.gitignore')
    $exemptDirs = @('rules/contrib/', 'tools/__pycache__/')
    foreach ($path in $paths) {
        $normalized = $path -replace '\\', '/'
        if ($exempt -contains $normalized) { continue }
        if ($exemptDirs | Where-Object { $normalized.StartsWith($_) }) { continue }
        return $true
    }
    return $false
}

# --- 0. The repo has to be a repo, with somewhere to push to. -------------------------------------
if (-not (Test-Path -LiteralPath (Join-Path $root '.git'))) { Fail 'not a git repository' 2 }

$branch = (git -C $root rev-parse --abbrev-ref HEAD 2>$null)
if ($LASTEXITCODE -ne 0 -or -not $branch) { Fail 'cannot read the current branch' 2 }
if ($branch -eq 'HEAD') { Fail 'detached HEAD - check out a branch first' 2 }

$remote = (git -C $root remote 2>$null | Select-Object -First 1)
if (-not $remote) { Fail 'no remote configured - nothing to push to' 2 }

# --- 1. Gate. Not skippable. ----------------------------------------------------------------------
$gate = Join-Path $root 'tools\check-rules.ps1'
if (-not (Test-Path -LiteralPath $gate)) { Fail 'tools/check-rules.ps1 is missing - cannot verify' 2 }

Write-Host 'deploy: running tools/check-rules.ps1' -ForegroundColor Cyan
& pwsh -NoProfile -File $gate
$gateCode = $LASTEXITCODE
if ($gateCode -eq 2) { Fail "the gate could not verify the canon (exit 2) - fix that before deploying" 2 }
if ($gateCode -ne 0) { Fail "the gate found violations (exit $gateCode) - nothing was staged" 1 }

# The four fast gates (CLAUDE.md "Working here") are named at every deploy, so a red one cannot sit for
# weeks as somebody else's problem (2026-10-28 .. 11-10: assert-portable and check-documents were red and
# called "not mine" in 17 reports). The canon gate above already blocked on anything but 0; the other three
# are advisory - the contracts catalog lives outside git and outside this repo, so a machine without
# P:\Contracts must still be able to ship a rule fix - and a gate that cannot run is reported as
# 'unavailable', never silently skipped. Nothing here changes the exit code.
function Invoke-FastGateReport {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][int]$CanonCode,
        [Parameter(Mandatory)][string]$ContractsRoot,
        [string]$Pwsh = 'pwsh',
        [string[]]$PythonCandidates = @('py', 'python')
    )
    $python = $PythonCandidates | Where-Object { Get-Command $_ -ErrorAction SilentlyContinue } | Select-Object -First 1
    $gates = @(
        @{ Name = 'check-contracts'; Script = 'tools\check-contracts.ps1'; Tool = $Pwsh; Args = @('-NoProfile', '-File', '{script}', '-CatalogRoot', $ContractsRoot); Needs = $ContractsRoot; NeedsText = "contracts catalog $ContractsRoot is not there" }
        @{ Name = 'check-documents'; Script = 'tools\docs\check-documents.py'; Tool = $python; Args = @('{script}'); ToolText = "none of $($PythonCandidates -join ', ') is on PATH" }
        @{ Name = 'assert-portable'; Script = 'tools\harness\assert-portable.ps1'; Tool = $Pwsh; Args = @('-NoProfile', '-File', '{script}') }
    )
    $report = @([pscustomobject]@{ name = 'check-rules'; code = $CanonCode; state = if ($CanonCode -eq 0) { 'ok' } else { 'red' }; why = '' })
    foreach ($gate in $gates) {
        $script = Join-Path $Root $gate.Script
        $why = ''
        if (-not (Test-Path -LiteralPath $script)) { $why = "$($gate.Script) is missing" }
        elseif (-not $gate.Tool) { $why = $gate['ToolText'] }
        elseif (-not (Get-Command $gate.Tool -ErrorAction SilentlyContinue)) { $why = "'$($gate.Tool)' is not on PATH" }
        elseif ($gate['Needs'] -and -not (Test-Path -LiteralPath $gate['Needs'])) { $why = $gate['NeedsText'] }
        if ($why) {
            $report += [pscustomobject]@{ name = $gate.Name; code = $null; state = 'unavailable'; why = $why }
            continue
        }
        $argList = @($gate.Args | ForEach-Object { $_ -replace '\{script\}', $script })
        try {
            $out = @(& $gate.Tool @argList 2>&1)
            $code = $LASTEXITCODE
        }
        catch {
            $report += [pscustomobject]@{ name = $gate.Name; code = $null; state = 'unavailable'; why = $_.Exception.Message }
            continue
        }
        $tail = if ($code -ne 0) { (@($out | ForEach-Object { "$_" } | Where-Object { $_.Trim() } | Select-Object -Last 3) -join "`n") } else { '' }
        $report += [pscustomobject]@{ name = $gate.Name; code = $code; state = if ($code -eq 0) { 'ok' } else { 'red' }; why = $tail }
    }
    foreach ($item in $report) {
        $shown = if ($null -eq $item.code) { 'unavailable' } else { "exit $($item.code)" }
        $color = if ($item.state -eq 'ok') { 'Green' } else { 'Yellow' }
        Write-Host "deploy:   $($item.name.PadRight(16)) $shown$(if ($item.state -eq 'unavailable') { " - $($item.why)" })" -ForegroundColor $color
        if ($item.state -eq 'red' -and $item.why) { ($item.why -split "`n") | ForEach-Object { Write-Host "deploy:     $_" } }
    }
    return $report
}

$ctrRoot = if ($env:SZA_CONTRACTS_ROOT) { $env:SZA_CONTRACTS_ROOT } else { 'P:\Contracts' }
Write-Host 'deploy: fast gates (the canon gate blocked above; the rest are advisory)' -ForegroundColor Cyan
$fastGates = @(Invoke-FastGateReport -Root $root -CanonCode $gateCode -ContractsRoot $ctrRoot)
$notGreen = @($fastGates | Where-Object { $_.state -ne 'ok' })
if ($notGreen.Count -gt 0) {
    Write-Host "deploy: $($notGreen.Count) of $($fastGates.Count) fast gates are red or unavailable ($(($notGreen | ForEach-Object { $_.name }) -join ', ')) - not a blocker here, but fix them" -ForegroundColor Yellow
}

# --- 2. Look at what would go in, without touching the index yet. ---------------------------------
# `git status --porcelain` already honours .gitignore and lists untracked files, so the preview and
# the -DryRun path never have to stage anything to find out what they would stage.
$pending = @(git -C $root status --porcelain)
if ($LASTEXITCODE -ne 0) { Fail 'cannot read the working tree status' 2 }
if ($pending.Count -eq 0) {
    Write-Host 'deploy: nothing to commit, working tree clean' -ForegroundColor Green
    exit 0
}

# --- 2a. Raise the version pair, before staging, so both files ride in this commit. ----------------
$ships = Test-ShipsToConsumers (@($pending) | ForEach-Object { Get-PendingPath $_ })
if ($NoVersionBump) {
    Write-Host 'deploy: -NoVersionBump - the version pair is left where it is' -ForegroundColor Yellow
} elseif (-not $ships) {
    Write-Host 'deploy: nothing in this change set reaches a consumer - no version bump' -ForegroundColor Yellow
} else {
    $bump = Join-Path $root 'tools\bump-canon-version.ps1'
    if (-not (Test-Path -LiteralPath $bump)) { Fail 'tools/bump-canon-version.ps1 is missing - cannot verify the version pair' 2 }
    if ($DryRun) { & pwsh -NoProfile -File $bump -DryRun } else { & pwsh -NoProfile -File $bump }
    $bumpCode = $LASTEXITCODE
    if ($bumpCode -ne 0) { Fail "the version bump failed (exit $bumpCode) - nothing was staged" $bumpCode }

    # The two version files are themselves changes; re-read so they appear in the preview and reach git add.
    $pending = @(git -C $root status --porcelain)
    if ($LASTEXITCODE -ne 0) { Fail 'cannot re-read the working tree status after the version bump' 2 }
}

Write-Host ''
Write-Host "deploy: $($pending.Count) change(s) on '$branch' -> $remote" -ForegroundColor Cyan
$pending | ForEach-Object { Write-Host "  $_" }
Write-Host ''

if (-not $Message) { $Message = "Canon update $(Get-Date -Format 'yyyy-MM-dd')" }

if ($DryRun) {
    Write-Host "deploy: DRY RUN - would commit with message: $Message" -ForegroundColor Yellow
    Write-Host "deploy: DRY RUN - would push to $remote/$branch. Nothing was staged." -ForegroundColor Yellow
    exit 0
}

# --- 3. Confirm. Pushing is one-way; the default branch deserves a second look. --------------------
if (-not $Yes) {
    $default = (git -C $root symbolic-ref --quiet --short "refs/remotes/$remote/HEAD" 2>$null) -replace "^$remote/", ''
    $target = if ($default -and $branch -eq $default) { "$remote/$branch (the DEFAULT branch)" } else { "$remote/$branch" }
    # ${target} braced on purpose: "$target?" would parse the '?' as part of the variable name.
    $answer = Read-Host "deploy: commit and push $($pending.Count) change(s) to ${target}? [y/N]"
    if ($answer -notmatch '^(y|yes)$') {
        Write-Host 'deploy: aborted. Nothing was staged.' -ForegroundColor Yellow
        exit 0
    }
}

# --- 4. Stage, commit, push. ----------------------------------------------------------------------
git -C $root add -A
if ($LASTEXITCODE -ne 0) { Fail 'git add failed' 1 }

git -C $root commit -m $Message
if ($LASTEXITCODE -ne 0) { Fail 'git commit failed - staging left in place' 1 }

git -C $root push $remote $branch
if ($LASTEXITCODE -ne 0) { Fail "git push failed - the commit exists locally, push it by hand" 1 }

$sha = (git -C $root rev-parse --short HEAD)
Write-Host ''
Write-Host "deploy: pushed $sha to $remote/$branch - $Message" -ForegroundColor Green

# --- 5. Bring this machine's plugin cache to the version just pushed. ------------------------------
# The cache is a directory named for the version, so "is this machine current" is readable without a
# network call. The update is part of the deploy because it was the step left to the operator and the one
# that was forgotten: the push succeeded and the machine kept running the previous copy (2026-10-29: three
# deploys in, the cache still held the version from before the first). Two calls, in this order - the
# marketplace refresh is what makes the new version visible, the plugin update is what installs it.
# Only on main: the marketplace is a GitHub source with no ref and follows main, so an update after a push
# from another branch delivers nothing. This never fails the deploy - the commit is on the remote either
# way - it says what happened and prints the manual commands when it could not finish. The new version is
# loaded by a session that starts after this; an open one keeps what it loaded.
function Update-PluginCache {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Branch,
        [string]$CacheRoot = (Join-Path ([Environment]::GetFolderPath('UserProfile')) '.claude\plugins\cache\sza-unified-rules\sza'),
        [string]$Cli = 'claude',
        [switch]$Skip
    )
    $manual = 'claude plugin marketplace update sza-unified-rules; claude plugin update sza@sza-unified-rules'
    if (-not (Test-Path -LiteralPath $CacheRoot)) { return 'no-cache' }
    $pluginText = Get-Content -LiteralPath (Join-Path $Root '.claude-plugin/plugin.json') -Raw
    if ($pluginText -match '"version"\s*:\s*"([^"]+)"') { $pushed = $Matches[1] } else { return 'no-version' }

    $newest = {
        Get-ChildItem -LiteralPath $CacheRoot -Directory -ErrorAction SilentlyContinue |
            ForEach-Object { $_.Name } |
            Sort-Object -Property { try { [version]$_ } catch { [version]'0.0.0' } } |
            Select-Object -Last 1
    }
    $cached = & $newest
    if (-not $cached -or $cached -eq $pushed) { return 'current' }

    Write-Host ''
    Write-Host "deploy: the plugin cache on this machine is at $cached, the canon is now at $pushed" -ForegroundColor Yellow
    if ($Skip) {
        Write-Host "deploy: -NoPluginUpdate - run: $manual" -ForegroundColor Yellow
        return 'skipped'
    }
    if ($Branch -ne 'main') {
        Write-Host "deploy: this was pushed from '$Branch' and the marketplace follows main - fast-forward main and push it, then run: $manual" -ForegroundColor Yellow
        return 'not-main'
    }
    if (-not (Get-Command $Cli -ErrorAction SilentlyContinue)) {
        Write-Host "deploy: '$Cli' is not on PATH - run: $manual" -ForegroundColor Yellow
        return 'no-cli'
    }

    Write-Host 'deploy: updating the plugin on this machine' -ForegroundColor Cyan
    try {
        & $Cli plugin marketplace update sza-unified-rules | Out-Host
        & $Cli plugin update 'sza@sza-unified-rules' | Out-Host
    }
    catch { Write-Host "deploy: the plugin update failed - $($_.Exception.Message)" -ForegroundColor Yellow }

    $cached = & $newest
    if ($cached -eq $pushed) {
        Write-Host "deploy: this machine now has plugin $pushed - restart open Claude sessions to load it" -ForegroundColor Green
        return 'updated'
    }
    Write-Host "deploy: the cache is still at $cached, the canon is at $pushed - run: $manual" -ForegroundColor Yellow
    return 'stale'
}

$null = Update-PluginCache -Root $root -Branch $branch -Skip:$NoPluginUpdate
exit 0
