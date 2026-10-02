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

## Canon re-sync 2026-09-25 - 2026.09.24.1 reconciled; four obligations carried forward

Run from `P:\WINDOWS\EPUB_2_HTML` against the installed plugin `2026.924.1` (= the canon repo's
`CANON_VERSION` `2026.09.24.1`), for the repo's ticket 22 (`contract-rule-adoption-sync`).

**What had to be re-read.** Stamp `2026.09.06.1` / `cdf49be6..`, set on 2026-09-06 by a version-only hand
re-stamp (`e3f4301`) - thirteen versions behind. Changed rule docs: AI_USAGE, DEVELOPMENT,
DOCUMENTATION_CONCEPT, INVARIANTS, LOCALIZATION, NEW_PROJECT_CHECKLIST, PLATFORM_OVERLAYS,
RELEASE_AND_DISTRIBUTION, REPOSITORY_LAYOUT, SECURITY_AND_PRIVACY, SUPPORT_AND_FEEDBACK, TESTING_AND_QA, the
new CONTRACTS (plus README, which the digest excludes). The gate called it a warning and step 7 of this
skill an error ("version gap of 2 or more"); the run followed the contract (`RULE-DELIVERY` rule 5) and
reconciled rather than re-adopting - the divergence is already the canon's own registry exception.

**Reconciled - held.**
- CONTRACTS, INVARIANTS 10, PLATFORM_OVERLAYS, REPOSITORY_LAYOUT, LOCALIZATION, NEW_PROJECT_CHECKLIST: 20
  pointers at `docs/contracts/<ID>.md` with an index, tracked since `0c67c4e`; the catalog path named once,
  in `AGENTS.md`; registry rows for every adopted contract. The rule-adoption rows were corrected this run
  (the 2026-09-24 row claimed a `.sza-profile.json`, overlay "A/C" and a `HARNESS-PROFILE` role) and one
  `REPO-LAYOUT` rule 3 exception added; `rule-adoption/PROPOSAL-2026-09-25-doc-html-translate-rule-adoption.md`
  seconds FileDO's three proposals and CyrFlip's item 3 and adds two findings (a repo that never runs the
  harness; the gate under Windows PowerShell 5.1).
- INVARIANTS 5 / TESTING_AND_QA §5: `scripts/release.ps1` reports BLOCKED unless the last `check.ps1` run
  exited 0 or 3 on the tree HEAD holds with a clean working tree - a missing verdict and a could-not-verify
  both stop the tag.
- SUPPORT_AND_FEEDBACK §7: no usage counter; the GUI's report mail uses one constant address and names the
  product and version in its subject.
- AI_USAGE, DEVELOPMENT: address a prompt-submit hook and a profile merge; this repo has neither.

**Reconciled - new gaps, carried forward** to the repo's ticket 31 (`canon-resync-new-duties`), owner
decisions first:
- DOCUMENTATION_CONCEPT §6: no documentation registry; the site half applies (Pages from the repo root, a
  tracked `sitemap.xml` nothing generates).
- SECURITY_AND_PRIVACY §7: no permission or network-surface inventory; the facts live in three privacy
  texts. Rows found: the extension's five permissions plus `<all_urls>`; capability rows for the Explorer
  registration; Google Translation (opt-in key), Ollama (localhost), the tessdata download, the GUI's
  loopback HTTP server, the extension's language-data fetch.
- RELEASE_AND_DISTRIBUTION §2 "Contract gate": the repo's `/release` flow and `DEV/RELEASE.md` never read
  the registry.
- `REPO-LAYOUT` rule 3, research half: notes under `DEV/research/` follow no declared scheme.

**Stamp.** `canon.version` `2026.09.24.1`, `coreDigest` `79ee3333..` (from `-PrintDigest`); a third
`SZA-SEC04` exemption for `internal/translator/translator_test.go`, whose made-up key-shaped fixture
arrived the same morning and was the baseline's one error. `adoptedOn` stays `2026-08-18` as this skill
directs.

