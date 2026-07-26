---
# Contribution: CyrFlip (overlay A, no-installer variant + a companion VS Code Marketplace channel; single app edition + a thin editor companion) -> Unified_Rules
Source repo: p:\WINDOWS\CyrFlip | Date: 2026-07-23
Read: all 16 core docs; contrib/{epub_2_html,fastmediasorter_lite,fastmediasorter_mob_v2,filedo,streams_player}.md (deduped against)
---

CyrFlip is a net48 WinForms tray utility (live EN/RU/UK layout indicator at the caret + one-key
transliteration/case-flip), owned by SZA, shipped through the **Overlay A desktop channels** (GitHub
Release + winget + Microsoft Store) as a **portable zip, no installer** (like StreamsPlayer). Its genuinely
new material is a **fourth channel the shared docs do not cover - the VS Code Marketplace** - and the shape
that rides it: a **thin in-repo companion extension** (TypeScript, no shared code) coupled to the app by a
one-way on-disk file contract, released on its own clock and cadence. Also new: a **no-root-CHANGELOG**
"What's new" model where the `/release` skill is the ship-together manifest, a concrete **GitHub Actions
cost/safety-lever** set, a **build-time-stamp-vs-tag** version pin, and two MSIX/Partner-Center traps.
The Overlay A no-installer + winget-portable + MSIX-`M*100+D`-remap + Store-CSV-export-then-merge +
build-deploys-to-sync-folders facts are already saturated by streams_player/filedo/fastmediasorter_lite and
are **CONFIRM, deduped out**.

## Overlay facts (verified against this repo)

- **Source root & release-mechanics.** `src/CyrFlip/` (net48 WinForms) + `tests/CyrFlip.Tests/` (xUnit);
  channels as top-level siblings (no `publishing/` umbrella): `winget/`, `msix/`, `.github/workflows/`,
  `store/` (plain-text listings). Release-mechanics are two root scripts: `build.ps1` (СБОРКА - free local
  build, may push but never tags) + `release.ps1` (РЕЛИЗ - the only tagger). **No installer folder** (no Inno
  `.iss` / WiX `.wxs`). Plus a self-contained `vscode-extension/` companion subtree (evidence: root `ls`,
  `build.ps1`, `release.ps1`).
- **Version shape (+ padding choice).** Dotted **`YY.M.D.HHmm`** (`26.7.22.1712`), stamped in the csproj as
  `$([System.DateTime]::Now.ToString('yy.M.d.HHmm'))` (`src/CyrFlip/CyrFlip.csproj:24`). MSIX remap
  `YY.(M*100+D).HHmm.0` (already core, from fastmediasorter_lite). The **VS Code extension runs its own semver
  clock** (`package.json "version": "0.1.1"`), decoupled from the app date tag.
- **Channels + listing files (4 publish ops + a site).** GitHub Release (`CyrFlip-<ver>-windows-x64.zip` +
  `.sha256`, body auto from `generate_release_notes`); winget `SerZhyAle.CyrFlip` (`winget/*.yaml`,
  `InstallerType: zip` / `NestedInstallerType: portable`, alias `cyrflip`, with `ReleaseNotes` in the locale
  manifests); Microsoft Store MSIX (`msix/build-msix.ps1`, listing `msix/store-listings.md` +
  `store-listing-export.csv`, manual Partner Center); **VS Code Marketplace** (`npx @vscode/vsce publish`,
  listing = `vscode-extension/package.json` + `README.md` + `CHANGELOG.md`). GitHub Pages from `/docs`
  (trilingual `docs/` + `docs/ru/` + `docs/uk/`, no CNAME). (evidence: `.github/workflows/release.yml`,
  `winget/SerZhyAle.CyrFlip.installer.yaml`, `.claude/skills/release/SKILL.md`.)
- **Frozen anchors.** winget `PackageIdentifier: SerZhyAle.CyrFlip`; MSIX Identity `Name: SZA.CyrFlip` +
  `Publisher: CN=F98ACEDB-1E22-4C39-AF63-F9FCFE807DCD` + PublisherDisplayName `SZA` + Store ID `9NB4W41NGQJ4`;
  exe/`AssemblyName` `CyrFlip`; **VS Code extension id `SerZhyAle.cyrflip-vscode`** (publisher + name). **No
  Inno `AppId` / WiX `UpgradeCode`** (portable-zip-only). The Publisher CN + PublisherDisplayName are the same
  SZA-constant values StreamsPlayer uses - CONFIRM of "publisher-constant, non-secret defaults" (evidence:
  `release.ps1:96`, `msix/AppxManifest.xml:29-33`, `vscode-extension/package.json:2,6`).
