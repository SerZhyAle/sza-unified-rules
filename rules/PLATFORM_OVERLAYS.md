# Platform Overlays - the concrete shape per project type

The universal core ([REPOSITORY_LAYOUT.md](REPOSITORY_LAYOUT.md), [DOCUMENTATION_CONCEPT.md](DOCUMENTATION_CONCEPT.md))
says *what roles exist*. This file says *what they are called and how they ship* for each project type.
A project reads the core, then exactly **one** of the overlays below - or, when it ships the same product
in more than one form (a desktop app *and* a browser extension), **one overlay per edition**, kept in sync
by a parity doc (see "Editions" below). A project may also combine one overlay's *distribution* with
another's *source shape* - e.g. Overlay A channels (GitHub + winget + Store) on an Overlay C Go
`cmd/`+`internal/` body. The last two sections cover editions of one product and contracts shared *between*
projects.

Each overlay answers the same four questions:

1. **Source root & release-mechanics folder** - the platform-specific names in the top-level shape.
2. **Version shape** - the one authoritative form and its channel remaps.
3. **Distribution channels** - where the built artifact goes and which listing files feed them.
4. **Frozen anchors** - the identifiers that correlate an *update* to an *install*; unique per product,
   never reorganized away. Two refinements that hold for every overlay: an anchor is tied to the
   **install location / id, not the binary's contents** - you may re-point it at a new implementation that
   installs to the same path (e.g. an in-place runtime migration that replaces the installed exe), and
   settings/associations/ARP/store update-correlation carry over. And the **visible name is decoupled from
   the anchor** - you may rebrand the display name on every surface while the anchor (package id, ARP
   DisplayName, store reserved name, install dir) stays frozen; only the anchor is off-limits, the name
   rides on top of it.

---

## Overlay A - Windows desktop app (GitHub Releases + winget + Microsoft Store)

Reference project: `FastMediaSorter_Lite`.

**Source root & release-mechanics.** Source in `src/` (or a Go `cmd/`+`internal/` body when the desktop
app is written in Go), tests in `tests/`, and the single most important convention - **one committed folder
per distribution channel**. The recommended grouping is a **`publishing/` umbrella** so "how do we ship?"
has one answer other repos copy wholesale:

```
publishing/
  installer/  Inno Setup (.iss) OR WiX MSI (.wxs) + helper .ps1 (elevation, pre-uninstall stop)
  winget/     the 3 winget manifests (version / installer / defaultLocale) - source of truth
  msix/       Store MSIX: AppxManifest.xml, build-msix.ps1, README.md (+ gitignored dist/, stage/)
  store/      Partner Center listing material: listingData.csv, screenshot scripts, listing prompt
```

Portability rules:
- **The invariant is one committed folder per channel; the `publishing/` umbrella is optional.** Channels
  may instead sit as top-level siblings (`winget/`, `msix/`, `installer/`, `store/` or `tools/store/`) when
  a repo predates the umbrella or mixes in a Go source body. Keep them grouped and self-contained either way.
- **Manifests are committed source, submissions are generated.** `publishing/winget/*.yaml` and
  `publishing/store/listingData.csv` are the canonical copies edited each release; the winget-pkgs PR
  and Partner Center upload are produced *from* them. Keep the repo copy in sync so the next release
  starts from the last shipped text, never a blank export.
- **Channel folders are self-contained.** A script inside `publishing/<channel>/` finds the repo root
  by going **two** levels up (`Split-Path (Split-Path $PSScriptRoot -Parent) -Parent`); relative paths
  to repo assets are `..\..\assets\...`. Re-check this one thing if you move a channel folder.
- **Generated output is gitignored, not deleted** (`publishing/msix/dist/`, `.../stage/`).
- **A desktop product may ship with no installer channel at all.** When the GitHub asset is a portable
  `<App>-<version>-<platform>.zip` (no Inno/WiX setup) and winget wraps that same zip (`InstallerType: zip`
  / `NestedInstallerType: portable`), there is no `installer/` folder and no Inno `AppId` / WiX
  `UpgradeCode` to reserve - the frozen-anchor set collapses to {winget `PackageIdentifier`, MSIX Identity
  `Name`/`Publisher`}. Reference: `StreamsPlayer` (portable-zip + winget-portable + MSIX).

