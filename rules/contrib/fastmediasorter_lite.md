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

## Canon adoption 2026-07-27

Adopted as the `sza` plugin (consumption model **reference**), committed. `.sza-canon.json`: overlay A,
dual-runtime + co-shipped-companion shapes, Keep-a-Changelog ledger, four channels, `packages/` declared as
vendored tooling.

The fact most worth recording: **Pages serves this repo from the root**, so `docs/index.html` is an
unpublished staging copy, not a second live page. The stamp now says so, which is what stops the next agent
from editing the decoy.

Compliance gate: **0 errors**, 8 warnings. Still open: the two `docs/guides/` mirrors carry the old SHA-form
banner and want re-stamping in the digest form; the live root page has no privacy link while the unpublished
`docs/` copy does.

## Canon reconcile 2026-08-02 - agent-process propagation

Canon **2026.07.27 -> 2026.08.02**, core digest `sha256:dae220bf..` -> `sha256:6c247452..`. Stamp
updated; the adoption itself is unchanged (consumption model **reference**, overlay A).

**What actually changed upstream:** [AI_USAGE.md](../AI_USAGE.md) only, in five sections - the
agent-process findings propagated from FastMediaSorter mob_v2 under its ticket S1342. Nothing in
`rules/` touched Windows packaging, the release flow, the channel matrix or anything else this project
depends on, so the staleness ladder's "re-read only the changed rule docs" path applies and a full
re-adoption was not run.

**Divergence check against this repo's shape - none found, and two of the new bullets are inert here.**

- The rules file references the canon rather than restating it, and carries no agent-behaviour section
  of its own, so there was nothing to reconcile. Grep for the new subjects - backgrounding thresholds,
  context reporting, subagent policy, memory discipline - returns only product code in this repo's
  `CLAUDE.md`, no competing rule text.
- **§4 persistent memory is inert:** this project has no `.claude/agent-memory/` at all. The budget,
  expiry and no-restatement rules cost it nothing and constrain nothing today. They apply the moment an
  agent memory appears here, which is the right time for them to arrive, so they were not carved out.
- **§3's session-boundary bullet is close to inert too**, for the reason S1342 §3 item 7 predicted: this
  repo's agent sessions are short. It is kept because the harness constraint it states - an agent cannot
  reset its own context - is a fact worth knowing before someone designs around the opposite.
- **The two bullets that do bite here** are §1's two-sided backgrounding threshold and §2's closure
  invariants. Both are directly applicable: this project runs a dual-toolchain build where a fast check
  and a full publish sit on opposite sides of any sensible threshold, and its compliance gate is exactly
  the kind of script the three invariants govern.

**Verification:** `pwsh -File tools/check-compliance.ps1 -RepoRoot <FMS_Lite>` - expected 0 errors,
actual **0 errors, 10 warnings**, all pre-existing and none introduced by this reconcile (`CLAUDE.md`
size, `...` in three files, the missing `robots.txt` / `sitemap.xml` / JSON-LD on the site surface, and
the two `docs/guides/` mirrors still carrying the old SHA-form banner recorded in the 2026-07-27 entry
above). The warning count moved 8 -> 10 through checks added upstream since that entry, not through
anything changed here.

This is the "at least one other project has adopted and reported the result" gate in S1342 §5. The
remaining eight stamped repos - CyrFlip, EPUB_2_HTML, FileDo, OneClickRunner, Streams_Player,
internal_IP_manager, the hub site and universal-agent-kit - are still on the previous digest and each
needs its own pass.

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

No command surface here - two skills, no `.claude/commands/`, no hooks - so finding 2 has no local target.
Finding 1 is the one that bears on this repo: it shares a product line with mob_v2, so a cost or usage
number measured on one and quoted about the other is exactly the claim the channel-union rule exists to
stop.

The tail of the 2026-08-02 entry above named eight repos still on the previous digest. All ten stamped
repos were re-stamped together in this pass, so that particular tail is closed - `universal-agent-kit` was
not among them, because it carries a contrib record but has never carried a stamp.

Verification: `check-compliance: FastMediaSorter_Lite - 0 error(s), 9 warning(s) (overlay A, canon 2026.08.05)` -
warnings are pre-existing and none was introduced here.

## Canon reconcile 2026-08-18 - the doc pass the stale plugin cache skipped

Canon **2026.08.05 -> 2026.08.18.1**, core digest `sha256:8d33fdab..` -> `sha256:961c9c8a..`. The stamp was
already re-pointed mechanically before this session and is correct; what had never happened was the
reconciliation against the docs. The `sza` plugin served a cache from 2026.07.27 for about three weeks, so
in this repo's sessions the 08-08 and 08-18 rule text was never in context at all.

