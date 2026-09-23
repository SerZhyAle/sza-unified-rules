# Documentation Concept - how a product presents, indexes, and supports itself

The companion to [REPOSITORY_LAYOUT.md](REPOSITORY_LAYOUT.md). Layout says *where files live*; this
says *what we write, how we want to be found, and how we treat the user*. Universal across project
types; the channel-specific fields are deferred to [PLATFORM_OVERLAYS.md](PLATFORM_OVERLAYS.md).

Principle: **one source of truth per fact, rendered into many surfaces.** A feature, a version, a
change, a privacy statement each has exactly one authoritative home in the repo; the site, the store
or Play listing, and the release notes are *renderings* of it, never independent re-authorings that
drift.

## 1. The single sources of truth

| Fact | Authoritative home | Rendered into |
| --- | --- | --- |
| What the product is / does | `README.md` (+ `README_<lang>.md`) | site landing page, store/Play description, package locale |
| What changed, per version | `CHANGELOG.md` | release body, site "What's new", store/Play release notes |
| Current version | the version tag / build id (see overlay) | binary stamp, asset names, store version (remapped) |
| Publication mechanics | `docs/guides/BUILD_AND_RELEASE.md` (+ store guide) | the release checklist / skill |
| Channel listing text | the overlay's listing file(s) | the store console / package PR |
| Privacy | `docs/privacy.html` (or the hosted policy URL) | store/Play listing URL, site footer |
| Shared contracts (format, algorithm, boundary behaviour, shared UX) | the shared contracts catalog, in the folder named after the **function** | `docs/contracts/<ID>.md` as a pointer in each repo; the other product that implements it ([CONTRACTS.md](CONTRACTS.md)) |

If a fact appears in two places, one is a render target and must be regenerated, not hand-edited.
Store/Play listing copy, for example, is trimmed to each field's character cap *from* the CHANGELOG
text - keep the long form in CHANGELOG, the trimmed form in the listing file.

## 2. Versioning & change tracking

- **Version is derived mechanically, never hand-bumped.** The exact shape is a per-platform frozen
  decision (see overlay: date tag `YY.M.D.HHmm` for desktop/CLI; `versionCode`+`versionName` for
  Android). Each channel that wants a different shape derives it mechanically from the one
  authoritative form.
- **CHANGELOG is the ledger.** Keep-a-Changelog format, English only (it is published verbatim as the
  release body and the site "What's new"). Categories: `Added / Changed / Fixed / Removed`.
  - Regular builds accrete bullets under `## [Unreleased]`.
  - A release moves `[Unreleased]` into `## [<version>] - <YYYY-MM-DD>` and opens a fresh empty
    `[Unreleased]`. That dated section *is* the release note - do not re-author it elsewhere.
  - **Four ledger shapes are accepted - pick one per project**, keeping exactly one authoritative
    internal ledger and one public-notes render:
    1. **Public ledger** - Keep-a-Changelog at repo root, rendered verbatim into the release body and
       the site "What's new" (reference: `FastMediaSorter_Lite`).
    2. **Dev log -> curated notes** - an internal per-change ledger (`DEV/CHANGELOG.md`) feeds a curated
       public "What's new" from the diff since the last release (reference: `doc-html-translate`).
    3. **Structured inventory** - a machine-validated capability inventory (`ALL_FEATURES.jsonl`,
       written through a CLI) is the developer source of truth; the public showcase is generated from
       its diff at release; chronology comes from git history (reference: `FastMediaSorter_mob_v2`).
    4. **No standalone ledger** - git history is the ledger, the release host auto-generates the
       release body (`generate_release_notes`), and the release skill/checklist fans the same "What's
       new" into every surface (reference: `CyrFlip`).
    Curated text is never hand-authored per change - it is derived from the ledger, then trimmed to
    each listing's caps.
- **Build vs Release are distinct and one is billable/irreversible.** A "build" is local, free, and
  publishes nothing. A "release" pushes the tag / uploads to the store - the single operation that
  triggers CI, costs money, or becomes publicly visible. Documenting this boundary explicitly prevents
  accidental paid or public runs.

## 3. Discoverability - how we want to be indexed

Every product is found through some subset of: **its store's own search**, **a package-manager
search**, and **web search of its site**. Which ones apply is per-platform (see overlay); the
principle is universal and none of it is automatic.

