---
name: release
description: 'Run an approved public release through preflight, version/tag, release notes, publication and proof. Use to release, publish a version, cut a tag or ship to GitHub, winget, Microsoft Store, Google Play or a marketplace. «релиз», «зарелизь», «опубликуй версию», «выпусти версию», «публикуем Android приложения». Local builds use /build.'
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
[CONTRACTS.md](../../rules/CONTRACTS.md) §6 (what a release owes the shared contracts),
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
where the repo keeps a **release package plan**: the work-remaining queue file and a ready side
([RELEASE_AND_DISTRIBUTION.md](../../rules/RELEASE_AND_DISTRIBUTION.md) §8; the shared harness keeps the queue in
`PLAN/RELEASE_QUEUE.md` and prints the ready side with `spec_catalog/release-queue -Show Ready`, the history with
`-Show Done`). That plan is **the** answer to
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
- the listing files that will be edited - the frozen anchors that will **not** change - the contract gate's
verdict (Phase 3) - and the single irreversible command. Where there is a release package plan, add its package marker (the `current-next-release` number) and its two counts: what the package ships,
and the unfinished lines that will **not** ship and stay for the owner to re-sort. Where the repo has a dry-run mode, run it first and use its output as the plan.

---

## Phase 0 - Classify and confirm

Name what is being asked: build, site publish, or release. State in one line what the release operation *is in
this repo* (a `v*` tag push? a Play upload? an `ext-cws-v*` tag?). A multi-edition product fans out into
several independent one-way ops on their own cadence - decide up front which are in scope for this run.

Obtain the owner's go for the named release in the session or its ticket before the one-way step. That
approval covers the whole release. Run the console commands and handle terminal input yourself without
per-step confirmation. Ask for approval again only when the version, channel or product changes. Hand off
UAC elevation, a new sign-in or consent screen, and hardware interaction to the owner.
See [RELEASE_AND_DISTRIBUTION.md](../../rules/RELEASE_AND_DISTRIBUTION.md) §1.

## Before you ship

- Ship **`THIRD-PARTY-NOTICES.txt` inside every distributed package** when the artifact bundles third-party
  binaries. ([SECURITY_AND_PRIVACY](../../rules/SECURITY_AND_PRIVACY.md) §6)
- Declare only the **permissions** the runtime actually uses, each with a one-sentence user-visible
  justification. ([SECURITY_AND_PRIVACY](../../rules/SECURITY_AND_PRIVACY.md) §3)
- Keep the **privacy page, the permission list, and the store data-safety form** saying the same thing;
  claim "no telemetry" only if it is true. ([SECURITY_AND_PRIVACY](../../rules/SECURITY_AND_PRIVACY.md) §4-5)
- File a fresh **IARC questionnaire** whenever the app's content-exposure profile differs; never copy a
  portfolio rating id. ([SECURITY_AND_PRIVACY](../../rules/SECURITY_AND_PRIVACY.md) §5)

Check the [surface rules](../feature-to-site/SKILL.md#before-you-ship) before drafting or updating release copy.

## Phase 1 - Preconditions and the build/release wall

- On `main`. The working-tree policy is a repo fact, not an assumption - most repos refuse a dirty tree; at
  least one deliberately allows it because the tag ships only what is committed. **Default: refuse, with an
  explicit override.**
- The tag must not exist **locally or on origin**, and `main` must not be behind origin. Check all three -
  a remote-only tag fails *after* the anchor commit and local tag are already made.
- **Where the repo has a dev branch and a trunk, nothing is stranded on the trunk.** Run
  `git rev-list --count <dev>..<trunk>`; a non-zero count means a trunk-direct commit (a site publish, a
  post-tag showcase, a hotfix) was never merged back, so back-merge it **before** merging dev into the trunk -
  both sides regenerate the same render targets, and one release hit 533 conflicted paths this way.
- Tools present and authenticated: `git`, `gh` (`gh auth status`), plus the shape's toolchain (`go`, `dotnet`,
  `wingetcreate`, `makeappx`/MSBuild, `vsce`).
- **Confirm GitHub Actions is actually enabled.** A malformed or 0-byte workflow file auto-disables Actions;
  the `v*` tag push then silently no-ops and the release looks pushed while nothing built.
