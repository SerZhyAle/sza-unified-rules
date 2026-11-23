# History: internal_ip_manager

## Spread-back applied 2026-07-23

Ran SPREAD_BACK_PROMPT in `p:\WINDOWS\internal_IP_manager` as a **NEW** repo (no prior contrib record).
Consumption model = **REFERENCE** (repo `CLAUDE.md` links to the canon, keeps only deltas locally; no
mirror). The repo already carried a mature "Universal Agent Kit"-adapted `CLAUDE.md` that predated the
canon.

**Changed in the repo:**
- **`CLAUDE.md`** - added a **"Unified Rules (canon)"** section (consumption model = REFERENCE, canon
  path, the Overlay A source-shape-only / internal-unshipped-tool DIVERGE, run-and-observe evidence
  ladder). Replaced the "AI assistant working method (Universal Agent Kit)" restated-universals intro
  with a pointer to `Unified_Rules/AI_USAGE.md`, keeping only the repo deltas (skill routing, `tasks/`
  ticket lifecycle, verification tags, project facts). Reconciled drift against the live tree:
  AppSettings now carries the router-sync settings (was "Currently just `IpRange`"); added
  `RouterClient.vb` + `RouterSync.vb` to the architecture map (TASK-6, absent before); `Form1.vb` line
  count corrected ~535 -> ~650; "What this is" now mentions the router DHCP sync.

**Open questions - status:**
- **Zero git history / initial commit** - RAISED to owner (not auto-resolved); a first commit bundles
  the whole repo, an owner decision.
- **Internal-only by design** - recorded as a DIVERGE; treated as deliberate.

**Verification (fresh run, PowerShell - dotnet not on the Bash PATH here):**
- `dotnet build internal_IP_manager.sln -c Release` -> **Build succeeded, 0 Warning(s), 0 Error(s)**,
  exit 0.

**Canon fixes needed (none blocking):** one PROPOSED core edit (Overlay A "internal / private tool"
note) - left for an owner-run canon session, not applied from this repo's session.

## Canon adoption 2026-07-27

Adopted as the `sza` plugin (consumption model **reference**), committed. `.sza-canon.json` declares role
**internal**: no remote, no tags, no CI, no site, no store. Most checks are legitimately N/A - a shape, not a
gap, and now written down so the gate degrades instead of inventing channels.

Fixed: the `CHANGELOG.md` heading is now `## [Unreleased]`, so the ledger is the shape it claims to be; 127
prose em-dashes across the docs, the worst style backlog in the portfolio.

Compliance gate: **0 errors**, 1 warning (`docs/` has no index).

## Canon reconcile 2026-08-02 - agent-process propagation

Canon **2026.07.27 -> 2026.08.02**, core digest `sha256:dae220bf..` -> `sha256:6c247452..`. Stamp
updated; the adoption model is unchanged. The upstream change is [AI_USAGE.md](../../AI_USAGE.md) only -
the agent-process findings propagated from FastMediaSorter mob_v2 under its ticket S1342 - so the
staleness ladder's "re-read only the changed rule docs" path applies and no full re-adoption was run.
Nothing in `rules/` touched packaging, release, channels or layout, and no divergence was found
between the new bullets and this repo's own rules file.

Deliberately has no in-repo memory store - its rules file says creating one would fork the shared
store - so §4 is inert by an existing decision rather than by absence, and the new bullets must not be
read as an invitation to create one. Role is `internal`, so the surface and channel checks stay out of
scope; the applicable additions are §1's threshold and §2's closure invariants.

Verification: `check-compliance: internal_IP_manager - 0 error(s), 1 warning(s) (overlay A, canon 2026.08.02)` - warnings are pre-existing and none was introduced here.

## Canon reconcile 2026-08-05 - measurement channels and ungated routing

Canon **2026.08.02 -> 2026.08.05**, core digest `sha256:6c247452..` -> `sha256:8d33fdab..`. Stamp updated;
the adoption model is unchanged. Upstream: [AI_USAGE.md](../../AI_USAGE.md) §3 and §5, plus the `agent-cost`
skill, which sits outside the digest. Two findings from the FastMediaSorter mob_v2 process retrospective of
2026-08-05, recorded in full in [fastmediasorter_mob_v2.md](../fastmediasorter_mob_v2.md) - **consumption
cannot be counted by tool name** (a `Read`-only scan of an artifact that is also edited, searched or opened
through the shell watches the smallest channel; the reference figure moved from 42% to 3.8% once every
channel was counted) and **a size-tier command ladder written as prose does not route anything** (434
invocations, the cheapest tier chosen 0 times; the remedy is an advisory `UserPromptSubmit` nudge, kept
always-exit-0, with no saving claimed yet). The staleness ladder's "re-read only the changed rule docs" path
applies, no full re-adoption was run, and nothing in `rules/` touched packaging, release, channels or layout.

