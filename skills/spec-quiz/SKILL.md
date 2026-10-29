---
name: spec-quiz
description: Clear the tickets that wait for the owner's answers (status BlockQuestions) in any SZA project - find them, research what the code and the records already settle, ask the owner only the real decisions as multiple choice, write the answers into each ticket, and restore each ticket one level so the queue can work it again. Use on /spec-quiz, /sq, "quiz S0021", "unblock the tickets", "answer the open questions", "what is waiting for my answers", or on the Russian phrasings - "разблокируй тикеты", "задай мне вопросы по тикету", "вопросы по спеке", "что ждёт моих ответов", "квиз", "сними блок вопросов". Owner-invoked; it writes decisions and moves status, never code.
---

# Spec quiz - drain the owner's questions in any project

A ticket enters `BlockQuestions` in one line and waits for an owner who is ready to answer. This skill is how it
leaves, in **any** registered project: it resolves which tickets are waiting, then runs the canon's procedure -
[spec-to-audit](../spec-to-audit/SKILL.md) "Quiz mode - draining the owner's questions", steps 1-8, which is the
authority and is **not restated here**. What this skill adds is the part that is the same in every project: finding
the tickets, naming the right project, and the mechanics of asking, writing back and moving.

`/sq` is the same command (skill `sq`); the arguments are the same.

## Usage

```text
/spec-quiz                    every ticket in BlockQuestions in the project of the current folder
/spec-quiz S0021              that ticket: looked up by id here first, then in the other projects
/spec-quiz fms-web:S0021      one ticket of a registered project, from any folder
/spec-quiz S0023, 24, 25      one sitting over several tickets (a bare number is the id's trailing digits)
/spec-quiz fms-web            every waiting ticket of that project
/spec-quiz --all              every waiting ticket of every registered project
/spec-quiz S0021 --dry        the questions that would be asked; nothing asked, nothing written, nothing moved
```

A project that ships its own `.claude/commands/spec-quiz.md` (FastMediaSorter_mob_v2) has its own implementation of
the same procedure, with its own tool paths; in that project follow that file for the paths and this skill for the
rest.

## Step 0 - Resolve the plugin root

```powershell
$sza = if ($env:CLAUDE_PLUGIN_ROOT) { $env:CLAUDE_PLUGIN_ROOT } else {
    ((Get-Content "$HOME/.claude/plugins/installed_plugins.json" -Raw | ConvertFrom-Json).plugins.'sza@sza-unified-rules' |
        Sort-Object lastUpdated -Descending | Select-Object -First 1).installPath
}
"$sza"
```

`CLAUDE_PLUGIN_ROOT` is not exported into a tool shell. **Print the resolved path and paste it literally** into the
commands below. The script is `<root>/tools/harness/portfolio/quiz-list.ps1`; it only reads.

## Step 1 - Find the tickets, from the ledgers

Ticket ids are unique only inside one project: `S0021` is a different ticket in each of several projects, and a
filename or a memory of "that one" is not a record. Ask the ledgers:

```powershell
pwsh -NoProfile -File "<root>/tools/harness/portfolio/quiz-list.ps1" [-Id <id>] [-Project <key|path>] [-All] [-Json]
```

| Request | Call |
| --- | --- |
| no argument | none - the project of the current folder |
| an id | `-Id <id>` (the current folder's project, then every other registered project) |
| `<key>:<id>`, a key | `-Project <key>` (plus `-Id <id>`) |
| `--all` | `-All` |

Each waiting ticket prints as `BQ <key>:<id> p<priority> <updated> <name>`, its spec file and the ledger's reason
note; the last line is the count (or, with `-Id`, `here=<key>:<id>=<status>` and `blockquestions=<list>`). `-Json`
gives the same records with the full note.

| Outcome | Do |
| --- | --- |
| the tickets asked for are waiting | go to Step 2 |
| `-Id` and `here=` is `BlockQuestions` | quiz that one; name the other projects' tickets with the same id once, as different tickets, and leave them |
| `-Id` and `here=` is any other status or `absent`, and `blockquestions=` lists others | do not guess. Say in one line that the id here is `<status>` and not waiting, list the waiting ones with their names, and ask which, with `AskUserQuestion` (`multiSelect` - a sitting over several is allowed) |
| nothing here, but other projects have waiting tickets | `-All`, report the count per project, ask which project to start with |
| nothing waiting anywhere | say so, with the status the asked-for id actually has |
| a ticket in another status | Quiz mode step 1 decides: `BlockNeedUserTest` needs a run (Sweep mode), `BlockExternal` needs the outside party, `BlockByOtherTask` clears on its blocker. Report it and mutate nothing |

More than five waiting tickets and no id given: take the first five in the list's order (the current project first,
then priority), say how many remain, and let the next sitting take them. Tickets that name each other as
prerequisites in their notes (`S0024` after `S0023`) go in that order, and a question two of them share is asked once.

