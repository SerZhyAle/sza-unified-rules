# Repository Layout - the universal core

The portable structure every project shares, independent of platform. It serves three goals: (1) one
obvious home for every kind of file, (2) a publication process that is identical *in shape* across
projects, (3) nothing secret or heavy ever committed by accident.

Read this as the *target shape*: adapt the names, keep the roles. Anything platform-specific (the
release-mechanics folder, the source root, the version remap) is deferred to
[PLATFORM_OVERLAYS.md](PLATFORM_OVERLAYS.md) - this file is only what holds for **all** project types.

## Top-level shape (universal)

```
<repo>/
  README.md  README_<lang>.md   product intro, per language (root - user-facing)
  CHANGELOG.md                   "What's new", Keep-a-Changelog style (root - user-facing)
  LICENSE
  <agent-instructions>           operating instructions for agents/contributors (CLAUDE.md / AGENTS.md)
  <build entry point(s)>         the one command a contributor runs to build (a.ps1 / build.ps1 / gradlew)
  <source root>                  platform-specific name - see overlay (src/ · app_v2/ · cmd/+internal/)
  tests/                         test projects/suites
  assets/                        shipped/icon/site assets
  <release-mechanics>            platform-specific - see overlay (publishing/ · none, gradle-driven · build.ps1)
  tools/                         build & release automation not tied to one channel
  docs/                          all internal documentation (taxonomy below)
```

**Root stays minimal.** Only what a *user* or a *first-time contributor* expects at eye level lives at
root: the READMEs, CHANGELOG, LICENSE, agent instructions, the build entry script(s), and (for
site-hosting repos) the landing page. Everything explanatory goes under `docs/`; everything
release-mechanical under the platform's release folder and `tools/`.

## `docs/` - documentation taxonomy (universal)

One folder per document *lifecycle stage*, one filename **prefix** per document *type*. The prefix is
the contract; the folder is where it currently sits.

```
docs/
  README.md            index of this tree (start here)
  guides/              living operational docs - read while doing the task
                       (BUILD_AND_RELEASE, TESTING, and mirrors of the Unified Rules if mirroring)
  specifications/      SPECIFICATION_*.md still being built
  specifications/done/ SPECIFICATION_*.md that shipped (archive - do not churn)
  roadmaps/            ROADMAP_*.md
  contracts/           CONTRACT_*.md - frozen wire/interface contracts shared with other products
  assets/  images/     doc/site images
  dev-notes/           throwaway diagnostics, captures, scratch (not authoritative)
```

**Filename prefixes** (uppercase `SNAKE_CASE`, type first): `SPECIFICATION_`, `ROADMAP_`, `CONTRACT_`,
`PROGRESS_`, `RESEARCH_`, `PLAN_`. A new doc takes the prefix of its type and lands in the matching
folder. The prefix is what makes `grep`/glob and the index reliable; the folder can change without
renaming the file.

> **Archive is frozen.** Files under `specifications/done/` may predate this convention (mixed-case,
> suffix-instead-of-prefix, cross-linked by exact filename). They are historical records - leave them.
> Apply the convention to *new* docs only.

> **Platforms with their own spec system keep it.** An Android project drives specs through its
> `PLAN/Sxxxx_*.md` catalog rather than `docs/specifications/`. That is the Android overlay's spec
> home; the taxonomy above still governs `guides/`, `roadmaps/`, and `contracts/`. Don't duplicate.

> **A `DEV/` umbrella is an accepted variant.** Some repos keep the *internal* working docs under a single
> `DEV/` tree (`DEV/CHANGELOG.md` as the engineering ledger, `DEV/plan/<YYYY-MM-DD>_<slug>.md` for tickets
> with `DEV/plan/ROADMAP.md` as the queue and `DEV/plan/done/` as the archive), reserving `docs/` for
> public/cross-edition material (`PARITY.md`, a spec-lifecycle doc). The *roles* are unchanged - one home
> per doc type, a dated/prefixed filename a glob can find - only the top folder differs. Note this also
> moves the CHANGELOG off repo root; see DOCUMENTATION_CONCEPT §2 for the internal-ledger + curated-notes
> split that goes with it.