- **Editions + parity mechanism.** **Single app edition.** The `vscode-extension/` is **not** an edition
  (it mirrors none of the product's behaviour - it only renders the layout marker at Monaco's caret) and
  **not** a co-shipped companion binary (it has its own channel, version clock and cadence, not the app's
  release tag). It is a **companion editor extension** coupled to the app by a **one-way file contract**:
  the app writes `layout.txt` (`LayoutPublisher.cs`), the extension polls it (`package.json`
  `cyrflip.layoutFile`/`pollIntervalMs`). No shared code (C# vs TypeScript) (evidence:
  `src/CyrFlip/LayoutPublisher.cs:11-22`, `vscode-extension/package.json:44-60`).

## Channel-matrix rows (this project)
Format: Channel | Trigger | Cost | Auth | Signer | Listing source | Frozen anchor | Verify live
- **GitHub Release** | `v*` tag push (or `workflow_dispatch`) -> `release.yml` | [PAID][PUBLIC] | `gh` ambient | self - **optional** Authenticode, secrets `SIGNING_CERT_*` unset so it ships **unsigned** | release body <- `generate_release_notes: true` (git log, no CHANGELOG) | exe name `CyrFlip.exe` (no installer id) | ZIP + `.sha256` download, hash matches (evidence: `release.yml:29-31,75-76,150`).
- **winget** | `wingetcreate update SerZhyAle.CyrFlip --version <ver> --urls <ZIP_URL> --submit` -> PR | [PUBLIC] | `gh` + one-time CLA | Microsoft re-hosts | `winget/*.yaml` (committed; `ReleaseNotes`+`ReleaseNotesUrl`) | `SerZhyAle.CyrFlip` (portable-in-zip, alias `cyrflip`) | `winget install --manifest`, then `winget search` after merge (evidence: `installer.yaml:11-19`, `locale.en-US.yaml:21-27`).
- **Microsoft Store (MSIX)** | **manual** Partner Center submission | [PUBLIC] | Partner Center console (individual MSA) | **Store re-signs** (unsigned `.msix` upload) | `msix/store-listings.md` (EN/RU/UK "What's new") + `store-listing-export.csv` (export-then-merge) | MSIX Identity `SZA.CyrFlip` + Publisher CN + Store ID `9NB4W41NGQJ4` | dashboard version; update over prior MSIX (evidence: `release.ps1:94-99`, `STORE_PUBLISHING.md`).
- **VS Code Marketplace** | **manual** `npx @vscode/vsce publish` (only if `vscode-extension/` changed) | [PUBLIC] | Marketplace PAT (Azure DevOps-backed) | Marketplace | `vscode-extension/package.json` + `README.md` + `CHANGELOG.md` | extension id `SerZhyAle.cyrflip-vscode` (publisher + name) | Marketplace page shows the new version; installed copies auto-update (evidence: `release/SKILL.md:83-86`, `vscode-extension/package.json`).
- **GitHub Pages** (site publish, not a release) | push to `main` touching `docs/**` | native Pages build | repo Pages setting (served from `/docs`) | - | `docs/*.html` + `docs/ru/` + `docs/uk/` | none (default `serzhyale.github.io/CyrFlip/`) | index/guide/privacy render EN/RU/UK; `sitemap.xml`/`robots.txt` resolve (evidence: `RELEASE.md:60`, `docs/sitemap.xml`).

## Deltas by document

