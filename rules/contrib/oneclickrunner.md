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

> **Keep this note in the record.** Current facts, edited in place. Never append a dated section to this file,
> and append nothing under `history/` either: those files are frozen ([the rules of that folder](history/README.md))
> and are not reading for a task. A delta the core absorbed, a candidate that was applied or refused and a
> question that was answered are deleted here.

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
  `CODE_QUALITY`, `VALIDATION`, `AGENT_MEMORY`, ..) (evidence: `AGENTS.md:3-8`; `git ls-files .claude/`).
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

## Open questions for the owner
- **Distribution intent** -> **RESOLVED 2026-07-23:** stand up a **GitHub Release** channel. Done -
  `release.ps1` added, first release cut (see follow-up). No frozen anchors needed (GitHub-Release-only).
- **`LICENSE` + `CHANGELOG`** -> **RESOLVED 2026-07-23:** both added (MIT + house `[Unreleased]` flow).
- **Hardcoded deploy path** `C:\GD\tc\SZA\_APP` in `build.ps1:3` - still open: parameterize (env var /
  `-Destination` arg) or leave as an owner-local constant. `build.ps1` is the local deploy (never tags);
  it is not the release path, so this is low urgency.
- **Framework-dependent release** needs the .NET 8 Desktop Runtime on the target. Keep it (small zip), or
  switch to self-contained for a zero-prereq download? `release.ps1 -SelfContained` already supports it.
