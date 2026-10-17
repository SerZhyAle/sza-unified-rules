# S0005_button-size-modes

Status: completed for contract publication; implementation and captures remain per-product work.
Date: 2026-10-17

## Request and scope

The portfolio owner requires buttons to accommodate compact, ordinary and very large interface sizes
on every platform, with smaller or larger text, eligible icon-only compact presentation and scalable
vector icons. Amend BUTTONS rather than creating a second button authority. Preserve touch/pointer
minimum targets, content-fit widths, safe dialog captions and accessibility text scaling.

## Changes

BUTTONS 1.3 introduces shared scale tokens, proportional text/glyph/geometry scaling, distinct interface,
text and device scales, vector rendering at requested resolution, compact label eligibility and size-range
evidence. ICON-RENDER will delegate scaled button sizes instead of treating its ordinary tiers as ceilings.

## Validation

- `pwsh -NoProfile -File tools/check-rules.ps1`: exit 0;
  `check-rules: OK (22 core docs, 14 contrib docs)`.
- `pwsh -NoProfile -File tools/check-contracts.ps1`: exit 1; the same two unrelated errors remain:
  expired FastMediaSorter_Lite blanket exception and missing artifacts key in broadcast-resource/README.md.
  Existing stale/lag warnings remain. No finding targets the changed contracts.
- BUTTONS 1.3 and ICON-RENDER 0.23 agree with their registry entries. Vocabulary and generated glyph
  artifacts are unchanged. No consumer adoption version is advanced.

## Limits

No product implementation or rendered evidence is claimed. Interface-size component support is mandatory;
whether a product exposes a user size selector is its product decision. Captions remain mandatory for
dialog answers and safety-critical commands. Compact visuals retain touch/pointer target floors.
