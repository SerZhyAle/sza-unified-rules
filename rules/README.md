# Unified Rules - one convention across every project

This folder is the **single canonical home** for the shared conventions that all of my projects
follow: repository layout, documentation, versioning, development discipline, testing, release &
distribution, localization, security & privacy, support, agent usage, site configuration, and the
author profile. Everything here is written to be true regardless of whether a project is an Android
app, a Windows desktop app, or a Go command-line tool.

Before this folder existed, the conventions lived only inside one product (`FastMediaSorter_Lite`) and
were phrased as "a Windows desktop app shipped through winget + Store". That made them impossible to
apply verbatim to an Android app or a Go tool. The fix is a two-layer split:

- **Universal core** - the rules that hold for *any* project shape. These are the bulk of the value
  and change rarely.
- **Platform overlays** - the concrete folder names, channels, and version shapes that differ by
  project type. A project reads the core, then exactly one overlay.

## The documents

**Do not read this folder front to back.** The rules ship as skills - load the one the task calls for
(`release`, `store-publish`, `feature-to-site`, `spec-to-audit`, `adopt-canon`) and it will send you to the
doc that owns a detail. These pages are the reference the skills render from.

**Always in context:** [INVARIANTS.md](INVARIANTS.md) - the twenty lines whose violation is expensive or
irreversible. In a repo that has adopted the canon they are injected at session start.

**Standing up a project:** [NEW_PROJECT_CHECKLIST.md](NEW_PROJECT_CHECKLIST.md) - the ordered front door
that sequences every doc below into one runbook.

**Structure & release** (universal core + the per-type shapes):

| File | Read it for |
| --- | --- |
| [REPOSITORY_LAYOUT.md](REPOSITORY_LAYOUT.md) | where every kind of file lives; secrets; binaries; versioning principle |
| [DOCUMENTATION_CONCEPT.md](DOCUMENTATION_CONCEPT.md) | single-source-of-truth model; changelog; discoverability; site pages; tone |
| [PLATFORM_OVERLAYS.md](PLATFORM_OVERLAYS.md) | the concrete shape for Android / Windows desktop / Go CLI, plus cross-project contracts |
| [RELEASE_AND_DISTRIBUTION.md](RELEASE_AND_DISTRIBUTION.md) | the shipping runbook: build/release boundary, coverage-regression gate, per-channel distribute, post-release checks |
| [CHANNEL_MATRIX.md](CHANNEL_MATRIX.md) | the per-channel publishing reference: trigger/cost/auth/signer/listing/anchor/verify for GitHub, winget, MS Store, Chrome, Edge, Play |
| [WINDOWS_PACKAGING.md](WINDOWS_PACKAGING.md) | the Windows delivery-shape decision guide: portable zip vs Inno vs WiX (+ MSIX), anchor set per shape, map of the packaging traps |

**Engineering & verification** (how the code gets built and proven):

| File | Read it for |
| --- | --- |
| [DEVELOPMENT.md](DEVELOPMENT.md) | the portable engineering discipline: layering, evidence rule, validation ladder, hygiene gates |
| [TESTING_AND_QA.md](TESTING_AND_QA.md) | evidence ladder, test tiers, device sweep, pre-release verdict, persona QA |
| [GITHUB_INTERACTION.md](GITHUB_INTERACTION.md) | git/gh rules: working-tree-is-truth, commit/PR conventions, release vs push, auth hygiene |

**Agent & people** (who does the work and for whom):

| File | Read it for |
| --- | --- |
| [AI_USAGE.md](AI_USAGE.md) | how an AI agent operates here: autonomy, evidence, cost, memory, skill routing |
| [AUTHOR.md](AUTHOR.md) | who you collaborate with - background, language, working style, product compass |

**Product surfaces** (what the user meets; take only what applies):

| File | Read it for |
| --- | --- |
| [LOCALIZATION.md](LOCALIZATION.md) | which surfaces translate, parity-enforced string workflow, shipped locales, text style |
| [SECURITY_AND_PRIVACY.md](SECURITY_AND_PRIVACY.md) | secrets, signing/identity anchors, minimal permissions, the privacy promise, store declarations |
| [SUPPORT_AND_FEEDBACK.md](SUPPORT_AND_FEEDBACK.md) | support path, diagnostic-log intake, feedback-to-ticket loop, answer-once-in-the-listing |
| [SITE_CONFIGURATION.md](SITE_CONFIGURATION.md) | hosting, custom domain, redirects, deploy flow (visual style lives in `kit/SZA-WEB-STYLE-GUIDE.md`) |

Read order for a new project: **NEW_PROJECT_CHECKLIST → AUTHOR → AI_USAGE → REPOSITORY_LAYOUT →
DOCUMENTATION_CONCEPT → DEVELOPMENT → TESTING_AND_QA → GITHUB_INTERACTION → RELEASE_AND_DISTRIBUTION →
CHANNEL_MATRIX → the one platform overlay → (as applicable) WINDOWS_PACKAGING / LOCALIZATION /
SECURITY_AND_PRIVACY / SUPPORT_AND_FEEDBACK / SITE_CONFIGURATION.**

