# Repository Layout - the universal core

The portable structure every project shares, independent of platform. It serves four goals: (1) one
obvious home for every kind of file, (2) a publication process that is identical *in shape* across
projects, (3) nothing secret or heavy ever committed by accident, (4) **git carries the project as a
*user* or a *forker* meets it** - the working developer's own material (the ticket workspace, the
engineering notes) stays local and ignored.

**The defaults are the names `FastMediaSorter_mob_v2` uses.** It is the repository where the practice is
earned and the others receive it ([PLATFORM_OVERLAYS.md](PLATFORM_OVERLAYS.md) "Overlay B"), so where this
page says *default* it means the folder that repository already has - and the one the shared harness already
reads (`PLAN/`, `temp/`, `dev/CHANGELOG.md`). A project keeps the *role* and may keep another *name* when
it already has one, and says so once in its agent-rules file so no reader has to guess. Anything
platform-specific (the source root, the release-mechanics folders, the version remap) is deferred to
[PLATFORM_OVERLAYS.md](PLATFORM_OVERLAYS.md); this file is only what holds for **all** project types.

## The role map

One row per kind of file. The **In git** column is the part to get right, and it is an audience split:
the rows marked **yes** are the project as a user or a forker receives it - the product, its source,
its published explanation - while the rows marked **no** are the working developer's own support and
are gitignored *by name*. A fresh clone - a user's download, a fork's starting point - must build and
understand the project without them.

| Role | Default | In git | What goes there |
| --- | --- | --- | --- |
| Product intro, licence | `README.md` (+ `README_<lang>.md`), `LICENSE` | yes | root, user-facing |
| Agent rules | `CLAUDE.md`, `AGENTS.md`, `GEMINI.md` | **no** | root on disk, gitignored in public repos (`REPO-LAYOUT` 0.12 rule 8); `check-compliance.ps1` reads them from disk ([AI_USAGE.md](AI_USAGE.md)). `canon-home` exempt; a product's own deliverable tree (`kit/`) stays tracked |
| Agent config & memory | `.claude/`, `.agents/`, `.codex/`, `.gemini/`, `memory/` | **no** | local agent skills, rules, settings and memory (`REPO-LAYOUT` 0.12 rule 8); `canon-home` and `internal` exempt |
| Portfolio & harness glue | `.sza-canon.json`, `.sza-profile.json`, `docs/contracts/`, `docs/DOCUMENT_REGISTRY.jsonl`, `docs/releases/`, `r0..rw.*`, `tools/harness.ps1` | **no** | local portfolio metadata, contract pointers, doc/release registries and queue launchers (`REPO-LAYOUT` 0.12 rule 8, `RELEASE-LEDGER` 0.3); read from disk by canon tools; `canon-home` and `internal` exempt |
| Launcher | `a.ps1` | yes | the one command a contributor runs - build, check, test, release; the toolchain's own wrapper (`gradlew`) sits beside it |
| Source and tests | the platform's source root(s) | yes | named by the [overlay](PLATFORM_OVERLAYS.md): `app_v2/` and `wear/` on Android, `src/` and `tests/` on desktop |
| Automation | `scripts/` | yes | everything that *drives* a build, check or release and is not tied to one channel; sub-folders by purpose, a script's own tests beside it (`guard.tests/`) |
| Engineering docs | `dev/` | **no** | developer-support documentation, local like `PLAN/`: process, the routing index, the ledger (`dev/CHANGELOG.md` for ledger shape `2`), dated research notes `<YY-MM-DD_HHm>_<slug>.md`, refuted approaches; `dev/archive/` is read-only |
| Maintained docs | `docs/` | yes | what a *user* or a *forker* reads - guides, public architecture/build docs, `docs/README.md`, `docs/CLI.md`, `docs/PARITY.md`, `docs/DOCS_MAP.md`, `docs/cli-commands*.json`, legal (`docs/privacy.html`); portfolio glue under `docs/` (`contracts/`, `DOCUMENT_REGISTRY.jsonl`, `releases/`) stays local |
| Site | the repo root, plus `documentation/` for a portal | yes | the published pages, as the stamp's `site.root` says ([SITE_CONFIGURATION.md](SITE_CONFIGURATION.md)) |
| Shared assets | `assets/` | yes | icons and images the product and its site ship |
| Channel sources | one folder per distribution channel, named after it, plus `store_assets/` | yes | the listing text, manifests and operator runbooks a channel is submitted *from*: `play/`, `meta/`, `fastlane/`, `fdroid/` on Android; `winget/`, `msix/`, `installer/` on desktop. `store_assets/` holds what several channels share - runbooks, screenshots, release waivers |
| Specs, tickets, roadmap, release queue | `PLAN/` | **no** | `PLAN/<id>_<slug>.md` per ticket and a `PLAN/<id>_<slug>/` folder for *that ticket's* research and evidence; the journal, the queue, `PLAN/archive/`. A local specification workspace the harness reads by name |
| Scratch | `temp/` | **no** | `temp/<ticket-id>/` for ticket-bound work, `temp/scratch/` for none; backups before editing a large file. Fixed infrastructure at the `temp/` root is *declared* by one inventory script, never listed in prose |
| Captured logs | `logs/` | **no** | runtime and device captures, crash dumps, evidence that belongs to no ticket |
| Built packages | toolchain output stays where the toolchain puts it (`build/`, `bin/`, `obj/`); packages collected for hand-off go to `DOWNLOADS/` | **no** | exe, msix, zip, apk, aab, `.sha256`, the build list |
| Secrets | `.secrets/` | **no** | keystores, `keystore.properties`, store API keys - see "Secrets" below |
| Bulky test data | `test_media/` | **no** | media and fixtures too large for the repo |

