# Contribution: epub_2_html (doc-html-translate) - Overlay A hybrid + new "extension edition" -> Unified_Rules
Source repo: p:\WINDOWS\EPUB_2_HTML | Date: 2026-07-23
Read: README, NEW_PROJECT_CHECKLIST, REPOSITORY_LAYOUT, DOCUMENTATION_CONCEPT, PLATFORM_OVERLAYS,
RELEASE_AND_DISTRIBUTION, DEVELOPMENT, TESTING_AND_QA, GITHUB_INTERACTION, AI_USAGE, AUTHOR,
LOCALIZATION, SECURITY_AND_PRIVACY, SUPPORT_AND_FEEDBACK, SITE_CONFIGURATION.

## Overlay facts (verified against this repo)

This project is **Overlay A distribution (GitHub + winget + Microsoft Store) on an Overlay C source
body (Go `cmd/`+`internal/`), plus a second independent JS "extension edition"** shipped to Chrome
Web Store + Edge. No single existing overlay describes it; the four facts below are the reconciled shape.

- **Source root & release-mechanics.**
  - Source is Go, Overlay-C-shaped: `cmd/doc-html-translate/` (CLI) + `cmd/doc-html-ui/` (GUI) +
    `internal/<fmt>/` packages, `go.mod` module `doc-html-translate` (evidence: `ls cmd/`, `ls internal/`,
    `head -3 go.mod`). **Not** Overlay A's `src/`.
  - Release-mechanics are **not** under a single `publishing/` umbrella. They are separate root folders,
    one per channel: `winget/`, `msix/`, `installer/` (Inno `.iss`), `tools/store/` (Partner Center
    `listingData.csv` + logo/screenshot scripts), and `extension/` (evidence: root `ls`; `ls winget/ msix/
    installer/ tools/store/`).
- **Version shape.** Authoritative date tag `YY.MMDD.HHmm` (winget `PackageVersion: "26.0702.1530"`),
  **MMDD zero-padded** - not the overlays' `YY.M.D.HHmm`. Stamped via Go `-ldflags "-X main.Version=..."`
  (evidence: `scripts/build.ps1:68`). The extension edition versions itself on its own clock and shape
  (`extension/manifest.json "version": "26.718.1849"`) - channels are not lockstepped.
- **Channels + listing files (5 one-way ops, each its own trigger).**
  1. GitHub Release (app exes/zip) - `v*` tag -> `.github/workflows/release.yml` `[PAID CI]`.
  2. winget - manifests in `winget/*.yaml` (source of truth), PR to microsoft/winget-pkgs.
  3. Microsoft Store - MSIX built by `msix/build-msix.ps1`, **manual** Partner Center upload; listing copy
     in `tools/store/listingData.csv`.
  4. Chrome Web Store - `ext-cws-v*` tag -> `publish-cws.yml` `[PAID CI]`; listing `extension/store/LISTING.md`,
     `extension/store/PRIVACY.md`.
  5. Edge Add-ons - `ext-edge-v*` tag -> `publish-edge.yml` `[PAID CI]`, **published independently of Chrome**.
  (evidence: `DEV/RELEASE.md` steps 2-6.)
- **Frozen anchors (this product).** winget `PackageIdentifier: SerZhyAle.DocHtmlTranslate`; Inno
  `AppId={{E8B4F1C7-2A9D-4E63-9F1B-7C3A5D8E2B04}` (marked "Do not change"); MSIX Identity `Name` =
  `SZA.Doc-HTML-Translate` (passed via `build-msix.ps1 -IdentityName`, template `{{...}}` in
  `msix/AppxManifest.xml`); Go module path `doc-html-translate`; **distinct Chrome item id and Edge
  product id** (never a shared/pinned manifest key). (evidence: `winget/SerZhyAle.DocHtmlTranslate.yaml`,
  `installer/doc-html-translate.iss`, `msix/AppxManifest.xml`, memory `extension-store-ids`.)

## Deltas by document

### PLATFORM_OVERLAYS.md
- DIVERGE: Overlay A mandates `publishing/` with one subfolder per channel and a "two-levels-up" repo-root
  rule. This repo has **no `publishing/`** - channels are top-level siblings (`winget/`, `msix/`,
  `installer/`, `tools/store/`, `extension/`). The umbrella is optional; the invariant that survives is
  "one folder per channel, manifests committed as source" (evidence: root `ls`).
