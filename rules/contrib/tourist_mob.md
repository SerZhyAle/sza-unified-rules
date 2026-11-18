---
# Contribution: tourist_mob (overlay B, flavor shape, three packages, no contract of its own) -> Unified_Rules
Source repo: P:\ANDROID\Tourist_mob | Date: 2026-10-02, refreshed 2026-11-13 (S0062)
Read: NEW_PROJECT_CHECKLIST, PLATFORM_OVERLAYS, CONTRACTS, INVARIANTS, RELEASE_AND_DISTRIBUTION section 8, harness README and spec_catalog SCHEMA, the adopt-canon and contract-sync skills; on 2026-11-13 also the product's remote `.sza-canon.json`, its `.github/workflows/pages.yml`, the names of its `docs/play/` files, the public GitHub API and the Pages URLs, and the deviceinfo (S0057) and StreamsPlayer (S0059) records as models; deduped against: contrib/streamsplayer_mob.md, contrib/fastmediasorter_mob_v2.md
---

> **Owner decision, 2026-11-16:** `PLAN/` and its archive are local and ignored. Earlier statements below
> that the workspace is tracked or public describe the former policy.

Tourist for Android: a hike kit - the Tourist dashboard with compass, SOS, the water flashlight, the screen and
camera flashlights, a multi-participant stopwatch - as a phone app, a Wear OS app and a watch face. An
independent product extracted from FastMediaSorter Android (`fastmediasorter_mob_v2.md`) under its ticket S4070;
the second extraction of the day after StreamsPlayer for Android (`streamsplayer_mob.md`), by the same method,
so almost all overlay-B material is CONFIRM of that record. New against the sibling: a product that holds **no
contract of its own and no definite producer role** - its only guarantee against drift from the extraction
source is the port ledger with its SHA-256 drift check (handoff section 6a), and the contract pointers it keeps
are adopter, consumer and conditional ones.

Public presence since 2026-11-13 (section "Public presence 2026-11-13"): a public GitHub repository, a GitHub Pages
privacy site and two Google Play Console apps, all created on the owner's order; nothing is published on Google Play yet.

> **Keep this note in the record.** Current facts, edited in place. Never append a dated section to this file:
> what happened and when goes to the file of the same name under `history/`
> ([the rules of that folder](history/README.md)), which is not reading for a task. A delta the core absorbed,
> a candidate that was applied or refused and a question that was answered are deleted here; the history
> section of that day says what became of them.

## Overlay facts (verified against this repo, 2026-10-02; refreshed 2026-11-13)

- **Source root & release-mechanics.** Gradle modules phone / wear / watchface, and `build-logic`, are on `main` of the
  public remote since the first push (commit `5db4d6e`, measured 2026-11-13); the 2026-10-02 "none exist yet" is history.
  Specs in `PLAN/Sxxxx_<slug>.md`, the harness run from the plugin through `tools/harness.ps1` (evidence:
  `.sza-profile.json`, `tools/harness.ps1`).
- **Version shape.** PACKAGE-VERSIONING Android profile; no tag yet (the remote has none on 2026-11-13, and
  `versionShape.tagRegex` is null in the remote stamp).
