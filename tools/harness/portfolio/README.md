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

The first ticket is found like this: walk the projects by their `rank` in the registry, the lowest first (the `#` column of
PQ Control Panel); for each project take its rows of the project queue in package and line order - a row naming a repository
asks that repository's own ticket queue for its head, a row naming a ticket takes exactly that ticket - or, when the file
does not mention the project, its own head. No package outranks another project.

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
| `hold` heading | a line of only the word `hold`; every row below it is out of reach of every robot until the row is removed; only `pq start -Ticket <key>:<id>` of that exact ticket (or of a ticket of a held project) passes it, and removes nothing |
| row | `<key>`, `<key>:*` or `<key>:<id>`; the key is the one `pq list` prints; anything after the key is a comment |
| order | projects by registry `rank`; inside one project, numbered packages ascending, then `--`; inside a package, line order |
| a repository named only by `<key>:<id>` rows | offers those named tickets; synchronization adds every other locally queued ticket right after that project's last row |
| a repository the file does not mention | still worked when it is enabled, at its place by `rank`, from its own head; put it under `hold` to keep it out |
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
| the projects in a set order | set the order with `pq rank` (or **▲ / ▼** in PQ Control Panel); the runner follows it at its next rank, `pq arrange` (**Arrange**, also run by **Open Portfolio Queue**) only lines the file up for reading |
| a project to go before another | move it up with `pq rank` or **▲** |
| a project paused | move its line under `hold` (`pq hold <key>`); `pq release <key>` takes it out again |
| one ticket done next in its project | `pq pin <key>:<id>`, or a `<key>:<id>` line at the top of that project's rows; to make it next in the whole portfolio, its project must also be first in the project order |
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
`pq arrange` rewrites everything above `hold` in the order of work: one package `1`, then the projects in the order
of the panel, each project's rows together in the order the runner takes them (its packages ascending, then `--`,
then line order), a blank line between two projects. Comment-only lines follow the rows; the lines above the first
package and everything under `hold` are not touched. The runner's order is the same before and after: the order
between projects is the `rank`, never the position of a line, and the order inside a project is kept. `pq queue`
(**Open Portfolio Queue**) arranges the file every time it opens it, and the sync adds a new ticket right after the
last row of its project, so the file and the project list read the same; after **▲ / ▼** press **Arrange** or open
the file again.

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
| PQ Status | `pq status` | see workers, today's (local-day) passes, what waits for you, whether `STOP` is set; `pq status -Next` also runs the rank and prints the next ticket |
| PQ Log | `pq log -Last 60` | read the last 60 events across all writers |
| PQ Stop | `pq stop` | let every worker finish the pass it is on, then end |
| PQ Stop Kill | `pq stop -Kill` | end now: runner children are terminated and the ticket in flight is abandoned |
| PQ Pause | `pq pause` | no worker launches a new pass until PQ Resume |
| PQ Resume | `pq resume` | undo PQ Pause |
| PQ Report | `pq report` | the last seven days in numbers, with the open findings |
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
| Start / Stop / Force Kill | `pq start` in a terminal of its own, `pq stop`, `pq stop -Kill`; Stop and Force Kill run at once, also while another command of the panel is still running, and Force Kill always asks first |
| Pause / Resume / Report / Problems | `pq pause`, `pq resume`, `pq report -Days 1`, `pq problems`, the output in the console; they run at once as Stop does |
| the project list (**Projects** tab) | in project order; **▲ / ▼** move the selected project (`pq rank -Order ..`), **Arrange** runs `pq arrange` |
| Ask / Test / Outside / Chain / Unbuilt | per project, what waits for you, from `pq inbox -Json` (read on start, by Refresh and every minute): your answers (`BlockQuestions`), your manual test (`BlockNeedUserTest`), someone outside (`BlockExternal`), another ticket (`BlockByOtherTask`, counted in the project the waiting ticket belongs to, whatever project its blocker is in), the audit (`Implemented`); a click lists the tickets in the console with what clears them; `?` means the count is unknown and the tooltip says why |
| Session | a terminal in the project folder running `claude` - an interactive session with the project's own commands and hooks, no VS Code window |
| **Queue** tab | the ticket rows of `PORTFOLIO_QUEUE.md` in the order the runner reads them, held rows last |
| Ticket / Project box | `pq pin`, `pq hold`, `pq release` on what it holds; a click on a project or a double-click on a worker, a pass or a Queue row fills it |
| double-click on a worker, a pass or a Queue row | also opens that ticket's spec, the file its project's ledger names for exactly that id; a row without a ticket opens nothing |
| Queue top | the first scheduled row of an enabled project nothing holds - the file's own answer; **Dry-Run** prints pq's exact plan |
| New Spec, Register, Doctor | `spec-draft.ps1`, `pq register`, `pq doctor -All` |
| Providers | which model providers spend tokens and in what order (`pq agents`, see Model providers below); the window title shows the order, with a provider marked while its usage limit is spent |