**Public-vs-local boundary enforcement (`REPO-LAYOUT` 0.12 rule 8).** In public repositories (`role` other than
`canon-home` and `internal`), `check-compliance.ps1` `SZA-LAY07` flags any Git-tracked file matching the **no**
rows above, while reading local agent rules, `.claude/rules/`, memory indexes and `docs/contracts/` directly from
disk. Existing public repos untrack violating files with `git rm --cached` plus `.gitignore` without rewriting
history; private/internal repos are exempt until published. Verify ignore coverage with `git check-ignore -v <path>`
and `git ls-files`.

**The specification workspace is local in every project.** Ignore the whole configured `paths.specsDir`,
its archive (`paths.specArchiveDir`, even when it is elsewhere), and any separate ticket journals, including
their contents and subfolders. This applies to existing workspaces as well as new ones; a local directory
named `PLAN/`, `tasks/`, `DEV/plan/` or `docs/specifications/` has the same role. Remove already tracked
workspace files from the Git index with `git rm --cached`, keeping their working copies; an ignore pattern
alone does not untrack them. Check both `git check-ignore --no-index` and `git ls-files` for the configured
paths. The existing Git history is not rewritten by this change. Keep any desired backup outside Git.

**Finished specifications move with their status.** The status tool moves a finished ticket's spec file and
its folder into the configured archive (`DONE/` or `archive/`) and back on reopening; configure that archive
as a directory distinct from the active one. The mechanics and the reconcile command are in
[SCHEMA.md](../tools/harness/spec_catalog/SCHEMA.md), "Where the spec file lives" (`TASK-FLOW` rules 17 and 70).

**Root stays minimal.** Only what a *user* or a *first-time contributor* expects at eye level is tracked at
root: the README(s), LICENSE, the launcher and the toolchain's own build files, the site's pages when the
repo hosts one, and public dot-files (`.gitignore`, `.gitattributes`). Local agent rules (`CLAUDE.md`,
`AGENTS.md`, `GEMINI.md`), `.sza-*` metadata and `r*.ps1` launchers live at root on disk and stay gitignored
in public repositories (`REPO-LAYOUT` 0.12 rule 8). Everything explanatory goes under `docs/`,
where a user or a forker reads it, or `dev/`, the developer's local workspace; everything automated
under `scripts/`, and **nothing generated lands at root** - an exe, a zip or a log at the root is a
build output or a capture in the wrong place.

