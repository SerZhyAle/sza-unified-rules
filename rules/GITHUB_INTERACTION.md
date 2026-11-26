# GitHub Interaction - git, releases, and the working tree

How to touch git and GitHub across every project. The rules are platform-neutral. Reconciled against
the portfolio; per-project records in `contrib/`.

## 1. The working tree is the source of truth

- **Current state is the live files, not git history.** These are solo repos where many tickets touch
  the same file over time, so `log` / `blame` / `diff` / `status` / `HEAD~N` mislead about *what the
  code is now*. Read the live files to know the present state.
- A dirty working tree is normal work-in-progress, not a problem to forensically explain. Do not open
  git history to reconstruct WIP.
- Use git history **only** on an explicit request or inside a release/commit flow - never as a default
  research step.
- **Tree state is not the agent's concern.** The owner works alone, with no feature branches and no
  merges; git exists to cut and publish releases. So outside a release/commit flow an agent does not:
  - mention, warn about, or summarize uncommitted, modified, untracked, or staged files - not at the
    start, not in the final report;
  - run `git status` / `git diff` to "check the state" before or after its work, or read the session's
    git-status snapshot as a task;
  - suggest a commit, stash or branch just to "get a clean base" before starting;
  - ask whose a change is, or pause because a file changed while it worked.
- **Changes the agent did not make are the current code, not someone else's problem.** Another session,
  another agent, or the owner may have edited any file; the file as it is on disk now is what the task
  works against. Build on it, and never narrow or refuse the task because of it. When such a change actually breaks the task - a red check outside the agent's
  own edit, a conflicting half-finished edit in the same function - say that in one line, naming the file,
  and carry on with what is in scope.
- **Git commands are the agent's to use as the work needs** - switching or creating a branch, stashing,
  restoring a file, rebasing. No hook refuses any of them. One carve-out: **parallel writer subagents in
  one shared tree** get disjoint file lists by name and run no git command and no shared-state run (a
  build, a catalog mutator, a closure); the dispatching session runs one central verification per wave.
- **The one place tree state matters is a release or commit flow**, and it is that flow's own gate, run
  by its script or skill (the `release` skill, a site publish, a `deploy` script) - not a check an agent
  adds on its own.

## 2. When to commit

- **Commit or push only when the user asks**, or when a release/commit flow calls for it. Routine edits
  are left uncommitted for the owner to batch.
- **Commits go on the checked-out branch** - in these repos the default branch, or the working branch
  where a repo keeps one beside its trunk. Do not create a branch for a commit unless the owner asks: there
  are no feature branches and no merges here (section 1), so nobody merges a side branch - a canon release
  pushed from one reached no session until `main` was fast-forwarded. This replaces an agent tool's
  built-in "if on the default branch, branch first".
- **Never** skip hooks (`--no-verify`), bypass signing, or force-push unless the user explicitly asks.
  If a hook fails, fix the underlying issue rather than bypassing it.

## 3. Commit & PR conventions

- **Language: English** for all commit messages, and for the title and body of a pull request to someone
  else's repository (chat stays in the owner's language; see [AUTHOR.md](AUTHOR.md)).
- **Message shape:** a terse, imperative subject that says the user-visible change, not the mechanism.
  In a project with a ticket system, reference the ticket id.
- **Agent-authored commits carry a co-author trailer** so authorship is honest:
  ```
  Co-Authored-By: <agent> <noreply@…>
  ```
- **A pull request goes only to someone else's repository** - a winget submission to
  `microsoft/winget-pkgs`, an entry in a directory or a list. Inside the owner's repositories none is opened:
  commits go straight on the checked-out branch (section 2). A PR body opened by an agent carries the
  generator trailer (e.g. the "Generated with Claude Code" line). Keep bodies factual - what changed and
  why, honest caveats, no marketing.
- Use the `gh` CLI for GitHub operations (PRs, issues, API); it reads the ambient auth at call time.

## 4. Releases vs site pushes vs plain commits

The three-way boundary (plain push - free; site publish - a Pages re-render; release - the one-way
versioned op that may cost money or become public) has one home:
[RELEASE_AND_DISTRIBUTION.md](RELEASE_AND_DISTRIBUTION.md) §1. The git-side rules:

- The authoritative published binary is the release-host asset, named from the version - never
  committed into the repo (see REPOSITORY_LAYOUT "Built binaries").
- Where "working tree is truth", build the release in a **dedicated git worktree**, not the main
  checkout, so a reproducible release never entangles with in-flight WIP.

## 5. Auth hygiene

- **A stale `GITHUB_TOKEN` in the environment is the top cause of push/auth failures** on these
  machines - clearing it lets the credential helper / keyring auth win (the site `deploy.bat` does this
  first). If a push fails auth, check for a stale token before anything else.
- No secret is ever committed; tokens are ambient and read at call time (policy home:
  [REPOSITORY_LAYOUT.md](REPOSITORY_LAYOUT.md) "Secrets").

## 6. Bash / tooling safety

- **No disk-wide or unbounded `find`**; prefer the editor's search - enforced by hook `guard-bash`, see
  [hooks/README.md](../hooks/README.md).
- **No `.ps1` in Bash command-head position** (`pwsh -NoProfile -File ./build.ps1`) - enforced by hook
  `guard-bash`, see [hooks/README.md](../hooks/README.md).