Finding 2 has a target here and is one step worse than the finding describes: `/quick` and `/fix` exist
among thirteen commands, `.claude/settings.json` declares no hooks, and `CLAUDE.md` does not order the
commands by size at all - so there is not even the prose that the measurement showed to be insufficient.
Whoever writes the routing nudge here writes the ordering at the same time. Carried as an owner decision,
not applied from this session.

Verification: `check-compliance: internal_IP_manager - 0 error(s), 1 warning(s) (overlay A, canon 2026.08.05)` -
the warning is pre-existing and none was introduced here.

## Canon re-sync 2026-09-03 - the internal case, now at zero

Run from the canon repo against `P:\WINDOWS\internal_IP_manager` (`check-compliance.ps1 -RepoRoot`).

**Same uncommitted-stamp story as OneClickRunner.** The committed stamp read `2026.07.27` while the
working tree held an uncommitted bump to `2026.08.18.1` from 2026-08-18, so this record's last entry was
2026-08-05 even though the reconcile had been done. Folded in and carried to `2026.09.03.3`.

**Reconciled against `Canon update 2026-08-28`.** Nothing binds: no lock queue, no ticket store with a
single write path, no closure facade, no unattended batch, one locale. The repo's shape is still the one
this record was written to capture - an internal tool with **no remote, no tags, no CI, no site, no
store** - so the new gate-placement rule's escape hatch (a project with no release boundary substitutes
CI-only) has nothing to attach to either. The commit for this re-sync is therefore local only; there is
no remote to push to, and that is the shape, not a gap.

**Drift closed in this pass (SZA-LAY03).** `docs/` held four method documents - `SPEC_LIFECYCLE.md`,
`VALIDATION.md`, `CODE_QUALITY.md`, `AGENT_MEMORY.md` - and no index, so a reader landing in the folder
got a file list and no map. Added `docs/README.md`: one row per document saying what question it answers,
plus the pointer that none of them restate the canon.

**Evidence.** `check-compliance.ps1 -RepoRoot P:/WINDOWS/internal_IP_manager` before -> `0 error(s), 2
warning(s)`; after -> **`0 error(s), 0 warning(s)`**, exit 0.

## Re-sync owed 2026-10-02 - stamp 2026.09.06.1 against canon 2026.09.30.1; nothing to commit

Read-only pass over `P:\WINDOWS\internal_IP_manager` (overlay A, role internal, 0 commits since 2026-09-06) with
`check-compliance.ps1`. Re-measured 2026-10-02: `0 error(s), 1 warning(s)`, the warning being `SZA-CANON03`. The
stamp (`2026.09.06.1`, `adoptedOn` 2026-08-18) is committed, with no uncommitted bump. **No re-sync was run;
nothing in the repo was edited.**

**The dirty tree and the verdict.** Only an untracked `.vscode/` (a per-machine editor tint; the hub gitignored the
same file on 2026-09-03). **Safe to commit: nothing to commit.** Add `.vscode/` to `.gitignore` if the owner wants.

### What a re-sync must reconcile - the smallest of all

The shape has no release boundary, no remote, no tags and no test suite, so INVARIANT 4 and 5, RELEASE §2 and §4,
the contract gate and the registry's site half are **not applicable by shape**; the re-sync should record that, as
the 2026-09-03 entry did. Owed:

- **DOCUMENTATION_CONCEPT §6, mandatory half:** `docs/` holds 6 files including the `README.md` index, so a 6-row
  registry.
- **SECURITY_AND_PRIVACY §7:** the permission inventory is empty and dated; the network inventory has **one real
  row** - outbound ICMP ping and scan of a user-typed range, concurrency 20, no listening port, nothing leaves the
  LAN - so the "nothing to list" shortcut does not apply.
- **Contracts:** classify the repo and declare `NO-ROLE` unless it shares the CSV schema (`ipnew.txt` is
  user-authored data, so INVARIANT 10 "a reader for every version" applies if it does).
- **Stale kit copies:** `docs/` holds an old `VALIDATION` of 95 lines against the kit's 331.
- **Stamp:** refresh `adoptedOn`.

## Promotion campaign (2026-10-09)

- Internal tool with no remote: no promotion ticket, by canon [PROMOTION](../../PROMOTION.md) section 8.

## In-app help (2026-10-16)

