# History: streams_player

## Candidate core edits (RESOLVED - all folded into core 2026-07-23)
Landing map: PLATFORM_OVERLAYS.md "Cross-project contracts" (consumed release artifact) + Overlay A (no-installer
variant, MSIX no-leading-zeros int-cast remap); SECURITY_AND_PRIVACY.md §2 (IARC not publisher-constant), §5 (fresh-IARC
carve-out + category-review framing), new §6 (bundled LGPL/GPL notices), §7 checklist steps 6-7; RELEASE_AND_DISTRIBUTION.md
§4 (CI tag `ParseExact` gate) + §5 (notices in every package); CHANNEL_MATRIX.md MSIX row (listing export-then-merge CSV
import + category-review note); LOCALIZATION.md §1 (per-surface locale coverage). No new docs, so no README/read-order/
NEW_PROJECT_CHECKLIST wiring needed.

- **[LANDED] PLATFORM_OVERLAYS.md → Cross-project contracts:** add a third coupling shape, **consumed published release artifact
  (data bank)**, distinct from wire-contract and edition/parity — a runtime dependency on another product's *release
  output*, with the same producer-frozen / consumer-forward-tolerant rule plus a consumer-side data-preservation
  invariant (protect user-owned rows on refresh). Prevents mis-modeling a release-artifact dependency as a wire contract
  or an edition. Evidence: `AGENTS.md:10-12`, `CatalogMerger.cs`.
- **PLATFORM_OVERLAYS.md → Overlay A:** document the **no-installer variant** (portable-zip + winget-portable + MSIX, no
  Inno/WiX, reduced anchor set) and add the **zero-padded `YY.MMDD.HHmm` → MSIX no-leading-zeros int-cast remap + `<=65535`
  ceiling** as a second documented remap beside `M*100+D`. Prevents a rejected MSIX Identity Version and a wrong
  "just append .0" assumption. Evidence: `build-msix.ps1:48-55`, `release.yml:46-54`.
- **SECURITY_AND_PRIVACY.md §5:** carve out the IARC-id-reuse rule — an app whose content-exposure profile differs (opens
  arbitrary third-party / uncurated content) must file a **fresh IARC questionnaire**; the portfolio IARC id is constant
  only within the same content profile. Prevents shipping a wrong age rating by copying the portable id. Evidence:
  `STORE_PUBLISHING.md:118-124`.
- **RELEASE_AND_DISTRIBUTION.md (+ CHANNEL_MATRIX playbook):** add a **bundled-native-media license rule** — an MIT app
  redistributing LGPL/GPL native libraries ships under the combined (GPL) obligation and must carry
  `THIRD-PARTY-NOTICES.txt` in every package; and a **Store infringing-content review** note for third-party-stream
  players. Prevents a license-compliance gap and a surprise Store rejection. Evidence: `THIRD-PARTY-NOTICES.txt:16-32`,
  `STORE_PUBLISHING.md:126-139`.
- **RELEASE_AND_DISTRIBUTION.md §4:** recommend a **CI tag-format + date semantic gate** (regex + `ParseExact`) as the
  mechanical guard that a `v*` tag is a real, monotonic version before the release job publishes. Prevents a mis-typed
  tag from cutting a bad release. Evidence: `release.yml:36-38`.
- **LOCALIZATION.md §1:** state that shipped-locale coverage is **per surface** (a website/README locale need not be an
  in-app or store locale). Prevents treating "EN/RU/UK" as a uniform obligation across every surface. Evidence: two
  `Localization.*.xaml` vs three `README.*.md`.

## Spread-back applied 2026-07-23

Ran `SPREAD_BACK_PROMPT.md` in a session started in `P:\WINDOWS\Streams_Player` (existing repo). Working tree
was clean on `main`, no prior canon reference in-tree. Build gate green after all edits: `./build.ps1 -Test
-Deploy:$false` → Build succeeded, 0 warnings/errors, 149/149 tests passed, exit 0; console output now English.

**Consumption model — hybrid REFERENCE (owner decision).** Added a canon pointer to `AGENTS.md` (new section
"SZA Unified Rules (canon)") and a one-bullet pointer to `CLAUDE.md` (Workflow tooling), but did **not** strip the
restated universal rules. DIVERGE from the prompt's default ("prefer REFERENCE + remove restated universal rules"):
the canon lives only at a local, non-committed, non-public path (`P:\WEB\...\Unified_Rules`) that CI and outside
contributors of the public GitHub repo cannot resolve; stripping universal rules and pointing there would break the
repo's self-containedness. Rules stay in-repo; canon is authoritative on disagreement. Owner confirmed the hybrid.

**Open questions closed:**
- **MSIX version doc bug — FIXED.** `AGENTS.md` version section now describes the int-cast remap
  (`26.0719.0131` → `26.719.131.0`, `≤ 65535` ceiling) to match `msix/build-msix.ps1:51-55`, replacing the wrong
  "appends only .0: 26.0719.0131.0" text.
- **Russian build-script strings — FIXED.** Translated the seven Russian console/error strings in `build.ps1`
  (lines ~49/54/61/66/69/173/187) to English. Verified no other `.ps1` console output is affected: the Cyrillic in
  `tools/store/make-store-images.ps1:93-94` is RU **content** for Store screenshot captions, and
  `tools/store/auto-capture.ps1:73` `'video|видео'` is a regex matching the localized player-window title — both are
  localized data, not script output, so they legitimately stay (recorded, not "fixed").
- **Product-UI locale set — RESOLVED to ADD UK (owner decision), deferred to a ticket.** Owner chose to bring the
  in-app UI to EN+RU+UK (matching the site). This is a real feature (extend `AppLanguage` enum in Core, add
  `Localization.uk.xaml` at full parity, turn the EN↔RU toggle into a 3-way selection, `uk-UA` culture), not a
  spread-back edit, so it was captured as **`PLAN/SP-0029_ukrainian_ui_locale.md` (Draft)** rather than folded into
  this commit. Once shipped, the earlier per-surface note (LOCALIZATION §1 delta above) no longer describes a UI gap.