**Correction to the 2026-08-05 entry above, and it matters for the other records.** That entry says the
upstream change was "AI_USAGE.md §3 and §5, plus the `agent-cost` skill". Commit `22e638d` also rewrote
**RELEASE_AND_DISTRIBUTION.md** (the whole new §8 release package plan, plus the hooks into it at §4 and
§6), **NEW_PROJECT_CHECKLIST.md** and **README.md**'s glossary. Any repo whose reconcile trusted that
summary instead of the diff has never seen §8. Verified with
`git show --stat 22e638d -- rules/ ":!rules/contrib/"`.

**Genuinely unreconciled scope, taken from the diff rather than from a summary**
(`git diff --stat 22e638d..HEAD -- rules/ ":!rules/contrib/"`): AI_USAGE.md, DEVELOPMENT.md,
GITHUB_INTERACTION.md, TESTING_AND_QA.md. **INVARIANTS.md has not changed since 2026.07.27** - it was named
in the task brief, and the diff is empty, so there was nothing to reconcile there.

### Reconciled against the live tree

- **AI_USAGE §1 fire-and-forget, §5 the hook family, GITHUB_INTERACTION §6** - `.claude/settings.json`
  carries permissions only, and there is no hook registration anywhere in the repo, so there is nothing to
  double-wire and nothing to unregister. Verified that the **installed plugin cache** (not the marketplace
  clone) carries the scripts and their registrations: the `2026.818.1` cache holds `guard-bash`,
  `guard-fire-and-forget`, `guard-uncapped-read` and `on-user-prompt`, each behind its bash pre-filter.
  Recorded in the rules file as a standing answer, so the next session does not hand-wire a second copy.
- **AI_USAGE §2's three closure invariants** - `tools/Run-AllTests.ps1` already satisfies all three, which
  is worth recording because it is the non-obvious case: a missing project, a missing `go.exe` and a
  missing worker repo are each recorded as **FAIL**, never as a skip, so `exit 1` genuinely means "found a
  defect OR could not verify". Only the explicit `-SkipGo` opt-out passes, and it is labelled as skipped in
  the summary table. No change needed.
- **DEVELOPMENT §10's lock queue** - inert. No `temp/BUILD.LOCK`, no `temp/CODE.LOCK`, no `temp/` at all;
  single machine, single agent. The rules stand ready for the day that changes.
- **DEVELOPMENT §15 / TESTING_AND_QA §8 gate-verdict cache** - deliberately NOT adopted, and §8 is the
  reason: it says measure the per-gate distribution *before* tuning anything. This repo's battery is two
  `dotnet test` runs plus `go test` and has never been measured, so caching it now would be the exact
  unmeasured optimisation §8 was written against. Recorded rather than done.
- **RELEASE_AND_DISTRIBUTION §8 release package plan** - **skipped, with the reason written into the rules
  file** (`adopt-canon` step 6 permits a one-line skip). §8 projects a ticket store; this repo has none.
  Specs move by hand between `docs/specifications/` and `docs/specifications/done/` - a two-state lifecycle
  with no ids, no status field and no single write path to hook a reconcile into. §8's own text makes
  building that write path the prerequisite, which is an owner scope call, not a consequence of adopting
  the canon.

### Drift found in the rules file, fixed against the tree

The working tree was the authority in every case; `CLAUDE.md` lost on all of them.

- **"No automated test suite. Validation is manual"** - false, and the most expensive line in the file: the
  tree carries **37 test sources** across `tests/Lite.Tests/` (27) and `tests/Companion.Tests/` (10), two
  integration harnesses under `tests/Integration/`, and `tools/Run-AllTests.ps1` to drive them. A sentence
  saying the suite does not exist is how an agent reaches TESTING_AND_QA §1 with no evidence and no idea
  one was available. Replaced with the commands, the three suites, and the note on how the runner treats a
  suite it could not run.
- **The `#If NETFRAMEWORK` seam list** - the file enumerated **16** files by hand; the tree carries **78**
  (`grep -rlE "#If (Not )?NETFRAMEWORK" src/ --include=*.vb`). Four-fifths behind. Replaced the list with
  that command plus the whole-file seams described by shape - a hand-maintained index of a greppable fact
  is the render-target mistake invariant 16 names, one directory over.
- **Settings window "five tabs"** - true of the net48 shell only. The modern build rebuilds the window in
  `Table_Form.ModernLayout.vb` as a sidebar-nav layout of **eight** pages: the same `Tab_Page_1..5` plus
  `Translation`, `Android / SFTP` and `About` from `BuildExtraModernSettingsPages` (present in `HEAD`, not
  WIP - checked with `git show HEAD:`). The file also said the Share tab "was removed" while an
  `Android / SFTP` page exists; corrected to what actually survived - the `btn_Share_Manager` launcher, on
  "Files and system" in net48 and reparented onto the modern page.
