---
name: spec-draft
description: Capture a task description or a problem as a Draft ticket in any SZA project - the owner's words kept verbatim in the spec, the row added to the project's own ticket queue (PLAN/RELEASE_QUEUE.md), and a plain report of whether the portfolio queue (pq) will pick it up and when. Use on /spec-draft, "draft a spec", "park this task", "add a bug to pq", "put this in the queue of <project>", or on the Russian phrasings - "создай спеку", "спека для проекта", "закинь задачу в очередь", "добавь баг в pq", "задача для <проект>", "зафиксируй проблему в проекте". Owner-invoked; it does not work the ticket and does not research it.
---

# Spec draft - one task into a project's queue and the portfolio queue

The owner gives a task or a problem for **any** project, from a session in that project or from any other. The
skill turns it into a `Draft` ticket: the ledger row, the spec file with the owner's words in section 0, and a row
at the end of the project's own ticket queue. The shared `pq` robot works the tickets of every registered, enabled
project, so a ticket in that queue is what it picks up - and the report says plainly when it will not.
The capture also refreshes the registered project's rows in `PORTFOLIO_QUEUE.md`; report any sync failure and
the printed repair command. Status changes through the shared catalog refresh both projections automatically.

**Capture fidelity is the whole contract.** The owner's text goes into the spec exactly as written: original
language, no rewriting, no summary, no `..` or `ё` clean-up (the house text style does not cover spec files).
Pasted excerpts - a stack trace, a log, repro steps - are part of the text. Losing material defeats the skill.

This skill captures and reports. It does **not** research, approve, plan or build the ticket (that is
[spec-to-audit](../spec-to-audit/SKILL.md)), and it never starts `pq`.

## Usage

```text
/spec-draft <free-form description>              the project holding the current folder
/spec-draft <project-key> <free-form description>  a key from `pq list`
/spec-draft <slug>                                 an explicit kebab-case name for the ticket
```

Optional words in the request: `urgent`/`срочно` (hotfix), a priority number, `pin`/`первым` (put it first in the
portfolio queue). A bare `Sxxxx` is an existing ticket, not a draft: do not capture it.

## Step 0 - Resolve the plugin root

```powershell
$sza = if ($env:CLAUDE_PLUGIN_ROOT) { $env:CLAUDE_PLUGIN_ROOT } else {
    ((Get-Content "$HOME/.claude/plugins/installed_plugins.json" -Raw | ConvertFrom-Json).plugins.'sza@sza-unified-rules' |
        Sort-Object lastUpdated -Descending | Select-Object -First 1).installPath
}
"$sza"
```

`CLAUDE_PLUGIN_ROOT` is not exported into a tool shell. **Print the resolved path and paste it literally** into the
command in Step 3. The script is `<root>/tools/harness/portfolio/spec-draft.ps1`.

## Step 1 - Decide four things, and say them in one line

1. **Project.** The first word is a registered key (`pwsh -NoProfile -File "<root>/tools/harness/portfolio/pq.ps1" list`)
   -> that project. Otherwise the project of the current folder. Neither -> ask which, listing the keys. Do not
   guess between two plausible projects.
2. **Slug.** An explicit kebab-case word is the slug. Otherwise 2-5 content words in English, lowercase,
   `[a-z0-9-]`, at most 60 characters, never starting with `spec_`. Prefix `bugfix-` for a bug, crash or defect
   (`ошибка`, `падает`, `краш`, `баг`), `hotfix-` for an urgent or release-blocking one (`срочно`, `блокер`) -
   never both. The script derives the priority from the prefix: 95, 90, otherwise 50.
3. **Complexity.** Pass `-Complexity "<light|medium|hard> - <one-line reason>"` only when the finding itself
   settles it: a known one-line fix is `light`, a symptom with no located cause is `hard`. Otherwise omit it - the
   ticket gets `medium - not assessed at capture` and its first pass settles the level. A capture never researches
   to find the level.
4. **Dedup.** When the text carries an error class, an exception or a distinctive symptom, pass it as
   `-DedupQuery "<that>"`. Several distinct problems in one message -> one capture each.

