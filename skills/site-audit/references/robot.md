# robot lens - what does a crawler without JavaScript see, and is it indexable?

Judges a site as a search crawler running no script, a social-card scraper and an AI crawler meet it: what a page says
before any script runs, which URLs can be indexed, what the host tells robots. It follows [conventions](conventions.md)
and proposes no patch; the report stage merges its overlap with the other lenses (conventions section 9).

## Inputs

- **Read first.** `robot.json`: `pages[]` for checks 1-12, `site` for checks 13-17. `ux_probe.json`: per page
  `desktop.probe` (`title`, `metaDesc`, `h1`, `lang`, `hasLangSwitch`) and `desktop.perf.heaviest`, and the top-level
  `apiGithubLoads`. A missing file: measure its fields live, each `robot.json` field and flag (`canonicalSelf`,
  `reciprocal`, `isParam`, `onSite`, `appShell`, `noreferrerOwnHost`) as the `.OUTPUTS` help of
  `tools/site-audit/robot-check.ps1` defines it, or put the checks that need it under "Not measured".
- **Re-measure live**, GET or HEAD, only what the evidence lacks (each check names it) or what looks wrong.
- **Read in the repository**, when there is one: each page's file in the served root (conventions section 3);
  `git ls-files` and `git log -1 --format=%cs -- <file>` there; whatever writes `sitemap.xml` and the head; the
  promotion ticket ([PROMOTION.md](../../../rules/PROMOTION.md) §8), for the locales meant to be found;
  `git --no-optional-locks status -sb`, never `git fetch`. When every page differs from its file, read the Pages
  source with `gh api repos/<owner>/<repo>/pages` (a GET) before calling the deploy stale
  ([SITE_CONFIGURATION.md](../../../rules/SITE_CONFIGURATION.md) §1). With no repository, check 18 and the repository
  halves of checks 12, 15, 19 and 20 go under "Not measured".
- **Budget.** The home page and up to 5 key pages: the stamp's pages first, else from the home page's links - docs
  index, install or download, what's new, privacy, support. Beyond the page fetches and the link checks conventions
  section 1 caps, at most 40 live requests and 3 web searches.

## Inspect

Checks 1-12 run per page, 13-21 site-wide; the area of each is in parentheses. A product landing is the first page of
any site but the hub (a `portfolio` site whose base URL is a host root). A page is "meant to be found" when the
sitemap lists it, the nav links it or the stamp declares it. A page kept out of search on purpose is not meant to be
found: a redirect stub, a byte-identical copy that canonicalises to its original, or a help page the help map names
(`CONTEXT-HELP` section 7 item G), whose head and indexing are graded only on its `noindex`, its absence from the
sitemap and its crawlability, LOW each (docs.md check 5). With the repository, a page whose live head or headings
differ from its served-root file with no build step to explain it is a `source` finding: MED when the live side is
the defective one, else LOW; "stale deploy" only after the Pages source check of Inputs.

1. **Status** (`status`, `redirect`) - `status`, `finalUrl`, `redirects`. A final status other than 2xx, or the base
   URL moving to another host so that the domain holds nothing to index: HIGH, unless it is the root/apex redirect to
   the owner's canonical custom domain ([SITE_CONFIGURATION.md](../../../rules/SITE_CONFIGURATION.md) §3 "Root/apex
   redirect repo pattern"); a move to a third-party host such as Google Sites stays HIGH. A 302 or 307 for a
   permanent move, or two hops or more: MED. One 301 behind a link of the site: LOW.
2. **Head** (`lang`, `title`, `description`; `layout` for the viewport, `link` for the icon and manifest) - `lang`,
   `title`, `titleLength`, `titleHasEmoji`, `description`, `descriptionLength`, `viewport`, `cyrillicChars` against
   `latinChars`. The shape: a title of value and brand under about 60 chars, "Name - category for platform" on a
   product landing, and a one-sentence functional description of about 150
   ([DOCUMENTATION_CONCEPT.md](../../../rules/DOCUMENTATION_CONCEPT.md) §3,
   [PROMOTION.md](../../../rules/PROMOTION.md) §2 "Derived fields"). MED: no title, description, `lang` or viewport; a
   product landing's title without its name, category or platform; any title with an emoji (`titleHasEmoji`); a
   title or description two self-canonical pages share (a redirect stub or a byte-identical copy that canonicalises
   to its original is exempt, as in check 3); a `lang` the visible text contradicts (a Cyrillic majority under `en`).
   LOW: a title over 60 chars; a description over 160, under 50 or cut mid-sentence; a missing or failing icon or
   manifest (SITE_CONFIGURATION.md §5).
