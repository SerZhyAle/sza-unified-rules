---
# Contribution: tourist_mob (overlay B, flavor shape, three packages, no contract of its own) -> Unified_Rules
Source repo: P:\ANDROID\Tourist_mob | Date: 2026-10-02
Read: NEW_PROJECT_CHECKLIST, PLATFORM_OVERLAYS, CONTRACTS, INVARIANTS, RELEASE_AND_DISTRIBUTION section 8, harness README and spec_catalog SCHEMA, the adopt-canon and contract-sync skills; deduped against: contrib/streamsplayer_mob.md, contrib/fastmediasorter_mob_v2.md
---

Tourist for Android: a hike kit - the Tourist dashboard with compass, SOS, the water flashlight, the screen and
camera flashlights, a multi-participant stopwatch - as a phone app, a Wear OS app and a watch face. An
independent product extracted from FastMediaSorter Android (`fastmediasorter_mob_v2.md`) under its ticket S4070;
the second extraction of the day after StreamsPlayer for Android (`streamsplayer_mob.md`), by the same method,
so almost all overlay-B material is CONFIRM of that record. New against the sibling: a product that holds **no
contract of its own and no definite producer role** - its only guarantee against drift from the extraction
source is the port ledger with its SHA-256 drift check (handoff section 6a), and the contract pointers it keeps
are adopter, consumer and conditional ones.

## Overlay facts (verified against this repo, 2026-10-02)

- **Source root & release-mechanics.** Gradle modules phone / wear / watchface, arriving with ticket S0002; none
  exist yet. Specs in `PLAN/Sxxxx_<slug>.md`, the harness run from the plugin through `tools/harness.ps1`
  (evidence: `.sza-profile.json`, `tools/harness.ps1`).
- **Version shape.** PACKAGE-VERSIONING Android profile; no build, no tag yet (`versionShape.tagRegex` null).
- **Channels + listing files.** None yet - `channels: []`; declared with owner decisions 4.5, 4.7 and 4.9
  (ticket S0010).
