---
name: release
description: Run a public RELEASE of an SZA product - the one-way, billable operation that stamps a version and publishes it to GitHub, winget, the Microsoft Store, Play, or a marketplace. Detects the repo's shape, channels and frozen anchors, writes "What's new" into every listing surface before tagging, then executes the single irreversible step and proves it landed. Use when the user asks to release, publish a version, cut a tag, or ship - including the Russian words "релиз", "зарелизь", "опубликуй версию", "выпусти версию". Do NOT use for a local build ("сборка", "собери", /build) - a build never tags and ships nothing.
---

# Release - the one-way operation

A **build** is local, free, and ships nothing. A **site publish** re-renders a page. A **release** stamps a
version and publishes it: it may spend paid CI minutes, it becomes publicly visible, and it burns a version
number that can never be reused. Never blur the three, and never run this skill "just to test" - that is the
repo's build flow.

**This is the only flow that creates a `v*` tag.**

Canon behind this skill: [RELEASE_AND_DISTRIBUTION.md](../../rules/RELEASE_AND_DISTRIBUTION.md) (the runbook),
[CHANNEL_MATRIX.md](../../rules/CHANNEL_MATRIX.md) (per-channel facts),
[PLATFORM_OVERLAYS.md](../../rules/PLATFORM_OVERLAYS.md) (project shapes),
[INVARIANTS.md](../../rules/INVARIANTS.md) (the lines that must not break).
Per-channel publishing detail lives in the **`store-publish`** skill - load it at Phase 7, not before.

The phase order below is non-negotiable. What varies per repo is only the *content* of each phase.

---

## DETECT - establish the facts before touching anything

Never invent a version shape, a tag format, a channel, or an anchor. Read them, in this order of authority
(**later wins on conflict, and report the conflict**):

1. **`.sza-canon.json`** at the repo root, if present - the per-repo stamp this canon defines. It carries the
   version shape and tag regex, the ledger shape, the channel set, and the site facts.
   See [adopt-canon](../adopt-canon/SKILL.md), which generates it.
2. **The repo's rules file** - `CLAUDE.md` and/or `AGENTS.md`. Some repos have only one; some have both with
   `AGENTS.md` authoritative. Read the publishing-boundary and autonomy sections.
3. **The contrib record** - `rules/contrib/<project>.md` in this plugin. Its "Overlay facts" and
   "Channel-matrix rows" sections carry the version shape, channels, listing files and literal anchors.
   Rich, but a copy that can lag.
4. **The repo's release doc** - `RELEASE.md`, `docs/guides/BUILD_AND_RELEASE.md`, `STORE_PUBLISHING.md`,
   or a per-channel `winget/README.md` / `msix/README.md`.
5. **The scripts and workflows** - always true, never narrative. `.github/workflows/*.yml` (`on.push.tags`),
   the `param()` block of `release.ps1`, the version-validating regex. **These override any prose.**

Those five settle the *mechanics*. The **scope** - which tickets this release carries - has its own source
where the repo keeps a **release package plan**: two plain-text files, work-remaining and ready, projected
from the ticket store ([RELEASE_AND_DISTRIBUTION.md](../../rules/RELEASE_AND_DISTRIBUTION.md) §8; default
names `PLAN/RELEASE_QUEUE.md` + `PLAN/RELEASE_READY.md` + a history file). That plan is **the** answer to
"what is left before we ship" - read it rather than re-deriving scope out of the ticket store, and never
reorder a line or touch a package number. Where the repo has no plan, scope comes from the ledger and the
commit log as before; do not stand one up mid-release.

### Signature detection, when the facts above are thin

- **Source body**: `go.mod` -> Go CLI. `*.sln` + `*.csproj`/`*.vbproj` -> .NET desktop (read *all*
  `TargetFramework`s - a dual-runtime repo builds two exes from one tree). `build.gradle.kts` + `app/` ->
  Android. `manifest.json` v3 under `extension/` -> browser-extension edition. `vscode-extension/package.json`
  with a `publisher` -> VS Code companion. `index.html` + `CNAME` + `deploy.bat`, no build -> site repo.
- **Delivery shape**: `installer/*.iss` -> Inno setup.exe. `packaging/wix/*.wxs` -> WiX MSI. Neither, but a
  workflow producing `*-windows-x64.zip` -> portable zip.
