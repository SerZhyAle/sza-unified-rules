# pq - the portfolio queue, operator's guide

`pq` works the owner's queue across every registered repository. It asks the rank for the first ticket, runs that
repository's own runner (`run-spec-queue.ps1`) on that one ticket, writes what happened to a log, and ranks again. With
nothing to do it waits a minute and looks again. Working by hand in any repository stays exactly as it is: a ticket a
manual session holds is never taken, and `pq` writes nothing inside a repository tree.

You steer it with **two plain text files**. Everything else is a button.

## The two files

| | The project queue | The ticket queue |
| --- | --- | --- |
| File | `PORTFOLIO_QUEUE.md` in the portfolio root | `PLAN/RELEASE_QUEUE.md` of each repository (its profile's `paths.releaseQueue`) |
| Decides | which project, or which exact ticket, goes next | which ticket of that project goes next |
| Open it | shortcut **PQ Projects**, or `pq queue` | shortcut **PQ Tickets `<key>`**, or `pq tickets <key>` |
| Who writes it | you order it; catalog writes refresh ticket rows, and `pq pin`, `pq hold` and `pq release` change your order | you move lines; the repository's plan tool adds a row for each new ticket and keeps status and time current, and never reorders |

Each catalog mutation reconciles the project's ticket queue and then its rows in the portfolio queue, including
when the last open ticket leaves it. `Implemented`, `Verified` and `BlockNeedUserTest` move to the local ready
file and leave the active portfolio queue; reopening returns them. Other status changes refresh the displayed
status. Central capture writes the same local ledger and queue. Existing order, comments and holds are preserved.
If a refresh fails, the catalog remains authoritative and the command reports the repair:
`pwsh -NoProfile -File tools/harness/portfolio/pq.ps1 sync -Path <repository>`. `pq sync` reconciles all registered
projects. Missing or unreadable local queues are left untouched; registration alone does not enable a worker.

Edit, save, and the next rank reads the new order: no restart, and a worker that is waiting picks it up in its next look.
`PQ Dry-run` prints the order the loop would take, launches nothing, and is the way to check an edit.

The first ticket is found like this: walk the project queue top to bottom; a row naming a repository asks that
repository's own ticket queue for its head, a row naming a ticket takes exactly that ticket; repositories the file does not
mention come after it, by the priority of their head ticket.

### The project queue

```
# comments and blank lines are yours and are kept
1                       # a package: a line of only digits; 1 is first
fms-a                   # a project: its own head ticket (a ticket queue decides which)
fms-web:S0028           # one named ticket, and nothing else of that project
2
tourist-mob:*           # the same as a bare key, spelled out
--                      # the unscheduled package: after every numbered one
epub-2-html

hold                    # nothing below this line is touched by a robot
fms-lite-docs
fms-web:S0030           # a held ticket is skipped, the project's next one is taken
```

| Element | Rule |
| --- | --- |
| package heading | a line of only digits, or `--`; the rows below it belong to it |
| `hold` heading | a line of only the word `hold`; every row below it is out of reach until the row is removed |
| row | `<key>`, `<key>:*` or `<key>:<id>`; the key is the one `pq list` prints; anything after the key is a comment |
| order | numbered packages ascending, then `--`, then repositories the file does not mention; inside a package, line order |
| a repository named only by `<key>:<id>` rows | offers those named tickets; synchronization adds every other locally queued ticket at the bottom |
| a repository the file does not mention | still worked when it is enabled, after everything the file lists; put it under `hold` to keep it out |
| a bad row | an unknown key or ticket is reported by `PQ Doctor` and skipped; it never stops the queue |

### The ticket queue

Each repository keeps its own order in its own file, the same shape in every repository:

```
current-next-release: 1

ticket                                                         changed         status
1
S0002_sandbox-two                                              26-10-28 10:20  Draft
S0001_pq-first-run                                             26-10-28 10:09  In Progress
--
S0003_sandbox-three                                            26-10-28 10:20  Draft
```

A bare number opens a package, `--` is work not yet scheduled, a row is the ticket. Inside a package the runner takes the
rows in line order. Moving a line is the whole edit; the status and time columns are kept current by the repository's tools.

### What to do with the two files

| You want | Edit |
| --- | --- |
| the projects in a set order, every ticket lined up by it | set the order with `pq rank` (or **▲ / ▼** in PQ Control Panel), then `pq arrange` (**Arrange**) |
| a project to go before another | move its line up in the project queue |
| a project paused | move its line under `hold` (`pq hold <key>`); `pq release <key>` takes it out again |
| one ticket done next, anywhere | `pq pin <key>:<id>`, or a `<key>:<id>` line at the top |
| exactly one ticket of a project and nothing else | put its other ticket rows under `hold` and do not add a bare project row |
| one ticket never taken | its `<key>:<id>` line under `hold` |
| the tickets of a project in another order | move their rows in that project's ticket queue (**PQ Tickets `<key>`**) |
| a ticket that must never run unattended | a one-way step (publication, release, store upload) belongs under `hold`, or in a project that is not enabled |

`pq release` only removes the row from under `hold`: it does not return it to its old package, and the project then
ranks as unlisted until you put its line back by hand.

### The project order and `pq arrange`

The priority of a project is its `rank` in the registry: lower goes first, equal ranks keep the order in which the
projects were registered.

```powershell
pq rank                                    # the project order, first to last
pq rank -Order streams-mob,fms-web         # these first, in this order, every other project after them
pq rank fms-web -Rank 15                   # one project's rank
pq arrange                                 # line PORTFOLIO_QUEUE.md up by that order
```

`-Order` writes ranks 10, 20, 30, .. for the whole list, so there is room to slot a project in later with `-Rank`.
`pq arrange` sorts the rows of every package (`1`, `2`, ..) by project order and keeps the order of each project's
own rows, as its ticket queue set them. Only row lines move, and only inside their own package: package headings,
comments and blank lines stay where they are, and the `--` package and everything under `hold` are not touched. A
ticket you want ahead of everything stays ahead when it sits in a package of its own above the rest (`1` for it,
`2` for the others). Changing the order does not rearrange the file by itself: run `pq arrange` when you want it.

## The shortcuts

`install-shortcuts.ps1` in this folder writes one shortcut per command, into the Desktop **and** into the root of the canon
working tree (the root copies are ignored by git). Each opens a PowerShell 7 window that stays open.

```powershell
pwsh -NoProfile -File tools/harness/portfolio/install-shortcuts.ps1            # create or refresh, Desktop and root
pwsh -NoProfile -File tools/harness/portfolio/install-shortcuts.ps1 -Where Desktop   # or -Where Root
pwsh -NoProfile -File tools/harness/portfolio/install-shortcuts.ps1 -DryRun    # show, write nothing
pwsh -NoProfile -File tools/harness/portfolio/install-shortcuts.ps1 -Remove    # take them off
```

Run it from the canon working tree, not from the plugin cache: the shortcuts point at the `pq.ps1` beside the script, and
the cache path changes with every plugin version. Run it again after a repository is registered or removed: it adds the
`PQ Tickets` shortcut of the new one and drops the one of a repository that is gone. A file of the same name that is not one
of ours is left alone.

| Shortcut | Runs | Use it to |
| --- | --- | --- |
| PQ Projects | `pq queue` | edit the order of the projects - file one |
| PQ Tickets `<key>` | `pq tickets <key>` | edit the order of that project's tickets - file two; one shortcut per registered repository |
| PQ Dry-run | `pq dry-run` | see the order the loop would take after your edit; launches nothing |
| PQ Start | `pq start` | run one worker; it waits when nothing is ranked |
| PQ Start 1 ticket | `pq start -MaxTickets 1` | do exactly one pass and stop - the attended first run |
| PQ Start Drain | `pq start -Drain` | work until nothing is ranked, then end |
| PQ Status | `pq status` | see workers, today's passes, the next ticket, whether `STOP` is set |
| PQ Log | `pq log -Last 60` | read the last 60 events across all writers |
| PQ Stop | `pq stop` | let every worker finish the pass it is on, then end |
| PQ Stop Kill | `pq stop -Kill` | end now: runner children are terminated and the ticket in flight is abandoned |
| PQ Doctor | `pq doctor` | check the enabled repositories and the queue file |
| PQ Repos | `pq list` | list the registered repositories |
| PQ Guide | - | open this file |

The same commands from a console: `pwsh -NoProfile -File tools/harness/portfolio/pq.ps1 <verb>`; `pq` is a script, not a
command on the path.

Several workers are several `PQ Start` windows (up to `maxWorkers` in the registry). Each takes the first free slot; a
repository is worked by one worker at a time unless its registration says `concurrent`.

## PQ Control Panel

`gui/` holds PQ Control Panel (`PQShell.exe`, .NET 8 WinForms), one window over the same commands. It reads the
portfolio root every 4 seconds (workers, the last passes, `STOP`, the projects and the top of the queue file) and
runs every change through `pq.ps1`, so it never writes a file of its own.

| Part | Does |
| --- | --- |
| Start / Stop / Force Kill | `pq start` in a terminal of its own, `pq stop`, `pq stop -Kill` |
| the project list | in project order; **▲ / ▼** move the selected project (`pq rank -Order ..`), **Arrange** runs `pq arrange` |
| Ticket / Project box | `pq pin`, `pq hold`, `pq release` on what it holds; a click on a project or a double-click on a worker or a pass fills it |
| Queue top | the first scheduled row of an enabled project nothing holds - the file's own answer; **Dry-Run** prints pq's exact plan |
| New Spec, Register, Doctor | `spec-draft.ps1`, `pq register`, `pq doctor -All` |

```powershell
pwsh -NoProfile -File tools/harness/portfolio/gui/build.ps1 publish -Configuration Release   # build and copy the exe
pwsh -NoProfile -File tools/harness/portfolio/gui/install-gui-shortcut.ps1                   # the desktop shortcut
```

The exe finds `pq.ps1` through `SZA_PQ_SCRIPT`, then beside itself or in a checkout above it, then at the canon working
tree's own path.

## Putting a task into a project's queue

The `spec-draft` skill (`/spec-draft`, or `spec-draft.ps1` in this folder) captures a task or a problem into any
registered project as a `Draft` ticket and then tells you, read only, what `pq` will do with it. A new ticket's
row goes to the **end of the current package** of that project's ticket queue (the file never reorders), so the
report gives its place in the project's own ranking: at position 38 it waits for 37 tickets, and `-Pin` (or
`pq pin <key>:<id>`) is the way to put it first. A project under `hold`, a project not enabled and a project not
registered are reported as they are; the script undoes none of them.

