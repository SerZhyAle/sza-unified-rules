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

## Commands

Nothing is built. Everything is PowerShell 7 plus one Python checker, run from the repo root:

```powershell
pwsh -NoProfile -File tools/check-rules.ps1               # the canon's own text; the one gate that blocks a deploy
pwsh -NoProfile -File tools/check-contracts.ps1           # the contracts catalog (SZA_CONTRACTS_ROOT or the default)
python tools/docs/check-documents.py                      # both documentation corpora; writes nothing
pwsh -NoProfile -File tools/harness/assert-portable.ps1   # no project value inside a shipped harness script
pwsh -NoProfile -File tools/tests/<name>.tests.ps1        # one suite
python tools/tests/documentation.tests.py                 # negative fixtures of check-documents
pwsh -NoProfile -File hooks/tests/smoke-hooks.ps1         # hook verdicts - after a hook change
pwsh -NoProfile -File hooks/tests/smoke-prefilters.ps1    # the hooks.json pre-filters, under Git Bash
pwsh -File deploy.ps1 -DryRun                             # the gates + what would be committed and bumped
```

- **The first four are the fast list**; which of the rest may run after an ordinary edit is decided by the 5 s
  line under "Working here". A suite that is not in the measured list there is release tier until it is measured.
- **There is no test runner and no case filter - "one test" is one file.** Each `tools/tests/*.tests.ps1` is a
  standalone script that prints a PASS or FAIL line per case and exits 1 on any failure; its header comment lists
  the cases and says what it touches (most build throwaway repositories and a throwaway portfolio root, and
  take `-KeepScratch` to leave them for inspection).
- **`tools/check-compliance.ps1` judges an adopting repository, not this one** - it is run from that repo
  (`-Strict`, `-Json`). Here the stamp's `role: canon-home` switches the surface and overlay checks off.
- **`deploy.ps1` without `-DryRun` is the owner's tool.** It stages everything (`git add .`), commits and pushes
  the current branch; an agent runs it only when asked for that deploy.

## Working here

- **Gate before committing anything under `rules/`:** `pwsh -File tools/check-rules.ps1` (exit 0 required).
  It validates internal links, section numbering, `§` references and the house text style.
- **An ordinary edit gets checks of 5 seconds or less only** ([TESTING_AND_QA.md](rules/TESTING_AND_QA.md) §2). Do
  not run any test, suite or gate above 5 s after a normal modification - the owner switched them off on 2026-10-28
  and set the 5 s line for the whole portfolio on 2026-10-29. Measured on 2026-10-29 (a timed call of each): fast -
  `check-rules.ps1` 0.8 s, `check-contracts.ps1` 2.4 s, `check-documents.py` 0.6 s, `assert-portable.ps1` 1.1 s;
  release tier - `layout-gate.tests.ps1` 26.5 s, `portfolio-events.tests.ps1` 20.4 s, `ticket-id-grammar.tests.ps1`
  about 18 s, and from 2026-10-28 `ledger-rules.tests.ps1` 313 s, `portfolio-queue.tests.ps1` about 200-330 s,
  `smoke-portfolio-runner.ps1` 120-300 s, `batch-runner.tests.ps1` 163 s, and from 2026-11-13 `block-links.tests.ps1` 19 s. What stays is the fast list and a direct call of
  the function or script that was changed. A release-tier suite runs only when the owner asks for it by name. When a change
  is not covered by a fast check, say so in the report instead of running a slow one.
- **The deploy names all four fast checks** (from 2026-11-11): after `check-rules.ps1`, which blocks, it runs
  `check-contracts.ps1`, `check-documents.py` and `assert-portable.ps1` and prints each exit code, or `unavailable` with the
  reason when one cannot run. Those three are advisory and never change the exit code, so a red one is named at every deploy
  instead of being called "not mine" for weeks. [tools/tests/deploy-fast-gates.tests.ps1](tools/tests/deploy-fast-gates.tests.ps1)
  covers it with stubs.
- **The shared contracts catalog is at `P:\Contracts`** - the one place in this repo's prose that gives the
  path, besides [rules/CONTRACTS.md](rules/CONTRACTS.md) and the `contract-sync` skill, which teach the rule
  itself, and the three scripts that need a default to fall back on when `SZA_CONTRACTS_ROOT` is unset.
  Everywhere else a contract is cited by
  **id and section** (`FDSEC-FORMAT.md section 8`, `OCR-OVERLAY rule 4`) and never linked, because whoever
  clones a repo has no `P:` drive; `check-compliance.ps1` enforces that in every repo whose stamp role is
  not `canon-home`. The catalog's own law is its `_meta/RULES.md`; the canon side is the rule doc above,
  and the per-repo alignment run is the skill.