```powershell
pwsh -NoProfile -File tools/harness/portfolio/gui/build.ps1 publish -Configuration Release   # build and copy the exe
pwsh -NoProfile -File tools/harness/portfolio/gui/install-gui-shortcut.ps1                   # the desktop shortcut
```

The exe finds `pq.ps1` through `SZA_PQ_SCRIPT`, then beside itself or in a checkout above it, then at the canon working
tree's own path.

## Answering a project's questions

A ticket that needs the owner's call leaves the queue as `BlockQuestions`, and `pq` never takes it back by itself.
The `spec-quiz` skill (`/spec-quiz` or `/sq`, with `quiz-list.ps1` in this folder) is the exit: it lists the waiting
tickets of the current project, of a named one (`<key>:<id>`) or of all (`--all`), asks only the decisions the code and
the records do not settle, writes the answers into each ticket and restores it one level - after which `pq` offers it
again, unless its project is on hold. `quiz-list.ps1 -Id S0021` is the lookup for an id that exists in several
projects: it prints the id's status in the current project and every project where it waits. The script reads only.

`pq inbox` is the one read-only list over all projects of everything that waits for you alone: one line per kind -
questions (`BlockQuestions`), tests (`BlockNeedUserTest`), outside (`BlockExternal`), chain (`BlockByOtherTask`),
unbuilt (`Implemented`) - with the count, the oldest age and the command that clears the kind, then the tickets with
id, age and note. A chain ticket prints as its chain root (`fms-web:S0021 (held, owner decision) frees 8`), walking
the `Blocker:` tokens with the same release test the picker uses. A local token counts only when its id matches the
project's `grammar.ticketIdPattern` (default `^S\d{4}$`); other words are prose. `-Json` gives the same records to the GUI.
`quiz-list.ps1 -Status <name[,name]>` lists any other statuses through the same reader (default `BlockQuestions`).
`pq status` ends with the same five counts and points at `pq inbox`.

The phone inbox listener files incoming packets as Draft tickets. `install-inbox-watcher.ps1` registers the
listener and a separate drain every 10 minutes; `drain-inbox.ps1` also runs manually. Each drain ingests
pending packets, then calls `pq start -Ticket <key>:<id>` for at most three filed tickets, oldest first.
The dispatcher retains its normal locks, leases, stops and registry gates; a named start passes queue hold
lines only for that ticket. Packets without a known project wait for the owner. `-MaxTickets` changes the
cap and `-FileOnly` records the tickets for the regular queue instead. The cursor beside the spool prevents
repeat starts, and `result.json` records each outcome; an interrupted start is not repeated automatically.
`pq status` shows new packets, filed tickets waiting for the drain and their oldest age.

## Remote delivery - build-deliver

After a pass changed a project, `build-deliver.ps1` (S0048) builds a fresh version and puts it where the owner
can test it from the phone: the synced Drive folder `C:\GD	c\SZA\_APP` (the `SZA_DELIVERY_ROOT` variable or
`-DeliveryRoot` overrides it). No new channel: the Drive sync is the transport, the Store is never touched.

```
<root>\<key>\<version>pp.exe          the artifact, delivered
<root>\<key>\<version>pp.exe.sha256   "<hash>  <name>" (the GitHub sidecar shape)
<root>\<key>\LATEST                     names the newest delivered version; the phone/WEB side reads it
```

```powershell
pwsh -NoProfile -File tools/harness/portfolio/build-deliver.ps1 -Project oneclickrunner                 # build + deliver
pwsh -NoProfile -File tools/harness/portfolio/build-deliver.ps1 -Project oneclickrunner -Json -Ticket S0123
```

