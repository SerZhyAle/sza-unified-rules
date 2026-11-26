# The audit verdict - vocabulary, scoring, and the output block

Reference for the `spec-to-audit` skill, Stage 5. This is the portfolio's verdict language; using it
consistently is what makes "done" mean the same thing in every repo.

## The audit is static by construction

It re-derives its verdict from the spec's own contract using greps and file checks. **It does not re-run the
build.** That is what keeps it cheap enough to actually run every time, and it is how the strongest existing
implementation in the portfolio works.

Static does not mean nothing ran. **`Verified` rests on a check this ticket executed** - the evidence Stage 4
produced, recorded in the block with its command and exit code. An audit that only read files ends at
`Implemented`.

Extract the verification contract from two places:

- **the spec** - goals, constraints, research items, acceptance criteria;
- **the plan** - per-phase Files Touched, step verifications, done criteria.

Then run each check and record exactly one outcome.

## Seven outcomes

| Outcome | Meaning |
| --- | --- |
| **PASS** | The check ran and the contract holds. |
| **WARN** | The contract holds ambiguously - most often a hit-count mismatch. |
| **FAIL** | The contract is broken. |
| **MANUAL** | Only a human at the keyboard, or a real device or target, can close this. |
| **UNCHECKABLE** | No mechanical check exists for this claim at this rung. |
| **EXEMPT** | Explicitly out of scope, with the reason recorded. |
| **RELEASE** | The proving rung is the full build or a test above 5 s; it was not run between releases (TESTING_AND_QA §2). The item names the exact command the release will run. |

## Scoring

| Verdict | Condition |
| --- | --- |
| **Verified** | every check is PASS, EXEMPT or a closed MANUAL, with **zero WARN, zero FAIL and zero RELEASE**, and at least one executed check recorded under `### Checks run` |
| **Implemented** | zero WARN and zero FAIL, but a RELEASE item is open or no check was executed |
| **Partial** | zero FAIL, at least one WARN |
| **Broken** | at least one FAIL |

Auto-chain: `Partial` or `Broken` -> the fix pass -> re-audit. `Verified` -> stop. `Implemented` -> stop, and the
report names the ticket as `Implemented (unrun checks: <the RELEASE count>)`.

## Grep rules

- **A grep miss is FAIL.** Not a warning, not a note.
- **A hit-count mismatch is WARN** - expected 1, found 3 - and **every hit is listed** in the finding.
- **Hits count only on declaration lines.** A match inside a comment or a string literal is not evidence that
  a symbol exists.

## The two refusals that protect "Verified"

1. **An open MANUAL item can never sit beneath a Verified.** The ticket stays at `BlockNeedUserTest` or
   `Partial` until a human closes it and a **re-audit** turns it green. A verdict is never upgraded by
   assertion.
2. **Entry precondition for `Implemented` / `BlockNeedUserTest`**: the headline user-visible behaviour already
   works end to end. Created classes, wired contracts and a passing compile are **milestones, not
   deliverables**. Never invite a human to test while the advertised action still logs, shows a placeholder,
   or no-ops.

These are the two places status gets inflated. Treat them as refusals.

## Never approve a Verified above a Broken phase

If any phase of the plan is `Broken`, the ticket cannot be `Verified`, regardless of how the individual checks
score.

## The output block

