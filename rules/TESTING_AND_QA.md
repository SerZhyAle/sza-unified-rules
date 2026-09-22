# Testing & QA - how a project proves it works

Verification discipline shared across the portfolio. It exists to make "it's done" mean "I watched it
pass", not "it should be fine". This is the one home of the evidence rule (§1) and the evidence ladder
(§2) - other docs point here. Reconciled against the portfolio; per-project records in `contrib/`.
Platform specifics marked *(overlay)*.

## 1. The flagship rule

**No completion claim without fresh evidence.** Before saying done / fixed / passing, run the command
that proves it, read its exit code and output, and cite them. A prior run, an assumption, or a
subagent's "it passed" is not evidence. Red-flag words - "should", "probably", "seems", "looks fixed" -
mean: stop and run the check first. Record `expected: X | actual: Y` and the exit code.

**A check only a human can run has not happened yet.** A closing audit that finds no failures but leaves
an unobserved manual line does not score "verified" - it scores "needs a human test", because nothing is
broken and something is merely unlooked-at. Count the unticked boxes in the ticket's audit section and let
a single one of them hold the closing status back; only the human pass converts it. In the reference
project this was not a formality: a ticket was declared done carrying one unticked device line, and an
hour on real hardware showed one of its five acceptance criteria failing outright.

**A check has four answers, and folding the last two together is how it starts lying.** Pass and
found-a-defect are obvious; *could not verify* is the third the exit-code invariant already demands
([AI_USAGE.md](AI_USAGE.md) §2). The fourth is **not applicable in this configuration**, and a check
that has no way to say it will report one of the other three instead. Two rules follow, both measured
on one release sweep in the reference project:

- **Validate the instrument before trusting its reading.** A reading that is physically impossible
  means the instrument is broken, not that the subject failed. A clip check took an impossible
  geometry at face value and called **5 of 5** screens off-glass; a walk over a navigation tree
  reported **18 of 28** rows unreachable. A checker in that state does not merely miss defects, it
  **manufactures release blockers that do not exist** - and the cost lands twice, once on the people
  chasing them and once on the credibility of every later red from the same check.
- **A false finding is as expensive as a miss, and louder.** "A real defect would be one row among
  eighteen false ones" is the failure stated exactly: the check kept running, kept reporting, and had
  become unreadable. Precision is not a nicety on a check whose output a human must triage.

## 2. Evidence ladder - cheapest rung that matches the risk

Don't over-test a typo or under-test a migration. Pick the rung the change actually needs:

- **Docs / text**: grep for the content.
- **Script**: run it, exit 0.
- **Config / layout / manifest**: the target build passes.
- **Code, pure symbol change**: compile-only check.
- **Code, behavioural change**: targeted tests for the touched area.
- **Reflection / serialization / DI / minification / startup**: proven on the **minified release/target
  variant**, not just debug - keep rules and reflective types survive shrinking.
- **User-facing flow**: exercised on a real device/emulator (below).

## 3. Test tiers

- **Unit** - fast, logic in isolation; the default for domain/use-case code.
- **Integration** - real dependencies at the boundary (a real DB, not a mock, where a mock would hide a
  migration/schema break).
- **Release-variant proof** - the minified/packaged build for any change that reflection/DI/keep-rules
  could break.
- **Contract conformance** - for anything a second product reads or writes: the vectors from the shared
  contracts catalog, at the version this product's registry row names ([CONTRACTS.md](CONTRACTS.md) §6).
  A vector copied into the repo and edited locally proves nothing; run against the catalog's copy.
- Track known-broken tests explicitly so a pre-existing red doesn't mask a new regression - a green you
  can't trust is worse than a red you can.

## 4. Device / emulator verification *(overlay)*

For anything a user sees or touches, drive it on real hardware or an emulator, not just unit tests.

- **Inclusive interaction and adaptable layout are part of the feature contract.** For every input mode
  the product declares - touch, keyboard, pointer, controller, or assistive technology - an interactive
  control is reachable, has a predictable focus/order model where relevant, and exposes its purpose and
  action semantically. Required viewport, orientation, and form-factor classes keep operable content clear
  of mandatory system UI. Exercise the declared modes and layout classes, or record a configuration as not
  applicable; a successful touch-only flow does not prove a keyboard, controller, or accessible flow.
