---
name: agent-cost
description: Measure what an agent session actually costs in this repo and act on the result - mine the Claude Code transcripts for token spend, context growth, tool-failure rates and compaction points, then decide what to gate. Use when asked to measure or reduce agent cost, to find where the tokens go, why a session got expensive or slow, whether a rule is actually being followed, or before writing any rule justified by cost. Also on the Russian phrasings - "сколько стоит", "почему так дорого", "измерь расход токенов", "куда уходит контекст", "замерь процесс".
---

# Agent cost - measure before you rule

Every cost argument about agent behaviour is wrong until it is measured, and the naive measurement is
wrong by roughly 3x. This skill carries the method and the extractor so a project does not re-derive
either. It answers one question - where does the spend actually go - and then hands you the evidence
needed to decide whether something deserves a gate, a compression, or nothing at all.

Use it before authoring a rule that cites cost, and after landing a process change to see whether it
did anything.

Canon: [AI_USAGE.md](../../rules/AI_USAGE.md) §3, §5 · [TESTING_AND_QA.md](../../rules/TESTING_AND_QA.md) §1

---

## Step 1 - Know the five defects before you trust any number

Each of these was found by a measurement that disagreed with itself. A tool that does not correct all
five produces confident, wrong numbers, and every decision downstream inherits them.

- **Deduplicate assistant usage by `requestId`, keeping the max per id.** One API response is written to
  the transcript as several records - thinking, text, one per tool call - and each repeats the same
  `usage` object verbatim. Forked sessions replay them again. Summing records instead of unique
  requests inflated tokens ~3x and all counts ~1.4x in the reference corpus. This is the big one.
- **Walk the transcript root recursively**, so nested subagent sessions are included. They were ~17% of
  traffic and had zero id overlap with the main tier - fully additive, and invisible to a flat glob.
  Report the tiers separately as well as combined: subagent conversations are structurally shorter, so
  a pooled average corrupts the per-turn headline.
- **Classify a hard tool failure by the error flag alone, never by a regex over the result body.** A
  source file containing the word `error` or a `catch` clause scores as a failed read; the reference
  corpus over-counted read failures ~25x that way. Keep a regex band only as a separately reported soft
  signal, and only over tools whose result body really is process output - the shell, subagent and
  skill calls. That band is not optional: a job that runs in the background reports a clean result even
  when it failed, so the flag alone under-reports.
- **Segment on the compaction boundary records** and report the percentile spread of the context size
  at each one. That series, not the total, is what tells you whether session boundaries are the problem.
- **Never count consumption by tool name.** Answering "is this artifact ever read again" by scanning
  for `Read` calls whose `file_path` matches it is invalid the moment the artifact is also written,
  searched, or opened through the shell. In the reference corpus the paths inside one plan directory
  appeared as `Edit.file_path` **2378** times, `Write.file_path` **762**, `Read.file_path` **740**,
  `Grep.path` **39** - the instrument was watching the smallest channel. Worse, *executing* a step in
  that project is an `Edit` that flips a `[ ]` checkbox to `[x]`, so the single event the metric
  existed to detect was the one event it could not see; and shell content reads (`head`, `sed`, `cat`,
  `Get-Content`, `Select-String`) carry no `file_path` field at all, so no tool-name scan sees them.
  The headline moved from "42% of these artifacts are never opened" to **3.8%** once every channel was
  counted and the population cleaned. The sensitivity across channel subsets on the same mature
  population - Read only **41.0%**, plus shell reads **25.6%**, plus search and subagent reads but no
  `Edit` **11.5%**, all channels **3.8%** - is the finding: every variant that admits non-Read
  evidence destroys the original figure. A second, independent error rode along with it, **population
  contamination**: the denominator was "any directory named `<ticket>_*`", which swept in crash logs,
  screenshots, research notes and an owner voice memo, and **17 of 126** directories held no plan at
  all. Define the population by what the artifact *is*, never by where it sits. So: before claiming an
  artifact is unread, enumerate every consumption channel, prefer a channel-union count, and state
  which channels it included. A single-channel count is not evidence.

