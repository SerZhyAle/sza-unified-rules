# HARNESS-PROFILE - pointer

| Field | Value |
| --- | --- |
| Contract | `HARNESS-PROFILE` |
| Version | 0.23, draft; source reader verified at 0.13; rules 9 to 12 and 14 to 17 implemented, rule 8 in part |
| Home | the shared contracts catalog, domain `rule-adoption/` (the path is in [CLAUDE.md](../../CLAUDE.md)) |
| Role | **consumer**, and the schema's owner. Each repository running the harness writes its own profile |

## What this repo must do to stay conformant

- `tools/harness/_profile.ps1` is the only reader and the home of the defaults. A default changed there
  changes what an absent key means in every repository running that harness - which makes it a contract
  change (rule 2), not a tidy-up.
- **The merge rule is binding**: objects merge key by key, arrays and scalars replace. An empty array in a
  profile means "none", never "use the default" (rule 3).
- **Lock domain ranks are acquired in order** and reordering them is a deadlock (rule 5).
- Dev-log defaults, overrides and disabled tools follow rule 2 and the 2026-10-17 amendment;
  `tools/tests/contract-sync.tests.ps1` exercises all ledger shapes without altering user ledgers.
- Version dispatch follows the 2026-10-23 amendment before merge. Legacy absence and `"1"` remain
  readable; higher MINOR and unknown keys are tolerated; unsupported MAJOR, null and malformed carriers
  refuse cleanly. Catalog reader vectors and all existing merge/dev-log regressions are replayed.
  Installed-consumer delivery remains unverified.
- The agent fields of `runner.instances.<name>`, the per-instance `promptTemplate` and `complexityModels`
  and the optional `portfolio` override object are 0.14 (the 2026-10-27 amendment, section 3 rules 8-10);
  every key is optional and the wire stays 1.0. Read against the code on 2026-11-15: **rule 8 holds for the
  fields the repository runner reads** - `command`, `argsTemplate`, `headlessMatch` and `effortByModel` resolve
  the pass's agent record, then the instance, then the shared value, then the shipped default
  (`Get-InstanceSetting` in `batch/run-spec-queue.ps1`, which calls `Get-SzaInstanceSetting` in
  `batch/_instance-settings.ps1`), and the `{effort}` substitution is known to it - and the portfolio reads the
  other agent fields from the registry's record, so a per-repository runner ignoring the rest is the allowed
  case. **Rule 9 is implemented (S0078, 2026-11-15)**: `promptTemplate` goes through the same chain, and the
  level map is chosen by it (`Get-SzaComplexityModel`) - the instance's own `complexityModels`, else
  `runner.complexityModels`; an instance map owns the whole map, so a level it omits is no declaration, not the
  shared answer. The shared paths were already declared in the default tree, so rule 4 held. The instance's
  fixed `model` of rule 8 is still not read by the runner. **Rule 10 is implemented (S0078, 2026-11-15)** as
  the resolver the portfolio calls - `Resolve-PqConsoleSetting` and `Resolve-PqAnalysisThreshold` in
  `portfolio/lib/registry.ps1`, order profile, registry, built-in default, a value that is not a number (a
  positive one for the minutes) skipped - and the default tree declares `portfolio` with `$null` values so it
  masks nothing. **No dispatcher code reads the registry's console or analysis values yet** (the registry only
  defaults and validates them; the gap is S0082's), so the override changes no behaviour until a reader calls
  the resolver. The reader tolerates additional profile keys through its unknown-key merge and reads instance
  fields through `Test-SzaHasProperty`. A change to `_profile.ps1` regenerates the reader vectors
  (`tools/tests/export-contract-vectors.ps1`), because the file is fingerprinted in their manifest; that
  regeneration is S0079, a release item. Fast cases: `tools/tests/instance-settings.tests.ps1` (rule 9) and
  `tools/tests/portfolio-profile-override.tests.ps1` (rule 10).
