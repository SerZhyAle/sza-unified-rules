# UI & UX - one family: the same room, the same buttons, the same voice

How every product of the portfolio looks, behaves and speaks to its user - on Android, on Windows, on a web
page, in the kit. The aim is that a user who knows one product opens another and finds the same things in the
same places, said in the same way. Where products cannot be identical, they must at least look alike.

This page holds the **principles, the precedence and the tone**. The exact shapes - palette roles, glyph
vocabulary, window behaviour, page layout - are shared contracts in the catalog (`APP-STYLE`,
`APP-BEHAVIOUR`, `WINDOWS-UI`, `BUTTONS`, `ICON-SET`, `ICON-RENDER`, `PAGE-STYLE`, `CONTEXT-HELP`; see [CONTRACTS.md](CONTRACTS.md)) and are cited
there by id and section, never copied here. Platform specifics are marked *(overlay)*.

## 1. The reference is FastMediaSorter Android

FastMediaSorter Android has been through the longest UI/UX development in the portfolio, and it has a
written standard (its phone component patterns, its communication policy, its button taxonomy, its icon
vocabulary). Every other product listens to it:

- **Where FMS has an answer, the other products take it** unless they record a reason. Where it has the
  numbers - spacing, radii, icon tiers, contrast targets - those numbers are the defaults everywhere.
- **Where FMS has no answer** (window state, tray, installer, single instance - moments that exist only on
  a desktop) the desktop contracts govern. Where a desktop contract and FMS disagree on something both
  cover, the product follows FMS and files a proposal to amend the contract.
- **A product that disagrees complies or amends** ([CONTRACTS.md](CONTRACTS.md)): a proposal to the catalog,
  or a dated exception with an `until` date. A silent local look is a violation, because it is invisible to
  every other product until a user notices that two of them feel unrelated.
- **Take the intent and the gate, not the raw counts.** FMS drifts from its own documents in places
  (literal text sizes in layouts, toasts where the policy says snackbar). Copying what FMS *does* instead of
  what it *specifies* copies the defect.

## 2. Take little of the user's screen; give the rest to content

- **Content first, chrome second.** One command strip, not title bar plus toolbar plus bottom bar. No title
  where the tab or the context already names the screen. No hero, banner or decoration in a tool.
- **Viewers and players go edge-to-edge**, and their chrome hides itself after a moment; the user can keep it
  visible. A thumbnail grid can drop its overlaid buttons.
- **A compact setting is reachable by the user** in every list-heavy UI. Compact is a density, not a different
  product: the same elements, smaller steps.
- **Space is spent through a closed set of named tokens**, not literals: spacing 4 / 8 / 12 / 16 / 24 / 32,
  corner radii 8 / 12 / 16, icon tiers 16 / 20 / 24 / 32 / 40 / 48, a short list of elevations, a type scale
  by role (title, subtitle, detail, badge). Buttons use the binding geometry of `BUTTONS` section 3,
  including its radius token. `UI-SIZING` governs values derived from shared size tokens; supported
  scaled values do not need per-value exceptions. Other values need a written decision.
- **Covered controls share `UI-SIZING` profiles:** ordinary targets use 32 logical units for pointer
  and 48 for touch; explicit compact mode may reduce them within a product's declared and tested range.
  These rules cover buttons, boolean options, group headers and settings navigation. Other controls
  retain `ICON-RENDER` floors. The painted glyph and its clickable area are separate measurements.
- **Reflow, do not fork.** One layout parametrised by width; a second layout only where the *structure*
  differs, not the size.
- **Collapsible groups follow `COLLAPSIBLE-GROUP` 1.0 or later.** Group by topic, use a distinct header
  with a current-state triangle, and expand in normal flow across the content region without losing
  the viewport anchor. A single-topic page normally has no collapsible wrapper. Packing collapsed
  headers into rows is a documented per-screen choice, not a universal requirement.
- **No dead ends.** An empty state is a glyph, one sentence giving the reason, and an invitation to act. A
  loading state says what is loading. An error state offers Retry.

## 3. No intrusive or dedicated advertising

Less advertising is a product rule, not a preference. What is ruled out on our own surfaces is **intrusive
advertising, and advertising dedicated to someone else's products and services** - not every ad slot.

- **Intrusive** - anything that interrupts or hides the user's work or reading: a pop-up, an interstitial, an
  overlay, a sticky or auto-playing ad, an ad inside a work flow or between a user and the result, an ad that
  imitates a control or a download button. Never, on any surface.
- **Dedicated to another's product or service** - a sponsored placement, a "recommended partner" banner, an
  affiliate pitch, a paid mention, a bundled offer. Never, on any surface. Linking the author's **own** products
  where it serves the reader is not advertising ([PROMOTION.md](PROMOTION.md) §4).
- **Inside an app: no ad network, no tracker or analytics SDK, no upsell, no paywall nag, no promo banner.** An
  in-app ad SDK is a tracker by construction, so the privacy promise rules it out even when it would be
  unobtrusive. Say "no ads" in the privacy page only if it is true
  ([SECURITY_AND_PRIVACY.md](SECURITY_AND_PRIVACY.md) §4).
