# Shared contracts - what binds across products

Every project in the portfolio implements something a second project depends on. This page says what that
makes it, where it lives, who may change it, and what happens at release time. It binds every repo that has
adopted the canon.

The contracts themselves are **not here**. They live in one catalog outside every repository, at
`P:\Contracts`, organized by function. This page is the canon's law about them; the catalog's own
`_meta/RULES.md` and `_meta/VERSIONING.md` are the operating detail. Where this page and the catalog
disagree, the catalog is newer and wins - and somebody owes this page an edit.

---

## 1. What a contract is

A **contract** is any durable functional solution that outlives one repository - something a second project
implements against, or that could be handed to an outside developer and still be correct:

- a **format** - a file on disk, a wire payload, an interchange schema, a published catalog;
- an **algorithm or pipeline** - the ordered decisions that produce a result, the constants they are pinned
  to, and the measurement that derived them;
- a **behaviour at a boundary** - what is accepted, what is refused, what it degrades to, what it must
  never destroy;
- a **user experience at a shared moment** - the install warning, the permission ask, the import that could
  overwrite a person's own work;
- a **documentation shape** - the structure a document set keeps so two products can be read against each
  other.

It is **not** how we develop. Repository layout, commit discipline, release mechanics, testing tiers,
ticket lifecycle, agent workflow: that is this canon, and it never moves into the catalog. One question
separates them - *does it describe what the software does, or how we build it?* Only the first kind is a
contract.

**One carve-out, since 2026-09-22.** This prose is not a contract; the **machine-readable interface**
between it and a repository is. The files a repo keeps so a program can read what it is - the adoption
stamp, the harness profile - the names tools address it by, and the handshake through which a rule set
arrives and is judged stale are a format on disk and a behaviour at a boundary, read by implementations
that never read a rule. They live in the catalog's `rule-adoption/` domain as `REPO-STAMP`,
`HARNESS-PROFILE`, `REPO-LAYOUT` and `RULE-DELIVERY`, owned by this repository. The test does not move:
the rule saying which layout to keep is canon; the file in which a repo declares the layout it kept is a
contract. A change to what a rule *says* still changes no contract.

A contract with exactly one implementation is still a contract. It is marked `solo` in the registry, and it
earns its place because a second implementation is possible, not because writing it there felt tidier.

## 2. One catalog, organized by function

`P:\Contracts` is the single home. Its folders are named after **what the software does** - `ocr-overlay/`,
`stream-catalog/`, `secure-container/` - never after the product that implemented it first.

That is not filing taste. A product-named folder quietly hands one product ownership of a shared decision,
and it cannot answer the question that matters: *how must this function behave here, in every product?* A
function-named folder can, and its `README.md` is where that answer is written and amended.

Each domain README carries the contract's header block (id, version, status, owner, consumers), the rules
that bind every implementation, the conformance evidence, and where each product stands. The long documents
beside it are the detail and the history.

## 3. A repo holds pointers, never copies

- **One line, one file.** Exactly one file per repository - the agent-rules file - says where the catalog
  is. Moving it then costs one edit per project rather than one edit per comment.
- **`docs/contracts/<ID>.md` is a pointer**, named after the contract id (`STREAM-BANK.md`; a family
  implemented as one unit may share a file that names every id, like `FDSEC.md`) and listed in
  `docs/contracts/README.md`. It holds the contract id, its version, its home, this product's role (producer / consumer / both), and what this repo must do to stay conformant. A pointer
  that grows a second page has become a copy, and a copy drifts.
