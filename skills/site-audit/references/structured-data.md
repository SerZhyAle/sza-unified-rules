# structured-data lens - do the JSON-LD and the share card state true facts a parser can read?

Reads each audited page's JSON-LD, Open Graph and Twitter tags as a parser without JavaScript does, holds them to
"truthful or absent" ([PROMOTION.md](../../../rules/PROMOTION.md) §3) and to the head every site page carries
([DOCUMENTATION_CONCEPT.md](../../../rules/DOCUMENTATION_CONCEPT.md) §3), and proposes the complete set per page
type - never a value the repository cannot render from its own sources.

## Inputs

- **Collected evidence first.** `robot.json` `pages[]`, home first: `url`, `finalUrl`, `canonical`, `lang`, `title`,
  `headings.h1NoJs`, `versions`, `links.downloads`, `hreflang`, `jsRewrites`, `scripts`, `og`, `ogLocale`,
  `ogLocaleAlternate`, `ogImage`, `twitter`, `jsonld[]`; `ux_probe.json` `pages.<key>.desktop.probe` for what the
  browser shows once the scripts ran: `versionsInText` (check 4) and `title` (check 8). With `robot.json` missing,
  GET the home, the stamp's pages, and the docs, install and privacy pages the home links.
- **Re-measured live.** `softwareApplication.has` holds booleans and `raw` stops at 3000 characters: a block whose
  `raw` is shorter is parsed from it, and a longer one, or one whose `raw` fails to parse while `parseError` is null,
  is re-read whole from a fresh GET; every block is parsed locally ([conventions](conventions.md) section 1). HEAD
  every URL a block or tag names, falling back to GET on 403, 405 and 501, except a `sameAs` profile URL, which is
  listed and never status-checked (LinkedIn answered 999 to GET and 405 or 999 to HEAD on 2026-11-07). GET the start
  of the `og:image` file for its pixel size. HEAD `https://github.com/<owner>/<repo>/releases/latest` for the
  `<owner>/<repo>` of the download links, else of `git -C <repo> remote get-url origin`: its `location` names the
  latest tag, or ends in `/releases` when there is no release; GET that tag's release page for its date (never
  `api.github.com`). GET the hub's home, `https://sza.od.ua/`.
- **Read in the repository**, read-only: each page's served-root file; whatever writes its JSON-LD and tags
  (`git -C <repo> grep -n -E "ld\+json|softwareVersion|og:image"` over the served root, build scripts and
  `.github/workflows/` - tracked files only, so the run folder and saved copies of other sites stay out) and the
  release manifest it reads; the committed `og:image` and screenshots; `git log -1 --format=%cs -- <file>`. With no
  repository (kind `external`), the `source` comparison, the writer, the `git log` dates and the committed-file
  checks go under "Not measured".
- **Writes:** `<run folder>/structured-data.md` and nothing else. Pages and blocks are parsed from `curl` piped into
  inline PowerShell or `py -I -c`, the image size from `curl -s -r 0-65535 <url>` piped the same way, never from a
  saved copy.
- **Budget:** the pages `robot.json` holds, one GET per language landing it lacks, the URLs the blocks and tags name,
  the release page and the hub's home; at most 40 GET or HEAD requests per site beyond the collected evidence.

## Inspect

The first page is the landing, and so is each language version of it - a self-canonical target of the home's
`hreflang[]` (`index-ru.html`, `/ru/`), judged as the landing is, its `url` against its own canonical. A `portfolio`
site whose base URL is a host root (path `/`) is the hub (check 6); every other landing is a product landing
(checks 3 and 8), a `portfolio` site under a project path included. A page whose canonical names another URL (a
stub, a copy such as `embed.html`) is judged at that URL only; the rest are secondary pages (check 5).

The area is `jsonld` unless a check names another. On every page a `FAQPage` or `HowTo` is LOW - neither yields a
rich result, and neither is added for reach - and so is a `WebSite` on any page under a project path, landing
included: site-name markup works only at a domain or subdomain root, so it belongs to the hub (PROMOTION.md §3). A
live block or tag that differs from its served-root file is a `source` finding (conventions section 3): with no
build step to explain it, MED when the live side is the defective one, else LOW; a difference a build step
explains: INFO naming that step.

