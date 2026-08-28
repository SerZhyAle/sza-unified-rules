# AI Usage - how agents work on these projects

The operating contract for any AI agent (Claude Code and siblings) working in this portfolio. It is the
*behaviour* layer; [DEVELOPMENT.md](DEVELOPMENT.md) is the *code* layer they produce. The fuller public
distillation lives in the **universal-agent-kit** repo - this file is the portable subset every project
shares. Reconciled against the portfolio; per-project records in `contrib/`.

## 1. Operating principles

- **Autonomy by default.** Run searches, builds, catalog/spec queries, and device/CLI chores without
  asking. Flag blockers up front.
- **Background a long job, foreground a short one - and state the threshold.** Set it at the agent
  harness's own foreground timeout, so the boundary is a fact rather than a preference. Above it,
  backgrounding is required: a job that would time out loses its output capture on the forced handoff.
  Below it, backgrounding is **forbidden** - it costs an extra turn plus the hand-polling that follows,
  and a fast check's verdict is worth having in the same turn that asked for it. A one-sided
  "background long jobs" rule reliably decays into backgrounding everything and then polling it by hand.
- **Never fire-and-forget a verdict.** This is the shape the rule above actually fails in: dispatching a
  gate, a closure facade or a catalog mutator asynchronously and moving straight on, on the intuition
  that not waiting is free. It is not. It saves no turn - the completion notification re-invokes the
  agent, so the call costs one *more* - and it quietly demotes a gate into an ungated rule, because a
  check whose exit code nobody reads is not a check. A backgrounded task also tends to report its
  wrapper's exit code rather than the command's, so the failure mode is a false PASS, the worst shape a
  defect can take. Shipped as the `guard-fire-and-forget` hook rather than left as this paragraph, for
  the reason section 5 gives.
- **Don't ask what the architecture already answers.** If a convention, flavor hierarchy, or contract
  decides the question, research it and recommend - don't kick it back to the owner. Reserve questions
  for genuine forks the owner must own (scope, product intent, UI ambiguity).
- **Surface UI placement/visibility/fallback ambiguity before implementing** - don't guess a
  user-facing decision.
- **Push back once, then obey.** If the owner's call looks wrong, argue the case once with evidence;
  if they hold, execute their decision cleanly.

## 2. Evidence over confidence

- The flagship rule from [DEVELOPMENT.md](DEVELOPMENT.md) §5 governs agent claims too: **no "done" /
  "fixed" / "passing" without a fresh command run, its exit code, and its output cited.** A subagent's
  self-report is not evidence - re-verify.
- Verify a memory/assumption against the live tree before acting on it - files get renamed and removed;
  a remembered path or symbol is a claim to re-check, not a fact.
- **Three invariants bind whatever script closes a change** - the checker, the gate battery, the closure
  facade, whatever the project calls it. One: **the verdict covers every file in the change**, not the
  one file that happened to be named. Two: **PASS is printed only when every gate passed** - a green
  tail line over a failed gate inside is worse than no gate, because callers read the tail. Three:
  **the exit code distinguishes "found a defect" from "could not verify"** - a missing tool, an
  unexpanded argument or a timeout is not a pass. The scripts differ per project; these do not.

## 3. Cost & parallelism discipline

- **Measure before you argue cost, and use the shared method** - the `agent-cost` skill carries it,
  along with the five corrections without which every token figure is inflated roughly threefold,
  every failure rate about as badly, and a "nobody ever reads this" claim wrong by an order of
  magnitude. That last one is the trap worth naming here: **consumption cannot be counted by tool
  name.** An artifact that is also written, searched or opened through the shell is consumed through
  channels a `Read`-only scan cannot see - and the shell reads carry no file path at all. Enumerate
  the channels first and report the sensitivity across them; a single-channel count is not evidence.
  A cost claim with no measurement behind it is how the reference audit started, and it was wrong.
- **The cost model, because every other bullet here follows from it.** Cost is accumulated context
  multiplied by turns, and inside one unbroken block it is quadratic - each turn re-reads everything
  before it. Cached input dominates the bill; the words the agent writes are a minor term. Two
  consequences worth stating outright: **trimming prose is not a cost lever** and neither is chat
  language, so do not pay for either in clarity; and a session that never resets is the expensive
  thing, however tidy each individual turn looks.
- **Session boundaries are the primary lever, and the agent cannot pull it alone.** An agent cannot
  execute its own context reset - that is a harness command the human types - so any design that
  assumes self-reset is unbuildable. What an agent *can* do is stop at a threshold and hand back a
  resume handle. Build the halt, not the reset.