- **The build command is discovered, never hardcoded**: `-BuildCommand`, else the project's optional profile
  member `delivery.buildCommand`, else the repository root's `build.ps1`. A repo's `release.ps1` and its
  `STORE_PUBLISHING.md` / `DEV/RELEASE.md` runbooks are probed and reported by the store staging plan, never
  auto-invoked - a release is the owner's own paid path. Optional `delivery` members:
  `buildCommand` (a command line relative to the repo), `versionCommand` (prints the version as its last
  line), `artifactPatterns` (glob patterns relative to the repo; without them the fresh
  exe/apk/msix/aab/msi/zip/appx under the repo is found by write time).
- **The version is read, not guessed**: `-Version`, else `versionCommand`, else the stamp the build put into
  the artifact (`FileVersion`), else the newest tag matching the stamp's `versionShape.tagRegex`. A build
  whose version does not resolve is refused (exit 4).
- **The build runs under the `resources/build` token** (rule 62) with the ticket id (else `build-deliver`), so
  it never races a PQ pass building the same repository; a busy token is waited out (`-TokenWaitSeconds`).
- Exit codes: 0 delivered (or built, with `-BuildOnly`), 2 a bad invocation (unknown project, no build
  command, conflicting switches), 3 the build failed or the token never freed, 4 the version did not resolve.
- One `build.delivered` event per delivery (EVENTS.md 3.9); with `-Ticket` the delivery is also a note on that
  ticket's ledger row, written through the project's own `update.ps1`. `-DeliverOnly -Artifact <file>` delivers
  an already-built artifact; `pq status` ends with a `delivered: <key> <version> (age)` line per project.
- The drain builds too: `drain-inbox.ps1 -After <key>:<id>` builds that ticket's project once its pass ran and
  its status reached `Implemented`/`BlockNeedUserTest`, and a packet whose text asked for a build ("собери",
  the ingest notes it in the ticket) is built the same way automatically. Each build decision lands in the
  packet's `result.json` as `builds` (additive): `delivered` with the version, `refused`/`not-built` with the
  reason, `deferred` to the next drain.

**Publishing to the Microsoft Store is different, and stays one-way.** A packet phrased "опубликуй ... in MS
Store" is recognized at ingest (`publishIntent: "ms-store"|"github"|"winget"` in `result.json`, a note in the
drafted ticket) - the agent then works it with the `store-publish` skill.
`stage-store-publish.ps1 -Project <key> [-Ticket <id> -SetStatus]` stages everything an agent can do: the
unsigned MSIX through the repo's own `msix/build-msix.ps1` with the reserved identity passed only where that
script accepts it, the packed `<Identity>` read back and asserted against the frozen anchors
(`CN=F98ACEDB-...` / `SZA`), the WACK verdict read from a staged report, the listing export-merge step
named - and then it STOPS: the Partner Center upload is the [PUBLIC] one-way manual step (the `msstore` CLI
needs a service principal an individual MSA does not have), so the report spells the click path, records
`uploaded: false` and, with `-SetStatus`, moves the ticket to `BlockExternal` through the project's own
tooling. No code path in the canon ever performs the store upload automatically.

## Putting a task into a project's queue

The `spec-draft` skill (`/spec-draft`, or `spec-draft.ps1` in this folder) captures a task or a problem into any
registered project as a `Draft` ticket and then tells you, read only, what `pq` will do with it. A new ticket's
row goes to the **end of the current package** of that project's ticket queue (the file never reorders), so the
report gives its place in the project's own ranking: at position 38 it waits for 37 tickets, and `-Pin` (or
`pq pin <key>:<id>`) is the way to put it first. An urgent blocker (a `hotfix-` slug, **Urgent Blocker** in the
New Spec dialog) is pinned by itself, so `pq` works it before everything else; `-NoPin` is the way out. A project under `hold`, a project not enabled and a project not
registered are reported as they are; the script undoes none of them.

A project with no task flow (no `.sza-profile.json`) is captured into too, as a plain `PLAN/<id>_<slug>.md` numbered
the way that project already numbers its tickets; no profile, ledger or queue row is written, and the report says
`pq=no-task-flow`, because `pq` cannot work a ticket that has no ledger.

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
loop:  stop files? -> end (see Stopping); paused? -> wait; end time (-Until) reached? -> end
       new stamped repositories under the discovery roots?  -> join (at start, then every 10 minutes)
       dropped tickets that changed, blockers released?     -> offer them again
       rank        -> first candidate not excluded
       blocker in another repository not released?          -> exclude it, rank again
       the owner in any repository (transcripts, all read before the rank)?  -> mark them, one walk goes past all of them
       the owner in the one the rank returned (a lease)?    -> mark it, rank again
       agent       -> first of agentOrder that may take it
       the build / emulator resource the ticket's Verify: level needs is taken?  -> skip it for a minute, rank again
       repository lock -> worker slot -> run-spec-queue.ps1 -Ids <id> -MaxTickets 1 -Instance pq<k>   (waits for it)
       read the outcome -> runs.jsonl + events -> drop the ticket if its status did not move
