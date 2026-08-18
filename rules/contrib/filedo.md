---
# Contribution: FileDO (Overlay A distribution on an Overlay C Go source body; single edition) -> Unified_Rules
Source repo: P:\WINDOWS\FileDo | Date: 2026-07-23
Read: README, NEW_PROJECT_CHECKLIST, REPOSITORY_LAYOUT, DOCUMENTATION_CONCEPT, PLATFORM_OVERLAYS,
RELEASE_AND_DISTRIBUTION, CHANNEL_MATRIX, DEVELOPMENT, TESTING_AND_QA, GITHUB_INTERACTION, AI_USAGE,
AUTHOR, LOCALIZATION, SECURITY_AND_PRIVACY, SUPPORT_AND_FEEDBACK, SITE_CONFIGURATION.
---

FileDO is a Windows-first Go **CLI** (storage speed test, fake-capacity/counterfeit-flash detection,
secure wipe, fill, duplicate management) shipping through the **Overlay A desktop channels** (GitHub
Release + winget + Microsoft Store) plus a direct-download MSI, with a co-shipped **VB.NET GUI**. Same
A-on-C family as `epub_2_html`, but the packaging choices differ: **WiX MSI** (not Inno), **portable-in-zip
winget** (not a setup.exe), **committed build artifacts** by design, and a **single `release.ps1`** that
fans out all channels from one `v*` tag.

> **Resolved since this contrib's first pass** (folded into the core by the epub reconcile, now deduped
> out of the deltas below): A-distribution-on-a-C-source-body and the optional `publishing/` umbrella
> (PLATFORM_OVERLAYS Overlay A); version digit-padding as a per-project frozen choice (same);
> curated-public-notes vs verbatim-CHANGELOG and the `DEV/` umbrella (DOCUMENTATION_CONCEPT §2,
> REPOSITORY_LAYOUT); `CHANNEL_MATRIX.md` now exists. What remains below is only still-live.

## Overlay facts (verified against this repo)

- **Source root & release-mechanics.** Go, Overlay-C-shaped but **not** idiomatic `internal/`: four
  `cmd/<binary>/` mains (`filedo`, `filedo-check`, `filedo-fill`, `filedo-test`) + shared **top-level**
  packages `fileduplicates/`, `helpers/`, `capacitytest/`; `go.mod` module `filedo`. **Multi-module** (4
  `go.mod`/`go.sum`). Release-mechanics are top-level channel siblings (no `publishing/`): `winget/`,
  `msix/`, `packaging/wix/`, committed `exe_to_download/`; two root scripts `build.ps1` (BUILD, never
  tags) + `release.ps1` (RELEASE, only tagger) (evidence: `AGENTS.md:3-4`, `git ls-files '*go.mod'` -> 4,
  root `ls`, `RELEASE.md`).
- **Version shape (+ padding choice).** Bare **separator-less** `yyMMddHHmm` (e.g. `2606120121`) - a
  continuous 10-digit integer, monotonic and sortable without any dots. Git tag `v<stamp>`; stamped via
  Go `-ldflags "-X main.version="`. Two mechanical remaps: MSIX `YY.(M*100+D).HHmm.0`
  (`msix/build-msix.ps1:87-93`), PE `VS_VERSIONINFO` `YY.MM.DD.HHmm` via `goversioninfo`
  (`release.yml:62-75`) (evidence: `build.ps1:50`, `winget PackageVersion "2606120121"`).
- **Channels + listing files (all from one `v*` tag via `release.ps1`).** (1) GitHub Release:
  `FileDO-<ver>-windows-x64.zip` **and** `.msi`, each `.sha256` (`release.yml:150-213`). (2) winget:
  `winget/SerZhyAle.FileDO*.yaml`, `wingetcreate submit` -> microsoft/winget-pkgs; installer is
  **`InstallerType: zip` / `NestedInstallerType: portable`**, 5 `PortableCommandAlias`
  (`installer.yaml:6-18`). (3) Microsoft Store: MSIX from `msix/build-msix.ps1`, listing
  `msix/store-listing.md`, **manual** Partner Center upload, Store re-signs an unsigned package.
- **Frozen anchors.** winget `PackageIdentifier: SerZhyAle.FileDO`; **WiX MSI `UpgradeCode`
  `4d6b3b1f-7c8e-4a25-9f1d-8e3b2c5a7d91`** + `HKLM\Software\FileDO` (the MSI update-to-install tie,
  Inno-`AppId` role); MSIX Identity `Name`/`Publisher` (placeholders -> Partner Center, defaults
  `SerZhyAle.FileDO` / `CN=SerZhyAle`); Go module `filedo`; the 5 `PortableCommandAlias` names (the
  on-PATH surface) (evidence: `winget/SerZhyAle.FileDO.yaml:4`, `packaging/wix/FileDO.wxs:8,52-57`,
  `msix/AppxManifest.xml:26-30`, `installer.yaml:8-18`).
- **Editions + parity mechanism.** **None - single edition.** The VB.NET GUI (`filedo_win_vb/`,
  `filedo_win.exe`) is **not** an edition (no independent release trigger/cadence, no parity doc): it is
  a **second-language companion binary co-shipped in the same release** (same zip/MSI/MSIX, same `v*`
  tag). It is also not a *flavor* (not one codebase, build-time variants). This is a third co-shipping
  shape the vocabulary does not name yet (evidence: `build.ps1:88-112`, `release.yml:138-148`,
  `msix/AppxManifest.xml:51-83` ships both `filedo.exe` + `filedo_win.exe` in one package).

