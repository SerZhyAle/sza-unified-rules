# tools/memory - three scopes for the agent's memory

Claude Code keeps an agent's file memory per project (`~/.claude/projects/<project key>/memory/`). A lesson learned in
one repository therefore stays there, and the next repository learns it again: the audit that started this folder
found the same Bash backslash trap written down in four projects and the same winget fork workaround in four more.

[memory.ps1](memory.ps1) adds two wider scopes outside every repository and does their mechanics. Which scope a lesson
belongs to stays the agent's judgement, made when it writes the memory; the script moves files, retires duplicates and
keeps the indexes true.

| Scope | Where | How it reaches a session |
|---|---|---|
| `global` | `~/.claude/memory/<slug>.md`, index `~/.claude/memory/MEMORY.md` | an `@~/.claude/memory/MEMORY.md` import in the user's own `~/.claude/CLAUDE.md` - every session, adopter or not |
| `type:<tag>` | `~/.claude/memory/types/<tag>/<slug>.md` + `type.json` | the plugin's [session-start hook](../../hooks/session-start.ps1) injects the index of every type whose `type.json` matches the repo's `.sza-canon.json` |
| `project` | the session's own memory folder | Claude Code itself |

`type.json` holds a title and a `match` object; a repository matches when any listed value appears in its stamp:

```json
{ "title": "Windows products shipped through winget and the Microsoft Store",
  "match": { "channels": ["winget", "msstore"] } }
```

The keys are `overlay`, `channels`, `site` (the stamp's `site.kind`) and `role`. The memory root is
`SZA_MEMORY_ROOT`, else `<claude home>/memory`, where the claude home is `CLAUDE_CONFIG_DIR`, else `~/.claude`.

Every memory says its scope inside its metadata block:

```markdown
---
name: winget-submit-without-fork-sync
description: one line, the trigger for recall
metadata:
  type: reference
  scope: type:windows-store
---
```

## Commands

```powershell
pwsh -NoProfile -File tools/memory/memory.ps1 audit                     # duplicates across folders, index drift, indexes over 8,000 chars, no-scope counts, old *-state memories
pwsh -NoProfile -File tools/memory/memory.ps1 types -Cwd P:\some\repo   # which types match that repository
pwsh -NoProfile -File tools/memory/memory.ps1 index -All                # resync every MEMORY.md with its folder
```

`promote` takes several paths, so call it in-process - `pwsh -File` hands an array over as one string:

```powershell
& tools/memory/memory.ps1 promote -Scope global -Name <slug> -Path <file>, <file>
```

- When `<slug>.md` does not exist at the target, the first path is moved there and the others are retired as
  duplicates; when it exists (written by hand as the merged memory), every path is retired.
- Retired files go to `~/.claude/memory/.retired/<project key>/`, never deleted.
- Each touched index is resynced and the target's `scope` line is set. Running it on a file already at its target
  only sets the scope line.

`index` keeps every existing line of a present file as written - including nested relative links such as
`[State index](state/INDEX.md)` without auto-adding every file inside `state/` - drops lines of missing files
and duplicates, and appends a line built from the frontmatter for each unlisted top-level file. `audit` checks
nested links for existence, flags any `MEMORY.md` over 8,000 characters, writes nothing, and exits 0.

## Routing rule

The rule an agent follows when it saves a memory is in the user's global `CLAUDE.md`, not here: decide the scope first,
read the global or type index for a memory that already covers the lesson and extend it, and file a canon ticket when
the lesson is a rule of process the canon should carry - the memory is retired once the canon ships it.
