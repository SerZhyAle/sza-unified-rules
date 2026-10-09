# Promotion - how a finished product gets found without spending money

A product that is built, released and translated is still invisible until a stranger can find it. This doc
is the one home for **free promotion**: positioning, being indexed correctly, the free channels by product
shape, launch moments, measurement without telemetry, and the shape of the promotion ticket every public
product carries. It was distilled on 2026-10-09 from the portfolio's campaigns (StreamsPlayer SP-0039, its
tactical plan, CyrFlip S0024, FastMediaSorter Android S1268, FileDO SP-0166 - first drafted as SP-0149)
and from the primary sources cited inline, all read on that date.

Boundaries: [DOCUMENTATION_CONCEPT.md](DOCUMENTATION_CONCEPT.md) §3 owns the tags a page must carry and §4 the
mandatory pages; [CHANNEL_MATRIX.md](CHANNEL_MATRIX.md) owns how a release is published to a channel. This doc
owns what makes the published thing **found**. The working procedure is the `promote` skill.

Third-party rules drift. Every rule below that belongs to someone else carries the date it was read; a step
that acts on one re-reads the source first and records the new date.

## 1. Principles - the non-negotiables

1. **No money.** No paid advertising, sponsored posts, paid directories, paid reviews, paid priority
   review, paid press. A paid listing fee that is the channel's entry ticket (a Store developer account) is
   distribution, not promotion, and is decided in [CHANNEL_MATRIX.md](CHANNEL_MATRIX.md).
2. **No telemetry to measure it.** No analytics script on a site, no tracker in the app, no click redirector,
   no `utm_` parameter. Measurement uses only counters the platforms already publish (§7). The privacy
   promise is a product feature and outranks attribution.
3. **Owned surfaces before outreach.** Whatever keeps working while the author sleeps - repository metadata,
   page tags, sitemap, package manifests, directory entries - comes before anything that needs a person to
   write a post. A post drives a spike; an indexed page compounds.
4. **Truth over reach.** Every claim maps to code, a test or a measured artefact; every number is read from
   the constant that produces it at write time, never copied from an older sentence. No superlatives or
   rankings ("best", "#1"), no invented rating, review, download count or traffic figure - in a listing, in
   structured data, or in a ticket's own baseline.
   **No competitor's name in anything we publish** (owner, 2026-10-09) - not as a keyword, topic or tag, not in
   a listing, site page, README or outreach text, not as "X alternative". A generic alternative is named instead
   ("unlike online converters"). Competitor names live only in the internal positioning worksheet and research.
   A component credit (a bundled library named in its notices) is not a competitor name.
5. **Disclosure is unconditional.** Every post names the author as the author. Where a community's rule asks
   about AI assistance, the product is disclosed as built with it or is not posted there; where a platform
   refuses generated text, the text is the owner's own. No second accounts, no vote or review requests, no
   comment posing as an ordinary user.
6. **Binary integrity.** A directory may link to, or mirror unmodified, the release files with their published
   SHA256. A site that wraps the download in its own installer or downloader is refused whatever traffic it
   offers; a listing found serving a different file is a removal request, checked by downloading through the
   directory's own button.
7. **Release-anchored cadence.** Outreach happens on a release, never as a standing activity: at most one post
   per community per release, never the same day everywhere. One-shot moments (§6) fire once per product.
8. **No nagging inside the product.** No rate-us prompt, share button or notification that exists to feed a
   channel. No feature invented to qualify for a directory.
9. **The agent executes; the owner authorises.** Every step carries one executor tag:

| Tag | Who | Covers |
| --- | --- | --- |
| **A** | agent alone | tree edits, local builds and gates, read-only API calls and browsing |
| **A·GO** | agent after the owner's go naming the step | any outward one-way act: a `gh` write, a push that publishes a site, a form submit, a pull request to a third-party repository, a console field |
| **A→O** | agent drives, owner acts at one point | sign-in, 2FA, CAPTCHA, OAuth consent, terms acceptance, identity data for an account - the agent stops there and resumes after |
| **O** | owner only | the human voice: the final submit of a community post and every reply to it, and any text on a platform that refuses generated text |

A go is quoted in a go ledger beside the ticket. Browser work happens in the owner's own signed-in browser,
records each submission (a GIF or the confirmation text), stops after two or three failed attempts, and never
sees a credential.

