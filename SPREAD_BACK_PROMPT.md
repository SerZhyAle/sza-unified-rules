# Spread-back implementation prompt

The one prompt the owner runs in **each repository** (existing or new) to adopt the Unified Rules
there. Copy the block below into a Claude Code session started in the target repo. The canon is never
edited from that session (except the contrib record, step 7) - rule fixes come back here in their own
session.

## Target repos and their contrib records

| Repo | Contrib record | Done |
| --- | --- | --- |
| `P:\WINDOWS\FastMediaSorter_Lite` | `contrib/fastmediasorter_lite.md` | [ ] |
| `P:\ANDROID\FastMediaSorter_mob_v2` | `contrib/fastmediasorter_mob_v2.md` | [ ] |
| `P:\WINDOWS\FileDo` | `contrib/filedo.md` | [ ] |
| `P:\WINDOWS\EPUB_2_HTML` | `contrib/epub_2_html.md` | [ ] |
| `P:\WINDOWS\Streams_Player` | `contrib/streams_player.md` | [ ] |
| `P:\WINDOWS\CyrFlip` | `contrib/cyrflip.md` | [ ] |
| a new repo | create from `contrib/TEMPLATE.md` | - |

Mark the Done column here after each repo's spread-back commit lands.

## The prompt

```text
Spread the SZA Unified Rules into this repository.

Canon (source of truth, read-only for this session except step 7):
P:\WEB\sites.google.comsiteszaodua\Unified_Rules

0. Mode. If <canon>/contrib/ has a record for this repo, this is an EXISTING repo - read that record
   first (overlay facts, channel rows, open questions). If not, this is a NEW repo - follow
   <canon>/NEW_PROJECT_CHECKLIST.md top to bottom instead of steps 2-5, then continue from step 6.

1. Read the canon README.md (structure, consumption model, read order), then the canon docs that
   apply to this repo's overlay and shape.

2. Choose the consumption model (README "How a project consumes these rules"):
   - Prefer REFERENCE: the repo's rules file links to the canon path; only project-specific decisions
     stay local.
   - MIRROR only if the repo must be self-contained: copy the needed docs into docs/guides/ with the
     sync marker (canon git short-sha + date). A mirror is a render target - never edited in place.

3. Update this repo's agent rules file (CLAUDE.md and/or AGENTS.md):
   - Add the canon pointer and this repo's overlay/shape facts (from the contrib record).
   - Remove restated universal rules that now live in the canon - keep only deltas and repo specifics.
   - Verify every kept claim against the live tree; fix statements that contradict it (stale paths,
     gitignored-vs-committed mismatches).

4. Close this repo's open questions from the contrib record. Mechanical fixes: do them now with
   evidence. Owner decisions: ask me in question-with-options mode, then apply my call.

5. Reconcile drift. Where the repo diverges from the canon: fix the repo, or - if the divergence is
   legitimate - keep it and record it as a DIVERGE delta in the contrib record. Never silently ignore
   a divergence.

6. Verify with evidence (canon TESTING_AND_QA rules): run this repo's build and gates, cite exit codes
   and output. No completion claim without a fresh run.

7. Record the result in the canon: append a dated "## Spread-back applied <YYYY-MM-DD>" section to
   this repo's contrib record (what changed, which questions closed, what remains). For a NEW repo,
   create the contrib record from <canon>/contrib/TEMPLATE.md first.

8. Commit in THIS repo per its conventions (English message, co-author trailer); push only if the
   repo's flow requires it. Do not commit the canon repo - list needed canon fixes in your report
   instead, I will apply them in a canon session and run its tools/check-rules.ps1 gate.

Chat with me in Russian; files, code, and commits in English. If a canon rule looks wrong for this
repo, push back once with evidence, then execute my decision.
```

## Notes

- One repo per session; do not batch several repos into one run - each has its own gates and its own
  commit.
- After all existing repos are done, the remaining consumers of the canon are new projects
  (NEW_PROJECT_CHECKLIST.md is their front door) and the per-repo contrib records are the live map of
  legitimate divergences.
