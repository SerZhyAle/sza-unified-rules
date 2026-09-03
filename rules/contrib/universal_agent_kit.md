---
# Contribution: universal-agent-kit (no overlay - public distillation + static site) -> Unified_Rules
Source repo: p:\WEB\universal-agent-kit | Date: 2026-07-23
Read: README, NEW_PROJECT_CHECKLIST, AI_USAGE, contrib/TEMPLATE; deduped against: all six existing contrib files (none overlap - this is not a product repo)
---

Not a consumer of the canon but its **public sibling distillation**: the repo publishes `kit/` (a
stack-neutral set of agent rules, slash-commands, subagent briefs, and method docs) plus a static
marketing site and a downloadable `universal-agent-kit.zip`. The canon already names it - README
"neighbouring kits .. must not duplicate", AI_USAGE.md:5-6 "The fuller public distillation lives in
the universal-agent-kit repo". The relationship is a **third consumption model** the README's
reference/mirror split does not cover (recorded below). Everything method-level is CONFIRM against
AI_USAGE.md; what is genuinely new here is the *obfuscation posture* a public render of the canon
must hold, and the fact that this repo is spread into by **alignment**, never by consumption - so it
is deliberately absent from SPREAD_BACK_PROMPT.md's target table.

## Overlay facts (verified against this repo)

Standard product overlay facts mostly do not apply - this is a docs-kit + static site, not a built
product. Recorded honestly rather than forced into the four-fact shape:

- **Source root & release-mechanics.** The product is `kit/` (Markdown: `CLAUDE.md` template,
  `AGENTS.md` pointer, `.claude/commands/*`, `.claude/agents/*`, `docs/*`, `memory/*`) rendered two
  ways: the root static site (`index.html`, `og-image.png`, `sitemap.xml`, `robots.txt`, `.nojekyll`)
  and `universal-agent-kit.zip`. No compile step. Release-mechanic = edit `kit/` -> rebuild the zip ->
  deploy the static site. (evidence: repo root `ls` shows `kit/`, `index.html`, `universal-agent-kit.zip`,
  `.nojekyll`, `sitemap.xml`, `robots.txt`; no `src/`, `tests/`, build tooling.)
- **Version shape.** None - rolling release. No `CHANGELOG`, no semver anchor; the site and the zip are
  regenerated in place. (evidence: no `CHANGELOG*` at root; README carries no version.) DIVERGE from
  DOCUMENTATION_CONCEPT §2 - legitimate for a living reference kit.
- **Channels + listing files.** Public GitHub repo + a static web property. Listing sources = the site
  page (`index.html`, tri-lingual RU/EN/UK) and `kit/README.md` + root `README.md`. No app-store
  channel. (evidence: `index.html` language blocks; `robots.txt`/`sitemap.xml` present.)
- **Frozen anchors.** The published site URL/domain, the repo name, and the zip's extraction root
  (`universal-agent-kit/`, not `kit/`). (evidence: zip layout recorded in owner memory; site files at
  root.)
- **Editions + parity mechanism.** None - single artifact. But note the cross-repo contract that is
  the point of this repo: `kit/` is a **one-way obfuscated render** of the canon's AI_USAGE.md (and
  neighbouring shared method), kept aligned by hand, scrubbed of every canon-private path/name.

## Channel-matrix rows (this project)

No app-store or package-manager channels. The only publishing surfaces:
- GitHub repo | push | free | git auth | n/a | `README.md` + `kit/README.md` | repo name | browse the repo
- Static site | deploy static files | free | host auth | n/a | `index.html` | site URL/domain | open the URL
- Distributable zip | rebuild on any `kit/` change | free | n/a | n/a | `universal-agent-kit.zip` | extraction root `universal-agent-kit/` | unzip and diff against `kit/`

## Deltas by document

### AI_USAGE.md
- CONFIRM (this repo is the fuller public distillation of exactly this doc): §1 autonomy /
  don't-ask-what-arch-answers / surface-UI-ambiguity / push-back-once -> kit `CLAUDE.md` §1-2; §2
  evidence-over-confidence -> kit `CLAUDE.md` §10 + `docs/VALIDATION.md`; §3 inline-vs-subagent,
  per-subagent tool budget, MCP-off-for-readers, fan-out ceiling, model-tier routing -> kit
  `CLAUDE.md` §12 + `docs/COST.md`; §4 four memory types, committed-vs-per-user is a per-project
  choice, memory-is-point-in-time -> kit `CLAUDE.md` §11 + `docs/AGENT_MEMORY.md`; §5 rules-file +
  named-skill routing, author-after-observed-failure, trigger-focused descriptions -> kit `CLAUDE.md`
  §4/§9 + `docs/AUTHORING.md`; §7 match-owner-language / English-in-code / dry-concise /
  no-trailing-summary -> kit `CLAUDE.md` §1. No contradictions found on any shared rule.
