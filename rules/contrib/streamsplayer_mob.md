---
# Contribution: streamsplayer_mob (overlay B, flavor shape, three packages, LIVE-BROADCAST producer) -> Unified_Rules
Source repo: P:\ANDROID\StreamsPlayer_mob | Date: 2026-10-02
Read: NEW_PROJECT_CHECKLIST, PLATFORM_OVERLAYS, REPOSITORY_LAYOUT, CONTRACTS, INVARIANTS, RELEASE_AND_DISTRIBUTION section 8, AI_USAGE (sections), harness README and spec_catalog SCHEMA; deduped against: contrib/fastmediasorter_mob_v2.md, contrib/streams_player.md
---

StreamsPlayer for Android: phone app, Wear OS app and watch face for internet radio, live video and RTSP, plus
live broadcast from phone and watch. An independent product extracted from FastMediaSorter Android
(`fastmediasorter_mob_v2.md`) under its ticket S4053 of that repository; the Android sibling of StreamsPlayer for
Windows (`streams_player.md`), with which it shares contracts only. Born on 2026-10-02 as a new repo adopting the
canon from commit one, so most overlay-B material is CONFIRM of the FastMediaSorter record. Genuinely new: a
product whose no-drift guarantee against its extraction source is a port ledger with a SHA-256 drift check rather
than shared code, and the first adopter of the shipped harness that never had a local copy of it.

## Overlay facts (verified against this repo, 2026-10-02)

- **Source root & release-mechanics.** Gradle modules phone / wear / watchface, arriving with ticket S0002; none
  exist yet. Specs in `PLAN/Sxxxx_<slug>.md`, the harness run from the plugin through `tools/harness.ps1`
  (evidence: `.sza-profile.json`, `tools/harness.ps1`).
- **Version shape.** PACKAGE-VERSIONING Android profile; no build, no tag yet (`versionShape.tagRegex` null).
- **Channels + listing files.** None yet - `channels: []`; `play` is declared with the first tracked
  `build.gradle.kts` (S0002), GitHub/sideload per owner decision 4.3 (S0010).
- **Frozen anchors (owner, 2026-10-02).** `com.sza.streamsplayer` shared by phone and watch (Data Layer needs one
  id and one key) and by the noLegal variant (sanctioned exception, never co-published to one store);
  `com.sza.streamsplayer.watchface`. Signing key at `P:\ANDROID\StreamsPlayer_credentials`; Play App Signing with
  the product's own key imported as the app signing key plus a separate upload key, so store and sideload builds
  carry one signature.
- **Editions + parity mechanism.** None - single edition. Shape: flavor (store, noLegal); wear and watchface are
  sibling modules. Coupling to FastMediaSorter: contracts plus a port ledger and drift check (handoff section 6a).

## Channel-matrix rows (this project)

- None yet. Recorded when S0002 (Play) and S0010 (distribution, decision 4.3) land.

## Deltas by document

### CONTRACTS.md
- CONFIRM: the repo names the catalog in one file (`CLAUDE.md` line 3); ten pointers in `docs/contracts/`
  (STREAM-BANK, LIVE-BROADCAST as producer, USER-PLAYLIST, MEDIA-CLASSIFICATION, PACKAGE-VERSIONING, INPUT-PARITY,
  DIAGNOSTIC-REPORT and INSTALL-TRUST conditional, the rule-adoption family, the product-web-pages family
  conditional). `docs/BOOTSTRAP_HANDOFF.md` names the catalog path too: an origin record written and amended on
  2026-10-02 by the FastMediaSorter session of its ticket S4053 (the amendment on the owner's instruction), not
  edited from this repository; it carries a dated SZA-CTR02 exemption.

### RELEASE_AND_DISTRIBUTION.md section 8
- CONFIRM with one DIVERGE: the harness release plan stood up as shipped; package number from the
  `current-next-release:` marker, not from a branch, because this repo works on `main`. DIVERGE: `PLAN/` is
  **tracked**, unlike FastMediaSorter's ignored store - there is no remote, so an ignored store would exist in one
  place only, and the tickets carry the owner's recorded decisions.

## No delta

REPOSITORY_LAYOUT (Android spec home), INVARIANTS, NEW_PROJECT_CHECKLIST.

## Candidate core edits (PROPOSED - apply only on owner instruction)

- **Harness ticket-id grammar (tools/harness):** `grammar.ticketIdPattern` is a profile key, but `New-CatalogId`
  (`spec_catalog/_lib.ps1`) and `insert.ps1 -Id` hard-code `^S\d{4}$` (canon session count: 57 occurrences in
  42 files). A profile with another scheme validates ids that allocation can never issue. Confirmed by the canon
  session 2026-10-02, not scheduled; this repo keeps the default.
- **adopt-canon step 1:** the session that started before a plugin update keeps the old skill listing; this run
  had to read the 2026.1002.2 skill, template and gate from the new install path by hand.

## Candidate NEW docs (not in any shared doc yet)

- None required.

## Open questions for the owner

- 4.3 distribution of the first release, 4.4 watch face composition, 4.5 GitHub remote, 4.7 site - each attached
  to the ticket of the phase that needs it (S0010, S0008, S0010, S0010).

## Canon adoption 2026-10-02

New-repo adoption against canon **2026.10.02.2**, core digest `sha256:410463a9..`, reference model, overlay B.

- **What changed in the repo:** `CLAUDE.md` rewritten from the bootstrap stub (canon pointer, catalog named once,
  handoff section 6a as standing law, frozen anchors, the release plan's six decisions); `AGENTS.md` kept as the
  delegating stub; new `.sza-canon.json`, `.sza-profile.json`, `tools/harness.ps1`, `LICENSE` (MIT),
  `.gitignore` leak globs, `docs/README.md`, `docs/contracts/` (index + ten pointers), `PLAN/` (journal, S0001-S0010,
  three release-plan files).
- **Owner decisions closed (2026-10-02, owner in the repo session):** 4.1 frozen application ids, 4.2 key location
  and Play App Signing mode, 4.6 license - recorded in ticket S0002 and in `CLAUDE.md` section 3.
- **Ticket id scheme:** `Sxxxx`, the harness default, cited with the repository name across repositories.
- **Divergences recorded:** `PLAN/` tracked (above).
- **Canon defect found and fixed (2026-10-02, by the canon session):** `spec_catalog/validate.ps1` exited 1 with
  "The property 'Count' cannot be found on this object" until the first `S####_*` entry existed in `PLAN/`:
  `$prefixed` was `$null` and line 93 read `$prefixed.Count` under StrictMode. Fixed at line 78 with `@()`;
  reproduced in a scratch repository with no journal file and with a zero-byte one, both exit 0 with 9 OK after
  the fix, and this repo's 10-ticket journal stays 9 OK. FastMediaSorter never met it: its `PLAN/` always holds
  ticket files.
- **Catalog:** this product's adoption rows written to the registry and a consumer entry to the stream-catalog
  consumers list, all `pending` until code exists; PACKAGE-VERSIONING families deliberately not registered
  (S0002 sends the amendment diff to the canon session).
- **Remains:** phases 2-10 as tickets S0002-S0010; open owner decisions 4.3, 4.4, 4.5, 4.7.
- **Verification:** see the repo's S0001 `## Last Audit` for the compliance gate and harness validator runs.

## Promotion campaign (2026-10-09)

- Spec `PLAN/S0014_free-promotion-campaign.md` (Draft, created through the harness), pre-launch, blocked by S0010 decisions; [PROMOTION](../PROMOTION.md).
