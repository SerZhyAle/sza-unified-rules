---
# Contribution: internal_IP_manager (overlay A - Windows desktop portable ZIP via GitHub Releases + WinGet, plus private local drop; single edition) -> Unified_Rules
Source repo: p:\WINDOWS\internal_IP_manager | Date: 2026-11-25
Read: README, NEW_PROJECT_CHECKLIST, TEMPLATE, PLATFORM_OVERLAYS, AI_USAGE, WINDOWS_PACKAGING, CHANNEL_MATRIX; deduped against: contrib/{cyrflip,streams_player,filedo,fastmediasorter_lite}.md
---

internal_IP_manager (IP Manager) is a single-window VB.NET WinForms desktop app (.NET 8, `net8.0-windows`)
that manages a CSV list of LAN devices - ping/online status, IP-range scan, hostname/MAC resolve, and a
TP-Link Archer BE550 DHCP-reservation sync. Following the 2026-11-20 owner scope decision (`win-suite:WINSUT-0040`,
`INTIPM-0023`), it transitioned from an internal-only drop tool to an **Overlay A portable-ZIP Windows desktop
product** (`role: "product"`, channels `github` + `winget`, `PACKAGE-VERSIONING` 0.10 dotted rendering,
dedicated GitHub Pages documentation and privacy site under `site/`) while retaining the legacy local drop
copy (`build.ps1 publish` -> `C:\GD\tc\SZA\_APP`). Microsoft Store / MSIX is out of scope. Also present:
`Debug.WriteLine`-only logging, run-and-observe at the release tier, and the shipped harness task-flow
(`tasks/INTIPM-####_<slug>.md`, legacy closed tickets keep `TASK-####`, `.sza-profile.json`,
`tasks/spec-catalog.jsonl`, `tools/harness.ps1`, `r0`-`r3`, `rs`, `rm`, `rw`).

> **Keep this note in the record.** Current facts, edited in place. Never append a dated section to this file,
> and append nothing under `history/` either: those files are frozen ([the rules of that folder](history/README.md))
> and are not reading for a task. A delta the core absorbed, a candidate that was applied or refused and a
> question that was answered are deleted here.

## Overlay facts (verified against this repo)

- **Source root & release-mechanics.** Source in `src/` (flat: `Form1.vb`, `DeviceListStore.vb`, `Columns.vb`,
  `AppSettings.vb`, `FormSettings.vb`, `RouterClient.vb`, `RouterSync.vb`, plus UI/help/identity modules);
  `.sln` and task-flow launchers (`r0`-`r3`, `rs`, `rm`, `rw`) at repo root; `publishing/winget/` holds the
  three CRLF WinGet 1.12.0 manifests; `site/` holds the dedicated static Pages landing and privacy pages;
  `.github/workflows/release.yml` and `.github/workflows/pages.yml` automate tagged releases and Pages deploy.
  `build.ps1` provides `check` (<= 5 s fast static checks including help, version-stamp self-test, and release
  surfaces), `package -Tag vYY.MMDD.HHmm` (pinned self-contained `win-x64` portable ZIP + `.sha256` with strict
  allowlist and PE read-back), and `publish` (legacy private copy to `C:\GD\tc\SZA\_APP`).
- **Version shape (+ padding choice).** Registered in `PACKAGE-VERSIONING` 0.10 section 10 (`fms-a:S4813`):
  Windows desktop `dotted` rendering, one validated `Europe/Malta` local minute per release:
  GitHub tag `vYY.MMDD.HHmm`, WinGet `PackageVersion` and PE `ProductVersion` `YY.MMDD.HHmm`, numeric PE
  `FileVersion` / `AssemblyVersion` `YY.int(MMDD).int(HHmm).0`, strict monotonic rejection of repeated/backward
  pins (`scripts/version-stamp.ps1`). Local dev builds carry non-releasable sentinels (`0.0.0-dev` / `0.0.0.0`).