- DIVERGE (§6 documentation-context loop): the canon's `docs/DOCUMENT_REGISTRY.jsonl` doc-context
  loop has no direct counterpart in the public kit. The kit carries the *principle* in generalized
  form (`docs/VALIDATION.md`: keep a "ship-together surfaces" manifest, re-validate registered
  surfaces on change) but deliberately omits the portfolio-specific JSONL registry mechanism. This is
  correct obfuscation, not drift: a public kit must not ship a private registry format. (evidence:
  `grep -rniE "DOCUMENT_REGISTRY|document registry|doc.context loop" kit/` returns nothing; the
  generalized manifest rule is `kit/docs/VALIDATION.md` post-change discipline.)

### DOCUMENTATION_CONCEPT.md
- CONFIRM (§5 house text style): the kit follows it and actively enforces it - the in-flight working
  tree converts en-dash to plain hyphen across `kit/.claude/commands/*` and adds the portfolio
  provenance sentence to `kit/README.md`. (evidence: `git diff HEAD` shows en-dash -> hyphen edits in
  seven command files; no `...`/em-dash introduced.)

### REPOSITORY_LAYOUT.md
- DIVERGE (no product skeleton): no `CHANGELOG`, `tests/`, `docs/{specifications,roadmaps,contracts}`,
  or overlay release-mechanics folder. Legitimate - a docs-kit + static site is not a built product.
  The kit *ships* that skeleton as its template; the repo hosting it does not need to *be* one.

## No delta

