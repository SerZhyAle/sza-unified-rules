# Documentation maintenance

The published registry, `DOCUMENT_REGISTRY.jsonl`, declares the maintained developer and forker corpus.
`document-corpus.json` owns its roots and explicit exclusions. Historical project surveys are frozen;
their exclusion is deliberate, rather than a claim that their old links and typography remain current.

Local engineering records have an independent ignored registry under `dev/`. Initialize it in a new
checkout with `python tools/docs/check-documents.py --init-local --register --render`. The local corpus
configuration declares the existing engineering roots and excludes frozen completed tickets. Neither
the published registry nor its generated map lists local records. A clone without a local corpus checks
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

Negative fixtures: `python tools/tests/documentation.tests.py`. Registered generated documents currently
consist of the two documentation maps; an additional render role without a generator fails. Other
maintained documents are authored sources, including the harness's schema reference.