- **Channels** (present only if a committed manifest folder **and** its trigger exist):
  `winget/*.yaml` | `winget/templates/*.yaml` | `publishing/winget/*.yaml` -> winget;
  `msix/AppxManifest.xml` -> Microsoft Store (count `<Application>` elements - two means a co-shipped
  companion); `.github/workflows/release.yml` with `on.push.tags: ['v*']` -> GitHub Release;
  `publish-cws.yml` / `publish-edge.yml` or `ext-*-v*` tags -> Chrome/Edge; `vscode-extension/package.json`
  -> VS Code Marketplace (gated on a subtree diff); `app*/build.gradle.kts` flavors -> Play rows per flavor;
  `pages.yml` / root `CNAME` -> a **site publish, not a release**.
- **Degenerate case**: no `.github/`, no channel folders -> the repo has **no release operation**, only a
  build and a copy. Say so; do not invent a tag.

### Print the run plan and let the owner veto it in one line

Before acting, print one screen: project shape - version stamp shape and the computed candidate - the tag -
the release script and its exact dry-run invocation - the ordered channel list with `[PAID]`/`[PUBLIC]` on each
- the listing files that will be edited - the frozen anchors that will **not** change - and the single
irreversible command. Where there is a release package plan, add its two counts: what the package ships,
and the unfinished lines that will **not** ship and stay for the owner to re-sort. Where the repo has a dry-run mode, run it first and use its output as the plan.

---

## Phase 0 - Classify and confirm

Name what is being asked: build, site publish, or release. State in one line what the release operation *is in
this repo* (a `v*` tag push? a Play upload? an `ext-cws-v*` tag?). A multi-edition product fans out into
several independent one-way ops on their own cadence - decide up front which are in scope for this run.

**Autonomy**: read the repo's policy and obey it - the repos genuinely disagree. Some carry a standing owner
instruction to run the whole flow without per-step permission, where saying "релиз" *is* the approval for the
billable tag and a second confirmation round is unwanted. Others say never tag or publish unless explicitly
asked. **Default when the repo is silent: ask once, immediately before the irreversible step, and never again.**

## Phase 1 - Preconditions and the build/release wall

- On `main`. The working-tree policy is a repo fact, not an assumption - most repos refuse a dirty tree; at
  least one deliberately allows it because the tag ships only what is committed. **Default: refuse, with an
  explicit override.**
- The tag must not exist **locally or on origin**, and `main` must not be behind origin. Check all three -
  a remote-only tag fails *after* the anchor commit and local tag are already made.
- Tools present and authenticated: `git`, `gh` (`gh auth status`), plus the shape's toolchain (`go`, `dotnet`,
  `wingetcreate`, `makeappx`/MSBuild, `vsce`).
- **Confirm GitHub Actions is actually enabled.** A malformed or 0-byte workflow file auto-disables Actions;
  the `v*` tag push then silently no-ops and the release looks pushed while nothing built.
- The wall: the build script must never tag. Whether that is structural or a commit-message contract is a
  repo fact - read it.

## Phase 2 - Pre-flight gate: pay locally before you pay CI

Run the repo's build+test gate in the **release** configuration, not the dev default. If the repo has a local
CI-parity build, run it: a failure discovered here is free, a failure discovered in a paid Windows job is not.

Handle environment blockers the gate itself trips on (a running tray app can lock the output exe and kill the
build) - and restore what you stopped.

Where the repo keeps a release package plan, run its **drift check** here (plan against ticket store) and
its reconcile if the check is red. A lying plan makes Phase 5's scope list wrong, which is exactly the loss
this skill exists to prevent. Drift is never itself a release blocker - fix the plan and carry on.

Then run the canon's pre-release sweep and end it with a **written PASS/FAIL**: clean install *and* update over
a prior version, resources present, sane defaults, the core scenario end to end, performance. **A FAIL blocks
the ship.** Known-red gates must be named and scoped, never silently skipped.

## Phase 3 - Coverage-regression gate

Compare the candidate against the last shipped build. **Stop** if any of these shrink: countries/regions, age
rating, minimum platform version, ABI/architecture, `uses-feature`, device count, flavor reach. On a flavor
fan-out, run the gate per flavor.

