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
nothing to ship. Also present but already-saturated: `Debug.WriteLine`-only logging, run-and-observe
as the top of the evidence ladder, a `tasks/TASK-N.md` Markdown spec lifecycle (CONFIRM of the core's
per-file `docs/specifications` model, no catalog CLI).

## Overlay facts (verified against this repo)

- **Source root & release-mechanics.** Source in `src/` (flat: `Form1.vb`, `Columns.vb`,
  `AppSettings.vb`, `FormSettings.vb`, `RouterClient.vb`, `RouterSync.vb`); `.sln` at repo root.
  **No `publishing/` folder, no `tests/`, no `.github/`.** Release-mechanics is a single `build.ps1`
  dotnet wrapper whose `publish` task emits a self-contained single-file `win-x64` exe to a **local
  drop folder `C:\GD\tc\SZA\_APP`** - the entire "distribution" (evidence: `build.ps1:32-33,61-81`,
  root `ls` shows no `publishing/`/`tests/`/`.github/`).
- **Version shape (+ padding choice).** **None.** The `.vbproj` sets no `<Version>`/`<AssemblyVersion>`;
  nothing is stamped, tagged, or date-shaped. An unversioned internal tool - DIVERGE from the Overlay A
  date-tag rule, legitimate because no update is ever correlated to an install (evidence:
  `grep -i version src/internal_IP_manager.vbproj` -> no match; `git rev-list --count --all` -> 0).
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
- **REPOSITORY_LAYOUT.md** - CONFIRM. `src/` + `docs/{...}` + `tasks/` + `tmp/` (gitignored) + root
  `README`/`CHANGELOG`/`LICENSE`/`CLAUDE.md`; `.gitignore` points at `bin/`/`obj/`/`.vs/`/`tmp/`.
- **DEVELOPMENT.md / TESTING_AND_QA.md** - CONFIRM. `Debug.WriteLine`-only logging, ~500-line file
  budget, run-and-observe as the top (and only) rung of the evidence ladder (no tests/linter/CI).
- **DOCUMENTATION_CONCEPT.md** - CONFIRM. Single-source-of-truth `CHANGELOG.md [Unreleased]`;
  `Col.*` constants as the column single-source-of-truth.
- **GITHUB_INTERACTION.md** - N/A at survey time: the repo has **zero commits and no remote** (see
  open questions).

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
- **Zero git history.** The repo is `git init`'d on `main` with **no commits and no remote** - every
  file is untracked. A spread-back commit here is therefore the repository's **initial commit** (the
  whole codebase), not an incremental one. Owner to confirm: make the initial commit now, or keep the
  spread-back edits staged for a separate commit?
- **No CI / no release pipeline by design?** Confirm the tool is meant to stay internal-only
  (file-copy distribution), so the missing `publishing/` + version stamp are a deliberate DIVERGE, not
  a gap to fill later.

## Spread-back applied 2026-07-23

Ran SPREAD_BACK_PROMPT in `p:\WINDOWS\internal_IP_manager` as a **NEW** repo (no prior contrib record).
Consumption model = **REFERENCE** (repo `CLAUDE.md` links to the canon, keeps only deltas locally; no
mirror). The repo already carried a mature "Universal Agent Kit"-adapted `CLAUDE.md` that predated the
canon.

**Changed in the repo:**
- **`CLAUDE.md`** - added a **"Unified Rules (canon)"** section (consumption model = REFERENCE, canon
  path, the Overlay A source-shape-only / internal-unshipped-tool DIVERGE, run-and-observe evidence
  ladder). Replaced the "AI assistant working method (Universal Agent Kit)" restated-universals intro
  with a pointer to `Unified_Rules/AI_USAGE.md`, keeping only the repo deltas (skill routing, `tasks/`
  ticket lifecycle, verification tags, project facts). Reconciled drift against the live tree:
  AppSettings now carries the router-sync settings (was "Currently just `IpRange`"); added
  `RouterClient.vb` + `RouterSync.vb` to the architecture map (TASK-6, absent before); `Form1.vb` line
  count corrected ~535 -> ~650; "What this is" now mentions the router DHCP sync.

**Open questions - status:**
- **Zero git history / initial commit** - RAISED to owner (not auto-resolved); a first commit bundles
  the whole repo, an owner decision.
- **Internal-only by design** - recorded as a DIVERGE; treated as deliberate.

**Verification (fresh run, PowerShell - dotnet not on the Bash PATH here):**
- `dotnet build internal_IP_manager.sln -c Release` -> **Build succeeded, 0 Warning(s), 0 Error(s)**,
  exit 0.

**Canon fixes needed (none blocking):** one PROPOSED core edit (Overlay A "internal / private tool"
note) - left for an owner-run canon session, not applied from this repo's session.

## Canon adoption 2026-07-27

Adopted as the `sza` plugin (consumption model **reference**), committed. `.sza-canon.json` declares role
**internal**: no remote, no tags, no CI, no site, no store. Most checks are legitimately N/A - a shape, not a
gap, and now written down so the gate degrades instead of inventing channels.

Fixed: the `CHANGELOG.md` heading is now `## [Unreleased]`, so the ledger is the shape it claims to be; 127
prose em-dashes across the docs, the worst style backlog in the portfolio.

Compliance gate: **0 errors**, 1 warning (`docs/` has no index).

## Canon reconcile 2026-08-02 - agent-process propagation

Canon **2026.07.27 -> 2026.08.02**, core digest `sha256:dae220bf..` -> `sha256:6c247452..`. Stamp
updated; the adoption model is unchanged. The upstream change is [AI_USAGE.md](../AI_USAGE.md) only -
the agent-process findings propagated from FastMediaSorter mob_v2 under its ticket S1342 - so the
staleness ladder's "re-read only the changed rule docs" path applies and no full re-adoption was run.
Nothing in `rules/` touched packaging, release, channels or layout, and no divergence was found
between the new bullets and this repo's own rules file.

Deliberately has no in-repo memory store - its rules file says creating one would fork the shared
store - so §4 is inert by an existing decision rather than by absence, and the new bullets must not be
read as an invitation to create one. Role is `internal`, so the surface and channel checks stay out of
scope; the applicable additions are §1's threshold and §2's closure invariants.

Verification: `check-compliance: internal_IP_manager - 0 error(s), 1 warning(s) (overlay A, canon 2026.08.02)` - warnings are pre-existing and none was introduced here.

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

Finding 2 has a target here and is one step worse than the finding describes: `/quick` and `/fix` exist
among thirteen commands, `.claude/settings.json` declares no hooks, and `CLAUDE.md` does not order the
commands by size at all - so there is not even the prose that the measurement showed to be insufficient.
Whoever writes the routing nudge here writes the ordering at the same time. Carried as an owner decision,
not applied from this session.

Verification: `check-compliance: internal_IP_manager - 0 error(s), 1 warning(s) (overlay A, canon 2026.08.05)` -
the warning is pre-existing and none was introduced here.