### PLATFORM_OVERLAYS.md
- ADD (a new channel + a new co-shipping shape - **companion editor extension on the VS Code Marketplace**):
  the "Co-shipping shapes" and "Editions" sections cover a *flavor*, a *dual-runtime variant*, a *co-shipped
  companion binary* (same release/tag), and a full *edition* (independent product + parity doc). CyrFlip's
  `vscode-extension/` fits none: it is an **in-repo, code-independent (TypeScript) companion** that renders
  **one** app feature the external overlay can't reach (the layout marker at Monaco's caret), published to the
  **VS Code Marketplace** on **its own semver clock and cadence** ("only if `vscode-extension/` changed") and
  coupled to the parent by a **one-way on-disk file contract** (`layout.txt`), not shared code. It sits between
  a co-shipped companion (same tag) and an edition (mirrors behaviour + parity doc). Neither existing overlay
  names the VS Code Marketplace as a channel (evidence: `vscode-extension/package.json`,
  `src/CyrFlip/LayoutPublisher.cs:11-22`, `.claude/skills/release/SKILL.md:39-42,83-86`).
- CONFIRM (no-installer Overlay A variant, dedup vs streams_player): portable-zip GitHub + winget-portable +
  MSIX, frozen-anchor set reduced to {winget `PackageIdentifier`, MSIX Identity `Name`+`Publisher`}, no Inno
  `AppId` / WiX `UpgradeCode`. A second data point for the variant (evidence: `installer.yaml:11-19`, no
  `installer/` folder).

### CHANNEL_MATRIX.md
- ADD (a new row - **VS Code Marketplace**): trigger = manual `npx @vscode/vsce publish`; cost [PUBLIC], no
  paid CI (published from the dev machine); auth = a **Marketplace Personal Access Token** (Azure DevOps org
  behind the publisher); signer/host = the Marketplace; listing source = `vscode-extension/package.json`
  (`displayName`/`description`/`categories`/`keywords`) + `README.md` (the gallery page) + `CHANGELOG.md`;
  frozen anchor = the **extension id `<publisher>.<name>`** (changing publisher or name orphans installs);
  verify = the gallery shows the new version and installed copies auto-update. Distinct from the Chrome/Edge
  rows (a different store, different auth, a single item id not two) (evidence: `release/SKILL.md:83-86`,
  `vscode-extension/package.json:2-3,6`).
- ADD (MSIX Partner-Center onboarding + `msstore`-CLI traps, hard-won): (1) register under **Partner Center
  "Windows"** program, **not** "Windows Desktop Applications" (the latter is telemetry for EV-signed Win32
  apps, not an MSIX submission path). (2) The `msstore` CLI's interactive `msstore reconfigure` **fails on an
  individual developer account** ("Error while retrieving Organization" - there is no Azure AD org behind a
  personal MSA); automation needs a service-principal `--tenantId/--clientId/--clientSecret`, so for
  individual accounts the **Partner Center web submission is the reliable path** (evidence:
  `STORE_PUBLISHING.md:73-75,122-126`).
- ADD (MSIX virtualization trap sharper than the HKCU-Run/firewall note already in the playbook - **a file a
  *different* process must read**): under MSIX a write to `%LOCALAPPDATA%` is virtualized into the package
  container, so the **companion VS Code extension (unpackaged, different process) cannot find `layout.txt`**.
  Fix: when packaged, write to **`%ProgramData%`** (not virtualized) and have the reader check both paths;
  detect packaging via `GetCurrentPackageFullName`. Generalizes the existing MSIX note from "autostart/firewall"
  to "any file used for inter-process IPC" (evidence: `src/CyrFlip/LayoutPublisher.cs:11-22`,
  `src/CyrFlip/PackageInfo.cs:11-15`, `STORE_PUBLISHING.md:22-32`).
- CONFIRM/instance (a whole app category draws extra Store review - a second concrete case beside
  stream-players): a **global keyboard hook + clipboard reads as a keylogger**, so MSIX certification adds
  scrutiny; pre-empt it with the `runFullTrust` justification + a plain "does not log keystrokes, no network,
  no data" description (evidence: `STORE_PUBLISHING.md:104-106`, `msix/AppxManifest.xml:70-73`).

### DOCUMENTATION_CONCEPT.md
- DIVERGE/ADD (a fourth "What's new" shape - **no root CHANGELOG; the release skill is the ship-together
  manifest; git log is the ledger**): CyrFlip has **no `CHANGELOG.md` at repo root** and no `DEV/CHANGELOG.md`.
  The GitHub Release body is generated from commit history (`generate_release_notes: true`), and the same
  "What's new in vXXX" is then authored **by hand into four surfaces** (Store `msix/store-listings.md`, winget
  locale `ReleaseNotes`, the extension `CHANGELOG.md`, README EN/RU/UK) driven by the **`/release` skill
  checklist**, which plays the DOCS_SURFACES.md role as a *skill* rather than a checked-in manifest file. §2's
  three accepted shapes all assume one authoritative CHANGELOG/ledger that renders out; here the source of
  truth for "what changed" is git history + the skill's fan-out (evidence: `release.yml:150`,
  `.claude/skills/release/SKILL.md:28-45`, absence of a root/`DEV` CHANGELOG).