## One-time setup, per repository

A repository registers only if it has adopted the canon (a readable `.sza-canon.json`); to be worked it also needs a
profile, a ticket ledger and a runner, which `task-flow-init` sets up.

1. **Register** - one command, nothing else to edit:

   ```powershell
   pwsh -NoProfile -File tools/harness/portfolio/pq.ps1 register -Path <repository> -Enable -PermissionMode bypassPermissions
   ```

   The key defaults to the folder name (`-Key` overrides it). Without `-Enable` the repository joins disabled; without
   `-PermissionMode` it is refused unattended work until `permissionMode` is set, on its record or once at the top of
   `repos.json` for all. Valid values: `acceptEdits`, `auto`, `bypassPermissions`, `manual`, `dontAsk`, `plan`; the value is
   handed to the agent as `--permission-mode`, so choose it per repository, deliberately. `repos.json` in the portfolio root
   is the only file `register` writes; nothing is written in the repository. Day 0 of `task-flow-init` and `adopt-canon`
   ends in this command.
2. **Shortcuts** - run `install-shortcuts.ps1` again, so the repository gets its **PQ Tickets** shortcut.
3. **Check** - `PQ Doctor` should report PASS for the repository's stamp, profile and ledger. Run `r0 -DryRun` inside the
   repository and `PQ Dry-run`; both should name the ticket you expect first.
