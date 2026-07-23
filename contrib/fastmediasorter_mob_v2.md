# Contribution: FastMediaSorter_mob_v2 (Overlay B - Android; multi-flavor -> multi-channel; one edition of a cross-repo product) -> Unified_Rules
Source repo: P:\ANDROID\FastMediaSorter_mob_v2 | Date: 2026-07-23
Read: README, NEW_PROJECT_CHECKLIST, REPOSITORY_LAYOUT, DOCUMENTATION_CONCEPT, PLATFORM_OVERLAYS,
RELEASE_AND_DISTRIBUTION, CHANNEL_MATRIX, DEVELOPMENT, TESTING_AND_QA, GITHUB_INTERACTION, AI_USAGE,
AUTHOR, LOCALIZATION, SECURITY_AND_PRIVACY, SUPPORT_AND_FEEDBACK, SITE_CONFIGURATION; plus
contrib/epub_2_html.md, contrib/filedo.md (dedup).

This is the **reference repo the core was extracted from**, so most of Overlay B is already CONFIRM - the
deltas below are only the Android richness the generalization dropped and new transferable rules, deduped
against the two existing contrib files.

## Overlay facts (verified against this repo)

- **Source root & release-mechanics.** Gradle multi-module: `:app_v2` (app), `:wear` (Wear OS), `:lint-rules`
  (custom lint), `:benchmark` (macrobenchmark) (evidence: `settings.gradle.kts:42-45`). No `publishing/` -
  Gradle + the Play console are the release mechanics. Android-specific homes replacing the universal
  taxonomy: specs in `PLAN/Sxxxx_<slug>.md` via `scripts/spec_catalog/` CLI + `PLAN/spec-catalog.jsonl`;
  class navigation via the gitignored generated `dev/CATALOG/` (query before grep). Internal docs stay under
  `docs/` + `dev/` (not the `DEV/` umbrella epub/filedo use).
- **Version shape.** `versionCode` (monotonic integer, the Play update key) + `versionName`, in
  `app_v2/build.gradle.kts` - not a date tag. (Confirms Overlay B; distinct from the desktop date-stamp
  family in epub/filedo.)
- **Channels + listing files.** One codebase fans out to **three different stores plus a site**, driven by a
  6-flavor `version` dimension (evidence: `app_v2/build.gradle.kts:304-491`):
  - **Google Play** - `standard` / `lite` / `photos` / `legacy`, each its own listing/track; store-published
    flavors carry an `applicationIdSuffix` (`.lite` `.photos` `.legacy`, lines 407/433/462).
  - **Sideload (direct APK)** - `noLegal` (full VR + `SYSTEM_ALERT_WINDOW`/`specialUse`/a11y-capture surface,
    Play-review-risky, so sideload-only; lines 338-403, 601-667).
  - **Meta Horizon Store (Quest)** - `vr` flavor (lines 487-491, "Meta Horizon Store (the Store binds the
    listing identity to applicationId)").
  - **GitHub Pages site** - `jekyll-gh-pages.yml`.
  Listing text: Play store fields (no keyword field); the developer capability inventory is
  `docs/ALL_FEATURES.jsonl` (+ gitignored `docs/ALL_FEATURES_noLegal.jsonl` for the sideload superset),
  curated into `docs/FEATURES*.md` only at release.
- **Frozen anchors.** `applicationId = com.sza.fastmediasorter` + upload/signing key (Play App Signing).
  **Deliberate exception to "one id per channel":** `noLegal` and `vr` **share the base `applicationId`**
  with `standard` (they are not co-published to Play alongside standard, so no collision), while store
  flavors get a suffix (evidence: `build.gradle.kts:273-287` S0232 policy comment, 339-343, 488-491).
- **Editions + parity mechanism.** FastMediaSorter ships as **editions living in separate repos** - this
  Android app, `FastMediaSorter_Lite` (Windows), `fms_companion` (Go). Their parity is **not** an in-repo
  `docs/PARITY.md` + gate (the model the core "Editions" section assumes); it is a **frozen cross-project
  wire contract**: `.fmscfg` / `CONFIG_FORMAT.md`, byte-identical canonical vector on both ends, versioned
  by `schemaVersion` (producer frozen, consumer forward-tolerant) (evidence:
  `fms_companion/docs/CONFIG_FORMAT.md`; memory `fmscfg-contract-v2-forward-compat`).

