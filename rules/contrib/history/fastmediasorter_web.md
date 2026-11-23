# History: fastmediasorter_web

## Canon adoption 2026-10-16

New-repo adoption against canon **2026.10.15.4**, core digest `sha256:224d2a22..`, reference model, overlay **E**
(drafted above).

- **What changed in the repo:** `CLAUDE.md` rewritten from the bootstrap stub (canon pointer, catalog named once, the
  widened goal and the names, ADR-1 and ADR-2, the standing law from handoff section 3, owner decisions, the ticket
  store and the six release-plan decisions, the R0 runner); `AGENTS.md` kept as the delegating stub; new
  `.sza-canon.json`, `.sza-profile.json`, `tools/harness.ps1`, `r0.ps1`, `LICENSE` (MIT), `docs/README.md`,
  `docs/contracts/` (index and pointers), `PLAN/` (journal, tickets from S0001, the three release-plan files, the
  ticket template); `.gitignore` gained the missing leak globs and the developer-local roles; `README.md` carries the
  widened goal.
- **Owner decisions closed (2026-10-16, owner in the repo session):** handoff decision 3, license MIT; the goal widened
  to a subset of FMS_A and FMS_Win functions; the names FMS_A, FMS_Win, FMS_Web; the R0 child permission mode
  `bypassPermissions`; the attended one-ticket rehearsal deferred.
- **Ticket id scheme:** `Sxxxx`, the harness default, cited with the repository name across repositories.
- **Divergences recorded:** `PLAN/` tracked; two SZA-CTR02 exemptions for the origin records; `editions` left empty
  with the reason above.
- **Catalog:** seven adoption rows written to the registry (`DEVICE-EXCHANGE`, `LIVE-BROADCAST`, `TASK-FLOW` pending;
  `REPO-STAMP`, `HARNESS-PROFILE`, `REPO-LAYOUT`, `RULE-DELIVERY` verified); `contract-lag.ps1` reads them with 0
  unparsed. No contract edited.
- **Remains:** S0002 onward; the attended R0 rehearsal; the first commit, when the owner asks.
- **Verification:** see the repo's S0001 `## Last Audit`.

## Re-sync 2026-10-16

Reconciled the same day against canon **2026.10.16.1**, core digest `sha256:18957ab0..`, which adopted overlay E
from this record and the three candidate core edits. Re-read the changed rule docs (PLATFORM_OVERLAYS "Overlay E",
INVARIANTS item 1, NEW_PROJECT_CHECKLIST step 0); nothing in the repository contradicted them - the dependencies are
to be vendored (S0003) and every function names its engine floor (S0002). Stamp `canon.version`, `coreDigest` and
`reconciledOn` moved together; `adoptedOn` unchanged. Gate on the repository itself: 0 errors, 0 warnings.

## Product scope 2026-10-16 (S0002)

The feature matrix (`docs/FEATURE_MATRIX.md`, 150 rows, sources dated 2026-10-16) and the owner's answers of the same
day: the first release holds the exchange account, devices, directory, clipboard and diagnosis, operator
administration, local browsing, player, images and slideshow, and the move to destination folder N (Chromium only,
disabled with the reason elsewhere); the floor is the current and the previous major version of each browser, "IE"
read as Microsoft Edge; the local and the exchange tracks run in parallel. Four more pending registry rows
(`MEDIA-CLASSIFICATION`, `INPUT-PARITY`, `ICON-SET`, `ICON-RENDER`). `check-contracts.ps1` exit 1 with three errors that
predate this product (FastMediaSorter_Lite's expired exception, the `broadcast-resource` header, the `clipboard-guard`
version). No proposal filed yet; the parity proposals go through ticket S0010.

## In-app help (2026-10-16)

- Ticket `PLAN/S0031_in-app-help-f1-and-button.md` (Draft), created by the canon session from the owner's request for F1 and a `?` button in every product ([UI_UX](../../UI_UX.md) §7, contract `CONTEXT-HELP` 0.1). The surface list comes from the view registry that S0028 must expose. Found on the way: `capture-draft -DedupQuery` threw on an empty search result (an `if` expression yielding `@()` unrolls to `$null` under StrictMode) - fixed in the canon harness the same day.

## Canon delivery reconciliation 2026-10-17 (S4307)

