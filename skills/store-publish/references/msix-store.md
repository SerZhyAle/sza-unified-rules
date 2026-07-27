# MSIX and the Microsoft Store - the full payload

Reference for the `store-publish` skill, Leg 3. Everything here is measured in this portfolio.

## Identity - three values, reserved once

Partner Center > Product > **Product identity** yields three values that go into the manifest:

| Manifest field | Script parameter | Scope |
| --- | --- | --- |
| `Package/Identity/Name` | `-IdentityName` | **per product** - reserved fresh for each new app |
| `Package/Identity/Publisher` | `-Publisher` | **account-wide** - `CN=F98ACEDB-1E22-4C39-AF63-F9FCFE807DCD` |
| `Package/Properties/PublisherDisplayName` | `-PublisherDisplayName` | **account-wide** - `SZA` |

Changing Identity `Name` or `Publisher` **orphans every installed copy**. Reserve once, never change.

The Store ID, the Package Family Name and the IARC rating id are also per product. Look them up in the repo's
`STORE_PUBLISHING.md` "Reserved identity" table, else the `build-msix.ps1` parameter defaults, else the
contrib record's "Frozen anchors".

### The bare-build trap

**Never run `build-msix.ps1` bare.** The identity defaults are not consistent across the portfolio: three
repos default to the reserved Partner Center identity and are Store-correct on a plain build, while two
default to a self-sign placeholder (`CN=SerZhyAle` / `SerZhyAle`) and produce a **Store-invalid package**.
Those two only work because their release flow passes all three values on the command line.

Always pass the three values explicitly, then **read back the packed `<Identity>` element and assert it
matches** the reserved values before offering the file for upload.

## Version remap

Store constraint: a 4-part `Major.Minor.Build.Revision` with **revision forced to 0** (the Store reserves it)
and **each part <= 65535**. A second, less-known constraint: the MSIX Identity Version schema **forbids
leading zeros in any part**.

Two remaps exist because two date-stamp shapes exist:

- `YY.M.D.HHmm` -> `YY.(M*100+D).HHmm.0`. Example: `26.7.26.0410` -> `26.726.410.0`.
- `YY.MMDD.HHmm` -> int-cast each component, append `.0`. The zero-padded shape collides with the
  no-leading-zeros rule, so `26.0723.0957` becomes `26.723.957.0`, never `26.0723.0957.0`.

Derive it **mechanically**, never hand-typed. Then assert: revision is 0, every part `<= 65535`, no leading
zeros, and the result is strictly greater than the version currently published in the dashboard. The
date-based stamp makes monotonicity automatic - verify it anyway.

## Unsigned upload, Store re-signing

The package is built **unsigned** and uploaded that way; Microsoft re-signs during certification.

- No code-signing certificate lives in the repo and none is needed. The alternative unpackaged exe/MSI Store
  path *does* require a paid cert chaining to a Microsoft-trusted root.
- A Store-signed build also defuses AV heuristic false positives (`IDP.Generic` and friends) better than
  anything else.
- `-SelfSign` exists **only** for local sideload testing and produces a package that must never be uploaded.
  When self-signing, the certificate subject must equal `-Publisher` - which is precisely why the self-sign
  path uses a different Publisher, and precisely the source of the bare-build trap above.

Local-verify pitfalls, all hit in practice:

- `Square310x310Logo` requires a paired `Wide310x150Logo`. Drop the large tile if you have no wide one.
- `Add-AppxPackage` installs but does **not** launch. Start from the Start menu, or
  `explorer.exe "shell:AppsFolder\<PFN>!<AppId>"`.
- A path-independent single-instance mutex makes the packaged copy exit silently if a dev copy is running.

## Container virtualization - static pre-checks before packaging

MSIX runs the desktop app in a light container with file and registry virtualization. The same exe ships
packaged and unpackaged, so branch at runtime via `GetCurrentPackageFullName`. Grep for these before packing:

| Pattern found | Why it breaks | Replace with |
| --- | --- | --- |
| `HKCU\..\Run` autostart write | Silently virtualized and ignored at sign-in | manifest `windows.startupTask` (`Enabled="false"` so the user opts in). The UI checkbox should open `ms-settings:startupapps` and **read** task state from `..\AppModel\SystemAppData\<PFN>\<TaskId>\State`, or it is stuck showing "off" |
| `%LOCALAPPDATA%` write another process must read | Redirected into the package container; a sibling reader cannot find it | `%ProgramData%` when packaged - and have the reader check both paths |
| `HKCU\Software\Classes` file association | Cannot be written under MSIX | manifest `windows.fileTypeAssociation` |
| `netsh` / registry firewall step at install time | Not available | `desktop2:FirewallRules` |

`windows.startupTask` sets a floor of `MinVersion 10.0.17763.0` (1809) in `TargetDeviceFamily`.

Rule of thumb: anything writing to `%LOCALAPPDATA%` or `HKCU` that must be visible outside the process, or
survive a real logon, needs an MSIX-aware path.

Also assert `THIRD-PARTY-NOTICES.txt` is in the staged payload when third-party binaries are bundled.

## Two applications in one package

A single MSIX can ship a clickable GUI tile plus a hidden console tool: one `<Application>` as the Start-menu
tile, another with `AppListEntry="none"` exposed on PATH via a
`uap3:Extension Category="windows.appExecutionAlias"` with `<desktop:ExecutionAlias Alias="tool.exe"/>`.
Recognise this shape rather than assuming one exe per package, and declare the `uap3` and `desktop` namespaces
in `IgnorableNamespaces`.

## Listing content contract

Listing text is a **render target**, never re-authored per channel. The long form lives in the CHANGELOG,
README, or the listing source file; each channel gets the same text trimmed to *its* field caps.
**Read the caps from the console at submit time - they drift, never hardcode them.**

| Text | Source of truth | Rendered into |
| --- | --- | --- |
| What changed in this version | the CHANGELOG dated section (English, canonical technical ledger) | GitHub Release body verbatim, winget `ReleaseNotes` per locale, Store "What's new", site "What's new" |
| Product description / features | the repo's listing deck | Store Description + Product features, winget `Description`/`ShortDescription` trimmed |
| Search discoverability | `search-terms.<code>.txt` (Store) / winget `Tags` + `Moniker` | Store SearchTerm1..7, winget Tags |
| Identifiers (Store Title, copyright) | `shared.txt` - written identically into every language column | every Store language column |
| Privacy promise | the hosted privacy page | Store privacy URL, the data-safety form, the listing copy, the in-app text |

Known caps at time of writing: Store "What's new" 1,500 chars; Description 10,000; ShortDescription 1,000;
each Product feature 200; `runFullTrust` justification ~1,000.

**Languages are per surface.** One repo in this portfolio ships 13 Store listing languages, 3 winget locales,
and EN/RU/UK on the site and README - deliberately. The ten non-EN/RU/UK Store decks are machine-produced and
nothing in the copy claims otherwise. **"What's new" is authored in EN/RU/UK only**; the machine-translated
columns get the English text, because a release note is dated prose nobody proofreads twice. The Store
*Title* often stays in one language across every column even where the body text is localized.

Store search terms: at most 7 per language, no duplicates within a set, nothing on the forbidden list. Terms
are written **per listing language** - Store search matches literally, and nobody types an English phrase into
a Hindi or Arabic query box. The forbidden list must therefore carry non-Latin transliterations of the banned
terms, because a Latin-only list cannot guard non-English sets.

## Partner Center listing CSV - export-then-merge

You **cannot** upload a hand-authored listing CSV. Partner Center's `ID` values are account-specific and
undocumented; a direct upload is rejected with "the ID column contains incorrect entries".