- **Always pass `-NoProfile`** when invoking PowerShell from a tool call: an operator's profile is not part
  of the contract, and loading it costs startup on every spawn.
- **Every tool call gets a fresh interpreter; only the working directory survives.** Shell state -
  variables, functions, dot-sourced modules, an activated environment - does not carry from one call to
  the next, so a command that depends on something an earlier call defined silently sees nothing rather
  than failing loudly. Two consequences. One: a chore that needs shared state must be batched into a
  single invocation (next bullet) or persisted to a file. Two: **do not try to build a warm shell to
  avoid the spawn.** Interpreter startup is 170-250 ms on Windows, while the turn it would have to save
  costs a full replay of the accumulated context - three orders of magnitude apart - and the harness has
  no persistent-session channel to read a result through in any case. What genuinely repays staying warm
  is the *build tool's* own daemon and its caches, which already persist because they are long-lived
  external processes: keep those alive, and stop looking for a faster shell.
- **Batch a multi-step shell chore into one process.** From Bash: `pwsh -NoProfile -Command "& { cmd1;
  cmd2 }"`; a bare `& { .. }` is refused by hook `guard-bash`, see [hooks/README.md](../hooks/README.md).
- **No PowerShell cmdlet in Bash command-head position** - enforced by hook `guard-bash`, see
  [hooks/README.md](../hooks/README.md).
- **An interpreter Bash cannot resolve is a dead command** (prefer a shim onto `PATH`) - enforced by hook
  `guard-bash`, see [hooks/README.md](../hooks/README.md).
- **A slash-command argument value is corrupted by MSYS** (`//name`, `MSYS2_ARG_CONV_EXCL='*'` or the
  PowerShell tool) - enforced by hook `guard-bash`, see [hooks/README.md](../hooks/README.md).
- **Three more silent Windows traps, none of them caught by a shipped hook.** A device path (`/sdcard/..`,
  `/data/local/tmp/..`) passed to `adb` becomes `C:/Program Files/Git/sdcard/..` even through a wrapper
  script, because MSYS rewrites the wrapper's arguments before it runs - same two ways out as above, the
  PowerShell tool or `MSYS2_ARG_CONV_EXCL='*'`. **Never probe an interpreter by running it**: a zero-length
  `WindowsApps\python3.exe` stub opens a modal "Select an app" picker on the owner's desktop instead of
  failing, so filter such stubs by file stat. **Never pipe a still-running writer through
  `Select-Object -First N`**: the pipeline closes early, the call returns in seconds with
  `$LASTEXITCODE` empty and the child carries on orphaned (a 141-insert catalog mutator was cut off this
  way); capture to a variable or a file first, then filter.
- **PowerShell reads the typographic quotes U+2018-U+201B as single quotes and U+201C-U+201E as double
  quotes**, so a Ukrainian word with the real apostrophe (`прев’ю`) inside a quoted string is a parse
  error: keep such text in a data file or build it with `[char]0x2019`. A negative `-split` limit splits
  from the end; use `[regex]::Split`.
- **The Bash and PowerShell tools resolve different PATHs.** A per-user install (`node`, `gh`, `rg`,
  `ffmpeg`, `claude` on the reference machine) may resolve only in the PowerShell tool, and a `pwsh` started
  from Bash inherits the short PATH. A "tool present?" branch gives the same verdict from either shell, or
  prints "cannot verify". `C:\WINDOWS\system32\bash.exe` is WSL, not Git Bash. A tool shell's environment is
  a snapshot taken at session start: an installer run since (a new `JAVA_HOME`) stays invisible until the
  session restarts.
- **Arguments through `pwsh -File` bind as strings.** A `[string[]]` parameter receives a comma list as one
  element, so split it inside; a `[bool]` refuses the string, so declare a `[switch]`; `-X:$false` arrives as
  two arguments through a forwarder that re-splats; an array splatted at a forwarder binds positionally.
  Non-ASCII text in a Bash-to-pwsh argument can silently do nothing - pass it through a file.
- **Bash quoting corrupts text without failing.** Backticks inside a quoted argument run as command
  substitution; `\$VAR` and `$false` inside a double-quoted `pwsh -Command` are expanded by Bash first; a
  heredoc collapses a doubled backslash, turns `\a` into BEL, breaks on an apostrophe and mangles Cyrillic.
  Author a file with the editor's write tool, not a heredoc (hook `guard-bash` limits its length).
- **Encoding across the shell boundary.** A child `pwsh`'s console output is cp866 while its arguments
  arrive intact, so verify text on disk, never from the echo; a script whose stdout is parsed as JSON writes
  raw UTF-8 bytes; in Git Bash `grep -c $'\r'` counts every line, and `grep -i` does not fold Cyrillic case.
- **A read-modify-write over real files never runs as an inline `pwsh -Command`.** Write a wrapper `.ps1`
  with `Set-StrictMode` and `$ErrorActionPreference = 'Stop'`, and run it with `-File`.
- **Never learn a script's interface by calling it.** A script with a write verb has no dry path; read the
  `param(` block of the copy that actually runs, resolving any forwarder first. A closure facade is never a
  probe: what it writes is permanent.
- Prefer the project's own wrapper scripts over hand-rolled git/gh invocations with fragile nested
  quoting.
- **The hooks named above ship with the `sza` plugin** and apply in every repository - see
  [hooks/README.md](../hooks/README.md).
