# Google Play - the first public presence of an Android product

Reference for `store-publish` (Leg 4) and `release`. Recorded from `deviceinfo_mob` on 2026-11-13 (DeviceInfo for
Android and Wear OS, overlay B), where every step below ran for real on the owner's order; written so
StreamsPlayer_mob, Tourist_mob, filler_mob and any new overlay-B product repeat it from this page and not from a copy.
It covers what exists **before any bundle is uploaded**: the GitHub repository, the Pages site, the Play Console app with
every App content declaration, the store settings, the listing, the form factors, and the notices to the family.
Uploading a bundle, a track release and any "Send for review" are the release, not this page.

## The one-way steps

Each binds a frozen anchor, accepts terms or publishes something. **Each needs the owner's explicit yes in chat at that
moment, even when the order covers the whole run** - an order that says "set it all up" is not the yes for a legal
declaration.

| Step | Why it cannot be undone |
| --- | --- |
| The package name in the Play create-app form | The application id is bound to the account from that click - a frozen anchor earlier than the first upload |
| Pricing "Free" | A published free app can never become paid |
| The Developer Program Policies and US export laws declarations | Legal declarations |
| The IARC terms of use in the content rating questionnaire | Accepted terms |
| The Wear OS review policy opt-in | A policy agreement |
| A public GitHub repository and a Pages deploy | Outward-facing: the order must name them ("create the repository on GitHub on my behalf") |

## Order, and why

1. **Decide in the repository first** (a ticket on the day, the S0008 shape in `deviceinfo_mob`): application id,
   license, remote name, channel, site pages. The id is the one that cannot be revised after step 4.
2. GitHub repository. 3. Pages site. 4. Play Console app. 5. Notices to the family. 6. Records.

Pages comes before the console because the console wants the privacy policy URL answering 200 and the store contact
website; the family notices come last because a notice names URLs that must already answer.

## 0. Preconditions in the repository

- Owner decisions recorded: application id, license, remote name, channel, site pages.
- `.gitignore` carries the signing leak globs (`*.jks`, `*.keystore`, `keystore.properties`, and the like),
  `local.properties`, `build/` and `temp/`.
- `site/` holds the privacy pages in every shipped locale and the rendered landing; the renderer has a byte-exact
  `-Check`.
- `docs/play/PLAY_LISTING.md` (the texts per locale and the console fields) and `docs/play/PLAY_DATA_SAFETY.md` (Data
  safety, App content and IARC answers) are the single sources; the 512 icon and the 1024x500 feature graphic are render
  targets of the product's store-asset renderer.

## 1. GitHub repository (about 5 minutes)

1. `gh auth status`, from the PowerShell tool on the reference machine - `gh` is not on the Git Bash PATH there. Clear
   a stale `GITHUB_TOKEN` first ([GITHUB_INTERACTION.md](../../../rules/GITHUB_INTERACTION.md) section 5). The `gh` token
   there has the scopes `repo, gist, read:org` and no `workflow`; pushing `.github/workflows/*` still worked because
   `git push` goes through Git Credential Manager (`credential.helper=manager`), whose token carries it. These are facts
   of that machine; another machine shows the same symptoms in the same places.
2. Scan what `git add -n .` would stage: no file over 300 KB, no private key, token or password pattern (a test fixture is
   the only expected hit), no `*.jks`, `*.keystore`, `*.p12`, `*.pem`, `*.apk` or `*.aab`; `gradle-wrapper.jar` is expected.
3. Fast gates green before the first commit: the landing `-Check`, the spec-catalog validator, the release-queue
   validator, and `check-compliance.ps1` (its parameter is `-RepoRoot`, not `-Root`).
4. Write the commit message to a file and run `git commit -F <file>`: a PowerShell here-string piped to `git commit -F -`
   arrives as a pathspec argument and fails. The co-author trailer goes in the message.
