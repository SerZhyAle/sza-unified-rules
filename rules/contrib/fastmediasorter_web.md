---
# Contribution: fastmediasorter_web (FMS_Web; new overlay E drafted - a browser application served as static files) -> Unified_Rules
Source repo: P:\WEB\FastMediaSorter_WEB | Date: 2026-10-16
Read: NEW_PROJECT_CHECKLIST, PLATFORM_OVERLAYS, INVARIANTS, REPOSITORY_LAYOUT, the adopt-canon, contract-sync and task-flow-init skills, the catalog's RULES, VERSIONING and REGISTRY, rule-adoption sections 2-5; deduped against: contrib/tourist_mob.md, contrib/streamsplayer_mob.md
---

> **Owner decision, 2026-11-16:** `PLAN/` and its archive are local and ignored. Earlier statements below
> that the workspace is tracked describe the former policy.

FMS_Web gives people on systems the native programs do not serve - macOS, Linux, ChromeOS, iOS and iPadOS, and anyone
who cannot install a program - a subset of the functions of FMS_A and FMS_Win inside the popular browsers (owner,
2026-10-16). One slice is the client of the device-exchange server that FMS_Win hosts (account, devices, resources,
broadcasts, clipboard, operator administration - the scope of FastMediaSorter Android S4246, which created the
repository on 2026-10-15); the other works on the person's own files in the browser. No code is shared with either
program. The adoption mechanics are CONFIRM of `tourist_mob.md`. Genuinely new: **no overlay fits** - the first
portfolio product whose artifact is a web application, neither an installed program nor a product page.

> **Keep this note in the record.** Current facts, edited in place. Never append a dated section to this file,
> and append nothing under `history/` either: those files are frozen ([the rules of that folder](history/README.md))
> and are not reading for a task. A delta the core absorbed, a candidate that was applied or refused and a
> question that was answered are deleted here.

## Names (owner, 2026-10-16)

- **FMS_A** - FastMediaSorter for Android, `P:\ANDROID\FastMediaSorter_mob_v2`.
- **FMS_Win** - FastMediaSorter for Windows, `P:\WINDOWS\FastMediaSorter_Lite`, which also holds the device-exchange
  server under `exchange-server/`.
- **FMS_Web** - this repository.
- The catalog's living text writes FMS_Win since 2026-10-16 (the canon session's rename on the owner's order, a
  `correction` row per contract, no version bump); its records, the repository's handoff and `docs/origin/` keep the
  former label `FMS_W` (`DEVICE-EXCHANGE` item CX). The repository quotes those verbatim and never writes `FMS_W` in
  new text.

## Overlay facts (verified against this repo, 2026-10-16)

- **Source root & release-mechanics.** None yet: the stack (static ES modules, Go to WebAssembly, or TypeScript with a
  bundler) is open owner decision S0003; where the exchange page is served from is research ticket S0004 (evidence:
  `docs/BOOTSTRAP_HANDOFF.md` sections 4 and 5; the `modules` comment in `.sza-profile.json`).
- **Version shape.** None yet; `versionShape.tagRegex` null. Settled with S0004 and S0020.
- **Channels + listing files.** None - `channels: []`. `REPO-STAMP` rule 4's channel vocabulary has no value for a
  static host, a copy served by another product's server, or an installed web app.
- **Frozen anchors.** None reserved yet. The candidate is the origin of the public address (overlay E draft below),
  which FMS_A's portal page and Play account-deletion address will point at (S0019, S0020).
- **Editions + parity mechanism.** **Not declared as an edition**, on purpose. Reading: FMS_Web has the *shape* of a
  cross-repo edition (PLATFORM_OVERLAYS "Editions") - independent code and release, behaviour held in step through
  catalog contracts, never shared code. But the stamp's `editions` field lists the editions a repository itself
  ships: FMS_Win declares `["server"]` for its in-repo server edition, FMS_A declares `[]`, and neither names the other
  or FMS_Web. A one-sided `editions` entry here would claim a relation no sibling stamp records, and FMS_Web offers a
  subset of *two* products, not a second form of one. The parity mechanism is therefore the catalog alone: the
  contracts it implements, and a `PROPOSAL-<date>-<slug>.md` beside the closest contract for any first-release
  function that must behave like FMS_A or FMS_Win and has none (ticket S0010). If the canon wants the relation
  recorded, a family-level `editions` vocabulary is a canon change, not this stamp's.

## Channel-matrix rows (this project)

- None yet. Recorded when S0020 settles how the product is served.

## Deltas by document

### PLATFORM_OVERLAYS.md
- ADD (overlay E): the candidate NEW section below. Evidence: the stamp declares `overlay: ["E"]` with a `$comment`;
  SZA-CANON04 counts overlays and does not check the letter, so the declaration passes without a finding
  (`tools/check-compliance.ps1` around line 238).

### CONTRACTS.md
- CONFIRM: the catalog is named in one file (`CLAUDE.md` line 3); pointers under `docs/contracts/` with an index
  stating that no contract is owned here. `docs/BOOTSTRAP_HANDOFF.md` and the verbatim spec copy in `docs/origin/`
  name the catalog path; both are origin records, carried by dated SZA-CTR02 exemptions, as in `tourist_mob.md`.
- CONFIRM the sealing rule from the consumer side: every amendment the handoff asked to be "written in the catalog
  first" (a `product` value in item CE, the browser transport in 7.1, item D's browser wording, the operator surface)
  is a proposal to the owner, FastMediaSorter Android - ticket S0010.

### REPOSITORY_LAYOUT.md
- CONFIRM: `PLAN/` tracked with no remote, the DIVERGE of `streamsplayer_mob.md` and `tourist_mob.md`.
- ADD (name-based leak globs against a security product's vocabulary): the `*token*` and `*secret*` globs the canon
  asks for, and SZA-SEC02 checks, swallow any source file whose name holds either word - in a product whose domain is
  tokens and device secrets (`session-token.js`, `secret-box.js`) that is a silent non-commit. The repo records the
  trap in `CLAUDE.md` section 5; a canon note beside the glob list would serve every product with an auth module.

### RELEASE_AND_DISTRIBUTION.md section 8
- CONFIRM: the harness release plan stood up as shipped; package number from the `current-next-release:` marker (the
  repo works on `main`); `PLAN/` tracked. `release-queue -Validate` exit 0 and `-List -Ready` exit 0 on a fresh store -
  the empty-ready-file defect recorded in `tourist_mob.md` is fixed in plugin 2026.1015.4.

## No delta

INVARIANTS (beyond the overlay E equivalents below), NEW_PROJECT_CHECKLIST (overlay choice aside), AI_USAGE.

## Open questions for the owner

- Stack (S0003), public name, remote and visibility (S0021), site (S0022), where the exchange page lives (S0004),
  transport (S0005), certificate trust (S0006), operator sign-in (S0007), folders (S0017), broadcasts (S0015),
  deletion address (S0019) - each attached to its ticket and asked once, right before the phase that needs it.
- The first-release function set, the browser support floor (with "IE" read as Microsoft Edge) and the order of the
  local and exchange tracks - asked in S0002.