Findings go into a compact, **overwritten** `## Last Audit` block at the bottom of the spec - the latest verdict
only, about 40 lines at most, and never a separate audit file per run, which accumulates noise nobody reads. A block
about to be overwritten goes to the [evidence log](#the-spec-stays-short) first, as does whatever does not fit.

```markdown
## Last Audit

**Date:** <YY-MM-DD HH:mm> | **Mode:** <static|re-audit|sweep> | **Outcome:** <Verified|Implemented|Partial|Broken>
**Counts:** PASS <n> | WARN <n> | FAIL <n> | MANUAL <n> | UNCHECKABLE <n> | EXEMPT <n> | RELEASE <n>

### Checks run
- `<command>` - exit <code> - expected: <..> | actual: <..>

### Action items
1. <finding> - <file:line> - <what must change>
2. ..

### Manual / on-target
- [ ] <the check a human must run, and what would count as passing>
```

**Every executed check is one line under `### Checks run`**: the command between backticks, then `exit <code>`. The
status tool refuses `Verified` unless the block holds at least one such line with `exit 0`, its `RELEASE` count is 0
and no line of it starts with the word `RELEASE` (TASK-FLOW 0.48; the patterns are in
`tools/harness/spec_catalog/_audit-evidence.ps1`). Never write the line for a command that did not run in this
ticket, and with nothing executed write no line at all.

**Write the `**Counts:**` line in exactly that shape** - all seven words and a number after each, on one line, as the
first such line of the block - so that a script can read the tally. The canon's harness reads its `RELEASE` figure at
the entry into `Verified` and acts on no other: a ticket that stays `Implemented` is not offered by the automatic
ranking whatever its counts say (TASK-FLOW rule 18), and the hold that once stamped the code tree after a
release-only audit is withdrawn (rule 67, 0.43). What stops a pass that works a ticket without moving it is the idle
hold of rule 24.

## The spec stays short

A spec is the working document the next pass reads whole. Logs and evidence live beside it.

- **The owner's words stand once, in section 0.** No later section or second block copies them; refer to section 0.
- **Records go to one file**, `<id>_<slug>/evidence/log.md` in the ticket's folder beside the spec (TASK-FLOW rule 19):
  per-pass records, earlier audit blocks, site-audit tables, command output, measurements. It is appended to, one dated
  `## <yyyy-MM-dd> - <pass>` section per pass, and never rewritten.
- **The spec links it once**, relatively, so the link holds when the file and the folder move (rule 70):
  `Evidence: [evidence log](<id>_<slug>/evidence/log.md)`. The first record adds the line; later passes leave it.
- **What stays in the spec** is what a script reads - status lines, literal tokens, question blocks, `**Release gate:**`,
  `**Device check:**`, the `## Last Audit` block with its counts, executed-check lines and RELEASE items - and what the
  next pass needs in order to act.
- **A table another ticket holds is cited, not pasted.**

**The status tool holds the limit (TASK-FLOW 0.53).** A spec above 40 KB (40960 bytes) enters `Implemented`,
`Verified` or `BlockNeedUserTest` only with that line: it starts with `Evidence:` and its relative link names an
existing file under `<id>_<slug>/evidence/`. On a refusal, move the logs there and add the line.

`tools/harness/spec_catalog/list-fat-specs.ps1 -Root <repo>` lists the spec files above 40 KB with their three biggest
sections. It moves nothing: moving a ticket's text is the work of a pass on that ticket.

## The probe-invariant sweep

Part of every audit, not a separate chore. A probe log line carrying the ticket id exists in code **if and only
if** the ticket is in the needs-manual-test status.

If the verdict moves the ticket out of that status, grep the ticket id and delete every probe line. The
operation must be **idempotent** and must also run on the cancel and archive paths - otherwise a cancelled
ticket leaves probes in shipped code. Permanent logs never carry a ticket id.

## Severity taxonomy for phase-boundary findings

| Severity | Shape | Handling |
| --- | --- | --- |
| **P0** | crash, data loss | fix now, with evidence at the matching ladder rung |
| **P1** | race, main-thread I/O, unbounded cache, unreleased resource | fix now, same evidence bar |
| **P2** | hot-path waste | park unless in scope |
| **P3** | style | park |

P0 and P1 are closed with **evidence, not opinion**.

## Audit triggers - when to escalate the rung

Escalate verification when the change touches any of: a new screen, worker or repository; lifecycle;
concurrency, listeners or observers; a database schema or migration; a player, media, caching or network
path; startup; a DI scope; the build or minification configuration.

## Recording a manual check

Two habits worth keeping from the strongest repo in the portfolio:

- **A manual check is recorded with a date and an explicit not-covered list** - what the live run did *not*
  exercise and still needs a human. "Verified live on `<date>`" alone hides the gap.
- **Manual checks accrete into a harness**, they do not stay ad hoc. Where a repo has a UI-driving harness,
  write new manual checks on top of it instead of hand-rolling a scratch script.

Two audit lessons worth generalizing:

- **A guard test must itself be provable-failable.** A walk that inspects nothing passes just as quietly as a
  clean one.
- **A rebuild-type bug needs a repeated rebuild** - the first one can never fail.

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
