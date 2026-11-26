---
name: spec-quiz
description: 'Clear BlockQuestions: apply researched recommendations, ask the owner the rest, record and restore status. /spec-quiz, /sq, quiz S0021, unblock the tickets, answer the open questions, what is waiting for my answers, «разблокируй тикеты», «задай мне вопросы по тикету», «вопросы по спеке», «что ждёт моих ответов», «квиз», «сними блок вопросов».'
---

# Spec quiz - drain the owner's questions in any project

A ticket enters `BlockQuestions` in one line and waits for an owner who is ready to answer. This skill is how it
leaves, in **any** registered project: it resolves which tickets are waiting, then runs the canon's procedure -
[Quiz mode](../spec-to-audit/references/quiz-mode.md) of the spec-to-audit skill, steps 1-8, which is the authority and
is **not restated here**; read that file before the first question. What this skill adds is the part that is the same
in every project: finding the tickets, naming the right project, and the mechanics of asking, writing back and moving.

`/sq` is the same command, through the project's forwarder in `.claude/commands/`; the arguments are the same.

## Usage

```text
/spec-quiz                    every ticket in BlockQuestions in the project of the current folder
/spec-quiz S0021              that ticket: looked up by id here first, then in the other projects
/spec-quiz fms-web:S0021      one ticket of a registered project, from any folder
/spec-quiz S0023, 24, 25      one sitting over several tickets (a bare number is the id's trailing digits)
/spec-quiz fms-web            every waiting ticket of that project
/spec-quiz --all              every waiting ticket of every registered project, held or not, in registry rank order - one sitting
/spec-quiz S0021 --dry        what would be applied and what asked; nothing asked, nothing written, nothing moved
/spec-quiz S0021 --assumed    the sitting plus the ticket's `### Assumed (unattended|attended, <date>)` entries and earlier
                              `applied by recommendation` decisions, listed for review and overrule
```

`--all` is the portfolio sitting, started from any folder - the `PQ Answer questions` shortcut and the PQShell button
`Answer questions (N)` open a terminal in the canon checkout running `claude "/sza:spec-quiz --all"`.

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

Each waiting ticket prints as `BQ <key>:<id> p<priority> <updated> <name>`, its spec file, the ledger's reason
note and the state of its question block (`block: current ... | stale - ... | answered ... | none - ...`,
TASK-FLOW rule 7). A `shared: <Q|DO> <text> [<key>:<id>, ..]` line names an open question or owner action that two
or more listed tickets carry in the same words, ticket ids aside; the last line is the count (or, with `-Id`,
`here=<key>:<id>=<status>` and `blockquestions=<list>`). `-Json` gives the same records with the full note, the
block's questions and each record's `shared` items. `-All` lists the projects in registry rank order (the
dispatcher's order, the panel's #), then priority; every other scope puts the current folder's project first.

| Outcome | Do |
| --- | --- |
| the tickets asked for are waiting | go to Step 2 |
| `-Id` and `here=` is `BlockQuestions` | quiz that one; name the other projects' tickets with the same id once, as different tickets, and leave them |
| `-Id` and `here=` is any other status or `absent`, and `blockquestions=` lists others | do not guess. Say in one line that the id here is `<status>` and not waiting, list the waiting ones with their names, and ask which, with `AskUserQuestion` (`multiSelect` - a sitting over several is allowed) |
| nothing here, but other projects have waiting tickets | `-All`, report the count per project, and sit over them as `--all` does - no "which project" question |
| nothing waiting anywhere | say so, with the status the asked-for id actually has |
| a ticket in another status | Quiz mode step 1 decides: `BlockNeedUserTest` needs a run (Sweep mode), `BlockExternal` needs the outside party, `BlockByOtherTask` clears on its blocker (the blocker's status move frees it, TASK-FLOW rule 69; when the owner's answer drops the dependency, remove the `Blocker:` token and run `block-links.ps1 -Check -Id <id>`). Report it and mutate nothing else |

There is no ticket cap: the sitting takes every listed ticket in the list's order, and an owner who stops early
leaves the rest waiting, untouched (Quiz mode step 7). Tickets that name each other as prerequisites in their notes
(`S0024` after `S0023`) go in that order.

**A shared decision or owner action is settled once.** Every `shared:` line is one item. Before the first round,
compare the rest of the decision points too: two or more tickets - in one project or in several - hold one item
when they need the same decision (the same subject, the same options, as cyrflip's GitHub topics in S0024 and
S0058) or ask the owner for the same act in the same place (one console sign-in, one device walk), although each
words it with its own names. Apply or ask it once, name every ticket it settles (`cyrflip:S0024, cyrflip:S0058`)
and what is each one's own part, and write the result into each of them before any of them moves; a ticket whose
own part the result does not cover stays open. A sitting narrower than `--all` also runs the list with `-All`: a
waiting ticket outside the scope that carries one of the sitting's items gets that result written into it, and
nothing else of it is settled. Decisions that only look alike - different subjects, different option sets, or
recommendations that point different ways - are kept apart; never merge them silently.

## Step 2 - Work inside the ticket's project

The ticket tools resolve their project from where they run: the harness walks up from the working folder to
`.sza-profile.json`. So every ticket command is the plugin's own script, run with `-WorkingDirectory` set to the
ticket's project - the same call for the current project and for another one, and for a project that has no
`tools/harness.ps1` forwarder (most do not):

```powershell
pwsh -NoProfile -WorkingDirectory "<project root>" -File "<root>/tools/harness/spec_catalog/select.ps1" -Id <id> -Format json
```

A project with its own `scripts/spec_catalog/` (FastMediaSorter_mob_v2) names its entry points in its `CLAUDE.md`; use
those with the same arguments. Read the project's `CLAUDE.md` and the ticket's spec before researching: the answers that need no question
are in the project's own records and code.

`select` is the authority on the status. If it disagrees with the list, trust `select` and say so.

## Step 3 - The sitting, with the mechanics fixed

Follow Quiz mode steps 2-8. The parts a project-independent skill must pin down:

- **Read the question block first.** A pass that parked the ticket wrote its researched questions into the spec
  file as a `### Questions (v1, <date>)` block (TASK-FLOW rule 7, S0026); the `block:` line of Step 1 already
  says what the list's reader found. **Current** - the newest block, not stamped ` - answered <date>`, dated no
  earlier than the day the ticket entered the status and carrying every `Q:` of the note - asks from the block:
  its questions, options, consequences and recommendations are the ticket's decision points as they stand, no
  re-research, and a `DO:` line in the block is presented instead of composed. **Stale, answered, none or another
  version**: research (next bullet) exactly as before 0.23 and leave the old block where it stands - neither it
  nor any other part of the ticket is edited on the way in.
