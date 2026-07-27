---
name: feature-to-site
description: Propagate a finished feature to every user-facing surface - in-app strings, the ledger, README and its translations, the product site, support pages, listing sources, and the sza.od.ua hub - each locale in one edit, so nothing goes stale. This is the canon's ship-together surfaces manifest, the /docs-sync slot. Use after implementing a user-visible change, or when asked to "update the docs", "propagate this feature", "the site is out of date", "did I forget anything", "docs-sync", "update the README and the page".
---

# Feature to site - the ship-together fan-out

A feature is not done when it works. It is done when every surface that mentions it says the same thing, in
every locale that surface ships, **in one edit**. "EN now, RU and UK later" is the exact failure this exists
to prevent - so is the site page nobody remembered.

This is **free and reversible**: edit files, run generators, run parity audits, commit. It never tags, never
submits to a store console, and never runs a site deploy without explicit confirmation.

Boundary with [release](../release/SKILL.md): this runs at **feature** time and drafts the listing *sources*;
release runs at **release** time and trims, cuts and submits them. Doc and site changes ride a free build
commit **before** the tag.

Canon: [DOCUMENTATION_CONCEPT.md](../../rules/DOCUMENTATION_CONCEPT.md) (the manifest rule is §5),
[LOCALIZATION.md](../../rules/LOCALIZATION.md), [SITE_CONFIGURATION.md](../../rules/SITE_CONFIGURATION.md),
[SUPPORT_AND_FEEDBACK.md](../../rules/SUPPORT_AND_FEEDBACK.md).

---

## Step 0 - Classify

- **Internal refactor, zero user-visible delta** -> stop. A ledger bullet only if this project's ledger tracks
  internals.
- **User-visible behaviour change** -> the full procedure.
- **New capability, edition, or channel** -> the full procedure **plus** the hub review.

The test: *can a user see, do, or be surprised by this?* If yes, it is at least a behaviour change.

## Step 1 - Detect and print the surface list (always)

Never assume. Two repos in this portfolio are actively misleading if you guess.

1. **Remote.** No remote -> internal tool. Surfaces collapse to in-app strings + README + ledger; report the
   rest N/A with the reason and stop the site and hub branches.
2. **Pages config - the authoritative answer, never inferred:**
   `gh api repos/<owner>/<repo>/pages --jq '[.build_type,.source.branch,.source.path,.html_url,.cname]|@tsv'`
   - `legacy` + `/` -> **root HTML is the site**; any `docs/` HTML is unpublished staging.
   - `legacy` + `/docs` -> `docs/` is the site; root HTML is not served.
   - `workflow` -> read the Pages workflow: `upload-pages-artifact`'s `path:` is the real site root, and
     `on.push.paths:` tells you which edits actually redeploy.
   - Offline fallback, and say it is unverified: a Pages workflow file > `docs/index.html` + `docs/_config.yml`
     > root `index.html` + root `.nojekyll`.
3. **Generator before HTML.** If `tools/site/` or a `build-site` script exists, the served tree is **build
   output**: edit the copy deck and templates, re-run, commit the diff. Hand-editing generated HTML is a
   guaranteed silent revert. Run the generator's staleness check if it has one.
4. **Site locale model**: separate per-language files (`docs/<code>/index.html`) vs in-page blocks
   (`data-l` / `data-i18n` spans). Record the exact codes and flag any `ua`-vs-`uk` mismatch.
5. **Other locale sets**: `README*.md`, the app string catalog, `winget/*.locale.*.yaml`, the store listing.
   Build a per-surface locale table - **do not normalize them to one set.**
6. **Ledger shape**: root `CHANGELOG.md`, a dev-log, a "Version History" section inside the READMEs, a
   machine-validated feature inventory, or `generate_release_notes` with no ledger. Exactly one is
   authoritative.
7. **Channels**: each one found is one listing source to draft into.
8. **Existing manifest**: a repo release skill, `RELEASE.md`, `STORE_PUBLISHING.md`, `CLAUDE.md`/`AGENTS.md`.
   If a surface list already exists, **extend it** rather than writing a second one.
9. **Hub membership**: is this product a card on sza.od.ua?
10. **Cross-link obligation**: the kit's cross-linking map, and the "More tools by SZA" footer on the served
    index.
11. **The contrib record** `rules/contrib/<project>.md` - read it first, but treat it as a hypothesis the
    filesystem confirms. It can lag reality.

**Print the resolved surface list before touching anything.**

## Step 2 - Write the one sentence

Draft the feature as one **task-first** user sentence, in English, in the product's voice: *"iPhone photos
open now (HEIC, HEIF, AVIF)"*, not *"added an ISO-BMFF decoder path"*. Check it against the repo's glossary if
it has one. This sentence is the atom every later surface renders. **One name for the thing, everywhere.**

## Step 3 - In-app strings (if the feature has UI)

Add or edit keys **through the repo's parity-enforcing tool**, every shipped locale in one edit. Then run the
parity audit. A missing-locale exit is **fix-first**, never deferred, never downgraded to a warning.

## Step 4 - Ledger

One bullet, in this project's shape, in English. Where the project has no ledger, the **commit message is the
ledger** - write it as a user-facing note, because it becomes the release body.