**Files touched in the repo:** `AGENTS.md` (canon pointer + MSIX version fix), `CLAUDE.md` (canon pointer bullet),
`build.ps1` (English console strings), new `PLAN/SP-0029_ukrainian_ui_locale.md`.

**Needed canon fixes (for a canon session, not applied here):** none. All universal deltas from this survey already
landed 2026-07-23 (see "Candidate core edits — RESOLVED" above). The hybrid-consumption divergence is repo-specific
(local-only canon path) and recorded here, not a canon rule change.

## Drift correction 2026-07-26 (owner-triggered)

The owner caught the agent chatting in English and asked for a canon diff. Four unrecorded drifts found - none of
them was a DIVERGE, all were plain drift the 2026-07-23 survey missed. Note that survey listed **AUTHOR.md under
"No delta"**, which was wrong: `AGENTS.md:98` contradicted `AUTHOR.md` §Language at that moment and was not flagged.

| Topic | Canon | Repo before | Fix applied in repo |
| --- | --- | --- | --- |
| Chat language | `AUTHOR.md:33`, `AI_USAGE.md:75` - chat in the owner's language (Russian) | `AGENTS.md:98` + `.claude/agents/streamsplayer-rd-lead.md:12` - "Chat, code, documentation, logs, and commits are English" | Both rewritten to the canon split; `CLAUDE.md` gained an explicit **Communication** block citing `AUTHOR.md` §Language + `AI_USAGE.md` §7 (it had no language rule at all) |
| Trailing summaries | `AUTHOR.md:42`, `AI_USAGE.md:76` - no trailing "what I did" summary | absent | Added to `AGENTS.md` + rd-lead agent + `CLAUDE.md` |
| Reply timestamp | `AI_USAGE.md:77` | absent | Same three files |
| Scratch tree | `DEVELOPMENT.md:101` - `temp/<ticket>/` | `tmp/` in `AGENTS.md:118`, `docs/agent/{VALIDATION,RESEARCH_INDEX,COST}.md`, two skills, two agent files | All rule sources switched to `temp/<ticket>/`; `.gitignore` already ignored both |

**Partial adoption, deliberate:** the existing `tmp/` tree was **not** renamed. It holds local, uncommitted evidence
referenced by ~30 closed `PLAN/DONE` tickets and by a `memory/MEMORY.md` pointer to a live driver script
(`tmp/uia/driver.ps1`). Rewriting those paths would falsify closed verification records for no gain. `AGENTS.md` now
says `temp/` is the target and `tmp/` is frozen history - do not add to it.

**This is a recurrence, not a one-off.** The identical chat-language defect was found and fixed in OneClickRunner
(`contrib/oneclickrunner.md:92-94`). Two repos drifting the same way suggests the canon's language rule is easy to
lose when a repo restates universal rules in-house (the hybrid-consumption model recorded above). Worth a canon-session
decision: either a spread-back checklist item that greps every repo's rules file for a chat-language line, or a
`tools/check-rules.ps1` extension that flags a repo rules file asserting English chat.

**Files touched in the repo:** `AGENTS.md`, `CLAUDE.md`, `.claude/agents/streamsplayer-rd-lead.md`,
`.claude/agents/streamsplayer-{solution-researcher,implementer}.md`,
`.agents/skills/streamsplayer-{research,verify}/SKILL.md`, `docs/agent/{VALIDATION,RESEARCH_INDEX,COST}.md`.

## Canon adoption 2026-07-27 - the fork is gone

This repo was the portfolio's only **self-declared fork** of the canon. `AGENTS.md:126` said it "deliberately
keeps those rules restated in-repo so the repository stays self-contained for CI and outside contributors",
and `CLAUDE.md:69` repeated it. The argument was sound while the canon lived at a local absolute path CI could
not resolve. It is void now: the canon installs as the `sza` plugin and travels with the session.

The restatement had already drifted - the 2026-07-26 correction above found four unrecorded divergences,
including a chat-language rule that contradicted `AUTHOR.md` and survived an entire survey unflagged.

Removed seven restated rules across the two files: chat language, English artifacts, no trailing summary,
working-tree-is-truth, the evidence rule, and build-is-not-a-release twice. Kept as genuinely repo-local: the
dependency direction, the research order, the memory discipline, and the **autonomy verdict** (ask first
before any publishing action) - a verdict stays local even when the rule it applies does not.

`.sza-canon.json`: overlay A no-installer variant, consumed-release-artifact coupling, ledger shape 4, three
channels, and the fact that `docs/` is **generated** by `tools/site/build-site.ps1` - hand-editing it is a
silent revert on the next run.

Compliance gate: **0 errors** (was 8), 4 warnings.

## Canon reconcile 2026-08-02 - agent-process propagation

Canon **2026.07.27 -> 2026.08.02**, core digest `sha256:dae220bf..` -> `sha256:6c247452..`. Stamp
updated; the adoption model is unchanged. The upstream change is [AI_USAGE.md](../../AI_USAGE.md) only -
the agent-process findings propagated from FastMediaSorter mob_v2 under its ticket S1342 - so the
staleness ladder's "re-read only the changed rule docs" path applies and no full re-adoption was run.
Nothing in `rules/` touched packaging, release, channels or layout, and no divergence was found
between the new bullets and this repo's own rules file.

The one repo besides FastMediaSorter where §4 lands **live rather than inert**: memory here is
file-based, committed and shared across tools, with `memory/MEMORY.md` as the always-loaded index and
the same four entry types. So the byte budget, the liveness-keyed expiry and the ban on restating the
rules file all apply to a real corpus today, and the index wants a mechanical ratchet the way
FastMediaSorter's got one. `AGENTS.md` already carries the verify-against-the-tree half of the
discipline, which the canon's §4 states too - agreement, not divergence.

