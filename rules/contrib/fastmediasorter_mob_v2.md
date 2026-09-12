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

## Spread-back applied 2026-07-23
- **Consumption model:** REFERENCE (owner-confirmed light-touch). No `docs/guides/` mirror created - this
  repo is the reference the core was extracted from, so mirroring the canon back into it would be circular.
- **What changed:** added a canon pointer to `CLAUDE.md` (top blockquote) and `AGENTS.md` §1 - both name the
  canon path (`Unified_Rules`, REFERENCE), state this repo is the reference the core came from, point to this
  contrib file for overlay facts + channel matrix, and declare the canon as source of truth for universal
  principles (fix them in a canon session, not here). No operational rule removed.
- **"Remove restated universal rules" - deliberate scope call (pushed back, owner chose light-touch):** applied
  literally, step 3 would have gutted `CLAUDE.md`'s operational manual (exact `a.ps1` targets, gate names, the
  6-flavor matrix, the Sxxxx spec/probe lifecycle). Those are repo-specific concretions, not redundant
  restatements of the generalized canon prose, and the canon is not a drop-in replacement for concrete
  commands. So nothing operational was trimmed; only the pointer + source-of-truth precedence were added.
- **Overlay facts re-verified against the live tree (still accurate):** 4 Gradle modules
  `:app_v2/:wear/:lint-rules/:benchmark` (`settings.gradle.kts:42-45`); `applicationId = com.sza.fastmediasorter`
  with the sanctioned shared-id exception for `noLegal`/`vr` (`app_v2/build.gradle.kts:219,274`); `a.ps1`
  launcher present. No drift found.
- **Open questions:** none remaining - all were RESOLVED 2026-07-23 (folded into the core, above).
- **Verification:** doc-only change; `scripts/document_registry/validate.ps1` PASS (23 records, exit 0); the
  touched registered document is `repository-rules` (covers `CLAUDE.md`/`AGENTS.md`, `generated:false` so no
  regeneration). Grep confirms 1 canon pointer in each file.
- **Canon-repo state:** this contrib edit is left uncommitted per the spread-back rule (step 8: do not commit
  the canon repo). No canon-doc fixes needed from this pass.

## Canon adoption 2026-07-27

Adopted as the `sza` plugin (consumption model **reference**). `.sza-canon.json`: overlay B, flavor shape,
ledger shape 3 (`docs/ALL_FEATURES.jsonl`), channels github/play, root-served site. The `release/` tag prefix
is recorded as a second clock - without it the version check misreads the newest tag and fails a good repo.

**Scoped commit** on branch `DEBUG-v030`: only `.gitignore` and the stamp. Twelve files of in-flight work were
left untouched.

Still open: three canon-owned rules remain restated in `AGENTS.md` (chat language, house text style,
find-safety). Removing them means editing a file that is mid-change, so it belongs to a session that owns that
work. `GEMINI.md` is git-ignored and local-only, so the gate correctly ignores it.

## Enforcement layer imported into the canon 2026-08-08 (canon `2026.08.08.1`)

The owner asked for the transferable skills and rules of this repo to be lifted into the canon and made
universal. The survey found that **the highest-value transferable asset was not a rule at all - it was the
enforcement**. The canon told projects four separate times to enforce a behaviour at the tool call rather
than state it as a rule (`AI_USAGE.md` section 3 twice, section 5 twice, `GITHUB_INTERACTION.md` section 6
once) and shipped **zero** such hooks. This repo had built all of them. Leaving them here meant they
protected one repository out of the portfolio, on one machine, wired through a machine-local
`~/.claude/settings.json` that no new checkout and no CI runner ever sees.

**Imported into the plugin's `hooks/`, generalized** (project rule numbers replaced by canon section
pointers, `dev/CATALOG` / `AGENT_COST_PLAYBOOK` / `temp/Sxxxx` references replaced by capability-neutral
wording, `SZA_HOOKS_OFF` escape added):

- `guard-find-command.ps1` - was CLAUDE.md Rule 24, now `GITHUB_INTERACTION.md` section 6. The contrib
  entry above ("find-safety is a hard hook, not convention") was folded into the canon as *prose* on
  2026-07-23; this closes it as *code*.
- `guard-ps1-in-bash.ps1` - was CLAUDE.md Rule 25. New canon bullet in `GITHUB_INTERACTION.md` section 6,
  because the exit-0 masquerade is the canon's "a green can lie" trap in its purest form and no review
  catches a false PASS.
- `guard-uncapped-read.ps1` - was wired against this repo's cost playbook; canon home is `AI_USAGE.md`
  section 3, which already demanded exactly this hook and its unconditional escape hatch.
- `nudge-small-task-tier.ps1` + the machine-global `warn-context-size.ps1` - merged into one
  `on-user-prompt.ps1`, because both fire on `UserPromptSubmit` and two interpreters would pay the
  PowerShell startup twice per prompt. Tier names generalized from this repo's `/quick` and `/skill-fix` to
  the canon's rung ladder (`spec-to-audit` stage 0), since no other repo has those commands.

