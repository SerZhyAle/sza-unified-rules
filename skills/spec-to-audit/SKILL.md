---
name: spec-to-audit
description: Run a task through the full SZA lifecycle - triage, spec, plan, implement, evidence, self-audit, documentation, commit - with a named gate at every boundary that refuses to advance when its preconditions are missing. Use when asked to implement a specification, "do this properly", "сделай по спецификации", to check whether something is actually implemented, to audit your own work before committing, to proceed to the next phase, or to sweep the tickets waiting on a manual check. Free and reversible: it never tags, publishes, or releases.
---

# Spec to audit - the lifecycle and its gates

The value here is not the audit at the end; it is that **every boundary is a gate that refuses**. A stage may
not be left until its gate is true, and no gate is satisfied by an opinion.

This skill lives entirely on the **build** side of the billable wall. It never creates or pushes a `v*` tag,
never submits a manifest, never uploads to a store, never publishes a site. When the next step is a release,
say so and stop - see [release](../release/SKILL.md).

Canon: [DEVELOPMENT.md](../../rules/DEVELOPMENT.md), [TESTING_AND_QA.md](../../rules/TESTING_AND_QA.md),
[AI_USAGE.md](../../rules/AI_USAGE.md), [AUTHOR.md](../../rules/AUTHOR.md),
[INVARIANTS.md](../../rules/INVARIANTS.md).

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

**Gate - all three:**
- Every *required* research item is closed. An open required item **stops the pipeline** - this is an encoded
  stop, not a judgement call.
- Every user-facing placement, visibility, or fallback decision is resolved. Surface UI ambiguity before
  implementing; never guess. (But do not ask what the architecture already answers - research it and
  recommend.)
- The ticket has one authoritative record with an id and a first-line **Status:**, mutated only through its
  tool where one exists - a catalog CLI, a journal - never hand-edited.

Status vocabulary, identical across the portfolio:
`Draft -> Approved -> Tactical -> In Progress -> Implemented -> Verified`, plus `Partial`, `Broken`,
`Archived`, and the `Block*` family (`BlockNeedUserTest`, `BlockByOtherTask`, `BlockQuestions`,
`BlockExternal`). **Every transition into a `Block*` status carries a one-line reason note**, cleared by
removing the condition and advancing exactly one level.

**Two literal tokens, because direction is not recoverable from prose.** A ticket's "related tickets"
section names blockers, successors, consumers and neighbours in one breath and is equally happy to *deny*
a relationship - measured on the reference corpus, **98 spec files yield a ticket id there against 15 that
carry a real directional line**, and most of the lines containing "blocks" use it to say "does not block".
A scraper reading ids out of that prose makes a producer look blocked by its own consumers. So the record
carries a literal token on its own line for each direction - one naming what blocks this ticket, one
naming the ticket that inherited an unanswered question. An id in prose is a mention; an id in the token
is a claim. Canon: [DEVELOPMENT.md](../../rules/DEVELOPMENT.md) §8.

Say which of the two is actually enforced, because they usually are not enforced alike: a carried-question
token is naturally a **hard gate at closure** (the write is refused), while a blocker token is often only
a **soft exclusion at selection** (nothing refuses the write; the ticket is skipped when work is picked
automatically). Both are legitimate - claiming both are gated is not.

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
An unchecked blocker is the encoded stop.

## Stage 3 - Implement

**Per-step loop:**
1. Re-read the step; verify its declared dependency step is done.
2. Confirm every symbol the step references **actually exists at the stated path**. If not, abort - never
   invent a path.
3. Ambiguity check: any `<TODO>`, `<choose..>` or `???` is a hard stop. Set `BlockQuestions`. Do not guess.
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

Also mandatory here: the **probe-invariant sweep**. If the verdict moves the ticket out of the
needs-manual-test status, grep-and-delete every ticket-id probe line - idempotently, including on the cancel
and archive paths.

## Stage 6 - Documentation

- **Documentation-context loop**: at task start, at any material scope change, at **each phase boundary**, and
  **before the final response**, consult the project's document registry for the touched area and state which
  records are affected versus unchanged. A registered document that changes is re-validated by its tool.
- **Ship-together surfaces**: every user-facing surface lands **atomically, every locale in one edit**. This
  is [feature-to-site](../feature-to-site/SKILL.md) - invoke it rather than improvising a surface list.
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
16. **Claim audit** - re-read my own final message and delete every "should / probably / seems / looks fixed".
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
