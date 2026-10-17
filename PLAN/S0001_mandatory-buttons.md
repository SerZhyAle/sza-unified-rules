# S0001_mandatory-buttons

Status: completed for contract publication; product migration and reference rendering are not performed here.
Date: 2026-10-17

## Request and decision

The portfolio owner requires cross-platform button unification to be mandatory rather than advisory.
Establish BUTTONS 1.0 as an active shared contract and route the canon to its normative requirements.

## Changes

- Add the buttons domain in the external catalog, its root index entry and contract registry row.
- Define behavior types, visual ranks, required glyphs, neutral dismissal, rectangular radius-4 shape,
  density profiles, intrinsic widths, horizontal wrapping, order, shortcuts and conformance evidence.
- Explicitly supersede conflicting optional button advice and platform button geometry in scope.
- Update UI_UX and its discovery entry; preserve historical owner-specific contract documents.
- Do not claim consumer adoption or generated screenshots that do not exist.

## Consolidation follow-up, 2026-10-17

The owner explicitly requested replacing scattered recommendations in the existing contracts.
WINDOWS-UI 0.5 section 11 and ICON-RENDER 0.20 section 14 now point to BUTTONS instead of presenting
optional alternative rules. Former text is preserved in clearly non-normative history files and old
document-log rows are retained. PAGE-STYLE 2.0 removes current pill/gold button advice and delegates
geometry, target sizes, flow and interaction to BUTTONS. Domain READMEs and contract registry versions
are synchronized; consumer adoption versions and exceptions are not falsified.

The hand-authored reference CSS remains the existing artifact; PAGE-STYLE explicitly requires an
identified BUTTONS adapter after the byte-identical kit until its revision. Byte identity or the previous
old-kit grace cannot establish button conformance. This task changes rules, not consuming applications.

## Validation

- Fresh `pwsh -NoProfile -File tools/check-rules.ps1`: exit 0;
  `check-rules: OK (22 core docs, 14 contrib docs)`.
- Fresh `pwsh -NoProfile -File tools/check-contracts.ps1`: exit 1; 2 errors, 2 warnings.
  Existing unrelated catalog findings: CTR-EXPIRE in the registry (FastMediaSorter_Lite blanket
  exception expired 2026-10-15); CTR-KEY in broadcast-resource/README.md (missing artifacts).
  Warnings report unverified and lagging consumer rows. No finding targets BUTTONS.
- Consolidation recheck on 2026-10-17: check-rules exit 0 with the same OK summary;
  check-contracts exit 1 with only the same two unrelated errors. Duplicate WINDOWS-UI headers,
  registry versions and relocated history links agree. Targeted consolidation assertions pass.

## Limits and follow-up

Product sessions must audit and implement BUTTONS, generate showcase captures and geometry/contrast/input
evidence, and maintain their own adoption and dated exception rows. This ticket publishes requirements;
it does not certify any product or supply rendered examples. Existing catalog errors remain with their
respective owners; they are not repaired by changing unrelated contracts or renewing exceptions here.
