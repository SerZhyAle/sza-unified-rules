# hooks/ - the canon's enforcement layer

The rule docs say four separate times that a behaviour is worth **enforcing at the tool call rather than
stating as a rule** - and until recently the canon shipped none of those hooks, leaving every project to
build them itself. One project did. These are those hooks, generalized, so the canon enforces what it
preaches everywhere the plugin is enabled.

The number behind all of it, from [AI_USAGE.md](../rules/AI_USAGE.md) section 5: measured across a month
of this portfolio's sessions, rules with a mechanical gate held at **~99%**; the same rules stated only as
prose held at **1-8%**. And the ceiling on what more prose can buy: the advice to read a large file with
an explicit range ships in the built-in tool description on **literally every turn**, and compliance
measured **22%**.

## Inventory

**This table is the inventory, and it is load-bearing.** Registering, removing or re-registering a hook
requires editing it in the same change; `check-compliance.ps1` `SZA-HOOK01` fails when something
registered in [`hooks.json`](hooks.json) is missing from it. Two deliberate limits keep that check from
crying wolf: it parses **this table only** - never the prose around it, because script names appear in
prose too and a loose parse turns every mention into a phantom entry - and it compares in **one direction
only**. A row with no registration here is *not* reported, because a hook registered in a machine-local
settings file is real, live and correctly listed, and the gate never reads that file. Judge what is
readable; degrade rather than guess. The gate finds this table by its **heading**, not by this file's
name, so a repo may keep its inventory wherever it documents hooks.

| Hook | Event | Verdict | What it does | Canon home |
| --- | --- | --- | --- | --- |
| [`session-start.ps1`](session-start.ps1) | `SessionStart` | injects | the twenty hard invariants, in an adopting repo only | [INVARIANTS.md](../rules/INVARIANTS.md) |
| [`guard-bash.ps1`](guard-bash.ps1) | `PreToolUse` (Bash) | refuses | five things that cannot work in Bash on Windows, plus one that corrupts silently | [GITHUB_INTERACTION.md](../rules/GITHUB_INTERACTION.md) section 6 |
| [`guard-uncapped-read.ps1`](guard-uncapped-read.ps1) | `PreToolUse` (Read) | rewrites | windows an uncapped read of a file over 500 lines, and says so | [AI_USAGE.md](../rules/AI_USAGE.md) sections 3 and 5 |
| [`on-user-prompt.ps1`](on-user-prompt.ps1) | `UserPromptSubmit` | warns, nudges | context size past the band; a micro-task reaching for the full pipeline | [AI_USAGE.md](../rules/AI_USAGE.md) sections 3 and 5 |

Why the inventory is a rule and not tidiness: **a hook is invisible by construction.** It fires inside a
tool call nobody is reading, so an undocumented one is indistinguishable from a bug in the tool - and a
*removed* one is indistinguishable from a rule that was never enforced. A hook file sitting on disk that
is registered nowhere is the mild case: an advisory, not a failure, because dead weight is not a
documentation gap.

## The verdict vocabulary

Seven verbs, so a reader can tell at a glance what a hook will do to them. Six of them came from the
reference inventory; **injects** is the canon's own addition, because it ships a hook whose entire verdict
is "here is context you did not ask for", which none of the other six describes.

| Verb | Event shape | What the caller experiences |
| --- | --- | --- |
| refuses | `PreToolUse` | the call does not happen; `exit 2` and the reason on stderr |
| rewrites | `PreToolUse` | the call happens with corrected input, plus a notice saying what changed |
| injects | `SessionStart` | context arrives that was never requested |
| observes | `PostToolUse` | the result stands; context may be attached to it |
| warns | any advisory event | a message, no verdict |
| nudges | `UserPromptSubmit` | a suggestion aimed at the next decision, not at this call |
| arms | `SessionStart` | nothing visible; a marker is set that a companion gate reads |

## Contracts