empty: wait, see Waiting
```

- **The robot yields to you.** In a repository that is not `concurrent`, a pass is not started while a session of yours is
  live there: a Claude Code transcript of that repository written within `occupiedMinutes` (registry, 3 minutes here; the
  shipped default is 10) that is not one of `pq`'s own passes, or a live ticket lease whose holder is not a `pq` pass. The
  worker prints `repository <key> is occupied (transcript, 55 s ago) - the robot waits for the owner`, takes the next
  repository of the rank, and prints `is free again` when it offers a ticket there and the owner has gone. The transcripts
  of every enabled repository are read before each rank (a directory listing and a 1 KB read each, no child process), so
  one walk of the rank goes past all of them; a repository stays marked until its window can have run out - a transcript
  only gets younger, so looking sooner cannot find it free - and never for less than half a minute. A pass already running
  is never interrupted when you arrive. The passes' own sessions are told apart by the session id the pass runs under,
  kept in `run\pass-sessions.json`. Not seen: an agent that writes no Claude transcript (Codex, Gemini), and a build or
  code lock whose holder has neither a transcript nor a lease.
- **Shared resources.** A ticket's `**Verify:** <level> - <why>` line names what proves it: `edit` takes nothing, `build`
  one `build` token, `emulator` a `build` and the `emulator` token, `device` is never given to a robot (the hardware is
  yours). No line, or a word outside the four, is `build`. The caps are `resources.build` (3) and `resources.emulator`
  (1) in the registry; a token is a file `resources\<token>\<key>__<id>.json` of the dispatcher that holds it, and one
  whose process is gone is cleared. A ticket that cannot get its token is skipped for a minute.
- **`concurrent` and `fill`.** A `concurrent` repository takes at most its `maxWorkers` workers at once. With `fill`
  `breadth` in the registry, a repository that already has a worker waits for the projects that have none; `depth` (the
  default) lets the project at the top take every worker it may have first.
- **Robot-filed tickets.** A ticket that is new in a repository after a pass is one the pass filed. The first
  `robotDraftCap` of them (20, per repository per run) are worked like any other; each one beyond is kept out of the rank,
  and a console line tells you (`pq report` counts them, and `PQ-SAFE02` appears in `pq problems`).

- For Claude the model is not chosen by `pq`. The runner reads the ticket's `**Complexity:** <light|medium|hard> - <why>`
  line at every launch: `light` is haiku, `medium` sonnet, `hard` opus. A spec without the line keeps the runner's earlier
  routing. Every other agent always runs its own fixed model and effort (see Other agents).
- A pass that ends with the ticket's status unchanged, or in failure, drops that ticket, so the loop never spins on one
  ticket. The drop remembers the ticket's status, its `updated` time and its spec file's time as they were when the pass
  ended; when any of the three changes - you tested it and set `Broken`, answered its questions, edited its spec - the next
  turn offers it again (`ticket <key>:<id> changed (status) - offered again`). The pass's own writes never lift its drop.
- A usage-limit stop is not a failure and is the only thing that moves a ticket to the next provider (see Model
  providers): the provider is held machine-wide until its limit lifts, the ticket is offered to the next provider of the
  order at once, and when every provider is spent the worker says so once and checks again every 30 seconds.
- A spec line `Blocker: <key>:<id>` (or `Блокер: <key>:<id>`) names a ticket of another registered repository. The ticket
  is not offered until that blocker is `Implemented`, `Verified` or `BlockNeedUserTest` with its tactical plan finished, or
  `Archived` - the rule the repository's own picker applies to a local blocker. A key that is not registered, a blocker id
  that is not in its ledger, or two tickets that block each other keep the ticket out, and the worker prints why
  (`ticket fms-web:S0040 waits on fms-a:S4470 (open: fms-a:S4470 is In Progress)`). Only `pq` reads the qualified form; the
  repository's own runner and a manual session ignore it, so such a ticket keeps its working status.
- A ticket whose drop was lifted three times within an hour keeps coming back unmoved, so something rewrites its row after
  every pass: it stays dropped for an hour (`ticket.thrash`) and is tried again after.
- `pq start -Drain` exits instead of waiting: 0 after at least one pass, 3 when nothing ran. `-MaxTickets N` ends the loop
  after N passes; `-Until <time>` (`HH:mm`, or a date and time) ends it at a clock time - no new pass after it, and a
  waiting worker ends at once.
- `pq start -Ticket <key>:<id>` runs exactly that ticket now, whatever its rank, and exits: one pass through the normal
  path (occupancy, repository lock, lease, resource tokens, provider order, the run row and the events), never a wait and
  never another ticket. It passes through the hold lines of `PORTFOLIO_QUEUE.md` that name its project or the ticket itself;
  the lines stay in the file and keep holding everything else. Nothing else is bypassed: the registry's `hold` and
  `enabled`, a stop, the owner's occupancy, a live lease, a provider's spent limit and the picker's gates (a `Block*`
  status, the owner gate) still apply. Exit 0 only when the pass ran; 3 with `pq: ticket <key>:<id> not run - <reason>`
  when it did not; 2 (before a worker slot is taken) for a malformed `-Ticket`, an unknown project key, or `-Ticket`
  together with `-Repo`. `-MaxTickets` with it must be 0 or 1. `pq start -Repo <key>` is a normal worker that ranks only
  that project - its ticket order, stops, waiting, `-Drain`, `-MaxTickets` and `-Until` as usual, every hold kept. Neither
  mode changes the project order or reorders the queue file; each runs the per-turn queue sync and file-to-ledger
  registration for its own project only and no discovery; `run.start` carries `target` (`ticket:<key>:<id>`, `repo:<key>`) and
  `rank.result` carries `named` and `heldBypassed` for the named start.
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

## Model providers

You choose who spends tokens, and in what order. Four providers are known:

| Provider | Agent record | Needs |
| --- | --- | --- |
| `openai` | `codex` | the Codex CLI (`npm install -g @openai/codex`) |
| `anthropic` | `claude` | Claude Code on PATH |
| `gemini` | `gemini` | Antigravity CLI `agy` (`irm https://antigravity.google/cli/install.ps1 \| iex`), signed in with Google; it reuses the Antigravity sign-in. The Gemini CLI no longer serves personal Google sign-ins (closed 2026-06-18) |
| `zai` | `zai` | Claude Code and the user environment variable `ZAI_API_KEY` (a key from z.ai/manage-apikey); the pass is Claude Code pointed at z.ai's Anthropic-compatible endpoint |