## Channel-matrix rows (this project)
Format: Channel | Trigger | Cost | Auth | Signer | Listing source | Frozen anchor | Verify live
- **GitHub Release** | `v*` tag push -> `release.yml` | [PAID CI-min are free (public repo), but [PUBLIC]/irreversible] | `gh auth` ambient | self (`.sha256`, no cert) | auto `generate_release_notes` + README "Version History" | - | `gh release view v<stamp>`; zip+MSI+sha present (evidence: `release.yml:1-22,196-213`).
- **winget** | `release.ps1` syncs `winget/*.yaml` then `wingetcreate submit` -> PR | [PUBLIC] | `gh auth token` | Microsoft re-hosts | `winget/*.yaml` (committed) | `PackageIdentifier SerZhyAle.FileDO` | `winget show SerZhyAle/FileDO` after merge (evidence: `RELEASE.md:76-80`, `SKILL.md:78-80`).
- **Microsoft Store (MSIX)** | **manual** Partner Center upload of `msix/out/FileDO_<ver>.msix` | [PUBLIC] | Partner Center console | **Store re-signs** (unsigned upload) | `msix/store-listing.md` | MSIX Identity `Name`+`Publisher` | dashboard shows version; update over prior MSIX (evidence: `RELEASE.md:72-74`, `build-msix.ps1:184-188`).
- **Direct MSI** (sub-asset of the GitHub row, not its own channel) | built in `release.yml` | [PUBLIC] | - | unsigned (SmartScreen reputation) | - | WiX `UpgradeCode` | install + update-over-prior verifies the UpgradeCode (evidence: `release.yml:165-194`, `packaging/wix/FileDO.wxs:15`).

## Deltas by document

### PLATFORM_OVERLAYS.md
- DIVERGE/CORRECT (installer is a role, not Inno): Overlay A's `publishing/` tree still hard-names
  `installer/ Inno Setup script (.iss)` and its fourth fact lists only Inno anchors. FileDO ships a **WiX
  v5 MSI** (`packaging/wix/FileDO.wxs`); its anchor is the WiX **`UpgradeCode` GUID** (+ `HKLM\Software\
  FileDO`), and the MSI does the Inno jobs itself (system-`PATH` entry, Start-menu shortcut, ARP
  metadata). Name the *role* (product-id + upgrade-code + uninstall/ARP + PATH/shortcut), list Inno **or**
  WiX as the tool (evidence: `packaging/wix/FileDO.wxs:4-15,26-58`).
- DIVERGE (winget can be portable-in-zip): Overlay A's "Distribution channels" assumes a
  `<App>-<version>-<platform>-setup.exe`. FileDO's winget row is **`InstallerType: zip` /
  `NestedInstallerType: portable`** with 5 `PortableCommandAlias` - the *same* release zip serves both
  direct download and winget, and there is no second installer to maintain for a multi-exe CLI (evidence:
  `installer.yaml:6-18`).
- CORRECT (a third version shape - separator-less): the core now lists dotted `YY.M.D.HHmm` and
  `YY.MMDD.HHmm` as the padding choices; FileDO's authoritative tag is **`yyMMddHHmm` with no separators
  at all** (a plain sortable integer), structure added only in the remaps. The rule "monotonic + sortable,
  frozen once" holds; the separator itself is free (evidence: `build.ps1:50`, `RELEASE.md:22-27`).
- ADD (co-shipped second-language companion): a product may ship **two binaries in different source
  languages inside one release** (Go CLI + VB.NET GUI, one zip/MSI/MSIX, one tag) - not a *flavor* (one
  codebase) and not an *edition* (independent release/cadence/parity doc). The Editions section covers
  independent-release siblings; this "one release, two-language payload" case is unnamed (evidence:
  `msix/AppxManifest.xml:51-83`, `release.yml:84-148`).

### REPOSITORY_LAYOUT.md
- DIVERGE (a repo may commit its OWN build output): the "Built binaries" policy has only a
  *vendored-sidecar-from-another-repo* exception. FileDO deliberately force-tracks its own
  `exe_to_download/*.exe` (`.gitignore` negates the global `*.exe` ignore with a why-comment "all of them
  must be committed"); `release.ps1` commits refreshed binaries. The authoritative release is still the
  GitHub asset - this committed set is a dev/local-distribution convenience + the home of the shipped
  `.bat` helpers (evidence: `.gitignore:7-9`, `git ls-files exe_to_download/`, `RELEASE.md` step 3).
- ADD (shipped `.bat` command shortcuts): `filedo_cd/clean/fill/speed/test.bat` are packaged assets
  beside the exes, copied into both the zip and the MSI - a CLI-ergonomics payload the taxonomy has no
  slot for (evidence: `packaging/wix/FileDO.wxs:96-110`, `release.yml:134`).

### DOCUMENTATION_CONCEPT.md
- DIVERGE (changelog is localized and embedded, with no separate ledger): §2 now accepts "verbatim root
  CHANGELOG" **or** "internal ledger -> curated public notes". FileDO fits neither cleanly: there is **no
  ledger file** (the source is `git log <lastTag>..HEAD`), and the curated note is written **into each
  localized README's "Version History"** in that language - so the ledger is *localized*, which
  LOCALIZATION §1 says to keep English. A third accepted shape: "git-log-derived, curated straight into
  the localized READMEs, no standalone CHANGELOG" (evidence: `.claude/skills/release/SKILL.md:28-57`; no
  root `CHANGELOG.md`).
- DIVERGE (privacy source for a zero-data CLI): §4-5 make a **hosted `privacy.html` mandatory**. FileDO
  ships none; being a local tool with no network/telemetry/accounts, its privacy promise lives in the
  **Store data declaration + `msix/store-listing.md` + in-app text**. For a no-data, no-site tool the
  Store's own declaration can be the single source; a hosted page adds nothing to render from (evidence:
  `msix/store-listing.md` "makes no network connections.. collects no personal data"; no `privacy.html`).

