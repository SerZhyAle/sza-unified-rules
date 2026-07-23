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

**Start here:** [NEW_PROJECT_CHECKLIST.md](NEW_PROJECT_CHECKLIST.md) - the ordered front door that
sequences every doc below into one runbook for standing up a project.

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

> **Status: reconciled.** Extracted from the portfolio's most mature repo, then reconciled against
> six active repos on 2026-07-23; every universal delta is folded into these docs. `contrib/` keeps
> the per-project records (overlay facts, channel rows, open project-specific questions) - read a
> project's contrib file before working in that repo. Neighbouring kits these docs cross-reference and
> must not duplicate: `kit/SZA-WEB-STYLE-GUIDE.md` (web visual/content), the `universal-agent-kit`
> repo (fuller AI-usage distillation).

## How a project consumes these rules

This folder is the **source of truth**; a project never re-authors the conventions, it references or
mirrors them.

- **Reference (preferred).** A project's own `docs/` links here (`../../Unified_Rules/REPOSITORY_LAYOUT.md`
  or the published URL) and keeps only its *project-specific* decisions locally. Nothing to keep in
  sync; the rules can't drift.
- **Mirror (when the repo must be self-contained).** Copy the relevant files into the project's
  `docs/guides/` and stamp each copy's top with the sync marker below. A mirror is a *render target*,
  never edited in place - fixes land here first, then re-mirror.

```
<!-- Mirrored from Unified_Rules @ <git-short-sha> on <YYYY-MM-DD>. Edit the canonical copy, not this. -->
```

Existing per-project copies (e.g. `FastMediaSorter_Lite/docs/guides/REPOSITORY_LAYOUT.md`) are
downstream mirrors from now on - treat them as stale until re-synced from here.

## Maintaining these rules

- **Gate before committing:** run `tools/check-rules.ps1` (exit 0 required) - it validates internal
  links, section numbering, `§`-references, and the house text style across the core docs.
- **Spreading into a repo:** run the prompt from [SPREAD_BACK_PROMPT.md](SPREAD_BACK_PROMPT.md) in a
  session started in that repo (one repo per session); mark its Done column there after the commit.
- **Surveying a new project:** copy `contrib/TEMPLATE.md`, fill it against the repo with evidence,
  dedupe against the existing contrib files, and fold only owner-approved universal deltas into the
  core.

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
