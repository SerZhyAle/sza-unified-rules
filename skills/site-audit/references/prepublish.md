# prepublish lens - may these site changes be pushed?

The gate before a push to the branch Pages builds from ([SITE_CONFIGURATION.md](../../../rules/SITE_CONFIGURATION.md)
§7): it judges the source tree in the served root as the push would publish it, one PASS, FAIL, WARN, n/a or
UNMEASURED per check; any FAIL means do not push, and a blocker check left unmeasured means the push is not cleared.
It follows [conventions](conventions.md), proposes no patch and writes only `prepublish.md`.

## Inputs

- **Collected evidence: none, by design** - `robot.json` and `ux_probe.json` are "missing" in prepublish mode and no
  skeptic re-measures this lens. With no repository on this machine nothing is gated: every check is "Not measured"
  and the push is not cleared.
- **The publish set**, what the deploy's "stage everything" puts live (SITE_CONFIGURATION §4):
  `git -C <repo> ls-files -co --exclude-standard -- <served root>`, less files gone from disk. Its `*.html` are the
  pages; the landing, the stamp's pages and the pages this push changes are the key pages.
- **This push**, what goes live that the Pages branch does not have yet:
  `git -C <repo> diff --name-status $(git -C <repo> merge-base origin/<source.branch> HEAD) -- <served root>`, the
  branch from check 1 (`@{upstream}` in its place when the Pages source is unknown; with neither, `HEAD` is the
  base), and `git -C <repo> status --porcelain -- <served root>`.