## Channel-matrix rows (this project)

| Channel | Trigger | Cost | Auth | Signer | Listing source | Frozen anchor | Verify live |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Google Play (standard/lite/photos/legacy) | AAB upload to track (`a.ps1 r`, built in a dedicated worktree) | [PUBLIC] | Play console / androidpublisher API (read via `temp/play_status.py`) | Play App Signing | Play store fields; `docs/ALL_FEATURES.jsonl` -> `FEATURES*.md` | `applicationId` (+ `.lite/.photos/.legacy` suffix) + upload key | track shows build; staged rollout; **update over prior install** |
| Sideload / direct APK (`noLegal`) | `a.ps1 nl`/`nd` + GitHub/site asset | [PUBLIC] self-host | none | own release key | `docs/ALL_FEATURES_noLegal.jsonl` + site | `applicationId` (shared `com.sza.fastmediasorter`) | install + update on device |
| Meta Horizon Store / Quest (`vr`) | vr build upload | [PUBLIC] | Meta dev console | Meta / own | Meta listing | `applicationId` (shared base) | Quest store shows build |
| GitHub Pages site | push (`jekyll-gh-pages.yml`) | site publish | `gh` ambient | n/a | site content | n/a | pages live |

> Play verdicts are **not** API-readable (androidpublisher exposes track/bundle state only) - review status
> needs a console screenshot from the owner (memory `play-console-api-access`).

## Deltas by document

### PLATFORM_OVERLAYS.md
- ADD (Overlay B is thin): a single Android codebase fans out to **more than Play tracks**. Flavors map to
  **three distinct distribution channels** - Play (store flavors), sideload (`noLegal`), Meta Horizon Store
  (`vr`) - each a different signing/listing/review path. The overlay's "each flavor to its own track/listing"
  understates this (evidence: `build.gradle.kts:304-491`, 852 "Native build (vr/noLegal only)").
- ADD (multi-module surface, a third axis): `:wear` is a **separate installable surface** (Wear OS) in the
  same repo/build - neither a flavor nor a cross-repo edition; `:lint-rules` and `:benchmark` are
  tooling modules. The edition/flavor pair needs a third case: **sibling modules of one build** (evidence:
  `settings.gradle.kts:42-45`).
- ADD (deliberate shared applicationId): the frozen-anchor "one id ties update->install per channel" rule
  has a sanctioned exception - flavors that are **never co-published to the same store** may share one
  `applicationId` on purpose (`noLegal`/`vr` share `standard`'s) (evidence: `build.gradle.kts:273-287`).
- DIVERGE (Editions across repos): the core "Editions" section assumes one repo, multiple source trees,
  `docs/PARITY.md` + a drift gate. FMS's editions are **separate repos** kept in sync by a **frozen wire
  contract** (`.fmscfg`), not an in-repo parity doc. The core's "Editions" and "Cross-project contracts"
  sections describe the same product and should be cross-linked: cross-repo editions use the contract
  mechanism; in-repo editions use PARITY.md (evidence: `fms_companion/docs/CONFIG_FORMAT.md`).

### CHANNEL_MATRIX.md
- ADD: the matrix has no row for **Sideload / direct-APK** or **Meta Horizon Store / Quest** - two channels
  this product ships to. Sideload's distinctive facts: no store review (so it carries the Play-risky
  capabilities), self-hosted asset, self-signed, a gitignored feature inventory. Quest's: Meta binds listing
  identity to `applicationId` (evidence: `build.gradle.kts:338-403, 487-491`).

