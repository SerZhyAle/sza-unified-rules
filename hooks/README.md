# hooks/ - the canon's enforcement layer

The rule docs say four separate times that a behaviour is worth **enforcing at the tool call rather than
stating as a rule** - and until now the canon shipped none of those hooks, leaving every project to build
them itself. One project did. These are those hooks, generalized, so the canon enforces what it preaches
everywhere the plugin is enabled.

The number behind all of it, from [AI_USAGE.md](../rules/AI_USAGE.md) section 5: measured across a month
of this portfolio's sessions, rules with a mechanical gate held at **~99%**; the same rules stated only as
prose held at **1-8%**. And the ceiling on what more prose can buy: the advice to read a large file with
an explicit range ships in the built-in tool description on **literally every turn**, and compliance
measured **22%**.

| Hook | Event | Canon home | What it does |
| --- | --- | --- | --- |
| [`session-start.ps1`](session-start.ps1) | `SessionStart` | [INVARIANTS.md](../rules/INVARIANTS.md) | injects the twenty hard invariants |
| [`guard-find-command.ps1`](guard-find-command.ps1) | `PreToolUse` (Bash) | [GITHUB_INTERACTION.md](../rules/GITHUB_INTERACTION.md) section 6 | blocks a `find` with a disk-wide root or no `-maxdepth` |
| [`guard-ps1-in-bash.ps1`](guard-ps1-in-bash.ps1) | `PreToolUse` (Bash) | [GITHUB_INTERACTION.md](../rules/GITHUB_INTERACTION.md) section 6 | blocks a `.ps1` in Bash command-head position |
| [`guard-uncapped-read.ps1`](guard-uncapped-read.ps1) | `PreToolUse` (Read) | [AI_USAGE.md](../rules/AI_USAGE.md) section 3 | blocks the first uncapped read of a file over 200 lines |
| [`on-user-prompt.ps1`](on-user-prompt.ps1) | `UserPromptSubmit` | [AI_USAGE.md](../rules/AI_USAGE.md) sections 3 and 5 | warns on context size; nudges a micro-task to the cheapest rung |

## Two scopes, on purpose

**`session-start.ps1` is self-limiting.** It fires only in a repo carrying an `.sza-canon.json` stamp, so
an unrelated project never pays for the injection.

**The guards and the advisories are not.** Each enforces a property of the operating system or of the
harness, not of a project's conventions: an orphaned `find.exe` floods handles on any Windows checkout, a
`.ps1` is unrunnable by any Bash, an uncapped read is billed by the harness, context grows the same way in
every repo. Gating them on adoption would leave the failure live in exactly the repos that have not
adopted yet.

## Contracts

- A **guard** returns `exit 2` to block and `exit 0` to allow, and **fails open** on any parse, path or IO
  error - a schema change must never make a tool unusable.
- An **advisory** always returns `exit 0` and emits either nothing or one `additionalContext` object. A
  false fire that refused a prompt would cost more than the miss it prevents.
- Every escape hatch is **unconditional**. `guard-uncapped-read` steps aside for any Read carrying an
  explicit `limit`, however large, because auditing an implementation end to end is legitimate work.

## Testing them

```powershell
pwsh -NoProfile -File hooks/tests/smoke-hooks.ps1     # 14 cases, exit 0 required
```

Every guard is smoked **from both sides** - one payload it must refuse and one it must allow - because a
guard that over-blocks gets turned off, and then nothing is enforced. The allow cases are the load-bearing
ones. The advisories are asserted on their *output*, not their exit code: they always exit 0, so an exit
check alone cannot tell "fired" from "stayed silent".

## Turning one off

```powershell
$env:SZA_HOOKS_OFF = '1'          # every hook in this folder steps aside
$env:SZA_NO_CONTEXT_WARN = '1'    # keep the rung nudge, drop the context warning
$env:SZA_NO_RUNG_NUDGE = '1'      # keep the context warning, drop the rung nudge
```

## Cost

A hook wired to a frequent tool must **pre-filter in the harness's own shell first**
([AI_USAGE.md](../rules/AI_USAGE.md) section 3). Starting PowerShell costs 170-250 ms on Windows, so the
two Bash guards and the Read guard are registered behind a `case` test in bash and spawn `pwsh` only on a
payload that could possibly trip them - on the reference corpus that skipped ~89% of the spawns and
changed no verdict. **The pre-filter may only skip calls the real check would have allowed**; the scripts
stay authoritative.

`on-user-prompt.ps1` carries **both** prompt-submit advisories in one process for the same reason: they
fire on the same event and each is a sub-second string check, so two interpreters would pay the startup
twice per prompt. That is the canon's own "batch the fast gates into one process"
([DEVELOPMENT.md](../rules/DEVELOPMENT.md) section 15) applied to its own hooks.

## If you already wired these by hand

These hooks previously lived in a machine-local `~/.claude/settings.json` and in one project's
`.claude/settings.json`. **Remove those registrations when the plugin is enabled** - two registrations of
the same guard fire it twice, paying the interpreter startup twice and printing the block message twice.
The plugin copy is the one to keep: it travels to every machine and every repo with the plugin, which is
the whole point.