1. **Every block parses and means something.** Source: `jsonld[].parseError` (quoted verbatim) and the local parse.
   A block that fails to parse or lacks a schema.org `@context` is dropped whole, and an `@type` schema.org does not
   define drops its entity: MED. A block or property a script writes (the repository grep, or a GET of the
   same-origin `scripts`) reaches only crawlers that run JavaScript: MED, and a release fact fetched that way also
   breaks [DOCUMENTATION_CONCEPT.md](../../../rules/DOCUMENTATION_CONCEPT.md) §4.
2. **Truthful or absent.** Source: the parsed block and the `og` and `twitter` tags against the page's visible text.
   `aggregateRating` or `review` with no rating by actual users visible on the page: HIGH - searchers read invented
   stars and the site risks a manual action ([PROMOTION.md](../../../rules/PROMOTION.md) §3); visible: INFO, the
   owner confirms the source. A missing one is never a finding: a free product without real ratings is not eligible
   for the app rich result, the honest outcome. A download count or traffic figure with no visible source, or a
   superlative or competitor's name in any value of a block (`description`, `keywords`, `alternateName`,
   `featureList`) or of an `og:` or `twitter:` tag: MED (PROMOTION.md §1 rule 4; a bundled library's credit is not
   one). A phrase or hedge DOCUMENTATION_CONCEPT.md §5 bans: MED in any block value; HIGH in `og:title`,
   `og:description`, `og:image:alt` or a `twitter:` title or description, which a visitor reads. A finding in a tag
   takes the area `og`, or `twitter` for a `twitter:` tag.
3. **The product landing's app entity.** Source: `softwareApplication`, `topLevelTypes`, the parsed block, the HEADs.
   - No `SoftwareApplication`, `MobileApplication` or `WebApplication` (`SoftwareSourceCode` or `WebPage` alone is
     none), two for one product, or one nested (`softwareApplication.nestedIn`, as in `WebPage.about`): MED.
   - Required by PROMOTION.md §3, all missing ones in one MED finding per block: `name`, `operatingSystem`,
     `applicationCategory`, `offers` with `price` 0, `url` equal to `canonical` (normalised as for `canonicalSelf`),
     a durable `downloadUrl` or `installUrl` (`/releases/latest`, a store or package page). A non-zero price on a
     free product, a `url` naming another page, or one of these URLs not answering 200 after redirects: MED. A
     versioned release-asset `downloadUrl` or `installUrl`: MED - the JSON-LD link is the durable one
     (PROMOTION.md §3).
   - Recommended, all missing ones in one LOW finding: `priceCurrency`, `isAccessibleForFree`, `datePublished`,
     `dateModified`, `license`, `author`, `screenshot`, `softwareHelp`, `releaseNotes`, `privacyPolicy`; an `author`
     that is not a `Person`, or lacks the hub's `url` or a `sameAs`, counts as missing. One of their URLs, `sameAs`
     aside, answering 4xx or 5xx to a GET: MED.
4. **Release facts in the block.** `softwareVersion` comes from the release manifest the visible version comes from
   (PROMOTION.md §3, DOCUMENTATION_CONCEPT.md §4). Source: the parsed block, `versions` (`versionsInText` where only
   a script renders the version), `links.downloads[].href`, the latest tag. A `softwareVersion` that differs from
   the visible version or the tag, ignoring a leading `v`: MED. Typed into the HTML source with nothing in the
   repository writing it: LOW while it matches. Missing where the page renders its version from the manifest: LOW,
   rendered with it; where it renders none, no finding - the release-facts fix adds both. `dateModified` more than a
   day off its source - for an app entity, or a `SoftwareSourceCode` standing in for one, the latest release's date
   from its public release page (`git log -1 --format=%cs <tag>` only as a cross-check), or with no release the last
   commit of the file its download serves; for a `WebPage` its own file's last commit: MED, crawlers read a false
   freshness.
5. **Secondary pages.** Source: `types`, the parsed block. A `WebPage` (or a subtype) whose `isPartOf` names the
   base URL (PROMOTION.md §3): missing LOW. A how-to or guide page without a `BreadcrumbList`: LOW. A missing
   `TechArticle` is no finding: the canon asks for the `WebPage`, which the docs lens proposes in its place.
6. **The hub.** Source: `hasGraph`, `types`, the parsed block, a HEAD and a GET per entry. One `@graph` of `WebSite`
   (`name`, `url`), `Person` (`name`, `url`, `jobTitle`, `knowsAbout`, `sameAs`) and an `ItemList` with one
   `SoftwareApplication` per product the hub links to (`name`, `url`, `operatingSystem`, `applicationCategory`). No
   `WebSite`, `Person` or `ItemList`: MED. A `Person` without `jobTitle`, `knowsAbout` or `sameAs`: LOW. A product
   the hub links to with no entry, or an entry without `name`, `url`, `operatingSystem` or `applicationCategory`:
   LOW, all in one finding. An entry whose `url` does not answer 200, or whose `name` or `operatingSystem` differs
   from that product's landing block: MED.