### DEVELOPMENT.md
- ADD (gate infrastructure, extends §9 beyond epub's "scoped allowlist"): three transferable gate-design
  patterns this repo runs. (1) **Ratchet baselines** - a gate counts existing findings and fails only on
  **net-new**, freezing debt and paying it down monotonically without a big-bang cleanup (evidence: Rule 19,
  `scripts/quality/assert-neuroslop.ps1`). (2) **Batched fast-gates** - neuroslop + deprecated-PM + listener
  + flavor + ticket-log run in **one process** (`a.ps1 fg` / `assert-fast-gates.ps1`) instead of N script
  spawns (evidence: §9 of CLAUDE.md). (3) **Diff-scoped dirty-tree closure** - `-ScopeToFile` fails only on
  findings in the changed file and downgrades project-wide ratchets to advisory, so a clean change closes
  without tripping on other tickets' in-flight WIP (evidence: CLAUDE.md §12 "Dirty-tree closure S0826").
- ADD (closure facade): mechanical closure is **one call** - `scripts/post-change.ps1` chains dev-log +
  catalog-sync + gates - not N hand-run rituals. Transferable: one facade command per project so "I changed
  a file, now what" has a single answer (evidence: `scripts/post-change.ps1`, CLAUDE.md §12).
- ADD (status-gated debug probe - a novel technique): a `Timber.d("Sxxxx: ..")` probe exists in code **iff**
  the ticket is in the `BlockNeedUserTest` state - inserted at the changed-flow entry before the test build,
  **deleted the moment the ticket leaves that state**, and **never present in a permanent/shipped log** (a
  fail-closed gate enforces no ticket id in permanent logs). A temporary probe whose lifetime is bound to a
  "needs device test" status, so probes can't ship (evidence: CLAUDE.md §2, `reference_ticket_log_gate`).
- ADD (PowerShell scripting hygiene, gated): **reachable exit codes** - under `$ErrorActionPreference='Stop'`
  a bare `Write-Error` throws, so any `exit N` after it never runs and the process reports 1 while the
  message still prints (survives review). Write `Write-Error $msg -ErrorAction Continue` before `exit N`; a
  script header must list the codes it returns. Every SZA project is PowerShell-driven, so this transfers
  (evidence: CLAUDE.md §7 S1070, `scripts/quality/assert-exit-contract.ps1`).

### DOCUMENTATION_CONCEPT.md
- ADD (a third internal-ledger shape): §2 now accepts Keep-a-Changelog **or** a prose dev-log (from epub).
  This repo runs a **structured, validated capability inventory**: `docs/ALL_FEATURES.jsonl`, one JSONL
  record per shipped capability, written via `scripts/all_features/add.ps1`, validated by `validate.ps1`;
  the curated public `docs/FEATURES*.md` is generated **only at release** from the inventory diff, and
  chronology comes from git history + release diffs (the old prose `FUNCTIONALITY.log` was retired). A
  queryable, machine-validated internal ledger, alongside the two prose shapes (evidence: CLAUDE.md §11,
  `docs/ALL_FEATURES.jsonl`).
- ADD (ship-together surfaces, mechanized as a gate): §5's surfaces manifest (from epub) is enforced here by
  a **settings doc-sync gate** - any change to a setting regenerates `docs/settings/settings-manifest.json`
  + `docs/SETTINGS_REFERENCE*.md` + annotations, or the build fails (`assert-settings-doc-sync.ps1`). The
  "surfaces move together" principle turned into a mechanical check for the settings surface (evidence:
  CLAUDE.md Rule 22).
- ADD (machine-queried doc registry): the "consult the document registry" loop (already in AI_USAGE §6) is
  backed by `docs/DOCUMENT_REGISTRY.jsonl` + `scripts/document_registry/query.ps1` (query by product area +
  change trigger) and `validate.ps1` / `generate.ps1 -Check` re-run when a registered doc changes - a
  queryable registry, not a prose index (evidence: `docs/DOCUMENT_REGISTRY.jsonl`, CLAUDE.md §5).

### TESTING_AND_QA.md
- ADD (a UI-flow tier above ad-hoc device drive): a **Maestro** e2e harness (`.github/workflows/maestro-tests.yml`)
  runs repeatable flows in CI. With an explicit triage rule: a Maestro FAIL is **often the harness, not the
  app** (a real device wipes config between runs), so a red gets read at the harness level before it's
  called a regression (evidence: `.github/workflows/maestro-tests.yml`, memory `prerelease-maestro-harness-flaky`).
- ADD (the device-test lifecycle bridge): the `BlockNeedUserTest` status (DEVELOPMENT delta above) **is** the
  gate between "code changed" and "human verified on hardware" - the ticket parks there with a live probe
  until the owner confirms on device, then the probe is removed and the status advances. A structured
  hand-off, not an informal "please test" (evidence: CLAUDE.md §2, `/spec-test-device`).

### AI_USAGE.md
- ADD (subagent MCP isolation): a spawned subagent gets `enable_mcp_tools = false` unless it must drive the
  UI/emulator, to avoid duplicate Node/MCP server instances. Transferable to any multi-agent project
  (evidence: CLAUDE.md §6 "Subagent MCP isolation").
- CONFIRM (resolves the epub/filedo tension): those repos reported agent memory as **per-user, not
  git-shared**. This repo is the counterexample the core §4 was written from - `.claude/agent-memory/<agent>/`
  **is committed and team-shared**. So the portfolio genuinely has **both** models; committed-vs-per-user is
  a per-project choice, not a single default (evidence: `.claude/agent-memory/android-rd-specialist/`).

### GITHUB_INTERACTION.md
- ADD (release build isolation): the release AAB is built in a **dedicated git worktree**, not the main
  checkout (`a.ps1 r`), so a release never entangles with WIP in the working tree. Transferable pattern for
  any repo where "working tree is truth" and releases must be reproducible (evidence: CLAUDE.md §9).
- ADD (find-safety is a hard hook, not convention): §6's "never run disk-wide `find`" is enforced by a global
  PreToolUse hook (`guard-find-command.ps1`, exit 2) that blocks the call before bash spawns - because an
  orphaned `find.exe` from a dropped session floods handles on Windows/MSYS (evidence: CLAUDE.md Rule 24).

### SECURITY_AND_PRIVACY.md
- ADD (native library as a policy/coverage constraint): a store may **ban on-demand native `.so` download**,
  forcing the `.so` to be bundled, and the native build is enabled only for some flavors (vr/noLegal) - so a
  native-dependency decision is simultaneously a store-policy and a device-reach decision, per flavor
  (evidence: `build.gradle.kts:852`, memory `native-so-bundle-standard-vs-ondemand-nolegal`).

### RELEASE_AND_DISTRIBUTION.md
- ADD (a third release shape between filedo's one-op and epub's edition fan-out): **one codebase, many
  flavors, many channels.** The release fans out across Play (4 flavor listings) + sideload + Meta Horizon
  Store, but from a single source tree (not independent editions). The coverage-regression gate (§3) applies
  **per flavor**: e.g. `legacy` exists solely to hold `minSdk 23` device reach - dropping it or raising its
  minSdk is a coverage regression even though the other flavors are unaffected (evidence:
  `build.gradle.kts:457-462`, memory `release-no-coverage-regression`).

## No delta
REPOSITORY_LAYOUT (this repo is the Android reference already captured, incl. the `PLAN/Sxxxx` + `dev/CATALOG`
notes), NEW_PROJECT_CHECKLIST, AUTHOR (same owner these rules were written from), SUPPORT_AND_FEEDBACK (the
`newlog`/`log-reader` intake is already the Android reference in §3), SITE_CONFIGURATION (standard Jekyll
Pages workflow; nothing epub/filedo/the core don't cover), LOCALIZATION (the `set-android-string.ps1` +
`check_strings_localized.ps1` parity tooling and EN/RU/UK set are already the core's Android reference; this
repo uses the ISO `uk`, confirming the core against filedo's non-ISO `ua`).

## Candidate core edits (PROPOSED - do not apply yet)
- **PLATFORM_OVERLAYS Overlay B**: flavors fan out across multiple stores (Play + sideload + Meta Horizon
  Store), not just Play tracks; add the sibling-module axis (`:wear`); note the sanctioned shared-`applicationId`
  exception. Prevents modelling Android as single-channel. Evidence: `build.gradle.kts:304-491`.
- **PLATFORM_OVERLAYS Editions + Cross-project contracts**: cross-link them - **cross-repo** editions sync by
  a frozen wire contract (`CONTRACT_*`/`.fmscfg`), **in-repo** editions by `PARITY.md` + gate. Prevents the
  false impression that all editions live in one repo. Evidence: `fms_companion/docs/CONFIG_FORMAT.md`.
- **CHANNEL_MATRIX**: add **Sideload / direct-APK** and **Meta Horizon Store / Quest** rows. Evidence: this
  project ships both.
- **DEVELOPMENT §9**: add the gate-infrastructure trio - **ratchet baselines** (fail on net-new only),
  **batched fast-gates** (one process), **diff-scoped dirty-tree closure** (`-ScopeToFile`) - and the
  **one-call closure facade** (`post-change.ps1`). Prevents each project reinventing gate plumbing and
  big-bang cleanups. Evidence: Rule 19, §9, §12, `scripts/post-change.ps1`.
- **DEVELOPMENT (new sub-point) or a "scripting hygiene" note**: **reachable exit codes** under PS `Stop`.
  Portfolio-wide PowerShell gotcha. Evidence: CLAUDE.md §7 S1070.
- **DEVELOPMENT §8 / TESTING §4**: the **status-gated debug probe** technique (probe exists iff ticket in a
  needs-device-test state; never ships; no ticket id in permanent logs). Evidence: CLAUDE.md §2.
- **AI_USAGE §3**: **subagent MCP isolation** (disable MCP tools for non-UI subagents). §4: record that
  **committed vs per-user memory is a per-project choice** (both exist in the portfolio). Evidence: CLAUDE.md
  §6; this repo commits `agent-memory`, epub/filedo do not.
- **DOCUMENTATION_CONCEPT §2**: add the **structured validated inventory** (`ALL_FEATURES.jsonl`) as a third
  internal-ledger shape feeding the curated showcase. §5: note a surfaces manifest can be **gated**
  (settings doc-sync). Evidence: CLAUDE.md §11, Rule 22.

## Candidate NEW docs (not in any shared doc yet)
- **QUALITY_GATES.md** (LOW confidence - may instead be a DEVELOPMENT §9 expansion): the gate subsystem is
  rich enough to arguably stand alone - ratchet-baseline authoring, the fast-gates batch, the post-change
  facade, diff-scoped dirty-tree closure, reachable-exit-code contract, and "promote a recurring finding to
  an `assert-*` gate". If §9 gets crowded, split it out; otherwise fold in. Evidence: `scripts/quality/`,
  `scripts/post-change.ps1`, CLAUDE.md §7/§12/Rule 19.

## Open questions - RESOLVED (2026-07-23, by owner instruction "как правильно так и сделай")
Universal truths folded into the core; Android-only specifics stay in this contrib file. Where each landed:
- **Editions across repos** -> `PLATFORM_OVERLAYS.md` "Editions" now states in-repo editions sync via
  `PARITY.md` + gate while **cross-repo** editions sync via a frozen `CONTRACT_*` wire contract; the
  "Cross-project contracts" intro now covers "two editions of one product living in separate repos".
- **CHANNEL_MATRIX sideload + VR-store rows** -> added both rows to the matrix, a combined per-channel
  playbook entry, and the overlay-usage note.
- **Shared applicationId across flavors** -> documented as a sanctioned exception in `PLATFORM_OVERLAYS.md`
  Overlay B frozen-anchors ("flavors never co-published to the same store may share one id").
- **Internal-ledger shape** -> `DOCUMENTATION_CONCEPT.md` §2 now lists the structured validated inventory
  (`ALL_FEATURES.jsonl`) as a third accepted shape, not the default.
- **Agent memory committed vs per-user** -> `AI_USAGE.md` §4 now states it is a per-project choice, both
  models valid, discipline identical.
- **Settings doc-sync gate** -> generalized into `DOCUMENTATION_CONCEPT.md` §5 (a generated ship-together
  surface is enforced by a gate), without naming Android.

Also folded (from the candidate-core-edits list): gate & closure mechanics as a **new `DEVELOPMENT.md`
§15** (ratchet baselines, batched fast-gates, diff-scoped dirty-tree closure, closure facade, reachable-exit
codes) + wired into `NEW_PROJECT_CHECKLIST.md` §4; the status-gated debug probe into `DEVELOPMENT.md` §8;
subagent MCP isolation into `AI_USAGE.md` §3; release-in-a-worktree and find-safety-as-a-hook into
`GITHUB_INTERACTION.md` §4/§6; the repeatable UI-flow harness + device-test handoff into `TESTING_AND_QA.md`
§4; the three release fan-out shapes + Android multi-store into `RELEASE_AND_DISTRIBUTION.md` §5.

## Candidate new doc - decision
- **QUALITY_GATES.md**: NOT created. The gate subsystem was folded into `DEVELOPMENT.md` §15 instead - no
  doc sprawl, no README index / read-order change needed. Revisit splitting it out only if §15 grows past a
  screen.
