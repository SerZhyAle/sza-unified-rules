# winget - the full payload

Reference for the `store-publish` skill, Leg 2. Everything here is measured in this portfolio, not guessed.

## The manifest set

A winget package is three or more YAML files in one folder,
`manifests/<first-letter>/<Publisher>/<Package>/<version>/`:

- **version manifest** `<Id>.yaml` - `PackageIdentifier`, `PackageVersion`, `DefaultLocale`,
  `ManifestType: version`, `ManifestVersion`.
- **installer manifest** `<Id>.installer.yaml`.
- **default-locale manifest** `<Id>.locale.en-US.yaml`, plus optional `<Id>.locale.<code>.yaml`.

### Must change every release, and must be identical across all files

- `PackageVersion` - **quote it**. A bare numeric stamp like `2606120121` is otherwise read as a number.
- `InstallerUrl` - carries the version twice, in the tag and in the asset name.
- `InstallerSha256`.
- `ReleaseDate` - ISO `YYYY-MM-DD`.
- `ReleaseNotes` **per locale**, and `ReleaseNotesUrl`.

`ReleaseNotesUrl` convention is currently split in the portfolio: `/releases/tag/v<ver>` pins the notes to the
version the manifest describes, `/releases/latest` drifts as soon as the next release ships. Prefer the
tagged form; if the repo uses `/latest`, follow the repo and flag it.

### Must never change

- `PackageIdentifier` - ever, from the first merge.
- `PackageName` **where an installer exists** - it must equal the installed ARP DisplayName, which is how
  `winget upgrade` correlates an installed copy with the catalog entry. Rebranding the product does not
  release this: the name stays frozen and only the descriptions change.
  *Corollary*: this coupling exists only where an installer registers ARP. A portable-zip package has no ARP
  entry, which is why a portable product can legitimately carry a localized `PackageName` per locale.
- `ManifestVersion` - unless the winget-pkgs PR template asks for a newer schema. Do **not** bump it merely
  because a newer client exists. Check the highest directory in
  `microsoft/winget-pkgs/doc/manifest/schema/` rather than trusting memory. The portfolio currently sits on
  `1.12.0`.
- `MinimumOSVersion` / `Architecture` describe the **installer**, not the narrowest exe inside it. A setup.exe
  that also installs a 32-bit fallback for older Windows must declare the *lower* floor, or the package is
  hidden from exactly the machines the fallback exists to serve. Where a repo carries this as an in-file
  comment, do not "fix" it.

## The `update`-vs-`submit` branch

The repos contradict each other here; this is the arbitration.

- `wingetcreate update <Id> --version .. --urls .. --submit` rebuilds from the manifest **already published in
  winget-pkgs** and only bumps version, URL and hash. Your repo's `Description`, `ShortDescription`, `Tags`,
  `Moniker` and `ReleaseNotes` never reach the catalog.
- **Use `update` only when nothing but version/URL/hash changed.**
- **Otherwise use the folder form**: copy the manifests to a **yaml-only** scratch dir, substitute the
  placeholder tokens, validate, install-test, then `wingetcreate submit <dir>`.

Because almost every release changes `ReleaseNotes`, the folder form is the default.

Token styles differ per repo - `__VERSION__`/`__URL__`/`__SHA256__`, `REPLACE_VERSION`/`REPLACE_SHA256`/
`REPLACE_RELEASE_NOTES_<LANG>`, or literal values already substituted. Read the manifests.

**Why yaml-only**: `winget validate --manifest winget/` on the repo folder trips over a `README.md` in that
folder being parsed as YAML.

## Pre-submit verification ladder - all blocking, in order

1. Confirm the GitHub Release asset exists, and **re-hash it yourself**. Sidecars go stale after a rebuild.
2. `winget validate --manifest <yaml-only dir>` - **schema only**. It does not download the URL and does not
   verify the hash.
3. `winget settings --enable LocalManifestFiles`, then `winget install --manifest <dir>` - the only gate that
   verifies URL + SHA end to end.