- Installed plugin `2026.1017.1` from published canon `2026.10.17.1` (`d06a64a`). The harness counts Done and Skipped as finished and preserves the phase-counter suffix.
- Re-read the changed canon guidance for delivery, documentation, localization, layout and sealed contracts. Existing product implementation and contract catch-up work remains owned by the recorded project tickets; this delivery check does not certify every product contract.
- Re-stamped through `restamp-canon.ps1` against the installed plugin reader: version, freshly computed core digest and reconciledOn move together; adoptedOn and project-specific fields stay unchanged.
- Compliance for FastMediaSorter_WEB: 0 error(s), 1 warning(s) before; 0 error(s), 0 warning(s) after; exit 0. Canon freshness findings cleared.
- Exchange server mark (2026-10-19): ticket `PLAN/S0036_exchange-mark-in-product-and-docs.md` (Draft, not queued - it sits in the `--` bucket), created by the canon session from the owner's order for one exchange server mark in every product (contract `EXCHANGE-MARK` 0.1): 26 inventory rows, five files to vendor under `web/vendor/exchange-mark/`, and a finding that this client is served at the exchange server's own address, so every page of it takes the contract's favicon (rule 13). Found on the way: the server answers `.ico` from the host's MIME database (no `.ico` case in its fallback), rules 10 and 11 overlap for a help page about a sign-in surface, and `Find-ExchangeMark.ps1` fails any file named like the mark whose bytes match nothing, which binds the help screenshot names of S0031.

## Test lab report (2026-10-23)

- Ticket `PLAN/S0038_test-lab-report.md` (Draft; `capture-draft` placed it at the end of package 1), created by the canon session from the owner's order of 2026-10-23 to collect what every project knows about its hardware, emulators and test practice (contract `TEST-LAB` 0.1, draft). Documentation only: the product files one inventory report and a pointer; no code, test or harness changes. Reports to the web profile owner (the hub).

## Fast checks between releases (2026-10-29)

- Ticket `PLAN/S0047_fast-checks-between-releases.md` (Approved, first in `PLAN/RELEASE_QUEUE.md` package 1), created by the canon session from the owner's order of 2026-10-29 to switch off full builds and tests longer than 5 s between releases (canon TESTING_AND_QA section 2, highest priority). The product classes `tests/smoke.ps1` and the harness checks as fast or release, makes the fast set one command, writes a release command in `CLAUDE.md` for the browser run and the document and contract gates, and rewords the runner prompt and the rule files to the fast tier; there is no branch CI to change.

## Canon adoption 26-11-08 18:24

Re-sync (ticket `PLAN/S0042_canon-resync-2026-10-21.md`) from canon **2026.10.17.1** to **2026.11.07.1**, core digest `sha256:9abe1d23..`, reference model, overlay **E**. The whole rule delta between `d06a64a` and `73dbbe4` was read; section 5 of the ticket gives each change and its result.

- **What changed in the repo:** `README.md` rewritten as present-tense facts from the owner's order, the bootstrap status line and the links into origin and planning records gone; launchers `r1`-`r3`, `rs`, `rm`, `rw` scaffolded, with a lock path rule; `CLAUDE.md` (runners, measured list, its own ticket tags removed, item CX program name); rule lines for a user's time zone and for the served root; stale statements about the `*.kt` probe gates and the retired Windows program name corrected; contract inventory at `TASK-FLOW` 0.13 and an id line in every generated pointer; stamp `schemaVersion` `1.0`, with version, digest and `reconciledOn` moved together and `adoptedOn` kept.
- **Catalog:** this product's tooling rows re-verified (`REPO-STAMP` 0.13, `HARNESS-PROFILE` 0.14, `REPO-LAYOUT` 0.11, `RULE-DELIVERY` 0.12), `TASK-FLOW` kept `pending` at 0.13, rows added for `APP-SETTINGS`, `APP-STYLE`, `APP-BEHAVIOUR`, `DOC-INTERNAL-QUALITY` and `TEST-LAB`, section 4 entry updated. No contract edited, no proposal filed; `contract-lag.ps1` reads the rows with 0 unparsed. `INSTALL-TRUST` does not apply: a page served by a browser ships no installer.
- **Divergences recorded:** none new. `PLAN/` stays tracked; what a first public history holds is ticket S0044's.
- **Remains, each with its carrier:** no application code exists (`web/` absent), so every product contract stays debt and not conformance; the unified UI plan's milestone M1 (2026-10-26) passed undelivered behind the owner's shell ruling on S0028, and the registry entry's `until` stays 2026-11-30 (S0032); S0033 waits on its consumer evidence; the attended R0 rehearsal stays deferred by the owner, while the portfolio dispatcher works the repository.
- **Gate:** `check-compliance.ps1` 0 errors, 3 warnings before (`SZA-CANON03`, two `SZA-CTR01`); 0 errors, 0 warnings after, exit 0.
- **Canon fixes for a canon session:** (1) no re-stamp writer ships: `REPO-STAMP` rule 8 says the adoption run writes the stamp, adopt-canon step 7 names no tool, and `restamp-canon.ps1`, cited in the 2026-10-17 section above, exists in neither the plugin nor the checkout, so this run wrote the three keys with an editor after recomputing the digest; (2) `REGISTRY` section 2 lets `Implements` and `Reads` both say `partial <version>`, but `contract-lag.ps1` reads `partial` only from `Implements` and reports it in `Reads` as `unparsed`.

