---
name: spec-next
description: Work the next ticket of the project's queue without naming it - the harness picks the first eligible ticket in the queue order and claims its lease, then /spec-all takes it from there. One ticket, one pass, then stop. Use on /spec-next, /sn, "what should I work on next", "take the next ticket", "pick the next ticket", or on the Russian phrasings - "возьми следующий тикет", "что дальше по очереди", "следующая задача из очереди". Owner-invoked; it never tags, publishes or releases.
---

# Spec next - /spec-all on the head of the queue

`/spec-next` is [spec-all](../spec-all/SKILL.md) with the ticket chosen by the project's queue instead of by the
owner. One ticket, one pass, then stop. A loop over the whole queue is the portfolio runner (`pq`), not this.

`/sn` is the same command (skill `sn`). It takes no argument: a ticket the owner names is `/spec-all <id>`.

A project that ships its own `.claude/commands/spec-next.md` (FastMediaSorter_mob_v2) has its own picker, with its
own scripts and the `-m` flag; in that project that file is the command and this skill is not used.

## Step 0 - Resolve the plugin root

The same resolution as [spec-all](../spec-all/SKILL.md) Step 0, including the rule that every harness call is
`pwsh -NoProfile -WorkingDirectory "<project root>" -File "<root>/tools/harness/<cluster>/<script>.ps1"`.

## Step 1 - Pick and claim, in one call

```powershell
pwsh -NoProfile -WorkingDirectory "<project root>" -File "<root>/tools/harness/spec_catalog/spec-next-preflight.ps1" -Claim -Reason "spec-next"
```

The pick and the lease are one call, so two sessions never take the same head. The queue order is the project's own
(`PLAN/PQ_QUEUE.md` or `PLAN/RELEASE_QUEUE.md`, release package then line order; the ledger's priority is the
fallback). Never re-derive the pick from priority and never skip the head for a more interesting ticket.

Read `selected` and `selected_none_reason` from the JSON:

- `selected` is set -> print one line, `Next: <id> <status> - <name>`, and go to Step 2. `selected.lease.outcome` is
  `claimed` or `already-mine`; a `claim-error` is not fatal, `/spec-all`'s own claim is the retry.
- `selected` is null -> print `selected_none_reason`. For `all-leased` name each holder in `leased_ids` (id, session,
  minutes since last seen). **Stop** - never wait, poll, or fall back to another ordering.
- a non-zero exit -> quote its error and stop.

A `lease handoff:` path in the result is what a runtime with no session id passes as `-Handoff` on later re-claims
and on the release.

## Step 2 - Delegate

Invoke the Skill tool with skill `sza:spec-all` and the picked id as its args, and follow it exactly from its Step 2:
claim (answers `already-mine`), drift, the stage the status names, release, report. Nothing of it is restated or
overridden here.
