# templates

Files a project copies into itself when it adopts the canon. Copy, then fill against the live tree - these are
starting points, not render targets, so the copy is edited freely afterwards.

| File | Copy to | Filled by |
| --- | --- | --- |
| [.sza-canon.json](.sza-canon.json) | the target repo's root | the [adopt-canon](../skills/adopt-canon/SKILL.md) skill |

## The stamp

`.sza-canon.json` is the one machine-readable record of how a repo relates to the canon. It answers, in one
place, what every other skill would otherwise have to re-derive by guessing:

- **`canon`** - which canon version was adopted, the digest of the rule docs at that moment, the date, the
  consumption model (`reference` or `mirror`), and the contrib record. The digest covers the **rule docs
  only** - not `README.md`, not `contrib/` - so one project's record changing can never mark every repo stale.
- **`role`** - `product`, `canon-home`, `portfolio`, or `internal`. Decides which surface checks apply at all.
- **`overlay`** / `shapes` / `editions` - exactly one overlay, unless the repo genuinely ships editions.
- **`versionShape.tagRegex`** - taken from the release script's own validation regex or from CI, **never from
  prose**. `null` when the repo has no tags. `editionTagPrefixes` lists any tag prefix on its own clock;
  getting it wrong makes the version check fail on a perfectly good repo.
- **`ledgerShape`** - `1` root Keep-a-Changelog, `2` dev-log, `3` structured inventory (name it in
  `ledgerFile`), `4` no ledger + auto-generated release notes, `"none"` when the repo ships nothing.
- **`channels`** - only channels with a committed manifest folder.
- **`site`** - the tree Pages actually serves. Confirm with `gh api repos/<owner>/<repo>/pages`; never assume
  root and `docs/` are meant to match.
- **`privacy`** - the hosted page. The zero-data carve-out needs no site *and* no sensitive access; a
  local-but-sensitive tool (keyboard hook, clipboard, capture) hosts a privacy page anyway.
- **`byteIdenticalPairs`** - file pairs a repo maintains identical by hand, so the gate can enforce what was
  previously only prose.
- **`vendorAllow`** - tracked binary paths that are vendored tooling rather than build output.
- **`exemptions`** - each with a check id, a reason, and an `until` date where it is temporary.
