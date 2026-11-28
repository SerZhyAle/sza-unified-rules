---
# Contribution: streamsplayer_mob (overlay B, flavor shape, three packages, LIVE-BROADCAST producer) -> Unified_Rules
Source repo: P:\ANDROID\StreamsPlayer_mob | Date: 2026-10-02, refreshed 2026-11-13 (S0059), re-synced 2026-11-27 (STRMOB-0230)
Read: AI_USAGE, CONTRACTS, GITHUB_INTERACTION, REPOSITORY_LAYOUT, SUPPORT_AND_FEEDBACK, UI_UX (delta re-sync against canon 2026.11.27.6; prior delta 2026-11-26 against 2026.11.26.9 and full 20-doc re-sync 2026-11-20 against 2026.11.20.4); harness README and spec_catalog SCHEMA; the store-publish skill's Google Play reference; the repository's own stamp, profile, `.git/config`, `.github/workflows/pages.yml`, `docs/play/`, `docs/releases/` and `docs/contracts/`; deduped against: contrib/fastmediasorter_mob_v2.md, contrib/streams_player.md
---

> **Owner decision, 2026-11-16:** `PLAN/` and its archive are local and ignored (`CLAUDE.md` section 4 item 6, `.gitignore` `/PLAN/`, `git ls-files PLAN` is 0). Earlier statements below that the workspace was tracked or public describe the former 2026-11-13 snapshot.

StreamsPlayer for Android: phone app, Wear OS app and watch face for internet radio, live video and RTSP, plus
live broadcast from phone and watch. An independent product extracted from FastMediaSorter Android
(`fastmediasorter_mob_v2.md`) under its ticket S4053 of that repository; the Android sibling of StreamsPlayer for
Windows (`streams_player.md`), with which it shares contracts only. Born on 2026-10-02 as a new repo adopting the
canon from commit one, so most overlay-B material is CONFIRM of the FastMediaSorter record. Genuinely new: a
product whose no-drift guarantee against its extraction source is a port ledger with a SHA-256 drift check rather
than shared code, and the first adopter of the shipped harness that never had a local copy of it.

Public presence since 2026-11-13 (section "Public presence 2026-11-13"): a public GitHub repository, a GitHub Pages
privacy site and two Google Play Console apps, all created on the owner's order; `com.sza.streamsplayer.watchface` (`2.61.1210.302`) published 2026-11-27, while `com.sza.streamsplayer` awaits pre-flight blockers (`STRMOB-0230`) and publication (`STRMOB-0047`, `STRMOB-0222`).

> **Keep this note in the record.** Current facts, edited in place. Never append a dated section to this file,
> and append nothing under `history/` either: those files are frozen ([the rules of that folder](history/README.md))
> and are not reading for a task. A delta the core absorbed, a candidate that was applied or refused and a
> question that was answered are deleted here.

## Overlay facts (verified against this repo, 2026-10-02; refreshed 2026-11-13 and 2026-11-20)

