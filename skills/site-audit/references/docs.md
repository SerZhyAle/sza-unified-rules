# docs lens - can a visitor learn the product, reach support and read its privacy promise on its own site?

Maps the help and documentation pages to the canon's page set and finds the reader sent off the site, the retired
address left at a 404 and the internal note published by mistake. It runs under [conventions](conventions.md).

## Inputs

- **Evidence first:** `robot.json` per page - `status`, `title`, `titleLength`, `titleHasEmoji`, `description`,
  `descriptionLength`, `canonical`, `canonicalAbsolute`, `canonicalSelf`, `metaRobots`, `og`, `twitter`, `headings`,
  `jsonld[]` (`types`, `raw`), `images`, `links.githubBlob`, `appShell`, `textNoJs`, `statusPhrases`, `versions` - and
  site-wide `sitemap` and `hostRobots.disallow`; then `ux_probe.json` per page `desktop.perf.thirdParty`,
  `desktop.probe.imgs` and the `brokenImgs` of `desktop.probe` and `mobile.probe` (the checks name them without the
  profile key), and the screenshots in `shots/`. Both files hold the home page and at most 5 more, the stamp's first.
- **Live:** a fresh GET of the sitemap and of each docs page, for what `robot.json` does not hold (footer links, word
  count, the full word list of check 10). For a page `robot.json` lacks, the fields of checks 5, 6, 7, 9 and 13 come
  from that HTML; for a page `ux_probe.json` lacks, the remote hosts are those of its `src` attributes and stylesheet
  links, and a broken image is a failing HEAD of its `src`. HEAD for checks 11, 12 and 13. The lens never re-runs
  `robot-check.ps1` or `ux-probe.js`, which would overwrite the evidence.
- **Repository, when present:** `.sza-canon.json` (`site`, `privacy`, `channels`, `ledgerShape`, `docRegistryFile`,
  `byteIdenticalPairs`), `git ls-files` and `git log` under the served root, the READMEs, the ledger, the help map the
  agent-rules file names, the scripts and workflows that render pages, the permission manifests and the build's
  dependency files; with none (kind `external`), each repository half goes under "Not measured".
- **Budget:** 30 docs pages fetched, one per Coverage row first, and 40 HEADs, inside conventions section 1.

## Inspect

Docs pages are all but the landing and its language copies, from the stamp, the landing's links, the sitemap and
the served tree, less forwarders (a canonical to another address with a refresh or a link), the copies the stamp's
`byteIdenticalPairs` names, `404.html` and console verification files; help pages are those the help map names
(`CONTEXT-HELP` rule 17). Severity: conventions section 4.

1. **Page set** ([DOCUMENTATION_CONCEPT.md](../../../rules/DOCUMENTATION_CONCEPT.md) §4). Map the docs pages to a
   product's set: privacy, how-to or guide (one page of anchored task sections counts), What's new, support or
   contact (a page or a titled section), and window help pages where there is a user interface; the Coverage table
   holds each address and its `status`. No how-to on or off the site, or no support route at all: HIGH. Another
   missing page: MED. A `portfolio` site at a host root (the hub) owes no product set, and check 3 asks it only for
   the contact address and a response expectation; a `portfolio` site under a project path that offers a download
   owes the set. Kind `external` is mapped from the live site alone. When the base URL redirects to another host
   that is no bridge to the owner's canonical domain (eltr.od.ua to Google Sites), the pages there are off the
   product's own domain: Coverage gives their addresses and the set is missing from the domain, MED; the redirect is
   the robot lens's (its check 1).
