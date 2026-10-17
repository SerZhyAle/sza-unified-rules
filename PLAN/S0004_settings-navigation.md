# S0004_settings-navigation

Status: completed for contract publication; implementation and measured evidence remain per-product work.
Date: 2026-10-17

## Findings and scope

APP-SETTINGS already requires a vertical page list, About last, language/theme on the first page,
shared page anatomy, license/privacy and diagnostics. WINDOWS-UI already requires glyphs, visible
indentation, remembered context and batched page presentation, with 150 ms repeat / 500 ms first-visit
budgets. ICON-RENDER permits per-destination identity colors but does not require a consistent mode.

Publish mandatory SETTINGS-NAVIGATION 1.0 to consolidate these with the owner's explicit short labels,
one child level, consistent colored/mono icon policy, resource-complete About, compact input-specific
targets and stable responsive content. Preserve commit models and user state. Adapt narrow layouts
without losing the logical start-side menu. Do not claim consumer implementation or captures.

## Validation

- `pwsh -NoProfile -File tools/check-rules.ps1`: exit 0;
  `check-rules: OK (22 core docs, 14 contrib docs)`.
- `pwsh -NoProfile -File tools/check-contracts.ps1`: exit 1, the same two unrelated existing errors:
  expired FastMediaSorter_Lite blanket exception and missing artifacts key in broadcast-resource/README.md.
  No finding targets the changed contracts; existing stale/lag warnings remain. Catalog: 68 registry
  contracts and 64 domain declarations.
- SETTINGS-NAVIGATION 1.0, APP-SETTINGS 0.6, WINDOWS-UI 0.8 and ICON-RENDER 0.22 headers agree with
  the registry. Consumer implementation versions and conformance claims are not advanced.

## Result and limits

The shared contract requires compact left/start navigation, consistent recognizable colored or mono
glyphs, one child level, main/advanced/About order, applicable resources and companion links, and one
coherent page frame with measured 150 ms repeat / 500 ms first-visit budgets. Narrow displays retain
the menu through a documented drawer/navigation-view adaptation. Real captures, reference hardware,
locale coverage and timing samples are required before a product claims conformance; none are invented.
