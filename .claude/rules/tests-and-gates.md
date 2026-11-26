---
paths:
  - "tools/tests/**"
  - "hooks/tests/**"
  - "tools/check-*.ps1"
  - "tools/docs/**"
  - "tools/harness/assert-portable.ps1"
---

# Tests and gates

Moved verbatim from [CLAUDE.md](../../CLAUDE.md) on 2026-11-25. The always-on rules stay there, the 5 s line included ("Working here").

- **The tiers have one home: [tools/tests/tiers.json](../../tools/tests/tiers.json)** - one row per gate or suite with its tier
  (`fast` is 5 s or less, `release` is above), the measured seconds, the date and what it covers. A suite with no row
  is release tier, unmeasured. [tools/tests/run-tier.ps1](../../tools/tests/run-tier.ps1) reads it: `-List` prints every row
  and every unlisted suite, `-Suite <name>` runs one fast suite and refuses any other, `-Tier fast` runs every fast row,
  and `-Suite <name> -Measure` is the owner-named run that times a suite and writes its row, `lastPass` included on a
  pass. `-Stale` lists the release suites whose test file or covered `paths` changed after `lastPass`, or that have no
  recorded pass; it runs no suite, and `deploy.ps1 -DryRun` prints it as information. A new release row gets its
  `paths` by hand.
- **There is no case filter - "one test" is one file.** Each `tools/tests/*.tests.ps1` is a standalone script that
  prints a PASS or FAIL line per case and exits 1 on any failure; its header comment lists the cases and says what it
  touches (most build throwaway repositories and a throwaway portfolio root, and take `-KeepScratch` to leave them for
  inspection). A header never states a tier or a time - the registry does.
- **`tools/check-compliance.ps1` judges an adopting repository, not this one** - it is run from that repo
  (`-Strict`, `-Json`). Here the stamp's `role: canon-home` switches the surface and overlay checks off.
- **Editing `tools/check-compliance.ps1`**: a new check earns its place only if it is mechanically decidable
  in an arbitrary repo, offline, with a near-zero false-positive rate. Verify a candidate against the real
  repos before shipping it; a check that cries wolf gets disabled, and then nothing is enforced.