- The wall: the build script must never tag. Whether that is structural or a commit-message contract is a
  repo fact - read it.

## Phase 2 - Pre-flight gate: pay locally before you pay CI

Run the repo's build+test gate in the **release** configuration, not the dev default: the full build and
every test tier, the release tier above 5 s included. Between releases nothing slower than 5 s ran
([TESTING_AND_QA.md](../../rules/TESTING_AND_QA.md) §2), so this run is the first proof of every `RELEASE`
item the tickets since the last release recorded - a red here is expected news, not a surprise to explain away. If the repo has a local
CI-parity build, run it: a failure discovered here is free, a failure discovered in a paid Windows job is not.
Where the release workflow tests on a runner and a CI workflow can be dispatched by hand, **dry-run it on the pushed
HEAD before the tag** and read `gh run view <id> --log-failed`: a runner differs from the dev machine (a 1024 px
display, a small slow machine, no foreground rights), and a green local gate once still left three burnt tags with no
GitHub Release.
Judge a **detached worktree of HEAD**, never the working tree: the tree is dirty by design, and `[skip ci]`
commits mean this is the only clean-room run before the paid one.

The ship step takes **evidence, not a bare verdict**: it names the plan that ran and the tree it judged, a
subset run never unlocks it, an edit during the run voids it, and a gate that checked nothing is COULD NOT
VERIFY, never PASS; any flow that rewrites tracked files runs *before* the gate. A gate that can only run on
the owner's machine travels as a committed `release-verdicts/<version>.json` inside the tagged tree (the writer
refuses a dirty tree and writes nothing on red; the checker needs the judged commit to be an ancestor of the
tag and nothing outside `release-verdicts/` changed since). Rules:
[RELEASE_AND_DISTRIBUTION.md](../../rules/RELEASE_AND_DISTRIBUTION.md) §2.

Check every channel credential that has a fixed lifetime against its recorded rotation date (Phase 8).

For a Microsoft Store product, before the tag run the shared read-only preflight when its machine channel is
configured. Read the Store ID from the product's identity file and pass the product name and candidate MSIX
version to [Store-Preflight.ps1](../../tools/Store-Preflight.ps1); the invocation and exit codes are in the
[store machine channel reference](../store-publish/references/store-machine-channel.md). Exit 1 stops the Store
preflight on a state or data problem; exit 2 means the Store step is manual and the release can continue.
The submission-channel contract proposal remains pending and unverified.

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

### Contract gate - what this release owes the shared contracts

A release that breaks another product's ability to read this one's data is a reach regression of its own
kind, and it is just as one-way. The rule is [CONTRACTS.md](../../rules/CONTRACTS.md) §6; this is how it
runs. The contracts in scope are the ones this product produces or consumes: its `docs/contracts/`
pointers, plus every row the shared registry holds for it. The catalog is wherever the repo's agent-rules
file says it is.

**First, catch up since the last reconciliation - every release, not only one that touches a boundary.** Run
`pwsh -File <root>/tools/contract-lag.ps1 -Product "<repository key>" -EmitSpec -OutFile temp/contract-catchup.md`
(`<root>` is the plugin root. `<repository key>` is this repository's key in the portfolio registry, the word its rows
in section 2 of the catalog registry start with; while those rows still carry the product's name instead, pass that
name - the spec then opens with "Selected by text" and may miss a row spelled differently, so look for one by hand.
The script reads the catalog from `SZA_CONTRACTS_ROOT` or the default) and read it:
the rows below their contract's version are sorted by what the document log holds in between
([CONTRACTS.md](../../rules/CONTRACTS.md) §6 item 6). `behind (breaking)`: every entry is read against the code, in
every release. `behind (additive)`: the entries are read against the code when this release touches that contract's
boundary (check 4) or adds a surface the contract governs; otherwise name the row in the release plan and leave it,
its dated reason, written once, being that the boundary was not touched (check 2). `unread`: nothing is owed - list
it, and move the row only if you read its entries. A divergence is fixed or recorded as a dated exception; a row
whose entries were read moves to the current version with today's verification date. The checks below judge the
result.

1. **Every contract in scope has a registry row** with a verification date no older than the last release
   tag. A missing row is a **blocker**; a stale one is a blocker until it is re-verified against the code -
   and only this product's own row is touched to do it.