## `tools/` - automation, not artifacts

Scripts that *drive* a build or release but are not tied to one distribution channel: the release
orchestrator, local CI mirrors, payload stagers, clean/test runners, download caches (gitignored). A
tools script references its siblings by the script-dir variable (`$PSScriptRoot`, depth-independent)
and repo-root files by a computed repo-root path - so `tools/` scripts survive a release-folder reorg
without edits. Channel-specific scripts live *inside* the release-mechanics folder instead (see
overlay).

## Secrets - never in the repo (universal)

No secret is ever committed. Design each channel so none is required in-repo.

| Secret | Where it lives | Why not in-repo |
| --- | --- | --- |
| Git host token (GitHub release/API) | the machine's `gh auth` cache / CI's injected token | ambient to the runner; scripts read it at call time |
| Code-signing cert / upload keystore | OS/keystore outside the repo, or the store re-signs | per-publisher credential, not source |
| Store/publisher identity (CN, package name) | script *defaults* + the store console | not a secret, but passed as a parameter, never hardcoded as a credential |
| App-level API keys (if any) | the user's machine via the OS secret store, at runtime | belongs to the end user, not the build |

If a project genuinely needs a build secret, it goes in the CI secrets store and is referenced by
name in the workflow - never written to a tracked file. `.gitignore` should pre-empt the common leaks
(`*.pfx`, `*.snk`, `*.jks`, `*.keystore`, `.env`, `*token*`, `*secret*`).

## Built binaries & artifacts - retention policy (universal)

Binaries are **build output, not source** - the repo never stores a compiled release.

- **Local build output** (`bin/`, `obj/`, `dist/`, `stage/`, `build/`, `.gradle/`, platform equivalents)
  is gitignored; it regenerates from a tag. **Caveat:** a case-folded build-output glob (`[Rr]elease/`) also
  matches a *source* dir literally named `release/` (e.g. a `/release` skill folder) and silently untracks it -
  negate it explicitly (`!.../release/` + `/**`) with a why-comment. Reference: `CyrFlip`.
- **The authoritative published binary is the release-host asset** (the GitHub Release asset, or the
  store's own hosted build), named from the version. The release *is* the artifact archive - versioned,
  immutable, downloadable. Don't duplicate it into the repo.
- **One vendored-binary exception**, if unavoidable (a prebuilt sidecar from another repo): keep it
  under a clearly gitignored `payload/` with a narrow allow-list for just the needed file, and document
  that a fresh clone lacks it until fetched. **Two variants, both valid - pick per project:** *gitignored*
  (no binary in history; a fresh clone lacks the feature until the sidecar is fetched) or *committed* (a
  narrow `.gitignore` negation - `!payload/<dir>/<file>` - tracks just that file so a fresh clone works out
  of the box, at the cost of a binary in history). Whichever you choose, `.gitignore` and the rules file
  must agree; a rules file that says "gitignored, clone lacks it" while the negation actually commits it is
  a drift to fix. (A repo may likewise deliberately track its *own* build output as a dev-distribution
  convenience under the same narrow-negation-with-a-why-comment rule; the authoritative release is still
  the release-host asset, never the committed copy.)
- **Version is a frozen-shape decision per platform** - see the overlay. The universal rule: the
  version is *derived mechanically*, not hand-bumped, and one authoritative form is stamped into the
  build and remapped where a channel demands a different shape. Keep the in-file stamp consistent with
  the release identifier.

## Applying this to a new project - checklist

1. Create the universal skeleton: root files, `docs/{guides,specifications,roadmaps,contracts}/`,
   `tests/`, `.gitignore`.
2. Add the release-mechanics folder and source root from your [platform overlay](PLATFORM_OVERLAYS.md).
3. Adopt the version + `CHANGELOG.md [Unreleased]` flow (see DOCUMENTATION_CONCEPT §2).
4. Reserve the platform's **frozen anchors** (overlay) - unique per product.
5. Point `.gitignore` at the platform's build-output dirs plus the secret globs above.
6. If site-hosted, set Pages to serve the right root and add the mandatory pages
   (DOCUMENTATION_CONCEPT §4).