- DIVERGE: an overlay can be **A-distribution on a C-source body**. The doc presents A and C as mutually
  exclusive; here the source root is Go `cmd/`+`internal/` while the channels are winget+Store (evidence:
  `cmd/`, `internal/`, `winget/`, `msix/`).
- CORRECT: version shape for a desktop app here is `YY.MMDD.HHmm` (MMDD zero-padded), not `YY.M.D.HHmm`
  (evidence: `winget PackageVersion "26.0702.1530"`). Different channels of the *same* product also carry
  different date shapes (extension `26.718.1849`) - the "one authoritative form, remapped mechanically"
  rule is only partly honored across the app/extension split.
- ADD (candidate new overlay / sub-overlay): **Browser-extension edition.** A second, code-independent JS
  product built from the same intent, published to Chrome Web Store + Edge, each on its own tag family and
  its own store id, with `extension/store/{LISTING,PRIVACY}.md` as listing files and `extension/_locales/`
  for UI strings. It has **no shared code** with the Go app - the two are hand-ported and kept in sync by a
  parity doc + gates (evidence: `extension/`, `DEV/RELEASE.md` step 5, `docs/PARITY.md`).

### REPOSITORY_LAYOUT.md
- DIVERGE: internal docs live under a **`DEV/`** umbrella, not `docs/`. `docs/` here holds only a few
  public/cross-edition docs (`PARITY.md`, `SPEC_LIFECYCLE.md`); the working set (`CHANGELOG.md`,
  `RELEASE.md`, `RELEASE_STATE.md`, `plan/`, `research/`, `DOCS_SURFACES.md`) is under `DEV/` (evidence:
  `ls DEV/`, `ls docs/`).
- DIVERGE: **CHANGELOG is not at repo root** and is not Keep-a-Changelog - it is `DEV/CHANGELOG.md`, a
  dev-log table (`Timestamp | Path | Target | Description`) (evidence: `head DEV/CHANGELOG.md`; no root
  `CHANGELOG.md`).
- DIVERGE: specs are `DEV/plan/<YYYY-MM-DD>_<slug>.md` with `DEV/plan/ROADMAP.md` as the priority queue and
  `DEV/plan/done/` as the archive - not the taxonomy's `docs/specifications/SPECIFICATION_*.md` (evidence:
  `ls DEV/plan/`, `CLAUDE.md` "Spec / plan tickets").

### DOCUMENTATION_CONCEPT.md
- ADD: a **documentation-surfaces manifest** (`DEV/DOCS_SURFACES.md`, driven by the `/docs-sync` skill)
  enumerates every user-facing surface that must move together when a feature ships, and pins **en/ru/uk as
  one atomic edit, not three follow-up requests**. This is the "one source, many render targets / one voice
  across surfaces" principle turned into a checked manifest, born from the failure of re-discovering the
  surface set by hand each release (evidence: `DEV/DOCS_SURFACES.md`).
- CONFIRM (with a twist): mandatory privacy page exists **once per edition** - root `privacy.html` (app) and
  `extension-privacy.html` (extension) (evidence: root `ls`).
- DIVERGE: the "CHANGELOG rendered verbatim into release body + site What's-new" flow does not hold here -
  `DEV/CHANGELOG.md` is an internal dev ledger; the public "What's new" is curated separately during release
  and the extension has its own `store/LISTING.md` What's-new block (evidence: `DEV/DOCS_SURFACES.md` rows,
  `DEV/RELEASE.md`).

### LOCALIZATION.md
- DIVERGE: **no `README_<lang>`** - the app README is EN-only; localization is carried on the site and a
  separate-file docs trio, not on the README (evidence: root `ls` shows only `README.md`).
- DIVERGE: **two web-localization models coexist**: separate files `docs.html` / `docs.ru.html` /
  `docs.uk.html` (the "3-language trio", mirrored content, translated prose) *and* in-page trilingual blocks
  inside a single `index.html` / `extension.html`. The doc assumes one model (evidence: `DEV/DOCS_SURFACES.md`).
- CONFIRM: parity-enforced string workflow holds for the extension via Chrome i18n - keys must exist in
  `extension/_locales/{en,ru,uk}/messages.json` "or none" (evidence: `ls extension/_locales/`,
  `DEV/DOCS_SURFACES.md` "Extension i18n" row).