**Evidence.** Gate before `1 error(s), 1 warning(s)` (SZA-SEC04, SZA-CANON03), after **`0 error(s),
0 warning(s)`**, exit 0. Under Windows PowerShell 5.1 on the same tree: `7 error(s), 3 warning(s)`, exit 1,
all from BOM-less UTF-8 read in the ANSI code page. `check-contracts.ps1 -CatalogRoot P:\Contracts`:
`2 error(s), 1 warning(s)`, both errors pre-existing and another product's (`CTR-KEY` on `app-activation`
and `clipboard-guard`), none from this run's rows.

**Canon fixes suggested.**
1. `check-compliance.ps1`: check the host first and exit `2` ("could not verify") under Windows PowerShell
   5.1 - `#requires -Version 7` alone exits 1, which a caller reads as FAIL.
2. `adopt-canon` step 7: drop the version-count rung (or implement it in the gate) - the open
   `RULE-DELIVERY` rule 5 exception.
3. `adopt-canon` step 7: name the section-level duties a re-sync can surface (doc registry, posture
   inventories, counting boundary, contract gate), as CyrFlip suggested the same day.

## Canon duties 2026-09-25 - the four obligations of the re-sync, built

Run from `P:\WINDOWS\EPUB_2_HTML` against plugin `2026.924.1` (digest unchanged, `79ee3333..`), for the
repo's ticket 31 (`canon-resync-new-duties`), on the owner's instruction to implement it - build now, all
four items.

**Built.**
- DOCUMENTATION_CONCEPT §6: `docs/DOCUMENT_REGISTRY.jsonl`, 39 records in the reference's record shape 1,
  built from the tree as it is. `scripts/doc-registry.ps1` runs in the repo's gate (`scripts/check.ps1`):
  items 1-5 both ways over every `.md` and `.html` git would commit, plus the site half - every `.html` Pages
  serves is announced by its own `<link rel="canonical">` or excluded with a reason, every announced page
  carries the §3 SEO block, and `sitemap.xml` equals its render (`-Generate`; the first render was
  byte-identical to the hand-kept file). `scripts/doc-query.ps1` answers the two facets. Item 8 is a
  once-per-release step in the release checklist.
- SECURITY_AND_PRIVACY §7: `docs/security-posture.json`, 13 permission rows (six extension declarations,
  MSIX `runFullTrust`, six app capability rows under item 8) and 9 network surfaces; the three privacy
  texts, the extension's permission justifications and the MSIX runFullTrust justification are marked blocks
  rendered from the rows. `scripts/security-posture.ps1` runs in the gate (item 6): declarations both ways,
  consumer and shown-string citations, reverse coverage of network call sites, the telemetry claim against
  `go.sum` and `package-lock.json`, every render. First reconciliation fixed five divergences, among them
  two declared extension permissions no privacy text named and store justifications citing menu labels the
  extension does not show.
- RELEASE_AND_DISTRIBUTION §2 "Contract gate" / CONTRACTS §6: `scripts/contract-gate.ps1`, run by
  `scripts/release.ps1` before the tag step; FAIL and UNVERIFIED block, and the checklist now exits 1 while
  blocked. First live run: WARN, five rows owned by other open tickets.
- `REPO-LAYOUT` rule 3, research half: `RESEARCH_<topic-slug>_<YYYY-MM-DD>.md`, declared in `CLAUDE.md`,
  enforced by `tests/research_naming_test.go`; the catalog exception row narrowed to the ticket half.

**Deviations of this repo from the text** - recorded so the sections are not read as a description of it:
- A page's address is its `<link rel="canonical">` plus its `hreflang` cluster, not a `permalink:` line:
  the site is static HTML without front matter. The canon harness's `validate.ps1` would therefore not
  accept this registry's page records; the repo's own check does.