7. **The share card** (area `og`; `twitter` for its tags), judged at the static value: share-card scrapers run no
   JavaScript, and `jsRewrites` marks a script that rewrites a tag. Source: `og`, `twitter`, `ogImage`, `ogLocale`,
   `ogLocaleAlternate`, `hreflang`, `jsRewrites`, the image measured live.
   - DOCUMENTATION_CONCEPT.md §3 requires `og:title`, `og:description`, `og:url`, `og:image` and `twitter:card`
     `summary_large_image`: one missing MED, another card type LOW. An `og:url` naming another page than
     `canonical`: MED. Missing `og:type` or a `twitter:` title, description or image: LOW, X reads the `og:` ones.
     A tag a script rewrites to other text (`jsRewrites`; quote the script line and the static value): MED,
     scrapers and visitors meet two cards.
   - The image ([SITE_CONFIGURATION.md](../../../rules/SITE_CONFIGURATION.md) §5, and `twitter:image` if another
     file): absolute in the raw tag, 200 with a raster `image/*` type (`ogImage.status`, `contentType`), at least
     1200x630 by its file header, under the base URL and committed in the served root (`ogImage.rawGithub` fails):
     each failure MED. No `og:image:width`, `:height` or `:alt`: LOW; a declared size off the measured one: MED.
   - `og:locale` is `ll_CC` for the page's `lang` from the portfolio's canonical 13-language map
     ([LOCALIZATION.md](../../../rules/LOCALIZATION.md) §3: `en_US`, `ru_RU`, `uk_UA`, `ar_AR`, `bn_BD`, `de_DE`,
     `es_MX`, `fr_FR`, `hi_IN`, `id_ID`, `pt_BR`, `ur_PK`, `zh_CN`; one exception: a page written in a regional
     variety takes that variety's territory, so `epub2html` keeps `pt_PT` for European Portuguese text, while
     `cyrflip` `ar_SA` -> `ar_AR` and `epub2html` `bn_IN` -> `bn_BD` reconcile to the map): another form (`en`) or a
     territory outside the map and exception is LOW, another language MED. A finding shared across products is asked
     once in the hub's portfolio promotion ticket and cited by each affected product ticket ([SKILL.md](../SKILL.md)
     Step 4). An `og:locale:alternate` with no `hreflang` target of that language that answers 200, is self-canonical
     (`selfCanonical`) and is neither `noindex` nor a parameter URL (`hreflang[]`) claims a version that does not
     exist: MED.
8. **One name** (product sites), on the landing and each language landing. Source: `title`, `og`, the parsed block,
   `desktop.probe.title` where a script rewrites the title, the hub GET. The name is the same in the `title`, the
   block's `name`, `og:title` and the hub's card for this base URL; the `h1` states the job (PROMOTION.md §2), so it
   joins only where it names the product. A mismatch, a language landing that renames the product included: MED,
   area `jsonld` when the block is the odd one out, `positioning` otherwise.

## Propose

Under "Proposed patches", never applied (conventions section 1); with no repository, every patch is a numbered plan.

- **One block per page type** - product landing (each language landing too), secondary page, hub - as a `@graph`
  where a page carries more than one entity, as a diff against the file that produces the page: the generator,
  template or workflow step when one writes it (a render target is regenerated, never hand-edited -
  [DOCUMENTATION_CONCEPT.md](../../../rules/DOCUMENTATION_CONCEPT.md) §1), else the served-root HTML file. A
  secondary page gets a `WebPage` that `isPartOf` the site and a `BreadcrumbList`; a guide page's `TechArticle` as
  its `mainEntity` is optional.
- **Every value from its one source.** `name`, `operatingSystem`, `description` and an `applicationCategory` app type
  (`UtilitiesApplication`) for the market category: the positioning source (PROMOTION.md §2). `softwareVersion`, the
  durable `downloadUrl` or `installUrl`, and `dateModified` as the latest release's date: rendered by the release
  flow from the manifest the visible version uses (DOCUMENTATION_CONCEPT.md §4); `datePublished`: the first
  release's date, which the release flow reads from the oldest release; with no such step yet, `softwareVersion`
  stays out and the release-facts patch is the prerequisite. `url`: the canonical; `screenshot`: committed images;
  `author`: the owner as a `Person` with the hub's `url` and `sameAs`; a `WebPage`'s `dateModified`: its file's last
  commit. Where the site has a build step it generates the block; on a hand-authored page the block is written once
  in the HTML, its release facts left to the release-facts patch; no `site.json` keeps a second copy.
