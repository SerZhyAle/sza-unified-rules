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
  the release script produces the billable `v*` tag.
- **`paths-ignore` on the CI workflow** - doc/manifest/asset/extension-only changes (`**.md`, `docs/**`,
  `winget/**`, `assets/**`, the extension subtree) never burn a full build.
- **Skip the release anchor commit in CI** - the release flow makes a `release:`-prefixed anchor commit that the
  tag's release workflow already builds+tests; a CI `if:` that skips `release:` commits avoids double-billing.
  Keep the tag trigger off the branch workflow (listen to `main` only), so a `v*` tag fires *only* the release
  job.
- **`concurrency`** - `cancel-in-progress: true` on CI so a burst of commits costs one active run, not N;
  `cancel-in-progress: false` on the release workflow so different tags never cancel each other and a
  half-finished release is never aborted.

## 2. Pre-flight gate (nothing ships red)

Before the release operation, the pre-release verification must pass - see
[TESTING_AND_QA.md](TESTING_AND_QA.md): clean install, resources present, settings sane, the core
scenario works, performance acceptable, explicit PASS/FAIL verdict. A red pre-flight blocks the
release; do not "release anyway".

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

- **Stamp the version mechanically** - never hand-bump (see [DOCUMENTATION_CONCEPT.md](DOCUMENTATION_CONCEPT.md)
  §2). Date tag `YY.M.D.HHmm` for desktop/CLI; monotonic `versionCode` + `versionName` for Android
  *(overlay)*. Remap to each channel's required shape mechanically.
- **A build-time date stamp is not the tag minute - pin the release build to the tag.** When the authoritative
  version is stamped from the clock at *build* time (`YY.M.D.HHmm` computed in the project file), it drifts
  minutes from the `v*` tag it ships under. The release CI must build with the version **pinned to the tag**
  (e.g. `-p:Version=<tag>`), so the version embedded in the binary matches the asset name and the tag exactly
  (reference: `CyrFlip`).
- **Gate the release trigger on a valid version.** When a `v*` tag drives the release, have the CI job
  reject a tag that is not a real version *before* it publishes - match the exact shape (e.g.
  `^v\d{2}\.\d{4}\.\d{4}$`) **and** parse it as a real date (`ParseExact 'yy.MMdd.HHmm'`), so a mistyped
  or impossible tag (`v26.1345.9999`) fails the job instead of cutting a bad release. This is the cheap
  mechanical guard that a one-way trigger is really the version you meant.
- **Cut the CHANGELOG**: move `## [Unreleased]` into `## [<version>] - <YYYY-MM-DD>`, open a fresh empty
  `[Unreleased]`. That dated section *is* the release note, rendered verbatim into the release body and
  the site "What's new". The public showcase/features text is generated *from* the changelog diff since
  the last release, never hand-authored per change.

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
- Record the release: version, date, channels shipped, and the coverage-gate result.

## 7. Rollback & hotfix

- A shipped release is immutable - you don't edit it, you ship the next version. Keep the version shape
  monotonic so a hotfix always sorts above the bad build.
- For a store still in review, you may be able to halt/replace the submission; for a public GitHub tag,
  ship a superseding tag and mark the bad one.
- A post-release fix for a specific ticket goes through the project's fix-release path, not an ad-hoc
  patch to the published artifact.

## 8. Applying to a new project

1. Write down the project's exact build/release boundary (§1) - what the release operation *is* here.
2. Wire the pre-flight gate (§2) to the project's test/sweep flow.
3. Codify the coverage-gate inputs (§3) for this platform.
4. Adopt the version + changelog cut (§4) and the per-channel distribute list (§5).
5. Script the post-release checks (§6), including an update-from-prior-install test.
