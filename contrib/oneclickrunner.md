---
# Contribution: OneClickRunner (Overlay A - Windows desktop, single channel = GitHub Release portable-zip, no winget/Store; single edition) -> Unified_Rules
Source repo: P:\WINDOWS\OneClickRunner | Date: 2026-07-23
Read: README, NEW_PROJECT_CHECKLIST, PLATFORM_OVERLAYS (Overlay A), AUTHOR; skimmed AI_USAGE,
DEVELOPMENT, TESTING_AND_QA, GITHUB_INTERACTION, REPOSITORY_LAYOUT, DOCUMENTATION_CONCEPT,
SITE_CONFIGURATION. Deduped against: contrib/filedo.md, contrib/streams_player.md.
---

OneClickRunner is a WPF/.NET 8 (`net8.0-windows`) single-project launcher: it runs configured
apps/scripts ("scenarios") from the taskbar **Jump List** and a **system-tray icon**. It uses Overlay A's
**source shape and version shape** but is the portfolio's first **undistributed** desktop app - it ships
through **no channel at all** (no GitHub Release, no winget, no MSIX/Store, no installer). Its only
"release" is a local `Copy-Item` of a single-file exe to a hardcoded dir. Everything about the desktop
source/version shape is CONFIRM against `FastMediaSorter_Lite` / `FileDO`; the one genuinely new thing is
the **zero-distribution, zero-frozen-anchor** end of the Overlay A spectrum (a step below the portable-zip
"no-installer variant" that `StreamsPlayer` anchors, which still ships a GitHub zip + winget).

## Overlay facts (verified against this repo)

- **Source root & release-mechanics.** Single WPF project `OneClickRunner/` (**not** `src/`); solution
  `OneClickRunner.sln` at root. **No `publishing/` and no per-channel folders** - there are no channels.
  Release-mechanics = one root `build.ps1`: `dotnet publish -c Release -r win-x64 --self-contained false
  -p:PublishSingleFile=true`, then `Copy-Item` the exe to a **hardcoded** `C:\GD\tc\SZA\_APP` (evidence:
  `build.ps1:1-3,10-14,37`; root `ls` shows `OneClickRunner/`, `OneClickRunner.sln`, `build.ps1`, no
  `publishing/`).
- **Version shape (+ padding choice).** Zero-padded date tag **`YY.MMdd.HHmm`**, stamped at build from
  `DateTime.Now.ToString("yy.MMdd.HHmm")` in the csproj (`ProductVersion` -> `Version` /
  `InformationalVersion`). No git tag, no channel remap (no channels to remap into). A valid Overlay A
  padding form (evidence: `OneClickRunner/OneClickRunner.csproj` `ProductVersion` line).
- **Channels + listing files.** **Exactly one channel: GitHub Release** (portable
  `OneClickRunner-<version>-win-x64.zip` + `.sha256`, framework-dependent). No winget, no MSIX/Store, no
  installer. Release-mechanics: `release.ps1` (the only tagger) publishes, zips, writes the sha256, tags
  `v<version>`, pushes it, and runs `gh release create`; release notes come from the `## [<version>]`
  section of the root `CHANGELOG.md`. `LICENSE` (MIT) + `CHANGELOG.md` are at root. A GitHub Pages **site**
  is served from `docs/` (hand-authored `index.html` + `guide.html` + `assets/` + mirrored `sza-kit.css` +
  `.nojekyll`) at `serzhyale.github.io/OneClickRunner/` (evidence: `release.ps1`; `CHANGELOG.md`;
  `LICENSE`; `git ls-files docs/`).
- **Frozen anchors.** **None - and none needed.** GitHub Release is a plain download with no
  update-correlation id; there is no winget `PackageIdentifier`, no Inno `AppId` / WiX `UpgradeCode`, no
  MSIX Identity to reserve. (The no-installer variant in the canon collapses the anchor set to
  `{winget PackageIdentifier, MSIX Identity}`; a **GitHub-Release-only** portable collapses it to
  **empty**.) Stable *runtime* identifiers - mutex `OneClickRunner_SingleInstance_Mutex`, IPC pipe
  `OneClickRunner_Command_Pipe`, deploy dir `C:\GD\tc\SZA\_APP` - are not distribution anchors (evidence:
  `App.xaml.cs`; `build.ps1:3`).
- **Editions + parity mechanism.** **None - single edition, single binary.** Not a flavor, not a
  co-shipped companion, not a dual-runtime variant (evidence: one `.csproj`, one `WinExe` output).

## Channel-matrix rows (this project)
Format: Channel | Trigger | Cost | Auth | Signer | Listing source | Frozen anchor | Verify live
- **GitHub Release** | `release.ps1` -> `v<version>` tag push + `gh release create` | free (public repo),
  [PUBLIC]/irreversible | `gh auth` ambient (SerZhyAle) | unsigned (SmartScreen reputation) | root
  `CHANGELOG.md` `## [<version>]` section | - (no anchor) | `gh release view v<version>`; zip + sha256
  present (evidence: `release.ps1`; `CHANGELOG.md`).