- **The latest release**: `gh release view --repo <owner>/<repo> --json tagName,publishedAt,assets` (the origin
  remote's), else the newest tag matching the stamp's `versionShape.tagRegex`
  (`git -C <repo> tag --list --sort=-v:refname`), never `git describe`; a tag of that shape on HEAD
  (`git tag --points-at HEAD`) is newer still, as a release commits its site, then tags
  (RELEASE_AND_DISTRIBUTION §4). A tag under `versionShape.editionTagPrefixes` is compared only with its own
  edition's controls (RELEASE_AND_DISTRIBUTION §5). With no release and no tag of that shape, nothing is compared
  with a release: check 7 keeps its status and committed-target lines, check 8 its committed-download line.
- **The Pages source**: `gh api repos/<owner>/<repo>/pages` - `source.branch`, `source.path`, `build_type`.
- **The stamp and the rules file**: `<repo>/.sza-canon.json` - `byteIdenticalPairs`, `privacy.page`, `versionShape`,
  `channels` and `exemptions`, where an `advertising` entry is the ad declaration (its `path` and `until`; past
  `until` it declares nothing) and an `SZA-SEC04` entry excuses one credential fixture (check 17); the agent-rules
  file (`CLAUDE.md`, `AGENTS.md`) for check 1.
- **Live**: HEAD each distinct download and install target, redirects followed, under conventions section 1; on a
  403, 405 or 501 one ranged GET (`-r 0-0`, the body discarded), and only its status after redirects counts (200 or
  206 passes); a 429 or a timeout is retried once and reported with its count, never a FAIL by itself - that target
  is then "Not measured". GET a release's `.sha256` where a page shows a checksum. No page of the site is fetched
  and no browser runs.
- **Budget**: counts and greps over every page as inline PowerShell or `py -I -c`, never a script file; check 3 reads
  every hit in context; checks 11 and 14 judge language on the key pages and 10 others, named in "Not measured".

## Inspect

Checks 1-10 and check 17's secrets line - the blocker checks - can FAIL, the rest only WARN; each gives its number's
source and a failure's severity (conventions section 4). A redirect stub (meta refresh, canonical to its target), a
`byteIdenticalPairs` copy and `404.html` answer only to checks 2-4, a stub and a copy to 6 as well. A search-console
verification file (`google<hex>.html`, `yandex_<hex>.html`, `BingSiteAuth.xml`) and an IndexNow key file answer to
no check, and no fix touches them ([PROMOTION.md](../../../rules/PROMOTION.md) §3).

Areas (conventions section 4): 1, 2, 17 `source`; 3, 22 `content`; 4, 19 `link`; 5 `404`, `docs` for its help
pages; 6 `canonical`, `robots` for `noindex`; 7 `download`; 8 `version`; 9 `jsonld`; 10 `robots.txt`; 11 `heading`;
12 `title`/`description`; 13 `hreflang`; 14 `lang`; 15 `og`/`twitter`; 16 `sitemap`; 18 `image`; 20 `third-party`;
21 `docs`.

1. **Pages source** ([SITE_CONFIGURATION.md](../../../rules/SITE_CONFIGURATION.md) §1, §4). The served root is what
   Pages publishes (`source.path`, or what a workflow's `upload-pages-artifact` step builds from), else HIGH and the
   rest "Not measured"; a Pages API that does not answer leaves check 1 "Not measured", and checks 2-22 run over the
   stamp's root. A branch build with no `_config.yml` and no `.nojekyll` at the served root: LOW; HIGH when a page
   links a path starting with `_`. Not on the Pages branch: INFO, nothing goes live before the merge. A Pages
   workflow (`build_type` `workflow`) whose deploy job does not wait for the same SHA's CI green while a CI
   `paths-ignore` spares the served root, unless the agent-rules file says so: LOW; a branch build has no deploy job
   and passes. Number: the API, the branch, the workflow.
2. **HTML integrity**. Per page, an `html.parser` pass (`py -I -c`) finds every element closed - void elements and
   those whose end tag the HTML standard lets an author omit (`p`, `li`, `td`, `tr`, `option` and the rest of its
   list) exempt - and the `<!--`/`-->` counts match; no unrendered placeholder (`{{name}}`, `<version>`,
   `&lt;version&gt;`, `%VERSION%`) the Pages build does not fill and no merge-conflict marker remains. Number: the
   unclosed elements, the counts, the first offender as `<path>:<line>`. Fail: HIGH - an unclosed element hides the
   rest of the page, and a placeholder is a false version fact.
3. **Release status in prose** ([DOCUMENTATION_CONCEPT.md](../../../rules/DOCUMENTATION_CONCEPT.md) §5). No forward
   look or readiness hedge §5 bans ("coming soon", "not yet", "in development", "beta" ..), in English or the Russian
   and Ukrainian forms it lists, no control tagged "soon", no heading over an empty section; §5's exceptions pass.
   Searched over the visible text, `title`/`alt`/`aria-label`, the meta description, JSON-LD strings and every locale
   of a script's i18n table; also no store badge or link for a channel the stamp's `channels` lacks and no live
   target proves (check 7), no published roadmap, and no `Planned` or `Upcoming` group on the what's-new page.
   Number: the phrase with its context, under 15 words, `<path>:<line>`. Fail: HIGH, a false release status.
4. **Internal links**. Every `href` and `src` that is relative or under the base URL resolves to a file of the publish
   set, a folder to its `index.html`. Number: the links checked, each broken one as `<path>:<line>`. Fail: HIGH for
   an `<a href>` or a control, a dead end; MED for a `src`, a stylesheet or an icon; LOW for a relative link that
   climbs out of the base URL - the public domain instead (SITE_CONFIGURATION §2).
5. **Removed, declared and orphaned pages**. The stamp's pages exist. A page once in the sitemap or linked, deleted
   or renamed by this push or since the previous run (else in 90 days: `git log --diff-filter=DR --name-status`),
   leaves a stub at its URL whose canonical names its target (PROMOTION §3), and so does every URL of this host the
   previous `report.md` or the baseline records as a held URL answering 404 (indexed, in a sitemap or linked; never
   the robot lens's 404 probe). On a site of stamp kind `product` (kind `portfolio` owes no product set), the
   privacy (`privacy.page`; the zero-data carve-out is for a tool with no site), how-to, what's-new and support pages
   of DOCUMENTATION_CONCEPT §4 are in the publish set (a titled section counts for how-to and support) and linked
   from the landing, support and privacy also from the footer (§1, §5), and the how-to pages link down to the window
   help pages the product ships (§4). Number: the diff line or the recorded 404, inbound links. Fail: HIGH, a 404 at
   a held URL or unreachable help - a dead end (conventions section 4); MED when a §4 page is missing or the landing
   or the footer skips one; LOW for a how-to page without its window help links, or another orphan.
6. **Canonical and noindex** (PROMOTION §3). One `<link rel="canonical">` per page, absolute and equal to its public
   URL (`index.html` and the trailing slash normalised); a stub and a `byteIdenticalPairs` copy name their target.
   Number: the href against the computed URL, the robots meta. Fail: HIGH when it names another page, or the landing
   or a stamp page is `noindex` - it leaves the index; MED when relative, missing, or off its sitemap row.
7. **Download and install controls**, on a product site (stamp kind `product`, or a landing offering a download): a
   control exists whenever a release does and no text denies one; its static `href` names a release asset, a store
   page, a package id or `/releases/latest`, a versioned one with a durable fallback beside it (SITE_CONFIGURATION §2);
   it answers 200 after redirects, to HEAD or to the ranged GET of Inputs
   ([RELEASE_AND_DISTRIBUTION.md](../../../rules/RELEASE_AND_DISTRIBUTION.md) §6). A versioned target or `.sha256` of
   the tag on HEAD with no published release yet: INFO "published by the release - prove it after the push
   (RELEASE_AND_DISTRIBUTION §6)", never a 4xx FAIL. Number: the href, the status chain, the tag. Fail: HIGH for no
   control, no static href or a 4xx/5xx - the visitor cannot get it; MED for no fallback, or a target committed in
   the publish set (RELEASE_AND_DISTRIBUTION §5).
8. **Release facts** (DOCUMENTATION_CONCEPT §4). The version shown, a versioned link's version and asset size,
   `softwareVersion`, a checksum and a release date equal the latest release's (edition prefix and `v` ignored;
   checksum against its `.sha256`; date against the release day in Europe/Malta, `publishedAt` converted or the date
   a `YY.MMDD.HHmm` version encodes - DOCUMENTATION_CONCEPT §2), in the static HTML - `api.github.com` may refine a
   fact, never be its only source; the landing shows the version by its control; workflow-filled facts are "Not
   measured", and so are the asset size and checksum of the tag on HEAD with no published release yet (check 7's
   INFO). With no release, a date shown for a committed download (in the text or a JSON-LD `dateModified`) equals
   its file's last commit date (`git -C <repo> log -1 --format=%cs -- <file>`; today's for a file this push changes).
   A PASS here is not the post-release proof: after the push those facts are re-read from the public page
   (RELEASE_AND_DISTRIBUTION §6). Number: each value as `<path>:<line>`. Fail: HIGH if one differs; MED if only
   `api.github.com` gives it or none shows.