**Version shape.** Date tag - monotonic, unique per minute, sortable, no manual bump, stamped into every
exe at build. **The digit-padding is a per-project frozen choice**: `YY.M.D.HHmm` (e.g. `26.7.23.1127`) or
zero-padded `YY.MMDD.HHmm` (e.g. `26.0702.1530`), or a **separator-less continuous stamp** `yyMMddHHmm`
(e.g. `2606120121`, a plain sortable integer) are all valid - the zero-padded and separator-less forms sort
lexically without a numeric parse. The only hard requirements: monotonic and sortable, and **once chosen
never change it** (the shape orders every future update against the installed one). Store remap:
`Major.Minor.Build.0` derived mechanically from the same stamp. **The MSIX Identity Version forbids leading
zeros in any component**, so a zero-padded stamp cannot merely gain a `.0` suffix - int-cast each component
to strip the padding (`26.0723.0959.0` -> `26.723.959.0`; equivalently a dotted `YY.M.D` stamp collapses the
date to `YY.(M*100+D)`) and guard each part at `<=65535`. GitHub and winget keep the canonical padded
value; only the MSIX identity is remapped.

**Distribution channels.** GitHub Release (authoritative asset `<App>-<version>-<platform>-setup.exe`,
`...-<platform>.zip`, each with `.sha256`); winget (from `publishing/winget/` - the winget artifact may be a
`setup.exe`, or a **portable-in-zip** (`InstallerType: zip` / `NestedInstallerType: portable`, one
`PortableCommandAlias` per exe) so the release zip doubles as the winget artifact for a multi-exe CLI);
Microsoft Store (MSIX, Store re-signs on certification so no cert in-repo). Discoverability surfaces: Store `SearchTerm1..N` /
`Feature1..N`, winget `Tags`/`Moniker`/`ShortDescription`, plus the GitHub Pages site.

**Frozen anchors** (reserve new, unique per product; changing them orphans every install): winget
`PackageIdentifier`/`PackageName`; the installer product identity - Inno `AppId` **or** WiX MSI `UpgradeCode`
(the ARP/PATH/shortcut owner and update-to-install tie) - plus
`UninstallDisplayName`/`DefaultDirName`/`OutputBaseFilename`; MSIX Identity `Name`/`Publisher`. (A
portable-zip-only product has no installer identity to reserve - see the no-installer variant above.)
Publisher-*constant* values shared across all products (Partner Center `Publisher` CN,
`PublisherDisplayName`) go into the msix build-script defaults - but a shared **IARC rating id is *not*
one of them** unless the app's content-exposure profile matches (see [SECURITY_AND_PRIVACY.md](SECURITY_AND_PRIVACY.md) "Store declarations").

**Site.** GitHub Pages served from repo **root** or **`/docs`** - live pages are root `*.html` + root
`assets/`, or a `docs/`-served static site (add `docs/.nojekyll` for hand-authored HTML). Check which source
Pages is set to: a `docs/` tree is either the live site or an unpublished staging copy depending on that
setting - don't assume root and `docs/` HTML match.

---

## Overlay B - Android app (Google Play, AAB, flavor matrix)

Reference project: `FastMediaSorter_mob_v2`.

**Source root & release-mechanics.** Gradle modules are the source root (`app_v2/`, `wear/`); there is
no `publishing/` - Gradle + the Play console *are* the release mechanics. Android-specific homes that
replace parts of the universal taxonomy:
- **Specs live in `PLAN/Sxxxx_<slug>.md`** driven by the `scripts/spec_catalog/` CLI and
  `PLAN/spec-catalog.jsonl`, not `docs/specifications/`. The `Sxxxx` lifecycle (Draft → Approved →
  Tactical → In Progress → Implemented → Verified) is the project's spec engine.