- **For an unattended batch, make the PROCESS boundary the reset.** The halt above still depends on an
  agent noticing a threshold and on a human restarting it afterwards. A driver script outside the session
  removes both: it takes the next work item off the queue, runs it in a **fresh headless process**, and
  repeats however that run ended - so every item starts on an empty context and the reset cannot be
  forgotten, which is exactly what a self-imposed halt cannot promise. Measured on the reference machine
  before such a driver existed, **83% of a week's usage was spent above 150k of carried context** - the
  shape an endless interactive loop produces by construction. Choose the model per item rather than fixing
  it for the whole run, and let several instances run at once; the lock queue in
  [DEVELOPMENT.md](DEVELOPMENT.md) §10 already keeps them off each other. Prefer the driver for anything
  left running unattended, and keep the interactive loop for work a human is watching.
- **Report context as a magnitude, not as a fraction of the window.** On a large window a percentage
  hides the cost at exactly the moment it peaks; band the warning by whichever of absolute size and
  fill fraction is worse, so a small window is not silently exempt.
- **Route models in two tiers: judgement and procedure.** Draw the boundary at "would a merely
  plausible answer be wrong here" - design, diagnosis and review are judgement; mechanical
  transformation, formatting and repetition are procedure. Keep the exotic tiers manual. And verify
  how routing is actually applied in your harness before relying on it: declaring a model in a
  command's frontmatter did not route anything in the measured corpus - every invocation kept the
  session model.
- **Route a subagent to a tier deliberately - an unpinned spawn is not free.** A harness's built-in
  general-purpose agent has no definition file, so it **cannot carry a model pin at all**: it takes the
  session's default, which is the most expensive tier. The remedy is therefore not "pin the agent" but
  "name the tier at the call site, or route through a purpose-defined agent that already pins one".
  Mechanical work - search, lookup, doc reading, running a gate and reporting its verdict - names a light
  tier; the expensive tier is for deep design and for writing code. And give every project-defined agent
  an explicit pin, for the same reason a script lists its exit codes: the default is invisible, and
  nobody audits an invisible default. **No saving is claimed.** What is measured, on one machine's mined
  telemetry over 2026-08-03..2026-08-17 (1 150 sessions, ~54 700 requests): the unpinnable built-in was
  the most-spawned subagent type at **182 spawns in 14 days**, and output tokens split **34.29 M on the
  expensive tier against 7.13 M on the mid tier**, 82.8% on the expensive one. That those spawns are what
  carried the 82.8% is a **deduction, not a measurement** - the miner records a spawn's type and a
  message's authoring model separately and never correlates the two. The earliest honest re-measurement
  is a fresh mining pass after this rule has been live; the telemetry itself is a local, repeatable mining
  run against a transcript store outside any repository, not committed history.
- **Read a large file with an explicit range, first time.** The blind whole-file read of a file you
  have not located anything in yet is the single largest avoidable context cost. Locate with one
  search, then take one window wide enough to cover it - iterative probing costs more turns than it
  saves context. This one is worth **enforcing as a hook rather than stating as a rule** (§5), and any
  such hook needs an unconditional escape hatch: an explicit re-issue carrying a range must always
  pass, because auditing an implementation end to end is legitimate work.
- **Put the context warning where the human can act on it - at prompt submit, not only in the
  statusline.** A statusline band is an advisory, and an ungated advisory performs the way every other
  ungated rule does: measured on the reference machine, the median request carried 215k tokens against
  a 28.7k floor, so roughly 186k of a typical turn was replayed conversation, and 29% of requests were
  past 300k - all of it while the statusline was already printing the number and marking the band. A
  prompt-submit hook that reads the tail of the session transcript, recovers the last request's token
  total and injects a threshold warning costs ~40 tokens on the turns where it fires and nothing on the
  rest. Set the thresholds **above** the median: a warning on every second prompt trains the reader to
  ignore it.
- **A hook that spawns a shell on every tool call must pre-filter in the harness's own shell first.**
  Starting PowerShell costs 170-250 ms on Windows, and a guard wired to a frequent tool pays it on every
  call including the large majority it will wave through. Test the payload cheaply for the condition
  that could possibly trip the guard, and spawn the interpreter only on a match - in the reference case
  that skipped ~89% of the spawns and changed no verdict. The rule generalises: the pre-filter may only
  skip calls the real check would have allowed.
- **Audit installed plugins, MCP servers and connectors by measured usage, not by intent.** They are
  paid for on every session - process memory, startup, and their descriptions in the system prompt of
  every request. Count actual invocations over a few weeks before keeping one: in the reference audit
  four plugins and two connectors had zero calls in three weeks while each session still started their
  processes. Removing them is small next to session hygiene, so do it for the tidiness, and do not
  mistake it for the fix.
- Prefer an inline lookup over spawning a subagent for a single fact (a few targeted tool calls).
  Reach for a subagent when the work is a real fan-out or would flood context with raw output.
- Offload raw artifacts (logs, captures, dumps) to `temp/<ticket>/` instead of holding them in the
  conversation.