## Step 5 - README and its translations

EN README first, then **every** localized README in the same edit. Absence of localized READMEs is not a gap
when the site carries the translation - the canon permits an EN-only README then.

## Step 6 - The product site

The step everyone skips.

- If a generator exists: edit the copy deck and template, re-run it, commit the regenerated tree.
- Otherwise: edit the served HTML for **every** language in lockstep.
- If the feature adds a limitation, permission, or risk, put the caveat **next to the affected action**, not
  in a footnote.
- Keep CTAs on **durable URLs** - `/releases/latest`, the package id, the store page. Never a hard-coded
  version. A release must not require a site edit.
- Keep the SEO block intact on any page touched: title, description, canonical, Open Graph, one `h1`, and an
  `hreflang` for each translated page.
- Mandatory pages must stay reachable from the served index: privacy, how-to or guide, support or contact.

## Step 7 - Support surfaces (conditional)

Touch the FAQ, how-to or guide page when the feature changes a task flow. Touch the privacy page when it
touches data, network, or a new permission. Touch the honest-limitations block when it adds one. A recurring
support question is a documentation defect.

## Step 8 - Listing sources (draft now, submit at release)

Update the listing **source** files so the release does not have to re-derive them from memory. The console
submission belongs to [store-publish](../store-publish/SKILL.md). Character caps are read from the console at
submit time, never hardcoded.

## Step 9 - The hub (conditional)

**A release alone changes nothing on the hub.** The hub carries no version, no "what's new", no download
button - by design. Do not churn it on every version.

A feature touches the hub only when it changes the one-sentence answer to *"what is this product"* - a new
platform, a new edition, a headline capability that makes the current card description wrong.

Three hard rules, and rule 2 is invisible from reading the markup:

1. The hub page and its embedded twin are kept **byte-identical by hand**. There is no generator and no gate.
   `diff -q index.html embed.html` must exit 0 **before** any deploy - state the hashes in your report.
2. **A card edit is four edits**: the inline English fallback in the card markup, plus the `en`, `ru` and `uk`
   dictionaries. `setLanguage()` overwrites `textContent` from the dictionary on load, so the inline text is
   only a pre-JS fallback - editing the card body alone is a **no-op at runtime**. These have already diverged
   in the live file.
3. Adding a product is an **owner decision**, not an automatic consequence of a repo existing - the hub is a
   curated index of current products, not a complete archive.

A new, renamed, or retired product additionally means: the kit's cross-link table, every sibling site's
"More tools by SZA" footer, and the hub repo's own README product list.

## Step 10 - Verify and report

Run the repo's drift gates, then the checklist below, then print the **surface table**:

| Surface | Source of truth or render target | Locales | Changed / N/A + reason |

**An unexplained "N/A" is a failure, not a pass** - that is exactly how a forgotten surface hides. Offer to
persist the table as `DOCS_SURFACES.md` in the repo; that materializes the manifest the canon requires.

---

## Done means

**One voice**
- [ ] The feature is named identically in the in-app string, the ledger, the README, the site copy and the
      listing draft. Prove it: grep the feature's noun across every touched file and read the hits.
- [ ] The bullet leads with the user-visible win, not the mechanism.

**Locale parity, per surface, in one commit**
- [ ] `git diff --name-only` contains the full sibling set for every touched surface.
- [ ] The repo's parity audit passes. A missing-locale exit blocks.
- [ ] No new locale code that disagrees with the rest of the repo - **one ISO 639-1 code per language across
      every surface**. Ukrainian is `uk` everywhere, never `ua` in one place and `uk` in another.
- [ ] The changelog and any contract docs are still English.

**The site is actually the site**
- [ ] The edited HTML is the tree Pages serves - restate the resolved `build_type/branch/path` and name the
      file.
- [ ] If generated: the generator was re-run, its staleness check is clean, and no generated file was
      hand-edited.
- [ ] Every language page changed, not just EN.
- [ ] The caveat sits next to the affected action.
- [ ] No hard-coded version in the diff.
- [ ] Privacy, how-to and support stay reachable from the served index.
- [ ] The SEO block is intact on every page touched.

**Ledger and release path**
- [ ] Exactly one ledger updated, in this project's shape. No second ledger invented.
- [ ] Listing sources carry the new text, ready for the next release. No console submission performed here.

**Hub and cross-links**
- [ ] The hub was touched only if positioning changed.
- [ ] If touched: four edits per card, and `diff -q index.html embed.html` exits 0 before deploy.
- [ ] New or renamed product: kit cross-link table, every sibling footer, and the hub README updated.

**Style**
- [ ] House style on touched prose and UI lines only: `..` not `...`, plain hyphen, Russian `ё`. Never in
      code, commands, logs, or vendored files.
- [ ] No emoji on site pages; icons support labels, never replace them.

## Guardrails

- Fix stray violations only **in the lines you touch**. No unrequested project-wide sweep - a small feature
  commit must not become a sweeping diff. Report pre-existing drift as findings instead.
- Never hand-edit a render target: generated site output, a mirrored doc, a published export. Regenerate it.
- Never run a site deploy without explicit confirmation.
- A doc-only change is cheap. On a repo whose CI ignores doc paths it costs nothing at all - do not hesitate
  to commit documentation.
