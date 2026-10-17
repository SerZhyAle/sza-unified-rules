# S0007_contract-proposal-consolidation

Status: complete (pre-existing catalog expiry finding retained)
Date: 2026-10-17

## Owner instruction

Fold outstanding contract proposals into the catalog, update contract versions, and create new
conformance specifications in every affected repository. Preserve every project's right to request
a justified exception. This instruction authorizes the cross-owner catalog edits and ticket delivery;
it does not claim implementation or conformance in any consuming product.

## Work

1. Inventory proposals and distinguish open decisions from accepted, rejected and superseded history.
2. Resolve alternatives explicitly in dated normative amendments; preserve historical decisions.
3. Synchronize headers, discovery pages and contract-version registry rows, preserving implementation rows.
4. Deliver registered specifications through each repository's own ticket conventions.
5. Run fresh catalog and canon checks and verify delivery coverage.

## Evidence

Baseline catalog check: exit 1, three pre-existing errors (expired FastMediaSorter_Lite exception,
missing BROADCAST-RESOURCE artifacts key, missing UI-SIZING registry row), two warnings.
Initial canon working tree already contained edits to rules/README.md and rules/UI_UX.md and PLAN/S0001-S0006.
Backups, inventory, delivery manifest and validation output live in temp/S0007_contract-proposal-consolidation/.

## Delivery result

30 contract versions (including new MEDIA-VIEWER and WORKER-LAUNCH), 57 completed proposal decisions,
and 16 delivered specifications including the Android release-worktree mirror. The local delivery
manifest records each file, target set and CLI/manual-index result. Product code remains untouched.
The catalog consolidation record carries the permanent dispatch index and evidence limits.

## Fresh validation

- Dispatch/version/artifact verification: exit 0, 412 conditions, zero failed.
- `pwsh -NoProfile -File tools/check-rules.ps1`: exit 0, OK (22 core docs, 14 contrib docs).
- Icon exporter: exit 0, PASS; 325 meanings, 346 glyph files, 38 decorated looks, eight themes,
  three changed generated artifacts and no pruned files.
- `pwsh -NoProfile -File tools/check-contracts.ps1`: exit 1, one pre-existing CTR-EXPIRE finding
  (FastMediaSorter_Lite evidence exception expired 2026-10-15), two informational warnings.
  This is not a catalog PASS; the Windows task owns its review.
- Implementation, verification and exception registry sections remain text-equivalent to the initial
  snapshot. No product implementation or conformance test was claimed by task dispatch.