Core docs with nothing to add for this repo: PLATFORM_OVERLAYS, RELEASE_AND_DISTRIBUTION,
CHANNEL_MATRIX, WINDOWS_PACKAGING, DEVELOPMENT, TESTING_AND_QA, GITHUB_INTERACTION, LOCALIZATION
(the site's RU/EN/UK is content, not the string-parity workflow), SECURITY_AND_PRIVACY,
SUPPORT_AND_FEEDBACK, SITE_CONFIGURATION, AUTHOR.

## Candidate core edits (PROPOSED - apply only on owner instruction)

- **README.md "How a project consumes these rules"**: add a third bullet next to reference/mirror -
  **sibling distillation**: a separate public repo that re-expresses the canon (or a subset) in
  obfuscated form for an outside audience; kept aligned by hand, never carries a canon pointer, and is
  spread into by alignment audit rather than by the SPREAD_BACK prompt. Names the relationship this
  repo has so the next survey does not try to treat it as a consumer.
- **SPREAD_BACK_PROMPT.md Notes**: one line that sibling-distillation repos (universal-agent-kit) are
  audited for alignment, not run through the consumption steps, and carry no canon pointer.

## Candidate NEW docs (not in any shared doc yet)

- None required.

## Open questions for the owner

- **Private dev rules file (option C, deferred this session).** The repo has no root dev-`CLAUDE.md`
  governing development of the kit itself - only `kit/CLAUDE.md`/`kit/AGENTS.md`, which are the
  *shipped artifact* (a `<PLACEHOLDER>` template). A private, git-ignored root `CLAUDE.md` could carry
  the canon pointer safely (never entering the zip or the site). Decision pending.
- **Canon §6 doc-context loop.** Keep it omitted from the public kit (current recommendation - it is a
  portfolio-specific mechanism), or fold in a generalized "document registry" doc? No action taken.

## Spread-back applied 2026-07-23

Scope run: alignment audit (A) + this contrib record (B); owner chose to skip the mechanical
consumption steps (2-5 of the prompt) because this repo is a sibling distillation, not a consumer,
and to defer the private dev-rules file (C).

- **Pushed back once with evidence** that the standard spread-back does not apply: adding a canon
  pointer would leak the private canon path/site-name into a public repo (grep confirmed the repo
  carried zero canon/private references, only the deliberate public FastMediaSorter provenance), and
  `kit/CLAUDE.md` is the shipped product, not this repo's dev-rules file. Owner confirmed A + B.
- **Alignment: strong.** Every shared AI_USAGE.md rule is reflected (obfuscated) in `kit/`; no
  contradiction found. In-flight working-tree edits are all house-style/alignment (en-dash -> hyphen,
  provenance sentence, VALIDATION "Red flags" section), no drift, no leak.
- **One recorded divergence:** AI_USAGE §6 doc-context loop is generalized into the kit's
  ship-together manifest rule, JSONL registry omitted by design.
- **No repo edits made** - the audit found nothing to fix. No canon pointer added (by design).
- **Canon changes needed:** none applied from this session. Two PROPOSED core edits above (README
  third consumption model; SPREAD_BACK note) await an owner canon-session.
- Canon @ ed69f27; kit repo @ 7915751.

## Questions closed

- "Is universal-agent-kit an EXISTING or NEW consumer?" -> Neither: sibling distillation. Recorded.
- "Does the public kit leak canon-private detail?" -> No (grep evidence above).
- "Does the kit contradict the canon on any shared rule?" -> No; one legitimate DIVERGE recorded.

## Remains

- Owner decision on the private dev-rules file (C) and on canon §6 generalization.
- Owner to apply the two PROPOSED canon edits in a canon session (then run tools/check-rules.ps1).

## Canon adoption 2026-07-27 - deliberately none

Confirmed out of scope and left without a `.sza-canon.json` stamp. This repo is a public, scrubbed **render**
of the canon, spread into by alignment rather than consumption, and putting a canon pointer here would leak
canon-private paths into a public repo - the objection recorded above still holds. It is not a gap in the
rollout; it is the third consumption model this record already describes.

## Canon adoption 2026-08-05 - the 2026-07-27 refusal reversed, on the owner's decision

**The refusal above is superseded, and the reason it was written is gone.** The 2026-07-27 entry left this
repo without a stamp because "putting a canon pointer here would leak canon-private paths into a public
repo". The canon is now itself a **public** repo shipping a public plugin
(`github.com/SerZhyAle/sza-unified-rules`, verified `visibility: PUBLIC`), so a pointer names a public
marketplace and leaks nothing. The owner was shown that and chose to adopt with a **tracked** dev-rules file.

The second objection from 2026-07-23 was real and survived on its own merits: `kit/CLAUDE.md` is the
*shipped product*, a `<PLACEHOLDER>` template, so `adopt-canon` step 4 had no legitimate target. That is
what deferred option C for two weeks. It is closed now by creating the missing file rather than by
repurposing the payload.

**The framing that dissolves the old contradiction.** This repo is two things at once, and the record kept
trying to make it one:

- it **consumes** the canon for its own development - root `CLAUDE.md`, `.sza-canon.json`, model
  `reference`;
- it **publishes** `kit/` as a scrubbed, stack-neutral sibling distillation of the shared method for an
  outside audience.

Those do not conflict. The scrub rule survives adoption intact and is now written down where it binds:
the canon pointer lives in the root file, and `kit/` still must never name a product, a portfolio path, or
a canon-internal doc.

### What was created or changed in the repo

| File | Change |
| --- | --- |
| `.sza-canon.json` | NEW. Canon 2026.08.05, digest `sha256:8d33fdab..`, model `reference`, `adoptedOn` 2026-08-05. `role: portfolio` because there is no product build and no platform overlay to declare - the only thing the gate reads `role` for - with the sibling-distillation relationship written into the stamp's `$comment`. `tagRegex: null` (0 tags), `ledgerShape: "none"` (rolling release), `channels: []`. `site` confirmed against the Pages API, not assumed: `source.branch main`, `path /`, `html_url https://serzhyale.github.io/universal-agent-kit/`. |
| `CLAUDE.md` | NEW, tracked, at the repo root. The canon pointer plus the four things that are genuinely this repo's: `kit/` is payload and never governs work here; the scrub rule; the three render targets with the frozen anchors (zip extraction root `universal-agent-kit/`, the Pages domain, the repo name); the rolling-release DIVERGE. It restates no canon rule. |
| `.gitignore` | Leak globs added (SZA-SEC02), and `!universal-agent-kit.zip` with a why-comment (SZA-SEC03) - the zip was already tracked deliberately, but the reason lived in a comment on the *staging* directory, where the gate could not attach it to the artifact. |

### Alignment fixes applied to `kit/` - the reason this pass was worth running

The audit against canon 2026.08.05 found the kit to be **upstream of finding 2 in every repo that imported
it**, which is a stronger result than a normal reconcile produces:

- `kit/CLAUDE.md` §4 shipped the ladder `/quick` -> `/fix` -> pipeline as **prose with nothing behind it**,
  and `kit/.claude/settings.json` shipped **no `hooks` section at all**. EPUB_2_HTML's identical, ungated
  ladder is a confirmed import of exactly this. Fixed at the source: §4 now carries the measurement (434
  invocations, `/quick` 0, `/fix` 2, pipeline 150) and the prompt-submit remedy, and `settings.json` carries
  a `//hooks-example` key in the file's own established pseudo-comment style. **Left as an example, not
  wired** - a `hooks` entry pointing at a script the downstream user has not written yet would fail on every
  prompt, which is a worse defect than the one being fixed.
- `kit/docs/COST.md` argued context hygiene **on answer quality** ("answer quality degrades as it fills")
  with no measurement behind it - precisely what the `agent-cost` skill's own guardrail forbids, since
  attaching a real practice to an unprovable rationale is how the practice gets reverted. Rewritten to argue
  it on cost, which is measurable, with the quality claim gated on having actually measured it.
- COST.md gained a **"Measure before you rule"** section. Scope note, because it exceeds what was asked: the
  owner approved propagating the *channel* rule, and all four corrections went in. Shipping the channel rule
  alone would have published a method that still inflates token totals roughly threefold through the
  request-id defect - a known-broken method in a public kit. Named here rather than done quietly.

No SZA product name, portfolio path or canon-internal doc name entered `kit/` in any of these edits; the
measurements travel as "a project" and "the reference corpus".

**No saving is claimed anywhere in the kit text.** The hook shipped on 2026-08-05 with no post-change
window behind it, and `skills/agent-cost` step 4 forbids presenting a carry-forward as an effect.

### Verification

`check-compliance.ps1 -RepoRoot P:\WEB\universal-agent-kit`: before **3 error(s), 1 warning(s)**
(SZA-CANON01 no stamp, SZA-RULES01 no root agent-instructions file, SZA-SEC03 the tracked zip; SZA-SEC02
missing leak globs) -> after **0 error(s), 0 warning(s)**, exit **0**. Both edited JSON files re-parsed
clean. `check-rules.ps1` in the canon: exit **0** (19 core docs, 11 contrib docs).

One mechanical detail worth recording, because it will bite the next adoption: SZA-RULES01 counts **tracked**
files only, by design - a git-ignored rules file is one person's scratch copy. A brand-new root `CLAUDE.md`
therefore does not clear the error until it is at least staged. That is also the concrete argument against
the git-ignored variant of option C: it would have left this repo permanently failing SZA-RULES01.

### Questions closed

- "Private dev rules file (option C, deferred 2026-07-23)" -> **closed**: created, tracked, not git-ignored.
- "Is this repo a consumer or a sibling distillation?" -> **both**, and the two roles are recorded
  separately above.
- "Does adopting leak canon-private detail into a public repo?" -> **no**: the canon repo is public.

### Remains

- **Not committed.** The working tree is staged and the gate is green against the staged index; the commit
  and any push are the owner's to make.
- The two PROPOSED canon edits from 2026-07-23 are still unapplied, and one now needs rewording:
  `README.md`'s third consumption model can no longer be described as "never carries a canon pointer",
  because this repo now does. The accurate shape is *a repo that consumes the canon for its own development
  while publishing a scrubbed render of it as product*. `SPREAD_BACK_PROMPT.md` still exists in the canon
  and its note is unwritten.
- Canon §6 doc-context loop stays omitted from the public kit, unchanged from 2026-07-23 - still a
  portfolio-specific mechanism, still correctly generalized into `kit/docs/VALIDATION.md`.
- `role: sibling-distillation` does not exist in `check-compliance.ps1`; `portfolio` was used because it is
  mechanically correct for the one thing `role` decides. A dedicated value would be more honest and is a
  candidate canon edit, not a blocker.

## Canon alignment 2026-08-18 - the five transferable additions of canon `2026.08.18.1`

Second half of a two-session pass: a canon session read this repo on 2026-08-18, re-stamped it, and wrote
a hand-authored work order into the repo's `temp/`. This entry records executing that order. **The stamp
was ahead of the alignment until now**, which is exactly the condition `SZA-CANON03` exists to catch; it is
closed by this pass. Stamp at the end: `2026.08.18.1` / `sha256:961c9c8a..` - and note that a *concurrent*
canon session bumped both the canon HEAD and this repo's stamp mid-run (from `2026.08.18` /
`sha256:03bc1c8c..`). The reconcile below was performed against the `9fea564..HEAD` diff, i.e. against
`.1` content, so the stamp is truthful either way.

