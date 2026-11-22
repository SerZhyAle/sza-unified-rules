---
# Contribution: internal_IP_manager (overlay A source shape only - internal, unshipped, unversioned desktop tool; single edition) -> Unified_Rules
Source repo: p:\WINDOWS\internal_IP_manager | Date: 2026-07-23
Read: README, NEW_PROJECT_CHECKLIST, TEMPLATE, PLATFORM_OVERLAYS, AI_USAGE; deduped against: contrib/{cyrflip,streams_player,filedo,fastmediasorter_lite}.md
---

internal_IP_manager is a single-window VB.NET WinForms desktop app (.NET 8, `net8.0-windows`) that
manages a CSV list of LAN devices - ping/online status, IP-range scan, hostname/MAC resolve, and a
TP-Link Archer BE550 DHCP-reservation sync. It uses the **Overlay A source shape** (`src/` flat, a
`build.ps1` dotnet wrapper) but is **not a shipped product**: it has no distribution channel at all -
no GitHub Release, no winget, no Store, no installer, no version stamp, no frozen anchors. Its
genuinely new material is exactly that shape: an **internal tool that consumes the engineering/agent
core but none of the release/distribution/channel machinery**, distributed by a plain file copy to a
local shared drop folder. Everything the shared docs already saturate for shipped Overlay A products
(channels, MSIX remap, winget-portable, frozen anchors) is **N/A here, not CONFIRM** - there is
nothing to ship. Also present: `Debug.WriteLine`-only logging, run-and-observe as the top of the
evidence ladder, and the shipped harness task-flow (`tasks/INTIPM-####_<slug>.md`, legacy closed tickets
keep `TASK-####`, `.sza-profile.json`, `tasks/spec-catalog.jsonl`, `tools/harness.ps1`, `r0`-`r3`, `rs`, `rm`, `rw`).

> **Keep this note in the record.** Current facts, edited in place. Never append a dated section to this file:
> what happened and when goes to the file of the same name under `history/`
> ([the rules of that folder](history/README.md)), which is not reading for a task. A delta the core absorbed,
> a candidate that was applied or refused and a question that was answered are deleted here; the history
> section of that day says what became of them.

## Overlay facts (verified against this repo)

- **Source root & release-mechanics.** Source in `src/` (flat: `Form1.vb`, `Columns.vb`,
  `AppSettings.vb`, `FormSettings.vb`, `RouterClient.vb`, `RouterSync.vb`, plus UI/help/identity modules
  `UiTokens.vb`, `Theme.vb`, `Palette.vb`, `UserMessages.vb`, `CommandRow.vb`, `HelpAsk.vb`,
  `HelpContent.vb`, `HelpLayer.vb`, `HelpMap.vb`, `ProductIdentity.vb`, `DiagnosticReport.vb`, etc.); `.sln`
  and task-flow launchers (`r0`-`r3`, `rs`, `rm`, `rw`, forwarding through `tools/harness.ps1`) at repo root.
  **No `publishing/` folder, no `tests/`, no `.github/`.** Release-mechanics is a single `build.ps1`
  dotnet wrapper (`check` for <= 5 s fast checks including `scripts/check-help.ps1`; `rebuild`/`publish`
  release-tier, recording builds in `docs/releases/` via `release-ledger.ps1`) whose `publish` task emits
  a self-contained single-file `win-x64` exe to a **local drop folder `C:\GD\tc\SZA\_APP`** (evidence:
  `build.ps1`, root `ls`).
- **Version shape (+ padding choice).** **None.** The `.vbproj` sets no `<Version>`/`<AssemblyVersion>`;
  nothing is stamped, tagged, or date-shaped. An unversioned internal tool - DIVERGE from the Overlay A
  date-tag rule, legitimate because no update is ever correlated to an install (evidence:
  `grep -i version src/internal_IP_manager.vbproj` -> no match).
- **Channels + listing files.** **None.** No public channel; the only "publish" is `build.ps1 publish`
  copying the exe to `C:\GD\tc\SZA\_APP`. No listing files, no store copy, no README-as-listing
  (evidence: `build.ps1:77-81`).
- **Frozen anchors.** **None to reserve.** No winget `PackageIdentifier`, no Inno `AppId` / WiX
  `UpgradeCode`, no MSIX Identity - nothing is installed through an anchor-bearing mechanism. The
  install "location" is a shared folder path, not an update-correlating id (evidence: no
  `publishing/`, no manifest of any kind in tree).
