# Development - the portable engineering discipline

The code-level rules that hold across every project, extracted from the most mature codebase in the
portfolio (`FastMediaSorter_mob_v2`, Android/Kotlin) and phrased so they transfer to a Windows desktop
app or a Go tool. Platform-specific tooling is marked *(Android reference)*; the principle above it is
universal. Reconciled against the portfolio; per-project divergences live in `contrib/`, not here.

## 1. Layered architecture

- One direction of dependency: **presentation -> application/domain -> data**. In the Android reference
  this is `UI -> ViewModel -> UseCase -> Repository -> DataSource`.
- **The UI layer holds zero business logic.** A view/activity/page reacts and delegates; decisions live
  one layer down. When a UI file grows logic, extract it to a named helper/manager, not into the view.
- I/O sits at the data boundary (`withContext(Dispatchers.IO)` at the repository/datasource edge in the
  Android reference), never buried in domain logic or pushed onto the caller.

## 2. Naming by role

- Names carry the role as a suffix so grep and the mental model agree: `VerbNounUseCase`,
  `NounRepository`, `NounViewModel`, `NounVerbManager` *(Android reference)*. Any project: a type's name
  says what layer it lives in.
- Files and docs use a stable *type prefix/suffix* that a glob can find (see REPOSITORY_LAYOUT docs
  taxonomy).

## 3. Size & decomposition

- **File-size ceiling** (Android reference: 1500 LOC). Past it, extract cohesive logic into a
  `helpers/*Manager` sibling rather than growing one file. Measure honestly - count real lines, don't
  eyeball.
- Back up any large file (Android reference: >500 LOC) to a scratch copy before a risky edit.

## 4. Comments & logging

- **Comments explain WHY, not WHAT.** English only. Only non-obvious logic, edge cases, workarounds,
  invariants. Never restate the adjacent line; remove stale comments in code you touch. Existing
  comments/KDoc are requirements - don't silently override them.
- **One logging abstraction per project**, never the raw platform logger. Android reference: `Timber`,
  and `android.util.Log`/`System.out` are banned. Real errors log at error level; expected fallbacks
  at info - don't cry-wolf at error for a normal fallback.
- **Script/console output is English**, like all code, logs, and commits - including build/release
  scripts only the owner runs (owner decision 2026-07-23). Chat follows the owner's language; script
  output does not.

## 5. Evidence discipline (the flagship rule)

- **No completion claim without fresh evidence.** Before saying anything is done / fixed / passing, run
  the command that proves it, read its exit code and output, and cite that. Red-flag words - "should",
  "probably", "seems", "looks fixed" - mean: stop and run the check first.
- The full rule, the evidence ladder, and the test tiers have one home:
  [TESTING_AND_QA.md](TESTING_AND_QA.md) §1-3.

## 6. Validation ladder

Pick the cheapest evidence rung that matches the risk. The ladder itself (docs -> script -> build ->
compile-only -> targeted tests -> minified release variant -> device) lives in
[TESTING_AND_QA.md](TESTING_AND_QA.md) §2 - one home, no drift.

## 7. Research order - index before grep

- Look things up in this order: the project's operations index -> the class/feature catalog -> domain
  docs -> the implementation. Never guess a path.
- **Query the generated catalog before a global grep** *(Android reference: `dev/CATALOG/scripts/query.ps1`
  before `Grep`/`Glob`)*. Any project with a generated index consults it first; the index is
  regenerated, not hand-edited or committed.

## 8. Ticket / spec lifecycle

- Every non-trivial change is a ticket with an explicit lifecycle (Android reference: `Sxxxx` specs,
  `Draft -> Approved -> Tactical -> In Progress -> Implemented -> Verified`, managed only through the
  `scripts/spec_catalog/` CLI - never hand-edit the journal). A desktop/Go project uses
  `docs/specifications/SPECIFICATION_*.md` instead; the discipline is the same: one authoritative
  ticket record, mutated through its tool, status synced into the file.
- **Out-of-scope findings are parked, not fixed inline** when they are unrelated, non-trivial, and need
  their own research: dedup by symptom first, capture the symptom/evidence in a fresh draft ticket,
  report it, and resume the original task. Never switch the active ticket for a parked finding. Trivial
  in-scope fixes are done on the spot.
- **A "needs device/user test" state is an explicit lifecycle status**, and a temporary debug probe may be
  bound to it: a probe log line exists in code *iff* the ticket sits in that status - inserted at the
  changed-flow entry before the test build, deleted the moment the ticket leaves it, and never present in a
  permanent or shipped log (a fail-closed gate keeps ticket ids out of permanent logs). The probe cannot
  ship, because its lifetime is the status, not the developer's memory.

