# History: filler_mob

## Canon state of this repository, 2026-11-13

The remote stamp declares canon `2026.11.09.1` with core digest `sha256:9abe1d23..` (adopted 2026-11-09, reconciled 2026-11-10, read from the remote `.sza-canon.json`). The canon at the time of this refresh is `2026.11.13.4` (this repository's `CANON_VERSION`, the same as the installed plugin `2026.1113.4`), so the stamp is behind it. The owner's report compared it with `2026.11.13.2` and names it as warning `SZA-CANON03`. The re-sync is that repository's own adopt-canon run. This record does not write a stamp it does not own, and it did not run `check-compliance` from that repository.

## Canon adoption 2026-11-10

Completion of the bootstrap adoption against canon **2026.11.10.1** (stamp version `2026.11.09.1`, core digest `sha256:9abe1d23..` equal to the installed canon's, so no re-sync and no version write by hand per REPO-STAMP rule 8), reference model, overlay B.

- **What changed in the repo:** `CLAUDE.md` rewritten from the bootstrap stub (canon pointer, catalog named once, upstream and parity as standing law, owner decisions taken and open, the release plan's six decisions, the layout, verification between releases); `AGENTS.md` replaced by the delegating stub; `.sza-canon.json` gained `schemaVersion`, `reconciledOn`, `contribRecord` and the LICENSE exemption; `.gitignore` gained the missing leak globs; the day-0 scaffold wrote the plan files `RELEASE_READY.md`, `RELEASE_QUEUE_DONE.md`, `TICKET_TEMPLATE.md`, the empty archive and burned-ids stores, and the launchers `r0`-`r3`, `rs`, `rm`, `rw`; the eight spec command forwarders were written to `.claude/commands/`.
- **Owner decisions closed:** none - the ticket forbids closing them by assumption; they are listed above.
- **Ticket id scheme:** `Sxxxx`, the harness default, cited with the repository name across repositories.
- **Divergences recorded:** `PLAN/` tracked; `LICENSE` absent under a dated exemption.
- **Catalog:** no registry rows written - the product holds no contract today; the first declared contract brings its rows and its `docs/contracts/` pointer.
- **Compliance gate:** 3 error(s), 1 warning(s) before; after, run from the installed plugin: 0 error(s), 1 warning(s), exit 0 - the warning is `SZA-CANON06` for this record, which that gate resolves under the installed plugin's `rules/`; run from the canon checkout (same core digest `9abe1d23..`, where this record exists): 0 error(s), 0 warning(s), exit 0. The installed-plugin warning clears when the canon repository publishes this record.
- **Remains:** S0002-S0007 as ticketed; the open owner decisions above.
- **Verification:** see the repository's S0001 `## Last Audit`.

## Record split 2026-11-18 (canon ticket S0120)

Every section of this file dated before this one was moved here verbatim from [../filler_mob.md](../filler_mob.md) when the record was split into facts and history. A line number quoted inside such a section counts lines of the record as it was before the move; relative links were deepened by one `../`; nothing else changed.

## Promotion campaign 2026-11-22 (FILLER-0064)

- `FILLER-0064` (`PLAN/FILLER-0064_product-promotion-campaign.md`): baseline measured (GitHub `SerZhyAle/Filler_Android`: MIT, 0 stars, 0 forks, 0 releases, `homepage: null`, `usesCustomOpenGraphImage: true`, 11 topics; 14d views 1, clones 50; live Pages root 404, `privacy.html` 200, `sitemap.xml` 200, host-root `robots.txt` 200 without `Filler_Android`), positioning worksheet and derived-fields audit written from `docs/SPECIFICATION_POSITIONING.md`, shape-A channels and tactical phases recorded, cross-repo `SEARCH-INDEXING` ticket filed as `hub:HUBSIT-0028`, parked in `BlockByOtherTask` (`FILLER-0022`, `FILLER-0060`, `FILLER-0061`, `hub:HUBSIT-0028`).
- `FILLER-0061` (`PLAN/FILLER-0061_sourceforge-channel-row.md`): owner reversed the 2026-11-13 Google-Play-only rule in quiz mode (2026-11-22) to plan SourceForge (`Files` + `Git` at mount point `git`, tentative slug `filler-android`) and GitHub Releases (signed APKs + `.sha256`); updated `CLAUDE.md`, `.sza-canon.json` (`channels: ["github", "play"]`), `tools/site/check-site.ps1`, `docs/releases/channels.json`, `tools/release/preflight.ps1` (`.sha256` sidecars), `docs/contracts/` (`SOURCEFORGE-CHANNEL.md`, `INSTALL-TRUST.md`, `README.md`), `P:\Contracts\_meta\REGISTRY.md` (`SOURCEFORGE-CHANNEL` `partial 0.1`, `INSTALL-TRUST` reopened `pending`), and `FILLER-0064`, and parked `FILLER-0065` (`Draft`) for `INSTALL-TRUST` adoption; parked `FILLER-0061` in `BlockByOtherTask` (`FILLER-0060`, `FILLER-0022`, `FILLER-0056`) pending `identity-manifest.json`, first release assets, live landing, and the owner's `A-GO` sitting.
