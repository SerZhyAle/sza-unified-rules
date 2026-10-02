# Release & Distribution - the shipping runbook

The end-to-end path from "code is ready" to "users have it", abstracted across project types. Release
is the highest-stakes operation in the portfolio: it costs money, becomes public, or is irreversible.
This doc is the single runbook so no step is improvised. Reconciled against the portfolio; per-project
records in `contrib/`. Platform specifics are marked *(overlay)* - see
[PLATFORM_OVERLAYS.md](PLATFORM_OVERLAYS.md).

## 1. The build/release boundary (know which one you're doing)

Three distinct operations - never blur them:

- **Build** - local, free, publishes nothing, tags nothing. Do this freely.
- **Site publish** - a push that re-renders a live site (see [SITE_CONFIGURATION.md](SITE_CONFIGURATION.md)).
- **Release** - the single operation that stamps a version and ships a versioned artifact, and thereby
  triggers paid CI, becomes publicly visible, and/or cannot be undone. A `v*` tag push (desktop/CLI) or
  a Play/Store upload (Android). **Treat every release as one-way.** Documenting this boundary is what
  prevents an accidental paid or public run. For a **multi-edition** product the release **fans out** into
  several independent one-way ops - one per edition and per channel, each with its own trigger tag (`v*` for
  the app, `ext-<store>-v*` per extension store) and its own cadence; none blocks the others.

### CI cost & safety levers (paid-minutes discipline)

The boundary above is enforced cheaply with a handful of CI levers, worth carrying wherever paid runner
minutes matter (reference: `CyrFlip`):

- **`[skip ci]` on every local-build commit** - a build validated locally is pushed with `[skip ci]` in the
  message, which GitHub skips natively, so committing a build to `main` costs nothing. The build/release wall
  then need not be a script-capability boundary (the build script *cannot* tag): it can be a **commit-message +
  trigger contract** - the build script may push to `main` freely because `[skip ci]` keeps it free, and only
  the release script produces the billable `v*` tag. The price is the only clean-room run between releases,
  which the pre-flight must then supply (§2).
- **`paths-ignore` on the CI workflow** - doc/manifest/asset/extension-only changes (`**.md`, `docs/**`,
  `winget/**`, `assets/**`, the extension subtree) never burn a full build.
- **Skip the release anchor commit in CI** - the release flow makes a `release:`-prefixed anchor commit that the
  tag's release workflow already builds+tests; a CI `if:` that skips `release:` commits avoids double-billing.
  Keep the tag trigger off the branch workflow (listen to `main` only), so a `v*` tag fires *only* the release
  job.
- **`concurrency`** - `cancel-in-progress: true` on CI so a burst of commits costs one active run, not N;
  `cancel-in-progress: false` on the release workflow so different tags never cancel each other and a
  half-finished release is never aborted.

### CI safety levers (what the tag publishes is what was gated)

The cost levers keep a release cheap; these keep a one-way workflow honest (reference: `EPUB_2_HTML`, `FileDO`):

- **It builds only the tree of the tag it names.** The tag is resolved and validated for shape and date before
  checkout, the checkout is `refs/tags/<tag>`, and a step stops unless HEAD is the tag's commit and the tree is
  clean. A manual dispatch takes an existing tag, runs from `main` only, and never lets the release action
  create the tag - otherwise "re-run for vX" after `main` moved ships `main` as vX, and winget then pins that
  zip's hash. Local installer and package builds take the version from the tag and refuse a dirty tree.
