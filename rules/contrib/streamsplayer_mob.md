---
# Contribution: streamsplayer_mob (overlay B, flavor shape, three packages, LIVE-BROADCAST producer) -> Unified_Rules
Source repo: P:\ANDROID\StreamsPlayer_mob | Date: 2026-10-02, refreshed 2026-11-13 (S0059)
Read: NEW_PROJECT_CHECKLIST, PLATFORM_OVERLAYS, REPOSITORY_LAYOUT, CONTRACTS, INVARIANTS, RELEASE_AND_DISTRIBUTION section 8, AI_USAGE (sections), harness README and spec_catalog SCHEMA; on 2026-11-13 also CHANNEL_MATRIX, SITE_CONFIGURATION, the store-publish skill's Google Play reference, the repository's own stamp, profile, `.git/config`, `.github/workflows/pages.yml` and its `docs/play/` file names, the public GitHub API and the Pages URLs, and the deviceinfo record (S0057) as the model; deduped against: contrib/fastmediasorter_mob_v2.md, contrib/streams_player.md
---

StreamsPlayer for Android: phone app, Wear OS app and watch face for internet radio, live video and RTSP, plus
live broadcast from phone and watch. An independent product extracted from FastMediaSorter Android
(`fastmediasorter_mob_v2.md`) under its ticket S4053 of that repository; the Android sibling of StreamsPlayer for
Windows (`streams_player.md`), with which it shares contracts only. Born on 2026-10-02 as a new repo adopting the
canon from commit one, so most overlay-B material is CONFIRM of the FastMediaSorter record. Genuinely new: a
product whose no-drift guarantee against its extraction source is a port ledger with a SHA-256 drift check rather
than shared code, and the first adopter of the shipped harness that never had a local copy of it.

Public presence since 2026-11-13 (section "Public presence 2026-11-13"): a public GitHub repository, a GitHub Pages
privacy site and two Google Play Console apps, all created on the owner's order; nothing is published on Google Play yet.

## Overlay facts (verified against this repo, 2026-10-02; refreshed 2026-11-13)