- A glob in a record may match nothing (the `RESEARCH_` pattern before its first note); an explicit path
  must exist, and each record must resolve at least one file. The reference requires every pattern to match.
- The two inventories are one JSON source with a generated Markdown render (`docs/SECURITY_POSTURE.md`),
  not an authored document: the public texts are marked blocks rendered from it, so item 5 is held by
  construction rather than by a wording comparison.
- The contract gate lives in a `release` placement class the repo added, not in the gate: its input, the
  catalog, exists only on the owner's machine, and a clone reports UNVERIFIED.

**Stamp.** Two keys added beside the ledger shape, additive under `REPO-STAMP` rule 7:
`docRegistryShape: 1`, `docRegistryFile: docs/DOCUMENT_REGISTRY.jsonl`. A fourth `SZA-SEC04` exemption, for
the archived ticket 22 that quotes the translator test's fixture key in the frozen archive.

**Evidence.** Compliance before `1 error(s), 1 warning(s)` (SZA-SEC04 on the archived ticket 22,
SZA-CTR01), after `0 error(s), 1 warning(s)` (SZA-CTR01, the repo's ticket 23), exit 0. In the repo's gate:
`doc-registry: PASS (39 record(s), 204 document file(s) covered, 18 page(s) announced)`,
`security-posture: PASS (13 permission row(s), 9 network surface(s), 7 declaration(s), 57 dependencies,
9 render(s))`, and the Go `tests` package ok with the new tests driving all three scripts to every outcome.
The gate's aggregate was FAIL on test, lint and typos from files this run did not touch.

**Canon fixes suggested.**
1. `templates/.sza-canon.json` and `check-compliance.ps1`: §6 item 5 asks for the record-shape number in
   the stamp, but the template has no key and the gate reads none. This repo used `docRegistryShape` /
   `docRegistryFile`, after `ledgerShape` / `ledgerFile`; name it in the template and check it.
2. `tools/harness/document_registry/validate.ps1`: accept `<link rel="canonical">` as a page's declared
   address - "a permalink or the equivalent" in §6 item 6 - so a static-HTML site can use the harness.
3. SECURITY_AND_PRIVACY §7 item 6: name the store forms' 1000-character justification limit as part of the
   consistency check; it is the cheapest failure to catch and the one a paste hides.

## Release-integrity wave 2026-09-26 (tickets 34-37, 5767e29)

The pre-release audit of ticket 34 (22 slices, 138 findings, 6 high, closed 2026-09-26) found its highs in the
**release path**, which the earlier audit of 2026-09-24 had left out entirely. They were fixed in `5767e29`
and `d11adae`:

- **Gate evidence binds to the tested tree.** Before: `check.ps1 -Plan <one child>` wrote release-grade
  evidence, so a lint-only run unlocked the tag line (R1, high); the tree was hashed after the children, so an
  edit made while the gate ran was recorded as tested (R3); the documented `build-local` flow rewrote tracked
  `build/*.exe` after the check, so evidence could never match HEAD and the BLOCKED hint looped, an invitation
  to bypass (R2); `contract-gate.ps1` printed PASS after checking zero contracts (R12). Now evidence records the
  plan and every child's verdict, `release.ps1` derives the "full plan" from the placement file and not from
  the evidence's own claim, the tree is hashed before the first child and after the last and a mismatch voids
  it (COULD NOT VERIFY), `build-local` builds first, then gates, then commits, and a gate that checked nothing
  exits 2. Tests: `TestGateEvidenceBindsTheRelease`, `TestContractGateOutcomes`.
- **`release.yml` builds only the tag it names** (ticket 37, R18-R25). Before: a `workflow_dispatch` with a
  free-text tag checked out the branch it started from and the release action created the tag if missing, so
  "re-run for vX" after `main` moved shipped `main` as vX and winget then pinned that zip's hash. Now the tag
  is resolved and its shape and date validated before checkout, `ref: refs/tags/<tag>` is checked out and a
  step stops unless HEAD is the tag's commit and the tree is clean, a dispatch runs from `main` only, actions
  are pinned by 40-hex commit with the version in a trailing comment, `contents: write` is granted on the
  publishing job only, dispatch input reaches scripts through `env:`, and the local installer and MSIX builds
  take `-Tag` and refuse a dirty tree or HEAD different from the tag. Release notes are ranged with
  `--match 'v*'` because `git describe` also matched the `ext-cws-` and `ext-edge-` tags and dropped commits.
  Verified with actionlint on the three workflows (exit 0).

**Candidates raised for the canon from this wave - proposed 2026-10-02, not applied:**

- *CI safety levers (provenance)* - landing in [RELEASE_AND_DISTRIBUTION](../RELEASE_AND_DISTRIBUTION.md) §1
  beside "CI cost & safety levers", one line each in [`skills/release/SKILL.md`](../../skills/release/SKILL.md)
  Phase 5 and the `store-publish` GitHub leg; mechanical checks `SZA-CI01` (a workflow with `contents: write`
  or a secret whose `uses:` ref is not a 40-hex commit, warn only, first-party `actions/*` an owner decision)
  and `SZA-CI02` (a publishing `workflow_dispatch` with no `refs/tags/` checkout) are **needs verification
  against the real repos** before shipping. Portfolio grep on 2026-10-02: moving-tag `uses:` still present in
  FastMediaSorter_Lite (8), Streams_Player (9, one pinned) and FastMediaSorter_mob_v2 (56 across 6 workflows);
  CyrFlip and FileDO are already pinned. A raw `${{ inputs.* }}` in a `run:` is **not** a repo-wide problem
  (Lite, Streams and FileDO already route it through `env:`). `store-publish` leg 3 ("never invoke
  `build-msix.ps1` bare, pass all three identity values") should be reconciled with this repo's safer shape,
  where the defaults are the frozen anchors and a bare unsigned build is refused unless `-Tag`.
- *Release evidence names the plan and the tree it judged* - landing in
  [RELEASE_AND_DISTRIBUTION](../RELEASE_AND_DISTRIBUTION.md) §2 (after "The absence of a verdict is not a
  pass"), a clause in [INVARIANTS](../INVARIANTS.md) item 5 ("naming the version **and tree** it judged") and a
  corollary in [DEVELOPMENT](../DEVELOPMENT.md) §15 ("order the work so the gate reads what the commit
  holds"), with the catalog first: `BUILD-EVIDENCE` rule 8, additive, 0.10. The catalog's 0.9 has subject banner,
  artifact version, no-retry and regenerate-and-compare, but nothing on binding the gate to the tree or on
  subset runs.

## Release 26.0930.1107 2026-09-30

Tag `v26.0930.1107` on `48cc355`, plus `ext-cws-v26.0930` and `ext-edge-v26.0930`. Per-channel state is kept in
`DEV/RELEASE_STATE.md` (`scripts/release-state.ps1`, `a rs`):

| Channel | State on 2026-09-30 | Note |
| --- | --- | --- |
| GitHub | live | run 36699011635, 8 assets, exe stamp verified |
| winget | submitted | PR #444113; 15 manifest files re-stamped and install-tested; the SHA taken from the release `.sha256`; previous PR #433869 merged |
| Microsoft Store | pending | unsigned MSIX built from the tag; the listing CSV release notes not refreshed yet |
| Chrome | submitted | `PENDING_REVIEW`; the previous revision stays published |
| Edge | submitted | the first run failed HTTP 401 on an expired `EDGE_API_KEY`; rerun after storing a new key (the Edge API key lasts about 72 days, `extension/PUBLISHING.md`) |

The release was cut from the ticket-70 audit commit, which included the RTF depth cap, the linear XHTML rewrite,
the winget-alias symlink fix and the report-redaction fix. **Candidates raised - proposed 2026-10-02:** durable
per-channel publish state with the vocabulary pending / submitted / live / blocked / n/a ("submitted" is not
"live"), and a credential-lifetime column with rotation dates checked in the release preflight, landing in
[RELEASE_AND_DISTRIBUTION](../RELEASE_AND_DISTRIBUTION.md) §6, `skills/release` Phase 8 and the Chrome/Edge
paragraph of [CHANNEL_MATRIX](../CHANNEL_MATRIX.md); the grep for "state file / PENDING_REVIEW / expire / rotate"
in rules and skills found nothing relevant.

## Final pre-release audit 2026-09-30 (ticket 70)

24 slices, 272 class-A files, 51 058 lines, **54 findings** (15 medium, 39 low), tickets 79-89, four days after
ticket 34 and on the code its fixes had rewritten: a regression of R5 (the typo gate red again), a
release-blocking test failure (ticket 89, `TestResearchNoteNaming`, a research note without the `RESEARCH_`
prefix cited in the catalog, fixed catalog-first with a backup because `P:\Contracts` is not under git), the
symlinked-alias OCR-data miss (ticket 83) and the unredacted user name (ticket 84). `audit-slices -Summary` PASS
with 135 of 135 re-checks. The stated rationale in ticket 34: "code written to close a finding has not itself
been read by anyone but its author" (about 13 100 Go lines added against a 22 700-line base).

**Caveat recorded:** the tree read was `8cc1bcb` plus uncommitted work, so slices touched afterwards must be
re-read before the next tag.

**Candidate raised - proposed 2026-10-02:** a sliced whole-repo audit with script-proven coverage (every
in-scope file in exactly one slice, every earlier finding id re-checked, class A = shipped code **and** the
release path), landing with the FastMediaSorter S3556 method in `skills/spec-to-audit/references/audit-campaign.md`
and a pointer in [DEVELOPMENT](../DEVELOPMENT.md) §11. This repo's `scripts/audit-slices.ps1` is 800 lines and
tied to its layout; promoting it needs a repo config for the class-A globs and the parity map.

## Contract pointers 2026-10-02 - SZA-CTR01 on three files

`check-compliance.ps1 -RepoRoot P:/WINDOWS/EPUB_2_HTML` reported three SZA-CTR01 warnings, on
`docs/contracts/APP-BEHAVIOUR.md`, `OCR-OVERLAY.md` and `OCR-PIPELINE.md` (43 to 47 lines each, against 37 or
fewer for the other 24 pointers), beside the stale-digest warning.

- **Root cause: a canon bug, now FIXED in the canon tool on 2026-10-02.** The id test accepted only
  `id: X` and `| Id | X |`; all three files carry the id in the portfolio-common bold forms (`- **Id:**
  `OCR-OVERLAY`` here, 27 of 27 pointers), so the check fell back to the length test (more than 40 lines). The
  pattern in `tools/check-compliance.ps1` is now bold-tolerant and also accepts the bullet form and the plural
  `Ids`. Measured after the fix, 2026-10-02: this repo reports 0 errors and 1 warning (`SZA-CANON03`); the three
  CTR01 warnings are gone without a repo edit. The Fix text of the rule ("Move the contract into the catalog")
  was not re-read in this entry.
- **Mapping to the catalog, no version drift.**

| Local file | Contract id | Catalog home | Local | Catalog | Role here |
| --- | --- | --- | --- | --- | --- |
| `OCR-OVERLAY.md` | `OCR-OVERLAY` | `ocr-overlay/README.md` | 1.2 | 1.2, active, shared | reference implementation, producer and consumer |
| `OCR-PIPELINE.md` | `OCR-PIPELINE` | `ocr-overlay/ocr-pipeline.md` | 1.8 | 1.8, active, owner doc-html-translate | producer and owner |
| `APP-BEHAVIOUR.md` | `APP-BEHAVIOUR` | `desktop-app-ux/APP-BEHAVIOUR.md` | 0.10 draft | 0.10 draft, owner StreamsPlayer | consumer |

- **Content drift of form, not of numbers.** `OCR-PIPELINE.md` carries the whole amendment history 1.1-1.8 in
  its `Version:` bullet (about 22 lines), a copy of the catalog's Document log that already lags (the log has a
  2026-09-30 correction row for 1.6 the pointer does not mention). `OCR-OVERLAY.md` narrates closed exceptions
  that registry rows already hold; only the two open ones (rule 1 JPEG-only EXIF, rule 10 extension `eng`,
  until 2026-12-31) belong near the pointer. `APP-BEHAVIOUR.md` carries a rule-by-rule paragraph on how the GUI
  meets rules 1-12 (about 25 lines), which is conformance evidence and the part most likely to rot. Nothing
  contradicts the catalog; it is the repetition [CONTRACTS](../CONTRACTS.md) §3 names ("a pointer that grows a
  second page has become a copy"). Trimming is **optional** now that the check is fixed; if done, it is a
  `contract-sync` pass for this repo, not a canon change.

## Deviation 2026-10-02 - cloud-session branches

This repo is worked by parallel cloud sessions that push `claude/*` branches (`worktree-agent-*` merges of
2026-09-25 and 2026-09-26, 12 or more worktrees). `scripts/sync-main.ps1` (`eb68101`, four auto-commits in the
window) commits everything, merges every branch ahead of `main` (conflicts in the append-only `DEV/CHANGELOG.md`
keep both sides, any other conflict aborts), builds as a cheap gate and pushes `main` - which here also publishes
GitHub Pages.

No other repo has such a script or a merged `claude/*` branch since 2026-09-20 (checked). It does not fit the
canon's working stance of 2026-09-30 ([INVARIANTS](../INVARIANTS.md) "Working stance": the owner works alone, no
branches or merges) nor INVARIANT 18's "commit only when asked" in letter. It stays here as a **repo delta, not a
canon proposal**: the re-sync that moves the stamp past `2026.09.24.1` needs an owner decision on this, not a
mechanical bump, and must record the delta instead of adopting the sentence. The stamp is still `2026.09.24.1`
(`SZA-CANON03`, measured 2026-10-02); the only reading owed is [GITHUB_INTERACTION](../GITHUB_INTERACTION.md) §1
and that stance.

## Open canon suggestions carried 2026-10-02

Status of the 2026-09-25 suggestions, re-checked against the canon working tree on 2026-10-02:

1. **`check-compliance.ps1` should exit 2 under Windows PowerShell 5.1** - the host guard is now present in the
   working tree of `tools/check-compliance.ps1` (exit 2 with a message, `-PrintDigest` exempt) but was not yet in
   a commit at the time of reading, so it reaches this repo with the next deploy.
2. **The CTR01 regex** - fixed 2026-10-02, see above.
3. **The stamp lacks a documented `docRegistryShape` / `docRegistryFile` key** - still open: `templates/.sza-canon.json`
   and the compliance tool name neither (only `ledgerShape` is read). This repo declares both, additively under
   `REPO-STAMP` rule 7.

**Further candidates from the 2026-10-02 mining, proposed and not applied** (each verified by grepping `rules/`,
`skills/`, `tools/` and the catalog; evidence is in the commits and ticket files named):

- *Untrusted-input checklist for apps that open files from the internet* - `SECURITY_AND_PRIVACY` (a new "Untrusted
  input" section before the inventories) plus a pathological-input tier in [TESTING_AND_QA](../TESTING_AND_QA.md)
  §3. Classes closed by the 2026-09-24 audit and the second pass: book paths confined to the book's tree, an output
  path handed to the shell (`x&calc&.epub`, `01f4003`), archive list-before-unpack, a pixel budget before decode,
  size-scaled helper deadlines with process-tree kill, an unbounded RTF `{` nesting that kills the process with an
  uncatchable OOM (99 MB of `{` under a 100 MB cap, ticket 81), a quadratic XHTML rewrite (60 KB 0.8 s, 240 KB
  13.3 s, ticket 86), a `ToLower` offset that breaks on Turkish `İ` (ticket 87).
- *A loopback GUI server is a listening port that is on by default* - `SECURITY_AND_PRIVACY` §3 (a bullet after the
  listening-port rule) and a scope clause on INVARIANT 11 (owner's call on wording). Ticket 03, `da78d1b`: any page
  the user visited could drive the GUI's API before the Origin, Host and token checks; the catalog already holds
  `PROPOSAL-2026-09-29-block-server-loopback.md` and a FileDO dated exception on `APP-BEHAVIOUR` rule 4.
- *Output-folder protocol* - [TESTING_AND_QA](../TESTING_AND_QA.md) §6 and [DEVELOPMENT](../DEVELOPMENT.md) §10:
  prove ownership with a token only the tool writes before deleting (ticket 05 deleted a user's folder holding one
  `a.jpg`; ticket 80 treated a saved DHT-22 page as ours), a foreign-looking folder skipped even under `-force`,
  reuse only against a completion record written last.
- *Diagnostic-report redaction covers every serialisation of the profile path* - catalog first
  (`DIAGNOSTIC-REPORT` rule 3, additive), then one clause in `SUPPORT_AND_FEEDBACK`. Ticket 84: the rule matched
  single backslashes, the settings JSON in the mailed archive held `\\`-escaped, forward-slash and `file:///`
  forms.
- *What the package holds is proven per channel; an ignore rule can drop an embedded binary* -
  [RELEASE_AND_DISTRIBUTION](../RELEASE_AND_DISTRIBUTION.md) §6 and `SECURITY_AND_PRIVACY` §6, with a possible
  `SZA-LAY0x` check (a path named in a `//go:embed` / `Include=` / installer `[Files]` source that
  `git check-ignore` reports ignored; false-positive rate **unverified**). Ticket 35: `pdftotext.exe` matched
  `*.exe` in `.gitignore`, so a clean-checkout CI build shipped the DLLs without the executable; ticket 38: "OCR -
  English bundled" in 13 winget locales while the winget zip, the MSIX and the CI zip carried no `eng.traineddata`.
- *winget mechanics on a 15-file locale set* - `skills/store-publish/references/winget.md` and the winget paragraph
  of [CHANNEL_MATRIX](../CHANNEL_MATRIX.md): re-stamp every manifest file before the local install test (else it
  verifies the previous release), keep the manifest folder flat, and resolve `os.Executable()` through the
  `WinGet\Links` symlink before looking for files beside the exe (ticket 83).
- *Windows build and runtime traps* - [DEVELOPMENT](../DEVELOPMENT.md) §16 and §10, `RELEASE_AND_DISTRIBUTION` §4:
  a tool another repo may also install is invoked by pinned version (FileDO pins `goversioninfo@v1.4.1`, this repo
  `@v1.7.0`, both against one shared `%USERPROFILE%\go\bin`), stage helper files under an ASCII-only root, derive a
  date-stamped version in UTC (R43), keep `./...` out of the gitignored `temp/` (R45), and a 386 toolchain's 2 GB
  address space turns a large test into a flaky OOM.
- *Promote the contract gate to a shared tool* - `tools/check-release-contracts.ps1` run by the `release` skill
  Phase 2, since the canon states the contract gate in prose and ships no script (this repo's
  `scripts/contract-gate.ps1`, 222 lines, is the only one in the portfolio). Medium effort: it assumes the
  `_meta/REGISTRY.md` column order.

**Seen, not worth a canon line:** permanent ticket ids under parallel sessions (two tickets numbered 51); a
once-per-release sitemap resubmission; the accessibility floor as measured gates (ticket 57), revisit if a second
product asks.
