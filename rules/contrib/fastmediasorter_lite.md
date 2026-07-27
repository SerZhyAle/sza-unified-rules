---
# Contribution: FastMediaSorter_Lite (overlay A; single product; dual-runtime "two exes one source tree" + co-shipped sibling program) -> Unified_Rules
Source repo: p:\WINDOWS\FastMediaSorter_Lite | Date: 2026-07-23
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

## Overlay facts (verified against this repo)

- **Source root & release-mechanics.** `src/` (VB.NET, three `.vbproj` in one `FastMediaSorter.sln`) +
  `publishing/{installer,winget,msix,store}/` umbrella + `tools/` automation. Pure Overlay A, no Go body
  (evidence: `ls src/*.vbproj src/Modern/ src/FastMediaSorterCompanion/`, `ls publishing/`).
- **Version shape (+ padding choice).** Dotted **`YY.M.D.HHmm`** (e.g. `26.7.23.1127`), the core's primary
  example. **Two exes carry the same stamp from two toolchains**: net10 via MSBuild `AutoVersion` property
  (`FastMediaSorter.Modern.vbproj:66-70`), net48 via an `UpdateVersion` target that rewrites
  `My Project\VersionInfo.vb` before compile (`FastMediaSorter.vbproj:471-481`); both accept
  `-p:ReleaseVersion=`. Store remap `YY.(M*100+D).HHmm.0` (already core).
- **Channels + listing files.** GitHub Release (`FastMediaSorter-<ver>-windows-x64-setup.exe` + `.zip`, each
  `.sha256`); winget `publishing/winget/*.yaml` -> microsoft/winget-pkgs; Microsoft Store MSIX from
  `publishing/msix/build-msix.ps1`, listing `publishing/store/listingData.csv`, **manual** Partner Center
  upload (evidence: `.github/workflows/release.yml`, the three `winget/*.yaml`).
- **Frozen anchors.** winget `PackageIdentifier: SerZhyAle.FastMediaSorter` **and `PackageName:
  FastMediaSorter LITE`** (frozen because it must equal the installed ARP DisplayName for `winget upgrade`
  to correlate - `locale.en-US.yaml:10-11`); Inno `AppId {7371E7F1-..}`, `UninstallDisplayName`
  (`= AppNameArp "FastMediaSorter LITE"`), `DefaultDirName FastMediaSorter_LITE`, `OutputBaseFilename`
  (`installer/FastMediaSorter.iss:21,35,42,47,51`); MSIX Identity `Name`/`Publisher` + reserved Store
  `DisplayName`; the frozen **exe name `FastMediaSorter_LITE.exe`**, the mutex
  `FastMediaSorterSingleInstanceMutex`, the registry hive `SZA\FastMediaSorter`, ProgIDs `FastMediaSorter.*`.
- **Editions + parity mechanism.** **None (single edition, shared source).** But it ships a **dual-runtime
  flavor**: `FastMediaSorter_LITE.exe` (net10 x64, `dotnet publish` single-file) **and**
  `FastMediaSorter_x86.exe` (net48 x86, MSBuild) side by side in one install folder, from the *same* `.vb`
  sources. Parity is enforced by **compile-time seams** (`#If NETFRAMEWORK`), not a `PARITY.md` (evidence:
  `FastMediaSorter.Modern.vbproj:13` vs `FastMediaSorter.vbproj:19,53,62`, `CLAUDE.md` "Two builds, one
  source tree"). It also **co-ships a separate program** (`FastMediaSorterCompanion.exe`, its own `.vbproj`,
  own mutex, tray host) as a sibling in every channel - a second product in one release.

## Channel-matrix rows (this project)
Format: Channel | Trigger | Cost | Auth | Signer | Listing source | Frozen anchor | Verify live
- **GitHub Release** | `v*` tag push -> `release.yml` | [PAID][PUBLIC] | `gh auth` ambient | self (`.sha256`, no cert) | release body <- CHANGELOG | - | asset downloads + checksum matches (evidence: `tools/Release.ps1 -Push` is the only tagger; defaults to DRY-RUN, `Release.ps1:9-11,41,57`).
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

## Candidate core edits - APPLIED to the core (2026-07-23, by owner "как правильно так и сделай")
All universal truths below were folded into the canonical docs (no commit/push). Where each landed:
- **Dual-runtime single-source shape** + **co-shipped companion binary** -> new **PLATFORM_OVERLAYS.md
  "Co-shipping shapes"** section (names *flavor* / *dual-runtime build variant* / *co-shipped companion
  binary*), glossary entry in **README.md**, and a pointer in **NEW_PROJECT_CHECKLIST.md §0**.
- **Anchor re-point to a new implementation** + **visible-name / anchor decoupling** -> PLATFORM_OVERLAYS.md
  four-facts intro (fact 4).