4. **Order** - `PQ Projects` (run `pq queue -Init` once to write the first file) and `PQ Tickets <key>`, as above.

## What a worker does

```
loop:  STOP file?  -> end
       new stamped repositories under the discovery roots?  -> join (at start, then every 10 minutes)
       dropped tickets that changed, blockers released?     -> offer them again
       rank        -> first candidate not excluded
       blocker in another repository not released?          -> exclude it, rank again
       agent       -> first of agentOrder that may take it
       repository lock -> worker slot -> run-spec-queue.ps1 -Ids <id> -MaxTickets 1 -Instance pq<k>   (waits for it)
       read the outcome -> runs.jsonl + events -> drop the ticket if its status did not move
empty: sleep up to pollSeconds (60) in short slices, rank again
```

- For Claude the model is not chosen by `pq`. The runner reads the ticket's `**Complexity:** <light|medium|hard> - <why>`
  line at every launch: `light` is haiku, `medium` sonnet, `hard` opus. A spec without the line keeps the runner's earlier
  routing. Every other agent always runs its own fixed model and effort (see Other agents).
- A pass that ends with the ticket's status unchanged, or in failure, drops that ticket, so the loop never spins on one
  ticket. The drop remembers the ticket's status, its `updated` time and its spec file's time as they were when the pass
  ended; when any of the three changes - you tested it and set `Broken`, answered its questions, edited its spec - the next
  turn offers it again (`ticket <key>:<id> changed (status) - offered again`). The pass's own writes never lift its drop.