- **The share card:** `og:title`, `og:description`, `og:type`, `og:url` equal to the canonical, `twitter:card`
  `summary_large_image`, `twitter:title`, `twitter:description` and `twitter:image` with the `og:` values, and
  `og:image` as an absolute URL to a committed image of at least 1200x630 under the served root's `assets/`, with
  `og:image:width`, `og:image:height` and `og:image:alt`; `og:locale` as `ll_CC`; `og:locale:alternate` only for an
  alternate that is a real URL; no script rewrites a tag.
- **Never in a patch:** `aggregateRating` or `review` without real ratings visible on the page, `FAQPage`, `HowTo`,
  `WebSite` off the hub, `<meta name="keywords">`, a typed version or date.
- **Larger than about 200 lines** (a generator to write, many pages): a numbered plan naming each file and the source
  of every value.
- **Each patch ends with its checks:** every proposed block parses locally; every existing URL it names answers 200
  now, and a file the patch adds is named as added; once the owner deploys it, the Rich Results Test on the
  landing, where "missing aggregateRating" reads "not eligible", never a defect
  ([PROMOTION.md](../../../rules/PROMOTION.md) §3).

## Output

On top of the conventions section 8 shape:

- **Structured data inventory**, after Findings, one row per page: page | blocks (parse errors) | top-level types |
  app entity (top-level, nested in X, none) | `og:image` (status, pixels, host) | `twitter:card`; under it, one
  **eligibility** line per page type - "Software App: not eligible, no real ratings - expected" for a free product.
- **Not measured** always names the Rich Results Test and the share-card debuggers: online validators the owner runs,
  never the lens (conventions section 1); it also lists the `sameAs` URLs, which no request checks.

## Canon differences

1. **Required against recommended.** The source (`site-structured-data.md`) flagged every missing property alike;
   the canon's set is MED and the rest LOW: `name`, `operatingSystem`, `applicationCategory`, `offers` price 0, `url`
   (new) and a `downloadUrl` or `installUrl` now required durable ([PROMOTION.md](../../../rules/PROMOTION.md) §3).
2. **One source per fact.** `softwareVersion` and the release dates are proposed from the release manifest the
   visible version uses and checked against the public release page, never typed ("fill from the latest tag" is
   gone); an absent `softwareVersion` is a finding only where the page renders its version, and `site.json` copies
   none of them (PROMOTION.md §3, [DOCUMENTATION_CONCEPT.md](../../../rules/DOCUMENTATION_CONCEPT.md) §1 and §4).
3. **Truthfulness added.** Invented ratings, reviews and counts are flagged and a missing rating never is; no
   superlative, competitor name or release-status phrase in any block value or share-card tag
   (PROMOTION.md §1 rule 4 and §3, DOCUMENTATION_CONCEPT.md §5).
4. **Docs pages:** `HowTo` dropped and `FAQPage` never proposed, either one found LOW; a secondary page carries a
   `WebPage` with `isPartOf` (PROMOTION.md §3 for the `WebPage`; `TechArticle` and `BreadcrumbList` are the
   source's, kept where the canon is silent - a missing `BreadcrumbList` is LOW, a missing `TechArticle` no finding,
   as the docs lens proposes the `WebPage` in its place).
5. **`WebSite` at a domain or subdomain root only:** the source asked it of any hub or portfolio page; a `portfolio`
   site under a project path gets none, and one found there is flagged (PROMOTION.md §3).
6. **Social card:** the canon's `og:title`, `og:description`, `og:url`, `og:image` and `twitter:card`
   `summary_large_image` are MED, the source's other tags LOW; "1200x630 PNG" became "at least 1200x630", a committed
   asset under the served root referenced absolutely ([SITE_CONFIGURATION.md](../../../rules/SITE_CONFIGURATION.md)
   §5, DOCUMENTATION_CONCEPT.md §3).
7. **Name check:** the `h1` states the job, not the name, so it joins the comparison only where it names the product
   (PROMOTION.md §2, derived fields).
8. **Verification:** no JSON validator or Rich Results Test run by the lens; blocks are parsed locally and the test
   is the owner's step after deploy (conventions section 1, PROMOTION.md §3).