## 2. Positioning - one worksheet, every field derived from it

Positioning is decided once per product, written in one source, and every discoverability field is derived from
it. Where the shared contracts catalog binds a product to a single positioning source with ordered pillars
(`SITE-REPRESENTATION`), that source **is** the worksheet's published half; do not keep a second one.

**The worksheet** (April Dunford's order - the alternatives come first, the category last):

1. **Competitive alternatives** - what the target user does today without this product: a built-in OS feature,
   a manual workaround, a paid suite, an online converter, "nothing". Taken from real issues, reviews and forum
   threads, not brainstormed.
2. **Unique attributes** - what the alternatives lack, each with a pointer to code, a flag, a test or a
   measured number. An attribute without a pointer is cut.
3. **Value** - each attribute answered with "so what?" in the user's words (jobs-to-be-done: when [situation],
   I want to [motivation], so I can [outcome]).
4. **Target persona** - by situation and job, one primary segment. The product compass
   ([AUTHOR.md](AUTHOR.md)) sets the default: ordinary non-technical people.
5. **Market category** - an existing category people already search for ("duplicate file finder", "keyboard
   layout switcher"). A solo developer never invents a category.

The internal **positioning statement** follows: *For [persona] who [need], [Product] is a [category] that
[value]. Unlike [alternative], it [attribute].* It is never published verbatim; the "unlike" names a generic
alternative in public copy ("unlike online converters"), never a brand.

**Derived fields** (limits read 2026-10-09):

| Field | Rule | Limit |
| --- | --- | --- |
| Tagline | category + value in plain words | about 6-10 words |
| GitHub description | category noun first, what it does, platform, one differentiator | 350 chars (practice) |
| GitHub topics | purpose, domain, platform, stack, the category and its synonyms | at most 20, lowercase, hyphens, 50 chars each |
| README first paragraph | the tagline plus who it is for | - |
| Site `<title>` / H1 / meta description | "Name - category for platform" / the job / tagline + value | DOCUMENTATION_CONCEPT §3 |
| winget | `ShortDescription` says what it does; `Tags` = category, synonyms, platform; `Moniker` = the most typed term | 3-256 chars; at most 16 tags |
| Microsoft Store | description opens with the value; features = the attributes | features 20 x 200; search terms at most 7 |
| Google Play | title = name plus at most a category word; short description = tagline + value | title 30, short 80, full 4000 |
| Per-locale search terms | researched per locale, never translated literally | same limits per locale |

**Keyword research without paid tools:** search-engine autocomplete (clean profile, locale set), store and
`winget search` suggestions, competitor listings for their *generic* terms, GitHub topic pages for the spelling
people use, and - once registered - the Search Console query report (§3.2). Competitor names are research
input only, never published (§1 rule 4) - the Microsoft Store forbids other product titles in search terms
(policy 10.1.3) and Play forbids references to other apps in metadata anyway.

**The compass conflict.** A differentiator that is jargon to the compass persona (RTSP, iSCSI, hash) still
matters to a smaller technical audience. Pick per channel and never average: the store and the site speak to
the persona; a CLI catalogue, a technical subreddit or a curated developer list may lead with the jargon.

## 3. Indexing done right

### Host root and project pages

Crawlers read `robots.txt` **only at the host root** (RFC 9309; Google: crawlers "don't check for robots.txt
files in subdirectories"). Every portfolio product site at `serzhyale.github.io/<repo>/` is a project page, so
its own `robots.txt` is read by nobody and its `Sitemap:` line reaches no crawler. The host root
`serzhyale.github.io` is served by the user-site repository `SerZhyAle/SerZhyAle.github.io`, which today is a
redirect to the hub and answers 404 for `/robots.txt`.

- **The portfolio fix is one file at the host root**: an allow-all `robots.txt` with one `Sitemap:` line per
  live project sitemap (a `Sitemap:` line may name any path on the host). A wrong `Disallow` there de-indexes
  every product at once, so it never disallows anything without a portfolio-level review. It is owned by the
  hub, whose tree keeps the source of the user-site files; the hub's promotion ticket carries it, and product
  tickets reference it instead of repeating it.
- A project sitemap is valid for its own subtree (sitemaps.org) and keeps being generated in the product repo.
  The project `robots.txt` is harmless and may stay; nothing should depend on it.
- **Never add a `CNAME` to the user-site repository**: it moves every project page onto that domain and breaks
  every canonical, sitemap and verified property.

### Search consoles

- **Google Search Console.** A Domain property is impossible on `github.io` (no DNS). Use one **URL-prefix
  property for the host root** `https://serzhyale.github.io/`, verified by the HTML-file method in the user-site
  repository (Search Console does not follow redirects, and the root page is one) - it covers every project
  path, and each product's sitemap is submitted there. A per-product URL-prefix property with a meta tag on the
  product's landing is the fallback where the host-root property is not yet in place. A verification token stays
  for good: removing it un-verifies the property.
- **Bing Webmaster Tools** imports sites and sitemaps from Search Console (auto-verified, ownership re-checked
  through that link); no separate token is needed.
- **IndexNow** (Bing, Yandex, Seznam, Naver and others; **not Google**) accepts a key file inside a project path
  when `keyLocation` is passed, and then only for URLs under that path. A ticket that claims IndexNow must show
  the key file served live.
- **Yandex Webmaster** verifies hosts, not paths, so it too is a host-root act. It matters only for a
  Russian-speaking audience outside Ukraine; Yandex has been blocked in Ukraine since 2017-05-17.
- **Request indexing** through URL Inspection for a handful of key pages; a sitemap for the rest. Crawling takes
  days to weeks; re-requesting does not speed it up.

### Sitemaps and page heads

- The sitemap is **generated**, lists only canonical URLs that answer 200, and its `lastmod` is the date the
  page last changed significantly - the source file's commit date, never the build time. `priority` and
  `changefreq` are ignored by Google; leave them out.
- `<link rel="canonical">` is absolute and self-referencing; a redirect stub canonicalises to its target.
- `hreflang` is reciprocal (every language version lists itself and all others), absolute, ISO 639-1, with an
  `x-default`. GitHub Pages cannot send headers, so it goes in `<link>` tags or in the sitemap.
- **A language that exists only as a script-switched variant of one URL is invisible to search.** If a locale
  is meant to be found, it gets its own URL with its own canonical and `hreflang`; otherwise its search reach is
  accepted as zero and stated as such.
- `<meta name="keywords">` is ignored by Google ("no effect on indexing and ranking at all") - never add it as
  promotion work.
- Never block CSS, scripts or images a page needs to render; `robots.txt` is not a de-indexing tool - a page
  kept out of search carries `<meta name="robots" content="noindex">` and stays crawlable.

### Structured data - truthful or absent

- The landing carries one `SoftwareApplication` (or `MobileApplication`, `WebApplication`): `name`,
  `operatingSystem`, `applicationCategory`, `offers` with `price` 0, the canonical `url`, a durable
  `downloadUrl` or `installUrl`. Other pages carry a `WebPage` that `isPartOf` the site.
- **No `aggregateRating` and no `review` unless they are real ratings by actual users, visible on the page.**
  Google lists one of them as required for the app rich result, so a free app without real ratings simply is not
  eligible - and an invented or self-controlled rating risks a manual action. Ineligible is the honest outcome.
- `FAQPage` no longer produces a rich result for any site (since 2026-05-07) and `HowTo` is retired: neither is
  added for search reach. A real FAQ page is still worth writing for people.
- `WebSite` site-name markup works only at a domain or subdomain root, never under a project path - it belongs
  to the hub, not to a product site.
- `softwareVersion` only when it is rendered from the same manifest as the visible page, never retyped.
- Validate with the Rich Results Test and read "missing aggregateRating" as "not eligible", not as a defect.

### Proof of indexing

`site:` searches and third-party indexes do not prove anything. Proof is the console: URL Inspection ("URL is on
Google"), the Page indexing report, and the sitemap status "Success" with its discovered-URL count; for Bing,
the URL submission and the indexed-pages count.

## 4. Owned surfaces - phase A

Done before any third party is asked for anything, each with a static predicate:

1. **Repository metadata**: description, homepage (the product site), topics - all from the worksheet; at most
   20 valid topics, none of them a policy-forbidden term. `gh repo edit` sets the three in one command.
2. **Social card**: one artwork rendered by one generator at 1200x630 for Open Graph (with `og:image:width`,
   `og:image:height`, `og:image:alt`) and at 1280x640 for the repository social preview (PNG under 1 MB). The
   preview is read through GraphQL `usesCustomOpenGraphImage` and set only through the browser.
3. **The page heads** of §3 on every page, the sitemap reaching a console, and the mandatory pages of
   [DOCUMENTATION_CONCEPT.md](DOCUMENTATION_CONCEPT.md) §4 - "What's new" rendered from the release notes and
   "Support" - because they are also indexable, fresh URLs.
4. **One demo capture**: one master, under a minute, silent, recorded once and encoded per surface (an MP4 the
   site plays from its own origin, a short GIF for the README). No embedded third-party player.
5. **Package fields**: every manifest and listing field derived from the worksheet, consistent across channels
   - a tag dropped from one channel for policy reasons is dropped from all, and a test keeps forbidden terms out
   of every tag list the build owns.
6. **Cross-links between the author's own products** where the audiences genuinely overlap: the product site,
   README and listing link a sibling only where it serves the reader. A link added to the family grid changes
   every family page, so it goes through `SITE-FAMILY-MAP` in the contracts catalog first; a product session
   never edits a sibling repository - it writes the request.
7. **The hub card** stays current through [DOCUMENTATION_CONCEPT.md](DOCUMENTATION_CONCEPT.md) §5 and the
   `feature-to-site` skill.

## 5. Channels by product shape

Read 2026-10-09; re-read before acting. **W** Windows desktop, **C** command-line tool, **A** Android app,
**K** a kit or library for developers.

| Channel | Fit | Gate | Notes |
| --- | --- | --- | --- |
| winget | W, C | silent install, one PR per version | the baseline Windows channel; catalogues fed by it (winstall, UniGetUI) need no submission |
| Microsoft Store | W | certification | listing fields from the worksheet, per locale |
| Scoop main | C | non-GUI, at least 500 stars and 150 forks | out of reach for a new tool |
| Scoop extras | W | issue before PR, popularity box | prepare and test the manifest; request only when the box is truthfully ticked |
| own Scoop bucket | W, C | none | zero-gate fallback; costs one repository and an autoupdate manifest |
| Chocolatey community | W, C | automated checks plus human moderation, 35-day response window | per-release maintenance; take it only when cheaper managers are current |
| SourceForge import | W, C, A | none | mirrors repository and releases unmodified; apply the integrity check |
| AlternativeTo | W, C, A | verified account, moderation, English, "solve real problems" | our description names no competitor (§1 rule 4) - the site's own users link alternatives; no links in the description |
| FossHub | W | contact form, no promise | adware-free by policy |
| Softpedia, MajorGeeks | W | manual form / e-mail to editors | rules unread at source on 2026-10-09; read before acting |
| Softonic, Uptodown, FileHippo, CNET Download | W | - | **refused**: wrapper and bundling history; if found listed, ask for a direct link or removal |
| F-Droid | A | FLOSS build from source, no Play Services, Firebase or proprietary trackers | anti-features are labels, not bans |
| IzzyOnDroid | A | FOSS, signed APK, size cap, **refuses apps made in part with generative AI** | apply §1 rule 5: not submitted for an AI-assisted app |
| Obtainium | A | none | publish an "Add to Obtainium" link from the GitHub releases |
| APKMirror, APKPure | A | - | not a channel; mirrors of Play builds |
| Google Play listing | A | metadata policy: no ranking, price or promo wording, no keyword repetition | title 30, short 80 |
| awesome-* lists | by list | age, stars, format; several refuse AI-generated work | read the list's own contributing note at attempt time; one entry per PR |
| Chrome / Edge / VS Code listings | K, extensions | per store | search terms and keywords from the worksheet |

Refused everywhere: a portable-software directory that defines "portable" as settings beside the program, unless
the product really does that; any topical list whose association a resolved owner decision removed; a channel
whose terms require a feature built only to qualify.

## 6. Launch moments and communities

One-shot moments fire **once per product**: on the first release where phase A is complete, the demo exists,
and every package channel serves the current version. Firing one on a broken week wastes it permanently.

| Venue | Self-promotion rule | AI rule | Gate |
| --- | --- | --- | --- |
| Show HN | something people can run; the maker posts and stays to answer; no upvote asks | no generated or AI-edited text | restricted for new accounts since March 2026 - history first, or ask the moderators |
| Product Hunt | self-hunting allowed, personal accounts only, no upvote asks | read at attempt time | onboarding; relaunch after six months; video slot is YouTube only |
| Reddit | each subreddit's rules, re-read before each post; mod permission where required | per subreddit, several refuse largely AI-generated projects | karma and age gates |
| Habr | promotional text once in "Я пиарюсь" or a company blog | no text written or edited by a neural network | sandbox and invite |
| dev.to | not primarily promotional; substantial content | AI assistance disclosed; AI may not promote | none |
| Lobsters | self-promotion under a quarter of activity | "meaningful human authorship" | invite only, 70-day limits |

The posting itself is always **O** (§1 rule 9): the agent prepares the facts, the rules record and the form,
and checks the owner's draft against the rules; the owner writes where a platform refuses generated text, posts,
and answers. Outreach texts live in the ticket's folder, one file per target, with a header naming the rules
they were checked against and the date, before they are used.

## 7. Measurement without telemetry

Success is read only from public or owner-held counters:

- per-release asset `download_count` (excluding checksum files) and the GitHub traffic API - which forgets after
  fourteen days, so checkpoints are never more than fourteen days apart while outreach is active;
- stars, forks, and `usesCustomOpenGraphImage`;
- store consoles (Partner Center acquisitions, Play Console installs);
- Search Console and Bing queries, impressions, clicks and indexed counts - crawler-side, not visitor tracking;
- the merge state of package-manager pull requests and the outcome line of every channel.

A script in the product repo produces each checkpoint as a dated file; a ticket never types a number it did not
read, and a number it cannot read is written "unknown", never estimated. A baseline is measured before the first
action. Attribution stays coarse - that is the accepted price of rule 2.

## 8. The promotion ticket - required shape

Every **public** product carries one promotion ticket in its own ticket store, in that store's id scheme and
header format. A product not yet public carries one too, gated on its release decisions, so the campaign is
designed before launch rather than after. An internal tool carries none and its contrib record says so.

Required sections:

1. **Goal** and **Why**, with a measured baseline (§7) dated.
2. **Non-goals** - §1 restated as this product's lines, plus product-specific ones (store-policy terms, privacy
   promises, over-claim traps).
3. **Decisions** - those of §1 by reference, then this product's own (channel order, refusals, audience split).
4. **Positioning** - a pointer to the worksheet's source, or the step that writes it.
5. **Channels** - every row of §5 that fits the shape: planned, deferred with its revisit condition, or refused
   with the reason.
6. **Acceptance criteria** - each a static predicate:
   1. repository description, homepage and topics set from the worksheet;
   2. every page carries the §3 head and one truthful JSON-LD block, gate green;
   3. the sitemap is generated, lists every page, and a console reports it read;
   4. one social-card artwork at 1200x630 and 1280x640; `usesCustomOpenGraphImage` true;
   5. one demo capture, referenced from the README and the site;
   6. every outreach text exists in the folder before use;
   7. one outcome line per attempted channel, refusals included;
   8. metrics at baseline and at each checkpoint, at most fourteen days apart while active;
   9. no analytics, tracker, telemetry or redirector added; privacy page still literally true;
   10. every text names the author, answers the AI rule, and carries no forbidden term;
   11. the mandatory pages of DOCUMENTATION_CONCEPT §4 exist and are in the sitemap;
   12. discoverability fields agree across channels;
   13. every outward act has a go-ledger row; every A→O and O act was the owner's.
   Criteria that the product's shape makes void are listed as void with the reason, not deleted.
7. **Channel outcomes**, **Metrics**, **Risks**, **Open questions** - the record.
8. A **tactical folder** once the ticket is approved: phases in dependency order (baseline, owned surfaces,
   indexing, pages, package fields, demo, directories, launch, metrics and closure), each step tagged with its
   executor, and a go ledger.

Portfolio-level work - the host-root `robots.txt` and console property, the hub's own indexing - lives in the
**hub's** promotion ticket. A product ticket names it as a dependency and does not repeat it.

## 9. Applying to a project

1. Run the `promote` skill in a session started in the product repo; it measures the baseline, writes or
   corrects the ticket in the repo's own store, and records the result in the repo's contrib record.
2. Write the positioning worksheet before any field is filled.
3. Execute phase A (§4) and the indexing work (§3) before any directory or community step.
4. Fire the one-shot moments only behind the gate of §6.
