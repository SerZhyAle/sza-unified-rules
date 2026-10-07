---
name: task-flow-init
description: Set up how a project works its tasks - the numbered ticket ledger, the queue and ready/done plan files, a ticket template, and an R0 runner that works the backlog one ticket per fresh agent process - from nothing, in one pass, and rehearse it before trusting it. Use when asked to start a new project's task flow, set up a task queue or backlog, build an R0 runner for a project, number and track tasks, "run all the tasks automatically", or on the Russian phrasings - "настрой задачи для проекта", "очередь задач", "нумерация задач", "раннер R0", "прогнать все задачи автоматически", "новый проект с нуля, много задач". Day 0 only; working a ticket is spec-to-audit.
---

# Task flow init - day 0 of a project's tickets and its R0 runner

The flow is: **a task is a numbered ticket; its ledger row and its spec file are created together; the owner's
order lives in the queue file; a runner takes tickets one at a time, each in a fresh agent process, and
records what happened.** R0 is the smallest correct runner - one agent alone on the tree, no leases, no
locks. Every other runner is R0 plus a per-ticket lease.

This skill creates the files and rehearses them. It does **not** work a ticket (that is
[spec-to-audit](../spec-to-audit/SKILL.md)), write a project's pipeline command, tag, push or publish. The
rules it implements are the `TASK-FLOW` contract in the shared catalog; cite them by id and rule number,
never by path (`TASK-FLOW rule 24`).

Run it **once per project, attended.** An unattended first run of a runner nobody has watched is how a
backlog gets burned.

## Step 0 - Resolve the plugin root

```powershell
$sza = if ($env:CLAUDE_PLUGIN_ROOT) { $env:CLAUDE_PLUGIN_ROOT } else {
    ((Get-Content "$HOME/.claude/plugins/installed_plugins.json" -Raw | ConvertFrom-Json).plugins.'sza@sza-unified-rules' |
        Sort-Object lastUpdated -Descending | Select-Object -First 1).installPath
}
"$sza"
```

`CLAUDE_PLUGIN_ROOT` is not exported into a tool shell; a bare `"$env:CLAUDE_PLUGIN_ROOT/..."` expands to
`/tools/...` and fails. **Print the resolved path and paste it literally** into the commands below - each tool
call gets a fresh interpreter. The harness is `<root>/tools/harness`.

## Step 1 - Read the project first

- A `.sza-profile.json` **and** a ledger already exist -> the project has a flow. Stop; offer only the
  launcher (`-RunnerPath`) and say what is already there.
- Is the agent CLI on `PATH` (`Get-Command claude`)? R0 exits 2 if not.
- Does the project already have a pipeline command that takes one ticket from its status to the next (a
  `.claude/commands` file)? If yes, that is the child's prompt: `-Prompt "/<command> {id}"`. If no, the default
  prompt points the agent at spec-to-audit.
- **Ask the owner once, and only this:** the permission mode the unattended child runs in. The default,
  `bypassPermissions`, lets it edit and run anything in the project; the alternatives are
  `acceptEdits`, `auto`, `plan`. Do not pick the permissive one silently, and write the answer down in Step 6.

## Step 2 - Scaffold

Dry first, then for real. Nothing is overwritten: an existing file is reported `exists` and left alone, so a
second run is safe.

```powershell
pwsh -NoProfile -File "<root>/tools/harness/scaffold/init-task-flow.ps1" -Root . -WhatIf
pwsh -NoProfile -File "<root>/tools/harness/scaffold/init-task-flow.ps1" -Root . -PermissionMode <mode> [-Prompt "<text with {id}>"] [-RunnerPath <project-relative>]
```

It writes: a minimal `.sza-profile.json` (only when absent), the specs and temp directories, the empty ledger,
archive and burned-ids files, the queue / ready / done plan files, `TICKET_TEMPLATE.md`, and the R0 launcher
(default `r0.ps1` in the project root, standalone - it needs no harness at run time).