**By functionality, not just name.** Present the product by the *jobs it does* - "sort photos and
videos with hotkeys", "open HEIC/AVIF without a codec", "share folders to a phone" - because that is
what users type. The name is a frozen anchor for *updates*, not the primary search hook. Fill every
search-term / tag / keyword slot with a distinct user phrase.

### SEO instrumentation every site page must carry

A page without these is invisible to crawlers even when live:

- `<title>` - value + brand, under ~60 chars
- `<meta name="description">` - one-sentence functional summary, ~150 chars
- `<link rel="canonical">` - the absolute public URL (prevents duplicate-content splitting)
- Open Graph + Twitter card - `og:title/description/image/url`, `twitter:card=summary_large_image`,
  with a real preview image (>=1200x630)
- One `<h1>` stating the job the product does; `<h2>`s for each feature area
- `JSON-LD` structured data (`SoftwareApplication`: name, OS, price, ratingValue) for an app
  rich-result
- `hreflang` for each translated page; language toggles use consistent ISO codes across the site
- A `sitemap.xml` + `robots.txt` at the site root listing every public page

## 4. Mandatory site pages

For any product with a public site. The minimum set for a credible, store-linked product site:

| Page | Purpose | Must have |
| --- | --- | --- |
| Landing (`index.html`) | value + download | H1 job statement, install CTAs, feature sections, screenshots, full SEO+OG |
| Privacy (`privacy.html`) | required by every store | plain-language "what we access & why", "no telemetry" if true, contact email |
| How-to / guide page(s) | reduce support load | task-oriented, screenshots, shortcuts |
| "What's new" | retention + SEO freshness | rendered from CHANGELOG; each version dated |
| Support / contact | user trust | how to report a bug (issue tracker), contact email, response expectation |

> **Zero-data carve-out.** A zero-data local tool with no site may skip the hosted `privacy.html`; a
> local-but-sensitive tool (keyboard hook, clipboard, capture) still hosts it. Rule and boundary in one
> home: [SECURITY_AND_PRIVACY.md](SECURITY_AND_PRIVACY.md) §5.

Buttons point at durable URLs (`/releases/latest`, the package id, the store product page), never a
hard-coded version, so the site never goes stale between releases.

## 5. User support & friendliness

The product's tone is a documented choice, not left to each writer:

- **Speak in the user's task, not our architecture.** "iPhone photos open now (HEIC, HEIF, AVIF)" -
  not "added an ISO-BMFF decoder path". CHANGELOG bullets lead with the user-visible win, then briefly
  the mechanism.
- **Every honest limitation is stated up front**, in the listing and the app: what the free tier does,
  what needs a network call, what a permission is for. Pre-empting a support question is cheaper than
  answering it and builds trust with reviewers.
- **One friendly voice across surfaces.** Same phrasing for a feature in README, site, and listing, so
  a user who reads two of them isn't confused by three names for one thing.
- **List the ship-together surfaces in one manifest.** Every user-facing surface a feature must touch
  (README, site, each localized docs page, each listing, the in-app strings) goes in one authoritative
  list - a `DOCS_SURFACES.md` driven by a `/docs-sync` skill, or the release skill's own checklist
  (reference: `CyrFlip`) - so a feature lands in *all* of them atomically, **every surface and every
  authored locale in one edit, not three follow-up requests**. The surface missing from the manifest is
  the one that silently goes stale. Where a surface is *generated* (a settings reference built from the
  settings UI), enforce the sync with a gate that fails the build on drift.
- **The rest of the declared locale set fans out at the RELEASE boundary, not at authoring - wherever a
  release boundary exists.** Surfaces must move together; locales beyond the ones the author writes
  himself need not. Nothing reaches a user between releases, so one bulk pass clears every new key of a
  release at once, while translating per change buys a full fan-out per key with no shipping benefit - in
  the reference product, ten further translations per key on top of the three authored ones. Put the
  refusal in the pre-release gate, and let the authoring call and the change's own closure only *name*
  what is still missing rather than block on it. A continuously published product has no boundary to batch
  to, and there the whole fan-out stays part of the one edit.
- **Support path is one click from everywhere**: issue tracker for bugs, an email for private contact,
  both linked from the site footer, the store listing, and the app's About.
