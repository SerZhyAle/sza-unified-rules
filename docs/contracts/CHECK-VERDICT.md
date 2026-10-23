# CHECK-VERDICT - pointer

| Field | Value |
| --- | --- |
| Contract | `CHECK-VERDICT` |
| Version | 0.13, draft |
| Home | Shared catalog, `automated-checks/`; resolution is in CLAUDE.md |
| Role | Scoped producer: `tools/tests/contract-sync.tests.ps1` only |

The suite reports one final verdict with executed test counts, runs remaining cases after a failure,
and refuses unavailable prerequisites with exit 2. Follow section 2, the 2026-10-17 amendment and the
2026-10-18 clarification. Other scripts retain their documented exit vocabularies; this scoped adoption
does not certify them. Catalog vectors are not available; see the S0008 audit for local evidence.