### DEVELOPMENT.md
- ADD (new discipline): **cross-edition parity** as a first-class rule. The product ships two editions of the
  same logic in two languages with **no shared code**; drift is managed by `docs/PARITY.md` (source of truth
  for shared invariants + intentional differences) plus two gates: `tests/parity_test.go` (VALUE invariants -
  theme palette, OCR/reflow constants) and `scripts/parity-check.ps1` (STRUCTURAL drift - one side of a
  Go<->JS ported capability moved without the other) (evidence: `scripts/parity-check.ps1` header,
  `CLAUDE.md` "Cross-edition parity"). The canonical docs assume one codebase per product.
- ADD (recurring-defect-to-gate, made concrete): the "promote a recurring defect to a mechanical gate" rule
  (DEVELOPMENT §9) is realized as checked-in Go tests: `tests/typography_test.go` (house text-style drift
  guard on generated HTML - allowlists an em-dash **only** inside a `<title>` literal), `tests/ui_cli_parity_test.go`
  (GUI must expose every CLI flag), `tests/smoke_test.go`, `tests/testdoc_test.go` (evidence: `ls tests/`).
- ADD (Windows filesystem trap): **run artifacts go in the repo's gitignored `temp/`, never a deep scratch
  path.** A ~111-char scratchpad path silently breaks OCR via Windows `MAX_PATH` and looks like an
  OCR-quality regression - a false bug (evidence: memory `run-artifacts-in-project-temp`; sharpens
  DEVELOPMENT §10 "no root writes / temp tree" with a Windows caveat).
- CONFIRM: the CRLF-vs-gofmt hazard is resolved structurally via `.gitattributes` (`*.go eol=lf`) so
  `gofmt`/lint are clean without a manual LF-normalize dance; `go` is on PATH in PowerShell, not in the Bash
  tool (evidence: `CLAUDE.md` Environment; memory `gofmt-crlf-gotcha`).

### TESTING_AND_QA.md
- CONFIRM/ADD: the pre-release sweep here is a **full-corpus re-test** (convert every sample format, then a
  headless view-check via the `/verify-view` skill), not just install/first-run/uninstall. The Windows-desktop
  device rung is "run the built exe on a clean path"; the persona happy-path is "convert, open `index.html` in
  Chrome, translate in-browser - no API key" (evidence: `CLAUDE.md` "What this is"; memory `sweep-run2-2026-07-18`;
  `scripts/verify-html.ps1`).

### GITHUB_INTERACTION.md / RELEASE_AND_DISTRIBUTION.md
- DIVERGE: "release" is **not one operation** - it is up to **5 independent one-way ops**, each its own
  trigger and cost tag: `v*` (app, paid CI), winget PR, MSIX manual upload, `ext-cws-v*` (Chrome, paid CI),
  `ext-edge-v*` (Edge, paid CI). The extension edition ships on its own cadence, decoupled from the app
  (evidence: `DEV/RELEASE.md` steps 2-6). The docs' single-"release" model needs a per-edition, per-channel
  fan-out.
- ADD (winget submit nuance): `wingetcreate update` copies the old metadata forward, so **to change
  description/tags you must edit `winget/` and `wingetcreate submit winget`** (the folder form), and the
  auto-generated PR body must be replaced with real notes via `gh pr edit`. Always `winget install
  --manifest winget` locally first - it is the only gate that verifies URL+SHA end-to-end (`winget validate`
  checks schema only) (evidence: `DEV/RELEASE.md` step 3; memory `release-winget-install-test`).
- ADD (release-time dependency sweep): before each release, check for newer OCR/translation model + lib
  versions (tesseract.js, the tessdata pin, pdfjs, Go deps) and fold worthwhile ones in; **the tessdata pin
  is a cross-edition parity invariant** (must match in both editions) (evidence: memory
  `release-check-dependency-updates`).

### SECURITY_AND_PRIVACY.md
- CONFIRM: no signing material tracked - the CWS/CRX signing key is git-ignored (`extension/.gitignore`:
  `cws-key*.json`, `*.pem`, `.env`), and MSIX is built unsigned (Store re-signs). Publisher-constant values
  are template placeholders in `msix/AppxManifest.xml`, passed as build params (evidence: `git ls-files
  extension/cws-key.json` -> empty; `extension/.gitignore`; `msix/AppxManifest.xml` `{{PUBLISHER}}`).