- **Class navigation via `dev/CATALOG/`** (gitignored, regenerated by `catalog_sync.ps1`) - query it
  before grep.
- `docs/guides`, `roadmaps`, `contracts` from the universal taxonomy still apply.

**Version shape.** `versionCode` (monotonic integer, the Play update key) + `versionName` (human string)
in `build.gradle.kts` - **not** the desktop date tag. Play requires a strictly increasing `versionCode`
per upload; derive it mechanically (e.g. from date/build counter) rather than hand-incrementing.

**Distribution channels.** A single codebase can fan out to **more than Play**. The `BuildConfig`-gated
flavor matrix (`standard` / `lite` / `photos` / `legacy` ..) maps to *different stores*, not just Play
tracks: the store flavors go to **Google Play** (each a separate listing/track); a **sideload-only** flavor
ships direct APK off the site/GitHub when it carries capabilities a store would reject; a **VR** flavor
ships to a VR store (Meta Horizon / Quest). Build/upload via `.\a.ps1 r` (AAB built in a dedicated
worktree). Play has no keyword field, so the description carries the functional phrasing; plus the product
site. Sibling **modules** of the same build (`:wear` for Wear OS, plus tooling modules) are a third axis -
not flavors, not editions.

**Frozen anchors** (unique per product/flavor; changing them breaks updates): the `applicationId`
(and any per-flavor `applicationIdSuffix`), and the upload/signing key registered with Play App
Signing. Reserve these once; never change them for a shipped app. **Sanctioned exception to "one id per
channel":** flavors that are never co-published to the *same* store may deliberately share one
`applicationId` (e.g. a sideload flavor and a VR flavor sharing the base id of the Play `standard`
flavor) - no collision, because they never meet on one store.

**Play-specific gates worth carrying in the release checklist:** no distribution-reach regression
(countries / min-API / device count), foreground-service and permission declarations must match
runtime use, native `.so` bundling constraints per flavor.

---

## Overlay C - Go CLI / Wails desktop tool (GitHub-only)

Reference project: `fms_companion` (Go + Wails; now a reference implementation whose config format is a
frozen cross-project contract - see below).

**Source root & release-mechanics.** Idiomatic Go layout: `cmd/<binary>/` entry points, `internal/`
private packages, `frontend/` for a Wails UI, `main.go` at root, `go.mod`/`go.sum`, `wails.json` for
Wails. Release mechanics are a single `build.ps1` (`-Release`, `-Installer`) - no `publishing/`
umbrella, because there is one channel.

**Version shape.** Date tag `YY.M.D.HHmm` like desktop (or a semver `vX.Y.Z` if the tool exposes a
stable API other code depends on). Stamped via Go `-ldflags "-X main.version=..."`.

**Distribution channels.** GitHub Releases only (portable binary / ZIP, `.sha256`; optional NSIS
installer). No store, no package manager unless the tool later earns one. Discoverability is the repo
README + GitHub topics; a site is optional.

**Frozen anchors.** The module path in `go.mod` (if imported by others) and the binary name. For a Wails
app that ships an installer, the installer's product GUID / install dir play the desktop-overlay role.

---

## Overlay D - Browser extension (Chrome Web Store + Edge Add-ons)

Reference edition: the `extension/` tree of `doc-html-translate`. Usually an **edition** of a parent
desktop/CLI app (see "Editions" below), not a standalone repo.

**Source root & release-mechanics.** A self-contained `extension/` subtree: `manifest.json` (MV3), `src/`,
`_locales/<lang>/messages.json`, a bundler (`build.mjs` or similar), and `store/` for listing material
(`LISTING.md`, `PRIVACY.md`, `screenshots/`). No `publishing/` - the two stores plus the bundler are the
release mechanics.

**Version shape.** The manifest `version` (dotted integers, e.g. `26.718.1849`); each store requires a
strictly increasing version per upload. Derive it mechanically from the date like the desktop stamp. An
edition may run on its **own clock**, decoupled from the parent app's version.