3. **Canonical, meta robots** (`canonical`, `robots`) - `canonical`, `canonicalAbsolute`, `canonicalSelf`,
   `metaRobots`. No canonical, or a relative one: MED. A canonical naming another URL, or a `noindex`, on a page meant
   to be found: HIGH; both are right on a redirect stub or a byte-identical copy, and a stub canonicalises to its
   target (PROMOTION.md §3 "Sitemaps and page heads").
4. **hreflang** (`hreflang`) - `hreflang[]`, `xDefault`. A target that answers other than 200, is not `selfCanonical`,
   is `noindex` or is `isParam` (a `?lang=` view whose canonical names another URL, so a copy of that URL): HIGH, that
   locale cannot be indexed. A `?lang=` target whose canonical names itself is an addressable page and is judged like
   any other target (`DOC-EXTERNAL-QUALITY` section 8 items S, T and U); `sameText` true marks it a stub, which the
   i18n lens's check 5 grades. A pair that is not `reciprocal`, a page that does not list itself, a relative `href`, a code that is not ISO 639-1 with an optional
   ISO 15924 script and ISO 3166-1 region (`ua` for Ukrainian, `en-UK`; `zh-Hans` and `pt-BR` pass): MED, the
   annotation is ignored. No `x-default`: LOW (PROMOTION.md §3).
5. **Social cards** (`og`, `twitter`) - `og`, `twitter`, `ogImage`. No `og:title`, `og:description`, `og:image`,
   `og:url` or `twitter:card`: MED. An `og:image` that is not 200, not `onSite`, `rawGithub`, or relative: MED - it is
   a committed asset of the site, referenced absolutely (SITE_CONFIGURATION.md §5). Pixel size and the rest of the
   card are the structured-data lens's.
