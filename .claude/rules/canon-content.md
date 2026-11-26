---
paths:
  - "rules/**"
  - "skills/**"
  - ".claude-plugin/**"
  - "memory/**"
  - "AGENTS.md"
---

# Canon content and plugin layout

Moved verbatim from [CLAUDE.md](../../CLAUDE.md) on 2026-11-25. The always-on rules stay there; in the text below "this file" means `CLAUDE.md`.

- **Changing a rule doc changes the digest**, which marks every adopting repo stale. That is intended: a
  differing digest is a warning at any age, and the gate names the rule docs that changed since the stamp was
  written (`canon.docDigests`), so a reconciliation re-reads those and nothing else - neither the version number
  nor the stamp's age decides anything (`RULE-DELIVERY` rule 5). This repo, role `canon-home`, is never stale
  against itself.
- **A rule doc does not grow for free.** `tools/rules-size-budget.json` holds one size line per `rules/*.md`
  (bytes without CR), and `check-rules.ps1` refuses a doc above it: delete as much in the same edit, or raise the
  line with the date and the reason. A new doc gets its line in the same edit. The task-flow contract has the same
  budget in the catalog, `_meta/SIZE_BUDGET.md`, judged by `check-contracts.ps1`.
- **Editing a skill**: the SKILL.md body is what loads on trigger; heavy payload goes in `references/`
  beside it. Keep the frontmatter `description` written in the words the owner actually uses to ask for the
  task, in both languages where that is how the request arrives - it is the trigger, not a summary.
  `tools/check-rules.ps1` judges the frontmatter, and the deploy blocks on it: `key: value` on one line (plain or
  quoted) or a block value, nothing nested, `name` and `description` present, the description 400 characters at
  most. Run it after a skill edit.

- `.claude-plugin/` holds **both** `marketplace.json` and `plugin.json` - the repo is its own marketplace,
  with the plugin at `source: "./"`.
- `.claude/rules/` in this repository applies only to sessions working inside this checkout: Claude Code's
  plugin loader discovers `commands/`, `agents/`, `skills/`, `hooks/`, `.mcp.json`, and `.lsp.json` only, so
  although `.claude/rules/` travels in the plugin clone and cache, consumer sessions ignore it (`claude plugin
  validate .` confirms plugin-root project context files are not loaded into consumers).
- Paths inside skills resolve through `${CLAUDE_PLUGIN_ROOT}` at run time and through relative links
  (`../../rules/...`) when read as files. Keep both working: a skill is read as a document *and* executed.
- `rules/` was moved here from the `sza.od.ua` site repo with its history intact (`git subtree split`). The
  site repo keeps a pointer, not a copy.
- [AGENTS.md](../../AGENTS.md) is the Codex entry point: a delegating stub that sends the agent to this file, plus the
  Codex-only routing bullets. It repeats no command, tier or style rule, so nothing here has a second copy to keep
  in step. `memory/` holds that agent's notes.

- Reports never mention commit, tree or deploy state.