```powershell
pq agents                                  # the four, with their place in the order, CLI and limit hold
pq agents -Order openai,anthropic          # these spend tokens, the first one first
pq agents -Release openai                  # forget openai's limit hold, try it again now
```

The same choice is **Providers..** in PQ Control Panel: check the providers, put them in order with **▲ / ▼**, **Apply**.
A provider whose CLI is not found cannot be checked and the line says what to install. `-Order` writes `agentOrder` in
`repos.json` and, for a provider with no record there yet, the shipped record built against the CLI found on this
machine; a record you already have is never touched. A running worker applies the new order to the next ticket it takes.

The first provider of the order works until its usage limit is spent. Only then does the next one take the ticket - the
limit is read from the provider's own output (Claude: its transcript; the others: the record's `limitDetector.pattern`
in the pass's output, which is why those passes are quiet in the console and keep their output in the repository's runs
folder as `<ticket>.log`), and a failure with no limit text in it is an ordinary failed pass that never moves the order
on. The spent provider is held machine-wide until the reset time its message gave; with none it is tried again every
`limitPollMinutes` (30) by one pass, and the first pass that ends without a limit puts it back at the head. The ticket is
neither dropped nor counted against while this happens. If a provider's real limit message is not matched, the worker
says `failed fast .. no usage-limit text was found` - extend `limitDetector.pattern` of its record.

A provider that is installed but not signed in (Gemini without a sign-in, z.ai without its key) is listed but cannot be
checked: such a pass would end in a second with no limit text and count as a failed one. The key is read from this process
first and then from your user and machine environment, so a key set with `setx` reaches a worker that was already running.