## Canon adoption 26-11-12 21:58

Re-sync (ticket `PLAN/S0052_compliance-gate-reds-s0048-canon-digest.md`) from canon **2026.11.07.1** to **2026.11.12.9**, core digest `sha256:af1470e6..`, reference model, overlay **E**. The whole rule delta between `73dbbe4` and the 2026-11-12 checkout was read: six docs, `AI_USAGE`, `CHANNEL_MATRIX`, `DEVELOPMENT`, `DOCUMENTATION_CONCEPT`, `LOCALIZATION` and `TESTING_AND_QA`; `CONTRACTS` did not change, so no `contract-sync` run.

- **Delta read against this repository:** the unattended-pass rules (assume the reversible answer, `DO:` owner actions, `Blocker: <key>:<id>` and `BlockByOtherTask`) are already how this repository's passes run and need no `CLAUDE.md` text; the declared compile-only check (`TESTING_AND_QA` section 2) has no key here, `commands.compileCheck` stays absent on purpose because the stack has no build step, and an unattended note says "no compile command"; the Store machine channel and the `og:locale` map bind a channel and a site this repository does not have yet (`channels` empty, `site.kind` none), so the map is read for the serving ticket, not applied.
- **What changed in the repo:** the stamp's `version`, `coreDigest` and `reconciledOn` moved together (`adoptedOn` kept); `.gitignore` gained a narrow negation with a why-comment for the one committed binary, the sample diagnostic report of the S0048 evidence (`SZA-SEC03`); the private-key redaction fixture in `tests/diagnostic.js` assembles its armor header at run time instead of carrying a whole header in the source (`SZA-SEC04`) - input and result proved byte-identical to the former literal through the real `redactText`.
- **Finding:** `SZA-SEC04` matched the PEM private-key armor fixture of the redaction test, not the `Password=` connection-string fixture the ticket guessed (the gate knows six fixed prefixes and a password is none of them). No stamp exemption was written, because an exemption would silence the gate for every later line of that file.
- **Divergences recorded:** none new.
- **Gate:** `check-compliance.ps1` 2 errors and 1 warning before (`SZA-SEC03`, `SZA-SEC04`, `SZA-CANON03`); 0 errors, 0 warnings after, exit 0.
- **Canon fixes for a canon session:** the `SZA-SEC04` fix line ("Rotate the credential, then untrack it") has no branch for a deliberate redaction or detection fixture; the owner of a secret-scanner test either splits the literal or exempts the whole file. A line in the fix text naming the split would spare the next repository the same reading.

## Promotion ticket 26-11-17 (S0061)

Campaign recorded and staged before the first release. The positioning worksheet is internal to the ticket folder (`docs/POSITIONING.md` stays the single published source). The generated site gained, through `tools/build-site.py`, its share image (`og:image` 1200x630), `twitter:card` and one truthful JSON-LD block per page (`WebApplication` on the three landings, `WebPage` `isPartOf` on the nine child pages), a 12-URL sitemap with commit-date `lastmod`, an allow-all robots copy with the product sitemap line, and an IndexNow key file; the generator first learned the S0037 three-components copy so a regeneration reproduces the committed pages byte-for-byte (drift measured, attributed, closed). Gate: `check-compliance.ps1` 0 errors, 14 promotion warnings closed to 1 foreign warning (`SZA-CANON03` adoption staleness, canon 2026.11.17.2 moving in flight). Outward steps (commit/push, Search Console, Bing, IndexNow ping, listings, launch moments) wait behind the owner `DO:` items and the release gate; the host-root sitemap line is drafted as `hub:S0019`. Parked: `S0065` (eight orphan probe lines of archived tickets in `web/`).
- **P7 update 2026-11-18:** 17-file site change set committed and pushed (`870be8e` on `main`); GitHub Pages `built`, live `/`, `/sitemap.xml`, `/robots.txt`, `/16d3f1802255040a0a2c2f62464b4666bd4a796f.txt`, and `/assets/og-image.png` all return HTTP 200; IndexNow 12-URL submission returned HTTP 202 Accepted. Remaining in P7: Search Console sitemap submission in the owner's signed-in host-root property (`DO:`), Bing Webmaster Tools import, and `hub:S0019`.