- **Research first.** The decision points are the reason note (`Q: ..?` questions and `DO: <action>` pre-implementation owner actions), every open research item and every unfilled owner input (including `- **DO:** <action>` lines under `### 3.3 Owner inputs (Approval gate)`) the note points at. What the ticket's own spec, the code, a contract in the catalog or a recorded decision settles is **not asked**: fill it in and list it as *resolved without asking*, with what settled it.
- **`--assumed` lists what was taken without a question.** With the flag, each ticket in scope has its
  `### Assumed (unattended, <date>)` and `### Assumed (attended, <date>)` blocks and its earlier
  `applied by recommendation` decision lines read out of the spec file and printed: date, decision, what was taken,
  the alternative (Quiz mode step 2). Without the flag they are not raised.
- **Apply the recommendation first.** Every question that has a recommended answer is applied, not asked, unless
  [AI_USAGE.md](../../rules/AI_USAGE.md) section 1 keeps it a question: a one-way or outward step, money, a fact
  only the owner has, a break of a hard invariant or of a recorded owner decision (the project's `CLAUDE.md`
  "Owner decisions" included), or a shared-contract amendment outside a consolidation round. Print one table before
  the first status move, headed **applied by recommendation**: `<key>:<id>`, question, applied answer, alternative,
  consequence. No confirmation is asked about it.
- **Overrule.** The owner may overrule an applied or assumed entry at any time - in the sitting, in chat later, or
  through `--assumed`: the entry is marked `overruled <date>: <the owner's answer in quotes>` in place, the owner's
  value is written into the owner input or research item it settled, and where a pass already built on it - the
  ticket at `Implemented` or beyond - the rework is captured with the project's capture tool and reported as
  `parked: <id>`. Unoverruled entries stay as they are.
