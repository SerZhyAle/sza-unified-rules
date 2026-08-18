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

## 2. When to commit

- **Commit or push only when the user asks**, or when a release/commit flow calls for it. Routine edits
  are left uncommitted for the owner to batch.
- **Never commit on the default branch** casually - branch first if a commit is needed and you're on
  `main`/`master`. **The one named exception is a site publish**: a Pages-served site deploys *from* the
  default branch, so its publish flow stages, commits with a dated auto-message, and pushes `main` by design
  ([SITE_CONFIGURATION.md](SITE_CONFIGURATION.md) §4). That carve-out covers the site publish only, not
  ordinary edits in a site repo.
- **Never** skip hooks (`--no-verify`), bypass signing, or force-push unless the user explicitly asks.
  If a hook fails, fix the underlying issue rather than bypassing it.

## 3. Commit & PR conventions

- **Language: English** for all commit messages, PR titles, and PR bodies (chat stays in the owner's
  language; see [AUTHOR.md](AUTHOR.md)).
- **Message shape:** a terse, imperative subject that says the user-visible change, not the mechanism.
  In a project with a ticket system, reference the ticket id.
- **Agent-authored commits carry a co-author trailer** so authorship is honest:
  ```
  Co-Authored-By: <agent> <noreply@…>
  ```
- **PR bodies carry the generator trailer** when opened by an agent (e.g. the "Generated with Claude
  Code" line). Keep bodies factual - what changed and why, honest caveats, no marketing.
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

- Never run `find` from a disk-wide root or without a depth bound in a shell tool - a dropped session
  can leave an orphaned scan flooding handles. Use the editor's file/content search or the project's
  catalog query instead. Enforce it with a pre-tool hook that blocks the call before the shell spawns,
  rather than trusting the convention.
- **Never put a PowerShell script in Bash command-head position** - `./build.ps1 -Release`,
  `.\a.ps1 fk`, `scripts/foo.ps1`. Bash cannot execute a `.ps1`: it chokes on the BOM plus the `<#`
  comment block and dies with a syntax error, **and a backgrounded task still reports exit 0** - so a
  failed build or a failed gate masquerades as passing. That is the worst shape a defect can take, because
  the false PASS is what gets read and reported. Route it through the interpreter:
  `pwsh -NoProfile -File ./build.ps1 -Release`. Reading a `.ps1` is fine - only the command-head position
  is the trap.
- **Always pass `-NoProfile`** when invoking PowerShell from a tool call: an operator's profile is not part
  of the contract, and loading it costs startup on every spawn.
- **Batch a multi-step shell chore into one process**, and mind which shell you are in. `& { cmd1; if
  ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; cmd2 }` is PowerShell syntax and a syntax error in Bash
  (`$LASTEXITCODE` is unset there and `& { .. }` backgrounds an empty group). From Bash, hand it to the
  interpreter: `pwsh -NoProfile -Command "& { cmd1; cmd2 }"`, or call one script per step.
- **Never put a PowerShell cmdlet in Bash command-head position** - `ls | Select-Object -First 3`,
  `Get-ChildItem -Recurse`, the same after a `;`. A `Verb-Noun` cmdlet is not a program on `PATH`, so Bash
  answers `exit 127` and returns nothing; measured on the reference machine, roughly **89 cmdlets were
  piped into the Bash tool in one week**, each one a turn that produced no output. Pipe to `head`/`sed`, or
  issue the whole line from the PowerShell tool.
- **An interpreter that is not installed on the machine is a dead command, not a convention** - and the
  cheaper fix is usually to *make the name work* (a shim onto `PATH`) rather than to guard it, because no
  hook can fix and retry a failed command.
- **An argument value beginning with a slash that names a command, not a path, is silently corrupted.**
  MSYS rewrites `-Reason "/spec-dev .."` into `C:/Program Files/Git/spec-dev ..` with **nothing failing**:
  the exit code stays 0 and the mangled text lands in exactly the files where that value was the only
  record of who was doing what. Three accepted forms: double the leading slash (`//spec-dev ..`), prefix
  the call with `MSYS2_ARG_CONV_EXCL='*'`, or issue it from the PowerShell tool.
- Prefer the project's own wrapper scripts over hand-rolled git/gh invocations with fragile nested
  quoting.
- **This whole family ships as one hook with the `sza` plugin**, in [`hooks/`](../hooks/README.md) - the
  `find` guard, the command-head guards for both a `.ps1` and a cmdlet, the missing-interpreter check and
  the slash-argument check are batched into a single script behind a single pre-filter, so five gates on
  the same event cost one interpreter start. They block the call before the shell spawns, in every
  repository, not only in canon adopters. A project does not need its own copy; see
  [AI_USAGE.md](AI_USAGE.md) section 5 for why an unenforced version of any of them is worth roughly
  nothing.