- Ticket `tasks/TASK-8-in-app-help.md` (Draft, priority 20), created by the canon session from the owner's request for F1 and a `?` button in every product ([UI_UX](../../UI_UX.md) §7, contract `CONTEXT-HELP` 0.1). Two windows (`Form1`, `FormSettings`), English-only UI, no site: the layer form is the likely fit; five owner decisions are in the ticket.

## Canon delivery reconciliation 2026-10-17 (S4307)

- Installed plugin `2026.1017.1` from published canon `2026.10.17.1` (`d06a64a`). The harness counts Done and Skipped as finished and preserves the phase-counter suffix.
- Re-read the changed canon guidance for delivery, documentation, localization, layout and sealed contracts. Existing product implementation and contract catch-up work remains owned by the recorded project tickets; this delivery check does not certify every product contract.
- Re-stamped through `restamp-canon.ps1` against the installed plugin reader: version, freshly computed core digest and reconciledOn move together; adoptedOn and project-specific fields stay unchanged.
- Compliance for internal_IP_manager: 0 error(s), 1 warning(s) before; 0 error(s), 0 warning(s) after; exit 0. Canon freshness findings cleared.

## Test lab report (2026-10-23)

- Ticket `tasks/TASK-11-test-lab-report.md` (Draft, not queued), created by the canon session from the owner's order of 2026-10-23 to collect what every project knows about its hardware, emulators and test practice (contract `TEST-LAB` 0.1, draft). Documentation only: the product files one inventory report and a pointer; no code, test or harness changes. Reports to the Windows profile owner (FMS_Win). The repo's `CLAUDE.md` does not yet name the catalog; the first run that creates `docs/contracts/` adds that line.

## Fast checks between releases (2026-10-29)

- Ticket `tasks/TASK-12-fast-checks-between-releases.md` (Approved, first in `tasks/README.md`; the repo has no queue), created by the canon session from the owner's order of 2026-10-29 to switch off full builds and tests longer than 5 s between releases (canon TESTING_AND_QA section 2, highest priority). The tool has no tests, so the fast tier is grep and a direct look at the diff (plus an optional small static script), `dotnet build` and the `/verify` run-and-observe move to the pre-flight of `build.ps1 publish`, and `CLAUDE.md`, the command files and `docs/VALIDATION.md` are reworded to match.

## Canon re-sync 2026-11-12 (ticket TASK-0007)

Canon **2026.10.17.1 -> 2026.11.12.3**, core digest `sha256:b467aefe..` -> `sha256:af1470e6..` (recomputed with `check-compliance.ps1 -PrintDigest`). Staleness ladder: digest differs, last reconciliation 26 days old, so a warn-level re-sync: the changed rule docs were re-read (`git diff d06a64a..HEAD -- rules`: CONTRACTS, SECURITY_AND_PRIVACY, DOCUMENTATION_CONCEPT, UI_UX read in full diff; the release, CI, site and channel documents do not apply to a tool with no release boundary) and `version`, `coreDigest` and `reconciledOn` were written together; `adoptedOn` is untouched. `restamp-canon.ps1`, named in the 2026-10-17 entry, is not in plugin 2026.1112.3, so the three fields were written by hand (REPO-STAMP rule 8).

**What the changed rules bind here.**

- DOCUMENTATION_CONCEPT section 6, mandatory half: `docs/DOCUMENT_REGISTRY.jsonl` now has one record per file of `docs/` (23, topic, area, change triggers, role), checked in both directions by a direct read (0 missing, 0 unregistered). The stamp declares it with `docRegistryShape` 1 and `docRegistryFile`. The record shape follows `tools/docs/check-documents.py` of the canon (`topic`, `area`, `update_triggers`, `role`); the harness `document_registry/validate.ps1` uses a different, site-oriented shape (`id`, `title`, `category`, ...) and would not accept this file - a canon inconsistency, listed below.
- SECURITY_AND_PRIVACY sections 7 and 9: `docs/SECURITY.md` holds the permission inventory (empty, dated, plus capability rows), the network inventory (ICMP, reverse DNS, TP-Link router client; no listening port) and the untrusted-input result for `ipnew.txt` and router replies. Two checks are recorded as not met: no size cap on `ipnew.txt` or router replies, and no worst-case bound test (the tool has no tests by design).
- UI_UX: failure dialogs now say what happened plus one next step with the exception text as secondary details (`UserMessages.vb`); literal hex colours moved to a palette module holding the shared day tones (`Palette.vb`). The hit-target floor is now governed by `UI-SIZING` (32 logical units pointer, 48 touch for covered controls); the toolbar strip is declared 25 px high, so the measurement and any change stay with the existing remediation ticket for the unified UI contracts, not this one.
- CONTRACTS: the repo holds no role beyond the index in `docs/contracts/README.md`; `docs/contracts/NO-ROLE.md` records that `ipnew.txt` and `settings.json` are private data and that `LAN-DISCOVERY` does not apply.

