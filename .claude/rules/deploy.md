---
paths:
  - "deploy.ps1"
  - "CANON_VERSION"
  - "tools/bump-canon-version.ps1"
  - ".claude-plugin/**"
  - "docs/releases/**"
  - "tools/tests/deploy-*.tests.ps1"
  - "tools/harness/releases/**"
  - "tools/harness/spec_catalog/ship-package.ps1"
---

# Deploy and delivery

Moved verbatim from [CLAUDE.md](../../CLAUDE.md) on 2026-11-25. The always-on rules stay there, "deploy.ps1 without -DryRun is the owner's tool" included; "here" below means that file.

- **The deploy names all four fast checks** (from 2026-11-11): after `check-rules.ps1`, which blocks, it runs
  `check-contracts.ps1`, `check-documents.py` and `assert-portable.ps1` and prints each exit code, or `unavailable` with the
  reason when one cannot run. Those three are advisory and never change the exit code, so a red one is named at every deploy
  instead of being called "not mine" for weeks. [tools/tests/deploy-fast-gates.tests.ps1](../../tools/tests/deploy-fast-gates.tests.ps1)
  covers it with stubs.
- **The version pair is written by `deploy.ps1`, not by hand.** It calls
  [tools/bump-canon-version.ps1](../../tools/bump-canon-version.ps1) before staging, which is the only writer of
  [CANON_VERSION](../../CANON_VERSION) and of `.claude-plugin/plugin.json` `version`, derived from it:
  `2026.08.18.1` -> `2026.818.1` (semver forbids the leading zero, so the month and day join into one
  numeric identifier). The plugin version is what actually delivers the canon: `claude plugin update`
  compares that number and nothing else - not the digest, not the commit - so a canon change shipped
  without it leaves every consumer on the cached copy of the previous version while `update` reports
  "already at the latest version". `-NoVersionBump` is the way out for a commit that reaches no consumer;
  the deploy also skips the bump on its own when the whole change set is `README.md`, `LICENSE`,
  `.gitignore`, `docs/releases/` or `rules/contrib/history/`. A facts record (`rules/contrib/<project>.md`) is
  read by skills from the plugin cache, so its change raises the version like any other shipped file.
- **The deploy also records the canon's own release ledger** ([docs/releases/RELEASES.md](../../docs/releases/RELEASES.md),
  package `sza`, channel `marketplace`, from 2026-11-17): after bumping the version pair it runs
  `release-ledger.ps1 build` (kind `release`) before staging, and after the plugin-cache check passes (`updated` or
  `current`) it runs `publish -State live` - warning on error and never failing the deploy.
  When the deploy is run without a message, one generated line (`Get-DeployChangeNote` in `deploy.ps1`) is both
  the commit subject and the note of that build row: the ids of the tickets the deploy carries
  (`Get-DeployTickets`: finished ledger rows since the last deploy commit and ids in unpushed subjects, else ids
  in the added diff lines) with the first title; only when no id is found, the subjects of the local commits not
  yet on the remote, the changed rule documents by name, and a count of the other changed paths per top-level
  folder. A line over 72 characters is cut in the subject and carried whole in the commit body. The body also
  holds one `id: title` line per ticket and names the plugin version, so `git log --grep` with a version number
  finds what that version holds. The `publish` row gets the ids as its note. With a message, the subject is the
  message and the build note is its first line.
  [tools/tests/deploy-release-ledger.tests.ps1](../../tools/tests/deploy-release-ledger.tests.ps1) covers it with stubs.
- **The deploy also ships the canon's own release package** (from 2026-11-18, TASK-FLOW rule 16): right after
  `publish -State live`, under the same guard, it runs `tools/harness/spec_catalog/ship-package.ps1 -Version <plugin
  version>` with `SZA_PROJECT_ROOT` pinned to this checkout. The finished rows of the plan are recorded as a
  shipment on their ledger rows, the marker advances, and the `Verified` tickets on neither side whose shipment names
  a version are archived with that reason; `Implemented`, `BlockNeedUserTest` and unproven `Verified` tickets stay in
  the ledger. A problem there warns and never changes the exit code. Case 9 of the suite above covers the call site.
- **The deploy also brings this machine's plugin to the pushed version** (from 2026-10-29): after the push, on `main`,
  when the cache is behind, it runs `claude plugin marketplace update sza-unified-rules` and `claude plugin update
  sza@sza-unified-rules` and checks that the cache reached the version. A failure only warns and prints the commands;
  off `main` it does nothing (the marketplace follows `main`); `-NoPluginUpdate` skips it. Open sessions keep what
  they loaded - restart them. The same step then runs for **ZCode** (from 2026-11-25) when the plugin is installed
  there: its own cache under `~/.zcode`, its CLI inside the app run under `ZCode.exe` as Node (a system Node exits 0
  and does nothing). Only the Claude result gates the release-ledger `publish` step.
  [tools/tests/deploy-plugin-update.tests.ps1](../../tools/tests/deploy-plugin-update.tests.ps1)
  covers both with stubs.
- **This was a manual step until 2026-09-07 and it was missed twice.** The portfolio first ran five canon
  updates against a plugin cache frozen at `2026.07.27`, and no session anywhere loaded them; then, four
  days after that was written down here, `ec00587` shipped three `tools/harness/spec_catalog/` files under
  an already-installed version. Both the deploy and the plugin update reported success each time. The rule
  did not change - only who executes it.
- **A fix under `skills/`, `tools/` or `hooks/` ships the same way, and only that way.** The digest covers
  `rules/*.md` alone, so such a fix marks nothing stale and needs no reconciliation - but a consumer still
  runs the cached copy until the plugin version moves, and a broken skill command left in the cache is as
  invisible as a rule that never arrived.
