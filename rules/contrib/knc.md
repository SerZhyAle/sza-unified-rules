---
# Contribution: KnC (overlays B + A + E, shared Kotlin Multiplatform core) -> Unified_Rules
Source repo: P:\MIX\KnC | Date: 26-11-24 19:05
Read: NEW_PROJECT_CHECKLIST, PLATFORM_OVERLAYS, REPOSITORY_LAYOUT, CONTRACTS; deduped against: contrib/fastmediasorter_mob_v2.md, contrib/fastmediasorter_web.md
---

> **Keep this note in the record.** Current facts, edited in place. Never append a dated section to this file,
> and append nothing under `history/` either: those files are frozen ([the rules of that folder](history/README.md))
> and are not reading for a task. A delta the core absorbed, a candidate that was applied or refused and a
> question that was answered are deleted here.

KnC (KnC: Kryvavitsa and the Monster) is the mini-game of FMS_A split out into standalone apps by FastMediaSorter
Android ticket S4859 (decision AD-02: one repository). The repository holds a shared Kotlin Multiplatform game core,
the content, and one native client per platform: KNC_A (Android) and KNC_A_WEAR (Wear OS) are the app names of the
Android and Wear clients inside the one repository, with a Windows desktop client and a web client beside them.
The logic is taken from FMS_A (the S4859 baseline); the history, and possibly mods and graphics, from the earlier web
game `KnC_26`. Genuinely new here: the first repository whose clients share compiled code across Android, JVM desktop
and JavaScript while releasing independently. The canon describes the
[shared-core multiplatform shape](../PLATFORM_OVERLAYS.md#shared-core-multiplatform-clients).
A new repository, created on 2026-11-24; nothing ships yet.

## Overlay facts (verified against this repo)

- **Source root & release-mechanics.** None yet. The decided layout is `core/` (Kotlin Multiplatform: common, jvm,
  android, js), `content/`, `android/`, `wear/`, `desktop/`, `web/` and, when the leaderboard starts, `server/`; the
  first implementation tickets create it. (evidence: the repository holds only the root files and the task-flow files
  on 2026-11-24; S4859 `architecture-decision.json` AD-02)
- **Version shape.** None, and no tag. Every build carries a `rulesVersion` and a `contentVersion`, and a saved run
  records both (S4859 check AC-VERSION-STAMP); the tag shape per edition is an owner decision for the release tickets.
  (evidence: the stamp's `versionShape.tagRegex` is null)
- **Channels + listing files.** None committed. (evidence: the stamp's `channels` is empty)
- **Frozen anchors.** None reserved. Each app reserves its own before its first upload: the Play `applicationId` and
  signing key of KNC_A and of KNC_A_WEAR, the Windows package identity, the web origin and manifest id.
- **Editions + parity mechanism.** Base product: the Android phone client (overlay B). Editions: `wear` (overlay B),
  `desktop` (overlay A), `web` (overlay E), each released on its own schedule (S4859 Q-PUB-01). Parity is held by the
  shared `core/` and by the captured reference cases RC-* run on the jvm, android and js targets, not by a PARITY.md;
  the difference kept on purpose is the round watch board geometry (S4859 Q-PAR-03, the ROUND_FIXED game type).
  (evidence: S4859 decisions AD-01 to AD-10 and checks AC-REFERENCE-CASES, AC-SEED-DETERMINISM, AC-VARIANTS)

## Channel-matrix rows (this project)

None yet.

## Deltas by document

None yet - the repository has not met a rule that needs a delta.

## No delta

Not assessed: nothing is built, so no rule document has been exercised.

## Shared contracts

This repository holds none today: it writes and reads no format that another product also reads. When the leaderboard
server starts, its wire and the replay check (the server recomputes a score from the move log with `core/`) are a
shared shape and move into the catalog first; the reference cases captured from FMS_A are the starting vectors.

## Open questions for the owner

- The licence of KnC. The owner's repositories carry MIT and Apache 2.0 and the predecessor `KnC_26` carries none;
  the stamp holds an exemption of check SZA-LAY01 until `LICENSE` exists.
- The GitHub remote and the public name. Nothing is created or pushed until the owner asks.
- What "history" means for the transfer from `KnC_26`: its git history, the story in its README and `OLD/`, or both, and
  the form of the transfer (imported git history or a copy).
- The order of the sixteen tickets KNCGAM-0001 to KNCGAM-0016 (filed in dependency order; the owner moves rows in
  PORTFOLIO_QUEUE.md), the public name of each app and the frozen anchors of each channel. The release ledger is hooked
  by KNCGAM-0010 and the registry rows by KNCGAM-0002; nothing builds yet, so neither is set up.
