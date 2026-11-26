# DOC-INTERNAL-QUALITY - pointer

| Field | Value |
| --- | --- |
| Contract | `DOC-INTERNAL-QUALITY` |
| Version | 0.13, draft; declared technical corpora |
| Home | Shared catalog, `documentation-quality/`; resolution is in CLAUDE.md |
| Role | Technical corpus: rules, skills, tooling documentation and contract pointers |

Section 2 and the 2026-10-17 amendment apply. Independent published and ignored local corpora have
machine-readable registries, reverse coverage and generated maps. Run `python tools/docs/check-documents.py`
for registry, link/anchor, asset, offline embedding, mechanical prose style and derivative checks.
[Documentation maintenance](../DOCUMENTATION.md) declares the roots, frozen exclusions and limitations.
The published registry never lists ignored local records. Negative fixtures exercise both corpora;
no remote-link availability or reference-product gate is claimed.

The clarifications of 0.11 to 0.13 hold as follows. The registry path is the one `docs/document-corpus.json`
names (items J, K); that check, `tools/docs/check-documents.py`, is the one that holds rules 2 and 3 over both
corpora (item L). The maintained corpus is the declared roots minus the reasoned ignore (item V). The one
generated file in it, `docs/DOCS_MAP.md`, is recorded `render`, its generator is the gate's own `--render` mode
and the gate's map comparison is its check (item W). A record may carry the optional `contract` field, and the
gate accepts a registry with or without it (item X). The frozen archive of item Q is the local corpus's
`PLAN/DONE` ignore.

For the repositories that run it, the shipped harness's `document_registry/validate.ps1` reads the local registry
their profile declares in `paths.localDocumentRegistry` (`HARNESS-PROFILE` rule 18, item K) and judges the
`generator` and `check` fields of a generated record (item W, CANONR-0235). A generated record with neither field
is an advisory there, because an adopter owes item W at its next alignment run, and an error under `-Strict`.