- **Frozen anchors (owner, 2026-10-02).** `com.sza.tourist` shared by phone, watch and the noLegal variant
  (sanctioned exception: never co-published to one store); `com.sza.tourist.watchface`, the module exists.
  Signing key at `P:\ANDROID\Tourist_credentials` (not created yet, the owner's); Play App Signing with the
  product's own key imported as the app signing key plus a separate upload key, so store and sideload builds
  carry one signature.
- **Editions + parity mechanism.** None - single edition. Shape: flavor (store, noLegal); wear and watchface are
  sibling modules. Coupling to FastMediaSorter: the shared catalog plus a port ledger and drift check.

## Channel-matrix rows (this project)

- None yet. Recorded when S0010 settles the distribution decisions.

## Deltas by document

### CONTRACTS.md
- CONFIRM: the repo names the catalog in one file (`CLAUDE.md` line 3); seven pointers in `docs/contracts/`
  (PACKAGE-VERSIONING, INPUT-PARITY, ICON-SET and ICON-RENDER conditional, DIAGNOSTIC-REPORT and INSTALL-TRUST
  conditional, the rule-adoption family, the product-web-pages family conditional) and an index stating that no
  contract is owned here. `docs/BOOTSTRAP_HANDOFF.md` names the catalog path too: an origin record written before
  the first commit and not edited from this repository, carried by a dated SZA-CTR02 exemption.

### RELEASE_AND_DISTRIBUTION.md section 8
- CONFIRM with the streamsplayer_mob DIVERGE: the harness release plan stood up as shipped, the package number
  from the `current-next-release:` marker because the repo works on `main`, and `PLAN/` **tracked** because there
  is no remote yet, so an ignored store would exist in one place only.

## No delta

REPOSITORY_LAYOUT (Android spec home), INVARIANTS, NEW_PROJECT_CHECKLIST.

## Candidate core edits (PROPOSED - apply only on owner instruction)

- **adopt-canon step 6 / `templates/`:** the release plan's three files must exist before the first ticket is
  inserted, or the harness skips the reconcile without a word (`Sync-ReleaseQueue` returns when the queue file is
  missing, `spec_catalog/_lib.ps1` lines 709-710) while `release-queue.ps1` itself exits 2 with "seed it". Ship the
  three seed files (the queue with its `current-next-release: 1` marker line) next to `.sza-profile.json` in
  `templates/`, and name them in the step. Without them every adopter re-derives the shape from a sibling.
  Prevents a ticket store that holds tickets and no plan; evidence: this run, where the seeds were written first
  and the first insert produced the queue block.
- **Harness forwarder in `templates/`:** the harness README says an adopter "can keep its own thin entry points",
  and the handoff text forbids hand-copying harness scripts, yet the plugin ships no forwarder; every adopter
  writes `tools/harness.ps1` from the sibling's description (two repositories in one day, written twice).
  Ship one forwarder in `templates/` and name it in adopt-canon step 3. Evidence: `grep -r "harness.ps1"` over the
  plugin finds only contrib text.
- **Harness `release-queue -List -Ready` on an empty ready file (tools/harness):** exits 1 with "The property
  'Count' cannot be found on this object" until the first ticket reaches `RELEASE_READY.md`. In
  `spec_catalog/release-queue.ps1`, line 256 assigns `$tickets = Get-QueueTickets ..` unwrapped (an empty result
  unrolls to `$null`; line 257 wraps it in `@()` only on the `-Release` path) and line 302 reads `$tickets.Count`
  under StrictMode. The same class as the validator defect recorded in `streamsplayer_mob.md` and fixed on
  2026-10-02; fix: `$tickets = @(Get-QueueTickets ..)`. Evidence: reproduced on a fresh store (exit 1), and
  `-List -Ready` exits 0 once S0001 moved to Verified. Not patched from this repository.
- **Harness ticket-id grammar (tools/harness):** unchanged since `streamsplayer_mob.md` - `grammar.ticketIdPattern`
  is a profile key but `New-CatalogId` and `insert.ps1 -Id` hard-code `^S\d{4}$` (57 occurrences in 42 files,
  counted on plugin 2026.1002.3). Two products on the same day now share the `S0001` space with FastMediaSorter;
  citing the repository name next to an id is the workaround recorded in `CLAUDE.md`.

## Candidate NEW docs (not in any shared doc yet)

- None required.

## Open questions for the owner

- 4.3 store-variant composition (before the wear phase, S0008), 4.4 watch face composition (S0009), 4.5
  distribution of the first release, 4.6 name and branding, 4.7 GitHub remote, 4.9 site (S0010), and the phone
  start-screen placement (S0004) - each attached to the ticket of the phase that needs it.

## Canon adoption 2026-10-02

New-repo adoption against canon **2026.10.02.3**, core digest `sha256:410463a9..`, reference model, overlay B.

- **What changed in the repo:** `CLAUDE.md` rewritten from the bootstrap stub (canon pointer, catalog named once,
  handoff section 6a as standing law, frozen anchors, the release plan's six decisions); `AGENTS.md` kept as the
  delegating stub; new `.sza-canon.json`, `.sza-profile.json`, `tools/harness.ps1`, `LICENSE` (MIT),
  `docs/README.md`, `docs/contracts/` (index + seven pointers), `PLAN/` (journal, S0001-S0010, three release-plan
  files); `README.md` status and license lines; one FastMediaSorter-only line removed from `.gitattributes`.
- **Owner decisions closed (2026-10-02, owner in the repo session):** 4.1 frozen application ids, 4.2 key location
  and Play App Signing mode, 4.4 watch face module existence, 4.8 license - recorded in tickets S0001 and S0002 and
  in `CLAUDE.md` section 3.
- **Ticket id scheme:** `Sxxxx`, the harness default, cited with the repository name across repositories.
- **Divergences recorded:** `PLAN/` tracked (above); SZA-CTR02 exemption for the handoff.
- **Catalog:** this product's adoption rows written to the registry (PACKAGE-VERSIONING and INPUT-PARITY
  `pending`, the rule-adoption family verified); PACKAGE-VERSIONING families deliberately not registered (S0002
  sends the amendment to the canon session as a proposal beside the contract).
- **Remains:** phases 2-10 as tickets S0002-S0010; open owner decisions listed above.
- **Verification:** see the repo's S0001 `## Last Audit` for the compliance gate and harness validator runs.
