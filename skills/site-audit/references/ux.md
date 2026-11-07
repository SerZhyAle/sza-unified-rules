# ux lens - can a first-time visitor tell what this is, get it and learn it, on a laptop and on a phone?

The visitor arrives from a search result or a shared link, on a 1366 px laptop and a 390 px phone. This lens walks
that visitor's three jobs - Understand, Get it, Learn - counts what each costs, and measures what slows it;
[conventions](conventions.md) holds everything this file does not say.

## Inputs

- **`ux_probe.json` first**: per page `desktop`, `mobile` and, for the first URL, `desktop-dark` - `nav`, `err`,
  `perf`, `probe`, `consoleErrs`, `failed`, `shot` - and `apiGithubLoads`. A screen is the profile's `probe.vh`.
- **The screenshots**: every `shot`, read with the Read tool before any visual claim and cited by file name. Each
  shot is the first screen only (no full-page capture): 1366x800 on the desktop; on the phone, 390x664 CSS px drawn
  at 3x (`probe.dpr`), so 1170x1992 image pixels; every other `probe` number is in CSS px. What lies below it is
  judged from `probe` numbers, `robot.json` and the source, never from a shot.
- **`robot.json`**: what a visitor without script, a crawler and a failed script get - `title`, `description`,
  `headings.h1NoJs`, `textNoJs` (its first 400 characters only), `versions`, `statusPhrases`, `images`,
  `links.downloads`, `scripts`, `jsRewrites`, `apiGithub`.
- **Live, GET and HEAD only**: each page of `ux_probe.json` (one GET), for the footer links of check 3 and the full
  text of check 5; each acquisition and Learn target through its redirects; the hub card that links to the base URL
  (one GET of `https://sza.od.ua/`); `https://github.com/<owner>/<repo>/releases/latest` (HEAD) when a page says
  nothing is published, offers only the source, or carries a release claim or a status phrase;
  `<host root>/ads.txt` (GET) when `probe.adSlots` is over 0.
- **The repository, when present**: the served root's HTML for what the probe does not report, the stylesheet
  (colour tokens, focus styles, font stacks, control sizes), the scripts (language and theme switch, every
  `api.github.com` call), the listing source, the README, `.sza-canon.json`, the network-surface inventory, the
  privacy page - cited `<path>:<line>`.
- **Budget**: the pages in `ux_probe.json`; a Learn walk of at most 3 clicks and 12 fetched pages; the caps of
  conventions section 1. The lens writes only `<run folder>/ux.md`, drives no browser and never re-runs `ux-probe.js`
  (it would overwrite the evidence); what neither the evidence, curl nor the source shows goes under "Not measured" -
  with no `ux_probe.json`, every rendered claim.

## Inspect

Checks 1-3 walk the three jobs in order on both profiles - clicks from the home page, screens from its top; on a site
of kind `portfolio`, Get it is opening a product's page from its card. Checks 4-14 measure. Each check names its area
in parentheses, any exception after it, because page, area and defect are what the site report merges on
(conventions section 9); severity is by conventions section 4.

1. **Understand - the first screen** (`content`). Quote the h1 and the opening of the first paragraph, each under 15
   words (conventions section 3), rendered (`probe.h1`, `probe.foldText`) and without script (`headings.h1NoJs`,
   `textNoJs`), and answer from the first screen of each profile: what is it, for which platform, what does it cost,
   is it released. The h1 states the job ([DOCUMENTATION_CONCEPT](../../../rules/DOCUMENTATION_CONCEPT.md) §3); the
   full name stands above it (`PAGE-CONTENT` "The landing always carries" item 1). **HIGH** when neither the h1 nor
   the first paragraph says what the product does (an apology, a notice, a bare "About"), or the live channel
   contradicts a price, platform or release claim; **MED** when a product's name or platform is not on the first
   screen; **LOW** when cost or release status first shows lower (give the screen), the full name or the eyebrow
   shows twice on the first screen, the header's short name aside (`PAGE-CONTENT` "Layout contract"), or a product's
   landing shows no screenshot - of its window, or of a command-line tool's output (DOCUMENTATION_CONCEPT §4).
