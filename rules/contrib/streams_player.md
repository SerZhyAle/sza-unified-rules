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

## Drift correction 2026-07-26 (owner-triggered)

The owner caught the agent chatting in English and asked for a canon diff. Four unrecorded drifts found - none of
them was a DIVERGE, all were plain drift the 2026-07-23 survey missed. Note that survey listed **AUTHOR.md under
"No delta"**, which was wrong: `AGENTS.md:98` contradicted `AUTHOR.md` §Language at that moment and was not flagged.

| Topic | Canon | Repo before | Fix applied in repo |
| --- | --- | --- | --- |
| Chat language | `AUTHOR.md:33`, `AI_USAGE.md:75` - chat in the owner's language (Russian) | `AGENTS.md:98` + `.claude/agents/streamsplayer-rd-lead.md:12` - "Chat, code, documentation, logs, and commits are English" | Both rewritten to the canon split; `CLAUDE.md` gained an explicit **Communication** block citing `AUTHOR.md` §Language + `AI_USAGE.md` §7 (it had no language rule at all) |
| Trailing summaries | `AUTHOR.md:42`, `AI_USAGE.md:76` - no trailing "what I did" summary | absent | Added to `AGENTS.md` + rd-lead agent + `CLAUDE.md` |
| Reply timestamp | `AI_USAGE.md:77` | absent | Same three files |
| Scratch tree | `DEVELOPMENT.md:101` - `temp/<ticket>/` | `tmp/` in `AGENTS.md:118`, `docs/agent/{VALIDATION,RESEARCH_INDEX,COST}.md`, two skills, two agent files | All rule sources switched to `temp/<ticket>/`; `.gitignore` already ignored both |

**Partial adoption, deliberate:** the existing `tmp/` tree was **not** renamed. It holds local, uncommitted evidence
referenced by ~30 closed `PLAN/DONE` tickets and by a `memory/MEMORY.md` pointer to a live driver script
(`tmp/uia/driver.ps1`). Rewriting those paths would falsify closed verification records for no gain. `AGENTS.md` now
says `temp/` is the target and `tmp/` is frozen history - do not add to it.

**This is a recurrence, not a one-off.** The identical chat-language defect was found and fixed in OneClickRunner
(`contrib/oneclickrunner.md:92-94`). Two repos drifting the same way suggests the canon's language rule is easy to
lose when a repo restates universal rules in-house (the hybrid-consumption model recorded above). Worth a canon-session
decision: either a spread-back checklist item that greps every repo's rules file for a chat-language line, or a
`tools/check-rules.ps1` extension that flags a repo rules file asserting English chat.

**Files touched in the repo:** `AGENTS.md`, `CLAUDE.md`, `.claude/agents/streamsplayer-rd-lead.md`,
`.claude/agents/streamsplayer-{solution-researcher,implementer}.md`,
`.agents/skills/streamsplayer-{research,verify}/SKILL.md`, `docs/agent/{VALIDATION,RESEARCH_INDEX,COST}.md`.

## Canon adoption 2026-07-27 - the fork is gone

This repo was the portfolio's only **self-declared fork** of the canon. `AGENTS.md:126` said it "deliberately
keeps those rules restated in-repo so the repository stays self-contained for CI and outside contributors",
and `CLAUDE.md:69` repeated it. The argument was sound while the canon lived at a local absolute path CI could
not resolve. It is void now: the canon installs as the `sza` plugin and travels with the session.

The restatement had already drifted - the 2026-07-26 correction above found four unrecorded divergences,
including a chat-language rule that contradicted `AUTHOR.md` and survived an entire survey unflagged.

Removed seven restated rules across the two files: chat language, English artifacts, no trailing summary,
working-tree-is-truth, the evidence rule, and build-is-not-a-release twice. Kept as genuinely repo-local: the
dependency direction, the research order, the memory discipline, and the **autonomy verdict** (ask first
before any publishing action) - a verdict stays local even when the rule it applies does not.

