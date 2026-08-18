# CLAUDE.md - sza-unified-rules (the canon and its plugin)

Agent rules for working **on** the canon. The canon's own content is in [rules/](rules/README.md) - read it
there; nothing is restated here.

## What this repo is

The single canonical home of the shared SZA conventions, shipped as a Claude Code plugin so the rules arrive
as auto-discovered skills in every session instead of as documents at a local path. See
[README.md](README.md) for the why and the install.

**Consumption model: this repo IS the source** - neither *reference* nor *mirror*, the two models a consuming
project picks between ([rules/README.md](rules/README.md)). "Never edit the canon from a project session"
does not apply here; this is where fixes land. It applies everywhere else.

## Working here

- **Gate before committing anything under `rules/`:** `pwsh -File tools/check-rules.ps1` (exit 0 required).
  It validates internal links, section numbering, `§` references and the house text style.
- **Changing a rule doc changes the digest**, which marks every adopting repo stale. That is intended - but
  bump [CANON_VERSION](CANON_VERSION) in the same commit so the staleness ladder can tell a minor
  reconciliation from a hard re-adoption.
- **Bump `.claude-plugin/plugin.json` `version` in that same commit**, derived from `CANON_VERSION`:
  `2026.08.18.1` -> `2026.818.1` (semver forbids the leading zero, so the month and day join into one
  numeric identifier). This is what actually delivers the canon: `claude plugin update` compares that
  number and nothing else - not the digest, not the commit - so a canon change shipped without it leaves
  every consumer on the cached copy of the previous version while `update` reports "already at the latest
  version". That is not hypothetical: the portfolio ran five canon updates against a plugin cache frozen
  at `2026.07.27`, and no session anywhere loaded them.
- **Editing a skill**: the SKILL.md body is what loads on trigger; heavy payload goes in `references/`
  beside it. Keep the frontmatter `description` written in the words the owner actually uses to ask for the
  task, in both languages where that is how the request arrives - it is the trigger, not a summary.
- **Editing `tools/check-compliance.ps1`**: a new check earns its place only if it is mechanically decidable
  in an arbitrary repo, offline, with a near-zero false-positive rate. Verify a candidate against the real
  repos before shipping it; a check that cries wolf gets disabled, and then nothing is enforced.
- **`rules/contrib/<project>.md`** is the per-project record. A project session may append its own record
  here and nothing else.

## Layout facts

- `.claude-plugin/` holds **both** `marketplace.json` and `plugin.json` - the repo is its own marketplace,
  with the plugin at `source: "./"`.
- Paths inside skills resolve through `${CLAUDE_PLUGIN_ROOT}` at run time and through relative links
  (`../../rules/...`) when read as files. Keep both working: a skill is read as a document *and* executed.
- `rules/` was moved here from the `sza.od.ua` site repo with its history intact (`git subtree split`). The
  site repo keeps a pointer, not a copy.

## Language

The portfolio language split has one home: [AUTHOR.md](rules/AUTHOR.md) "Language". The only repo-specific
note is that a Russian phrase inside a skill's `description` frontmatter is **trigger data the matcher needs**,
not prose - so it is not an exception to that rule, it is not prose at all.
