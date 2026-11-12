---
name: spec-to-audit
description: Run a task through the full SZA lifecycle - triage, spec, plan, implement, evidence, self-audit, documentation, commit - with a named gate at every boundary that refuses to advance when its preconditions are missing. Use when asked to implement a specification, "do this properly", "сделай по спецификации", to check whether something is actually implemented, to audit your own work before committing, to proceed to the next phase, to sweep the tickets waiting on a manual check, or to unstick the tickets waiting on the owner's answers - "this spec is stuck", "decide the open questions", "задай мне вопросы по тикетам", "разблокируй задачи". Free and reversible: it never tags, publishes, or releases.
---

# Spec to audit - the lifecycle and its gates

The value here is not the audit at the end; it is that **every boundary is a gate that refuses**. A stage may
not be left until its gate is true, and no gate is satisfied by an opinion.

This skill lives entirely on the **build** side of the billable wall. It never creates or pushes a `v*` tag,
never submits a manifest, never uploads to a store, never publishes a site. When the next step is a release,
say so and stop - see [release](../release/SKILL.md).

Canon: [DEVELOPMENT.md](../../rules/DEVELOPMENT.md), [TESTING_AND_QA.md](../../rules/TESTING_AND_QA.md),
[AI_USAGE.md](../../rules/AI_USAGE.md), [AUTHOR.md](../../rules/AUTHOR.md),
[CONTRACTS.md](../../rules/CONTRACTS.md), [INVARIANTS.md](../../rules/INVARIANTS.md).

**The flagship rule, before anything else:** *no completion claim without fresh evidence.* Before saying done,
fixed, or passing - run the command that proves it, read its exit code **and** its output, and cite both.
A prior run, an assumption, or a subagent's "it passed" is not evidence.

---

## Run-time slots - discovered, never invented

The skill body is the lifecycle. These six are per-repo and filled at run time:

1. **Build command** 2. **Test command** 3. **Cheap rungs** (compile-only, static gates)
4. **Known-broken non-gates** 5. **Closure facade and hygiene gates** 6. **Ticket system and id scheme**

Discovery order, fail-soft:

1. The repo's agent-rules file - `CLAUDE.md`, else `AGENTS.md`. Where both exist, **stricter wins**; note
   that one repo's `CLAUDE.md` is a deliberate bare pointer to `AGENTS.md`.
2. `rules/contrib/<project>.md` in this plugin - overlay facts and recorded divergences.
3. `.claude/skills/` and `.claude/commands/` - **prefer an existing project skill over any built-in pattern.**
4. Root build scripts - read the script **header**, do not infer flags.
5. Still unknown? **Ask once, then write the answer into the repo's rules file** so the slot is filled
   permanently instead of re-derived every session.

**Load the known-broken list before running anything.** Some repos have deliberate reds - a root test target
left broken on purpose with a scoped gate beside it, a formatter check that reports a pre-existing baseline
and is a diagnostic rather than a gate. Without this you will chase a failure that is not yours and may
"fix" a tracked known-red, destroying the signal that protects against masked regressions.

**Hard rule: a command that is not discovered is not invented.** Drop one evidence rung and say so.

---

## Stage 0 - Triage: pick the rung

Do **not** start at "write a spec". Pick the rung first, and never bypass the cheap ones:

| Rung | When | Ceremony |
| --- | --- | --- |
| Quick edit | one string, constant, or label | no spec, no build gate |
| Fix | a narrow, understood bug | no spec |
| **Primitive spec** | see the test below | three sections - Problem / Approach / Done criteria - implemented in place |
| **Complex** | any criterion below fails | the full spec -> plan -> implement -> audit pipeline |

The test for primitive: **all** of these true - at most 3 existing files change, no new files, no new public
types, no schema or migration, no new DI wiring, no new screen or route, mechanically deterministic with no
deferred decisions, under ~100 lines of delta. Any one false -> complex.

**Gate**: the chosen rung is stated, together with the criterion that forced it upward. A rung was never
chosen downward to avoid ceremony.

## Stage 1 - Spec: the strategic what and why

Problem, goals, constraints, open questions. Deliberately **no** class names, file paths, or signatures - this
is the contract the audit later checks the build against.

**Gate - all five:**
- The spec says whether the change touches a **shared-contract boundary** - a format, a wire shape, an
  algorithm constant, or a behaviour that another product reads or reproduces. The repo's
  `docs/contracts/` pointers name the contracts it holds; a serializer, importer or exporter with no pointer
  is still a boundary. If it does, the catalog amendment - version bump, dated document-log row, registry
  rows - already exists or is the plan's first phase, and no boundary code is written before it
  ([CONTRACTS.md](../../rules/CONTRACTS.md) §4). The `contract-sync` skill does the catalog side.