Verification: `check-compliance: Streams_Player - 0 error(s), 4 warning(s) (overlay A, canon 2026.08.02)` - warnings are pre-existing and none was introduced here.

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

Finding 2 has a target here, with a local twist: all eighteen commands carry a `streamsplayer-` prefix, so
the cheap tier is `/streamsplayer-quick` - the longest name on the ladder belongs to the tier meant to be
reached for first, and any nudge written here has to emit the prefixed forms or it will name commands that
do not exist. Whether the prefix itself suppresses the cheap tier is a hypothesis, not a measurement; the
transcript corpus can answer it before anyone renames anything. No hooks are configured. Carried as an owner
decision, not applied from this session.

Verification: `check-compliance: Streams_Player - 0 error(s), 4 warning(s) (overlay A, canon 2026.08.05)` -
warnings are pre-existing and none was introduced here.

## Canon re-sync 2026-08-18 - four updates at once, and a reversed rule

Canon **2026.08.05 -> 2026.08.18.1**, core digest `sha256:8d33fdab..` -> `sha256:961c9c8a..`. The stamp
had already been moved mechanically before this session; it was **verified, not trusted** -
`check-compliance.ps1 -PrintDigest` recomputes `961c9c8a..`, so it is correct as written.

**Why this one is not an ordinary one-step reconcile.** The `sza` plugin served a cached
**2026.07.27** for roughly three weeks, so the 08-02, 08-05, 08-08 and 08-18 updates never loaded in a
session started in this repo - including the 08-02 and 08-05 reconciles recorded above, which were
written against docs the session could not actually see. This pass re-read the diff from `7dd3dde`
(2026-07-27) to `HEAD` directly out of the canon repo rather than trusting the plugin cache.

Rule docs changed in that span: **AI_USAGE, DEVELOPMENT, GITHUB_INTERACTION, RELEASE_AND_DISTRIBUTION,
TESTING_AND_QA** (plus README and NEW_PROJECT_CHECKLIST). **INVARIANTS.md did not change** - worth
recording, because it was on the review list and a null result there is a real finding, not a skipped
step.

Also noted: the plugin cache holds a newer **2026.08.18.2**, and its core digest is **identical**
(`961c9c8a..`) - that bump touched `skills/` and `tools/`, which the digest deliberately excludes. The
stamp sitting at `.1` therefore is not stale in the sense the staleness ladder measures. Left alone.

### A canon rule this repo had adopted was reversed

The 2026-07-26 drift table above records "Reply timestamp | `AI_USAGE.md:77` | absent | Added to three
files" as a *fix*. **AI_USAGE section 7 now says the opposite** - "Never prefix a reply with a clock
time.. This supersedes the earlier rule to timestamp from the prompt" - because the model has no clock
and the prompt-submit injection goes stale inside any autonomous run. The repo was still carrying the
July version in two places, one of them load-bearing:

- `CLAUDE.md` declared it as the repo's **only** repo-local communication addition - now removed, and
  replaced with an explicit note that section 7 supersedes it, so the next session does not re-add it.
- `.claude/agents/streamsplayer-rd-lead.md:12` - the **default orchestrator's** own rules line, i.e. it
  was reaching the system prompt of most sessions in this repo. Fixed.

Generalisable: when the canon reverses a rule, the adopters that were most diligent about adopting it
are the ones now most wrong, and a grep for the *old* rule's wording is the only thing that finds it -
the compliance gate cannot, because a superseded rule is not a restatement of a live one.

### GITHUB_INTERACTION section 6 - the .ps1 command-head family, and a permission list it made dead

The new Bash-safety family ships as `guard-bash.ps1`. Verified live rather than assumed: piping a
`{"command":"./build.ps1 -Test -Deploy:$false"}` payload into the hook returns **exit 2** with the
"Bash cannot execute a .ps1" refusal.

Two consequences here, and the second is the interesting one:

- Both rules files documented every script as `./build.ps1 ..`, `./scripts/check.ps1 ..` - the exact
  refused shape. Rewritten to `pwsh -NoProfile -File ./..`, with a one-line note that a human in
  PowerShell types the bare form and an agent must not. The README, the site and the Store docs keep
  the bare form deliberately: those are instructions for a human, not tool calls.
- `.claude/settings.json` allow-listed `Bash(./build.ps1*)`, `Bash(./run.ps1*)` and `Bash(./scripts/*)`.
  Those three rules had become **unusable by construction** - the hook refuses the call before the
  permission layer is ever consulted. Removed, with the reason recorded in the file's own comment.
  `Bash(pwsh *)` already covers the compliant form. **A permission entry that a hook makes unreachable
  is worth a check of its own**: it reads as a granted capability and is in fact a dead rule, and
  nothing in the current gate set notices.

This repo registers **no hooks of its own**, so AI_USAGE section 5's "drop your hand-wired copy rather
than run it twice" had nothing to act on. `CLAUDE.md` now says so explicitly, so a future session does
not add a local copy of a hook the canon already ships.

### The rules files were carrying four false statements about their own tree

The re-sync's "verify every kept claim against the live tree" step found more than the canon delta did.
All four verified twice - once by a subagent, once directly:

- **`SP-0052` was described as "not implemented; do not describe it as shipped".** It is `Implemented`,
  sits in `PLAN/DONE/`, and ships: `BundledCatalogSnapshot`, `CatalogSnapshotService`,
  `FirstRunCatalogWindow`, an embedded `Resources\catalog-snapshot.zip` whose absence **fails the
  build**, and a `scripts/release.ps1` step that makes regenerating it a release blocker. The
  instruction was not merely stale, it was actively dangerous: an agent obeying it would have refused
  to describe a release-gating feature that exists, or re-implemented it. Now recorded as shipped and
  awaiting manual verification (`Implemented`, not `Verified`).
