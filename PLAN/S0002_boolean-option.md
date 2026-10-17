# S0002_boolean-option

Status: completed for contract publication; product implementation and captures remain per-product work.
Date: 2026-10-17

## Scope

Publish mandatory BOOLEAN-OPTION 1.0 for Windows, Android and web, as specified by the portfolio owner.
Use a leading visible checkbox, heading glyph when available, short name, conditional local help and
compact explanatory text. Heading activation toggles on Windows/web but not Android; Android scrolling
must not accidentally toggle. Preserve accessibility activation and settings commit semantics.

## Integration

Register and index the shared contract, route the UI/UX canon and Windows boolean pattern to it, and
clarify BUTTONS surface help versus local option help. Product migrations and actual screenshot generation
remain per-product work, not claims made by contract publication.

## Validation

- `pwsh -NoProfile -File tools/check-rules.ps1`: exit 0;
  `check-rules: OK (22 core docs, 14 contrib docs)`.
- `pwsh -NoProfile -File tools/check-contracts.ps1`: exit 1; 2 errors and 2 warnings.
  Errors are the existing expired FastMediaSorter_Lite blanket exception (2026-10-15) and missing
  artifacts key in broadcast-resource/README.md. No finding targets the changed contracts.
  The catalog reports 66 registered contracts and 62 domain declarations; warnings concern stale/lagging adoption.
- BOOLEAN-OPTION 1.0 is indexed and registered. BUTTONS 1.1 distinguishes local from surface help;
  WINDOWS-UI 0.6 and its duplicate domain header agree with the registry.

## Limits

No product is certified conformant and no screenshots are claimed. Existing boolean values and commit
models must survive migration. The contract requires real captures and both positive and negative input
checks, particularly Android scrolling versus deliberate checkbox activation.