## Documents - where a type goes and what it is called

**A document's folder follows its role; its name carries its type.** One filename *prefix* per type
(uppercase `SNAKE_CASE`, type first): `SPECIFICATION_`, `ROADMAP_`, `PROGRESS_`, `RESEARCH_`, `PLAN_`. A new
document takes the prefix of its type and lands in the folder its role names: a spec or a roadmap in
`PLAN/`, a research note beside the ticket it served (or, when it serves none, in `dev/`), a guide in
`docs/`. The prefix is what makes `grep`/glob and the index reliable; the folder can change without
renaming the file. Contract pointers are the one exception: a pointer lives in `docs/contracts/` and is
named after the contract id it points at (`STREAM-BANK.md`), because the id is what a reader looks it up
by. The older `CONTRACT_<ID>.md` spelling is still read.

> **Archive is frozen.** Files under `PLAN/archive/`, `dev/archive/` or a `done/` tree may predate this
> convention (mixed-case, suffix-instead-of-prefix, cross-linked by exact filename). They are historical
> records - leave them. Apply the convention to *new* docs only.

> **A declared spec-id scheme stands.** A project that names its own ticket scheme in its agent-rules file
> (`Sxxxx_<slug>`, `SP-XXXX`, `DEV/plan/NN_<date>_<slug>`) keeps it wherever those files live, and the
> type-prefix rule above is not applied to them.

> **A repository that already keeps its specs elsewhere** (`docs/specifications/`, `DEV/plan/`, `tasks/`)
> keeps them there and says so; the roles are unchanged - one home per document type, a dated or prefixed
> filename a glob can find. The ledger sits where the stamp's `ledgerShape` says, so it moves off the repo
> root only on shape `2` (see [DOCUMENTATION_CONCEPT.md](DOCUMENTATION_CONCEPT.md) §2 for the internal
> ledger plus curated notes). On shape `2` the dev-log rides in gitignored `dev/`, so the curated public
> notes are the only ledger rendering a clone or a fork ever receives.

> **`docs/guides/` is the mirror home, and nothing else.** Only a repository on the *mirror* consumption
> model ([README.md](README.md)) has it: the canon's copies, each stamped with the sync marker.

## `scripts/` - automation, not artifacts

Scripts that *drive* a build or release but are not tied to one distribution channel: the release
orchestrator, local CI mirrors, payload stagers, clean/test runners, the quality gates, download caches
(gitignored). A script references its siblings by the script-dir variable (`$PSScriptRoot`,
depth-independent) and repo-root files by a computed repo-root path - so scripts survive a folder reorg
without edits. Channel-specific scripts live *inside* the channel's folder instead (see the overlay).

`tools/` is the same role under the name most desktop repositories already use; it stays valid until the
repository migrates. This repository keeps `tools/` because that is the plugin's own layout.

## Secrets - never in the repo (universal)

No secret is ever committed. Design each channel so none is required in-repo.

| Secret | Where it lives | Why not in-repo |
| --- | --- | --- |
| Git host token (GitHub release/API) | the machine's `gh auth` cache / CI's injected token | ambient to the runner; scripts read it at call time |
| Code-signing cert / upload keystore | `.secrets/` (gitignored), or outside the working tree, or the store re-signs | per-publisher credential, not source |
| Store API credentials (a Play service-account key) | `.secrets/` | per-publisher credential, not source |
| Store/publisher identity (CN, package name) | script *defaults* + the store console | not a secret, but passed as a parameter, never hardcoded as a credential |
| App-level API keys (if any) | the user's machine via the OS secret store, at runtime | belongs to the end user, not the build |