The posture is unchanged and governs every line below: `kit/` is a scrubbed, stack-neutral distillation
for an outside audience. No canon name, no product name, no portfolio path, no canon-internal doc name
travels. Measurements travel **with their shape and their window, without their provenance**.

### What changed, per target

| Target | Change |
| --- | --- |
| `.gitignore` | `temp/` added. The canon's scratch-tree rule was unenforced here, and the work order itself was sitting in `temp/scratch/` untracked-but-committable. Done first, before anything else. |
| `kit/.claude/agents/*.md` (4) | **The payload defect.** All four shipped `model: inherit`, so a kit that teaches tier routing for *skills* demonstrated the opposite for its own *agents* - and every downloader inherited it. Now pinned: `solution-researcher` light (read-only search), `implementer` and `doc-writer` mid, `rd-lead` strong. Each pin carries a one-line YAML comment saying the tier names are the harness's and a downloader on another runtime maps them. |
| `kit/docs/COST.md` | Section retitled "Model-tier routing - per skill, and per spawn" and given the subagent half: the built-in general-purpose agent **cannot** carry a pin, so the remedy is naming the tier at the call site or routing through a pinned agent; every project-defined agent gets an explicit tier because *nobody audits an invisible default*. New section "Serializing a shared resource - a queue, not a refusal" with the eight transferable lock-queue rules. |
| `kit/docs/SPEC_LIFECYCLE.md` | New section "Two literal tokens: direction, and the question that leaves with a closed ticket". Defines `Blocked-by` and `Carried-to` as mandatory header tokens, states which of the two is actually enforced and how, and carries the four gate mechanics (gate the transition not the state; never gate archive; an unfilled placeholder counts as unanswered; locate a section by heading text and wire the gate into every closing path). |
| `kit/docs/HOOKS.md` | **New doc.** The kit used "hook" only to mean *a place to wire a gate*; a hook is a **verdict on an event**. Carries the seven-verb vocabulary, the preference order (correct the input; refuse only where no correct input exists), the per-verdict contracts, the turn-refusing shape, the hook inventory rule with its two anti-crying-wolf limits, and the pre-filter testing rule. |
| `kit/docs/VALIDATION.md` | "A green can lie" gained the backgrounded-gate worked example - a gate that cannot run still reports success - plus "prefer making a name work over guarding it", both stripped of their OS specifics. |
| `kit/docs/AUTHORING.md` | Fifth row in "Where each kind of directive lives": the event hook, pointing at `HOOKS.md`. The table previously had a hole exactly where an event hook belongs. |
| `kit/CLAUDE.md` | Section 5 gains the two ticket tokens; section 4 points at `HOOKS.md`; section 12 gains the spawn-tier line and the lock-queue line. |
| `kit/.claude/commands/spec.md` | Template header carries both tokens; the owner-inputs step and the Status-lifecycle paragraph now say prose is a mention and the token is the claim; Constraints make both tokens mandatory with `none` as a value. |
| `kit/.claude/commands/spec-check.md` | New check row "Open questions closed" (locate the section by heading, template placeholder counts as unanswered), the scoring note that an unhanded open item refuses `Verified`, and a constraint to gate the **transition** and never the archive. This is the hard half. |
| `kit/.claude/commands/backlog.md` | Reads `Blocked-by` and nothing else; a missing token is a ticket defect, treated as `none` and reported, never guessed from prose. Named explicitly as the **soft** half. |
| `kit/README.md`, `README.md`, `merge-prompt.txt` | Doc lists updated for `HOOKS.md`. Root `README.md` was also missing `AUTHORING` in both its EN and RU trees - a pre-existing staleness, fixed in the same edit. `merge-prompt.txt` is inside the zip and lists every doc, so it needed the row too. |
| `universal-agent-kit.zip` | Rebuilt: 42 entries, verified byte-identical to `kit/` + `merge-prompt.txt` by per-file SHA-256. Extraction root `universal-agent-kit/` unchanged. |

