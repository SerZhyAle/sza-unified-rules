# History: filedo

## Candidate core edits - APPLIED 2026-07-23 (per owner "как правильно так и сделай")
Where each landed (some were already folded by the concurrent `FastMediaSorter_Lite` reconcile):
- Installer-as-a-role + WiX `UpgradeCode` anchor -> **APPLIED** PLATFORM_OVERLAYS Overlay A (publishing
  tree + fourth fact) + SECURITY_AND_PRIVACY §2.
- winget portable-in-zip -> **APPLIED** PLATFORM_OVERLAYS Overlay A "Distribution channels" (CHANNEL_MATRIX
  winget playbook already carried the `zip`+`portable` form).
- Committed-own-output exception -> **ALREADY FOLDED** in REPOSITORY_LAYOUT "Built binaries" (narrow
  negation + why-comment) by the concurrent reconcile.
- Separator-less version shape (`yyMMddHHmm`) -> **APPLIED** PLATFORM_OVERLAYS Overlay A version shape.
- Go/desktop release hardening -> **APPLIED** DEVELOPMENT §16 (new subsection; renumbered from §15 in the 2026-07-23 dedup pass).
- Destructive-action persona clause -> **APPLIED** TESTING_AND_QA §6.
- Zero-data privacy carve-out -> **APPLIED** DOCUMENTATION_CONCEPT §4 + SECURITY_AND_PRIVACY §5.
- winget CRLF gate -> **ALREADY FOLDED** in CHANNEL_MATRIX winget playbook; Actions-disabled/tag-no-op trap
  -> **APPLIED** CHANNEL_MATRIX GitHub Release playbook.
- `/docs` as a Pages source -> **APPLIED** PLATFORM_OVERLAYS Overlay A "Site" + SITE_CONFIGURATION §1;
  one-ISO-code-per-language-across-every-surface -> **APPLIED** LOCALIZATION §3.