- **One solicitation at most: a review request**, shown only after proven use (reference: 20 successful
  operations and 3 sessions), then silent for 90 days. It never blocks and never appears after an error.
- **Help routes to one channel, and only in a dead end** - the docs for a fixable setup, e-mail for a repeated
  failure. Never inside a toast, never after a success.
- **A product site tells what the product does in a few honest lines** - no water, no superlatives, no
  comparison with a competitor, edition limits stated plainly.
- **A general ad slot on a site is allowed when it is neither of the above** - a contextual network block
  (AdSense-style) placed beside the content, never in it, never above the job statement or the download. It
  is declared in the repo's stamp and capped (at most one slot per page), it is a network-surface row
  ([SECURITY_AND_PRIVACY.md](SECURITY_AND_PRIVACY.md) §7), and the site's privacy page says it is there. The
  default is none.

## 4. Voice: clear and friendly

Friendly, clear, brief. This is the one voice of the app, the site, the listing and the support page.

- **Light irony only against ourselves, never at the user,** never where data can be lost, and never in place
  of the next step. One level for every surface: dry and light. A joke is garnish on a message that already
  works.
- **A formula for each kind of message:**
  - *Toast*: one thought, one glance, no next step. "Moved."
  - *Error*: what happened plus **one** next step. A raw exception, class name or protocol status is never the
    headline; details sit in a secondary "Details".
  - *Empty*: the reason and an invitation. Never "No items found."
  - *Progress*: calm and specific. "Scanning the folder.."
  - *Success*: "Done." - not "The operation completed successfully."
  - *Destructive confirm*: what will happen and whether it can be undone. No jokes.
- **Banned:** bureaucratic phrasing ("an error has occurred", "please be advised"), unexplained jargon,
  emoji images, shouting capitals inside a sentence, "please" as padding, and any promise or hedge - "coming
  soon", "not yet available", "experimental", "beta", a greyed-out control tagged "soon". A feature the owner
  ordered has its control and its final strings, written as complete and working with no regard to its build
  state; a feature that was not ordered has neither
  ([DOCUMENTATION_CONCEPT.md](DOCUMENTATION_CONCEPT.md) §5 is the rule).
- **One name per concept**, with the forbidden synonyms listed, in a termbase the app, the docs and the site
  share. The same word names the same thing everywhere ([LOCALIZATION.md](LOCALIZATION.md) §5).
- **The text must fit the narrowest layout without truncation** - check it before merging the string.
- **House text style applies** (`..`, plain hyphen, `ё`): [DOCUMENTATION_CONCEPT.md](DOCUMENTATION_CONCEPT.md)
  §5 is its one home.

| Before | After | Why |
| --- | --- | --- |
| Server error. No response. | The server didn't answer. Try again in a moment. | what happened + one step |
| Error opening file: %1$s | Couldn't open "%1$s". It may be damaged or need another app. | no "Error:" prefix, no raw detail |
| Nothing here. We checked twice. | No files here yet. Add a folder or open another one. | an invitation, not only a joke |
| Delete %1$d file(s)? This cannot be undone. | This will delete %1$d files for good - there's no undo. | consequence, a plural resource |

## 5. One kit of elements

The same thing should look the same in every product. Reach for the kit; build a new element only when the
kit has none.

- **Colour comes from a named palette, day and night, and never from a literal.** The platform-neutral role
  names of `APP-STYLE` section 4 are the cross-platform vocabulary; a platform's own attributes (Material
  3 on Android, resource keys on Windows, custom properties on the web) map onto them. The state hues
  (ok, warning, error) and the category and source hues of `ICON-RENDER` are shared by every product.
  **Values default to the shared ones** - the shared accent, the shared neutrals; a product takes its own
  accent only where its identity requires it, and records why.
- **Contrast is measured, not claimed:** text 4.5:1, glyphs and other non-text 3:1, and a check fails the
  build under it. Dark and light both pass.
- **Icons: one meaning, one glyph, one name** (`ICON-SET`). Take the glyph from the vocabulary; never redraw
  it, never substitute an emoji, never pick a second glyph for a meaning that has one. A control that is only
  a glyph carries an accessible name containing the meaning's name.
- **A language is named in its own language, never by a flag** (`ICON-EXTERNAL`): "Русский", "Українська",
  "English". A flag denotes a country, not a language.
- **Buttons follow `BUTTONS` 2.0 or later on Windows, Android and the web.** This is mandatory, not an
  opt-in recommendation. Behavior types, visual ranks, glyphs, palette, shape, density, content-fit widths,
  grouping, stable order, wrapping, keyboard interaction and generated reference evidence have one home
  in that contract. It takes precedence over the earlier Windows button recommendation and conflicting
  platform button styling. Useful semantic glyphs are required; obvious answers may be text-only.
  Buttons in one visual row share the tallest member's height; widths follow content and known states.
  Permanent supported variants and temporary migration follow section 8.