9. **Structured data** (PROMOTION §3). Every JSON-LD block parses, locally. A product landing (as check 7 defines a
   product site) has one top-level `SoftwareApplication` (or `MobileApplication`, `WebApplication`), not nested in a
   `WebPage`, with `name`, `operatingSystem`, `applicationCategory`, `offers` at price 0, the canonical `url`, a
   durable `downloadUrl` or `installUrl`, and `softwareVersion` only where the release manifest renders it; every
   other page carries a `WebPage` that `isPartOf` the site. Number: the parse error, the types, the missing names.
   Fail: HIGH for an `aggregateRating` or `review` with no real ratings on the page, a false fact; MED for a parse
   error, or the landing's node nested, missing or short of a property; LOW for another page without its `WebPage`,
   or for `FAQPage`, `HowTo` or a project-path `WebSite`.
10. **Host-root files** (PROMOTION §3). `robots.txt` counts only at a host root: judge it when the base URL's path is
    `/` and in the user-site source the hub keeps (`github-root-redirect/`); a project's own file draws no finding and
    is never the fix. No `Disallow` covers a page or what it renders with (`noindex` keeps a page out), each comment
    names a path that resolves as check 4 resolves a link (a folder to its `index.html`), and the user-site source
    disallows only what a portfolio-level review records (the hub's promotion ticket) and has no `CNAME`. Number: the
    line, its path. Fail: HIGH for a `Disallow` over a sitemap row, the landing or a stamp page, an unreviewed
    user-site `Disallow`, or any user-site `CNAME`; MED for a `Disallow` over a page meant to stay out (`noindex` is
    the tool) or over what a page renders with; LOW for a stale comment.
11. **Headings** (DOCUMENTATION_CONCEPT §3). One `<h1>` per page, one language as a crawler without JavaScript reads it
    (all spans, tags stripped; a Latin name in a Cyrillic h1 is still one); feature areas are `<h2>`, not
    `role="heading"` spans or `<h3>` under the `<h1>`. Number: the h1 count, text and letters by script. Fail: MED.
12. **Title and description** (DOCUMENTATION_CONCEPT §3). `<title>` 1-60 chars without emoji, description 50-155
    chars, each unique in the publish set and equal to what the page's scripts set (`document.title =`,
    `setAttribute('content'`, an i18n table's default locale). Number: lengths, duplicates, both strings. Fail: MED.
13. **hreflang** (PROMOTION §3). Each `hreflang`, in `<link>` or the sitemap's `xhtml:link`, is absolute and ISO 639-1
    (an ISO 15924 script and an ISO 3166-1 region may follow: `zh-Hans`, `pt-BR`), and targets an indexable,
    self-canonical page of the publish set that lists this page and itself; `x-default` exists; a `?lang=`, `#ru`
    or same-file target is no page, and an `og:locale:alternate` needs a page too. Number: the target, its
    canonical, the missing back-link. Fail: MED.
14. **One language without JavaScript** (PROMOTION §3, DOCUMENTATION_CONCEPT §1). Where a script switches languages on
    one URL, `<html>` or `<body>` carries the default statically (`data-lang` or the switch's attribute) equal to
    `<html lang>`, and the static copy equals the script's default-locale strings; and the static text of each judged
    page, scripts and styles removed, reads as `<html lang>` - a Cyrillic share `cyr / (cyr + lat)` over 20% under
    `en` or another Latin-script `lang`, or under 50% under `ru` or `uk`, does not (the i18n lens's measure). Number:
    the attribute, the text's letters by script, the differing keys. Fail: MED. A script-only language has no search
    reach: INFO for the owner.
15. **Social card** ([SITE_CONFIGURATION.md](../../../rules/SITE_CONFIGURATION.md) §5, DOCUMENTATION_CONCEPT §3).
    `og:title`, `og:description` and an `og:url` equal to the canonical are present; `og:image` and `twitter:image`
    are absolute on the site's own host (never `raw.githubusercontent.com`), a publish-set file of at least 1200x630
    by its header; `twitter:card` is `summary_large_image`. Number: the URL, the pixels, the missing tags. Fail: MED.
16. **Sitemap** (PROMOTION §3). It lists every indexable page (self-canonical, not `noindex`, no stub) and nothing
    else - no missing file, no non-canonical URL; each `lastmod` is the file's last commit date
    (`git -C <repo> log -1 --format=%cs -- <file>`; for a file this push adds or changes, today's date passes), never
    one stamped date. Number: the rows against the pages, the distinct `lastmod` values, the offending rows. Fail:
    MED; LOW for a missing `lastmod`, or for any `priority` or `changefreq` element (PROMOTION §3: leave them out).
17. **Internal material and secrets** (SITE_CONFIGURATION §1). No publish-set path lies in a row the role map marks
    **no** ([REPOSITORY_LAYOUT.md](../../../rules/REPOSITORY_LAYOUT.md): `PLAN/`, `dev/`, `temp/`, `logs/`, `build/`,
    `bin/`, `obj/`, `DOWNLOADS/`, `.secrets/`, `test_media/`) or is internal material (a prompt, spec, audit report,
    ticket workspace, draft or status note - SITE_CONFIGURATION §1 gives examples, not a closed list). The secrets
    line: no path under `.secrets/` or named `*.pfx`, `*.snk`, `*.jks`, `*.keystore`, `keystore.properties` or
    `.env`, and no credential literal - files named `*token*` or `*secret*` read first - by the SZA-SEC04 rule of the
    plugin's `tools/check-compliance.ps1` (its six patterns: a GitHub, AWS, Slack or Google key, a private-key header;
    its text types; vendored trees skipped), unless a stamp `exemptions` entry `SZA-SEC04` covers the file (its
    `path`, before any `until`). Number: path, tracked or staged; for a credential the pattern and `<path>:<line>`,
    never the value. Fail: HIGH on the secrets line - do not push (REPOSITORY_LAYOUT "Secrets"); MED otherwise; the
    agent-rules files the role map keeps at the root: INFO (moving them breaks REPOSITORY_LAYOUT; serving from
    `docs/` is the owner's decision).
18. **Images**. A file over 100 KB declared under 200 px wide - by any CSS rule that matches the image, an attribute
    or an inline style: MED; no `width`/`height`: LOW; below the first section without `loading="lazy"`: LOW. Number:
    KB, pixels, declared px.
19. **Link attributes**. `target="_blank"` with no visible or accessible new-window hint: LOW; `noreferrer` on a link
    to one of the owner's hosts (`sza.od.ua`, `serzhyale.github.io`, `eltr.od.ua`): LOW. Number: the counts per page.
20. **Third-party hosts** ([SECURITY_AND_PRIVACY.md](../../../rules/SECURITY_AND_PRIVACY.md) §7, the network-surface
    row). The hosts of external scripts, stylesheets and iframes; one this push adds or changes against its base
    (Inputs): MED. An ad slot ([UI_UX.md](../../../rules/UI_UX.md) §3) the stamp does not declare, a second one on a
    page, one the privacy page does not name, one before the `<h1>` or the download control or inside the content,
    or a pop-up, interstitial, overlay, sticky or auto-playing one: MED. An analytics or tracking script other than
    the declared ad loader, or a `utm_` link parameter: MED (PROMOTION §1 rule 2). A remote script or font on a window
    help page: MED (UI_UX §7). Number: the host list, the diff line.
21. **Off-site help links** (DOCUMENTATION_CONCEPT §4). A nav or footer link for Documentation, Changelog, Release
    notes or License that leaves the site while an on-site page serves it: MED. Number: the link, the on-site page.
22. **Build stamps, debug text, keywords**. A build time, a commit hash, `debug`, `TODO` or filler in the visible
    text: LOW; a version among them is check 8's. A `<meta name="keywords">` this push adds: LOW (PROMOTION §3).
    Number: the fragment as `<path>:<line>`.

## Output

Added to the conventions section 8 shape:

- **`## Verdict`** under the header, three lines: `Blockers: <n> (checks <list>)`, `Warnings: <n> (checks <list>)`,
  `Re-run: /site-audit prepublish <repository path>`. Each `<n>` counts the findings returned at that level - HIGH
  for blockers, the number the workflow reports, MED and LOW for warnings. With no blocker,
  `Blockers: 0 - the push may go`, unless a blocker check is "Not measured" for a reason other than a fact the Pages
  build or the release fills: then `Blockers: unknown - checks <list> not measured; the push is not cleared`. With
  blockers, the unmeasured checks follow on the same line. The structured result's `verdict` repeats it: `pass`,
  `blocked` or `unknown`; the HIGH count alone cannot say "unknown", so the verdict decides.
- **`## Checklist`**, one line per check in order:
  `<PASS|FAIL|WARN|n/a|UNMEASURED> <n> <name> - <one evidence fragment>`. The worst page sets the mark and is named
  with the count (`3 of 212 links`); an INFO rides on its check's line; `n/a` states its reason (no release, no
  hreflang) and returns nothing; `UNMEASURED` states what was not measured and why.
- **Findings**: each FAIL as HIGH, each WARN as MED or LOW, and the INFO notes - one per check and page, or past 5
  pages one `site` line with the count and the first 5 paths. **Already good**: up to 8 PASS lines (conventions
  section 6); the Checklist is the gate's full record. **Changed since**: conventions section 7 over the rows a
  check here re-measures; the live-only rest is named once as not re-measured.
- **Returned**: `report` (the absolute path of `prepublish.md`), `findings`, `good` (those PASS lines) and
  `unmeasured`, no `jobs`; the workflow counts HIGH as blockers.

## Canon differences

- **Report, target, severity**: `<run folder>/prepublish.md`, not `audit/prepublish-<date>.md`, with no argument
  placeholder and the served root checked against the Pages source, never assumed (SITE_CONFIGURATION §1). FAIL is
  HIGH by conventions section 4, so the source's blockers that fail as a misread signal (h1, title and description,
  canonical form, hreflang, JSON-LD parse and shape, social image, sitemap, static language) are WARN MED; each rule
  stands.
- **Source-only proxies**: "parses" is an `html.parser` pass over the elements whose end tag HTML requires, and
  rendered size and the fold are read from the source - no browser runs.
- **Added**: release-status prose (DOCUMENTATION_CONCEPT §5); the Pages source, `.nojekyll`, the branch, the deploy
  gate, internal material (SITE_CONFIGURATION §1, §4); secrets in the publish set block the push
  (REPOSITORY_LAYOUT "Secrets"; the canon decides, conventions section 5); `noindex` on key pages, the user-site
  `CNAME`, a new `<meta name="keywords">` (PROMOTION §3); stubs for removed pages and recorded 404s, the lens's own
  rule, as a 404 at a held URL is a dead end (conventions section 4); reachable help, the privacy page and `<h2>`
  areas (DOCUMENTATION_CONCEPT §4, §3); static copy equal to the script's (DOCUMENTATION_CONCEPT §1, one source per
  fact); ad slots and their placement (UI_UX §3), analytics and `utm_` (PROMOTION §1 rule 2), remote help-page
  assets (UI_UX §7).
- **Canonical, hreflang, language**: a stub or declared copy canonicalises to its target; hreflang is also absolute,
  ISO 639-1, self-listing, may sit in the sitemap and never targets `?lang=`; a static `data-lang` only steadies the
  default - a script-switched language stays unfindable, the owner's decision, never reported as solved (PROMOTION §3).
- **Release facts**: the asset link, checksum and date join the version, all static, never from `api.github.com`
  alone, a durable fallback beside a versioned link (DOCUMENTATION_CONCEPT §4, SITE_CONFIGURATION §2); a target
  answers 200, a committed binary is no target, a tag on HEAD is the latest and its asset is proven after the push
  (RELEASE_AND_DISTRIBUTION §6, §5, §4); a date is read on the version clock, Europe/Malta
  (DOCUMENTATION_CONCEPT §2), and with no release a committed download's date is its file's last commit.
- **JSON-LD**: the canon's set (`name`, `operatingSystem`, `applicationCategory`, `offers` at price 0, `url`, a
  durable `downloadUrl` or `installUrl`, and a `WebPage` that `isPartOf` the site on every other page);
  `softwareVersion` only when the manifest renders it, so its absence passes; the two subtypes count; the rating,
  `FAQPage`, `HowTo` and `WebSite` rules join (PROMOTION §3).
- **Social card, sitemap, robots.txt**: `og:title`, `og:description`, `og:url`, and a >=1200x630 committed image with
  `summary_large_image` (SITE_CONFIGURATION §5, DOCUMENTATION_CONCEPT §3); canonical 200 URLs only, `lastmod` from
  the file's commit, no `priority` or `changefreq`; only a host-root `robots.txt` is judged, a project's own is never
  the fix (PROMOTION §3).
- **Since when**: third-party changes count from this push's base, the merge base with the Pages branch, as the
  deploy pushes all that is unpushed (SITE_CONFIGURATION §4); a relative link to a sibling site takes the public
  domain (SITE_CONFIGURATION §2).
