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

## 8. Applying to a new project

1. Adopt the flagship rule (§1) and the evidence ladder (§2) as the definition of "done".
2. Stand up unit tests for domain logic; add integration tests where a mock would hide a real break.
3. Script the pre-release sweep (§5) with a written verdict; wire it to the release gate.
4. Write the persona happy-path (§6) as a repeatable check, not a vibe.