**Also imported:** `/caveman`, `/caveman-commit` and `/caveman-review` merged into the canon skill
`caveman` - project-agnostic, and the never-compress list (security warnings, destructive confirmations,
ordered steps, every exact string, a gate's reason) is what makes terse mode safe rather than lossy.

**Rule fix found by the same pass:** `AI_USAGE.md` section 7 said "timestamp replies with the local time
provided in the prompt". This repo's CLAUDE.md section 1 had already refuted that in the field - the model
has no clock and the injection goes stale within minutes of any autonomous run, so the printed time was
wrong more often than right. The canon bullet now carries the refutation. This is the one place the source
repo was *ahead* of the canon on a universal rule rather than beside it.

**Deliberately NOT imported, with the reason** - so a later pass does not re-propose them:

- The `/spec-*` command family (14 commands, ~180 KB) and `/build`, `/git`, `/verify`, `/doc-update`,
  `/log-reader`, `/research`. Their *discipline* is already the canon's `spec-to-audit`, `release` and
  `feature-to-site` skills; what remains in the command bodies is gradle targets, `a.ps1` verbs, Sxxxx
  catalog CLI calls and flavor names. Porting the bodies would import the concretions, not the rules.
- `.claude/templates/*.md` (strategic spec, tactical index, phase file, compact bugfix). Kotlin paths,
  flavor placement rules, gradle gates - and the bugfix skeleton's body is written in Russian, which the
  canon forbids for an artifact. The transferable part (a step ends in a static predicate; every step
  carries a `Why`) is already `spec-to-audit` stage 2.
- `guard-catalog-before-kt-search.ps1` and `reset-catalog-touch-marker.ps1` - both assume a generated
  Kotlin class catalog exists. Not mechanically decidable in an arbitrary repo.
- The `android-*` subagents and `run-fastmediasorter` skill - platform-bound by construction.
- `document-registry` skill - the loop is already `AI_USAGE.md` section 6 and `spec-to-audit` stage 6; the
  skill body is three calls into `scripts/document_registry/`, which is this repo's tooling.

**Follow-up owed by this repo (not done here - it is a different session's work):** drop the now-duplicated
hook registrations, or the guards fire twice. In `~/.claude/settings.json` that is the `PreToolUse` Bash and
Read blocks; in this repo's `.claude/settings.json` it is the `nudge-small-task-tier.ps1` registration.
CLAUDE.md Rules 24 and 25 can then shrink to a canon pointer, since the hook they describe is no longer
this repo's.

## Release package plan - the reference implementation (2026-07-30)

The **release package plan** in [RELEASE_AND_DISTRIBUTION.md](../RELEASE_AND_DISTRIBUTION.md) §8 was designed
and proven here first, on overlay B, and generalized into the canon from this implementation. The canon carries
the concept only; this section is the concrete instance, so a reader can see one filled-in answer per decision
without treating PowerShell as part of the convention.

| Decision (canon / `adopt-canon` step 6) | This repo |
| --- | --- |
| (a) the three files | `PLAN/RELEASE_QUEUE.md` (work remaining), `PLAN/RELEASE_READY.md` (ready), `PLAN/RELEASE_QUEUE_DONE.md` (shipped history, newest first) |
| (b) single write path + reconcile hook | `Write-Catalog` in `scripts/spec_catalog/_lib.ps1` - the one function every status change already went through, so the reconcile came for free and no skill or `/spec-*` command knows the plan exists |
| (c) done-set | `Implemented`, `Verified`, `BlockNeedUserTest` - the third is the awaiting-verification status (a ticket parked on an owner device check), and including it is what keeps a hard-to-reproduce check from blocking the plan forever |
| (d) package number | from the working branch: `DEBUG-v030` -> package `30`; `--` is the not-scheduled bucket |
| (e) operator CLI | `scripts/spec_catalog/release-queue.ps1` - `list`, `list-ready`, `validate`, `reconcile`, `set-current`, `ship` (with a dry run) |
| (f) tracked or working artifact | tracked, so the plan is reviewable and travels with the branch |

Facts worth carrying that only showed up in practice here:

- **The awaiting-verification inclusion is the whole design.** `BlockNeedUserTest` tickets waiting on a device
  the owner does not always have to hand used to dominate the remaining-work list and make it unreadable. They
  are treated as shipped; the rare reopened one falls back below done and rides a later package.
- **Ship before the archive sweep.** This repo's cleanup sweep flips finished tickets to an archived state, and
  the reconcile drops archived lines - so running the sweep before `ship` deleted exactly the lines that
  recorded what the release contained. The ordering is in the canon (§8, and the `release` skill's Phase 8)
  because it was found the expensive way here.
- **The status-gated debug probe pairs with it.** `BlockNeedUserTest` already carries a live `Timber.d` probe
  (DEVELOPMENT delta above); the same status also means "counted as ready in the plan". One status, two
  mechanisms, and they agree.
- **Nothing in the convention is PowerShell.** `Write-Catalog` is where *this* repo's single write path
  happened to be; the transferable part is that there **was** one, and that the projection hangs off it.

## Spread-back applied 2026-08-02 - agent-process findings

Source: FastMediaSorter ticket S1342, propagating the umbrella S1338 and its three children S1339
(session boundaries), S1340 (gate or compress), S1341 (model routing). The underlying survey is
`dev/AGENT_PROCESS_AUDIT_2026-07-31.md` - 347 main plus 869 nested session transcripts over
2026-06-30..2026-07-31, 143 findings, adversarially verified.

**What changed in `rules/`:** [AI_USAGE.md](../AI_USAGE.md) only, in five places.

| Section | Change |
| --- | --- |
| §1 Operating principles | REPLACED the one-sided "background long jobs" bullet with a two-sided threshold rule. The old wording was the measured defect, not a neutral simplification: it drove backgrounding of checks that finish in seconds, and then hand-polling them - about 1,300 polling turns and 81 minutes of literal sleep in one month of one repo. |
| §2 Evidence over confidence | ADDED the three closure-facade invariants - the verdict covers every file in the change, PASS prints only when every gate passed, and the exit code separates "found a defect" from "could not verify". |
| §3 Cost & parallelism | ADDED six bullets: measure-first with a pointer to the new skill, the cost model, session boundaries as the primary lever plus the harness constraint that an agent cannot reset its own context, magnitude-not-fraction context reporting, two-tier model routing, and explicit-range reading. |
| §4 Persistent memory | ADDED a budget on the always-loaded index with a mechanical ratchet, expiry keyed to work-item liveness rather than age, and the written-more-than-read observation. |
| §5 Rules file & skill routing | ADDED gate-or-compress with its measurement, the 22% datum, and the driver-plus-reference shape for large command bodies. |

**House voice - a deliberate, narrow break.** This file cited no measurements before today; S1342 §2.1
asked for every propagated rule to carry its number. Both cannot hold, so the rule applied was: carry a
number only where the number *is* the argument, and strip it to a principle everywhere else. Two
numbers survived - **99% against 1-8%** for gated versus ungated rule compliance, and the **22%**
compliance on advice that already ships in the built-in tool description on every turn. Everything else
went in qualitatively ("dominates the bill", "roughly threefold", "far more often than it is read").
Anyone tightening this file later should cut the prose before cutting those two numbers.

**Invariant-grade: no, and the page said so first.** S1342 §3 item 3 asked whether anything here belongs
on [INVARIANTS.md](../INVARIANTS.md). The one candidate worth arguing was the transcript measurement
method, on the grounds that a wrong number propagates into every later decision. Rejected on the page's
own admission criterion - expensive, irreversible, or outward-facing. A wrong cost number is none of the
three: nothing ships, no user sees it, and the remedy is to measure again. The page's "What is
deliberately not here" paragraph already names *memory discipline* and *CI cost levers* as standing
exclusions, so the whole class was refused before this survey existed. The page is also exactly twenty
lines and says so in its own title and first paragraph; a twenty-first line means displacing one, not
appending, and nothing here displaces a release or security invariant.

**Portable tooling shipped, not copied.** Two new artifacts, neither of which is covered by the core
digest, so neither marks an adopting repo stale:

- `tools/mine-agent-transcripts.py` - the transcript extractor, stack-agnostic by construction (it reads
  Claude Code transcripts, which every project has, and names no language or toolchain). It was written
  that way from the start under S1338 §9 rather than ported afterwards, which is why this step was a
  copy rather than a rewrite.
- `skills/agent-cost/SKILL.md` - the method that makes the extractor trustworthy: deduplicate by
  `requestId`, walk nested subagent sessions, classify a hard failure by the error flag and never by a
  regex over a result body, segment on the compaction boundary. Without all four, token figures inflate
  roughly threefold and read-failure counts about twenty-five-fold. The skill also carries the two
  reading traps - a window that predates the change measures nothing, and an unchanged metric can be the
  correct answer.

**Overlay B deltas - stay here, not in `rules/`.** kapt-to-KSP migration, detekt configuration cache,
the flavor matrix, the `a.ps1` target list, the `assert-*` gate inventory, the Sxxxx lifecycle
mechanics, `post-change.ps1` parameters and the emulator harness are all Android or this toolchain. Per
S1342 §2.2 they are recorded as this project's shape and are not admissible to the core.

**Not propagated, deliberately.** Everything in S1338 §8, each item killed under adversarial
verification: prose and output trimming, within-segment re-read suppression, subagent-count tuning on
cost grounds, a prompt-submit context-pricing hook, command-surface deletion for token savings, and
decomposing a large build file on read-cost grounds. Carrying a refuted recommendation into ten projects
is worse than never having surveyed - it gives a measured non-problem permanent shelf space.

**Sequencing constraint broken, on the owner's explicit instruction.** S1342 §3 item 1 and §4 require
the corpus to be re-measured after the local changes have been live two weeks, so the canon receives
proven practice rather than a hypothesis. S1341 reached Verified on 2026-08-01; the window closes around
2026-08-15. The agent argued the case and the owner chose to propagate in full on 2026-08-02 anyway.
Recorded here rather than glossed, because it changes what the reader may rely on: **the methods,
invariants and observations above are measured; any tuned constant is not.** The one that matters is
S1339's context-reset threshold - the canon therefore states the *shape* of that rule ("stop at a
threshold and hand back a resume handle") and deliberately does **not** name a number, so the
unverified constant did not travel. Re-measure after 2026-08-15 and correct this entry if the local
result disagrees.

**Verification:** `pwsh -File tools/check-rules.ps1` - expected exit 0, actual **0** (19 core docs, 11
contrib docs). `pwsh -File tools/check-compliance.ps1 -RepoRoot <FMS>` after re-stamping - expected 0
errors, actual **0 errors, 1 warning**, and the warning is a pre-existing `...` in
`delivery/stream-catalog/README.md:148`, untouched by this work. `CANON_VERSION` 2026.07.30 ->
**2026.08.02**; core digest `sha256:74832f28..` -> **`sha256:6c247452..`**; both the canon's own
`.sza-canon.json` and FastMediaSorter's re-stamped to the new pair in the same pass.

**Downstream tail.** A `rules/*.md` edit changes the core digest, so all ten repos carrying a contrib
record are now one version behind and need an `adopt-canon` reconcile pass. That is intended, but it is
work: the propagation is not finished when this entry is written, it is finished when each repo has
re-stamped. FastMediaSorter itself is done. The `universal-agent-kit` repo is a second, different
target - `AI_USAGE.md`'s own preamble names it the fuller public distillation, and S1342 §3 item 8
leaves per-item admission there to the owner rather than making it an automatic consequence of this
change.

**Process note.** This propagation was authored from a FastMediaSorter session, not a canon session.
[README.md](../../README.md) and the canon's `CLAUDE.md` reserve edits under `rules/` to a canon session
and allow a project session to touch only its own contrib record. The deviation was the owner's
instruction to implement S1342 now; it is named here so the next reader does not infer that the
guardrail lapsed.

## Spread-back applied 2026-08-05 - measurement channels and ungated routing

Source: the FastMediaSorter mob_v2 process retrospective of 2026-08-05. Two findings, both universal - one
about how an agent measures its own process, one about how a routing rule behaves - and neither
Android-specific. This repo is where both were measured; the other nine stamped repos took the reconcile
pass off the back of it.

**What changed upstream:**

| Target | Change |
| --- | --- |
| `skills/agent-cost/SKILL.md` step 1 | ADDED a **fifth** measurement defect - consumption cannot be counted by tool name - at the same weight as the other four, plus a `Done means` line requiring any "never read" claim to name its channels and its population rule. The 2026-08-02 entry above says "four corrections"; that record is frozen, the count is now five. |
| [AI_USAGE.md](../AI_USAGE.md) §3 | The measure-first bullet now names five corrections and carries the tool-name trap in one sentence, so the rule is readable without opening the skill. |
| [AI_USAGE.md](../AI_USAGE.md) §5 | ADDED two bullets: the ungated size-tier measurement with the `UserPromptSubmit` remedy, and the same-event-opposite-verdict boundary that keeps the context-pricing refutation from being reused against it. |

### Finding 1 - consumption cannot be counted by tool name

The question was "is this artifact ever read again", and the instrument was a scan for `Read` calls whose
`file_path` matched. That is invalid for any artifact that is also written, searched, or read through the
shell, and this one is all three. Counted over the same corpus, paths inside a plan directory appeared as
`Edit.file_path` **2378** times, `Write.file_path` **762**, `Read.file_path` **740**, `Grep.path` **39** -
the instrument was watching the smallest channel. Worse than a bias: *executing* a step in this project is
an `Edit` that flips a `[ ]` checkbox to `[x]`, so the single event the metric existed to detect was the one
event it structurally could not see. Shell content reads - `head`, `sed`, `cat`, `Get-Content`,
`Select-String` - carry no `file_path` field at all and are invisible to any tool-name scan.

The headline moved from **"42% of tactical plans are never opened"** to **3.8%**. Sensitivity across channel
subsets on the same mature population: Read only **41.0%**, plus shell reads **25.6%**, plus `Grep` and
subagent reads but no `Edit` **11.5%**, all channels **3.8%**. Every variant that admits non-Read evidence
destroys the original figure, which is the part that makes this a defect in the method rather than a tuning
argument.

A second, independent error rode along with it: **population contamination**. The denominator was "any
directory named `<ticket>_*`", which swept in crash logs, screenshots, research notes and an owner voice
memo - **17 of 126** directories held no plan at all. Define the population by what the artifact *is*, never
by where it sits.

Why this earned canon space rather than a note here: the wrong number was an order of magnitude out **and it
was acted on**. That is the failure mode the whole `agent-cost` skill exists to prevent, and four defects
did not cover it.

### Finding 2 - a size-tier ordering written as prose does not route anything

This repo documents a smallest-first command tier in its always-on rules file: a micro-task command, then a
fast-fix command, then the full pipeline. Measured across the whole transcript corpus on 2026-08-05: **434
slash-command invocations, of which the micro-task command 0 and the fast-fix command 2, against the
pipeline commands 91 + 44 + 15.** The cheapest tier had never once been chosen in a month. It is the same
1-8% ungated-compliance figure the 2026-07-31 audit established, reproduced on a rule that was new - so the
figure is not an artifact of old habits outliving a rule change.

The remedy that went to the canon is a shape, not this repo's command names: put the nudge on
`UserPromptSubmit`, because **routing is decided the moment the owner types**. Match the prompt against a
short, high-precision micro-task pattern list, veto on a real-work list, drop anything past a length
ceiling, emit `additionalContext` naming the cheap tiers, keep it advisory, always exit 0 - a false fire
that refuses a prompt costs more than the miss it prevents.

**The boundary, recorded on purpose.** The 2026-07-31 audit killed a *context-pricing* `UserPromptSubmit`
hook as timing-blind: it reads accumulated context, and that tax accrues inside autonomous blocks where no
prompt is ever submitted, so the event misses exactly the case that costs. Routing is the inverse - the
decision genuinely happens at prompt submit. Same event, different question, opposite verdict. Without that
sentence in writing, the earlier refutation gets quoted to kill this hook too, and the canon carries it for
that reason alone.

**Honesty constraint, kept.** The hook went live on 2026-08-05 with **zero data behind its effect**. The
canon therefore carries the measured failure and the shape of the remedy and states explicitly that no
saving is claimed. `skills/agent-cost` step 4 forbids presenting a carry-forward as an effect, and the
earliest honest re-measurement is roughly three uncontaminated weeks out - call it **on or after
2026-08-26**, and correct the canon entry if the local result disagrees.

**Not propagated, deliberately.**

- [INVARIANTS.md](../INVARIANTS.md) was not touched. Its own "what is deliberately not here" paragraph
  already excludes this class, S1342 left it alone on the same reasoning, and neither finding is expensive,
  irreversible or outward-facing in the sense that page admits.
- No command names travelled. `/quick`, `/fix` and the `spec-*` pipeline are this repo's surface; the canon
  states the tier ordering and the event, and names nothing.
- No number for the pattern lists, the length ceiling, or the expected saving. The first two are unmeasured
  tuning constants; the third does not exist yet.

**This repo's pair.** `FastMediaSorter_release` shares this contrib record and was re-stamped in the same
pass. It carries the same 32-command surface and, unlike mob_v2, has **no `UserPromptSubmit` hook** - so the
ladder there is still entirely ungated. Named here because the shared record is the only place a reader
would find it.

**Verification:** `pwsh -File tools/check-rules.ps1` - expected exit 0, actual **0** (19 core docs, 11
contrib docs). `CANON_VERSION` 2026.08.02 -> **2026.08.05**; core digest `sha256:6c247452..` ->
**`sha256:8d33fdab..`**; all ten stamped repos re-stamped to that pair in one pass, each verified with
`check-compliance.ps1 -RepoRoot`. This repo: `check-compliance: FastMediaSorter_mob_v2 - 0 error(s), 1
warning(s) (overlay B, canon 2026.08.05)`, exit 0. Nine of the ten came back with zero errors; CyrFlip's
single error is the pre-existing store-listing typography recorded in its own file on 2026-08-02.

**Eleventh repo, not a reconcile target.** `universal-agent-kit` (`p:\WEB\universal-agent-kit`) carries a
contrib record but no stamp, so it took no reconcile pass here. Calling that a gap would be wrong: its own
record carries a dated 2026-07-27 decision to stay unstamped. It matters more after finding 2 than before
it, because the ungated `/quick` + `/fix` ladder in EPUB_2_HTML is imported from that kit - which puts the
kit upstream of the defect in every repo that imported it. See
[universal_agent_kit.md](universal_agent_kit.md), "Canon adoption 2026-08-05": that decision was reversed
the same day, on the owner's call, once the leak objection behind it turned out to be void.

## Spread-back applied 2026-08-08 - how an agent talks to the operating system

**Origin.** The owner asked three optimisation questions in one prompt: fire-and-forget the logging and
status-change commands instead of waiting for them, keep one warm terminal session ready so each command
does not pay for a new one, and make lookups serve pre-computed results instead of running a classic
command in a fresh shell each time. Two are wrong, one was already built. The **refutations** are the
contribution here - a measured "no" belongs in a canon at least as much as a new practice does, because
all three are ideas any agent will re-derive from first principles and none of them survives contact with
how the harness actually reaches the operating system.

**What travelled.**

- **[AI_USAGE.md](../AI_USAGE.md) section 1, "Never fire-and-forget a verdict."** The corollary the
  foreground/background threshold was missing. Backgrounding a gate does not save a turn, it adds one -
  the completion notification re-invokes the agent - and it silently demotes a gate into an ungated rule,
  which this record already measured at 1-8% against ~99%. The failure mode is a false PASS, so review
  does not catch it.
- **[GITHUB_INTERACTION.md](../GITHUB_INTERACTION.md) section 6, the shell process model.** Every tool
  call gets a fresh interpreter and only the working directory survives; shell state does not. Stated
  because its two consequences are what the owner's second question was really about: state must be
  batched into one invocation or written to a file, and **a warm shell is not worth building** - 170-250 ms
  of interpreter startup against a turn that replays the whole accumulated context, with no
  persistent-session channel to read a result through anyway. What repays staying warm is the build
  tool's own daemon, which already does.
- **[DEVELOPMENT.md](../DEVELOPMENT.md) section 15, two gate-economics bullets.** Cache the expensive
  gate's *clean* verdict under a fingerprint of exactly what it analysed - never a failure, never a scoped
  pass, and expire on age as well as fingerprint. And: a gate's measured duration is scheduling cost, not
  compute cost, unless you say which (152 s average against 25 s measured directly, same gate).
- **[`hooks/guard-fire-and-forget.ps1`](../../hooks/guard-fire-and-forget.ps1).** The first bullet as a
  `PreToolUse` guard rather than a paragraph, wired behind a bash pre-filter on the literal
  `"run_in_background":true` field so it never spawns on a foreground call. Deny-list by literal command
  shape, not heuristic, because a guard that over-blocks gets switched off; a long job on the same command
  line overrides it outright, since backgrounding *that* is required by the same canon bullet.

**What did not travel, and why.**

- This repo's literal fast targets (`a.ps1 fk|fc|fg|dq`) live in the guard's deny list, not in prose. A
  repository without those commands cannot match the string, so shipping them costs nothing and states
  nothing false - but they are not a portable rule and are not written as one.
- No [INVARIANTS.md](../INVARIANTS.md) change. None of this is irreversible, billable or outward-facing
  in the sense that page admits; it is operating discipline, which is exactly what the page excludes.
- No number for the guard's deny list or for an expected saving. The list is a judgement call and the
  saving is unmeasured.

**The process lesson, recorded because it cost real turns.** Three of the four optimisations recommended
in that chat answer - session-boundary resets, caching the expensive gate's verdict, batching the closure
facade over the whole changed set - were **already implemented**, two of them the same day. That was
discovered only by checking the tree before acting. Recommending from memory without verifying is the trap
[AI_USAGE.md](../AI_USAGE.md) section 2 already names, and the reference repo walked straight into it while
answering a question about efficiency. The rule earns its place again: a memory naming a mechanism is a
claim about when the memory was written, not about now.

**Verification.** `pwsh -NoProfile -File hooks/tests/smoke-hooks.ps1` - expected exit 0, actual **0** (20
cases, 6 of them new: 3 must-block and 3 must-allow). The pre-filter was exercised end to end through the
same `case` snippet the wiring uses, in both the compact and spaced JSON forms - blocked with exit 2, and
skipped the spawn entirely on a foreground payload. `CANON_VERSION` 2026.08.08.1 -> **2026.08.08.2**.

## Spread-back applied 2026-08-18 - locks, tiers, hook verdicts, an inventory gate, and two token shapes

Source: a propagation brief prepared from a FastMediaSorter mob_v2 session on 2026-08-18 and **executed
from a session started in the canon repo** - so, unlike the 2026-08-02 entry, the guardrail did not have
to bend: nothing outside `rules/contrib/` was edited from a project session. Owner decision the same day:
propagate all six items, and do the edit from a canon session.

Six findings, all universal, none Android-specific. Four of them the canon was already arguing against
itself: it carried the `& { .. }`-in-Bash trap as **prose** while measuring in the next document that
prose holds at 1-8%; it shipped an enforcement layer in `2026.08.08.1` and wrote no rule that the layer
stays described; its read guard **blocked** where the reference machine had already measured blocking to
be the wrong verdict; and the words "Opus" and "Carrier" appeared nowhere in it at all.

**What changed upstream:**

| Target | Change |
| --- | --- |
| [DEVELOPMENT.md](../DEVELOPMENT.md) 10 | The single "serialize expensive shared operations" bullet - which described the **refuse**-shape - now leads into thirteen rules for a lock **queue**: queue rather than refuse, a distinct exit code for "queued", the explicit lock-free work list, hold the lock around the edit and not the task, ticket identity over session identity, a bounded head-of-queue reservation, liveness per lock kind with a PID-reuse defence, eviction by liveness OR ceiling with "undetermined" never grounds for it, an environment check before the queue, a marker-file verdict for a background waiter, re-entrancy, and the shared git directory in a multi-worktree checkout. |
| [DEVELOPMENT.md](../DEVELOPMENT.md) 8 | ADDED four bullets: the literal direction token (an id in prose is a mention, an id in the token is a claim), the closure rule for unanswered questions with its 8.9% measurement, gate-the-transition-not-the-state with the archive carve-out and the placeholder rule, and wire-the-gate-into-every-mutator with heading-text-not-number. |
| [AI_USAGE.md](../AI_USAGE.md) 3 | ADDED the subagent tier rule. The built-in general-purpose agent has no definition file, so it **cannot be pinned at all** - the remedy is naming the tier at the call site or routing to a pre-pinned agent, not "pin the agent". |
| [AI_USAGE.md](../AI_USAGE.md) 5 | ADDED the verdict preference order - correct the input where the correct input is knowable, refuse only where no correct input exists - with the 381-fires / 31.8%-wasted measurement, the three rewrite mechanics, and the fail-open-harder rule. ADDED the hook-inventory rule and the test-the-pre-filter rule. The "canon now ships the hooks it asks for" bullet gained the installed-cache warning. |
| [GITHUB_INTERACTION.md](../GITHUB_INTERACTION.md) 6 | ADDED three bullets - the cmdlet in command-head position with its ~89-in-a-week measurement, the interpreter that resolves nowhere (with the canon's preference for shimming over guarding), and the MSYS slash-argument corruption with its three accepted forms. The closing bullet now describes one batched guard rather than two. |
| `hooks/guard-bash.ps1` | NEW, and it **absorbs** `guard-find-command.ps1` and `guard-ps1-in-bash.ps1`, which are deleted. Five refusal checks plus the slash-argument check in one script behind one pre-filter. |
| `hooks/guard-uncapped-read.ps1` | REWRITTEN from blocking to **rewriting**: `permissionDecision: allow` plus a complete `updatedInput` carrying an injected `limit`, plus the notice in `additionalContext`. |
| `hooks/README.md` | REWRITTEN around an `## Inventory` table with a verdict column, plus the verb vocabulary, the contracts for every shape including the two the canon documents but does not ship, and the installed-cache trap. |
| `tools/check-compliance.ps1` | ADDED group `HOOK` (`SZA-HOOK01` registered-but-not-inventoried, error; `SZA-HOOK03` orphan script, warn) and `SZA-CANON07` (a stamp claiming a version ahead of the canon's own, error). |
| `hooks/tests/smoke-prefilters.ps1` | NEW - asserts the **registered pre-filter patterns**, recovered from `hooks.json` and run under Git Bash. The canon had no equivalent. |
| `skills/agent-cost/SKILL.md` step 5, `skills/spec-to-audit/SKILL.md` stages 1 and 7 | Cross-references, each stating what the measurement does *not* prove. |

### The design objection in the brief, and how it was resolved

The brief asked the executing session to justify itself if it did **not** batch the new Bash checks into
one process, because the canon's own precedent points that way. It batched them, and went one step
further: the two pre-existing Bash guards were absorbed too, so the event carries **one** registration
rather than three. The second reason turned out to be stronger than the latency one - three of the five
checks need the same quote-aware segmentation and heredoc stripping, so separate scripts would have
carried three copies of that parse. One behaviour changed as a side effect, recorded rather than hidden:
heredoc bodies are now stripped before the `find` check as well, so a heredoc body containing a `find`
line writes a document instead of being refused. That is a relaxation, and the right one.

### Deviations from the brief, each deliberate

- **A seventh verb.** The brief's vocabulary has six - refuses, rewrites, observes, warns, nudges, arms.
  The canon ships a `SessionStart` hook whose entire verdict is "here is context you did not ask for",
  which none of the six describes, so **injects** was added and marked as the canon's own addition.
- **The read guard's threshold moved from 200 lines to 500.** The old number was chosen when acting cost
  the caller a whole turn; rewriting costs nothing, so the threshold moved to where the cost actually is,
  and 500 is the canon's own "large file" line ([DEVELOPMENT.md](../DEVELOPMENT.md) 3). Stated plainly
  because it **reduces what the guard touches**: an uncapped read of a 300-line file is now allowed
  through untouched where it used to be blocked.
- **The observe, arm and turn-refusing hooks are documented but not shipped.** Their contracts are in
  `hooks/README.md` because a contracts section claiming to describe the shapes a hook can take must
  actually describe them; the implementations stay downstream, where the brief itself places them.
- **`SZA-HOOK02` was written, tested, and then deleted.** It reported an inventory row the gate could not
  match to a registration. That is wrong in every real repo: a hook registered in a machine-local
  settings file is live and correctly listed, and the gate deliberately never reads that file, so every
  such row was a false phantom. The brief's own rule - degrade to one direction where the other half is
  not readable - is why it went.

### The gate was wrong first, which is the part worth recording

`SZA-HOOK01` was written to look for the inventory in `hooks/README.md`. Its first run against **this
repo** reported "6 hooks registered, no inventory table" - against a repo whose inventory has lived in
`docs/AGENT_HOOKS.md` since `2026.08.08.1`, complete, with the verdict column this pass then copied
upstream. A check that cries wolf gets disabled, and then nothing is enforced. The fix: find the table by
its **heading**, not by a filename, across a bounded candidate set, and where several documents carry an
"Inventory" heading, pick the one naming the most registered scripts.

A second false positive died the same way one step earlier: the first version read script names out of
the raw text of `hooks.json`, whose `description` field legitimately names other scripts - so the gate
invented three registrations that did not exist. It now reads the parsed command strings only. Both
failures are the failure the rule itself is about, one level up: **parse the structure, never the prose.**

### Two pre-existing defects found in the gate while running it

- A stamp with no `site` key crashed `check-compliance.ps1` with exit 2. `@($stamp.site.pages)` over a
  missing key yields a one-element array holding `$null`, so the path resolved to the repo root and
  `Get-Content` was handed a directory. Fixed in four places. No stamped repo hit it, because every one
  of them declares a `site` block - which is why it survived this long.
- `-Only` and `-Skip` do not accept a comma-separated list through `pwsh -File`: `-File` passes arguments
  as literal strings, so `-Only A,B` binds one element `"A,B"` and silently filters out everything. Not
  fixed - it is a property of `-File`, not of the script - but recorded, because the failure mode is a
  run that reports zero findings and looks clean.

### Honesty constraints, stated rather than glossed

- **No effect data exists** for the lock queue, the hook-inventory gate, the tier-routing rule or the
  cmdlet/interpreter/slash guards **as canon rules**. What is measured is the failure each was built for,
  never the improvement each produced. `skills/agent-cost` step 4 forbids presenting a carry-forward as
  an effect, and the earliest honest re-measurement is a fresh mining pass after these have been live.
- **The tier finding is a measurement wrapped around a deduction, and the canon says so in the rule
  itself.** Measured over 2026-08-03..2026-08-17 (1 150 sessions, ~54 700 requests): the unpinnable
  built-in was the most-spawned subagent type at **182 spawns in 14 days**, and output tokens split
  **34.29 M expensive against 7.13 M mid**, 82.8% expensive. That those spawns carried that 82.8% is a
  deduction - the miner never correlates a model to a spawn. The brief's own prose said "five of six"
  local agents carry a pin; the working tree says six of six, and the undercount did not travel.
- **Every constant from the lock queue stayed downstream.** The reservation windows, the ticket ceilings,
  the staleness minutes and the unreadable-ticket grace period are tuning constants nobody measured. The
  canon states the shape and omits the number, exactly as the two prior spread-backs did.
- **The measured numbers that did travel**, because they are observations rather than settings: the 479
  seconds one lock was held across a phase, the ~89 cmdlets piped into Bash in a week, 381 blocks in a
  week with 31.8% answered by reading the whole file anyway, 134 of 1 506 closures carrying an open
  question (8.9%), and 98 files yielding an id against 15 carrying a direction. Each travels with its
  corpus.
- **[INVARIANTS.md](../INVARIANTS.md) was not touched**, on the precedent of both prior spread-backs:
  none of this class is expensive, irreversible or outward-facing in the sense that page admits.
- **No command names travelled.** No spec ids, no slash commands, no script names from this repo.

### A defect found here that belongs to this repo, not to the canon

The local documentation for the lock queue lists three outcome-marker values (`granted` / `timeout` /
`evicted`); the code writes a **fourth**, `enqueue-failed`. A reader branching on the documented three
treats a failed enqueue as an unknown state. Recorded here so it is not lost - the canon's version of the
rule now says a marker must carry "a closed set of outcome values that the reader can branch on
exhaustively", which is the general form of this bug.

**Verification.** `pwsh -File tools/check-rules.ps1` - expected exit 0, actual **0** (19 core docs, 11
contrib docs). `pwsh -File hooks/tests/smoke-hooks.ps1` - expected 0, actual **0**, 40 cases, up from 14.
`pwsh -File hooks/tests/smoke-prefilters.ps1` - expected 0, actual **0**, 20 cases, new. Both new gate
checks were proven from both sides against a synthetic repo before being trusted: `SZA-HOOK01` fires on a
missing inventory and on a missing row, and stays silent when the inventory is complete or lives in
`docs/AGENT_HOOKS.md`; `SZA-CANON07` fires on a stamp claiming `2026.08.08.2` against a canon at
`2026.08.08.1` - which is the exact blocker this brief opened with. `CANON_VERSION` `2026.08.08.1` ->
**`2026.08.18`**; core digest `sha256:3a194628..` -> **`sha256:03bc1c8c..`**.

**Re-stamped in the same pass: all twelve stamped repos**, each verified with
`check-compliance.ps1 -RepoRoot`. Every staleness warning cleared, and the `SZA-CANON07` blocker this
brief opened with - both FastMediaSorter stamps claiming `2026.08.08.2`, a version that was never
published - is gone, superseded rather than hand-patched, which is what the brief asked for. Nine of the
twelve came back at exit 0 with zero errors. The three that did not carry **pre-existing** violations,
none introduced by this pass and none of them canon work:

| Repo | Error | Status |
| --- | --- | --- |
| CyrFlip | `SZA-STYLE01` store-listing typography | the same one recorded in its own file on 2026-08-02, still open |
| Streams_Player | `SZA-SEC03` committed `catalog-snapshot.zip` with no why-comment; `SZA-STYLE01` 38 dashes in one doc | new since 2026-08-05, that repo's own work |
| EPUB_2_HTML | `SZA-SEC04` in `internal/report/archive_test.go` and `redact_test.go` | **a false positive, and it is the gate's fault** |

That last one is worth naming, because it is the failure mode this gate's own header warns about. The
matched literal is `AIzaSy` + a keyboard walk, and the two files are the tests for the **redaction** code
- a fake credential is precisely what must appear there, and there is no real key. `SZA-SEC04` was left
unchanged: weakening a secret check is the owner's call, not a propagation's, and the stamp already
carries the right instrument for it (a scoped `exemptions` entry naming the two paths and the reason).
Recorded here so the next reader does not spend the same half hour proving it is not a leak.


## Canon re-sync 2026-08-18 - the first reconciliation after a three-week stale plugin cache

Executed **from a project session**, touching nothing in the canon but this file. Unlike the entry above -
which was a spread-back *up* into the canon - this one is the reconciliation *down* into the repo, and it had
never been done: the `sza` plugin served a cache pinned at `2026.07.27` for three weeks, so the canon updates
of 08-02, 08-05, 08-08 and 08-18 reached zero sessions in this repository. The plugin now resolves
`2026.818.1`. The stamp had already been advanced mechanically to `2026.08.18.1` / `sha256:961c9c8a..`; it was
correct and was left untouched.

**Compliance gate, before and after: `0 error(s), 0 warning(s)` both times** (`check-compliance.ps1`, exit 0).
That is the finding, not a formality - the gate reads the stamp, the version ladder, the style rules, the
secret patterns and the hook inventory. It cannot see whether a rules file *restates* a canon rule, so a repo
can sit at zero errors while its agent-rules file has drifted into a fork. Every item below was invisible to
it. A future re-sync should not read a clean gate as "nothing to do".

**The brief asked for the gate's warnings to be worked through. There were none**, and the prompt's own
placeholder for them reached the session unsubstituted. Recorded because the honest answer to "resolve these
warnings" was "the gate reports zero, and the list was never pasted" - not an invented triage.

### What was reconciled in the repo

| Target | Change |
| --- | --- |
| `CLAUDE.md` section 1 | The clock-time rule and the caveman trigger collapsed into one pointer at [AI_USAGE.md](../AI_USAGE.md) 7, which now carries both verbatim in substance. |
| `CLAUDE.md` section 6 | `Initiative` deleted outright - a pure restatement of [AI_USAGE.md](../AI_USAGE.md) 1. The 120 s threshold kept its concrete boundary and target lists and lost the rationale the canon now owns. Cost discipline and subagent MCP isolation reduced to pointer plus the repo-only mechanic. |
| `CLAUDE.md` section 7 | `-NoProfile`, one-process batching and the fresh-interpreter model folded into one pointer at [GITHUB_INTERACTION.md](../GITHUB_INTERACTION.md) 6. Reachable exit codes reduced to pointer plus the gate name. |
| `CLAUDE.md` rules 24, 25, 27, 28 | Each compressed to a canon pointer plus the repo's escape hatch, and each now names the plugin's `guard-bash.ps1` as the enforcer. Numbering was **not** changed: rule numbers are cross-referenced from about twenty files, so renumbering would have broken more than it tidied. |
| `CLAUDE.md` rules 15, 23, 26, 31 and section 12 | Evidence rule, lock-queue design, fire-and-forget and subagent tier routing all reduced to pointers plus the concrete scripts, codes and agent names this repo owns. |
| `AGENTS.md` | Same treatment on its four restatement lines, plus two factual corrections below and the background/foreground threshold, which it had never carried at all. |
| `docs/AGENT_HOOKS.md` | The `guard-bash-slash-arg` row and its contract paragraph removed; a new paragraph records the plugin-duplication state of the whole global half. |
| `.claude/settings.json` | The `guard-bash-slash-arg` registration removed. |

### The stale claim that mattered most

`CLAUDE.md` Rule 24 and its `AGENTS.md` mirror both said the file-search safety rule "has one home in the
canon; **this repo owns only the enforcement**". That stopped being true in `2026.08.08.1` and is now flatly
wrong: the canon ships `guard-bash.ps1`, which absorbs that guard along with four other checks. A rules file
that claims ownership of an enforcement layer it no longer owns is worse than silence - it is the sentence
that stops the next reader from looking for the duplicate.

### A duplicated project hook, removed - with the verification the canon asks for

[AI_USAGE.md](../AI_USAGE.md) 5 says a project that hand-wired a guard the canon now ships should drop its
own registration rather than run it twice, **and verify the installed cache rather than the marketplace
clone**. Both halves were done:

- The installed cache at `sza/2026.818.1` carries `guard-bash.ps1` with the MSYS slash-argument check as
  check 6. Verified by reading the installed file, not the clone.
- Proven live rather than by inspection: a Bash call carrying a slash-command argument value was **refused**
  by `guard-bash` before the shell spawned, quoting canon `GITHUB_INTERACTION.md` section 6.
- **Coverage was compared before deleting, not after.** The two guards are not equivalent. The project hook
  was *name-aware* - it built its deny-list from `.claude/commands/*.md`. The canon guard is *shape-aware* -
  it refuses any first path segment that is not in a POSIX-root allowlist. Canon's is broader on command
  heads and narrower on names: a command named after a POSIX root (`run`, `dev`, `var`, `bin`, `etc`, `opt`,
  `lib`, `tmp`, `usr`..) would pass unrefused. All 32 of this repo's command names were enumerated and
  checked against that allowlist - **no collision, and no single-letter name** - so the deletion loses
  nothing today. The residue is written into Rule 27 and into `docs/AGENT_HOOKS.md` rather than left to be
  rediscovered.

### Open, and deliberately not fixed from this session

**Every hook in the `global` half of this repo's inventory is now also shipped by the plugin, and both
fire.** `~/.claude/settings.json` still hand-registers the disk-scan guard, the `.ps1`-head guard, the
unavailable-command guard, `guard-fire-and-forget`, `guard-uncapped-read` and `warn-context-size`, while the
installed cache ships `guard-bash.ps1` (absorbing the first three), `guard-fire-and-forget.ps1`,
`guard-uncapped-read.ps1` and `on-user-prompt.ps1`. Each duplicate costs a second PowerShell start
(170-250 ms) on every matching call, and the read guard rewrites the same input twice under two different
windows - the plugin's is 500 lines. One thing checked and found **not** to be wrong: both read guards
*rewrite*; the hand-wired one had already been upgraded from blocking, so the canon's 08-18 change is not
being neutralised.

**This duplication produced a live false refusal during this very session, which is the sharpest evidence
available.** Appending this section from the Bash tool was refused by the hand-wired disk-scan guard, because
the word it matches on appears in the *body of the heredoc* being written. The canon's `guard-bash.ps1`
strips heredoc bodies before that check - a relaxation deliberately recorded in the 2026-08-18 spread-back
above - so the newer guard would have allowed the identical call. The stale copy is not merely redundant; it
is now *stricter than the canon intends*, and it refuses correct work. The section was written through the
PowerShell tool instead.

The fix is to drop the six hand-wired registrations, but that file is per-machine and outside this
repository, so it is the owner's call and was not made here. The inventory rows stay while the registrations
stay - `assert-hook-inventory.ps1` judges the global half against that file whenever it is readable, so
deleting a row first would fail the gate.

### Two facts the working tree corrected

- **`AGENTS.md` claimed "Kotlin 1.9+".** The live pin is **2.2.10** in both `build.gradle.kts` and the
  Compose plugin, and `CLAUDE.md` carries it correctly in a machine-generated block. A hand-maintained
  version number next to a generated one drifts; the line now names the generator as authoritative instead
  of restating a second copy.
- **The defect this file recorded on 2026-08-18 against this repo is already closed.** The entry above says
  the lock-queue documentation lists three outcome-marker values while the code writes a fourth,
  `enqueue-failed`. `docs/DEV_OPS.md` now documents all four, and `wait-for-lock-turn.ps1` writes exactly
  those. Working tree beats the record; the note above is stale and this line supersedes it.

### One canon rule verified rather than assumed

[DEVELOPMENT.md](../DEVELOPMENT.md) 15's clean-verdict cache is **already implemented here** - it is the
reference the rule was extracted from - with all three constraints the canon states: only the
clean-everywhere verdict is cached, a failure never is, and the entry expires on age as well as on
fingerprint. The one clause worth checking was "take `-NoCache` on the release and CI paths": no caller
passes it, but no release or CI path invokes the static-analysis gate at all, and `temp/` is gitignored so a
fresh CI checkout has no cache to inherit. Vacuously satisfied rather than violated - recorded so the next
reader who wires that gate into CI knows the switch is the thing to reach for.

### A rule this session broke, recorded rather than glossed

`CODE.LOCK` was not taken before deleting the project hook script and editing `.claude/settings.json`.
Rule 23 counts repository scripts and config among the things needing the lock. No collision resulted, but
the omission is the reader's to know about, and it is the same shape as the failures this file keeps
recording: the rule was prose at the moment it applied.

**Verification.** `check-compliance.ps1` - expected 0, actual **0**, `0 error(s), 0 warning(s)` before and
after. `assert-hook-inventory.ps1` - expected 0, actual **0**, `PASS (11 registered hook(s), project +
global)`. `assert-rule-digest-sync.ps1` - expected 0, actual **0**, 31 rules cited across both digests.
`post-change.ps1` over the four changed files with `-ScopeToFile -RegistryAck 'repository-rules' -ChangeType
Mixed` - expected 0, actual **0**, `post-change: PASS`, one dev-log row. The fast-gate battery returns **1**
on four gates - listener symmetry (+2), unreferenced strings (6), the memory-index budget (253 B over) and
gate-hint sync (1) - **none of them attributable to this change**: the tree carries 194 dirty Kotlin files
plus a modified `strings.xml` and memory index from other tickets, and this change touched six paths, none of
them Kotlin, strings or memory. That is exactly the case `-ScopeToFile` exists for, and the scoped closure
passed clean.

### Canon fix proposed from this session - not applied here

`guard-bash.ps1`'s POSIX-root allowlist silently exempts a real command name that happens to match a root
word. A project whose command set includes `run`, `dev` or `lib` as a slash command would lose the check with
no signal. Worth either narrowing the allowlist to single letters plus the segments that cannot be command
names, or emitting a warning rather than a silent skip when the segment is followed by more arguments.

## Spread-back applied 2026-08-28 - gate placement, the closure's own ladder, lock domains, batch drivers, and a locale contradiction

Raised from a session whose original question was "have our rules grown heavy enough to throttle
development" - the owner had watched another agent close comparable tickets up to 4x faster. The
measurement that opened the session is the reason five of these six are here, and it is also why two
obvious-looking fixes are NOT here.

**What the measurement found**, over 2026-08-14..28 (520 sessions, 346.7 h of active wall, idle above
15 min excluded) plus the competing agent's own timestamped log for the same repository (111 tasks,
2026-04-10..08-28), controlled on the **31 tickets both agents worked**:

- The gap is real - median wall 16 min against 47 min - but the work is the same size: **166 tool calls
  against 190, 28 edits against 31**. The other agent runs this repo's *same* process (1,191 catalog
  calls, 242 closure-facade runs, 347 lock calls) and is still faster, so process volume is not the cause.
- Process machinery is **27.5% of calls and 16.8% of ticket wall**. Deleting every gate and every catalog
  write therefore caps out near 1.2x and cannot produce 2.9x.
- Turn latency tracks **what the model writes, not what it reads**: correlation with output tokens
  **+0.681**, with context size **+0.065**. By output band: under 200 tokens 2.7 s, 500-1000 7.2 s, over
  2000 23.8 s. Across context bands 50k to 600k+ the median moves only 3.0 s to 6.2 s.
- **76.5% of billed output is hidden reasoning** and only **5.6%** of it ever reaches a file. Written
  artifacts - every spec, every line of code - are 5.6% of generation, and spec prose alone is 3.3%.

**Consequence for the canon, stated once so it is not re-derived:** trimming rule text, spec templates or
artifact volume is not a *latency* lever any more than it is a cost lever. [AI_USAGE.md](../AI_USAGE.md)
§3 already says prose is not a cost lever; this session adds that it is not a speed lever either, and by a
different mechanism.

### Raised

- **Gate placement, per-change or release-scope** -> [DEVELOPMENT.md](../DEVELOPMENT.md) §15. Zero prior
  presence in `rules/` (grepped: no hit for "release-scope" or "gate placement" outside `contrib/`). The
  four-part test, both corollaries, and the substitution for a project with no release boundary. Evidence
  carried across: three tree-scope gates produced 68 of 191 red lines across 53 batch runs; one spent 33
  minutes of closure time in a month for one finding.
- **The closure runs the ladder's rung, it does not ask for it** -> §15. The canon had the ladder (§6) and
  the facade (§15) and never joined them, so a project can hold both and still ship the defect: a broken
  layout closed green and its ticket reached "install this and test it" without the artifact ever being
  built.
- **A lock is a (kind, domain) pair, derived not declared** -> §10, with the all-or-nothing acquisition
  rule and the "full set when it does not decompose" fallback. Plus the lifecycle hole the split exposes:
  **abandoning a queued intent obliges you to withdraw your own ticket**, because the sweep judges the
  session (alive) while it was the intent that died - and only the *granted-but-unclaimed* head self-heals.
- **For an unattended batch, make the process boundary the reset** -> [AI_USAGE.md](../AI_USAGE.md) §3.
  A genuine advance on the canon's own "build the halt, not the reset": an external driver pulls the lever
  the agent cannot. Evidence: 83% of a week's usage spent above 150k of carried context before one existed.
- **A check only a human can run has not happened yet** -> [TESTING_AND_QA.md](../TESTING_AND_QA.md) §1.
  A closing audit with no failures but an unticked manual line scores "needs a human test", never
  "verified". Evidence: a ticket declared done on one unticked device line, and an hour on real hardware
  failed one of its five acceptance criteria.
- **A contradiction on the always-loaded page, fixed** -> [INVARIANTS](../INVARIANTS.md) 17 and
  [DOCUMENTATION_CONCEPT.md](../DOCUMENTATION_CONCEPT.md) §5. The invariant read "every surface and every
  locale in one edit"; this repo ruled (owner, 2026-08-14) that surfaces move together while the rest of
  the declared locale set batches to the release, since nothing ships between releases and per-change
  translation buys ten further translations per key for no shipping benefit. Both now say: every surface
  and every *authored* locale in one edit, the remainder at the release boundary where one exists. The
  reference repo was knowingly non-compliant with line 17 until this edit.

### Deliberately NOT raised - two proposals this session's own measurement refuted

- **Relaxing the fire-and-forget guard so gates can be dispatched asynchronously.** The other agent gets a
  real win this way - 89% of its heavy invocations are background dispatches and it reads **97%** of them
  back, so it is overlapping, not skipping. But `hooks/guard-fire-and-forget.ps1` already carries the
  counter-measurement in its own header (~1,297 polling turns and 81 minutes of literal sleep in a month),
  and the harnesses differ at the decisive point: a completion notification re-invokes this agent rather
  than letting its loop continue. The guard stands unchanged. The in-repo form of the same idea was already
  implemented and needed nothing: the closure facade starts its slowest gate as a background job before the
  lexical ones and joins it after, turning (lexical + heavy) into ~max(lexical, heavy), with the two other
  build-backed gates inside the same window.
- **Trimming the spec templates to cut written volume.** Measured and dropped: spec prose is 3.3% of
  generated tokens, so halving it moves wall-clock by a fraction of a percent while costing information
  that is demonstrably consumed. Section-level measurement found no dead sections either - the largest
  near-empty one is 0.8% of spec bytes.

**Verification.** `tools/check-rules.ps1` - expected 0, actual **0**, `check-rules: OK (19 core docs, 11
contrib docs)`, run before and after the version bump. `CANON_VERSION` **2026.08.18.2 -> 2026.08.28.1** and
`.claude-plugin/plugin.json` **2026.818.2 -> 2026.828.1** in the same change, per this repo's own delivery
rule. Six `rules/*.md` files touched, so every adopting repo is marked stale for reconciliation - intended.

**Procedural note, recorded rather than glossed.** This canon edit was made from a *project* session, which
this repo's `CLAUDE.md` tells every other repo not to do. The owner directed it explicitly after being shown
the constraint. The gate and both version bumps were run exactly as a canon session would, so the change is
well-formed regardless of where it was authored; the deviation is the venue, not the process.

## Canon re-sync 2026-08-28 - reconciling the repo against the rules it had just raised

Immediately after the spread-back above, run in the same project session at the owner's direction. Six
rules in this repo's `CLAUDE.md` had become restatements of canon text by virtue of that spread-back, which
is the exact condition step 4 of `adopt-canon` exists to clear.

**Plugin root used: the live canon checkout `P:\WEB\sza-unified-rules`, not the plugin cache.** The cache
on this machine holds `2026.818.1` and `2026.818.2`; the canon had just moved to `2026.08.28.1`. Stamping
against the cache would have recorded a canon version that no longer exists, so the digest was taken with
`tools/check-compliance.ps1 -PrintDigest` from the checkout - reported here because the skill asks which
root was used.

### Converted from restatement to pointer

Each keeps its repo wiring, its script names and its ticket ids, and drops the principle now stated once in
the canon:

- **Rule 33** -> `DEVELOPMENT.md` 15. Keeps the two runners (`assert-release-scope-gates.ps1` at step 0.4
  of `/spec-prerelease`; `post-change.ps1` and `a.ps1 fg`) and notes that the canon carries S1939's and
  S1392's numbers without naming a project because they came from here.
- **Rule 23** -> `DEVELOPMENT.md` 10. Keeps the five domain names, the table's location, exit code **4**,
  the waiting contract, the withdraw commands and the pre-split honouring; drops the (kind, domain) pair,
  the derived-not-declared rule, the full-set fallback, all-or-nothing acquisition and the withdrawal
  rationale, all now canon.
- **Rule 30** -> `DOCUMENTATION_CONCEPT.md` 5. Keeps the thirteen-locale `locales_config.xml` fact and the
  gate at step 0.8; records that until 2026-08-28 this rule contradicted invariant 17.
- **Validation ladder, layout/manifest rung** (section 12) -> `DEVELOPMENT.md` 15. Keeps `resource-link-gate`
  and its measured 1.9-41.8 s per flavor.
- **Open manual check** (section 4) -> `TESTING_AND_QA.md` 1. Keeps the `## Last Audit` mechanism and the
  `MANUAL` -> `BlockNeedUserTest` scoring.
- **Unattended batches** (section 3) -> `AI_USAGE.md` 3. Keeps `run-spec-queue.ps1` and the parallel-instance
  detail - **and was corrected in the same edit**, because the model tiers stated there had gone stale that
  morning: routing now reads status before tier, with the code-complete states (`Implemented`,
  `BlockNeedUserTest`) and tiers 1-3 on the cheap model, decision states and tier 4+ on the strong one.

### A divergence kept, and why

`AGENTS.md`, `GEMINI.md` and `.github/copilot-instructions.md` keep the **full statement** of every rule
converted above. They are the parallel rule set for agents that do not load the canon plugin, so a pointer
there would leave those agents with no rule at all. The registry's sibling prompt named them and the
acknowledgement was deliberate, not a skip. `assert-rule-digest-sync.ps1` is what keeps them honest, and it
passes with **33 rules cited across 2 full digests, 1 pointer reachable**.

### Verification

`assert-rule-digest-sync.ps1` - expected 0, actual **0**. `post-change.ps1` over `CLAUDE.md` +
`.sza-canon.json` with `-ScopeToFile -RegistryAck 'repository-rules' -ChangeType Mixed` - expected 0, actual
**0**, `post-change: PASS (Mixed, 9166 ms)`, one dev-log row. `check-compliance.ps1` before **9 error(s), 7
warning(s)**, after **9 error(s), 6 warning(s)** - the cleared warning is `SZA-CANON03`, the stamp now
reading `2026.08.28.1` / `sha256:cdf49be6..` with `adoptedOn` deliberately left at 2026-08-18, since a
re-sync is a reconciliation and not a re-adoption.

The **9 errors are pre-existing and none is attributable to this work**: all are `SZA-STYLE01` em/en-dashes
in prose across the locale triplets of `docs/launcher`, `docs/wear` and `README`, in files this session never
opened. The 2026-08-18 record above cites `check-compliance` at 0 errors, so this is a regression from the
ten days between. Parked as **S2216** (Draft) rather than fixed here, with the gate output captured verbatim
and two open questions: whether any gate judges house style in `docs/**` at all (the neuroslop gate covers
`.kt` only), and whether such a check is per-ticket or release-scope under the rule this session just raised.

### Canon fix worth considering, not applied

`tools/check-compliance.ps1` raises `SZA-HOOK03` for five hook scripts in this repo that are "registered
nowhere and in no inventory row", while the repo's own `assert-hook-inventory.ps1` passes on the same tree.
One of the two is reading the wrong place. Worth reconciling the two inventories rather than leaving a
warning the repo's own gate contradicts.

## The development-process harness moves into the canon (S2402, 2026-09-03)

The rules described the process; this repository was the only place it actually ran. 71 scripts and
16 843 lines of PowerShell drove 2 389 tickets here, and every one of the ten adopting projects got
the description and had to write the implementation itself. That is now a shipped layer:
`tools/harness/` with a single seam, `templates/.sza-profile.json`.

### What travelled

Eight clusters, measured before anything moved (the entanglement dossier and the dependency graph in
`PLAN/S2402_propagate-dev-release-tooling-canon/research/`), and all eight selected by the owner:

- `spec_catalog/` - the ticket journal, its CRUD and every closing gate, plus the two probe helpers
  the gates and the tree checker have to agree on.
- `locks/` - domain locks, the queue and its head reservation, ticket leases, agent identity.
- `chat/` - the descriptive layer beside the locks.
- `devlog/` - the change journal.
- `document_registry/` - the document catalogue, its query CLI and the map/sitemap generator.
- `batch/` - the queue runner, its monitor and the snapshot both surfaces render.
- `all_features/` - the capability ledger.
- `aliases/` - the command-alias generator.

### The seam

`_profile.ps1` merges `<project root>/.sza-profile.json` over defaults that ARE the canon's own
conventions, so a project overrides only what differs. It carries the working-directory roots, the
ticket-id and spec-file grammars, the status vocabulary, the lock domain table with its path rules,
the probe shape, the runner's model policy, the status -> command map, the ledger's dimension, the
site's locales, and an entry-point map used only in printed hints.

Three findings the conversion produced, each of which would have shipped as a defect:

- **The path -> domain table is data, not code.** It was fourteen hand-written branches with the
  reasoning for each in comments; the reasoning stays as the rule ("first match wins; a bare type is
  the fail-closed answer; null means already serialised by something finer"), the fourteen product
  paths became six template rows.
- **An empty list in a profile read as one blank entry.** `$v = if (..) {..} else {..}` sends its
  value through the pipeline, which unrolls an empty array to nothing; the merge then stored `$null`,
  and `@($null).Count` is 1. "This project declares no aliases" arrived as one alias row with no
  canonical command. Fixed with plain assignment and `[object[]]@(..)` at every storage site.
- **Half the set is dot-sourced and half is invoked**, so a consuming project's forwarder cannot
  choose one shape: `& $target` defines nothing a dot-sourcing caller can see, and `exit` inside a
  dot-sourced file kills the caller. The forwarder branches on `$MyInvocation.InvocationName -eq '.'`.

### What deliberately stayed behind

- **The test suites.** A `*.tests/Run-Tests.ps1` exercises the harness through one project's paths,
  statuses and fixtures. Run in the project it belongs to it proves the shipped layer works there,
  which is exactly what an adopting project's own suite proves for its own; exported, it would ship
  this repository's `PLAN/`, `temp/` and `Sxxxx` grammar as if they were the canon's.
- **Platform gates.** The 99 files of `scripts/quality/` are tied to Gradle, Kotlin, Android, Room,
  detekt and a device. The contrib record already declared them unfit for the core.
- **Command bodies.** `.claude/commands/*.md` is one product's pipeline. The alias generator ships;
  the commands it aliases do not.
- **`migrate_from_log.ps1`**, which migrated this repository's retired `FUNCTIONALITY.log` once.

### The layer's own gate

`tools/harness/assert-portable.ps1` refuses a harness script whose CODE lines (comments stripped)
name a product path, an environment prefix, a log call or a build-system marker - the values a
profile could no longer override. It is the check that turned "the scripts were copied" into "the
scripts were converted": the first run reported 405 such lines.

### This repository as a consumer

The 2 383 call sites here were not rewritten. Each exported script's local path became a generated
five-line forwarder that resolves the shipped copy - `SZA_HARNESS_ROOT`, then the plugin cache's
newest version, then the canon checkout - and re-invokes it. The plugin cache path carries both the
home directory and the plugin version, so no call site could name it and stay correct across an
update; the forwarder is the one place that resolution belongs.

### Venue

Landed from the project session at the owner's explicit direction, exactly as the 2026-08-18 and
2026-08-28 entries above record for their own changes. The canon's guardrail against editing it from
a project session stands; this is a recorded deviation, not a precedent, and it is recorded here for
the same reason those two were.

## 2026-09-05 - S2520: six gate refusals carry their own evidence

### What changed

Six harness scripts now print, on their refusal branch only, the date, the measured quantity and
the ticket id behind the rule they enforce: `spec_catalog/check-open-items-carried.ps1` (S1607,
2026-08-13), `check-audit-recorded.ps1` (S2298 and S2367, two measured populations),
`check-probe-present.ps1` (S2324), `check-headings-unique.ps1` (S2357),
`check-audit-current.ps1` (S2367, both FAIL branches), and `locks/enter-code-lock.ps1` (S2342,
S2109 and S2419 on the exit-4 branch). Every number already sat in each script's header comment
and in the consumer's rule pages; none of it reached the operator the script stopped.

### Why the refusal and not the rule page

The consumer keeps two rule sets. `CLAUDE.md` can push a topic into `.claude/rules/<topic>.md`
with `paths:` frontmatter, which Claude Code loads only after reading a matching file - the lever
S2521 used. `AGENTS.md`, the parallel set for agents that never load this plugin, has no such
lever: a pointer there leaves the reader with no rule at all. A gate refusal is the one
destination both sets can delegate to, because `Assert-ClosingGates` runs for every agent that
changes a status, whatever the runtime. Measured 2026-09-05, that is 4 959 B of rationale in
`.claude/rules/spec-catalog.md` and 1 853 B in `AGENTS.md`.

### Deploy owed

**These edits are not deployed.** `CANON_VERSION`, `.claude-plugin/plugin.json` and `deploy.ps1`
were deliberately left to a canon session, per the S2410 split of the edit from the deploy. Until
that runs, the checkout is ahead of plugin cache `2026.903.3` and the refusals still print their
previous text at run time. The consumer's own removal of the duplicated rationale is gated on this
deploy and has not been performed - stripping first would leave the rule unexplained in both
places.

### Verification performed

Each of the five closing gates was invoked directly with `SZA_HARNESS_ROOT` pointed at the
checkout and returned exit 1 with the new text. `enter-code-lock.ps1` was driven to exit 4 in a
sandboxed `SZA_PROJECT_ROOT`, so the consumer's live lock files and queue were never written -
note that the sandbox only holds when the harness script is called directly, because the
consumer's forwarder sets `SZA_PROJECT_ROOT` to its own repository root before delegating.

## 2026-09-06 - S1809: the fire-and-forget guard now sees the wear module's fast targets

### What changed

`hooks/guard-fire-and-forget.ps1`'s verdict-bearing "fast check" pattern gained the wear module's
three targets: `fw|fwr|fwu` join `fk|fkn|fc|fr|fg|dq|ch|ss|bf`. Before this, `a.ps1 fwu` dispatched
with `run_in_background` passed the guard untouched, so a wear gate could be backgrounded and its
exit code never read - exactly the shape rule 26 exists to stop.

They belong in the list on the same evidence as the rest of it: S1807 measured their foreground cost
on a warm daemon at 2 s (`fw`), 1 s (`fwr`) and 11 s (`fwu`), all far inside the 120 s threshold the
rule gates on. A backgrounded call at that cost does not save a turn, it adds one.

### Verification performed

`hooks/tests/smoke-hooks.ps1` passes at 48 cases, up from 46: the fix carries its own regression
pair - `backgrounded wear fast check` (expect deny, exit 2) and `wear fast check in foreground -
allowed` (expect exit 0). All three targets were additionally driven through the hook directly, both
backgrounded and in the foreground, and each returned the expected code.

### The S2520 deploy owed above is now performed

This deploy carries the six harness scripts of the 2026-09-05 entry as well - they sat committed
nowhere, waiting for exactly this canon session, per the S2410 split of the edit from the deploy.
Both ship as `CANON_VERSION` **2026.09.06.1**, plugin `2026.906.1`. The consumer's removal of the
rationale it duplicates from those refusals is no longer gated: the refusals now print it at run
time from the cache, once `claude plugin update` has run.


## 2026-09-07 - S2463: the deploy raises the version pair, so a pushed canon change actually reaches consumers

`deploy.ps1` ran the gate, committed and pushed, and stopped there. Nothing raised
`.claude-plugin/plugin.json` `version` or `CANON_VERSION`, and the consumer's cache is a directory named
for the plugin version - so content pushed under an already-installed number is never refetched. The
deploy returns 0 and `claude plugin update` reports "already at the latest version", so nothing announces
the gap.

Measured twice. On 2026-09-03 the canon was pushed at `8f39a93` with the S2421 lock fix present in the
checkout, while `2026.903.2/tools/harness/locks/agent-lock.ps1` in the cache carried zero occurrences of
that ticket id; the forwarder resolved to the cache, so the fixed mechanism was in no runtime. On
2026-09-07, four days after the manual rule was written into `CLAUDE.md`, `ec00587` shipped three
`tools/harness/spec_catalog/` files with both version files untouched at `2026.09.06.1` / `2026.906.1` -
the same number this machine's newest cache directory already held.

### What changed

- `tools/bump-canon-version.ps1` - new, and the only writer of the pair. Reads `CANON_VERSION` as
  `yyyy.MM.dd.N`, keeps the stored date and increments `N` when that date is today or later, otherwise
  starts today at `N = 1`, and derives the plugin version as `yyyy.<month without a leading zero><day>.N`.
  It replaces the one `version` line rather than re-serialising the manifest. `-Print`, `-DryRun`, exit
  codes 0 / 1 / 2.
- `deploy.ps1` - calls it before staging whenever the pending set reaches a consumer, then re-reads the
  status so both version files ride in the same commit; `-NoVersionBump` opts out, and the bump is skipped
  on its own when the whole set is `README.md`, `LICENSE`, `.gitignore`, `CANON_VERSION`, the manifest
  itself or `rules/contrib/`. After the push it compares the newest directory under
  `~/.claude/plugins/cache/sza-unified-rules/sza/` with the version just written and names
  `claude plugin update sza` when they differ - a report, never a gate, since updating the plugin is the
  operator's action.
- `CLAUDE.md` and `README.md` - the manual-bump instructions now say the deploy owns the number. The
  recorded consequence of shipping without one is kept, and the 2026-09-07 miss added to it.

### Verification performed

`tools/check-rules.ps1` exits 0. `bump-canon-version.ps1 -Print` reports the live pair
`2026.09.06.1` / `2026.906.1`; `-DryRun` names `2026.09.07.1` / `2026.907.1` and leaves both files
byte-identical. `deploy.ps1 -DryRun` runs the gate, prints that dry-run bump, lists the two pending
changes and stages nothing; `-DryRun -NoVersionBump` prints the opt-out line instead. The two decision
helpers were driven directly: a rename porcelain line yields the new path, a `tools/` path ships, a set of
only `rules/contrib/` plus `README.md` does not, and a mixed set does.

### What is owed

The deploy itself. It is the operator's command (INVARIANTS 18) and was not run from this session, so
these changes sit in the checkout and reach no consumer until the owner runs `pwsh -File deploy.ps1` -
which will now raise the pair on its own. One line in `rules/README.md` still tells a maintainer to bump
`CANON_VERSION` by hand; `rules/` is not a file a project session may edit, so that correction is left to
a canon session.
## 2026-09-11 - S2934: the probe invariant is guarded in both directions, and by shape

The consumer's Rule 2 states the debug-probe invariant as an equivalence - a probe exists in source if
and only if its ticket is in `BlockNeedUserTest` - and the harness guarded exactly half of it.

### What changed

- `spec_catalog/check-probe-absent.ps1` - new. Refuses a transition OUT of `BlockNeedUserTest` while
  any probe of the ticket is still in source, and prints the project's removal command filled in with
  the id. A refusal and not a deletion: removing the probes from a catalog mutator would write source
  outside any code-domain lock and outside the closure that judges a source edit.
- `spec_catalog/_lib.ps1` - `Assert-ClosingGates` runs that checker before its early return. The
  return was the hole: the function read `$NewStatus` only, so `BlockNeedUserTest -> In Progress`
  names no gated status and reached no checker at all. `archive.ps1` never calls this function and is
  untouched, which is deliberate - it is the path a release sweep takes, and the sweep deletes the
  probes of everything it archives and proves it with the consumer's tree gate.
- `spec_catalog/check-probe-present.ps1` - asks a second question of every probe it finds: does it own
  its physical line. A malformed probe no longer satisfies presence, because split across two checkers
  presence answers PASS about the very line shape answers FAIL about.
- `spec_catalog/lib/blockneedusertest-probes.ps1` - `Test-TicketProbeInSource` gains `-All` and a
  `LineText` field. Default behaviour is unchanged. Separately, `Get-ExcusedProbeTickets` returned the
  set's ELEMENTS rather than the set: an `object[]` when the baseline had rows, which still answers
  `.Contains()` and hid the defect, and `$null` when the baseline was empty or absent - crashing the
  caller with "You cannot call a method on a null-valued expression" and exiting 1, a refusal phrased
  as a missing probe on a tree where nothing was wrong. Both returns now carry the comma.
- `_profile.ps1` - two new `probes` keys: `ownLineRegex` (the shape predicate, default
  `^Timber\.d\(.*\)$`) and `removeCommand` (default empty; the refusal falls back to naming the probe
  form when a project has no remover).

### Why the shape predicate is a profile key and not a library function

The consuming repository had the predicate inlined in its own tree gate, which is the S1621 split
this ticket closes. A new library function would have closed it only after a deploy: the consumer's
gate resolves the harness through the plugin cache, so the function would be undefined in every
sibling session until the owner deployed, and `.\a.ps1 fg` would go red over a change no session
running it could ship. `Merge-SzaProfileNode` carries a key unknown to the defaults into the merged
tree, so the project profile makes the value readable by the already-deployed harness. The consumer
half therefore landed live and behaviour-identical, proven equivalent on the correct shape and on all
five shapes the original incident measured.

### Verification performed

Against the checkout with `SZA_HARNESS_ROOT`: the consumer's `check-probe-present.tests` suite reports
`13 passed, 0 failed`; `assert-closing-gates.tests` reports `11 passed, 0 skipped`, its new cases
refusing a real parked ticket's exit while its probe stood in source, accepting an excused ticket's,
and staying silent on an exit from another status. Against the deployed cache the same two suites
report `11 passed, 0 failed, 2 case(s) skipped` and `8 passed, 3 skipped`, every skip naming S2934 -
the rule S2577/S2578 established, so no sibling session goes red over a deploy it cannot run.

### What is owed

The deploy. Until it runs, the two gates exist in the checkout and no consumer executes them: the
exit gate and the shape half are inert, and only the profile key and the consumer's tree gate are
live. The pile they join is the normal state recorded above, not damage - one deploy clears all of it.
