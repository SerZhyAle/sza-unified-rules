---
# Contribution: <ProjectName> (<overlay letter(s) + notable shape>) -> Unified_Rules
Source repo: <path> | Date: <YYYY-MM-DD>
Read: <core docs read>; deduped against: contrib/<existing files>.md
---

One paragraph: what the project is, which overlay(s)/shapes it uses, and what is *genuinely new* here.
Material already saturated by earlier contrib files is CONFIRM - name those files and drop the detail.

## Overlay facts (verified against this repo)

The four overlay facts + editions, each with evidence (file:line or a command output):

- **Source root & release-mechanics.** .. (evidence: ..)
- **Version shape (+ padding choice).** .. (evidence: ..)
- **Channels + listing files.** .. (evidence: ..)
- **Frozen anchors.** .. (evidence: ..)
- **Editions + parity mechanism.** .. or "None - single edition". Name the shape by the glossary:
  flavor / dual-runtime build variant / co-shipped companion binary / companion editor extension /
  edition / consumed release artifact. (evidence: ..)

## Channel-matrix rows (this project)

Format: Channel | Trigger | Cost | Auth | Signer | Listing source | Frozen anchor | Verify live
- .. (evidence per row)

## Deltas by document

One subsection per core doc that has deltas. Each delta starts with a verdict:
ADD (new universal rule) / DIVERGE (valid alternative to the core) / CORRECT (the core is wrong) /
CONFIRM (matches the core - keep only if it settles an open tension, otherwise drop).

### <DOC_NAME>.md
- ADD (<one-line claim>): body, then evidence.

## No delta

Core docs verified with nothing to add: <list>.

## Candidate core edits (PROPOSED - apply only on owner instruction)

- **<target doc + section>**: the universal rule to fold in; the failure it prevents; evidence.

## Candidate NEW docs (not in any shared doc yet)

- <name + justification, or "None required.">

## Open questions for the owner

- <project-specific decisions the shared docs cannot make>