- **"Ф-1 has no drawing tools"** - stale. `Image_Editor_Form.Tools.vb` is 41 KB with an `EditorTool` enum
  (crop, brush, rectangle outline/filled, ellipse outline/filled) behind `EditorImageOps.vb` and
  `EditorUndoStack.vb`.
- **Two dead spec links** - `SPECIFICATION_COPY_ACTIONS_REWORK.md` and
  `SPECIFICATION_SEND_LOGS_TO_AUTHOR.md` were linked at `docs/specifications/` and have moved to `done/`.
  Found by testing all 105 link targets in the file; the other 103 resolve.
- **`Main_Form.vb` "~665 LOC .. ~20 partials totaling ~7,700 LOC"** - actually 779 LOC across 38 partials
  totaling ~14,200. Replaced with the counting command rather than with fresher numbers, since the last
  three numbers were also correct when they were written.
- **`SharpCompress 0.50.4`** was missing from a dependency list that claims to enumerate. The other nine
  pinned versions in that section all check out against `FastMediaSorter.Modern.vbproj` and
  `packages.config`.
- **The two `docs/guides/` mirror banners** carried the pre-plugin SHA form *and* a source-of-truth path
  (`P:\WEB\sites.google.comsiteszaodua\Unified_Rules\..`) that no longer exists on this machine.
  Re-stamped to the digest form, naming the GitHub repo. This closes the item left open in the 2026-07-27
  entry.
- One `canon-ok` marker added: the "сборка"/"собери" -> local-flow-only line is invariant 4 mapped onto the
  two Russian trigger words the owner actually types, which the canon cannot know.

### Recorded, not fixed - each needs someone else's decision

- **DIVERGE, stamp**: `.sza-canon.json` says `"editions": []`, but the repo ships a **Server edition** with
  its own winget package (`publishing/winget/server/`, `SerZhyAle.FastMediaSorter.Server`), its own Inno
  `AppId`, ARP name, install dir and `..-server-setup.exe` asset built by `tools/Build-ServerInstaller.ps1`.
  `editionTagPrefixes: []` **is** right - the Server edition ships off the same `v*` tag, no separate
  clock. The stamp was declared correct by the owner for this pass and was not touched; `editions` wants a
  second look in a session that owns it.
