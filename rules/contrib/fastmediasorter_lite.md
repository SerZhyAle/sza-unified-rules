---
# Contribution: FastMediaSorter_Lite - Fast Media Sorter & Sharing for Windows (FMS_Win): a media and file manager, a local sharing and scheduling service and a Media Exchange Server, three optional parts of one product (overlay A; dual-runtime "two exes one source tree" + co-shipped Share Manager) -> Unified_Rules
Source repo: p:\WINDOWS\FastMediaSorter_Lite | Date: 2026-07-23 (header and "Overlay facts" corrected in place 2026-10-26, FMS_Win ticket 273; every dated section below is history and is not rewritten)
Read: README, NEW_PROJECT_CHECKLIST, REPOSITORY_LAYOUT, DOCUMENTATION_CONCEPT, PLATFORM_OVERLAYS,
RELEASE_AND_DISTRIBUTION, CHANNEL_MATRIX, DEVELOPMENT, TESTING_AND_QA, GITHUB_INTERACTION, AI_USAGE,
AUTHOR, LOCALIZATION, SECURITY_AND_PRIVACY, SUPPORT_AND_FEEDBACK, SITE_CONFIGURATION; contrib/epub_2_html.md,
contrib/filedo.md.
---

FastMediaSorter_Lite is the **reference project the Overlay A core was extracted from**, so most of its
shape is already the canonical text (`publishing/` umbrella, dotted `YY.M.D.HHmm` date tag, GitHub +
winget + Store, MSIX `YY.(M*100+D).HHmm.0` remap, build-vs-release wall, committed manifests). Those are
**CONFIRM, deduped out below.** What remains is this repo's genuinely uncaptured experience: it ships
**two exes built from one source tree by two toolchains** (a shape the vocabulary does not yet name),
co-ships a **separate companion program** in every channel, and it is where the concrete **winget
failure-mode list** and the **frozen-anchor-vs-visible-name decoupling** were learned.

> **Keep this note in the record.** Current facts, edited in place. Never append a dated section to this file:
> what happened and when goes to the file of the same name under `history/`
> ([the rules of that folder](history/README.md)), which is not reading for a task. A delta the core absorbed,
> a candidate that was applied or refused and a question that was answered are deleted here; the history
> section of that day says what became of them.

## Overlay facts (verified against this repo; corrected in place 2026-10-26, ticket 273)

- **What the product is.** *Fast Media Sorter & Sharing for Windows* (FMS_Win; repository
  `FastMediaSorter_Lite`) is one product of **three optional parts, always in this order** (owner decision
  2026-10-26; machine source `tools/site-facts.json` `positioning`, human source `docs/guides/POSITIONING.md`):
  (1) a **media and file manager** - views and sorts photos and videos with one key per file and manages
  files in local folders, on SFTP and SMB servers and on the devices of an exchange account (the file
  manager mode of the Grid panel, F3); (2) a **local sharing and scheduling service** - the Share Manager and
  its Go SFTP worker share folders over SFTP (QR pairing for Android; FileDO disk hosting is a capability of
  sharing, never a part of its own), run file operations on a schedule and connect this PC to an exchange
  account; (3) the **Media Exchange Server** - a server the user runs, to which their devices enroll in an
  account and through which they reach each other. Each part is optional and none is the core of another.
  The words photo sorter, image viewer and video player are search keywords only (`discoverability`), never
  the definition. The register of what the product does, with a state and evidence per row, is
  `capabilities` in the same data file; the retired definitions are its `retiredPhrases`.
- **Source root & release-mechanics.** `src/` (VB.NET, three `.vbproj` in one `FastMediaSorter.sln`) +
  `publishing/{installer,winget,msix,store}/` umbrella + `tools/` automation, **and two Go bodies that are
  parts of the same tree, not a second overlay**: the Media Exchange Server in `exchange-server/` (own
  `go.mod`, `cmd/`, `internal/`; its release step is held shut by `INCLUDE_EXCHANGE: 'false'` in
  `.github/workflows/release.yml`, so no package carries it) and the SFTP worker, built in the sibling
  repository `fms_companion` and vendored as `payload/companion/fms-share-worker.exe`. Overlay A (evidence:
  `ls src/*.vbproj src/Modern/ src/FastMediaSorterCompanion/ exchange-server/ payload/companion/`,
  `ls publishing/`).