### Deliberately not propagated

- **The Windows / Git-Bash trap family** (a shell-specific cmdlet in command-head position, an interpreter
  that resolves nowhere, a path-translating shell rewriting an argument). Stack-specific; a stack-neutral
  kit has no business carrying it. Only the two generalizable sentences travelled, into `VALIDATION.md`.
- **Every tuning constant in the lock queue** - windows, ceilings, grace periods, timeouts. None was
  measured. The kit states the shape and says explicitly that the constants are per project. Verified
  absent by grep.
- **Any threshold in a hook.** Same reason.
- **A lock implementation.** The kit is method; which file, which shell, which liveness API is a stack
  decision, and shipping a script would make the kit non-neutral.
- **`index.html`.** Section 8 of the work order asserted that a new doc "changes the doc list, so it
  touches all of them", naming the page. That is wrong for this page: `index.html` is a narrative article
  and enumerates no doc list at all - grepping it for `SPEC_LIFECYCLE`, `CODE_QUALITY`, `AGENT_MEMORY` or
  `COST` returns nothing. Nothing on the page is now false, so nothing was hand-edited into it. Padding a
  marketing article to satisfy a checklist is not what the ship-together rule asks for.
- **The `//hooks-example` stance**, kept exactly as it was: left as an example, not wired. It is itself an
  instance of the preference order.
