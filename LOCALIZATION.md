# Localization - which surfaces speak the user's language

The portfolio ships to real Russian-, Ukrainian-, and English-speaking users, so localization is a
first-class concern, not an afterthought. This doc says what gets translated and how strings are
managed without drift. Reconciled against the portfolio; per-project records in `contrib/`. Platform
specifics marked *(overlay)*.

## 1. What localizes, what stays English

- **Localize the user-facing surfaces**: the app UI, `README`/`README_<lang>`, the site pages, and the
  store/Play listing - to the audiences you actually have. `README_<lang>` is optional when the site and a
  localized docs page set already carry the translation; an EN-only README is fine then, not a gap.
- **Keep English (canonical technical ledgers)**: `CHANGELOG.md` (published verbatim as the release
  body and site "What's new"), `docs/contracts/CONTRACT_*.md`, code, and technical/tactical specs.
- Shipped locales for this portfolio: **EN, RU, UK.** Add a locale only when there are users for it -
  a half-translated surface reads worse than an honest English one.
- **Locale coverage is per surface, not one uniform set.** "EN/RU/UK" is the portfolio ceiling, not an
  obligation every surface must meet - a surface carries a locale only when there are users *for that
  surface*. It is fine and common for the website + README to ship EN/RU/UK while the app UI and store
  listing ship EN/RU only (reference: `StreamsPlayer` - UK on the site and README, EN+RU in the app and the
  Store listing). Do not treat a locale present on the site as a gap in the app; each surface's set is its
  own decision.

## 2. String management without drift

- **User-facing strings live in the platform's string resource, never hardcoded** in code or layouts.
  A hardcoded string can't be translated and leaks jargon.
- **One tool adds/edits a key across all locales with parity enforced** - a key must exist in every
  shipped locale or the build/audit fails *(Android reference: `set-android-string.ps1 add` writes the
  key across EN/RU/UK atomically; `check_strings_localized.ps1` fails on a missing translation)*.
- Edit strings byte-preservingly through the tool; hand-edit the resource only for the structural cases
  the tool doesn't own (plurals, arrays, comments, regrouping).
- After any string change, run the parity audit; a missing-locale exit is a fix-first, not a warning to
  defer.

## 3. Web localization *(overlay)*

- Every translated page carries `hreflang`, and each language uses **one consistent ISO 639-1 code across
  every surface** - the site toggle, the `README_<lang>` suffix, and the in-app UI (Ukrainian is `uk`
  everywhere, not `uk` in the app and `ua` in the README). One code per language, portfolio-wide (see
  [DOCUMENTATION_CONCEPT.md](DOCUMENTATION_CONCEPT.md) §3).
- The same fact has one authoritative source and is rendered per language - translations are render
  targets, not independent re-authorings that drift.
- Two page models are both valid: **separate per-language files** (`docs.html` / `docs.ru.html` /
  `docs.uk.html` - mirrored content, translated prose) or **in-page language blocks** in one file toggled
  client-side. Pick one per page; keep the toggle's ISO codes consistent site-wide either way, and edit all
  languages of a page in lockstep (see the ship-together surfaces manifest in DOCUMENTATION_CONCEPT §5).

## 4. Text style

The house text style (`..`, plain hyphen, `ё`; prose + UI only; fix stray violations in touched lines
only) has one home: [DOCUMENTATION_CONCEPT.md](DOCUMENTATION_CONCEPT.md) §5. It applies identically in
every language.

## 5. Tone across languages

The product compass ([AUTHOR.md](AUTHOR.md)) holds in every locale: task-first phrasing, zero jargon,
one voice across surfaces (the same feature has the same name in README, site, listing, and app), and
every user-facing failure states a human next step - translated, never a bare error code.

## 6. Applying to a new project

1. Decide the shipped locales (EN + the audiences you actually have).
2. Put every user-facing string in the resource; wire the parity-enforcing add/audit tool.
3. Keep CHANGELOG + contracts English; localize README/site/listing/UI.
4. Apply the text style to prose/UI; add `hreflang` + consistent ISO codes on the site.
