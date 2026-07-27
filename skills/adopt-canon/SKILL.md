---
name: adopt-canon
description: Adopt the SZA Unified Rules canon in this repository - write the .sza-canon.json stamp, point the repo's agent-rules file at the canon instead of restating it, reconcile every divergence found, and record the result in the repo's contrib file. Also the re-sync path when the canon has changed since adoption. Use when asked to adopt, apply, spread, or sync the canon or the unified rules in a repo, to set up a new project against the conventions, or when check-compliance reports a missing or stale canon stamp.
---

# Adopt the canon in this repository

One repo per run. This replaces the old copy-paste spread-back prompt: the canon now travels with the session
as a plugin, so nothing is copied and nothing can drift silently.

The canon is **read-only** from this session, with exactly one exception: the repo's own record under
`rules/contrib/`. Rule fixes go back to the canon repo in their own session.

Canon: [README.md](../../rules/README.md) (consumption model),
[NEW_PROJECT_CHECKLIST.md](../../rules/NEW_PROJECT_CHECKLIST.md) (the new-repo front door),
[PLATFORM_OVERLAYS.md](../../rules/PLATFORM_OVERLAYS.md) (pick exactly one overlay),
[INVARIANTS.md](../../rules/INVARIANTS.md).

---

## Step 0 - Mode

- **`rules/contrib/<repo>.md` exists** -> this is an **existing** repo. Read that record first: overlay facts,
  channel rows, open questions, recorded divergences.
- **No record** -> this is a **new** repo. Follow
  [NEW_PROJECT_CHECKLIST.md](../../rules/NEW_PROJECT_CHECKLIST.md) top to bottom in place of steps 2-4, then
  continue from step 5, creating the record from `rules/contrib/TEMPLATE.md`.
- **A stamp already exists and the canon has moved on** -> this is a **re-sync**. Jump to step 6, then fix
  whatever the digest comparison surfaced.

## Step 1 - Read the repo before changing it

Read the current agent-rules file (`CLAUDE.md`, `AGENTS.md`, or both - where both exist, **stricter wins**),
the build and release scripts, `.github/workflows/`, and the channel folders. **The working tree is the
authority**; a contrib record is a hypothesis the filesystem confirms.

Run the compliance gate first, to get the real baseline rather than an assumed one:

```powershell
pwsh -File "$env:CLAUDE_PLUGIN_ROOT/tools/check-compliance.ps1"
```

## Step 2 - Choose the consumption model

- **Reference (strongly preferred).** The repo's rules file points at the canon and keeps only its own
  deltas. Nothing to sync; the rules cannot drift. **Now that the canon ships as a plugin, this works even in
  CI and for outside contributors** - which removes the one argument that ever justified the alternative.
- **Mirror (only when the repo must be genuinely self-contained).** Copy the needed docs into `docs/guides/`
  with a sync banner. A mirror is a **render target** - never edited in place. Fixes land in the canon first,
  then re-mirror.

```
<!-- Mirrored from Unified_Rules @ <canonVersion> digest:<first12> on <YYYY-MM-DD>. Edit the canonical copy, not this. -->
```

**A self-contained restatement is a fork, not a mirror.** If the repo declares that it deliberately duplicates
the canon so it "stays self-contained", that is the thing to fix - either delete the restated rules and keep
the pointer, or convert them into marked mirrors and re-sync. Record the choice as a DIVERGE delta.

## Step 3 - Write the stamp

Copy [templates/.sza-canon.json](../../templates/.sza-canon.json) to the repo root and fill it against the
live tree. This one file is what every other skill and the compliance gate read.

- `canon.version` - from `CANON_VERSION` at the plugin root.
- `canon.coreDigest` - recompute it; do not copy one from another repo.
  `pwsh -File "$env:CLAUDE_PLUGIN_ROOT/tools/check-compliance.ps1" -PrintDigest`
- `canon.model` - `reference` or `mirror`.
- `overlay` - exactly one, unless the repo has editions, in which case declare them too.
- `versionShape.tagRegex` - **take it from the release script's own validation regex or from CI**, never from
  prose. `null` when the repo has no tags.
- `versionShape.editionTagPrefixes` - any tag prefix on its own clock. Getting this wrong makes the version
  check fail on a perfectly good repo.
