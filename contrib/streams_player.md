# Contribution: streams_player (overlay A, no-installer variant / cross-product data-bank consumer / single edition) -> Unified_Rules
Source repo: P:\WINDOWS\Streams_Player | Date: 2026-07-23
Read: all 16 core docs; contrib/{epub_2_html,fastmediasorter_lite,fastmediasorter_mob_v2,filedo}.md (deduped against)

StreamsPlayer is a .NET 10 / WPF Windows desktop internet-radio / live-video / RTSP player, owned by SZA. It is an
**independent product** that consumes the FastMediaSorter published stream bank at runtime. It is NOT an edition of
FastMediaSorter (no shared code, no parity doc) and the coupling is NOT the `.fmscfg` wire contract already documented —
it depends on another SZA product's **release artifact** (a published ZIP catalog). That coupling shape, the bundled
LGPL/GPL native media stack, and the third-party-stream Store-review posture are the genuinely new material here.
Version shape, winget mechanics, MSIX/Store re-sign, agent-kit/spec-lifecycle, and WPF/.NET desktop specifics are already
saturated by fastmediasorter_lite/epub/filedo and are NOT repeated.

## Overlay facts (verified against this repo)
- **Source root & release-mechanics:** `src/StreamsPlayer.Core` (platform-neutral) + `src/StreamsPlayer.App` (WPF);
  `tools/StreamsPlayer.CatalogHarness`; `tests/StreamsPlayer.Core.Tests`. No `publishing/` umbrella — channels are
  top-level siblings: `winget/templates/`, `msix/`, `.github/workflows/release.yml`, empty `manifests/s/` scaffold.
  **No installer folder at all** (no Inno `.iss` / WiX `.wxs`): the GitHub channel ships a portable
  `StreamsPlayer-<ver>-windows-x64.zip` (`.github/workflows/release.yml:46-54`).
- **Version shape:** zero-padded `YY.MMDD.HHmm` (`26.0723.1040`, `Directory.Build.props:11-14`) — same padding as epub, so
  the shape itself is not new. New: the **MSIX remap for this padding**. MSIX Identity Version forbids leading zeros, so
  `build-msix.ps1:48-55` int-casts each component (`26.0723.0959.0 -> 26.723.959.0`) with a per-component `<=65535`
  ceiling guard; GitHub + winget keep the canonical 3-component zero-padded value. (fastmediasorter_lite documents the
  `M*100+D` formula from the *dotted* shape; this is the reconciliation for the *single-MMDD-field* zero-padded shape.)
- **Channels + listing files:** GitHub Release (portable zip + `.sha256`); winget `SerZhyAle.StreamsPlayer`
  (`winget/templates/*.yaml`, `InstallerType: zip` + `NestedInstallerType: portable`, alias `streamsplayer`); Microsoft
  Store MSIX (`msix/store-listing.md`, `msix/store-listing-import.csv`). GitHub Pages site at
  `serzhyale.github.io/StreamsPlayer/` from `/docs` (no CNAME / custom domain).
- **Frozen anchors:** winget `PackageIdentifier: SerZhyAle.StreamsPlayer`; MSIX Identity `Name: SZA.StreamsPlayer`,
  `Publisher: CN=F98ACEDB-1E22-4C39-AF63-F9FCFE807DCD`, PublisherDisplayName `SZA`, PFN
  `SZA.StreamsPlayer_fdk7e19xt9z9j`, Store ID `9NBTD5SXB8TB`; exe/`AssemblyName` `StreamsPlayer`. **No Inno `AppId` / WiX
  `UpgradeCode`** — the portable-zip-only distribution has no classic-installer anchor (`STORE_PUBLISHING.md:9-19`).
- **Editions:** none. Single product, single codebase. Distinct coupling: **consumed published release artifact** — the
  catalog ZIP at `StreamCatalogService.CatalogUrl` from a FastMediaSorter release (`AGENTS.md:10-12`, `CLAUDE.md` key
  data-flow contracts). Producer-frozen / consumer-forward-tolerant applies, but it is a release-artifact dependency,
  not a `.fmscfg` wire/config contract and not an edition/parity relationship.

