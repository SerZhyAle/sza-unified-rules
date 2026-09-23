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
  firewall allow for that one exe), taken once, visible to the user - never a background elevation. The
  portable form of this rule, and the inventory row such a feature owes, are §7.

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

## 7. The security posture inventory - what a product declares it can touch and send

§3-§5 say what to promise and how to keep the promise honest. This section says in what **form** the
promise is held, so that keeping it consistent is a check somebody runs rather than something the author
remembers. Two inventories, both mandatory, both part of the product's registered documentation
(DOCUMENTATION_CONCEPT §6).

1. **The permission inventory.** One row per declared permission: what is declared, **where** it is
   declared (which manifest, which build variant / edition / source set - a product whose variants differ
   has no single true list), **which features consume it**, the **one sentence of user-visible
   justification** (§3), and whether that sentence is actually shown at the moment the permission is
   requested. A permission whose consumer cannot be named is removed, not explained.
2. **Several consumers per permission is the normal case, not a defect.** The justification covers all of
   them honestly. Never narrow a manifest to make the inventory tidy: the narrowing breaks a consumer the
   row did not mention, and the correct repair is the wording of the disclosure (reference:
   `FastMediaSorter_mob_v2`, where splitting a location permission per flavor was reverted after it broke
   three independent consumers of it).
3. **The network-surface inventory.** One row per surface that opens a listening port, initiates an
   outbound connection, or hands a file outward, each answering the same four questions: **on by default or
   off**, **what turns it on**, **how long it lives**, and **what leaves, to where**. This inventory - not
   the privacy page's prose - is the material for the "no telemetry" claim and for answering a user asking
   what the product can send.
4. **Born off, dies with its session.** A new listening surface, or a feature needing elevation, ships
   disabled, is enabled by a deliberate user action, stops when the user-visible session that created it
   stops, and never advertises a local address as an external one. §3's desktop form is one instance of
   this; it applies to a phone's on-device server, a watch's transport and a browser extension's native
   host alike. A wire-level norm for one *protocol* belongs in the cross-project contract catalog
   (CONTRACTS.md), not here - this rule is about defaults, not framing.
5. **The three public forms are renders of the inventory, not three texts.** The hosted privacy page, the
   in-app justification strings, and the store-form source files (§5) all derive from these rows. Kept as
   three independently authored texts they diverge silently, and the divergence is found by a store
   rejection; as renders, divergence is a state a check can see.
6. **The consistency check blocks the submission, and it runs over the whole tree.** Place it in the
   pre-release sweep, not per change: its subject is the product as a whole, and a red pre-flight stops the
   ship (INVARIANTS 5). It compares the declared permissions against the inventory in both directions, the
   inventory's justifications against the strings actually shown, and the "no telemetry" claim against the
   **build's dependency set** - the claim is proven by what is linked in, never by the page saying so.
7. **Nothing to list is itself a declaration.** A product with no permissions and no network keeps both
   inventories, empty, each carrying the date it was last reconciled and one sentence saying why it is
   empty. An absent inventory is not compliance: an unstated claim never ages and can never be checked,
   and "no telemetry" is only a trust asset once stated (§4).
8. **A platform with no permission manifest still has rows.** Where the OS declares nothing, the row
   describes the *capability* the product takes - the directory it writes, the hook it installs, the device
   it opens - in the same five fields. The inventory is about what the product can do, not about what a
   manifest happens to name.

## 8. Applying to a new project

1. Confirm no secret is tracked; set the `.gitignore` globs (§1).
2. Reserve and record the signing/identity frozen anchors (§2).
3. List every permission with its one-sentence user-visible justification; drop the rest (§3).
4. Write the privacy page in plain language (§4-5); derive the store data-safety form from it.
5. Re-check permission-vs-behaviour traps on the target platform before shipping.
6. Confirm the age rating fits the app's content profile, not a copied portfolio id (§5).
7. If the app bundles third-party binaries, ship the `THIRD-PARTY-NOTICES.txt` in every package (§6).
8. Stand up both inventories - permissions and network surfaces - register them, and wire the consistency
   check into the pre-release sweep; an empty inventory with a date is the compliant answer for a product
   with nothing to list (§7).
