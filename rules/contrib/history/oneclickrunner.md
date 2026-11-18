# History: oneclickrunner

## Spread-back applied 2026-07-23
Ran `SPREAD_BACK_PROMPT.md` in `P:\WINDOWS\OneClickRunner` as a **NEW** repo (no prior contrib record;
NEW_PROJECT_CHECKLIST followed for the adoption, this record created from TEMPLATE.md).

**What changed (in the repo).** Adopted the **reference** consumption model in the single rules file
`CLAUDE.md` (`AGENTS.md` already delegates to it):
- Added an **SZA Unified Rules (canon)** section: canon path + read order, a link to this contrib record,
  and a condensed **overlay-facts** block (Overlay A minimal / undistributed, version shape `YY.MMdd.HHmm`,
  local-copy deploy, no channels, no anchors).
- Aligned **Communication** to the canon (`AUTHOR.md` §Language): "Chat in English" -> "Chat in Russian;
  code/comments/logs/commits in English".
- **Reconciled internal drift** in the Architecture section against the live tree (independent of the
  canon, but required by step 3 "verify every kept claim"): the elevation "gotcha" was **inverted** - code
  now unifies elevation on `RunAsAdmin` regardless of launch surface (`ScenarioLauncher.Launch`, T0001), so
  the "Jump List always elevates" claim was removed; the system tray now exists (`TrayIconService`) so the
  "not a system tray" / "README is stale" caveats were replaced; pipe IPC is now `PipeIpcService` (dead
  `StartPipeServer`/`StartPipeListener` naming removed, T0019); `SPECIAL_YTDLP` is now only
  `ScenarioLauncher.LegacyYtDlpSentinel` back-compat with a first-class yt-dlp scenario type (T0013);
  `Debug.WriteLine` note dropped (0 occurrences, T0020); file-budget note repointed from the now-thin
  `App.xaml.cs` (~240) to `MainWindow.xaml.cs` (~460).

**Verification (fresh run 2026-07-23).**
- `dotnet build -c Release` -> **exit 0**, 0 warnings, 0 errors (after stopping a running instance that
  held a file lock on the output exe - a MSB3027 copy-lock, not a compile error).
- Overlay facts each cited to `build.ps1` / `OneClickRunner.csproj` / `git ls-files` above.

**Questions closed.** None requiring owner input were mechanically closable; the three above are genuine
owner decisions (distribution intent, LICENSE/CHANGELOG, deploy-path parameterization) and stay open.

**What remains / canon edits still needed (NOT committed from the repo session - owner to apply in a canon
session, then run `tools/check-rules.ps1`):**
- Add a **OneClickRunner row** to `SPREAD_BACK_PROMPT.md`'s target table (contrib record
  `contrib/oneclickrunner.md`) and mark its Done column after this repo's spread-back commit lands.
- Consider the one **candidate core edit** above (Overlay A GitHub-Release-only = empty anchor set). Low
  urgency; only OneClickRunner needs it so far.

## Spread-back follow-up 2026-07-23 (distribution stood up)
Owner chose, in the same session: **GitHub Release + LICENSE + CHANGELOG + push**.
- Added `LICENSE` (MIT, `Serhii Zhyhunenko (SerZhyAle)`) and `CHANGELOG.md` (house `[Unreleased]` flow).
- Added `release.ps1` - the single tagger (build/release wall vs the local-deploy `build.ps1`): publishes
  framework-dependent single-file win-x64, zips `OneClickRunner-<version>-win-x64.zip` + `.sha256`
  (`-p:DebugType=none`, no pdb), tags `v<version>`, pushes, `gh release create` with notes from CHANGELOG.
  Version is overridden to the exact tag so exe stamp = tag = zip name; `-DryRun` and `-SelfContained` levers.
- Updated `CLAUDE.md` overlay block: no longer "undistributed" - one channel (GitHub Release), build/release
  wall, LICENSE/CHANGELOG present.