## Step 2 - Write the owner's words to a file

Use the Write tool, to a UTF-8 file **outside every repository** (the session scratchpad), named
`draft-<slug>.txt`. The content is the owner's text and every excerpt they gave, verbatim. Do not pass the text as
a command-line argument: quotes, newlines and encodings do not survive it.

## Step 3 - One call

```powershell
pwsh -NoProfile -File "<root>/tools/harness/portfolio/spec-draft.ps1" -Project <key|path> -Slug <slug> -TextFile <file> [-Complexity "<level> - <reason>"] [-DedupQuery "<symptom>"] [-Priority <n>] [-Pin]
```

Leave `-Project` out to use the current folder's project. Add `-WhatIf` first when you want only the dedup report.
Add `-Pin` only when the owner asked for the ticket to go first in the portfolio queue. `-Attach "<path;path>"` is
accepted only by a project whose own capture script takes attachments; it is refused otherwise, before anything is
created.

The script uses the project's own `scripts/utils/capture-draft.ps1` when it has one (FastMediaSorter_mob_v2 does:
its templates, tier and attachments), else the canon's, which needs `PLAN/TICKET_TEMPLATE.md`.

| Exit | Meaning | What to do |
| --- | --- | --- |
| 0 | the ticket exists | Step 4 |
| 1 | the catalog refused, or the spec file could not be written | quote the message; do not retry blindly - a row without its file is named in it |
| 2 | bad invocation, unknown project, or no task flow there | fix the argument; for "no task flow" run [task-flow-init](../task-flow-init/SKILL.md) in that project first |
| 3 | the dedup query hit a **closed** ticket | the defect is already dealt with: name that ticket, create nothing; add `-AllowClosedDuplicate` only if the owner says it came back |

An **open** ticket in the `dedup:` lines that already covers the problem is not an error: reference its id to the
owner and, unless they say otherwise, stop. A draft the owner asked for is otherwise always written.

## Step 4 - Report, in Russian, from the script's own lines

The last line is the result: `drafted <key>:<id> file=<path> priority=<n> pq=<verdict> position=<p>/<total>`.
Give the owner: the ticket id and file, the project, and what `pq` will do:

| `pq=` | Say |
| --- | --- |
| `dispatchable` | pq takes it. Quote the position: it is **N of M in the project's own queue**, so N-1 tickets run before it (a new ticket goes to the end of the current package - the owner orders that file). For an urgent one, offer `-Pin` |
| `held-by-queue`, `held` | captured, but the project is on hold - `pq` will not touch it. Say that lifting a hold is the owner's call; **do not remove it** |
| `disabled` | registered but not enabled - same: report, do not enable |
| `unregistered` | `pq` does not know the project. Give the register command the script printed; registering needs the owner's choice of permission mode |
| `not-offered`, other | the project's own picker does not offer it; quote the reason the script printed |

Do not summarise this as "queued" when the verdict is anything but `dispatchable`. Then **return to the task that
was in flight** - a capture never switches the active ticket, and the ticket is not worked now.

## What this skill never does

- Lift a hold, enable a project, register one, or reorder `PORTFOLIO_QUEUE.md` - except the single `pq pin` row that
  `-Pin` writes on the owner's explicit word. The automatic projection refresh keeps existing order and holds.
- Capture a finding an agent noticed on its own as a plain draft. In a project `pq` works, a fresh Draft is
  eligible at once, before anyone has triaged it (FastMediaSorter_mob_v2 measured its runner attempting three
  fresh parked drafts within half an hour of capture). Such a finding goes through the project's own parking
  mechanism if it has one (FastMediaSorter_mob_v2: its `/spec-draft -Parked`), or is reported to the owner instead.
- Commit, push, or run the ticket.

## Gates - what refuses

| Gate | Refuses |
| --- | --- |
| Step 1 | an ambiguous project; an empty description |
| Step 3 | an invalid slug, a missing or empty text file, an unknown project, a project with no task flow, `-Attach` without a script that takes it |
| Step 3 | a dedup hit on a closed ticket without `-AllowClosedDuplicate` |
| Step 3 | `-Pin` for a project `pq` will not dispatch |