- **Channels + listing files.**
  - GitHub Releases (`SerZhyAle/internal_IP_manager`): portable `win-x64` ZIP + `.sha256`, `.github/workflows/release.yml`.
  - WinGet (`SerZhyAle.InternalIPManager`): `publishing/winget/*.yaml` (3 flat CRLF files, `zip` + `portable`,
    stamped from one tag pin via `scripts/stamp-winget.ps1`).
  - GitHub Pages (`https://serzhyale.github.io/internal_IP_manager/`): `site/` (`index.html`, `privacy.html`,
    vendored `sza-kit.css` with SHA-256 provenance).
  - Legacy private drop: `build.ps1 publish -Configuration Release` -> `C:\GD\tc\SZA\_APP` (excluded from release ledger).
- **Frozen anchors.** WinGet `PackageIdentifier` = `SerZhyAle.InternalIPManager`, `PackageName` = `IP Manager`,
  nested executable `internal_IP_manager.exe`, portable command alias `internal_IP_manager`, repository
  `https://github.com/SerZhyAle/internal_IP_manager`, documentation `https://serzhyale.github.io/internal_IP_manager/`.
- **Editions + parity mechanism.** **None - single edition.** One `.vbproj`, one self-contained `win-x64` exe.

## Channel-matrix rows (this project)
Format: Channel | Trigger | Cost | Auth | Signer | Listing source | Frozen anchor | Verify live
- **GitHub Release** | `v*` tag push (`.github/workflows/release.yml`) | [PAID] [PUBLIC] | `GITHUB_TOKEN` / `gh auth` | unsigned (`.sha256` sidecar) | release notes from git/CHANGELOG | `SerZhyAle/internal_IP_manager` | anonymous ZIP download + `.sha256` match + PE read-back
- **WinGet** | PR to `microsoft/winget-pkgs` | [PUBLIC] | `gh` + CLA | Microsoft re-hosts | `publishing/winget/*.yaml` (CRLF, stamped by `scripts/stamp-winget.ps1`) | `SerZhyAle.InternalIPManager` (`internal_IP_manager.exe`) | `winget validate`, `winget install --manifest publishing/winget`, then `winget show --id SerZhyAle.InternalIPManager --exact --source winget`
- **Local drop folder** (legacy private copy, not a public channel) | manual `build.ps1 publish -Configuration Release` | free, private | filesystem write access to `C:\GD\tc\SZA\_APP` | unsigned | none | none | copied `internal_IP_manager.exe` runs on target machine

## Deltas by document

### PLATFORM_OVERLAYS.md
- No Store / MSIX channel by scope decision (`INTIPM-0023`); portable ZIP (`github` + `winget`) plus retained
  legacy local drop folder.

## No delta

- **AI_USAGE.md** - CONFIRM.
- **REPOSITORY_LAYOUT.md** - CONFIRM. `src/`, `publishing/winget/`, `site/`, `docs/` (35 registry records),
  `tasks/` (gitignored), `temp/` / `tmp/` (gitignored), root `README.md`, `CHANGELOG.md`, `LICENSE`,
  `THIRD-PARTY-NOTICES.txt`, `CLAUDE.md`, launchers (`r0`-`r3`, `rs`, `rm`, `rw`). Known warning `SZA-SEC05`
  on `src/UiTokens.vb` (`*token*` glob) is tracked in `INTIPM-0022`.
- **DEVELOPMENT.md / TESTING_AND_QA.md** - CONFIRM. `Debug.WriteLine`-only logging, ~500-line file budget,
  fast static checks (`build.ps1 check`) between releases, full build / `build.ps1 package` / run-and-observe
  reserved for release pre-flight (`.sza-profile.json` omits `commands.compileCheck`).
- **DOCUMENTATION_CONCEPT.md / SITE_CONFIGURATION.md** - CONFIRM. Dedicated static `site/` published via
  workflow artifact; `docs/DOCUMENT_REGISTRY.jsonl` (35 records); `docs/SECURITY.md` feeds `site/privacy.html`
  and `src/AboutPage.vb`.
- **CONTRACTS.md** - CONFIRM. `PACKAGE-VERSIONING` 0.10 Producer/Consumer; `ipnew.txt` remains private user
  data (`docs/contracts/NO-ROLE.md`).
- **WINDOWS_PACKAGING.md / CHANNEL_MATRIX.md** - CONFIRM. Portable `zip` + `portable` WinGet shape with no
  `Scope` or `Dependencies`, CRLF manifests, symlink resolution via `DeviceListStore.ExecutableDirectory()`.
