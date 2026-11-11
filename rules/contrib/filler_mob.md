---
# Contribution: filler_mob (overlay B, single phone module, no contract of its own) -> Unified_Rules
Source repo: P:\ANDROID\filler_mob | Date: 2026-11-10
Read: NEW_PROJECT_CHECKLIST, PLATFORM_OVERLAYS, REPOSITORY_LAYOUT, CONTRACTS, INVARIANTS, TESTING_AND_QA section 2, DEVELOPMENT section 8, the adopt-canon skill, REPO-STAMP and REPO-LAYOUT pointers, the harness scaffold and release-queue scripts; deduped against: contrib/tourist_mob.md, contrib/streamsplayer_mob.md, contrib/fastmediasorter_mob_v2.md
---

Filler for Android: the local-storage Filler of FastMediaSorter (upstream ticket S4521, `fastmediasorter_mob_v2.md`) as an independent phone product with its own release lifecycle, requested by FastMediaSorter S4523. The third Android extraction after StreamsPlayer for Android and Tourist for Android (`streamsplayer_mob.md`, `tourist_mob.md`), so almost all overlay-B material is CONFIRM of those records. Genuinely new against the siblings: the repository was born as a bootstrap with a stamp that supported scheduler discovery only (`contribRecord: null`, no pointer in the agent files, no launchers), and S0001 completed the adoption afterwards instead of at commit one; and the owner left the application id, signing key, license, remote and distribution channel open on purpose, so the adoption records those as decisions attached to tickets rather than as frozen anchors.

## Overlay facts (verified against this repo, 2026-11-10)

- **Source root & release-mechanics.** Gradle module `phone` arrives with ticket S0002; `phone/src/main` and `phone/src/test` exist as empty folders and no `build.gradle.kts` is tracked. Specs in `PLAN/Sxxxx_<slug>.md`, harness run from the plugin through `tools/harness.ps1`; root launchers `r0.ps1`, `r1`-`r3`, `rs`, `rm`, `rw` rendered by the scaffold on 2026-11-10 (evidence: `.sza-profile.json`, `tools/harness.ps1`, root listing). Portfolio entry: key `filler-mob`, rank 120, registry `permissionMode` `bypassPermissions` (evidence: `pq list -Json`).
- **Version shape.** PACKAGE-VERSIONING Android profile expected; no build and no tag yet (`versionShape.tagRegex` null). The contract is declared by S0002.
- **Channels + listing files.** None - `channels: []`; distribution is an open owner decision (ticket S0007).
- **Frozen anchors.** None reserved, deliberately: the owner has chosen no application id, no signing key and no Play signing mode. S0002 builds under an explicit provisional id that is not an anchor; S0007 freezes the real one on the owner's decision.
- **Editions + parity mechanism.** None - single edition, `shapes: []` (no flavor decision yet). Coupling to FastMediaSorter: behaviour parity against the completed S4521, re-inventoried before every port ticket; the form of the parity inventory (a port ledger with a SHA-256 drift check as in the siblings, or another) is decided in S0003's plan pass.

## Channel-matrix rows (this project)

- None yet. Recorded when S0007 settles the distribution decisions.

## Deltas by document

### CONTRACTS.md
- CONFIRM: the repo holds no shared contract today - it writes and reads no format another product reads, and the registry has no row for it (grepped over the catalog on 2026-11-10: the only hits for the product name are the English word "filler" in `FDSEC-FORMAT` and `PAGE-STYLE`). The catalog is named once, in `CLAUDE.md` line 3; there is no `docs/contracts/` yet, it arrives with the first declared contract. Expected declarations are listed in `CLAUDE.md` section 5 (package versioning, input parity, in-app help, the unified UI family, conditionally install trust and the web-page family). No `contract-sync` run was needed; it is owed by the tickets that build those surfaces.

### RELEASE_AND_DISTRIBUTION.md section 8
- CONFIRM with the sibling DIVERGE: the harness release plan stands as shipped (`RELEASE_QUEUE.md` with its `current-next-release: 1` marker, `RELEASE_READY.md`, `RELEASE_QUEUE_DONE.md`); package number from the marker, not from a branch; `PLAN/` **tracked** because there is no remote, so an ignored store would exist in one place only. `release-queue -Validate` exits 0, `-List -Ready` exits 0 on the empty ready file.

### REPOSITORY_LAYOUT.md
- DIVERGE (temporary): no `LICENSE`. The owner has not chosen a license and the ticket forbids choosing one by assumption, so `SZA-LAY01` for `LICENSE` is an exemption in the stamp with `until` 2027-02-10; S0007 adds the file or renews the entry. Not a permanent divergence and not a request to change the rule.

