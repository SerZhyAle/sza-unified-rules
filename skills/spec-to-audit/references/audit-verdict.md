# The audit verdict - vocabulary, scoring, and the output block

Reference for the `spec-to-audit` skill, Stage 5. This is the portfolio's verdict language; using it
consistently is what makes "done" mean the same thing in every repo.

## The audit is static by construction

It re-derives its verdict from the spec's own contract using greps and file checks. **It does not re-run the
build.** That is what keeps it cheap enough to actually run every time, and it is how the strongest existing
implementation in the portfolio works.

Extract the verification contract from two places:

- **the spec** - goals, constraints, research items, acceptance criteria;
- **the plan** - per-phase Files Touched, step verifications, done criteria.

Then run each check and record exactly one outcome.

## Six outcomes

| Outcome | Meaning |
| --- | --- |
| **PASS** | The check ran and the contract holds. |
| **WARN** | The contract holds ambiguously - most often a hit-count mismatch. |
| **FAIL** | The contract is broken. |
| **MANUAL** | Only a human at the keyboard, or a real device or target, can close this. |
| **UNCHECKABLE** | No mechanical check exists for this claim at this rung. |
| **EXEMPT** | Explicitly out of scope, with the reason recorded. |

## Scoring

| Verdict | Condition |
| --- | --- |
| **Verified** | every check is PASS, MANUAL or EXEMPT, with **zero WARN and zero FAIL** |
| **Partial** | zero FAIL, at least one WARN |
| **Broken** | at least one FAIL |

Auto-chain: `Partial` or `Broken` -> the fix pass -> re-audit. `Verified` -> stop.

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

Findings go into a compact, **overwritten** `## Last Audit` block at the bottom of the spec - never a separate
audit file per run, which accumulates noise nobody reads.

```markdown
## Last Audit

**Date:** <YYYY-MM-DD> | **Mode:** <static|re-audit|sweep> | **Outcome:** <Verified|Partial|Broken>
**Counts:** PASS <n> | WARN <n> | FAIL <n> | MANUAL <n> | UNCHECKABLE <n> | EXEMPT <n>

### Action items
1. <finding> - <file:line> - <what must change>
2. ..

### Manual / on-target
- [ ] <the check a human must run, and what would count as passing>
```

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
