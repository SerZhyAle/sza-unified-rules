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
  `main`/`master`.
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
- Prefer the project's own wrapper scripts over hand-rolled git/gh invocations with fragile nested
  quoting.