- The local `build.ps1` `Copy-Item` to `C:\GD\tc\SZA\_APP` remains a developer-local **deploy**, not a
  channel. The GitHub Pages **site** (`docs/`) distributes docs, not the binary (evidence: `build.ps1:37`).

## Deltas by document

### PLATFORM_OVERLAYS.md
- DIVERGE (a **GitHub-Release-only** portable has an **empty** frozen-anchor set): the Overlay A
  "no-installer variant" collapses the anchor set to `{winget PackageIdentifier, MSIX Identity}` for a
  portable-zip app - but it still assumes **winget + Store** alongside the GitHub zip. OneClickRunner ships
  the portable zip through **GitHub Release only** (no winget, no Store, no installer), so it has **no
  update-correlation id at all** - the anchor set collapses to **empty**. The Overlay A source shape and the
  `YY.MMdd.HHmm` version shape still fully apply, and `release.ps1` is the single tagger. This "one channel,
  no anchors" shape sits one step below the documented no-installer variant (evidence: `release.ps1`; no
  `winget/`, no `msix/`, no `installer/`).

### REPOSITORY_LAYOUT.md
- CONFIRM (root `CHANGELOG` + `LICENSE` added this session): the layout makes them standard; both were
  absent and are now present - `LICENSE` (MIT, matching the family) and `CHANGELOG.md` (house `[Unreleased]`
  flow, feeding the GitHub Release notes). No longer a divergence (evidence: `LICENSE`, `CHANGELOG.md`).

### AI_USAGE.md
- CONFIRM (canon-preferred agent-rules shape): the single canonical rules file is **`CLAUDE.md`**, with
  `AGENTS.md` a thin delegator ("read `CLAUDE.md` in full") - exactly the doc's one-file model. The skills
  live in **committed** `.claude/commands/*.md` + `.claude/agents/*.md` (team-shared through git), *unlike*
  FileDO where `.claude/` is git-ignored. Local working-method docs are in `doc/` (`SPEC_LIFECYCLE`,
  `CODE_QUALITY`, `VALIDATION`, `AGENT_MEMORY`, ...) (evidence: `AGENTS.md:3-8`; `git ls-files .claude/`).
- CONFIRM (spec tickets use a **T-catalog**): specs are `PLAN/T####_<slug>.md` (T0001..T0024) with an
  `INDEX.md`, status from the working tree not the filename - the same lifecycle as Overlay B's `Sxxxx`
  catalog but with a `T` prefix and living under `PLAN/` on a Windows-desktop project (evidence:
  `git ls-files PLAN/`).

### SITE_CONFIGURATION.md / DOCUMENTATION_CONCEPT.md
- CONFIRM (`/docs` Pages source + mirrored SZA kit): the site is served from **`docs/`** with `.nojekyll`
  for hand-authored static HTML, and the SZA web kit is **mirrored** to `docs/assets/sza-kit.css` - matches
  the `/docs`-as-Pages-source rule already folded into the core by the FileDO reconcile (evidence:
  `docs/.nojekyll`, `docs/assets/sza-kit.css`, `docs/index.html`).

### AUTHOR.md
- CORRECT (applied in-repo this session): `CLAUDE.md` said "**Chat in English**"; canon `AUTHOR.md`
  §Language is "chat in the owner's language (**Russian**); code/docs/logs/commits in English". Fixed the
  repo to match the canon (evidence: `AUTHOR.md:33`; CLAUDE.md "Communication" line, now Russian).

## No delta
DEVELOPMENT, TESTING_AND_QA, GITHUB_INTERACTION, RELEASE_AND_DISTRIBUTION, CHANNEL_MATRIX (no channels),
SECURITY_AND_PRIVACY, LOCALIZATION (single-language app), SUPPORT_AND_FEEDBACK - verified, nothing to add
beyond what the desktop reference repos already carry.

## Candidate core edits (PROPOSED - apply only on owner instruction)
- **PLATFORM_OVERLAYS.md Overlay A ("no-installer variant" paragraph)**: note that when a portable-zip app
  ships through **GitHub Release only** (no winget, no Store), the frozen-anchor set is **empty** - there is
  no update-correlation id to reserve at all. The current text stops at `{winget PackageIdentifier, MSIX
  Identity}`; add the GitHub-Release-only end of the spectrum so a single-channel portable reads as
  compliant with zero anchors (evidence: `release.ps1`; OneClickRunner).

## Candidate NEW docs (not in any shared doc yet)
- **None required.** The one new fact (undistributed shape) is a one-line addition to Overlay A.

## Open questions for the owner
- **Distribution intent** -> **RESOLVED 2026-07-23:** stand up a **GitHub Release** channel. Done -
  `release.ps1` added, first release cut (see follow-up). No frozen anchors needed (GitHub-Release-only).