2. **Behind the current version** is allowed with a dated reason in the row. **One MAJOR behind** is a
   warning in the plan; **two** blocks the release if it touches that boundary.
3. **An exception has no end date** (owner decision, 2026-11-16): an open row in the registry stands until it
   is closed and a date in its text is history, so no check here judges time. The release verdict still names
   each open exception that touches this release and its impact.
4. **The diff since the last tag touches a contract boundary** - a file a pointer names as the
   implementation, a serializer, importer or exporter, a wire field - **blocks until the catalog change is
   in**: the version bump and the dated document-log row exist before the tag does.
5. **The conformance vectors** ran in this product's own suite against the catalog's vectors, at the version
   the registry names - command, exit code, output. A green suite against a stale vector is not a pass.

The gate ends in a written PASS, WARN or FAIL, and FAIL blocks the tag exactly as a red pre-flight does.
**If the catalog cannot be reached from this machine the gate is UNVERIFIED, never PASS** - say so in the
run plan and let the owner decide. A repo with no pointer, no registry row and no boundary code says so in
one line and the gate is `n/a`.

## Phase 4 - Version cut

- Compute the stamp **mechanically** from the repo's frozen shape; never hand-bump. Shapes in this portfolio:
  dotted `YY.M.D.HHmm`, zero-padded `YY.MMDD.HHmm`, separator-less `yyMMddHHmm`, and Android
  `versionCode` + `versionName`. Prefer the regex in the release script or CI over any prose.
- Validate with **both** a shape regex and a real-date parse before anything irreversible - that is what stops
  a mistyped `v26.1345.9999`.
- Monotonic against every published version - every channel's list, including an off-tag stamp that shipped on
  one channel only. Read that list from the release ledger after a fresh `probe`
  ([RELEASE_AND_DISTRIBUTION.md](../../rules/RELEASE_AND_DISTRIBUTION.md) §10: `release-ledger probe`, then
  `release-ledger show`), and ask a channel by hand only where the probe says `unverified`. Never reuse a timestamp. Derive date stamps in UTC, or name the local clock the repo uses
  and keep it; the clock is part of the frozen shape.
- **Pin the build to the tag** where the stamp is otherwise computed at build time from the clock
  (`-p:Version=<tag>`, `-p:ReleaseVersion=<tag>`, `-ldflags -X main.version=<tag>`), so binary, asset name and
  tag agree, then **read the version back out of the built artifact** - a source-level check agrees with a stale
  artifact by construction.
- Compute channel remaps mechanically. MSIX Identity forbids leading zeros and caps each part at 65535:
  int-cast every component (`26.0723.0959.0` -> `26.723.959.0`).
- Where no orchestrator writes the version, this skill owns the edit (`Directory.Build.props`, the csproj
  property, `VersionInfo.vb`, `build.gradle.kts`) plus its commit.

## Phase 5 - "What's new" - written BEFORE the tag

This is the anti-loss phase and the reason this skill exists.