- **Channels + listing files.** `channels: ["play"]` on the remote stamp (2026-11-13, the owner's order of the same day):
  the store variant of phone and wear under `com.sza.tourist`, and the watch face under `com.sza.tourist.watchface`.
  Listing sources are on `main` under `docs/play/` (`PLAY_LISTING*.md` for en-US, ru-RU and uk, `PLAY_DATA_SAFETY.md`,
  `icon-512.png`, `feature-graphic-1024x500.png`). The sideload channel of the noLegal variant waits for its first release
  (S0010). Owner decisions 4.5, 4.7 and 4.9 were open on 2026-10-02 (ticket S0010); the 2026-11-13 report answers them.
- **Frozen anchors (owner, 2026-10-02; bound to the console 2026-11-13).** `com.sza.tourist` shared by phone, watch and
  the noLegal variant (sanctioned exception: never co-published to one store), bound to the Play app "Tourist: Hiking Kit";
  `com.sza.tourist.watchface`, the module exists, bound to "Tourist Watch Face". Signing key at
  `P:\ANDROID\Tourist_credentials` (the 2026-10-02 record says not created yet; the 2026-11-13 report does not say whether it
  exists now). Play App Signing with the product's own key imported as the app signing key plus a separate upload key, so
  store and sideload builds carry one signature (the 2026-10-02 plan; the 2026-11-13 report does not confirm the import).
- **Editions + parity mechanism.** None - single edition. Shape: flavor (store, noLegal); wear and watchface are
  sibling modules. Coupling to FastMediaSorter: the shared catalog plus a port ledger and drift check.

## Channel-matrix rows (this project)

Format: Channel | Trigger | Cost | Auth | Signer | Listing source | Frozen anchor | Verify live

- **Google Play (Android), app "Tourist: Hiking Kit", phone and Wear OS in one listing** | AAB upload to a track: the phone
  bundle, then the Wear OS bundle to the same app; no upload is named in the 2026-11-13 report | [PUBLIC] | Play Console, the
  owner's personal developer account | Play App Signing; the upload key and the signing-key import are not confirmed by the
  2026-11-13 report (the 2026-10-02 plan names the import) | `docs/play/PLAY_LISTING*.md` (en-US, ru-RU, uk) and
  `docs/play/PLAY_DATA_SAFETY.md`; graphics `docs/play/icon-512.png` and `docs/play/feature-graphic-1024x500.png` |
  `com.sza.tourist` (bound 2026-11-13) | track shows the build, staged rollout, update over a prior install on a phone and on
  a watch - **not run**, nothing is published. (evidence: owner's report of 2026-11-13; the remote tree of `main`)
- **Google Play (Android), app "Tourist Watch Face"** | AAB upload to a track; no upload is named in the 2026-11-13 report;
  listing empty as reported | [PUBLIC] | same console account | same open items as above | none yet - no listing text |
  `com.sza.tourist.watchface` (bound 2026-11-13) | track shows the build - **not run**.

The generic Google Play row of CHANNEL_MATRIX is unchanged: a project's own rows live in its record (`TEMPLATE.md`), and the
generic row already says a secondary form-factor artifact has its own store guidelines.

## Public presence 2026-11-13

Recorded as the owner's session reported it; what the canon session measured itself is marked as such.

- **GitHub.** Public remote `https://github.com/SerZhyAle/Tourist_Android`, branch `main`, head `5db4d6e` (the product
  tree), created 2026-11-13. GitHub detects the license as MIT; the description is the product's one-line statement; 14 topics;
  no homepage (it waits for the landing, below); wiki and projects off, issues on; no tags. (measured by the canon session
  2026-11-13: GitHub API for the repository and for `main`)
- **History.** The five foundation commits were rewritten before the first push, to redact one private address from an owner
  quote in `PLAN/S0012`; a backup bundle was kept outside the repository (owner's report). The public history starts at the
  rewritten commits.
- **Publication scan (owner's report).** No signing material and no token or key pattern in the tree (test fixtures only); the
  `.gitignore` hid nothing but `local.properties`, and the IDE output `build-logic/convention/bin/` was added to it; one emulator
  capture showed the emulator's Google account name in the notification shade and was painted over.
- **`PLAN/` is public with the remote** (owner decision in the report).
- **Site.** `https://serzhyale.github.io/Tourist_Android/`, served by GitHub Pages with the workflow build type through
  `.github/workflows/pages.yml`: a check job on `windows-latest` that first runs `git config --global core.autocrlf false`, then
  `tools/site/check-site.ps1` and `tools/docs/check-docs.ps1 -Check all -NoHarness`; then a deploy job on `ubuntu-latest`. The
  first run `43456039842` (`Publish site/ to GitHub Pages`, push on `main`) completed with success (measured by the canon session
  2026-11-13). Measured the same day: `privacy.html`, `privacy-ru.html`, `privacy-uk.html`, `sitemap.xml` and `robots.txt` answer
  200; the site root answers **404**, because the product landing does not exist yet (`tourist-mob:S0026`, owner's report), so the
  repository has no homepage and the listings no website. The owner's report adds that the vendored `sza-kit.css` is byte-identical
  to the catalog copy (not re-measured here).
- **Remote stamp.** `.sza-canon.json` on `main` declares `channels: ["play"]`, site kind product with the three privacy pages,
  `privacy.page` `site/privacy.html` and `sensitiveAccess: true` (the phone reads location, sent to Open-Meteo for the weather,
  and drives the camera torch). Its canon is `2026.10.17.1`; see the canon-state section.
- **Google Play Console, app "Tourist: Hiking Kit"** (the owner's personal developer account, the one that holds DeviceInfo and
  StreamsPlayer), package `com.sza.tourist` bound on 2026-11-13, App, Free, en-US; Developer Program Policies, US export laws and
  the IARC terms accepted on the owner's explicit yes. App content: privacy policy
  `https://serzhyale.github.io/Tourist_Android/privacy.html`; sign-in details no; ads no; advertising ID no; government no;
  financial features none; health features: activity and fitness (steps and cadence); target audience 18 and over. Data safety:
  precise location and in-app search history collected, not shared, processed ephemerally, optional, for App functionality (the
  weather and place-search requests to Open-Meteo). Content rating from a fresh IARC questionnaire, every answer No: ESRB
  Everyone, PEGI 3, USK all ages, ClassInd all ages, IARC 3+. Store settings: category Travel & Local, the contact address set by
  the owner (not written here), no website until the landing answers. Listing filled in en-US, ru-RU and uk with the icon and the
  feature graphic (render targets of `tools/store/render-store-assets.ps1`). Form factors: Wear OS added; Android XR left active
  by Google's default.
- **Google Play Console, app "Tourist Watch Face"**, package `com.sza.tourist.watchface` (bound 2026-11-13), App, Free: every App
  content item complete ("You're all caught up"): no data collected, IARC all No (Everyone, PEGI 3), target audience 13 and over;
  contact address set by the owner; Wear OS form factor; listing empty (owner's report).
- **Not published.** Nothing is published on Google Play (owner's report). The report names no bundle upload, no review submission
  and no release. Nothing here claims an upload.
- **Still before publication (owner's report, not canon work):** `tourist-mob:S0054`; the family notices `hub:S0011` and one
  footer-grid ticket per map consumer.

## Deltas by document

### CONTRACTS.md
- CONFIRM: the repo names the catalog in one file (`CLAUDE.md` line 3); seven pointers in `docs/contracts/`
  (PACKAGE-VERSIONING, INPUT-PARITY, ICON-SET and ICON-RENDER conditional, DIAGNOSTIC-REPORT and INSTALL-TRUST
  conditional, the rule-adoption family, the product-web-pages family conditional) and an index stating that no
  contract is owned here. `docs/BOOTSTRAP_HANDOFF.md` names the catalog path too: an origin record written before
  the first commit and not edited from this repository, carried by a dated SZA-CTR02 exemption.

### RELEASE_AND_DISTRIBUTION.md section 8
- CONFIRM with the streamsplayer_mob DIVERGE: the harness release plan stood up as shipped, the package number
  from the `current-next-release:` marker because the repo works on `main`, and `PLAN/` **tracked**. On 2026-10-02
  the reason was that there was no remote yet; since 2026-11-13 the remote is public and `PLAN/` is public with it
  (owner's decision), so the 2026-10-02 reason no longer holds and `PLAN/` stays tracked.

## No delta

REPOSITORY_LAYOUT (Android spec home), INVARIANTS, NEW_PROJECT_CHECKLIST.

## Candidate core edits (PROPOSED - apply only on owner instruction)

- **adopt-canon step 6 / `templates/`:** the release plan's three files must exist before the first ticket is
  inserted, or the harness skips the reconcile without a word (`Sync-ReleaseQueue` returns when the queue file is
  missing, `spec_catalog/_lib.ps1` lines 709-710) while `release-queue.ps1` itself exits 2 with "seed it". Ship the
  three seed files (the queue with its `current-next-release: 1` marker line) next to `.sza-profile.json` in
  `templates/`, and name them in the step. Without them every adopter re-derives the shape from a sibling.
  Prevents a ticket store that holds tickets and no plan; evidence: this run, where the seeds were written first
  and the first insert produced the queue block.
- **Harness forwarder in `templates/`:** the harness README says an adopter "can keep its own thin entry points",
  and the handoff text forbids hand-copying harness scripts, yet the plugin ships no forwarder; every adopter
  writes `tools/harness.ps1` from the sibling's description (two repositories in one day, written twice).
  Ship one forwarder in `templates/` and name it in adopt-canon step 3. Evidence: `grep -r "harness.ps1"` over the
  plugin finds only contrib text.
- **Harness `release-queue -List -Ready` on an empty ready file (tools/harness):** exits 1 with "The property
  'Count' cannot be found on this object" until the first ticket reaches `RELEASE_READY.md`. In
  `spec_catalog/release-queue.ps1`, line 256 assigns `$tickets = Get-QueueTickets ..` unwrapped (an empty result
  unrolls to `$null`; line 257 wraps it in `@()` only on the `-Release` path) and line 302 reads `$tickets.Count`
  under StrictMode. The same class as the validator defect recorded in `streamsplayer_mob.md` and fixed on
  2026-10-02; fix: `$tickets = @(Get-QueueTickets ..)`. Evidence: reproduced on a fresh store (exit 1), and
  `-List -Ready` exits 0 once S0001 moved to Verified. Not patched from this repository.
- **Harness ticket-id grammar (tools/harness):** unchanged since `streamsplayer_mob.md` - `grammar.ticketIdPattern`
  is a profile key but `New-CatalogId` and `insert.ps1 -Id` hard-code `^S\d{4}$` (57 occurrences in 42 files,
  counted on plugin 2026.1002.3). Two products on the same day now share the `S0001` space with FastMediaSorter;
  citing the repository name next to an id is the workaround recorded in `CLAUDE.md`.

## Candidate NEW docs (not in any shared doc yet)

- None required.

## Open questions for the owner

- **Play variant.** The remote stamp declares the store variant for the Play app; the owner's 2026-11-13 report names no
  variant. Confirm it.
- **Watch-face listing text.** The report says the watch-face listing is empty. Whether it waits for its source, as the
  StreamsPlayer watch face does (S0059), is the owner's call.
- **Landing.** The repository's homepage and the Play website field wait for the landing `tourist-mob:S0026`; the site
  root answers 404 until then.
- **Contact address.** The owner's address is set on both apps and is not written into this record. Say if it should be.
- **Still open from 2026-10-02:** 4.3 store-variant composition (before the wear phase, S0008), 4.4 watch face composition
  (S0009), 4.6 name and branding, and the phone start-screen placement (S0004), each attached to the ticket of the phase that
  needs it. 4.5, 4.7 and 4.9 are answered by the 2026-11-13 report.