- **Verified:** `release.ps1 -DryRun` -> exit 0; exe `ProductVersion=26.0723.1719` matches tag; zip holds
  only `OneClickRunner.exe`; sha256 written. Real release: tag `v26.0723.1719` cut and `gh release create`
  run (see repo commit + release URL in the session report).
- Repo commits **pushed** to `origin/main`.

## Canon adoption 2026-07-27

Adopted as the `sza` plugin (consumption model **reference**), committed. `.sza-canon.json`: overlay A, single
channel (GitHub Release only - no winget, MSIX, Store or installer, so no frozen anchors beyond the repo
slug), Keep-a-Changelog ledger, docs/ site.

`AGENTS.md` is a deliberate delegation to `CLAUDE.md` ("keep exactly one canonical rules file, do not fork the
rules here"). The gate now recognises that pattern instead of reporting it as a missing pointer.

Compliance gate: 1 error. It is real and needs a decision, not an edit: a product with a public site must host
a privacy page, and this repo has none. The zero-data carve-out lapses once there is a site.

## Canon reconcile 2026-08-02 - agent-process propagation

Canon **2026.07.27 -> 2026.08.02**, core digest `sha256:dae220bf..` -> `sha256:6c247452..`. Stamp
updated; the adoption model is unchanged. The upstream change is [AI_USAGE.md](../../AI_USAGE.md) only -
the agent-process findings propagated from FastMediaSorter mob_v2 under its ticket S1342 - so the
staleness ladder's "re-read only the changed rule docs" path applies and no full re-adoption was run.
Nothing in `rules/` touched packaging, release, channels or layout, and no divergence was found
between the new bullets and this repo's own rules file.

Per-user memory store, no committed one, so §4 transfers the same partial way it does for EPUB_2_HTML.
Nothing in the rules file competes with the new bullets. §1's threshold rule is the one with immediate
bite - this repo's build and its fast checks sit on opposite sides of any sensible boundary.

Verification: `check-compliance: OneClickRunner - 0 error(s), 2 warning(s) (overlay A, canon 2026.08.02)` - warnings are pre-existing and none was introduced here.

## Canon reconcile 2026-08-05 - measurement channels and ungated routing

Canon **2026.08.02 -> 2026.08.05**, core digest `sha256:6c247452..` -> `sha256:8d33fdab..`. Stamp updated;
the adoption model is unchanged. Upstream: [AI_USAGE.md](../../AI_USAGE.md) §3 and §5, plus the `agent-cost`
skill, which sits outside the digest. Two findings from the FastMediaSorter mob_v2 process retrospective of
2026-08-05, recorded in full in [fastmediasorter_mob_v2.md](../fastmediasorter_mob_v2.md) - **consumption
cannot be counted by tool name** (a `Read`-only scan of an artifact that is also edited, searched or opened
through the shell watches the smallest channel; the reference figure moved from 42% to 3.8% once every
channel was counted) and **a size-tier command ladder written as prose does not route anything** (434
invocations, the cheapest tier chosen 0 times; the remedy is an advisory `UserPromptSubmit` nudge, kept
always-exit-0, with no saving claimed yet). The staleness ladder's "re-read only the changed rule docs" path
applies, no full re-adoption was run, and nothing in `rules/` touched packaging, release, channels or layout.

Finding 2 has a target here - `/quick` and `/fix` sit among ten commands - and the repo has no
`.claude/settings.json` at all, so a routing nudge would be the first hook it ever carries. That is the
cheapest possible place to try the shape and also the place where a false fire would be most visible, which
is why the canon's always-exit-0 clause is the part to copy first. Carried as an owner decision, not applied
from this session.

Verification: `check-compliance: OneClickRunner - 0 error(s), 2 warning(s) (overlay A, canon 2026.08.05)` -
warnings are pre-existing and none was introduced here.

## Canon re-sync 2026-09-03 - two updates owed, an uncommitted one recovered, and the gate cleared

Run from the canon repo against `P:\WINDOWS\OneClickRunner` (`check-compliance.ps1 -RepoRoot`).

**The stamp was two things at once.** Committed, it read `2026.07.27`; the working tree carried an
**uncommitted** bump to `2026.08.18.1` that had been sitting there since 2026-08-18 - which is why this
record stops at 2026-08-05 while the repo behaved as if re-synced. That edit was folded into this pass
rather than reverted, so the history now shows the move to `2026.09.03.3` in one commit with a record
behind it.

**Reconciled against `Canon update 2026-08-28`** (AI_USAGE, DEVELOPMENT, DOCUMENTATION_CONCEPT,
INVARIANTS, TESTING_AND_QA; the 2026-09-03 canon movement is `tools/harness/` and moves no digest). Three
of the five describe machinery this repo does not run - no lock queue, no headless batch driver, no
closure facade. The locale rule is a relaxation and this repo is monolingual, so it cannot bind. The
fifth, TESTING_AND_QA's **"a check only a human can run has not happened yet"**, lands squarely on
`PLAN/` - and finds it already compliant, which is worth recording rather than assuming: the lifecycle
is `Draft -> Approved -> Tactical -> In Progress -> Implemented -> Verified`, `Implemented` **is** the
awaiting-verification status the rule demands a done-set include, and `PLAN/INDEX.md` states outright
that 23 tickets sit at `Implemented` with the interactive `/verify` pass still owed while only T0024 is
`Verified`. That is exactly the honesty the new rule asks for, written before the rule existed.

**Drift closed in this pass (SZA-SURF02, both site pages).** `docs/index.html` and `docs/guide.html`
carried `canonical`, `og:title`, `og:description`, `og:image` and `twitter:card` but no `og:url` and no
JSON-LD. Added: `og:url` on each, a `SoftwareApplication` block on the landing page and a `TechArticle`
block on the guide, every field taken from what the page already asserts - no `downloadUrl`, because this
repo's distribution is a portable zip on the Release page and inventing a URL for it is exactly the kind
of stamp-fiction the skill forbids. Both blocks were parsed with `ConvertFrom-Json` before committing.

**Evidence.** `check-compliance.ps1 -RepoRoot P:/WINDOWS/OneClickRunner` before -> `0 error(s), 3
warning(s)`; after -> **`0 error(s), 0 warning(s)`**, exit 0.

## Re-sync owed 2026-10-02 - stamp 2026.09.06.1 against canon 2026.09.30.1; one real finding

Read-only pass over `P:\WINDOWS\OneClickRunner` (overlay A, 0 commits since 2026-09-06) with
`check-compliance.ps1` on the working tree. Re-measured 2026-10-02: `0 error(s), 1 warning(s)`, the warning being
`SZA-CANON03`. The stamp (`2026.09.06.1`, `adoptedOn` 2026-08-18) is **committed**; `git diff -- .sza-canon.json`
is empty, so there is no uncommitted bump. This record's last entry is 2026-09-03 (the 09-06 version move was a
re-stamp only). **No re-sync was run; nothing in the repo was edited.**