`.sza-canon.json`: overlay A no-installer variant, consumed-release-artifact coupling, ledger shape 4, three
channels, and the fact that `docs/` is **generated** by `tools/site/build-site.ps1` - hand-editing it is a
silent revert on the next run.

Compliance gate: **0 errors** (was 8), 4 warnings.

## Canon reconcile 2026-08-02 - agent-process propagation

Canon **2026.07.27 -> 2026.08.02**, core digest `sha256:dae220bf..` -> `sha256:6c247452..`. Stamp
updated; the adoption model is unchanged. The upstream change is [AI_USAGE.md](../AI_USAGE.md) only -
the agent-process findings propagated from FastMediaSorter mob_v2 under its ticket S1342 - so the
staleness ladder's "re-read only the changed rule docs" path applies and no full re-adoption was run.
Nothing in `rules/` touched packaging, release, channels or layout, and no divergence was found
between the new bullets and this repo's own rules file.

The one repo besides FastMediaSorter where §4 lands **live rather than inert**: memory here is
file-based, committed and shared across tools, with `memory/MEMORY.md` as the always-loaded index and
the same four entry types. So the byte budget, the liveness-keyed expiry and the ban on restating the
rules file all apply to a real corpus today, and the index wants a mechanical ratchet the way
FastMediaSorter's got one. `AGENTS.md` already carries the verify-against-the-tree half of the
discipline, which the canon's §4 states too - agreement, not divergence.

Verification: `check-compliance: Streams_Player - 0 error(s), 4 warning(s) (overlay A, canon 2026.08.02)` - warnings are pre-existing and none was introduced here.

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

Finding 2 has a target here, with a local twist: all eighteen commands carry a `streamsplayer-` prefix, so
the cheap tier is `/streamsplayer-quick` - the longest name on the ladder belongs to the tier meant to be
reached for first, and any nudge written here has to emit the prefixed forms or it will name commands that
do not exist. Whether the prefix itself suppresses the cheap tier is a hypothesis, not a measurement; the
transcript corpus can answer it before anyone renames anything. No hooks are configured. Carried as an owner
decision, not applied from this session.

Verification: `check-compliance: Streams_Player - 0 error(s), 4 warning(s) (overlay A, canon 2026.08.05)` -
warnings are pre-existing and none was introduced here.

## Canon re-sync 2026-08-18 - four updates at once, and a reversed rule

Canon **2026.08.05 -> 2026.08.18.1**, core digest `sha256:8d33fdab..` -> `sha256:961c9c8a..`. The stamp
had already been moved mechanically before this session; it was **verified, not trusted** -
`check-compliance.ps1 -PrintDigest` recomputes `961c9c8a..`, so it is correct as written.

**Why this one is not an ordinary one-step reconcile.** The `sza` plugin served a cached
**2026.07.27** for roughly three weeks, so the 08-02, 08-05, 08-08 and 08-18 updates never loaded in a
session started in this repo - including the 08-02 and 08-05 reconciles recorded above, which were
written against docs the session could not actually see. This pass re-read the diff from `7dd3dde`
(2026-07-27) to `HEAD` directly out of the canon repo rather than trusting the plugin cache.

Rule docs changed in that span: **AI_USAGE, DEVELOPMENT, GITHUB_INTERACTION, RELEASE_AND_DISTRIBUTION,
TESTING_AND_QA** (plus README and NEW_PROJECT_CHECKLIST). **INVARIANTS.md did not change** - worth
recording, because it was on the review list and a null result there is a real finding, not a skipped
step.

Also noted: the plugin cache holds a newer **2026.08.18.2**, and its core digest is **identical**
(`961c9c8a..`) - that bump touched `skills/` and `tools/`, which the digest deliberately excludes. The
stamp sitting at `.1` therefore is not stale in the sense the staleness ladder measures. Left alone.

### A canon rule this repo had adopted was reversed

The 2026-07-26 drift table above records "Reply timestamp | `AI_USAGE.md:77` | absent | Added to three
files" as a *fix*. **AI_USAGE section 7 now says the opposite** - "Never prefix a reply with a clock
time.. This supersedes the earlier rule to timestamp from the prompt" - because the model has no clock
and the prompt-submit injection goes stale inside any autonomous run. The repo was still carrying the
July version in two places, one of them load-bearing:

