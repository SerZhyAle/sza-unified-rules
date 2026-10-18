# S0009 - Update the contract core from project recommendations

Status: complete (pre-existing catalog expiry finding retained)
Date: 2026-10-19

## Authority and scope

The portfolio owner requested a contract-core update from project recommendations. This authorizes
catalog decisions in this canon session, including cross-owner amendments. Review proposals since
the 2026-10-17 consolidation and unresolved earlier recommendations. Preserve submitted documents,
append reasoned decisions, version accepted changes and keep product adoption claims unchanged.
Product code, other repositories' task stores, releases and deployment are outside this request.

## Work and evidence

1. Inventory proposals and distinguish historical decisions from outstanding recommendations.
2. Read current contracts; accept compatible improvements, narrow conflicting wording explicitly.
3. Update dated normative amendments, headers, contract registry rows and generated artifacts.
4. Verify preservation of implementation/exception rows, vector hashes and generated output.
5. Run fresh catalog and canon checks; report existing findings separately.

Scratch, backups, inventory and command output: `temp/S0009_contract-core-recommendations/`.
Baseline catalog check: exit 1; one pre-existing expired FastMediaSorter_Lite exception (2026-10-15),
two warnings. No implementation conformance is inferred from publication of contract text.

## Result

Resolved six proposals: five new submissions dated 2026-10-18 and the unresolved sealed-name proposal
dated 2026-09-30. Earlier accepted/rejected decisions remain history. The catalog's dated record is
`_meta/CONSOLIDATION-2026-10-19.md`; full backups and SHA-256 change manifest are in the scratch folder.
Twenty-eight catalog files were added or changed, with no pre-existing file deleted.

| Contract | Before | Current | Result |
| --- | --- | --- | --- |
| WINDOWS-UI | 0.9 | 0.10 | Final-width remeasurement, full-width vertical flows and proportionate spacing. |
| UI-SIZING | 1.0 | 1.1 | Keep shared pointer/touch/compact profiles; remeasure on explicit scale changes. |
| ICON-SET | 0.34 | 0.35 | Add app.tour with thirteen catalog names and generated glyph/catalog/gallery. |
| DEVICE-EXCHANGE | 1.4 | 1.5 | Adopt scoped administration vectors; safe clipboard authority, local audit and concurrent discovery/isolation. |
| LIVE-BROADCAST | 1.1 | 1.2 | Independent slots for multi-stream receivers; single-stream support retained. |
| FDSEC-FORMAT | 1.3 | 1.4 | Preserve portable names and distinguish destination limitations from damage. |
| FDSEC-BEHAVIOUR | 1.5 | 1.6 | Safe restore refusal or explicit replacement-name consent; preserve originals. |

Four proposals are partly accepted with written reasons; the tour and sealed-name proposals are accepted.
Unspecified alternate broadcast/clipboard commands are not made normative. The incorrect assertion
that authorized client directories must never receive access descriptors is explicitly rejected.
No consuming repository, implementation/verification/exception row, release or deployment was changed.
Product replay, generated FDSEC boundary vectors and rendered/runtime acceptance remain unverified.

## Fresh validation

- `python temp/S0009_contract-core-recommendations/finalize_catalog.py`: exit 0, 174 conditions,
  zero failed. Checks cover registry preservation, every original vector/provenance file, adopted
  corpus bytes, administration JSON framing, seven header/registry version pairs and tour data.
- Owner icon exporter with a staging CatalogRoot: exit 0, PASS; 326 meanings, 347 glyph files,
  38 decorated looks, eight themes, zero pruned files and zero contrast roles below 3:1.
  Only three changed generated files were published, byte for byte: app.tour.svg, CATALOG.md, gallery.html.
- `pwsh -NoProfile -File tools/check-rules.ps1`: exit 0, OK (22 core docs, 14 contrib docs).
- `pwsh -NoProfile -File tools/check-contracts.ps1`: exit 1, the same pre-existing CTR-EXPIRE
  finding for FastMediaSorter_Lite (expired 2026-10-15), two warnings. No new catalog errors remain.
  Lag increases from 181 to 190 rows because published versions advanced; product claims stayed unchanged.

The catalog is outside git and these catalog edits are live. Hook behavior and enforcement scripts
were untouched, so hook smoke suites were not required. CANON_VERSION and plugin version are unchanged.