- A usage-limit stop is not a failure: the runner records it and waits out its own hold before the next launch. For Claude
  the hold is per repository, so an account-wide limit is met once in each repository.
- A spec line `Blocker: <key>:<id>` (or `Блокер: <key>:<id>`) names a ticket of another registered repository. The ticket
  is not offered until that blocker is `Implemented`, `Verified` or `BlockNeedUserTest` with its tactical plan finished, or
  `Archived` - the rule the repository's own picker applies to a local blocker. A key that is not registered, a blocker id
  that is not in its ledger, or two tickets that block each other keep the ticket out, and the worker prints why
  (`ticket fms-web:S0040 waits on fms-a:S4470 (open: fms-a:S4470 is In Progress)`). Only `pq` reads the qualified form; the
  repository's own runner and a manual session ignore it, so such a ticket keeps its working status.
- `pq start -Drain` exits instead of waiting: 0 after at least one pass, 3 when nothing ran. `-MaxTickets N` ends the loop
  after N passes.
- A pass child does not inherit the starting agent's session variables, so `pq` may be started from an agent's shell as well
  as from a shortcut.

## New repositories join by themselves

Every worker looks one level under each discovery root - `discoveryRoots` in `repos.json`, else the folders that hold the
registered repositories (today `P:\ANDROID`, `P:\WEB`, `P:\WINDOWS`) - when it starts and every ten minutes after. A folder
with a canon stamp (`.sza-canon.json`) that is not registered joins when it is ready: the stamp reads, `.sza-profile.json`
exists, `validate.ps1` exits 0 and the runner's dry run exits 0. A ready repository is registered with its folder name as
its key, one worker and not concurrent, and the worker says so once:

```
new repository my-tool (P:\WINDOWS\My_Tool) joined the portfolio and is enabled: 4 open tickets, permission bypassPermissions
```

It is enabled only while `autoEnable` is on (the default) **and** `repos.json` names a `permissionMode` at the top level -
the one choice of how unattended agents may act, made once for every repository that joins. Without it the repository is
registered disabled and the line says why. A worktree of a registered repository is never registered a second time. A
stamped folder that is not ready is announced once per worker (`found .. - not joined: no .sza-profile.json ..`) and
nothing is written into it: run `task-flow-init` there, which ends in `pq register`. To keep a repository out, set its
`enabled` to `false` or put it under `hold`; to stop joining altogether, set `autoEnable` to `false`.

## Other agents

`agentOrder` in `repos.json` is the spend order, and Claude comes last: for each pass the worker takes the first agent that
is not held, is under its `maxParallel`, whose `levels` admit the ticket's level (a spec without a Complexity line counts
as `medium`) and that can reach the repository's pipeline. An agent without slash commands (`promptForm: file`) is told to
open the pipeline's command file - `.claude/commands/spec-all.md` for a repository whose prompt is `/spec-all {id}` - and
follow it; a repository whose prompt is plain text gets that text. A repository whose command file is missing is left to
the next agent. Every agent other than Claude always runs the `model` and `effort` written in its record, whatever the
ticket's level.

A record for Codex, beside the Claude record (once `agents` is present, Claude needs its own record too):

```json
"agentOrder": ["codex", "claude"],
"agents": [
  { "name": "codex", "command": "node",
    "argsTemplate": ["C:\\Users\\<you>\\AppData\\Roaming\\npm\\node_modules\\@openai\\codex\\bin\\codex.js", "exec",
                     "--model", "{model}", "-c", "model_reasoning_effort=\"{effort}\"",
                     "--dangerously-bypass-approvals-and-sandbox", "{prompt}"],
    "headlessMatch": "(?i)codex\\.js\"?\\s.*\\bexec\\b", "promptForm": "file",
    "model": "gpt-6.1-sol", "effort": "max", "maxParallel": 2, "limitPollMinutes": 30,
    "limitDetector": { "kind": "exitText", "pattern": "(?i)usage limit|rate limit", "status": "unproven" } },
  { "name": "claude", "command": "claude", "promptForm": "slash",
    "argsTemplate": ["-p", "{prompt}", "--permission-mode", "{permissionMode}", "--model", "{model}"],
    "modelByComplexity": { "light": "haiku", "medium": "sonnet", "hard": "opus" }, "maxParallel": 5 }
]
```

