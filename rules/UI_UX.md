# UI & UX - one family: the same room, the same buttons, the same voice

How every product of the portfolio looks, behaves and speaks to its user - on Android, on Windows, on a web
page, in the kit. The aim is that a user who knows one product opens another and finds the same things in the
same places, said in the same way. Where products cannot be identical, they must at least look alike.

This page holds the **principles, the precedence and the tone**. The exact shapes - palette roles, glyph
vocabulary, window behaviour, page layout - are shared contracts in the catalog (`APP-STYLE`,
`APP-BEHAVIOUR`, `ICON-SET`, `ICON-RENDER`, `PAGE-STYLE`; see [CONTRACTS.md](CONTRACTS.md)) and are cited
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
  by role (title, subtitle, detail, badge). A value outside the set needs a decision, written down.
- **Touch target floor: 48 dp on touch platforms, 44 px with a pointer** (`ICON-RENDER` section 3.5).
- **Reflow, do not fork.** One layout parametrised by width; a second layout only where the *structure*
  differs, not the size.
- **No dead ends.** An empty state is a glyph, one sentence giving the reason, and an invitation to act. A
  loading state says what is loading. An error state offers Retry.

## 3. No advertising in the product

Less advertising is a product rule, not a preference.

- **No ads, no ad network, no tracker or analytics SDK, no upsell, no paywall nag, no promo banner inside an
  app.** Say so in the privacy page only if it is true ([SECURITY_AND_PRIVACY.md](SECURITY_AND_PRIVACY.md)
  §4).
- **One solicitation at most: a review request**, shown only after proven use (reference: 20 successful
  operations and 3 sessions), then silent for 90 days. It never blocks and never appears after an error.
- **Help routes to one channel, and only in a dead end** - the docs for a fixable setup, e-mail for a repeated
  failure. Never inside a toast, never after a success.
- **A product site tells what the product does in a few honest lines** - no water, no superlatives, no
  comparison with a competitor, edition limits stated plainly. A third-party ad network on a product site is
  an exception that must be declared in the repo's stamp and capped; the default is none.

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
  emoji images, shouting capitals inside a sentence, "please" as padding.
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
- **Buttons are chosen by role, not by look:** primary (at most one per surface), tonal, outlined, text,
  icon, destructive. The same role looks the same in every product.
- **Destructive confirms:** the acting button is the red one; Escape is the one no-action way out; the safe
  answer holds the default focus. On touch the confirm and cancel may differ in size, for the blind thumb.
- **Three channels for a message:** a toast for one glance, an inline state for an error with Retry or Undo,
  a dialog for a confirm or a long error. One dialog factory per product, not one per screen.
- **A thing the kit lacks is proposed to the catalog first,** then built: a missing meaning, a missing
  role, a missing token. Specify first, migrate opportunistically, and hold the line with a gate whose
  baseline only falls - never a rewrite campaign.

## 6. Reachable by everyone

- A visible keyboard focus on every interactive element; the pointer is never the only way in.
- Right-to-left by layout start and end, never by absolute left and right; media transport glyphs are never
  mirrored.
- Dark, light and follow-the-system, switching live.
- The locale set is declared once and its parity enforced ([LOCALIZATION.md](LOCALIZATION.md) §2); a
  missing translation falls back to the source language, never to a bare key.

## 7. Making it hold

- A principle nothing checks drifts. Each product names, in its agent-rules file, the gate that guards each
  rule that applies to it: literal colours and sizes, glyph names, locale parity, contrast, string
  boilerplate. A gate that counts a baseline may only lower it.
- A repository with a user interface says so in its stamp's profile, which is how `check-compliance.ps1`
  knows to look at it. What can be decided mechanically in an arbitrary repo - the house text style in string
  files, the banned boilerplate, a missing tone policy - the canon's check reports; the rest is the
  product's own gate.
- A per-form-factor pattern document (phone, tablet, watch, desktop window, web page) is the right place for
  numbers; it cites this page for the why and the catalog for the shapes.
