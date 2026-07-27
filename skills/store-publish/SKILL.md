---
name: store-publish
description: Publish an SZA product to its distribution channels - GitHub Release, winget (microsoft/winget-pkgs), and the Microsoft Store via MSIX and Partner Center. Resolves the repo's manifest paths, reserved identity and frozen anchors at run time, then runs each channel as its own one-way operation with its own pre-submit gates and recovery paths. Use when publishing or updating a winget manifest, building or uploading an MSIX, reserving a Store identity, fixing a rejected winget PR or a rejected Partner Center listing import, or onboarding a new product to a store.
---

# Store publishing - three channels, three one-way operations

**"Publish" is not one action.** Windows desktop products use three independent channels, each with its own
trigger, cost, auth, signer, listing source, frozen anchor, and liveness check. Never collapse them.

| Channel | Trigger | Cost | Signer | Frozen anchor | Irreversible at |
| --- | --- | --- | --- | --- | --- |
| GitHub Release | `v*` tag push | `[PAID]` CI minutes | you (`.sha256` sidecar) | none | the tag push; a shipped release is immutable |
| winget | PR to `microsoft/winget-pkgs` | `[PUBLIC]` | Microsoft re-hosts | `PackageIdentifier` (+ `PackageName` where an installer exists) | the **merge**; the PR itself is closable |
| Microsoft Store | manual Partner Center upload | `[PUBLIC]` | **the Store re-signs at certification** | MSIX Identity `Name` + `Publisher` | publication; identity is permanent from name reservation |

**Ordering**: the GitHub Release must exist first - winget is hard-gated on a public release URL and its
SHA256. The Store leg is independent and may run in parallel. winget goes last.

This skill supplies the channel mechanics. The release *order* and the gates before any of it belong to the
[release](../release/SKILL.md) skill - if the repo has its own release skill, **defer to it** and supply only
the mechanics below.

Canon: [CHANNEL_MATRIX.md](../../rules/CHANNEL_MATRIX.md),
[WINDOWS_PACKAGING.md](../../rules/WINDOWS_PACKAGING.md),
[SECURITY_AND_PRIVACY.md](../../rules/SECURITY_AND_PRIVACY.md),
[LOCALIZATION.md](../../rules/LOCALIZATION.md).

---

## Entry - discover, never assume

Five repos already use four different folder layouts and three different placeholder-token styles. **Anything
hardcoded will be wrong in at least two of them.** Probe for:

- `STORE_PUBLISHING.md` at the repo root - the repo's own store runbook, where one exists.
- `msix/build-msix.ps1` **or** `publishing/msix/build-msix.ps1`.
- `winget/*.yaml`, `winget/templates/*.yaml`, or `publishing/winget/*.yaml`.
- `tools/store/build-store-listing-csv.ps1` or `msix/build-store-listing-csv.ps1`.
- The listing copy: `msix/listing/<code>.txt` + `shared.txt` + `search-terms.*`, `msix/store-listings.md`,
  `msix/store-listing.md`, `publishing/store/listingData.csv`, `tools/store/listingData.csv`.
- `.claude/skills/release/SKILL.md` - a repo-local release skill takes precedence.
- `rules/contrib/<repo>.md` in this plugin - "Frozen anchors" and "Channel-matrix rows".

**Two values, and only two, are account-wide constants:**

```
Publisher            = CN=F98ACEDB-1E22-4C39-AF63-F9FCFE807DCD
PublisherDisplayName = SZA
```

`IdentityName`, Store ID, PFN and the IARC rating id are **per product** - always looked up, never carried
over from another repo.

**Fail closed on ambiguity.** If a repo has more than one plausible listing source, read the render-target
banner; if there is none, **stop and ask which is authoritative**. Two sources of truth is exactly how a
corrected claim survives in a live listing. At least one repo in this portfolio carries three overlapping
listing copies with the resolution still half-applied.

## Gates before anything public

Print a visible verdict; refuse to proceed on red, never merely warn.

1. **Pre-flight** PASS/FAIL - clean install, resources, defaults, core scenario.
2. **Coverage regression** vs the last shipped build - countries, age rating, minimum OS, architecture.
   A stricter age rating is itself a coverage regression and therefore a release-blocker.
3. **Version** stamped mechanically, shape-validated and parsed as a real date.

---

## Leg 1 - GitHub Release

The authoritative asset host and the precondition for winget.

- Confirm **Actions is enabled** before trusting a tag. A leftover 0-byte workflow file fails to parse, and
  GitHub's auto-disable-after-repeated-failures policy pauses Actions repo-wide; a `v*` tag then produces
  `total_count: 0` runs and the release looks pushed while nothing built. Recovery is three steps: delete the
  dead workflow, re-enable Actions **in the browser** (no API on a free account), and **re-cut the tag** -
  pushes that fire before Actions is enabled are never retried.
- Watch the run (`gh run watch`) and confirm green before moving on.
- Verify the asset set: expected names and count, each with a `.sha256`.
- **Re-hash the uploaded asset yourself.** A `.sha256` sidecar can go stale after a rebuild.
- `THIRD-PARTY-NOTICES.txt` must be **inside** the release zip when third-party binaries are bundled - not
  only inside the MSIX. Check the workflow's packaging step actually copies it.

## Leg 2 - winget