2. **Privacy page** ([SECURITY_AND_PRIVACY.md](../../../rules/SECURITY_AND_PRIVACY.md) §4-5,
   [SUPPORT_AND_FEEDBACK.md](../../../rules/SUPPORT_AND_FEEDBACK.md) §7.2). The carve-out is for a tool with no site,
   so never here. Quote what the page says is accessed, why, whether it leaves the device, and the contact email.
   An item missing, a permission the repository declares (Android `uses-permission`, MSIX `Capability`, extension
   `permissions`) left unnamed, `privacy.sensitiveAccess` true with that access unexplained, or "no telemetry"
   without the local counting the code does (an item of the promise, SUPPORT_AND_FEEDBACK §7.2): MED. A claim the
   evidence contradicts: HIGH - "no tracking" beside an ad or analytics host in `perf.thirdParty`, or, with the
   repository, "no telemetry" or "no tracking" beside an analytics, crash-reporting or ad SDK in the build's
   dependency files (SECURITY_AND_PRIVACY §7 item 6). A site of any kind that loads an ad or analytics host
   (`perf.thirdParty`, or the loader in the fetched HTML) with no privacy page that names it: MED
   ([UI_UX.md](../../../rules/UI_UX.md) §3, SECURITY_AND_PRIVACY §7 item 3).
3. **Support path** (SUPPORT_AND_FEEDBACK §1, §3, §7.4). The support page or section names the tracker, the contact
   email, a response expectation and, where the product exports a diagnostic bundle, where it is and what to attach;
   tracker and `mailto:` links are counted in each fetched docs page's footer. A support page or section without the
   tracker, the contact email or a response expectation, or a docs page footer missing the tracker or the `mailto:`
   link: MED. LOW: no diagnostic-bundle note where the product exports one, a second support address on a product
   site, a support `mailto:` whose subject does not name the product (§7.4), or a help page whose footer does not end
   in that path - a help page takes this LOW, not the footer MED. On a product site, a support address another
   product's site also carries: INFO, once per report, naming for the owner the conflict between
   SUPPORT_AND_FEEDBACK §7.4 (one address per product) and `SITE-FAMILY-MAP` rule 3 (one contact everywhere).
4. **What's new** (DOCUMENTATION_CONCEPT §2, §4). Number: versions and dates quoted from a fresh GET, and the writer
   the stamp's `ledgerShape` names (§2): shape 1, the script or workflow that renders `CHANGELOG.md`; shape 2, the
   step that derives the curated notes from the dev-log; shape 3, the showcase generator; shape 4, the release skill
   or checklist that fans the notes out; with no shape, the script or workflow that names the page's file. An
   undated version, entries out of newest-first order, or a version with no link to its release: LOW. A shape 1 or 3
   page that no script renders, or that differs from its ledger, so a render edited by hand (§1): LOW. An
   `[Unreleased]` group on the page: MED (§5). Whether the newest entry is the latest release is the release-facts
   lens's question.
5. **Window help pages** (DOCUMENTATION_CONCEPT §4, UI_UX §7, which leaves their shape to `CONTEXT-HELP`). Against
   the help map's rows whose form is `page` or `both` (`layer`, `inherit` and `none` rows publish no page,
   `CONTEXT-HELP` rules 4 and 5): a page not published, a published page neither byte-equal to the shipped file nor
   generated from its source - judged by reading the generator and its inputs, never by running it (conventions
   section 1) - or one that needs a script (`appShell`, `textNoJs`) or makes a remote request (`perf.thirdParty`, or
   a remote script, font or image in the fetched HTML): MED. A page in the sitemap, without `noindex` (`metaRobots`)
   or under `hostRobots.disallow` (`CONTEXT-HELP` section 7 item G), or not linked from the how-to pages: LOW. No help
   map in a repository whose source has windows, screens or routes: LOW, page `repo` (UI_UX §7); with no repository,
   "Not measured". Check 6 skips help pages.
6. **Heads of docs pages** (DOCUMENTATION_CONCEPT §3, [PROMOTION.md](../../../rules/PROMOTION.md) §3): `titleLength`
   under 60, `descriptionLength` 50 to 160 and one whole sentence, no emoji (`titleHasEmoji`, `h1HasEmoji`),
   `h1Count` 1, sections as `h2` (`h2Count` 0 beside `h3Count` above 0, or any `roleHeadingSpans`, fails), an
   absolute self canonical, the Open Graph and Twitter tags, and a `WebPage` (`jsonld[].types`) that `isPartOf` the
   site. A canonical naming another URL, or a `noindex`, on a docs page meant to be found (the sitemap lists it, the
   nav links it or the stamp declares it): HIGH. No title, description or canonical, a relative canonical, or no
   `og:title`, `og:description`, `og:image`, `og:url` or `twitter:card`: MED (DOCUMENTATION_CONCEPT §3). A title or
   description shared by two or more pages, an emoji, or a broken outline: MED. A length out of range, a description
   that is not one whole sentence, or no `WebPage` that `isPartOf` the site: LOW; `FAQPage` or `HowTo`: LOW, as
   neither gives a rich result (PROMOTION §3).
