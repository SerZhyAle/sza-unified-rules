---
# Contribution: SZA Windows Suite (Overlay A) -> Unified_Rules
Source repo: P:\WINDOWS\sza-windows-suite | Date: 2026-11-15 23:20
Read: rules/PLATFORM_OVERLAYS.md, rules/WINDOWS_PACKAGING.md, rules/CHANNEL_MATRIX.md; deduped against: contrib/fastmediasorter_lite.md, contrib/cyrflip.md, contrib/filedo.md
---

SZA Windows Suite (`win-suite`) is a unified application discovery hub, workflow synergy explorer, and selective component installer for Windows tools in the SZA portfolio. Distributed via GitHub Releases, winget, and Microsoft Store as both an online bootstrapper and an offline standalone installer bundle.

> **Keep this note in the record.** Current facts, edited in place. Never append a dated section to this file:
> what happened and when goes to the file of the same name under `history/`
> ([the rules of that folder](history/README.md)), which is not reading for a task. A delta the core absorbed,
> a candidate that was applied or refused and a question that was answered are deleted here; the history
> section of that day says what became of them.

## Overlay facts (verified against this repo)

The four overlay facts + editions, each with evidence:

- **Source root & release-mechanics.** Source in `src/SzaWindowsSuite/` (C# / .NET 10 WPF), tests in `tests/SzaWindowsSuite.Tests/`. Packaging grouped under the `publishing/` umbrella: `publishing/installer/` (Inno Setup `setup.iss`), `publishing/winget/` (3 manifests), `publishing/msix/` (`AppxManifest.xml`, `build-msix.ps1`), and `publishing/store/` (`listingData.csv`). (evidence: filesystem)
- **Version shape (+ padding choice).** Monotonic date stamp `YY.MMDD.HHmm` (for example, `26.1115.2300`), tagged as `v<stamp>`, remapped for MSIX as `Major.Minor.Build.0`. (evidence: `CLAUDE.md`, `.sza-canon.json`)
- **Channels + listing files.** GitHub Releases (`setup.exe` and `.zip`), winget (`publishing/winget/SZA.WindowsSuite.*.yaml`), and Microsoft Store (`publishing/msix/AppxManifest.xml`). (evidence: `publishing/`)
- **Frozen anchors.** winget `PackageIdentifier: SZA.WindowsSuite`, Inno Setup `AppId: {{B8799C0A-90D1-4E15-992F-437EE8D36622}}`, MSIX Identity Name `SZA.WindowsSuite`, Publisher `CN=Serhii Zhyhunenko`. (evidence: `CLAUDE.md`, `publishing/installer/setup.iss`, `publishing/msix/AppxManifest.xml`)
- **Editions + parity mechanism.** None - single edition. Produces dual delivery artifacts: online bootstrapper and offline bundle. (evidence: `tools/assemble-suite.ps1`)
- **Command surface & single-instance activation.** `APP-COMMANDS` 0.3 (`docs/cli-commands.json` compiled verbatim in `CliCommandManifest.cs`, rendered into `docs/CLI.md`) exposes five `safe` base verbs (`commands`, `version`, `status`, `show`, `quit`) at `cliVersion` 1.0 alongside the `install` family; `APP-ACTIVATION` 0.16 uses per-session mutex `Local\SzaWindowsSuiteSingleInstance` (`SingleInstanceLock.cs`), named pipe `\\.\pipe\sza-windows-suite-single-instance` created `CurrentUserOnly` (`ActivationPipe.cs`) with 1000 ms bounded connect and no-vanish fallback, `ForegroundActivation` (`SMTO_ABORTIFHUNG` 50 ms probe), no URI scheme, and no network listener. (evidence: `src/SzaWindowsSuite/Activation/`, `src/SzaWindowsSuite/Cli/CliCommandManifest.cs`, `docs/cli-commands.json`)

## Channel-matrix rows (this project)

Format: Channel | Trigger | Cost | Auth | Signer | Listing source | Frozen anchor | Verify live
- GitHub | git tag v* push | $0 | GITHUB_TOKEN | None | publishing/installer/ | setup.exe, zip | release page
- winget | release publish | $0 | WINGET_TOKEN | None | publishing/winget/ | SZA.WindowsSuite | winget show SZA.WindowsSuite
- Store | release publish | $0 | PARTNER_CENTER | Microsoft | publishing/store/ | SZA.WindowsSuite | Store PDP

## Deltas by document

### PLATFORM_OVERLAYS.md
- CONFIRM (Overlay A): confirms standard Overlay A packaging structure under `publishing/` umbrella with Inno Setup, winget, and MSIX.

### WINDOWS_PACKAGING.md
- CONFIRM (Inno + winget): confirms Inno Setup modern wizard style with silent command-line flags and winget manifest pairing.

## No delta

Core docs verified with nothing to add: INVARIANTS.md, DEVELOPMENT.md, TESTING_AND_QA.md, REPOSITORY_LAYOUT.md, DOCUMENTATION_CONCEPT.md.

## Candidate core edits (PROPOSED - apply only on owner instruction)

None required.

## Candidate NEW docs (not in any shared doc yet)

None required.

## Open questions for the owner

None. All reversible technical choices assumed and confirmed.