### The dirty tree and the verdict

Two entries, docs-only: `CLAUDE.md` (+3 / -1: the line "Cross-project contracts live outside this repository .."
naming the catalog, and the scenario-storage bullet tagged `SCENARIO-FILE`) and the untracked `docs/contracts/`
(a README, the `SCENARIO-FILE` pointer with its declared owner and three open debts, and an `INSTALL-TRUST`
pointer with its gap declared). It is an **unfinished contract-sync run of 2026-09-23**: the README's "Bound, not
yet aligned" table still owes `APP-BEHAVIOUR` / `APP-STYLE`, `PAGE-CONTENT` / `PAGE-STYLE` / `SITE-FAMILY-MAP` and
`REPO-STAMP`.

**Safe to commit: yes**, as one docs-only commit after `check-compliance` (0 errors with it), and best done
together with the re-sync so the record exists. Per the canon, committing is on the owner's request.

### What a re-sync must reconcile

- **The real finding: an INVARIANT 4/5 gap.** `release.ps1` tags, pushes and runs `gh release create` by default
  (`-DryRun` is opt-in), with no preflight verdict, no tests and no version-naming PASS. There is no test suite
  (`PLAN/INDEX.md`: 23 tickets `Implemented`, only T0024 `Verified`). Under the reworded INVARIANT 5 a missing
  verdict must stop the ship step; FastMediaSorter_Lite's `Release.ps1` (dry-run default, `-Push`, a bare-PASS
  gate) is the pattern to follow.