5. `gh repo create <owner>/<Name> --public --description "<category-first description>" --homepage
   "https://<owner>.github.io/<Name>/" --source . --remote origin`, then `git push -u origin main`.
6. `gh repo edit --enable-wiki=false --enable-projects=false --add-topic <up to 20 topics>` ([PROMOTION.md](../../../rules/PROMOTION.md)
   on repository metadata). License detection (`gh api repos/<owner>/<repo>/license`) answers within a minute.

## 2. GitHub Pages from `site/` (about 5 minutes)

1. Copy [templates/github-pages.yml](../../../templates/github-pages.yml) to `.github/workflows/pages.yml`: it triggers on a
   push to `main` that touches `site/**`, the site tooling or the workflow itself, plus `workflow_dispatch`; the `check`
   job runs the renderer's `-Check`, and the `deploy` job (`needs: check`) runs `configure-pages@v5`,
   `upload-pages-artifact@v3` (`path: site`) and `deploy-pages@v4`
   ([SITE_CONFIGURATION.md](../../../rules/SITE_CONFIGURATION.md) section 4).
2. **Trap: `core.autocrlf` on the Windows runner.** It checks out with `core.autocrlf=true`, so LF render targets become
   CRLF and a byte-exact `-Check` fails in CI while it passes locally. The template's first step of the check job is
   `git config --global core.autocrlf false`, before `actions/checkout`.
3. Enable Pages with the workflow build type: `gh api -X POST repos/<owner>/<repo>/pages -f build_type=workflow`. The first
   push run may start before Pages exists; re-run it or push again.
4. Watch: `gh run watch <id> --exit-status`; on failure `gh run view <id> --log-failed`.
5. Verify every page and asset with `curl -s -o /dev/null -w "%{http_code} %{url_effective}\n" -L <url>`, then every external
   link the pages carry (extract each `href` and `src` from the live HTML). The one expected non-200 is the Play button,
   until the listing is published.

## 3. Play Console app (about 40 minutes in the owner's browser)

A personal developer account with the owner signed in; Claude in Chrome tools did the clicking on 2026-11-13. App pages
live under `/console/u/0/developers/<accountId>/app/<appId>/`. **Guessed paths redirect to Home** (`main-store-listing`,
`advanced-settings`, `app-content/finance-declaration`): navigate through the dashboard and the App content overview
(`app-content/overview`) and click "Start declaration" instead.

1. Search the account's app list for the name first, so there is no duplicate app.
2. **Create app.** App name (30 characters); the package name - the form asks for it at creation and has "Check
   availability" (ONE-WAY: the application id is bound to the account from this click); default language `en-US`; type
   App; Free (ONE-WAY); the declarations - Developer Program Policies and US export laws (ONE-WAY: ask). Google adds an
   automatic installer check, on by default; leave it.
3. **App content**, each item saved separately ("Change saved. Send for review in Publishing overview"), from
   `PLAY_DATA_SAFETY.md`. Verify each claim against the product before declaring it - the manifests and dependencies, not
   memory.
   - Privacy policy URL: the hosted page, which must answer 200 first.
   - Sign in details (formerly App access): "No" when no part is restricted.
   - Ads: No.
   - Target audience: 18 and over only (a summary step, then Save).
   - Advertising ID: No - after checking that no `AD_ID`, ads, Firebase or analytics is in the manifests or dependencies.
   - Government apps: No.
   - Financial features: "My app doesn't provide any financial features" (bottom of the list), Next, Save.
   - Health apps: "My app does not have any health features" - after checking there is no `BODY_SENSORS` or health
     permission - Next, Save.
   - Data safety: Overview Next, then "Does your app collect or share any of the required user data types?" No, Next; the
     preview reads "No data collection declared / No data shared with third parties"; Save.
   - Content rating: Start questionnaire; the product contact email; category "All Other App Types"; the IARC terms of use
     checkbox (ONE-WAY: ask); downloaded content No, user content sharing No, online content No, age-restricted products
     No; then Miscellaneous - location sharing No, digital purchases No, cash rewards or NFT No, web browser or search
     engine No, news or educational No; Save (Next stays disabled until Save), Next, Summary (Everyone, L for all ages on a
     device-information utility), Save. **A fresh questionnaire per app, never a copied rating id**
     ([SECURITY_AND_PRIVACY.md](../../../rules/SECURITY_AND_PRIVACY.md) section 5). An app that opens third-party or
     uncurated content answers differently; answer honestly.
   - The overview then reads "You're all caught up".