- **Refusing** returns `exit 2` to block and `exit 0` to allow, and **fails open** on any parse, path or
  IO error - a schema change must never make a tool unusable.
- **Rewriting beats refusing wherever the correct input is knowable.** The preference order is: correct
  the input; refuse only where no correct input exists. A block cannot fix and retry - it can only cost
  the caller a round trip and hope they choose better. Measured: the blocking predecessor of
  `guard-uncapped-read` fired **381 times in one week** and **31.8% of those blocks were answered by
  re-issuing the same read with an explicit limit of 1500+** - the whole file anyway. No context saved, a
  turn spent. Three mechanics, each easy to get wrong:
  - `updatedInput` is honoured only alongside `permissionDecision: "allow"`, and must be a **complete**
    replacement of the tool input - a partial object drops the fields it omits.
  - `additionalContext` reaches the model; a `permissionDecisionReason` does not. The notice travels in
    the former or it is not read.
  - a rewriting hook must **fail open harder** than a blocking one: when it errs it corrupts what the
    model reads, rather than merely gating a call. Attach the notice only when it carries information -
    a notice on a call that was not actually changed is noise, and noise is what gets a hook turned off.
- **Observing** is a `PostToolUse` shape and cannot change the result the model sees - it can only attach
  context. That constraint is what makes the shape safe, and it is worth stating because the natural
  assumption is the opposite. The design rule that comes with it: **an observing hook must be built so
  that being wrong is structurally impossible**, not merely unlikely. The reference instance speaks only
  when it holds a counter-example in hand - a scoped search returned nothing, so it silently re-ran the
  search unscoped and spoke only because the wider run found something. If the wider run also finds
  nothing it stays silent and the original verdict stands. Nobody audits a hook that is merely usually
  right.
- **Arming** is a `SessionStart` shape that resets a marker so a companion pre-tool gate starts each
  session requiring one fresh action before it stands down. Trivial mechanically, worth naming because it
  is how a gate becomes "once per session" rather than "always" or "never" - and because the pair breaks
  silently if one half moves. Always `exit 0`: a session start is never worth blocking.
- **Refusing a turn** is the one shape that guards neither a call nor a prompt. On the `Stop` event, while
  a marker armed by this session says an autonomous loop is running, it refuses to let the agent finish
  and says what to do instead. Everything else in this file answers "may this call proceed"; this answers
  "may you consider yourself done" - the one decision an agent otherwise makes entirely alone. The canon
  **does not ship one**, because the live instance is paired with a specific autonomous-loop command and
  is project surface; the contract is recorded here because a contracts section that claims to describe
  the shapes a hook can take must actually describe them:
  - **exit 0 always**; the verdict travels in stdout JSON. A session must never fail to end because a
    hook errored.
  - **Silence means allow.** Every allow-path writes nothing at all.
  - **Every allow-path is a liveness question**: no marker exists; the marker belongs to another session
    and has gone stale past a ceiling; a background waiter is genuinely in flight and its completion is
    the wake signal; or the operator disarmed it.
  - **Escalate on repeated bouncing.** A refusal that repeats identically is a loop, and the agent did not
    understand the first one - so the message escalates from "resume" to a specific named next action.
  - **Only an explicit operator action ends it.** The harness's own "the stop hook already fired" signal
    is deliberately ignored, because continuing is the hook's entire purpose.
  - The sanctioned way to be idle is to **launch a background waiter and then end the turn**; the hook
    recognises that marker and steps aside. Without such a path, a turn-refusing hook is a trap.
- **Every escape hatch is unconditional.** `guard-uncapped-read` never touches a Read carrying an explicit
  `limit` or `offset`, however large, because auditing an implementation end to end is legitimate work.

## Two scopes, on purpose

**`session-start.ps1` is self-limiting.** It fires only in a repo carrying an `.sza-canon.json` stamp, so
an unrelated project never pays for the injection.