z.ai is reached through Claude Code with `ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN` (`%ZAI_API_KEY%`) and
`API_TIMEOUT_MS` set **for that pass only**, as z.ai's own Claude Code guide describes. Do not put those in
`~/.claude/settings.json` or your user environment: `anthropic` would then spend z.ai's plan too. The model is left to
z.ai's mapping of `opus`. Gemini runs as `agy --model gemini-3.8-flash-high --dangerously-skip-permissions --print`; the
slug carries the effort, `agy models` lists the others, and each model has its own quota - change `model` in the record to
switch. ZCode's own CLI is not used: it needs the desktop app's runtime files.

The z.ai pattern follows z.ai's error code list (1308, 1310, 1316-1321 `Usage limit reached` / `Limit Exhausted`, 1113
`Insufficient balance`, 1302 `Rate limit reached`); the Gemini one matches agy's real message, `Individual quota reached.
.. Resets in 57h10m24s.` (`RESOURCE_EXHAUSTED`, exit 3), whose reset time is read. Neither has run a whole pass yet, so
`limitDetector.status` stays `unproven`. z.ai's `reset at` names no time this runner reads, so its hold polls every
`limitPollMinutes`.

## Other agents

`agentOrder` in `repos.json` is the spend order (Model providers above): for each pass the worker takes the first agent that
is not held, is under its `maxParallel`, whose `levels` admit the ticket's level (a spec without a Complexity line counts
as `medium`) and that can reach the repository's pipeline. An agent without slash commands (`promptForm: file`) is told to
open the pipeline's command file - `.claude/commands/spec-all.md` for a repository whose prompt is `/spec-all {id}`, the
plugin's `skills/spec-to-audit/SKILL.md` for `/sza:spec-to-audit` - and follow it; a repository whose prompt is plain text
gets that text. A repository without a prompt of its own, or whose prompt names a command it does not have (no command or
skill file in the repository or in `~/.claude`), gets the shared default, `/sza:spec-to-audit {id}` with the
unattended-pass instructions, for every agent: an unknown slash command is not an error to the CLI, the child would read
it as plain text and improvise. The runner prints `prompt note` when it makes that swap. Every agent other than Claude always runs the `model` and `effort` written in its record, whatever the
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
    "model": "gpt-6.1-terra", "effort": "xhigh", "maxParallel": 2, "limitPollMinutes": 30,
    "limitDetector": { "kind": "exitText", "pattern": "(?i)usage limit|rate limit", "status": "unproven" } },
  { "name": "claude", "command": "claude", "promptForm": "slash",
    "argsTemplate": ["-p", "{prompt}", "--permission-mode", "{permissionMode}", "--model", "{model}"],
    "modelByComplexity": { "light": "haiku", "medium": "sonnet", "hard": "opus" }, "maxParallel": 5 }
]
```

The command is `node` with Codex's own script, because the `codex` on PATH is a PowerShell shim a process cannot start
directly. The record is the whole launch: `{model}` and `{effort}` come from the record, `{prompt}` from the repository. An
optional `env` object sets environment variables for the pass only (a value may name a variable as `%NAME%`, so a key stays
in your environment and never reaches the registry); the shipped `zai` record uses it. A pass whose output matches `limitDetector.pattern` and that exited non-zero has spent its provider's limit: the
provider is held in `holds\<agent>.json` and the ticket goes to the next one. Exception (S0035): when a ticket is
`In Progress` and the primary provider in `agentOrder` has an active hold whose reset time is 15 minutes or less away,
the ticket waits for the primary provider's reset via temporary transient hold rather than delegating to fallback
providers (a free fallback agent may remain idle during the wait). Matched detector text is never stored in holds or
events.

## Waiting

When nothing is offerable the worker does not rank again every minute. The wait costs no agent and no picker: once per
`pollSeconds` it compares the sizes and write times of the files a change in which could matter - per enabled repository the
ledger, archive, ticket queue, ready and done files, the names of the files in its lease folder (a lease's own heartbeat is
not a change, a claim or a release is), its shared stop file, and the spec file of every ticket it has dropped; and the
registry, `PORTFOLIO_QUEUE.md`, the folder of provider holds and the resource tokens. A change is acted on after one more
quiet poll (you who just captured a Draft may still be editing it), so a ticket is taken within about two polls of its
change. With no change a rank still runs every tenth poll, because some eligibility is a matter of time (a provider's limit,
your occupancy window), and every poll while the worker itself holds something back for a moment. The worker says why it
waits, once per change: `waiting for tickets (poll 60s) - nothing offerable: occupied 1, dropped 2`. `wait.enter` carries
the same counts, `poll.change` names what changed, and one `poll.summary` per hour counts the polls, the changes and the
ranks skipped as unchanged.