- ADD: a store-wide **Publisher GUID + display name + portable IARC rating id** is reused across all SZA
  Store apps and lives in the MSIX build-script defaults - one identity, many products (evidence: memory
  `sza-store-publisher-identity`; matches Overlay A's "publisher-constant values in build-script defaults").

### AI_USAGE.md
- CONFIRM/ADD: the memory model here is Claude Code's **native per-user memory** (`~/.claude/projects/.../memory/`
  with a `MEMORY.md` index), not the doc's reference `.claude/agent-memory/<agent>/` in-repo, git-shared
  layout. Same discipline (durable/non-obvious only, verify a remembered path before acting), different home -
  it is per-user and **not** committed with the team (evidence: `CLAUDE.md` "Persistent memory"; this repo's
  memory dir).

## No delta
NEW_PROJECT_CHECKLIST, SUPPORT_AND_FEEDBACK, SITE_CONFIGURATION, AUTHOR (all confirmed, nothing to add beyond
what the shared docs already state; AUTHOR is the same owner profile these rules were written from).

## New candidate rules (not in any shared doc yet)
- **Multi-edition products need a parity source-of-truth doc + a drift gate.** When the same product ships as
  two independent codebases (Go app + JS extension), a hand-port drifts silently. Prevent it with one
  `PARITY.md` (invariants that must match + intentional differences that must not be "fixed") and a gate that
  fails when one side of a paired capability moves alone. Prevents a shipped behavior mismatch between editions
  (evidence: `docs/PARITY.md`, `scripts/parity-check.ps1`).
- **Ship-together surfaces belong in one manifest, edited atomically across locales.** A feature that lands in
  code but not in every listing/site/README-locale is a real, observed failure. A `DOCS_SURFACES.md` manifest
  + a `/docs-sync` skill make en/ru/uk one edit, not three follow-ups (evidence: `DEV/DOCS_SURFACES.md`).
- **On Windows, artifact path length is a correctness constraint, not just tidiness.** Deep scratch paths
  break `MAX_PATH`-sensitive subprocesses (OCR) and masquerade as quality bugs; pin run artifacts to a short
  repo-relative `temp/` (evidence: memory `run-artifacts-in-project-temp`).
- **A drift guard may need a scoped allowlist for a legitimate exception.** The typography gate bans em-dashes
  everywhere in output except inside a `<title>` literal (`Book - Page N` keeps the conventional book em
  dash). A blanket ban would force a wrong fix; encode the one exception in the gate (evidence:
  `tests/typography_test.go`, `CLAUDE.md` Typography).

## Open questions - RESOLVED into the canonical docs (2026-07-23, by owner instruction)
The owner directed that these files are the universal source of truth and to fold the answers in directly.
Applied:
- **Overlay D - Browser extension (Chrome Web Store + Edge Add-ons)** added to `PLATFORM_OVERLAYS.md`, plus a
  new **"Editions"** section (one product, several overlays, kept in sync by a parity doc). The extension is
  documented as an *edition* of a parent app, not a bolt-on.
- **`publishing/` umbrella relaxed** in `PLATFORM_OVERLAYS.md` Overlay A: the invariant is now "one committed
  folder per channel"; the umbrella is the recommended-but-optional grouping. Also notes A-distribution can
  sit on a Go `cmd/`+`internal/` source body.
- **Version shape broadened**: `PLATFORM_OVERLAYS.md` now states the digit-padding (`YY.M.D.HHmm` vs
  zero-padded `YY.MMDD.HHmm`) is a **per-project frozen choice**; requirement is monotonic + lexically
  sortable, never changed after first ship. Not forced onto other projects.
- **CHANGELOG model reconciled**: `DOCUMENTATION_CONCEPT.md` §2 now accepts two shapes - verbatim
  Keep-a-Changelog at root, **or** an internal engineering ledger (`DEV/CHANGELOG.md`) feeding a curated
  public "What's new" from the diff since last release. `REPOSITORY_LAYOUT.md` notes the `DEV/` umbrella as
  an accepted variant.
- Also folded in: multi-edition **parity discipline** (`DEVELOPMENT.md` §12), scoped-allowlist-in-gate and
  the Windows `MAX_PATH` artifact caveat (`DEVELOPMENT.md` §9-10), the **ship-together surfaces manifest**
  (`DOCUMENTATION_CONCEPT.md` §5), the two web-localization page models + optional `README_<lang>`
  (`LOCALIZATION.md`), the release fan-out per edition/channel (`RELEASE_AND_DISTRIBUTION.md` §1, §5), the
  extension frozen anchors + CRX-key exclusion (`SECURITY_AND_PRIVACY.md` §2), the **Edition** glossary term
  (`README.md`), and the overlay/edition note in `NEW_PROJECT_CHECKLIST.md` §0.

