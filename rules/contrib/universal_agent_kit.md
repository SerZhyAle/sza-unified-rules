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

> **Keep this note in the record.** Current facts, edited in place. Never append a dated section to this file,
> and append nothing under `history/` either: those files are frozen ([the rules of that folder](history/README.md))
> and are not reading for a task. A delta the core absorbed, a candidate that was applied or refused and a
> question that was answered are deleted here.

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