7. **Readers sent off the site** (DOCUMENTATION_CONCEPT §1, §4). Each link labelled Documentation, Docs, Guide, Help,
   Manual, Reference, Changelog or Release notes, in any locale of the site, that leaves for `github.com`, a README, a
   wiki, a PDF or Google Sites (`links.githubBlob` is the first count): MED, whether or not a site page carries that
   content - say which, and name that page when one does. A link to `LICENSE` that answers 200: no finding.
8. **Content only in the README** (DOCUMENTATION_CONCEPT §1, §5). README sections a user works from - commands and
   flags, settings, configuration files and file formats, shortcuts - with no page or anchored section on the site.
   Number: the README headings against a search of the fetched docs pages for three distinctive terms of each
   section. MED.
9. **Stamps and script-only text** (PROMOTION §3). `sitemap.lastmodDistinct` 1 over more than one row, or
   `lastmodMissing` above 0: LOW, since `lastmod` is the source file's commit date. A build date-time in the visible
   text (`versions` or the fetched text) that is neither a version in the `YY.MMDD.HHmm` clock
   (DOCUMENTATION_CONCEPT §2) nor the release date shown beside a release (DOCUMENTATION_CONCEPT §4, the
   release-facts lens's): LOW. Content that needs JavaScript (`appShell` true, or a `Loading` placeholder in
   `textNoJs`): HIGH when it is the page's main content, MED when it is one section.
10. **Shipped facts and house style** (DOCUMENTATION_CONCEPT §5). Search the visible text of every docs page for the
    words and forms §5 bans, in every locale the site uses (`statusPhrases` holds part of the list): MED, HIGH when
    the live release record (the release page, the store listing) shows the thing as shipped. A dated deprecation
    notice, an app state string, the name of a store track the owner runs and a limitation stated in the present
    tense are not findings. A three-dot ellipsis, an em dash, an en dash or a horizontal bar in the prose: LOW,
    counted, and fixed in the lines the next edit touches, never by a sweep; a quoted real UI string and a Windows
    menu item's trailing ellipsis pass (§5 house style).
11. **Reach and addresses** (DOCUMENTATION_CONCEPT §4, PROMOTION §3). The landing links the docs entry and each page
    of check 1; a Docs, Help or Get started control aimed at an in-page anchor or off the site while an on-site guide
    exists counts as none: MED. A docs or help page that a page of the site links and that answers 4xx or 5xx: HIGH.
    A docs page, help pages aside, missing from the sitemap, or failing while nothing links it: MED. HEAD the retired
    addresses, newest first (`.html` files deleted or renamed under the served root, by
    `git log --diff-filter=DR --name-status`), and each docs address held elsewhere (the README, the app, a store
    listing, a sibling site, the previous run's report, or this host's baseline rows; `SITE-STRUCTURE` rule 8): a 404
    with no forwarder is HIGH when held, MED otherwise; a forwarder without a canonical to its target is LOW.
12. **Served tree and registry** ([SITE_CONFIGURATION.md](../../../rules/SITE_CONFIGURATION.md) §1,
    DOCUMENTATION_CONCEPT §6), repository only. HEAD up to 10 tracked files under the served root that the role map
    of [REPOSITORY_LAYOUT.md](../../../rules/REPOSITORY_LAYOUT.md) marks **no** (`PLAN/`, `dev/`, `temp/`, `logs/`,
    `DOWNLOADS/`, `build/`, `bin/`, `obj/`, `.secrets/`, `test_media/`) or that are the prompts, specs, audit reports
    or ticket workspaces SITE_CONFIGURATION §1 names: each 200 is MED. A served `.html` in no sitemap row and no
    registry exclusion that is no forwarder, no `noindex` page, no `byteIdenticalPairs` copy, no `404.html` and no
    console verification file: LOW (DOCUMENTATION_CONCEPT §6 item 4). With a `docRegistryFile`, a sitemap row that no
    record's address or page group covers (§6 item 6), or a record whose address fails: LOW.
