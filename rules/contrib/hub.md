# Contribution: hub / sza.od.ua (Web overlay - GitHub Pages + Google Sites bridge, single property) -> Unified_Rules
Source repo: P:\WEB\sites.google.comsiteszaodua | Date: 2026-07-23
Read: README, NEW_PROJECT_CHECKLIST, SITE_CONFIGURATION, DOCUMENTATION_CONCEPT, LOCALIZATION, REPOSITORY_LAYOUT; deduped against: all six existing contrib files (all Windows/Android app repos - none is a website).

The hub is the SZA portfolio website (`sza.od.ua`): a hand-authored single-page site served from the repo root via GitHub Pages and mirrored into Google Sites. It is the **first web-shape repo** to reach `contrib/` - every earlier record is a Windows desktop or Android app, so the store/winget/MSIX machinery they document does not apply here at all. The genuinely new material is the **Web overlay in practice** (Pages + custom domain + Google-Sites-bridge, site-update vs release, no version/changelog) and the fact that this one repo is also the **shared-kit home**: it hosts both the `Unified_Rules/` canon and the `kit/` web style system that the rest of the portfolio consumes. SITE_CONFIGURATION.md was itself extracted from this repo, so most plumbing is CONFIRM, not new.

## Overlay facts (verified against this repo)

- **Source root & release-mechanics.** Live site is the repo-root `index.html` served by GitHub Pages, plus root `assets/` (project thumbnails + kit logo). `embed.html` is the Google-Sites-embedded variant and is byte-identical to `index.html` (`diff -q index.html embed.html` -> identical, both 36317 bytes). Release-mechanics = `deploy.bat` (stage all, dated auto-commit, push `main`); Pages rebuilds on push. No `docs/` source - Pages serves from root. (evidence: `deploy.bat`, `CNAME`, root `ls`)
- **Version shape (+ padding choice).** None. A site is not a released artifact: no version string, no `CHANGELOG.md`, no tags. Each publish is a dated auto-commit `Auto-publish portfolio: <date> <time>` (`deploy.bat:35`); git log shows `Auto-publish portfolio: 07/19/2026 5:01:43`. This is the "site update, not a release" case (SITE_CONFIGURATION §4). (evidence: `git log --oneline`, `deploy.bat:34-36`)
- **Channels + listing files.** Two publish surfaces for one page: (1) GitHub Pages at `serzhyale.github.io/sza.od.ua/embed.html`, custom-domained to `sza.od.ua`; (2) Google Sites at `sites.google.com/site/szaodua`, where the repo is the *published render* (`google-sites-publish/` + `embed.html`) - edit the Sites source, re-publish, then commit the export; never hand-edit the mirror. Apex/origin forwarding lives in `github-root-redirect/`. (evidence: `CNAME` = `sza.od.ua`, `README.md:3,15`, `CURRENT_STATE.md:6`, SITE_CONFIGURATION §3)
- **Frozen anchors.** Custom domain `sza.od.ua` (root `CNAME`); Pages origin `serzhyale.github.io/sza.od.ua`; repo slug `github.com/SerZhyAle/sza.od.ua` (`deploy.bat:26` remote). Changing the domain or slug orphans inbound links and breaks the Google Sites embed. No package id / signing key / module path - a site has no install to tie an update to. (evidence: `CNAME`, `deploy.bat:26`, `git remote -v`)
- **Editions + parity mechanism.** None - single web property, single page. Distinct role instead: this repo is the **shared-kit home** for the whole portfolio - it hosts the `Unified_Rules/` canon and the `kit/` web style system (`SZA-WEB-STYLE-GUIDE.md`, `sza-kit.css`, `SZA-PROJECT-PAGE-CONTENT-SPEC.md`, `kit/prompts/`). No other contrib repo hosts a shared kit; the coupling to the rest of the portfolio is "these repos read my kits", not code or release-artifact parity. (evidence: `ls Unified_Rules kit`)

## Channel-matrix rows (this project)

Format: Channel | Trigger | Cost | Auth | Signer | Listing source | Frozen anchor | Verify live
- GitHub Pages (hub site) | push to `main` (`deploy.bat` / auto-publish) | [PUBLIC] free | `git` keyring, `GITHUB_TOKEN` cleared first (`deploy.bat:5`) | n/a (static HTML) | root `index.html` / `embed.html` + `assets/` | domain `sza.od.ua` + Pages origin | `sza.od.ua` renders the latest page within ~1 min of push
- Google Sites (embed) | manual re-publish of the Google Sites source, then commit the export | [PUBLIC] free | Google account | n/a | `google-sites-publish/` + `embed.html` (published render) | Sites URL `sites.google.com/site/szaodua` | embedded page matches the repo render; `google-sites-publish/` never hand-edited in place

