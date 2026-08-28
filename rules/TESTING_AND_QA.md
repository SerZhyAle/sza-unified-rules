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
- Track known-broken tests explicitly so a pre-existing red doesn't mask a new regression - a green you
  can't trust is worse than a red you can.

## 4. Device / emulator verification *(overlay)*

For anything a user sees or touches, drive it on real hardware or an emulator, not just unit tests.

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