- Android reference: on-device UI drive + logcat harvest (`spec-test-device`), batch sweeps over pending
  tickets (`spec-sweep`), quick ad-hoc device chores via the adb wrapper. Beware emulator quirks
  (unindexed media store, untappable bottom-sheet items, touch wedges) - they cause false FAILs.
- Desktop/CLI: run the built artifact on a clean machine/VM; verify install, first-run, and uninstall.
- **A repeatable UI-flow harness sits above ad-hoc device drive.** Scripted flows (reference: Maestro) run
  the core journeys the same way every time, in CI. Triage a red at the harness level first: a flaky harness
  (a device that wipes config between runs, a timing wedge) fails for its own reasons - confirm the app
  actually regressed before calling it a regression.
- **Bind "needs device test" to the ticket lifecycle.** A change only a human can confirm on hardware parks
  in an explicit test-blocked status (with a status-gated probe, see [DEVELOPMENT.md](DEVELOPMENT.md) §8)
  until the owner verifies on a real device - a structured hand-off, not an informal "please test".

## 5. Pre-release sweep (gates the release)

Before shipping (see [RELEASE_AND_DISTRIBUTION.md](RELEASE_AND_DISTRIBUTION.md) §2), run one end-to-end
sweep and produce an explicit **PASS/FAIL verdict**:

1. **Clean install** - install over nothing *and* over a prior version (update path).
2. **Resources** - every shipped asset/string/icon is present and correct for the target variant.
3. **Settings** - defaults are sane; first success needs zero configuration.
4. **Scenario** - the core job the product exists for completes end-to-end.
5. **Performance** - startup, memory, jank within budget on a representative device.
6. **Verdict** - PASS or FAIL, in writing. FAIL blocks the release.

**A waiver covers a known gap, never a "could not verify" the same run just produced.** A sweep that
cannot reach its subject has measured nothing, and signing that off converts an unknown into a
recorded pass - the one conversion the whole sweep exists to prevent. In the reference project the
device smoke returned `VERDICT FAIL .. smoke=no-device/infra`, the gate mapped it to a
waiver-eligible coverage gap, and the waiver was signed. The category was right and the motion was
wrong: **an unreachable interpreter and a genuinely absent device produced the same bucket**, so the
signature covered a tooling defect while appearing to accept a known limitation. Separate them at the
source - an infrastructure fault is not a coverage gap - and make a fresh could-not-verify block the
ship exactly as a FAIL does, since neither one proves the thing.

**A gate that has not run since the last release is itself unverified.** The smoke above had rotted:
three independent defects sat in it at once because nothing had invoked it in months, and they were
found by the release that needed it rather than before. Anything the release depends on runs on a
cadence that does not wait for the release - in CI, in the periodic sweep, or on a schedule - or its
first run in months happens at the worst possible moment.

## 6. Persona QA (the product compass, as a test)

Test as the real users, not as the author (see [AUTHOR.md](AUTHOR.md) product compass):

- **The happy path reaches a result with zero mandatory configuration.** If a step would stop the
  grandmother opening her photos or the gym-goer starting music, it's a **defect**, not an edge case.
- **Every failure states a human next step** ("Computer is off or not on the same network"), never a
  bare error code or a stack trace in the face.
- **Robust on the real-world path**: weak Wi-Fi, screen lock, headset, dropped connection - graceful,
  no crash, sane lock-screen/background behaviour.
- **Zero jargon** in anything the persona sees.
- **For a destructive action the happy path inverts.** When the core job overwrites or deletes data
  (wipe / fill / format / bulk-delete), "runs with zero friction" is the wrong pass condition: the pass
  condition is that the **confirmation fires and cannot be force-bypassed for dangerous targets**
  (drive/share roots, reparse points/junctions, the system drive or TEMP). A `--force`/`-y` flag skips the
  *prompt*, never the *safety checks*. A silent data-loss path that "passed" a friction-free test is the
  defect.

## 7. Audit triggers (test more when these change)

Escalate verification when a change touches: a new screen/worker/repository; lifecycle; concurrency /
listeners / observers; DB schema or migration; player / media / caching / network path; startup; DI
scope; build/minification. In a multi-phase task, audit the just-finished phase before starting the
next ([DEVELOPMENT.md](DEVELOPMENT.md) §11).

