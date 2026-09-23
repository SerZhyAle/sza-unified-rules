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

## 7. What a product may count about its users

§§1-6 describe the loop back from users as three tiers: **contact** (§1), **diagnostics** (§3), and
**counting** - the numbers the product keeps about its own use. The first two are a human act every
time. The third runs without one, which is why it needs a boundary written down rather than left to
whoever adds the next counter.

### 7.1 The boundary

- **A minimal always-on basis, and nothing more.** Only what is needed to place the install in time -
  first-run timestamp, run count, the version first installed. It exists whatever the user chose,
  because a product that cannot tell a first run from a thousandth cannot read its own crash reports.
- **Everything else is off until the user turns it on**, in a control that says what it turns on.
- **Withdrawal deletes.** Turning detailed collection off erases the detailed data and keeps the
  basis. A consent that only stops future writes is a consent in name.
- **No identifier that links two runs.** No user, device, install or session id, no fingerprint
  assembled from properties that are individually harmless. This is the line that separates counting
  from tracking, and it is the one a useful-sounding feature erodes first.
- **The count lives on the device**, cheap enough to be invisible on weak hardware - in memory, flushed
  in batches, never a write per event.
- **Data leaves only by a user gesture** - a button the user presses, with the content visible to them
  before it goes. A product that ships anything on its own initiative has telemetry, whatever it calls
  it.
- **A surface that exists only while collection is on.** A statistics screen offered to a user who
  turned collection off shows either nothing or a lie.

### 7.2 The promise says both halves

A product claiming no telemetry names its local counting **in the same promise**
([SECURITY_AND_PRIVACY.md](SECURITY_AND_PRIVACY.md) §4-5). "No analytics or usage tracking" beside an
undisclosed statistics screen is true and incomplete, and a reader who finds the screen has no way to
tell which it is. State the claim, then state what the device counts and that it stays there.

### 7.3 Describing what exists is not introducing what does not

The diagnostic channel of §3 is **pull and manual**: the user captures the bundle and sends it, the
developer ingests it. That is the portfolio norm and it is what keeps the privacy promise unconditional.
App-initiated intake - a server that receives, a background upload, a voluntary aggregate the product
transmits - is a **new capability with its own decision**, never a wider reading of this section. So is
splitting counts by period, or any aggregate leaving the device without a gesture.

### 7.4 One declared channel per product

Each product holds its own support address; the portfolio does not share a mailbox. What the contract
requires is that the address exist **once**, as a single declared constant, and that the subject line
name the product and its version - so a second address cannot appear beside the first without someone
noticing.

## 8. Applying to a new project

1. Wire the issue tracker + contact email into footer, listing, and About; state a response
   expectation.
2. Audit user-facing errors for a human next step (§2).
3. Add an in-app "send diagnostics" path and a repeatable intake+analysis procedure (§3).
4. Route reports through the ticket lifecycle with symptom-dedup (§4); feed recurring questions into
   the docs (§5).
5. Fix the counting boundary before the first counter ships (§7): name the always-on basis, put the
   rest behind consent, and make the privacy promise say both halves.