4. Line endings: `git ls-files --eol -- manifests/<letter>/<Publisher>/<Pkg>/<ver>/*`.
   Bad is `i/mixed w/mixed attr/text=auto`; good is `i/mixed w/crlf attr/text=auto`.
5. Grep every substituted `ReleaseNotes` value for `': '` before validating - see the colon-space trap below.

For an Inno shape, additionally run
`setup.exe /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- /CURRENTUSER` and confirm exit 0 plus an ARP entry
with the right `DisplayVersion`. Pre-check Defender yourself with
`MpCmdRun.exe -Scan -ScanType 3 -File <asset>` before the pipeline does.

## Line endings - the gate and the repair

winget-pkgs rejects LF or mixed endings with `Validation-Line-Endings-Error`. Repair, preserving UTF-8
no-BOM and normalizing to CRLF:

```powershell
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
foreach ($file in Get-ChildItem '<dir>/*.yaml') {
  $c = [System.IO.File]::ReadAllText($file.FullName)
  $n = [System.Text.RegularExpressions.Regex]::Replace($c, '\r\n|\n|\r', "`r`n")
  [System.IO.File]::WriteAllText($file.FullName, $n, $utf8NoBom)
}
```

**Never edit manifests with `sed`** - default settings rewrite line endings and produce huge no-op diffs.
Set `git config core.autocrlf false` in the fork checkout so git does not rewrite on commit.

## The installer shape, and the four aborts that actually happened

Shape is chosen by install-time needs, not habit:

- **Portable zip** when the app needs no install-time work: `InstallerType: zip` +
  `NestedInstallerType: portable` + one `PortableCommandAlias` per exe.
- **Inno `setup.exe`** when it needs shortcuts, file associations, ARP presence, or install-time logic:
  `InstallerType: inno`, pointed at the setup.exe directly.
- **WiX MSI** where a channel demands `.msi` - usually still shipped to winget as zip+portable with the MSI
  as a direct-download sub-asset.

Four real aborts on one PR, ~12 hours lost:

| Shape | Failure |
| --- | --- |
| `single-exe.zip` self-extracting bootstrap | Defender ML flags `Program:Script/Wacapew.A!ml`. Persistent false positive. Never point winget at one. |
| Heavy portable zip (~99 MB) | Archive scan passes, extraction takes ~2 min, install aborts `0x80004004` (E_ABORT) mid-placement. The same shape works with a smaller payload. |
| Inno + `Dependencies: Microsoft.VCRedist.2015+.x64` | Dependency-resolution loop; VCRedist returns `0x8A150010`, package aborts `0x8A150044`. The app installs fine undeclared - validation never launches it. |
| Inno + `Scope: user` | Harness runs `--scope user` with `Elevation: False`, aborts `0x8A150044` "no suitable installer". **Omit `Scope` entirely.** |

The winning shape passes because it is not an archive (no local malware scan, no slow extraction), has no
dependency churn, and its `.iss` sets `AppVersion={#Version}` so the ARP `DisplayVersion` equals
`PackageVersion` - exactly what Installation Validation matches on. `PrivilegesRequired=lowest` installs
per-user.

## Error-code table

| Symptom | Cause and fix |
| --- | --- |
| `0x8A150044` | A declared `Dependencies` (drop VCRedist) **or** `Scope: user` (drop `Scope`). |
| `0x80004004` | Heavy portable-zip payload. Switch shape or shrink it. |
| `Program:Script/Wacapew.A!ml` | A self-extracting bootstrap zip was pointed at. Never do that. |
| `Validation-Line-Endings-Error` | Mixed or LF endings. Repair as above. |
| `mapping values are not allowed in this context` | A `': '` inside a substituted plain scalar - the YAML scanner reads it as a nested mapping. Use a spaced hyphen, or a block scalar (`ReleaseNotes: \|-`, `Description: >-`) which tolerates `: `. **First thing to check** when validation rejects a manifest that looks fine. |