- **DIVERGE, code**: `CLAUDE.md` states "`Is_Russian_Language` is a derived compatibility shim .. **new
  code must not read it**", and `Table_Form.ModernLayout.vb` reads it (`Dim ru As Boolean =
  Is_Russian_Language`, in `LocalizeModernSettingsLayout`) - the precise anti-pattern
  `LocalizationCoverageTests` exists to catch. Left alone because that file carries another task's
  uncommitted work.
- **`.claude/` is gitignored here**, so the repo's `build` and `release` skills are per-machine working
  artifacts rather than shared conventions. The `git add -A` fix noted below therefore does not propagate
  to another clone. Worth knowing before anyone treats a repo skill as a durable rule surface.

### Evidence - fresh runs, exit codes cited

- **Compliance gate before**: `0 error(s), 9 warning(s)` (overlay A, canon 2026.08.18.1), exit 0.
- **Compliance gate after**: `0 error(s), 5 warning(s)`, exit 0. Cleared: both `SZA-CANON05` mirror
  banners, `SZA-STYLE02` in `CLAUDE.md` and in `docs/contracts/SETTINGS_WINDOW_INVENTORY_DOTNET10.md`.
- **`pwsh -NoProfile -File tools/Build-SitePages.ps1 -Check`** -> "All language pages match
  site-copy.json.", exit **0**.
- **`pwsh -NoProfile -File tools/Run-AllTests.ps1`** -> all three suites PASS (viewer 475 net10 + 147
  net48, Share Manager 82, Go worker 5 pkg ok), exit **0**. `dotnet` is not on `PATH` in this harness's
  shell and the runner dies on it under `$ErrorActionPreference = "Stop"`; prepending
  `C:\Program Files\dotnet` is the whole fix, and it is GITHUB_INTERACTION §6's "an interpreter that is not
  installed is a dead command" in the small.
- **Honest note on the first run**: the initial `Run-AllTests.ps1` came back **exit 1** with one failure in
  each .NET suite, neither reproducible on re-run. Another task was writing source into this tree
  throughout the session - `git status` grew from 14 modified paths to 26 plus 2 untracked, and the viewer
  test count moved 472 -> 475 mid-session. So the green verdict above is a snapshot of a moving tree, not a
  claim about a quiet one.

### Warnings left, each with its reason

- `SZA-RULES05 CLAUDE.md: 444 lines` - informational by the gate's own text. Checked: the bulk is
  module-by-module architecture, the frozen-anchor matrix and the two-exe seam rules. No process
  restatement; `SZA-RULES03` finds nothing.
- `SZA-STYLE02 CHANGELOG.md:313,315` - both hits are `- ...` placeholder bullets inside the commented-out
  release-section template. Legitimate under the rule's own "a CLI placeholder is legitimate"; see canon
  fix 3.
- `SZA-SURF02 index.html` JSON-LD, `SZA-SURF03 robots.txt`, `sitemap.xml` - raised as a fork rather than
  done silently, because all three are live-site work rather than canon reconciliation. **The owner chose
  to do them now, through the generator**; shipped in a separate commit, and the section below records what
  that turned up. Open since the 2026-07-27 entry, now closed.

### The site pass the owner asked for, and the two live defects it exposed

Done as its own commit, entirely through `tools/Build-SitePages.ps1` rather than into the twelve rendered
pages by hand (invariant 16). What made it worth more than a warning count: **the generator had been
pointing every translated page at two assets that do not exist**, `assets/og-image.png` and
`assets/favicon.ico`. Confirmed against the published site, not inferred - `GET
.../assets/og-image.png` returns **404**. So all 12 pages had been shipping a dead link preview and a dead
favicon, while the hand-authored root page pointed at the real `assets/social-preview-1280x640.png` and
`assets/icons/Fast_Media_Sorter.ico`. The generated pages also carried `og:*` but no `twitter:card` at all.
Both assets are now named once at the top of the script, which is what stops the pair from drifting again.

Added: JSON-LD `SoftwareApplication` on the root page and on all 12 translated pages (built via
`ConvertTo-Json` in the generator, because the localized copy needs JSON escaping and `Esc()` is HTML
escaping - the wrong tool inside a `ld+json` block); `twitter:card`/`title`/`description`/`image`;
`og:site_name` and `og:locale`; and `robots.txt` + `sitemap.xml` as render targets of the same script,
covered by `-Check`. The sitemap derives its public set at run time - every root `*.html` plus one
directory per translated language, 22 URLs - so adding a page needs no edit; the entry page is listed as
the bare directory URL to agree with `canonical`, and only that entry carries the `xhtml:link` alternates.
Deliberately no `softwareVersion`: a version baked into a page is what `SZA-VER04` exists to catch.

**Second live defect, reported and NOT fixed - it needs an owner decision.** The shipped app links to
`https://serzhyale.github.io/FastMediaSorter_Lite/privacy.html` from its About page
(`Table_Form.ModernLayout.vb`, `AddProjectLinkRow(flow, "project_privacy", ..)`), and that URL returns
**404**: Pages serves this repo from the root, and `privacy.html` exists only as `docs/privacy.html`, which
is the unpublished staging tree. Nothing else in the repo references a privacy URL - the Store listing
holds its own in Partner Center and could not be checked from here. This is invariant 14 territory (the
privacy page, the permission list and the store data-safety form must say the same thing) and it cannot be
satisfied by a page that does not resolve. It was left alone because publishing a privacy text is a content
decision, and `docs/` is described in this repo as an unpublished redesign - copying it to the root would
publish whichever revision happens to sit there. It is also why the new `sitemap.xml` does not list it.

### Canon fixes found - not applied from here

1. **`SZA-CANON03` never implements the version-gap rung, so it can only ever warn.** The `adopt-canon`
   ladder says a gap of 2 or more versions is an **error**; the code branches on `adoptedOn` age alone
   (`$sev = if ($ageDays -gt 180) { "error" }`) and never compares versions at all. Worse, `adoptedOn` is
   refreshed by every re-stamp, so the age rung cannot fire either while anyone keeps the stamp current.
   This repo sat three canon versions behind at warn level - **this is the gate hole that let a three-week
   drift pass unnoticed**, and it is the highest-value fix in this list.
2. **`SZA-STYLE02` turns a correct `..` range into a false positive when it abuts a code span.** The check
   strips backtick spans and then tests the residue, so `` `MoveOn1`..`MoveOn9`. `` collapses to `...` and
   is reported as an ellipsis. The remedy in this repo was to write a hyphen instead - i.e. the gate pushed
   a document away from the house `..` form. Test before stripping, or collapse the residue.
3. **`SZA-STYLE02` does not skip HTML comments**, though it already skips fenced blocks. A changelog's
   commented-out release template is prose to it, and there is no way to satisfy it without editing a
   template placeholder into something that reads like real content.
4. **`SZA-RULES06`'s dead-local-path check should extend to `SZA-CANON05` mirror banners.** The banner here
   named a local absolute path that had not existed for weeks, in exactly the shape RULES06 exists to
   catch, while CANON05 looked only at the SHA-versus-digest form.
5. **The `adopt-canon` re-sync path under-specifies the audit.** Step 7 sends you to re-read "the rule docs
   whose per-file digest changed", which finds the changed docs but not a *previous entry that understated
   its own scope* - the failure this session actually hit. One line telling the re-syncer to diff against
   the last **stamped** version rather than against the last written summary would have caught it.