2. **Get it - the first acquisition control** (`download`; no version: `version`): a file, a store, a package id, a
   releases page, or on a hub a card's link. Take `probe.firstCta` per profile and every `links.downloads` entry,
   HEAD each target through its redirects, and note the version and date beside it (`probe.versionsInText`,
   `versions`, `versioned`). Cost: clicks from the first screen to the file, store page or package command. A
   `firstCta` whose `href` is a fragment of the same page is an in-page jump - one click, not the control: judge the
   control it lands on from the shot and the source. **HIGH** when there is no control, the only one is the source
   while `releases/latest` redirects to a tag, or a control answers 4xx or 5xx or names a channel the product is not
   on (DOCUMENTATION_CONCEPT §5); **MED** when the first control is below the first screen of either profile, shows
   no version (DOCUMENTATION_CONCEPT §4), or sits in a closed `<details>` (`PAGE-CONTENT` "Mandatory page order for
   apps": the first safe action is never hidden); **LOW** when it shows no date.
3. **Learn - from the home page** (`docs`; a broken link: `link`). Reach the documentation and its install guide, the
   command reference where the README has one, "What's new", support and privacy (DOCUMENTATION_CONCEPT §4), and a
   UI product's window help ([UI_UX](../../../rules/UI_UX.md) §7); on a hub, the contact block, which stands for the
   support page and its footer links, and each card's target (HEAD, 200 expected) - a product's documentation is
   walked by that product's own run. Count clicks at 1366 and 390 px (a menu tap counts) and GET each target.
   **HIGH** when the documentation or support is not reachable in 3 clicks or its link answers 4xx or 5xx; **MED**
   when the documentation is more than one click away (`PAGE-CONTENT` "The landing always carries" item 4), a page's
   footer lacks the issue-tracker link or the contact `mailto:` (DOCUMENTATION_CONCEPT §5: both linked from the site
   footer), "What's new" or privacy is unreachable, a target leaves the site (github.com, Google Sites, a PDF) while
   no site page carries its content (**LOW** when one does, as docs check 7), or the support page lacks an issue
   tracker or a contact address (DOCUMENTATION_CONCEPT §4); **LOW** when the support page states no response
   expectation. A header command that duplicates a destination the page offers elsewhere (the hub's Contact) and
   leaves the strip under 481 px is no finding (`PAGE-STYLE` amendment 2026-10-21 item 7); a caption hidden to fit
   (`layout`, the same item) or a language switcher only in the footer or behind a menu (`lang`, `PAGE-CONTENT` "The
   landing always carries" item 2) is **LOW**. A phone number in plain text is **INFO**.
4. **One positioning** (`positioning`; a rewritten head: `title` or `description`, as robot check 12;
   [PROMOTION](../../../rules/PROMOTION.md) §2). Side by side: the static `title` and `probe.title`, `headings.h1NoJs`
   and `probe.h1`, the description, the first paragraph, the hub card, the listing source (store metadata, a winget
   `ShortDescription`) and the README's first paragraph. The title reads "Name - category for platform", the h1 the
   job, the description the tagline and the value; a store's own listing omits its platform, which is no mismatch.
   **MED** for a second category or job on any surface, and for a static head the script rewrites into other words
   (`jsRewrites` over 0, `title` against `probe.title`). On a hub, a card whose text runs over twice the median
   card's word count is **LOW** (`content`; `PAGE-CONTENT` "Copy rules": one card, one recognisable task).
5. **Release status and voice** (`content`; emoji in the title: `title`, in the h1: `heading`; DOCUMENTATION_CONCEPT
   §5, UI_UX §3-4). From `statusPhrases` (part of the list), `probe.foldText`, and a search of each page's full
   visible text in every locale the site ships (a fresh GET, and the source where a script swaps the language) for
   every word and form DOCUMENTATION_CONCEPT §5 bans and for its wordless forms (a disabled control tagged soon, a
   heading over an empty section): a banned phrase or readiness hedge is **MED** anywhere on the page, **HIGH** when
   the live releases contradict it. The fix deletes it or states the shipped fact, and never moves it lower: a
   component that was not ordered is on no surface; one the product's `SITE-REPRESENTATION` profile lists as `gated`
   stays, in the present tense, with no marker, date or version and no download link or call to action
   (DOCUMENTATION_CONCEPT §5, `SITE-REPRESENTATION` 0.2 rule 4a). A store track's name, a dated deprecation and a
   present-tense limitation stay. Superlatives and a competitor's name or a comparison with one (PROMOTION §1
   rule 4) are **LOW**, and so are emoji in the h1; emoji in the title are **MED** (as robot check 2).
6. **Release facts fetched by the browser** (`version`; DOCUMENTATION_CONCEPT §4). When `apiGithub` is over 0, count
   the `apiGithubLoads` that did not answer 200 ("403 on 2 of 6 loads"; a 403 whose `remaining` is 0 is the hourly
   limit of the measuring machine's address, which a visitor hits the same way) and read what a failed call leaves: the
   static control (`links.downloads`, `textNoJs`) and the script's failure branch. `apiGithubLoads` covers the first
   URL only (one load per profile plus 3 desktop reloads); a call on another page has no count - quote its `failed`
   lines and put the count under "Not measured". **HIGH** when no working acquisition link is left; **MED**, even
   when every load succeeded, when the version exists only after the call (not in `versions`) or the versioned link
   does (no `links.downloads` entry with `versioned`), or when the button has no durable fallback
   (`/releases/latest`, the package id, the store page); no finding when the static page carries both, beside that
   fallback, and the call only refines them.
7. **Weight** (`perf`; an image: `image`; [SITE_CONFIGURATION](../../../rules/SITE_CONFIGURATION.md) §5). Match
   `perf.heaviest` to `images.items`: an image heavier than an uncompressed bitmap of its rendered size at the phone's
   3x density (width x height x 36 bytes, the size from `width`/`height` or the stylesheet) is **MED** - export it at
   that size, set `width` and `height`, lazy-load it below the first screen. **LOW**: a font stylesheet from another
   host in the head; a script from another host in the head without `async` or `defer` (read in the served HTML:
   `scripts[]` records neither attribute nor where the script stands); a font stack with no system fallback; a
   weight no rule uses; a script library among the five heaviest assets (with its bytes).
8. **Errors** (`image` for a broken image, else `perf`), per profile (`consoleErrs`, `failed`, `probe.brokenImgs`,
   `err`): a broken image or a failed same-origin request is **MED**; a console error **LOW**, or the job's severity
   when it breaks a control; a failed third-party request **INFO**. A profile whose `err` holds a `navigation:`
   timeout (no load event within 45 s) is **MED**, with the third-party hosts it loaded (`perf.thirdParty`) named as
   the suspects (SITE_CONFIGURATION §5).
9. **Phone layout** (`layout`). `probe.overflow` at 390 px is **MED**; so is a header taller than a quarter of `vh` or
   content starting below half of it (`headerHeight`, `firstContentTop`; count the header's rows on the shot), by
   UI_UX §2 "content first". A page over 2 screens (`docH` / `vh`) with no back-to-top control (`PAGE-STYLE` 4.12),
   or with a header that does not stay at the top (4.1; its `position` in the stylesheet), is **LOW**, each. On every
   shot, clipped or truncated text and overlapping or stray elements are **MED** when they hide the job text or a
   control, **LOW** otherwise (UI_UX §4: text fits the narrowest layout).
10. **Targets** (`a11y`; UI_UX §2, `UI-SIZING`). Touch, 48 px: `probe.smallTapTargetsAboveFold`, kept to covered
    controls - buttons and button-styled links, boolean options, group headers, and the language, theme, copy, menu
    and back-to-top controls when they are buttons; a plain text link, a row of language links included, keeps its
    own geometry (`PAGE-STYLE` section 12). **MED** when the first acquisition control is among them, **LOW**
    otherwise. Pointer, 32 px: the desktop control sizes in the stylesheet, **LOW**.
11. **Text** (`a11y`) - `probe.fonts` and `bodyFontPx` on the phone: body text, or any text row such as a language
    row, under 15 px is **LOW**. `probe.fonts` reads only `p`, `li`, `dd`, `td`, `blockquote` and `figcaption`, so a
    language or nav row is measured from its selector's `font-size` in the stylesheet and checked on the phone shot.
    Contrast (UI_UX §5): 4.5:1 for text, 3:1 for controls, borders and glyphs, light and dark both, from the
    stylesheet's colour tokens against their background (cross-check `probe.bgColor`); text under it is **MED**,
    non-text **LOW**.
12. **Keyboard and links** (`a11y`; link text: `link`; UI_UX §5-6). No visible focus - a rule that removes the focus
    outline with no `:focus-visible` or `:focus` rule drawing an outline, border or shadow - is **MED**. **LOW**: no
    skip link (`probe.skipLink`); a glyph-only control with no accessible name; a theme control without its visible
    word, even with an `aria-label` (`PAGE-STYLE` 4.3); a decorative glyph a screen reader reads, such as a `#`
    before each h2 with no `aria-hidden` (`PAGE-STYLE` amendment 2026-10-21 item 3); new-tab links with no visible
    or `aria` hint (`probe.newTabNoHint`, with the count). One link text repeated for different targets is **MED**
    (as robot check 9); a card whose name is not its link is **MED** on a hub, **LOW** elsewhere.
13. **Theme and language** (`a11y`; a language defect: `lang`; UI_UX §5-6). A theme switch exists
    (`probe.hasThemeSwitch`), the first visit follows the system (the `desktop-dark` `bgColor`, under `colorScheme`
    "dark", differs from `desktop`'s), the choice persists and switches without a reload (`PAGE-STYLE` 4.3): each gap
    **LOW**; text that vanishes on the dark shot **MED**. A flag image or emoji standing for a language is **LOW**;
    the RU EN UA segmented control and the secondary row of two-letter codes pass (the shape `PAGE-STYLE` 4.2 gives
    UI_UX §5); a picker or list that shows a code with no endonym, or a language named in another language, is
    **LOW**. When the address carries no language (no per-language URL, no `?lang=` written on a switch, `PAGE-STYLE`
    section 7), a shared link opens in the recipient's language: **MED**. A page that ignores the shared `sza-lang`
    key (same section) is **LOW**; across hosts only the address can carry the choice: **INFO**.
14. **Ads, consent, third parties** (`third-party`, `consent`; UI_UX §3, PROMOTION §1 rule 2,
    [SECURITY_AND_PRIVACY](../../../rules/SECURITY_AND_PRIVACY.md) §4, §7). From `perf.thirdParty`, `probe.adSlots`
    (declared, filled or not) and `probe.adSlotsShown` (seen this time), `probe.consentDialog`, the page's links and
    the shots: an analytics or tracking host other than the hosts of a declared ad slot's network, a click
    redirector, or a `utm_` parameter on a link is **MED** (PROMOTION §1 rule 2). Any other host in
    `perf.thirdParty` (a font or script CDN) with no network-surface row or no line on the privacy page is **LOW**
    (SECURITY_AND_PRIVACY §7 item 3). An ad slot stands beside the content, never in it and
    never above the h1 or the download, one per page at most. It is declared in `.sza-canon.json` (the hub's form:
    an `exemptions` entry `advertising` whose `until` has not passed), is a row of the network-surface inventory,
    and is named on the privacy page; `ads.txt` at the host root names the loader's publisher id
    (SECURITY_AND_PRIVACY §7 item 3). Each unmet condition is **MED**. A sponsored placement, a partner banner or an
    affiliate pitch is **MED** on any page (UI_UX §3); an ad that imitates a control or a download is **HIGH**, any
    other intrusive form **MED**. A consent dialog is **MED**, with what it covers and the hosts it loads. A privacy
    page that says "no ads", "no tracking" or "no telemetry" while the page loads an ad, analytics or tracking host
    is **HIGH**.

## Output

Added to the conventions section 8 report, where every visual finding names its screenshot file:

- **"## Three jobs"**, after "Findings": job | cost (desktop / phone) | where it stalls - three rows, Understand in
  screens, Get it and Learn in clicks, the stall as page and point ("/ - Install at 1.4 screens on the phone") or
  "none". The same three rows are the structured result's `jobs` (`job`, `cost`, `stall`).
- **"## Measured"**, before "Not measured": page | profile | load ms | bytes | requests | third-party hosts | header
  px | content top px | screens | small targets | shot - one row per page and profile, so "Changed since" can
  compare numbers; the earlier numbers are read from the previous run folder's `ux.md`, since its `report.md` does
  not carry them.

## Canon differences

Changes from the prompt-pack source, `site-audit-ux.md`:

- **Targets**: the pack's 44 px becomes 48 px for touch, plus 32 px for a pointer, on covered controls (UI_UX §2).
- **Positioning**: "the h1 omits the product name" is dropped - the h1 states the job (DOCUMENTATION_CONCEPT §3),
  the name lives in the title "Name - category for platform" and above the h1; hero against hub and listing becomes
  PROMOTION §2's derived fields across title, h1, description, hub card, listing and README.
- **Unreleased claims** cover every banned phrase, hedge and wordless form on the page, and the fix deletes, never
  moves lower (DOCUMENTATION_CONCEPT §5). An ordered component that no package carries keeps its present-tense name
  where PROMOTION §2 would drop it, because DOCUMENTATION_CONCEPT §5 is the rule's one home (`SITE-REPRESENTATION`
  0.2 rule 4a).
- **A runtime version** - one only the browser call supplies - is a defect even when every reload succeeds; a call
  that refines a rendered version is not (DOCUMENTATION_CONCEPT §4).
- **Reloads**: "reload 3 times" is the probe's 3 desktop reloads of the first URL; a browser call on another page
  has no count and is judged from its `failed` lines.
- **Heaviest assets**: listing the 3 heaviest moves to the robot lens (its check 8); this lens judges their weight.
- **Contrast** of muted paragraphs becomes 4.5:1 text and 3:1 non-text in both themes; the theme control shows its
  word and switches live; no flag stands for a language (UI_UX §5-6).
- **Focus** is read from the stylesheet, not seen on Tab: the probe presses no key; tab order and keyboard operation
  go under "Not measured".
- **Learn** reaches the mandatory pages, and the tracker and the email are one click from every page, both in its
  footer (DOCUMENTATION_CONCEPT §4-5).
- **Ads and consent**: from "what they cost" to the canon's terms - one declared, capped slot beside the content, with
  its network-surface row, its privacy-page line and `ads.txt`; no analytics host beyond that slot's network and no
  sponsored placement; privacy claims that hold (UI_UX §3, PROMOTION §1 rule 2, SECURITY_AND_PRIVACY §4, §7).
- **Fonts and head scripts** are checked against SITE_CONFIGURATION §5: a system-font fallback, nothing waits on the
  network.
- **Renderer**: the collect stage's `ux-probe.js` is the only render; the lens opens no browser tool, so no two
  lenses judge different renders; without `ux_probe.json` every rendered claim goes under "Not measured"
  (conventions section 3).
- **Output**: no `audit/ux-<date>.md` or `audit/shots/` in the repository, only `<run folder>/ux.md`, because every
  tracked file under the served root is public (SITE_CONFIGURATION §1).
