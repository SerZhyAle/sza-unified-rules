# Channel Matrix - the per-channel publishing reference

The concrete "how do we push to each store/index" companion to the two docs it sits between:

- [RELEASE_AND_DISTRIBUTION.md](RELEASE_AND_DISTRIBUTION.md) owns the **order and the gates** (build/release
  boundary, coverage gate, pre-flight, post-release) - the *when/why*.
- [PLATFORM_OVERLAYS.md](PLATFORM_OVERLAYS.md) owns the **folder shapes and frozen anchors** per project type.
- **This file** pins, for every distribution channel, the invariant facts a release must satisfy: what
  triggers it, what it costs, where its auth comes from, who signs, which listing file feeds it, its frozen
  anchor, and how you prove it live.

**Boundary - convention matrix, not a command dump.** This is the set of *facts every channel playbook must
fill*, shared across projects. The exact commands (`wingetcreate submit`, `build-msix.ps1 -IdentityName`,
the tag names) live in each repo's release skill (e.g. a project `DEV/RELEASE.md`), which renders *from* this
matrix - it does not get re-authored here. Cost tags: **[PAID]** = spends paid CI minutes; **[PUBLIC]** =
publishes to a store/index (irreversible, one-way).

## The matrix

| Channel | Trigger | Cost | Auth source | Who signs | Listing source | Frozen anchor | Verify live |
| --- | --- | --- | --- | --- | --- | --- | --- |
| GitHub Release | `v*` tag push | [PAID] | `gh auth` ambient | self (`.sha256`) | release body <- CHANGELOG | - | asset downloads + checksum matches |
| winget | PR to `microsoft/winget-pkgs` | [PUBLIC] | `gh` + one-time CLA | Microsoft re-hosts | `winget/*.yaml` (committed) | `PackageIdentifier` | `winget install --manifest`, then `winget search` after merge |
| Microsoft Store (MSIX) | **manual** upload in Partner Center | [PUBLIC] | Partner Center console | **Store re-signs** (no cert in repo) | `store/listingData.csv` | MSIX Identity `Name` + `Publisher` | dashboard shows new version; update over a prior MSIX |
| Chrome Web Store | `ext-cws-v*` tag push | [PAID] [PUBLIC] | CWS API creds + `cws-key` (git-ignored) | CRX / CWS | `extension/store/LISTING.md` | Chrome **item id** | store page shows version; installed copies update |
| Edge Add-ons | `ext-edge-v*` tag push | [PAID] [PUBLIC] | Edge Partner API | Edge | same `extension/store/LISTING.md` | Edge **product id** (distinct from Chrome) | dashboard shows version; independent of Chrome |
| VS Code Marketplace | **manual** `vsce publish` (only if the extension subtree changed) | [PUBLIC] | Marketplace PAT (Azure DevOps-backed) | Marketplace | `package.json` + `README.md` + `CHANGELOG.md` | extension id `<publisher>.<name>` | gallery shows version; installed copies auto-update |
| Google Play (Android) | AAB upload to a track | [PUBLIC] | Play console / API key | Play App Signing | Play store fields | `applicationId` + upload key | track shows build; staged rollout; update over prior install |
| Sideload / direct APK | site/GitHub asset (self-host) | [PUBLIC] self-host | none | own release key | site + a per-variant feature inventory | `applicationId` (may be shared) | install + update on a real device |
| VR store (Meta Horizon / Quest) | build upload to the VR store | [PUBLIC] | VR store dev console | store / own | VR store listing | `applicationId` (store binds listing to it) | store shows build; update over prior install |

> Rows a given project uses depend on its overlay: a Windows-desktop app uses GitHub + winget + Store; a
> product with a browser edition adds Chrome + Edge; a companion editor extension adds VS Code Marketplace;
> an Android app uses Play (plus Sideload / VR-store when a flavor targets them); a Go CLI uses GitHub only.

## Per-channel playbook (the facts each one adds)

**GitHub Release** - the authoritative asset host. Asset name carries the version
(`<App>-<version>-<platform>-setup.exe` / `.zip`, each with `.sha256`). The release body is the dated
CHANGELOG section, verbatim or curated (see [DOCUMENTATION_CONCEPT.md](DOCUMENTATION_CONCEPT.md) §2).
Discoverability: repo README + GitHub topics. No re-sign, no review, no frozen anchor - it is the render
target everything else points at via a durable URL (`/releases/latest`). **Trap**: a malformed or 0-byte
workflow file auto-disables the repo's Actions, and a `v*` tag push then silently does nothing (no run, no
retry) - a release looks pushed while nothing built. Confirm Actions is enabled before trusting the tag
trigger.