- ADD (version cut - **a build-time date stamp drifts from the tag minute**): the csproj stamps
  `YY.M.D.HHmm` at *build* time, which is minutes off the `v*` tag it is released under, so `release.yml`
  builds with **`-p:Version=<tag>`** to pin the exe's embedded FileVersion to the tag exactly. Generalizes:
  when the authoritative version is a build-time date stamp, the tag and the stamp can disagree - the release
  build must re-pin to the tag or the in-file stamp and the asset name split (evidence: `release.yml:60-64`,
  `CyrFlip.csproj:24`).
- CONFIRM (SEO instrumentation + zero-data carve-out **boundary**): full SEO block on `docs/index.html`
  (title/description/canonical/OG/Twitter/JSON-LD `SoftwareApplication`), plus newly-added `sitemap.xml` +
  `robots.txt` - all per §3. But CyrFlip is **not** a zero-data tool: it touches keyboard + clipboard
  (sensitive), so it **does** host `docs/privacy.html` even though it is fully local. The zero-data
  `privacy.html` carve-out (filedo) applies to no-data tools; a **local-but-sensitive** input/clipboard tool
  still needs the hosted page (evidence: `docs/index.html:6-30`, `docs/sitemap.xml`, `docs/privacy.html`).

### RELEASE_AND_DISTRIBUTION.md
- ADD (a portfolio-wide **GitHub Actions cost & safety-lever** set - the concrete engineering behind the
  [PAID] tags): all repos here run on paid Windows minutes and the owner cares, so name the levers CyrFlip
  wires:
  1. **`[skip ci]` on every build commit** - `build.ps1` appends it, so a СБОРКА pushed to `main` is skipped
     natively by GitHub and costs nothing (it was already validated locally) (`build.ps1:105-109`).
  2. **`paths-ignore` on CI** - `**.md`, `docs/**`, `PLAN/**`, `winget/**`, `assets/**`, `vscode-extension/**`
     don't burn a Windows build (`ci.yml:8-25`).
  3. **`if:` skip of `release:`-prefixed commits** - the release anchor commit doesn't double-build, because
     the tag's `release.yml` already builds+tests (`ci.yml:38`).
  4. **The tag doesn't trigger CI** - `ci.yml` listens only to branch `main`; only `release.yml` runs on
     `refs/tags/v*` (`ci.yml:3-5`).
  5. **`concurrency cancel-in-progress: true` on CI** - a burst of commits costs one active run, not N
     (`ci.yml:29-31`); **`cancel-in-progress: false` on release** - different tags never cancel each other and
     a half-finished release is never aborted (`release.yml:18-20`).
- ADD (the **build/release wall enforced by commit-message convention**, not only by script capability):
  filedo/fastmediasorter_lite enforce the wall structurally (`build.ps1` physically cannot tag). CyrFlip's
  `build.ps1` *can* push to `main`, but stays free via `[skip ci]`; the billable boundary is the **`release:`
  anchor commit + the `v*` tag** produced only by `release.ps1`. A valid alternative enforcement - the wall is
  a commit-message + trigger-filter contract, not a capability boundary (evidence: `build.ps1:13-14,105-120`,
  `release.ps1:19-21,67-68`).
- ADD (release = **independent-cadence op for the companion**): the VS Code extension is published on its own
  trigger and only when it changed ("only if `vscode-extension/` changed"), so a CyrFlip release fans out into
  up to four ops, one of which (the Marketplace) is gated on a subtree diff, not on the app version. Confirms
  the "fan-out, none blocks the others" model with a companion-on-its-own-clock case (evidence:
  `release/SKILL.md:39-42,83-86`).