A coverage regression is a release-blocker needing an explicit owner decision **before** the release, never
discovered after. Windows instance of the same rule: winget `MinimumOSVersion`/`Architecture` describe the
*installer*, not the narrowest exe inside it - a high floor on a setup.exe that also drops a 32-bit fallback
hides the package from exactly the machines that fallback exists for.

## Phase 4 - Version cut

- Compute the stamp **mechanically** from the repo's frozen shape; never hand-bump. Shapes in this portfolio:
  dotted `YY.M.D.HHmm`, zero-padded `YY.MMDD.HHmm`, separator-less `yyMMddHHmm`, and Android
  `versionCode` + `versionName`. Prefer the regex in the release script or CI over any prose.
- Validate with **both** a shape regex and a real-date parse before anything irreversible - that is what stops
  a mistyped `v26.1345.9999`.
- Monotonic against every published version. Never reuse a timestamp.
- **Pin the build to the tag** where the stamp is otherwise computed at build time from the clock
  (`-p:Version=<tag>`, `-p:ReleaseVersion=<tag>`, `-ldflags -X main.version=<tag>`), so binary, asset name and
  tag agree.
- Compute channel remaps mechanically. MSIX Identity forbids leading zeros and caps each part at 65535:
  int-cast every component (`26.0723.0959.0` -> `26.723.959.0`).
- Where no orchestrator writes the version, this skill owns the edit (`Directory.Build.props`, the csproj
  property, `VersionInfo.vb`, `build.gradle.kts`) plus its commit.

## Phase 5 - "What's new" - written BEFORE the tag

This is the anti-loss phase and the reason this skill exists.

1. **Gather**: `git describe --tags --abbrev=0`, then `git log <last-tag>..HEAD`, plus any accreted
   `## [Unreleased]` bullets. Distil into user-facing bullets. *Every meaningful commit becomes a line or is
   deliberately dropped* - that is the standard, not just the command.
   **Where the repo keeps a release package plan, its ready block for the current package *is* the scope of
   this release** - read that block rather than re-deriving the scope by re-reading every ticket's status,
   and cross-check it against the commit log instead of the other way round. The plan's ready block includes
   the repo's awaiting-verification status on purpose: those tickets ship. The lines still in the
   work-remaining file are **reported** in the run plan and shipped by nothing - re-sorting them into a
   later package is the owner's call, not this skill's.
2. **Cut the ledger** in whichever shape this repo uses: a root `CHANGELOG.md` moved from `[Unreleased]` to
   `## [<version>] - <YYYY-MM-DD>` with a fresh empty `[Unreleased]`; a dev log distilled into curated notes;
   a structured feature inventory; or no ledger at all, where auto-generated release notes plus **this skill's
   fan-out list is the ledger**.
3. **Fan the same text into every listing surface this repo has.** The rule is hard: *the same notes in all N
   surfaces, or it is not done* - one missed surface ships a release with stale notes. N and the paths come
   from DETECT: the GitHub Release body, the Store listing "What's new" block per language, the winget locale
   manifests' `ReleaseNotes` + `ReleaseNotesUrl`, an extension `CHANGELOG.md` + `package.json` version,
   localized READMEs' Version History and their footer version strings.
4. Apply house text style to prose (`..` not `...`, plain hyphen, Russian `ё`) and keep the ledger English
   where the canon requires it.
5. Update README/site/privacy if user-visible behaviour changed - but **do not hardcode a version on the
   site**: CTAs point at `/releases/latest` and the package id precisely so they never go stale.
6. **Commit and push these doc changes to `main` first** (free), so the tag ships them.

## Phase 6 - The irreversible action

1. **Announce**: version, tag, what fires, and that this is the one-way and billable step.
2. **Anchor commit**, where the repo uses one: build commits often carry `[skip ci]`, and a tag pointing at a
   `[skip ci]` commit means the workflow never runs. The fix is an empty `release: v<stamp>` commit whose
   prefix makes the CI workflow skip the branch push, so only the release workflow bills. Never hand-tag
   around it.
3. Push the branch, then `git push origin <tag>` - the single action that starts everything.
4. **Know the rollback before pushing.** Tag pushed and CI failed: either re-dispatch the workflow for the
   *same* tag from the Actions tab (release workflows serialize per tag and deliberately do not
   cancel-in-progress), or delete the tag and Release and re-run with a **new** version. A shipped release is
   immutable - you ship the next version, and the monotonic shape guarantees the hotfix sorts above the bad
   build. If `git tag` fails after the anchor commit was made, drop it with `git reset --hard HEAD~1` first.
