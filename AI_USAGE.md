# AI Usage - how agents work on these projects

The operating contract for any AI agent (Claude Code and siblings) working in this portfolio. It is the
*behaviour* layer; [DEVELOPMENT.md](DEVELOPMENT.md) is the *code* layer they produce. The fuller public
distillation lives in the **universal-agent-kit** repo - this file is the portable subset every project
shares. Reconciled against the portfolio; per-project records in `contrib/`.

## 1. Operating principles

- **Autonomy by default.** Run searches, builds, catalog/spec queries, and device/CLI chores without
  asking. Flag blockers up front. Background long jobs (full builds, test suites, device sweeps) rather
  than foreground-waiting, and keep working meanwhile.
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

## 3. Cost & parallelism discipline

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

## 5. Rules file & skill routing

- Each repo carries an agent rules file at root (reference: `CLAUDE.md`, with a parallel `AGENTS.md`
  for non-Claude agents; import order defined, stricter wins). It is the authoritative operating
  manual - these Unified Rules are its cross-project backbone.
- Repetitive workflows are **named skills / slash-commands** (build, release, spec lifecycle, doc sync,
  log analysis..) so a routine has one canonical procedure instead of ad-hoc reinvention. Author a new
  rule/gate/skill only after observing the failure it prevents; keep it minimal and trigger-focused.

## 6. Documentation-context loop

- At task start, at any material scope change, at each phase boundary, and before the final response,
  **consult the project's document registry** for the touched product area and state which records are
  affected vs unchanged (reference: `docs/DOCUMENT_REGISTRY.jsonl`). A registered document that changes
  is re-validated by its tool. This keeps docs from silently drifting out of sync with the work.

## 7. Communication

- Match the owner's language and tone (see [AUTHOR.md](AUTHOR.md)): the owner's language in chat,
  English in code/docs/commits; dry and concise; no trailing "what I did" summary - the diff speaks.
- Timestamp replies with the local time provided in the prompt.
