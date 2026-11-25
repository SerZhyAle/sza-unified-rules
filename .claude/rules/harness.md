---
paths:
  - "tools/harness/**"
  - "tools/harness.ps1"
  - "r0.ps1"
  - "r1.ps1"
  - "r2.ps1"
  - "r3.ps1"
  - "rm.ps1"
  - "rs.ps1"
  - "rw.ps1"
  - ".claude/commands/**"
  - "templates/**"
---

# Payload, root files and harness

Moved verbatim from [CLAUDE.md](../../CLAUDE.md) on 2026-11-25. The always-on rules stay there, the documentation corpora included ("How the pieces fit").

- **One payload, four layers.** `rules/` (the reference), `skills/` (the procedures), `hooks/` (enforcement at
  the tool call, registered in `hooks/hooks.json`) and `tools/` (the gates and the harness) all ship in the
  plugin. A consumer runs them from its plugin cache (`~/.claude/plugins/cache/sza-unified-rules/sza/<version>/`),
  not from this checkout - which is why nothing here exists for an attended session until the version moves. The
  portfolio queue is the one exception: `pq` and every robot pass it starts run `tools/harness/` of this checkout,
  and the pass carries that folder as `SZA_HARNESS_ROOT`, so a saved harness edit is live for robots at once
  (a lib a worker already loaded - after that worker restarts) and absent for attended sessions until the deploy.
  `pq doctor` prints both folders and how many scripts differ in its `harness` line.
- **Two root files are the whole interface to a repository**, both contract-bound, both templated in
  [templates/](../../templates/README.md). `.sza-canon.json` is the stamp: what was adopted (canon version + the
  digest of `rules/*.md`), the role, overlay, channels and exemptions; `check-compliance.ps1` and the
  session-start hook read it. `.sza-profile.json` is the harness profile: paths, ticket and spec-file grammars,
  the status vocabulary, lock domains; it is read through `tools/harness/_profile.ps1`, and a key it omits
  keeps the canon default.
- **[tools/harness/](../../tools/harness/README.md) is the shipped process layer**, one folder per mechanism:
  `spec_catalog/` (the ticket ledger and its closing gates), `locks/` (ticket leases, domain locks), `batch/`
  (the repository runner: one fresh agent process per ticket), `scaffold/` (day 0), `portfolio/`, `releases/`
  (the release ledger's writer and read-only channel probes), and the smaller `document_registry/`,
  `all_features/`, `chat/`, `devlog/`, `aliases/`. A script body never carries a
  project's path, prefix or vocabulary - that is what `assert-portable.ps1` refuses. Each script finds the
  project root itself: `SZA_PROJECT_ROOT`, the first profile above the working directory, the first above the
  harness, then the first `.git`.
- **`portfolio/pq.ps1` is the dispatcher over every registered repository** ([operator's
  guide](../../tools/harness/portfolio/README.md)): `lib/` ranks the projects, picks one ticket and calls that
  repository's own `batch/run-spec-queue.ps1` for it. Its registry, queue file, logs and `runs.jsonl` live
  outside every repo, in `SZA_PORTFOLIO_ROOT` or `%USERPROFILE%\.sza\portfolio`; it never writes ticket status
  itself. `portfolio/gui/` is PQShell, the VB.NET panel over the same commands.
- **This repo is also a consumer of its own harness**, with its own profile, a `PLAN/` ledger and the
  `.claude/commands/` forwarders. `tools/harness.ps1` - and the `r1`-`r3`, `rs`, `rw`, `rm` launchers that go
  through it - resolves the **newest installed plugin cache, not `tools/harness/` in this tree**. To exercise
  an edit, call the script under `tools/harness/` directly or set `SZA_HARNESS_ROOT` to that folder; a green
  run through the forwarder proves the previous deploy. Inside a robot pass started by `pq` the forwarder resolves
  this tree instead, because the pass carries `SZA_HARNESS_ROOT`. Set that variable by hand for one command only,
  never in the user environment: a folder without `.sza-profile.json` would then take this repo for its project root.