- **Contracts:** finish the alignment above and add the catalog registry rows; the `INSTALL-TRUST` exception is
  dated but its ticket is "proposed, not yet opened".
- **DOCUMENTATION_CONCEPT §6:** the site is `docs/` (index, guide, privacy), so both the mandatory half and the site
  half apply (the page declares its address, the sitemap is generated).
- **SECURITY_AND_PRIVACY §7:** the permission row is the per-scenario "Run as Administrator" elevation (nothing
  elevates on its own); the network inventory is empty with a date and a reason, but the privacy page's "no network
  calls of its own" must stay true while scenarios can launch yt-dlp (`SPECIAL_YTDLP`), and the row must say so.
- **SUPPORT_AND_FEEDBACK §7:** `activity.log` is local-only and counts nothing.
- **Stale kit copies:** `doc/` holds hand copies of kit documents - `VALIDATION` 132 lines against the kit's 331
  (211 differing lines), `COST` 83 against 294, and no four-answers text. **Proposed 2026-10-02:** a repo that
  copies kit documents stamps each copy with the kit date or version so the re-sync can compare it (medium-low
  confidence; `SZA-CANON05` looks only at canon document names).
- **Stamp:** refresh `adoptedOn`.

## Promotion campaign (2026-10-09)

- Ticket `PLAN/T0028_free-promotion-campaign.md` (new), positioning through T0026; [PROMOTION](../../PROMOTION.md).
- 2026-11-07, site audit: 3 HIGH, 23 MED (of 77 findings) recorded in ticket T0028 (Draft); the 2026-11-03 baseline re-measured: 9 open, 1 partial, 0 fixed, the console half of row 1 not re-measured; criterion 14 added.

## In-app help (2026-10-16)

- Ticket `PLAN/T0029_in-app-help.md` (Draft, row in `PLAN/INDEX.md`), created by the canon session from the owner's request for F1 and a `?` button in every product ([UI_UX](../../UI_UX.md) §7, contract `CONTEXT-HELP` 0.1). Four windows and a tray menu; the site guide carries web fonts and script language switching, so it is not reusable as a help page as it stands; how pages ship with a single-exe package is an owner question (T0024).

## Canon delivery reconciliation 2026-10-17 (S4307)

- Installed plugin `2026.1017.1` from published canon `2026.10.17.1` (`d06a64a`). The harness counts Done and Skipped as finished and preserves the phase-counter suffix.
- Re-read the changed canon guidance for delivery, documentation, localization, layout and sealed contracts. Existing product implementation and contract catch-up work remains owned by the recorded project tickets; this delivery check does not certify every product contract.
- Re-stamped through `restamp-canon.ps1` against the installed plugin reader: version, freshly computed core digest and reconciledOn move together; adoptedOn and project-specific fields stay unchanged.
- Compliance for OneClickRunner: 0 error(s), 1 warning(s) before; 0 error(s), 0 warning(s) after; exit 0. Canon freshness findings cleared.

## Test lab report (2026-10-23)

- Ticket `PLAN/T0032_test-lab-report.md` (Draft, not queued), created by the canon session from the owner's order of 2026-10-23 to collect what every project knows about its hardware, emulators and test practice (contract `TEST-LAB` 0.1, draft). Documentation only: the product files one inventory report and a pointer; no code, test or harness changes. Reports to the Windows profile owner (FMS_Win).