- **Version shape (+ padding choice).** Dotted **`YY.M.D.HHmm`** (e.g. `26.10.25.1830`, the published tag
  `v26.10.25.1830`), the core's primary example. **Two exes carry the same stamp from two toolchains**: net10
  via MSBuild `AutoVersion` property (`FastMediaSorter.Modern.vbproj`, `AutoVersion`, lines 65-68), net48 via
  an `UpdateVersion` target that rewrites `My Project\VersionInfo.vb` before compile
  (`FastMediaSorter.vbproj`, target `UpdateVersion`, line 1128); both accept `-p:ReleaseVersion=`. Store
  remap `YY.(M*100+D).HHmm.0` (already core).
- **Channels + listing files.** GitHub Release (`FastMediaSorter-<ver>-windows-x64-setup.exe`, the `.zip`
  and the Server edition's `FastMediaSorter-<ver>-windows-x64-server-setup.exe`, each `.sha256`); winget
  `publishing/winget/*.yaml` and `publishing/winget/server/*.yaml` (two packages) -> microsoft/winget-pkgs;
  Microsoft Store MSIX from `publishing/msix/build-msix.ps1` (two `<Application>` entries: the viewer and the
  Share Manager), listing `publishing/store/listingData.csv` (13 locales, written by `Build-ListingData.ps1`),
  **manual** Partner Center upload; the Inno installers under `publishing/installer/`. The Media Exchange
  Server has no channel: its packaging cell reads "Not in this package" (evidence:
  `.github/workflows/release.yml`, the `winget/*.yaml` files, `tools/site-facts.json` `availability`).
- **Release ledger (`RELEASE-LEDGER` 0.1).** `docs/releases/` (`channels.json`, `builds.json`, `history.jsonl`,
  rendered `RELEASES.md`), written through `tools/harness.ps1 releases/release-ledger` and
  `tools/lib/ReleaseLedgerHook.ps1`. Four packages: `user` (`github`, `winget`, `installer`), `user-msix`
  (`msstore`, split for its remapped `YY.(M*100+D).HHmm.0` version), `server` (`winget-server`,
  `installer-server`), and `exchange-server` (no channels while gated). Build scripts record `test` (or
  `release` on unsigned Store MSIX / `Release.ps1 -Push`) non-fatally.
- **Frozen anchors.** winget `PackageIdentifier: SerZhyAle.FastMediaSorter` **and `PackageName:
  FastMediaSorter LITE`** (frozen because it must equal the installed ARP DisplayName for `winget upgrade`
  to correlate - `locale.en-US.yaml`, `PackageName`, line 17); Inno `AppId {7371E7F1-..}`,
  `UninstallDisplayName` (`= AppNameArp "FastMediaSorter LITE"`), `DefaultDirName FastMediaSorter_LITE`,
  `OutputBaseFilename` (`installer/FastMediaSorter.iss:41,55,62,67,79`); MSIX Identity `Name`/`Publisher` +
  reserved Store `DisplayName`; the frozen **exe name `FastMediaSorter_LITE.exe`**, the mutex
  `FastMediaSorterSingleInstanceMutex`, the registry hive `SZA\FastMediaSorter`, ProgIDs `FastMediaSorter.*`.
  The visible product name is `Fast Media Sorter & Sharing for Windows` (`#define AppName`, line 16); only
  the visible name moves, never an anchor.
- **Editions + parity mechanism.** **One public edition besides the full package: the Server edition**
  (the local sharing and scheduling service as a Windows service; own installer `FastMediaSorterServer.iss`,
  own winget package `SerZhyAle.FastMediaSorter.Server`, own Inno `AppId`); it is a packaging and host-mode
  variant of the same source tree, ships off the same `v*` tag and carries no tag prefix of its own, and it
  never installs the Media Exchange Server. The product also ships a **dual-runtime flavor**:
  `FastMediaSorter_LITE.exe` (net10 x64, `dotnet publish` single-file) **and** `FastMediaSorter_x86.exe`
  (net48 x86, MSBuild) side by side in one install folder, from the *same* `.vb` sources. Parity is enforced
  by **compile-time seams** (`#If NETFRAMEWORK`), not a `PARITY.md` (evidence: `FastMediaSorter.Modern.vbproj:13`
  vs `FastMediaSorter.vbproj:19,53,62`, `CLAUDE.md` "Two builds, one source tree"). It also **co-ships a
  separate program** (the Share Manager, `FastMediaSorterCompanion.exe`: its own `.vbproj`, own mutex, tray
  host) as a sibling in the full package - the host of part 2.

## Channel-matrix rows (this project)
Format: Channel | Trigger | Cost | Auth | Signer | Listing source | Frozen anchor | Verify live
- **GitHub Release** | `v*` tag push -> `release.yml` | [PAID] [PUBLIC] | `gh auth` ambient | self (`.sha256`, no cert) | release body <- CHANGELOG | - | asset downloads + checksum matches (evidence: `tools/Release.ps1 -Push` is the only tagger; defaults to DRY-RUN, `Release.ps1:9-11,41,57`).
- **winget** | `wingetcreate submit publishing/winget` -> PR to microsoft/winget-pkgs | [PUBLIC] | `gh` + one-time CLA | Microsoft re-hosts | `publishing/winget/*.yaml` (committed) | `PackageIdentifier` **+ `PackageName` = installed ARP DisplayName** | `winget install --manifest` then `winget search` after merge (evidence: PR #386820 noted in `installer.yaml:2`).
- **Microsoft Store (MSIX)** | **manual** Partner Center upload | [PUBLIC] | Partner Center console | **Store re-signs** (unsigned upload) | `publishing/store/listingData.csv` | MSIX Identity `Name`+`Publisher` + reserved `DisplayName` | dashboard shows version; update over a prior MSIX (evidence: `build-msix.ps1`, `msix/AppxManifest.xml`).

## Deltas by document

### PLATFORM_OVERLAYS.md
- ADD (a fourth co-shipping shape - **dual-runtime, one source tree, two toolchains**): distinct from
  *flavor* (one codebase, build-time variants of ONE artifact), *edition* (independent codebases, parity
  doc), and FileDO's *two-language payload* (two source languages). Here **one `.vb` source set** compiles
  into **two exes via two toolchains** (`dotnet publish` net10 x64 single-file + `msbuild` net48 x86),
  installed **side by side in one folder**, and the installer picks which one the shortcut/associations
  target **by the running OS** (`UseModernExe`: Win10 build >=14393 -> mainline, older -> x86). Neither is
  shippable alone; `msbuild` never produces the mainline (evidence: `FastMediaSorter.sln` 3 projects,
  `build.ps1` runs both toolchains, `installer/FastMediaSorter.iss:211-219` `UseModernExe`/`UseLegacyExe`).
- ADD (**a frozen anchor can be re-pointed to a new implementation** without orphaning installs): the
  `.NET 10` migration reassigned the frozen exe name `FastMediaSorter_LITE.exe` from the net48 build to the
  new net10 mainline (it replaces the installed exe **in place**, same path, so settings/associations/ARP/
  winget+Store update-correlation carry over); the old net48 build took a **new** name
  `FastMediaSorter_x86.exe`. Rule refinement: an anchor is tied to the *install location/id*, not the
  binary's contents - you may swap the implementation behind it (evidence: `CLAUDE.md` "Naming rule",
  `iss` `AppExeName`).
- ADD (**visible name and frozen anchor are decoupled surfaces**): a "light rebrand" changed the
  user-visible display name on every surface (`AppName "Fast Media Sorter for Windows"`) while every
  channel kept ONE frozen technical anchor for update-correlation - Inno `AppName` (wizard) rides on top of
  a pinned `UninstallDisplayName`/`AppNameArp "FastMediaSorter LITE"` (ARP); winget `ShortDescription`
  refreshed but `PackageName` frozen; Store listing Description refreshed but `DisplayName` frozen. You can
  rebrand the name without touching the anchor (evidence: `iss:16,21,42`, `locale.en-US.yaml:10-11`).

### DEVELOPMENT.md
- ADD (a distinct parity model - **the compiler is the parity gate**, not a `PARITY.md` + drift script):
  §12 covers independent-codebase editions kept in sync by a parity doc + value/structural gates. This
  repo's two exes share **one** source, so parity is enforced at compile time: divergences live behind
  `#If NETFRAMEWORK` seams and a shared-source change that breaks the other runtime **fails the build**
  (`BC30451`). **Two hard traps this model has that a parity doc does not:** (1) the constant is defined by
  hand - old-style projects don't get `NETFRAMEWORK` implicitly, so `FastMediaSorter.vbproj` sets
  `<DefineConstants>NETFRAMEWORK=True</DefineConstants>` in **both** configs; delete/typo it and every seam
  silently compiles the wrong branch, no error (`FastMediaSorter.vbproj:58-62,75`). (2) The old-style
  project carries an **explicit `<Compile Include>` list** (71 entries) while the SDK project globs
  `..\**\*.vb`; a new file is picked up only by the mainline, so a file **nothing references yet is
  silently absent from the x86 exe** until added to the list by hand (evidence:
  `FastMediaSorter.Modern.vbproj:101` glob vs `grep -c '<Compile Include' FastMediaSorter.vbproj` = 71).
- ADD (**runtime-migration compatibility pins** - a new runtime silently flips defaults): porting a
  pixel-tuned WinForms app net48 -> net10 changes three invisible defaults, each a visible regression that
  must be pinned back to the reference build: **DPI awareness** (net10 defaults SystemAware; the shipped
  net48 exe never embedded `app.manifest` so DpiUnaware is the reference - `ApplyApplicationDefaults` pins
  `HighDpiMode.DpiUnaware` + `Microsoft Sans Serif 8.25` instead of Segoe UI 9); **culture/collation**
  (.NET 5+ uses ICU, net48 uses NLS - pinned `System.Globalization.UseNls=true` so `abc`/`xyz` file sorting
  matches; `FastMediaSorter.Modern.vbproj:60`); single-file publish empties `Assembly.Location`, breaking
  loaders that read it (Tesseract `CustomSearchPath`). Generalize: **on a runtime migration, enumerate the
  new runtime's changed defaults and pin the ones the UI/behaviour depended on** (evidence: `CLAUDE.md`
  "Modern-only compatibility pins").