4. **Store settings.** App category (a dropdown, the option is near the end - Tools for a utility), Save; the store listing
   contact details: the product email and the **website - the product landing, not the repository**, Save. External
   marketing is left on.
5. **Default store listing** (`store-listings/default/edit`, reached from the dashboard "Set up your store listing"):
   - Set the short and full description with `form_input` on the field refs; the counters confirm the value registered.
   - App icon: "Add assets" opens a side panel whose single hidden `input[type=file]` is not multiple - **upload one file
     per call**: the icon first, then click the feature graphic's "Add assets" and upload the 1024x500 file.
   - "Save as draft" (Next belongs to the review step).
   - Languages: the language chip, Manage languages, search and tick each shipped locale (`ru-RU`, `uk` on the reference
     product), Apply; fill each language's name, short and full description, "Next language", Save as draft. Graphics fall
     back to the default language.
   - Phone screenshots (2 to 8, 16:9 or 9:16, 320 to 3840 px) are required to finish the listing and come from a real
     device check; the dashboard stays at 10 of 11 setup tasks until then.
6. **Wear OS.** Test and release, the form factor chip, Manage form factors (Advanced settings, the Form factors tab), "Add
   form factor", Wear OS. The console then lists three steps: Wear OS screenshots for every listing, a Wear bundle on a
   testing track, and the opt-in to the Wear OS review policy (ONE-WAY: ask). Android XR shows as Active by Google's default;
   leave it - never shrink reach ([PLATFORM_OVERLAYS.md](../../../rules/PLATFORM_OVERLAYS.md) Overlay B).

## 4. Not part of this run

The upload keystore, the release bundles, the app signing key import at the first upload, any track release and any "Send
for review" - the release, with its pre-flight and its update-over-a-prior-install proof. The account-level "Declare your
trader status" banner (due February 2027 on the reference account) belongs to the owner, not to a product. The console
shows setup finished only after the screenshots exist.

## 5. Notices to the family (about 10 minutes)

1. **Canon:** one `spec-draft` ticket refreshing `rules/contrib/<repo>.md` and the product's channel-matrix row.
2. **Hub** (the SITE-FAMILY-MAP owner): the new row and a hub card - entered only after the product's URL answers
   (rule 5 of that contract) and, by the owner's word, after the Play listing is published; the card links the landing
   first, then the listing.
3. **Every product in the map's consumers line:** one ticket to add the new tool to its footer grid from its own source
   (dictionary, footer template, generator) - no body cross-link (rule 4 of that contract).
4. **`spec-draft.ps1` refuses (exit 2) a project that has a profile and no `PLAN/TICKET_TEMPLATE.md`** - the hub and
   OneClickRunner did on 2026-11-13. The half-set-up guard is deliberate; the way through is the owner's: either the
   scaffold (`init-task-flow`, which also renders launchers and queue files there), or write the ticket by hand as
   `PLAN/<next id>_<slug>.md` from the canon template, which the portfolio queue sync registers (TASK-FLOW rule 65 - a ticket
   file written to `PLAN/` with no ledger row is registered by the sync, where the profile says so). A project with no
   profile at all is not refused: it gets a plain capture.

## 6. Records in the product repository

`CLAUDE.md` (the remote, Pages and the console app as dated facts), `docs/RELEASE.md` (the owner steps: what is done and
what remains), `docs/play/PLAY_LISTING.md` (website = the landing) and the release ticket's DO list.
