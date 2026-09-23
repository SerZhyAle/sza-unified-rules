# Experience map - sza-unified-rules

> Owner's framing, verbatim. Kept exactly as written, typos included. The sections below check each
> sentence against the repositories and add facts, links and lists.
>
> В основном опыт работы с агентами джобывается во время производства работ над проектом FMS_Android
>
> Там много разных агентов каждый жень ведут работу
>
> Затем его обфусцированная верхушка попадает сюда - унифицированые правила
>
> Отсюда она доминирует при работае с другими моими проектами
>
> Но при работе с этими проектами иногда редко я прихожу к мысли что-то исправить в общем своде законов и распространить на все проекты тоже
>
> Отдельно э проект Universal;-Agent-Kit - он олицетворяет резульат, опыт, который я хочу передать комьюнити. При чем не толкьо программистам, а любым специфоистам, кто работает с агентами над "проектами"

**Snapshot 2026-09-20.** Every number was read from the repositories, from `git`, or from the local Claude Code
transcript store on that date. "(derived)" marks arithmetic done here, not a measurement. "FMS_Android" is read as
the repo `FastMediaSorter_mob_v2`. Anything that goes stale is dated where it appears.

## 1. The flow

```text
FMS_Android (FastMediaSorter_mob_v2)      daily agent work: tickets, hooks, locks, batch runs
    |
    |  (a) distilled: audit findings, hook designs, the harness, the record in rules/contrib/
    v
sza-unified-rules (this repo)             rules/ + skills/ + hooks/ + tools/harness/, shipped as plugin "sza"
    |                       \
    |  (b) plugin, stamp,     \  (d) scrubbed one-way render, aligned by hand
    |      gates               \
    v                           v
the other stamped repos         universal-agent-kit (public, for the community)
    |
    '-- (c) rare: a fix noticed there goes back to the canon
```

- (a) is section 4, (b) section 5, (c) section 6, (d) section 7.
- The owner's word "obfuscated" for (a) is, mechanically, generalization: project paths, prefixes and vocabulary
  move behind one profile seam, and [assert-portable.ps1](tools/harness/assert-portable.ps1) refuses a script
  that still names a product. The canon itself uses "obfuscated" for (d), the public render
  ([universal_agent_kit.md](rules/contrib/universal_agent_kit.md)).

## 2. The portfolio at a glance

| Repo | Role, overlay | Commits (last) | Retained sessions | Canon stamp | Contrib record (lines) |
| --- | --- | --- | --- | --- | --- |
| FastMediaSorter_mob_v2 | product, B Android | 956 (2026-09-20) | 1,880 | 2026.09.06.1 | [fastmediasorter_mob_v2.md](rules/contrib/fastmediasorter_mob_v2.md) (1,331, 52 of them uncommitted) |
| FastMediaSorter_release | second checkout of the same remote | 952 (2026-09-19) | 0 | 2026.09.06.1 | shared with mob_v2 |
| FastMediaSorter_Lite | product, A Windows desktop | 210 (2026-09-20) | 16 | 2026.09.06.1 | [fastmediasorter_lite.md](rules/contrib/fastmediasorter_lite.md) (579) |
| FileDo | product, C Go CLI | 82 (2026-09-20) | 14 | 2026.09.06.1 | [filedo.md](rules/contrib/filedo.md) (540) |
| Streams_Player | product, A | 104 (2026-09-19) | 10 | 2026.09.06.1 | [streams_player.md](rules/contrib/streams_player.md) (520) |
| CyrFlip | product, A | 97 (2026-09-16) | 7 | 2026.09.06.1 | [cyrflip.md](rules/contrib/cyrflip.md) (483) |
| EPUB_2_HTML | product, A | 133 (2026-09-19) | 5 | 2026.09.06.1 | [epub_2_html.md](rules/contrib/epub_2_html.md) (437) |
| OneClickRunner | product, A | 21 (2026-09-06) | 0 | 2026.09.06.1 | [oneclickrunner.md](rules/contrib/oneclickrunner.md) (249) |
| internal_IP_manager | internal, A, no git remote | 5 (2026-09-06) | 0 | 2026.09.06.1 | [internal_ip_manager.md](rules/contrib/internal_ip_manager.md) (193) |
| sza.od.ua hub | portfolio | 30 (2026-09-06) | 1 | 2026.09.06.1 | [hub.md](rules/contrib/hub.md) (187) |
| universal-agent-kit | portfolio, public kit | 30 (2026-09-06) | 1 | 2026.09.08.2 in the working tree, uncommitted (committed: 2026.09.06.1) | [universal_agent_kit.md](rules/contrib/universal_agent_kit.md) (438) |
| sza-unified-rules | canon home | 43 (2026-09-18) | 5 | head 2026.09.18.1 | - |