- **This repo owns four contracts.** `REPO-STAMP`, `HARNESS-PROFILE`,
  `REPO-LAYOUT` and `RULE-DELIVERY`, in the catalog's `rule-adoption/` domain, bind the machine-readable
  interface between the canon and a repository - the stamp, the harness profile, the names tools address,
  the version pair that decides whether a rule change arrives. The rules' own text is **not** a contract
  and never becomes one. Pointers are in [docs/contracts/](docs/contracts/), beside the pointers for four
  contracts outside that domain - `TASK-FLOW` (owner `shared`, implemented by the harness), `CHECK-VERDICT`,
  `DOC-INTERNAL-QUALITY` and `DOC-EXTERNAL-QUALITY` - whose roles are in that folder's README. Changing `.sza-canon.json`,
  `.sza-profile.json`, the three agent-rules filenames or the digest's coverage is a contract change, so
  the catalog moves first and the code follows.
- **Touching the catalog?** `pwsh -File tools/check-contracts.ps1` (exit 0 required) validates it: the
  governance pages, every domain's header block, the registry agreeing with it, expired exceptions, and
  links. The catalog is outside git, so nothing else can catch a broken edit there - the deploy runs this
  advisory, never as a blocker, because a machine without the drive must still be able to ship a rule fix.
- **Changing a rule doc changes the digest**, which marks every adopting repo stale. That is intended: the
  version raised alongside it lets the staleness ladder tell a minor reconciliation from a hard re-adoption.
- **The version pair is written by `deploy.ps1`, not by hand.** It calls
  [tools/bump-canon-version.ps1](tools/bump-canon-version.ps1) before staging, which is the only writer of
  [CANON_VERSION](CANON_VERSION) and of `.claude-plugin/plugin.json` `version`, derived from it:
  `2026.08.18.1` -> `2026.818.1` (semver forbids the leading zero, so the month and day join into one
  numeric identifier). The plugin version is what actually delivers the canon: `claude plugin update`
  compares that number and nothing else - not the digest, not the commit - so a canon change shipped
  without it leaves every consumer on the cached copy of the previous version while `update` reports
  "already at the latest version". `-NoVersionBump` is the way out for a commit that reaches no consumer;
  the deploy also skips the bump on its own when the whole change set is `README.md`, `LICENSE`,
  `.gitignore` or `rules/contrib/`.
- **The deploy also brings this machine's plugin to the pushed version** (from 2026-10-29): after the push, on `main`,
  when the cache is behind, it runs `claude plugin marketplace update sza-unified-rules` and `claude plugin update
  sza@sza-unified-rules` and checks that the cache reached the version. A failure only warns and prints the commands;
  off `main` it does nothing (the marketplace follows `main`); `-NoPluginUpdate` skips it. Open sessions keep what
  they loaded - restart them. [tools/tests/deploy-plugin-update.tests.ps1](tools/tests/deploy-plugin-update.tests.ps1)
  covers it with a stub `claude`.
- **This was a manual step until 2026-09-07 and it was missed twice.** The portfolio first ran five canon
  updates against a plugin cache frozen at `2026.07.27`, and no session anywhere loaded them; then, four
  days after that was written down here, `ec00587` shipped three `tools/harness/spec_catalog/` files under
  an already-installed version. Both the deploy and the plugin update reported success each time. The rule
  did not change - only who executes it.
- **A fix under `skills/`, `tools/` or `hooks/` ships the same way, and only that way.** The digest covers
  `rules/*.md` alone, so such a fix marks nothing stale and needs no reconciliation - but a consumer still
  runs the cached copy until the plugin version moves, and a broken skill command left in the cache is as
  invisible as a rule that never arrived.
- **Editing a skill**: the SKILL.md body is what loads on trigger; heavy payload goes in `references/`
  beside it. Keep the frontmatter `description` written in the words the owner actually uses to ask for the
  task, in both languages where that is how the request arrives - it is the trigger, not a summary.
- **Editing `tools/check-compliance.ps1`**: a new check earns its place only if it is mechanically decidable
  in an arbitrary repo, offline, with a near-zero false-positive rate. Verify a candidate against the real
  repos before shipping it; a check that cries wolf gets disabled, and then nothing is enforced.
- **`rules/contrib/<project>.md`** is the per-project record. A project session may append its own record
  here and nothing else.