## New doc created from this project's experience
- **`CHANNEL_MATRIX.md`** added to the core: a per-channel publishing reference (trigger / cost / auth /
  signer / listing source / frozen anchor / verify) for GitHub, winget, MS Store, Chrome, Edge, Play. It
  unifies facts that were previously only in this repo's `DEV/RELEASE.md`. Wired into `README.md` index +
  read-order, `RELEASE_AND_DISTRIBUTION.md` §5, and `NEW_PROJECT_CHECKLIST.md` §6.

## Open questions for the owner
- None outstanding. If the extension edition ever ships as its **own** repo (not a subtree of the parent
  app), revisit whether "Overlay D" should carry a standalone `publishing/`-style layout instead of the
  in-app `extension/` subtree described now.

## Spread-back applied 2026-07-23
Ran the SPREAD_BACK_PROMPT flow in `p:\WINDOWS\EPUB_2_HTML` (EXISTING-repo mode).

- **Consumption model: REFERENCE** (not a mirror). The repo links to the canon path and keeps only its
  deltas/repo-specifics locally - nothing to keep in sync. No `docs/guides/` mirror created.
- **Repo rules updated:**
  - `AGENTS.md` - added a top "## SZA Unified Rules (canon)" section: canon path + read-`README` pointer,
    the explicit "this file keeps only deltas, does not restate universal rules" statement, a pointer to
    this contrib record, and the four overlay facts (A-on-C source body + JS extension edition; no
    `publishing/` umbrella / `DEV/` docs umbrella / `DEV/CHANGELOG.md` ledger; version shape `YY.MMDD.HHmm`;
    5 one-way release ops; frozen anchors).
  - `CLAUDE.md` - added a one-line canon pointer in the intro that defers to the AGENTS.md section (single
    source, no drift).
  - Nothing removed: AGENTS.md was already almost entirely repo-specific deltas, so there were no restated
    universal rules to strip.
- **Claims re-verified against the live tree** (all still true): root has no `publishing/` (channels are
  top-level siblings `winget/ msix/ installer/ tools/store/ extension/`); internal docs under `DEV/`;
  `go.mod` module `doc-html-translate`; winget `PackageIdentifier: SerZhyAle.DocHtmlTranslate`;
  `extension/store/{LISTING,PRIVACY}.md` + `extension/_locales/{en,ru,uk}/` present; both privacy pages
  (`privacy.html`, `extension-privacy.html`) at root; web-loc trio `docs.ru.html` / `docs.uk.html`.
- **Open questions:** none were outstanding; none opened.
- **Drift:** none newly found; the pre-existing DIVERGE deltas above remain legitimate and are now pinned
  in the repo's own AGENTS.md.
- **Verification (canon TESTING_AND_QA):** `./scripts/check.ps1` -> **exit 0**. Go tests pass (incl.
  `tests/` 125.5s: typography + ui/cli-parity + smoke + testdoc drift guards), `Lint passed`,
  `Typo check passed` (scans the edited `.md`), `parity-check: no cross-edition drift`.
- **Commit:** landed in the repo per its conventions (English message + co-author trailer); not pushed
  (local "build" flow, no tag).
- **Needed canon fix (owner to apply in a canon session, not committed from here):** mark the
  `P:\WINDOWS\EPUB_2_HTML` row Done in `SPREAD_BACK_PROMPT.md`.

## Canon adoption 2026-07-27

Adopted as the `sza` plugin (consumption model **reference**), committed. `.sza-canon.json`: overlay A,
browser-extension edition with `ext-cws-`/`ext-edge-` tag prefixes on their own clock, ledger shape 2
(`DEV/CHANGELOG.md`), six channels, root-served site.

Fixed: the verbatim house-text-style restatement in `CLAUDE.md` (the book-page em-dash exception is genuinely
repo-specific and stays); the missing why-comment beside the committed-binary negations, now covering both the
`build/` exes and the vendored Poppler DLLs; `<link rel="canonical">` on the three docs pages; the em dash in
the index title.

Compliance gate: **0 errors**, 13 warnings (og/twitter/JSON-LD, sitemap/robots, no `docs/README.md`).

