# S0010 - Position FMS_Win as three optional components

Status: complete (canon and task dispatch; consuming implementation remains Draft)
Date: 2026-10-20

## Owner decision

FMS_Win has three independently optional product roles: media viewer/sorter, local SFTP folder
sharing service, and Media Exchange Server. Present two installation intents: a viewer with optional
server functions (including the Microsoft Store channel), or a server with an optional viewer
(from the product website). Documentation briefly mentions alternative installation profiles and
uses the same positioning on product pages, the shared portal and sza.od.ua.

This authorizes canon edits and delivery of local implementation tickets. Product implementation,
public publishing and releases are not performed by this dispatch.

## Findings

- Windows `docs/guides/POSITIONING.md` sections 1-3 and the local naming/positioning rule currently
  make FileDO the third pillar and the viewer the core of every package. FileDO remains an optional
  capability of folder sharing, rather than one of these three top-level components.
- The old Q155-2 decision limits Media Exchange Server to a planned reservation. The new owner
  decision supersedes that presentation restriction; actual shipped availability still needs proof.
  Exchange server code and recent implementation tickets exist, which alone does not prove release.
- The shared media-exchange portal belongs to FastMediaSorter Android. The portfolio website
  belongs to `sites.google.comsiteszaodua`; `SerZhyAle.github.io` only carries host-root infrastructure.
- `SITE-REPRESENTATION` rules 1-5 already cover the single positioning source, order and limitations.
  No catalog amendment is required for this product decision; declare focused install profiles in
  the product source and retain truthful channel-specific capability boundaries.

## Work and evidence

- Update PROMOTION and DOCUMENTATION_CONCEPT with optional component/profile/channel discipline.
- Record the dated product decision in the Windows contribution record.
- Deliver registered, linked Draft tickets to Windows, Android/portal, FMS_Web and the portfolio hub.
- Verify ticket registration, preserved existing content and fresh canon validation.

Scratch and command output: `temp/S0010_fms-win-three-components/`.

## Dispatch and validation

| Repository / surface | Registered Draft ticket |
| --- | --- |
| FMS_Win | 249, `docs/specifications/249_SPECIFICATION_FMS_WIN_THREE_COMPONENTS.md` |
| FastMediaSorter Android / shared portal | S4408, `PLAN/S4408_fms-win-three-components.md` |
| FMS_Web | S0037, `PLAN/S0037_fms-win-three-components.md` |
| sza.od.ua | S0003, `PLAN/S0003_fms-win-three-components.md` |

Windows and hub tickets use their existing manual indexes; Windows also has a release-queue entry.
Android registration used the project's insert CLI; FMS_Web used capture-draft with the verbatim
owner request. Existing journal records and index/queue content were preserved. Every task names
the other three, the shared decision, local surfaces, dependencies and evidence requirements.

Fresh validation:

- `pwsh -NoProfile -File tools/check-rules.ps1`: exit 0, OK, 22 core and 14 contribution docs.
- Android and FMS_Web ticket-store validate commands: each exit 0, 9 OK, 0 WARN, 0 FAIL.
- Android release-queue `-Validate`: exit 0, 228 tickets, no drift.
- FMS_Web release-queue `-Validate`: exit 0, 37 tickets, no drift.
- Windows `tools/Get-Spec.ps1 -Id 249`: exit 0, registered Draft file found.
- `py temp/S0010_fms-win-three-components/verify.py`: exit 0, PASS, 64 conditions covering
  four registrations, cross-references, required scope, prior record preservation and queue placement.
- `git diff --check`: exit 0.

No catalog files, product code, rendered pages or published listings changed. Hook behavior did
not change, so hook smoke suites are not applicable. No release or deployment ran; delivery versions
remain managed by deploy.ps1. Creating these tasks establishes neither implementation nor publication.
