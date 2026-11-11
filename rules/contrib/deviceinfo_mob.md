---
# Contribution: deviceinfo_mob (overlay B, phone and wear sibling modules, no contract of its own) -> Unified_Rules
Source repo: P:\ANDROID\deviceinfo_mob | Date: 2026-11-10
Read: NEW_PROJECT_CHECKLIST, PLATFORM_OVERLAYS, REPOSITORY_LAYOUT, CONTRACTS, INVARIANTS, TESTING_AND_QA section 2, DEVELOPMENT section 8, the adopt-canon skill, REPO-STAMP and REPO-LAYOUT pointers, the harness scaffold and release-queue scripts; deduped against: contrib/filler_mob.md, contrib/tourist_mob.md, contrib/streamsplayer_mob.md, contrib/fastmediasorter_mob_v2.md
---

DeviceInfo for Android and Wear OS: the Device Information (System Info) sub-applications of FastMediaSorter (phone `SystemInfoActivity`, wear `SystemInfoScreen` and its contributor architecture, plus the battery work of FastMediaSorter S4529; `fastmediasorter_mob_v2.md`) as an independent product with its own release lifecycle, requested by FastMediaSorter S4528. The fourth Android extraction after StreamsPlayer, Tourist and Filler (`streamsplayer_mob.md`, `tourist_mob.md`, `filler_mob.md`), so almost all overlay-B material is CONFIRM of those records, and the adoption itself follows `filler_mob.md` step for step: a bootstrap stamp that supported scheduler discovery only (`contribRecord: null`, no pointer in the agent files, no launchers), completed afterwards by the repository's own S0001. Genuinely new against the siblings: the repository ships two installable packages from two Gradle modules (`phone`, `wear`) under one application id from the first ticket, with no flavor decision and no watch face; and the tree is not a git repository yet, so the "PLAN tracked" acceptance is read from the ignore list, not from `git check-ignore`.

## Overlay facts (verified against this repo, 2026-11-10)

- **Source root & release-mechanics.** Gradle modules `phone` and `wear` arrive with ticket S0002; `phone/src/main`, `phone/src/test`, `wear/src/main` and `wear/src/test` exist as empty folders and no `build.gradle.kts` is tracked. Specs in `PLAN/Sxxxx_<slug>.md`, harness run from the plugin through `tools/harness.ps1`; root launchers `r0.ps1`, `r1`-`r3`, `rs`, `rm`, `rw` rendered by the scaffold on 2026-11-10 (evidence: `.sza-profile.json` modules `phone`, `wear`; `tools/harness.ps1`; root listing). Portfolio entry: key `deviceinfo-mob`, rank 130, registry `permissionMode` `bypassPermissions` (evidence: `pq list`, `pq list -Json`).
- **Version shape.** PACKAGE-VERSIONING Android profile expected; no build and no tag yet (`versionShape.tagRegex` null). The contract is declared by S0002, with one application id for both packages.
- **Channels + listing files.** None - `channels: []`; distribution is an open owner decision (ticket S0008).
- **Frozen anchors.** None reserved, deliberately: the owner has chosen no application id, no signing key and no Play signing mode. S0002 builds under explicit provisional ids that are not anchors; S0008 freezes the real one on the owner's decision. The phone and wear packages share one id because the Wear OS Data Layer needs it (`docs/BOOTSTRAP_HANDOFF.md` section 1).
- **Editions + parity mechanism.** None - single edition, `shapes: []`; `wear` is a sibling module of the same build, not a flavor and not an edition (PLATFORM_OVERLAYS, overlay B, third axis). Coupling to FastMediaSorter: behaviour parity against the upstream's fresh inventory before every port ticket; the form of the parity inventory (a port ledger with a SHA-256 drift check as in the siblings, or another) is decided in S0003's plan pass.

## Channel-matrix rows (this project)

- None yet. Recorded when S0008 settles the distribution decisions.

## Deltas by document

### CONTRACTS.md
- CONFIRM: the repo holds no shared contract today - it writes and reads no format another product reads, and the registry has no row for it (a case-insensitive search of the catalog on 2026-11-10 for "deviceinfo", "device information", "device_info" and "System Info" found nothing). The catalog is named once, in `CLAUDE.md` line 3; there is no `docs/contracts/` yet, it arrives with the first declared contract. Expected declarations are listed in `CLAUDE.md` section 5 (package versioning, input parity, in-app help, the unified UI family, conditionally install trust and the web-page family). The phone-to-watch Data Layer pair is internal to one application id, the same reading `stream-catalog` takes for StreamsPlayer ("a Data Layer implementation contract, not a published interchange format"); whether it ever becomes a boundary is S0005's question. No `contract-sync` run was needed; it is owed by the tickets that build those surfaces.

### RELEASE_AND_DISTRIBUTION.md section 8
- CONFIRM with the sibling DIVERGE: the harness release plan stands as shipped (`RELEASE_QUEUE.md` with its `current-next-release: 1` marker, `RELEASE_READY.md`, `RELEASE_QUEUE_DONE.md`); package number from the marker, not from a branch; `PLAN/` **tracked** because there is no remote, so an ignored store would exist in one place only. `release-queue -Validate` exits 0.