- **Editions + parity mechanism.** **None - single edition.** One codebase, one artifact, no flavor
  / dual-runtime / companion binary / editor extension (evidence: one `.vbproj`, one exe).

## Channel-matrix rows (this project)
Format: Channel | Trigger | Cost | Auth | Signer | Listing source | Frozen anchor | Verify live
- **Local drop folder** (not a public channel) | manual `build.ps1 publish -Configuration Release` | free, private | filesystem write access to `C:\GD\tc\SZA\_APP` | unsigned | none | none | the copied `internal_IP_manager.exe` runs on the target machine (evidence: `build.ps1:61-81`).

## Deltas by document

### PLATFORM_OVERLAYS.md
- DIVERGE (a legitimate **"internal tool" degenerate of Overlay A** - source shape, zero distribution):
  the Overlay A "no-installer variant" (streams_player, cyrflip) still collapses the frozen-anchor set to
  {winget `PackageIdentifier`, MSIX Identity} and still ships to **winget + Store**. internal_IP_manager
  goes one step further: it ships to **no public channel at all** - no version shape, no frozen anchors,
  the "release" is a file copy to a shared folder. It consumes the core's source-shape and engineering
  discipline but none of the release/channel/anchor machinery. Worth one line in Overlay A noting that a
  private internal tool may legitimately have an **empty distribution set** (no version tag, no anchors) -
  the four overlay questions collapse to just "source root" (evidence: `build.ps1:32-33,61-81`, no
  `publishing/`, no `<Version>`).

## No delta

- **AI_USAGE.md** - CONFIRM. Autonomy/evidence/memory/communication all match; the repo's `CLAUDE.md`
  is already an AI_USAGE-shaped rules file with skill routing (`.claude/commands/`) and native
  per-project memory (no in-repo `memory/`). Nothing beyond core.
- **REPOSITORY_LAYOUT.md** - CONFIRM. `src/` + `docs/` (with `docs/contracts/`, `docs/releases/`,
  `docs/DOCUMENT_REGISTRY.jsonl`) + `tasks/` (gitignored, with `RELEASE_QUEUE.md`/`RELEASE_READY.md`/
  `RELEASE_DONE.md`) + `temp/` + `tmp/` (gitignored) + root `README`/`CHANGELOG`/`LICENSE`/`CLAUDE.md`/
  launchers (`r0`-`r3`, `rs`, `rm`, `rw`). Known warning `SZA-SEC05` on `src/UiTokens.vb` (`*token*` glob)
  is tracked in `INTIPM-0022`.
- **DEVELOPMENT.md / TESTING_AND_QA.md** - CONFIRM. `Debug.WriteLine`-only logging, ~500-line file
  budget, fast static checks (`build.ps1 check`) between releases, full build and run-and-observe
  reserved for release pre-flight (no tests/linter/CI; `.sza-profile.json` omits `commands.compileCheck`).
- **DOCUMENTATION_CONCEPT.md** - CONFIRM. Single-source-of-truth `CHANGELOG.md [Unreleased]`;
  `Col.*` constants as column single-source-of-truth; `docs/DOCUMENT_REGISTRY.jsonl` (31 records,
  `docRegistryShape` 1).
- **CONTRACTS.md / PROMOTION.md** - CONFIRM. No shared wire/data contract (`docs/contracts/NO-ROLE.md`,
  `ipnew.txt` is private user data); consumes rule-adoption, UI, help, identity, doc-quality and
  release-ledger contracts (`docs/contracts/README.md`). Internal tool with no remote: no promotion ticket.
- **GITHUB_INTERACTION.md** - CONFIRM (local git only, 5 commits, no remote).

## Candidate core edits (PROPOSED - apply only on owner instruction)

- **PLATFORM_OVERLAYS.md, Overlay A**: add a one-line "internal / private tool" note - an Overlay A
  source-shape app may legitimately ship to **no public channel**, with no version shape and no frozen
  anchors (distribution = a file copy to a local/shared path). Distinguishes "unshipped internal tool"
  from the already-documented "no-installer but still winget+Store" variant. Prevents an agent from
  fabricating a version stamp / winget manifest for a tool that deliberately has none. Evidence:
  `build.ps1:32-33,61-81`.

## Candidate NEW docs (not in any shared doc yet)
- None required.

## Open questions for the owner
- **No CI / no release pipeline by design?** Confirm the tool is meant to stay internal-only
  (file-copy distribution), so the missing `publishing/` + version stamp are a deliberate DIVERGE, not
  a gap to fill later.

