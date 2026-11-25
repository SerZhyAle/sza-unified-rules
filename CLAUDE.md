# CLAUDE.md - sza-unified-rules (the canon and its plugin)

Agent rules for working **on** the canon. The canon's own content is in [rules/](rules/README.md) - read it
there; nothing is restated here.

## What this repo is

The single canonical home of the shared SZA conventions, shipped as a Claude Code plugin so the rules arrive
as auto-discovered skills in every session instead of as documents at a local path. See
[README.md](README.md) for the why and the install.

**Consumption model: this repo IS the source** - neither *reference* nor *mirror*, the two models a consuming
project picks between ([rules/README.md](rules/README.md)). "Never edit the canon from a project session"
does not apply here; this is where fixes land. It applies everywhere else.

## Read before touching

Detail lives in `.claude/rules/`. Claude Code loads a file when a matching path is touched; every other agent
opens it by hand first.

| Before you touch or do this | Read |
| --- | --- |
| a test suite, a gate, the tier registry, `check-compliance.ps1` | [tests-and-gates.md](.claude/rules/tests-and-gates.md) |
| `deploy.ps1`, the version pair, the release ledger, the plugin update, what ships | [deploy.md](.claude/rules/deploy.md) |
| the stamp, the profile, digest coverage, the contracts this repo owns, `docs/contracts/` | [contracts.md](.claude/rules/contracts.md) |
| `tools/harness/`, `pq`, the forwarder and root launchers, `templates/` | [harness.md](.claude/rules/harness.md) |
| a rule doc, a skill, `.claude-plugin/`, `AGENTS.md`, `memory/` | [canon-content.md](.claude/rules/canon-content.md) |

## Commands

Nothing is built. Everything is PowerShell 7 plus one Python checker, run from the repo root:

```powershell
pwsh -NoProfile -File tools/check-rules.ps1               # the canon's own text; the one gate that blocks a deploy
pwsh -NoProfile -File tools/check-contracts.ps1           # the contracts catalog (SZA_CONTRACTS_ROOT or the default)
python tools/docs/check-documents.py                      # both documentation corpora; writes nothing
pwsh -NoProfile -File tools/harness/assert-portable.ps1   # no project value inside a shipped harness script
pwsh -NoProfile -File tools/tests/<name>.tests.ps1        # one suite
pwsh -NoProfile -File tools/tests/run-tier.ps1 -List      # every gate and suite: tier, seconds, date
python tools/tests/documentation.tests.py                 # negative fixtures of check-documents
pwsh -NoProfile -File hooks/tests/smoke-hooks.ps1         # hook verdicts - after a hook change
pwsh -NoProfile -File hooks/tests/smoke-prefilters.ps1    # the hooks.json pre-filters, under Git Bash
pwsh -File deploy.ps1 -DryRun                             # the gates + what would be committed and bumped
```

- **`deploy.ps1` without `-DryRun` is the owner's tool.** It stages everything (`git add -A`), commits and pushes
  the current branch; an agent runs it only when asked for that deploy. A new untracked file or folder at the repo
  root stops it before anything is written (`-AllowNew` accepts one that is meant to ship).

## Working here

- **Gate before committing anything under `rules/`:** `pwsh -File tools/check-rules.ps1` (exit 0 required).
  It validates internal links, section numbering, `§` references and the house text style.
- **An ordinary edit gets checks of 5 seconds or less only** ([TESTING_AND_QA.md](rules/TESTING_AND_QA.md) §2). Do
  not run any test, suite or gate above 5 s after a normal modification - the owner switched them off on 2026-10-28
  and set the 5 s line for the whole portfolio on 2026-10-29. Which check is fast is recorded in
  [tools/tests/tiers.json](tools/tests/tiers.json) and nowhere else; `pwsh -NoProfile -File tools/tests/run-tier.ps1 -List`
  prints it. The line is per suite: `-Tier fast` runs every fast row in turn and its total is far above 5 s, so after an
  edit the call is the rows that cover what changed (`-Suite <name>`). What stays is the fast rows and a direct call of
  the function or script that was changed. A release-tier or unmeasured suite runs only when the owner names it, in chat
  or in the ticket being worked, and that run is `-Suite <name> -Measure`, which records the time. This file holds no
  time and no case count: a suite that a ticket adds gets its row from one such run in that ticket's pass, and a ticket
  text that asks for a clause or a count in a list here edits nothing in this file. When a change is not covered by a
  fast check, say so in the report instead of running a slow one.