5. Watch the run (`gh run watch`) and confirm green before any store step.

## Phase 7 - Distribute, in order

**Load the [store-publish](../store-publish/SKILL.md) skill now** - it carries the per-channel payload, the
traps, and the recovery paths. The order here is fixed because every downstream channel needs the GitHub
Release's asset URL and SHA256:

1. **GitHub Release** - assets named per the repo's convention, each with a `.sha256`. Verify the body reads
   sensibly; where the repo keeps a CHANGELOG, replace the auto-generated body with the dated section.
2. **winget** - refresh the committed manifests, validate and install locally from them, then submit and
   **rewrite the PR body**.
3. **Microsoft Store** - build the MSIX unsigned with the real Partner Center identity, upload, refresh the
   listing.
4. **Any extra channel**: VS Code Marketplace (own semver clock, only if the subtree changed), Chrome/Edge
   (independent reviews), Play tracks, sideload, VR.
5. **Site publish**, if the repo serves one - see [feature-to-site](../feature-to-site/SKILL.md).

Cross-cutting: if the artifact bundles third-party binaries, `THIRD-PARTY-NOTICES.txt` must be **inside every
package** - the release zip and the store package alike, not one of the two.

## Phase 8 - Prove it landed

A release is not done until it is proven live.

- The versioned asset downloads and its checksum matches; the asset **count and names** match what this repo
  expects.
- The listing or store page renders the new version and the new notes.
- Durable-URL CTAs on the site resolve.
- **The update path works from a real prior install** - not just a fresh install. A frozen-anchor mistake is
  invisible on a fresh install and only surfaces when a real user cannot update, by which point it is
  irreversible.
- Channel liveness with the right latency: `winget show <Id>` only after the PR merges (hours to a day); the
  Store sits in certification for days; Edge review is slower than Chrome.
- Reset state: `## [Unreleased]` empty again.
- **Ship the release package, and ship it before any archive or cleanup sweep.** One operator command moves
  the ready block into the history file (newest first, stamped with the version that shipped) and advances
  the package marker. A sweep that flips finished tickets to an archived state runs **after** this, never
  before - run it first and it drops those lines, and the record of what shipped goes with them. Then report
  the unfinished lines; never auto-move them and never re-order the file.
- Record the release - version, date, channels shipped, coverage-gate result - and report to the owner with
  links and an honest list of what is still in review or still manual.

---

## Done means

- [ ] The operation was named a release, and the repo's autonomy policy was read and obeyed.
- [ ] Pre-flight green **before** any billable or irreversible step, with a written PASS/FAIL sweep verdict.
- [ ] Coverage gate: no regression, or an explicit owner decision recorded.
- [ ] Version computed mechanically, shape-validated **and** date-parsed, unused locally and on origin,
      monotonic, and pinned into the build.
- [ ] "What's new" identical across **all N** listing surfaces - name them in the report - committed and
      pushed **before** the tag.
- [ ] The irreversible action executed exactly once, from `main`, on the right commit, announced.
- [ ] CI green, and Actions confirmed enabled - a tag that silently no-ops is a failed release, not a slow one.
- [ ] GitHub Release published with the exact expected asset set, each with `.sha256`;
      `THIRD-PARTY-NOTICES.txt` inside every package that bundles third-party binaries.
- [ ] Every detected channel shipped or explicitly declared out of scope.
- [ ] Frozen anchors verified unchanged on every channel touched.
- [ ] Post-release proof including **update from a real prior install**.
- [ ] Release package shipped into the history file **before** any archive sweep, marker advanced, the
      unfinished lines reported and left exactly as the owner ordered them (where the repo keeps a plan).
- [ ] State reset, release recorded, owner told with links.

## Guardrails

- Never run this to test something. That is the build flow.
- Never change a frozen anchor during a release. They are read-only here.
- Never claim a step passed without its command, exit code, and output.
- Never tick a checkbox on a submission PR for something you did not actually do.
- Never reorder the release package plan or rewrite its package column. That column and that order are the
  owner's intent, and they are the only thing in those files a ticket store cannot reconstruct.
- Report a contrib-vs-script conflict; never silently pick one.