**winget** - manifests are committed source (`winget/*.yaml`); the PR is generated *from* them. Always
**local-install-test the manifest first** (`winget install --manifest winget`) - it is the only gate that
verifies URL + SHA end-to-end; `winget validate` checks schema only. `wingetcreate update` copies old
metadata forward, so to change description/tags you must edit `winget/` and `wingetcreate submit winget`
(the folder form). Replace the auto-generated PR body with real notes; sign the CLA once. Latency: hours to
a day after merge before `winget search` sees it. Discoverability: `Tags` / `Moniker` / `ShortDescription`.
winget-pkgs rejects LF/mixed line endings (`Validation-Line-Endings-Error`) - edit manifests CRLF-preserving,
never with `sed`. Read the real failure from the build's `InstallationVerificationLogs` artifact, not the
generic bot comments.

*winget failure modes (each a real validation abort, learned the hard way - reference:
`FastMediaSorter_Lite`):* point winget at the installer **directly** (`InstallerType: inno`, or
`zip`+`portable` for a portable CLI) with **no `Scope`, no `Dependencies`, no `NestedInstallerType`** unless
proven necessary. Concretely: **don't declare a VCRedist (or similar) dependency** - winget enters a
resolution loop and aborts `0x8A150044`, and the app installs fine undeclared (validation never launches
it); **don't add `Scope: user`** - it forces `--scope user` and aborts `0x8A150044` ("no suitable
installer"); **never point winget at a self-extracting single-file bootstrap zip** - Defender ML flags it
`Program:Script/Wacapew.A!ml` (persistent false positive); a **heavy portable payload zip** can pass the
scan then abort `0x80004004` (E_ABORT) mid-extract. The "Missing `NestedInstallerType`" note is a **cosmetic**
`Validation-Guide`, not a failure.

*Two anchor traps:* winget's **`PackageName` must equal the installed ARP DisplayName** - that string is how
`winget upgrade` correlates, so if you rebrand the product keep `PackageName` (and the installer's
uninstall/ARP DisplayName it mirrors) frozen. And **`MinimumOSVersion` / `Architecture` describe the
installer, not the narrowest exe inside it** - declaring a high floor on an installer that also serves older
OSes (e.g. a setup.exe that drops a 32-bit fallback for Win7/8.1) wrongly hides the package from the very
machines that fallback exists for.

**Microsoft Store (MSIX)** - built unsigned (`build-msix.ps1`), uploaded **by hand** in Partner Center; the
**Store re-signs on certification**, so no cert lives in the repo. Publisher-constant, non-secret values
(Partner Center `Publisher` CN, `PublisherDisplayName`) live in the build-script defaults, passed as
parameters - **but not a shared IARC rating id**: reuse it only when the content profile matches, and file a
fresh questionnaire for an app that opens uncurated third-party content (see
[SECURITY_AND_PRIVACY.md](SECURITY_AND_PRIVACY.md) §5). Listing copy is trimmed from `listingData.csv` to
each field's cap. Discoverability: `SearchTerm1..N` / `Feature1..N`. Anchor mistake here (changed Identity
`Name`/`Publisher`) orphans every installed copy - verify an **update**, not just a fresh install. One MSIX
package can carry a **co-shipped companion** as a second `<Application>` in the same manifest (see
[PLATFORM_OVERLAYS.md](PLATFORM_OVERLAYS.md) "Co-shipping shapes"); inside the container an HKCU `Run`
autostart write is silently virtualized away, so retarget autostart to a `uap5:StartupTask` and declare any
firewall opening via `desktop2:FirewallRules` rather than an installer-time registry/`netsh` step. The same
virtualization hits **a file another process must read**: a write to `%LOCALAPPDATA%` is redirected into the
package container, so a sibling reader (a companion editor extension, an external tool) can't find it - write
such inter-process files to **`%ProgramData%`** (not virtualized) when packaged and have the reader check both
paths; detect packaging at runtime via `GetCurrentPackageFullName`.

- **`msstore` CLI + Partner Center onboarding traps (individual accounts).** Register the product under Partner
  Center's **"Windows"** program, **not** "Windows Desktop Applications" (the latter is telemetry for EV-signed
  Win32 apps, not an MSIX submission path). The `msstore` CLI's interactive `msstore reconfigure` **fails on an
  individual developer account** ("Error while retrieving Organization" - there is no Azure AD org behind a
  personal MSA); automation needs a service-principal (`--tenantId/--clientId/--clientSecret`), so for
  individual accounts the **Partner Center web submission is the reliable path**.