- **`LICENSE` + `CHANGELOG`** -> **RESOLVED 2026-07-23:** both added (MIT + house `[Unreleased]` flow).
- **Hardcoded deploy path** `C:\GD\tc\SZA\_APP` in `build.ps1:3` - still open: parameterize (env var /
  `-Destination` arg) or leave as an owner-local constant. `build.ps1` is the local deploy (never tags);
  it is not the release path, so this is low urgency.
- **Framework-dependent release** needs the .NET 8 Desktop Runtime on the target. Keep it (small zip), or
  switch to self-contained for a zero-prereq download? `release.ps1 -SelfContained` already supports it.

## Spread-back applied 2026-07-23
Ran `SPREAD_BACK_PROMPT.md` in `P:\WINDOWS\OneClickRunner` as a **NEW** repo (no prior contrib record;
NEW_PROJECT_CHECKLIST followed for the adoption, this record created from TEMPLATE.md).

**What changed (in the repo).** Adopted the **reference** consumption model in the single rules file
`CLAUDE.md` (`AGENTS.md` already delegates to it):
- Added an **SZA Unified Rules (canon)** section: canon path + read order, a link to this contrib record,
  and a condensed **overlay-facts** block (Overlay A minimal / undistributed, version shape `YY.MMdd.HHmm`,
  local-copy deploy, no channels, no anchors).
- Aligned **Communication** to the canon (`AUTHOR.md` §Language): "Chat in English" -> "Chat in Russian;
  code/comments/logs/commits in English".
- **Reconciled internal drift** in the Architecture section against the live tree (independent of the
  canon, but required by step 3 "verify every kept claim"): the elevation "gotcha" was **inverted** - code
  now unifies elevation on `RunAsAdmin` regardless of launch surface (`ScenarioLauncher.Launch`, T0001), so
  the "Jump List always elevates" claim was removed; the system tray now exists (`TrayIconService`) so the
  "not a system tray" / "README is stale" caveats were replaced; pipe IPC is now `PipeIpcService` (dead
  `StartPipeServer`/`StartPipeListener` naming removed, T0019); `SPECIAL_YTDLP` is now only
  `ScenarioLauncher.LegacyYtDlpSentinel` back-compat with a first-class yt-dlp scenario type (T0013);
  `Debug.WriteLine` note dropped (0 occurrences, T0020); file-budget note repointed from the now-thin
  `App.xaml.cs` (~240) to `MainWindow.xaml.cs` (~460).

**Verification (fresh run 2026-07-23).**
- `dotnet build -c Release` -> **exit 0**, 0 warnings, 0 errors (after stopping a running instance that
  held a file lock on the output exe - a MSB3027 copy-lock, not a compile error).
- Overlay facts each cited to `build.ps1` / `OneClickRunner.csproj` / `git ls-files` above.

**Questions closed.** None requiring owner input were mechanically closable; the three above are genuine
owner decisions (distribution intent, LICENSE/CHANGELOG, deploy-path parameterization) and stay open.

**What remains / canon edits still needed (NOT committed from the repo session - owner to apply in a canon
session, then run `tools/check-rules.ps1`):**
- Add a **OneClickRunner row** to `SPREAD_BACK_PROMPT.md`'s target table (contrib record
  `contrib/oneclickrunner.md`) and mark its Done column after this repo's spread-back commit lands.
- Consider the one **candidate core edit** above (Overlay A GitHub-Release-only = empty anchor set). Low
  urgency; only OneClickRunner needs it so far.

## Spread-back follow-up 2026-07-23 (distribution stood up)
Owner chose, in the same session: **GitHub Release + LICENSE + CHANGELOG + push**.
- Added `LICENSE` (MIT, `Serhii Zhyhunenko (SerZhyAle)`) and `CHANGELOG.md` (house `[Unreleased]` flow).
- Added `release.ps1` - the single tagger (build/release wall vs the local-deploy `build.ps1`): publishes
  framework-dependent single-file win-x64, zips `OneClickRunner-<version>-win-x64.zip` + `.sha256`
  (`-p:DebugType=none`, no pdb), tags `v<version>`, pushes, `gh release create` with notes from CHANGELOG.
  Version is overridden to the exact tag so exe stamp = tag = zip name; `-DryRun` and `-SelfContained` levers.
- Updated `CLAUDE.md` overlay block: no longer "undistributed" - one channel (GitHub Release), build/release
  wall, LICENSE/CHANGELOG present.
- **Verified:** `release.ps1 -DryRun` -> exit 0; exe `ProductVersion=26.0723.1719` matches tag; zip holds
  only `OneClickRunner.exe`; sha256 written. Real release: tag `v26.0723.1719` cut and `gh release create`
  run (see repo commit + release URL in the session report).
- Repo commits **pushed** to `origin/main`.
