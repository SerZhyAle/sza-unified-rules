<#
deploy.ps1 - stage everything in this repo, commit, push.

Operator tool: the owner runs it. An agent does not run it on its own initiative - committing and
pushing happen only when asked (INVARIANTS 18).

The repo's own gate runs first and there is no flag to skip it: `git add .` would otherwise sweep a
broken rules edit past tools/check-rules.ps1, which is the one thing CLAUDE.md requires before
anything under rules/ is committed. -Yes skips the confirmation prompt, never the gate
(INVARIANTS 9).

  pwsh -File deploy.ps1                      # gate, stage, confirm, commit, push
  pwsh -File deploy.ps1 "Fix the digest"     # same, with an explicit commit message
  pwsh -File deploy.ps1 -DryRun              # gate + show what would be committed, change nothing
  pwsh -File deploy.ps1 -Yes                 # no prompt (for a scheduled or piped run)

Exit codes: 0 = pushed, or nothing to push; 1 = gate failed, or a git step failed;
2 = cannot verify (not a repo, gate script missing, no remote).
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)][string]$Message,
    [switch]$DryRun,
    [switch]$Yes
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

function Fail([string]$text, [int]$code) {
    Write-Host "deploy: $text" -ForegroundColor Red
    exit $code
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
exit 0
