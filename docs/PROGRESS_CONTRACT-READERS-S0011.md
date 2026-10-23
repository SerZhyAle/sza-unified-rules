# S0011 - Contract reader and documentation evidence

Verified source scope on 2026-10-23 with PowerShell 7.6.6 and Python 3.10.11. Delivery and wider
TASK-FLOW claims remain separately owned by reviewed successor S0012, with review due 2026-12-31.
Neither deployment nor consuming-repository edits were authorized or performed.

| Scope item | Result and limits |
| --- | --- |
| 1. REPO-STAMP | Owned 0.13 amendment defines optional `schemaVersion`, absent = wire 1.0, and staged required-carrier migration only for an explicit future incompatible shape. Legacy stamps remain readable indefinitely. Template/adoption instructions emit the optional carrier. Actual repository stamp is unchanged. |
| 2. HARNESS-PROFILE | Owned 0.13 amendment defines the existing optional `version`; absent and `"1"` mean wire 1.0. Validate before merge. Higher MINOR is tolerated; unsupported MAJOR, malformed carriers and non-object documents refuse. Existing explicit/null/empty replacement and ledger defaults pass all regressions. |
| 3. Unknown role | `SZA-CANON08` reports the unknown value. Strict product checks, including the required overlay, still run. Unknown keys remain tolerated. |
| 4. Registry columns | Both tools use the shared header-name reader. Tests reorder all three tables and add unknown columns; pending/version reads stay correct. Expired exception negatives exit 1 and contain `CTR-EXPIRE`. Missing required headers exit 2. Legacy continuation rows retain the current table header across prose. |
| 5. Documentation | Published and ignored local registries are independent, with declared maintained roots, source/render roles, areas and triggers. Reverse coverage, file/heading links, assets, offline embedding, mechanical prose style and generated-map drift have positive/negative checks. Frozen surveys and archived tickets are explicitly excluded. Published registry/map contain no ignored local ticket paths. |
| 6. Catalog artifacts | Generated stamp/profile and age-ladder cases/verdicts live in the owned catalog domain, with contract versions, generator command and source/artifact SHA-256 hashes. Replay reads the catalog files. This is a scoped reader set, not every section 7 rung: real delivery and broader layout/writer evidence remain S0012. |
| 7. TASK-FLOW | Re-read section 5 and the existing partial 0.2 adoption row. G1/G3 remain scaffold workarounds; G6 remains narrowed; G2/G4/G5 were previously closed. The partial row and its 2026-10-07 date are unchanged. S0012 lists all previously unexercised rules; no full batch runner, live child or timeout evidence is inferred. |

Amendments preceded reader edits. Only the two owned contract headers/metadata and this repository's
adoption/exception rows changed in the catalog. Five source exceptions were closed with evidence;
their original 2026-12-31 deadlines were not extended. Separate delivery/harness evidence retains that
deadline. Other products' rows and the original TASK-FLOW adoption row are preserved.

| Command | Expected / actual | Exit |
| --- | --- | --- |
| `pwsh -NoProfile -File tools/tests/export-contract-vectors.ps1 -CatalogRoot <catalog>` | Generate only after assertions pass / `PASS (run=43 skipped=0)`, cases/verdicts/manifest written | 0 |
| `pwsh -NoProfile -File tools/tests/contract-reader.tests.ps1 -CatalogRoot <catalog>` | Catalog replay, hashes and registry negatives / `PASS (run=44 skipped=0)` | 0 |
| `pwsh -NoProfile -File tools/tests/contract-sync.tests.ps1` | Preserve existing behavior / `PASS (run=49 skipped=0)` | 0 |
| `python tools/tests/documentation.tests.py` | Corpus positive/negative fixtures / `PASS (run=12 skipped=0)` | 0 |
| `python tools/docs/check-documents.py` | Both real corpora / `PASS`, zero errors | 0 |
| `pwsh -NoProfile -File tools/check-rules.ps1` | Canon gate / `OK (22 core docs, 14 contrib docs)` | 0 |
| Catalog replay against a scratch catalog with altered `reader-cases.json` | Refuse corruption / hash mismatch, `COULD NOT VERIFY (run=0 skipped=0)` | 2 |
| Reader tests with nonexistent `-SourceRoot` | Refuse missing prerequisite / `COULD NOT VERIFY (run=0 skipped=0)` | 2 |
| Document gate with nonexistent `--config` | Refuse missing corpus / `COULD NOT VERIFY` | 2 |

Catalog artifact identity after the generation above. Superseded on 2026-10-23 by S0012: source files are
now hashed with CRLF read as LF and the artifacts were regenerated, so the three values below are no longer
current; see [PROGRESS_CONTRACT-DELIVERY-S0012.md](PROGRESS_CONTRACT-DELIVERY-S0012.md) for the reason and
the current values.

| Artifact in `rule-adoption/vectors/` | SHA-256 |
| --- | --- |
| `manifest.json` | `C3559786F3F26A649792AF5A6D65BD35312BD643CBC97F8E389FCC8CC8A35986` |
| `reader-cases.json` | `6E26F231A5EAD8358F45622C639182E549EAD87529993CECAC4F4B94EFD19CF6` |
| `reader-verdicts.json` | `F7AE5AD449CF71472253579035B536866F69D55A91DB7E096DDCDBCFD541BC11` |

The manifest also fingerprints every owning implementation file used by generation. A missing,
incomplete, corrupt or stale source/artifact set refuses verification. Catalog document versions are
REPO-STAMP 0.13, HARNESS-PROFILE 0.13 and the tested RULE-DELIVERY age rules 0.12.

Documentation gate limits: static Markdown/reference/HTML link and GitHub heading checks cover the
declared corpus syntax; no remote endpoint is contacted, and remote availability/permanence or natural
language grammar is not certified. Only the two documentation maps are declared generated documents;
additional render records without a generator fail. Negative tests include a missing registry entry,
missing/duplicate records, broken files/anchors/assets, untracked published assets, escaped paths,
HTTP/script/font/pixel embedding, altered maps, leaked ignored paths and independent local assets.

The source reader accepts supported additive data without modifying user files. The no-write checks
and existing writer/completion ledger-preservation tests pass. This does not prove any deployment,
re-adoption, full harness lifecycle or other product's implementation.