**The guard and the advisories are not.** Each enforces a property of the operating system or of the
harness, not of a project's conventions: an orphaned `find.exe` floods handles on any Windows checkout, a
`.ps1` and a `Verb-Noun` cmdlet are unrunnable by any Bash, an uncapped read is billed by the harness,
context grows the same way in every repo. Gating them on adoption would leave the failure live in exactly
the repos that have not adopted yet.

## Cost

A hook wired to a frequent tool must **pre-filter in the harness's own shell first**
([AI_USAGE.md](../rules/AI_USAGE.md) section 3). Starting PowerShell costs 170-250 ms on Windows, so both
`PreToolUse` registrations sit behind a `case` test in bash and spawn `pwsh` only on a payload that could
possibly trip them - on the reference corpus that skipped ~89% of the spawns and changed no verdict.
**The pre-filter may only skip calls the real check would have allowed**; the scripts stay authoritative.

The same rule is why the five Bash checks live in **one** script. Five registrations on one event would
pay the interpreter start up to five times for a single command, and three of the five need the same
quote-aware segmentation, so five scripts would also have carried five copies of that parse. That is the
canon's own "batch the fast gates into one process"
([DEVELOPMENT.md](../rules/DEVELOPMENT.md) section 15) applied to its own hooks -
`on-user-prompt.ps1` carries **both** prompt-submit advisories for the identical reason.

## Testing them

```powershell
pwsh -NoProfile -File hooks/tests/smoke-hooks.ps1        # 40 cases, exit 0 required
pwsh -NoProfile -File hooks/tests/smoke-prefilters.ps1   # 20 cases, exit 0 required
```

Every refusal is smoked **from both sides** - payloads it must refuse and payloads it must allow -
because a guard that over-blocks gets turned off, and then nothing is enforced. The allow cases are the
load-bearing ones. The advisories and the rewriter are asserted on their *output*, not their exit code:
they always exit 0, so an exit check alone cannot tell "fired" from "stayed silent".

**The second suite is not optional, and it is the one most projects are missing.** It asserts the
registered **pre-filter**, recovered out of `hooks.json` and run under Git Bash - not the hook. The
regression it exists for: a pattern `*[A-Z]-[A-Z]*`, meant to catch `Verb-Noun` cmdlets, matched no real
cmdlet at all, because in `Select-Object` the character before the hyphen is lowercase. The hook was
correct and simply never ran, which looks exactly like a hook that was never needed. Test under **Git
Bash specifically**: a `bash` on `PATH` may be WSL, which is a different shell and proves nothing about
the live registration.

## Turning one off

```powershell
$env:SZA_HOOKS_OFF = '1'          # every hook in this folder steps aside
$env:SZA_NO_CONTEXT_WARN = '1'    # keep the rung nudge, drop the context warning
$env:SZA_NO_RUNG_NUDGE = '1'      # keep the context warning, drop the rung nudge
```

## If you already wired these by hand

These hooks previously lived in a machine-local `~/.claude/settings.json` and in one project's
`.claude/settings.json`. **Remove those registrations when the plugin is enabled** - two registrations of
the same guard fire it twice, paying the interpreter startup twice and printing the block message twice.
The plugin copy is the one to keep: it travels to every machine and every repo with the plugin, which is
the whole point.

**Verify the installed plugin cache, not the marketplace clone.** Until the *installed* cache carries a
given script, a hand-wired registration is the only thing making that guard live, and removing it
"because the plugin has it now" **silently disarms it** - which looks exactly like a guard that was never
needed. This repo publishes the plugin, so it is the one place that can warn about the window between
"the clone has it" and "my cache has it".

Two names moved in the same pass that added the cmdlet, interpreter and slash-argument checks:
`guard-find-command.ps1` and `guard-ps1-in-bash.ps1` are **gone**, absorbed into `guard-bash.ps1`. A
hand-wired registration still pointing at either path is now a dead registration - it fails silently,
which is the exact failure this section is about.