## 9. Dead-weight & AI-tell hygiene

- **Delete orphaned code, resources, and keys in the same change** that makes them dead; verify on the
  release/target variant.
- **Block the machine-generated smells** (Android reference gate: `assert-neuroslop.ps1`): trivial
  comments that restate code; broad/empty `catch` with no recovery, safe default, or correctly-levelled
  log; hardcoded hex colors in layouts (use a theme attr / named color); lifecycle-unsafe async
  collection; global/ambient coroutine scopes; non-abstraction logging; shipped runtime stubs
  (`TODO()`/`NotImplementedError`); typographic long dashes in code.
- **When a defect type recurs, promote it to a mechanical gate** (a checked-in `assert-*` script or test)
  rather than re-catching it by eye. Recurring review finding -> gate.
- **A gate may carry a scoped allowlist for a legitimate exception** rather than being dropped or made
  blanket. Encode the one place the rule does not apply *inside the gate* - e.g. a typography drift-guard
  that bans em-dashes in generated output except inside a `<title>` literal (conventional book typography) -
  so the exception is explicit and the rule still holds everywhere else.

## 10. Multi-agent & filesystem safety

- **No root writes.** All scratch, logs, artifacts, and backups go under a `temp/` tree, organized by
  ticket (`temp/<ticket>/`, or `temp/scratch/` when none).
- **On Windows, the artifact path length is a correctness constraint, not just tidiness.** A deep
  per-session temp dir can push a working file past `MAX_PATH` (260 chars) and **silently** break a
  path-sensitive subprocess (OCR, a packager) - which then looks like a quality bug, not a path bug. Prefer
  the repo's short `temp/` over a deep system temp path for anything a child process reads.
- **Serialize expensive shared operations** when several agents may run at once: an advisory build lock
  so two builds never overlap, a code lock before a multi-file edit *(Android reference:
  `temp/BUILD.LOCK` / `temp/CODE.LOCK`)*. Judge staleness by process liveness, not a guessed timeout.
- **Fix the project's own scripts** when they are buggy or insufficient - don't work around them.

## 11. Phase-boundary audits

- In any multi-phase task, **audit the phase just finished before starting the next**, at the cheapest
  evidence rung that matches the risk. Catching a defect at the next phase boundary costs one phase of
  rework; catching it at the end costs every intervening phase. Tag findings by severity
  (crash/data-loss -> race/main-thread-IO -> hot-path waste -> style) and fix the serious ones with
  matching evidence, not opinion.

## 12. Multi-edition parity (a product shipped in more than one codebase)

When the same product ships as two editions built from independent source trees (see
[PLATFORM_OVERLAYS.md](PLATFORM_OVERLAYS.md) "Editions") - e.g. a Go desktop app and a JS browser
extension - logic is hand-ported and drifts silently. Guard it:

- **One parity doc is the source of truth** (`docs/PARITY.md`): the port map (which module mirrors which),
  the **value invariants** that must match number-for-number (palettes, reflow/OCR constants, defaults), and
  the **intentional** differences that must not be "fixed".
- **Two gates, not one.** A *value* gate proves the invariants still match across editions (a checked-in
  test that reads both sides). A *structural* drift gate flags when one side of a paired capability changed
  and the other did not (a diff-aware script over the change set) - advisory locally, blocking in CI.
- **Update the parity doc in the same change** that alters a shared invariant. Touching it is the escape
  hatch that tells the drift gate "parity was considered" - which is exactly what an intentional divergence
  needs anyway.

## 13. Single-source multi-target (the compiler is the parity gate)

