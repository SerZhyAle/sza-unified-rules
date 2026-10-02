# Repository Layout - the universal core

The portable structure every project shares, independent of platform. It serves three goals: (1) one
obvious home for every kind of file, (2) a publication process that is identical *in shape* across
projects, (3) nothing secret or heavy ever committed by accident.

**The defaults are the names `FastMediaSorter_mob_v2` uses.** It is the repository where the practice is
earned and the others receive it ([PLATFORM_OVERLAYS.md](PLATFORM_OVERLAYS.md) "Overlay B"), so where this
page says *default* it means the folder that repository already has - and the one the shared harness already
reads (`PLAN/`, `temp/`, `dev/CHANGELOG.md`). A project keeps the *role* and may keep another *name* when
it already has one, and says so once in its agent-rules file so no reader has to guess. Anything
platform-specific (the source root, the release-mechanics folders, the version remap) is deferred to
[PLATFORM_OVERLAYS.md](PLATFORM_OVERLAYS.md); this file is only what holds for **all** project types.

## The role map

One row per kind of file. The **In git** column is the part to get right: a fresh clone must build and
explain itself without the rows marked **no**, and each of those is gitignored *by name*.

| Role | Default | In git | What goes there |
| --- | --- | --- | --- |
| Product intro, licence | `README.md` (+ `README_<lang>.md`), `LICENSE` | yes | root, user-facing |
| Agent rules | `CLAUDE.md`, `AGENTS.md`, `GEMINI.md` | yes | root; the canon is a pointer, never a restatement ([AI_USAGE.md](AI_USAGE.md)) |
| Launcher | `a.ps1` | yes | the one command a contributor runs - build, check, test, release; the toolchain's own wrapper (`gradlew`) sits beside it |
| Source and tests | the platform's source root(s) | yes | named by the [overlay](PLATFORM_OVERLAYS.md): `app_v2/` and `wear/` on Android, `src/` and `tests/` on desktop |
| Automation | `scripts/` | yes | everything that *drives* a build, check or release and is not tied to one channel; sub-folders by purpose, a script's own tests beside it (`guard.tests/`) |
| Engineering docs | `dev/` | yes | how the project is worked: process, the routing index, the ledger (`dev/CHANGELOG.md` for ledger shape `2`), dated research notes `<YYYY-MM-DD>_<slug>.md`, refuted approaches; `dev/archive/` is read-only |
| Maintained docs | `docs/` | yes | what a contributor or a user reads: guides, the sources of public pages, legal, release docs. `docs/README.md` indexes the tree; where a repo keeps a document registry it is `docs/DOCUMENT_REGISTRY.jsonl`, naming each document's audience, owner, update trigger and whether it is published; `docs/contracts/` holds the contract pointers |
| Site | the repo root, plus `documentation/` for a portal | yes | the published pages, as the stamp's `site.root` says ([SITE_CONFIGURATION.md](SITE_CONFIGURATION.md)) |
| Shared assets | `assets/` | yes | icons and images the product and its site ship |
| Channel sources | one folder per distribution channel, named after it, plus `store_assets/` | yes | the listing text, manifests and operator runbooks a channel is submitted *from*: `play/`, `meta/`, `fastlane/`, `fdroid/` on Android; `winget/`, `msix/`, `installer/` on desktop. `store_assets/` holds what several channels share - runbooks, screenshots, release waivers |
| Specs, tickets, roadmap, release queue | `PLAN/` | **no** | `PLAN/<id>_<slug>.md` per ticket and a `PLAN/<id>_<slug>/` folder for *that ticket's* research and evidence; the journal, the queue, `PLAN/archive/`. A local specification workspace the harness reads by name |
| Scratch | `temp/` | **no** | `temp/<ticket-id>/` for ticket-bound work, `temp/scratch/` for none; backups before editing a large file. Fixed infrastructure at the `temp/` root is *declared* by one inventory script, never listed in prose |
| Captured logs | `logs/` | **no** | runtime and device captures, crash dumps, evidence that belongs to no ticket |
| Built packages | toolchain output stays where the toolchain puts it (`build/`, `bin/`, `obj/`); packages collected for hand-off go to `DOWNLOADS/` | **no** | exe, msix, zip, apk, aab, `.sha256`, the build list |
| Secrets | `.secrets/` | **no** | keystores, `keystore.properties`, store API keys - see "Secrets" below |
| Bulky test data | `test_media/` | **no** | media and fixtures too large for the repo |

`.claude/` and `.agents/` hold an agent's working configuration. Whether they are tracked is the
repository's choice and not a layout role.

Nothing checks the **In git** column yet; `git check-ignore -v <path>` is the proof, and it is the first
thing to run on a repository whose layout is in doubt.

**Root stays minimal.** Only what a *user* or a *first-time contributor* expects at eye level lives at
root: the README(s), LICENSE, the agent rules, the launcher and the toolchain's own build files, the
site's pages when the repo hosts one, and the dot-files. Everything explanatory goes under `docs/` or
`dev/`, everything automated under `scripts/`, and **nothing generated lands at root** - an exe, a zip or a
log at the root is a build output or a capture in the wrong place.

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
> ledger plus curated notes).

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

1. Create the universal skeleton: the root files, `scripts/`, `dev/`, `docs/` (with `docs/contracts/`),
   the source root and tests, and a `.gitignore` that names every **no** row of the role map.
2. Add the channel folders and source root from your [platform overlay](PLATFORM_OVERLAYS.md).
3. Adopt the version + ledger flow (see DOCUMENTATION_CONCEPT §2).
4. Reserve the platform's **frozen anchors** (overlay) - unique per product.
5. Create `PLAN/`, `temp/`, `.secrets/` locally and prove with `git check-ignore -v` that each is ignored.
6. If site-hosted, set Pages to serve the right root and add the mandatory pages
   (DOCUMENTATION_CONCEPT §4).