## Channel-matrix rows (this project)
- GitHub Release | `v*` tag push (CI-validated regex `^v\d{2}\.\d{4}\.\d{4}$` + `ParseExact 'yy.MMdd.HHmm'`) | [PAID] | `gh` ambient | self, `.sha256` | release body <- `generate_release_notes` | anchor: exe name `StreamsPlayer.exe` | verify: zip downloads + SHA256 matches
- winget | PR to `microsoft/winget-pkgs` via `wingetcreate update` | [PUBLIC] | `gh` + CLA | Microsoft re-hosts | `winget/templates/*.yaml` (schema 1.12.0) | `SerZhyAle.StreamsPlayer` | verify: `winget install --manifest`, then `winget search` after merge — **gated on an existing GitHub Release** (URL+SHA256)
- Microsoft Store (MSIX) | manual Partner Center upload | [PUBLIC] | Partner Center console | **Store re-signs** (unsigned upload) | `msix/store-listing.md` + CSV merge-import | MSIX Identity `SZA.StreamsPlayer` + Publisher CN + Store ID `9NBTD5SXB8TB` | verify: dashboard version; update over prior MSIX; **fresh IARC**
- GitHub Pages (site publish, not a release) | push to `main` touching `docs/**` (`pages.yml` path filter) | [PAID CI] | GH Actions OIDC | — | `docs/*.html` (trilingual client-side i18n) | anchor: none (default `github.io/<repo>`) | verify: `privacy.html` renders, EN/RU/UA switch works

## Deltas by document

### PLATFORM_OVERLAYS.md
- ADD (coupling shape): **consumed published release artifact / data-bank consumer** — a third coupling shape beside
  editions(parity) and wire-contracts. StreamsPlayer depends at runtime on another product's *release output*: a ZIP at
  `StreamCatalogService.CatalogUrl` from a FastMediaSorter release, where `streams.csv` MUST be the first ZIP entry
  (reader rejects the bank otherwise) and `favicon-atlas.png` is optional and `<=4 MB`. Consumer-side invariant: a
  URL-keyed merge only updates/removes `SourceOrigin==Catalog` rows and never touches `MANUAL`/`IMPORTED`; refresh is
  explicit-only (no background downloads). Evidence: `CLAUDE.md` "Key data-flow contracts", `src/StreamsPlayer.Core/CatalogMerger.cs`, `AGENTS.md:53-56`.
- ADD (overlay-A variant): a Windows-desktop product may have **no installer channel** — portable-zip GitHub +
  winget-portable + MSIX only. The frozen-anchor set then reduces to {winget `PackageIdentifier`, MSIX Identity
  `Name`+`Publisher`} with **no Inno `AppId` / WiX `UpgradeCode`**. Evidence: `release.yml:46-54`, `winget/templates/SerZhyAle.StreamsPlayer.installer.yaml`, absence of any `installer/` folder.
- ADD/CORRECT (version remap): the zero-padded `YY.MMDD.HHmm` shape collides with MSIX Identity Version's
  no-leading-zeros rule; remap by int-casting each component (`26.0723.0959.0 -> 26.723.959.0`) plus a `<=65535`
  per-component ceiling; GitHub + winget keep the 3-component zero-padded value. Evidence: `msix/build-msix.ps1:48-55`.
  Note: this contradicts the repo's own `AGENTS.md:93` ("MSIX ... appends only .0: 26.0719.0131.0") — see open questions.
- CONFIRM: winget portable-in-zip shape (`InstallerType: zip` + `NestedInstallerType: portable` + `PortableCommandAlias`)
  — already core via filedo. Evidence: `winget/templates/...installer.yaml:4-11`.

