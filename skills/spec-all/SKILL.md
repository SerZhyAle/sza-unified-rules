---
name: spec-all
description: Take one ticket of any SZA project from where it stands to its audit - claim the ticket's lease, check drift, then run the spec-to-audit lifecycle for it (spec, plan, implement, evidence, self-audit) and release the lease. A new idea text is captured as a Draft first. The ticket may be named across projects as <key>:<id> (fms-web:S0123), and a bare project key takes that project's next eligible ticket. Use on /spec-all, /sa, "take S0123 to done", "do this ticket", "work this ticket end to end", "/sa fms-web:S0123", "/sa fms-web", or on the Russian phrasings - "доведи тикет до конца", "прогони тикет", "сделай тикет", "возьми S0123 в работу", "возьми тикет проекта fms-web". Owner-invoked; one ticket, then stop; it never tags, publishes or releases.
---

# Spec all - one ticket, end to end

The lifecycle is [spec-to-audit](../spec-to-audit/SKILL.md) and is **not restated here**. What this skill adds is the
part that is the same in every project and was missing outside FastMediaSorter_mob_v2: naming the ticket, claiming
its lease so two sessions never work it at once, picking the stage the ticket's status says it is at, and handing
the lease back. One ticket, one pass, then stop - a loop over the queue is the portfolio runner (`pq`), not this.

`/sa` is the same command (skill `sa`); the arguments are the same.

A project that ships its own `.claude/commands/spec-all.md` (FastMediaSorter_mob_v2) has its own pipeline with its
own stages, paths and flags (`-m`); in that project that file is the command and this skill is not used.

## Usage

```text
/spec-all S0123            the ticket, in the project of the current folder
/spec-all <slug>           a ticket by its slug
/spec-all fms-web:S0123    one ticket of a registered project, from any folder
/spec-all fms-web          the next eligible ticket of that project, from any folder; then stop
/spec-all <idea text>      capture the idea as a Draft ticket (spec-draft), then work that ticket
```

An empty invocation stops with one line: no ticket and no idea given.

## Step 0 - Resolve the plugin root

```powershell
$sza = if ($env:CLAUDE_PLUGIN_ROOT) { $env:CLAUDE_PLUGIN_ROOT } else {
    ((Get-Content "$HOME/.claude/plugins/installed_plugins.json" -Raw | ConvertFrom-Json).plugins.'sza@sza-unified-rules' |
        Sort-Object lastUpdated -Descending | Select-Object -First 1).installPath
}
"$sza"
```

`CLAUDE_PLUGIN_ROOT` is not exported into a tool shell. **Print the resolved path and paste it literally.** Every
ticket tool is `<root>/tools/harness/<cluster>/<script>.ps1`, run from the project with `-WorkingDirectory`; the
harness finds the project by walking up from that folder to `.sza-profile.json`, so the call is the same in a
project that has the `tools/harness.ps1` forwarder and in one that has not:

```powershell
pwsh -NoProfile -WorkingDirectory "<project root>" -File "<root>/tools/harness/spec_catalog/<script>.ps1" <arguments>
```