- **`CatalogMerger.Merge` "only updates/removes rows whose SourceOrigin == Catalog"** - the
  MANUAL/IMPORTED protection holds, but removal is now gated on `CatalogMergeOptions.RemoveMissing`,
  which the snapshot path passes as `false`. The claim was true of one of two merge modes.
- **"sixteen partials"** - there are 26. The number was stale by ten while the same sentence said
  "glob, do not memorize". Deleted rather than corrected.
- **The dialog list** named a `LanguageWindow` that does not exist and missed `ChannelInfoWindow`,
  `FirstRunCatalogWindow` and `LogArchiveReadyWindow`. Replaced with a glob instruction and no list.

Also corrected: `CLAUDE.md` cited a 3.9 MB live favicon atlas where the source comment says 2.9 MB, in
a sentence whose own advice is "read the constant, never a number from prose" - the number is gone;
`AGENTS.md` claimed the four version fields in `Directory.Build.props` "are updated together before a
release", where `release.yml` in fact derives the version from the `v*` tag and passes it as
`-p:Version=..` (the props file is the local-build stamp only); and the stale "after the GitHub
repository is created, add the remote" block was dropped, `origin` having existed for some time.

**The pattern worth carrying:** every one of these sat in a file whose *canon* conformance was already
clean. Reference-model adoption removes the restated universal rules, which is exactly what makes the
remaining repo-specific claims the only thing left to rot - and nothing gates them. The count-shaped
claims ("sixteen", "3.9 MB", a hand-kept list) went stale fastest, which argues for writing the glob
instruction instead of the count wherever a rules file is tempted to enumerate.

### Compliance gate: 6 warnings -> 1

`check-compliance.ps1`, before: **0 errors, 6 warnings**. After: **0 errors, 1 warning**.

- `SZA-LAY03` - `docs/` held three markdown files and no index. Added `docs/README.md`, which mostly
  exists to state the split a newcomer gets wrong: most of `docs/` is a **generated** Pages site and
  hand-editing it is a silent revert, while the maintainer documents beside it are hand-written.
- `SZA-SURF02` x2, `SZA-SURF03` x2 - no SEO block, no `robots.txt`, no `sitemap.xml`. Fixed **in the
  generator, never in `docs/`** (invariant 16). The SEO block went into the shared `_head.html`
  partial, so one edit covered 26 pages in 13 languages; every value it needed already existed as a
  structural token, so no copy deck changed and no translation was invented.
  - `robots.txt` and `sitemap.xml` are generated from the same language x page product the pages come
    from, so a fourteenth language lands in them with no edit - the failure mode a hand-kept sitemap
    always reaches. 26 URLs, each carrying the full `hreflang` alternate set plus `x-default`.
  - **JSON-LD is built in the script, not in the template.** An HTML parser does not decode entities
    inside a `ld+json` script element, so reusing the HTML-escaped `{{page.title}}` there would have
    emitted a literal `&quot;` into the JSON and broken it on every page. Values are taken raw from the
    copy deck and escaped by `ConvertTo-Json`. Verified by parsing the emitted block on all 26 pages -
    0 failures, Cyrillic intact.
  - `og:image` is a real 1200x630 card generated by a new `tools/site/make-og-image.ps1` from the
    existing icon and the site's own palette (`--bg #0a0f0a`, `--accent #3fb950`), not the 256 px icon
    reused as a square. It has a `-Check` mode, like the site generator.
- `SZA-STYLE02` (`memory/MEMORY.md:552,749`) - **kept, deliberately.** Both hits are the case the
  gate's own fix text calls legitimate: an exact quoted UI automation string and a CLI placeholder.
  House style governs prose, not exact strings (invariant 20), and rewriting a UIA name to satisfy a
  warn-only style check would break the thing it names. Recorded rather than "fixed".

### Two contrib deltas above are now stale

Recorded rather than silently amended, since they were true when written:

- **LOCALIZATION delta** says in-app UI is EN+RU only against EN/RU/UK on the site. The repo now ships
  **thirteen** interface languages from a single `InterfaceLanguages` registry in Core, read by the
  PowerShell tooling out of the built assembly. `SP-0029` (the "add UK" ticket that delta produced) was
  overtaken by a much larger change. The per-surface-coverage rule the delta established still holds;
  its example does not.
- **PLATFORM_OVERLAYS delta** says the favicon atlas is "optional and `<=4 MB`". The cap is now
  `StreamBankReader.MaximumAtlasBytes` = 30 MB. The invariant that matters (an over-cap atlas is
  silently dropped, not an error) is unchanged. Same lesson as the rules files: the constant belongs in
  the record by name, not by value.

### Verification

Every command run fresh in this session, exit codes cited:

| Command | Exit | Result |
| --- | --- | --- |
| `check-compliance.ps1` (before) | 0 | 0 errors, 6 warnings |
| `check-compliance.ps1` (after) | 0 | 0 errors, 1 warning |
| `pwsh -NoProfile -File tools/site/build-site.ps1` | 0 | 13 languages x 2 = 26 pages, + robots.txt, sitemap.xml |
| `pwsh -NoProfile -File tools/site/build-site.ps1 -Check` | 0 | `docs/ is up to date.` |
| `pwsh -NoProfile -File tools/site/make-og-image.ps1 -Check` | 0 | present at 1200x630 |
| `./build.ps1 -Test -Deploy:$false` | 0 | Build succeeded, 0 warnings, **789/789 tests passed** |

One honest note on that last row: the first attempt returned **exit 1**, ".NET SDK not found", from the
agent's Bash sandbox, where `dotnet` is not on `PATH`. That is a **could-not-verify, not a failure** -
AI_USAGE section 2's third invariant - and re-running the identical command through the PowerShell tool
gave 10.0.302 and a green run. Recorded because a sandbox that lacks the toolchain will otherwise be
read as a red gate by the next session.

The working tree also carried **unrelated uncommitted work** (a random-station feature) throughout. It
was not touched, not staged, and not reverted; the commit for this pass names its paths explicitly, and
`git add -A` was never run. The 789-test green above covers that WIP too, which is why it is quoted as
context rather than as this change's own evidence - nothing in this pass touched C#.

