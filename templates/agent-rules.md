# Agent-rules snippet for a product command line

When the repository has a `docs/cli-commands.json` or `docs/cli-commands.<program>.json` manifest,
copy this line into its authoritative agent-rules file, replacing `<executable>` with the product's
command name and naming each program where there is more than one:

> Product commands: read `docs/CLI.md` and run `<executable> commands --json` before driving the product's window or writing a one-off script.