### DEVELOPMENT.md
- ADD (Go-on-Windows release hardening - portable, not project-specific): build with **`-trimpath`,
  `CGO_ENABLED=0`, and keep debug symbols** - the workflow deliberately omits `-s -w` because stripping
  "correlates with higher AV heuristic false-positive rates for Go binaries" (a false SmartScreen/AV flag
  is a real distribution defect); embed PE version info + app manifest via `goversioninfo` (evidence:
  `release.yml:84-132`).
- ADD (multi-module Go cache trap): a repo with N `go.mod` must enumerate **every** `go.sum` in
  `actions/setup-go` `cache-dependency-path`, or the key falls back to root `go.sum` and misses on every
  run. FileDO also mixes Go versions across its 4 modules (1.24.4 / 1.21), resolved via
  `go-version-file: go.mod` (evidence: `release.yml:44-51`; the four `go.mod`).
- CONFIRM: the build/release wall is structural - `build.ps1` HARD RULE "must never create or push a `v*`
  tag"; only `release.ps1` tags (evidence: `build.ps1:6-14`).

### TESTING_AND_QA.md
- ADD (destructive-tool persona QA inverts the happy-path): the persona test in §6 assumes "the happy
  path reaches a result with zero mandatory configuration". For a tool whose **core job destroys data**
  (wipe/fill), the pass condition inverts: `wipe` must demand typing `WIPE`; `--force`/`-y` skips only the
  *prompt*, never the *safety checks* on drive/share roots, reparse points, and system TEMP; writes at the
  system drive `C:` are redirected to `%TEMP%\FileDO_Operations`. "Refuses to destroy the wrong thing" is
  the defect line, not friction (evidence: `README.md:27-31`, `docs/spec-safety-speed-improvements.md`
  §1).
- ADD (a data-loss bug becomes a permanent invariant): the duplicate-finder's hash cache must key on
  path + size + **modtime**; keying on size alone let a same-size edited file reuse a stale hash and be
  deleted as a false duplicate - §9 "recurring defect -> permanent guard" applied to a data-loss path
  (evidence: `docs/spec-safety-speed-improvements.md` §2, `README.md:42-45`).
- CONFIRM (known-red, scoped and named): root `go test ./...` is known-broken (fmt/vet debt), so the gate
  runs a scoped `go test ./cmd/filedo-test` + a smoke-run asserting the built exe prints the stamped
  version - the "track known-broken explicitly so a real regression isn't masked" rule in practice
  (evidence: `AGENTS.md:14`, `build.ps1:137-164`).

### GITHUB_INTERACTION.md / CHANNEL_MATRIX.md
- ADD (winget-pkgs CRLF gate): winget-pkgs **rejects LF/mixed line endings** (`Validation-Line-Endings-
  Error`); edit manifests in place CRLF-preserving (`[System.IO.File]::ReadAllText/WriteAllText`), never
  `sed`. Belongs in the CHANNEL_MATRIX winget playbook next to "local-install-test first" (evidence:
  `docs/how-i-posted-this-project-to-winget.md`).
