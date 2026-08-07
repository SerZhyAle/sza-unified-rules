# SZA Unified Rules

One convention across every SZA project, delivered as **working skills** instead of documents nobody reads.

This repository is three things at once:

1. **The canon** - [`rules/`](rules/README.md) holds the shared conventions every project follows: repository
   layout, documentation, development discipline, testing, release and distribution, localization, security,
   support, agent usage, site configuration.
2. **A Claude Code plugin** - the process rules ship as [`skills/`](#the-skills), which are listed in every
   session automatically and load only when the task calls for them.
3. **Its own marketplace** - one command installs it, from any machine, in any repository.

## Why it is shaped this way

The canon existed for months as 18 markdown documents at a local path, referenced from each repo's rules
file. It did not work. The rules were fine; the delivery was not:

- **The canon was unreachable.** A local absolute path is invisible to CI, to a session on another machine,
  and to any outside contributor.
- **Nothing loaded it.** Only a repo's own `CLAUDE.md`/`AGENTS.md` is read automatically. Reaching the canon
  meant *choosing* to open ~200 KB of rules before starting work - which no one does, correctly.
- **So every repo re-grew its own copy of the process**, and one of them wrote down that it duplicates the
  canon *on purpose* so the repo stays self-contained. That is a fork, not a mirror.
- **Nothing could check compliance.** The old gate validated the canon's own text - never whether a project
  followed it. A rule that cannot be checked mechanically will drift. That is a law, not a shortcoming.

The fix is not more documentation. It is to stop treating the canon as documentation:

| Layer | What it is | When it loads |
| --- | --- | --- |
| [`rules/INVARIANTS.md`](rules/INVARIANTS.md) | 20 lines whose violation is expensive or irreversible | every session, in an adopting repo, via the [session-start hook](hooks/README.md) |
| [`hooks/`](hooks/README.md) | the behaviours the canon refuses to leave as prose | at the tool call, before the shell spawns |
| [`skills/`](#the-skills) | the process, as procedures with gates | when the task matches - the model picks |
| [`rules/`](rules/README.md) | the full reference | when a skill sends you there |
| [`tools/check-compliance.ps1`](tools/check-compliance.ps1) | the mechanical gate | manually, in CI, or from a hook |

## Install

```
/plugin marketplace add SerZhyAle/sza-unified-rules
/plugin install sza@sza-unified-rules
```

From a local clone, for development:

```
/plugin marketplace add P:/WEB/sza-unified-rules
```

Then adopt it in a project - once per repo:

```
/sza:adopt-canon
```

That writes [`.sza-canon.json`](templates/.sza-canon.json) at the repo root: the one machine-readable record
of the overlay, version shape, ledger shape, channels, site facts and exemptions that every skill and the
compliance gate read instead of guessing.

## The skills

| Skill | What it owns |
| --- | --- |
| [`release`](skills/release/SKILL.md) | the nine-phase release spine: classify, preconditions, pre-flight gate, coverage-regression gate, version cut, "what's new" fan-out **before** the tag, the one irreversible action, channel fan-out, post-release proof |
| [`store-publish`](skills/store-publish/SKILL.md) | GitHub Release, winget and Microsoft Store as three separate one-way operations, each with its own gates, traps and recovery paths |
| [`feature-to-site`](skills/feature-to-site/SKILL.md) | the ship-together fan-out: in-app strings, ledger, READMEs, the product site, support pages, listing sources, the hub - every locale in one edit |
| [`spec-to-audit`](skills/spec-to-audit/SKILL.md) | the task lifecycle from triage through spec, plan, implementation, evidence, self-audit, documentation and commit, with a refusing gate at each boundary |
| [`adopt-canon`](skills/adopt-canon/SKILL.md) | adopting or re-syncing the canon in a repository, and writing its stamp |
| [`agent-cost`](skills/agent-cost/SKILL.md) | measuring what a session actually costs, with the five corrections without which every token figure is inflated roughly threefold |
| [`caveman`](skills/caveman/SKILL.md) | terse mode - prose compressed, every exact string and every gate reason left intact; plus the commit and review shapes |

Skills carry their heavy payload in `references/` beside them, loaded on demand - the winget error table and
the Partner Center listing flow do not belong in every session.

## The hooks

The rule docs say four separate times that a behaviour is worth **enforcing at the tool call rather than
stating as a rule**. The canon used to ship none of those hooks, so each project either built its own or
went unprotected. Now [`hooks/`](hooks/README.md) carries them:

| Hook | Event | Blocks or warns about |
| --- | --- | --- |
| `session-start` | `SessionStart` | injects the hard invariants (adopting repos only) |
| `guard-find-command` | `PreToolUse` Bash | a `find` with a disk-wide root or no `-maxdepth` |
| `guard-ps1-in-bash` | `PreToolUse` Bash | a `.ps1` in command-head position - it fails yet reports exit 0 |
| `guard-uncapped-read` | `PreToolUse` Read | the first uncapped read of a file over 200 lines |
| `on-user-prompt` | `UserPromptSubmit` | context past 250k/400k; a micro-task reaching for the full pipeline |

The argument for all of it is one measurement, from [AI_USAGE.md](rules/AI_USAGE.md) section 5: gated rules
held at **~99%** across a month of sessions, the same rules as prose at **1-8%** - and the advice to read a
large file with a range, which ships in the tool description on *every* turn, measured **22%**.

Guards fail open, return `exit 2` to block, and keep an unconditional escape hatch; advisories always
`exit 0`. `SZA_HOOKS_OFF=1` stands them all down.

## The compliance gate

```powershell
pwsh -File tools/check-compliance.ps1              # the repo at the working directory
pwsh -File tools/check-compliance.ps1 -Strict      # warnings become errors
pwsh -File tools/check-compliance.ps1 -Json        # machine-readable
```

Exit codes: `0` clean, `1` violations, `2` internal error. Checks are grouped `CANON` (adoption and
staleness), `RULES` (canon pointer, no restatement, no self-declared fork), `LAY` (layout and ledger), `SEC`
(secrets and committed artifacts), `VER` (version shape and channel manifests), `SURF` (privacy page, SEO
block, sitemap), `STYLE` (house text style).

Two design choices matter:

- **Staleness is a digest, not a git SHA.** The digest covers the rule docs only, so a change to one
  project's contrib record can never mark every repo stale - which a SHA comparison would, on its first run.
- **Restatement is detected per bullet, with a canon-reference suppressor** - not by line count. A 500-line
  rules file that is all module architecture is clean; a 130-line file that re-authors the language policy is
  not. Pointing at a rule is correct; re-authoring it is the drift.

The canon's own text is checked separately by [`tools/check-rules.ps1`](tools/check-rules.ps1) - run it
before committing anything under `rules/`.

## Layout

```
.claude-plugin/     plugin.json + marketplace.json - this repo is both
rules/              the canon: INVARIANTS.md + 18 reference docs + contrib/ per-project records
skills/             the seven skills, each with its own references/
tools/              check-rules.ps1 (the canon) + check-compliance.ps1 (a project)
hooks/              the enforcement layer: invariant injection + three guards + the prompt advisories
templates/          .sza-canon.json - what a project copies when it adopts
CANON_VERSION       the monotonic version the stamp records
```

## Contributing to the canon

- Rule fixes land **here first**, then spread to repos - never the other way round.
- Run `pwsh -File tools/check-rules.ps1` (exit 0 required) before committing under `rules/`.
- A project's own record lives in [`rules/contrib/`](rules/contrib/) and is the one file a project session
  may edit here.
- Bump `CANON_VERSION` when a rule doc changes; that is what tells adopters to re-sync.