## Stopping

`pq stop` writes a stop file in the portfolio root; the workers read the stop files every second, and a waiting worker at
once. The default is `STOP`, every worker, level `pass`: each worker ends after the pass in progress. Levels (`-Level`):

| Level | What happens |
| --- | --- |
| `drain` | take no new ticket; the ticket whose pass was in flight goes on with its next passes while they move it, then the worker ends |
| `pass` (default) | no new pass, not even the next one of the same ticket; the passes in flight end, then the worker ends |
| `halt` | end the pass now; every agent record says `halt: none` (no polite interrupt exists), so it is a kill that is recorded as `pass.halt` |
| `kill` (`PQ Stop Kill`, `-Kill`) | kill the process tree of the pass now |

A target narrows it: `-Worker <n>`, `-Repo <key>`, `-Agent <name>` or `-Ticket <key:id>` (one of them). While the file
exists the target gets no new work and its passes stop at the level; once nothing runs under it any more the file is deleted.
A repository stop leaves the repository on hold (`pq release <key>` clears it); the others leave nothing, the target is
eligible again at the next pick, and a ticket you want kept out is held (`pq hold`). Exit 0 when the request was recorded,
2 when nothing matched the target (unknown repository, agent or ticket key, no worker with that slot), 3 when no worker
is running at all (nothing is written). `drain` continues a ticket only for a stop of everything or of one worker.

Each worker kills the process tree of its own pass and nothing else - a local runner's agent and a session of yours in any
repository are never touched. A halted or killed pass is journalled as `halted` or `killed`, the lease the pass made is
released so the ticket is offered again at once, the build and emulator tokens it held are released, the repository's ledger
is validated (`validate` in `pass.halt` / `pass.kill`); its status stays where the agent left
it, and a stop never decides a status. Ctrl+C in a worker window ends that worker and its pass tree at once and releases
the lease the same way; the interrupted pass writes no `runs.jsonl` row (its `pass.launch` has no `pass.end`). Starting a
worker with a `STOP` present clears it and says so; if workers from the previous stop are still draining, the start exits 3
instead. A stop of one worker slot that an earlier run left behind is cleared when a worker takes that slot.

`pq pause` makes every worker launch no new pass (`paused - pq resume continues`); passes in flight finish, a stop still
ends a paused worker, and the pause outlives workers until `pq resume`. `pq status` shows the stop files, the pause and the
workers.

## Following a pass and reading the numbers

`pq tail [<key:id>] [-Worker <n>]` follows what the agent of a running Claude pass is doing, from the transcript the pass
writes as it works (`> the agent's words`, `. Read path` for a tool it called, `! text` for a tool error); it ends with the
pass or on Ctrl+C and never touches the pass. The runner buffers another agent's output until its pass ends, so there is
nothing to follow for a Codex or Gemini pass.

| Command | Shows |
| --- | --- |
| `pq inbox [-Json]` | what waits for the owner across all projects: one line per kind (count, oldest age, the command that clears it), then the tickets with id, age and note; `BlockByOtherTask` as chain roots |
| `pq report [-Days n]` | the last n days (7): passes, moved and ok shares, outcomes, ending statuses overall and by agent, entries and exits for owner-waiting statuses, the splits by agent, model, complexity and repository (only where n is at least 5), waiting, occupancy, resources, stops, robot-filed tickets, limits, log health and the open findings; `-Json` for the object |
| `pq problems [-Days n]` | the open findings only, severity first, each with the events behind it: `PQ-RACE01` (a lost claim), `PQ-SAFE01` (a tripwire), `PQ-SAFE02` (the robot-filed cap), `PQ-LIMIT01` (a limit with no reset time), `PQ-THRASH01`, `PQ-RES03` (a token waited on for 30 minutes), `PQ-STALL01`, `PQ-XREPO01` (a blocker cycle), `PQ-DATA01` (a log gap or error), `PQ-COST02` (`light` that needed three passes), `PQ-ADOPT01` (a repository far below the median) |
| `pq trace <key:id>` | every event of one ticket in time order, grouped by pass |
| `pq export [-What runs|events] [-Format jsonl|csv] [-Days n]` | the run rows (default) or the events, to stdout |
| `pq compare [-By canon|plugin|registryHash|profileHash|agent|model|complexity|repo] [-Days n]` | the run rows split by that field in the order its values first appear, with n, ok share, and a verdict between the last two values: `better` or `worse` at 15 points and n of at least 5 each, else `no evidence` |

