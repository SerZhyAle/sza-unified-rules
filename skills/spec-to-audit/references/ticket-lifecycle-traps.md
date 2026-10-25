# Ticket lifecycle traps

Loaded from the [spec-to-audit](../SKILL.md) Stage 7 pointer. Each entry is a condition, the remedy, and the
escape hatch where there is one. Statuses use the portfolio vocabulary; read `BlockNeedUserTest` as "the
project's needs-manual-test status".

## Resuming a ticket

- **The tree beats the tracking.** On resume, trust in this order: the live source tree and the shared
  chat, then the status note, ticked step boxes, phase notes and evidence prose. Run each step's own
  verification and grep the spec's new symbols before believing a box; then correct the tracking to match
  the tree. A sibling that ended mid-step leaves its work done and its boxes unticked, or the reverse.
- **A phase-boundary audit on a resumed ticket covers the whole ticket**, including phases a prior session
  marked done. Its "done" is a claim from a context you do not have.
- **Re-read before the verdict.** Right before writing the `## Last Audit` block or flipping the status,
  re-read the ticket's status and the spec's level-1 and level-2 headings from disk. The body may have been
  rewritten under your lease. An audit block already present means a sibling finished - stop and read it.

## Status moves

- **A found problem ends `BlockNeedUserTest` in the same action.** The ticket goes back to the
  work-remaining set with the finding in its status note, and its probes are removed. Exception: every
  finding is already its own ticket in the same release package.
- **Scaffolding is not done** - the Stage 5 entry precondition. No `Implemented`, no `BlockNeedUserTest`,
  no invitation to test while the headline action is a stub.
- **Rework of a delivered feature is a new ticket.** Reopen only for a defect in a ticket that is
  unreleased or unverified. An older ticket on the same surface is a reference, not a duplicate.
- **Deferred work keeps a blocker token.** Work deferred to "after milestone X" stays `Draft` or `Tactical`
  with the literal blocker token naming the milestone's ticket. It is never archived and never
  `BlockExternal` - the milestone is ours, not an outside party's.
- **A blocker releases its dependents at `BlockNeedUserTest` or later**, unless the shippable work the
  dependent needs is absent. A blocker's readiness predicate is a behaviour question about the tree ("does
  the exporter write field X"), never a grep for an identifier the waiting ticket invented.
- **Busyness is a lease, not a status.** Never add a lifecycle status meaning "a session is driving this".

## Probes

- **Probes are the last code edits**, and the status flips to `BlockNeedUserTest` **before** the closure
  runs, because the probe gate reads the status from the journal.
- **One probe is one statement, alone on one line.** Count the probe lines after placing them, not from the
  plan.
- **A probe marker in a status note counts only at line start.** A probe count reported as `0` because the
  gate could not read the contract set is "could not verify", not "none".
- **A ticket that changes no code cannot host a probe**, so it cannot wait in `BlockNeedUserTest`. It closes
  on durable evidence instead.

## Evidence

- **Closing evidence is durable.** A `Verified` audit cites only tracked ticket artifacts - never a path
  under `temp/`, not even in a sentence; the project's evidence-durability gate refuses it. Keep the
  measurement (the number, the verdict line), not the screenshot. Write the verdict into the spec at the end
  of each run, not at the end of the ticket.

## Dedup by symptom

- **An empty name search proves nothing.** Grep ticket bodies, not only names and titles; run several
  one-word searches; include the archive; search with the mechanism's domain nouns, not the words of the
  symptom report. A project's catalog search that matches name and title only cannot answer a dedup on its
  own.

## Leases and sibling sessions

- **Claim the ticket lease before research, not before the edit.** Research spent on a ticket another
  session holds is wasted. Re-claim it at every stretch with no catalog write (a lock-queue wait counts), so
  it does not lapse under you. Release it on the same command line as the final status transition, guarded
  by that transition's exit code.
- **A granted lease does not prove nobody else is on the ticket.** A session that never took a lease edits
  freely; read the shared chat before trusting the grant.
- **Two sessions on one ticket race in the plan directory**, where no lock looks - the lost-update traps
  are in [DEVELOPMENT.md](../../../rules/DEVELOPMENT.md) section 10, "Locks do not see every lost update".