- **The shared contracts catalog is at `P:\Contracts`** - the one place in this repo's prose that gives the
  path, besides [rules/CONTRACTS.md](rules/CONTRACTS.md) and the `contract-sync` skill, which teach the rule
  itself, and the three scripts that need a default to fall back on when `SZA_CONTRACTS_ROOT` is unset.
  Everywhere else a contract is cited by
  **id and section** (`FDSEC-FORMAT.md section 8`, `OCR-OVERLAY rule 4`) and never linked, because whoever
  clones a repo has no `P:` drive; `check-compliance.ps1` enforces that in every repo whose stamp role is
  not `canon-home`. The catalog's own law is its `_meta/RULES.md`; the canon side is the rule doc above,
  and the per-repo alignment run is the skill.
- **A contract change starts in the catalog.** Changing `.sza-canon.json`, `.sza-profile.json`, the three
  agent-rules filenames or the digest's coverage is a contract change, so the catalog moves first and the code
  follows. After a catalog edit `pwsh -File tools/check-contracts.ps1` must exit 0.
- **The catalog has its own local git history, and a session of this repo is its only committer** (one branch `main`, no
  remote, `.gitattributes` `* -text`, so no line ending is ever converted). Before the first catalog edit of a task:
  `git -C P:\Contracts add -A`, then `git -C P:\Contracts commit -q -m "Before <task>: the catalog as found"` - it records
  what the product sessions wrote since the last snapshot, and "nothing to commit" is a normal answer. After the last
  edit and a green `check-contracts.ps1`: the same pair with `-m "<task>: <what changed>"`. This is a standing commit
  flow, the one place a session of this repo commits without being asked, and it is never reported as tree state. When
  git answers that `index.lock` exists, another session is taking its snapshot: run the pair once more, and never
  delete the lock file. A consolidation round makes no backup copy, compares nothing by hand and audits no line
  endings: between the two snapshots `git -C P:\Contracts status --short` and `git -C P:\Contracts diff --stat` name
  every file the round changed, and a file whose line endings were converted shows every line changed.
  Never run there: `reset --hard`, `checkout --`, `restore`, `clean`, `stash`, `rebase`, `commit --amend`, a second
  branch, a remote, a push. A product session runs no git command in the catalog at all
  ([rules/CONTRACTS.md](rules/CONTRACTS.md); the catalog's `_meta/RULES.md` section 6).
- **Only a version bump delivers a change.** A fix under `rules/`, `skills/`, `tools/` or `hooks/` reaches an
  attended consumer session only when the plugin version moves. `deploy.ps1` writes `CANON_VERSION` and the
  `.claude-plugin/plugin.json` `version`; never edit either by hand. A changed rule doc also changes the digest,
  which marks every adopting repo stale - intended.
- **`rules/contrib/<project>.md`** is the per-project facts record, edited in place; its dated sections are
  appended to `rules/contrib/history/<project>.md`, which no skill reads. A project session may edit those two
  files of its own project here and nothing else; a change it wants anywhere else it files as a ticket in this
  canon (`spec-draft.ps1 -Project canon`), and a canon session decides.

## How the pieces fit

- `rules/` (reference), `skills/` (procedures), `hooks/` (enforcement, `hooks/hooks.json`) and `tools/` (gates and
  harness) ship in the plugin; a consumer runs them from its plugin cache, not from this checkout.
- **`pq` and every robot pass it starts run `tools/harness/` of this checkout:** a saved harness edit is live for
  robots at once (a lib a worker already loaded - after that worker restarts).
- **The forwarder does not run this tree.** `tools/harness.ps1` and the `r1`-`r3`, `rs`, `rw`, `rm` launchers resolve
  the newest installed plugin cache, so a green run through them proves the previous deploy. To exercise an edit,
  call the script under `tools/harness/` directly or set `SZA_HARNESS_ROOT` to that folder - for one command only,
  never in the user environment: a folder without `.sza-profile.json` would then take this repo for its project root.
- A harness script never carries a project's path, prefix or vocabulary; `assert-portable.ps1` refuses it.
- **Two documentation corpora, one checker** ([docs/DOCUMENTATION.md](docs/DOCUMENTATION.md)). The published
  one is declared by `docs/document-corpus.json` and `docs/DOCUMENT_REGISTRY.jsonl` and includes this file,
  so a link or a style slip here turns `check-documents.py` red; the local one under `dev/` is ignored by git.
  `docs/DOCS_MAP.md` is a render target: after adding a document run the checker with `--register --render`.

## Layout facts

- **`.gitignore` is what stands between a local file and the payload**, because the deploy stages
  everything inside the tracked top-level folders (a new path at the repo root is refused instead). Local by design: `PLAN/` (this repo's tickets and ledger), `temp/`, the `dev/` registry files,
  the `PQ *.lnk` launchers and `/.sza-profile.json` - the harness looks for a profile above its own root, so a
  shipped one would become the project root of every consumer that has none.

## Language

The portfolio language split has one home: [AUTHOR.md](rules/AUTHOR.md) "Language". The only repo-specific
note is that a Russian phrase inside a skill's `description` frontmatter is **trigger data the matcher needs**,
not prose - so it is not an exception to that rule, it is not prose at all.