- ADD (two silent CI traps): a **0-byte / malformed workflow file auto-disables all Actions** (paused
  this repo's CI for weeks), and **a `v*` tag push then silently no-ops** (no retry) - a release looks
  "pushed" while nothing ran. Verify Actions is enabled before trusting a tag trigger (evidence:
  `docs/how-i-posted-this-project-to-winget.md` lessons 1-2).
- ADD (why the MSI exists): a store catalog that **requires an installable `.exe`/`.msi`** (not ZIP-only)
  forced adding the WiX MSI - a channel's asset-type requirement can drive a whole packaging path
  (evidence: `docs/github-store-submission.md`).
- CONFIRM (single-product release fan-out from one tag): `release.ps1` runs one `v*` tag -> GitHub CI ->
  winget sync+submit -> MSIX build, one manual Partner Center tail. The RELEASE_AND_DISTRIBUTION
  "fan-out per edition/channel" holds here with a single edition and one orchestrator (evidence:
  `RELEASE.md` steps 1-9).

### LOCALIZATION.md
- ADD (one ISO code per language across **all** surfaces, not just the site): §3 mandates consistent ISO
  codes *site-wide*. FileDO uses non-ISO **`ua`** in READMEs (`README.ua.md`) but ISO **`uk`** in the GUI
  string table (`Localization.vb Languages = {en, ru, uk, de, fr}`) - same language, two codes, one
  product. Extend the rule to "one code per language across every surface (README, site, UI)" (evidence:
  `README.ua.md`; `filedo_win_vb/Localization.vb`).
- ADD (a valid non-resource string model with English fallback): the GUI localizes via a flat
  `key|value` table read at runtime with **English fallback** for any missing key, persisted in
  `HKCU\Software\FileDO\GuiLang` - not the §2 parity-enforced resource (a missing key degrades to English,
  it does not fail a build). A legitimate lighter model for a small GUI (evidence:
  `filedo_win_vb/Localization.vb`).
- DIVERGE (locale set): ships EN/RU/**UA**/FR/DE - adds FR+DE beyond the portfolio's EN/RU/UK; parity is
  honest-partial (`README.de.md` has no Version History and is skipped) (evidence: root `ls README.*`,
  `.claude/skills/release/SKILL.md:40-42`).

### SECURITY_AND_PRIVACY.md
- DIVERGE (§2 anchor list): "winget/Inno/MSIX identity" omits the MSI case; add the **WiX MSI
  `UpgradeCode`** as the installer-product anchor when the desktop app ships an MSI instead of Inno
  (evidence: `packaging/wix/FileDO.wxs:8`).
- ADD (full-trust justification is a listing artifact): a broad desktop capability (`runFullTrust`, raw
  `\\.\PhysicalDrive` access) needs a one-sentence justification written for the Store's ~1000-char
  capability field, kept in the listing source - the "name each permission in one sentence" rule realized
  as a Partner Center free-text field, not a manifest list (evidence: `msix/store-listing.md`,
  `AppxManifest.xml:47-49`).
- ADD (least-privilege at the unpackaged layer): `cmd/filedo/app.manifest` runs
  `requestedExecutionLevel level="asInvoker"` (only `probe` asks admin, when it needs raw-LBA access) +
  `longPathAware=true` - the Windows analogue of an in-context runtime permission (evidence:
  `cmd/filedo/app.manifest`).
- CONFIRM: no signing material tracked; MSIX unsigned (Store re-signs); `-SelfSign` is local-test only
  with `*.pfx`/`*.cer` git-ignored (evidence: `.gitignore:104`, `build-msix.ps1:159-183`).

### SITE_CONFIGURATION.md
- DIVERGE (Pages source is `/docs`): the live site serves **from `docs/`** (no root `index.html`) at
  `serzhyale.github.io/FileDO/` - plain static (`docs/.nojekyll`, `_config.yml` = `theme: null`), no
  `CNAME`. Overlay A and this doc still say "served from repo root"; `/docs` is a valid Pages source and
  should be recorded. The SZA kit is **mirrored** to `docs/kit/sza-kit.css` (evidence: root `ls`,
  `ls docs/`, `docs/_config.yml`, `docs/.nojekyll`).

### AI_USAGE.md
- DIVERGE (agent-rules file + skill home): the rules file is **`AGENTS.md`** (no `CLAUDE.md`); in-repo
  skills (`.claude/skills/{build,release}/SKILL.md`) exist but **`.claude/` is git-ignored**, so they are
  local-only, not team-shared through git as the doc's memory model assumes. Durable memory is Claude
  Code's per-user store (evidence: `AGENTS.md`, `.gitignore:75-76`, `.claude/skills/`).

### SUPPORT_AND_FEEDBACK.md
- DIVERGE (empty templates): the support path (issue tracker + `serzhyale@gmail.com`) is wired into
  winget `PublisherSupportUrl`, WiX `ARPHELPLINK`, and the Store listing, but
  `.github/ISSUE_TEMPLATE/{bug_report,feature_request}.md` + `pull_request_template.md` are **0-byte
  placeholders** - present but unrealized (evidence: `ls -l .github/ISSUE_TEMPLATE/`).

## No delta
NEW_PROJECT_CHECKLIST, RELEASE_AND_DISTRIBUTION (single-edition fan-out confirmed above), AUTHOR (same
owner profile these rules were written from).

## Candidate core edits - APPLIED 2026-07-23 (per owner "как правильно так и сделай")
Where each landed (some were already folded by the concurrent `FastMediaSorter_Lite` reconcile):
- Installer-as-a-role + WiX `UpgradeCode` anchor -> **APPLIED** PLATFORM_OVERLAYS Overlay A (publishing
  tree + fourth fact) + SECURITY_AND_PRIVACY §2.
- winget portable-in-zip -> **APPLIED** PLATFORM_OVERLAYS Overlay A "Distribution channels" (CHANNEL_MATRIX
  winget playbook already carried the `zip`+`portable` form).
- Committed-own-output exception -> **ALREADY FOLDED** in REPOSITORY_LAYOUT "Built binaries" (narrow
  negation + why-comment) by the concurrent reconcile.
- Separator-less version shape (`yyMMddHHmm`) -> **APPLIED** PLATFORM_OVERLAYS Overlay A version shape.
- Go/desktop release hardening -> **APPLIED** DEVELOPMENT §16 (new subsection; renumbered from §15 in the 2026-07-23 dedup pass).
- Destructive-action persona clause -> **APPLIED** TESTING_AND_QA §6.
- Zero-data privacy carve-out -> **APPLIED** DOCUMENTATION_CONCEPT §4 + SECURITY_AND_PRIVACY §5.
- winget CRLF gate -> **ALREADY FOLDED** in CHANNEL_MATRIX winget playbook; Actions-disabled/tag-no-op trap
  -> **APPLIED** CHANNEL_MATRIX GitHub Release playbook.
- `/docs` as a Pages source -> **APPLIED** PLATFORM_OVERLAYS Overlay A "Site" + SITE_CONFIGURATION §1;
  one-ISO-code-per-language-across-every-surface -> **APPLIED** LOCALIZATION §3.
- Co-shipped-companion vocabulary -> **ALREADY FOLDED** in PLATFORM_OVERLAYS "Co-shipping shapes" (names
  FileDO's GUI directly); the compile-time-parity variant is DEVELOPMENT §13.

Original proposals (kept as the record):
- **PLATFORM_OVERLAYS.md Overlay A (source-root/publishing tree + fourth fact) & SECURITY_AND_PRIVACY.md
  §2**: name the installer by **role**, not tool - "Inno Setup `.iss` **or** WiX MSI (`.wxs`)"; list the
  MSI **`UpgradeCode` GUID** (+ ARP/PATH/shortcut) as an accepted frozen anchor alongside Inno `AppId`.
  Prevents a valid WiX-based desktop app reading as non-compliant (evidence: `packaging/wix/FileDO.wxs`).
- **PLATFORM_OVERLAYS.md Overlay A "Distribution channels" + CHANNEL_MATRIX.md winget playbook**: note
  winget may ship a **portable-in-zip** (`InstallerType: zip` / `NestedInstallerType: portable`, N
  `PortableCommandAlias`) - the release zip doubles as the winget artifact for a multi-exe CLI; no
  separate installer manifest. Prevents forcing a setup.exe where a portable CLI needs none (evidence:
  `installer.yaml:6-18`).
- **REPOSITORY_LAYOUT.md "Built binaries & artifacts"**: add a second exception - a repo **may
  deliberately track its own build output** (a committed dev-distribution set) if `.gitignore` declares
  it with a why-comment; the authoritative release is still the release-host asset, never this copy.
  Prevents a cleanup deleting shipped files and a reviewer flagging intent as a leak (evidence:
  `.gitignore:7-9`).
- **PLATFORM_OVERLAYS.md version shape**: broaden the padding note - the authoritative stamp may also be
  **separator-less** (`yyMMddHHmm`, a sortable integer); separators are a free choice as long as the form
  is monotonic, sortable, and frozen once. Prevents a third real shape reading as a divergence (evidence:
  `build.ps1:50`).
- **DEVELOPMENT.md (new short subsection, Go/desktop release hardening)**: keep debug symbols (avoid
  `-s -w`) to reduce AV false-positives, `-trimpath`, `CGO_ENABLED=0`, embed PE versioninfo/manifest; for
  a multi-module repo list every `go.sum` in the CI cache key. Prevents a false-positive AV flag and
  silent cache misses (evidence: `release.yml:44-51,120-124`).
- **TESTING_AND_QA.md §6 (persona QA)**: add a **destructive-action clause** - for a tool whose core job
  destroys data, the happy-path pass condition inverts to "the confirmation fires and cannot be
  force-bypassed for dangerous targets". Prevents shipping a data-loss footgun that "passed" a
  zero-friction test (evidence: `README.md:27-31`, `docs/spec-safety-speed-improvements.md` §1).
- **DOCUMENTATION_CONCEPT.md §4-5 (privacy)**: carve out that a **zero-data-collection local tool with no
  site** may use the Store's own data declaration + listing copy + in-app text as the privacy source of
  truth; no hosted `privacy.html` is required, but the promise must still be stated in the listing and
  app. Prevents demanding an empty page that renders nothing (evidence: `msix/store-listing.md`).
- **CHANNEL_MATRIX.md winget playbook**: add the **CRLF line-ending** requirement (winget-pkgs rejects
  LF/mixed) and edit-in-place method; add a GitHub-Actions note that a **malformed/0-byte workflow
  disables Actions** and a tag push then silently no-ops. Prevents two real, hard-to-diagnose release
  failures (evidence: `docs/how-i-posted-this-project-to-winget.md`).
- **SITE_CONFIGURATION.md §1 + PLATFORM_OVERLAYS.md Overlay A "Site"**: record **`/docs` as an accepted
  Pages source** (with `.nojekyll` for hand-authored static), not only repo root. Prevents a docs-served
  site reading as "unpublished staging" (evidence: `docs/.nojekyll`, no root `index.html`).
- **LOCALIZATION.md §3**: strengthen to **one ISO code per language across every surface** (README, site,
  UI), not just site-wide. Prevents the `ua`-in-README vs `uk`-in-GUI split (evidence: `README.ua.md`,
  `Localization.vb`).

## Candidate NEW docs (not in any shared doc yet)
- **None required.** Every FileDO delta fits an existing doc via the surgical edits above. If the
  installer-role + winget-portable + Go-hardening notes grow, a short **`WINDOWS_PACKAGING.md`** appendix
  (Inno-vs-WiX, setup.exe-vs-portable-zip, MSIX two-app package, PE stamping) could consolidate them - but
  it is not warranted yet; keep them inline in the overlay + DEVELOPMENT.

## Open questions - RESOLVED 2026-07-23 (by owner instruction)
- **Privacy page** -> **RESOLVED into the core.** DOCUMENTATION_CONCEPT §4 + SECURITY_AND_PRIVACY §5 now
  carry a zero-data carve-out: a no-network, no-telemetry local tool with no site may use the store's data
  declaration + listing copy + in-app text as the privacy source of truth; no hosted `privacy.html`
  required. FileDO is compliant as-is.
- **Naming the co-shipped GUI** -> **RESOLVED into the core** (by the concurrent reconcile).
  PLATFORM_OVERLAYS "Co-shipping shapes" names it a **co-shipped companion binary** (one release, one tag,
  a sibling program - not a flavor, not an edition) and cites FileDO's GUI directly.
- **Committed `exe_to_download/`** -> **RESOLVED at the rules level.** REPOSITORY_LAYOUT "Built binaries"
  now permits deliberately committing a repo's own build output under a narrow `.gitignore` negation with a
  why-comment (FileDO satisfies this). Whether to *keep* the set now that CI rebuilds from source is a
  project-cleanup decision, no longer a compliance question - **owner's call, not a rules gap.**
- **Localized changelog** -> **left as a project choice, not folded.** The canon stays: LOCALIZATION §1
  keeps ledgers English; DOCUMENTATION_CONCEPT §2 accepts a curated public "What's new". FileDO's
  git-log-derived, per-README **localized** "Version History" is a project-specific variant that does not
  generalize, so it was **not** promoted to the core - **owner decides** whether FileDO keeps it or moves
  to one English source rendered per locale (evidence: `.claude/skills/release/SKILL.md:38-53`).

## Open questions for the owner (still open)
- None. The one live decision (localized "Version History" vs one English source) was **resolved by the
  owner on 2026-07-23: migrate to an English-source-rendered-per-locale changelog** (see Spread-back
  below). The migration itself is a scheduled follow-up, not yet executed.

## Spread-back applied 2026-07-23
Ran `SPREAD_BACK_PROMPT.md` in `P:\WINDOWS\FileDO` (existing repo; this contrib read first).

**What changed (in the repo).** Rewrote the single agent-rules file `AGENTS.md` to the **reference**
consumption model:
- Added the canon pointer (`P:\WEB\sites.google.comsiteszaodua\Unified_Rules`, read order, and a link to
  this contrib record as the per-project source of overlay facts + divergences).
- Added a condensed **overlay-facts** block (source root / multi-module / version shape `yyMMddHHmm` /
  release-mechanics siblings / frozen anchors) verified live: WiX `UpgradeCode
  4d6b3b1f-...-8e3b2c5a7d91`, winget `PackageIdentifier SerZhyAle.FileDO`, 5 `PortableCommandAlias`, Go
  1.24.4/1.21 across 4 `go.mod`.
- Stripped restated universal Go conventions (tabs/mixedCaps/lowerCamelCase/file-naming prose) down to
  "Go defaults via gofmt" + the repo-specific `*_windows.go`/`*_unsupported.go` split.
- Recorded the two live divergences inline (AGENTS.md-only, no CLAUDE.md; `.claude/skills/` git-ignored)
  and pointed universal git discipline at canon `GITHUB_INTERACTION.md`.

**Verification (evidence, fresh run 2026-07-23).**
- `go build -o filedo.exe .\cmd\filedo` -> exit **0**.
- Scoped gate `go test ./...` in `cmd/filedo-test` -> **ok** (exit 0, no tests to run).
- Known-red confirmed: root `go test ./...` -> exit **1**, `FAIL filedo/cmd/filedo [build failed]`
  (non-constant format string in `damaged_disk_handler.go`, `fmt.Sprintf %T` arg mismatch in `main.go`).
  The gate's smoke path is `filedo.exe -?` matching the stamped version (`build.ps1:141-149`).
- Working tree after the doc edit: only `AGENTS.md` modified (root `filedo.exe` is git-ignored).

**Questions closed.** The localized-changelog decision -> owner chose **migrate to one English source,
rendered per locale**. Not executed this session; it is a scheduled repo follow-up (rework the `/release`
skill's "Version History" generation + the per-language READMEs). Until then FileDO still emits localized
`Version History` (a temporary, now-owned divergence, not a permanent one).

**What remains.**
- Execute the changelog migration above (separate FileDO session).
- Pre-existing repo debt, out of spread-back scope: root `go test ./...` fmt/vet failures; 0-byte
  `.github/ISSUE_TEMPLATE/*` + `pull_request_template.md`.

**Canon edits still needed (NOT committed from the repo session - owner to apply in a canon session):**
- Mark FileDO's **Done** column in `SPREAD_BACK_PROMPT.md` after this repo's spread-back commit lands.
- No new rule fixes: every candidate core edit from this contrib was already APPLIED on 2026-07-23, and the
  changelog decision conforms FileDO to the existing canon (LOCALIZATION §1) rather than changing it.

## Canon adoption 2026-07-27

Adopted as the `sza` plugin (consumption model **reference**). `.sza-canon.json`: overlay C, co-shipped
companion, separator-less `yyMMddHHmm` tag, ledger shape 4 verified against `generate_release_notes` in the
release workflow, four channels.

**Scoped commit**: `.gitignore`, `docs/index.html` and the stamp. `AGENTS.md` and the untracked `CLAUDE.md`
carried in-flight work and were left alone.

**The one error left is the sharpest real finding in the portfolio**: FileDO ships to the Microsoft Store and
winget and has a live Pages site, so neither privacy carve-out applies - and it hosts no privacy page at all.
`msix/store-listing.md` still carries it as an unfulfilled TODO. This is a store-rejection risk and needs
content, not an edit.

## Canon reconcile 2026-08-02 - agent-process propagation

Canon **2026.07.27 -> 2026.08.02**, core digest `sha256:dae220bf..` -> `sha256:6c247452..`. Stamp
updated; the adoption model is unchanged. The upstream change is [AI_USAGE.md](../AI_USAGE.md) only -
the agent-process findings propagated from FastMediaSorter mob_v2 under its ticket S1342 - so the
staleness ladder's "re-read only the changed rule docs" path applies and no full re-adoption was run.
Nothing in `rules/` touched packaging, release, channels or layout, and no divergence was found
between the new bullets and this repo's own rules file.

No agent memory and no competing agent-behaviour text in either rules file, so this is a pure stamp
move. §2's closure invariants are the live ones: this repo's release path is a single one-way
operation, and "PASS only when every gate passed" is exactly the property that path needs.

Verification: `check-compliance: FileDo - 0 error(s), 4 warning(s) (overlay C, canon 2026.08.02)` - warnings are pre-existing and none was introduced here.

## Canon reconcile 2026-08-05 - measurement channels and ungated routing

Canon **2026.08.02 -> 2026.08.05**, core digest `sha256:6c247452..` -> `sha256:8d33fdab..`. Stamp updated;
the adoption model is unchanged. Upstream: [AI_USAGE.md](../AI_USAGE.md) §3 and §5, plus the `agent-cost`
skill, which sits outside the digest. Two findings from the FastMediaSorter mob_v2 process retrospective of
2026-08-05, recorded in full in [fastmediasorter_mob_v2.md](fastmediasorter_mob_v2.md) - **consumption
cannot be counted by tool name** (a `Read`-only scan of an artifact that is also edited, searched or opened
through the shell watches the smallest channel; the reference figure moved from 42% to 3.8% once every
channel was counted) and **a size-tier command ladder written as prose does not route anything** (434
invocations, the cheapest tier chosen 0 times; the remedy is an advisory `UserPromptSubmit` nudge, kept
always-exit-0, with no saving claimed yet). The staleness ladder's "re-read only the changed rule docs" path
applies, no full re-adoption was run, and nothing in `rules/` touched packaging, release, channels or layout.

No command surface here - two skills, no `.claude/commands/`, no hooks - so finding 2 has no local target
and nothing is owed. Finding 1 is method, not packaging or release, so it changes nothing in this repo's
shape either; it applies the next time anything here is called unused.

Verification: `check-compliance: FileDo - 0 error(s), 4 warning(s) (overlay C, canon 2026.08.05)` -
warnings are pre-existing and none was introduced here.

## Canon reconcile 2026-08-18 - the stale-cache catch-up

Canon **2026.07.27 -> 2026.08.18.1**, core digest `sha256:dae220bf..` -> `sha256:961c9c8a..`, recomputed
here rather than copied (`check-compliance.ps1 -PrintDigest`). Consumption model unchanged (**reference**).

**Why this is a four-update jump and not a one-step move.** The `sza` plugin served a cached
**2026.07.27** build for three weeks, so the 08-02, 08-05, 08-08 and 08-18 canon updates never reached a
session in this repo. The plugin is now **2026.818.1**.

**The record contradicted the repo, and the repo won.** The two sections above - *Canon reconcile
2026-08-02* and *Canon reconcile 2026-08-05* - both state "Stamp updated". **The stamp was never updated.**
`git log --follow -- .sza-canon.json` in `P:\WINDOWS\FileDo` returns exactly two commits, `697508d` and
`0460b6a`, both dated 2026-07-27, both carrying `"version": "2026.07.27"`. Those two reconciles were
recorded in the canon repo and never landed in the consumer repo, and this record asserted a repo-side fact
that the repo contradicted for a fortnight. Working-tree-is-truth applies to this file too: **a reconcile
section should cite the consumer-repo commit that carried the stamp**, and one that cannot is a claim, not
a record.

**Re-read and reconciled** - only the docs whose content moved since 2026.07.27:

- **[AI_USAGE.md](../AI_USAGE.md) section 1 - fire-and-forget is now forbidden**, with the threshold set at
  the harness's foreground timeout. Live target here: the `/build` skill drives `build.ps1 -Test`, which is
  a gate, and a backgrounded gate reports its wrapper's exit code. The skill now says so and requires the
  foreground. Every gate run for this reconcile was foreground.
- **[AI_USAGE.md](../AI_USAGE.md) section 2 - the three closure invariants.** This is where the repo
  genuinely diverged. `build.ps1 -Test` satisfied invariants 1 and 2 - the verdict covers all four binaries,
  and `Test gate passed.` prints only after both checks - but **failed invariant 3**: a missing Go toolchain
  or a missing artifact was reported as exit 1, indistinguishable from a real defect, and `go test` output
  went to `Out-Null` so a failure was undiagnosable. Fixed: **exit 2 = "could not verify", exit 1 = "found a
  defect"**, the toolchain check moved **ahead of the builds** (DEVELOPMENT section 10 - environment before
  work, not after; inside the gate it would have been dead code, since a missing Go surfaces as build errors
  first), and failing test output is now printed. `release.ps1:95` tests `-ne 0`, so exit 2 still stops a
  release.
- **[AI_USAGE.md](../AI_USAGE.md) section 5 - the canon ships its hooks; do not rebuild them per project.**
  `.claude/settings.json` in this repo carries a single `permissions.allow` entry and **no hook
  registrations**, so there is nothing repo-side to disarm. Recorded in `AGENTS.md` so a later session does
  not hand-wire a local copy. The hook family is demonstrably live: the plugin's `guard-bash` blocked an
  unbounded directory scan during this session. **But see the machine-level duplication below** - the rule
  has a live violation, just not in this repository.
- **[DEVELOPMENT.md](../DEVELOPMENT.md) section 15 - caching the expensive gate's CLEAN verdict.**
  **Not applicable, and recorded rather than skipped silently.** The rule targets a static-analysis gate that
  was 86% of gate wall time; FileDO's gate is a compile plus a smoke-run, about a minute wall clock including
  the GUI MSBuild step, with no serialisation lock to queue behind. A fingerprint cache here would save
  nothing. The section's other half did apply - "verify which path is actually used" - see the console-text
  defect below.
- **[GITHUB_INTERACTION.md](../GITHUB_INTERACTION.md) section 6 - the Bash/tooling family.** The
  highest-value section for this repo, whose two entry points are both `.ps1`. `AGENTS.md` now states the
  `pwsh -NoProfile -File` routing for a Bash caller instead of only the bare `.\build.ps1` form, without
  restating the rule the hook already enforces. "Every tool call gets a fresh interpreter" needed no repo
  change - nothing here depends on shell state surviving a call.
- **[INVARIANTS.md](../INVARIANTS.md) - unchanged since adoption.** `git log 7dd3dde..HEAD` returns nothing
  for it. The plugin-cache copy and the canon-repo copy differ by byte only because the cache ships **CRLF**
  and the repo **LF**; content-identical after `tr -d '\r'`. Worth knowing before anyone builds a byte
  comparison between the two trees.

**A defect the reconcile surfaced on its own.** `build.ps1` printed `go test ./cmd/filedo-test ...` while
actually running `Push-Location cmd\filedo-test; go test ./...`. The printed form **cannot work** - that
directory is its own module, so from the root it fails with *main module (filedo) does not contain package*
- and `AGENTS.md` had documented the trap for months while the script kept advertising the broken form on
every green run. The `/build` skill had copied the broken form from that console line. Both fixed; the
script now prints the command it runs.

**Agent-rules trim.** `AGENTS.md` lost the restatements that have exactly one home in the canon: commit
language, message shape, the co-author trailer, and the evidence rule - the whole `## Commit & PR` section
collapsed to the two genuine deltas (verification output in the body, screenshots for GUI/installer/docs).
The build/release wall was rewritten from a restated universal ("HARD RULE: never creates a tag") into the
checkable repo fact - `build.ps1` contains no `git tag` call at all, `release.ps1` holds it at lines 130-131
- and carries a `canon-ok` marker for the part that still reads like a restatement. `CLAUDE.md` was itself
violating this repo's own recorded divergence: it is meant to be a bare pointer and had grown a duplicate of
the tag rule and the testing-gate delta. Now a true pointer. Every kept claim was re-verified against the
tree; the tag regex `^v\d{10}$` is confirmed at `release.ps1:77`.

**Closed from the 2026-07-27 section.** "It hosts no privacy page at all", called the sharpest real finding
in the portfolio, is **resolved**: `docs/privacy.html` landed in `0460b6a` on 2026-07-27 and
`msix/store-listing.md` now carries the live URL instead of a TODO. The gate has reported 0 errors since.

**Warnings: 4 -> 0.** All four were real and all four are fixed, not exempted. `docs/README.md` now indexes
the tree and separates the site from the unlinked repo documents; `docs/robots.txt` and `docs/sitemap.xml`
were added, the sitemap listing the **6 canonical pages only** - the `ru/ua/de/fr` index files are redirect
stubs that canonicalise to the root, and listing a non-canonical redirect is what makes a sitemap lie;
`docs/index.html` gained a JSON-LD `SoftwareApplication` block modelled on the one `docs/privacy.html`
already carried. `docs/` has **no generator**, so these are edits in place and not render-target violations
(invariant 16) - confirmed by grep, not assumed.

**Verification** - fresh runs, this session:

- `pwsh -File tools/check-compliance.ps1` - baseline `0 error(s), 4 warning(s)`, final
  `0 error(s), 0 warning(s) (overlay C, canon 2026.08.18.1)`, exit **0**.
- `.\build.ps1 -Test` - exit **0**, `Test gate passed.` Run twice: once before the environment-check move,
  once after.
- `pwsh -NoProfile -Command "$env:PATH='C:\Windows\System32'; & build.ps1 -Test"` - exit **2**,
  `Cannot verify: 'go' is not on PATH - nothing was built or checked.` The new exit code is proven by
  driving it, not by reading it.
- The gate runs restamped the tracked binaries in `exe_to_download/`; restored with
  `git checkout -- exe_to_download/` so the commit carries only the intended change.

**Carried forward, not closed:**

- `.sza-canon.json` `site.pages` lists `index.html` and `privacy.html` while Pages serves **6** canonical
  pages - the four `guides/` pages are absent. Left alone this pass because the owner declared the stamp
  correct and off-limits; it wants a decision on whether `pages` is meant to be exhaustive or indicative.
- The in-repo skills under `.claude/skills/` are git-ignored, so this session's `/build` skill fix is
  **local-only and cannot be committed**. Every machine has its own copy and none of the others got this
  fix. The divergence is now explicit in `AGENTS.md`, but the underlying problem - a corrected skill that
  cannot travel - is unresolved.
- **Machine-level hook duplication, owner decision, not applied.** `~/.claude/hooks/` holds a complete
  hand-wired copy of the canon family - `guard-find-command.ps1`, `guard-ps1-in-bash.ps1`,
  `guard-bash-unavailable-command.ps1`, `guard-fire-and-forget.ps1`, `guard-uncapped-read.ps1`,
  `warn-context-size.ps1` - registered in the user-level `settings.json` and running **alongside** the
  plugin's own. AI_USAGE section 5's precondition for removing them is satisfied and was checked, not
  assumed: the installed cache at `sza/2026.818.1/hooks/` really does carry `guard-bash.ps1` (the five
  Bash gates batched behind one pre-filter), `guard-fire-and-forget.ps1` and `guard-uncapped-read.ps1`.
  Both families fired in this session. This is outside the repository, so it is reported rather than
  changed.

**Canon fixes needed - NOT applied from this session:**

1. **The staleness ladder cannot detect its own staleness.** A consumer reading a stale plugin cache
   computes a digest that matches its own stamp and reports a clean bill of health - exactly what happened
   here for three weeks across four canon updates. The ladder compares the stamp against the *installed*
   canon, never against the *published* one. Consider having `check-compliance` surface the plugin build it
   read, so "healthy" and "healthy but three weeks behind" stop looking identical.
2. **A reconcile section in `contrib/` should cite the consumer-repo commit that carried the stamp.** The
   08-02 and 08-05 sections here asserted a stamp move that never happened, and nothing caught it because
   the record is prose. Same "a claim is not a record" shape the canon already applies to gates.
3. **The hook pre-filters match prose, not command position.** Both the plugin's batched pre-filter and the
   hand-wired one test the raw payload for a bare substring, so a heredoc that merely *discusses* a
   directory scan is blocked as though it were one - it happened twice while writing this very section, and
   the canon's own guidance is that a pre-filter "may only skip calls the real check would have allowed",
   which says nothing about the false-positive direction. Anchoring on command-head position would cost
   nothing and remove a class of dead turns.
4. Minor: the plugin cache ships **CRLF** and the canon repo **LF**, so a naive byte comparison between the
   two trees reports every rule doc as differing. Worth one line wherever the two are compared.