- Paths: `p:\ANDROID\` (both FMS checkouts), `p:\WINDOWS\` (Lite, FileDo, Streams_Player, CyrFlip, EPUB_2_HTML,
  OneClickRunner, internal_IP_manager), `p:\WEB\` (universal-agent-kit, sza-unified-rules, the hub in
  `sites.google.comsiteszaodua`).
- Overlays: A Windows desktop, B Android, C Go CLI / Wails tool ([PLATFORM_OVERLAYS.md](rules/PLATFORM_OVERLAYS.md)).
- Retained sessions = `*.jsonl` files under `~/.claude/projects/<folder>`. The earliest is 2026-08-20, so older
  sessions are not counted. Total 1,939 (derived): FMS 1,880 (97%), the other eight folders 59 together.
- All 11 stamps carry consumption model `reference`; no repo mirrors the canon.
- The FMS record is 17% (derived) of the 7,637 lines in the 19 rule docs plus 11 contrib files, and longer than the
  next two records combined (579 + 540 = 1,119, derived).

## 3. FMS_Android - where the experience is earned

| Fact | Value |
| --- | --- |
| Repo | [SerZhyAle/FastMediaSorter_mob_v2](https://github.com/SerZhyAle/FastMediaSorter_mob_v2), public. Local `p:\ANDROID\FastMediaSorter_mob_v2` |
| History | 956 commits on the checked-out branch, from the 2026-02-09 "Initial commit - clean history" to 2026-09-20 |
| Tickets | 2,389 driven through the harness by 2026-09-03 (S2402); ids reached S3336 on 2026-09-19 (an id, not a count) |
| Retained sessions | 1,880 in 2026-08-20..2026-09-20, about 59 a day (derived), 2.6 GB of transcripts |
| Volume in its own audits | 347 main + 869 nested subagent transcripts (1.7 GB), 2026-06-30..2026-07-31. 497 sessions in 954 files, 31,776 unique requests, 38,699 tool calls, 2026-08-05..2026-08-11. 520 sessions, 346.7 active hours, 2026-08-14..2026-08-28. Definitions differ, so do not divide one row by another |
| Not all hand-driven | the batch runner starts headless `claude -p` children ([run-spec-queue.ps1](tools/harness/batch/run-spec-queue.ps1), [monitor-spec-queue.ps1](tools/harness/batch/monitor-spec-queue.ps1)) |
| Product | overlay B; modules `:app_v2`, `:wear`, `:lint-rules`, `:benchmark`; 6 flavors over Google Play (standard, lite, photos, legacy), sideload (noLegal), Meta Horizon Store (vr) and a GitHub Pages site; sibling editions FastMediaSorter_Lite (Windows) and fms_companion (Go), tied by the frozen wire contract `FMSCFG` (the `.fmscfg` file, as recorded 2026-07-23) |

### Five agent runtimes named in the repo's own rule files

- Claude Code - `CLAUDE.md`.
- Codex and ZCode - `AGENTS.md`, which is "this file only" as their repository contract.
- Gemini CLI - `GEMINI.md`, "the shortest of four descriptions of the same repository".
- GitHub Copilot - `.github/copilot-instructions.md`, named in `AGENTS.md`.
- Hooks protect only Claude Code. `AGENTS.md` tells the others "Claude hooks do not protect your tool calls", so a
  gate refusal in the harness is the one place a rule reaches every runtime (record, 2026-09-05).

### Agent surface in the repo

- 6 role agents in `.claude/agents/`: android-device-operator, android-kotlin-developer, android-rd-specialist,
  android-solution-researcher, friendly-android-doc-writer, repo-mechanic.
- 42 command files in `.claude/commands/`: the spec pipeline (`spec`, `spec-tech`, `spec-dev`, `spec-check`,
  `spec-fix`, `spec-all`, `spec-sweep`, `spec-draft`, ..), `quick`, `research`, `build`, `release`, `skill-fix*`,
  and short aliases in two layouts (`/sd`, and the same keys on the Cyrillic layout `/ыв`), generated by
  [generate-command-aliases.ps1](tools/harness/aliases/generate-command-aliases.ps1) because the owner types in two
  keyboard layouts.
- 14 hook scripts in `.claude/hooks/`: `guard-catalog-before-kt-search`, `guard-manual-task-wait`,
  `guard-mcp-one-way-tools`, `guard-release-freeze`, `nudge-check-target-by-change-type`, `nudge-context-budget`,
  `nudge-small-task-tier`, `observe-empty-grep`, `observe-plan-tick-batching`, `post-agent-chat-session`,
  `refuse-spec-do-stop`, `refuse-unexplained-red-verdict`, `reset-catalog-touch-marker`,
  `sweep-agent-lock-queues`.
- 3 project skills (`document-registry`, `run-fastmediasorter`, `screenshot-usability-audit`), 4 path-scoped rule
  files (`agent-chat`, `android-source`, `command-authoring`, `spec-catalog`).
- Root files for the runtimes and tools: `CLAUDE.md`, `AGENTS.md`, `GEMINI.md`, `.claudeignore`, `.aiexclude`,
  `.zcodeignore`, `.mcp.json`, and `.sza-profile.json` (the harness seam).

### Its own audits of agent work (local, `p:\ANDROID\FastMediaSorter_mob_v2\dev\`)

- `AGENT_PROCESS_AUDIT_2026-07-31.md` (282 lines): 13 parallel dimension audits, 26 adversarial verifications and one
  synthesis, run by 40 agents (4.29 M subagent tokens, 63 min wall clock). 143 findings; 26 went through adversarial
  verification and 20 of those were knocked down. Its first pass was wrong by 3x: one API response is written as
  several records that repeat the same `usage`, and a naive sum inflates tokens 3.13x.
- `AGENT_PROCESS_AUDIT_2026-08-12.md` (149 lines): which repeated manual sequences can become a script, a hook or a
  gate. Every finding was parked as its own Draft ticket.
- `AGENT_WORKFLOW.md` (31 lines): the routing page for the size tiers `/quick`, `/skill-fix`, `/spec-all`.

### Measured 2026-08-28: two agents, 31 shared tickets

Prompted by the owner watching another agent close comparable tickets up to 4x faster. Window 2026-08-14..2026-08-28:
520 sessions, 346.7 h of active wall (idle above 15 min excluded), against the other agent's own log of 111 tasks.

- Median ticket wall 16 min (the other agent) against 47 min, for work of the same size: 166 against 190 tool calls,
  28 against 31 edits. The other agent runs the same process, so process volume is not the cause.
- Process machinery is 27.5% of calls and 16.8% of ticket wall. Deleting every gate caps near 1.2x, not 2.9x.
- Turn latency tracks what the model writes (correlation +0.681 with output tokens), not what it reads (+0.065 with
  context size). 76.5% of billed output is hidden reasoning; 5.6% of it reaches a file.
- Two proposals were refuted and recorded as "not raised": relaxing the fire-and-forget guard, and trimming spec
  templates (spec prose is 3.3% of generated tokens).
- Source: "Spread-back applied 2026-08-28" in [fastmediasorter_mob_v2.md](rules/contrib/fastmediasorter_mob_v2.md).

## 4. What crossed from FMS into the canon

### Hooks (2026-08-08, canon 2026.08.08.1)

The canon told projects four times to enforce behaviour at the tool call and shipped zero hooks; the FMS repo had
built them. Generalized on import (project rule numbers replaced by canon section pointers, `SZA_HOOKS_OFF` escape
added):

| FMS hook then | Canon file now | Canon home |
| --- | --- | --- |
| `guard-find-command` (FMS rule 24) | [guard-bash.ps1](hooks/guard-bash.ps1) | [GITHUB_INTERACTION.md](rules/GITHUB_INTERACTION.md) section 6 |
| `guard-ps1-in-bash` (FMS rule 25) | [guard-bash.ps1](hooks/guard-bash.ps1) | same |
| `guard-uncapped-read` | [guard-uncapped-read.ps1](hooks/guard-uncapped-read.ps1) | [AI_USAGE.md](rules/AI_USAGE.md) sections 3 and 5 |
| `nudge-small-task-tier` + machine-global `warn-context-size` | [on-user-prompt.ps1](hooks/on-user-prompt.ps1) | AI_USAGE sections 3 and 5 |
| the canon's own, not from FMS | [session-start.ps1](hooks/session-start.ps1) | [INVARIANTS.md](rules/INVARIANTS.md) |

- The fire-and-forget guard ([guard-fire-and-forget.ps1](hooks/guard-fire-and-forget.ps1)) carries an FMS
  measurement: about 1,300 polling turns and 81 minutes of literal sleep in one month (record, 2026-08-02).
- `guard-find-command`, `guard-ps1-in-bash` and `guard-uncapped-read` are no longer in FMS's `.claude/hooks/` (they run
  from the plugin); `nudge-small-task-tier` still is. The turn-refusing `Stop` shape is documented in
  [hooks/README.md](hooks/README.md) but not shipped.

### The harness (2026-09-03, S2402)

- 71 scripts and 16,843 lines of PowerShell drove 2,389 tickets in FMS. The shipped layer is 74 scripts behind one
  seam, `templates/.sza-profile.json` ([tools/harness/README.md](tools/harness/README.md)); 79 `.ps1` files sit in
  the working tree today, one new and uncommitted.
- Eight clusters: `spec_catalog/` (ticket journal and closing gates), `locks/` (domain locks, queue, ticket leases),
  `chat/`, `devlog/`, `document_registry/`, `batch/` (queue runner, monitor), `all_features/` (capability ledger),
  `aliases/`.
- The first `assert-portable.ps1` run reported 405 code lines still naming a product path, prefix or log call.
- FMS keeps its 2,383 call sites through generated five-line forwarders: `SZA_HARNESS_ROOT`, then the newest plugin
  cache, then the canon checkout.
- Three conversion findings (each would have shipped as a defect): the path -> domain table is data, not code; an
  empty profile list read as one blank entry; half the set is dot-sourced and half invoked.
- After shipping, FMS's own suites caught three more defects (commit `370e367`), fixed here.

### Skills

- `agent-cost` - introduced with the 2026-08-02 spread-back; a fifth measurement defect added 2026-08-05.
- `caveman` - FMS's `/caveman`, `/caveman-commit` and `/caveman-review` merged into one skill, 2026-08-08.

### Measured lessons - and whether the kit has them

The kit column is a search of `kit/` on 2026-09-20 for the number or its key phrase ("fire-and-forget", "polling",
"hidden reasoning"); "no match" means those strings are absent, not that the idea is.

| Lesson | Evidence | Canon home | In the kit |
| --- | --- | --- | --- |
| A gated rule is followed, prose is not | ~99% gated against 1-8% prose, a month of sessions | [AI_USAGE.md](rules/AI_USAGE.md) section 5 | `docs/AUTHORING.md`, `docs/VALIDATION.md` |
| The ceiling for prose | 22% compliance on advice shipped in the tool description every turn | AI_USAGE section 5 | no match |
| Rewrite beats block | a blocking guard fired 381 times in a week; 31.8% re-issued the same read with a limit of 1500+ | AI_USAGE section 5, [hooks/README.md](hooks/README.md) | `docs/HOOKS.md` |
| Cost is context times turns; reset at the process boundary | 83% of a week's usage above 150k carried context | AI_USAGE section 3 | `docs/COST.md` |
| Context is replayed, not read once | median request 215k against a 28.7k floor; 29% of requests past 300k | AI_USAGE section 3 | no match |
| Never fire-and-forget a verdict | ~1,300 polling turns, 81 min of sleep in a month | AI_USAGE section 1 | no match |
| Measure with the corrections | a naive transcript sum inflates tokens roughly threefold (3.13x in the FMS audit) | AI_USAGE section 3, skill [agent-cost](skills/agent-cost/SKILL.md) | `docs/COST.md`, as "roughly threefold" |
| Speed is set by output, not by rule volume | +0.681 output tokens against +0.065 context; 76.5% hidden reasoning | the FMS record only | no match |
| Route a subagent to a tier on purpose | 182 unpinned-agent spawns in 14 days; 82.8% of output on the expensive tier (a deduction) | AI_USAGE section 3 | `docs/COST.md` |

Lessons without a single number, with their canon homes (from the FMS record, 2026-07-23 and 2026-08-28):

- Gate placement (per change or release scope), and the closure runs the ladder's rung - DEVELOPMENT section 15.
- Ratchet baselines, batched fast-gates, diff-scoped closure, the one-call closure facade - DEVELOPMENT section 15.
- A lock is a (kind, domain) pair; abandoning a queued intent obliges withdrawing your ticket - DEVELOPMENT section 10.
- The status-gated debug probe - DEVELOPMENT section 8.
- A check only a human can run has not happened yet - TESTING_AND_QA section 1.
- Surfaces move together; authored locales in one edit, the rest at the release - INVARIANTS 17, DOCUMENTATION_CONCEPT
  section 5. FMS ruled this on 2026-08-14 and was knowingly non-compliant with the old wording until 2026-08-28.
- The release package plan, designed and proven in FMS first - RELEASE_AND_DISTRIBUTION section 8.
- Android multi-store rows (sideload, Meta Horizon) - CHANNEL_MATRIX, PLATFORM_OVERLAYS Overlay B.

### What stayed behind in FMS

The `*.tests/Run-Tests.ps1` suites, the 99 platform gate files in `scripts/quality/` (Gradle, Kotlin, Room, detekt,
device), the command bodies in `.claude/commands/`, `migrate_from_log.ps1`, and the 14 project hooks.

## 5. How the canon reaches the other projects

- **Plugin.** `sza` from the marketplace `sza-unified-rules` (`source: "./"`), installed at user scope on 2026-07-27, so
  one `claude plugin update sza@sza-unified-rules` covers every repo on the machine.
- **Version.** CANON_VERSION `2026.09.18.1` maps to plugin `2026.918.1`. The pair is written only by `deploy.ps1`
  through [bump-canon-version.ps1](tools/bump-canon-version.ps1), since 2026-09-07 (S2463).
- **Stamp.** `.sza-canon.json` at each repo root (version, core digest, adoption date, consumption model, contrib
  record, role, overlay), written by the [adopt-canon](skills/adopt-canon/SKILL.md) skill.
- **In session.** The SessionStart hook injects the 20 invariants where a stamp exists; 7 skills load on a task
  match; the four guards and advisories run wherever the plugin is enabled, adopted or not.
- **Gates.** [check-rules.ps1](tools/check-rules.ps1) validates the canon's own docs;
  [check-compliance.ps1](tools/check-compliance.ps1) `-RepoRoot <path>` validates an adopting repo (rule ids such as
  SZA-RULES06 and SZA-HOOK01).
- **Consumption models.** Reference (all 11 stamped repos), mirror (none today), sibling distillation
  (universal-agent-kit).

What ships:

- 19 rule docs and 11 contrib files, 7,637 lines (derived). [INVARIANTS.md](rules/INVARIANTS.md) is the 20-line
  page that is always in context.
- 7 skills: [adopt-canon](skills/adopt-canon/SKILL.md), [agent-cost](skills/agent-cost/SKILL.md),
  [caveman](skills/caveman/SKILL.md), [feature-to-site](skills/feature-to-site/SKILL.md),
  [release](skills/release/SKILL.md), [spec-to-audit](skills/spec-to-audit/SKILL.md),
  [store-publish](skills/store-publish/SKILL.md).
- 5 hooks with smoke tests; tools `check-rules`, `check-compliance`, `bump-canon-version`, `fix-house-style`,
  `mine-agent-transcripts.py`; the harness.
- 43 commits, 2026-07-23..2026-09-18, all under the owner's git identity. 26 `Co-Authored-By` trailers: Opus 5 x21
  (12 of them "1M context"), Fable 5 and 5.1 x5. Of the 43: 15 deploy commits ("Canon update <date>", the default
  message in `deploy.ps1`), 11 `contrib:` commits, 5 that cite an FMS ticket, 12 others.

State on 2026-09-20:

- Head `f59fdc6` (2026-09-18). Installed on this machine: `2026.913.1`, built from `d50356d`, updated 2026-09-13; the
  cache holds `2026.906.1`, `2026.912.1`, `2026.913.1`. Two deploy commits behind (`e9b7b6c`, `f59fdc6`).
- Committed stamps: all 11 at `2026.09.06.1`. universal-agent-kit's working tree says `2026.09.08.2`, uncommitted.

Delivery failures worth remembering:

- The plugin cache sat pinned at `2026.07.27` for three weeks, so the canon updates of 08-02, 08-05, 08-08 and 08-18
  reached zero sessions in FMS. The first re-sync (2026-08-18) ran against a compliance gate that read
  `0 error(s), 0 warning(s)` both before and after - the gate cannot see a rules file that restates a canon rule.
- The version bump was a manual step until 2026-09-07 and was missed twice; `ec00587` shipped harness files under an
  already-installed version. Both the deploy and `claude plugin update` reported success each time.
- Before the plugin, the canon was 18 markdown files at a local path: unreachable from CI, loaded by nothing, and
  every repo regrew its own copy ([README.md](README.md) "Why it is shaped this way").

## 6. The return channel: project -> canon

- **The rule.** Never edit the canon from a project session; fixes land here ([CLAUDE.md](CLAUDE.md)). A project
  session may append its own record to `rules/contrib/<project>.md` and nothing else.
- **Deviations on record.** 2026-08-02 (the guardrail bent), 2026-08-28 (the owner directed it explicitly after being
  shown the constraint), 2026-09-03 S2402 ("a recorded deviation, not a precedent"). The 2026-08-18 propagation was
  executed from a canon session and did not need to bend.
- **The S2410 split.** A project session lands the edit and writes the record; the deploy (version pair, gate,
  commit, push) is left to a canon session. Each record ends with "what is owed".
- **Lifecycle.** (1) an FMS session lands the edit in this checkout and adds its entry to the contrib record; (2) a
  canon session runs `deploy.ps1`: gate, version pair, commit "Canon update <date>", push; (3) `claude plugin update`
  refreshes the cache; (4) each repo re-syncs with `adopt-canon` and records it in its contrib file.
- **Dated entries in the FMS record: 17, 2026-07-23..2026-09-19** - six spread-backs, six ticketed entries (S2402,
  S2520, S1809, S2463, S2934, S3288), the adoption, the release plan, the hook import and two re-syncs.
- **Canon commits citing a ticket:** `5e8bcef`, `370e367`, `108170d` (S2402, 2026-09-03), `2a3710b` (S1809 and S2520,
  2026-09-06), `d50356d` (S2697, 2026-09-13). All five are FMS tickets.
- **Fixes not tied to an FMS ticket:** `729cc38` (check-compliance hardened against false positives found on the
  portfolio, 2026-07-27), `014b163` (SZA-RULES06, 2026-07-27), `ba2cb4c` (two canon defects, 2026-08-18).
- **The other projects.** Of the 11 `contrib:` commits (FMS included), 10 record a re-sync or alignment and one a
  drift correction (StreamsPlayer, 2026-07-26). The seven other project folders hold 54 retained sessions between
  them (derived), against FMS's 1,880.
- **Pending on 2026-09-20.** The S3288 entry, the new `tools/harness/lib/tool-failure-journal.ps1`, and edits to
  `_profile.ps1` and `spec_catalog/_lib.ps1` are in this working tree, uncommitted. No consumer runs them until
  `deploy.ps1` runs.

## 7. universal-agent-kit - the community-facing result

| Fact | Value |
| --- | --- |
| Repo | [SerZhyAle/universal-agent-kit](https://github.com/SerZhyAle/universal-agent-kit), public. Local `p:\WEB\universal-agent-kit`. 30 commits, 2026-06-14..2026-09-06 |
| Article | [serzhyale.github.io/universal-agent-kit](https://serzhyale.github.io/universal-agent-kit/), one HTML page, EN, RU and UK |
| Download | [universal-agent-kit.zip](https://github.com/SerZhyAle/universal-agent-kit/raw/main/universal-agent-kit.zip); extracts to `universal-agent-kit/` beside `merge-prompt.txt` |
| Licence | kit MIT, article prose CC BY 4.0; "No source code or proprietary content from the origin project is included - only the working method" |
| Release shape | rolling: no tags, no changelog; the site and the zip are regenerated in place |
| Contents | 42 files in `kit/`: 18 slash-commands, 4 role agents, 11 docs, 5 memory files, `CLAUDE.md`, `AGENTS.md`, `README.md`, `settings.json` |
| Ways in | a paste-at-your-agent prompt; `merge-prompt.txt` (inventory, plan, stop for approval, "your files always win"); the offline zip; the minimum start `CLAUDE.md` + `/quick` + `/fix` |
| Runtimes | native to Claude Code; for Cursor, Cline, Windsurf, Codex and Aider "an adaptation, not a drop-in" |
| Relation to the canon | sibling distillation: `kit/` is "a one-way obfuscated render" of AI_USAGE.md and the neighbouring method, aligned by hand. No canon pointer under `kit/`; the pointer lives in the repo's own `CLAUDE.md`. It also consumes the canon for its own development (stamp, `role: portfolio`) |
| Audits | the external-audit prompt lives outside the repo, `p:\WEB\universal-agent-kit-audit-prompt.md`; two audit passes are recorded on 2026-06-14 (`6a1e3ad`, `3db770d`) |

- Commands: backlog, caveman, caveman-commit, caveman-review, fix, git, park, quick, research, review, spec,
  spec-all, spec-check, spec-dev, spec-fix, spec-tech, ui-clarify, verify.
- Role agents: rd-lead, solution-researcher, implementer, doc-writer.
- Docs: AGENT_MEMORY, AUTHORING, CODE_QUALITY, COST, HOOKS, PARALLEL, REPLACES, REPLACES_RU, RESEARCH_INDEX,
  SPEC_LIFECYCLE, VALIDATION. Memory: an index template plus one example per type (user, feedback, project, reference).
- Canon -> kit moves so far: adopts canon 2026.08.18.1 and aligns (2026-08-18); measured cost split, gated-versus-prose
  compliance, index hit rate (`ecd8f66`, 2026-08-20); re-sync to 2026.09.03.3 with five additions, and `PARALLEL.md` as
  a first-class pillar (2026-09-03).
- Order of origin: the kit's first commit (2026-06-14) predates the canon's (2026-07-23), so it did not start as a
  render of the canon. The README says only "distilled from a real project". FMS has commands of the same names
  (`spec-tech`, `spec-dev`, `ui-clarify`) and role agents for the same jobs.
- **Audience gap, as of 2026-09-20.** The README describes "a portable method for AI-assisted development" that fits
  "most git-backed repos with a promptable agent", and its adoption prompt asks for build, test, lint and run
  commands, architecture layers, a logger and a ticket-id scheme. The owner's stated goal is wider: any specialist who
  works with agents on "projects".

## 8. Timeline

Direction: `out` FMS -> canon, `in` canon -> projects, `kit` involves universal-agent-kit.

| Date | Where | Event | Dir |
| --- | --- | --- | --- |
| 2026-02-09 | FMS | initial commit of the repo ("clean history") | - |
| 2026-06-14 | kit | first commit: bilingual article site and kit; two external-audit passes the same day | kit |
| 2026-06-30..2026-07-31 | FMS | corpus of the first agent-process audit | - |
| 2026-07-23 | canon | first commit "Add Unified_Rules"; `SPREAD_BACK_PROMPT.md`; FMS record calls FMS "the reference repo the core was extracted from" | out |
| 2026-07-27 | canon | plugin with working skills; check-compliance hardened on the portfolio; rollout, every adoption recorded | in |
| 2026-08-02 | FMS | agent-process findings S1338..S1342 into AI_USAGE (99% against 1-8%, 22%); `agent-cost` skill; the guardrail bent | out |
| 2026-08-05 | FMS | retrospective findings: a fifth measurement defect; ungated routing (434 slash-command invocations) | out |
| 2026-08-08 | FMS | enforcement layer: hooks generalized into the plugin (canon 2026.08.08.1); the OS-interaction refutations | out |
| 2026-08-12 | FMS | second audit: repeated manual sequences to script, hook or gate | - |
| 2026-08-18 | all | six-item propagation executed from a canon session; first re-sync after the stale cache; version-bump commit `6906983`; the kit adopts the canon | out, in, kit |
| 2026-08-20 | kit | measured cost split, gated-versus-prose compliance, index hit rate | kit |
| 2026-08-28 | FMS | speed-versus-process measurement; gate placement, lock domains, batch drivers raised from a project session | out |
| 2026-09-03 | FMS | S2402 harness ships; three defects caught by the consumer's suites; re-sync wave over hub, kit and the Windows products | out, in, kit |
| 2026-09-05..2026-09-06 | FMS | S2520 refusals carry evidence; S1809 wear fast targets; deployed as 2026.09.06.1 | out |
| 2026-09-07 | canon | S2463: the deploy raises the version pair itself | out |
| 2026-09-11 | FMS | S2934: the probe invariant guarded in both directions | out |
| 2026-09-13 | FMS | S2697 lock domains (`d50356d`) - the build installed on this machine | out |
| 2026-09-18 | canon | head, 2026.09.18.1 (`f59fdc6`) | - |
| 2026-09-19 | FMS | S3288 refusal journal - in the working tree, not deployed on 2026-09-20 | out |

## 9. Links

Public:

- Canon: [SerZhyAle/sza-unified-rules](https://github.com/SerZhyAle/sza-unified-rules), public. Install with
  `/plugin marketplace add SerZhyAle/sza-unified-rules`, then `/plugin install sza@sza-unified-rules`, then
  `/sza:adopt-canon` once per repo.
- FMS_Android: [SerZhyAle/FastMediaSorter_mob_v2](https://github.com/SerZhyAle/FastMediaSorter_mob_v2), public.
- universal-agent-kit: [repo](https://github.com/SerZhyAle/universal-agent-kit),
  [article](https://serzhyale.github.io/universal-agent-kit/),
  [zip](https://github.com/SerZhyAle/universal-agent-kit/raw/main/universal-agent-kit.zip), all public.
- Hub: [sza.od.ua](https://sza.od.ua), repo `SerZhyAle/sza.od.ua`.
- Other remotes as configured locally (visibility not checked): `SerZhyAle/FastMediaSorter_Lite`,
  `SerZhyAle/FileDO`, `SerZhyAle/StreamsPlayer`, `SerZhyAle/CyrFlip`, `SerZhyAle/OneClickRunner`,
  `SerZhyAle/doc-html-translate` (the EPUB_2_HTML folder).

In this repo:

- [README.md](README.md), [CLAUDE.md](CLAUDE.md), [rules/README.md](rules/README.md),
  [rules/INVARIANTS.md](rules/INVARIANTS.md), [rules/AI_USAGE.md](rules/AI_USAGE.md),
  [rules/AUTHOR.md](rules/AUTHOR.md), [hooks/README.md](hooks/README.md),
  [tools/harness/README.md](tools/harness/README.md), [tools/mine-agent-transcripts.py](tools/mine-agent-transcripts.py).

In FMS (local): `dev/AGENT_PROCESS_AUDIT_2026-07-31.md`, `dev/AGENT_PROCESS_AUDIT_2026-08-12.md`,
`dev/AGENT_WORKFLOW.md`, `CLAUDE.md`, `AGENTS.md`, `GEMINI.md`, `.claude/commands/`, `.claude/hooks/`.

## 10. To confirm

Things the repositories cannot settle:

- Is "FMS_Android" exactly `FastMediaSorter_mob_v2` (with `FastMediaSorter_release` as its second checkout)? This map
  assumes so.
- Which agent was the faster one in the 2026-08-28 comparison? The record does not name it; `AGENTS.md` names Codex,
  ZCode, Gemini CLI and GitHub Copilot as the other runtimes.
- Two statements about origin coexist: [rules/README.md](rules/README.md) says the conventions first lived inside
  `FastMediaSorter_Lite`, and the FMS record says the core was extracted from the Android repo. Both may be true;
  say so once, or fix one.
- Is FMS the "real project" the kit was distilled from? The README does not name it (section 7).
- "Many agents a day" in numbers: the 1,880 retained sessions mix hand-driven sessions with the batch runner's
  headless children. Splitting them needs a pass with [mine-agent-transcripts.py](tools/mine-agent-transcripts.py).
- Whether the kit should speak to non-programmers (section 7, audience gap), and whether the numbers marked "no match"
  in section 4 belong in it.