- **The provenance credit in `kit/README.md`.** The work order's scrub regex demanded that name come back
  empty from `kit/`. It does not, and should not: the credit is deliberate, is published on the site in all
  three locales, and predates every scrub rule. The scrub that matters - the canon's own name and any
  absolute portfolio path - comes back empty. Flagged rather than silently deleted.

### Honesty constraints held

- **No effect data exists** for any of this as a kit rule. What is measured is the failure each rule was
  built for, never the improvement it produced. Nothing here is presented as a saving; `COST.md`'s own
  "Measure before you rule" section forbids it and the new tier paragraph says so in its own text.
- **The five numbers that travelled**, each with its window: 479 seconds of one lock held across a phase;
  381 blocks in a week with 31.8% answered by reading the whole file anyway; 134 of 1 506 closures carrying
  an open question (8.9%); 98 files yielding an id against 15 carrying a direction; 182 spawns of an
  unpinnable type in 14 days against an 82.8% expensive-tier output split - with the causal link labelled a
  **deduction, not a measurement**, and the further caution that a tier split is an output figure while
  cached input dominates the bill.
- **One deviation from the work order's recommendation, argued rather than taken silently.**
  `doc-writer` was proposed for the cheap tier; it is pinned mid. Its brief is about tone, warmth and
  not-changing-meaning - a judgement call, not a lookup - and the kit's own routing rule reserves the cheap
  tier for mechanical leaf work. `solution-researcher` remains the clear light-tier case and is pinned
  there. The tier mapping was called "a proposal, not a law" in the order; this is the one place it was
  overridden.
- **Substance stated once.** The false-PASS rule lives in `VALIDATION.md` and `HOOKS.md` points at it,
  rather than both carrying it - `AUTHORING.md` forbids pasting the same paragraph into three files.

### Verification

| Check | Expected | Actual |
| --- | --- | --- |
| `check-compliance.ps1` in the repo | exit 0, no errors | **0 error(s), 0 warning(s)**, exit **0** (canon 2026.08.18.1). Baseline before the pass was 0 errors / **1 warning** (SZA-CANON03 stale digest) |
| Agent frontmatter still parses | four files, `model` resolves to a bare tier name | PyYAML: `sonnet`, `sonnet`, `opus`, `haiku`; the `tools` list on `solution-researcher` intact. The inline `#` comment is stripped, as the harness's own frontmatter reference documents |
| No unpinned agent left | zero hits for `model: inherit` under `kit/.claude/agents/` | zero |
| Accepted values for the `model` field | verified, not assumed | `inherit` / `sonnet` / `opus` / `haiku`, from the harness's own agent-development skill ("### model (required)") - which incidentally *recommends* `inherit`, so the pin is a deliberate departure on cost grounds |
| Zip vs source | every `kit/` file byte-identical inside the archive | 41 kit files + `merge-prompt.txt` = **42 entries**, **0 mismatches** by per-file SHA-256 |
| Tuning constants absent from `kit/` | no window / ceiling / timeout numbers | grep for `grace period of`, `timeout of N`, `ceiling of N`, `N ms/seconds window` - empty |
| Scrub | no canon name, no absolute portfolio path | empty. The one provenance name is present once, deliberately, see above |
| House style in the new prose | no em-dash, no three-dot ellipsis | grep across `kit/` for U+2013 / U+2014 / U+2026 and the literal three dots - only `go build ./...` inside code spans |
| Every doc reference resolves | no dangling `docs/*.md` link | all resolve; the only unresolved names are `<PLACEHOLDER>` examples (`ARCHITECTURE.md`, `PARKED.md`) |