### Needed canon fixes (for a canon session, not applied here)

- **A dead permission entry has no check.** `.claude/settings.json` carried three allow rules that
  `guard-bash` had made unreachable. Nothing in `check-compliance.ps1` notices a permission that grants
  a capability a shipped hook refuses, and the failure is silent in the safe direction, which is why it
  survived. Worth a gate, or at least a line in the hooks README's contract section.
- **Superseded rules need a migration note, not just a rewrite.** The reply-timestamp reversal was
  findable only by grepping adopters for the *old* wording. When a canon rule flips, the update is
  cheap to write and expensive to propagate; a short "adopters carrying X should remove it" line in the
  changed doc would make the next re-sync mechanical instead of archaeological.

## Canon re-sync 2026-09-03 - two updates behind, and only the stamp moved

Run from the canon repo against `P:\WINDOWS\Streams_Player` (`check-compliance.ps1 -RepoRoot`).

**What had to be re-read.** The stamp was at `2026.08.18.1` / digest `961c9c8a`. `Canon update 2026-08-28` is
the only one of the two intervening updates that touched rule docs (AI_USAGE, DEVELOPMENT,
DOCUMENTATION_CONCEPT, INVARIANTS, TESTING_AND_QA); the 2026-09-03 movement is `tools/harness/` and moves no
digest, only the plugin version.

**Reconciled: nothing owed, and one rule checked rather than assumed.** The lock-domain split, the abandoned
ticket's withdrawal, the unattended batch driver and the closure-runs-the-rung rule all presuppose machinery
absent here - no lock queue, no ticket store with a single write path, no closure facade. The locale rule
(INVARIANT 17 / DOCUMENTATION_CONCEPT §5) relaxed rather than tightened, so the three authored READMEs and the
12 `Localization.*.xaml` tables are already inside what it permits. The one worth checking on the tree instead
of by assumption was TESTING_AND_QA's new "a check only a human can run has not happened yet": it wants the
closing status held back by an unticked manual line, and `PLAN/` carries **no checkbox at all** - `grep -rn
"- \[ \]" PLAN/` returns nothing across all 21 specs and `PLAN/DONE/`. So the rule has no surface to bind to
here; standing up an audit section per spec is an owner call, not a re-sync side effect. Carried forward.

**Evidence.** `check-compliance.ps1 -RepoRoot P:/WINDOWS/Streams_Player` before -> `0 error(s), 2 warning(s)`,
after -> `0 error(s), 1 warning(s)`, exit 0. The remaining SZA-STYLE02 is `memory/MEMORY.md:659,856`, and both
hits are quoted material - an in-app string ("Add a channel someone sent you as text..") and a quoted GitHub
error about the `workflow` scope - which the check's own fix line names as legitimate.

**Commit discipline.** The working tree carried in-flight work across the three READMEs and twelve
`Localization.*.xaml` files. Only `.sza-canon.json` was staged; `git add -A` was never run.

## Mined 2026-10-02 (window 2026-09-20 .. 10-01) - record last dated 2026-09-03

Mined read-only from a canon session. 13 commits in the window; releases **26.0924.1704** (09-24; the first
attempt `26.0924.1655` was retired) and **26.1001.0140** (10-01). `gh` was not installed on the mining machine, so
no CI run history was read, and `PLAN/` is gitignored, so ticket bodies (SP-0156, SP-0180, SP-0184) were read only
through their commits and scripts.

### Overlay facts that changed since the record (07-23, 07-26)

- **The "no-installer variant" statement is false.** An Inno installer channel has existed since 2026-08-21
  (SP-0092, `installer/StreamsPlayer.iss`) and the release assets now include
  `StreamsPlayer-<ver>-windows-x64-setup.exe`. The **frozen-anchor list gains the Inno `AppId`
  `{15F4F08C-E78B-41B7-9039-6A3332D7D080}`**, plus `DefaultDirName` `{autopf}\StreamsPlayer`,
  `OutputBaseFilename` and `AppName` "STREAMS Player". `AGENTS.md` line 147 already says "installer variant"; the
  record and the stamp do not.
- **`.sza-canon.json` `site.pages` lists only `index.html` and `privacy.html`**; `docs/trust.html` exists
  (INSTALL-TRUST adopted 2026-09-24).
- **Contracts:** the repo now owns four (`APP-BEHAVIOUR`, `APP-STYLE`, `USER-PLAYLIST`, `DIAGNOSTIC-REPORT`) and is
  a producer of `INSTALL-TRUST` and `CAPTURE-OUTPUT`; the record predates all of it.
- **Version stamp clock.** Stamps at or below `26.0806.2131` were UTC and read one to two hours early; the shape is
  now the author's local time (Europe/Malta). `5cea4cc` (10-01): `build.ps1` reads one local instant per
  invocation and passes `-p:Version/AssemblyVersion/FileVersion/InformationalVersion` to every dotnet call without
  ever writing `Directory.Build.props`, which stays the release sentinel. `scripts/assert-release-version.ps1`
  compares against every `v*` tag plus an off-tag list (`26.0806.2225`, a stamp the Microsoft Store shipped that
  GitHub and winget never carried).

### Compliance now: 0 errors, 3 warnings (re-measured 2026-10-02, canon `2026.09.30.1`)

- **`SZA-CANON03`:** stamp `2026.09.06.1`; 15 rule docs changed since, including the new CONTRACTS, so a full
  `adopt-canon` re-sync is owed.