## Record split 2026-11-18 (canon ticket S0120)

Every section of this file dated before this one was moved here verbatim from [../fastmediasorter_web.md](../fastmediasorter_web.md) when the record was split into facts and history. A line number quoted inside such a section counts lines of the record as it was before the move; relative links were deepened by one `../`; nothing else changed.

## Recommendation decisions 2026-11-23 (CANONR-0172)

The compliance gate supports repositories before their first commit and explains how to draft a new overlay. Overlay E and the scaffolded forwarder are part of the canon.

### Candidate core edits (PROPOSED - apply only on owner instruction)

- **adopt-canon step 1 / step 8 - the gate on a repository with no commit:** `check-compliance.ps1` judges only
  tracked files (`git ls-files`), so on a brand-new repository with an empty index it reports SZA-RULES01 "no
  agent-instructions file" while `CLAUDE.md` is on disk, and skips every RULES check. Adoption runs before the first
  commit by design (the handoff forbids committing). This run verified on a scratch copy with a staged index (`git
  init` and `git add -A` in the session scratchpad, `-RepoRoot` pointed there). A `-IncludeUntracked` switch, or the
  step saying "stage into a scratch copy", would save every new repository the detour. Evidence: the baseline run on
  the repository gave 3 errors (CANON01, LAY01, RULES01) with `CLAUDE.md` present; the staged copy gave 0.
- **SZA-CANON04 fix text:** "Declare one of A B C D" is the only overlay guidance a new repository sees. When none
  fits, NEW_PROJECT_CHECKLIST step 0 says "draft a new overlay", but the gate's text does not, and nothing says where a
  draft lives until the canon adopts it (this run: the contrib record plus a stamp `$comment`).
- **Harness forwarder in `templates/`** - unchanged from `tourist_mob.md`: this repository copied `tools/harness.ps1`
  from Tourist, the third adopter to do so.

### Candidate NEW docs (not in any shared doc yet)

- **PLATFORM_OVERLAYS "Overlay E - browser application (static files, no install)"**, drafted from this repository;
  the canon session decides its letter and wording.
  - **Source root and release mechanics.** A static file set under one source root (`web/` or `src/`), vendored
    dependencies, an optional build step; served as files. No `publishing/` umbrella: the serving shapes below are the
    release mechanics, each a folder or a script beside the source.
  - **Version shape.** Derived mechanically and frozen for the product's life (invariant 8): the desktop date tag
    `YY.MMDD.HHmm` fits, stamped into the files at build or at packaging. The page shows it in its About view and in
    every diagnostic report. A Service Worker that caches the page compares the version of the page it holds with a
    small version file fetched with `cache: no-store` on each start (or reacts to its own `updatefound`), and tells the
    person that a new version is ready; it never swaps the page under a running session. "Update a real prior install"
    (invariant 6) becomes: a cached prior page and its stored state (IndexedDB, the Service Worker cache, the
    non-extractable keys) survive the new version.
  - **Distribution channels.** Each free: (1) a free static host (GitHub Pages, or any host the owner already has);
    (2) the copy served by another product's server, when that product carries the files (for FMS_Web, the exchange
    server - a server change, proposed through the catalog); (3) PWA install from either, through the web app
    manifest. No store channel; discoverability is the product page, if any.
  - **Frozen anchors.** The **origin** - scheme, host and port. IndexedDB, the non-extractable device key, granted
    permissions, the Service Worker and the PWA install all hang on it, so moving the page to another origin turns
    every browser into a new device of its account and orphans every install: the web analogue of a changed
    `applicationId`. With it: the web app manifest `id` (the install's identity; when absent it falls back to
    `start_url`, so set it explicitly at first publish) and the Service Worker scope and `start_url` path. The visible
    name rides on top and may change.
  - **Web equivalents of invariants 13 and 14.** Request a browser permission (camera, microphone, clipboard read,
    notifications, persistent storage, a folder handle) only at the moment the function that needs it is used, each
    with a one-sentence justification on screen; never at load. Keep the privacy page and the list of permissions the
    page can request saying the same thing; claim "no telemetry" only if the page sends nothing to any address but the
    one the person chose (no analytics, no font or script CDN that logs visitors).
  - **Traps.** No raw sockets; TLS and certificate trust belong to the browser, so a self-signed server needs a trust
    story (FMS_Web S0006); support differs per engine (File System Access write-back, BarcodeDetector, streamed upload
    are Chromium-only) and nearly every iOS browser is WebKit; clearing site data or storage eviction erases the
    device; an `https:` page cannot load `http:` LAN resources (mixed content).