- Every *required* research item is closed. An open required item **stops the pipeline** - this is an encoded
  stop, not a judgement call.
- Every user-facing placement, visibility, or fallback decision is resolved. Surface UI ambiguity before
  implementing; never guess. (But do not ask what the architecture already answers - research it and
  recommend.) In an **unattended pass** the researched recommendation is taken, not asked: a choice that is
  reversible inside the ticket is recorded under `### Assumed (unattended, <date>)` with the alternative it
  was weighed against and "owner may overrule", and the pass goes on. What stays an owner decision even
  unattended: one-way and outward steps (publish, release, store submit), contract changes, scope, money,
  and facts only the owner knows.
- The ticket has one authoritative record with an id and a first-line **Status:**, mutated only through its
  tool where one exists - a catalog CLI, a journal - never hand-edited.
- The ticket's `**Complexity:**` line exists and was **rewritten at this spec pass**, confirmation included:
  it no longer reads `not assessed at capture` (see [DEVELOPMENT.md](../../rules/DEVELOPMENT.md) section
  8). A primitive-spec rung skips this item - it has three sections and no pipeline.

Status vocabulary, identical across the portfolio:
`Draft -> Approved -> Tactical -> In Progress -> Implemented -> Verified`, plus `Partial`, `Broken`,
`Archived`, and the `Block*` family (`BlockNeedUserTest`, `BlockByOtherTask`, `BlockQuestions`,
`BlockExternal`). **Every transition into a `Block*` status carries a one-line reason note**, cleared by
removing the condition and advancing exactly one level. `BlockQuestions` is the one whose condition only
the owner can remove; its exit is [Quiz mode](#quiz-mode---draining-the-owners-questions).

**`BlockExternal` is only for a party outside the portfolio** - a third-party vendor, an upstream library
maintainer, a store review, hardware shipment. It is never for work this repo's session is allowed to do
itself, never for another registered repository in the portfolio, and never for an action the owner performs.
The canon is read-only from a project session with one exception, the repo's own `rules/contrib/<repo>.md`
record ([adopt-canon](../adopt-canon/SKILL.md)), so a ticket that says "record it in the canon contrib record
by a canon session" is not blocked: write the record, with the re-sync it belongs to. Where a ticket genuinely
waits on another registered repository in the portfolio (the canon included when a rule, skill or contract
must change first), file the needed ticket there with `spec-draft.ps1 -Project <key>`, record
`Blocker: <key>:<id>` in section 10 or `statusNote`, and park the waiting ticket in `BlockByOtherTask`
(TASK-FLOW rule 52, S0042). Where an owner action on a device, at the desk, or in an outside console account
must happen **before** implementation can proceed, write `- **DO:** <action>` under
`### 3.3 Owner inputs (Approval gate)` and park the ticket in `BlockQuestions` with `DO: <action>` in
`statusNote`; `BlockNeedUserTest` stays exclusively for tickets whose implementation and self-audit are done
and that await the owner's device test (TASK-FLOW rules 7-8, S0042).

**Two literal tokens, because direction is not recoverable from prose.** A ticket's "related tickets"
section names blockers, successors, consumers and neighbours in one breath and is equally happy to *deny*
a relationship - measured on the reference corpus, **98 spec files yield a ticket id there against 15 that
carry a real directional line**, and most of the lines containing "blocks" use it to say "does not block".
A scraper reading ids out of that prose makes a producer look blocked by its own consumers. So the record
carries a literal token on its own line for each direction - one naming what blocks this ticket (`Blocker: Sxxxx`
for a local ticket, or `Blocker: <repoKey>:<id>` for a ticket in another registered repository), one
naming the ticket that inherited an unanswered question (`Carrier: Sxxxx`). An id in prose is a mention; an id in the token
is a claim. Canon: [DEVELOPMENT.md](../../rules/DEVELOPMENT.md) §8.

Say which of the two is actually enforced, because they usually are not enforced alike: a carried-question
token is naturally a **hard gate at closure** (the write is refused), while a blocker token is both an
**entry gate on `BlockByOtherTask`** (the transition requires a local or qualified blocker token) and a
**soft exclusion at selection** (the local picker holds local blockers and holds `BlockByOtherTask` tickets
carrying a qualified `<repoKey>:<id>` blocker; the portfolio dispatcher resolves `<repoKey>:<id>` across
repositories and releases the dependent when the blocker reaches a release-ready status). Both are legitimate -
claiming every token is enforced at closure is not.

## Stage 2 - Plan: the tactical how

Three passes, then a mandatory self-review:

1. **Coverage inventory** - list every goal, constraint with impact, resolved research finding, decision
   record and acceptance criterion, and map each to a phase or mark it `out-of-scope: <reason>`. An unmapped
   line means the plan is incomplete.
2. **Produces/consumes topology** - per phase, list produced and consumed artifacts. **No phase may consume
   what a later phase produces.** A forward reference means reorder before writing anything.
3. **Real-work filter** - every step's primary action changes source, resources, or config. Steps that only
   edit plan text, "review docs", or restate a prior step are **not steps**. Sole exception: the final docs
   phase.

**Self-review**: re-read the written plan against the inventory and the topology. Every inventory line maps to
a written step; every consumed symbol greps in the code or is produced earlier.

**Gate**: the self-review is done, every step ends in a **static** check (file exists / symbol declared /
value equals / command exits 0 - never "works correctly"), and every pre-implementation blocker is ticked.
An unchecked blocker is the encoded stop. The plan pass has also read the ticket's complexity level against
the plan and rewritten its `**Complexity:**` line where the plan disagrees (see
[DEVELOPMENT.md](../../rules/DEVELOPMENT.md) section 8).

## Stage 3 - Implement

**Per-step loop:**
1. Re-read the step; verify its declared dependency step is done.
2. Confirm every symbol the step references **actually exists at the stated path**. If not, abort - never
   invent a path.
3. Ambiguity check: any `<TODO>`, `<choose..>` or `???` is a hard stop. In an attended pass set
   `BlockQuestions` with the open question as its reason note - do not guess; the answer arrives through
   Quiz mode, not from you. In an **unattended pass** a decision with a researched, ticket-reversible
   recommendation is taken and recorded under `### Assumed (unattended, <date>)` (with the alternative and
   "owner may overrule") instead of blocking. `BlockQuestions` stays for one-way and outward steps,
   contract changes, scope, money, facts only the owner knows (whose reason note is a literal `Q: ..?`
   token), and pre-implementation owner actions on a device, at the desk, or in an outside console account
   (recorded as `- **DO:** <action>` in `### 3.3 Owner inputs (Approval gate)` and a literal `DO: <action>`
   token in `statusNote`, S0042). The block-note gate refuses a `BlockQuestions` note that carries neither
   `Q: ..?` nor `DO: <action>`. Whichever pass enters `BlockQuestions` also writes the fixed **question block**
   the quiz asks from, into the ticket's spec file (TASK-FLOW rule 7, S0026): a heading
   `### Questions (v1, <yyyy-MM-dd>)` - the day it is written - holding one `- Q: <question>?` line per question,
   each followed by two to four option lines indented two spaces, `  - <option> - <one-line consequence>`, the
   first option suffixed ` (recommended)`, and one `- DO: <action>` line per owner action, with no option lines.
   The options are the researched ones - the same lines the quiz would present - written while the finding is in
   front of the pass, so the quiz asks from the block instead of researching the ticket again. A newer block is
   appended, never replacing an older one, and a line the pass does not recognise inside an existing block stays
   untouched. A slow run is never asked about: it is recorded as a release item (Stage 4),
   not a question.
4. Pre-edit guards: read-only zones; back up an oversized file into `temp/<ticket>/`; refuse an edit projected
   past the file-size ceiling; paired-file guard.
5. Flip the step in-progress.
6. Edit **strictly to the step's scope** - no drive-by refactors, no opportunistic import cleanup, no extra
   comments.
7. Run the step's verification predicates. PASS -> done. **Any FAIL -> leave in-progress and hard stop.**

**Four in-flight disciplines:**

- **Park, do not fix.** An out-of-scope finding is deduped by symptom, captured as a fresh draft ticket with
  symptom and evidence, reported as `parked: <id>`, and left alone. **Never switch the active ticket.**
  Trivial in-scope fixes are done on the spot. A read-only context cannot mutate the catalog - it returns
  park *candidates* to its caller.
- A finding belonging to another registered project is captured there with `spec-draft.ps1 -Project <key>`,
  with its evidence in the ticket; the reply names the drafted `<key>:<id>`. If that other project's ticket
  must land before the current ticket can proceed, record `Blocker: <key>:<id>` in section 10 or `statusNote`
  and move the current ticket to `BlockByOtherTask` (never `BlockExternal`).
- **Scratch goes to `temp/<ticket>/`** (or `temp/scratch/`), never the repo root. On Windows a short
  repo-local temp path is a **correctness** constraint, not tidiness - MAX_PATH silently breaks a
  path-sensitive child process.
- **Serialize expensive shared operations** through the project's advisory build or code lock, judging
  staleness by process liveness, not a guessed timeout.
- **Status-bound debug probes**: a probe log line carrying the ticket id exists in code **if and only if** the
  ticket sits in the needs-manual-test status. Insert probes at the changed-flow entry as the **last** code
  edits before the final build, so one build validates code and probes together. Delete them the moment the
  ticket leaves that status. Permanent logs never carry a ticket id.

**Per-phase gate**: the phase-boundary audit is **mandatory**, not deferred to the end. Audit the phase just
finished before starting the next, at the cheapest evidence rung matching the risk, tagging findings by
severity: **P0** crash or data loss, **P1** race / main-thread I/O / unbounded cache / unreleased resource,
**P2** hot-path waste, **P3** style. P0 and P1 are fixed now, with evidence at the matching rung - not with
an opinion.

*Why it must be at the boundary*: catching a defect at the next phase boundary costs one phase of rework;
catching it at the end costs every intervening phase.

## Stage 4 - Evidence

**The ladder** - pick the cheapest rung that matches the risk:

`grep < run-script < compile < targeted test < full build < run-and-observe`

- Docs or text -> grep for the content.
- A script -> run it, exit 0.
- Config, layout, manifest -> the target build passes.
- Code, pure symbol change -> compile only.
- Code, behavioural change -> targeted tests for the touched area.
- Reflection, serialization, DI, minification, startup -> proven on the **release/target variant**, not debug.
- User-facing flow -> actually run and observed. A changed GUI action needs run-and-observe, not merely a
  build.

**Between releases, nothing above 5 seconds runs** ([TESTING_AND_QA.md](../../rules/TESTING_AND_QA.md) §2).
No full build, no full suite, no single test, suite or gate whose recorded wall time is above 5 s, and none
with no recorded time - unless the owner names that run, or this is the release itself. Use the fast tier,
a fast filter of the touched area, static inspection and a direct call of what changed. Each rung skipped for
this reason goes into the audit as a `RELEASE` item naming the command the release will run, and the report
says "not built, not tested until the release". A project whose build or test command has no fast form gets
that fact written into its rules file, not a slow run. The owner is never asked which slow run to name -
the reference study measured seven repos asking that question back and getting the same answer every time
(S0039): an unattended pass records the skipped rung as a `RELEASE` item and moves on.

**One exception (S0040, owner decision 2026-11-11): the declared compile check in an unattended pass.** A
pass that edited compiled source runs the repository's declared compile-only command once, in the
foreground, before it sets `Implemented` or `BlockNeedUserTest`. The command is
`commands.compileCheck` in this repo's `.sza-profile.json`; absent or empty is a declared absence - the
note says "no compile command", never an invented run. A failure is fixed inside the pass or written
into the ticket, and this exception authorizes no other run above 5 s: no full build, no suite, no
second attempt. What does not change: the compile check proves compilation, not behaviour - a pass
whose compile passed and nothing else writes `compiled, not tested` into its note and still owes the
release rungs it skipped.

**Three traps:**

1. **Red-flag words.** "Should", "probably", "seems", "looks fixed", "I think it passes" each mean the proving
   command has not been run. *The hedge is the confession.* Hard stop, run it, then state the result in past
   tense with the evidence.
2. **A green can lie.** When commands are chained, piped, or backgrounded, the aggregate exit status often
   reflects a wrapper or a trailing step, not the operation you care about. Read the **specific verdict line**
   of the operation that matters. (Concrete instance: a `.ps1` run as a Bash command head fails yet reports
   exit 0 - a failed build masquerading as passing.)
3. **Known-red must be tracked explicitly**, so a pre-existing failure cannot mask a new regression. A green
   you cannot trust is worse than a red you can.

**Gate**: for every claim in the final message there is a named command, its exit code, and an
`expected: X | actual: Y` line.

## Stage 5 - Self-audit

**Load [references/audit-verdict.md](references/audit-verdict.md)** for the outcome vocabulary, the scoring
table, the grep rules, and the `## Last Audit` block format.

The self-audit is a **separate, static pass** against the spec's own contract - not a re-run of the build.
That is what keeps it cheap enough to actually run.

Two rules give "Verified" its meaning, and both are **refusals**, not advice:

- **An open MANUAL item can never sit beneath a Verified.** An unresolved manual or on-target signal keeps
  the ticket at `BlockNeedUserTest` or `Partial` until a human closes it and a **re-audit** turns it green.
- **Entry precondition**: a ticket may enter `Implemented` or `BlockNeedUserTest` only when its **headline
  user-visible behaviour already works end to end**. Created classes, wired contracts and a passing compile
  are milestones, not deliverables. Never invite a human to test while the advertised action still logs,
  shows a placeholder, or no-ops.
- **The unattended compile gate (S0040)**: in an unattended pass that edited compiled source,
  `BlockNeedUserTest` is entered only after the repository's declared compile check passed - or after the
  repo declares none (`commands.compileCheck` absent or empty) and the note says so. An `Implemented`
  note distinguishes compilation from an absent command: "compiled, not tested" or "no compile
  command". A failed check is fixed in the pass or recorded in the ticket, never silenced or retried
  at another rung.

Also mandatory here: the **probe-invariant sweep**. If the verdict moves the ticket out of the
needs-manual-test status, grep-and-delete every ticket-id probe line - idempotently, including on the cancel
and archive paths.

## Stage 6 - Documentation

- **Documentation-context loop**: at task start, at any material scope change, at **each phase boundary**, and
  **before the final response**, consult the project's document registry for the touched area and state which
  records are affected versus unchanged. A registered document that changes is re-validated by its tool.
- **Ship-together surfaces**: every user-facing surface lands **atomically, every locale in one edit**. This
  is [feature-to-site](../feature-to-site/SKILL.md) - invoke it rather than improvising a surface list. The
  text is written from the order, as a finished fact, with no regard to how much of the feature is implemented
  or tested yet; the feature ships with its text.
- **One source of truth per fact**: what the product does lives in the README; what changed lives in the
  ledger; the version is derived mechanically. Anything appearing twice is a render target - regenerate it,
  never hand-edit it.
- Regenerate any generated index or catalog **once per logical change**, not per file.

## Stage 7 - Commit

**Hygiene gates**, run diff-scoped: trivial comments restating the adjacent line; broad or empty catch with
no recovery, safe default, or correctly-levelled log; hardcoded colour literals where a theme attribute
exists; lifecycle-unsafe async collection; global or ambient coroutine/task scopes; logging that bypasses the
project's single logging abstraction; shipped runtime stubs; typographic long dashes in code. Plus the
**dead-weight rule**: orphaned code, resources, string keys and keep-rules are deleted in the **same change**
that makes them dead, verified on the release variant.

Mechanics that make this cheap: **ratchet baselines** (fail on net-new only; a hand-edited baseline is
ignored - regenerate through the gate); **batch the fast gates into one process**; **diff-scope on a dirty
tree** so a clean change closes amid other tickets' WIP, with the strict full-project gate reserved for
release and CI; **one closure facade**, not N rituals. For PowerShell, respect the reachable-exit-code
contract: under `$ErrorActionPreference='Stop'` a bare `Write-Error` throws, so a following `exit N` never
runs - use `Write-Error $msg -ErrorAction Continue` before `exit N`, and list a script's codes in its header.

**The closing gate itself, if the project has one.** Closing a ticket requires every open question to be
answered or handed to a named successor through the token above - measured on the reference corpus,
**134 of 1 506 closed specs carried a still-open research item, 372 items in all, 8.9% of every
closure**, and each one left the queue with the question inside it. Four mechanics decide whether such a
gate does anything at all: gate the **transition**, not the state, and only on an actual change; do
**not** gate the archive transition, which closes a ticket that already passed; treat an unfilled
template placeholder as **unanswered**; and locate the section by its **heading text, never its number**,
because numbers shift when a template gains a section and the gate then reads the wrong part of every
older file while staying green. Above all, **wire it into every mutator that can close and verify which
path is actually used** - a gate wired into one of several equivalent paths guards the path used least,
and the reference instance sat on the wrong one for weeks and almost never fired.

**Resuming a ticket, moving it out of a `Block*` status, writing its audit block, deduping a symptom, or
working beside a sibling session on one ticket?** Load
[references/ticket-lifecycle-traps.md](references/ticket-lifecycle-traps.md) first - each trap there closed
a ticket wrongly at least once.

**Attribute a failure before fixing it.** On a multi-writer tree a red check may belong to a sibling's
in-flight edit; confirm the failure is inside your diff first. The working tree, not git history, is the
authority for current state.

**Git boundary**: commit or push only when asked or when a commit flow calls for it. Never casually on the
default branch. Never `--no-verify`, force-push, or bypassed signing. English imperative subject naming the
**user-visible change**, not the mechanism; ticket id where one exists; agent co-author trailer.

---

## Sweep mode - draining the human gate

The lifecycle deliberately accumulates human-gated tickets. Left alone they pile up. Do this as a **periodic
batch, never a per-ticket interruption** - deferring the human gate to one batch is the whole reason the block
state exists.

1. Group every ticket at the needs-manual-test status.
2. For each, run the recorded manual check. Its probe tags say exactly which paths a real run exercised -
   grep the ticket id in the log.
3. Re-audit the batch: the ones whose manual signal is now closed flip to Verified and **their probes are
   removed in the same pass**; the rest stay blocked with a note.

This is also where the pre-release sweep hooks in: clean install over nothing **and** over a prior version,
resources, first success with zero configuration, the core scenario end to end, performance - ending in a
written PASS/FAIL verdict where FAIL blocks the release.

## Quiz mode - draining the owner's questions

A ticket enters `BlockQuestions` in one line; this is how it leaves. Like Sweep mode it is a **sitting, not
an interruption**: the block exists so the questions wait for an owner who is ready to answer them. The owner
starts it with `/spec-quiz` (`/sq`) - the [spec-quiz](../spec-quiz/SKILL.md) skill finds the waiting tickets in
any project and carries the mechanics; the procedure below is its authority.

1. **Resolve each ticket from its authoritative record**, never from a filename. Only `BlockQuestions`
   clears here. `BlockNeedUserTest` needs a post-implementation device run (Sweep mode), `BlockExternal`
   needs the party outside the portfolio, and `BlockByOtherTask` clears on its local or cross-repo
   (`Blocker: <repoKey>:<id>`) blocker's status - unless the owner picks a fallback that removes the
   dependency, which is a question like any other. Report the rest and mutate nothing.
2. **Extract the decision points**: the questions (`Q: ..?`) and pre-implementation owner actions
   (`DO: <action>`) in the block's reason note, plus every open research item and unfilled owner input
   (including `- **DO:** <action>` lines in `### 3.3 Owner inputs (Approval gate)`) that note points at. On request (`--assumed`) the sitting also lists the
   ticket's `### Assumed (unattended, <date>)` entries - each with what was taken, the alternative it was
   weighed against and the date - so the owner can review and overrule them in the same sitting. An
   overrule is an answer of step 5's kind: the entry is marked `overruled <date>` with the owner's answer,
   the owner's value is written into the owner input or research item the assumption settled, and where a
   pass already built on the assumption the rework is captured as a fresh `Draft` and reported as parked.
   Unoverruled entries stay as they are.
3. **Research each one before asking - unless the ticket asks from a current question block.** A pass that
   parked the ticket wrote its researched questions into the spec file as a `### Questions (v1, <date>)` block
   (Stage 3, TASK-FLOW rule 7): the newest block that is not stamped `- answered <date>` on its heading is
   current while its date is not earlier than the day the ticket entered `BlockQuestions` and every `Q:` text
   of the note appears in it. **A current block replaces the research of this step**: its questions, options,
   consequences and recommendations are what gets asked, as they stand - the sitting does not re-research the
   ticket. A block that is missing, stale, of another version, malformed or already answered is not read:
   research exactly as below and leave the old block where it stands. Whatever the architecture, the code, a contract or a decision
   already recorded settles is **not asked**: fill it in and list it in the report as *resolved without
   asking*, with what settled it ([AI_USAGE.md](../../rules/AI_USAGE.md) §1). Only a genuine owner call -
   scope, product intent, priority, wording, platform reach, build versus buy - or a pre-implementation
   owner `DO:` action (device, desk, or outside console account step) goes to the owner. In the
   reference sitting this settled 5 of 20 decision points without a word to the owner. Nothing left to
   ask -> write the fills and go to step 6.
4. **Ask multiple choice (and present `DO:` actions).** Each question specific, 2-4 options, each with its one-line consequence, the
   researched recommendation **listed first** and marked recommended. For a `- **DO:** <action>` item,
   show the exact action line to the owner and take the result (completed with the observed output/value,
   or an alternative/skip decision) as the owner input (S0042). Most-blocking first, in rounds where
   the runtime caps a round, never more than unblocking needs. A ticket with several questions may first be
   shown as one table - question, recommended answer, consequence - with one owner choice over it: accept all,
   pick the exceptions, or one by one (S0026). Accepting the table is the owner's answer to every row, given
   by the owner's click; nothing is accepted without it. The questions that arrive here are the
   owner-owned ones only: since S0039 an unattended pass takes a researched, ticket-reversible
   recommendation itself and records it under `### Assumed (unattended, <date>)`, so a reversible default
   no longer reaches this sitting as a question. What does arrive is still answered by the owner - in the
   reference sitting the owner chose something other than the default in 3 of 15 answers - and the
   recommendation never replaces a question that earned its place here. **After each round, re-apply the
   owner's own standing rules to the chosen option.** Where one of them contradicts the choice, show the
   collision once, with both outcomes, and let the owner pick - the menu was at fault, not the answer.
5. **Write back before any status move.** Each answer goes into the ticket's own record - the input
   filled, the research item resolved - plus a dated decisions block: question, chosen answer, one-line
   reason. A block that was asked from is stamped by appending ` - answered <yyyy-MM-dd>` to its heading,
   never deleted (TASK-FLOW rule 7). The order is the point: an interrupted sitting then leaves answered tickets still blocked,
   never moved tickets whose answers exist nowhere.
6. **Restore one level.** The ticket returns to the status it would have had without the block, inferred
   from what exists: a plan with progress -> `In Progress`; a plan without progress -> `Tactical`; settled
   owner inputs and no plan -> `Approved`; otherwise `Draft`. Two equally plausible -> ask one more
   question. The move goes through the ticket's tool and runs whatever gate guards the restored status; a
   refusal keeps the block and names the residue. Then stop - continuing the pipeline is a separate,
   explicit request, and a quiz writes no code and runs no build.
7. **A skipped answer is never invented.** The input stays unfilled, the gate that needs it stays closed,
   the ticket stays in `BlockQuestions` with its reason note narrowed to what is still open. The answers
   that did arrive are still written back.
8. **Report per ticket**: start -> end status; asked (question -> answer); resolved without asking
   (decision -> value -> what settled it); assumed listed and any overrule (entry -> the owner's answer);
   outstanding.

**Several tickets in one sitting are allowed - with one write-back and one status move per ticket.** What
the block defers is the owner's attention, and that is paid per sitting, not per ticket: the reference
sitting cleared three tickets with 15 questions in 5 rounds, where three single-ticket sittings would have
cost three context loads and three interruptions for the same answers. What stays per ticket is what makes
a ticket auditable on its own - its decisions live in its own record, its move is judged on its own
evidence, and a question two tickets share is asked once and written into both. Rounds may mix tickets;
each question names the ticket it settles. "One ticket at a time" confuses the unit of conversation with
the unit of record.

## Campaign mode - auditing code that did not change

Everything above judges a change. A tree too large for one pass, before a major release, is audited as a
**campaign**: a script cuts the shipped code and the release path into risk-ordered slices (parity pairs kept
together), a second script proves every file is in exactly one slice and exits non-zero until every slice is
closed, slices are generated from one template, a live defect-class registry turns a second sighting into a
tree-wide sweep, and every file changed after its slice closed is audited again - code written to close a
finding has been read by nobody but its author. The campaign closes only on the roll-up's exit 0, and the
owner's device tests are drained once afterwards, in Sweep mode. Load
[references/audit-campaign.md](references/audit-campaign.md) for the method and the measured yields.

## Unattended pass - headless queue runs

An unattended pass runs without human interaction in a headless queue session.

- **The ticket and tool are named up front**: the ticket is `<spec path>` in `<repo root>`; change its status only with `<update.ps1 path> -Id <id> -Status <s>`, never by editing the `**Status:**` line.
- **Strict repo boundary**: never read or change a ticket of another repository.
- **Foreground execution only**: this is a headless pass: start no background agent or command, wait for each in the foreground, and set the status before your last message. In headless mode the end of the turn is the end of the pass; orphaned background work fails.
- **Compile gate (S0040)**: if this pass edited compiled source, run the repository's declared
  compile-only command - `commands.compileCheck` in this repo's `.sza-profile.json` - once, in the
  foreground, before setting `Implemented` or `BlockNeedUserTest`. An empty or absent key means the
  repo declares none: write "no compile command" in the note and do not invent a run. Fix a compile
  failure inside the pass or write it into the ticket; no other run above 5 s is authorized.
- **Assume the reversible, ask the rest**: a choice that is reversible inside the ticket and has a researched recommendation is taken, not asked - record it under `### Assumed (unattended, <date>)` with the alternative and "owner may overrule", and the pass goes on (S0039). `BlockQuestions` is for one-way and outward steps (publish, release, store submit), contract changes, scope, money, facts only the owner knows (whose note carries a literal `Q: ..?` token), and pre-implementation owner actions on a device, at the desk, or in an outside console account (recorded as `- **DO:** <action>` in `### 3.3 Owner inputs (Approval gate)` and a literal `DO: <action>` token in `statusNote`, S0042). Post-implementation device verification goes to `BlockNeedUserTest`; a wait on another registered repository in the portfolio is filed there with `spec-draft.ps1 -Project <key>`, written as `Blocker: <key>:<id>`, and parked in `BlockByOtherTask` (`BlockExternal` is only for parties outside the portfolio); a deferred idea becomes its own Draft. A slow run is never asked about: it is recorded as a release item. Parking a ticket in `BlockQuestions` also writes its question block into the spec file, in the pass's own hand, at the moment of the transition (Stage 3; TASK-FLOW rule 7, S0026).
- **Autonomous stopping**: take this one ticket as far as it goes and do not start another. When it cannot move, set the matching `Block*` status with a `statusNote` naming what is missing.
- **Claim**: a lease on the ticket whose reason is `run-spec-queue` followed by an instance name is the claim the runner made for you: it is yours.
- **Context handoff for in-progress work**: when a pass leaves a multi-step ticket `In Progress` with work done and must stop before completion (or upon approaching turn or context limits), it writes `<tempDir>/<id>/context-handoff.json` (specifying `id`, `tokens`, `boundary`) before ending. The runner checks this marker and relaunches up to `handoffCap` with a fresh context instead of recording an idle or no-progress drop.

## The self-audit checklist

Each question has a mechanical answer.

1. **Contract coverage** - does every goal, constraint and acceptance criterion map to a check I ran, or to an
   explicit `out-of-scope: <reason>`? An unmapped line is FAIL, not a rounding error.
2. **Freshness** - was every check run *in this run*? Name the command, its exit code, expected|actual.
3. **Rung match** - is the evidence the cheapest rung that actually proves *this* change, and did I climb high
   enough?
4. **Green integrity** - did I read the verdict line of the operation that matters, not a wrapper's exit code?
   Was every known-red named so it cannot mask my regression?
5. **Entry precondition** - does the headline behaviour work end to end? If not, the status is In Progress.
6. **No open manual item under a green.**
7. **Probe invariant** - a ticket-id probe exists in code iff the ticket is in the needs-manual-test status.
8. **Scope purity** - every edit inside the declared Files Touched; everything found outside scope was parked
   and reported, not fixed inline; the active ticket never switched.
9. **Hygiene gates** - the diff passes them, and this change deleted what it made dead.
10. **Recurrence** - is this defect type one I have now hit more than once? Propose promoting it to a
    mechanical gate rather than re-catching it by eye.
11. **Doc sync** - registry records stated, ship-together surfaces touched, ledger written, catalogs
    regenerated once.
12. **House style** - prose and UI only: `..`, plain hyphen, `ё`. Code untouched by these rules.
13. **Filesystem safety** - no writes to the repo root; scratch under `temp/<ticket>/`; nothing left behind.
14. **Persona pass** (user-visible changes) - zero jargon, zero mandatory configuration before first success,
    every failure states a human next step. **For a destructive action the pass condition inverts**: the
    confirmation fires and cannot be force-bypassed for dangerous targets, and a `--force`/`-y` flag skips
    only the prompt, never the safety checks.
15. **Coverage and reach** - does anything here reduce supported platforms, countries, age rating, minimum OS,
    or device coverage? **Hard stop.**
16. **Contract boundary** - if the diff changes what another product reads, writes or reproduces, the
    catalog amendment exists with its version bump, and the conformance vectors ran against the catalog's
    copy at that version. Code ahead of its contract is FAIL, whatever the tests say.
17. **Claim audit** - re-read my own final message and delete every "should / probably / seems / looks fixed".
    Each is either replaced with a cited result or the claim is withdrawn.

## Composition with the repo's own skills

- **Call, do not reimplement.** This skill owns the lifecycle, the evidence discipline, the verdict and the
  closure. It **delegates** compile/test/deploy mechanics by invoking the repo's build skill or its script,
  and never re-specifies build flags.
- **Defer where the project skill already covers a stage.** Several repos' build skills already own "verify
  the real behaviour, because unit tests do not cover interop" and "capture user-facing notes for the next
  release". Their "Done means" stays the local authority; supply a step only where they have none.
- **Never invoke the release flow from here**, under any wording - "finish it", "ship it". Surface that the
  next step is a release, and stop.
- **A build script that also commits is opt-in only.** Read the script's contract before running it.

## Communication

Chat in Russian; write files, code, comments, logs, commit messages and script console output in English -
including build and release scripts only the owner ever sees. Dry and concise, high autonomy: run searches,
builds and CLI chores without asking, background long jobs and keep working, flag blockers up front. No
trailing "what I did" summary - the diff speaks. Push back once with evidence if a call looks wrong, then
execute it cleanly. Reserve questions for genuine forks the owner must own: scope, product intent, UI
ambiguity.
