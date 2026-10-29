---
name: spec-all
description: Take one ticket of any SZA project from where it stands to its audit - claim the ticket's lease, check drift, then run the spec-to-audit lifecycle for it (spec, plan, implement, evidence, self-audit) and release the lease. A new idea text is captured as a Draft first. Use on /spec-all, /sa, "take S0123 to done", "do this ticket", "work this ticket end to end", or on the Russian phrasings - "доведи тикет до конца", "прогони тикет", "сделай тикет", "возьми S0123 в работу". Owner-invoked; one ticket, then stop; it never tags, publishes or releases.
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
Read the project's agent-rules file first - the slots spec-to-audit lists (build, test, closure) are filled from it.

## Step 1 - Name the ticket

| Argument | Do |
| --- | --- |
| `S0123` (the project's own id shape) | use it |
| a slug | `spec_catalog/select.ps1 -Query <slug> -Format json` - the query matches the whole slug only; a hit -> its id, `[]` -> say the slug is unknown and stop (a partial word is not searched, and free text is an idea, below) |
| free text | capture it with the [spec-draft](../spec-draft/SKILL.md) skill's script for this project (its Step 3, the owner's words verbatim); the id is on its `drafted <key>:<id>` line. Capturing is all that step does - research starts in Step 3 |

## Step 2 - Claim the lease and read the ticket, in one call

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
- Take a second ticket: when this one ends, it stops. The next one is `/spec-next` or `pq`.
- Answer an owner question itself - a ticket that needs the owner's call goes to `BlockQuestions` and stops.
- Tag, publish, release, commit or push unless the project's own rules and the owner's request say to commit.
- Edit `spec-catalog.jsonl` or the queue files by hand.