## Step 2 - Work inside the ticket's project

The ticket tools resolve their project from where they run. For a ticket of another project than the current folder,
run every command of that project with `-WorkingDirectory`:

```powershell
pwsh -NoProfile -WorkingDirectory "<project root>" -File "<project root>/tools/harness.ps1" spec_catalog/select -Id <id> -Format json
```

`tools/harness.ps1` is the adopted forwarder every canon-adopting repository has; a project with its own
`scripts/spec_catalog/` names its entry points in its `CLAUDE.md`. Read the project's `CLAUDE.md` and the ticket's
spec before researching: the answers that need no question are in the project's own records and code.

`select` is the authority on the status. If it disagrees with the list, trust `select` and say so.

## Step 3 - The sitting, with the mechanics fixed

Follow Quiz mode steps 2-8. The parts a project-independent skill must pin down:

- **Research first.** The decision points are the reason note, every open research item and every unfilled owner
  input the note points at. What the ticket's own spec, the code, a contract in the catalog or a recorded decision
  settles is **not asked**: fill it in and list it as *resolved without asking*, with what settled it.
- **Ask with `AskUserQuestion`, in Russian** (chat language). A `header` of at most 12 characters, a specific
  question ending in `?`, 2-4 options, the researched recommendation **first** with `(Рекомендуется)` appended, and
  one line of consequence in each option's description. At most four questions per call, the most blocking first.
  With several tickets in one round, start each question with `<key>:<id>`. `multiSelect` only when the choices
  combine. A name, a number or an address that only the owner can supply: offer the researched candidates as options -
  the built-in *Other* takes the owner's own text. A recommendation is never applied in the owner's place.
- **After each round**, check the chosen options against the owner's standing rules (the project's `CLAUDE.md`
  "Owner decisions", the canon's hard invariants). Where one contradicts the choice, show the collision once with
  both outcomes and let the owner pick.
- **Write back before any status move**, with plain `Edit` on the spec file, in English (it is an artifact): the
  filled owner input, the research item marked resolved, and one dated block
  ```markdown
  ### Quiz decisions (YYYY-MM-DD)
  - <question> -> <chosen answer> (<one-line reason>)
  ```
  The owner's own typed text goes in verbatim, in its language, inside quotes. Section 0 (the owner's capture) and
  every unrelated section stay untouched. Do not edit the ledger or the `**Status:**` line by hand.
- **Restore one level** through the project's ticket tool, which also rewrites the spec's status line and clears the
  block's note:
  ```powershell
  pwsh -NoProfile -WorkingDirectory "<root>" -File "<root>/tools/harness.ps1" spec_catalog/update -Id <id> -Status <restored>
  ```
  A restore to `Approved` first passes the owner-inputs gate (`spec_catalog/check-owner-inputs -Id <id>`, exit 0); on
  exit 1 the residue it names is either one more round of questions or the ticket stays blocked with the note
  narrowed (step 7). The restored status is inferred from what exists (step 6); two equally plausible are one more
  question.
- **A skipped answer is never invented.** The input stays unfilled, the ticket stays in `BlockQuestions`, and the
  answers that did arrive are still written back.
- **`--dry`** composes the questions and prints them with their options and recommendations, then stops.
- **Read specs with a limit** (`Read` with `limit`); a long spec read whole is blocked by the plugin's read guard.

## Step 4 - Report, in Russian, one block per ticket

```text
<key>:<id> <slug>
  Было: BlockQuestions   Стало: <status>
  Спросил (<N>): <header> -> <ответ>
  Решил без вопроса (<M>): <решение> -> <значение> (<что решило>)
  Осталось: <ничего | что именно и почему блок остался>
```

Then run `quiz-list.ps1` once more for the same scope and give the count that is still waiting. Say plainly what the
move did to the queue: a restored ticket is eligible for `pq` again if its project is enabled and not on hold - and
that lifting a hold is the owner's call.

## What this skill never does

- Answer for the owner, or accept a default silently; invent an answer to a skipped question.
- Move a ticket that is not in `BlockQuestions`, or move one more than a single level.
- Write code, run a build or a test, commit, push, start `pq`, lift a hold, or register a project.
- Edit `spec-catalog.jsonl`, the queue files, or another project's files outside the tickets it was asked about.
- Continue into the restored ticket's pipeline: that is a separate, explicit request.
