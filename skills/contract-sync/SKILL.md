---
name: contract-sync
description: 'Sync shared contracts with the catalog. Inventory or migrate copies, write pointers and registry rows, and audit compatibility. Use for a shared format, algorithm, schema, protocol or contract version, or before a boundary release. «контракты», «приведи контракты в порядок», «синхронизируй контракты», «перенеси контракты в каталог», «общий формат с другим проектом», «версия контракта».'
---

# Contract sync - align this repo with the shared catalog

One repo per run. The catalog at `P:\Contracts` is the source of truth; this repository holds
implementations and pointers, never copies.

Canon: [CONTRACTS.md](../../rules/CONTRACTS.md) (the law),
[INVARIANTS.md](../../rules/INVARIANTS.md) item 10,
[PLATFORM_OVERLAYS.md](../../rules/PLATFORM_OVERLAYS.md) "Cross-project contracts" (the coupling shapes
that are *not* contracts).
Catalog: `P:\Contracts\README.md`, then `_meta\RULES.md`, `_meta\VERSIONING.md`, `_meta\REGISTRY.md`.

---

## Step 0 - Read the law before looking at the repo

Read the four catalog pages above. Classify against the definition, not against intuition, or the
inventory turns into a list of every markdown file in `docs/`.

**A contract** is a durable functional solution that outlives one repository: a format, an algorithm with
the constants it is pinned to, a behaviour at a boundary, a user experience at a shared moment, the shape a
document set keeps. **Not** how we develop - repo layout, release mechanics, testing tiers and agent
workflow are the canon's, and they never move into the catalog.

Three questions decide it: does a second implementation depend on this, could it be handed to an outside
developer, would a change here break somebody else. **Two yeses make it a contract.**

## Step 1 - Inventory

Read what you find; do not judge by filename.

- `docs/contracts/`, `docs/specifications/`, `docs/guides/` - anything describing a format, schema,
  protocol, exchange or parity table;
- the strings `CONTRACT`, `schemaVersion`, `canonical vector`, `byte-identical`, `wire`, `frozen`,
  `PARITY` in docs **and** in source comments;
- serializers, parsers, importers, exporters - any code reading or writing what another product also reads
  or writes;
- test fixtures that must stay byte-stable;
- published artifacts other products download: a ZIP, a bank, a catalog, an event stream on stdout;
- user-facing text that exists in more than one product in almost the same words - an install-trust page,
  a permission explanation, an import warning. These are contracts too, and they are the ones nobody
  thinks to look for;
- check scripts and their reports, and the document set itself: the catalog's automated-checks domain
  (`CHECK-VERDICT`, `CHECK-BASELINE`, `CHECK-PLACEMENT`, `BUILD-EVIDENCE`) and documentation-quality domain
  (`DOC-INTERNAL-QUALITY`, `DOC-EXTERNAL-QUALITY`) are the interface a gate or a doc set adopts. Count them
  as held, not as local inventions.

## Step 2 - Classify and place

| Finding | Action |
| --- | --- |
| Already in the catalog | Keep a pointer here; delete the local copy of the text. A local copy that says something the catalog does not is an **amendment to write**, not a copy to keep. |
| A contract, not yet in the catalog | **Move** it into the catalog - the function folder it belongs to, or a new one created from `_meta\CONTRACT_TEMPLATE.md` - with its conformance artifacts. Leave a pointer behind. |
| Not a contract | Leave it. Say so in the report so the next run does not re-litigate it. |

A new folder is named after **what the software does**, never after this product. If the contract only
makes sense under the product's name, it is probably a private decision rather than a contract.

## Step 3 - Repoint

- The agent-rules file names the catalog in **exactly one place**, with the rule that contracts are cited
  by id and never linked.
- Each `docs/contracts/<ID>.md` is a pointer, named after the contract id and listed in
  `docs/contracts/README.md`: **id, version, home, role** (producer / consumer / both), and what this repo
  must do to stay conformant. Nothing more - a pointer that grows a second page
  has become a copy.
