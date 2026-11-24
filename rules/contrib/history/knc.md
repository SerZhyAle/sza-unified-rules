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