When **one source tree** compiles into more than one artifact for different runtimes/toolchains (a
**dual-runtime build variant** - see [PLATFORM_OVERLAYS.md](PLATFORM_OVERLAYS.md) "Co-shipping shapes",
reference: `FastMediaSorter_Lite`'s `net10` + `net48` exes), parity is enforced at **compile time**, not by
a `docs/PARITY.md` + drift script (that is §12, for *independent* codebases). Divergences live behind
compile-time seams (`#If NETFRAMEWORK` / an equivalent constant), and a shared-source change that breaks the
other target **fails the build** - the good case. Two traps this model has that a parity doc does not:

- **The seam constant may be defined by hand.** If one toolchain does not define the constant implicitly
  (an old-style project vs an SDK-style one), it is set explicitly in *both* build configs. Delete or typo
  it and every seam silently compiles the wrong branch - no error, just the wrong code path in that
  artifact. Treat the constant definition as load-bearing.
- **A globbed project and an explicit-file-list project silently disagree on a new file.** When one project
  globs its sources (`..\**\*.vb`) and the other carries an explicit compile list, a new file is picked up
  only by the glob; a file nothing references yet is **silently absent** from the other artifact until added
  to the list by hand. Add the file to the explicit list in the *same* change - and know that a *referenced*
  new symbol fails that build loudly (the safe case), while an unreferenced one hides.

## 14. Runtime-migration compatibility pins

Porting a UI/behaviour-tuned app to a newer runtime silently flips the new runtime's **defaults**, each an
invisible regression. Before shipping a migration, enumerate the changed defaults and pin the ones the app
depended on back to the reference build's behaviour (reference: `FastMediaSorter_Lite` net48 -> net10):

- **DPI / scaling** - a modern runtime may default to a DPI-awareness mode the old one never had; a
  pixel-tuned layout shifts. Pin the reference mode until the layout is re-tested at each scale.
- **Culture / collation** - .NET 5+ uses ICU where .NET Framework used NLS, so string sorting changes
  order; pin `System.Globalization.UseNls=true` (or the platform equivalent) if sort order is user-visible.
- **Default font**, default control styles, and **single-file publish emptying `Assembly.Location`** (which
  breaks loaders that read it) are the same class of trap.

The rule: a runtime migration is not "recompile and ship" - it is "recompile, diff the runtime's default
behaviours, pin the ones that matter, re-test the visible surface". Each unpinned default is a quality bug
that looks like a code bug.

## 15. Gate & closure mechanics

The machinery that makes the hygiene rules (§9) and the parity gates (§12) run cheaply and repeatably.

- **Ratchet baselines - fail on net-new only.** A gate records the current count of a finding and fails
  the build only when a change *adds* to it, so existing debt is frozen and paid down monotonically without
  a big-bang cleanup. A hand-edited baseline is ignored; regenerate it through the gate.
- **Batch the fast gates into one process.** Running each `assert-*` check as its own script spawn is slow;
  a single batch runner (reference: a `fast-gates` command) executes the cheap gates
  (smells + deprecated-API + listener-symmetry + flavor-isolation + log-hygiene) in one pass.
- **Diff-scope the gate on a dirty tree.** To close one change amid other tickets' WIP, a scoped mode fails
  only on findings *in the changed file(s)* and downgrades the project-wide count-ratchets to advisory - so
  a clean change closes without tripping on unrelated in-flight work. The full-project strict gate still
  runs for release/CI.
- **One closure facade, not N rituals.** Mechanical closure (dev-log + index/catalog sync + gates) runs as
  a single command (reference: a `post-change` facade), so "I changed a file, now what" has one answer and
  no step is forgotten.
- **Reachable exit codes (PowerShell).** Under `$ErrorActionPreference = 'Stop'` a bare `Write-Error`
  throws, so any `exit N` after it never runs and the process reports 1 while the message still prints
  (which is why it survives review). Write `Write-Error $msg -ErrorAction Continue` before `exit N`, and
  list the codes a script returns in its header. Gate it (an `assert-exit-contract` check) since the whole
  portfolio is PowerShell-driven.

## 16. Native-binary release hardening (Go / desktop reference)

Portable gotchas for *shipping* a compiled native binary to end users, not just building it:

- **Do not strip symbols to shrink the binary.** For Go on Windows, `-s -w` correlates with higher
  AV / SmartScreen heuristic false-positive rates; a false malware flag is a real distribution defect. Build
  with `-trimpath` (reproducible paths) and `CGO_ENABLED=0` (static, no runtime DLL to ship) and **keep the
  symbols**.
- **Stamp identity into the binary, not only the asset name.** Embed the version + an app manifest (Go
  reference: `goversioninfo` writing a PE `VS_VERSIONINFO` + `resource.syso`; the manifest sets
  `requestedExecutionLevel` - `asInvoker` unless a command genuinely needs elevation - and `longPathAware`).
- **Multi-module repo cache key.** When a repo has several `go.mod`, list *every* `go.sum` in the CI
  cache-dependency path, or the key falls back to the root module and silently misses on every run.

See also: [AI_USAGE.md](AI_USAGE.md) for how an agent should *operate* while following these, and
[REPOSITORY_LAYOUT.md](REPOSITORY_LAYOUT.md) for where the artifacts live.