`.secrets/` is a folder of the working tree that is **not** part of the repository: ignored by name, holding
nothing a fresh clone needs in order to build. A *template* with placeholder values
(`test_credentials.json.template`) is tracked beside it, so a new machine knows what to fill in.

If a project genuinely needs a build secret, it goes in the CI secrets store and is referenced by
name in the workflow - never written to a tracked file. `.gitignore` should pre-empt the common leaks
(`*.pfx`, `*.snk`, `*.jks`, `*.keystore`, `.env`, `*token*`, `*secret*`).

**A name-based glob also swallows legitimate files, silently** - neither `git add -A` nor a clean-tree check
says a word. After adding one, check the candidates with `git check-ignore -v <path>`, and make the
pre-flight list the files that are on disk, ignored and of a build-input kind. A build that passes only
because an ignored file exists locally proves nothing about the tagged checkout.

**`*token*` and `*secret*` do this to product source** - a design-token file, a secret store of the product itself
(`RoomSecretStore.kt`, `UiSizeTokens.kt`), seen in three repositories before the check below existed. The globs stay in
the list, because the leak they pre-empt is the expensive one; a product that owns a source file with either word in
its name adds a **narrow negation for that one file with a why-comment** (`!app/src/RoomSecretStore.kt`) under the
glob, never a wider glob or a dropped one. `check-compliance.ps1` names the file: `SZA-SEC05` (advisory) lists every
ignored file of a code kind that one of the two words hides, offline; a secret store kept ignored on purpose is a dated
`SZA-SEC05` exemption naming its path. The same listing is the fresh-clone check of the first public push:
`git ls-files --others --ignored --exclude-standard --directory`, read for source and test fixtures before the push
([google-play.md](../skills/store-publish/references/google-play.md) section 1).

## Built binaries & artifacts - retention policy (universal)

Binaries are **build output, not source** - the repo never stores a compiled release.

- **Local build output** (`bin/`, `obj/`, `build/`, `.gradle/`, the `DOWNLOADS/` collection folder, platform
  equivalents) is gitignored; it regenerates from a tag. **Caveat:** a case-folded build-output glob
  (`[Rr]elease/`) also matches a *source* dir literally named `release/` (e.g. a `/release` skill folder)
  and silently untracks it - negate it explicitly (`!.../release/` + `/**`) with a why-comment. Reference:
  `CyrFlip`.
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
- **A bundled third-party binary is tracked, pinned and verified.** Track it (every ignore-rule negation
  carries a why-comment - a bare `*.exe` rule with a re-include for its DLLs once shipped packages without
  the executable), pin it in a hash table, and have the release workflow verify every row of that table
  before it builds.
- **Version is a frozen-shape decision per platform** - see the overlay. The universal rule: the
  version is *derived mechanically*, not hand-bumped, and one authoritative form is stamped into the
  build and remapped where a channel demands a different shape. Keep the in-file stamp consistent with
  the release identifier.

## Applying this to a new project - checklist

1. Create the universal skeleton: the tracked root files (`README.md`, `LICENSE`), `scripts/`, `docs/`,
   the source root and tests, and a `.gitignore` that names every **no** row of the role map (agent rules,
   agent config/memory, portfolio/harness glue, `PLAN/`, `dev/`, `temp/`, `.secrets/`).
2. Add the channel folders and source root from your [platform overlay](PLATFORM_OVERLAYS.md).
3. Adopt the version + ledger flow (see DOCUMENTATION_CONCEPT §2).
4. Reserve the platform's **frozen anchors** (overlay) - unique per product.
5. Create the local support files/folders (`CLAUDE.md`, `.sza-canon.json`, `docs/contracts/`, `PLAN/`, `dev/`,
   `temp/`, `.secrets/`) locally and prove with `git check-ignore -v` and `check-compliance.ps1 -Only SZA-LAY07`
   that none is tracked in Git.
6. If site-hosted, set Pages to serve the right root and add the mandatory pages
   (DOCUMENTATION_CONCEPT §4).
