# History: streamsplayer_mob

## Canon state of this repository, 2026-11-13

The stamp declares canon `2026.10.17.1` with core digest `sha256:b467aefe..` (reconciled 2026-10-17, read from
`.sza-canon.json`); the canon at the time of this refresh is `2026.11.13.2`, so the stamp is behind it. The re-sync is that
repository's own adopt-canon run. This record does not write a stamp it does not own, and it did not run `check-compliance`
from that repository.

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

- Spec `PLAN/S0014_free-promotion-campaign.md` (Draft, created through the harness), pre-launch, blocked by S0010 decisions; [PROMOTION](../../PROMOTION.md).

## In-app help (2026-10-16)

- Ticket `PLAN/S0035_in-app-help-f1-and-help-button.md` (Draft, priority 40), created by the canon session from the owner's request for F1 and a `?` button in every product ([UI_UX](../../UI_UX.md) §7, contract `CONTEXT-HELP` 0.1). About 20 phone surfaces and 7 Wear routes; `SupportDestination.HELP` still opens the FastMediaSorter docs; no site yet (decision 4.7). Eight owner questions are in the ticket.

## Canon delivery reconciliation 2026-10-17 (S4307)

- Installed plugin `2026.1017.1` from published canon `2026.10.17.1` (`d06a64a`). The harness counts Done and Skipped as finished and preserves the phase-counter suffix.
- Re-read the changed canon guidance for delivery, documentation, localization, layout and sealed contracts. Existing product implementation and contract catch-up work remains owned by the recorded project tickets; this delivery check does not certify every product contract.
- Re-stamped through `restamp-canon.ps1` against the installed plugin reader: version, freshly computed core digest and reconciledOn move together; adoptedOn and project-specific fields stay unchanged.
- Compliance for StreamsPlayer_mob: 0 error(s), 2 warning(s) before; 0 error(s), 1 warning(s) after; exit 0. Canon freshness findings cleared.

## Exchange server mark (2026-10-19)

- Ticket `PLAN/S0039_exchange-server-mark.md` (Draft, priority 45), created by the canon session from the owner's request for one shared mark of the exchange server in every product (contract `EXCHANGE-MARK` 0.1). 30 inventory rows: the exchange screen, its errors and certificate dialogs, the publish state line, the portal topic chooser and one docs row take the mark; the watch has no exchange surface yet (S0022) and the phone has no About, account list, source-kind row or site. Four findings for the catalog (no flat Android vector for 24 dp; the one-tone file's `?attr` tint cannot be a notification small icon; the portal's name differs; the check script walks `build/`). Four owner questions are in the ticket.

## Test lab report (2026-10-23)

- Ticket `PLAN/S0040_test-lab-report.md` (Draft, deliberately not queued: `release-queue -Validate` exits 1 until the owner places it), created by the canon session from the owner's order of 2026-10-23 to collect what every project knows about its hardware, emulators and test practice (contract `TEST-LAB` 0.1, draft). Documentation only: the product files one inventory report and a pointer; no code, test or harness changes. Reports to the Android profile owner (FMS_A).
- Ticket `PLAN/S0056_fast-checks-only-between-releases.md` (Draft, first in package 1 of `PLAN/RELEASE_QUEUE.md`), created by the canon session from the owner's order of 2026-10-29 to switch off full builds and tests longer than 5 s between releases (canon TESTING_AND_QA section 2, highest priority). The repo has to name a fast command and a release command in `CLAUDE.md`, move the self-tests, the phone and wear Gradle suites and the done criteria of its open tickets to the release tier unless a recorded time puts them at 5 s or less, and keep `tools/release/pre-release-sweep.ps1` whole; it has no branch CI that builds or tests on push.

## Document registry (2026-11-08, S0051)

- The stamp declares `docRegistryShape: 1` and `docRegistryFile: docs/DOCUMENT_REGISTRY.jsonl` (`REPO-STAMP` rule 4), with no canon re-sync: `canon.version` and the digest did not move in this run. One registry, no local one: the corpus is tracked as a whole (`DOC-INTERNAL-QUALITY` item K). `PLAN/` stays outside it, its journal being its registry, and the working-tree `PLAN/` ignore line was removed to match `CLAUDE.md` section 4 item 6; StreamsPlayer_mob S0046 input D1 stays the owner's before the first push.
- The canon's `document_registry/validate` runs inside `tools/docs/assert-doc-registry.ps1`, which adds what it lacks per item L: reverse coverage, the `role` field, the docs index. `document_registry/generate` is not used: this site's sitemap has its own generator. Permanent variants: `docs/design/DOC_QUALITY_VARIANTS.md` in that repository.
- A canon defect to weigh in a canon session, not a stop here: the record's `generated` field and the contract's `role` carry one fact twice, and this repository holds them equal by gate.

## Record split 2026-11-18 (canon ticket S0120)

Every section of this file dated before this one was moved here verbatim from [../streamsplayer_mob.md](../streamsplayer_mob.md) when the record was split into facts and history. A line number quoted inside such a section counts lines of the record as it was before the move; relative links were deepened by one `../`; nothing else changed.