### Remains

- **Not committed.** The working tree carries every change and the gate is green against it; the commit and
  any push are the owner's.
- `.vscode/` sits untracked at the repo root and is neither ignored nor committed. Out of scope for this
  pass, named so the next survey does not re-derive it.
- The owner's per-project memory index for this repo points at three memory files that no longer exist.
  Also out of scope, also named.
- A candidate canon edit, unchanged from 2026-08-05: `role: sibling-distillation` still does not exist in
  `check-compliance.ps1`; `portfolio` remains mechanically correct for the one thing `role` decides.
- Canon @ 6906983 (moved mid-session by a concurrent canon session); kit repo @ 0880457 + working tree.

## Canon re-sync 2026-09-03 - canon `2026.09.03.3`

Pure re-sync, entered through `SZA-CANON03`: the stamp read `2026.08.18.1` / `sha256:961c9c8a..` against
a canon at `2026.09.03.3` / `sha256:cdf49be6..`. Baseline gate **0 error(s), 1 warning(s)**, exit 0 - the
warning being exactly that staleness and nothing else, so the alignment work from 2026-08-18 held.

Five rule docs moved between the two versions (`AI_USAGE`, `DEVELOPMENT`, `DOCUMENTATION_CONCEPT`,
`INVARIANTS`, `TESTING_AND_QA`), diffed against the still-cached `2026.818.2` plugin rather than re-read
whole. All five carry transferable method; none needed a repo behaviour change; all five reached `kit/`.
The posture is unchanged and governed every line: no canon name, no product name, no portfolio path, no
canon-internal doc name travels, and measurements travel **with their shape and their window, without
their provenance**.

### What changed, per target

| Target | Change |
| --- | --- |
| `.sza-canon.json` | Re-stamped to `2026.09.03.3` / `sha256:cdf49be6..`, `adoptedOn` 2026-09-03. Digest recomputed with `-PrintDigest`, not copied. Nothing else in the stamp moved: no product build appeared, no channel, no tag, so `role`, `overlay`, `versionShape`, `ledgerShape` and `site` are unchanged and still true. |
| `kit/docs/COST.md` | Three additions. **Context hygiene** gains the process-boundary reset for unattended runs - a driver outside the session running each item in a fresh headless process, because a self-imposed halt depends on somebody noticing a threshold and an unattended run has nobody watching; carries the 83%-above-150k observation with an explicit note that the threshold is that machine's window and not a recommendation, plus the two things the boundary buys on top of the reset (per-item model choice, several instances at once). The **lock queue** gains the (kind, domain) rule with its three anti-deadlock clauses and the 12 s observation, and the abandoned-intent withdrawal rule with the one half of it that self-heals. |
| `kit/docs/VALIDATION.md` | Four additions. A new rung note **"The top rung is often a human, and a human check has not happened yet"** - no failures plus an unobserved manual line scores *needs a human test*, not *verified*; carries the five-acceptance-criteria observation and points at `SPEC_LIFECYCLE.md` / `/spec-check`, which already own the mechanics. **Post-change discipline** now says *every surface and every authored locale*, with the release-boundary batching for the rest of the declared set and the continuously-published exception. **Composition** gains "the closure RUNS the rung; it does not merely ask for it", with the closed-green broken-layout failure. **Closing a change on a dirty tree** gains "Place a gate by its subject, not by how much it once hurt" - the four-part release-scope test, the three keep-per-change conditions, both corollaries, and the 68-of-191 / 33-minutes measurement. |
| `kit/docs/AUTHORING.md` | The automated-gate row in "Where each kind of directive lives" now says a gate names its **scope class** at birth and that unnamed defaults to per-change. One clause, pointing at `VALIDATION.md` - the substance is stated there once. |
| `kit/CLAUDE.md` | Section 10 gains the human-check line and the authored-locale nuance; section 12 gains the lock-domain sentence, the withdrawal sentence, and the unattended process-boundary bullet. |
| `kit/.claude/commands/backlog.md` | A blockquote after Step 5: prefer looping the **process**, not the session. This is the payload defect the `AI_USAGE` addition exposed - the kit shipped an unattended drainer whose loop is explicitly in-session, so ticket 1 sits in context while ticket 9 runs. Says where the skip-cache and report buckets must live for the loop to survive a process boundary, and keeps the in-session shape as the fallback where no headless mode exists. |
| `.gitignore` | `.vscode/` ignored, closing an item this record carried twice. Not an owner decision on inspection: the directory holds one `settings.json` containing only a personal editor colour scheme, which the file's own "OS / editor junk" section already covers. |
| `universal-agent-kit.zip` | Rebuilt. 42 entries, 0 mismatches by per-entry SHA-256 against source. Extraction root `universal-agent-kit/` unchanged. |

