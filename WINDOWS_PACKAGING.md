# Windows Packaging - the delivery-shape decision guide

One front door for "how does a Windows product ship". The facts themselves stay in their homes -
[CHANNEL_MATRIX.md](CHANNEL_MATRIX.md) (per-channel playbooks), [PLATFORM_OVERLAYS.md](PLATFORM_OVERLAYS.md)
Overlay A (folder shapes, version remaps, frozen anchors), [DEVELOPMENT.md](DEVELOPMENT.md) §13-14 and §16
(build parity, migration pins, native hardening). This doc only *chooses between them* and maps where
each detail lives - do not restate rules here, link them.

## 1. Choose the delivery shape

| Shape | Pick it when | Installer folder | winget form | Extra frozen anchors | Reference |
| --- | --- | --- | --- | --- | --- |
| **Portable zip** (no installer) | the app needs no install-time work: no shortcuts, associations, or PATH entry | none | `zip` + `portable` (one alias per exe) | none beyond the base set | `StreamsPlayer`, `CyrFlip` |
| **Inno setup.exe** | the app needs shortcuts, file associations, ARP presence, or install-time logic (OS-dependent exe selection, pre-uninstall stop) | `installer/*.iss` | `inno`, pointed at the setup.exe directly | Inno `AppId`, `UninstallDisplayName`, `DefaultDirName` | `FastMediaSorter_Lite` |
| **WiX MSI** | a channel demands an installable `.msi`, or per-machine PATH/registry is required | `packaging/wix/*.wxs` | usually `zip` + `portable`, with the MSI as a direct-download sub-asset | WiX `UpgradeCode` (+ its registry hive) | `FileDO` |

Every shape ships the **Microsoft Store MSIX** beside it (unsigned upload, Store re-signs) and the
**GitHub Release** as the authoritative asset host. Base frozen-anchor set for all shapes: winget
`PackageIdentifier` (plus `PackageName` = installed ARP DisplayName where an installer exists) and MSIX
Identity `Name` + `Publisher`. Reserve-once rules: PLATFORM_OVERLAYS Overlay A, fact 4.

Default to the **portable zip** until a requirement in the second column forces an installer - the
no-installer variant has the smallest anchor set and no installer identity to freeze.

## 2. Version stamping map

- The date-stamp shapes (dotted `YY.M.D.HHmm`, zero-padded `YY.MMDD.HHmm`, separator-less `yyMMddHHmm`)
  and both MSIX remaps (`M*100+D`; no-leading-zeros int-cast with the `<=65535` guard):
  PLATFORM_OVERLAYS Overlay A "Version shape".
- Pin the release build to the tag when the stamp is computed at build time: RELEASE_AND_DISTRIBUTION §4.
- PE `VS_VERSIONINFO` + app-manifest stamping for native (Go) exes: DEVELOPMENT §16.

## 3. Where the traps live

- winget validation failure modes (no `Scope` / no `Dependencies`, never a self-extracting zip, CRLF-only
  manifests, the `PackageName`/ARP coupling, the `MinimumOSVersion` anti-pattern): CHANNEL_MATRIX winget
  playbook.
- MSIX container traps (virtualized HKCU Run and `%LOCALAPPDATA%` -> use `%ProgramData%` for
  cross-process files, `uap5:StartupTask`, `desktop2:FirewallRules`, two `<Application>` in one package,
  Partner Center program choice, listing CSV export-then-merge): CHANNEL_MATRIX MSIX playbook.
- A disabled-Actions repo silently ignoring a `v*` tag push: CHANNEL_MATRIX GitHub Release playbook.
- Two exes from one source tree (dual-runtime) and co-shipped companion binaries: PLATFORM_OVERLAYS
  "Co-shipping shapes" + DEVELOPMENT §13.
- Runtime migration pins (DPI, ICU-vs-NLS collation, default font, `Assembly.Location`): DEVELOPMENT §14.
- Go-on-Windows release hardening (keep symbols, `-trimpath`, `CGO_ENABLED=0`): DEVELOPMENT §16.
- Store category scrutiny (stream players, keyboard hooks) and IARC per content profile:
  SECURITY_AND_PRIVACY §5.

## 4. Applying to a new Windows project

1. Pick the shape from §1 by install-time needs, not habit.
2. Reserve the shape's frozen anchors once (PLATFORM_OVERLAYS Overlay A, fact 4).
3. Wire winget with the shape's form and local-install-test the manifest (CHANNEL_MATRIX).
4. Build the MSIX unsigned; upload via the Partner Center web flow (CHANNEL_MATRIX MSIX playbook).
5. Verify the update path from a real prior install, not just a fresh one (RELEASE_AND_DISTRIBUTION §6).
