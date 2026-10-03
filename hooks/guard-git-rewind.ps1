<#
guard-git-rewind.ps1 - Claude Code PreToolUse hook (matcher: Bash|PowerShell), shipped by the sza plugin.

Refuses the git commands that REWRITE FILES ON DISK from history, so an agent cannot "fix the build" by
rolling the working tree back to a commit and destroying the uncommitted work of the owner and of every
other session sharing that tree.

Refused:
  checkout    (any form except creating a branch: -b / -B / --orphan)
  switch      (any form except creating a branch: -c / -C / --create)
  restore     (unless it is index-only: --staged without --worktree)
  reset       with --hard, --merge or --keep   (soft and mixed leave the files alone and stay allowed)
  clean       (unless -n / --dry-run)
  stash       (every subcommand except list and show)
  revert, rebase, cherry-pick, checkout-index, and `apply -R` / `apply --reverse`

Read-only history commands (log, show, diff, blame, status, ls-files, stash list ..) are not touched, and
neither are commit, tag, push, fetch, branch, add - the release flow needs those and they do not overwrite
files. Whether an agent should read history at all is a convention (GITHUB_INTERACTION.md section 1), not
something this hook decides.

Canon home: GITHUB_INTERACTION.md section 1 "The working tree is the source of truth". The prose there has
said "never revert it, never restore it from HEAD" all along and an agent still rolled two days of work back
to make a build pass; a rule stated only as prose holds at 1-8%, one enforced at the tool call at ~99%
(AI_USAGE.md section 5). This file is that enforcement.

The sanctioned way out is the OWNER running the command: a `!` prefix in the session runs it as the user and
never reaches a hook. An agent that thinks it needs a rewind says so and asks; it does not look for another
route to the same end (git show REV:path > path, git archive, a copy out of .git, another tool).

Applies in every repository, not only in canon adopters: the harm is the same wherever the plugin is
enabled. Escape hatch for a whole session: set SZA_HOOKS_OFF=1.

Contract:
  exit 2 = block the tool call (stderr is shown to Claude)
  exit 0 = allow
Fail-open on any parse error so a malformed payload never breaks a shell tool globally.

Exit codes (DEVELOPMENT.md section 15, reachable-exit-code contract):
  0  allow - nothing that rewrites files found, or the payload could not be judged.
  2  block - one of the commands above, named in the message.

Heredoc bodies are removed and quoted spans are blanked before the head check, so `git reset --hard` inside a
commit message, an echo or a heredoc is data. The one exception is a shell interpreter in head position
(bash -c '..', pwsh -Command ".."): its quoted argument IS a command line and is judged as one.
#>

function Allow { exit 0 }
function Deny([string]$msg) { [Console]::Error.WriteLine($msg); exit 2 }

if ($env:SZA_HOOKS_OFF -in @('1', 'true', 'TRUE')) { Allow }

# --------------------------------------------------------------------------- shared parsing
# Same two helpers as guard-bash.ps1; copied, not shared, because a hook is a standalone process.

function Remove-HeredocBodies([string]$text) {
    $lines = $text -split "`r?`n"
    $out = New-Object System.Collections.Generic.List[string]
    $tag = $null
    foreach ($line in $lines) {
        if ($null -ne $tag) {
            if ($line.Trim() -eq $tag) { $tag = $null }
            continue
        }
        $out.Add($line)
        $m = [regex]::Match($line, '(?<!<)<<-?\s*(?:''([^'']+)''|"([^"]+)"|([A-Za-z_][A-Za-z0-9_]*))(?!<)')
        if ($m.Success) {
            $tag = @($m.Groups[1].Value, $m.Groups[2].Value, $m.Groups[3].Value |
                Where-Object { $_ })[0]
        }
    }
    return ($out -join "`n")
}

# Split on command separators that sit OUTSIDE single/double quotes: | ; & ( ) ` and newline.
function Split-UnquotedSegments([string]$text) {
    $segs = New-Object System.Collections.Generic.List[string]
    $sb = New-Object System.Text.StringBuilder
    $inS = $false; $inD = $false
    foreach ($c in $text.ToCharArray()) {
        $ch = [string]$c
        if ($inS) { if ($ch -eq "'") { $inS = $false }; [void]$sb.Append($ch); continue }
        if ($inD) { if ($ch -eq '"') { $inD = $false }; [void]$sb.Append($ch); continue }
        switch ($ch) {
            "'"  { $inS = $true; [void]$sb.Append($ch) }
            '"'  { $inD = $true; [void]$sb.Append($ch) }
            '|'  { [void]$segs.Add($sb.ToString()); [void]$sb.Clear() }
            ';'  { [void]$segs.Add($sb.ToString()); [void]$sb.Clear() }
            '&'  { [void]$segs.Add($sb.ToString()); [void]$sb.Clear() }
            '('  { [void]$segs.Add($sb.ToString()); [void]$sb.Clear() }
            ')'  { [void]$segs.Add($sb.ToString()); [void]$sb.Clear() }
            '`'  { [void]$segs.Add($sb.ToString()); [void]$sb.Clear() }
            "`n" { [void]$segs.Add($sb.ToString()); [void]$sb.Clear() }
            default { [void]$sb.Append($ch) }
        }
    }
    [void]$segs.Add($sb.ToString())
    return $segs
}

# --------------------------------------------------------------------------- the judgement