## Step 2 - Run the extractor

```
python "$env:CLAUDE_PLUGIN_ROOT/tools/mine-agent-transcripts.py" --root <transcript-dir> --out <output-dir> [--since YYYY-MM-DD] [--until YYYY-MM-DD]
```

Stack-agnostic on purpose - it reads Claude Code transcripts, which every project has, and references
no language or toolchain. Exit codes: 0 report written, 1 error, 2 cannot verify (root missing or
empty). A project may wrap it in its own operator entry point; the wrapper must forward those codes
rather than collapsing them.

## Step 3 - Record a baseline before changing anything

Write the numbers down before the first edit, in the ticket or wherever the work is tracked. At
minimum: unique requests, cached input volume, the median and p90 context size at compaction, the hard
failure rate and the soft-band rate, and the wall clock of whatever gate battery the project runs.

A baseline recorded after the change is not a baseline.

## Step 4 - Read the result against what it can actually prove

Two traps, both of which produced a confident wrong answer in the reference project:

- **A window that mostly predates the change measures nothing.** Re-run no sooner than two weeks after
  the change is live. A one-day delta is the old corpus plus one day, and that day is usually the work
  itself. If the interval has not elapsed, report the partial measurement and name which figures need
  the full window - do not present a carry-forward as an effect.
- **A number that did not move can still be the right number.** If nothing has landed that would move
  it, an unchanged metric is evidence the metric is measuring the right thing.

## Step 5 - Decide gate, compress, or nothing

Feed the result into [AI_USAGE.md](../../rules/AI_USAGE.md) §5. A finding earns a mechanical gate only
when a defect actually reached the owner; otherwise it is compressed to one line and a pointer, or
dropped. Record what you dropped and the measurement that killed it, in the project's own record -
a refuted recommendation that stays undocumented gets re-proposed every audit.

**Check the subagent tier before anything else, because it is the largest single lever this measurement
can reach.** A harness's built-in general-purpose agent has no definition file, so it cannot carry a model
pin and takes the session's default - the most expensive tier - and the mining pass shows the tier split
and the per-type spawn counts side by side. The rule is [AI_USAGE.md](../../rules/AI_USAGE.md) §3, "route
a subagent to a tier deliberately". Two cautions specific to reading it *here*: the miner records a
spawn's `subagent_type` and a message's authoring model **separately and never correlates them**, so
"these spawns ran on that tier" is a deduction and must be labelled one; and the tier split is an output
figure, while cached input dominates the bill - do not present a tier saving as a bill saving without
both.

Watch the counter-metric too. Anything that narrows what the agent reads raises the risk of editing
against partial context, so track the failed-edit rate alongside the saving.

---

## Done means

- [ ] The extractor ran and its output path is cited, not paraphrased.
- [ ] The five corrections in step 1 are in force - if you used a different tool, you verified all five.
- [ ] Any "this artifact is never read" claim names the consumption channels it counted and its
      sensitivity across them, and its population is defined by what the artifact is.
- [ ] A baseline exists from before the change, with a date.
- [ ] Every figure presented is labelled as measured-now or as needing a longer window.
- [ ] Each finding ends as a gate, a one-line rule with a pointer, or a recorded decision not to act.

## Guardrails

- Never fit the measurement to the expected answer. If a band comes out wider than the one you were
  reproducing, report the definition difference - do not tune it until it matches.
- Never argue context hygiene on quality grounds unless you measured quality degrading with context
  size. Attaching a real fix to a false rationale is how the fix gets reverted later.
- Do not spend the measurement on prose. Output is a minor term in the bill and chat language is the
  owner's preference, not a cost lever.
- The transcript corpus gets pruned. A re-run over "the same window" can legitimately return fewer
  sessions; check the session counts before calling a shortfall an extractor defect.