## Canon reconcile 2026-08-02 - agent-process propagation

Canon **2026.07.27 -> 2026.08.02**, core digest `sha256:dae220bf..` -> `sha256:6c247452..`. Stamp
updated; the adoption model is unchanged. The upstream change is [AI_USAGE.md](../AI_USAGE.md) only -
the agent-process findings propagated from FastMediaSorter mob_v2 under its ticket S1342 - so the
staleness ladder's "re-read only the changed rule docs" path applies and no full re-adoption was run.
Nothing in `rules/` touched packaging, release, channels or layout, and no divergence was found
between the new bullets and this repo's own rules file.

Memory here is the per-user store (`~/.claude/projects/../memory/` with a `MEMORY.md` index), not a
committed one, so §4's new rules apply to a store this repo does not own. The budget and the
no-restatement rule still transfer - the index is billed per turn wherever it lives - but the expiry
rule keyed to work-item liveness has no ticket system here to key against, and is inert until one
exists. Named rather than carved out, so a later reader does not mistake silence for exemption.

Verification: `check-compliance: EPUB_2_HTML - 0 error(s), 11 warning(s) (overlay A, canon 2026.08.02)` - warnings are pre-existing and none was introduced here.

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

**Finding 2 reproduces here, verbatim, and this is the repo where it is worth acting on.** `CLAUDE.md`
"Skill routing (slash commands)" opens with "Pick the cheapest path that fits:" and then lists `/quick`
(trivial edit) and `/fix` (narrow fix) ahead of the `/spec-*` pipeline - the same smallest-first ordering,
stated as prose, with nothing behind it: `.claude/settings.json` declares no hooks at all. The paragraph
also says the ladder was **imported from the Universal Agent Kit**, which is where the shape came from and
where every other importing repo got it too.

Not fixed from this session. Installing a routing hook is a behaviour change in this repo, its pattern lists
have to be written against this repo's real prompts, and the canon states outright that the remedy's effect
is unmeasured. Carried as an owner decision, named here so silence is not read as an exemption.

Verification: `check-compliance: EPUB_2_HTML - 0 error(s), 11 warning(s) (overlay A, canon 2026.08.05)` -
warnings are pre-existing and none was introduced here.

## Canon reconcile 2026-08-18 - the two updates the plugin cache never served

Canon **2026.08.05 -> 2026.08.18.1**, core digest `sha256:8d33fdab..` -> `sha256:961c9c8a..`. Consumption
model unchanged (**reference**).

Why this is not a routine tick: the `sza` plugin served a cached **2026.07.27** in this repo for roughly
three weeks, so no session here ever loaded the 08-08 or the 08-18 rule docs. The 08-02 and 08-05 sections
above were written against the canon repository directly rather than through the plugin, so they stand -
**the real gap is 08-08 and 08-18 only**, and this section covers exactly those two. Recorded because the
next reader will otherwise assume a four-update backlog and re-do work that is already on this page.

The stamp had already been moved to 2026.08.18.1 by hand before this session, and was re-derived rather
than trusted: `check-compliance.ps1 -PrintDigest` recomputes `sha256:961c9c8a..`, matching the stamp, and
both `exemptions` paths resolve in the tree. No stamp field was edited from this session.

Upstream inside the gap: AI_USAGE §1/§3/§5, DEVELOPMENT §15/§16, GITHUB_INTERACTION §6, TESTING_AND_QA §8.

### The 2026-08-05 carried-forward decision is closed - by the canon, not by this repo

The 08-05 section left one owner decision open: whether to install a `UserPromptSubmit` routing nudge,
since this repo reproduces the ungated size-tier ladder verbatim. **AI_USAGE §5 as of 08-18 answers it: the
canon ships the hook itself, and a project must not rebuild one.** Verified against the installed plugin
cache rather than the marketplace clone, as that same bullet demands: `hooks/on-user-prompt.ps1` exists in
`sza/2026.818.1` and `hooks/hooks.json` registers it on `UserPromptSubmit`. This repo's
`.claude/settings.json` declares no hooks at all, so there is nothing to drop and nothing running twice.
The decision is closed with no repo change - which is the outcome the cache blackout hid for three weeks.

### Divergences found against the live tree, all fixed here

The working tree was the authority throughout; four of these were documents asserting things the tree
contradicts.

