<#
deploy.ps1 - stage everything in this repo, commit, push.

Operator tool: the owner runs it. An agent does not run it on its own initiative - committing and
pushing happen only when asked (INVARIANTS 18).

The repo's own gate runs first and there is no flag to skip it: `git add .` would otherwise sweep a
broken rules edit past tools/check-rules.ps1, which is the one thing CLAUDE.md requires before
anything under rules/ is committed. -Yes skips the confirmation prompt, never the gate
(INVARIANTS 9).

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

Exit codes: 0 = pushed, or nothing to push; 1 = gate failed, the version bump failed, or a git step
failed; 2 = cannot verify (not a repo, gate script missing, no remote, version files unreadable).
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)][string]$Message,
    [switch]$DryRun,
    [switch]$Yes,
    [switch]$NoVersionBump
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

# --- 5. Say out loud whether this machine's plugin cache actually carries the version just pushed. --
# The cache is a directory named for the version, so a stale one is readable without a network call.
# This reports, it never fails: updating the plugin is the operator's action, not the deploy's, and a
# deploy that pushed correctly has done its job.
$cacheRoot = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.claude\plugins\cache\sza-unified-rules\sza'
if (Test-Path -LiteralPath $cacheRoot) {
    $pluginText = Get-Content -LiteralPath (Join-Path $root '.claude-plugin/plugin.json') -Raw
    if ($pluginText -match '"version"\s*:\s*"([^"]+)"') {
        $pushedVersion = $Matches[1]
        $cached = Get-ChildItem -LiteralPath $cacheRoot -Directory -ErrorAction SilentlyContinue |
            ForEach-Object { $_.Name } |
            Sort-Object -Property { try { [version]$_ } catch { [version]'0.0.0' } } |
            Select-Object -Last 1
        if ($cached -and $cached -ne $pushedVersion) {
            Write-Host ''
            Write-Host "deploy: the plugin cache on this machine is at $cached, the canon is now at $pushedVersion" -ForegroundColor Yellow
            Write-Host 'deploy: run `claude plugin update sza` - until then this machine keeps running the cached copy' -ForegroundColor Yellow
        }
    }
}
exit 0
