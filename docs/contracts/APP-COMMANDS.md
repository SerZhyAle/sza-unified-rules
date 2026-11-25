# APP-COMMANDS - pointer

| Field | Value |
| --- | --- |
| Contract | `APP-COMMANDS` |
| Version | 0.3, draft |
| Home | the shared contracts catalog, domain `app-commands/` (the path is in [CLAUDE.md](../../CLAUDE.md)) |
| Role | **reader of the discovery interface**: `tools/harness/portfolio/app-commands-list.ps1` lists what each registered product offers from its manifests. The owner is `shared` |

## What this repo is, and is not

This repository offers no command of its own and runs no first instance, so rules 1 to 17 (the command line, the
request-response profile, the risk gate, the base verbs) and cases C1 to C20 bind the products that adopted the
contract and do not apply here. What binds the canon is the reader side: rule 18 (the manifest, its members, "a
reader ignores one it does not know"), item R.1 of 0.2 (one manifest per program) and rule 20 (the manifests are
the discovery interface, and a tool that lists the commands of every product reads only those). The canon's duty
beyond that is the one rule 20 gives it: the interface is there to read, and how an agent learns it exists is the
canon's business.

## What this repo must do to stay conformant

- `app-commands-list.ps1` reads `docs/cli-commands.json` and every `docs/cli-commands.<program>.json` of each
  registered repository and nothing else, writes nothing, and lists a manifest of another program as
  `<key>/<program>`. A file whose middle part is not a short lower-case name is not a manifest. It was found on
  2026-11-15 (S0081) that the lister read the main manifest only and so left out the Share Manager's 15 commands of
  `fms-lite`; item R.1 is the rule that asked for the second file.
- The members it reads are `schemaVersion`, `product`, `exe`, `cliVersion` and, per command, `name`, `summary`,
  `risk` and `coldStart`; every other member (`aliases`, `forward`, `audience`, `families`, `environment`, `oneOf`,
  `defaultFor`, `target`, `paged` and the rest) is ignored by rule 18. A manifest with a `schemaVersion` other than 1
  is shown `INVALID`; a risk or cold start the manifest omits prints as `unknown`, which is never `safe`, so a caller
  that gates every class but `safe` (rule 13) errs the cautious way. A value outside the four classes passes through
  as written and is never read as `safe`.
- `check-compliance.ps1` (`SZA-CTR04`) asks for the command-line pointer only for a manifest that describes a
  command line. A manifest that names no `exe` (top level or on a verb) and whose every verb carries a `remote`
  object is a remote-only one (`REMOTE-CONTROL` 0.9 rules 6 and 7) and asks for nothing; an empty or unreadable
  manifest counts as a command line.
- Not shown, by choice and not by rule: `audience: developer` verbs are listed with the others (item D says the
  manifest and `commands --json` carry them always), and `families[]` (item B) is not listed. No manifest of the
  portfolio carries either on 2026-11-15 (the six manifests of five repositories were read for this), so nothing is
  hidden today; the first manifest that uses one reopens the question.

## Evidence

`tools/tests/app-commands-list.tests.ps1`: seven cases, 1.8 s, exit 0 on 2026-11-15 (the seventh covers item R.1).
A direct run over the real registry on the same day listed 95 commands in 6 manifests of 5 repositories, none
invalid. The catalog holds no machine-readable manifest schema and no vector yet (the contract says both are owed),
so no replay was possible.