### REPOSITORY_LAYOUT.md
- ADD (build default has a local-install side effect): `./build.ps1` defaults `-Deploy:$true`, which forces Release +
  win-x64, publishes a **self-contained single-file exe**, and copies it into hardcoded local machine folders
  (`C:\GD\i`, `C:\GD\tc\SZA\_APP`). A pure solution build requires `-Deploy:$false`. The build/release wall holds (it is
  still not a release) but the *default build* mutates machine state — a real footgun for the "build = local, free, ships
  nothing" mental model. Evidence: `build.ps1:10,24,121-169`.
- CONFIRM: release-mechanics as top-level siblings (no `publishing/` umbrella) — already relaxed by epub to "one committed
  folder per channel". Evidence: repo root `winget/ msix/ manifests/ .github/`.

### DOCUMENTATION_CONCEPT.md
- DIVERGE: publication mechanics are documented **per channel** (a README inside each channel folder:
  `winget/README.md`, `msix/README.md`, plus a root `STORE_PUBLISHING.md` Store runbook) rather than in one
  `docs/guides/BUILD_AND_RELEASE.md`. Evidence: those three files.

### RELEASE_AND_DISTRIBUTION.md
- ADD (CI tag semantic gate): the release job **rejects a malformed or impossible version tag before publishing** — it
  requires `^v\d{2}\.\d{4}\.\d{4}$` AND `[DateTime]::ParseExact($version,'yy.MMdd.HHmm',Invariant)`, so e.g. `v26.1345.9999`
  fails the job. Stronger than "derive the version mechanically". Evidence: `.github/workflows/release.yml:36-38`.
- ADD (bundled-native-media license obligation): an **MIT** app that redistributes LibVLC/VLC native plugins ships under a
  **combined GPL-2.0-or-later** obligation and MUST carry `THIRD-PARTY-NOTICES.txt` in every distributed package (release
  ZIP and MSIX). Removing it breaks license compliance. Evidence: `msix/THIRD-PARTY-NOTICES.txt:16-32`, `STORE_PUBLISHING.md:47-49`.
- ADD: the winget channel is hard-gated on an existing public GitHub Release (URL + SHA256), so it can only be refreshed
  *after* an approved release; with no release yet, `manifests/s/` is an empty committed scaffold. Evidence: `winget/README.md:17-28`.