### Deliberately not propagated

- **Every tuning constant.** The reservation window, the eviction ceiling, the sweep interval. None was
  measured; the kit states the shape and says the constants are per project. The one number in the
  withdrawal rule is a *behaviour* ("granted but not taken inside the window"), not a duration.
- **The canon's own section numbers and doc names.** The kit's cross-references point at kit docs only.
- **`index.html` and the READMEs.** No document was added or removed, so no doc list changed. The page is
  a narrative article that enumerates no doc list - re-checked, not assumed - and nothing on it became
  false, so it was not padded to satisfy a checklist. Both README trees still list ten `docs/*` files
  correctly.
- **The stamp's structural fields.** A re-sync is not an excuse to re-derive facts that did not move.

### Honesty constraints held

- **No effect is claimed for any of it.** Each addition names the failure it was authored against; none
  names an improvement it produced, and `COST.md`'s "Measure before you rule" forbids the latter.
- **The numbers that travelled, each with its window:** 83% of one machine's week above 150k of carried
  context; two module checks running together in 12 s after a lock split; 68 of 191 red lines across 53
  batch runs, and 33 minutes of closure time in a month for one finding; one ticket closed with an
  unticked device line failing one of five acceptance criteria on real hardware; ten unauthored
  translations per key against three authored. The 150k figure is explicitly labelled as that machine's
  window rather than a recommended threshold.
- **Substance stated once.** The gate-scope rule lives in `VALIDATION.md` and `AUTHORING.md` points at
  it; the human-check rule lives in `VALIDATION.md` and defers its mechanics to `SPEC_LIFECYCLE.md`; the
  1-8% prose-compliance figure is cited from `AUTHORING.md`, not restated.

### Verification

| Check | Expected | Actual |
| --- | --- | --- |
| `check-compliance.ps1` | exit 0, no errors, no warnings | **0 error(s), 0 warning(s)**, exit **0** (canon 2026.09.03.3). Baseline was 0 errors / **1 warning** (SZA-CANON03) |
| `.sza-canon.json` re-parses | valid JSON, new version and digest | parsed; `2026.09.03.3` / `sha256:cdf49be6..` / `adoptedOn` 2026-09-03 |
| Zip vs source | every file byte-identical inside the archive | 41 kit files + `merge-prompt.txt` = **42 entries**, **0 mismatches** by per-entry SHA-256 |
| House style in the new prose | no en-dash, em-dash or three-dot ellipsis | only `go build ./...` inside code spans, unchanged from the previous pass |
| Scrub | no canon name, no product name, no portfolio path, no canon doc name in `kit/` | empty. The one FastMediaSorter provenance credit in `kit/README.md` is present once, deliberately, as recorded on 2026-08-18 |
| Doc lists still complete | ten `docs/*` entries in both READMEs | complete; no doc added or removed this pass |

### Questions closed

- "`.vscode/` untracked and neither ignored nor committed" (carried 2026-08-18) -> **closed**: ignored,
  with the reason in the file.
- "The owner's per-project memory index points at three memory files that no longer exist" (carried
  2026-08-18) -> **closed** outside the repo: the index was rebuilt against what exists. One of the three
  was recreated (an editorial standard, not derivable from any file), one was folded into the zip-rebuild
  memory it duplicated, and one was dropped as a verbatim restatement of the global rules file.
  Separately, the `reference-unified-rules` memory was **wrong** and is rewritten: it still asserted that
  this repo carries no canon pointer because one would leak a private path - both halves untrue since
  2026-08-05.

### Remains

- **A candidate canon edit, unchanged since 2026-08-05:** `role: sibling-distillation` still does not
  exist in `check-compliance.ps1`; `portfolio` remains mechanically correct for the one thing `role`
  decides, and the `$comment` still carries the real relationship.
- **The two PROPOSED core edits from 2026-07-23** are still unapplied. The `README.md`
  third-consumption-model wording still needs the correction noted on 2026-08-05 - it can no longer say
  "never carries a canon pointer".
- Canon @ ae5f37f (clean); kit repo committed this session, not pushed.