- Source comments cite `<DOCUMENT>.md section N` or `<ID> rule N`. No `P:\` path in a tracked file:
  whoever clones the repo does not have that drive.

## Step 4 - Fill the registry

In `P:\Contracts\_meta\REGISTRY.md`, for every contract this product produces or consumes: the version it
**implements**, the range it **reads**, today's date as **verified**, a one-line note. Record deviations
under the rights and evidence requirements in step 5; an exception has no end date and stands until it is closed.

Write the cells in the format `REGISTRY.md` section 2 states, because a program reads them: the `Product` cell starts
with this repository's key, then a surface in parentheses (rows that still carry the product's name keep it until the
repository rewrites all of its rows together with its own checks that read the name), **one** version
(or `partial <version>`, or `-`) per cell, one contract id per row, `pending` or a date in `Verified`, and
everything else in the note. `tools/contract-lag.ps1` reports a row it cannot read as `unparsed`; fix your own.

**The note is at most 300 characters, and a new one replaces the old one.** Never put the new account in front of the
previous one (`Earlier: ..`): the catalog's history keeps every earlier state. Say what was verified and name where the
evidence is - a ticket, an audit, a progress record of this repository, which is where the long account is written.
`check-contracts.ps1` reports a longer note as `CTR-NOTE`.

**Edit this product's rows only.** Another product's row, and another product's contract, are amended by
written proposal, never by edit. Every contract is sealed (since 2026-10-07), drafts included: only its owner
edits it, so a draft this product merely consumes is not this product's to supplement. A row you cannot verify honestly stays `pending` with a note naming what
is missing - that is a correct answer, and the registry is designed to carry it.

**The registry is a hand-edited file with many writers and no lock.** Copy it to `temp/` before the first
edit; change it with exact-string replacements only, never a whole-file rewrite or a line-ending
normalisation; and expect the diff against the copy to be pure addition or a change inside this product's
own rows. A hunk you did not write belongs to a sibling session - read it before calling it yours or
reverting it. The same goes for any edit outside this repo: re-grep its anchors in the step that writes the
verdict, not from memory of the edit.

## Step 5 - Audit the consumer code against the compatibility law

**Rights retained throughout synchronization.** The project may declare justified exceptions in its own
registry rows without prior contract-owner approval and recommend corrections or additions. Record the
clause, scope, evidence, impact, compensating behavior and review condition. Temporary debt needs a
remediation ticket and no end date; a permanent supported variant needs a dated linked design record. For
another owner's contract, file a dated proposal and retain an exception until its decision where needed.
Do not equate synchronization with unconditional conformity or remove these rights from the final report.
Independent legal, store, security and data-safety release blockers still apply (CONTRACTS section 4).

`_meta\VERSIONING.md` §4, restated in [CONTRACTS.md](../../rules/CONTRACTS.md) §5. Read the code and answer
each with a file and a line:

1. Fields and columns matched **by name**, never by position?
2. A higher **MINOR** accepted, unknown additions skipped?
3. A higher **MAJOR** refused **cleanly** - one clear message, never a partial import, never a crash, never
   a version guessed from the bytes?
4. An unknown **enum value** degrading to the documented default?
5. Ingest **preserving user-authored data** - merge by stable key, touch only producer-origin rows?
6. Every index **bounds-checked**, degrading to the nothing-case?
7. **Defaults** for missing optional fields written down in the contract rather than decided locally?

Each `no` is a ticket in this repo's store. **Do not change behaviour at a contract boundary inside this
run** unless the owner asked for that change: the contract moves first, then the code (CONTRACTS §4).

## Step 6 - Run the conformance artifacts

Where the contract has vectors, run this product's tests against the vectors **in the catalog**, at the
version the registry names, and cite the command, the exit code and the output. Where there are none, say
so: the registry's artifacts column exists to make the gap visible, not comfortable.

## Step 7 - Report

- contracts **moved** into the catalog, with ids and versions;
- contracts **already there**, now pointed at correctly;
- findings **left** as non-contracts, one line each;
- registry rows **written**, exceptions **recorded** with scope, impact, responsible project and review
  condition; temporary debt with a remediation ticket, permanent supported variants with a dated
  linked design record;
- the seven answers from step 5, with the tickets opened;
- what could not be verified, and what it would take.

Commit only if the owner asks, and only in this repository. A change in the catalog is live the moment it is
written - say plainly what you changed in it. The catalog keeps a local git history that only the canon
session (`sza-unified-rules`) writes: **from any other repository's session, run no git command in
`P:\Contracts`** - not `status`, not `diff`, not `add`, `commit`, `checkout`, `restore` or `stash`. Several
sessions write there at once, and one session's command can stage or discard the work of another.

---

## Which product is behind, and the spec that catches it up

For a portfolio-wide catch-up, use the [spec-draft tracking campaign](../spec-draft/SKILL.md).
Keep one checklist in the canon with `-Tracking`. Use `-NeedsWork` for repos that need code changes
or use a bounded `-Check` script whose exit 1 identifies code work. A registry or pointer check can close
its row directly with `-TrackingTicket` when it passes. The product still owns its registry updates and
exception decisions.

The registry is the ledger of which version each product is synchronized with. From the canon repo:

- `pwsh -File tools/contract-lag.ps1` lists every adoption row that is **behind** its contract, `partial`,
  `pending` or unreadable. `check-contracts.ps1` shows the totals as `CTR-LAG`.
- `pwsh -File tools/contract-lag.ps1 -Product <repository key> -EmitSpec -OutFile <path>` writes the **synchronization
  spec** for one product: per contract, the document-log entries between its version and the current one, each
  with its kind and what it obliges, plus the definition of done. Hand it to that product's own session; this
  skill, run in the canon, never edits another product's rows or tree.
- Running this skill **in a product's repo** with such a spec in hand is the catch-up run: steps 4-6 for the
  contracts the spec lists, then the registry rows, written by the product.

A row can be behind because the code is, or because nobody re-read the contract since it moved; the spec
cannot tell which, and the owner's verification is what tells.

**Every release starts with this catch-up** (the owner's order of 2026-11-15, [CONTRACTS.md](../../rules/CONTRACTS.md)
§6 item 6): generate the spec for the product's repository key; read the entries of each
`behind (breaking)` row against the code, and those of a `behind (additive)` row when the release touches that
contract's boundary; then move the rows that were read. An `unread` row opens no ticket. The `release` skill's
contract gate reads the result; do not wait for release time when a breaking change has landed - a product that
sees one opens the catch-up as its own ticket.

## Answering a request from a sibling product

When another product asks about a shared contract, answer in a dated `RESPONSE` document ([CONTRACTS.md](../../rules/CONTRACTS.md) §4): contract facts cite id and section; implementation facts cite code with the tree's date and say what was **not run**; every deviation found while answering becomes a ticket in this repo and a registry row; the answer amends nothing; and it corrects the requester's wrong premises rather than answering around them.

## What this skill must not do

- **Never weaken a contract to match the code.** If the code is right, write the amendment with evidence;
  if the contract is right, the code is a ticket.
- **Never invent a version.** A version comes from the change's own kind (`_meta\VERSIONING.md` §2-3), not
  from how big the edit felt.
- **Never delete anything from the catalog.** A contract is superseded or retired in writing, with its log
  row intact, because a consumer may have shipped against it.
- **Never touch another repository's working tree.** One repo per run, and the other side of a shared
  contract finds out by proposal, not by surprise.
- **Never run a git command in the catalog from a product session.** Its history is written by the canon
  session alone (`_meta\RULES.md` section 6); a change there that you did not make is a sibling's work.
- **Never edit a contract this product does not own** - sealed, draft or not. Write
  `PROPOSAL-<date>-<topic>.md` beside it in its domain folder and leave the contract untouched.