- **Cite by id, never link.** A source comment says `FDSEC-FORMAT.md section 8` or `OCR-OVERLAY rule 4`.
  No `P:\` path in a tracked file: whoever clones the repo does not have that drive.
- **A restatement is a fork.** A repo that describes a shared format in its own words has forked it, and
  the fork will diverge silently. This is the same failure the canon's own reference-versus-mirror rule
  exists to prevent ([README.md](README.md), "How a project consumes these rules").

## 4. Comply, or amend - never deviate in silence

A product that finds a contract wrong, insufficient, or in the way does exactly one of two things:

1. **Amend the contract in the catalog** - a new dated section, a version bump, regenerated artifacts, an
   updated registry row - and only then change the code; or
2. **Record a dated exception** in the catalog's registry, carrying a reason and an `until` date.

There is no third option, and "temporarily" is not one. A local fix that nothing records is invisible to
every other product until the day their data disagrees, which is the failure the catalog exists to end.

Finding a defect creates an obligation, not a licence: whoever finds it writes the amendment, even when the
defect belongs to another product's contract. Silence about a known defect is itself a violation.

**Who writes what.** A product edits the contracts it owns and its own registry rows. For anything else -
another product's contract, another product's row - the amendment is written as a **proposal**: a dated
`PROPOSAL-<date>-<topic>.md` beside the contract in its domain folder, stating the finding, the evidence and
the change it asks for. The owner accepts it by folding it into the contract as a dated amendment, or
rejects it in writing, and the proposal stays as the record either way. A proposal is how the obligation
above is met without one product rewriting another's decision.

**The contract changes before the code does.** Agree it in the catalog, bump the version, regenerate the
conformance artifacts, update the registry, tell the consumers, and only then let the implementations
follow. Code that ships ahead of its contract is how two projects stop being able to read each other's data.

**Telling the consumers is the changing product's job.** A MAJOR is announced in each consuming product's
own record - its `rules/contrib/` file in this canon, or a ticket in its store - before the producer ships
it, not discovered by the consumer afterwards. The registry names who they are.

## 5. Versioning and backward compatibility

The catalog's `_meta/VERSIONING.md` owns this in full. The short form, for a session that cannot reach the
catalog:

- A contract carries a document version `MAJOR.MINOR`, and where the format has a wire carrier - a
  `schemaVersion` field, a version byte, a named column set - the carrier is what code dispatches on. They
  bump together.
- **MAJOR** when an implementation that shipped against the previous version would do something *wrong*
  rather than something *less*: a field removed, renamed or given new meaning or units; an optional value
  becoming required; an "optional" addition whose absence changes security or write semantics; a derivation
  an older reader hard-coded; a change to what absence means; a change to ordering, alignment or framing.
- **MINOR** for an addition an older reader can ignore with no loss but the new feature itself.
- The test is never diff size. Write down what the **oldest shipped consumer** does when it meets the new
  artifact. If the answer contains "wrong", "silently" or "partially", it is a MAJOR.

**The compatibility law.** The producer stays frozen within a MAJOR: it may add optional things, never stop
emitting something, change a meaning, or reorder what was ordered. The consumer is forward-tolerant, and
that means all seven of these:

1. Match by **name**, never by position; an unknown name is ignored, not fatal.
2. A higher **MINOR** is accepted, unknown additions skipped.
3. A higher **MAJOR** is refused **cleanly** - one clear message naming the contract. Never a partial
   import, never a crash, never a guess, and never a version inferred by looking at the bytes.
4. An unknown **enum value** degrades to the documented default.
5. **Absence is not authority to destroy.** Merge by stable key, touch only producer-origin records, leave
   anything the user created or imported by hand untouched.
6. **Bounds-check and degrade** to the nothing-case, never to an error the user must interpret.
7. **Defaults are part of the contract**: what a missing optional field means is written down, not decided
   per implementation.

**How long an old version lives.** The previous MAJOR is supported while any shipped consumer can still
hold data in it - at least one full release of every consumer in the registry. A **reader for every MAJOR
that ever wrote user data is kept forever**: a writer may be retired, a reader may not. A producer starts
emitting a new MAJOR only when the registry shows every declared consumer reads it, or behind an explicit
opt-in that leaves the default path on the old shape. Deprecation is a ladder - `active`, `deprecated` with
the removing MAJOR named, `removed` - and nothing is removed in the version that deprecated it.

## 6. What a release owes

Read as a gate. The `release` skill runs it as its contract gate, ending in PASS, WARN or FAIL beside the
pre-flight verdict; an unreachable catalog makes it UNVERIFIED, never PASS. Before release time the same
rule is caught earlier: `spec-to-audit` asks whether a change touches a contract boundary, and
`adopt-canon` hands a repo that holds a contract to `contract-sync`.

1. Every contract this product produces or consumes has a **current registry row** - version plus a
   verification date not older than the last release.
2. **Ship against the current version where possible.** Behind is allowed with a dated reason in the row;
   absent is not.
3. **One MAJOR behind is a warning; two is a blocker** for new work at that boundary.
4. A release that changes anything at a contract boundary **blocks until the catalog change is in** (§4).
5. The **conformance vectors run in this product's own suite**, against the catalog's vectors, at the
   version the registry names. A green suite against a stale vector proves nothing.

## 7. Evidence

A contract claim is a claim like any other and obeys the evidence rule ([DEVELOPMENT.md](DEVELOPMENT.md),
[TESTING_AND_QA.md](TESTING_AND_QA.md)): the vectors, the command that produced them, the exit code, the
output. Conformance artifacts are **generated, never hand-edited** - a hand-edited vector proves the
editor's belief, not the implementation's behaviour.

Where a contract has no artifacts yet, the registry says so. A contract that claims conformance it cannot
demonstrate is worse than one that names the gap, because the gap is what gets funded.

## 8. Where the rest of it lives

- The catalog's own law, template, registry and migration record: `P:\Contracts\_meta\`.
- The per-repo alignment run: the `contract-sync` skill, or `P:\Contracts\_meta\PROJECT_PROMPT.md` for a
  session without the plugin.
- Coupling shapes that are **not** contracts - editions kept in sync by a parity doc, co-shipping shapes, a
  consumed release artifact: [PLATFORM_OVERLAYS.md](PLATFORM_OVERLAYS.md) "Editions", "Co-shipping shapes",
  "Cross-project contracts".
- Where a pointer file sits in the repo skeleton: [REPOSITORY_LAYOUT.md](REPOSITORY_LAYOUT.md).
- Why a copy is a render target and never hand-edited: [DOCUMENTATION_CONCEPT.md](DOCUMENTATION_CONCEPT.md).
- The one line that is always in context: [INVARIANTS.md](INVARIANTS.md), item 10.