- `commands.compileCheck` is optional and empty by default (rule 11, the 2026-11-11 amendment): the
  repository's declared compile-only command, run once by an unattended pass that edited compiled source
  before it sets `Implemented` or `BlockNeedUserTest` (`Testing & QA` section 2, its one exception).
  Absent or empty means none is declared - the pass writes that into its note instead of running or
  inventing a command. It merges by key beside `commands.statusCommands` and `commands.aliases`, and the
  generated reader vectors cover both the declared and the absent case.
- `runner.effortByModel` is optional (rule 12, the 2026-11-11 amendment, S0041): a map from a model alias
  to the reasoning effort a queue child launches with - shipped default haiku `xhigh`, sonnet `xhigh`,
  opus `medium` (the owner's 2026-09-30 child decision). It resolves instance first, then shared, then
  the shipped default, and applies only where the pass's agent record names no `effort`; a model the map
  does not name launches with no effort. This amendment also changes a shipped default, the first to do
  so: `runner.argsTemplate` now carries `--effort {effort}` after `--model {model}`, and the element is
  dropped with its flag when no effort resolves - so every launch that resolved no effort, and every
  non-Claude agent, still starts exactly as before (verify with the S0041 suite,
  `tools/tests/runner-model-routing.tests.ps1`). Interactive sessions are untouched: the flag exists only
  in the runner's argument vector. A change to `_profile.ps1` regenerates the reader vectors.
- `extraction` is optional (rule 13, the 2026-11-13 amendment): `ledger`, `scope`, `sourceProject` and
  `lagBudgetDays` for a repository that is a product derived from a source product, the rules of the ledger being
  `PORT-LEDGER` 0.1. No key has a shipped default and no shipped tool reads the block yet; when one does it carries
  its own absence default, because `Get-SzaProfileValue` throws on an unknown dotted path by design. `_profile.ps1`
  is unchanged, so the reader vectors are not regenerated by this step.
- `paths.releasesDir` is optional (rule 14, the 2026-11-17 amendment, S0092): the release ledger's folder, shipped
  default `docs/releases` in `_profile.ps1` and in the profile template; `tools/harness/releases/` reads it, and
  `pq releases` reads it from each repository's profile as written. The default was added to `_profile.ps1`, so the
  reader vectors are regenerated at the next release (`tools/tests/export-contract-vectors.ps1`), not in S0092.
- Eight defaults are derived, not fixed (rule 15, the 2026-11-18 amendment, S0122): `paths.journal`,
  `journalArchive`, `burnedIds`, `releaseQueue`, `releaseReady`, `releaseQueueDone`, `grammar.specFileTemplate`
  and `grammar.specFilePattern` follow the profile's `paths.specsDir`, `paths.specArchiveDir` and
  `grammar.ticketIdPattern` (`Get-SzaDerivedDefaults` in `_profile.ps1`, applied by `Get-SzaProfile`); a key the
  profile carries wins, and `paths.probeBaseline` stays fixed. Five readers parse a profile on their own and
  still read the fixed defaults (`portfolio/lib/queue-file.ps1`, `portfolio/lib/ledger-watch.ps1`,
  `portfolio/spec-draft.ps1`, `spec_catalog/block-links.ps1`, the ledger check of `tools/check-compliance.ps1`),
  so a profile drops one of the eight keys only after they call the same function. Fast case:
  `tools/tests/portfolio-profile-override.tests.ps1`. The reader vectors are regenerated at the next release.
- `grammar.legacyTicketIdPatterns` is optional (rule 16, the 2026-11-19 amendment, S0152): the id shapes before the one
  prefix migration of TASK-FLOW 0.37, written only by `spec_catalog/rename-prefix.ps1`. `_profile.ps1` ships it empty;
  `Test-SzaTicketId`, `ConvertTo-SzaTicketNumber`, `Get-SzaTicketIdFragment` and the rule-15 derivation read it.
  Fast case: `tools/tests/rename-prefix.tests.ps1`. The reader vectors are regenerated at the next release.
- 0.23 (2026-11-26, CANONR-0204, rule 17: the optional `runner.passCeiling`, a launch's `minutes` and `usd`) is
  validated by the profile reader and exercised by the `pass-ceiling` suite.
