---
# Contribution: fastmediasorter_web (FMS_Web; new overlay E drafted - a browser application served as static files) -> Unified_Rules
Source repo: P:\WEB\FastMediaSorter_WEB | Date: 2026-10-16
Read: NEW_PROJECT_CHECKLIST, PLATFORM_OVERLAYS, INVARIANTS, REPOSITORY_LAYOUT, the adopt-canon, contract-sync and task-flow-init skills, the catalog's RULES, VERSIONING and REGISTRY, rule-adoption sections 2-5; deduped against: contrib/tourist_mob.md, contrib/streamsplayer_mob.md
---

FMS_Web gives people on systems the native programs do not serve - macOS, Linux, ChromeOS, iOS and iPadOS, and anyone
who cannot install a program - a subset of the functions of FMS_A and FMS_Win inside the popular browsers (owner,
2026-10-16). One slice is the client of the device-exchange server that FMS_Win hosts (account, devices, resources,
broadcasts, clipboard, operator administration - the scope of FastMediaSorter Android S4246, which created the
repository on 2026-10-15); the other works on the person's own files in the browser. No code is shared with either
program. The adoption mechanics are CONFIRM of `tourist_mob.md`. Genuinely new: **no overlay fits** - the first
portfolio product whose artifact is a web application, neither an installed program nor a product page.

## Names (owner, 2026-10-16)

- **FMS_A** - FastMediaSorter for Android, `P:\ANDROID\FastMediaSorter_mob_v2`.
- **FMS_Win** - FastMediaSorter for Windows, `P:\WINDOWS\FastMediaSorter_Lite`, which also holds the device-exchange
  server under `exchange-server/`.
- **FMS_Web** - this repository.
- The catalog's living text writes FMS_Win since 2026-10-16 (the canon session's rename on the owner's order, a
  `correction` row per contract, no version bump); its records, the repository's handoff and `docs/origin/` keep the
  former label `FMS_W` (`DEVICE-EXCHANGE` item CX). The repository quotes those verbatim and never writes `FMS_W` in
  new text.

## Overlay facts (verified against this repo, 2026-10-16)

- **Source root & release-mechanics.** None yet: the stack (static ES modules, Go to WebAssembly, or TypeScript with a
  bundler) is open owner decision S0003; where the exchange page is served from is research ticket S0004 (evidence:
  `docs/BOOTSTRAP_HANDOFF.md` sections 4 and 5; the `modules` comment in `.sza-profile.json`).
- **Version shape.** None yet; `versionShape.tagRegex` null. Settled with S0004 and S0020.
- **Channels + listing files.** None - `channels: []`. `REPO-STAMP` rule 4's channel vocabulary has no value for a
  static host, a copy served by another product's server, or an installed web app.
- **Frozen anchors.** None reserved yet. The candidate is the origin of the public address (overlay E draft below),
  which FMS_A's portal page and Play account-deletion address will point at (S0019, S0020).
- **Editions + parity mechanism.** **Not declared as an edition**, on purpose. Reading: FMS_Web has the *shape* of a
  cross-repo edition (PLATFORM_OVERLAYS "Editions") - independent code and release, behaviour held in step through
  catalog contracts, never shared code. But the stamp's `editions` field lists the editions a repository itself
  ships: FMS_Win declares `["server"]` for its in-repo server edition, FMS_A declares `[]`, and neither names the other
  or FMS_Web. A one-sided `editions` entry here would claim a relation no sibling stamp records, and FMS_Web offers a
  subset of *two* products, not a second form of one. The parity mechanism is therefore the catalog alone: the
  contracts it implements, and a `PROPOSAL-<date>-<slug>.md` beside the closest contract for any first-release
  function that must behave like FMS_A or FMS_Win and has none (ticket S0010). If the canon wants the relation
  recorded, a family-level `editions` vocabulary is a canon change, not this stamp's.

## Channel-matrix rows (this project)

- None yet. Recorded when S0020 settles how the product is served.

## Deltas by document

### PLATFORM_OVERLAYS.md
- ADD (overlay E): the candidate NEW section below. Evidence: the stamp declares `overlay: ["E"]` with a `$comment`;
  SZA-CANON04 counts overlays and does not check the letter, so the declaration passes without a finding
  (`tools/check-compliance.ps1` around line 238).

### CONTRACTS.md
- CONFIRM: the catalog is named in one file (`CLAUDE.md` line 3); pointers under `docs/contracts/` with an index
  stating that no contract is owned here. `docs/BOOTSTRAP_HANDOFF.md` and the verbatim spec copy in `docs/origin/`
  name the catalog path; both are origin records, carried by dated SZA-CTR02 exemptions, as in `tourist_mob.md`.
- CONFIRM the sealing rule from the consumer side: every amendment the handoff asked to be "written in the catalog
  first" (a `product` value in item CE, the browser transport in 7.1, item D's browser wording, the operator surface)
  is a proposal to the owner, FastMediaSorter Android - ticket S0010.

### REPOSITORY_LAYOUT.md
- CONFIRM: `PLAN/` tracked with no remote, the DIVERGE of `streamsplayer_mob.md` and `tourist_mob.md`.
- ADD (name-based leak globs against a security product's vocabulary): the `*token*` and `*secret*` globs the canon
  asks for, and SZA-SEC02 checks, swallow any source file whose name holds either word - in a product whose domain is
  tokens and device secrets (`session-token.js`, `secret-box.js`) that is a silent non-commit. The repo records the
  trap in `CLAUDE.md` section 5; a canon note beside the glob list would serve every product with an auth module.

### RELEASE_AND_DISTRIBUTION.md section 8
- CONFIRM: the harness release plan stood up as shipped; package number from the `current-next-release:` marker (the
  repo works on `main`); `PLAN/` tracked. `release-queue -Validate` exit 0 and `-List -Ready` exit 0 on a fresh store -
  the empty-ready-file defect recorded in `tourist_mob.md` is fixed in plugin 2026.1015.4.

## No delta

INVARIANTS (beyond the overlay E equivalents below), NEW_PROJECT_CHECKLIST (overlay choice aside), AI_USAGE.

## Candidate core edits (PROPOSED - apply only on owner instruction)

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

## Candidate NEW docs (not in any shared doc yet)

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

## Open questions for the owner

- Stack (S0003), public name, remote and visibility (S0021), site (S0022), where the exchange page lives (S0004),
  transport (S0005), certificate trust (S0006), operator sign-in (S0007), folders (S0017), broadcasts (S0015),
  deletion address (S0019) - each attached to its ticket and asked once, right before the phase that needs it.
- The first-release function set, the browser support floor (with "IE" read as Microsoft Edge) and the order of the
  local and exchange tracks - asked in S0002.

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

- Ticket `PLAN/S0031_in-app-help-f1-and-button.md` (Draft), created by the canon session from the owner's request for F1 and a `?` button in every product ([UI_UX](../UI_UX.md) §7, contract `CONTEXT-HELP` 0.1). The surface list comes from the view registry that S0028 must expose. Found on the way: `capture-draft -DedupQuery` threw on an empty search result (an `if` expression yielding `@()` unrolls to `$null` under StrictMode) - fixed in the canon harness the same day.
