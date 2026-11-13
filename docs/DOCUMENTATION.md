# Documentation maintenance

The published registry, `DOCUMENT_REGISTRY.jsonl`, declares the maintained developer and forker corpus.
`document-corpus.json` owns its roots and explicit exclusions. Historical project surveys are frozen;
their exclusion is deliberate, rather than a claim that their old links and typography remain current.

Local engineering records have an independent ignored registry under `dev/`. Initialize it in a new
checkout with `python tools/docs/check-documents.py --init-local --register --render`. The local corpus
configuration declares the existing engineering roots and excludes frozen completed tickets and every
ticket file (`PLAN/S<nnnn>_*.md`): the ledger records a ticket, so a capture needs no registry row and
no step is owed after one. Other documents under `PLAN/` - queue files, phase notes, attachments - are
registered like any document. A checkout whose local corpus was written before this exclusion adds the
second ignore entry from `LOCAL_IGNORE` in `tools/docs/check-documents.py` and runs `--register --render`
once; the tickets' rows drop out. Neither the published registry nor its generated map lists local records. A clone without a local corpus checks
the published corpus only; the verdict reports how many corpora it inspected.

Each record declares its path, topic, product area, update triggers and source/render role. When adding
documents, run `python tools/docs/check-documents.py --register --render`, then review the registry
metadata. Preserve more specific existing topics and triggers. Regenerate maps with `--render` after
registry edits; map edits never become authoritative.

Run `python tools/docs/check-documents.py` to check both declared corpora, or select a corpus with
`--config docs/document-corpus.json`. The gate checks reverse coverage, record uniqueness, generated-map
drift, relative Markdown/reference/HTML links and heading anchors, local assets, HTTPS references and
offline embedding and mechanical house style in prose. Published image assets must be tracked; ignored local assets must stay in their
own corpus. Fenced and inline syntax examples are not navigable references. HTTPS links are checked
statically; the gate makes no network requests and cannot prove remote availability or permanence.
Executable code and command examples keep their own syntax. The canon's house-style/reference gate
remains `pwsh -NoProfile -File tools/check-rules.ps1`; it does not certify prose outside its rule corpus.

Negative fixtures: `python tools/tests/documentation.tests.py`. The optional `generated` list in the corpus
configuration declares entries with `pattern`, `generator` and `check` as non-empty strings; patterns match
paths like `ignore` patterns. Matching documents are registered as `render`, as is the documentation map;
an undeclared render or a generated document recorded as `source` fails. The generator and drift-check
commands are named for the repository's own gates; this checker neither runs nor parses them. A generated
document can instead be excluded with an ignore whose reason names its generator and check.
