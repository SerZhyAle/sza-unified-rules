# pq - the portfolio queue, operator's guide

`pq` works the owner's queue across every registered repository. It asks the rank for the first ticket, runs that
repository's own runner (`run-spec-queue.ps1`) on that one ticket, writes what happened to a log, and ranks again. With
nothing to do it waits a minute and looks again. Working by hand in any repository stays exactly as it is: a ticket a
manual session holds is never taken, and `pq` writes nothing inside a repository tree.

The model for a ticket is not chosen by `pq`. The runner reads the ticket's `**Complexity:** <light|medium|hard> - <why>`
line at every launch: `light` is haiku, `medium` sonnet, `hard` opus. A spec without the line keeps the runner's
earlier routing.

## The desktop shortcuts

`install-shortcuts.ps1` in this folder puts one shortcut per command on the Desktop. Each opens a PowerShell 7 window that
stays open.

```powershell
pwsh -NoProfile -File tools/harness/portfolio/install-shortcuts.ps1            # create or refresh
pwsh -NoProfile -File tools/harness/portfolio/install-shortcuts.ps1 -DryRun    # show, write nothing
pwsh -NoProfile -File tools/harness/portfolio/install-shortcuts.ps1 -Remove    # take them off
```

Run it from the canon working tree, not from the plugin cache: the shortcuts point at the `pq.ps1` beside the script, and
the cache path changes with every plugin version. A file of the same name that is not one of ours is left alone.

| Shortcut | Runs | Use it to |
| --- | --- | --- |
| PQ Start | `pq start` | run one worker; it waits when nothing is ranked |
| PQ Start 1 ticket | `pq start -MaxTickets 1` | do exactly one pass and stop - the attended first run |
| PQ Status | `pq status` | see workers, today's passes, the next ticket, whether `STOP` is set |
| PQ Log | `pq log -Last 60` | read the last 60 events across all writers |
| PQ Stop | `pq stop` | let every worker finish the pass it is on, then end |
| PQ Stop Kill | `pq stop -Kill` | end now: runner children are terminated and the ticket in flight is abandoned |
| PQ Dry-run | `pq dry-run` | see the order the loop would take; launches nothing |
| PQ Queue | `pq queue` | open `PORTFOLIO_QUEUE.md` in the editor |
| PQ Doctor | `pq doctor` | check the enabled repositories and the queue file |
| PQ Repos | `pq list` | list the registered repositories |
| PQ Guide | - | open this file |

Several workers are several `PQ Start` windows (up to `maxWorkers` in the registry). Each takes the first free slot; a
repository is worked by one worker at a time unless its registration says `concurrent`.

## One-time setup, per repository

A repository registers only if it has adopted the canon (a readable `.sza-canon.json`); to be worked it also needs a
profile, a ticket ledger and a runner, which `task-flow-init` sets up. It joins disabled; the owner turns it on after looking
at the order it produces.

1. **Register** - `pwsh -NoProfile -File tools/harness/portfolio/pq.ps1 register -Path <repository>`. The key defaults to
   the folder name (`-Key` overrides it). This writes `repos.json` in the portfolio root and nothing in the repository.
   Day 0 of `task-flow-init` and `adopt-canon` ends in this command.
2. **Check** - `PQ Doctor` should report PASS for the repository's stamp, profile and ledger. Run `r0 -DryRun` inside the
   repository and `PQ Dry-run`; both should name the ticket you expect first.
3. **Enable** - edit `repos.json` in the portfolio root: set `"enabled": true` for the repository and give it an explicit
   `"permissionMode"`, either on its own record or once at the top level for all (valid values: `acceptEdits`, `auto`,
   `bypassPermissions`, `manual`, `dontAsk`, `plan`). No mode is supplied by default, and without one `pq start` refuses to
   do unattended work. The value is handed to the agent as `--permission-mode`; choose it per repository, deliberately.
4. **Order** - `PQ Queue` (run `pq queue -Init` once to write the first file). Edit it as plain text, see below.

## The order

The first ticket is chosen in this order, and `PQ Dry-run` prints exactly this:

1. `PORTFOLIO_QUEUE.md`, top to bottom. A row is `<repo>`, `<repo>:*` or `<repo>:<ticket id>`; anything after `#` is a
   comment. A line of only digits starts a numbered package (1 is first); `--` is the unscheduled package after the
   numbered ones; a line holding only `hold` starts a section that nothing below is touched from.
2. Repositories the file does not mention, by the priority of their head ticket, ties by the registry's repository order.

Disabled and held repositories are skipped. A repository's own queue decides the order inside it. Moving a line changes the
order at the next rank, no restart needed. `pq pin <repo:id>` puts a ticket on top, `pq hold <repo[:id]>` and
`pq release <repo[:id]>` move a row under or out of `hold`. `release` only removes the row from under `hold`: it does not
return it to its old package, and the repository then ranks as unlisted until you put its line back by hand.

## What a worker does

```
loop:  STOP file?  -> end
       rank        -> first candidate not excluded
       repository lock -> worker slot -> run-spec-queue.ps1 -Ids <id> -MaxTickets 1 -Instance pq<k>   (waits for it)
       read the outcome -> runs.jsonl + events -> exclude the ticket if its status did not move
empty: sleep up to pollSeconds (60) in short slices, rank again
```

