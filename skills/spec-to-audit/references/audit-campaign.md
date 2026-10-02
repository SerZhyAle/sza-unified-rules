# The audit campaign - auditing a tree too large for one pass

Reference for the `spec-to-audit` skill, next to Sweep mode. A phase-boundary audit (Stage 3) judges one
change. A campaign judges code that did **not** change - the whole shipped tree before a major release - and
it is a process with a script at both ends, not a long session. Five repos arrived at this shape
independently; what follows is the common part, with no project's ticket scheme or language in it.

## Where this was measured

The projects' own measurements, quoted as evidence for the method, not as targets.

| Repo | Campaign | Measured |
| --- | --- | --- |
| FastMediaSorter_mob_v2 | 147 generated slice tickets, defect-class registry of 43 classes | 756 findings in the first 64 slices; 144 slices closed with 3 residuals at last count |
| EPUB_2_HTML | two campaigns four days apart, release path in scope | 138 findings, then 54 on the code the first wave's fixes had rewritten; 239 files, 0 uncovered, 0 held twice |
| FileDo | slice, manifest, fan-out, summary scripts | 420 findings in all; the redo wave over changed files alone still found 10 high |
| Streams_Player | audit tooling with an always-class and a switch-class | slicer, fan-out, summary and fixture tests; coverage rows committed with the verdict |
| FastMediaSorter_Lite | partition, fan-out, status scripts | long-run defects found that no per-change audit had reached |

## The method

1. **Scope is the shipped code AND the release path.** Workflows, packaging, installer and publish scripts
   are code users depend on. In one campaign the earlier audit had left the release path out and two of the
   six high findings were in it.
2. **Slice deterministically, by risk.** A script cuts the in-scope files into slices small enough to read
   line by line, ordered by a risk score (size, concurrency, I/O, parsing, destructive paths). Same input,
   same slices. **Parity pairs stay together** - a platform file and its twin, an edition's module and its
   port, markup and its code-behind - because a defect lives in the difference between them.
3. **Coverage is proven by a script with exit codes, not by status lines.** Every in-scope file belongs to
   exactly one slice: 0 uncovered, 0 duplicated. A file added after the cut becomes a **tail slice**, never
   a silent loss. Exit 0 only when every slice is closed and coverage holds; a distinct non-zero code for a
   file missing or listed twice. A manifest of per-file hashes also lets the script flag a closed slice
   whose file changed since.
4. **Slices are generated from one template.** Each child is a self-contained record: files, rules, the
   severity table, a `Last Audit` block. A defect in the method is fixed in the **template and the children
   regenerated** - never hand-edited one by one, which is how 110 un-started slices ended up carrying a
   stale gate list.
5. **Keep one live defect-class registry.** The first slice to meet a kind of defect names it; the
   **second** slice to meet it does not record another local fix - it opens a **tree-wide sweep ticket** and,
   when the kind is decidable by a script, a gate (DEVELOPMENT §9: a recurring defect becomes a gate). Slices
   still un-started read the registry again before they run.
6. **A finding whose action names a sweep is not closed until the roll-up confirms the sweep touched that
   site.** The roll-up script lists every such "assignment"; one that points at a sweep which was
   verified without ever naming the site is open, whatever the finding's own status says.
7. **Taxonomy: severity x confidence.** Severity as in `audit-verdict.md` (crash or data loss first);
   confidence says whether the finding was reproduced, read from code, or suspected. A high-severity
   low-confidence finding is a question for evidence, not a verdict.
8. **Inline-fix rule.** A slice fixes a finding in place only when the proof needs no owner machine: a
   failing-then-passing test, or behaviour-preserving by construction; a destructive path only with a
   black-box test. One slice's fixes at a time. Everything else becomes a ticket, filed by one orchestrating
   session that owns finding ids and dedupe.
9. **Re-audit the first third before fanning out the rest.** Read the early slices' output as a reviewer:
   are findings real, is the template asking the right questions, is the registry being used. Fixing the
   method at one third costs one third.
10. **A closed slice with zero findings over a large file is flagged as shallow.** The summary prints it
    with the file's line count; a clean verdict on 1 600 lines is a claim that needs a second read.
11. **Redo wave.** Code written to close a finding has been read by nobody but its author. After the fix
    wave, **every audited file changed since its slice closed is audited again**. Measured: the second
    campaign in one repo found a regression of an earlier fix and a release-blocking test failure; the redo
    wave in another found 10 high after the first pass was declared done.
12. **The campaign closes only on the roll-up's exit 0.** Not on the slice count, not on a status note. The
    check is red by design until the last slice closes, so it is declared hand-run and kept out of the
    per-change closure (DEVELOPMENT §15, place a gate by its subject).
13. **Owner device tests are drained once, after the campaign.** A static finding is proven by a build or an
    edit; state the proof level (`edit`, `build`, `unit`, `device`) per ticket so nothing a build proves waits
    for hardware. What really needs a device is batched into one Sweep-mode pass when the campaign ends,
    not interleaved with it.

## Driving it

- Slices run as parallel **read-only** auditors; one orchestrating session owns ids, dedupe and tickets. Put
  each auditor's exact file list in its own prompt - never point several at lines of one shared list.
- Re-run the roll-up after every wave, not once at the end; its output is the campaign's only progress
  figure.
- Write the campaign's own method fixes (template, registry, scripts) as tickets of the campaign, so the
  next campaign starts from the corrected template instead of from memory.