### REPOSITORY_LAYOUT.md
- DIVERGE (temporary): no `LICENSE`. The owner has not chosen a license and the ticket forbids choosing one by assumption, so `SZA-LAY01` for `LICENSE` is an exemption in the stamp with `until` 2027-02-10; S0008 adds the file or renews the entry. Not a permanent divergence and not a request to change the rule. Same entry, same date as `filler_mob.md`.

### TESTING_AND_QA.md section 2
- CONFIRM: no build or test command exists yet, so `CLAUDE.md` section 6 names the fast tier as it stands (harness validator 0.9 s to 1.0 s, release-queue validator 0.8 s, compliance gate 1.2 s, all measured on 2026-11-10) and says that S0002 records the build command with its time and splits fast from release before the first test lands.

## No delta

INVARIANTS, NEW_PROJECT_CHECKLIST, DEVELOPMENT section 8 (ticket grammar and Complexity line), SECURITY_AND_PRIVACY (no permission is declared yet).

## Candidate core edits (PROPOSED - apply only on owner instruction)

- **`r0.ps1` template, `-DryRun`:** a dry run that only prints the order still resolves the child command and exits 2 with "r0: command 'claude' not found" when `claude` is not on the shell's PATH. Observed 2026-11-10 in an unattended session: `claude.exe` lives in `%USERPROFILE%\.local\bin`, which the tool shell's PATH does not carry; the same call exits 0 once that folder is on PATH and prints `child: C:\Users\serzh\.local\bin\claude.exe -p ..`. Either print the order with the command name unresolved, or name `-Command` in adopt-canon step 6a item 3, so "prove it" does not depend on the caller's PATH. Evidence: `r0.ps1` line 80 (`$Command = 'claude'`) and the two runs.
- **Scaffold default prompts:** the child prompt `r0.ps1` prints says "Work ticket {id} through ONE step of the task lifecycle .. advance it by exactly one status transition .. and stop", while the profile-less default the scaffold announces for `r1`-`r3` says "take this one ticket as far as it goes". Two meanings of one pass under one runner family; an owner reading `-DryRun` output of `r0` and the note of the scaffold sees both in one terminal. Say which is intended, or render both from one string. Evidence: `init-task-flow.ps1 -WhatIf` output, note line, and `r0.ps1 -DryRun` output, `child:` line, 2026-11-10.
- Confirmed unchanged from `filler_mob.md`, not repeated: the `tools/harness.ps1` forwarder cannot forward `check-compliance`; the `release-queue.ps1` header spells the marker `current-release:` where the script reads `current-next-release:`; adopt-canon step 6a item 1 reads as a gap in repositories worked only through `pq`.

## Candidate NEW docs (not in any shared doc yet)

- None required.

## Open questions for the owner

- Application id and its freeze, signing key and location, Play signing mode, license, public remote, distribution channel or channels, site and privacy page, store name and branding - all attached to ticket S0008 (the provisional ids to S0002), none decided.
- A local git repository for the tree - none exists; attached to S0002.
- Form of the parity inventory against the upstream - decided in the plan pass of S0003, after the upstream has been re-inventoried.

## Canon adoption 2026-11-10

Completion of the bootstrap adoption against canon **2026.11.10.1** (stamp version `2026.11.09.1`, core digest `sha256:9abe1d23..` equal to the installed canon's, so no re-sync and no version write by hand per REPO-STAMP rule 8), reference model, overlay B.

- **What changed in the repo:** `CLAUDE.md` rewritten from the bootstrap stub (canon pointer, catalog named once, upstream and parity as standing law, owner decisions taken and open, the release plan's six decisions, the layout, verification between releases); `AGENTS.md` replaced by the delegating stub; `.sza-canon.json` gained `schemaVersion`, `$comment`, `reconciledOn`, `contribRecord` and the LICENSE exemption; the day-0 scaffold wrote the plan files `RELEASE_READY.md`, `RELEASE_QUEUE_DONE.md`, `TICKET_TEMPLATE.md`, the empty archive and burned-ids stores, and the launchers `r0`-`r3`, `rs`, `rm`, `rw`; the eight spec command forwarders were written to `.claude/commands/`. `.gitignore` needed no change: the compliance gate reported no leak-glob finding.
- **Owner decisions closed:** none - the ticket forbids closing them by assumption; they are listed above.
- **Ticket id scheme:** `Sxxxx`, the harness default, cited with the repository name across repositories.
- **Divergences recorded:** `PLAN/` tracked; `LICENSE` absent under a dated exemption.
- **Catalog:** no registry rows written - the product holds no contract today; the first declared contract brings its rows and its `docs/contracts/` pointer.
- **Compliance gate:** 3 error(s), 0 warning(s) before (`SZA-LAY01` LICENSE; `SZA-RULES02` in `AGENTS.md` and in `CLAUDE.md`); after, run from the installed plugin: 0 error(s), 1 warning(s), exit 0 - the warning is `SZA-CANON06` for this record, which that gate resolves under the installed plugin's `rules/`; run from the canon checkout (same core digest `9abe1d23..`, where this record exists): 0 error(s), 0 warning(s), exit 0. The installed-plugin warning clears when the canon repository publishes this record.
- **Remains:** S0002-S0008 as ticketed; the open owner decisions above.
- **Verification:** see the repository's S0001 `## Last Audit`.