- **Localize the user-facing surfaces** (README, site, store listing) to the audiences you actually
  have; keep the CHANGELOG English (it is the canonical technical ledger).

### House text style (the one home for this rule)

Applies to documentation prose and user-visible UI text in any language. It does **not** apply to code,
specs, commands, logs, vendored files, or chat - this list is authoritative, and any other statement of the
scope elsewhere renders from it:

- `..` never `...`; plain hyphen `-`, never em-/en-dash/horizontal bar.
- Russian `ё`/`Ё` wherever grammatically correct.
- When editing an existing file, fix stray violations in the lines you touch; no unrequested
  project-wide sweep. A gate may carry a scoped allowlist for a legitimate exception
  ([DEVELOPMENT.md](DEVELOPMENT.md) §9).

## 6. The documentation registry - what a project declares about its own docs

§1 says every fact has one authoritative home. That is of no use to a reader who cannot find the home, and
invisible to a check that cannot enumerate it. The registry is the machine-readable answer to three
questions: which documents the project maintains, which of them are published, and which are deliberately
not announced and why. It is a declaration the project keeps, not a prose index a reader has to trust.

**The mandatory half - every project, site or no site:**

1. **One record per maintained document.** A record carries the path, what the document is about, a
   **product area**, one or more **change triggers**, the document's role in the source-of-truth chain
   (`source` or `render`), whether it is published, and room for the reason a publishable file is
   deliberately not announced. The `render` role is a promise: that document is regenerated and never
   hand-edited (§1).
2. **Two query facets.** "What must I read before touching this" is answered by product area plus change
   trigger, in every project, in the same shape. The vocabulary of both is the project's own; only the
   existence of the two facets is the contract.
3. **Validation from the registry to the tree.** Every record points at a file that exists, and a record
   claiming a published page must have an address to publish.
4. **Reverse coverage, from the tree to the registry.** A file sitting in the publishable area that
   declares no address and is named in no exclusion fails the check. Without this half a registry describes
   only what it already knows about, and a new file joins the site in silence.
5. **A versioned record shape.** The shape carries a number, declared in the project's adoption stamp
   beside the ledger shape, so a later change to it stays readable for a project that adopted an earlier
   one. A field a project cannot fill is omitted, never faked.

**The site half - only where a public site exists:**

6. **The page declares its own address; the record decides publication.** The address lives in the page (a
   `permalink` or the equivalent), the publish and index decisions live in the record, and the record
   covers a group of pages rather than a single file. A file then cannot change its public status on its
   own, and no page has to be listed twice.
7. **The site map is generated** from the records that declare an address, never hand-maintained, and every
   listed page carries the SEO block of §3.
8. **Search engines are notified after publication**, once per release, never per edit.

A project with no public site runs items 1-5 and is compliant. That is a permanent, declared state, not a
stage on the way to the full set.

Two ordering rules make the registry true rather than aspirational: a document is registered **before**
anything links to it, and on adoption the registry is built from the tree **as it actually is**, exclusions
and reasons included, rather than from the tree somebody meant to have.

Adoption is per repository, in a session started in that repository ([adopt-canon](../skills/adopt-canon/SKILL.md)),
and the stamp is the only tracker. A project that has not adopted shows it in its own stamp; there is no
portfolio-wide list to keep, because that list is what went stale last time.

> **Reference implementation:** `FastMediaSorter_mob_v2` - a JSONL registry with a query / validate /
> generate CLI, the reverse-coverage half wired into the release-scope gate, and the site served out of the
> repository itself. Every way it differs from this section is recorded in its contrib file, so the
> reference cannot quietly become the definition.

## 7. Applying to a new project

1. Stand up the sources of truth (§1) - most are empty files to start.
2. Adopt the version + CHANGELOG `[Unreleased]` flow (§2), with the version shape from your overlay.
3. Fill the store/package search + feature fields functionally (§3); add the SEO block to every page.
4. If site-hosted, ship the mandatory pages (§4) with durable-URL CTAs.
5. Write the README/listing in the task-first friendly voice (§5) and localize the user-facing surfaces.
6. Build the registry from the tree you have (§6) and wire both its checks; without a site, the mandatory
   half is the whole of it.
