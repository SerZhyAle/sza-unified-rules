# S0003_collapsible-group

Status: completed for contract publication; implementation and captures remain per-product work.
Date: 2026-10-17

## Scope

Publish mandatory COLLAPSIBLE-GROUP 1.0 as specified by the portfolio owner. Keep packing collapsed
headers into horizontal rows a documented per-screen choice. Require semantic topics, distinct header
background/type, current-state triangles, whole-header activation, in-flow full-width bodies, stable
viewport anchoring and no redundant wrapper for a single-topic screen/page.

## Integration

Index/register the shared contract. Route the canon and current Windows, settings, button and web
contracts to it. Make the distinction from command-button width rules and action disclosure glyphs
explicit. Do not claim consumer adoption, generated screenshots or reference-kit migration.

## Validation

- `pwsh -NoProfile -File tools/check-rules.ps1`: exit 0;
  `check-rules: OK (22 core docs, 14 contrib docs)`.
- `pwsh -NoProfile -File tools/check-contracts.ps1`: exit 1 with the same two unrelated existing errors:
  expired FastMediaSorter_Lite blanket exception and missing artifacts key in broadcast-resource/README.md.
  No error targets the changed contracts. Existing stale/lag warnings remain; 67 registered contracts,
  63 domain declarations.
- Current pointers and registry versions agree: COLLAPSIBLE-GROUP 1.0, WINDOWS-UI 0.7,
  APP-SETTINGS 0.5, BUTTONS 1.2, PAGE-STYLE 2.1 and ICON-RENDER 0.21.

## Limits

The reference web kit still draws the former action chevron; current rules explicitly require an
identified adapter until the kit is revised. No consumer versions or conformance claims are advanced.
The new triangle is a control state indicator, not a redefinition or redraw of shared action glyphs.