**Distribution channels.** Chrome Web Store and Microsoft Edge Add-ons, **published independently** - a
separate submission, separate review, and (by default) a **separate item id** on each. Listing copy in
`store/LISTING.md` + `store/PRIVACY.md`; UI strings in `_locales/`. Discoverability is each store's own
search (title + description + category); no package manager.

**Frozen anchors.** The **Chrome item id** and the **Edge product id** - distinct per store, assigned by the
store on first publish. Never pin a private `key` in the manifest to force one. The signing/CRX key
(`cws-key*.json`, `*.pem`) is git-ignored, never committed. Changing an id orphans the installed base on
that store.

**Store traps worth carrying in the checklist:** the MV3 permission list must map to real use (an unused
permission triggers review rejection); the two stores drift in policy and review time - treat each as its
own release; keep `_locales` keys at parity across shipped languages or the build is inconsistent.

---

## Editions - one product shipped in several forms

A single product can ship as more than one **edition** - e.g. a desktop app (Overlay A) *and* a browser
extension (Overlay D) - built from two **independent codebases with no shared code** (logic hand-ported
between them). An edition is not a *flavor* (one codebase, build-time variants); it is a separate source
tree that must stay behaviourally in sync with its sibling.

- **One product = one cross-edition ticket.** A user-facing feature is planned and shipped across *every*
  edition at once, not filed per edition.
- **A parity doc is the source of truth** (`docs/PARITY.md`) for what must match (shared constants,
  palettes, algorithm outputs, defaults) and the **intentional** differences that must not be "fixed". The
  drift guards live in DEVELOPMENT "Multi-edition parity".
- **Editions version and release independently** - each on its own trigger and cadence (a `v*` tag for the
  app, an `ext-<store>-v*` tag per extension store). The "release" operation **fans out** per edition and
  per channel; none blocks the others.
- **In-repo vs cross-repo editions use different parity mechanisms.** Editions in one repo (independent
  source trees side by side) sync through `docs/PARITY.md` + a drift gate. Editions that live in
  **separate repos** (e.g. an Android app, a desktop app, and a CLI companion of the same product) sync
  through a **frozen wire contract** instead - a `docs/contracts/CONTRACT_*.md` with a byte-identical test
  vector both ends validate against (see "Cross-project contracts" below). Same goal, different home.

---

## Co-shipping shapes - several artifacts, one product, one release

Distinct from *editions* (independent codebases, independent release triggers, kept in sync by a parity
doc). These are cases where **one release ships more than one binary** for **one product**, on **one
trigger**. Name them so they are not mistaken for editions or flavors:

- **Flavor** (already in the glossary) - one codebase, build-time variants of one artifact (Android
  `standard`/`lite`; a `BuildConfig` gate). One source, one toolchain, N configured outputs.
- **Dual-runtime build variant** - **one source tree compiled into two (or more) exes by two toolchains**,
  installed **side by side in one folder**, where the installer selects which exe the shortcut / file
  associations target **by the running OS**. Reference: `FastMediaSorter_Lite` ships a `net10` x64 mainline
  (`dotnet publish`, single-file) and a `net48` x86 fallback (`msbuild`) from the same `.vb` sources;
  `UseModernExe` in the Inno script points Win10+ at the mainline, Win7/8.1 at the x86 sibling. Parity is
  enforced by **compile-time seams** (`#If NETFRAMEWORK`), not a `PARITY.md` - the compiler is the gate (see
  [DEVELOPMENT.md](DEVELOPMENT.md) "Single-source multi-target"). Neither artifact is shippable alone;
  every packager builds both.
- **Co-shipped companion binary** - a second program (or a second-language build of the tool) shipped as a
  **sibling in the same release**, one tag, one zip/installer/package - **not** a flavor (it is a separate
  program) and **not** an edition (no independent release trigger, cadence, or parity doc). Examples: the
  `FastMediaSorter_Lite` **Share Manager** companion (its own `.vbproj`, own mutex, tray host, a *second*
  `<Application>` in the one MSIX package); FileDO's VB.NET GUI co-shipped beside its Go CLI. A store package
  may carry it as an extra `<Application>` in one manifest; an installer as a selectable component.