- Never run two heavyweight jobs that collide (e.g. two builds) - serialize via the project's advisory
  lock (DEVELOPMENT §10).
- Give a subagent only the tools it needs; don't hand UI/emulator automation tools to an agent that
  only reads code. In particular, **disable a subagent's MCP tools unless it must drive the UI/emulator** -
  each MCP-enabled agent can spin up its own server process, so a read-only agent with MCP on is pure
  overhead.

## 4. Persistent memory

- Agents keep a **file-based memory** (reference layout: `.claude/agent-memory/<agent>/` with a `MEMORY.md`
  index pointing at per-topic files). **Committed vs per-user is a per-project choice:** some repos commit
  `.claude/agent-memory/` so it is project-scoped and team-shared through git; others keep the agent's
  memory in a per-user store outside the repo (local-only). The discipline below is identical either way -
  only the home differs.
- **Save** durable things: the owner's profile and preferences, corrections *and* confirmed-good
  approaches (with the *why*), ongoing project context not derivable from code, and pointers to
  external systems.
- **Don't save** what the code/git already tells you: paths, structure, conventions, who-changed-what,
  one-off fix recipes, or anything already written in the project's rules file.
- Memory is point-in-time. On any conflict between memory and the live tree, **trust the observation**
  and update/remove the stale memory.
- **Budget the always-loaded index, and enforce the budget mechanically.** Only the index is billed on
  every turn; the topic files cost nothing until opened, so the index is the only part that needs a
  ceiling - and a hand-run cleanup does not hold, it regrows within the week. Give the index a target
  and a ratchet that refuses growth. The restatement ban above is part of this: a memory that repeats
  the rules file bills the same instruction twice per turn, forever.
- **Expire memory by work-item liveness, not by age.** A memory anchored to a ticket that no longer
  exists is dead weight; a three-month-old trap that cost real turns to discover is not. Prune by
  "never opened" and by dead anchor, and flag a memory whose named paths have disappeared - that one
  guards trust rather than bytes, since a memory naming a vanished file will eventually be believed.
- Memory is **written far more often than it is read**. Before writing, ask whether a future session
  would open this file - most of the corpus never is.

## 5. Rules file & skill routing

- Each repo carries an agent rules file at root (reference: `CLAUDE.md`, with a parallel `AGENTS.md`
  for non-Claude agents; import order defined, stricter wins). It is the authoritative operating
  manual - these Unified Rules are its cross-project backbone.
- Repetitive workflows are **named skills / slash-commands** (build, release, spec lifecycle, doc sync,
  log analysis..) so a routine has one canonical procedure instead of ad-hoc reinvention. Author a new
  rule/gate/skill only after observing the failure it prevents; keep it minimal and trigger-focused.
- **Gate it or compress it - prose in a rules file is not enforcement.** Measured across a month of
  this portfolio's sessions: rules with a mechanical gate held at **~99%**; the same rules stated only
  as prose held at **1-8%**. So a rule that matters earns a gate, and a rule that does not is compressed
  to one line plus a pointer. The corollary is the part that bites: **an unenforced rule is not
  neutral** - it teaches that the rules file is optional, and that lesson transfers to the rules that
  do matter.
- **The number that settles "rule or hook" arguments: 22%.** The advice to read a file with an explicit
  range ships in the built-in tool description on literally every turn, and compliance measured **22%**.
  Advice the model is already reading, and still mostly not following, is the ceiling for what more
  prose can buy you. If a behaviour is worth having, block it at the tool call.
- **A hook has more verdicts than block and allow - and refusing is rarely the best of them.** The
  preference order: **correct the input where the correct input is knowable; refuse only where no correct
  input exists.** A block cannot fix and retry - it can only cost the caller a round trip and hope they
  choose better the second time. Measured on the reference machine: a blocking uncapped-read guard fired
  **381 times in one week**, and **31.8% of those blocks were answered by re-issuing the same read with an
  explicit limit of 1500+** - the whole file anyway. No context saved, a turn spent. That generalises to
  every guard whose objection is "your parameters are wrong" rather than "this call must not happen". Two
  mechanics, both established by probe rather than guess: a rewrite must carry the **full** input object
  and not just the changed field, and `additionalContext` reaches the model while a permission-decision
  reason does not. And a rewriting hook must **fail open harder** than a blocking one - when it errs it
  corrupts what the model reads, rather than merely gating a call. The full verdict vocabulary, the
  post-call observe shape whose correctness is structural rather than heuristic, and the turn-refusing
  `Stop` shape live in [`hooks/`](../hooks/README.md).