> **Status: shipped as a plugin.** Extracted from the portfolio's most mature repo, reconciled against the
> active repos through 2026-07-27, then moved out of the site repository into its own home so it can be
> installed rather than pointed at. `contrib/` keeps the per-project records (overlay facts, channel rows,
> open project-specific questions) - read a project's record before working in that repo. Neighbouring kits
> these docs cross-reference and must not duplicate: the web style kit in the `sza.od.ua` repo, and the
> `universal-agent-kit` repo (a public, scrubbed AI-usage distillation).

## How a project consumes these rules

This folder is the **source of truth**; a project never re-authors the conventions.

- **Reference (strongly preferred).** The project's rules file points at the canon and keeps only its own
  deltas. Nothing to sync, so nothing can drift. Since the canon now travels with the session as a plugin,
  this works in CI and for outside contributors too - which removes the one argument that ever justified
  the alternative.
- **Mirror (only when the repo must be genuinely self-contained).** Copy the needed docs into the project's
  `docs/guides/` and stamp each copy with the sync marker below. A mirror is a *render target*, never
  edited in place - fixes land here first, then re-mirror.

```
<!-- Mirrored from Unified_Rules @ <canonVersion> digest:<first12> on <YYYY-MM-DD>. Edit the canonical copy, not this. -->
```

**A self-contained restatement is a fork, not a mirror.** A repo that duplicates these rules in its own
words - however deliberately - has forked them, and the copy will diverge silently. That is the failure this
whole arrangement exists to end.

Each adopting repo records what it adopted in a `.sza-canon.json` stamp at its root. That stamp, not a table
in this folder, is the live map of adoption - `tools/check-compliance.ps1` reads it and reports staleness.

## Maintaining these rules

- **Gate before committing:** run `tools/check-rules.ps1` (exit 0 required) - it validates internal links,
  section numbering, `§`-references, and the house text style across these docs.
- **Bump `CANON_VERSION`** in the same commit as any rule-doc change. The digest changes anyway; the version
  is what lets an adopter tell a minor reconciliation from a hard re-adoption.
- **Adopting or re-syncing a repo:** run the `adopt-canon` skill in a session started in that repo, one repo
  per session. It replaces the old copy-paste spread-back prompt.
- **Surveying a new project:** copy `contrib/TEMPLATE.md`, fill it against the repo with evidence, dedupe
  against the existing records, and fold only owner-approved universal deltas into the core.

## Adopting on a new project

The ordered runbook now lives in its own doc: **[NEW_PROJECT_CHECKLIST.md](NEW_PROJECT_CHECKLIST.md)**.
It sequences the skeleton, the overlay, the version/changelog flow, the engineering and testing
discipline, the git/release conventions, the product surfaces, and the frozen-anchor reservation - each
step linking the doc that owns it. Start there rather than re-deriving the steps here.

## House style

- The house text style (`..` never `...`; plain hyphen `-`; Russian `ё`; prose + UI only, never code)
  has one home: [DOCUMENTATION_CONCEPT.md](DOCUMENTATION_CONCEPT.md) §5.
- English for canonical technical ledgers (CHANGELOG, contracts); localize user-facing surfaces
  ([LOCALIZATION.md](LOCALIZATION.md)).

## Glossary - shared vocabulary

One name per concept, so every project and every agent means the same thing:

- **Source of truth** - the one authoritative home for a fact; everything else renders from it.
- **Render target / mirror** - a copy generated from a source of truth (a store listing from the
  CHANGELOG, a `docs/guides/` copy of these rules). Never hand-edited in place; regenerated.
- **Reference vs mirror** - *reference* links to the canonical doc (no drift); *mirror* copies it with a
  sync stamp (self-contained, must be re-synced).
- **Universal core vs platform overlay** - core rules hold for any project; the overlay is the concrete
  names/channels/version shape for one project type (Android / Windows desktop / Go CLI / browser extension).
- **Edition** - one product shipped from more than one independent codebase, kept behaviourally in
  sync (in-repo: parity doc; cross-repo: wire contract). Distinct from a *flavor* (one codebase,
  build-time variants). See PLATFORM_OVERLAYS "Editions".
- **Co-shipping shapes** - several artifacts of *one* product in *one* release on *one* trigger: a
  *flavor*, a *dual-runtime build variant* (one source tree, two toolchains, parity by compile-time
  seams), or a *co-shipped companion binary*. See PLATFORM_OVERLAYS "Co-shipping shapes".
- **Companion editor extension** - a thin, in-repo, code-independent helper published to an editor
  marketplace on its own version clock, coupled to the app by a one-way on-disk file contract. See
  PLATFORM_OVERLAYS "Companion editor / IDE extension".
- **Frozen anchor** - an identifier that ties an *update* to an *install* (package id, app identity,
  signing key, module path). Reserve once; changing it orphans every installed copy.
- **Build vs release** - a *build* is local and free and ships nothing; a *release* is the one-way
  operation that stamps a version and publishes, and may cost money or become public.
- **Coverage / reach** - the market surface of a build: countries, age rating, minimum platform
  version, ABI/feature/device set. A release must never shrink it.
- **Overlay fact** - one of the four per-type specifics: source root & release-mechanics folder, version
  shape, channels + listing files, frozen anchors.
- **Contribution (`contrib/`)** - a per-project delta file recording that project's overlay facts and
  divergences; reconciled into the core on 2026-07-23 and kept as the per-project record.
- **Product compass / persona** - the non-technical target users (the grandmother, the gym-goer) whose
  happy-path defines what counts as a defect.