- **Listing CSV import is export-then-merge, not upload-your-own.** A direct upload of a hand-authored
  listing CSV is rejected ("the ID column contains incorrect entries") because Partner Center's `ID` values
  are account-specific and undocumented. Working flow: **Export listing** from Partner Center, then fill the
  language columns of *that* file (keeping its `Field`/`ID`/`Type` untouched) from your content source of
  truth via a merge script, then **Import**. Keep the file **UTF-8 with BOM** so Cyrillic survives Excel.
- **A whole app category can draw extra review.** Apps that open third-party streams get infringing-content
  scrutiny; frame the listing by the legitimate job (a curated catalog player), drop the trigger-prone
  keyword (e.g. `IPTV player`), and paste the full-trust justification verbatim (see SECURITY_AND_PRIVACY §5).
  A **global keyboard hook + clipboard read reads as a keylogger** and draws the same extra scrutiny; pre-empt
  it with the `runFullTrust` justification and a plain "does not log keystrokes, no network, no data"
  description. Reference: `CyrFlip`.

**Chrome Web Store** and **Edge Add-ons** - two stores, **published independently**: separate submission,
separate review, and by default a **separate item id** each. Never pin a private `key` in the manifest to
force an id; keep the CRX/CWS signing key (`cws-key*.json`, `*.pem`) git-ignored. The MV3 permission list
must map to real use - an unused permission is a common review rejection. Listing + "What's new" come from
`extension/store/LISTING.md`; UI strings from `_locales/<lang>/messages.json` (keys at parity across shipped
languages). Edge review is typically slower than Chrome; treat each as its own release.

**VS Code Marketplace** - a **companion editor extension** (see [PLATFORM_OVERLAYS.md](PLATFORM_OVERLAYS.md)
"Companion editor / IDE extension"), **not** a browser extension: different store, different auth. Published
**by hand** from the dev machine (`npx @vscode/vsce publish`), so no paid CI; auth is a **Marketplace Personal
Access Token** (backed by an Azure DevOps org, ambient via `vsce login` / `VSCE_PAT`, never committed).
Listing copy is the extension's own `package.json` (`displayName`/`description`/`categories`/`keywords`) +
`README.md` (the gallery page) + `CHANGELOG.md`; it runs its **own semver clock** decoupled from the parent
app and ships **only when its subtree changed**. Frozen anchor: the **extension id `<publisher>.<name>`** -
changing publisher or name orphans installs. Reference: `CyrFlip`'s `SerZhyAle.cyrflip-vscode`.

**Google Play (Android)** - AAB to the right track (internal -> closed -> production), staged rollout where
appropriate. Play has no keyword field, so the description carries the functional phrasing. Foreground-service
and permission declarations must match runtime use or Play rejects. `versionCode` must strictly increase.

**Sideload / direct APK** - the escape hatch for a flavor carrying capabilities a store would reject (broad
overlay / accessibility / capture permissions): self-hosted APK off the site or GitHub, self-signed, its own
(often gitignored) feature inventory. No review, so *you* own the safety and the honest-limitations copy.
**VR store (Meta Horizon / Quest)** - a VR flavor to the VR store; the store binds the listing identity to
`applicationId`, and review is its own track, decoupled from the Play flavors' cadence.

## Cross-channel invariants (hold for every row)

- **Listing text is a render target, never re-authored per channel.** The long form lives in
  CHANGELOG / README / the listing source file; each channel gets the same text trimmed to *its* field caps.
  Fill every search-term / tag / keyword slot with a distinct user phrase (see
  [DOCUMENTATION_CONCEPT.md](DOCUMENTATION_CONCEPT.md) §3). Character caps drift - read them from the console
  at submit time, do not hardcode a number that will go stale.
- **The frozen anchor is reserved once and never changed** - changing it orphans the installed base on that
  channel. Reserve per product/store (see [PLATFORM_OVERLAYS.md](PLATFORM_OVERLAYS.md), each overlay's fourth
  fact, and [SECURITY_AND_PRIVACY.md](SECURITY_AND_PRIVACY.md) §2).
- **Post-release proof is the update path, not just a fresh install.** A frozen-anchor mistake only shows up
  when a real prior install tries to update (see [RELEASE_AND_DISTRIBUTION.md](RELEASE_AND_DISTRIBUTION.md)
  §6). Record: version, date, channels shipped, coverage-gate result.
- **A multi-edition release fans out per channel and edition; none blocks the others.** Each row is its own
  one-way op with its own trigger tag and cadence (see PLATFORM_OVERLAYS "Editions").

## Applying to a new project

1. Keep only the rows this project's overlay(s) use; delete the rest.
2. For each kept row, wire its trigger, auth source, and listing source into the project's release skill -
   the skill renders the concrete commands *from* this matrix.
3. Reserve each row's frozen anchor (once).
4. Add the update-from-prior-install check to the post-release step for every store row.