A project with its own `scripts/spec_catalog/` names its entry points in its `CLAUDE.md`; use those, same arguments.
Read the agent-rules file of the project the ticket belongs to (Step 1's `root`) first - the slots spec-to-audit lists (build, test, closure) are filled from it.

## Step 1 - Name the ticket and its project

Ticket ids are unique only inside one project (`S0021` is a different ticket in each of several), so the project is
named **before** any ticket is read. The argument goes through the resolver, which decides the same way every time and
only reads (from the folder the command was typed in):

```powershell
pwsh -NoProfile -File "<root>/tools/harness/portfolio/resolve-ticket.ps1" -Arg "<the argument text>"
```

One JSON line comes back: `{ kind, project, root, id, slug, reason }`. Exit 0 is a reading; exit 2 is `refused` or
`ambiguous` - print its `reason` in one line and **stop**. Nothing else is tried: a failed or ambiguous lookup never
operates on a same-numbered ticket in the current project.

| `kind` | Argument | Do |
| --- | --- | --- |
| `ticket` | `<key>:<id>`, `<key>` a registered project | use `id` in the project at `root` |
| `project-next` | a bare registered project key | pick that project's next eligible ticket, as [spec-next](../spec-next/SKILL.md) Step 1 does (`spec-next-preflight.ps1 -Claim` with `-WorkingDirectory` set to `root`); work the ticket it selects, then stop. `selected` null -> print `selected_none_reason` and stop |
| `local-id` | `S0123` (the project's own id shape) | use `id` in the current project |
| `local-slug` | a slug of the current project | `id` is the hit (the resolver ran `select`'s whole-slug match on the ledger) |
| `idea` | free text | capture it with the [spec-draft](../spec-draft/SKILL.md) skill's script for this project (its Step 3, the owner's words verbatim); the id is on its `drafted <key>:<id>` line. Capturing is all that step does - research starts in Step 3 |

**Precedence, first match wins:** (1) `<key>:<id>` with a registered key; (2) a bare token equal to a registered project
key (exact, case-sensitive), no other words; (3) the current project's own id shape; (4) a slug of the current project;
(5) free text is an idea. A token that is both a registered key and a local id or slug is **ambiguous** and refused with
one line naming both readings (`use <key>:<id> or the slug with its id`) - the skill never guesses. A `<token>:<id>`
whose token is not a registered key is not a project reference. A registered key with an id its ledger does not hold is
refused (`no such ticket in <key>`).

## Step 2 - Claim the lease and read the ticket, in one call

The project root is the resolver's `root` (the current project's for a local reading). **Every** tool call from here to
the release runs with `-WorkingDirectory` set to it - the lease, the status moves, the audit - so a ticket of another
project is never read or changed through the current folder.

```powershell
pwsh -NoProfile -WorkingDirectory "<project root>" -File "<root>/tools/harness/spec_catalog/spec-preamble.ps1" -Id <id> -Reason "spec-all"
```

One block comes back - `status`, `file`, the tactical phase files, whether a `## Last Audit` exists, `lease`,
`drift` - read it once.

| Exit | Meaning | Do |
| --- | --- | --- |
| 0 | the record is resolved and the lease is this session's | Step 3 |
| 2 | the id is in neither journal | say so; if the argument was free text the capture failed - quote it; stop |
| 3 | a live sibling session holds the lease | report the holder and the chat lines the block prints, and stop **before any work** |

A runtime with no session id prints a `lease handoff:` path with the claim: keep it and pass `-Handoff <path>` on
every later re-claim and on the release. Re-claim at a long phase boundary
(`locks/ticket-lease.ps1 -Verb Claim -Id <id> -Reason "spec-all"`) so the heartbeat stays fresh.

`drift: DRIFT` on a Draft, Approved, Tactical or Broken ticket means code for it may already exist: read the spec,
and if no `## Last Audit` exists write one from what the code already holds, then go to the audit stage instead of
building it again.

## Step 3 - Work it from its status

The status says which stage of spec-to-audit is next. Do **not** redo finished work; read the spec and the plan
files and continue.

| Status | Continue at |
| --- | --- |
| `Draft` | Stage 0 triage, then Stage 1 - research, write the spec, settle the owner inputs the code cannot answer; the gate is `Approved` |
| `Approved` | Stage 2 (plan), or straight to Stage 3 when triage chose a primitive spec |
| `Tactical`, `In Progress` | Stage 3 - implement from the plan; continue where its progress marks stop |
| `Partial`, `Broken` | Stage 3 on what the last audit names as open, then Stages 4-5 |
| `Implemented` | Stages 4-5 - evidence and self-audit; a manual or on-device item left open keeps it at `BlockNeedUserTest` |
| `BlockQuestions` | not this command: run [spec-quiz](../spec-quiz/SKILL.md) first, release the lease, stop |
| `BlockNeedUserTest`, `BlockExternal`, `BlockByOtherTask` | report what it waits for, release the lease, stop |
| `Verified` and the closed statuses | nothing to do; say so, release the lease |

Status moves go through `spec_catalog/update.ps1 -Id <id> -Status <word>` (it rewrites the spec's status line and
the ledger together), never by hand. Closing the ticket at the end of the audit goes through the project's closure
facade (spec-to-audit slot 5).

**Between releases nothing above 5 seconds runs** ([TESTING_AND_QA.md](../../rules/TESTING_AND_QA.md) section 2): a
build or suite with no fast form is recorded in the audit as a `RELEASE` item and the report says "not built, not
tested until the release".

## Step 4 - Release the lease and report, in Russian

```powershell
pwsh -NoProfile -WorkingDirectory "<project root>" -File "<root>/tools/harness/locks/ticket-lease.ps1" -Verb Release -Id <id> [-Handoff <path>]
```

Release on every exit - finished, blocked, or stopped by an error - so the queue never waits on a dead lease. Then
one block: the ticket, `Было` and `Стало` (status), what was done in each stage reached, what is still open and who
owns it, and the next step if there is one. When the next step is a release, say so and stop
([release](../release/SKILL.md)).

## What this skill never does

- Work a ticket whose lease a live sibling holds, or skip the release of its own lease.
- Take a second ticket: when this one ends, it stops. The next one is `/spec-next` or `pq`. A bare project key is one
  ticket too, never the project's queue.
- Fall back to a same-numbered ticket of the current project when a `<key>:<id>` lookup fails or is ambiguous.
- Answer an owner question itself - a ticket that needs the owner's call goes to `BlockQuestions` and stops.
- Tag, publish, release, commit or push unless the project's own rules and the owner's request say to commit.
- Edit `spec-catalog.jsonl` or the queue files by hand.