- **`SZA-CTR01` x3 is gone: fixed in the canon tool on 2026-10-02.** The three pointers (`APP-BEHAVIOUR.md` 53
  lines, `APP-STYLE.md` 48, `CAPTURE-OUTPUT.md` 45) carry the house `| **Id** |` header and were judged on length
  alone. **No drift** in any of the three: versions and roles equal the registry (`APP-BEHAVIOUR` 0.10 draft,
  `APP-STYLE` 0.10 draft, `CAPTURE-OUTPUT` 0.2 draft with this repo a producer of `video_frame`, `stream_video`
  and `stream_audio`). About a third of the first two files is a history of closed deviations
  (2026-09-22 .. 09-24) that the registry's closed rows already hold; trimming is optional now.
- **`SZA-CTR02` x2 remain** (`git grep -F` for the catalog path finds `CLAUDE.md:3`, which is the one allowed
  place, plus two more). Exact replacements:
  1. `docs/contracts/README.md`, lines 3-4: say the contract store is "located by the first line of `CLAUDE.md`"
     instead of naming its path; the next paragraph already says the location is named in exactly one file.
  2. `tools/Sync-IconGlyphs.ps1`, the `.EXAMPLE` lines 35-36: drop the literal catalog path. The `-CatalogRoot`
     parameter already defaults to `$env:SZA_CONTRACTS_ROOT`, so the first example needs no path at all and the
     `-Check` example takes `<catalog root, see CLAUDE.md line 3>`; the script's own comment already says "never
     a literal path". Re-run the compliance tool afterwards; both lines should clear. Not applied from here.

### Release engineering added in the window

`26.0924.1655` was retired and `26.0924.1704` released after the CRLF failure below (`803579c`, re-stamp
`36dd448`); `26.1001.0140` was released with committed smoke and code-audit verdicts, green-CI and pinned-natives
gates in `release.yml`, no replaced asset, and the Pages deploy behind a `ci-gate` job (`cfb659a`, SP-0156).

### Audit result, with a caveat