$prefixTokens = @('sudo', 'time', 'nice', 'command', 'env', 'builtin', 'exec', '\')
# Interpreters whose quoted argument is itself a command line.
$shellHeads = @('bash', 'bash.exe', 'sh', 'sh.exe', 'zsh', 'pwsh', 'pwsh.exe', 'powershell', 'powershell.exe', 'cmd', 'cmd.exe')
# git's own global options that take a SEPARATE value token; every other leading dash token is a bare flag.
$gitOptWithValue = @('-C', '-c', '--git-dir', '--work-tree', '--namespace', '--exec-path', '--super-prefix', '--config-env')

function Test-AnyToken([string[]]$tokens, [string[]]$names) {
    foreach ($t in $tokens) { if ($names -contains $t) { return $true } }
    return $false
}

# Returns the offending form as text ("git reset --hard"), or $null when the call does not rewrite files.
function Get-RewindForm([string]$sub, [string[]]$a) {
    switch ($sub) {
        'checkout' {
            if (Test-AnyToken $a @('-b', '-B', '--orphan')) { return $null }
            return 'git checkout'
        }
        'switch' {
            if (Test-AnyToken $a @('-c', '-C', '--create', '--force-create')) { return $null }
            return 'git switch'
        }
        'restore' {
            # Index-only is harmless to the files: --staged and no --worktree.
            if ((Test-AnyToken $a @('--staged', '-S')) -and -not (Test-AnyToken $a @('--worktree', '-W'))) { return $null }
            return 'git restore'
        }
        'reset' {
            if (Test-AnyToken $a @('--hard', '--merge', '--keep')) { return 'git reset --hard' }
            return $null
        }
        'clean' {
            foreach ($t in $a) {
                if ($t -eq '--dry-run' -or $t -match '^-[A-Za-z]*n[A-Za-z]*$') { return $null }
            }
            return 'git clean'
        }
        'stash' {
            $first = @($a | Where-Object { -not $_.StartsWith('-') })[0]
            if ($first -in @('list', 'show')) { return $null }
            if ($first) { return "git stash $first" }
            return 'git stash'
        }
        'revert'         { return 'git revert' }
        'rebase'         { return 'git rebase' }
        'cherry-pick'    { return 'git cherry-pick' }
        'checkout-index' { return 'git checkout-index' }
        'apply' {
            if (Test-AnyToken $a @('-R', '--reverse')) { return 'git apply --reverse' }
            return $null
        }
    }
    return $null
}

function Get-FirstRewind([string]$text, [int]$depth) {
    foreach ($seg in (Split-UnquotedSegments $text)) {
        if ([string]::IsNullOrWhiteSpace($seg)) { continue }
        $s = $seg.Trim().TrimStart('(', '{', ' ')
        if ($s -eq '') { continue }

        $tokens = @($s -split '\s+' | Where-Object { $_ -ne '' })
        if ($tokens.Count -eq 0) { continue }

        $i = 0
        while ($i -lt $tokens.Count -and ($tokens[$i] -match '^[A-Za-z_]\w*=' -or $prefixTokens -contains $tokens[$i])) { $i++ }
        if ($i -ge $tokens.Count) { continue }

        $rawHead = $tokens[$i]
        if ($rawHead.StartsWith("'") -or $rawHead.StartsWith('"')) { continue }
        $head = $rawHead.Trim('"', "'")
        $headLower = $head.ToLowerInvariant()
        $rest = @(if ($i + 1 -le $tokens.Count - 1) { $tokens[($i + 1)..($tokens.Count - 1)] } else { @() })

        # A shell interpreter: judge each quoted argument as a command line of its own (one level only).
        if ($depth -lt 2 -and $shellHeads -contains ($headLower -replace '^.*[\\/]', '')) {
            foreach ($qm in [regex]::Matches($s, '(["''])(?<body>[^"'']*)\1')) {
                $found = Get-FirstRewind $qm.Groups['body'].Value ($depth + 1)
                if ($found) { return $found }
            }
            continue
        }

        if ($head -notmatch '(^|[\\/])git(\.exe)?$') { continue }

        # Walk past git's global options to the subcommand.
        $j = 0
        while ($j -lt $rest.Count -and $rest[$j].StartsWith('-')) {
            if ($gitOptWithValue -contains $rest[$j]) { $j += 2 } else { $j++ }
        }
        if ($j -ge $rest.Count) { continue }
        $sub = $rest[$j].Trim('"', "'").ToLowerInvariant()
        $subArgs = @(if ($j + 1 -le $rest.Count - 1) { $rest[($j + 1)..($rest.Count - 1)] } else { @() })

        $form = Get-RewindForm $sub $subArgs
        if ($form) { return $form }
    }
    return $null
}

# --------------------------------------------------------------------------- payload

try {
    $raw = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($raw)) { Allow }
    $cmd = [string](($raw | ConvertFrom-Json).tool_input.command)
} catch {
    Allow
}

if ([string]::IsNullOrWhiteSpace($cmd)) { Allow }

try {
    $form = Get-FirstRewind (Remove-HeredocBodies $cmd) 0
} catch {
    Allow
}

if ($form) {
    Deny("Blocked by sza guard-git-rewind (canon GITHUB_INTERACTION.md section 1): '$form' rewrites files on disk from git history. The working tree is the source of truth, and it holds uncommitted work - the owner's and that of every other session sharing it - that no command can bring back once it is overwritten. A red build is fixed by fixing the script or the change, never by rolling files back to a commit; if the cause is a change you did not make, say so in one line naming the file and fix forward. If the owner explicitly asked for exactly this operation, tell them the command and let them run it themselves with a '!' prefix. Do not reach the same end another way (git show REV:path > path, git archive, a copy out of .git, a different tool) - that is the same act under another name.")
}

Allow