### REPOSITORY_LAYOUT.md
- ADD (a real `.gitignore` gotcha - **the `[Rr]elease/` build-output glob silently swallows a source folder
  named `release/`**): the build-output ignore `[Rr]elease/` also matches `.claude/skills/release/` (the
  `/release` skill's own folder), which would leave the skill untracked. CyrFlip negates it explicitly
  (`!.claude/skills/release/` + `/**`). Worth a one-line warning in "Secrets/Built binaries": a case-folded
  build-output glob can hide a legitimately-named source dir; add a negation with a why-comment (evidence:
  `.gitignore:6-9`).

### SECURITY_AND_PRIVACY.md
- CONFIRM (release ships **unsigned**): `release.yml` Authenticode-signs only when `SIGNING_CERT_BASE64` /
  `SIGNING_CERT_PASSWORD` are set; they are unset, so the shipped exe is unsigned (the Store re-signs the MSIX;
  winget/GitHub carry the unsigned zip). Matches the "store re-signs, no cert in repo" posture; the local
  `build.ps1` has the same opt-in signing via `CYRFLIP_SIGN_PFX` (evidence: `release.yml:75-76`,
  `build.ps1:69-82`).
- CONFIRM (§5 category-review + §4 promise for a **sensitive-but-local** tool): the keyboard-hook/clipboard
  keylogger-scrutiny instance (see CHANNEL_MATRIX) and the explicit "no keystroke logging, no network, no
  telemetry, no data" promise stated in the listing, the `runFullTrust` justification, and `docs/privacy.html`
  (evidence: `STORE_PUBLISHING.md:104-106,150-186`).

### LOCALIZATION.md
- CONFIRM (uniform EN/RU/UK across **every** surface): app UI (`AppConfig.UiLanguage` ru/uk/en), README
  (`README.md`/`README_RU.md`/`README_UK.md`), site (`docs/` + `docs/ru/` + `docs/uk/`), winget
  (`locale.{en-US,ru-RU,uk-UA}.yaml`), Store (`msix/store-listings.md` EN/RU/UK). A uniform-coverage
  counterpoint to StreamsPlayer's per-surface split - confirms the core's "per-surface set is its own decision"
  from the all-three-everywhere end (evidence: root `README*.md`, `winget/*.locale.*.yaml`, `docs/ru docs/uk`).

## No delta
NEW_PROJECT_CHECKLIST, DEVELOPMENT (net48 single-concern modules + `WarningsAsErrors` convention + manual
interop verification are standard; nothing beyond core), TESTING_AND_QA (xUnit for pure logic, run-the-tray-exe
for interop - the desktop device rung already in core; `/build` skill step 3 mandates it), GITHUB_INTERACTION
(working-tree-is-truth, English commits, `release.ps1` preflight on-main + clean-tree gate - all core),
AI_USAGE (per-user Claude memory + `CLAUDE.md` only, no `AGENTS.md`; `/build` + `/release` skills as the
canonical workflow - matches core §5 and the epub/filedo/streams per-user model), AUTHOR (same owner),
SUPPORT_AND_FEEDBACK (issue tracker + `serzhyale@gmail.com` in winget `PublisherSupportUrl`, site, About -
standard), SITE_CONFIGURATION (Pages from `/docs`, no CNAME - already core via filedo/streams).

## Candidate core edits - APPLIED to the core (2026-07-23, by owner "как правильно так и сделай")
All universal truths below were folded into the canonical docs (no commit/push). Where each landed:
- **VS Code Marketplace channel + the companion-editor-extension shape** -> new **PLATFORM_OVERLAYS.md
  "Companion editor / IDE extension"** section; new **VS Code Marketplace row + playbook** in
  **CHANNEL_MATRIX.md** (matrix table, overlay-usage note, per-channel playbook); glossary term in
  **README.md**; a pointer in **NEW_PROJECT_CHECKLIST.md §0**.
- **GitHub Actions cost & safety levers** + **build/release wall via commit-message convention** -> new
  **RELEASE_AND_DISTRIBUTION.md §1 "CI cost & safety levers"** subsection.
- **Build-time-date-stamp-vs-tag pin** -> **RELEASE_AND_DISTRIBUTION.md §4** (new version-cut bullet).
- **Fourth "What's new" shape** (no root CHANGELOG; git-log + `generate_release_notes`; release-skill as the
  ship-together manifest) -> **DOCUMENTATION_CONCEPT.md §2** (ledger-shapes bullet) + **§5** (surfaces-manifest
  bullet).
- **MSIX `%LOCALAPPDATA%`->`%ProgramData%` cross-process redirect** + **`msstore`-CLI / Partner-Center-program
  traps** -> **CHANNEL_MATRIX.md** MSIX playbook.
- **Keyboard-hook/clipboard = keylogger category-review** -> **CHANNEL_MATRIX.md** MSIX playbook +
  **SECURITY_AND_PRIVACY.md §5**.
- **Zero-data privacy-page carve-out boundary** (local-but-sensitive still needs the page) ->
  **DOCUMENTATION_CONCEPT.md §4** + **SECURITY_AND_PRIVACY.md §5**.
- **`[Rr]elease/` glob swallows a `release/` source dir** -> **REPOSITORY_LAYOUT.md "Built binaries"** caveat.

### Original proposals (retained for provenance)
- **CHANNEL_MATRIX.md (new row) + PLATFORM_OVERLAYS.md (Co-shipping shapes / a note near Editions)**: add the
  **VS Code Marketplace** channel and name the **companion editor-extension** shape - an in-repo,
  code-independent companion that surfaces the parent app's state via a one-way file contract, published to the
  Marketplace on its own version clock and cadence (frozen anchor = extension id `<publisher>.<name>`; auth =
  Marketplace PAT; manual `vsce publish`). Prevents mis-reading it as a co-shipped companion (same tag) or a
  full edition (parity doc). Evidence: `vscode-extension/package.json`, `LayoutPublisher.cs:11-22`.
- **RELEASE_AND_DISTRIBUTION.md (+ CHANNEL_MATRIX GitHub Release playbook)**: add the **GitHub Actions cost &
  safety levers** ( `[skip ci]` build commits; `paths-ignore`; `release:`-prefix skip; branch-only tag
  trigger; `cancel-in-progress` true on CI / false on release). Portfolio-wide, since every repo runs paid
  Windows minutes. Evidence: `ci.yml`, `release.yml`, `build.ps1`.
- **DOCUMENTATION_CONCEPT.md §2**: (a) accept a fourth "What's new" shape - **no root CHANGELOG; git-log +
  `generate_release_notes` as the ledger; a release *skill* as the ship-together manifest** fanning the notes
  to N surfaces by hand. (b) Add the **build-time-date-stamp-vs-tag** rule: pin the release CI build to the tag
  (`-p:Version=<tag>`) so the embedded stamp matches the asset name. Evidence: `release.yml:60-64,150`,
  `release/SKILL.md:28-45`.
- **CHANNEL_MATRIX.md MSIX playbook**: add the **`msstore`-CLI-fails-on-individual-accounts** fact (use
  Partner Center web) + the **"Windows" vs "Windows Desktop Applications"** program trap + the
  **`%LOCALAPPDATA%`->`%ProgramData%` cross-process file redirect** under MSIX. Evidence:
  `STORE_PUBLISHING.md:73-75,122-126`, `LayoutPublisher.cs:11-22`.
- **REPOSITORY_LAYOUT.md**: one-line warning that a case-folded build-output ignore glob (`[Rr]elease/`) can
  silently swallow a legitimately-named source dir (a `release/` skill folder); negate it with a why-comment.
  Evidence: `.gitignore:6-9`.
- **SECURITY_AND_PRIVACY.md §5**: note the zero-data `privacy.html` carve-out's **boundary** - a
  **local-but-sensitive** tool (keyboard hook / clipboard) still needs the hosted privacy page even with no
  network/telemetry; and add keyboard-hook/clipboard as a second "category draws extra Store review" instance
  beside stream players. Evidence: `STORE_PUBLISHING.md:104-106,150-186`, `docs/privacy.html`.

## Candidate NEW docs (not in any shared doc yet)
- **None required.** Every delta fits an existing doc (CHANNEL_MATRIX row + MSIX playbook, PLATFORM_OVERLAYS
  co-shipping shape, RELEASE cost-levers, DOCUMENTATION_CONCEPT ledger shape). The recurring
  `WINDOWS_PACKAGING.md` appendix idea (raised by filedo/fastmediasorter_lite) plus this repo's VS-Code-channel
  and CI-cost material would consolidate nicely if that surface keeps growing - still not warranted.

## Open questions for the owner (project-specific, not folded into core)
- **No CI tag-format gate.** `release.yml`/`release.ps1` don't validate the `v*` tag shape or parse it as a
  real date (the `^v\d{2}\.\d{4}\.\d{4}$` + `ParseExact` gate StreamsPlayer landed in core). Adopt the same
  mechanical guard for CyrFlip so a mistyped tag can't cut a bad release?
- **Three overlapping Store-listing sources.** `store/listing-{en,ru,uk}.txt`, `msix/store-listings.md`, and
  `msix/store-listing-export.csv` all carry listing copy; the `/release` skill points only at
  `msix/store-listings.md`. Which is the single source of truth - the other two are drift risk. Owner to pick
  one and mark the rest render targets.
- **VS Code extension published by hand, own clock.** No `ext-vscode-v*` tag / workflow and a separate semver
  (`0.1.1`) decoupled from the app date tag. Keep it manual, or wire a tagged trigger for a reproducible
  Marketplace publish?
- **House-style slip.** `docs/index.html:6` `<title>` uses an em-dash ("CyrFlip — fix wrong-layout text") -
  the house style is a plain hyphen (and CyrFlip is not a book-typography case that would earn the scoped
  allowlist). Fix in the touched line at the next docs edit.

## Spread-back applied 2026-07-23

Ran SPREAD_BACK_PROMPT in `p:\WINDOWS\CyrFlip`. Consumption model = **REFERENCE** (repo links to the canon,
keeps only deltas locally; no mirror).

**Changed in the repo:**
- **`CLAUDE.md`** - replaced the stale "Common project conventions (imported from FastMediaSorter_Lite)"
  section (which still claimed "release pipeline... not set up yet" and described an Inno `.exe` installer -
  both false: `build.ps1`/`release.ps1`/`ci.yml`/`release.yml` all exist and CyrFlip ships portable-zip,
  no installer) with a new "Unified Rules & release conventions" section: canon pointer, the overlay facts
  (version shape, 4 channels + site, frozen anchors, companion-extension shape), the build/release wall +
  CI cost levers, and the resolved repo decisions. Restated universal rules removed.
- **`docs/index.html:6`** - em-dash → plain hyphen in `<title>` (house-style fix).
- **`release.ps1`** - added a tag-format gate (`^\d{2}\.\d{1,2}\.\d{1,2}\.\d{4}$` + `ParseExact` on
  `yy.M.d.HHmm`) before tagging, so a mistyped `-Version` fails before any push. Verified against
  `26.7.22.1712` (pass), `26.13.40.9999`/`26.7.22` (reject).
- **`msix/store-listings.md`** - added a render-target banner naming `msix/store-listing-export.csv` as the
  single source of truth for Store-listing copy.

**Open questions closed (owner decisions, 2026-07-23):**
1. **CI tag-format gate** - owner: **yes, adopt.** Added to `release.ps1` (see above). *Remaining:* the same
   guard is not in `release.yml` (the workflow only strips the `v` prefix); could mirror it there.
2. **Three overlapping Store-listing sources** - owner: **`msix/store-listing-export.csv` is the SoT**;
   `store-listings.md` + `store/listing-*.txt` are render targets (banner added to the `.md`; `.txt` left
   un-bannered to avoid leaking a note into pasted listing fields - documented in `CLAUDE.md` instead).
   *Remaining:* the `/release` checklist (`release.ps1` step 4) + the `/release` skill still point operators
   at `store-listings.md`; repoint them at the CSV SoT (needs the owner's export→merge text-flow, so left as
   a follow-up, not silently rewired).
3. **VS Code extension publish** - owner: **keep manual** (`vsce publish`, own semver, only when the subtree
   changed). Recorded as a deliberate choice; no `ext-vscode-v*` tag/workflow.
4. **House-style em-dash** - fixed (see above).

**Verification (fresh runs, PowerShell - `dotnet` is not on the Bash tool's PATH here):**
- `dotnet build CyrFlip.sln -c Release` → **Build succeeded, 0 Warning(s), 0 Error(s)**, exit 0.
- `dotnet test CyrFlip.sln -c Release --no-build` → **Passed! Failed: 0, Passed: 53**, exit 0.

**Canon fixes needed (none blocking):** none. All CyrFlip universal deltas were already folded into the core
on 2026-07-23 (see "Candidate core edits - APPLIED" above); this spread-back only consumed them.
