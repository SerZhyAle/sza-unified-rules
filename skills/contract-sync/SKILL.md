---
name: contract-sync
description: Align this repository with the shared contracts catalog at P:\Contracts - inventory what the repo holds, move the real contracts into the catalog under the function they belong to, replace every local copy with a pointer, fill the registry rows, audit the consumer code against the compatibility law, and record each deviation as a dated exception. Use when asked to sync, align, migrate or tidy contracts, to share a format or algorithm with another product, when adding or changing a shared format, schema, protocol or wire shape, before a release that touches a contract boundary, or on the Russian phrasings - "контракты", "приведи контракты в порядок", "синхронизируй контракты", "перенеси контракты в каталог", "общий формат с другим проектом", "версия контракта".
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
  thinks to look for.

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
**implements**, the range it **reads**, today's date as **verified**, a one-line note. Every deviation
becomes a dated **exception** with a reason and an `until` date.

**Edit this product's rows only.** Another product's row, and another product's contract, are amended by
written proposal, never by edit. A row you cannot verify honestly stays `pending` with a note naming what
is missing - that is a correct answer, and the registry is designed to carry it.

## Step 5 - Audit the consumer code against the compatibility law

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
- registry rows **written**, exceptions **recorded** with expiry dates;
- the seven answers from step 5, with the tickets opened;
- what could not be verified, and what it would take.

Commit only if the owner asks. The catalog is outside git, so changes there are live the moment they are
written - say plainly what you changed in it.

---

## What this skill must not do

- **Never weaken a contract to match the code.** If the code is right, write the amendment with evidence;
  if the contract is right, the code is a ticket.
- **Never invent a version.** A version comes from the change's own kind (`_meta\VERSIONING.md` §2-3), not
  from how big the edit felt.
- **Never delete anything from the catalog.** A contract is superseded or retired in writing, with its log
  row intact, because a consumer may have shipped against it.
- **Never touch another repository's working tree.** One repo per run, and the other side of a shared
  contract finds out by proposal, not by surprise.