- `CLAUDE.md` declared it as the repo's **only** repo-local communication addition - now removed, and
  replaced with an explicit note that section 7 supersedes it, so the next session does not re-add it.
- `.claude/agents/streamsplayer-rd-lead.md:12` - the **default orchestrator's** own rules line, i.e. it
  was reaching the system prompt of most sessions in this repo. Fixed.

Generalisable: when the canon reverses a rule, the adopters that were most diligent about adopting it
are the ones now most wrong, and a grep for the *old* rule's wording is the only thing that finds it -
the compliance gate cannot, because a superseded rule is not a restatement of a live one.

### GITHUB_INTERACTION section 6 - the .ps1 command-head family, and a permission list it made dead

The new Bash-safety family ships as `guard-bash.ps1`. Verified live rather than assumed: piping a
`{"command":"./build.ps1 -Test -Deploy:$false"}` payload into the hook returns **exit 2** with the
"Bash cannot execute a .ps1" refusal.

Two consequences here, and the second is the interesting one:

- Both rules files documented every script as `./build.ps1 ..`, `./scripts/check.ps1 ..` - the exact
  refused shape. Rewritten to `pwsh -NoProfile -File ./..`, with a one-line note that a human in
  PowerShell types the bare form and an agent must not. The README, the site and the Store docs keep
  the bare form deliberately: those are instructions for a human, not tool calls.
- `.claude/settings.json` allow-listed `Bash(./build.ps1*)`, `Bash(./run.ps1*)` and `Bash(./scripts/*)`.
  Those three rules had become **unusable by construction** - the hook refuses the call before the
  permission layer is ever consulted. Removed, with the reason recorded in the file's own comment.
  `Bash(pwsh *)` already covers the compliant form. **A permission entry that a hook makes unreachable
  is worth a check of its own**: it reads as a granted capability and is in fact a dead rule, and
  nothing in the current gate set notices.

This repo registers **no hooks of its own**, so AI_USAGE section 5's "drop your hand-wired copy rather
than run it twice" had nothing to act on. `CLAUDE.md` now says so explicitly, so a future session does
not add a local copy of a hook the canon already ships.

### The rules files were carrying four false statements about their own tree

The re-sync's "verify every kept claim against the live tree" step found more than the canon delta did.
All four verified twice - once by a subagent, once directly:

- **`SP-0052` was described as "not implemented; do not describe it as shipped".** It is `Implemented`,
  sits in `PLAN/DONE/`, and ships: `BundledCatalogSnapshot`, `CatalogSnapshotService`,
  `FirstRunCatalogWindow`, an embedded `Resources\catalog-snapshot.zip` whose absence **fails the
  build**, and a `scripts/release.ps1` step that makes regenerating it a release blocker. The
  instruction was not merely stale, it was actively dangerous: an agent obeying it would have refused
  to describe a release-gating feature that exists, or re-implemented it. Now recorded as shipped and
  awaiting manual verification (`Implemented`, not `Verified`).
- **`CatalogMerger.Merge` "only updates/removes rows whose SourceOrigin == Catalog"** - the
  MANUAL/IMPORTED protection holds, but removal is now gated on `CatalogMergeOptions.RemoveMissing`,
  which the snapshot path passes as `false`. The claim was true of one of two merge modes.
- **"sixteen partials"** - there are 26. The number was stale by ten while the same sentence said
  "glob, do not memorize". Deleted rather than corrected.
- **The dialog list** named a `LanguageWindow` that does not exist and missed `ChannelInfoWindow`,
  `FirstRunCatalogWindow` and `LogArchiveReadyWindow`. Replaced with a glob instruction and no list.

Also corrected: `CLAUDE.md` cited a 3.9 MB live favicon atlas where the source comment says 2.9 MB, in
a sentence whose own advice is "read the constant, never a number from prose" - the number is gone;
`AGENTS.md` claimed the four version fields in `Directory.Build.props` "are updated together before a
release", where `release.yml` in fact derives the version from the `v*` tag and passes it as
`-p:Version=..` (the props file is the local-build stamp only); and the stale "after the GitHub
repository is created, add the remote" block was dropped, `origin` having existed for some time.