## Companion editor / IDE extension - a thin helper on its own channel

Distinct from both an *edition* (a full second form of the product, kept in behavioural parity) and a
*co-shipped companion binary* (a sibling program in the **same** release/tag). A **companion editor
extension** is an **in-repo, code-independent** helper (a `vscode-extension/` subtree, TypeScript, no shared
code with the app) that surfaces **one** piece of the parent app's state where the app itself cannot reach -
e.g. rendering the layout marker at the VS Code (Monaco) caret, which an external overlay can't track.
Because it reimplements none of the product's logic, it needs **no parity doc**. Its defining traits:

- **Coupled by a one-way on-disk contract, not shared code.** The app writes a small state file
  (`%LOCALAPPDATA%\<App>\<state>.txt`, or `%ProgramData%` when packaged - see the MSIX cross-process note in
  [CHANNEL_MATRIX.md](CHANNEL_MATRIX.md)); the extension polls it. This is a degenerate in-repo case of the
  producer-frozen / consumer-forward-tolerant contract rule below, one product, two processes/languages.
- **Its own channel, version clock, and cadence.** It ships to the **VS Code Marketplace**
  (`npx @vscode/vsce publish`), on its **own semver** (decoupled from the app's date tag) and **only when the
  subtree changed** - a release op gated on a subtree diff, not on the app version. See the VS Code
  Marketplace row in [CHANNEL_MATRIX.md](CHANNEL_MATRIX.md).
- **Frozen anchor:** the Marketplace **extension id `<publisher>.<name>`** - changing publisher or name
  orphans installs; the signing/publish PAT is ambient, never committed. Reference: `CyrFlip`'s
  `SerZhyAle.cyrflip-vscode` beside the desktop app.

## Cross-project contracts

When two products - or two editions of one product living in separate repos - share a wire format or
on-disk file, that format is a **frozen contract**, owned by one repo and consumed byte-identically by
the others.

- **Home:** `docs/contracts/CONTRACT_<name>.md` in the *producing* repo (universal taxonomy), with a
  canonical test vector both ends validate against.
- **Example:** the `.fmscfg` / config format is defined in `fms_companion/docs/CONFIG_FORMAT.md` and
  consumed by the Android importer - a byte-identical canonical vector on both ends. The Go repo is the
  reference implementation even though the companion is discontinued as a shipped product.
- **Rule:** a contract changes only with a version bump inside the file (`schemaVersion`), never a
  silent reshape. Producers stay frozen at the shipped shape; consumers stay forward-tolerant (accept
  a higher `schemaVersion` they can still parse). Reorganizing folders is safe; changing the wire shape
  breaks every counterpart that shipped against it.

**A consumed *release artifact* is a third coupling shape** - distinct from an edition (kept in sync by a
parity doc) and from a wire contract owned in-repo. A product may depend at runtime on **another product's
published release output**: e.g. a data bank downloaded from the producer's GitHub Release / a known URL,
not a file the consumer's user hands it. Because the consumer does not own the format and cannot bump it,
the same **producer-frozen / consumer-forward-tolerant** rule applies, plus two consumer-side invariants:

- **Preserve user-authored local data across a refresh.** Ingesting the external artifact must never
  destroy the user's own records - key by a stable id, update/remove only *producer-origin* rows, and leave
  manually-added or imported rows untouched.
- **The fetch stays explicit.** No silent background download of the external artifact; the user (or an
  obvious action) triggers each refresh.

Optionally mirror the consumed shape as a **read-only** `docs/contracts/CONTRACT_*.md` even though you do
not own it, so a breaking upstream change is caught against a local vector. Reference: `StreamsPlayer`
consuming the `FastMediaSorter` stream-bank ZIP (a `streams.csv` that must be the **first** ZIP entry or the
bank is rejected; a URL-keyed merge that only touches catalog-origin rows).