`release-verdicts/26.1001.0140.audit.json` holds 293 file rows and **62 findings** (High 0, Medium 12, Low 50):
11 fixed in `abab3a6`, 5 Medium exceptions (installer `InstallDelete` of `{app}`, the smoke-verdict commit not
compared to the tagged commit, natives comparison limited to two DLLs, native Stop/Dispose on the UI thread for
the broadcast leg, `RemoveDownloaded` deleting pinned rows) tracked in SP-0183, 46 Lows in SP-0184. **The caveat:**
`scripts/Assert-AuditVerdict.ps1` tests only "non-empty", and the file shows it is satisfied by boilerplate - all 11
`fixed` findings carry one identical evidence string ("expected: the defect no longer reproduces and the
build/test gates stay green | actual: fixed in commit abab3a6; scripts/check.ps1 PASS .."), all 5 `exception`
findings one identical `ownerDecision` sentence, and all 46 `ticketed` Lows point at one ticket with 6 summaries
literally `TICKET`. Whether the owner said what the exceptions quote cannot be read from the file.

### Hygiene

`memory/MEMORY.md` is **1274 lines, 114,783 bytes** (roughly 25-30k tokens) against its own header ("add one link
per entry; keep entry bodies in separate files") and the `CLAUDE.md` line calling it "the always-loaded index"; the
other indexes in the portfolio run 11-90 lines. Four of the 13 window commits (`95fa72b`, `40f1076`, `6cdf6ae`,
`cfb659a`) have the message `1`, and `cfb659a` touches 165 files including the release and Pages workflows -
[GITHUB_INTERACTION](../../GITHUB_INTERACTION.md) §3 asks for an imperative subject, and the release machinery changed
under an unnamed commit (CyrFlip has two such commits, `a928ace` and `e619590`).

### Candidates delivered from this record - proposed 2026-10-02, none applied

- *A suite is proven on a clean checkout; byte-exact files say so in `.gitattributes`* (also CyrFlip) -
  [TESTING_AND_QA](../../TESTING_AND_QA.md) §3, one sentence in [REPOSITORY_LAYOUT](../../REPOSITORY_LAYOUT.md); the
  `store-publish` MSIX reference already holds the CSV-only version (`-text`). Evidence: `803579c`, the release
  job of `26.0924.1655` failed because the runner's `core.autocrlf=true` plus `text=auto` turned the LF vendored
  ICON-SET SVGs into CRLF and every SHA-256 in `assets/glyphs/PROVENANCE.txt` stopped matching; the re-stamped
  release commit cites "CRLF checkout (core.autocrlf=true worktree): 1119/1119 tests passed" as its proof.
  Streams memory (09-23, 09-30): line endings are a fact about the checkout, not the file; count CRLF, LF and lone
  CR in PowerShell before a scripted insert, `grep -c $'\r'` is unreliable.
- *A published tag is never rebuilt; a tag that failed before publishing is retired* (also CyrFlip) -
  [RELEASE_AND_DISTRIBUTION](../../RELEASE_AND_DISTRIBUTION.md) §4 and `skills/release` Phase 6 item 4. SP-0156: "an
  already published asset is never replaced with different bytes"; `36dd448` re-stamps because the first tag
  "failed its release job and published nothing, so the number is retired rather than reused".
- *The ship step's verdict travels as a committed file that the tag workflow checks* -
  [RELEASE_AND_DISTRIBUTION](../../RELEASE_AND_DISTRIBUTION.md) §2 (a paragraph after "Wire the gate into the command
  that ships") and `skills/release` Phase 3. `release-verdicts/26.1001.0140.json` (smoke) and `.audit.json`;
  `release.yml` requires a completed green CI run for the tagged commit, the smoke verdict,
  `Assert-AuditVerdict.ps1`, the pinned natives and no replaced asset. The smoke can only run on the owner's
  machine (real audio and video), so its PASS must travel as a file inside the tagged tree; the writers refuse a
  dirty tree and write nothing on red; the checker requires gate, result and version to match, the audited commit
  to be HEAD or an ancestor, and nothing outside `release-verdicts/` changed since. Fixture tests:
  `tools/audit/Test-AuditVerdictGate.ps1`. The canon's INVARIANT 5 and RELEASE §2 say to name the version and wire
  the gate into the shipping command, but not where it is enforced for a tag-triggered workflow, nor the freshness
  rule.
- *A verdict gate that checks shape is satisfied by boilerplate* - [TESTING_AND_QA](../../TESTING_AND_QA.md) §5 after
  the waiver paragraph, the same family as "validate the instrument" (§1): reject duplicated evidence and
  placeholder summaries, require a fixed finding's evidence to cite its own command and exit code, record an
  owner exception in the owner's own words with date and place. Evidence is the audit file above; the facts are
  exact, the intent is inferred (confidence medium-high).
- *A pre-release audit of code that did not change, sliced, with a coverage manifest and a closing exit code*
  (CyrFlip converged independently: `PLAN/S0027_full-code-audit-pre-release` with 18 phases, `Get-AuditCoverage.ps1`
  / `Test-AuditCoverage.ps1`, exit 0 all closed, 1 one open, 2 a file missing or listed twice) -
  `skills/spec-to-audit/references/audit-campaign.md` and [TESTING_AND_QA](../../TESTING_AND_QA.md) §7. Streams:
  `docs/agent/CODE_AUDIT.md` and `tools/audit/` (1370 lines: slicer, fan-out, summary, fixture tests; class A
  always, class B behind a switch; markup and code-behind never split; 16 read-only slice auditors; High and Medium
  block, Low is ticketable). Read together with the boilerplate caveat above.
- *A site that deploys on push needs a CI gate between the push and the deploy* -
  [SITE_CONFIGURATION](../../SITE_CONFIGURATION.md) §4. `pages.yml` (`cfb659a`): a `ci-gate` job polls
  `gh run list -w ci.yml -c <sha>` for up to 25 minutes and requires success before `deploy`; CI runs
  `scripts/check-docs.ps1` and `tools/site/build-site.ps1 -Check`. Streams memory of 2026-08-21 records why: the
  generated site once published a download tile before the release that held the file.
- *The version stamp names its clock; "newer than every published version" is checked against every channel's
  list, including a stamp that shipped on one channel and never got a tag* - one bullet in
  [RELEASE_AND_DISTRIBUTION](../../RELEASE_AND_DISTRIBUTION.md) §4 and the catalog `PACKAGE-VERSIONING` (this repo is a
  declared consumer; FileDO filed `PROPOSAL-2026-09-30-filedo-desktop-stamps.md`). The local-clock and in-build
  rules are already catalog rules 1 and 6, so only the clock choice and the off-tag clause are new.
- *PowerShell source traps that hit Ukrainian and Russian text* - [DEVELOPMENT](../../DEVELOPMENT.md) §15 beside
  "Reachable exit codes (PowerShell)". Memory 2026-09-23 (SP-0109) and again 2026-09-30 (SP-0160): PowerShell reads
  U+2018 .. U+201B as single quotes and U+201C .. U+201E as double quotes, so a single-quoted table with the
  Ukrainian word that uses the real apostrophe fails to parse (build such text with `[char]0x2019` or read it from a
  data file); a negative `-split` limit splits from the end (use `[regex]::Split`); in the Bash tool `$'\r'`
  inside `$( )` inside double quotes is a parse error for the whole call. The first recurred within a week; no
  canon text mentions any of them.
- *The always-loaded memory index has no size gate* - a warn-only check (proposed name `SZA-MEM01`: a committed
  `memory/MEMORY.md` or `.claude/agent-memory/**/MEMORY.md` over 200 lines) and the measured portfolio numbers in
  [AI_USAGE](../../AI_USAGE.md) §4; [AI_USAGE](../../AI_USAGE.md) §4 already says to give the index a target and a ratchet
  that refuses growth, nothing enforces it. Near-zero false positives on today's portfolio: this one repo trips it.
  **Needs verification** against the real repos before it ships as a check.

**Dropped as already covered:** parallel readers safe and parallel writers not (kit `docs/PARALLEL.md`, `COST.md`);
`[skip ci]`, the `paths` filter and the tag-only trigger ([RELEASE_AND_DISTRIBUTION](../../RELEASE_AND_DISTRIBUTION.md)
§1); tag regex and build pinned to the tag (§4, `BUILD-EVIDENCE` rule 2); source-scanning conformance tests
([DEVELOPMENT](../../DEVELOPMENT.md) §9); check-placement records (`CHECK-PLACEMENT`).

## Canon adoption 2026-10-02 (SP-0186)

Full canon reconciliation to **2026.10.02.5** (core digest `sha256:1a8cbbb10997597ade50c7bd78edbd0c072cd5df8ac6279773d27d20adcb0903`, `reconciledOn: "2026-10-02"`).

### Reconciled items and fixes:
- **`SZA-CTR02` cleared:** Removed literal `P:\Contracts` occurrences from `docs/contracts/README.md` and `tools/Sync-IconGlyphs.ps1`.
- **`SZA-MEM01` cleared:** Modularized `memory/` into focused topic files (`feedback.md`, `project_architecture.md`, `project_playback.md`, `project_theme.md`, `project_localization.md`, `project_distribution.md`, `project_testing_and_automation.md`, `project_contracts.md`) and reduced `memory/MEMORY.md` to an index under 50 lines. Declared all in `DOCUMENT_REGISTRY.jsonl`.
- **Contract pointers synchronized:** All 20 pointers in `docs/contracts/*.md` updated to latest catalog versions.
- **`APP-BEHAVIOUR` rule 5 safe default button focus:** Updated all confirmation dialogs (`MessageBox.Show`) to set default button focus to safe result (`MessageBoxResult.No` / `MessageBoxResult.Cancel`).
- **`APP-STYLE` warning color:** Synchronized light `WarningBrush` day tone to `#EF6C00` / `#FFEF6C00` (`ThemeService.cs`, `App.xaml`), matching `ICON-RENDER` 0.14 section 10 D.
- **`WAVE-PARTICLES` rule 9:** Integrated Windows host animation signal via `SystemParameters.ClientAreaAnimation` (`BackdropEnvironment.AnimationEffectsEnabled` listened to in `WaveParticlesBackdrop.UpdateTicking`). Closed rule 9 exception in `P:\Contracts\_meta\REGISTRY.md`.
- **Adoption rows in `P:\Contracts\_meta\REGISTRY.md`:** Updated all StreamsPlayer rows with current versions, `2026-10-02` sync date and `SP-0186` citations.

### Verification:
- `check-compliance.ps1`: `Streams_Player - 0 error(s), 0 warning(s) (overlay A, canon 2026.10.02.5)`
- `check-docs.ps1`: `docs-quality: PASS (134 documents, 95 source documents checked, 180 links)`
- `build.ps1 -Test -Deploy:$false`: 0 warnings, 0 errors, 1847/1847 tests passed.


## Promotion campaign (2026-10-09)

- Ticket `PLAN/SP-0039_free_promotion_campaign.md` (In Progress) - the campaign canon [PROMOTION](../../PROMOTION.md) was distilled from. Amended 2026-10-09: open point O4 (host root) moved to the hub ticket, phase 3 uses the host-root property when it exists, plus an own Scoop bucket fallback, dev.to and Lobsters rows, and the positioning statement.
- DIVERGE (DOCUMENTATION_CONCEPT.md section 3, the SEO block; 2026-10-09, SP-0039): the site's `SoftwareApplication` block carries no `ratingValue` or `aggregateRating`, and no `softwareVersion` - `PAGE-CONTENT` allows no claim the page cannot demonstrate and the product has no rating it can show, and `SITE-EXPERIENCE` rule 13 allows no page to name a version it did not render from the landing's source (the landing resolves its release at run time); the block states a zero price, the operating system, `inLanguage`, a durable `releases/latest` download address and the locale's screenshot instead. The same section's "sitemap.xml + robots.txt at the site root" is met for the sitemap by console submission (SP-0039 phase 3) and for robots only nominally: a `robots.txt` under the project path is read by no crawler (RFC 9309), so the host-root file belongs to the hub's promotion ticket (SP-0039 open point O4, resolved 2026-10-09). Evidence: `tools/site/SiteDiscovery.ps1` (`Get-JsonLd`), `docs/robots.txt`.
- 2026-11-07, site audit: 0 HIGH, 21 MED (of 76 findings) recorded in ticket SP-0039 (In Progress); the 2026-11-03 baseline re-measured: 8 open (the console half of #1 not re-measured), 0 partial, 0 fixed, 1 re-graded by the canon (no finding today); criterion 14 added.

## In-app help (2026-10-16)

- Ticket `PLAN/SP-0230_in_app_help_f1_and_a_help_button_on_every_window.md` (Draft), created by the canon session from the owner's request for F1 and a `?` button in every product ([UI_UX](../../UI_UX.md) §7, contract `CONTEXT-HELP` 0.1). 18 `Window` classes and 6 Settings pages (about 24 map rows), no F1 handler yet, 13 locales; overlaps SP-0224 (portal links); five owner decisions are in the ticket.

## Canon delivery reconciliation 2026-10-17 (S4307)

- Installed plugin `2026.1017.1` from published canon `2026.10.17.1` (`d06a64a`). The harness counts Done and Skipped as finished and preserves the phase-counter suffix.
- Re-read the changed canon guidance for delivery, documentation, localization, layout and sealed contracts. Existing product implementation and contract catch-up work remains owned by the recorded project tickets; this delivery check does not certify every product contract.
- Re-stamped through `restamp-canon.ps1` against the installed plugin reader: version, freshly computed core digest and reconciledOn move together; adoptedOn and project-specific fields stay unchanged.
- Compliance for Streams_Player: 0 error(s), 1 warning(s) before; 0 error(s), 0 warning(s) after; exit 0. Canon freshness findings cleared.

## Exchange server mark (2026-10-19)

- Ticket `PLAN/SP-0234_exchange_server_mark_in_the_product_ui_and_docs.md` (Draft, not queued), created by the canon session from the owner's order of 2026-10-19 for one shared sign of the exchange server in every product (contract `EXCHANGE-MARK` 0.1). 19 inventory rows (12 surfaces get or may get the mark, 7 recorded as none, absent or left without), two server-bays glyphs to replace (`source.exchange-server`, `feature.server-relay`), 17 system message boxes that cannot draw it, 13 locales; overlaps SP-0224 (the glyphs), SP-0230 (help pages) and SP-0222; nine conflicts for the catalog and six owner decisions are in the ticket.

## Test lab report (2026-10-23)

- Ticket `PLAN/SP-0242_report_the_test_lab_to_the_portfolio.md` (Draft, not queued; `PLAN/` is git-ignored), created by the canon session from the owner's order of 2026-10-23 to collect what every project knows about its hardware, emulators and test practice (contract `TEST-LAB` 0.1, draft). Documentation only: the product files one inventory report and a pointer; no code, test or harness changes. Reports to the Windows profile owner (FMS_Win).

## Fast checks between releases (2026-10-29)

- Ticket `PLAN/SP-0256_fast-checks-only-between-releases.md` (Approved, first in `PLAN/PQ_QUEUE.md`; `PLAN/` is git-ignored), created by the canon session from the owner's order of 2026-10-29 to switch off full builds and tests longer than 5 s between releases (canon TESTING_AND_QA section 2, highest priority). The product inventories every between-release build and test (push and pull-request CI, the validation ladder, the agent-rules commands), classes each as fast or release from recorded times, and moves the full build, the full suite and the CI waits of `release.yml` and `pages.yml` onto the release path.

## Record split 2026-11-18 (canon ticket S0120)

Every section of this file dated before this one was moved here verbatim from [../streams_player.md](../streams_player.md) when the record was split into facts and history. A line number quoted inside such a section counts lines of the record as it was before the move; relative links were deepened by one `../`; nothing else changed.
