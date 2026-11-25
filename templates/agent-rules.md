# Agent-rules snippets

## Delegating stub, for `AGENTS.md`

Use this as the entire body of `AGENTS.md` in a repository whose core contract is `CLAUDE.md` (include the
second paragraph whenever `.claude/rules/` exists, `SZA-RULES09`):

```markdown
Read CLAUDE.md in full; it is the authoritative agent contract and carries the canon pointer; the
stricter file wins. If you are not Claude Code, the canon plugin is not loaded: read
rules/INVARIANTS.md at https://github.com/SerZhyAle/sza-unified-rules first.

**Area rules.** The detail behind `CLAUDE.md` lives in `.claude/rules/*.md`. Only Claude Code loads those files by itself. Every other agent opens them by hand: each file starts with a `paths:` list, and before the first edit, review or command in a matching area you read the whole file. The table in `CLAUDE.md` names them.
```

## Area rules, for `AGENTS.md`

Add this where the repository has `.claude/rules/` files ([AI_USAGE.md](../rules/AI_USAGE.md) section 5):

> **Area rules.** The detail behind `CLAUDE.md` lives in `.claude/rules/*.md`. Only Claude Code loads those files by itself. Every other agent opens them by hand: each file starts with a `paths:` list, and before the first edit, review or command in a matching area you read the whole file. The table in `CLAUDE.md` names them.

## Global project rules (every repository)

Canonical section installed into non-Claude user-level instruction files (`~/.codex/AGENTS.md`,
`~/.gemini/GEMINI.md`, `~/.zcode/AGENTS.md`, `~/.vibe/AGENTS.md`) by `tools/install-agent-rules.ps1`:

<!-- sza-global-rules:start -->
## Project rules (every repository)

- The repository's agent contract is its root `CLAUDE.md`. Read it in full before the first change, even when your tool loads only `AGENTS.md` or `GEMINI.md`. When the repository's own `AGENTS.md` or `GEMINI.md` names a different contract for your tool, follow that file.
- Area rules live in `.claude/rules/*.md`. Only Claude Code loads them by itself. Each file starts with a `paths:` list: before the first edit, review or command in a matching area, read that whole file. The core file's table names them.
- Keep the always-loaded files small: new detail goes into the area rule file, never into `CLAUDE.md` or `AGENTS.md` (budget 20,000 characters, hard limit 40,000).
<!-- sza-global-rules:end -->

## Product command line

When the repository has a `docs/cli-commands.json` or `docs/cli-commands.<program>.json` manifest,
copy this line into its authoritative agent-rules file, replacing `<executable>` with the product's
command name and naming each program where there is more than one:

> Product commands: read `docs/CLI.md` and run `<executable> commands --json` before driving the product's window or writing a one-off script.

A remote-only manifest takes no such line: a product with no command line keeps its remote verbs alone in
the same file (`REMOTE-CONTROL` rule 6), names no `exe` and marks every verb `remote`, so there is no guide
and no executable to point at.
