# Support & Feedback - the loop back from users

How a user reaches help, how a problem report becomes a fix, and how support load is driven down over
time. Cheap to get right, expensive to ignore. Reconciled against the portfolio; per-project records
in `contrib/`. Platform specifics marked *(overlay)*.

## 1. The support path is one click from everywhere

- **Issue tracker for bugs, an email for private contact** - both linked from the site footer, the
  store/Play listing, and the app's About screen. A user should never have to hunt for how to reach you.
- State a **response expectation** ("best-effort, usually within a few days") so silence isn't read as
  abandonment.
- One voice: the support copy matches the product's friendly, task-first tone (see
  [AUTHOR.md](AUTHOR.md)).

## 2. Failures help themselves

- **Every user-facing failure states a human next step** - the persona rule ([AUTHOR.md](AUTHOR.md)
  product compass, tested in [TESTING_AND_QA.md](TESTING_AND_QA.md) §6). A good error message is the
  cheapest support you'll ever ship.
- Design the unhappy path as deliberately as the happy one: weak network, screen lock, dropped
  connection - degrade gracefully with a message the persona understands.

## 3. Diagnostic-log intake *(overlay)*

When a user hits something you can't reproduce, a diagnostic bundle is the bridge:

- Make it **easy for the user to capture and send** a log/diagnostic bundle from the app.
- Have a **repeatable intake procedure** on your side: ingest the bundle, analyze it, extract the
  failure *(Android reference: the `newlog` intake skill + logcat sinks under `temp/`; the `log-reader`
  analysis flow)*.
- **Out-of-scope problems the log surfaces are parked as tickets, not fixed inline**: dedup by symptom,
  capture the symptom + evidence in a fresh draft ticket, then resume. One ticket per distinct problem.

## 4. Feedback becomes tickets

- Every actionable report becomes a ticket in the project's lifecycle (see [DEVELOPMENT.md](DEVELOPMENT.md)
  §8) - dedup against open tickets by symptom first, so the same bug isn't filed twice.
- Reproduce with evidence before "fixing"; a report is a symptom, not yet a diagnosis.

## 5. Answer once, in the listing

- **A recurring support question is a documentation defect.** Pre-empt it where users look *before*
  asking: the listing description, the how-to page, the in-app copy. Stating an honest limitation up
  front ("what the free tier does", "what needs a network call", "what a permission is for") is cheaper
  than answering it repeatedly and builds trust with reviewers too.
- Feed the top recurring questions back into the FAQ / how-to page each release.

## 6. Review & public-feedback posture

- Reply to store reviews honestly: acknowledge, state the real status or caveat, never over-promise a
  fix or a date.
- Public feedback that names a real defect becomes a ticket like any other report.

## 7. Applying to a new project

1. Wire the issue tracker + contact email into footer, listing, and About; state a response
   expectation.
2. Audit user-facing errors for a human next step (§2).
3. Add an in-app "send diagnostics" path and a repeatable intake+analysis procedure (§3).
4. Route reports through the ticket lifecycle with symptom-dedup (§4); feed recurring questions into
   the docs (§5).