1. **Gather**: the last *published* release (`gh release list`, or the channel's own record) - not merely the last
   tag, because a failed release run leaves a tag with no release - then `git log <that-tag>..HEAD`, plus any accreted
   `## [Unreleased]` bullets. Distil into user-facing bullets. *Every meaningful commit becomes a line or is
   deliberately dropped* - that is the standard, not just the command.
   **Where the repo keeps a release package plan, its ready block for the current package *is* the scope of
   this release** - read that block rather than re-deriving the scope by re-reading every ticket's status,
   and cross-check it against the commit log instead of the other way round. The plan's ready block includes
   the repo's awaiting-verification status on purpose: those tickets ship. The lines still in the
   work-remaining file are **reported** in the run plan and shipped by nothing - re-sorting them into a
   later package is the owner's call, not this skill's.
2. **Cut the ledger** in whichever shape this repo uses: a root `CHANGELOG.md` moved from `[Unreleased]` to
   `## [<version>] - <YY-MM-DD HH:mm>` with a fresh empty `[Unreleased]`; a dev log distilled into curated notes;
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
   **Sweep every released surface for promises and hedges** - "coming soon", "planned", "not yet",
   "experimental", "beta", `скоро`, `планируется`, `ещё не`, `экспериментально`, `бета` - and for placeholders
   (a "soon" button, a link to a page that does not exist). A
   feature shipped by this release loses its promise line everywhere; a feature not in this release is not
   mentioned ([DOCUMENTATION_CONCEPT.md](../../rules/DOCUMENTATION_CONCEPT.md) §5).
6. **Commit and push these doc changes to `main` first** (free), so the tag ships them.

## Phase 6 - The irreversible action

1. **Announce**: version, tag, what fires, and that this is the one-way and billable step.
2. **Anchor commit**, where the repo uses one: build commits often carry `[skip ci]`, and a tag pointing at a
   `[skip ci]` commit means the workflow never runs. The fix is an empty `release: v<stamp>` commit whose
   prefix makes the CI workflow skip the branch push, so only the release workflow bills. Never hand-tag
   around it.
3. Push the branch, then `git push origin <tag>` - the single action that starts everything. The workflow
   behind it builds only the named tag's tree, refuses a tag whose commit carries no gate stamp, and holds
   `contents: write` on the publish job alone ([RELEASE_AND_DISTRIBUTION.md](../../rules/RELEASE_AND_DISTRIBUTION.md)
   §1 "CI safety levers"); never publish around it.
4. **Know the rollback before pushing.** Tag pushed and CI failed **before anything was published**: re-dispatch
   the workflow for the *same* tag from the Actions tab (release workflows serialize per tag and deliberately
   do not cancel-in-progress), or delete the tag and re-run with a **new** version. **Once the Release carries
   its asset, the tag is never rebuilt** - a rebuilt zip has other bytes and breaks the hash already merged
   into winget; the workflow refuses it (`overwrite_files: false`). After a failure that published nothing and
   cannot be re-dispatched, cut a new, strictly newer stamp and leave the failed number retired. A shipped
   release is immutable - you ship the next version, and the monotonic shape guarantees the hotfix sorts above
   the bad build. If `git tag` fails after the anchor commit was made, drop it with `git reset --mixed HEAD~1`
   first (the stamp stays in the files and the next run overwrites it; `--mixed` keeps the working tree, which
   is what a release wants here).
5. Watch the run (`gh run watch`) and confirm green before any store step.

## Phase 7 - Distribute, in order

**Load the [store-publish](../store-publish/SKILL.md) skill now** - it carries the per-channel payload, the
traps, and the recovery paths. The order here is fixed because every downstream channel needs the GitHub
Release's asset URL and SHA256:

1. **GitHub Release** - assets named per the repo's convention, each with a `.sha256`. Verify the body reads
   sensibly; where the repo keeps a CHANGELOG, replace the auto-generated body with the dated section.
2. **winget** - refresh the committed manifests (every file of every locale), validate and install locally
   from them, then submit and **rewrite the PR body**. The manifest carrying the asset hash is the one
   generated file that may be committed after the tag: one scripted commit right after the publish, verified
   against the published `.sha256`.
3. **Microsoft Store** - build the MSIX unsigned with the real Partner Center identity, then follow the
   manual Partner Center upload and listing flow by default. For a machine submission, follow
   WINDOWS-STORE rule 22 and amendment E for the commit switch and owner confirmation.
   After the tag, a Store channel failure is reported and never fails the release or stops other channels.
   The preflight's sanitized JSON result omits identifiers and raw responses; the future submission
   evidence format remains part of the pending proposal (see the machine channel page in `store-publish`).
4. **Any extra channel**: VS Code Marketplace (own semver clock, only if the subtree changed), Chrome/Edge
   (independent reviews), Play tracks, sideload, VR. For Play, follow the
   [API release procedure](../store-publish/references/google-play.md#7-publishing-a-release-through-the-api).
   One release train is one review submission per application id: phone, Wear and listing changes ship in one edit and
   one commit, never as several submissions in a row (the procedure's opening section says why).
5. **Site publish**, if the repo serves one - see [feature-to-site](../feature-to-site/SKILL.md).

Cross-cutting: if the artifact bundles third-party binaries, `THIRD-PARTY-NOTICES.txt` must be **inside every
package** - the release zip and the store package alike, not one of the two.

## Phase 8 - Prove it landed

A release is not done until it is proven live.

- The versioned asset downloads and its checksum matches; the asset **count and names** match what this repo
  expects.
- The listing or store page renders the new version and the new notes.
- Durable-URL CTAs on the site resolve.
- Every "includes X" sentence in a listing holds for each channel's **built artifact**, not only the source tree.
- **The update path works from a real prior install** - not just a fresh install. A frozen-anchor mistake is
  invisible on a fresh install and only surfaces when a real user cannot update, by which point it is
  irreversible.
- Channel liveness with the right latency: `winget show <Id>` only after the PR merges (hours to a day); the
  Store sits in certification for days; Edge review is slower than Chrome.
- **Record each channel's step in the release ledger as it happens**
  ([RELEASE_AND_DISTRIBUTION.md](../../rules/RELEASE_AND_DISTRIBUTION.md) §10), through the harness script
  `releases/release-ledger` (the repository's `tools/harness.ps1 releases/release-ledger ..` or the plugin's
  `tools/harness/releases/release-ledger.ps1`): `publish -Key <channel> -Version <v> -State <state> -Ref <tag, PR,
  submission> -Url <public page>`, with `pending`, `submitted`, `live`, `blocked`, `rejected`, `withdrawn`, `n/a` -
  `submitted` is not `live`. Then run `probe` and report what it still says `submitted` or `unverified`. A repository
  that still keeps a hand-run `RELEASE_STATE.md` records in the ledger as well, and its adoption ticket retires the old
  file. Note every credential with a fixed lifetime and its rotation date in the release doc (the Edge Add-ons API key
  lasts about 72 days; an expired key shows as HTTP 401 at the one-way step, so check it in Phase 2).
- Reset state: `## [Unreleased]` empty again.
- **Ship the release package, and ship it before any archive or cleanup sweep.** Where the repository runs the
  shared harness this is one script, `spec_catalog/ship-package` (the repository's
  `tools/harness.ps1 spec_catalog/ship-package ..` or the plugin's `tools/harness/spec_catalog/ship-package.ps1`).
  Run it with `-Release <N> -Version <v> -DryRun` first - `<N>` is the package marker the run plan printed,
  `<v>` the version that shipped - read the counts, then run it again without `-DryRun`. It records every numbered
  ready block up to `<N>` as shipped (newest first, stamped with the version), puts the marker on `<N>+1`, and only
  then archives the `Verified` tickets on neither side whose recorded shipment names a version. A ticket shipped as
  `Implemented` or awaiting the owner's test stays in the ticket store until it is verified; a `Verified` ticket with
  no recorded shipment, or shipped without `-Version`, stays too and is named - archive it with a reason. Skip the script
  where the repository's own release script already shipped the package: a second run with the same
  `-Release <N>` finds nothing ready and moves nothing. A repository with a plan tool of its own keeps the same
  order - never run the sweep first: it drops those lines, and the record of what shipped goes with them. Then
  report the unfinished lines and the rows the script says stay; never auto-move them and never re-order the file.
- Record the release - the ledger's events carry the version, the date and the channels shipped; put the
  coverage-gate result into the note of the first one - and report to the owner with links and an honest list of
  what is still in review or still manual (`release-ledger show` prints it).

---

## Done means

- [ ] The operation was named a release, and the repo's autonomy policy was read and obeyed.
- [ ] Pre-flight green **before** any billable or irreversible step, with a written PASS/FAIL sweep verdict.
- [ ] Coverage gate: no regression, or an explicit owner decision recorded.
- [ ] Contract gate: PASS, WARN with its warnings named, `n/a` with its reason, or UNVERIFIED with the owner's
      decision recorded - never a FAIL shipped.
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
- [ ] Release package recorded as shipped **before** any archive sweep, marker advanced, the
      unfinished lines reported and left exactly as the owner ordered them (where the repo keeps a plan).
- [ ] Every channel step recorded in the release ledger, a `probe` run after the last one.
- [ ] State reset, release recorded, owner told with links.

## Guardrails

- Never run this to test something. That is the build flow.
- Never change a frozen anchor during a release. They are read-only here.
- Never claim a step passed without its command, exit code, and output.
- Never tick a checkbox on a submission PR for something you did not actually do.
- Never reorder the release package plan or rewrite its package column. That column and that order are the
  owner's intent, and they are the only thing in those files a ticket store cannot reconstruct.
- Report a contrib-vs-script conflict; never silently pick one.