### CHANNEL_MATRIX.md
- ADD (**winget failure-mode list** - hard-won, each a real validation abort; complements FileDO's CRLF +
  workflow-disable traps): point winget at the **Inno `setup.exe` directly (`InstallerType: inno`) with NO
  `Scope`, NO `Dependencies`, NO `NestedInstallerType`.** Concretely - **don't declare
  `Microsoft.VCRedist.2015+.x64`** (dependency-resolution loop, aborts `0x8A150044`; the app installs fine
  undeclared); **don't add `Scope: user`** (forces `--scope user`, aborts `0x8A150044` "no suitable
  installer"); **never point winget at the self-extracting `single-exe.zip`** (Defender ML persistent false
  positive `Program:Script/Wacapew.A!ml`); **don't use the portable `windows-x64.zip`** (`InstallerType:
  zip`+`NestedInstallerType: portable` - the ~99 MB payload aborts `0x80004004` after extraction); the
  "Missing `NestedInstallerType`" note is a **cosmetic** `Validation-Guide`, not a failure. Get the real
  reason from the build's `InstallationVerificationLogs` artifact, not the generic bot comments (evidence:
  `docs/specifications/done/SPECIFICATION_WINGET_PUBLISHING.md:13,25,59-66`, `installer.yaml:2-4`).
- ADD (**winget `PackageName` must equal the installed ARP DisplayName**): the winget update key correlates
  by matching `PackageName` to the ARP ("Add/Remove Programs") DisplayName the installer wrote. Rename the
  visible product but keep `PackageName` (and the Inno `UninstallDisplayName` it mirrors) frozen, or
  `winget upgrade` stops seeing installed copies. The matrix's winget row should name this coupling
  (evidence: `locale.en-US.yaml:10-11`, `iss:20-21,42`).
- ADD (**winget `MinimumOSVersion` is an anti-pattern for a mixed-floor installer**): the setup.exe is
  `Architecture: x64` but installs a 32-bit net48 sibling too and serves Windows 7/8.1 (installer
  `MinVersion=6.1`); declaring `MinimumOSVersion: 10.0.14393` would wrongly **hide the package from the
  machines the sibling exists for**. Architecture/floor in the manifest describe the *installer*, not the
  narrowest exe inside it (evidence: `installer.yaml:6-12`).
- ADD (**one MSIX package can carry a second `<Application>`**): the Store package ships both the viewer and
  the companion as two `<Application>` entries in one `AppxManifest.xml`, with the autostart moved to a
  `uap5:StartupTask` (an HKCU Run write is silently virtualized away inside the MSIX container) and a
  `desktop2:FirewallRules` element (the manifest equivalent of the installer's firewall opt-in) (evidence:
  `msix/AppxManifest.xml:65,107,121-122,135`).

### SECURITY_AND_PRIVACY.md
- ADD (**the one owner-approved scoped exception to "no firewall / no elevation", made explicit and
  gated**): exposing folders over SFTP + punching a Windows Firewall hole is a deliberate admin-level act,
  so the entire server surface is **dormant until an explicit, never-silent opt-in**. `IsEnabled()` is true
  only when one of: an elevated-installer **machine marker file** `companion\server-features.enabled`, a
  deferred **HKCU flag** `Share_ServerFeaturesEnabled=1` (set after one UAC prompt that adds a
  program-scoped inbound allow for the worker exe), or **packaged** (Store, firewall via manifest). The
  privileged step is one UAC prompt, program-scoped, logged - never a background elevation (evidence:
  `src/FastMediaSorterCompanion/Core/ServerFeatures.vb:11-52`,
  `docs/specifications/done/SPECIFICATION_SHARE_SERVER_OPTIN_INSTALL.md`). Generalizes §3 to: **a feature
  that opens a network port or needs elevation ships OFF and is enabled only by an explicit, gated,
  auditable user action.**

### REPOSITORY_LAYOUT.md
- CORRECT/refine (**a vendored sidecar may be COMMITTED, not only gitignored**): the "Built binaries"
  vendored-exception says keep the prebuilt sidecar under a **gitignored** `payload/` and document that a
  fresh clone lacks it. This repo instead **commits** the worker via a narrow `.gitignore` negation
  (`!payload/companion/fms-share-worker.exe` + `.sha256`), so a fresh clone **has** the Share feature - at
  the cost of tracking a ~binary from another repo. Both are valid; the choice is "fresh-clone-works" vs
  "no binary in history". (Note: `CLAUDE.md` still says the worker is gitignored and a clone lacks it - that
  text is stale vs the live `.gitignore`.) Reinforces FileDO's "a repo may deliberately track build output"
  candidate (evidence: `.gitignore:8-14`, `git ls-files payload/` -> worker tracked).

### PLATFORM_OVERLAYS.md (Cross-project contracts)
- CONFIRM (consumer/producer side of a frozen contract): this repo **consumes** the `.fmscfg` contract
  owned by `fms_companion` (Overlay C reference) but **builds the export on its own side**
  (`ShareConfigBuilder`) rather than via the worker's `ExportConfig`, so it can advertise a
  manually-forwarded router port / schema-v2 per-root params the worker can't. Confirms the "producer frozen
  at shipped shape, consumer forward-tolerant" rule from a real second-repo vantage (evidence: `CLAUDE.md`
  "Android Folder Share", `SPECIFICATION_ANDROID_FOLDER_SHARE.md`).

## No delta
NEW_PROJECT_CHECKLIST, DOCUMENTATION_CONCEPT (this repo is the reference: root Keep-a-Changelog English,
publishing/ umbrella, durable-URL CTAs - all already core), RELEASE_AND_DISTRIBUTION (build/release wall +
coverage gate are the owner rules these docs were written from; `Release.ps1` dry-run default confirms),
TESTING_AND_QA (manual sweep in both exes, already core), GITHUB_INTERACTION (working-tree-is-truth,
co-author trailer, dry-run tagger - core), AI_USAGE (per-user Claude memory, same as epub), AUTHOR (same
owner these rules describe), LOCALIZATION (EN/RU/UK READMEs + site, already core), SITE_CONFIGURATION
(Pages from root - the Overlay A default), SUPPORT_AND_FEEDBACK (`AppFileLogger` current.log intake -
standard).

## Open questions for the owner (project-specific, not folded into the core)
- **Stale CLAUDE.md vs live `.gitignore`**: the FMS rules file says the worker is gitignored / absent on a
  fresh clone, but the live `.gitignore` negation commits it. The **universal** rule ("`.gitignore` and the
  rules file must agree; a claim of gitignored-while-committed is drift to fix") landed in
  REPOSITORY_LAYOUT.md, but the concrete CLAUDE.md fix is a project edit outside this collection phase - fix
  the rules file to say "committed", or revert to gitignored? (Owner's call; not a core-doc change.)