- **Source root & release-mechanics.** Gradle modules `phone`, `wear` and `watchface` (the profile's `modules.names`);
  the JVM library `exchange-core` is named in the profile's probe roots as well (`settings.gradle.kts`, `.sza-profile.json`). Specs in
  `PLAN/STRMOB-NNNN_<slug>.md` (own ticket prefix STRMOB since 2026-11-19, repository ticket S0164; a ticket closed
  before it keeps `S####_<slug>.md`, `grammar.legacyTicketIdPatterns`), the harness run from the plugin through
  `tools/harness.ps1`, the day-0 launchers `r0.ps1`, `r1.ps1`-`r3.ps1`, `rs.ps1`, `rm.ps1`, `rw.ps1` at the root and the
  eight spec-command forwarders in `.claude/commands/` (`a.ps1` builds packages and records builds in `docs/releases/`).
- **Version shape.** PACKAGE-VERSIONING Android profile, tag regex `^v\d+\.\d+\.\d+\.\d+$` (the stamp's
  `versionShape.tagRegex`, set after 2026-10-02); no release tag has been cut yet.
- **Channels + listing files.** `channels: ["play"]` (the stamp; owner decision B39 of 2026-10-14, S0010, declared with
  S0033 on 2026-10-25). The 2026-10-02 reading "GitHub/sideload per owner decision 4.3" is superseded: the stamp's comment
  adds a sideload channel the day one opens, and none is declared. Listing source: `docs/play/PLAY_LISTING.md`,
  `PLAY_LISTING-ru.md`, `PLAY_LISTING-uk.md`, `PLAY_LISTING_WATCHFACE.md`, `PLAY_LISTING_WATCHFACE-ru.md`,
  `PLAY_LISTING_WATCHFACE-uk.md`, `PLAY_DATA_SAFETY.md`, `PLAY_REACH.md` and `PLAY_RELEASE_RECORD.md`; the 512 icon and
  the 1024x500 feature graphic sit in `docs/play/` beside them (rendered from `docs/brand/streamsplayer-icon.png` by
  `tools/store/render-store-assets.ps1`). Release ledger: `docs/releases/` (`channels.json` declaring 6 Play tracks across
  `phone`, `wear` and `watchface`, `builds.json`, `RELEASES.md`; S0154).
- **Frozen anchors (owner, 2026-10-02; bound 2026-11-13; keys imported 2026-11-17).** `com.sza.streamsplayer` shared by phone and watch (Data Layer
  needs one id and one key) and by the noLegal variant (sanctioned exception, never co-published to one store);
  `com.sza.streamsplayer.watchface`. Both ids are bound to Play Console apps (created 2026-11-13: `4972961129584993008` and
  `4976077107533670611`). Signing keys live at `P:\ANDROID\StreamsPlayer_credentials`; Play App Signing with the product's
  own key (`61:CF:02:09:..:F4:97`) imported into both console apps on 2026-11-17 via `pepk`, plus a separate upload key
  (`A8:68:0E:EA:..:FB:D0`, reset requested 2026-11-17, valid 2026-11-19 16:20/16:21; `docs/play/PLAY_RELEASE_RECORD.md`
  section 1), so store and sideload builds carry one app-signing signature.
- **Editions + parity mechanism.** None - single edition. Shape: flavor (store, noLegal); wear and watchface are
  sibling modules. Coupling to FastMediaSorter: shared contracts plus the port ledger (`docs/port-ledger.jsonl`), outbound
  ledger (`docs/port-outbound.jsonl`), scope manifest (`docs/port-scope.jsonl`) and feature parity manifest
  (`docs/feature-parity.jsonl`) gated by `tools/port-ledger/assert-port-drift.ps1` and `tools/family/assert-family-sync.ps1`.

## Channel-matrix rows (this project)

Format: Channel | Trigger | Cost | Auth | Signer | Listing source | Frozen anchor | Verify live

- **Google Play (Android), app "StreamsPlayer: Internet Radio", phone and Wear OS in one listing** | signed AAB to a track through the Play Developer API:
  the phone bundle, then the Wear OS bundle to the same app; nothing published yet (`STRMOB-0047`, `STRMOB-0072`) | [PUBLIC] | Play Console, personal
  developer account `8446656778368889827`, owner's login (`SZA_PLAY_SERVICE_ACCOUNT_JSON` for API/probe); the review account's sign-in details are the owner's to type | Play App Signing with
  imported app signing key `61:CF:..:F4:97` and separate upload key `A8:68:..:FB:D0` (valid 2026-11-19) | `docs/play/PLAY_LISTING*.md` (en-US,
  ru-RU, uk) + `docs/play/PLAY_DATA_SAFETY.md` + `docs/play/PLAY_RELEASE_RECORD.md`; graphics `docs/play/icon-512.png` and `docs/play/feature-graphic-1024x500.png`
  | `com.sza.streamsplayer` (bound 2026-11-13, app `4972961129584993008`) | track read-back, review and public serving (`probe` prints readings only; `live` confirmed by hand); update over a prior install on a
  phone and on a watch - **not run**, nothing is live. (evidence: `docs/play/PLAY_RELEASE_RECORD.md`, `docs/play/PLAY_DATA_SAFETY.md`)
- **Google Play (Android), app "StreamsPlayer Watch Face"** | signed AAB to a track through the Play Developer API; `2.61.1210.302` (versionCode `261121030`) published 2026-11-27 (`Submission ID 1`) | [PUBLIC] | same console account `8446656778368889827` | same app signing key `61:CF:..:F4:97` and upload key `A8:68:..:FB:D0` | `docs/play/PLAY_LISTING_WATCHFACE*.md` (en-US, ru-RU, uk) + `docs/play/PLAY_RELEASE_RECORD.md` | `com.sza.streamsplayer.watchface` (bound 2026-11-13, app `4976077107533670611`) | `release-ledger probe` = `PUBLISHED`, public store page HTTP 200 in en/ru/uk (recorded in `docs/releases/` and `docs/play/PLAY_RELEASE_RECORD.md`).

The generic Google Play row of CHANNEL_MATRIX is unchanged: a project's own rows live in its record (`TEMPLATE.md`), and the
generic row already says a secondary form-factor artifact has its own store guidelines.

## Public presence 2026-11-13 (updated 2026-11-20)

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
- **`PLAN/` is local and gitignored since 2026-11-16.** On 2026-11-16 the owner ruled that `PLAN/`, its journal and its
  archive are local and ignored by Git (`CLAUDE.md` section 4 item 6); `.gitignore` carries `/PLAN/` and `git ls-files PLAN`
  returns 0 files (verified 2026-11-20).
- **Site.** `https://serzhyale.github.io/StreamsPlayer_Android/`, served by GitHub Pages with the workflow build type through
  `.github/workflows/pages.yml`: a check job on `windows-latest` that first runs `git config --global core.autocrlf false`
  (the fix for the CRLF render-target problem in SITE_CONFIGURATION section 4), then `tools/site/build-site.ps1 -Check`; then
  the deploy job. The owner's report gives the first run as 43438392545, green. Measured by the canon session 2026-11-13:
  `privacy.html`, `privacy-ru.html`, `privacy-uk.html`, `sitemap.xml` and `robots.txt` answer 200; the site root answers
  **404**, because the product landing does not exist yet (the product's ticket STRMOB-0045), so the repository has no homepage and
  the Play listing no website. On 2026-11-20 (STRMOB-0170) the three privacy pages gained their `og:image` (`social-card-1200x630.png`)
  and regenerated permission tables.
- **Help.** The in-app help is not hosted yet; it is published with the first release (the product's STRMOB-0048, decision D2,
  owner's report). The shared media exchange portal answers 200, including the account-deletion page that the Data safety
  form links (owner's report, not re-measured).
- **Google Play Console** (personal developer account `8446656778368889827`, the one that holds DeviceInfo). App "StreamsPlayer: Internet Radio",
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
  graphic). Form factors: Wear OS added; Android XR left active by Google's default. App signing key `61:CF:..:F4:97`
  imported 2026-11-17; separate upload key `A8:68:..:FB:D0` reset valid 2026-11-19 16:20 (`docs/play/PLAY_RELEASE_RECORD.md`).
- **Waiting for the first Play upload and console completion** (`STRMOB-0047`, `STRMOB-0072`): establish accepted prior
  artifact history or an authorized, documented bootstrap for each app before API upload. The phone app's new
  foreground-service types require saved declarations before API writes. An unavailable form stops that path
  (`GOOGLE-PLAY` 0.4 section 8C). Review account sign-in details, target audience (18 and over), and Data safety
  submission are still pending for the phone app.
- **Google Play Console, second app "StreamsPlayer Watch Face"**, package `com.sza.streamsplayer.watchface` (bound to the account
  on 2026-11-13), App, Free. Every App content item complete ("You're all caught up"): no restricted access, no ads, no data
  collected, IARC all No (Everyone, PEGI 3), target audience 13 and over. Category Personalization, contact `sza@ukr.net`, Wear
  OS form factor. App signing key `61:CF:..:F4:97` imported 2026-11-17; upload key `A8:68:..:FB:D0` reset valid 2026-11-19 16:21.
  Listing sources authored in `docs/play/PLAY_LISTING_WATCHFACE*.md`; console upload awaits captured watch-face icons (`STRMOB-0099`).
- **Published watch face; main app awaiting pre-flight & publication.** `com.sza.streamsplayer.watchface` (`2.61.1210.302`) is live on Google Play (`2026-11-27`); `com.sza.streamsplayer` awaits remaining pre-flight blockers (`STRMOB-0230`) and publication (`STRMOB-0047`, `STRMOB-0222`).
- **Referring to the product.** The owner wants the other projects, `sza.od.ua` included, to refer to it once it is published.
  That waits for the publication and for the landing (`STRMOB-0045`); the canon files nothing in another repository for it.

## Deltas by document

### AI_USAGE.md
- CONFIRM: section 5 always-loaded rules budget (20,000 budget, 40,000 hard limit) and area-rule split hold (`CLAUDE.md` delegates area detail to 7 `.claude/rules/*.md` files with `paths:` frontmatter; `AGENTS.md` carries the area-rules paragraph).

### CONTRACTS.md
- CONFIRM: the repo names the catalog in one file (`CLAUDE.md` line 3); 28 pointers in `docs/contracts/` covering 41
  pointer versions (`RULE-ADOPTION`, `PORT-LEDGER`, `REMOTE-CONTROL`, `FUNCTION-PARITY`, `CAPTURE-OUTPUT`, `STREAM-BANK`,
  `USER-PLAYLIST`, `MEDIA-CLASSIFICATION`, `PACKAGE-VERSIONING`, `ICONOGRAPHY`, `INPUT-PARITY`, `LIVE-BROADCAST`,
  `DEVICE-EXCHANGE`, `INSTALL-TRUST`, `DIAGNOSTIC-REPORT`, `PRODUCT-WEB-PAGES`, `TEST-LAB`, `PORTAL-DOCS`, `UNIFIED-UI`,
  `CONTEXT-HELP`, `AUTOMATED-CHECKS`, `EXCHANGE-MARK`, `WAVE-PARTICLES`, `GOOGLE-PLAY`, `RELEASE-LEDGER`,
  `PRODUCT-IDENTITY`, `SOURCEFORGE-CHANNEL`, `ABOUT-PAGE`) and 35 `streams-mob` adoption rows in `_meta/REGISTRY.md` (`check-sync.ps1`
  PASS on 41 pointer versions; `contract-lag.ps1 -Product streams-mob -FailOnLag` exit 0 with 0 behind, 9 current,
  25 partial with dated reasons, 1 n/a). `docs/BOOTSTRAP_HANDOFF.md` names the catalog path too: an origin
  record written and amended on 2026-10-02 by the FastMediaSorter session of its ticket S4053, not edited from this
  repository; it carries a dated SZA-CTR02 exemption in `.sza-canon.json`.

### REPOSITORY_LAYOUT.md & RELEASE_AND_DISTRIBUTION.md sections 8 and 10
- CONFIRM (`REPO-LAYOUT` 0.12 rule 8, `RELEASE-LEDGER` 0.3): public-vs-local boundary adopted (`STRMOB-0218`, `STRMOB-0230`).
  Root agent rules (`CLAUDE.md`, `AGENTS.md`, `GEMINI.md`), `.claude/`, `.sza-canon.json`, `.sza-profile.json`,
  `docs/contracts/`, `docs/DOCUMENT_REGISTRY.jsonl`, `docs/releases/`, `dev/`, `PLAN/`, `r0..rw.ps1` and `tools/harness.ps1`
  stay intact on disk and are gitignored and untracked (`check-compliance.ps1` exits 0 with 0 errors).
- CONFIRM: the harness release package plan stands with all six decisions recorded in `CLAUDE.md` section 4 (the shared
  harness writes only `PLAN/RELEASE_QUEUE.md` through `Write-Catalog` -> `Sync-ReleaseQueue`, renders ready and shipped
  history views from the ledger via `release-queue -List -Ready` / `-Show Ready|Done`, and reads legacy
  `PLAN/RELEASE_READY.md` and `PLAN/RELEASE_QUEUE_DONE.md` only to import prior rows; package number from
  `current-next-release:` marker because this repo works on `main`; `PLAN/` local and gitignored since 2026-11-16). The
  release ledger (`docs/releases/`, `RELEASE-LEDGER` 0.3, local/gitignored) is initialized with 6 Play channel rows, hooked into `a.ps1`
  (S0154), and records the 2026-11-27 `watchface` publication (`2.61.1210.302`) and builds. Under
  `GOOGLE-PLAY` 0.6 section 10 (rule 31), `docs/play/PLAY_RELEASE_RECORD.md` records Shape 1 (One salvo).

### TESTING_AND_QA.md section 2
- CONFIRM: fast gates (5 s or less) are listed with measured wall times in `CLAUDE.md` section 5a; `.sza-profile.json`
  declares no `commands.compileCheck` because Android/Gradle has no measured fast compile form between releases, so passes
  record "no compile command" and defer full builds, Gradle unit suites and slow tool self-tests to
  `tools/release/pre-release-sweep.ps1`.

### SECURITY_AND_PRIVACY.md
- EXEMPT (`SZA-SEC01`, `SZA-SEC04`): `.sza-canon.json` records dated exemptions for `exchange-core/src/test/resources/device-exchange/tunnel-test.p12` (self-signed `BroadcastTunnelTlsTest` fixture) and `wear/src/test/resources/golden/wear-payload/payload_sync_v1.json` (ported golden v1 fixture from FastMediaSorter whose `sshPrivateKey` stub `b3BlbnNzaA==` decodes to `openssh`, `STRMOB-0209`).

## No delta

AUTHOR, CHANNEL_MATRIX, DEVELOPMENT, DOCUMENTATION_CONCEPT, GITHUB_INTERACTION, INVARIANTS, LOCALIZATION,
NEW_PROJECT_CHECKLIST, PLATFORM_OVERLAYS, PROMOTION, SITE_CONFIGURATION,
SUPPORT_AND_FEEDBACK, TESTING_AND_QA, UI_UX; WINDOWS_PACKAGING is not applicable to overlay B.

## Open questions for the owner

Open as of 2026-11-20 (each carried by its project ticket; none blocks the canon):

- **Play variant.** Whether the Play app `com.sza.streamsplayer` ever carries a second variant beyond `store` stays as
  decided on 2026-10-02 (`noLegal` shares the base id as a sideload variant and is never co-published to one store).
- **Landing (`STRMOB-0045`).** The repository homepage and the Play website field wait for it; they stay empty until
  the landing answers 200.
- **Watch-face captured icons (`STRMOB-0099`).** Replacing the drawn watch-face launcher vector and listing graphics with
  captures of the real face (`GOOGLE-PLAY` rule 25) before uploading `com.sza.streamsplayer.watchface` (`STRMOB-0072`).
- **Pending Play publication steps (`STRMOB-0047`, `STRMOB-0072`).** Pre-release sweep PASS after drift/canon blockers,
  followed by the first-use checks and Console inputs in the Play record above.

Settled or superseded since 2026-10-02 and 2026-11-13: 4.3 distribution (play first, per the stamp's comment; a sideload
channel is added when it opens), 4.4 watch-face composition (the second app exists and its listing source is
`docs/play/PLAY_LISTING_WATCHFACE*.md`), 4.5 GitHub remote (created 2026-11-13), 4.7 site (Pages is live; the landing is
STRMOB-0045), public `PLAN/` (local and gitignored by owner decision of 2026-11-16), app signing key import and separate
upload key registration (completed 2026-11-17, valid 2026-11-19).