- **Ask what is left with `AskUserQuestion`, in Russian** (chat language): a question with no recommendation, one
  that section 1 keeps a question, and every `DO:` action. A `header` of at most 12 characters, a specific question
  ending in `?`, 2-4 options, one line of consequence in each option's description, and a recommendation, where
  there is one, **first** with `(Рекомендуется)` appended. For a pre-implementation `- **DO:** <action>` line
  (device, desk, or outside console account action that precedes implementation, S0042), show the `DO:` line to the
  owner and take the result (done + observed value/output, or fallback/skip) as the owner input. At most four
  questions per call, the most blocking first. In a sitting over several tickets or projects (`--all` always),
  start every question and every table row with `<key>:<id>` - every ticket it settles, for a shared item.
  `multiSelect` only when the choices combine. A name, a number or an address that only the owner can supply: offer
  the researched candidates as options - the built-in *Other* takes the owner's own text.
- **After each round**, check the chosen options against the owner's standing rules (the project's `CLAUDE.md`
  "Owner decisions", the canon's hard invariants). Where one contradicts the choice, show the collision once with
  both outcomes and let the owner pick.
- **Write back before any status move**, with plain `Edit` on the spec file, in English (it is an artifact): the
  filled owner input, the research item marked resolved, and one dated block
  ```markdown
  ### Quiz decisions (YYYY-MM-DD)
  - <question> -> <chosen answer> (<one-line reason>)
  - <question> -> <recommended answer> (applied by recommendation: <reason>; alternative: <other>; owner may overrule)
  ```
  The owner's own typed text goes in verbatim, in its language, inside quotes; an applied line is never written as
  the owner's answer and quotes nobody. A question block the sitting settled from is stamped by appending
  ` - answered <date>` to its heading once all its items are settled, whoever settled each. If the sitting had no
  current question block, write a new block for the questions settled and stamp it the same way. Keep earlier
  blocks and their lines. Mark each settled owner-input action with
  ` - done <yyyy-MM-dd>` or ` - dropped <yyyy-MM-dd>`, optionally followed by `: <result or reason>`
  (TASK-FLOW rule 7). Section 0 (the owner's capture) and
  every unrelated section stay untouched. Do not edit the ledger or the `**Status:**` line by hand.
- **Restore one level** through the project's ticket tool, which also rewrites the spec's status line and clears the
  block's note:
  ```powershell
  pwsh -NoProfile -WorkingDirectory "<project root>" -File "<root>/tools/harness/spec_catalog/update.ps1" -Id <id> -Status <restored>
  ```
  The status writer refuses the restore while it finds an unanswered `Q:` or an unmarked `DO:`.
  A restore to `Approved` also passes the owner-inputs gate (`check-owner-inputs.ps1 -Id <id>`, exit 0); on
  exit 1 the residue it names is either one more round of questions or the ticket stays blocked with the note
  narrowed (step 7). The restored status is inferred from what exists (step 6); two equally plausible are one more
  question.
- **A skipped answer is never invented.** The input stays unfilled, the ticket stays in `BlockQuestions`, and the
  answers that did arrive are still written back.
- **`--dry`** prints what would be applied and what would be asked, with options and recommendations, then stops.
- **Read specs with a limit** (`Read` with `limit`); a long spec read whole is blocked by the plugin's read guard.

## Step 4 - Report, in Russian, one block per ticket

```text
<key>:<id> <slug>
  Было: BlockQuestions   Стало: <status>
  Спросил (<N>): <header> -> <ответ>
  Applied by recommendation (<A>): <вопрос> -> <ответ> (альтернатива: <другой вариант>; можно отменить)
  Решил без вопроса (<M>): <решение> -> <значение> (<что решило>)
  Допущения (<K>): <решение> -> <принято | отменено владельцем> (<дата>)   [только с --assumed]
  Осталось: <ничего | что именно и почему блок остался>
```

Keep the label `applied by recommendation` as written, so it can be searched for. Then run `quiz-list.ps1` once more for the same scope and give the count that is still waiting. Say plainly what the
move did to the queue: a restored ticket is eligible for `pq` again if its project is enabled and not on hold - and
that lifting a hold is the owner's call.

## What this skill never does

- Write an applied recommendation as the owner's answer, apply one that AI_USAGE section 1 keeps a question, or
  invent an answer to a skipped question. A pass records its reversible recommendations under `### Assumed`
  (S0039); this skill lists them on request and changes one only on the owner's word.
- Move a ticket that is not in `BlockQuestions`, or move one more than a single level.
- Write code, run a build or a test, commit, push, start `pq`, lift a hold, or register a project.
- Edit `spec-catalog.jsonl`, the queue files, or another project's files outside the tickets it was asked about and
  the tickets a shared item names.
- Continue into the restored ticket's pipeline: that is a separate, explicit request.
