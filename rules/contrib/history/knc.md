# History: knc

## Canon adoption 26-11-24 19:10

New-repository adoption against canon **2026.11.24.3**, core digest `sha256:de51be9d..`, reference model, overlays **B**,
**A** and **E** with the editions `wear`, `desktop` and `web` (the adopting session's reading; the canon has no overlay
for a shared-core multiplatform repository, recorded as a candidate core edit in the facts record).

- **Why the repository exists.** FastMediaSorter Android ticket S4859 (knc-standalone-apps) closed Verified on
  2026-11-24 with decision AD-02, one KnC repository, and created nothing. The owner asked whether the new project was
  in the system (it was not: no registry key, no folder, no ticket). A first follow-up, FMS_A ticket S4887, was drafted
  in the FMS_A queue by a wrong guess and archived the same day on the owner's word; day 0 was run from the canon
  session instead, in the folder the owner chose (`P:\MIX\KnC`, the owner's new parent folder for repositories that
  span platforms).
- **What was created in the repo:** `.sza-canon.json`, `.sza-profile.json` (ticket id pattern `^KNCGAM-\d{4}$`, the
  six-character prefix of the owner's map of 2026-11-19), `CLAUDE.md`, the delegating `AGENTS.md`, `README.md`,
  `.gitignore` with the leak globs, `PLAN/` (ledger, archive, burned ids, the three release-plan files, the ticket
  template), `tools/harness.ps1`, the launchers `r0`-`r3`, `rs`, `rm`, `rw`, and `dev/origin/` (local copies of the
  S4859 baseline, options matrix, architecture decision, questionnaire and the S4859 and S4887 specs).
- **Owner statements recorded:** `KnC_26` is not an obsolete copy - history, possibly mods and graphics come from it;
  the game logic comes from FMS_A as of 2026-11-24; KNC_A and KNC_A_WEAR are app names inside one repository; the goal is
  a convenient, fast, beautiful application that has a history; FMS_A is only the donor and later gets cross-references
  and takes part in the top.
- **Closed:** the consumption model (reference), the permission mode of unattended children (the registry's
  `bypassPermissions`), the shared-contract question (none held today).
- **Remains:** the licence (stamp exemption of SZA-LAY01), the GitHub remote and public name, what "history" means for
  the transfer from `KnC_26`, the first implementation tickets and the frozen anchors, and the release ledger hook
  (nothing builds yet).

## Tickets filed 26-11-24 19:20

The owner asked for tickets and for the repository to be put under every rule, canon and contract. Sixteen Draft
tickets were filed in dependency order with the owner's words kept verbatim in section 0 of each: KNCGAM-0001 build
skeleton, 0002 contract catch-up (the registry rows are written there, after the contracts are read), 0003 game core
port from FastMediaSorter Android, 0004 content module, 0005 to 0008 the four clients (KNC_A, KNC_A_WEAR, Windows,
web), 0009 verification and test lab, 0010 release ledger and versioning, 0011 interface family, help and identity,
0012 localization and documents, 0013 privacy, security and store presence, 0014 site, indexing and promotion, 0015
history and asset transfer from KnC_26 (BlockQuestions, a Q: token), 0016 leaderboard server specification (priority 10,
last). The contract set named in 0002 comes from the registry rows of Filler Android (38), DeviceInfo (23) and
FastMediaSorter Android (48) on this date plus the Windows and web contracts. No registry row was written from this
session: a row says "verified", and nobody had read the contracts at their versions for this repository. The project
stays disabled in the portfolio registry, so no robot takes a ticket until the owner enables it.

## Recommendation decision 2026-11-25 (CANONR-0179)

Accepted by the portfolio owner. PLATFORM_OVERLAYS defines shared-core multiplatform clients, and
NEW_PROJECT_CHECKLIST points to that shape. The existing B, A and E overlays and the edition
declarations cover KnC. Each client follows its own platform and release rules. The shared core
and reference cases cover common behaviour. The original proposal and resolved question follow.

### Candidate core edits (PROPOSED - apply only on owner instruction)

- **PLATFORM_OVERLAYS, Editions / Co-shipping shapes**: name the shared-core multiplatform shape - one repository,
  one compiled core shared by clients on several platforms, independent releases per client, parity held by shared
  code and reference cases instead of a PARITY.md and not by compile-time seams of a single exe. Until then a repository
  of this shape declares a combination of overlays plus editions, as this one does. The failure it prevents: each such
  repository inventing its own reading of `overlay` and `editions`. Evidence: the stamp of this repository and
  `check-compliance.ps1` SZA-CANON04, which accepts several overlays only with an `editions` or `shapes` entry.

### Candidate NEW docs (not in any shared doc yet)

None required.

### Question as filed

- Whether the canon adopts a dedicated overlay for this shape (the candidate core edit above).