6. **JSON-LD** (`jsonld`) - `jsonld[]`, parsed locally, with `raw` for what `softwareApplication.has` does not hold.
   A `parseError`: MED, the block is ignored whole. On a product landing, MED: no top-level `SoftwareApplication` (or
   `MobileApplication`, `WebApplication`; see `topLevelTypes`, `softwareApplication.nestedIn`), or one without `name`,
   `operatingSystem`, `applicationCategory`, `offers` at `price` 0, the canonical `url`, or a durable `downloadUrl` or
   `installUrl`. A `softwareVersion` other than the version the page shows: MED, as release-facts check 5 grades it;
   an absent one is no finding, nor is a missing `aggregateRating` or `review` (PROMOTION.md §3 "Structured data -
   truthful or absent"). The rest of the graph is the structured-data lens's.
7. **Headings** (`heading`) - `headings`. No `h1`, or more than one: MED. An `h1` that does not state the job the
   product does (quote `h1NoJs`): MED; the name belongs in the title (DOCUMENTATION_CONCEPT.md §3). MED as well:
   `roleHeadingSpans` above 0; section or product titles that are styled text, not headings; no `h2` on a page with
   feature areas; every heading repeated once per language (re-measured when `h3Count` is a multiple of the language
   count). `h1HasEmoji`: LOW. On the hub, an `h1` and title that name neither the owner nor the portfolio: INFO, the
   owner's decision.
8. **Images** (`image`) - `images`. `noAlt` above 0: MED. An empty `alt` on a logo or a screenshot, or `noSize` above
   0: LOW. List the 3 heaviest images with their bytes - the `perf.heaviest` entries whose name matches an
   `images.items` src, as ux.md check 7, else a HEAD of each `images.items` src within the budget; the ux lens judges
   weight.
9. **Links, downloads, version** (`link`, `download`, `version`) - `links`, `versions`, `apiGithub`. HIGH: a broken
   download, store, help or nav link; a product landing with no download or install link. MED: another broken
   internal link; one anchor text for different URLs (re-measured); no version in the no-JavaScript text of a product
   landing or an install or download page - quote the browser call and its 403 count in `apiGithubLoads`. LOW:
   `rawGithub` links, `noreferrerOwnHost`, a relative link into a sibling site; `githubBlob` links are the docs lens's
   (docs.md check 7). A version comes from the release manifest and a sibling link uses the public domain
   (SITE_CONFIGURATION.md §2).
10. **Languages in one DOM** (`lang`) - `langSpans`, `dataLang`, `headings.h1NoJs`, `hasLangSwitch`. A second language
    in `langSpans` with more than 5 elements (more than a switch needs), or an `h1NoJs` in two languages: MED - a
    crawler reads them all as this page's text; quote it, the counts, and whether `dataLang` sets the default
    statically. A locale meant to be found - declared by an `hreflang`, an `og:locale:alternate` or a sitemap
    alternate, or named so by the promotion ticket (PROMOTION.md §8) - with no indexable URL of its own: HIGH,
    invisible to search (an `hreflang` target is check 4's). Any other locale kept on one URL (a switch, a script,
    hidden spans): MED for the site, naming the locales; INFO, citing the ticket's line, when the promotion ticket
    states that zero reach (PROMOTION.md §3). The patch is the i18n lens's.
11. **Content without JavaScript** (`content`) - `appShell`, `textNoJs`. `appShell` true (visible text under 200 chars,
    or a Loading placeholder on a page under 100 words): HIGH, a crawler indexes an empty page; a redirect stub is
    exempt (check 3). A Loading placeholder in one section of a page whose main content is static: MED, quote it. A
    `textNoJs` (its first 400 chars) that holds neither the `h1` nor the lead paragraph, a menu or a sidebar coming
    first: LOW, quote the opening.
12. **Static against rendered** (`title`, `description`, `heading`, `lang`) - `title`, `description`, `headings.h1`,
    `lang` against `desktop.probe` `title`, `metaDesc`, `h1`, `lang`; `jsRewrites` and `scripts[]` locate the writer.
    The `description` and `metaDesc` are compared whitespace-collapsed and cut to 160 chars (ux-probe.js keeps 160),
    each `h1` on its first 120 chars. A difference: MED, quote both - crawler and visitor meet two identities; HIGH
    when it names another subject or product, or changes a version, platform, price or release status (as i18n.md
    check 8). An `h1` difference that hidden language spans explain is check 10's and is not reported here. With the
    repository, count the i18n keys whose default text differs from the markup.
13. **Host-root `robots.txt`** (`robots.txt`) - `hostRobots`, groups read in `body`. Only this file counts: below the
    host root the project's own file (`robots`) is read by no crawler, never a finding and never the fix; on a
    host-root base the two are one file. HIGH: a 5xx, read as disallow-all (give the count); a `Disallow` for `*` or a
    search crawler covering the base path. MED: a `Disallow` on CSS, scripts or images a page needs; no file, or no
    `Sitemap:` line for this site. LOW: a `Disallow` hiding a 200 page (`noindex` is the tool), one on a 404 path, a
    comment the live paths contradict. On `github.io` the file is the hub's: the fix names the hub's ticket, never a
    `CNAME` in the user-site repository; on the hub, GET `https://<owner>.github.io/robots.txt` too (PROMOTION.md §3).
    `aiCrawlers` - GPTBot, ClaudeBot, PerplexityBot, CCBot and Google-Extended, each `blocked`, `allowed` or
    `unmentioned`: INFO (conventions section 5).
14. **`llms.txt`** (`llms.txt`) - `llms`: INFO either way, the owner's decision (conventions section 5).
15. **Sitemap** (`sitemap`) - `sitemap`. MED: not 200; rows that redirect, fail, canonicalise elsewhere, carry a
    parameter or lie outside the sitemap's own subtree (`sampled`, `problems`, `paramUrls`), with the count - it lists
    only canonical URLs that answer 200, and a project sitemap is valid for its own subtree. LOW: `lastmodDistinct` 1
    over several rows, `lastmodMissing` above 0, a `lastmod` other than the source file's commit date (up to 5 rows
    against `git log`), `<priority>` or `<changefreq>`, a page meant to be found left out, no generator in the
    repository (PROMOTION.md §3 "Sitemaps and page heads").
16. **Host redirects** (`redirect`) - `redirects`. `http` answering 200 instead of moving to `https`, or a `www` that
    fails on a custom domain: MED. More than one hop, or a 302 where a 301 belongs: LOW - a host alias no link of the
    site uses; a chain behind a link is check 1's MED.