- **Compiler-as-parity-gate** + its two traps -> **DEVELOPMENT.md §13 "Single-source multi-target"**.
- **Runtime-migration compatibility pins** -> **DEVELOPMENT.md §14**.
- **winget failure-mode list** (no Scope/Dependencies/VCRedist, never single-file bootstrap zip / heavy
  portable zip, cosmetic NestedInstallerType) + **`PackageName` = ARP DisplayName** + **`MinimumOSVersion`/
  `Architecture` describe the installer** -> **CHANNEL_MATRIX.md** winget playbook.
- **One MSIX, second `<Application>` + StartupTask + FirewallRules** -> CHANNEL_MATRIX.md MSIX playbook.
- **Server/elevation feature ships OFF, gated opt-in** -> **SECURITY_AND_PRIVACY.md §3**.
- **Vendored sidecar may be committed (fresh clone works); `.gitignore` and rules file must agree** ->
  **REPOSITORY_LAYOUT.md "Built binaries"** (also subsumes FileDO's committed-own-output candidate).

### Original proposals (retained for provenance)
- **PLATFORM_OVERLAYS.md (new subsection near "Editions", or an Overlay A note)**: name the **dual-runtime
  single-source** shape - one source tree compiled by two toolchains into two exes installed side-by-side,
  the installer selecting per running OS; parity enforced by compile-time seams, not a parity doc. Distinct
  from flavor / edition / two-language-payload. Prevents this reading as either an edition (it shares
  source) or a plain flavor (two toolchains, two runtimes, two artifacts) (evidence: `build.ps1`,
  `iss:211-219`, the two `.vbproj`).
- **PLATFORM_OVERLAYS.md fourth-fact + SECURITY_AND_PRIVACY.md §2**: add that a frozen anchor ties to the
  **install location/id, not the binary's contents** - you may re-point it to a new implementation that
  installs to the same path (the net48 -> net10 in-place swap). And state the **visible name / frozen anchor
  decoupling**: rebrand the display name freely; freeze the anchor (evidence: `CLAUDE.md` "Naming rule").
- **CHANNEL_MATRIX.md winget playbook**: append the concrete failure-mode list (no `Scope`, no
  `Dependencies`/VCRedist -> `0x8A150044`; never `single-exe.zip` -> Defender `Wacapew.A!ml`; never portable
  `windows-x64.zip` -> `0x80004004`; `NestedInstallerType` note is cosmetic; read
  `InstallationVerificationLogs` for the real reason) and the **`PackageName` = ARP DisplayName** coupling +
  the mixed-floor **`MinimumOSVersion` anti-pattern**. Prevents a string of real, opaque validation aborts
  (evidence: `SPECIFICATION_WINGET_PUBLISHING.md`).
- **DEVELOPMENT.md (new short subsection: single-source multi-target)**: the compiler-as-parity-gate model
  + its two traps (the hand-defined `NETFRAMEWORK` constant; a globbed project vs an explicit-file-list
  project silently disagreeing on a new file). Sits beside §12's independent-codebase parity (evidence: the
  two `.vbproj`).
- **DEVELOPMENT.md (runtime-migration pins)**: on a runtime migration, enumerate the new runtime's changed
  defaults (DPI awareness, culture/collation ICU-vs-NLS, default font, single-file `Assembly.Location`) and
  pin the ones behaviour depended on - each is an invisible regression. Prevents a silent layout/sort/loader
  break that looks like a quality bug (evidence: `CLAUDE.md` "Modern-only compatibility pins",
  `FastMediaSorter.Modern.vbproj:60`).
- **SECURITY_AND_PRIVACY.md §3**: add the "server/elevation feature ships OFF, enabled only by an explicit,
  gated, auditable opt-in (marker file / HKCU flag / packaged manifest), one scoped UAC prompt, never
  silent" rule as the single sanctioned exception to no-firewall/no-elevation. Prevents an app silently
  opening a listening port (evidence: `ServerFeatures.vb`).
- **REPOSITORY_LAYOUT.md "Built binaries"**: broaden the vendored-sidecar exception - the sidecar **may be
  committed** via a narrow `.gitignore` negation (fresh clone works) instead of gitignored (no binary in
  history); state the trade-off. Prevents a "why is this exe tracked?" cleanup and aligns with FileDO's
  committed-output candidate (evidence: `.gitignore:8-14`).

## Candidate NEW docs (not in any shared doc yet)
- **None required.** Every delta fits an existing doc. The dual-runtime shape, the winget failure list, and
  the runtime-migration pins are all Overlay-A / DEVELOPMENT / CHANNEL_MATRIX inline additions. (If the
  Windows-packaging notes across FileDO's WiX-vs-Inno + portable-winget and this repo's winget failure list
  keep growing, a shared `WINDOWS_PACKAGING.md` appendix would consolidate them - same conclusion FileDO
  reached; still not warranted.)