Then add the temp directory to `.gitignore`: it holds run journals and leases, which are not source.

## Step 3 - Seed the backlog, one ticket at a time

A new project has many tasks at once. Create each with `capture-draft.ps1` - **serially**, never in parallel
(the id is `max + 1` under a lock, and a parallel creator only queues):

```powershell
pwsh -NoProfile -File "<root>/tools/harness/spec_catalog/capture-draft.ps1" -Slug <kebab-slug> -TextFile <file> [-Priority 0..100] [-DedupQuery <symptom>]
```

- The text is the owner's words, **byte for byte** - a paraphrase loses the part the audit later checks against.
  `-TextFile` is the safe form for multi-line text and quotes.
- `-DedupQuery` first for anything that sounds like a bug or a repeat: hits print as `dedup:` lines; whether an
  open one is the same ticket is a decision, not a default. A hit in a closed status stops the capture (exit 3):
  say which ticket it was; `-AllowClosedDuplicate` only when the owner says the old defect really came back.
- Each call creates the row **and** the spec file. A row without its file is a malformed ticket; if the call
  reports that, fix it before creating the next.
- The plan tool appends a queue row per ticket in creation order and **never reorders**. The order the owner
  wants is written by moving lines in the queue file (a bare number is a package, `--` is unscheduled);
  priority only orders what the queue file does not list. Ask the owner for the order; do not infer it.

## Step 4 - Rehearse (the gate before any unattended run)

In this order, each reading its own exit code and output:

1. `validate.ps1` -> exit 0.
2. `pwsh -NoProfile -File ./r0.ps1 -DryRun` -> the order printed is the order the owner expects, and parked
   (`Block*`) tickets are not in it.
3. **One ticket, attended:** `pwsh -NoProfile -File ./r0.ps1 -MaxTickets 1 -TimeoutMinutes 30`. Then read the run
   row (`<temp>/spec-queue/runs-mono.jsonl`) **and** the ticket's new status and spec file. A row that says `ok`
   while the status did not move is a runner problem; a `no-progress` row means the agent had no next step - read
   why before running again.

The part of this that needs no agent is `reference/day0-rehearsal.ps1` in the catalog's `task-flow/` domain: it
builds a throwaway project, runs the scaffold, and checks the rules with a fake child. Run it when the harness
itself changed, not on every project.

## Step 5 - Unattended, with a ceiling

`pwsh -NoProfile -File ./r0.ps1 -MaxTickets <n>` - a ceiling on every unattended run until the journal shows what
a ticket costs. To stop: create the file named by the launcher's `-StopFile` default; the runner finishes the
ticket in hand, consumes the file and exits 0. Do not kill the process to stop it - a killed child leaves a half-written
status.

A second parallel runner (R1..Rn) is added only when the journal shows the single runner's idle time is the
constraint (`TASK-FLOW rule 40`); it needs a per-ticket lease and its own agent identity, which this scaffold
does not create.

## Step 6 - Write it down where the next session will read it

Put four facts in the project's agent-rules file (`CLAUDE.md`, else `AGENTS.md`), so slot 6 of spec-to-audit
("ticket system and id scheme") is filled once instead of rediscovered:

- tasks come from the ledger (`validate.ps1`, `select.ps1`, `search.ps1`) and are created only with `capture-draft.ps1`;
- the owner's order is the queue file; finished work leaves it through the plan tool, not by hand;
- how to run R0 (`./r0.ps1`, the dry-run and the ceiling), and the permission mode the owner chose;
- the statuses a ticket can be in (`Block*` needs a `statusNote`; `Verified` needs a `## Last Audit` block).

## Gates - what refuses

| Gate | Refuses |
| --- | --- |
| Step 1 | a project that already has a flow, a missing agent CLI, a permission mode nobody chose |
| Step 3 | a ticket whose row exists and whose file does not; text that is not the owner's words |
| Step 4 | the unattended run, until the validate, the dry run and one attended ticket have all been read |
| Step 5 | an unattended run with no ceiling |