13. **Screenshots** (DOCUMENTATION_CONCEPT §4, UI_UX §7), per how-to and help page: the image count, `noAlt`,
    `emptyAlt`, an `alt` that is a file name or a bare "screenshot", `probe.brokenImgs`. A broken image, or `noAlt`
    above 0: MED. LOW: an empty `alt`, a file name or a bare "screenshot" as a screenshot's `alt` (as robot check 8);
    one in another language than its page, or showing real paths or accounts instead of demo content
    (SECURITY_AND_PRIVACY §4); a help-page screenshot no script generates (repository; UI_UX §7, `CONTEXT-HELP`
    rule 14); and, for a product with a user interface, one screenshot or none across all its docs pages (page
    `site`, which then stands for the how-to pages too), a how-to page with no screenshot, or a window or panel a
    how-to page names with no screenshot of it there.
14. **Install paths and stated limits** (DOCUMENTATION_CONCEPT §4-5). Each channel in the stamp's `channels` has its
    install path on the site, a product with optional components shows its component, profile and channel matrix,
    and an artifact the release workflow does not sign has the operating system's warning explained beside that
    path: MED for each gap. A limit a user meets (what needs a network, what a permission is for, that third-party
    content the product opens is not its own) stated on no page a visitor reads before installing (the landing, the
    install path, the how-to): LOW.

## Propose

Under "Proposed patches", never applied: the lens writes `<run folder>/docs.md` and nothing else.

- **A diff** against the named repository file when the fix is under about 200 lines: a docs page head, against the
  generator, template or workflow step that writes it, else the served-root file
  ([INVARIANTS.md](../../../rules/INVARIANTS.md) 16); the link that sends a reader off the site; a forwarder at a
  retired address (a link, a canonical and a refresh to the target - `SITE-STRUCTURE` rule 8, PROMOTION §3);
  `noindex` on help pages and their removal from the sitemap generator; the `.gitignore` line with the
  `git rm --cached` step the ticket runs, or the move, that takes internal material out of the served root
  (SITE_CONFIGURATION §1).
- **A numbered plan** when larger, one item per missing page: its file under the served root, a title under 60
  characters with no emoji, a description of about 150, the absolute canonical with the Open Graph and Twitter tags,
  the `h1`, and 3 to 6 `h2` sections carrying what the "Must have" column of DOCUMENTATION_CONCEPT §4 asks of that
  page, each written whole in the present tense (§5). The plan adds no link before its page exists and no heading
  over a section still to be written.
- **Generated, never copied:** a page made from README content or the ledger names the command that renders it (the
  README section, `--help` output, a settings schema, the ledger) and the gate that fails the build on drift
  (DOCUMENTATION_CONCEPT §1, §5); a generator the repository already has is extended, not replaced.
- **Docs JSON-LD:** a `WebPage` that `isPartOf` the site (PROMOTION §3) with a `BreadcrumbList` breadcrumb, and a
  guide's `TechArticle` as its `mainEntity` where the page keeps one; no `FAQPage` or `HowTo`.

## Output

Added to the report of conventions section 8:

- **`## Coverage`**, after Findings: `page type | address | status | words | gaps`, a row per page of check 1, one for
  the help pages (published of mapped, `noindex`, in the sitemap), one each for install, reference and FAQ content
  wherever it lives, and `none` where a page does not exist.
