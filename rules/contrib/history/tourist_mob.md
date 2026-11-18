# History: tourist_mob

## Canon state of this repository, 2026-11-13

The remote stamp declares canon `2026.10.17.1` with core digest `sha256:b467aefe..` (reconciled 2026-10-17, read from the
remote `.sza-canon.json`); the canon at the time of this refresh is `2026.11.13.2` (this repository's `CANON_VERSION`), so the
stamp is behind it, and the owner's report names it as warning `SZA-CANON03`. The re-sync is that repository's own adopt-canon
run. This record does not write a stamp it does not own, and it did not run `check-compliance` from that repository.

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

## Promotion campaign (2026-10-09)

- Spec `PLAN/S0012_free-promotion-campaign.md` (Draft, created through the harness), pre-launch, blocked by S0010 decisions; [PROMOTION](../../PROMOTION.md).

## In-app help (2026-10-16)

- Ticket `PLAN/S0014_in-app-help.md` (Draft), created by the canon session from the owner's request that every product with a user interface get F1 and a `?` button ([UI_UX](../../UI_UX.md) §7, contract `CONTEXT-HELP` 0.1). No code yet, so the surface count (about 7 screens, 4 dialogs, 4 widgets) is provisional; blocked behind S0004 (app bar and F1 path); the watch is out of scope; owner decisions D1-D9 are in the ticket.

## Canon delivery reconciliation 2026-10-17 (S4307)

- Installed plugin `2026.1017.1` from published canon `2026.10.17.1` (`d06a64a`). The harness counts Done and Skipped as finished and preserves the phase-counter suffix.
- Re-read the changed canon guidance for delivery, documentation, localization, layout and sealed contracts. Existing product implementation and contract catch-up work remains owned by the recorded project tickets; this delivery check does not certify every product contract.
- Re-stamped through `restamp-canon.ps1` against the installed plugin reader: version, freshly computed core digest and reconciledOn move together; adoptedOn and project-specific fields stay unchanged.
- Compliance for Tourist_mob: 0 error(s), 1 warning(s) before; 0 error(s), 0 warning(s) after; exit 0. Canon freshness findings cleared.

## Test lab report (2026-10-23)

- Ticket `PLAN/S0017_test-lab-report.md` (Draft; the harness placed it in package 1 of `RELEASE_QUEUE.md`), created by the canon session from the owner's order of 2026-10-23 to collect what every project knows about its hardware, emulators and test practice (contract `TEST-LAB` 0.1, draft). Documentation only: the product files one inventory report and a pointer; no code, test or harness changes. Reports to the Android profile owner (FMS_A).
- Ticket `PLAN/S0030_fast-checks-only-between-releases.md` (Draft, first in package 1 of `PLAN/RELEASE_QUEUE.md`), created by the canon session from the owner's order of 2026-10-29 to switch off full builds and tests longer than 5 s between releases (canon TESTING_AND_QA section 2, highest priority). The repo has to name a fast command and a release command in `CLAUDE.md`, move the Gradle unit suites, the emulator help and UI scripts and the done criteria of its open tickets to the release tier unless a recorded time puts them at 5 s or less, and keep `tools/release/preflight.ps1` whole; it has no branch CI.

## Record split 2026-11-18 (canon ticket S0120)

Every section of this file dated before this one was moved here verbatim from [../tourist_mob.md](../tourist_mob.md) when the record was split into facts and history. A line number quoted inside such a section counts lines of the record as it was before the move; relative links were deepened by one `../`; nothing else changed.