17. **404** (`404`) - `notFound`. A nonsense path answering 200, a soft 404: MED. A 404 without the site's own page
    (GitHub's default title, no link home): LOW.
18. **Served tree** (`source`, page `site`, each file's path in the evidence) - `git ls-files` under the served root.
    Internal material there - a folder the role map of [REPOSITORY_LAYOUT.md](../../../rules/REPOSITORY_LAYOUT.md)
    marks **no**, a prompt, a spec, an audit report, a ticket workspace - is published and indexed
    (SITE_CONFIGURATION.md §1): MED, proven by a HEAD on up to 5 files; the fix moves it out of the served root or to
    a git-ignored folder, never a `Disallow`.
19. **Console tokens** (`robots`) - the landing's `google-site-verification` and `msvalidate.01` tags, re-measured, and
    a `google*.html` file in the served root. On a `github.io` base and on the hub, also the host-root property's
    file: the `google*.html` of the user-site repository, whose source the hub's tree keeps, listed by
    `gh api repos/<owner>/<owner>.github.io/contents --jq ".[].name"` (a GET) and proven by a HEAD at
    `https://<owner>.github.io/<file>`; while it answers 200, a landing without a meta tag is no finding. Each token
    found (kind, value, where) is a line of "## Site files"; one listed in the "## Site files" of
    `<previous run folder>/robot.md` and gone now: MED, removing it un-verifies the property (PROMOTION.md §3
    "Search consoles"). No token and no file anywhere: INFO, "no verification found - proof is the console"
    (PROMOTION.md §3 "Proof of indexing").
20. **Indexation, directional** (`robots`) - with a web search tool only: the product name, `<name> <platform>`,
    `<owner> <name>` (most tools ignore `site:`); on the hub, the owner's full name and the brand. Per query, the
    first 10 URLs, the site's place and what ranks above it: INFO, directional - proof and fix are the console's URL
    Inspection and sitemap status (PROMOTION.md §3 "Proof of indexing"). With or without the tool, a URL of this
    owner outside the base that a search result, the previous run or this host's baseline rows name is re-requested:
    a served internal file is check 18; a live, self-canonical copy of this product (a legacy path) is MED, fixed by
    a redirect stub to this site. The repository's metadata, read with
    `gh api repos/<owner>/<repo> --jq "{description,homepage,topics}"` (a GET): `homepage` not the base URL, or no
    description or topics: LOW (`positioning`; PROMOTION.md §4 item 1, §2 "Derived fields").
21. **Lost URLs** (`status`) - each URL under the base that a search result (check 20), the previous run's appendix or
    this host's baseline rows name as indexed, linked or live: one that answers 404 now with no stub is HIGH, a
    visitor from search meets a dead end; the fix is a redirect stub that canonicalises to its successor.

## Output

`<run folder>/robot.md`, the only file the lens writes, in the conventions section 8 shape plus, after "Changed since"
(after "Not measured" when there is none):

- `## Appendix` - per budget page: page | status | bytes | title (len) | description len | canonical (`self`, `other`,
  `relative`, `none`) | h1 (count, first 60 chars of `h1NoJs`) | JSON-LD types | images (total, `noAlt`, `noSize`) |
  internal links (total, checked, broken); the first eight columns are those of the site report's appendix
  (conventions section 9 item 8).
- `## Site files` - a line each: host-root `robots.txt` (status, `Sitemap:` lines for this site), sitemap (status,
  rows, distinct `lastmod`), `llms.txt`, the 404 probe, the `http` and `www` chains, and each console token that
  check 19 found.
- `## Indexation (directional)` - when check 20 ran: query | date | tool | place or "absent" | what ranks above it.

## Canon differences

Changes from the prompt-pack source, `site-audit-robot.md`:

- **Report** - `audit/robot-<date>.md` in the repository became the git-ignored `<run folder>/robot.md`: a tracked
  report under a served root is published ([SITE_CONFIGURATION.md](../../../rules/SITE_CONFIGURATION.md) §1).
- **robots.txt** - the host root only; below it the project's file is never a finding or the fix, a `github.io` fix is
  the hub's ticket, and a `Disallow` never hides a page ([PROMOTION.md](../../../rules/PROMOTION.md) §3).
- **h1** - "names the product" became "states the job"; the name goes in the title
  ([DOCUMENTATION_CONCEPT.md](../../../rules/DOCUMENTATION_CONCEPT.md) §3).
- **JSON-LD** - a missing `softwareVersion` is no finding and a mismatched one is MED; `name`, `url` and a durable
  download link join the fields; a missing rating is never a defect (PROMOTION.md §3).
- **Sitemap** - "`lastmod` present and varied" became "the source file's commit date"; `priority` and `changefreq`
  are flagged (PROMOTION.md §3).
- **Languages** - a second language in one DOM counts above 5 elements, fewer being the switch's endonyms (as i18n.md
  check 1); a script-picked locale gets a severity: meant to be found (declared, or named by the promotion ticket)
  with no URL of its own HIGH; any other MED, INFO where the ticket states its zero reach (PROMOTION.md §3).
- **Version, `og:image`** - a version only a browser call supplies is a defect (SITE_CONFIGURATION.md §2); the image
  is a committed site asset referenced absolutely, not merely off raw GitHub (SITE_CONFIGURATION.md §5).
- **Search results** - INFO and directional only, never HIGH or MED (PROMOTION.md §3 "Proof of indexing").
- **Added** - check 18 (SITE_CONFIGURATION.md §1), check 19 with the host-root verification file (PROMOTION.md §3
  "Search consoles"), the repository metadata of check 20 (PROMOTION.md §4 item 1), the icon and manifest
  (SITE_CONFIGURATION.md §5), the `hreflang` code, absolute-URL and `x-default` rules, the sitemap's subtree, and the
  redirect stub for lost and legacy URLs (PROMOTION.md §3).
- **AI crawlers, `llms.txt`** - INFO, the owner's call: the canon is silent on both (conventions section 5).