**Verification.** `check-compliance: internal_IP_manager - 0 error(s), 0 warning(s) (overlay A, canon 2026.11.12.3)`, exit 0, 0.64 s. `build.ps1 check` exit 0. Not built and not run until the release.

**Canon fixes needed (none applied from this session).**

1. Two registry record shapes exist (`check-documents.py` versus `document_registry/validate.ps1`) and `docRegistryShape` has no defined values; no tool reads the stamp key.
2. The plugin ships no `restamp-canon.ps1`, though the 2026-10-17 entry of this record names one.

## Record split 2026-11-18 (canon ticket S0120)

Every section of this file dated before this one was moved here verbatim from [../internal_ip_manager.md](../internal_ip_manager.md) when the record was split into facts and history. A line number quoted inside such a section counts lines of the record as it was before the move; relative links were deepened by one `../`; nothing else changed.


## Canon re-sync 26-11-22 01:45 (ticket INTIPM-0021)

Canon **2026.11.12.3 -> 2026.11.21.1**, core digest `sha256:af1470e6.. -> sha256:9fc6d1e6..`, and `canon.docDigests` (all 20 rule documents) recorded in `.sza-canon.json` (`schemaVersion: "1.0"`, `reconciledOn: "2026-11-22"`, `adoptedOn: "2026-08-18"` preserved).

**What was reconciled and run:**

- Re-read all 20 canon rule documents (`canon.docDigests` was absent before this run) against the `internal` Overlay A desktop shape.
- Ran `adopt-canon` Step 6a (`init-task-flow.ps1`, `release-queue.ps1 -Seed -Release 1 -Apply`, `pq register`, `register-spec-commands.ps1`): added `tools/harness.ps1`, `r0`-`r3`, `rs`, `rm`, `rw`, `tasks/TICKET_TEMPLATE.md`, and `tasks/RELEASE_{QUEUE,READY,DONE}.md` (21 ready + 2 queued tickets).
- Ran `contract-sync` for the five `behind` rule-adoption and documentation-quality rows (`REPO-STAMP` 0.14, `RULE-DELIVERY` 0.13, `HARNESS-PROFILE` 0.21, `REPO-LAYOUT` 0.11, `DOC-INTERNAL-QUALITY` 0.13), updating `docs/contracts/` pointers, `docs/contracts/README.md`, and `internal-ip` rows in `P:\Contracts\_meta\REGISTRY.md`.
- Kept `commands.compileCheck` absent in `.sza-profile.json` (`HARNESS-PROFILE` 0.15 declared absence, matching `CLAUDE.md`'s 5 s line). Left `SZA-SEC05` (`src/UiTokens.vb` in `.gitignore`) out of scope under `INTIPM-0022`, and left `partial` UI rows with `INTIPM-0009`/`INTIPM-0014`/`INTIPM-0017`.
- Updated `rules/contrib/internal_IP_manager.md` in place (5 local commits present, no remote; task-flow harness and release ledger live).

**Verification:** `check-compliance.ps1 -IncludeUntracked` cleared `SZA-CANON03` (`0 error(s), 1 warning(s)`, remaining warning is `SZA-SEC05` under `INTIPM-0022`); `contract-lag.ps1 -Product internal-ip` reports `behind 0`; `spec_catalog/validate.ps1`, `release-queue -Validate`, `r0.ps1 -DryRun`, `document_registry/validate.ps1`, and `build.ps1 check` all pass.

## Recommendation decisions 2026-11-23 (CANONR-0172)

Overlay A permits the private file-copy shape. The product decision for IP Manager includes GitHub Releases and WinGet, with the family recorded in PACKAGE-VERSIONING 0.10.

### Candidate core edits (PROPOSED - apply only on owner instruction)

- **PLATFORM_OVERLAYS.md, Overlay A**: add a one-line "internal / private tool" note - an Overlay A
  source-shape app may legitimately ship to **no public channel**, with no version shape and no frozen
  anchors (distribution = a file copy to a local/shared path). Distinguishes "unshipped internal tool"
  from the already-documented "no-installer but still winget+Store" variant. Prevents an agent from
  fabricating a version stamp / winget manifest for a tool that deliberately has none. Evidence:
  `build.ps1:32-33,61-81`.

### Candidate NEW docs (not in any shared doc yet)
- None required.