- **Source root & release-mechanics.** Gradle modules `phone`, `wear` and `watchface` (the stamp's `modules.names`);
  the directory `exchange-core` is named in the profile's probe roots as well (directory listing, 2026-11-13). Specs in
  `PLAN/Sxxxx_<slug>.md`, the harness run from the plugin through `tools/harness.ps1` (evidence: `.sza-profile.json`,
  `tools/harness.ps1`).
- **Version shape.** PACKAGE-VERSIONING Android profile, tag regex `^v\d+\.\d+\.\d+\.\d+$` (the stamp's
  `versionShape.tagRegex`, set after 2026-10-02); no release tag is named in the 2026-11-13 report.
- **Channels + listing files.** `channels: ["play"]` (the stamp; owner decision B39 of 2026-10-14, S0010, declared with
  S0033 on 2026-10-25). The 2026-10-02 reading "GitHub/sideload per owner decision 4.3" is superseded: the stamp's comment
  adds a sideload channel the day one opens, and none is declared. Listing source: `docs/play/PLAY_LISTING.md`,
  `PLAY_LISTING-ru.md`, `PLAY_LISTING-uk.md` and `PLAY_DATA_SAFETY.md`; the 512 icon and the 1024x500 feature graphic
  sit in `docs/play/` beside them.
- **Frozen anchors (owner, 2026-10-02; bound 2026-11-13).** `com.sza.streamsplayer` shared by phone and watch (Data Layer
  needs one id and one key) and by the noLegal variant (sanctioned exception, never co-published to one store);
  `com.sza.streamsplayer.watchface`. Both ids are now bound to Play Console apps (created 2026-11-13; the create-app form
  takes the package name, so the id is frozen from that day - see PLATFORM_OVERLAYS overlay B). Signing key at
  `P:\ANDROID\StreamsPlayer_credentials`; Play App Signing with the product's own key imported as the app signing key plus
  a separate upload key, so store and sideload builds carry one signature. The 2026-11-13 report does not say whether the
  upload key exists or the signing key has been imported; this record does not claim either.
- **Editions + parity mechanism.** None - single edition. Shape: flavor (store, noLegal); wear and watchface are
  sibling modules. Coupling to FastMediaSorter: contracts plus a port ledger and drift check (handoff section 6a).

## Channel-matrix rows (this project)

Format: Channel | Trigger | Cost | Auth | Signer | Listing source | Frozen anchor | Verify live

- **Google Play (Android), app "StreamsPlayer: Internet Radio", phone and Wear OS in one listing** | AAB upload to a track:
  the phone bundle, then the Wear OS bundle to the same app; no upload is named in the 2026-11-13 report | [PUBLIC] | Play Console, personal
  developer account, owner's login; the review account's sign-in details are the owner's to type | Play App Signing; the
  upload key and the signing-key import are not confirmed by the 2026-11-13 report | `docs/play/PLAY_LISTING*.md` (en-US,
  ru-RU, uk) + `docs/play/PLAY_DATA_SAFETY.md`; graphics `docs/play/icon-512.png` and `docs/play/feature-graphic-1024x500.png`
  | `com.sza.streamsplayer` (bound 2026-11-13) | track shows the build, staged rollout, update over a prior install on a
  phone and on a watch - **not run**, nothing is published. (evidence: owner's report of 2026-11-13, S0059 section 0;
  `docs/play/` listing)
- **Google Play (Android), app "StreamsPlayer Watch Face"** | AAB upload to a track; no upload is named in the 2026-11-13 report;
  listing empty by owner decision until its source exists | [PUBLIC] | same console account | same open items as above | none
  yet - no listing source | `com.sza.streamsplayer.watchface` (bound 2026-11-13) | track shows the build - **not run**.

The generic Google Play row of CHANNEL_MATRIX is unchanged: a project's own rows live in its record (`TEMPLATE.md`), and the
generic row already says a secondary form-factor artifact has its own store guidelines.

## Public presence 2026-11-13

Recorded as the owner's session reported it; what the canon session measured itself is marked as such.

- **GitHub.** Public remote `https://github.com/SerZhyAle/StreamsPlayer_Android`, branch `main`, created 2026-11-13. GitHub
  detects the license as MIT (the repository's `LICENSE`); the description is the product's one-line statement from
  POSITIONING section 1; 13 topics; no homepage yet (it waits for the landing, below); wiki and projects off, issues on.
  Commits on `main`: `fb96544` (foundation, canon adoption, contracts, ticket store), `b8cee28` (provenance of the bootstrap
  handoff), `7b6ce41` ("Import the product tree for the first public push"). (evidence, measured by the canon session
  2026-11-13: GitHub API for the repository, `.git/config` remote, `git log`)
- **Publication scan (before the first push, owner's report).** No signing material and no token or key pattern in the tree;
  one private address (an owner quote in S0014) was redacted. The `.gitignore` secret globs `*token*` and `*secret*` were
  hiding product source (`RoomSecretStore.kt`, `UiSizeTokens.kt` and its test) and the self-signed test identity of
  `BroadcastTunnelTlsTest`; the globs stay at `.gitignore` lines 31-32, and the comment at lines 39-41 and the negations at
  lines 42-43 undo them for the product source and the test identity, so a fresh clone has them.
  The three runbook lessons this run found are parked as S0060 against S0058, not written into the canon rules here.
- **`PLAN/` is public with the remote.** `git ls-files PLAN` returns 192 files on 2026-11-13, including `PLAN/DONE/` and its
  attachments; the 2026-10-02 reason for tracking it ("there is no remote") no longer holds. Open question below.
- **Site.** `https://serzhyale.github.io/StreamsPlayer_Android/`, served by GitHub Pages with the workflow build type through
  `.github/workflows/pages.yml`: a check job on `windows-latest` that first runs `git config --global core.autocrlf false`
  (the fix for the CRLF render-target problem in SITE_CONFIGURATION section 4), then `tools/site/build-site.ps1 -Check`; then
  the deploy job. The owner's report gives the first run as 43438392545, green. Measured by the canon session 2026-11-13:
  `privacy.html`, `privacy-ru.html`, `privacy-uk.html`, `sitemap.xml` and `robots.txt` answer 200; the site root answers
  **404**, because the product landing does not exist yet (the product's ticket S0045), so the repository has no homepage and
  the Play listing no website. The owner's report adds that both CSS files and every external link on the pages answer 200
  (not re-measured here).
- **Help.** The in-app help is not hosted yet; it is published with the first release (the product's S0048, decision D2,
  owner's report). The shared media exchange portal answers 200, including the account-deletion page that the Data safety
  form links (owner's report, not re-measured).
- **Google Play Console** (personal developer account, the one that holds DeviceInfo). App "StreamsPlayer: Internet Radio",
  package `com.sza.streamsplayer`, App, Free, en-US; Developer Program Policies and US export laws accepted on the owner's
  explicit yes. App content saved: privacy policy `https://serzhyale.github.io/StreamsPlayer_Android/privacy.html`; ads none;
  advertising ID not used; government app no; financial features none; health features none. Content rating from a fresh
  IARC questionnaire (terms accepted on the owner's yes): users exchange audio and video live, limited to invited listeners;
  third-party online content that can contain violence, sexual content without pornography, offensive language and drug
  references (the catalog's "Adult" rubric, 37 audio stations). Results: ESRB Teen (Diverse Content: Discretion Advised),
  PEGI Parental guidance, USK 16, ClassInd 16, IARC generic 12+. Data safety saved as a draft (it submits after the target
  audience): directory data collected, not shared, optional; App functionality with User IDs, Files and docs, and Device or
  other IDs; encrypted in transit; no account creation in the app (accounts come from the exchange server); deletion link =
  the portal's account-deletion page. Store settings: category Music & Audio, contact `sza@ukr.net`, no website until the
  landing answers. Listing filled in en-US, ru-RU and uk (title, short and full description, 512 icon, 1024x500 feature
  graphic). Form factors: Wear OS added; Android XR left active by Google's default.
- **Waiting for the owner** (owner's report): the review account's sign-in details (instructions written; the login, password
  and server address are typed by the owner), then the target audience (18 and over, an owner decision, not yet saved), then
  the Data safety submit.
- **Google Play Console, second app "StreamsPlayer Watch Face"**, package `com.sza.streamsplayer.watchface` (bound to the account
  on 2026-11-13), App, Free. Every App content item complete ("You're all caught up"): no restricted access, no ads, no data
  collected, IARC all No (Everyone, PEGI 3), target audience 13 and over. Category Personalization, contact `sza@ukr.net`, Wear
  OS form factor. Listing empty until its source exists (owner decision).
- **Not published.** Nothing is published on Google Play (owner's report). The report names no bundle upload, no review
  submission and no release; the open steps it does name are the review sign-in details, the target audience and the Data
  safety submit, above. Nothing here claims an upload.
- **Referring to the product.** The owner wants the other projects, `sza.od.ua` included, to refer to it once it is published.
  That waits for the publication and for the landing (S0045); the canon files nothing in another repository for it.

## Canon state of this repository, 2026-11-13

The stamp declares canon `2026.10.17.1` with core digest `sha256:b467aefe..` (reconciled 2026-10-17, read from
`.sza-canon.json`); the canon at the time of this refresh is `2026.11.13.2`, so the stamp is behind it. The re-sync is that
repository's own adopt-canon run. This record does not write a stamp it does not own, and it did not run `check-compliance`
from that repository.

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
  place only, and the tickets carry the owner's recorded decisions. Since 2026-11-13 the remote is public, so the tickets
  are public with it (192 files under `git ls-files PLAN`); the 2026-10-02 reason no longer holds, and whether to keep it
  so is an open question below.

## No delta

REPOSITORY_LAYOUT (Android spec home), INVARIANTS, NEW_PROJECT_CHECKLIST.

## Candidate core edits (PROPOSED - apply only on owner instruction)

- **Harness `close` deletes the spec header's `**Status note:**` line (`tools/harness/spec_catalog/_lib.ps1`,
  `Sync-SpecHeaderStatus`, plugin 2026.1002.3; found by the StreamsPlayer Android session 2026-10-10):**
  the parameter is `[string] $StatusNote = $null`, and an omitted `[string]` parameter binds as `''`
  (the type coerces the absent value; measured in pwsh 7.5 - `$null -eq $StatusNote` is `False` even with
  the default removed), so the caller that omits it - `close.ps1`, `archive.ps1`, `bulk-update.ps1` -
  reaches the `elseif ($StatusNote -eq '')` "Clear note line" branch, never the documented
  "$null - preserve" branch. Every `spec_catalog/close` therefore rewrites the header block as the
  status line alone. Observed twice on 2026-10-10: S0001 and S0002 closed to Verified and both spec
  headers lost their note line (the journal note survives - the journal is the source of truth, but the
  header is the half the owner reads at a glance). The function's own comment on the adjacent `[ref]`
  parameter documents exactly this coercion class. Proposed exact diff:

  ```diff
  -        if ($null -ne $StatusNote -and $StatusNote -ne '') {
  +        if ($PSBoundParameters.ContainsKey('StatusNote') -and $StatusNote -ne '') {
               # Upsert note
               $newBlock = $newStatusLine + $lineEnd + '**Status note:** ' + $StatusNote + $lineEnd
  -        } elseif ($StatusNote -eq '') {
  +        } elseif ($PSBoundParameters.ContainsKey('StatusNote') -and $StatusNote -eq '') {
               # Clear note line
               $newBlock = $newStatusLine + $lineEnd
           } else {
  ```

  (`$PSBoundParameters.ContainsKey` is how `update.ps1` already distinguishes omitted from explicit
  empty - `NoteSupplied` - so the fix reuses the corpus's own idiom. The `= $null` default on the
  parameter declaration should also go: it is the same trap the `[ref]` comment warns about.)
- **Harness ticket-id grammar (tools/harness):** `grammar.ticketIdPattern` is a profile key, but `New-CatalogId`
  (`spec_catalog/_lib.ps1`) and `insert.ps1 -Id` hard-code `^S\d{4}$` (canon session count: 57 occurrences in
  42 files). A profile with another scheme validates ids that allocation can never issue. Confirmed by the canon
  session 2026-10-02, not scheduled; this repo keeps the default.
- **adopt-canon step 1:** the session that started before a plugin update keeps the old skill listing; this run
  had to read the 2026.1002.2 skill, template and gate from the new install path by hand.

## Candidate NEW docs (not in any shared doc yet)

- None required.

## Open questions for the owner

Open as of 2026-11-13 (the owner's call each; none blocks the canon):

- **Public `PLAN/`.** The tickets are on GitHub with the remote (192 files). Keep them public, or ignore `PLAN/` as the
  FastMediaSorter store is ignored; nothing in this record changes it. (The publication scan redacted one address in S0014.)
- **Play variant.** Whether the Play app `com.sza.streamsplayer` carries the store variant only or also the noLegal one is not
  in the 2026-11-13 report; the 2026-10-02 reading (noLegal never co-published to one store) stands until the owner says
  otherwise.
- **Watch-face listing.** Empty until the watch-face source exists (owner decision); the app is complete in App content but
  has no listing text.
- **Landing (the product's S0045).** The repository homepage and the Play website field wait for it; they stay empty until
  the landing answers 200.
- **Upload key and signing-key import.** Not in the 2026-11-13 report; the owner's step.
- **Pending Play steps.** Sign-in details for the review account, the target audience (18 and over), then the Data safety
  submit.

Settled or superseded since 2026-10-02: 4.3 distribution (play first, per the stamp's comment; a sideload channel is added
when it opens), 4.4 watch-face composition (the second app exists), 4.5 GitHub remote (created 2026-11-13), 4.7 site (Pages
is live; the landing is S0045).

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

## In-app help (2026-10-16)

- Ticket `PLAN/S0035_in-app-help-f1-and-help-button.md` (Draft, priority 40), created by the canon session from the owner's request for F1 and a `?` button in every product ([UI_UX](../UI_UX.md) §7, contract `CONTEXT-HELP` 0.1). About 20 phone surfaces and 7 Wear routes; `SupportDestination.HELP` still opens the FastMediaSorter docs; no site yet (decision 4.7). Eight owner questions are in the ticket.

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
