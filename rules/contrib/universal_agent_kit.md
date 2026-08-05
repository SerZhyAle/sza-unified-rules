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