**Load [references/winget.md](references/winget.md)** for the full payload: the manifest set and the fields
that change per release, the `update`-vs-`submit` branch, the pre-submit verification ladder, the CRLF gate,
the error-code table, PR-body discipline, and how to read the real error out of the validation logs.

The three rules that decide most outcomes:

- **Default to the folder form.** `wingetcreate update` rebuilds from the manifest already published in
  winget-pkgs and only bumps version/URL/hash, so your repo's `Description`, `Tags` and `ReleaseNotes` never
  reach the catalog. `update` is legitimate **only** when nothing but version/URL/hash changed - and since
  almost every release changes `ReleaseNotes`, that is the exception, not the rule.
- **`winget install --manifest <dir>` is the only gate that verifies URL + SHA end to end.** `winget validate`
  checks schema only.
- **Never re-run `wingetcreate submit` to fix a PR** - that opens a second PR. Patch the existing branch.
  And after submitting, wait: every push or `@wingetbot run` cancels the in-flight run and re-queues from
  scratch. `REVIEW_REQUIRED` means a human moderator, not an error.

## Leg 3 - Microsoft Store (MSIX)

**Load [references/msix-store.md](references/msix-store.md)** for the full payload: identity resolution, the
version remap rules, the container-virtualization pre-checks, the Partner Center click path, and the
export-then-merge listing CSV flow with its eight measured rules.

The three rules that decide most outcomes:

- **Never invoke `build-msix.ps1` bare.** Two repos in this portfolio default to a self-sign placeholder
  Publisher (`CN=SerZhyAle`), so a plain build produces a Store-invalid package. Always pass all three
  identity values explicitly, then **read back the packed `<Identity>` element and assert it matches** the
  reserved values before offering the file for upload.
- **The package is uploaded unsigned; Microsoft re-signs at certification.** No certificate lives in the repo
  and none is needed. `-SelfSign` exists only for local sideload testing and produces a package that must
  never be uploaded.
- **The listing CSV is export-then-merge, never hand-authored.** Partner Center `ID` values are
  account-specific; a direct upload is rejected. Take a fresh export every attempt.

---

## Exit - prove it landed

- The versioned asset downloads and its checksum matches.
- The listing or store page renders the new version and the new notes.
- Durable-URL CTAs resolve.
- **The update path works from a real prior install.** This is the only check that catches a frozen-anchor
  mistake, and it is invisible on a fresh install. Do not mark the task done on a fresh-install-only
  verification.
- Liveness latency is per channel: `winget show <Id>` only after the PR merges (hours to a day); the Store
  sits in certification for days; Edge review is slower than Chrome.
- Record: version, date, channels shipped, coverage-gate result.

## New product - the one-time path

Distinct from an update and easy to get wrong:

1. Register under Partner Center's **"Windows"** program - **not** "Windows Desktop Applications", which is
   telemetry for EV-signed Win32 apps and not an MSIX submission path. Free; choose Individual.
2. Create a product > **MSIX or PWA app** > reserve the name > read the three identity values from
   Product identity.
3. Sign the winget CLA once.
4. Decide the delivery shape from install-time needs, not habit - see
   [WINDOWS_PACKAGING.md](../../rules/WINDOWS_PACKAGING.md). Portable zip by default.
5. Reserve the frozen anchors once, and record them in the repo's contrib record.
6. **File a fresh IARC questionnaire** if the content profile differs from an existing product. The portfolio
   rating id does **not** transfer to an app that can open arbitrary third-party or uncurated content -
   a stream player, a web view, a remote-media file opener. Answer honestly.
7. Note the `msstore` CLI cannot automate submissions on an individual MSA account - interactive
   `msstore reconfigure` fails with "Error while retrieving Organization" because there is no Azure AD org
   behind it. The Partner Center web submission is the reliable path; present the Store leg as a guided
   manual checklist, never as a CLI submit.

## Categories that draw extra Store review

Two shapes in this portfolio attract it, and both are pre-emptable in the listing copy:

- **An app that opens third-party streams** gets infringing-content review. Frame the listing by the
  legitimate job - a curated catalog player, not a piracy tool - and keep the most trigger-prone keyword out.
  The forbidden-terms guard is **Store-scoped**; winget has no equivalent review, so do not silently
  propagate the ban to winget or silently allow the term back into the Store. Surface the discrepancy.
- **A global keyboard hook plus clipboard read reads as a keylogger.** Same pre-emption: the `runFullTrust`
  justification plus a plain "does not log keystrokes, no network, no data" description.

Every desktop MSIX needs a `runFullTrust` justification, capped at ~1000 characters - keep a long and a short
variant in the repo. Keep the privacy statement, the permission list and the data-safety form mutually
consistent; a mismatch is a common rejection. A local-but-sensitive tool hosts a privacy page even with zero
network and zero telemetry - the zero-data carve-out does not apply to it.

## Guardrails

- Three channels, three operations. Never one "publish".
- Frozen anchors are read-only here. Changing one orphans every installed copy on that channel.
- Never hardcode a character cap - read it from the console at submit time; they drift.
- Never add or drop a locale on your own initiative. Locale sets are per-surface contracts: one repo
  deliberately ships 13 Store languages and 3 winget locales, and "completing" the winget set would buy
  machine-translated metadata with no reader.
- Never tick a submission checkbox for a check you did not run.