## How the pieces fit

- **One payload, four layers.** `rules/` (the reference), `skills/` (the procedures), `hooks/` (enforcement at
  the tool call, registered in `hooks/hooks.json`) and `tools/` (the gates and the harness) all ship in the
  plugin. A consumer runs them from its plugin cache (`~/.claude/plugins/cache/sza-unified-rules/sza/<version>/`),
  never from this checkout - which is why nothing here exists for a consumer until the version moves.
- **Two root files are the whole interface to a repository**, both contract-bound, both templated in
  [templates/](templates/README.md). `.sza-canon.json` is the stamp: what was adopted (canon version + the
  digest of `rules/*.md`), the role, overlay, channels and exemptions; `check-compliance.ps1` and the
  session-start hook read it. `.sza-profile.json` is the harness profile: paths, ticket and spec-file grammars,
  the status vocabulary, lock domains; it is read through `tools/harness/_profile.ps1`, and a key it omits
  keeps the canon default.
- **[tools/harness/](tools/harness/README.md) is the shipped process layer**, one folder per mechanism:
  `spec_catalog/` (the ticket ledger and its closing gates), `locks/` (ticket leases, domain locks), `batch/`
  (the repository runner: one fresh agent process per ticket), `scaffold/` (day 0), `portfolio/`, and the
  smaller `document_registry/`, `all_features/`, `chat/`, `devlog/`, `aliases/`. A script body never carries a
  project's path, prefix or vocabulary - that is what `assert-portable.ps1` refuses. Each script finds the
  project root itself: `SZA_PROJECT_ROOT`, the first profile above the working directory, the first above the
  harness, then the first `.git`.
- **`portfolio/pq.ps1` is the dispatcher over every registered repository** ([operator's
  guide](tools/harness/portfolio/README.md)): `lib/` ranks the projects, picks one ticket and calls that
  repository's own `batch/run-spec-queue.ps1` for it. Its registry, queue file, logs and `runs.jsonl` live
  outside every repo, in `SZA_PORTFOLIO_ROOT` or `%USERPROFILE%\.sza\portfolio`; it never writes ticket status
  itself. `portfolio/gui/` is PQShell, the VB.NET panel over the same commands.
- **This repo is also a consumer of its own harness**, with its own profile, a `PLAN/` ledger and the
  `.claude/commands/` forwarders. `tools/harness.ps1` - and the `r1`-`r3`, `rs`, `rw`, `rm` launchers that go
  through it - resolves the **newest installed plugin cache, not `tools/harness/` in this tree**. To exercise
  an edit, call the script under `tools/harness/` directly or set `SZA_HARNESS_ROOT` to that folder; a green
  run through the forwarder proves the previous deploy.
- **Two documentation corpora, one checker** ([docs/DOCUMENTATION.md](docs/DOCUMENTATION.md)). The published
  one is declared by `docs/document-corpus.json` and `docs/DOCUMENT_REGISTRY.jsonl` and includes this file,
  so a link or a style slip here turns `check-documents.py` red; the local one under `dev/` is ignored by git.
  `docs/DOCS_MAP.md` is a render target: after adding a document run the checker with `--register --render`.

## Layout facts

- `.claude-plugin/` holds **both** `marketplace.json` and `plugin.json` - the repo is its own marketplace,
  with the plugin at `source: "./"`.
- Paths inside skills resolve through `${CLAUDE_PLUGIN_ROOT}` at run time and through relative links
  (`../../rules/...`) when read as files. Keep both working: a skill is read as a document *and* executed.
- `rules/` was moved here from the `sza.od.ua` site repo with its history intact (`git subtree split`). The
  site repo keeps a pointer, not a copy.
- **`.gitignore` is the only thing between a local file and the payload**, because the deploy stages
  everything. Local by design: `PLAN/` (this repo's tickets and ledger), `temp/`, the `dev/` registry files,
  the `PQ *.lnk` launchers and `/.sza-profile.json` - the harness looks for a profile above its own root, so a
  shipped one would become the project root of every consumer that has none.
- [AGENTS.md](AGENTS.md) is the Codex entry point: it defers to this file and repeats only the command list,
  so a command that changes here changes there too. `memory/` holds that agent's notes.

## Language

The portfolio language split has one home: [AUTHOR.md](rules/AUTHOR.md) "Language". The only repo-specific
note is that a Russian phrase inside a skill's `description` frontmatter is **trigger data the matcher needs**,
not prose - so it is not an exception to that rule, it is not prose at all.
