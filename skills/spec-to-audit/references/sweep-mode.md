# Sweep mode - draining the human gate

Reference for the `spec-to-audit` skill ([SKILL.md](../SKILL.md)), moved out of the always-read text. A sweep is started by the owner; a queue pass working one ticket never runs it. See also [the audit campaign](audit-campaign.md), whose device tests drain here.

The lifecycle deliberately accumulates human-gated tickets. Left alone they pile up. Do this as a **periodic
batch, never a per-ticket interruption** - deferring the human gate to one batch is the whole reason the block
state exists.

1. Group every ticket at the needs-manual-test status.
2. For each, run the recorded manual check. Its probe tags say exactly which paths a real run exercised -
   grep the ticket id in the log.
3. Re-audit the batch: the ones whose manual signal is now closed flip to Verified and **their probes are
   removed in the same pass**; the rest stay blocked with a note.

This is also where the pre-release sweep hooks in: clean install over nothing **and** over a prior version,
resources, first success with zero configuration, the core scenario end to end, performance - ending in a
written PASS/FAIL verdict where FAIL blocks the release.