### TESTING_AND_QA.md section 2
- CONFIRM: no build or test command exists yet, so `CLAUDE.md` section 6 names the fast tier as it stands (harness validator, release-queue validator, compliance gate, all measured under 2 s on 2026-11-10) and says that S0002 records the build command with its time and splits fast from release before the first test lands.

## No delta

INVARIANTS, NEW_PROJECT_CHECKLIST, DEVELOPMENT section 8 (ticket grammar and Complexity line), SECURITY_AND_PRIVACY (no permission is declared yet).

## Candidate core edits (PROPOSED - apply only on owner instruction)

- **`tools/harness.ps1` forwarder / adopt-canon step 8:** the forwarder's candidate directories all end in `tools/harness`, so the canon's own compliance gate (`<plugin>/tools/check-compliance.ps1`) cannot be run through it, and every adopter's agent file has to describe how to resolve the plugin root by hand from `installed_plugins.json`. Forward `check-compliance` (and `-PrintDigest`) the same way as the harness scripts, or ship a one-line `tools/check-canon.ps1` in the scaffold. Prevents each repo writing a different plugin-root recipe into its rules file; evidence: `tools/harness.ps1` lines 34-55 of this repository's forwarder.
- **`spec_catalog/release-queue.ps1` header, line 24:** documents the marker as `current-release:`, while the script reads and writes `current-next-release:` (lines 177, 182, 252) and the scaffold seeds that spelling. Fix the header comment. Evidence: `grep -n "current-" release-queue.ps1` on plugin 2026.1110.1.
- **adopt-canon step 6a, item 1:** it says a repo with a profile, a ledger and launchers "stands" on day 0 and otherwise runs the scaffold; Tourist_mob carries neither `r0.ps1` nor an `a.ps1` (checked 2026-11-10), so the step as written reads as a gap in an adopted repository; StreamsPlayer_mob has no `r0.ps1` but an `a.ps1` whose `r0` target was not inspected. Say whether the launchers are mandatory for repositories that are worked only through `pq`, or let the FLOW gate (still advisory behind `-CheckTaskFlow`) report them uniformly.

## Candidate NEW docs (not in any shared doc yet)

- None required.

## Open questions for the owner

- Application id and its freeze, signing key and location, Play signing mode, license, public remote, distribution channel or channels, site and privacy page, store name and branding - all attached to ticket S0007 (the provisional id to S0002), none decided.
- Form of the parity inventory against S4521 - decided in the plan pass of S0003, after the upstream has been re-inventoried.

## Canon adoption 2026-11-10

Completion of the bootstrap adoption against canon **2026.11.10.1** (stamp version `2026.11.09.1`, core digest `sha256:9abe1d23..` equal to the installed canon's, so no re-sync and no version write by hand per REPO-STAMP rule 8), reference model, overlay B.

- **What changed in the repo:** `CLAUDE.md` rewritten from the bootstrap stub (canon pointer, catalog named once, upstream and parity as standing law, owner decisions taken and open, the release plan's six decisions, the layout, verification between releases); `AGENTS.md` replaced by the delegating stub; `.sza-canon.json` gained `schemaVersion`, `reconciledOn`, `contribRecord` and the LICENSE exemption; `.gitignore` gained the missing leak globs; the day-0 scaffold wrote the plan files `RELEASE_READY.md`, `RELEASE_QUEUE_DONE.md`, `TICKET_TEMPLATE.md`, the empty archive and burned-ids stores, and the launchers `r0`-`r3`, `rs`, `rm`, `rw`; the eight spec command forwarders were written to `.claude/commands/`.
- **Owner decisions closed:** none - the ticket forbids closing them by assumption; they are listed above.
- **Ticket id scheme:** `Sxxxx`, the harness default, cited with the repository name across repositories.
- **Divergences recorded:** `PLAN/` tracked; `LICENSE` absent under a dated exemption.
- **Catalog:** no registry rows written - the product holds no contract today; the first declared contract brings its rows and its `docs/contracts/` pointer.
- **Compliance gate:** 3 error(s), 1 warning(s) before; after, run from the installed plugin: 0 error(s), 1 warning(s), exit 0 - the warning is `SZA-CANON06` for this record, which that gate resolves under the installed plugin's `rules/`; run from the canon checkout (same core digest `9abe1d23..`, where this record exists): 0 error(s), 0 warning(s), exit 0. The installed-plugin warning clears when the canon repository publishes this record.
- **Remains:** S0002-S0007 as ticketed; the open owner decisions above.
- **Verification:** see the repository's S0001 `## Last Audit`.