## Open questions - RESOLVED into the canonical docs (2026-07-23, by owner instruction)
- **Name the dual-runtime shape** -> RESOLVED. Named **"dual-runtime build variant"** in PLATFORM_OVERLAYS.md
  "Co-shipping shapes" + README glossary; distinguished from flavor / edition / co-shipped companion.
- **Co-shipped sibling program** (also raised by FileDO's GUI) -> RESOLVED. Named **"co-shipped companion
  binary"** in the same PLATFORM_OVERLAYS section + glossary; the one-MSIX-two-`<Application>` mechanics
  landed in CHANNEL_MATRIX.md. FileDO's "two-language payload" is the same shape under this name.

## Open questions for the owner (project-specific, not folded into the core)
- **Stale CLAUDE.md vs live `.gitignore`**: the FMS rules file says the worker is gitignored / absent on a
  fresh clone, but the live `.gitignore` negation commits it. The **universal** rule ("`.gitignore` and the
  rules file must agree; a claim of gitignored-while-committed is drift to fix") landed in
  REPOSITORY_LAYOUT.md, but the concrete CLAUDE.md fix is a project edit outside this collection phase - fix
  the rules file to say "committed", or revert to gitignored? (Owner's call; not a core-doc change.)

## Spread-back applied 2026-07-23

Ran SPREAD_BACK_PROMPT in `p:\WINDOWS\FastMediaSorter_Lite`. Consumption model = **REFERENCE** (the rules
file links to the canon and keeps only FMS deltas; the two pre-canon `docs/guides/` originals are marked as
downstream mirrors rather than re-authored). FMS is the reference project the Overlay A core was extracted
from, so this spread-back mostly *consumed* rules that already originated here - the work was adding the
canon pointer, fixing one live drift, and stamping the ancestor docs.

**Changed in the repo (docs-only; no source touched):**
- **`CLAUDE.md`** - inserted a new "## Unified Rules & release conventions" section after the Naming-rule
  block: canon pointer (`P:\WEB\...\Unified_Rules`, Overlay A, "reference project the core was extracted
  from"), REFERENCE consumption note, pointer to `contrib/fastmediasorter_lite.md`, and a compact list of the
  six FMS-owned deltas that were folded into the core on 2026-07-23 (dual-runtime build variant, anchor
  re-point + visible-name decoupling, runtime-migration pins, winget failure list + `PackageName`=ARP,
  server-feature gated opt-in, committed vendored sidecar) - each cross-linking the canon doc that now owns
  it and the local section that shows it. No universal rules were re-authored into the file.
- **`CLAUDE.md` drift fix (open question #1, owner: option A)** - the two stale claims that the Go worker is
  "gitignored / a fresh clone has no Share feature" were corrected to "**committed** via a narrow `.gitignore`
  negation, so a fresh clone **has** the Share feature", matching the live `.gitignore:8-14` and the
  deliberate fresh-clone-works choice. This closes the sole owner open question in this record.
- **`docs/guides/REPOSITORY_LAYOUT.md` + `docs/guides/DOCUMENTATION_CONCEPT.md`** - added a downstream-mirror
  banner to each (HTML comment: `Downstream mirror of Unified_Rules @ ed69f27 on 2026-07-23`, naming the
  canonical path as source of truth). Owner chose the banner over thin stubs or leave-as-is, so the many
  cross-links from `docs/README.md` and specs stay intact while the files are honestly marked stale-vs-canon.

**Open questions closed (owner decisions, 2026-07-23):**
1. **Stale CLAUDE.md vs live `.gitignore`** - owner: **fix the rules file to say "committed"** (option A).
   Applied above; `.gitignore` left as-is (it deliberately commits the worker).
2. **Consumption model for the two `docs/guides/` originals** - owner: **downstream-mirror banner** (keep full
   text, stamp source-of-truth), not thin stubs and not leave-untouched. Applied.

**Verification (fresh runs, Bash tool):**
- `git diff --stat` -> 3 files, all Markdown: `CLAUDE.md` (+18/-2), the two `docs/guides/` mirrors (+2 each).
  **No source (`*.vb`/`*.vbproj`/`*.ps1`) touched**, so the dual-toolchain `build.ps1` is unaffected and was
  not re-run (it would prove nothing about a docs-only change; the last commit `dc96965` already built).
- House-style gate on added lines: `git diff -U0 | grep '^\+' | grep -E '—|\.\.\.'` -> **CLEAN** (no em-dash,
  no triple-dot).

**Canon fixes needed (none blocking):** none. Every FMS universal delta was already folded into the core on
2026-07-23 (see "Candidate core edits - APPLIED" above); this spread-back only consumed them. Marked the
Done column `[x]` for FMS in `SPREAD_BACK_PROMPT.md` (canon left uncommitted for the owner's canon session +
`tools/check-rules.ps1` gate).