**A point fix on a shared contract is half a fix - sweep every site of that contract in the same
ticket.** When the defect is not "this code is wrong" but "this code did not pay what the platform,
the API or the wire format demands", the same debt is almost certainly unpaid elsewhere, written by
the same hand on the same day. The sweep is cheap because the contract names its own call sites; the
alternative is discovering them one production crash at a time. Measured in the reference project:
the identical service-lifecycle contract had already been paid **twice** in one subsystem, each time
as a point fix, and a third service in the same repo was never looked at - it crashed in the field,
was reported by remote diagnostics **three hours after the release shipped**, and cost a same-day
fix-release. Two paid fixes were, between them, the map of every place to look.

## 8. Gate cost - keep the machinery cheap without weakening it

A mature project accumulates mechanical gates, and they start costing real waiting time. The instinct
is to prune the ones that never catch anything. Measured on the reference repo over three weeks - 8,562
gate runs, 555 failures, 2,803 minutes of wall time - that instinct was wrong, and the correction is
worth carrying everywhere.

- **Measure the per-gate distribution before proposing that any gate be removed, weakened or
  reordered.** The distribution is extremely skewed: one gate (detekt) was 86% of all gate wall time,
  while the thirteen gates that never fired once cost 133 minutes between them - 4.7%. Deleting the
  quiet gates removes insurance and buys a rounding error. Optimise the head.
- **A gate that never fires is not evidence that it is useless.** It may be the reason the failure
  stopped happening. Retire one only on a stated argument about the risk, never on its own silence.
- **The argument that does carry weight is demonstrated redundancy, not silence.** Silence says a
  gate found nothing; redundancy says a *cheaper check already standing in front of it* found
  everything it would have. Measure the pair, not the gate alone. In the reference project an
  expensive static-analysis step ran in **291 closures, and in 291 of 291 the cheap lexical pass had
  already come back clean** - the expensive one never ran on a tree the cheap one had objected to -
  while **real findings the cheap pass missed, over the whole corpus, came to 0**. It cost **21.4% of
  the summed gate wall**, and a closure that ran it took **67.1 s against 26.6 s** for one that did
  not. That is a retirement argument; "we have not seen it go red" is not. One trap inside it:
  **count findings, not non-passes.** That gate's only two non-PASS verdicts were *could not verify*,
  which is not yield - reading them as "it caught two things" is how a redundant gate survives its
  own audit.
- **Every number a gate rests on ships with its date and the one command that regenerates it.** A
  threshold is a measurement, and a measurement decays. In the reference project a concurrency bound
  of **14.1 s**, measured on one date, was still refusing work seven weeks later when the real median
  over 157 runs was **56.0 s** - about **4x drift**, with the documented figure quoted all the while
  as if it were current. The second-order failure is worse than the first: **a standing refusal
  blinds the audit that would have caught it**, because the range it forbids produces no runs, so the
  data that would show the bound is wrong can never be collected. Date every threshold, name its
  regenerating command beside it, and treat a bound that has never been re-measured as an assumption
  rather than a limit.
- **Cache a clean verdict against a fingerprint of every input the verdict can depend on** - the
  analysed sources, the tool's config, its baselines, the build files and the gate script itself. In
  the reference repo 56% of the expensive gate's runs analysed a tree in which nothing it reads had
  changed since the previous run, which is simply what closing one task file by file produces. Four
  conditions make this safe, and all four are load-bearing: cache only the fully-clean verdict, because
  it holds for every later caller's scope; never cache a scoped or partial pass, and never cache a
  failure; re-compute the fingerprint after the run and store it only if it still matches, so a
  concurrent edit is never certified; and check the cache **before** queueing for the build lock, since
  the queue is part of what you are avoiding. Give it an explicit bypass flag and use that flag on the
  release and CI paths, where the point is the run itself, not the answer.
- **A recorded step duration usually includes waiting for the lock, not just the work.** The same gate
  measured 152 s averaged across recorded runs and 25 s when invoked directly on a warm daemon. Both
  are true; they answer scheduling cost and compute cost. State which one you mean.
- **Never disable a check to make the loop faster.** Speed comes from not repeating work whose inputs
  did not change, not from checking less. If a gate is genuinely too slow, cache it, narrow its trigger
  or move it off the hot path - do not silence it.

## 9. Applying to a new project

1. Adopt the flagship rule (§1) and the evidence ladder (§2) as the definition of "done".
2. Stand up unit tests for domain logic; add integration tests where a mock would hide a real break.
3. Script the pre-release sweep (§5) with a written verdict; wire it to the release gate.
4. Write the persona happy-path (§6) as a repeatable check, not a vibe.
5. Once the gates are more than a handful, measure their cost distribution (§8) before tuning any of them.
