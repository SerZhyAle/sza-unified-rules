# Security & Privacy - secrets, permissions, and the promise to the user

Two things this covers: keeping credentials out of the repo, and being honest and minimal about what
the product touches on the user's machine. Both are cross-cutting and both are checked at every store
submission. Reconciled against the portfolio; per-project records in `contrib/`. Platform specifics
marked *(overlay)*.

## 1. Secrets never in the repo

The policy and the per-secret table have one home: [REPOSITORY_LAYOUT.md](REPOSITORY_LAYOUT.md)
"Secrets". In short: no secret is ever committed; tokens are ambient to the runner and read at call
time; signing material lives outside the repo or the store re-signs; `.gitignore` pre-empts the common
leak globs; a real build secret goes in the CI secrets store, referenced by name.

## 2. Signing & identity *(overlay)*

- The signing key / certificate and the identity fields are **frozen anchors**: the winget / installer
  (Inno `AppId` **or** WiX MSI `UpgradeCode`) / MSIX identity (desktop), the `applicationId` + Play
  upload/signing key (Android), the installer product id (Wails), the **Chrome item id + Edge product id**
  (browser extension - distinct per store). Reserve once;
  changing them orphans every installed copy. For an extension, never pin a private `key` in the manifest to
  force an id, and keep the CRX/CWS signing key (`cws-key*.json`, `*.pem`) git-ignored, never committed.
- Publisher-constant, non-secret values (publisher CN / display name) live in the build-script
  defaults, passed as parameters, never hardcoded as credentials. **A shared age-rating (IARC) id is *not*
  automatically one of them** - it is reusable across products only when their content-exposure profile
  matches; an app that exposes uncurated third-party content needs its own questionnaire (see §5).
- Per-keystore hashes matter: a re-signed build can need its own registered hash *(Android reference:
  each signing config declares its browser-tab/redirect hash in the manifest and the auth provider)*.

## 3. Minimal permissions, each justified

- **Declare only what the runtime actually uses.** An unused permission cuts market reach, spooks
  reviewers, and invites rejection.
- **Every permission maps to a user-visible feature** you can name in one plain sentence. If you can't,
  remove it.
- Watch platform traps where declaring a permission *changes behaviour* *(Android reference: declaring
  `CAMERA` breaks permission-free `ACTION_IMAGE_CAPTURE`; foreground-service types and `mediaProjection`
  must match real use or Play rejects)*.
- Runtime permission requests are asked in context, with a plain reason, at the moment the feature needs
  them - never a wall of prompts at launch.
- **A feature that opens a listening network port or needs elevation ships OFF, enabled only by an
  explicit, gated, auditable opt-in** - never silently at install or first run. This is the single
  sanctioned exception to "the product needs no firewall/elevation to work" (reference:
  `FastMediaSorter_Lite`'s folder-share server). Gate the *entire* surface (UI + the process that binds the
  port) behind one enablement check that is true only when the user deliberately turned it on - an
  elevated-installer machine marker file, a deferred per-user flag set after **one** scoped UAC prompt, or
  a packaged manifest capability. The privileged step is the narrowest possible (a program-scoped inbound
  firewall allow for that one exe), taken once, visible to the user - never a background elevation.

## 4. Data handling & the privacy promise

- **Local-first, and say so.** State what stays on the device, what leaves it, and why - in plain
  language, in the listing and in the app.
- **"No telemetry" only if true**, and then say it loudly - it is a trust asset. If anything phones
  home, name it and let the user opt out where the platform requires.
- **User data belongs to the user**: app-level credentials/keys live in the OS secret store at runtime,
  not in the build, not in plain files.
- Network calls are named and bounded; nothing silently uploads user content.

## 5. Store declarations (one source, many forms)

- **Privacy page is mandatory** and hosted (`docs/privacy.html` or the site) - the Store and Play both
  require the URL. It is the single source; the store's structured privacy/data-safety form is filled
  *from* it, not authored independently. **Carve-out**: a zero-data-collection local tool with no site may
  instead use the store's own data declaration + listing copy + in-app text as the source (no hosted page);
  the promise must still be stated in the listing and the app (see DOCUMENTATION_CONCEPT §4). **The carve-out
  is for a *zero-data* tool only:** a **local-but-sensitive** tool (a keyboard hook, clipboard, screen capture)
  hosts the page even with no network/telemetry - the sensitive access is exactly what the reviewer and the
  user want explained (reference: `CyrFlip`).
- Keep the privacy statement, the permission list, and the data-safety form mutually consistent - a
  mismatch is a common review rejection.
- The privacy page is plain-language: what we access, why, whether it leaves the device, and a contact
  email.
- **Age rating (IARC) is per content-profile, not per publisher.** A shared portfolio rating id transfers
  only between apps that answer the questionnaire the same way. An app that can open **arbitrary
  third-party / uncurated content** (a stream player, a web view, a file opener that fetches remote media)
  must complete a **fresh IARC questionnaire** - the uncurated-content answers differ, and copying a curated
  app's rating ships the wrong rating. Answer honestly (no accounts / purchases / ads / user-to-user
  publishing where true; uncontrolled third-party content where true).
- **A store may add extra review for a whole app category.** Apps that open third-party streams draw
  infringing-content scrutiny; pre-empt it - frame the listing by the legitimate job (a curated
  internet-radio / live-stream *catalog* player, not a piracy tool), drop the most trigger-prone keyword
  (e.g. `IPTV player`), and paste the capability/full-trust justification verbatim. A **global keyboard hook +
  clipboard read reads as a keylogger** and draws the same scrutiny; pre-empt it with the `runFullTrust`
  justification and a plain "does not log keystrokes, no network, no data" description (reference: `CyrFlip`).

## 6. Bundled third-party binaries and their licenses

- **Redistributing native libraries pulls in their license, and it can be stronger than your own.** An
  MIT/BSD-licensed app that bundles **LGPL/GPL** native components (media codecs, decoders, a bundled
  player runtime) ships under the **combined** obligation - if any bundled plugin is GPL, the redistributed
  whole is governed by the GPL. Carry a `THIRD-PARTY-NOTICES.txt` (component, license, upstream source URL,
  the full license text or a link) in **every** distributed package - the release ZIP *and* the store
  package - and never strip it from the packaging. Reference: `StreamsPlayer` bundling LibVLC/VLC
  (LGPL + GPL plugins) under an MIT app.

## 7. Applying to a new project

1. Confirm no secret is tracked; set the `.gitignore` globs (§1).
2. Reserve and record the signing/identity frozen anchors (§2).
3. List every permission with its one-sentence user-visible justification; drop the rest (§3).
4. Write the privacy page in plain language (§4-5); derive the store data-safety form from it.
5. Re-check permission-vs-behaviour traps on the target platform before shipping.
6. Confirm the age rating fits the app's content profile, not a copied portfolio id (§5).
7. If the app bundles third-party binaries, ship the `THIRD-PARTY-NOTICES.txt` in every package (§6).