1. **Three dead pointers.** `DEV/plan/ROADMAP.md`, `DEV/plan/_TEMPLATE_cross-edition.md` and
   `DEV/plan/2026-07-01_cross-edition-parity.md` were all deleted in commit `814e4c5`, and both `CLAUDE.md`
   and `AGENTS.md` still linked them. The queue is now `DEV/plan/RELEASE_QUEUE.md`, and its precedence rule
   is **asymmetric** - the queue wins on order, the ticket file wins on status. The old prose said the
   opposite ("the prose usually wins"), so an agent following it would have re-ordered work against the
   queue's stated intent.
2. **A resolved gotcha still documented as live.** `CLAUDE.md` warned that the tree is CRLF and `gofmt -l .`
   therefore flags every file, prescribing an LF-normalise dance. Measured: `.gitattributes` pins
   `*.go text eol=lf`, and `gofmt -l .` returns 2 paths, both throwaway files under the gitignored `temp/`.
   Replaced with the settled fact plus a do-not-re-litigate note.
3. **The slash-command list was short by three.** `.claude/commands/` holds 14; the rules file listed 11,
   omitting `/changelog`, `/docs-sync` and `/verify-view` - the automation rungs most likely to be skipped.
4. **Canon-owned rules still restated.** `CLAUDE.md` carried its own copies of build-is-not-a-release, the
   cross-edition process and the memory discipline, all duplicated from `AGENTS.md` or the canon; they are
   now pointers. `AGENTS.md` re-authored the house text style in order to state its scoping - rewritten to
   name the canon rule and keep only the delta, which is the part that matters: **the style binds `en`,
   `ru` and `uk` only**, the other ten interface languages are exempt, and `tests/typography_test.go`
   enforces that scoping.