The working flow: **Export listing -> merge-fill the language columns of *that* file (keeping `Field`/`ID`/
`Type` untouched) from the content source of truth -> Import.**

Eight rules, all measured:

1. **Add every language to the submission first** (Store listings > Manage additional languages). An import
   cannot create a column; a language not already there has its copy dropped **silently** - no error, no
   warning, nothing in the report.
2. **Re-take the export every time.** It carries the current submission's asset URLs and defines which
   columns the next import accepts. A partial import changes the submission, so a held export goes stale
   immediately.
3. **The import is all-or-nothing per LANGUAGE, not per file.** One invalid `DesktopScreenshot1` value once
   dropped ten languages while three imported cleanly.
4. **A relative image path is rejected** in a flat CSV upload. The only accepted value is the asset URL of an
   image already uploaded to the current submission - so an import can *reference* screenshots but never
   *create* them. Upload a new language's screenshot in the UI first, then re-export to pick up its URL.
5. **A listing is Incomplete until it has both a description and at least one screenshot.** A text-only
   language just sits there and Partner Center reports nothing.
6. **Never copy `OverrideLogosForWin10 = True` into a language with no `StoreLogo` rows of its own.** It holds
   the listing Incomplete with nothing shown on the page. It once stranded ten listings.
7. **Encoding**: UTF-8 **without** BOM, every field quoted, CRLF between records, no trailing newline.
   A Partner Center export arrives *with* a BOM - strip it.
8. Re-sending a field you did not need to change is another chance to have a language rejected. Prefer a
   terms-only mode that writes only the SearchTerm rows.

`ReleaseNotes` is left alone by the CSV flow and filled per submission in the UI.

**The builder self-test**: where a repo automates the listing, it should commit a real export with the copy
cells emptied and all language columns present, and running the builder with a fill-nothing switch against it
must produce a **byte-identical** output. That is the guarantee the builder cannot corrupt an export it does
not understand, and it makes the round trip checkable without a Partner Center session. Mark the fixture
`-text` in `.gitattributes` so git never normalizes its line endings. Run this round trip before any real
merge; recommend creating the fixture in any repo that lacks one.

## Submission click path

**First submission**: Apps and games > `<product>` > **Packages** (upload the unsigned `.msix`) >
**Store listings** (add every language in Manage additional languages **first**, then export/build/import,
upload screenshots) > **Properties** (category) > **Age ratings** (IARC) > **Pricing and availability**
(Free via the Retail price dropdown; markets) > Submit for certification. A few business days.

**Update**: **Create new submission** > replace the package (same identity, higher version) > refresh listings
and "What's new" > submit. The remap is monotonic so no manual bump is needed - verify it exceeds the
published version anyway.

**Listing materials**: privacy policy URL (required when the app touches keyboard, clipboard, or personal
data); at least one screenshot, PNG >= 1366x768 - real in-app captures beat composed marketing cards for a
media app; Store logos optional (the Store falls back to package logos) but box art improves the page;
Description; Product features; the `runFullTrust` justification.

## Age rating

**IARC is per content-profile, not per publisher.** A portfolio rating id does **not** transfer to an app that
can open arbitrary third-party or uncurated content - a stream player, a web view, a remote-media file
opener - because "uncontrolled online content" changes the questionnaire answers. File a fresh questionnaire
and answer honestly: no accounts, purchases, ads, or user-to-user publishing where that is true; uncontrolled
third-party content where that is true.

A stricter rating is a **coverage regression** and therefore a release-blocker under the owner's hard rule -
decide it before the release, never discover it after.

## Third-party licenses

Where the product bundles third-party binaries under a copyleft license, the **combined** redistribution is
governed by the stronger license. `THIRD-PARTY-NOTICES.txt` - component, license, upstream source URL, full
text or link - ships **inside every distributed package**: the release zip and the store package alike. Assert
its presence in the packed MSIX **and** in the release zip before either is published. Never strip it from
packaging.
