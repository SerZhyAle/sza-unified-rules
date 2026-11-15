---
name: app-commands
description: Discover and use a product's command line before driving its window or writing a script. Use when asked to list product commands, control an app from an agent or script, inspect an app's status, or use its CLI instead of clicks. Also use for Russian requests such as "какие команды есть у программы", "управляй приложением из скрипта", "инструменты приложений", "не кликай по окнам".
---

# Use a product's commands

Before driving a product's window or writing a one-off script around it, list its commands and use an
existing command when it does the requested work. This also applies when the product is in another
registered repository: the portfolio lister finds commands without opening that repository's source.

## Discover

From any directory, resolve the installed `sza` plugin root and list the registered products:

```powershell
$sza = if ($env:CLAUDE_PLUGIN_ROOT) { $env:CLAUDE_PLUGIN_ROOT } else {
    $record = Join-Path $env:USERPROFILE '.claude/plugins/installed_plugins.json'
    if (Test-Path -LiteralPath $record) {
        ((Get-Content -LiteralPath $record -Raw | ConvertFrom-Json).plugins.'sza@sza-unified-rules' |
            Sort-Object lastUpdated -Descending | Select-Object -First 1).installPath
    }
}
if (-not $sza) { throw 'The sza plugin root is unavailable; locate the plugin checkout or cache.' }
pwsh -NoProfile -File "$sza/tools/harness/portfolio/app-commands-list.ps1"
```

Pass `-Project <repo-key>` to narrow the list, or `-Json` for data. `OK` lists each verb, summary,
risk and cold-start mode. A label `<repo-key>/<program>` identifies another program in the same
repository. `NONE` means no manifest, `INVALID` means a manifest could not be trusted, and `MISSING`
means the registered folder is absent; none of these says a running executable has no commands.

For a product, read its `docs/CLI.md` and `docs/cli-commands.json`; another program in the repository
has its own `docs/cli-commands.<program>.json`. Run the target executable's `commands --json` to see
its embedded manifest. For a window executable, follow the guide's instructions for waiting and
capturing output, or use its console companion where documented. If the lister or registry is
unavailable, inspect these interfaces directly. Use the command's synopsis, arguments, risk,
cold-start and response, rather than guessing from its name. See APP-COMMANDS rules 13, 18 and 20
and section 7 item R for the contract.

## Execute

- The running product wins when it disagrees with the repository manifest. `commands --json` reports
  the executable's own copy; an older first instance can still refuse a verb, so respect the actual
  response. Do not claim a command succeeded on a timeout or a refusal.
- For every risk other than `safe`, including a missing or unknown risk, the agent requires the person's
  setting to be on. The agent never enables it, through the UI, configuration, an alias or any other
  route. If it is off or cannot be established, leave it off and report what is needed. This agent
  policy also covers `forward: never` commands, which APP-COMMANDS section 7 item C.4 does not require
  a product to gate by the setting of rule 13.
- If there is no usable command for the requested work, use another appropriate method. A missing or
  invalid manifest is not permission to treat an unclassified command as `safe`.