The command is `node` with Codex's own script, because the `codex` on PATH is a PowerShell shim a process cannot start
directly. The record is the whole launch: `{model}` and `{effort}` come from the record, `{prompt}` from the repository. A
pass of a non-Claude agent that fails fast - under two minutes, nothing moved - is taken as its usage limit: the agent is
held in `holds\<agent>.json`, the ticket is not dropped, the next pass gives it to the next agent, and after
`limitPollMinutes` one probe pass decides - a probe that does not fail fast clears the hold. Its limit text is never read,
so the detector stays `unproven`.

## Stopping

`PQ Stop` writes `STOP` in the portfolio root. Each worker checks it before every rank and in every sleep slice and ends after
the pass in progress. With `PQ Stop Kill` each worker kills the process tree of its own pass and nothing else - a local
runner's agent and a session of yours in any repository are never touched: the pass is journalled
as `killed`, the lease the pass made is released so the ticket is offered again at once, and its status stays where the agent
left it. Ctrl+C in a worker window ends that worker and its pass tree at once and releases the lease the same way; the
interrupted pass writes no `runs.jsonl` row (its `pass.launch` has no `pass.end`). Starting a worker with a `STOP` present
clears it and says so; if workers from the previous stop are still draining, the start exits 3 instead.

A repository's own queue stop works on the portfolio too. While its shared stop file (`temp/STOP-SPEC-QUEUE`, written by
its `rs` or by a release freeze) exists, `pq` takes no ticket there and `PQ Dry-run` prints `skip <key> - stopped`; it
starts again once that file is gone (the freeze lifts, or you delete it or start the repository's own runner).

## Where things are

The portfolio root is `SZA_PORTFOLIO_ROOT`, else `%USERPROFILE%\.sza\portfolio`. It is outside every repository and never in git.

| File | Holds |
| --- | --- |
| `PORTFOLIO_QUEUE.md` | file one: the owner's order; synchronization refreshes ticket rows, and `pin`, `hold`, `release` change their order or hold |
| `repos.json` | the registry: repositories, `enabled`, `permissionMode`, `maxWorkers`, `pollSeconds` |
| `STOP` | present while a stop is requested |
| `run\worker-<k>.json` | one live worker: pid, repository, ticket, agent, since |
| `holds\<agent>.json` | an agent other than Claude held after a fast failure; delete the file to give it work again at once |
| `run\repo-<key>.lock` | the repository a worker is in |
| `runs.jsonl` | one row per pass: run, pass, repository, ticket, status before and after, exit code, seconds, outcome |
| `log\events-<UTC day>.<writer>.jsonl` | every step as an event |

File two is `PLAN/RELEASE_QUEUE.md` inside each repository. The repository's own runner keeps its rows for these passes as
instance `pq<k>` (`runs-pq<k>.jsonl`), so they show up in the repository's monitor as one more instance.

## Reading the log

`PQ Status` is the first look. `PQ Log` shows events in timestamp order; narrow it in a console with `pq log -Repo <key>`,
`-Ev <name>` and `-Json`. The events a loop writes: `run.start`, `run.end`, `rank.result`, `pass.launch`, `pass.end`,
`pass.limit`, `wait.enter`, `wait.exit`, `run.stop`, `owner.action`, `ticket.dropped`, `ticket.dropLifted`,
`ticket.blocked`, `ticket.unblocked`, `xrepo.resolve`, `xrepo.cycle`, `agent.fallback`, `agent.hold`, `agent.unproven`,
`agent.resume`, `dispatch.skip`, `repo.discovered`, `repo.notready`, `repo.ready`, `repo.enabled`. No line carries prompt
text, environment values or keys.

## When it does not do what you expect

| You see | Meaning and fix |
| --- | --- |
| `RegistryMissing` | nothing registered yet - `pq register -Path <repository>` |
| `StampMissing` on register | the repository has not adopted the canon - run `adopt-canon` there first |
| `start` waits and `Next: none` | no enabled repository offers a ticket: `PQ Dry-run`, then check `enabled`, a `hold` section in either file, and that the ticket is not leased by a manual session |
| the order is not what the file says | `PQ Dry-run` prints the rule behind each pick and `PQ Doctor` lists bad rows; a repository named only by `<key>:<id>` rows offers just those tickets |
| a ticket is passed over | it did not move last time and stays dropped until its status, `updated` or spec file changes; or another worker holds the repository; or its `Blocker: <key>:<id>` is not released (the worker printed `waits on`) |
| an agent gets no work | it is held after a fast failure (`holds\<agent>.json`, probed again after `limitPollMinutes`), at its `maxParallel`, its `levels` exclude the ticket, or the repository has no command file for it |
| a new repository did not join | the worker printed `not joined: <why>` once; fix that and the next scan, within ten minutes, picks it up. Registered but disabled: set a top-level `permissionMode` in `repos.json` |
| `start` exits 3 at once | a previous `STOP` is still draining live workers - wait for them to leave |
| refuses unattended work | the repository has no `permissionMode` - register it again with `-PermissionMode`, or set it in `repos.json` |
| `TicketQueueMissing` from `pq tickets` | there is no ticket queue file at the path the message prints; restore it, or point the profile's `paths.releaseQueue` at the right file |
| a worker window was closed by force | its state files stay; the next start reclaims files whose process is gone. If only the worker process ended and its runner ran on, the repository stays `occupied` until that pass ends |
| `skip <key> - stopped` | that repository's own queue stop file exists (its `rs`, or a release freeze) - see Stopping |

## A first test in throwaway repositories

Before pointing `pq` at a product, run it over repositories that exist only for the test. A repository gets the runner's own
prompt (`/spec-all` and the like) only if it has the command, so a scaffolded throwaway repository, whose profile carries a
self-contained prompt, is the cleanest bench. Two benches show both files at work: the project queue needs two projects, the
ticket queue needs two tickets in one of them.

1. New folder, `git init`, a `.sza-canon.json` copied from `templates/.sza-canon.json` and filled (or `adopt-canon`), then
   `tools/harness/scaffold/init-task-flow.ps1 -Root <folder> -PermissionMode bypassPermissions`.
2. Tickets: `capture-draft.ps1 -Slug <slug> -TextFile <file> -Complexity "light - <why>"`, each a task that needs no
   research and no question (for example, create one text file holding one line). `validate.ps1` must exit 0.
3. `pq register -Path <folder> -Enable -PermissionMode bypassPermissions`, then `pq queue -Init` once; run
   `install-shortcuts.ps1` again.
4. `PQ Doctor` reports 0 FAIL. Edit both files and watch `PQ Dry-run` follow them: swap two project lines, move a ticket row,
   put a `<key>:<id>` row on top, put a project under `hold`. The pass itself can be previewed without an agent:
   `run-spec-queue.ps1 -RepoRoot <folder> -Ids <id> -MaxTickets 1 -ModelPolicy shape -Instance pq1 -PermissionMode
   bypassPermissions -DryRun` (with `SZA_PROJECT_ROOT` set to the folder) prints the model the Complexity line picks.
5. `PQ Start 1 ticket`. One pass runs and the window stays open. Then `PQ Status` and `PQ Log`.

What a good pass leaves behind: the ticket's status moved (it may land on a `Block*` status with a note, which is also
a move); one new row in the portfolio's `runs.jsonl`; `pass.launch` and `pass.end` events in `PQ Log`; and a row in the
repository's own `temp/spec-queue/runs-pq1.jsonl`. The three records must agree on ticket and outcome. A ticket that did not
move is excluded for the rest of that run and the log says so.

## Not in this version

A machine-wide usage-limit hold for Claude, a console with stop levels, metrics and analysis, and day 0 written into a
repository that joins are not part of `pq`. It is a loop, a rank, a few agents and a log.

## Checking the tool itself

`pwsh -NoProfile -File tools/tests/smoke-portfolio-runner.ps1` from the canon root runs the loop over throwaway
repositories with a fake runner; it starts no agent. It also covers the shortcuts and `pq tickets`.
`pwsh -NoProfile -File tools/tests/portfolio-queue.tests.ps1` covers the registry, the project queue file, the picker and the
rank, case by case.