- A pass that ends with the ticket's status unchanged, or in failure, excludes that ticket until this `pq start` ends, so
  the loop never spins on one ticket.
- A usage-limit stop is not a failure: the runner records it and waits out its own hold before the next launch. The hold is
  per repository, so an account-wide limit is met once in each repository.
- `pq start -Drain` exits instead of waiting: 0 after at least one pass, 3 when nothing ran. `-MaxTickets N` ends the loop
  after N passes.

## Stopping

`PQ Stop` writes `STOP` in the portfolio root. Each worker checks it before every rank and in every sleep slice and ends after
the pass in progress. `PQ Stop Kill` also tells each runner to stop and kills the pass process tree. Ctrl+C in a worker
window ends that worker and its pass tree at once. Starting a worker with a `STOP` present clears it and says so; if workers
from the previous stop are still draining, the start exits 3 instead.

## Where things are

The portfolio root is `SZA_PORTFOLIO_ROOT`, else `%USERPROFILE%\.sza\portfolio`. It is outside every repository and never in git.

| File | Holds |
| --- | --- |
| `repos.json` | the registry: repositories, `enabled`, `permissionMode`, `maxWorkers`, `pollSeconds` |
| `PORTFOLIO_QUEUE.md` | the owner's order; the owner's file, `pq` changes it only through `pin`, `hold`, `release` |
| `STOP` | present while a stop is requested |
| `run\worker-<k>.json` | one live worker: pid, repository, ticket, since |
| `run\repo-<key>.lock` | the repository a worker is in |
| `runs.jsonl` | one row per pass: run, pass, repository, ticket, status before and after, exit code, seconds, outcome |
| `log\events-<UTC day>.<writer>.jsonl` | every step as an event |

The repository's own runner keeps its rows for these passes as instance `pq<k>` (`runs-pq<k>.jsonl`), so they show up in the
repository's monitor as one more instance.

## Reading the log

`PQ Status` is the first look. `PQ Log` shows events in timestamp order; narrow it in a console with `pq log -Repo <key>`,
`-Ev <name>` and `-Json`. The events a loop writes: `run.start`, `run.end`, `rank.result`, `pass.launch`, `pass.end`,
`pass.limit`, `wait.enter`, `wait.exit`, `run.stop`, `owner.action`. No line carries prompt text, environment values or keys.

## When it does not do what you expect

| You see | Meaning and fix |
| --- | --- |
| `RegistryMissing` | nothing registered yet - `pq register -Path <repository>` |
| `StampMissing` on register | the repository has not adopted the canon - run `adopt-canon` there first |
| `start` waits and `Next: none` | no enabled repository offers a ticket: `PQ Dry-run`, then check `enabled`, `hold`, a `hold` section in the queue file, and that the ticket is not leased by a manual session |
| a ticket is passed over | it did not move last time and is excluded until this `start` ends, or another worker holds the repository |
| `start` exits 3 at once | a previous `STOP` is still draining live workers - wait for them to leave |
| refuses unattended work | the repository has no `permissionMode` - set it in `repos.json` |
| a worker window was closed by force | its state files stay; the next start reclaims files whose process is gone |

## A first test in a throwaway repository

Before pointing `pq` at a product, run one pass in a repository that exists only for the test. A repository gets the
runner's own prompt (`/spec-all` and the like) only if it has the command, so a scaffolded throwaway repository, whose profile
carries a self-contained prompt, is the cleanest bench.

1. New folder, `git init`, a `.sza-canon.json` copied from `templates/.sza-canon.json` and filled (or `adopt-canon`), then
   `tools/harness/scaffold/init-task-flow.ps1 -Root <folder> -PermissionMode bypassPermissions`.
2. One ticket: `capture-draft.ps1 -Slug <slug> -TextFile <file> -Complexity "light - <why>"`, with a task that needs no
   research and no question (for example, create one text file holding one line). `validate.ps1` must exit 0.
3. `pq register -Path <folder> -Enable`, then add `"permissionMode": "bypassPermissions"` to that repository's record in
   `repos.json`, and `pq queue -Init` once.
4. `PQ Doctor` reports 0 FAIL; `PQ Dry-run` names the ticket first. The pass itself can be previewed without an agent:
   `run-spec-queue.ps1 -RepoRoot <folder> -Ids <id> -MaxTickets 1 -ModelPolicy shape -Instance pq1 -PermissionMode
   bypassPermissions -DryRun` (with `SZA_PROJECT_ROOT` set to the folder) prints the model the Complexity line picks.
5. `PQ Start 1 ticket`. One pass runs and the window stays open. Then `PQ Status` and `PQ Log`.

What a good pass leaves behind: the ticket's status moved (it may land on a `Block*` status with a note, which is also
a move); one new row in the portfolio's `runs.jsonl`; `pass.launch` and `pass.end` events in `PQ Log`; and a row in the
repository's own `temp/spec-queue/runs-pq1.jsonl`. The three records must agree on ticket and outcome. A ticket that did not
move is excluded for the rest of that run and the log says so.

## Not in this version

Other agents than Claude, a machine-wide usage-limit hold, a console, metrics and analysis, automatic joining of new
repositories and cross-repository blockers are not part of `pq`. It is a loop, a rank and a log.

## Checking the tool itself

`pwsh -NoProfile -File tools/tests/smoke-portfolio-runner.ps1` from the canon root runs the loop over throwaway
repositories with a fake runner; it starts no agent.