**The pattern worth carrying:** every one of these sat in a file whose *canon* conformance was already
clean. Reference-model adoption removes the restated universal rules, which is exactly what makes the
remaining repo-specific claims the only thing left to rot - and nothing gates them. The count-shaped
claims ("sixteen", "3.9 MB", a hand-kept list) went stale fastest, which argues for writing the glob
instruction instead of the count wherever a rules file is tempted to enumerate.

### Compliance gate: 6 warnings -> 1

`check-compliance.ps1`, before: **0 errors, 6 warnings**. After: **0 errors, 1 warning**.

- `SZA-LAY03` - `docs/` held three markdown files and no index. Added `docs/README.md`, which mostly
  exists to state the split a newcomer gets wrong: most of `docs/` is a **generated** Pages site and
  hand-editing it is a silent revert, while the maintainer documents beside it are hand-written.
- `SZA-SURF02` x2, `SZA-SURF03` x2 - no SEO block, no `robots.txt`, no `sitemap.xml`. Fixed **in the
  generator, never in `docs/`** (invariant 16). The SEO block went into the shared `_head.html`
  partial, so one edit covered 26 pages in 13 languages; every value it needed already existed as a
  structural token, so no copy deck changed and no translation was invented.
  - `robots.txt` and `sitemap.xml` are generated from the same language x page product the pages come
    from, so a fourteenth language lands in them with no edit - the failure mode a hand-kept sitemap
    always reaches. 26 URLs, each carrying the full `hreflang` alternate set plus `x-default`.
  - **JSON-LD is built in the script, not in the template.** An HTML parser does not decode entities
    inside a `ld+json` script element, so reusing the HTML-escaped `{{page.title}}` there would have
    emitted a literal `&quot;` into the JSON and broken it on every page. Values are taken raw from the
    copy deck and escaped by `ConvertTo-Json`. Verified by parsing the emitted block on all 26 pages -
    0 failures, Cyrillic intact.
  - `og:image` is a real 1200x630 card generated by a new `tools/site/make-og-image.ps1` from the
    existing icon and the site's own palette (`--bg #0a0f0a`, `--accent #3fb950`), not the 256 px icon
    reused as a square. It has a `-Check` mode, like the site generator.
- `SZA-STYLE02` (`memory/MEMORY.md:552,749`) - **kept, deliberately.** Both hits are the case the
  gate's own fix text calls legitimate: an exact quoted UI automation string and a CLI placeholder.
  House style governs prose, not exact strings (invariant 20), and rewriting a UIA name to satisfy a
  warn-only style check would break the thing it names. Recorded rather than "fixed".

### Two contrib deltas above are now stale

Recorded rather than silently amended, since they were true when written:

- **LOCALIZATION delta** says in-app UI is EN+RU only against EN/RU/UK on the site. The repo now ships
  **thirteen** interface languages from a single `InterfaceLanguages` registry in Core, read by the
  PowerShell tooling out of the built assembly. `SP-0029` (the "add UK" ticket that delta produced) was
  overtaken by a much larger change. The per-surface-coverage rule the delta established still holds;
  its example does not.
- **PLATFORM_OVERLAYS delta** says the favicon atlas is "optional and `<=4 MB`". The cap is now
  `StreamBankReader.MaximumAtlasBytes` = 30 MB. The invariant that matters (an over-cap atlas is
  silently dropped, not an error) is unchanged. Same lesson as the rules files: the constant belongs in
  the record by name, not by value.

### Verification

Every command run fresh in this session, exit codes cited:

| Command | Exit | Result |
| --- | --- | --- |
| `check-compliance.ps1` (before) | 0 | 0 errors, 6 warnings |
| `check-compliance.ps1` (after) | 0 | 0 errors, 1 warning |
| `pwsh -NoProfile -File tools/site/build-site.ps1` | 0 | 13 languages x 2 = 26 pages, + robots.txt, sitemap.xml |
| `pwsh -NoProfile -File tools/site/build-site.ps1 -Check` | 0 | `docs/ is up to date.` |
| `pwsh -NoProfile -File tools/site/make-og-image.ps1 -Check` | 0 | present at 1200x630 |
| `./build.ps1 -Test -Deploy:$false` | 0 | Build succeeded, 0 warnings, **789/789 tests passed** |

One honest note on that last row: the first attempt returned **exit 1**, ".NET SDK not found", from the
agent's Bash sandbox, where `dotnet` is not on `PATH`. That is a **could-not-verify, not a failure** -
AI_USAGE section 2's third invariant - and re-running the identical command through the PowerShell tool
gave 10.0.302 and a green run. Recorded because a sandbox that lacks the toolchain will otherwise be
read as a red gate by the next session.

The working tree also carried **unrelated uncommitted work** (a random-station feature) throughout. It
was not touched, not staged, and not reverted; the commit for this pass names its paths explicitly, and
`git add -A` was never run. The 789-test green above covers that WIP too, which is why it is quoted as
context rather than as this change's own evidence - nothing in this pass touched C#.

### Needed canon fixes (for a canon session, not applied here)

- **A dead permission entry has no check.** `.claude/settings.json` carried three allow rules that
  `guard-bash` had made unreachable. Nothing in `check-compliance.ps1` notices a permission that grants
  a capability a shipped hook refuses, and the failure is silent in the safe direction, which is why it
  survived. Worth a gate, or at least a line in the hooks README's contract section.
- **Superseded rules need a migration note, not just a rewrite.** The reply-timestamp reversal was
  findable only by grepping adopters for the *old* wording. When a canon rule flips, the update is
  cheap to write and expensive to propagate; a short "adopters carrying X should remove it" line in the
  changed doc would make the next re-sync mechanical instead of archaeological.

## Canon re-sync 2026-09-03 - two updates behind, and only the stamp moved

Run from the canon repo against `P:\WINDOWS\Streams_Player` (`check-compliance.ps1 -RepoRoot`).

**What had to be re-read.** The stamp was at `2026.08.18.1` / digest `961c9c8a`. `Canon update 2026-08-28` is
the only one of the two intervening updates that touched rule docs (AI_USAGE, DEVELOPMENT,
DOCUMENTATION_CONCEPT, INVARIANTS, TESTING_AND_QA); the 2026-09-03 movement is `tools/harness/` and moves no
digest, only the plugin version.

**Reconciled: nothing owed, and one rule checked rather than assumed.** The lock-domain split, the abandoned
ticket's withdrawal, the unattended batch driver and the closure-runs-the-rung rule all presuppose machinery
absent here - no lock queue, no ticket store with a single write path, no closure facade. The locale rule
(INVARIANT 17 / DOCUMENTATION_CONCEPT §5) relaxed rather than tightened, so the three authored READMEs and the
12 `Localization.*.xaml` tables are already inside what it permits. The one worth checking on the tree instead
of by assumption was TESTING_AND_QA's new "a check only a human can run has not happened yet": it wants the
closing status held back by an unticked manual line, and `PLAN/` carries **no checkbox at all** - `grep -rn
"- \[ \]" PLAN/` returns nothing across all 21 specs and `PLAN/DONE/`. So the rule has no surface to bind to
here; standing up an audit section per spec is an owner call, not a re-sync side effect. Carried forward.

**Evidence.** `check-compliance.ps1 -RepoRoot P:/WINDOWS/Streams_Player` before -> `0 error(s), 2 warning(s)`,
after -> `0 error(s), 1 warning(s)`, exit 0. The remaining SZA-STYLE02 is `memory/MEMORY.md:659,856`, and both
hits are quoted material - an in-app string ("Add a channel someone sent you as text..") and a quoted GitHub
error about the `workflow` scope - which the check's own fix line names as legitimate.

**Commit discipline.** The working tree carried in-flight work across the three READMEs and twelve
`Localization.*.xaml` files. Only `.sza-canon.json` was staged; `git add -A` was never run.