## Fast checks between releases (2026-10-29)

- Ticket `PLAN/T0033_fast-checks-only-between-releases.md` (Approved, first in `PLAN/INDEX.md` and `PLAN/README.md`; this repo has no release queue file), created by the canon session from the owner's order of 2026-10-29 to switch off full builds and tests longer than 5 s between releases (canon TESTING_AND_QA section 2, highest priority). The product has no tests and no CI, so it inventories the between-release builds (`build.ps1`, `dotnet build -c Release` in `CLAUDE.md`, `/verify --build`, the build rungs of `/spec-dev` and `/spec-tech`), names a fast command or a static fast tier, and keeps the full build on the release path (`release.ps1`).

## Canon re-sync 2026-11-14 (T0025)

- Ticket `PLAN/T0025_canon-contracts-sync-notice.md` (the 2026-10-02 synchronisation notice, Approved this date with owner inputs D1-D3): stamp moved 2026.10.17.1 -> 2026.11.13.8, digest recomputed (`sha256:75bd013b..`), reconciledOn 2026-11-14; adoptedOn unchanged.
- Compliance: before 5 error(s) / 5 warning(s); after 0 / 0 expected run recorded in the ticket - the 5 SZA-STYLE01 metadata em-dashes fixed to the plain hyphen in five pages, SZA-SEC05 closed by a `.gitignore` negation for the tracked gate `scripts/check-theme-tokens.ps1`, the three SZA-VER04 landing findings answered by a recorded stamp exemption (the release links are `data-release-href` markers rendered from the release manifest, PAGE-STYLE 3.10), SZA-CANON03 cleared by the stamp.
- `UI_UX.md` read against the product: holds through the T0029 (CONTEXT-HELP), T0030 (sizing tokens, buttons, profile, a11y gate), T0026+T0040 (kit, full-width) adoptions; the two recorded variances stand (single-window migration debt until T0030 phase 3; no compact-mode selector, the approved variant in `doc/UI_PROFILE.md`).
- Day 0 of the task flow completed: the ledger and profile stood since 2026-10-29, the launchers did not - `init-task-flow.ps1` wrote `r0`-`r3`, `rs`, `rm`, `rw`, `tools/harness.ps1`, the release-queue trio under `PLAN/` and the ticket template; `spec_catalog/validate` 10 OK / 0 WARN / 0 FAIL; `r0 -DryRun` prints the order (the `claude` CLI must be on PATH); `pq register` already-registered; the spec commands registered (wrote 3, unchanged 5). The T0033 note "this repo has no release queue file" is superseded.
- `contract-sync` ran in the same pass (the canon's CONTRACTS.md moved, so the re-sync includes it): SCENARIO-FILE 0.13 (reader carrier refusal + one-message import, item E tie-breaks, item D Id persistence, the owner's current-shape vector in `vectors/`; rule-9 count ticket T0051 opened; the carrier exception closed), APP-ACTIVATION adopted 0.14 (frozen anchors declared), APP-BEHAVIOUR adopted 0.14 (twelve moments read against the source, pointer written), the site declared against PAGE-CONTENT 1.5 / PAGE-STYLE 3.10 / SITE-FAMILY-MAP 1.12 (rows written; the footer grid corrected to the map's canonical rows on all sixteen pages). `contract-lag.ps1 -Product OneClickRunner`: 14 rows, 0 pending, 0 unparsed.
- Release safety (owner decision D1): `release.ps1` now runs `scripts/preflight.ps1` - one CHECK-VERDICT aggregator over all nine gates - before staging anything; the ship step (tag / push / `gh release create`) runs only on a passing verdict.

## Record split 2026-11-18 (canon ticket S0120)

Every section of this file dated before this one was moved here verbatim from [../oneclickrunner.md](../oneclickrunner.md) when the record was split into facts and history. A line number quoted inside such a section counts lines of the record as it was before the move; relative links were deepened by one `../`; nothing else changed.