- `ledgerShape` - one of the four accepted shapes, or `none` when the repo ships nothing.
- `channels` - only channels with a committed manifest folder.
- `site` - the tree Pages actually serves. Confirm with
  `gh api repos/<owner>/<repo>/pages`, never by assuming root and `docs/` match.
- `exemptions` - each with a reason and, where it is temporary, an `until` date.

## Step 4 - Rewrite the repo's agent-rules file

- Add the canon pointer: the plugin, the overlay, the consumption model, the contrib record.
- **Delete every restated universal rule.** Keep only deltas and repo specifics - architecture, frozen
  anchors, build commands, known-broken gates, owner decisions.
- Verify every kept claim against the live tree. Fix statements that contradict it: stale paths,
  gitignored-versus-committed mismatches, a documented remap that the script does not actually perform.
- A rule that genuinely is a repo-specific delta but reads like a restatement gets an inline
  `<!-- canon-ok: <reason> -->` so the gate stops flagging it.

**What "restated" means in practice**: size is not the signal. A 500-line rules file that is all module
architecture is clean; a 130-line file that re-authors the language policy, the house style and the
find-safety rule is not. The rules with exactly one home in the canon are: working-tree-is-truth, when to
commit and push, the co-author trailer, English artifacts, chat language, the find-safety rule, the secrets
rule, build-is-not-a-release, mechanical versioning, the changelog shape, the house text style, the evidence
rule, and the no-trailing-summary rule.

## Step 5 - Close the open questions and reconcile drift

Take the open questions from the contrib record. **Mechanical fixes: do them now, with evidence.** Owner
decisions: ask in question-with-options form, then apply the answer.

Where the repo diverges from the canon: **fix the repo, or - if the divergence is legitimate - keep it and
record it as a DIVERGE delta.** Never silently ignore a divergence; that is how the canon rots.

If a canon rule looks wrong for this repo, push back once with evidence, then execute the decision. Collect
needed **canon fixes** in your report - do not edit the canon from this session.

## Step 6 - Re-sync (existing adoption, canon moved)

The staleness ladder, from the compliance gate:

- Digest equal -> nothing to do.
- Digest differs, version within one minor -> **warn**, with the list of rule docs whose per-file digest
  changed. Re-read exactly those, reconcile, then update `canon.version` and `canon.coreDigest`.
- Digest differs with a version gap of 2 or more, or `adoptedOn` older than 180 days -> **error**. Re-run this
  skill in full.

Note the digest deliberately covers the **rule docs only** - not `README.md`, not the spread prompt, not
`contrib/`. A change to one project's own record must never mark all eight repos stale.

## Step 7 - Verify with evidence

Run the repo's build and gates. Cite exit codes and output. **No completion claim without a fresh run.**
Re-run the compliance gate and show the before/after counts.

## Step 8 - Record and commit

- Append a dated `## Canon adoption <YYYY-MM-DD>` section to `rules/contrib/<repo>.md`: what changed, which
  questions closed, which divergences are now recorded, what remains.
- Commit **in the target repo** per its conventions - English message, co-author trailer. Push only if the
  repo's flow requires it.
- Report the canon fixes you found so they can be applied in a canon session.

---

## Done means

- [ ] `.sza-canon.json` exists at the repo root, complete, with a freshly computed digest.
- [ ] The agent-rules file points at the canon and restates nothing that has a canon home.
- [ ] Every divergence is either fixed or recorded as a DIVERGE delta with its reason.
- [ ] Every open question from the contrib record is closed or explicitly carried forward with an owner.
- [ ] The repo's own gates pass, with exit codes cited.
- [ ] The compliance gate's error count is zero, or every remaining error has a recorded exemption.
- [ ] The contrib record carries a dated adoption section.
- [ ] Needed canon fixes are listed in the report, and the canon itself was not edited.

## Guardrails

- One repo per run. Never batch several - each has its own gates and its own commit.
- The canon is read-only here, except this repo's contrib record.
- Never invent a fact for the stamp. A tag regex comes from the release script; the site root comes from the
  Pages API. An unknown value is asked about once, then written down.
- Adding a product to the hub is an owner decision, not a consequence of adopting the canon.