## Deltas by document

### SITE_CONFIGURATION.md
- CONFIRM (the doc is written from this repo): every plumbing reference resolves here - `deploy.bat` (§4), root-served Pages (§1), `CNAME` = `sza.od.ua` (§2), `google-sites-publish/` + `embed.html` bridge (§3), `github-root-redirect/` (§3). Nothing to add; this repo is the doc's own hub reference.
- CORRECT->fixed in repo (not a divergence, a gap): §1 requires `.nojekyll` at the served root for hand-authored HTML so Pages serves files verbatim. It was absent. Reconciled this session by adding root `.nojekyll`. (No underscore dirs today, so Jekyll was not actively mangling anything - the file makes the guarantee explicit and future-proof.)

### DOCUMENTATION_CONCEPT.md / LOCALIZATION.md
- CONFIRM: the site's user-facing prose is RU-first (`GOOGLE_SITES_TEXT.md`, `SITE_DRAFT_RU.md`), matching the portfolio's EN/RU/UK ceiling with per-surface coverage. No parity-enforced string resource applies - a hand-authored HTML page has no string-catalog tool; the "one authoritative source, rendered per language" rule holds via the Google Sites source being the authority.

## No delta

Core docs verified with nothing to add: REPOSITORY_LAYOUT (root-served static site fits the layout model), RELEASE_AND_DISTRIBUTION / CHANNEL_MATRIX / WINDOWS_PACKAGING (no releases, no store, no installer - N/A for a site), TESTING_AND_QA (no build/test suite; the gate here is `Unified_Rules/tools/check-rules.ps1` for the canon, and visual review for the page), SECURITY_AND_PRIVACY (static site, no secrets, `.gitignore` drops `*.gsite`/`*.gdoc` Drive pointers and `.research/`), SUPPORT_AND_FEEDBACK / GITHUB_INTERACTION / AUTHOR / AI_USAGE (portfolio-wide, no hub delta).

## Candidate core edits (PROPOSED - apply only on owner instruction)

- **REPOSITORY_LAYOUT.md or SITE_CONFIGURATION.md**: none required. The "shared-kit home" role (one repo hosting `Unified_Rules/` + `kit/`) is repo-specific, not a universal rule - it belongs in this record, not the core.

## Candidate NEW docs (not in any shared doc yet)

- None required. The Web overlay is already carried by SITE_CONFIGURATION.md.

## Open questions for the owner

- **Canon co-hosting.** `Unified_Rules/` currently ships inside the hub repo, so it is published to Pages along with the site. The spread-back model treats the canon as read-only from *target* repos, but here it is not a separate repo. Keep it co-hosted, or split the canon into its own repo (e.g. `universal-agent-kit` neighbour) so the site deploy and the canon have independent clocks?
- **`index.html` / `embed.html` duplication.** The two are byte-identical today (maintained in lockstep by hand). Should one be the canonical source and the other a generated copy (to remove the drift risk of editing one and forgetting the other), or is the duplication intentional (two stable entry-point URLs)?

## Spread-back applied 2026-07-23

Applied the SZA Unified Rules to this repo (the canon home + web hub). Consumption model: **REFERENCE** (the canon lives in-repo at `Unified_Rules/`; nothing mirrored).

What changed:
- Created root `CLAUDE.md` - the repo had no agent-rules file. It points at the canon, states the dual role (canon home + web hub + kit home), records the Web-overlay facts above, and defers all universal rules to the canon.
- Added root `.nojekyll` - closes the SITE_CONFIGURATION §1 gap (hand-authored HTML served verbatim by Pages).
- Created this contrib record (first Web-shape entry in `contrib/`).
- Marked the hub row Done in `SPREAD_BACK_PROMPT.md`.

Questions closed:
- Consumption model -> REFERENCE (mechanical, canon is in-repo).
- `.nojekyll` gap -> fixed with evidence (no underscore dirs; file added for the verbatim guarantee).

What remains (owner decisions, see Open questions above): canon co-hosting vs split; `index.html`/`embed.html` de-duplication.

Verification: `pwsh -File Unified_Rules/tools/check-rules.ps1` -> exit 0 (see the session report for output). No canon-core doc was edited except `SPREAD_BACK_PROMPT.md` (the target table).