5. **A genuine delta reading as a restatement.** The ledger-shape line ("the engineering ledger
   `DEV/CHANGELOG.md`, not a root Keep-a-Changelog") tripped SZA-RULES03/DC2a. It is a real delta - stamp
   `ledgerShape` 2 - so it is now marked `<!-- canon-ok: .. -->` rather than deleted.

Gate warnings cleared in the same pass: `docs/README.md` written as the index of that tree (SZA-LAY03), and
the optional SEO block completed on all seven declared site pages (SZA-SURF02) - `og:image`, `twitter:card`
and JSON-LD, with the three `docs.*` locales done together and given mutual `hreflang` links, since they had
none. All seven JSON-LD blocks were parsed to confirm they are valid, and both `og:image` targets are
tracked files that Pages actually serves.

### Checked against the new rules, clean, no action taken

- **DEVELOPMENT §15's reachable-exit-code trap does not exist here.** No script uses `Write-Error` at all,
  and the closure script's shape was proven rather than reasoned about: a probe mirroring `scripts/check.ps1`
  (`$ErrorActionPreference = 'Stop'`, child piped through `Tee-Object`, green tail line after) shows the
  child's `throw` propagating, the tail line never printing, and exit code 1. AI_USAGE §2's three invariants
  hold: `check.ps1` covers every gate, prints its PASS only after all of them, and cannot report a false PASS.
- **TESTING_AND_QA §8 does not trigger.** Its own precondition is "once the gates are more than a handful";
  this repo runs three (test, lint, typos) plus an advisory parity check. No verdict cache was built, because
  §8 is explicit that the distribution must be measured before any gate is tuned, and there is nothing here
  worth measuring yet. Revisit when the gate count grows.
- **AI_USAGE §1's fire-and-forget prohibition** matches existing practice; the one long job in this session
  (the full gate) was backgrounded because it exceeds the foreground timeout, and its exit code and per-stage
  pass lines were both read before anything was called done.

### Release package plan (adopt-canon step 6) - what this repo actually has

Recorded as found, not as prescribed. (a) Files: `DEV/plan/RELEASE_QUEUE.md` is the work-remaining file and
`DEV/plan/done/` is the shipped history; **there is no separate ready file** - a ticket goes straight from
the queue to `done/`. (c) Done-set: `Implemented` and `Verified` leave the queue; `Draft`, `Approved`,
`Tactical`, `In Progress`, `Partial`, `Broken` and every `Block*` state are work remaining. (d) The `rel`
column is a package ordinal, never a version - the version is derived mechanically as `26.MMDD.HHmm` - with
`--` for unscheduled and a `current-next-release:` marker line. (f) Tracked, and it shows up in diffs.

**(b) and (e) are not stood up and are carried forward.** There is no single write path into the ticket
store and no `validate` / `reconcile` / `ship` commands; the queue is maintained by hand, so a status change
means editing the ticket and the queue line separately and the queue drifts between edits - the file itself
records having gone stale once already. `scripts/release-state.ps1` is not that write path; it tracks
per-channel publish state, a different thing. Building the write path was out of scope for a canon sync and
is an owner decision; the gap is now written into `CLAUDE.md` so a session inherits it instead of trusting a
stale queue.

### Verification

- `check-compliance: EPUB_2_HTML - 0 error(s), 0 warning(s) (overlay A, canon 2026.08.18.1)`, exit 0.
  Baseline before this session: **0 errors, 11 warnings**.
- `pwsh -NoProfile -File .\scripts\check.ps1` - exit 0. 29 packages `ok`, no `FAIL`, and each stage printed
  its own verdict (`Tests passed`, `Lint passed`, `Typo check passed`,
  `parity-check: no cross-edition drift in the change set.`, `All checks passed`). The integration package
  `doc-html-translate/tests` ran 158.074s.

### Needed canon fixes (for a canon session - not edited from here)

1. **The skill's own step-1 command fails as written.** `pwsh -File "$env:CLAUDE_PLUGIN_ROOT/tools/check-compliance.ps1"`
   died with exit 64 (`The argument '/tools/check-compliance.ps1' is not recognized..`) because
   `CLAUDE_PLUGIN_ROOT` is not exported into the tool's shell - only the skill's own base directory is known.
   Worth one line in `adopt-canon/SKILL.md`: if the variable is empty, the plugin root is the skill directory's
   grandparent. Every repo running this skill hits it.
2. **SZA-RULES03/DC2a fires on a repo declining the rule.** The DC2a regex matches `keep-a-changelog`
   anywhere, so the sentence "the engineering ledger `DEV/CHANGELOG.md`, **not** a root Keep-a-Changelog" -
   a delta declaration - scores as a restatement. `SZA-RULES04` already has `$forkNegationRe` for exactly
   this shape; the `canonPhrases` loop has no equivalent. A negation guard there would stop pushing repos
   toward `canon-ok` comments on lines that were never restatements.

**Both landed in canon 2026.08.18.2** (plugin `2026.818.2`), fixed in the canon repo rather than worked
around here. `adopt-canon` step 1 now resolves the plugin root from
`~/.claude/plugins/installed_plugins.json` and states why the bare variable cannot work; `agent-cost` step 2
carried the same defect and got the same fix. `DC2a` is now marked `negatable`, with a guard that skips a
mention preceded by a negation **in the same clause** - so the `canon-ok` comment on the ledger-shape bullet
in this repo's `AGENTS.md` is no longer needed: replaying that file with the comment stripped goes from
`WARN SZA-RULES03 .. restates DC2a` to no finding at all.

## Canon re-sync 2026-09-03 - clean, and the gate says so with nothing left over

Run from the canon repo against `P:\WINDOWS\EPUB_2_HTML` (`check-compliance.ps1 -RepoRoot`).

**What had to be re-read.** The stamp was at `2026.08.18.1` / digest `961c9c8a`. Only one of the two canon
updates since then touched rule docs - `Canon update 2026-08-28` (AI_USAGE, DEVELOPMENT, DOCUMENTATION_CONCEPT,
INVARIANTS, TESTING_AND_QA); today's ships `tools/harness/` alone and moves no digest.

**Reconciled: no change owed.** The lock-domain split, the queued-ticket withdrawal, the unattended batch
driver and the "closure runs the ladder's rung" rule all address a ticket store, a lock queue and a closure
facade; this repo has none of the three. The one rule that does reach it is the relaxation in
DOCUMENTATION_CONCEPT §5 / INVARIANT 17 - authored locales move with the change, the rest of the declared set
may fan out at the release boundary. The repo already routes documentation through its own `/docs-sync`
command, which is precisely the ship-together manifest the rule names, so the relaxation loosens a constraint
it was meeting rather than asking for new work.

**Evidence.** `check-compliance.ps1 -RepoRoot P:/WINDOWS/EPUB_2_HTML` before -> `0 error(s), 1 warning(s)`,
after -> **`0 error(s), 0 warning(s)`**, exit 0. The single warning was SZA-CANON03 and the stamp bump cleared
it; nothing else in the repo was touched.
