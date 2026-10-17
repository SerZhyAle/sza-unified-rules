# S0006_ui-decisions

Status: completed for contract publication; product implementation and real UI evidence remain per-product work.
Date: 2026-10-17

## Accepted decisions

The owner answered all sixteen UI review questions. The Latin choice letters below preserve the answers.

| Question | Choice | Required outcome |
| --- | --- | --- |
| 1 | A | Useful semantic icons; simple obvious answers/actions may be text-only without an exception. |
| 2 | B | All buttons in a visual row use the tallest button's height, including multiline captions. |
| 3 | B | Explicit compact mode may shrink hit targets, including touch; declare and test supported sizes. |
| 4 | A | Stable surface input profile; do not reflow for every mouse/touch event. |
| 5 | A | Checkbox, name and glyph toggle on every platform; recognized scrolling cancels activation. |
| 6 | A | Shared interface scaling; text-only accessibility enlargement need not enlarge icons proportionally. |
| 7 | A | Reserve the widest known button-state content width to prevent neighbor movement. |
| 8 | A | Semantic segmented controls and virtual keyboards may use equal-sized parts. |
| 9 | A | Keep primary commands visible; overflow secondary commands by panel policy; dialog answers stay visible. |
| 10 | A | Optional packed groups may reflow; retain active-header visibility and feasible vertical anchor. |
| 11 | A | Omit explanations that merely repeat obvious checkbox captions. |
| 12 | A | Short hover/focus help; full persistent help on activation, one authored source. |
| 13 | B | Navigation is required for every settings surface, including small utilities. |
| 14 | B | Every product must supply the complete About/resources/diagnostic set. |
| 15 | A | Warm 150 ms / first 500 ms budgets use p95; investigate outliers and block repeated delays. |
| 16 | A | Permanent supported variants live in standards/design records; temporary debt has a dated migration plan. |

## Scope and versioning

Synchronize all current UI contracts, the canon, discovery and registry. Preserve historical logs and
consumer implementation rows. BUTTONS, BOOLEAN-OPTION and SETTINGS-NAVIGATION need major versions because
existing mandatory presentation/activation/coverage expectations change. UI-SIZING is a shared new
authority for size/input profiles; other contracts delegate instead of restating conflicting floors.

## Validation

- Fresh `pwsh -NoProfile -File tools/check-rules.ps1`: exit 0;
  `check-rules: OK (22 core docs, 14 contrib docs)`.
- Fresh `pwsh -NoProfile -File tools/check-contracts.ps1`: exit 1, the same existing errors only:
  expired FastMediaSorter_Lite blanket exception (2026-10-15) and missing artifacts key in
  broadcast-resource/README.md. Stale/lag warnings remain. No finding targets changed contracts.
- Registry: 69 contracts; 65 domain declarations. Current headers agree with registry versions.
- No implementation, screenshot or measured UI behavior is claimed. Product registry implementation
  rows and existing exception due dates are untouched.

## Result

All sixteen selections are reflected in current normative text. Added UI-SIZING 1.0; published
BUTTONS 2.0, BOOLEAN-OPTION 2.0, COLLAPSIBLE-GROUP 1.1 and SETTINGS-NAVIGATION 2.0; synchronized
APP-SETTINGS 0.7, WINDOWS-UI 0.9, ICON-RENDER 0.24 and PAGE-STYLE 3.0. The owner-selected compact
touch reduction has no newly invented numeric floor: products must declare and test actual supported
limits. Shared sizing, permanent variants and temporary dated migration have explicit precedence.