- Co-shipped-companion vocabulary -> **ALREADY FOLDED** in PLATFORM_OVERLAYS "Co-shipping shapes" (names
  FileDO's GUI directly); the compile-time-parity variant is DEVELOPMENT §13.

Original proposals (kept as the record):
- **PLATFORM_OVERLAYS.md Overlay A (source-root/publishing tree + fourth fact) & SECURITY_AND_PRIVACY.md
  §2**: name the installer by **role**, not tool - "Inno Setup `.iss` **or** WiX MSI (`.wxs`)"; list the
  MSI **`UpgradeCode` GUID** (+ ARP/PATH/shortcut) as an accepted frozen anchor alongside Inno `AppId`.
  Prevents a valid WiX-based desktop app reading as non-compliant (evidence: `packaging/wix/FileDO.wxs`).
- **PLATFORM_OVERLAYS.md Overlay A "Distribution channels" + CHANNEL_MATRIX.md winget playbook**: note
  winget may ship a **portable-in-zip** (`InstallerType: zip` / `NestedInstallerType: portable`, N
  `PortableCommandAlias`) - the release zip doubles as the winget artifact for a multi-exe CLI; no
  separate installer manifest. Prevents forcing a setup.exe where a portable CLI needs none (evidence:
  `installer.yaml:6-18`).
- **REPOSITORY_LAYOUT.md "Built binaries & artifacts"**: add a second exception - a repo **may
  deliberately track its own build output** (a committed dev-distribution set) if `.gitignore` declares
  it with a why-comment; the authoritative release is still the release-host asset, never this copy.
  Prevents a cleanup deleting shipped files and a reviewer flagging intent as a leak (evidence:
  `.gitignore:7-9`).
- **PLATFORM_OVERLAYS.md version shape**: broaden the padding note - the authoritative stamp may also be
  **separator-less** (`yyMMddHHmm`, a sortable integer); separators are a free choice as long as the form
  is monotonic, sortable, and frozen once. Prevents a third real shape reading as a divergence (evidence:
  `build.ps1:50`).
- **DEVELOPMENT.md (new short subsection, Go/desktop release hardening)**: keep debug symbols (avoid
  `-s -w`) to reduce AV false-positives, `-trimpath`, `CGO_ENABLED=0`, embed PE versioninfo/manifest; for
  a multi-module repo list every `go.sum` in the CI cache key. Prevents a false-positive AV flag and
  silent cache misses (evidence: `release.yml:44-51,120-124`).
- **TESTING_AND_QA.md §6 (persona QA)**: add a **destructive-action clause** - for a tool whose core job
  destroys data, the happy-path pass condition inverts to "the confirmation fires and cannot be
  force-bypassed for dangerous targets". Prevents shipping a data-loss footgun that "passed" a
  zero-friction test (evidence: `README.md:27-31`, `docs/spec-safety-speed-improvements.md` §1).
- **DOCUMENTATION_CONCEPT.md §4-5 (privacy)**: carve out that a **zero-data-collection local tool with no
  site** may use the Store's own data declaration + listing copy + in-app text as the privacy source of
  truth; no hosted `privacy.html` is required, but the promise must still be stated in the listing and
  app. Prevents demanding an empty page that renders nothing (evidence: `msix/store-listing.md`).
- **CHANNEL_MATRIX.md winget playbook**: add the **CRLF line-ending** requirement (winget-pkgs rejects
  LF/mixed) and edit-in-place method; add a GitHub-Actions note that a **malformed/0-byte workflow
  disables Actions** and a tag push then silently no-ops. Prevents two real, hard-to-diagnose release
  failures (evidence: `docs/how-i-posted-this-project-to-winget.md`).
- **SITE_CONFIGURATION.md §1 + PLATFORM_OVERLAYS.md Overlay A "Site"**: record **`/docs` as an accepted
  Pages source** (with `.nojekyll` for hand-authored static), not only repo root. Prevents a docs-served
  site reading as "unpublished staging" (evidence: `docs/.nojekyll`, no root `index.html`).
- **LOCALIZATION.md §3**: strengthen to **one ISO code per language across every surface** (README, site,
  UI), not just site-wide. Prevents the `ua`-in-README vs `uk`-in-GUI split (evidence: `README.ua.md`,
  `Localization.vb`).

## Open questions - RESOLVED 2026-07-23 (by owner instruction)
- **Privacy page** -> **RESOLVED into the core.** DOCUMENTATION_CONCEPT §4 + SECURITY_AND_PRIVACY §5 now
  carry a zero-data carve-out: a no-network, no-telemetry local tool with no site may use the store's data
  declaration + listing copy + in-app text as the privacy source of truth; no hosted `privacy.html`
  required. FileDO is compliant as-is.
- **Naming the co-shipped GUI** -> **RESOLVED into the core** (by the concurrent reconcile).
  PLATFORM_OVERLAYS "Co-shipping shapes" names it a **co-shipped companion binary** (one release, one tag,
  a sibling program - not a flavor, not an edition) and cites FileDO's GUI directly.
- **Committed `exe_to_download/`** -> **RESOLVED at the rules level.** REPOSITORY_LAYOUT "Built binaries"
  now permits deliberately committing a repo's own build output under a narrow `.gitignore` negation with a
  why-comment (FileDO satisfies this). Whether to *keep* the set now that CI rebuilds from source is a
  project-cleanup decision, no longer a compliance question - **owner's call, not a rules gap.**
- **Localized changelog** -> **left as a project choice, not folded.** The canon stays: LOCALIZATION §1
  keeps ledgers English; DOCUMENTATION_CONCEPT §2 accepts a curated public "What's new". FileDO's
  git-log-derived, per-README **localized** "Version History" is a project-specific variant that does not
  generalize, so it was **not** promoted to the core - **owner decides** whether FileDO keeps it or moves
  to one English source rendered per locale (evidence: `.claude/skills/release/SKILL.md:38-53`).

## Spread-back applied 2026-07-23
Ran `SPREAD_BACK_PROMPT.md` in `P:\WINDOWS\FileDO` (existing repo; this contrib read first).

**What changed (in the repo).** Rewrote the single agent-rules file `AGENTS.md` to the **reference**
consumption model:
- Added the canon pointer (`P:\WEB\sites.google.comsiteszaodua\Unified_Rules`, read order, and a link to
  this contrib record as the per-project source of overlay facts + divergences).
- Added a condensed **overlay-facts** block (source root / multi-module / version shape `yyMMddHHmm` /
  release-mechanics siblings / frozen anchors) verified live: WiX `UpgradeCode
  4d6b3b1f-...-8e3b2c5a7d91`, winget `PackageIdentifier SerZhyAle.FileDO`, 5 `PortableCommandAlias`, Go
  1.24.4/1.21 across 4 `go.mod`.
- Stripped restated universal Go conventions (tabs/mixedCaps/lowerCamelCase/file-naming prose) down to
  "Go defaults via gofmt" + the repo-specific `*_windows.go`/`*_unsupported.go` split.
- Recorded the two live divergences inline (AGENTS.md-only, no CLAUDE.md; `.claude/skills/` git-ignored)
  and pointed universal git discipline at canon `GITHUB_INTERACTION.md`.

**Verification (evidence, fresh run 2026-07-23).**
- `go build -o filedo.exe .\cmd\filedo` -> exit **0**.
- Scoped gate `go test ./...` in `cmd/filedo-test` -> **ok** (exit 0, no tests to run).
- Known-red confirmed: root `go test ./...` -> exit **1**, `FAIL filedo/cmd/filedo [build failed]`
  (non-constant format string in `damaged_disk_handler.go`, `fmt.Sprintf %T` arg mismatch in `main.go`).
  The gate's smoke path is `filedo.exe -?` matching the stamped version (`build.ps1:141-149`).
- Working tree after the doc edit: only `AGENTS.md` modified (root `filedo.exe` is git-ignored).

**Questions closed.** The localized-changelog decision -> owner chose **migrate to one English source,
rendered per locale**. Not executed this session; it is a scheduled repo follow-up (rework the `/release`
skill's "Version History" generation + the per-language READMEs). Until then FileDO still emits localized
`Version History` (a temporary, now-owned divergence, not a permanent one).

**What remains.**
- Execute the changelog migration above (separate FileDO session).
- Pre-existing repo debt, out of spread-back scope: root `go test ./...` fmt/vet failures; 0-byte
  `.github/ISSUE_TEMPLATE/*` + `pull_request_template.md`.

**Canon edits still needed (NOT committed from the repo session - owner to apply in a canon session):**
- Mark FileDO's **Done** column in `SPREAD_BACK_PROMPT.md` after this repo's spread-back commit lands.
- No new rule fixes: every candidate core edit from this contrib was already APPLIED on 2026-07-23, and the
  changelog decision conforms FileDO to the existing canon (LOCALIZATION §1) rather than changing it.

## Canon adoption 2026-07-27

Adopted as the `sza` plugin (consumption model **reference**). `.sza-canon.json`: overlay C, co-shipped
companion, separator-less `yyMMddHHmm` tag, ledger shape 4 verified against `generate_release_notes` in the
release workflow, four channels.

**Scoped commit**: `.gitignore`, `docs/index.html` and the stamp. `AGENTS.md` and the untracked `CLAUDE.md`
carried in-flight work and were left alone.

**The one error left is the sharpest real finding in the portfolio**: FileDO ships to the Microsoft Store and
winget and has a live Pages site, so neither privacy carve-out applies - and it hosts no privacy page at all.
`msix/store-listing.md` still carries it as an unfulfilled TODO. This is a store-rejection risk and needs
content, not an edit.

## Canon reconcile 2026-08-02 - agent-process propagation

Canon **2026.07.27 -> 2026.08.02**, core digest `sha256:dae220bf..` -> `sha256:6c247452..`. Stamp
updated; the adoption model is unchanged. The upstream change is [AI_USAGE.md](../../AI_USAGE.md) only -
the agent-process findings propagated from FastMediaSorter mob_v2 under its ticket S1342 - so the
staleness ladder's "re-read only the changed rule docs" path applies and no full re-adoption was run.
Nothing in `rules/` touched packaging, release, channels or layout, and no divergence was found
between the new bullets and this repo's own rules file.

No agent memory and no competing agent-behaviour text in either rules file, so this is a pure stamp
move. §2's closure invariants are the live ones: this repo's release path is a single one-way
operation, and "PASS only when every gate passed" is exactly the property that path needs.

Verification: `check-compliance: FileDo - 0 error(s), 4 warning(s) (overlay C, canon 2026.08.02)` - warnings are pre-existing and none was introduced here.

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

No command surface here - two skills, no `.claude/commands/`, no hooks - so finding 2 has no local target
and nothing is owed. Finding 1 is method, not packaging or release, so it changes nothing in this repo's
shape either; it applies the next time anything here is called unused.

Verification: `check-compliance: FileDo - 0 error(s), 4 warning(s) (overlay C, canon 2026.08.05)` -
warnings are pre-existing and none was introduced here.

## Canon reconcile 2026-08-18 - the stale-cache catch-up

Canon **2026.07.27 -> 2026.08.18.1**, core digest `sha256:dae220bf..` -> `sha256:961c9c8a..`, recomputed
here rather than copied (`check-compliance.ps1 -PrintDigest`). Consumption model unchanged (**reference**).

**Why this is a four-update jump and not a one-step move.** The `sza` plugin served a cached
**2026.07.27** build for three weeks, so the 08-02, 08-05, 08-08 and 08-18 canon updates never reached a
session in this repo. The plugin is now **2026.818.1**.

**The record contradicted the repo, and the repo won.** The two sections above - *Canon reconcile
2026-08-02* and *Canon reconcile 2026-08-05* - both state "Stamp updated". **The stamp was never updated.**
`git log --follow -- .sza-canon.json` in `P:\WINDOWS\FileDo` returns exactly two commits, `697508d` and
`0460b6a`, both dated 2026-07-27, both carrying `"version": "2026.07.27"`. Those two reconciles were
recorded in the canon repo and never landed in the consumer repo, and this record asserted a repo-side fact
that the repo contradicted for a fortnight. Working-tree-is-truth applies to this file too: **a reconcile
section should cite the consumer-repo commit that carried the stamp**, and one that cannot is a claim, not
a record.

**Re-read and reconciled** - only the docs whose content moved since 2026.07.27:

- **[AI_USAGE.md](../../AI_USAGE.md) section 1 - fire-and-forget is now forbidden**, with the threshold set at
  the harness's foreground timeout. Live target here: the `/build` skill drives `build.ps1 -Test`, which is
  a gate, and a backgrounded gate reports its wrapper's exit code. The skill now says so and requires the
  foreground. Every gate run for this reconcile was foreground.
- **[AI_USAGE.md](../../AI_USAGE.md) section 2 - the three closure invariants.** This is where the repo
  genuinely diverged. `build.ps1 -Test` satisfied invariants 1 and 2 - the verdict covers all four binaries,
  and `Test gate passed.` prints only after both checks - but **failed invariant 3**: a missing Go toolchain
  or a missing artifact was reported as exit 1, indistinguishable from a real defect, and `go test` output
  went to `Out-Null` so a failure was undiagnosable. Fixed: **exit 2 = "could not verify", exit 1 = "found a
  defect"**, the toolchain check moved **ahead of the builds** (DEVELOPMENT section 10 - environment before
  work, not after; inside the gate it would have been dead code, since a missing Go surfaces as build errors
  first), and failing test output is now printed. `release.ps1:95` tests `-ne 0`, so exit 2 still stops a
  release.
- **[AI_USAGE.md](../../AI_USAGE.md) section 5 - the canon ships its hooks; do not rebuild them per project.**
  `.claude/settings.json` in this repo carries a single `permissions.allow` entry and **no hook
  registrations**, so there is nothing repo-side to disarm. Recorded in `AGENTS.md` so a later session does
  not hand-wire a local copy. The hook family is demonstrably live: the plugin's `guard-bash` blocked an
  unbounded directory scan during this session. **But see the machine-level duplication below** - the rule
  has a live violation, just not in this repository.
- **[DEVELOPMENT.md](../../DEVELOPMENT.md) section 15 - caching the expensive gate's CLEAN verdict.**
  **Not applicable, and recorded rather than skipped silently.** The rule targets a static-analysis gate that
  was 86% of gate wall time; FileDO's gate is a compile plus a smoke-run, about a minute wall clock including
  the GUI MSBuild step, with no serialisation lock to queue behind. A fingerprint cache here would save
  nothing. The section's other half did apply - "verify which path is actually used" - see the console-text
  defect below.
- **[GITHUB_INTERACTION.md](../../GITHUB_INTERACTION.md) section 6 - the Bash/tooling family.** The
  highest-value section for this repo, whose two entry points are both `.ps1`. `AGENTS.md` now states the
  `pwsh -NoProfile -File` routing for a Bash caller instead of only the bare `.\build.ps1` form, without
  restating the rule the hook already enforces. "Every tool call gets a fresh interpreter" needed no repo
  change - nothing here depends on shell state surviving a call.
- **[INVARIANTS.md](../../INVARIANTS.md) - unchanged since adoption.** `git log 7dd3dde..HEAD` returns nothing
  for it. The plugin-cache copy and the canon-repo copy differ by byte only because the cache ships **CRLF**
  and the repo **LF**; content-identical after `tr -d '\r'`. Worth knowing before anyone builds a byte
  comparison between the two trees.

**A defect the reconcile surfaced on its own.** `build.ps1` printed `go test ./cmd/filedo-test ...` while
actually running `Push-Location cmd\filedo-test; go test ./...`. The printed form **cannot work** - that
directory is its own module, so from the root it fails with *main module (filedo) does not contain package*
- and `AGENTS.md` had documented the trap for months while the script kept advertising the broken form on
every green run. The `/build` skill had copied the broken form from that console line. Both fixed; the
script now prints the command it runs.

**Agent-rules trim.** `AGENTS.md` lost the restatements that have exactly one home in the canon: commit
language, message shape, the co-author trailer, and the evidence rule - the whole `## Commit & PR` section
collapsed to the two genuine deltas (verification output in the body, screenshots for GUI/installer/docs).
The build/release wall was rewritten from a restated universal ("HARD RULE: never creates a tag") into the
checkable repo fact - `build.ps1` contains no `git tag` call at all, `release.ps1` holds it at lines 130-131
- and carries a `canon-ok` marker for the part that still reads like a restatement. `CLAUDE.md` was itself
violating this repo's own recorded divergence: it is meant to be a bare pointer and had grown a duplicate of
the tag rule and the testing-gate delta. Now a true pointer. Every kept claim was re-verified against the
tree; the tag regex `^v\d{10}$` is confirmed at `release.ps1:77`.

**Closed from the 2026-07-27 section.** "It hosts no privacy page at all", called the sharpest real finding
in the portfolio, is **resolved**: `docs/privacy.html` landed in `0460b6a` on 2026-07-27 and
`msix/store-listing.md` now carries the live URL instead of a TODO. The gate has reported 0 errors since.

**Warnings: 4 -> 0.** All four were real and all four are fixed, not exempted. `docs/README.md` now indexes
the tree and separates the site from the unlinked repo documents; `docs/robots.txt` and `docs/sitemap.xml`
were added, the sitemap listing the **6 canonical pages only** - the `ru/ua/de/fr` index files are redirect
stubs that canonicalise to the root, and listing a non-canonical redirect is what makes a sitemap lie;
`docs/index.html` gained a JSON-LD `SoftwareApplication` block modelled on the one `docs/privacy.html`
already carried. `docs/` has **no generator**, so these are edits in place and not render-target violations
(invariant 16) - confirmed by grep, not assumed.

**Verification** - fresh runs, this session:

- `pwsh -File tools/check-compliance.ps1` - baseline `0 error(s), 4 warning(s)`, final
  `0 error(s), 0 warning(s) (overlay C, canon 2026.08.18.1)`, exit **0**.
- `.\build.ps1 -Test` - exit **0**, `Test gate passed.` Run twice: once before the environment-check move,
  once after.
- `pwsh -NoProfile -Command "$env:PATH='C:\Windows\System32'; & build.ps1 -Test"` - exit **2**,
  `Cannot verify: 'go' is not on PATH - nothing was built or checked.` The new exit code is proven by
  driving it, not by reading it.
- The gate runs restamped the tracked binaries in `exe_to_download/`; restored with
  `git checkout -- exe_to_download/` so the commit carries only the intended change.

**Carried forward, not closed:**

- `.sza-canon.json` `site.pages` lists `index.html` and `privacy.html` while Pages serves **6** canonical
  pages - the four `guides/` pages are absent. Left alone this pass because the owner declared the stamp
  correct and off-limits; it wants a decision on whether `pages` is meant to be exhaustive or indicative.
- The in-repo skills under `.claude/skills/` are git-ignored, so this session's `/build` skill fix is
  **local-only and cannot be committed**. Every machine has its own copy and none of the others got this
  fix. The divergence is now explicit in `AGENTS.md`, but the underlying problem - a corrected skill that
  cannot travel - is unresolved.
- **Machine-level hook duplication, owner decision, not applied.** `~/.claude/hooks/` holds a complete
  hand-wired copy of the canon family - `guard-find-command.ps1`, `guard-ps1-in-bash.ps1`,
  `guard-bash-unavailable-command.ps1`, `guard-fire-and-forget.ps1`, `guard-uncapped-read.ps1`,
  `warn-context-size.ps1` - registered in the user-level `settings.json` and running **alongside** the
  plugin's own. AI_USAGE section 5's precondition for removing them is satisfied and was checked, not
  assumed: the installed cache at `sza/2026.818.1/hooks/` really does carry `guard-bash.ps1` (the five
  Bash gates batched behind one pre-filter), `guard-fire-and-forget.ps1` and `guard-uncapped-read.ps1`.
  Both families fired in this session. This is outside the repository, so it is reported rather than
  changed.

**Canon fixes needed - NOT applied from this session:**

1. **The staleness ladder cannot detect its own staleness.** A consumer reading a stale plugin cache
   computes a digest that matches its own stamp and reports a clean bill of health - exactly what happened
   here for three weeks across four canon updates. The ladder compares the stamp against the *installed*
   canon, never against the *published* one. Consider having `check-compliance` surface the plugin build it
   read, so "healthy" and "healthy but three weeks behind" stop looking identical.
2. **A reconcile section in `contrib/` should cite the consumer-repo commit that carried the stamp.** The
   08-02 and 08-05 sections here asserted a stamp move that never happened, and nothing caught it because
   the record is prose. Same "a claim is not a record" shape the canon already applies to gates.
3. **The hook pre-filters match prose, not command position.** Both the plugin's batched pre-filter and the
   hand-wired one test the raw payload for a bare substring, so a heredoc that merely *discusses* a
   directory scan is blocked as though it were one - it happened twice while writing this very section, and
   the canon's own guidance is that a pre-filter "may only skip calls the real check would have allowed",
   which says nothing about the false-positive direction. Anchoring on command-head position would cost
   nothing and remove a class of dead turns.
4. Minor: the plugin cache ships **CRLF** and the canon repo **LF**, so a naive byte comparison between the
   two trees reports every rule doc as differing. Worth one line wherever the two are compared.

## Canon re-sync 2026-09-03 - clean, no deltas disturbed

Run from the canon repo against `P:\WINDOWS\FileDo` (`check-compliance.ps1 -RepoRoot`).

**What had to be re-read.** The stamp was at `2026.08.18.1` / digest `961c9c8a`, so the rule-doc changes owed
were those of `Canon update 2026-08-28`: AI_USAGE, DEVELOPMENT, DOCUMENTATION_CONCEPT, INVARIANTS,
TESTING_AND_QA. Today's canon movement is `tools/harness/` only - it bumps the plugin version and no digest.

**Reconciled: no change owed.** Four of the five additions are process machinery this repo does not run - the
headless batch driver, the (kind, domain) lock split with its all-or-nothing multi-domain take, the mandatory
withdrawal of an abandoned queue ticket, and the closure facade obliged to run the artifact-class rung. FileDo
has no lock queue, no ticket store and no closure facade; its gates are the Go build and its test suite, which
are per-change by nature and correctly placed under the new gate-placement test. The fifth is the locale
relaxation (INVARIANT 17), which only widens what is allowed - the five READMEs already move together.

**Evidence.** `check-compliance.ps1 -RepoRoot P:/WINDOWS/FileDo` before -> `0 error(s), 1 warning(s)`, after ->
**`0 error(s), 0 warning(s)`**, exit 0 (overlay C). The cleared warning was SZA-CANON03.

## Canon re-sync 2026-09-24 - rule-adoption contracts, and the 2026-09-06 move accounted for

Run from the FileDO session (its spec SP-0018 T1) against the installed plugin `2026.922.2`, resolved from
`installed_plugins.json`. The canon home's `2026.09.23.1` sits on an unpublished branch;
`claude plugin update` reported `2026.922.2` as the latest, so that is what was reconciled.

**The 2026-09-06 move, which had no record.** FileDO commit `822e133` moved `canon.version` from
`2026.09.03.3` to `2026.09.06.1` and left `coreDigest` at `cdf49be6..`. That was correct: the canon change
of that day was hooks-only (the fire-and-forget guard's fast targets), and the cached `2026.906.1` rules
digest to `cdf49be6..` - recomputed, not assumed. It was a version-only catch-up, and this line is its
record.

**What had to be re-read** (`2026.906.1` -> `2026.922.2`): AI_USAGE, DEVELOPMENT, DOCUMENTATION_CONCEPT,
INVARIANTS, NEW_PROJECT_CHECKLIST, PLATFORM_OVERLAYS, RELEASE_AND_DISTRIBUTION, REPOSITORY_LAYOUT,
TESTING_AND_QA, and the new CONTRACTS.

**Reconciled, already held:** CONTRACTS sections 2-3 and INVARIANT 10 - FileDO names the catalog in one
place (`AGENTS.md`, "External contracts"), holds pointers and never copies under `docs/contracts/`, cites
by id. Pointers are spelled `<ID>.md`, which the catalog's 2026-09-23 correction to `REPO-LAYOUT` made
authoritative over the canon prose's `CONTRACT_*.md` (canon fix 1 below). This run added the missing
pointers `REPO-STAMP.md`, `REPO-LAYOUT.md`, `RULE-DELIVERY.md`, and FileDO's own registry rows for them.
The AI_USAGE, DEVELOPMENT and TESTING_AND_QA additions are measured lessons about machinery FileDO does
not run (prompt-submit routing hooks, profile overrides, device sweeps) - no change owed.

**Carried forward, open - owner: FileDO, next `/release` change:**
- INVARIANT 5 as reworded and RELEASE_AND_DISTRIBUTION section 2: the ship step must take a written
  PASS/FAIL verdict naming the version it judged as its input. FileDO's `release.ps1` already runs its
  gate inside the ship command (`build.ps1 -Test`, step 2, before the tag), so the gate cannot be skipped;
  what is missing is the written verdict artifact that names the version - today the input is an exit code.
- CONTRACTS section 6 / RELEASE_AND_DISTRIBUTION "Contract gate": nothing in the FileDO release path yet
  checks registry-row freshness or runs the catalog's vectors from the catalog's copy.

**Stamp.** `canon.version` `2026.09.22.2`, `coreDigest`
`sha256:13abcb8a7c2f0a354328bdd03c12e75ea361b6f8208134dc1ba3d1bd884e567d` (from `-PrintDigest`),
`adoptedOn` moved to `2026-09-24` as the 2026-08-18 re-sync did - this run re-read every changed
document. Which run should move `adoptedOn` is asked in the catalog proposal
`rule-adoption/PROPOSAL-2026-09-23-adoption-date.md`. Every other key, `$comment` included, unchanged.
Carried by a FileDO commit not yet made on this date - the next reconcile section should cite its hash.

**Evidence.** `check-compliance.ps1` at the FileDO root: before -> `0 error(s), 2 warning(s)`
(`SZA-CANON03`, `SZA-RULES05`); after -> **`0 error(s), 1 warning(s)`**, exit 0 (overlay C, canon
2026.09.22.2). The remaining warning is `SZA-RULES05`, `AGENTS.md` size only.

**Canon fixes needed - NOT applied from this session:**

1. CONTRACTS section 3, DOCUMENTATION_CONCEPT section 1, PLATFORM_OVERLAYS and REPOSITORY_LAYOUT still
   spell the pointer `docs/contracts/CONTRACT_<name>.md`; the catalog's `REPO-LAYOUT` rule 2 (corrected
   2026-09-23) says `<ID>.md`, which is what every repository holding pointers uses.
2. `check-compliance.ps1` `SZA-CTR01`: the id pattern does not match the house pointer header
   `| **Id** | ..` because of the bold markers, so pointers are recognised by length alone and one over
   40 lines would be reported as a copy.
3. Three contract questions filed in the catalog, not here: `PROPOSAL-2026-09-23-stamp-defaults.md`,
   `-adoption-date.md`, `-own-spec-scheme.md` under `rule-adoption/`.

## Canon re-sync owed 2026-10-02 - stamp 2026.09.22.2 behind canon 2026.09.30.1

Read-only mining of `P:\WINDOWS\FileDo` against canon `2026.09.30.1` (21 commits in 2026-09-20 .. 10-01, 12 of
them bodiless: "1", "2", "4", "Build v..", "Sync winget"; the real history lives in `AGENTS.md`, `RELEASE.md`
and the untracked `PLAN/` tree). **The re-sync itself has not been run**; this entry records what it must
reconcile so the next run starts from facts.

- **What to re-read** since the 2026-09-24 stamp (`2026.09.22.2`): CONTRACTS, DOCUMENTATION_CONCEPT,
  LOCALIZATION, PLATFORM_OVERLAYS, README, REPOSITORY_LAYOUT, SECURITY_AND_PRIVACY, SUPPORT_AND_FEEDBACK (the
  2026-09-23 update) and GITHUB_INTERACTION, INVARIANTS (the 2026-09-30 update, the "tree state is not the
  agent's concern" stance). Both of the 2026-09-30 files are about working-tree etiquette; nothing in the
  release path is touched.
- **Canon fix 1 of 2026-09-24 is applied** (the pointer spelled `<ID>.md`, REPOSITORY_LAYOUT line 57).
- **Canon fix 2 of 2026-09-24 (SZA-CTR01 and the bold `| **Id** |` header) is applied: fixed in the canon tool on
  2026-10-02.** The three CTR01 warnings this repo carried (`APP-BEHAVIOUR.md` 49 lines, `CLI-EVENT-STREAM.md` 42,
  `ICON-SET.md` 55) were the check misreading the house header, not drift; `ICON-RENDER.md` at exactly 40 lines
  had escaped by one line. Measured on 2026-10-02 after the fix: `0 error(s), 3 warning(s)` (was `0 error(s),
  6 warning(s)` before): `SZA-CANON03` (stale stamp), `SZA-CTR02` and `SZA-RULES05`.
- **SZA-CTR02, `cmd/filedo/vdisk_surfaces_test.go` line 275** is a negative assertion that fails if a README links
  into the catalog, and it spells the banned string `P:\Contracts` literally, so the check cannot tell the test
  from a leak. Repo-side fix: replace the literal with a regular expression for "a drive-letter path to a
  Contracts folder, or a catalog folder-qualified contract file" (`regexp` is already imported); the assertion
  becomes stricter and `git grep -F` stops matching. A canon-side skip for `canon-ok:` lines was considered and
  **rejected** (not mechanically decidable for arbitrary `_test` files). Still open in the repo.
- **SZA-RULES05 stays informational** until the AGENTS.md question below is answered.
- **The three pointers are not drifted in version** (APP-BEHAVIOUR 0.10, CLI-EVENT-STREAM 0.11, ICON-SET 0.16
  all equal the registry) but two have text drift: `APP-BEHAVIOUR.md` rule 4 says "No network code" while the
  same file's Status and the dated registry exception (loopback block server, until 2026-12-31) record that the
  mount path listens on 127.0.0.1, and its rule 6 names `filedo_win.log` while the shell now writes
  `filedo_win.session-*.log`; `ICON-SET.md` lines 40-55 are a history paragraph that stops at the 0.14 meanings
  although 0.16 added `content.disk-container`, and it cites SP-0016, an untracked PLAN id. All three
  paraphrase the catalog's rules, which is not a pointer's job. Target 25-35 lines each: header table, "what this
  repository must do" as obligations each held by a named test or selftest row, exceptions left to the registry.
- **What the dirty tree is** (88 modified, 33 untracked, 121 entries): the preflight remediation for the next
  release plus new features - the Go toolchain pin 1.26.1 -> 1.26.8, `.gitattributes` `-text` for vdisk and event
  fixtures, a new WACK verdict parser `msix/wack-verdict.ps1`, rebuilt `exe_to_download/*.exe`, 25 refreshed MSIX
  screenshots, settings / tray / autostart / Disk Manager work, a new `fmsworker/` and `contracts/` and
  `vdisk_share.go` (SP-0121 FMS share integration), and the `INPUT-PARITY.md` / `DIAGNOSTIC-REPORT.md` pointer
  changes. Not judged safe to commit as one unit by this entry; committing is the owner's call.

## Carried-forward items of 2026-09-24 - status 2026-10-02

- **INVARIANT 5 verdict artifact: substantially met, owner to confirm closure.** The gate's last line
  `build-gate <stamp>: PASS` names the version, `release.ps1` runs the gate before the tag, and since `c565277`
  (2026-10-01, AUD-68-F1, owner decision) CI refuses a tag whose commit no gate stamped: the tagged tree must
  contain the gate's own `exe_to_download\filedo.exe` printing the tag's stamp and a `filedo_win.exe` whose PE
  FileVersion equals it, and a second step re-runs the gate's `go test` set on the tagged source before building.
  `release.ps1` `Get-TagSourceDrift` refuses the Store MSIX unless HEAD equals the tag outside `winget\` and the
  tree is clean, even under `-Resume`.
- **CONTRACTS §6 / the release contract gate: still open** in `release.ps1` (no registry-row freshness check
  seen on 2026-10-02).

## Overlay facts refresh 2026-10-02

Several lines of "Overlay facts" and the channel rows above are stale; they are not rewritten, this is current:

- **MSIX identity is no longer a placeholder:** reserved name `SZA.FileDO`, Store ID `9PH1LPCMRG83`, live
  2026-09-23.
- **The direct artifact is a WiX Burn setup EXE carrying the MSI**, with its own bundle `UpgradeCode` (a separate
  identity from the MSI's, which makes the setup EXE replace itself in Apps and features).
- **Five binaries and a third codebase:** C++ `shellext/` (MSIX-only first-level menu, SP-0020). `capacitytest/`
  is retired (SP-0026); `fsx/` and `statedir/` were added.
- **Version remaps now include the MSI three-field map:** Windows Installer compares only the first three
  fields, so `yy.M.d.HHmm` made two same-day releases equal; `ProductVersion` is now
  `yy.M.((d-1)*1440 + H*60 + m)` and `release.ps1` reads the latest release's MSI and refuses a triple that is
  not greater (SP-0030 PKG-01).
- **Toolchain pin:** Go 1.26.x through the `toolchain` line of `go.mod`, which must equal `release.yml`'s
  `go-version` (the gate fails when they differ).
- **Contracts:** FileDO owns FDSEC-FORMAT 1.3, FDSEC-BEHAVIOUR 1.4, CLI-EVENT-STREAM 0.11, FDD-FORMAT and
  FDD-BEHAVIOUR 0.1, and consumes 17 listed in `docs/contracts/README.md`.

## Audit campaign record 2026-09-25 .. 10-01

Specs SP-0023, SP-0031, SP-0064 and SP-0065, the FileDO analogue of the FastMediaSorter S3556 campaign.

- **SP-0023:** eight parallel read-only auditors, about 190 defects, 15 critical, in code the gate was passing;
  ten cross-cutting themes each fixed once as a shared mechanism (stop model, path identity, error to verdict,
  atomic writes, state root, secret hygiene, child-process contract, test what ships, GUI/CLI destructive
  parity, promises not true). The 337-file commit `3349bbb` carries the implementation.
- **SP-0031:** `slice.ps1` cuts by package or file family at 12 files / 2500 lines with a risk score,
  `manifest.json` records per-file hashes, `fanout.ps1` writes one self-contained record per slice,
  `summary.ps1` reports uncovered, duplicate and drifted files and exits 1 until every slice is closed. Inline-fix
  rule: a fix needs a failing-then-passing test or is behaviour-preserving by construction, one slice's fixes at
  a time under a write lock, destructive paths only with a black-box test.
- **Yield by wave:** first pass 29 slices, 2 critical / 28 high; final audit of the new virtual-disk code 13
  slices, 3 critical / 10 high; the "redo" wave re-auditing files changed since their slice closed, 36 slices,
  0 critical / 10 high / 53 medium. **Total 420 findings (5 / 49 / 176 / 190 by severity).** The redo wave is the
  measurement worth keeping: re-auditing files that earlier fixes had changed still found 10 high.
- **A protocol defect found by AUD-66-F1** (a stop must not outrank a defect in the event stream) was fixed
  contract-first: CLI-EVENT-STREAM 0.11, 2026-10-01.

## Lessons promoted from this window - proposed 2026-10-02, none applied yet

Twelve candidates; each is a proposal until the owner approves it, at which point the line below gets the
section it landed in, as the 2026-07-23 "APPLIED" list does. Each was grepped against `rules/`, `skills/`,
`tools/` and `hooks/`; "no hit" means the canon says nothing today.

| # | Lesson | Proposed landing | Evidence (this repo) |
| --- | --- | --- | --- |
| C1 | Bind the tag to the gate in CI; build derived channels only from tag-equal sources | [RELEASE_AND_DISTRIBUTION](../../RELEASE_AND_DISTRIBUTION.md) §2 after "Wire the gate into the command that ships", one line in `skills/release` Phase 3 | `release.yml` step "Bind the tag to the release gate", `Get-TagSourceDrift`; a valid-looking tag on an un-gated commit is what INVARIANT 5 leaves open |
| C2 | Split the release workflow (read-only build job, a publish job that alone may write and runs no project code); pin by commit SHA; `persist-credentials: false`; tag through `env:`; `make_latest` only when the stamp is newer than the current Latest | [RELEASE_AND_DISTRIBUTION](../../RELEASE_AND_DISTRIBUTION.md) §1 "CI cost & safety levers", one sentence in the GitHub Release playbook of [CHANNEL_MATRIX](../../CHANNEL_MATRIX.md) | SP-0030 CI-01..03, `release.yml` lines 516-549; grep for `make_latest` in rules/skills: no hit |
| C3 | Parse-check every CI shell step before the one-way tag | [DEVELOPMENT](../../DEVELOPMENT.md) §15 next to "Reachable exit codes (PowerShell)", a clause in RELEASE §2 | `007151f` (2026-09-24): `"release-artifacts $version: PASS"` failed the tagged v2609241700 run because PowerShell reads `$version:` as a scope qualifier; the language parser reports it. The gate is the report's proposal, **not mechanised in FileDO** |
| C4 | A name-glob secrets guard (`*secret*`, `*token*`) silently swallows legitimate files; gate on "ignored but needed" | [REPOSITORY_LAYOUT](../../REPOSITORY_LAYOUT.md) "Secrets - never in the repo" and [TESTING_AND_QA](../../TESTING_AND_QA.md) §5 pre-flight item 2 | SP-0049 AUD-18-F1: two catalog glyphs ignored, a local build passed while the tagged CI checkout lacked them; `packaging/check-build-inputs.ps1`. A canon check only if a decidable list survives a run over real repos |
| C5 | Windows App Certification Kit procedure: read the verdict from the report, never `appcert`'s exit code | `skills/store-publish/references/msix-store.md` (new "Pre-submission: WACK") and one line in the MSIX playbook of [CHANNEL_MATRIX](../../CHANNEL_MATRIX.md) | `appcert.exe` needs elevation even for `/?`, exits 0 for a session that found failures, rolls an optional FAIL into `OVERALL_RESULT=WARNING`; `msix/wack-verdict.ps1`, seven regression checks; grep for WACK/appcert: no hit |
| C6 | Windows Installer compares three version fields; refuse an MSI not greater than the published one | [WINDOWS_PACKAGING](../../WINDOWS_PACKAGING.md) §2 version stamping map, cross-linked from the version shape in [PLATFORM_OVERLAYS](../../PLATFORM_OVERLAYS.md) | SP-0030 PKG-01, see the overlay refresh above |
| C7 | The anchor set of a WiX product is wider than the `UpgradeCode`: component GUIDs, feature ids, file-type extension and ProgId, a COM class id, a Burn bundle's own `UpgradeCode` | [SECURITY_AND_PRIVACY](../../SECURITY_AND_PRIVACY.md) §2 anchor list; whether INVARIANT 1 is touched is the owner's call | AGENTS.md lines 48-60; `TestShellExtClsidAgrees` |
| C8 | A secret handed between processes travels by environment-variable name, is deleted from the receiver on read, an empty value is an error; every text surface redacts through one function with a single shared vector file | [SECURITY_AND_PRIVACY](../../SECURITY_AND_PRIVACY.md) §4 (new bullet) | SP-0025 FDSEC-07/19; `cmd/filedo/testdata/redaction/vectors.tsv` read by the Go test and the VB `--selftest`; release-queue R-F1 (2026-10-01), a password with spaces slipped through word-rule redaction |
| C9 | One persisted shape with N writers: make the installer a test fixture of the program's own writer, compare both directions, remove only what carries your mark | [DEVELOPMENT](../../DEVELOPMENT.md) new §12a beside §12-§13 (the third parity model) | `TestRegistryParity_TheMSIAndFdsecRegisterWriteTheSameShellIntegration`, `TestShellExtMenuMatchesClassic`, `FileDO.RegisteredBy` |
| C10 | Byte-exact fixtures need `-text`, and a fresh-worktree run proves it | [TESTING_AND_QA](../../TESTING_AND_QA.md) §3 "Contract conformance" bullet, cross-linked from [REPOSITORY_LAYOUT](../../REPOSITORY_LAYOUT.md) | `.gitattributes`; the preflight report: "a fresh Windows worktree had exposed CRLF-induced provenance/sample failures". Streams and CyrFlip found the same on the same days |
| C11 | Auditing a tree too big for one pass: slice, hash, re-audit what the audit changed | `skills/spec-to-audit/references/audit-campaign.md` plus a pointer in [DEVELOPMENT](../../DEVELOPMENT.md) §11 (the same landing as the FastMediaSorter candidate; the generic tools can be lifted from `PLAN/SP-0031*/tools/`) | the campaign record above, 420 findings, redo wave 10 high |
| C12 | Verify the built artifact for the property, not the build log | [DEVELOPMENT](../../DEVELOPMENT.md) §16 ("and prove the result is in the artifact") and the evidence ladder row "Packaging / resources: inspect the built artifact" in [TESTING_AND_QA](../../TESTING_AND_QA.md) §2 | a WiX build omitting `-loc` and the two bitmap `-d` defines "still succeeds and quietly ships the stock blue dialogs"; unpinned `WixToolset.*.wixext` resolves to 7.x; SP-0023 T8, "the gate tested a 386 build with no manifest and a different Go than the one that shipped" |

The report's top five by value: C1, C4, C5, C8, C11.

**Considered and dropped:** the persona inversion / force-skips-prompts / modtime cache rules (applied
2026-07-23, [TESTING_AND_QA](../../TESTING_AND_QA.md) §6 and INVARIANT 9; `AGENTS.md` still carries a copy);
known-red `go test ./...` and the shrink-only vet baseline (`CHECK-BASELINE`); the three-state verdict (`CHECK-VERDICT`);
the unmeasured "about 90 s" claim (registry row closed 2026-10-01). **Not worth a standalone rule, optional
one-liners if the owner wants them:** the `.NET Framework` DPI pair (`app.manifest` plus `app.config` must both
ship, and winget `ArchiveBinariesDependOnPath: true` because portable aliases are symlinks); Go `os.Rename`
replaces its target on Windows; the MSIX integrity sidecar is hashed after signing; site download buttons
resolved by release-asset suffix; a GUI-subsystem exe has no exit code in PowerShell unless started with
`Start-Process -Wait -PassThru`.

## Open question for the owner 2026-10-02 - split the 756-line AGENTS.md?

`AGENTS.md` is 756 lines, 71,078 bytes, loaded every turn (roughly 18k tokens per session);
[AI_USAGE](../../AI_USAGE.md) §5 says a rule that does not earn a gate is compressed to one line plus a pointer.
`SZA-RULES05` is informational at 400 lines and says only "check the bulk is repo-specific architecture", which
FileDO did and which still leaves the file at 756 lines.

- **About 520 lines (70%) are correct content in the wrong file:** lines 62-161 the installer, MSI/Burn, wizard
  strings, registry shape and shell extension (100); 163-377 the code map (215, 29% of the file); 461-486 Store
  channel facts; 570-652 the GUI shell, Disk Manager and child-process contract; 654-689 coding style, site and
  the PLAN scheme. Proposal: move 62-377 and 570-652 to a tracked, registered internal doc (for example
  `docs/dev/ARCHITECTURE.md`, with a row in `docs/DOCUMENT_REGISTRY.jsonl`, which `check-internal-docs.ps1`
  already requires) and leave one line per trap with a pointer. Target 250-300 lines. No canon change is needed.
- **About 85 lines duplicate the canon or a contract:** the plugin-hooks restatement (lines 14-18), the
  known-broken `go test`, 0/1/2 exit semantics, persona inversion and modtime cache (489-490, 508-513, 564-568),
  the "shell consumes APP-BEHAVIOUR / APP-STYLE" bullets (602-611, 625-632), and the External contracts block
  (691-752, 62 lines), whose two tables of 25 rows duplicate `docs/contracts/README.md` with different row sets
  (`INPUT-PARITY` is in AGENTS.md only, five other ids are in the README only). Keep the one paragraph naming the
  catalog (SZA-CTR03 needs it) and the vector-regeneration command.
- **Lessons to extract first** (then shrink to one line each): lines 337-340 -> C4, 342-354 -> C8, 102-116 and
  146-157 -> C9, 79-88 -> C12, 38-43 and 405-409 -> C6, 48-60 -> C7, 438-445 -> C2, 446-451 -> C5.
- **Optional canon-side change:** reword the `SZA-RULES05` Fix text to name the remedy ("move architecture to a
  registered internal doc and leave one line per trap"). Not applied.

The decision is the owner's: split now, or accept `SZA-RULES05` as a standing note with a dated reason here.

## Promotion campaign (2026-10-09)

- Ticket `PLAN/SP-0166 free-promotion-campaign.md` (Draft), aligned to canon [PROMOTION](../../PROMOTION.md). It replaces the open draft that wrongly carried `SP-0149`, an id owned by the closed `done/SP-0149` disk-sharing spec; invented traffic, install and star figures were replaced by a measured baseline. Depends on the hub ticket for the host-root `robots.txt` and console property.
- 2026-11-07, site audit: 0 HIGH, 27 MED (of 75 findings) recorded in ticket SP-0166, section 12; the ticket, closed before 2026-10-29 (Status "Implemented in the tree 2026-10-09", file in `PLAN/done/`, id on the ledger's burned list), was reopened the same day on the owner's word, status Partial, file `PLAN/SP-0166_free-promotion-campaign.md`; the 2026-11-03 baseline re-measured: 6 open, 0 partial, 0 fixed; criterion 14 added, failing until every MED is fixed or refused in the ticket.

## In-app help (2026-10-16)

- Ticket `PLAN/SP-0168 in-app-help-f1-and-help-pages.md` (Draft - not approved, not queued), created by the canon session from the owner's request for F1 and a `?` button in every product ([UI_UX](../../UI_UX.md) §7, contract `CONTEXT-HELP` 0.1). The VB.NET shell has 36 rail destinations, two main windows and about 50 expected map rows; the Disk Manager already has a `?` button that opens a menu and an F1 that opens a different window, which `CONTEXT-HELP` rule 3 (the same answer for both) asks the owner to settle (O3). The CLI's `--help` is out of scope.

## Canon delivery reconciliation 2026-10-17 (S4307)

- Installed plugin `2026.1017.1` from published canon `2026.10.17.1` (`d06a64a`). The harness counts Done and Skipped as finished and preserves the phase-counter suffix.
- Re-read the changed canon guidance for delivery, documentation, localization, layout and sealed contracts. Existing product implementation and contract catch-up work remains owned by the recorded project tickets; this delivery check does not certify every product contract.
- Re-stamped through `restamp-canon.ps1` against the installed plugin reader: version, freshly computed core digest and reconciledOn move together; adoptedOn and project-specific fields stay unchanged.
- Compliance for FileDo: 0 error(s), 1 warning(s) before; 0 error(s), 0 warning(s) after; exit 0. Canon freshness findings cleared.

## Test lab report (2026-10-23)

- Ticket `PLAN/SP-0172 test-lab-report.md` (Draft, not queued; `PLAN/` is git-ignored), created by the canon session from the owner's order of 2026-10-23 to collect what every project knows about its hardware, emulators and test practice (contract `TEST-LAB` 0.1, draft). Documentation only: the product files one inventory report and a pointer; no code, test or harness changes. Reports to the Windows profile owner (FMS_Win).

## Fast checks between releases (2026-10-29)

- Ticket `PLAN/SP-0173 fast-checks-between-releases.md` (Approved, first in `PLAN/release-queue.md`; `PLAN/` is git-ignored), created by the canon session from the owner's order of 2026-10-29 to switch off full builds and tests longer than 5 s between releases (canon TESTING_AND_QA section 2, highest priority). The product has to take `build.ps1 -Test` (the twelve-step gate) and the installer step off the between-release path of `AGENTS.md` and the build skill in favour of a fast tier, while `release.ps1` keeps the full gate, the full `go test ./fdsec/` run, `govulncheck` and the operations run.

## Record split 2026-11-18 (canon ticket S0120)

Every section of this file dated before this one was moved here verbatim from [../filedo.md](../filedo.md) when the record was split into facts and history. A line number quoted inside such a section counts lines of the record as it was before the move; relative links were deepened by one `../`; nothing else changed.