### CHANNEL_MATRIX.md
- ADD (Store listing CSV import mechanics): a **direct** Partner Center CSV import is rejected ("The ID column contains
  incorrect entries") because the `ID` values are account-specific and undocumented. Working flow: Export listing ->
  merge-fill the `Field/ID/Type`-preserving template via `tools/store/merge-listing-csv.ps1` -> Import. The file must
  stay **UTF-8 with BOM** to preserve Cyrillic. Evidence: `STORE_PUBLISHING.md:82-116`.
- ADD (Store infringing-content review gate for stream players): apps that open third-party streams draw extra Store
  review under the infringing-content policy; the keyword `IPTV player` is the likely trigger. Mitigate by framing the
  listing as an internet-radio / live-stream **catalog** player and pasting the runFullTrust justification verbatim.
  Evidence: `STORE_PUBLISHING.md:126-139`.

### SECURITY_AND_PRIVACY.md
- CORRECT: epub established "the SZA IARC rating id is reused across all Store apps (in msix build-script defaults)".
  That is **not** universal — an app whose content-exposure profile differs must file a **fresh IARC questionnaire**.
  StreamsPlayer can open arbitrary third-party live audio/video (uncurated online content), which changes the answers, so
  the portable SZA rating id does not transfer. The shared IARC id is constant only *within the same content profile*.
  Evidence: `STORE_PUBLISHING.md:118-124`.
- ADD (privacy posture for a networked media app): the promise is "explicit-refresh only, stream playback only, **no
  telemetry, no background fetch, no accounts, no ads**". This exact statement is both the Store `runFullTrust`
  justification and the `docs/privacy.html` source of truth. Evidence: `STORE_PUBLISHING.md:34,137`, `docs/privacy.html`,
  `AGENTS.md:53-54`.

### LOCALIZATION.md
- ADD/CORRECT: the portfolio "shipped locales EN/RU/UK" is **not uniform per surface**. Here: in-app UI = EN+RU only
  (`Localization.en.xaml` / `Localization.ru.xaml`, a runtime-swapped `ResourceDictionary`, choice persisted in
  `CatalogState.Language`); README + GitHub Pages = EN+RU+UK; Store listing + winget locale = EN+RU. UK ships on the
  website and README but not in the product UI or the store. Refinement: locale coverage is **per surface** — a surface
  carries a locale only when there are users for *that surface*. Evidence: two `Localization.*.xaml`; `README.ru.md`,
  `README.uk.md`; `docs/index.html:22-24` (`uk` detection); `winget/templates/*.locale.{en-US,ru-RU}.yaml`.
- CONFIRM: web i18n is in-page client-side blocks (`data-i18n` + `localStorage streamsplayer-lang`), ISO `uk` in code
  (the switcher label "UA" is display-only, not an ISO code). Matches core's in-page model + `uk`-not-`ua` rule.

### TESTING_AND_QA.md
- ADD: a dedicated **live network-contract smoke harness** as a separate console project
  (`tools/StreamsPlayer.CatalogHarness`), run manually against the real published bank
  (`dotnet run --project tools/StreamsPlayer.CatalogHarness -- artifacts/favicon-sample.png`), distinct from the offline
  unit tests. It validates the *external* data-bank contract (ZIP shape, `streams.csv` first-entry rule, favicon atlas)
  against the network — a tier between unit tests and the GUI run, specific to a product with an external live data
  dependency. Evidence: `docs/agent/VALIDATION.md:10` (rung 6), the harness project.

### DEVELOPMENT.md
- CONFIRM (layering at project granularity): the one-way graph is enforced by **project references**, not just
  conventions — `StreamsPlayer.Core` is a platform-neutral library that references no WPF/App/tools/tests, and the media
  stack (LibVLC / `MediaElement`, `~10 s` live buffer) lives only in App, so Core is unit-testable without UI or media.
  Evidence: `CLAUDE.md` architecture graph, `AGENTS.md:102`.
- CONFIRM: `guard-find-command.ps1` PreToolUse find-safety hook (mob_v2 core item) is **active in this repo too** — it
  blocked an unbounded `find` during this survey; use Glob/Grep or `-maxdepth`.

### AI_USAGE.md
- CONFIRM: committed in-repo agent memory (`memory/MEMORY.md`, types user/feedback/project/reference) alongside both
  `CLAUDE.md` + `AGENTS.md` and `/streamsplayer-*` skill routing — confirms "committed-vs-per-user memory is a
  per-project choice". Evidence: `memory/MEMORY.md`, `docs/agent/AGENT_MEMORY.md`.
- DIVERGE (gray zone): developer-facing PowerShell console/error strings are in **Russian** in `build.ps1`
  (`Не найден .NET SDK`, `dotnet завершился с кодом $LASTEXITCODE`, `Запуск StreamsPlayer...`), unlike the
  "English for code/logs/commands" rule — owner-facing operational script output follows chat-language, not code-language.
  Evidence: `build.ps1:54,50,69,187`. See open questions.

### SITE_CONFIGURATION.md
- CONFIRM: Pages served from `/docs` via a path-filtered workflow; theme + language persisted in `localStorage`
  (`streamsplayer-theme`, `streamsplayer-lang`); **no CNAME / custom domain** (default `serzhyale.github.io/StreamsPlayer/`)
  — a valid variant of the `/docs` + no-custom-domain shape. Evidence: `.github/workflows/pages.yml:4-8`,
  `Directory.Build.props:10`, `docs/index.html:11-28`.

## No delta
README.md, NEW_PROJECT_CHECKLIST.md, GITHUB_INTERACTION.md, SUPPORT_AND_FEEDBACK.md, AUTHOR.md.

## Candidate core edits (RESOLVED - all folded into core 2026-07-23)
Landing map: PLATFORM_OVERLAYS.md "Cross-project contracts" (consumed release artifact) + Overlay A (no-installer
variant, MSIX no-leading-zeros int-cast remap); SECURITY_AND_PRIVACY.md §2 (IARC not publisher-constant), §5 (fresh-IARC
carve-out + category-review framing), new §6 (bundled LGPL/GPL notices), §7 checklist steps 6-7; RELEASE_AND_DISTRIBUTION.md
§4 (CI tag `ParseExact` gate) + §5 (notices in every package); CHANNEL_MATRIX.md MSIX row (listing export-then-merge CSV
import + category-review note); LOCALIZATION.md §1 (per-surface locale coverage). No new docs, so no README/read-order/
NEW_PROJECT_CHECKLIST wiring needed.

- **[LANDED] PLATFORM_OVERLAYS.md → Cross-project contracts:** add a third coupling shape, **consumed published release artifact
  (data bank)**, distinct from wire-contract and edition/parity — a runtime dependency on another product's *release
  output*, with the same producer-frozen / consumer-forward-tolerant rule plus a consumer-side data-preservation
  invariant (protect user-owned rows on refresh). Prevents mis-modeling a release-artifact dependency as a wire contract
  or an edition. Evidence: `AGENTS.md:10-12`, `CatalogMerger.cs`.
- **PLATFORM_OVERLAYS.md → Overlay A:** document the **no-installer variant** (portable-zip + winget-portable + MSIX, no
  Inno/WiX, reduced anchor set) and add the **zero-padded `YY.MMDD.HHmm` → MSIX no-leading-zeros int-cast remap + `<=65535`
  ceiling** as a second documented remap beside `M*100+D`. Prevents a rejected MSIX Identity Version and a wrong
  "just append .0" assumption. Evidence: `build-msix.ps1:48-55`, `release.yml:46-54`.
- **SECURITY_AND_PRIVACY.md §5:** carve out the IARC-id-reuse rule — an app whose content-exposure profile differs (opens
  arbitrary third-party / uncurated content) must file a **fresh IARC questionnaire**; the portfolio IARC id is constant
  only within the same content profile. Prevents shipping a wrong age rating by copying the portable id. Evidence:
  `STORE_PUBLISHING.md:118-124`.
- **RELEASE_AND_DISTRIBUTION.md (+ CHANNEL_MATRIX playbook):** add a **bundled-native-media license rule** — an MIT app
  redistributing LGPL/GPL native libraries ships under the combined (GPL) obligation and must carry
  `THIRD-PARTY-NOTICES.txt` in every package; and a **Store infringing-content review** note for third-party-stream
  players. Prevents a license-compliance gap and a surprise Store rejection. Evidence: `THIRD-PARTY-NOTICES.txt:16-32`,
  `STORE_PUBLISHING.md:126-139`.
- **RELEASE_AND_DISTRIBUTION.md §4:** recommend a **CI tag-format + date semantic gate** (regex + `ParseExact`) as the
  mechanical guard that a `v*` tag is a real, monotonic version before the release job publishes. Prevents a mis-typed
  tag from cutting a bad release. Evidence: `release.yml:36-38`.
- **LOCALIZATION.md §1:** state that shipped-locale coverage is **per surface** (a website/README locale need not be an
  in-app or store locale). Prevents treating "EN/RU/UK" as a uniform obligation across every surface. Evidence: two
  `Localization.*.xaml` vs three `README.*.md`.

## Candidate NEW docs (not in any shared doc yet)
- None. Everything fits the existing 16. (Optional: a *consumer-side* mirror of a consumed data-bank contract could live
  as `docs/contracts/CONTRACT_*.md` even though the consumer does not own the format — worth a one-line mention in
  PLATFORM_OVERLAYS rather than a new doc.)

## Open questions for the owner (project-specific; deliberately NOT folded into core)
The universal truths behind these already landed in core; what remains is StreamsPlayer-repo action the shared docs cannot decide:
- **MSIX version doc bug (repo-local):** the *universal* remap rule now lives in PLATFORM_OVERLAYS Overlay A, but the
  repo's own `AGENTS.md:93` ("appends only .0", `26.0719.0131.0`) still contradicts `build-msix.ps1:48-55`
  (`26.723.131.0`). Owner action: fix `AGENTS.md` in the StreamsPlayer repo to match its script.
- **Russian build-script strings:** RESOLVED 2026-07-23 (owner) - the portfolio rule is **English-only**
  script/console output (now DEVELOPMENT §4); StreamsPlayer's `build.ps1` messages are a slip to fix at
  spread-back.
- **Product-UI locale set:** core now *permits* per-surface coverage (LOCALIZATION §1); whether StreamsPlayer's app
  should add UK to match the site is an owner call.

## Spread-back applied 2026-07-23

Ran `SPREAD_BACK_PROMPT.md` in a session started in `P:\WINDOWS\Streams_Player` (existing repo). Working tree
was clean on `main`, no prior canon reference in-tree. Build gate green after all edits: `./build.ps1 -Test
-Deploy:$false` → Build succeeded, 0 warnings/errors, 149/149 tests passed, exit 0; console output now English.

**Consumption model — hybrid REFERENCE (owner decision).** Added a canon pointer to `AGENTS.md` (new section
"SZA Unified Rules (canon)") and a one-bullet pointer to `CLAUDE.md` (Workflow tooling), but did **not** strip the
restated universal rules. DIVERGE from the prompt's default ("prefer REFERENCE + remove restated universal rules"):
the canon lives only at a local, non-committed, non-public path (`P:\WEB\...\Unified_Rules`) that CI and outside
contributors of the public GitHub repo cannot resolve; stripping universal rules and pointing there would break the
repo's self-containedness. Rules stay in-repo; canon is authoritative on disagreement. Owner confirmed the hybrid.

**Open questions closed:**
- **MSIX version doc bug — FIXED.** `AGENTS.md` version section now describes the int-cast remap
  (`26.0719.0131` → `26.719.131.0`, `≤ 65535` ceiling) to match `msix/build-msix.ps1:51-55`, replacing the wrong
  "appends only .0: 26.0719.0131.0" text.
- **Russian build-script strings — FIXED.** Translated the seven Russian console/error strings in `build.ps1`
  (lines ~49/54/61/66/69/173/187) to English. Verified no other `.ps1` console output is affected: the Cyrillic in
  `tools/store/make-store-images.ps1:93-94` is RU **content** for Store screenshot captions, and
  `tools/store/auto-capture.ps1:73` `'video|видео'` is a regex matching the localized player-window title — both are
  localized data, not script output, so they legitimately stay (recorded, not "fixed").
- **Product-UI locale set — RESOLVED to ADD UK (owner decision), deferred to a ticket.** Owner chose to bring the
  in-app UI to EN+RU+UK (matching the site). This is a real feature (extend `AppLanguage` enum in Core, add
  `Localization.uk.xaml` at full parity, turn the EN↔RU toggle into a 3-way selection, `uk-UA` culture), not a
  spread-back edit, so it was captured as **`PLAN/SP-0029_ukrainian_ui_locale.md` (Draft)** rather than folded into
  this commit. Once shipped, the earlier per-surface note (LOCALIZATION §1 delta above) no longer describes a UI gap.

**Files touched in the repo:** `AGENTS.md` (canon pointer + MSIX version fix), `CLAUDE.md` (canon pointer bullet),
`build.ps1` (English console strings), new `PLAN/SP-0029_ukrainian_ui_locale.md`.

**Needed canon fixes (for a canon session, not applied here):** none. All universal deltas from this survey already
landed 2026-07-23 (see "Candidate core edits — RESOLVED" above). The hybrid-consumption divergence is repo-specific
(local-only canon path) and recorded here, not a canon rule change.
