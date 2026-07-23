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
