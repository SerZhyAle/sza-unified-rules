# Agent-rules snippets

## Area rules, for `AGENTS.md`

Add this where the repository has `.claude/rules/` files ([AI_USAGE.md](../rules/AI_USAGE.md) section 5):

> **Area rules.** The detail behind `CLAUDE.md` lives in `.claude/rules/*.md`. Only Claude Code loads those files by itself. Every other agent opens them by hand: each file starts with a `paths:` list, and before the first edit, review or command in a matching area you read the whole file. The table in `CLAUDE.md` names them.

## Product command line

When the repository has a `docs/cli-commands.json` or `docs/cli-commands.<program>.json` manifest,
copy this line into its authoritative agent-rules file, replacing `<executable>` with the product's
command name and naming each program where there is more than one:

> Product commands: read `docs/CLI.md` and run `<executable> commands --json` before driving the product's window or writing a one-off script.