- **Buttons support variable interface sizes** (`BUTTONS` section 8): compact through very large,
  with coherent shared geometry and vector scaling under `UI-SIZING`. Text-only accessibility enlargement
  need not enlarge icons proportionally; compact mode may reduce declared hit targets.
  Compact icon-only presentation follows command eligibility; large text and DPI never cause clipping,
  bitmap enlargement or container-width stretching. Baseline tokens are not fixed sizes or upper limits.
- **Boolean options follow `BOOLEAN-OPTION` 2.0 or later.** The compact checkbox, heading, explanation,
  conditional local help and platform-specific activation regions have one mandatory cross-platform
  contract. Checkbox, heading and glyph activate on every platform; recognized scrolling cancels taps.
  Obvious options may omit redundant explanations. Hover/focus help is short; activation opens full help.
- **Settings navigation follows `SETTINGS-NAVIGATION` 2.0 or later.** The compact page rail, one child
  level, consistent glyph policy, main-to-advanced order, final About page and stable fast content
  presentation are mandatory even for small settings surfaces. Every product owes the full About,
  official-resource and diagnostic-export set. Existing commit and safety semantics remain in force.
- **Destructive confirms:** the acting button is the red one; Escape is the one no-action way out; the safe
  answer holds the default focus. Button geometry and answer treatment follow `BUTTONS` sections 3 and 4.
- **Three channels for a message:** a toast for one glance, an inline state for an error with Retry or Undo,
  a dialog for a confirm or a long error. One dialog factory per product, not one per screen.
- **A thing the kit lacks is proposed to the catalog first,** then built: a missing role, a missing token.
  **A missing meaning is the exception** (`ICON-SET` section 15): the product draws it to the catalog's style,
  ships it and files the proposal in the same change, so a control never waits for an icon. Specify first,
  migrate opportunistically, and hold the line with a gate whose baseline only falls - never a rewrite
  campaign.

## 6. Reachable by everyone

- A visible keyboard focus on every interactive element; the pointer is never the only way in.
- Right-to-left by layout start and end, never by absolute left and right; media transport glyphs are never
  mirrored.
- Dark, light and follow-the-system, switching live.
- The locale set is declared once and its parity enforced ([LOCALIZATION.md](LOCALIZATION.md) §2); a
  missing translation falls back to the source language, never to a bare key.

## 7. Help: one key, one button, one answer per window

A user who does not know what a window is for, or in what order to use what is on it, asks the window - never
a search engine. The shape of the ask and of the answer is the shared contract `CONTEXT-HELP`; this section
holds the principles.

- **The ask is the same in every product.** F1 on a keyboard, and a `?` button (the `app.help` glyph) in the
  top-right corner of the window, doing the same thing. The button **adds** to the corner; it never replaces,
  covers or re-purposes a control already there - the close box, a search field and the rest keep their place.
  F1 is never taken for anything else, and never captured system-wide.
- **The answer is one of two, and the project decides per window which fits.** An explanation drawn over the
  live window, naming every significant element; or an HTML page for the window - a screenshot with numbered
  markers, the order to use the parts in and why, each element explained in full behind a click, and links
  across to the help of the neighbouring windows, the site's guides and a sibling product where the function
  is shared. Both speak in the user's language and in the voice of §4: what a thing does and why you would
  want it, never a restated label.
- **A help page is simple, and made from the kit.** Plain, readable, light and dark, working with no script
  and no network, shipped inside the product and published from the same files on the site. A screenshot is a
  render target: generated from the build in each language with demo content, regenerated in the same edit as
  the window it shows, never touched by hand.
- **A large number of windows, not all of them.** A one-question confirmation is its own help; a file picker
  is the system's. Everything else has an entry. The product keeps one **help map** of its windows and a gate
  that counts them against it, and a window with no help says why.
- **Help is not promotion.** No tracker, no remote font or script on a help page, no upsell inside it (§3).

## 8. Making it hold

- Approved permanent variants named by the shared UI contracts are recorded in the product's design
  or profile, without expiring exceptions. Missing mandatory behavior is temporary migration debt:
  maintain a dated plan with a deadline, referenced in that product's registry migration/exception row.
  A plan is not conformance. New or substantially reworked surfaces follow current rules immediately;
  existing surfaces are not permanently grandfathered. Never advance another product's implementation row.
- Validation uses a mandatory baseline scenario set plus risk-selected combinations with recorded
  coverage, not the full product of every locale, theme and scale on every edit. Runtime performance
  and reference screenshots come from real controls and measurements, never inferred from document checks.
- A principle nothing checks drifts. Each product names, in its agent-rules file, the gate that guards each
  rule that applies to it: literal colours and sizes, glyph names, locale parity, contrast, string
  boilerplate. A gate that counts a baseline may only lower it.
- A repository with a user interface says so in its stamp's profile, which is how `check-compliance.ps1`
  knows to look at it. What can be decided mechanically in an arbitrary repo - the house text style in string
  files, the banned boilerplate, a missing tone policy - the canon's check reports; the rest is the
  product's own gate.
- A per-form-factor pattern document (phone, tablet, watch, desktop window, web page) is the right place for
  numbers; it cites this page for the why and the catalog for the shapes.
