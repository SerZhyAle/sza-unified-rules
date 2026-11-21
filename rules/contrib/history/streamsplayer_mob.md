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

## Canon adoption 26-11-20 19:58 (STRMOB-0176)

Full 20-document re-sync from canon **2026.10.17.1** (`sha256:b467aefe..`, reconciled 2026-10-17, no `canon.docDigests`) to canon **2026.11.20.4** (`sha256:202d3d9a..`, reconciled 2026-11-20), reference model, overlay B.

- **Reconciled rule documents (all 20):** `AI_USAGE`, `AUTHOR`, `CHANNEL_MATRIX`, `CONTRACTS`, `DEVELOPMENT`, `DOCUMENTATION_CONCEPT`, `GITHUB_INTERACTION`, `INVARIANTS`, `LOCALIZATION`, `NEW_PROJECT_CHECKLIST`, `PLATFORM_OVERLAYS`, `PROMOTION`, `RELEASE_AND_DISTRIBUTION`, `REPOSITORY_LAYOUT`, `SECURITY_AND_PRIVACY`, `SITE_CONFIGURATION`, `SUPPORT_AND_FEEDBACK`, `TESTING_AND_QA`, `UI_UX`, `WINDOWS_PACKAGING` (not applicable to overlay B).
- **What changed in the repo:**
  - `.sza-canon.json`: added `schemaVersion` `"1.0"`, updated `canon.version` to `"2026.11.20.4"`, `canon.coreDigest` to `"sha256:202d3d9a49cb559dc7b760aa6f10bb6f49a2764dd4cf46d80573bbbabed4008b"`, wrote all 20 `canon.docDigests`, and set `canon.reconciledOn` to `"2026-11-20"` (`adoptedOn` stays `"2026-10-02"`).
  - Day-0 task flow (step 6a): ran `init-task-flow.ps1 -Root .` to render `r0.ps1`, `r1.ps1`, `r2.ps1`, `r3.ps1`, `rs.ps1`, `rm.ps1`, `rw.ps1`, `PLAN/spec-catalog-archive.jsonl`, `PLAN/spec-catalog-burned-ids.jsonl` and `PLAN/TICKET_TEMPLATE.md`; verified `pq.ps1 register` (`already registered streams-mob`), `register-spec-commands.ps1` (`StreamsPlayer_mob wrote 3, unchanged 5`), `spec_catalog/validate` (`11 OK, 0 WARN, 0 FAIL`), `release-queue -Validate` (`OK - 183 ticket(s), no drift`) and `r0.ps1 -DryRun`.
  - Release ledger (step 6b): `docs/releases/` and the `a.ps1` build hook (`Invoke-ReleaseLedgerBuild`, S0154) stand; ran `release-ledger import` (`0 new event(s)`) and `release-ledger probe` (`0 new event(s)`, all 6 Play channels `nothing published`).
  - Shared-contract catch-up (`contract-sync`):
    - `DEVICE-EXCHANGE` 1.17 -> 1.18: read section 42 and `REMOTE-COMMAND-2026-11-20.md` (items GC-GG); `command-v1` target is owned by `STRMOB-0168` (`REMOTE-CONTROL` adoption) and nothing is declared before it lands; item GG adopts the `vectors/fmsw-dy/` server corpus without changing vendored client vectors. Pointer and own registry row moved to `partial 1.18`.
    - `EXCHANGE-MARK` 0.5 -> 0.6: re-vendored `phone/src/main/assets/help/img/exchange-mark-full.svg` byte for byte from the 0.6 catalog artwork (rule 16); `Find-ExchangeMark.ps1` exited 0 (`exchange-mark: PASS (4 of 45 manifest files vendored, 0 inline)`). Pointer and own registry row moved to `partial 0.6`.
    - `GOOGLE-PLAY` 0.2 -> 0.3: read section G (rules 28-31, submissions and review time); updated `docs/contracts/GOOGLE-PLAY.md`, `docs/play/PLAY_RELEASE_RECORD.md` section 6 and the own registry row to `partial 0.3`.
    - `ICON-SET` 0.43 -> 0.44: read sections 31 and 32 (`app.logo` redrawn to the FastMediaSorter family mark; another family shows its own mark as identity artwork). Recorded a dated Section 3 exception for the ported donor `ic_notification_app_logo.xml` (`phone` and `wear`, used as `NotificationIcons.STATUS_BAR` and in `view_settings_about.xml:31`), carried by `STRMOB-0167` (`PRODUCT-IDENTITY` alignment), and moved the pointer and own registry row to `partial 0.44`.
- **Divergences and candidates retired from the facts record:**
  - Former `DIVERGE: PLAN/ is tracked` and open question `Public PLAN/` deleted: settled 2026-11-16 by the owner (`PLAN/` is local and gitignored; `.gitignore:64`, `git ls-files PLAN` is 0).
  - Candidate core edit `Harness ticket-id grammar` deleted: absorbed in canon S0152 (`New-CatalogId` reads `Get-SzaTicketIdSpec`), migrated here in `STRMOB-0164` (`STRMOB-NNNN`).
  - Open question `Upload key and signing-key import` closed: completed 2026-11-17 (`docs/play/PLAY_RELEASE_RECORD.md` section 1).
  - Open question `Watch-face listing` closed as a source gap: `docs/play/PLAY_LISTING_WATCHFACE*.md` exists (`S0072`); watch-face upload waits on captured watch-face icons (`STRMOB-0099`).
- **Verification:** `check-compliance.ps1` 0 error(s), 1 warning(s) (`SZA-CANON03`) before -> `0 error(s), 0 warning(s)` after, exit 0; `check-sync.ps1` exit 0 (`contract-sync: PASS (37 pointer versions)`); `contract-lag.ps1 -Product 'StreamsPlayer Android' -FailOnLag` exit 0 (`behind 0, unread 0, partial 19, current 11, n/a 1, pending 0, unparsed 0`).

## Play API first-use correction (2026-11-21, CANONR-0164)

- The canon facts record replaces the 0.2 declaration-after-draft-upload instructions with the first-use
  stops in `GOOGLE-PLAY` 0.4 section 8C. This records the contract owner's disposition. StreamsPlayer's
  adoption evidence remains the responsibility of its Android repository.