- Areas match the lens that finds the same defect, so the report stage merges the two (conventions section 9):
  `docs` for a missing page, a page-set or install-path gap, a privacy or support item and check 4; `link` for check
  7; `status` for an address of check 11 that fails; `source` with page `repo` for check 12's internal material, as
  robot check 18 files it; `content` for script-only text and check 10; `sitemap` for a `lastmod` or a missing row;
  `image` for check 13; the field's own area for a head or outline defect. "Not measured" names each
  repository-only check by number when there is no repository; the result has no `jobs`.
- **Changed since** (conventions section 7): a head finding of the previous run or the baseline on a help page is
  listed as obsolete, superseded by `CONTEXT-HELP` section 7 item G, with that page's `noindex` and sitemap state as
  today's evidence; so is a gap the page set of check 1 retires, such as a reference kept on one long page.

## Canon differences

- The nine-page skeleton becomes the canon's set: getting-started, install, reference, FAQ and a docs index are
  content a guide may carry, `trust` is no required page (an unsigned artifact's warning is a limit beside its install
  path, §5; the checksum is the release-facts lens's), and a `portfolio` site at a host root owes none but the privacy
  page an ad or analytics loader needs (UI_UX §3), while one under a project path that offers a download owes the
  set - DOCUMENTATION_CONCEPT §4-5.
- Privacy: "one sentence per data class" becomes access, reason, whether it leaves the device, contact email, every
  declared permission, sensitive access, local counting beside "no telemetry", and each ad or analytics loader the
  site carries; the carve-out never applies on a site, and "no telemetry" is held against the build's dependencies -
  SECURITY_AND_PRIVACY §4-5 and §7 items 3 and 6, SUPPORT_AND_FEEDBACK §7.2, UI_UX §3.
- Support adds the tracker and email in every footer, one address per product with the product named in its
  `mailto:` subject, and help pages ending in that path - SUPPORT_AND_FEEDBACK §1, §7.4; an address the family shares
  is INFO for the owner, as `SITE-FAMILY-MAP` rule 3 asks for one contact everywhere.
- Window help pages are added, for the help map's `page` and `both` rows, and judged by publication from the shipped
  files, no request, `noindex` and absence from the sitemap, not by the SEO block - DOCUMENTATION_CONCEPT §4,
  UI_UX §7 (`CONTEXT-HELP` rules 4 and 5, section 7 item G).
- Title at most 60 and description at most 155 become under 60 and about 150 (50 to 160), and the head check adds the
  absolute canonical and the Open Graph and Twitter tags - DOCUMENTATION_CONCEPT §3.
- A `License` link to the repository's `LICENSE` is no finding while it answers 200: the role map keeps the licence at
  the repository root (REPOSITORY_LAYOUT role map, "Product intro, licence"); a `Changelog` link counts only where
  What's new is missing or bypassed (DOCUMENTATION_CONCEPT §4).
- A reference "generated when possible" is always a render with a drift gate - DOCUMENTATION_CONCEPT §1, §5.
- `lastmod` is the source file's commit date (the robot lens compares it); a forwarder canonicalises to its target and
  carries a link and a refresh to it (`SITE-STRUCTURE` rule 8); a docs page's type is a `WebPage` that `isPartOf` the
  site, and `FAQPage` and `HowTo` are never proposed - PROMOTION §3. `TechArticle`, on which the canon is silent,
  stays only as a guide's `mainEntity`, never in place of the `WebPage`.
- Help-page screenshots are judged as render targets, per language with demo content - UI_UX §7, `CONTEXT-HELP` rule
  14, whose language rule how-to screenshots follow too; a capture showing real paths or accounts is a finding on any
  docs page - SECURITY_AND_PRIVACY §4.
- Added: the shipped-fact and house-style scan of docs pages, and proposed pages written whole, with no empty
  section and no link ahead of its page - DOCUMENTATION_CONCEPT §5.
- Added: internal material in the served tree, and reverse coverage; proposals stay in the report, never as files
  under the site root, where every tracked file is published - SITE_CONFIGURATION §1, DOCUMENTATION_CONCEPT §6.
- Not from the canon: the workflow's target fields replace the base-URL argument; a plan starts at about 200 lines; a
  titled support section on another docs page counts as the support page.