**Non-blocking noise, ignore it**: the "Missing property `NestedInstallerType`/`NestedInstallerFiles` /
Sequence `Tags` contains fewer items" note is an informational `Validation-Guide` that fires whenever the
installer shape differs from the previously published version. "Signature Update failed / Inconclusive
Signature update" is the validation VM failing to update Defender signatures - environmental.

## Submit, PR body, and recovery

**Submit**: `wingetcreate` forks winget-pkgs, creates a branch `<PackageId>-<version>-<uuid>`, copies the
manifests into place, commits, and opens a PR titled `<PackageId> version <version>`. Prefer device-code or
browser auth over `--token`; `wingetcreate` itself warns the token may be logged. Scope `public_repo` only.
If a PAT ever leaks into a transcript, revoke it immediately.

**PR body is mandatory, not polish.** `wingetcreate` submits Microsoft's template untouched - empty
description, every box unticked - which reads as "nothing was verified" and stalls review. Generate the body
from the checks you actually ran, tick only those boxes, mark "Linked to an issue" as not applicable, apply
with `gh pr edit <n> --repo microsoft/winget-pkgs --body-file <file>`, then **re-read it to confirm**.
Never tick "tested with winget install locally" if you did not.

**Automated checks** (~10-30 min): ManifestValidation, InstallerValidation (downloads, verifies SHA256,
SmartScreen, sandbox install), URLValidation, DefenderScan. Then `Validation-Completed` and a human moderator
queue - hours to days, with extra scrutiny for first-time publishers.

**Recovery**: patch the existing PR branch; never re-run `wingetcreate submit`, which opens a second PR.
Cloning a fork of winget-pkgs is multi-GB, so use a partial clone with sparse-checkout:

```bash
git init -q; git remote add origin https://github.com/<you>/winget-pkgs.git
git config core.sparseCheckout true
echo "manifests/s/SerZhyAle/<Pkg>/" > .git/info/sparse-checkout
git fetch --depth 1 origin <pr-branch>; git checkout -q FETCH_HEAD
```

A push to the PR branch is the reliable re-validation trigger; `@wingetbot run` may fail with "Commenter does
not have sufficient privileges".

**Do not thrash.** After submitting, wait for a result before changing anything - every push or
`@wingetbot run` cancels the in-flight run and re-queues from scratch. A PR sitting in `REVIEW_REQUIRED` is
waiting for a human, not erroring. Pick one shape and stop changing it.

**Read the real error** from the build's `InstallationVerificationLogs` artifact, which is anonymously
downloadable - not from the generic bot comments:

```powershell
$org="shine-oss"; $proj="8b78618a-7973-49d8-9174-4360829d979b"; $build=<id>
$arts = Invoke-RestMethod "https://dev.azure.com/$org/$proj/_apis/build/builds/$build/artifacts?api-version=7.0"
$u = ($arts.value | ? name -eq 'InstallationVerificationLogs').resource.downloadUrl
```

Read `*Log_InstallationClient*.txt` for the exit code and `*WinGet-*.log` for the terminating HRESULT. The
`<id>` is in the `WinGetSvc-Validation-...-<id>` link the bot posts.

## Locales

The default-locale manifest is mandatory. Additional `<Id>.locale.<code>.yaml` files are optional, and each is
prose a human must re-check every release because `ReleaseNotes` is per locale.

Locale coverage is **per surface**, not one uniform set - a locale present on the site is not a gap in winget.
Read the existing locale file set as the contract and **never add or drop one on your own initiative**.

## Discoverability

`Tags` + `Moniker` + `ShortDescription` are the winget discoverability surface; fill every slot with a
distinct user phrase. Note that a Store forbidden-terms list is **Store-scoped** - winget has no
infringing-content review - so do not propagate the ban to winget silently, and do not silently allow a banned
term back into the Store. Surface the discrepancy for an owner decision.