They only read `runs.jsonl` and the event files and compute each time; nothing is filed or written. The finding lifecycle
(`finding.open` and `finding.close`), the daily digest and the `from-telemetry` tickets are not built.

Ending statuses count passes, not unique tickets. An unchanged status is neither an entry nor an exit;
where either endpoint is missing, no transition is counted. Missing ending statuses and agents are shown as
`(unknown)`. `Implemented` appears with the owner-waiting statuses because it waits for an audit.

A repository's own queue stop works on the portfolio too. While its shared stop file (`temp/STOP-SPEC-QUEUE`, written by
its `rs` or by a release freeze) exists, `pq` takes no ticket there and `PQ Dry-run` prints `skip <key> - stopped`; it
starts again once that file is gone (the freeze lifts, or you delete it or start the repository's own runner).

## Where things are

The portfolio root is `SZA_PORTFOLIO_ROOT`, else `%USERPROFILE%\.sza\portfolio`. It is outside every repository and never in git.

| File | Holds |
| --- | --- |
| `PORTFOLIO_QUEUE.md` | file one: the owner's order; synchronization refreshes ticket rows, and `pin`, `hold`, `release` change their order or hold |
| `repos.json` | the registry: repositories, `enabled`, `permissionMode`, `maxWorkers`, `pollSeconds` |
| `STOP`, `STOP-worker__<n>`, `STOP-repo__<key>`, `STOP-agent__<name>`, `STOP-ticket__<key>__<id>` | present while a stop is requested, for everything or for one target; the level is in the file |
| `PAUSE` | present while `pq pause` is in force |
| `run\worker-<k>.json` | one live worker: pid, repository, ticket, agent, since |
| `run\pass-sessions.json` | the newest 200 session ids `pq`'s own passes ran under, so their transcripts are not taken for yours |
| `resources\<build\|emulator>\<key>__<id>.json` | a build or emulator token and who holds it |
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
`agent.resume`, `dispatch.skip`, `repo.discovered`, `repo.notready`, `repo.ready`, `repo.enabled`, `repo.occupied`,
`repo.free`, `resource.acquire`, `resource.release`, `resource.wait`, `poll.change`, `poll.summary`, `ticket.thrash`,
`intake.robotDraft`, `run.pause`, `run.resume`, `pass.halt`, `pass.kill`. No line carries prompt text,
environment values or keys.

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
| `repository <key> is occupied` | a session of yours wrote a transcript there within `occupiedMinutes`, or holds a live lease: the robot goes past it to the next repository and looks again when the window can have run out (never sooner than half a minute); a session that ended is seen as gone after the window |
| `waits for the build resource` | `resources.build` tokens are all held (or `emulator`); the ticket is skipped for a minute. `Verify: device` tickets are never taken - the worker says so once |
| `pq stop` says `no worker is running` | exit 3, nothing is written; a worker window may have been closed by force, see its state files in `run\` |
| `paused - pq resume continues` | `PAUSE` is in the portfolio root: `pq resume` |

## A first test in throwaway repositories

Before pointing `pq` at a product, run it over repositories that exist only for the test. A repository gets its own
command (`/spec-all` and the like) only if it has the command file, and the plugin's lifecycle skill otherwise, so a
scaffolded throwaway repository, whose profile carries a self-contained prompt, is the cleanest bench. Two benches show both files at work: the project queue needs two projects, the
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

Day 0 written into a repository that joins, the finding lifecycle events and the `from-telemetry` tickets, a daily digest,
the live monitor page and a polite interrupt for `halt` are not part of `pq`. The code and build locks of a manual session
are not read for occupancy (its transcript and lease are). It is a loop, a rank, a few agents, a console and a log.

## Checking the tool itself

`pwsh -NoProfile -File tools/tests/smoke-portfolio-runner.ps1` from the canon root runs the loop over throwaway
repositories with a fake runner; it starts no agent. It also covers the shortcuts and `pq tickets`.
`pwsh -NoProfile -File tools/tests/portfolio-queue.tests.ps1` covers the registry, the project queue file, the picker and the
rank, case by case.