- **A size-tier ordering written as prose does not route anything - put the nudge on the prompt-submit
  event.** A project documented a smallest-first command ladder in its always-on rules file: a
  micro-task command, then a fast-fix command, then the full pipeline. Measured across its whole
  transcript corpus: **434 slash-command invocations, of which the micro-task tier 0 and the fast-fix
  tier 2, against 91 + 44 + 15 for the pipeline commands.** The cheapest tier had not been chosen once
  in a month - the same 1-8% ungated figure as above, observed on a rule that was brand new. The
  remedy is an event, not a paragraph, and the event is `UserPromptSubmit`, **because routing is
  decided the moment the owner types**: match the prompt against a short, high-precision micro-task
  pattern list, veto on a real-work list, drop anything past a length ceiling, and emit
  `additionalContext` naming the cheap tiers. Keep it advisory and **always exit 0** - a false fire
  that refuses a prompt costs more than the miss it prevents. Measured is the failure and the shape;
  no saving is claimed, because the first such hook went live with no post-change window behind it.
- **Same event, opposite verdict - write down which question you are asking.** A *context-pricing*
  hook on that same `UserPromptSubmit` was killed as timing-blind: it reads accumulated context, and
  that tax accrues inside autonomous blocks where no prompt is ever submitted, so the event misses
  exactly the case that costs. Routing is the inverse - the decision genuinely happens at prompt
  submit, so the event is the right one. Record the boundary wherever a hook is refused; otherwise the
  refutation gets reused to kill the hook it does not apply to.
- **The canon now ships the hooks it asks for - do not rebuild them per project.** Every "enforce this at
  the tool call" clause in these docs has a working implementation in the plugin's
  [`hooks/`](../hooks/README.md): the impossible-in-Bash family, batched into one guard
  ([GITHUB_INTERACTION.md](GITHUB_INTERACTION.md) section 6), the uncapped-large-read rewriter and the
  context-size warning (section 3 above), and the micro-task rung nudge (the bullet above). They arrive
  with the plugin, so a new machine or a fresh checkout is covered without setup. A project that already
  wired one by hand should drop its own registration rather than run it twice - **and verify the installed
  plugin cache, not the marketplace clone**, because until the cache carries the script the hand-wired
  registration is the only thing making it live, and removing it "because the plugin has it now" silently
  disarms the guard. A project that needs a behaviour the canon does not ship should propose it here rather
  than keep a private copy - a hook living in one repo protects one repo.
- **Registering, removing or re-registering a hook requires editing the hook inventory in the same
  change**, and a gate fails when something registered is missing from it. A hook is invisible by
  construction - it fires inside a tool call nobody is reading - so an undocumented one is
  indistinguishable from a bug in the tool. The inventory is a table with a fixed verdict vocabulary,
  parsed from the table alone and never from the surrounding prose, since script names appear in prose
  too and a loose parse turns every mention into a phantom entry. Two limits keep such a gate honest:
  find the table by its **heading**, not by a filename, and compare in **one direction only** - a row the
  gate cannot match is not a failure, because a hook registered per-machine is real and live and the gate
  cannot read that registration. Judge each home by what is readable, and degrade rather than guess.
  **Test the registered pre-filter, not only the hook**: a pre-filter that matches nothing leaves a
  correct hook that simply never runs, and it looks exactly like a hook that was never needed.
- Prefer **a skill loaded on demand over a rule read on every turn**, and one method that travels over
  ten copies of a script. A command or skill body is injected in full and stays for the rest of the
  session, so a large one is paid for long after the paragraph that mattered - split it into a driver
  plus a reference the driver opens by name when a stated condition holds.

## 6. Documentation-context loop

- At task start, at any material scope change, at each phase boundary, and before the final response,
  **consult the project's document registry** for the touched product area and state which records are
  affected vs unchanged (reference: `docs/DOCUMENT_REGISTRY.jsonl`). A registered document that changes
  is re-validated by its tool. This keeps docs from silently drifting out of sync with the work.

## 7. Communication

- Match the owner's language and tone (see [AUTHOR.md](AUTHOR.md)): the owner's language in chat,
  English in code/docs/commits; dry and concise; no trailing "what I did" summary - the diff speaks.
- **Never prefix a reply with a clock time.** The model has no clock, and the one signal it ever had - a
  prompt-submit time injection - is stamped once per owner message, so it goes stale within minutes of any
  autonomous run. Measured on the reference repo, the printed time was wrong far more often than right,
  and paid tokens for being wrong. Print a real time only when it carries information *and* comes from a
  command that just ran: a build verdict, a log line, a hand-off. This supersedes the earlier rule to
  timestamp from the prompt.
- **Brevity is a mode the owner asks for, not a saving.** When the owner asks for terse output - "кратко",
  "be brief", `/caveman` - load the `caveman` skill: it compresses prose only and carries the
  never-compress list (security warnings, destructive confirmations, ordered steps, every exact string).
  Trimming prose is not a cost lever (see the cost model in section 3), so brevity is never a reason to
  skip a check or drop a gate's reason.
