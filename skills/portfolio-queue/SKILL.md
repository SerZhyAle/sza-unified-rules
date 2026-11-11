---
name: portfolio-queue
description: Work with the portfolio queue runner (pq) - the robots that take tickets from every registered project in the owner's order - see what they are doing, why one is idle, stop, pause or steer them, and read what they did. Use on "pq", "portfolio queue", "start the robots over all projects", "what are the robots doing", "why does the robot not take the ticket", "stop the robots", "pause the queue", "report on the robots", "robot queue status", or on the Russian phrasings - "запусти роботов по всем проектам", "очередь по всем репозиториям", "что делают роботы", "почему робот не берёт тикет", "останови роботов", "поставь очередь на паузу", "отчёт по роботам", "что сделали роботы за неделю", "задачи по всем проектам". It reads and steers; it never starts a worker on its own, and it never tags, publishes or releases.
---

# Portfolio queue - the robots over all projects

`pq` is the loop that works the tickets of every registered project, one pass per ticket, in the order of two plain text
files the owner edits: `PORTFOLIO_QUEUE.md` (the projects and their tickets) and each project's own
`PLAN/RELEASE_QUEUE.md`. The operator's guide is [the portfolio README](../../tools/harness/portfolio/README.md); this
skill only says which command answers which question. Read the guide for the why.

## Step 0 - Resolve the plugin root

The same resolution as [spec-all](../spec-all/SKILL.md) Step 0: print the resolved path and paste it literally. `pq` is a
script, not a command on the path:

```powershell
pwsh -NoProfile -File "<root>/tools/harness/portfolio/pq.ps1" <verb> <arguments>
```

The portfolio state is outside every repository (`SZA_PORTFOLIO_ROOT`, else `%USERPROFILE%\.sza\portfolio`); run `pq` from
any folder.

## Which command answers which question

| The owner asks | Run |
| --- | --- |
| what are the robots doing, is anything running | `pq status` (workers, stop files, pause, today's outcomes, the next ticket) |
| what is the agent of that pass doing right now | `pq tail <key:id>` (Claude passes only; it follows until the pass ends - run it with a time limit or hand the command to the owner) |
| why does the robot not take ticket X / why is a project idle | `pq dry-run` (the order and the rule behind each pick, what is skipped and why), then `pq trace <key:id>` (every event of that ticket), then the worker's own line: `occupied` (a session of the owner's is live there), `waits for the build resource`, `waits on <key:id>` (a blocker in another repository), a dropped ticket (it did not move; it returns when its status, `updated` or spec changes), `hold` in either file |
| what did the robots do this week, what went wrong | `pq report -Days 7`, `pq problems` (open findings with the events behind them) |
| did the last canon or plugin version make the robots better | `pq compare -By canon` (or `plugin`, `agent`, `model`) |
| stop them | `pq stop` (after the passes in flight), `pq stop -Level kill` (now), `pq stop -Repo <key>` / `-Agent <name>` / `-Ticket <key:id>` / `-Worker <n>` for one target |
| pause, then go on | `pq pause`, `pq resume` |
| move a project or a ticket up, hold it, release it | `pq queue` / `pq tickets <key>` open the two files; `pq pin <key:id>`, `pq hold <key[:id]>`, `pq release <key[:id]>`, `pq rank`, `pq arrange` |
| run exactly this ticket now, whatever its rank | `pq start -Ticket <key>:<id>` - hand the command to the owner (see "Run one ticket or one project" below) |
| keep a worker on one project only | `pq start -Repo <key>` - hand the command to the owner |
| which providers work, in what order, who is out of limit | `pq agents` (and `-Order codex,claude`, `-Release <provider>`) |
| is the setup sound | `pq doctor`, `pq list` |

## Run one ticket or one project

Two ways to aim a worker without touching the saved order (`pq rank`, `PORTFOLIO_QUEUE.md` stay as they are):

| Command | What runs |
| --- | --- |
| `pq start -Ticket <key>:<id>` | exactly one pass on that ticket, whatever its rank, through the normal loop (occupancy, repository lock, lease, resources, provider order, run row, events); then it exits. It never waits for the ticket and never takes another one |
| `pq start -Repo <key>` | a normal worker that ranks only that project: ticket order, stops, waiting, `-Drain`, `-MaxTickets` and `-Until` as usual |

`-Ticket` and `-Repo` together are refused. A malformed `-Ticket`, an unknown project key or an unknown `-Repo` key exits 2
with `pq: <Name> - <message>` before anything starts. A valid target that does not run (ticket absent or not offered, leased,
blocked, repository occupied, stopped or disabled, no agent, resource busy) exits 3 and prints the reason; exit 0 only when
the pass ran.

**The hold rule (owner decision 2026-11-11).** `-Ticket` runs the named ticket **through a hold line of
`PORTFOLIO_QUEUE.md`** - a whole-project hold row or the ticket's own `hold` row - and does **not** remove it. Only those
queue-file lines are bypassed. Still in force for the named ticket: the registry's own `hold` and `enabled: false`,
occupancy, the repository lock, the lease, resource tokens, a provider out of limit, `STOP`, and the picker's gates (status
not eligible or `Block*`, an unreleased cross-repo `Blocker:`). `-Repo` bypasses nothing: every hold stays. `pq release`
stays the owner's call.

The same two aims exist in `PQ Control Panel` from the build that follows this change (**Run now** beside Pin Top, **Start on this project** on a project row) and
in the one-ticket skills: `/spec-all <key>:<id>` and `/sa <key>:<id>` work one named ticket of any project from any folder,
`/spec-all <key>` and `/spec-next <key>` take that project's next eligible ticket, then stop.

## What this skill does not do

- **It does not start a worker.** `pq start` runs until stopped and spends the owner's tokens; the owner starts it from the
  `PQ Start` shortcut or a terminal of their own. Say so and give the command (`pq start`, `pq start -MaxTickets 1` for one
  pass, `pq start -Drain` to end when nothing is ranked, `pq start -Until 23:00`, `pq start -Ticket <key>:<id>` for one
  named ticket, `pq start -Repo <key>` for one project). Run it only when the owner names that
  exact start, and then in a background process, never in the foreground of a chat.
- **It does not edit the two queue files by hand.** The owner's order is theirs; use the verbs above, which keep it.
- **It does not change a ticket's status.** Status moves through the ticket tool (TASK-FLOW rule 4); a stop never decides a
  status either.
- **It never releases, tags or pushes.** The robots do not either (`INVARIANTS` 4, 18).

## Reading the answer

- A repository `occupied` by the owner is not a fault: the robot yields and looks again after half a minute. The window is
  `occupiedMinutes` in `repos.json` (3 minutes on the owner's machine).
- `pq problems` lists findings with stable ids (`PQ-RACE01`, `PQ-SAFE02`, `PQ-THRASH01`, `PQ-LIMIT01`, `PQ-DATA01` and others);
  a figure is printed with its n and a split only where n is at least 5. Say "no evidence" where the report does.
- A provider out of limit is held machine-wide until its reset time (`pq agents` shows it); the ticket goes to the next
  provider of the order and the robot comes back by itself.
- A fix to `pq` itself under `tools/` reaches the owner's sessions only after the plugin version moves (the canon's
  `deploy.ps1`, on the owner's request); open workers keep the code they loaded until restarted.