- **A hand-pushed `v*` tag cannot bypass the gate.** CI refuses a tag whose commit carries no gate stamp (the
  gate's own version-stamped output, or the verdict file of §2) and re-runs the tests on the tagged source
  before it builds. A channel artifact built after the tag - a Store package, a resumed channel - is built
  only from sources equal to the tag, never from a `main` that moved on.
- **Least privilege.** The build job is read-only; `contents: write` belongs to a separate publish job that runs
  no project code. Pin third-party actions by commit with the version in a trailing comment, set
  `persist-credentials: false` on checkout, and pass the tag and dispatch inputs to scripts through `env:`,
  never into script text.
- **`/releases/latest` only moves forward.** Publish with `make_latest` only when the new stamp is newer than
  the current Latest, so a resumed or older tag cannot roll the durable download URL backward.

## 2. Pre-flight gate (nothing ships red)

Before the release operation, the pre-release verification must pass - see
[TESTING_AND_QA.md](TESTING_AND_QA.md): clean install, resources present, settings sane, the core
scenario works, performance acceptable, explicit PASS/FAIL verdict. A red pre-flight blocks the
release; do not "release anyway".

**The absence of a verdict is not a pass, and that is the way this gate actually fails.** "A red
blocks the ship" says nothing about a sweep that never ran, so a project can hold the rule perfectly
and ship unverified for months - no rule was broken, because nothing ever went red. Close it by
making the **one-way step itself refuse without a verdict artifact that names the version it
judged**: the artifact is the input to the ship, not a report filed next to it. Naming the version
matters as much as producing it, since a verdict from the previous release is exactly what a hurried
ship reaches for.

**Wire the gate into the command that ships, not into a command beside it.** The reference project
had the whole apparatus - a standard release gate producing a single PASS / FAIL / WAIVED verdict,
documented, working - owned by its *pre-release sweep* command while releases were cut by a separate
runbook that never mentioned it. Grep of the shipping runbook for the gate's own name: **zero
matches**. Skipping the sweep therefore skipped the gate **silently**, and two consecutive releases
went out across six flavors with no written verdict at all. Whenever a check and the irreversible act
it guards live in two different commands, the check is optional in practice however the docs read.

**Evidence names the plan that ran and the tree it judged** (`BUILD-EVIDENCE`, `CHECK-VERDICT`). A subset run
(one child of the plan, lint only) never unlocks the ship step - it derives the full plan from the project's
placement file, not from the evidence's own claim. The tree is hashed before the first check and after the
last, and an edit in between voids the evidence. A gate that checked nothing (zero contracts, zero tests
discovered) is COULD NOT VERIFY, never PASS. A flow that rewrites tracked files (a rebuilt exe, a generated
icon, an appended log) runs before the gate, so the evidence can match HEAD - otherwise it never does, and the
BLOCKED hint becomes an invitation to bypass.

**The pre-flight judges the commit, not the working tree.** The working tree is dirty by design and is not
what the tag ships: build and test a detached worktree of HEAD (or a fresh clone), and let verdict writers
refuse a dirty tree - a verdict about a dirty tree is a verdict about no commit.

**A gate that can only run on the owner's machine** (device smoke, real audio, hardware) travels to CI as a
file committed inside the tagged tree, `release-verdicts/<version>.json`, and the tag workflow refuses to
build without it (§1 safety levers). The writer refuses a dirty tree and writes nothing on red; the checker
requires the version to match the tag, the judged commit to be HEAD or an ancestor of the tag, and nothing
outside `release-verdicts/` to have changed since, so any later edit voids the verdict.

### Contract gate (the same shape, for what binds other products)

A release also carries the product's **shared contracts**, and they fail the same way a verdict does -
silently, because nothing went red. Before the one-way step ([CONTRACTS.md](CONTRACTS.md) §6):

- every contract this product produces or consumes has a **current registry row** in the catalog, with a
  verification date not older than the last release;
- the product ships against the **current version** where possible; behind is allowed with a dated reason
  in that row, absent is not. One MAJOR behind is a warning, two is a blocker for new work at that
  boundary;
- anything this release changes **at a contract boundary** is already in the catalog - the contract commit
  comes first, never after;
- the **conformance vectors ran in this product's own suite**, against the catalog's vectors at the
  version the registry names, and the run is cited like any other evidence.

## 3. Coverage-regression gate (the owner's hard rule)

**Never ship a release that shrinks market/reach.** Compare the candidate against the last shipped
build and STOP if any of these regress:

- Countries / regions available.
- Age rating (a stricter rating cuts audience).
- Minimum platform version (`minSdk`, min OS build) - raising it drops devices.
- ABI / architecture, `uses-feature`, device count, flavor reach *(overlay)*.

A coverage regression is a release-blocker, not a footnote. If a change forces one, it is an explicit
owner decision, made before the release, never discovered after.

## 4. Version & changelog cut

- **The scope of this cut** - which tickets this version claims - comes from the release package plan's
  ready block (§8) where the project keeps one, never from re-deriving it out of the ticket store.
- **Stamp the version mechanically** - never hand-bump (see [DOCUMENTATION_CONCEPT.md](DOCUMENTATION_CONCEPT.md)
  §2). Date tag `YY.M.D.HHmm` for desktop/CLI; monotonic `versionCode` + `versionName` for Android
  *(overlay)*. Remap to each channel's required shape mechanically.
- **A build-time date stamp is not the tag minute - pin the release build to the tag.** When the authoritative
  version is stamped from the clock at *build* time (`YY.M.D.HHmm` computed in the project file), it drifts
  minutes from the `v*` tag it ships under. The release CI must build with the version **pinned to the tag**
  (e.g. `-p:Version=<tag>`), so the version embedded in the binary matches the asset name and the tag exactly
  (reference: `CyrFlip`).
- **Read the version back out of the built artifact** (embedded file or product version, MSIX identity, APK
  `versionCode`) and compare it with the build you meant. A check that reads the source agrees with a stale
  artifact by construction - a stale watch package once reported an old version and downgraded the device it
  was installed on.
- **The version shape includes the clock it is read from.** Derive date stamps in UTC, or name the local clock
  and keep it: a CI (UTC) build and a local release near midnight otherwise produce non-monotonic versions a
  store rejects, and changing the clock midstream skews both order and reading. "Newer than every published
  version" is checked against every channel's list, including a stamp that shipped on one channel and never
  got a tag.
- **Gate the release trigger on a valid version.** When a `v*` tag drives the release, have the CI job
  reject a tag that is not a real version *before* it publishes - match the exact shape (e.g.
  `^v\d{2}\.\d{4}\.\d{4}$`) **and** parse it as a real date (`ParseExact 'yy.MMdd.HHmm'`), so a mistyped
  or impossible tag (`v26.1345.9999`) fails the job instead of cutting a bad release. This is the cheap
  mechanical guard that a one-way trigger is really the version you meant.
- **A published tag is never rebuilt.** The release workflow refuses to run for a tag whose Release already
  carries its asset, and the publish step never overwrites (`overwrite_files: false`): a ZIP rebuilt from the
  same tag has other bytes (archive tools stamp fresh file times), and the hash already merged into winget no
  longer matches. Re-dispatching a tag is safe only while nothing was published; after a failure that
  published nothing, cut a new, strictly newer stamp and leave the failed number retired.
- **Cut the CHANGELOG**: move `## [Unreleased]` into `## [<version>] - <YYYY-MM-DD>`, open a fresh empty
  `[Unreleased]`. That dated section *is* the release note, rendered verbatim into the release body and
  the site "What's new". The public showcase/features text is generated *from* the changelog diff since
  the last release, never hand-authored per change.
- **Nothing a release generates may be committed after the one-way step. Generate, commit, then
  tag.** Anything the release itself produces - listing text, store changelogs, release notes, a
  cleanup of markers the version retires - is part of the version, so it belongs in history *before*
  the act that freezes it. Put it after, and it becomes work with no deadline behind it: the ship has
  already happened, the operator has moved on, and nothing is red. Measured in the reference project:
  the commit the tag points at landed at **17:33**, the store changelogs at **17:45** - and that one
  late commit was carrying the orphaned listing text of **three earlier releases** nobody had
  noticed. Two structural amplifiers, both worth checking for by name. The cleanup ran **in a
  separate release worktree**, whose `git status` no one reads because the operator works in another
  one; and the runbook cut the **next development branch from the trunk before that cleanup**, so the
  two diverged by construction at every release and paid for it later in merge conflicts over commits
  that were byte-identical on both sides. **One named exception:** a manifest that embeds the SHA-256 of a
  published asset (winget `InstallerSha256`) cannot exist before the asset, so it is the one generated file
  that may follow the tag - a single scripted commit made right after the publish, verified against the
  published `.sha256` before the PR, with nothing else folded into it ([CHANNEL_MATRIX.md](CHANNEL_MATRIX.md)
  winget).
- **Back-merge what landed on the trunk between releases.** A commit that goes straight onto the trunk (a site
  publish, a post-tag showcase, a hotfix) is merged back into the development branch in the same session.
  Before merging dev into trunk run `git rev-list --count <dev>..<trunk>`; a non-zero count means back-merge
  first, because both sides regenerate the same render targets and the conflict surface is every generated
  file (533 conflicted paths in one measured release, 0 in the next).
- **A fix-release is where the ship-together rules break, so check them there first.** The hurry that
  justifies a fix-release is exactly the pressure that splits one surface set across two commits. In
  the reference project the English release notes and all three READMEs went in one commit and the
  other two locales followed **eight minutes later** - the "every surface and every authored locale in
  one edit" invariant broken not by disagreement but by haste. Evidence that the rule wants a gate on
  the release path rather than another paragraph.

## 5. Distribute per channel *(overlay)*

Push the one built artifact to every channel the project targets; the listing text is regenerated from
the sources of truth, not retyped. The per-channel facts (trigger, auth, who signs, listing source,
frozen anchor, verify step) are pinned in [CHANNEL_MATRIX.md](CHANNEL_MATRIX.md) - this section is the
order, that file is the reference. **Fan-out has three shapes:** a single op (one product, one channel); a
**flavor fan-out** (one codebase -> many build flavors -> several stores, e.g. an Android app to Play +
sideload + a VR store); and an **edition fan-out** (several independent codebases, each its own tags and
cadence). Match the coverage gate (§3) to the grain that fans out - per flavor for a flavor fan-out.

- **Windows desktop**: GitHub Release asset (`<App>-<version>-<platform>-setup.exe` / `.zip` + `.sha256`),
  winget-pkgs PR from `publishing/winget/`, Microsoft Store MSIX (Store re-signs).
- **Android**: Play AAB to the right track (internal -> closed -> production), staged rollout where
  appropriate, listing from the store fields; each store flavor to its own track/listing. A sideload-only
  flavor ships direct APK off the site/GitHub; a VR flavor ships to a VR store (Meta Horizon / Quest) - see
  the Sideload and VR-store rows in CHANNEL_MATRIX.
- **Go CLI / Wails**: GitHub Release only (portable binary/ZIP + `.sha256`, optional installer).
- **Browser extension** *(edition)*: Chrome Web Store and Edge Add-ons, submitted **independently** (own
  tag, own review, own item id), listing regenerated from `extension/store/`. May ship on its own cadence,
  not lockstepped to the app.

The authoritative published binary is the release-host asset - never committed into the repo.

**If the artifact bundles third-party binaries, its license notices ship inside every package** - the
release ZIP *and* the store package must carry `THIRD-PARTY-NOTICES.txt` (see
[SECURITY_AND_PRIVACY.md](SECURITY_AND_PRIVACY.md) §6). A bundled LGPL/GPL component can also make the
*combined* redistribution GPL even when your own code is MIT; the notices file is not optional packaging.

## 6. Post-release verification

A release is not "done" until proven live:

- The versioned asset is downloadable and its checksum matches.
- The listing / store page renders the new version and notes.
- Durable-URL CTAs on the site resolve (`/releases/latest`, package id, store page).
- **The update path works from a real prior install** - a frozen-anchor mistake (changed package id /
  identity / signing key) orphans existing users and only shows up here. Verify an update, not just a
  fresh install.
- **Every "includes X" sentence in a listing is true of each channel's built artifact**, and is checked against
  that package, not the source tree: the GitHub zip, the winget zip, the installer and the MSIX are different
  builds, and a bundled tool or data pack can be present in one and absent from another.
- **A fan-out keeps durable per-channel state** in a tracked file (default `RELEASE_STATE.md`), one row per
  channel, with the vocabulary `pending`, `submitted`, `live`, `blocked`, `n/a`. `submitted` is not `live` - a
  store that keeps the previous revision published while the new one is in review is `submitted`. Record every
  credential with a fixed lifetime beside it, with its rotation date, and check it in the pre-flight (§2): the
  Edge Add-ons API key lasts about 72 days, and an expired one first shows as HTTP 401 at the one-way step.
- Record the release: version, date, channels shipped, and the coverage-gate result.
- Where the project keeps a release package plan, ship the package now (§8) - the ready block moves into
  the history file and the package marker advances - **before** any archive or cleanup sweep runs.

## 7. Rollback & hotfix

- A shipped release is immutable - you don't edit it, you ship the next version. Keep the version shape
  monotonic so a hotfix always sorts above the bad build.
- For a store still in review, you may be able to halt/replace the submission; for a public GitHub tag,
  ship a superseding tag and mark the bad one.
- A post-release fix for a specific ticket goes through the project's fix-release path, not an ad-hoc
  patch to the published artifact.

## 8. The release package plan (what is left before we ship)

A ticket store knows every ticket's **status**. It never knows the owner's **intent**: which release
package a ticket belongs to, and in what order the remaining work should happen. Without that, "what is
left before we ship" has to be re-derived by hand every time, and the answer differs from session to
session. The release package plan is the one place that intent lives, and the owner is the one who
authors it.

This is **process hygiene, not an invariant** - breaking it costs planning clarity, not money, users, or a
one-way publish, so it is deliberately absent from the hard-invariants page. Worth carrying in any project
that keeps a ticket store and ships in packages: CLI tool, site, mobile app, Go service alike (reference
implementation: `FastMediaSorter_mob_v2`, see `contrib/fastmediasorter_mob_v2.md`).

### Two plain-text files, split by exactly one question

The split is "is there work left on this ticket?" and nothing else:

- **The work-remaining file** - the sorting surface. Every ticket whose status is below "done": in
  progress, drafted, approved, and everything **blocked** - by another ticket, by an open question, by an
  external party. Blocked work still has to be planned around, so it stays visible.
- **The ready file** - the package's finished content. Done, verified, **and awaiting-verification**.

That last inclusion is deliberate and is the point of the design. A verification step that keeps not
happening - a device check that is hard to reproduce, a sweep waiting on hardware the owner does not have
to hand - would otherwise sit among the remaining work forever and drown out the lines that actually need
a decision. Treat it as shipped. If it later proves broken it is reopened, and it rides a later package.

Recommended default names: `PLAN/RELEASE_QUEUE.md` (work remaining) and `PLAN/RELEASE_READY.md` (ready),
with `PLAN/RELEASE_QUEUE_DONE.md` as the shipped history. Any names work - pick them once and write them
into the repo's rules file.

### Line shape - fixed width, because a human reorders it by hand

One ticket per line, four columns, padded so the file stays readable and re-orderable in any plain editor:

```
<package>  <ticket>  <changed>  <status>
```

- **package** - a release package **number**, not a version. Tie it to the working branch so it needs no
  separate bookkeeping (branch `DEBUG-v030` -> package `30`). A **"not scheduled" bucket is required**;
  `--` is the recommended marker for it.
- **ticket** - whatever identifies a ticket in this project: a spec file name, a catalog id, an issue
  number.
- **changed** - the date the **status** last moved, not the date the ticket text was last edited. This is
  the column that exposes a line that has been sitting still.
- **status** - mirrored from the project's ticket store, never authored in this file.

Both files carry the same four columns, so a line moves between them unchanged. Filled in, with this
project's own ticket ids and status names:

```
# work remaining - the sorting surface, in the owner's execution order
30  S0930_wear_tile.md    2026-07-24  InProgress
30  S0928_rotate_fix.md   2026-07-22  BlockDependency
--  S0944_cloud_sync.md   2026-07-19  Draft

# ready - what package 30 already contains
30  S0912_export.md       2026-07-21  Implemented
30  S0925_thumbs.md       2026-07-23  BlockNeedUserTest
30  S0918_grid.md         2026-07-20  Verified
```

The history file keeps those same lines, grouped under a heading per shipped version, newest block on top -
so it reads as "what package 30 contained" long after package 30 is gone.

Plain text and fixed width are the requirement, not an aesthetic: the owner has to be able to drag lines
around in any editor, and a diff of the file has to read as a change of plan.

### Ownership, and this part is absolute

- The **ticket store** owns **status**.
- These two files own **package assignment** and **order**, and both of those belong to the human.

A machine **may**: add a line for a new ticket, refresh a line's status and date, move a line between the
two files when its ticket crosses the done boundary, drop a line whose ticket was archived or deleted.

A machine **may not**: reorder lines, or rewrite the package column. Ever. Line order is the owner's
recommended execution sequence - nothing enforces it, and nothing may rewrite it. An agent that helpfully
sorts the file has destroyed the only thing these files carry that the ticket store does not.

### A projection, not a second source of truth

Hook the reconcile into the **single write path** of the ticket store, so every command and skill that
changes a status updates the plan for free and no skill needs to know these files exist. If the project
has no single write path - if statuses get edited in several places - **create one first**. That is the
prerequisite, not an optional refactor: a plan maintained by a second, parallel mechanism is a second
source of truth and will disagree with the store within a week.

Two consequences of being a projection:

- **Movement across the boundary is bidirectional.** A ticket that falls back below done - failed
  verification, reopened bug - returns to the work-remaining file automatically and **keeps its package
  number**. It was scheduled for that package and still is, until the human says otherwise.
- **A done-status ticket present in neither file is never auto-added.** It shipped in an earlier package.
  This one rule is what keeps release history out of the plan; without it every reconcile drags the whole
  finished backlog back in.

### Shipping a package

One operator command, and the order inside it matters:

1. Move the ready file's block for the current package into the history file - **newest first**, stamped
   with the version that actually shipped.
2. Advance the current-package marker.
3. **Report** the unfinished lines still in the work-remaining file. They are never shipped and never
   auto-moved; re-sorting them into a later package is the human's decision, taken with the shipped
   release in hand.

**Ship the package before any archive or cleanup sweep** that flips tickets to an archived state. Run the
sweep first and it drops those lines as archived, taking the record of what shipped away with them. In
the runbook order that means: cut the version and the changelog, publish, verify, ship the package, and
only then let housekeeping run.

### Two checks

- A **drift check** (plan against ticket store) that the release runbook can call: every below-done
  ticket appears exactly once in the work-remaining file, every ready line's status is still in the
  done-set, no line names a ticket that no longer exists, no ticket sits in both files.
- An **on-demand reconcile**, for after a bulk edit or a hand fix, so the projection can be rebuilt
  without waiting for the next status write.

Neither is a release blocker. A red drift check means the plan is lying, so fix the plan before trusting
it as the scope list - it never stops the ship.

### Adopting it

Nothing here mandates an implementation language, a storage format, a ticket-id scheme, a branch-naming
scheme, or a file name; the recommended defaults above are defaults. The per-project decisions - the file
names, the single write path, the done-set (including the project's awaiting-verification status), how the
package number is derived, the operator commands, and whether the files are tracked or working artifacts -
are the checklist in the `adopt-canon` skill.

## 9. Applying to a new project

1. Write down the project's exact build/release boundary (§1) - what the release operation *is* here.
2. Wire the pre-flight gate (§2) to the project's test/sweep flow.
3. Codify the coverage-gate inputs (§3) for this platform.
4. Adopt the version + changelog cut (§4) and the per-channel distribute list (§5).
5. Script the post-release checks (§6), including an update-from-prior-install test.
6. Decide whether the project keeps a release package plan (§8); if it does, hook its reconcile into the
   ticket store's single write path before anything else.
