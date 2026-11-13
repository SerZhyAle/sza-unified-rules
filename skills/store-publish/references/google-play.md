# Google Play - the first public presence of an Android product

Reference for `store-publish` (Leg 4) and `release`. Recorded from `deviceinfo_mob` on 2026-11-13 (DeviceInfo for
Android and Wear OS, overlay B), where every step below ran for real on the owner's order; written so
StreamsPlayer_mob, Tourist_mob, filler_mob and any new overlay-B product repeat it from this page and not from a copy.
It covers what exists **before any bundle is uploaded**: the GitHub repository, the Pages site, the Play Console app with
every App content declaration, the store settings, the listing, the form factors, and the notices to the family.
Uploading a bundle, a track release and any "Send for review" are the release, not this page.

First re-run: `streamsplayer_mob`, 2026-11-13. Three corrections from it are folded in below (S0060): what `.gitignore`
hides, the tracked `PLAN/` and `docs/` prose, and a Pages site that answers before its landing exists.

Second re-run, the same product (S0061): the second Play app, the sign-in declaration, the content-rating branches for
third-party content, the target audience rule, the Data safety form, the deep links that work, the owner's decision per
app and the gates after the first commit are folded in below.

Third re-run, `tourist_mob`, 2026-11-13 (S0063): the history of a repository that already had commits, the images of the push set, a site with no privacy page, the ephemeral-processing answer, the activity category, the target audience before any rating, the queue robot during the push, the gates that run without the plugin, the plugin path, and the console details of the Wear OS step, the asset panel and the screenshots are folded in below.

Fourth re-run, `filler_mob`, 2026-11-13 (S0065): an earlier removed app of the same product on the account, an unborn branch, a product whose code is not ported yet, a console id bound before its build, the read-back of typed console values, a transient git lock, and the price words that the listing check flags are folded in below.

This file is read from the plugin cache, whose version folder changes with every deploy. Resolve the plugin root from `~/.claude/plugins/installed_plugins.json` (the `sza@sza-unified-rules` entry), never from a hard-coded version; the `spec-draft` skill's Step 0 does the same.

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
| A public GitHub repository and a Pages deploy | Outward-facing: the order must name them ("create the repository on GitHub on my behalf"). What becomes public is everything tracked - a tracked `PLAN/` and the prose of `docs/` included |

## Order, and why

1. **Decide in the repository first** (a ticket on the day, the S0008 shape in `deviceinfo_mob`): application id,
   license, remote name, channel, site pages, whether `PLAN/` is public. The id is the one that cannot be revised after
   step 4. The console may bind the decided id before the build carries it (section 0).
2. GitHub repository. 3. Pages site. 4. Play Console app. 5. Notices to the family. 6. Records.

Pages comes before the console because the console wants the privacy policy URL answering 200; the store contact website
and the repository homepage wait for the landing (section 2), so Pages may go live with the privacy pages alone. The
family notices come last because a notice names URLs that must already answer.

## 0. Preconditions in the repository

- Owner decisions recorded: application id, license, remote name, channel, site pages - and **whether `PLAN/` stays
  public or is ignored**. The canon default is ignored ([REPOSITORY_LAYOUT.md](../../../rules/REPOSITORY_LAYOUT.md) role
  map); a repository that tracked it while it had no remote (`streamsplayer_mob` had 192 files under `PLAN/` on
  2026-11-13) publishes every ticket with the first push. Ask the owner in the same batch as the other open inputs; the
  answer is not assumed from the tree.
- **The console may bind the decided id before the build carries it.** On the filler_mob run the build still carried a
  provisional id (`com.sza.filler.provisional`) under a release guard that refuses release packaging while the id ends
  in `.provisional`, and the console app was created with the decided id, which binds it. The build switch stays with the
  release ticket, because it lifts the guard and needs a build. The record names that ticket, and no bundle goes to the
  console under the provisional id.
- **The product's own publication tickets come first.** Read them before the first push. A product that already has
  publication tickets (GitHub, Play, family links) carries open owner inputs in them: what is public, the history shape,
  the support route, the AI line, the app access, the watch face, the audience, the graphics. Ask all of them in one
  batch, then push.
- **Count the Play apps.** A product with a second package id (a watch face, a companion app) is a second Play app: its
  own create-app form (the package name binds there), its own declarations, IARC questionnaire and Data safety form. Ask
  for the second app explicitly, as FastMediaSorter does; do not infer it from the tree.
- **A product whose code is not ported yet.** Its source manifest is the first input of the privacy page, the Data safety
  answers and the listing, but the order describes the finished product (invariant 17), while invariant 14 needs the page
  and the form to match what ships. On the filler_mob run the one empty activity had no permission and no INTERNET, while
  the upstream code the port carries uses a system folder picker with a persistable grant, an app-specific external files
  directory and StatFs, and has no service and no network. So audit the upstream source the port carries as well, and write
  into `docs/play/PLAY_DATA_SAFETY.md` the clause that a port adding a permission, a library, a service or a network call
  changes the page and the form in the same edit.
- `.gitignore` carries the signing leak globs (`*.jks`, `*.keystore`, `keystore.properties`, and the like),
  `local.properties`, `build/` and `temp/`. The canon's `*token*` and `*secret*` globs stay, with a narrow per-file
  negation for any product source they hide (step 1.2).
- `site/` holds the privacy pages in every shipped locale, and the rendered landing once it exists; the renderer has a
  byte-exact `-Check`. A product with no landing yet goes ahead with the privacy pages alone (section 2, step 5). A product
  with no privacy page at all needs the minimum of [SITE_CONFIGURATION.md](../../../rules/SITE_CONFIGURATION.md) section 6.
  The page text comes from a permission and network audit of the source manifest of every source set (variant removals
  with `tools:node="remove"` included) and of the network code. A merged manifest left in `build/` by an earlier build is
  stale - it lacks permissions added since - and is not the audit's source.
- `docs/play/PLAY_LISTING.md` (the texts per locale and the console fields) and `docs/play/PLAY_DATA_SAFETY.md` (Data
  safety, App content and IARC answers) are the single sources; the 512 icon and the 1024x500 feature graphic are render
  targets of the product's store-asset renderer.
- **Hold the queue before the first push.** A portfolio-queue robot may still write into the tree while the import is
  prepared: on the Tourist_mob run it created eight tickets during the run, and one of them failed the docs style gate
  minutes before the import commit. Check `pq` for the project and hold it (`pq hold <key>`, see the
  [portfolio-queue](../../portfolio-queue/SKILL.md) skill), or state in chat that the import takes whatever is on disk.
  Rerun the product's gates immediately before `git add -A`.

## 1. GitHub repository (about 5 minutes)

1. `gh auth status`, from the PowerShell tool on the reference machine - `gh` is not on the Git Bash PATH there. Clear
   a stale `GITHUB_TOKEN` first ([GITHUB_INTERACTION.md](../../../rules/GITHUB_INTERACTION.md) section 5). The `gh` token
   there has the scopes `repo, gist, read:org` and no `workflow`; pushing `.github/workflows/*` still worked because
   `git push` goes through Git Credential Manager (`credential.helper=manager`), whose token carries it. These are facts
   of that machine; another machine shows the same symptoms in the same places.
2. Scan what `git add -n .` would stage: no file over 300 KB, no private key, token or password pattern (a test fixture is
   the only expected hit), no `*.jks`, `*.keystore`, `*.p12`, `*.pem`, `*.apk` or `*.aab`; `gradle-wrapper.jar` is expected.
   Three more scans, each a finding when it hits:
   - **What `.gitignore` hides.** `git add -n .` cannot show an ignored file, so the clone that will exist after the push
     is checked from the other side: `git ls-files --others --ignored --exclude-standard --directory` lists the ignored
     files on disk (fully ignored directories collapse to one line). Read it for source, tests and fixtures. The leak
     globs `*token*` and `*secret*` hid `RoomSecretStore.kt`, `UiSizeTokens.kt` and its test on 2026-11-13, and the `*.p12`
     glob hid the self-signed test identity of a TLS test: a fresh clone would not have compiled. `check-compliance.ps1`
     names the first kind as `SZA-SEC05`; the fix is a narrow per-file negation with a why-comment, the glob stays
     ([REPOSITORY_LAYOUT.md](../../../rules/REPOSITORY_LAYOUT.md) "Secrets"). A test identity that is tracked on purpose
     raises `SZA-SEC01` until a dated exemption in `.sza-canon.json` says why.
   - **Prose that becomes public.** The scan covers the text of `PLAN/` (when it is tracked) and `docs/`, not only code: a
     private address can sit inside an owner quote in a ticket (one was found in a ticket of `streamsplayer_mob` and
     redacted before the push). `git grep --no-index --exclude-standard -I -n -o -E
     "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}" -- PLAN docs` lists every address in the push set, before the
     first commit and after it (drop `--no-index --exclude-standard` once tracked); then grep for the owner's own
     phone, street and machine paths, which only the owner can name. The commit author address is the owner's own git
     setting, the same in every public repository, and is not a finding.
   - **`PLAN/`.** If it is tracked, the owner's answer from step 0 decides: ignore it (`git rm -r --cached PLAN`, add it
     to `.gitignore`) or push it after the scan above.
   - **Images.** Look at every image in the push set, montaged to save turns: a capture can show what no text scan finds.
     On the Tourist_mob run an emulator's notification shade showed the emulator's signed-in Google account name, and a
     location capture was safe only because its ticket recorded a fixed `geo fix`. Record a disposition for each image.
   - **The history.** A push carries every commit, not only the tree: an address removed from a ticket stays in each
     commit that carried it. Before the first public push, list the commits with `git rev-list --all`, and the commits
     whose diff adds or removes a match with `git log --all --oneline -G "<pattern>"` (the pattern of the prose scan
     above). Where the history holds a match, redact it without touching the working tree, which may hold other sessions'
     edits and makes `git filter-branch` refuse: first `git bundle create <file outside the repository> --all`; then for
     each commit in order, `git read-tree` into a temporary `GIT_INDEX_FILE`, `git update-index --cacheinfo` with the
     redacted blob, `git write-tree`, and `git commit-tree` with the already rewritten parent (`-p`) and the original
     author and committer names, emails and dates (`GIT_AUTHOR_*` and `GIT_COMMITTER_*` from `git show -s --date=raw`);
     finally `git update-ref` with the old value. The gates of step 3 run again after the rewrite, as in step 7.
3. Fast gates green before the first commit: the landing `-Check`, the spec-catalog validator, the release-queue
   validator, and `check-compliance.ps1` (its parameter is `-RepoRoot`, not `-Root`).
4. Write the commit message to a file and run `git commit -F <file>`: a PowerShell here-string piped to `git commit -F -`
   arrives as a pathspec argument and fails. The co-author trailer goes in the message.
   - **Unborn branch.** A repository that `git init` created may have no commit yet and an unborn branch named `master`,
     while this runbook pushes `main`. Before the first commit, run `git branch --show-current`; if it names `master`, run
     `git symbolic-ref HEAD refs/heads/main` first. A rename after the push would have to move the remote's default branch
     as well. (filler_mob, 2026-11-13: the `.git` folder had no commit.)
   - **Transient index lock.** Right after `git add -A` on a Windows checkout, `git commit` can fail once with
     `Unable to create .git/index.lock: File exists`; a second later the lock was gone and the same commit succeeded
     (filler_mob, 2026-11-13). Look at the lock first: its age, and whether a git process is alive (`Get-Process git` in the
     PowerShell tool). Retry once. Never delete the lock blindly, because a live process may own it.
5. `gh repo create <owner>/<Name> --public --description "<category-first description>" --source . --remote origin`, then
   `git push -u origin main`. **`--homepage "https://<owner>.github.io/<Name>/"` only when the landing already answers
   200** (the Pages site root answers 404 until a landing exists, section 2); otherwise leave the homepage empty and set it
   later with `gh repo edit --homepage <url>`.
6. `gh repo edit --enable-wiki=false --enable-projects=false --add-topic <up to 20 topics>` ([PROMOTION.md](../../../rules/PROMOTION.md)
   on repository metadata). License detection (`gh api repos/<owner>/<repo>/license`) answers within a minute.
7. Run the step 3 gates again after the first commit. Until a commit exists, a gate that compares with HEAD reports
   COULD NOT VERIFY; the first commit turns it into a real check ([NEW_PROJECT_CHECKLIST.md](../../../rules/NEW_PROJECT_CHECKLIST.md)
   section 6).

## 2. GitHub Pages from `site/` (about 5 minutes)

1. Copy [templates/github-pages.yml](../../../templates/github-pages.yml) to `.github/workflows/pages.yml`: it triggers on a
   push to `main` that touches `site/**`, the site tooling or the workflow itself, plus `workflow_dispatch`; the `check`
   job runs the renderer's `-Check`, and the `deploy` job (`needs: check`) runs `configure-pages@v5`,
   `upload-pages-artifact@v3` (`path: site`) and `deploy-pages@v4`
   ([SITE_CONFIGURATION.md](../../../rules/SITE_CONFIGURATION.md) section 4).
   Any gate that the `check` job calls must run without the plugin, because the runner has none: the Tourist_mob docs
   gate is called with its `-NoHarness` switch. A gate that needs the installed plugin cannot run there, so give it a
   no-plugin switch and call that.
2. **Trap: `core.autocrlf` on the Windows runner.** It checks out with `core.autocrlf=true`, so LF render targets become
   CRLF and a byte-exact `-Check` fails in CI while it passes locally. The template's first step of the check job is
   `git config --global core.autocrlf false`, before `actions/checkout`.
3. Enable Pages with the workflow build type: `gh api -X POST repos/<owner>/<repo>/pages -f build_type=workflow`. The first
   push run may start before Pages exists; re-run it or push again.
4. Watch: `gh run watch <id> --exit-status`; on failure `gh run view <id> --log-failed`.
5. Verify every page and asset with `curl -s -o /dev/null -w "%{http_code} %{url_effective}\n" -L <url>`, then every external
   link the pages carry (extract each `href` and `src` from the live HTML). The one expected non-200 is the Play button,
   until the listing is published.
   **A site with no landing yet.** The root `https://<owner>.github.io/<Name>/` answers 404 while the pages beside it
   (`privacy.html` and its locales, `sitemap.xml`, `robots.txt`) answer 200 - measured for `streamsplayer_mob` on
   2026-11-13. That is a valid state: Pages goes live with the privacy pages alone, which is all the console needs. The
   repository homepage and the Play "website" field (step 3.4) stay **empty** until the root answers 200; the
   product's landing ticket sets both, and the hub card and the notices of section 5 wait for the same 200.

## 3. Play Console app (about 40 minutes in the owner's browser)

A personal developer account with the owner signed in; Claude in Chrome tools did the clicking on 2026-11-13. App pages
live under `/console/u/0/developers/<accountId>/app/<appId>/`. **Guessed paths redirect to Home** (`main-store-listing`,
`advanced-settings`, `app-content/finance-declaration`): navigate through the dashboard and the App content overview
(`app-content/overview`) and click "Start declaration" instead. These paths open their page when typed directly (the
2026-11-13 run): `app-content/privacy-policy`, `app-content/ads-declaration`, `app-content/testing-credentials`,
`app-content/target-audience-content`, `app-content/data-privacy-security`, `app-content/ad-id-declaration`,
`app-content/government-apps`, `app-content/finance`, `app-content/health`, `app-content/content-rating-overview`; and
`store-settings` and `advanced-distribution?tab=releaseTypes` (the form factors). The redirect note holds for every other
slug.

**Read every typed value back.** After typing into a console field, read the field's value before saving, not only the
character counters of a listing field. On the filler_mob run, select-all and typing over the contact email in the IARC
questionnaire left a stray character in it; only a triple-click, Delete and a retype fixed it. Read the value, not the count.

1. Search the account's app list for the name first, so there is no duplicate app. **An earlier app of the same product is
   a finding, not a duplicate to skip.** When the search finds an app with another package id that is removed or
   unpublished, open its Policy status before the create-app form and tell the owner what it says. The owner's earlier yes
   for the package name did not know it, so the one-way yes of step 2 is asked again with that fact in hand. A corrected new
   version is allowed; re-publishing the violation is not. The console shows only the generic policy line, so the original
   notice - in the owner's mailbox - is read before the first "Send for review" (section 4). Creating the draft app sends
   nothing for review. (filler_mob, 2026-11-13: an app of the same name from 2018, "Removed by Google", Policy status "Not
   adhering to Google Play Developer Program policies", rejected on 2018-06-07.)
2. **Create app.** App name (30 characters); the package name - the form asks for it at creation and has "Check
   availability" (ONE-WAY: the application id is bound to the account from this click); default language `en-US`; type
   App; Free (ONE-WAY); the declarations - Developer Program Policies and US export laws (ONE-WAY: ask). Google adds an
   automatic installer check, on by default; leave it. **Before this form**, read the planned title and short
   description for price and promotion words - "free", "best", "#1", "new" and the like - even when the word names a
   technical thing; step 5 has the flags that follow.
3. **App content**, each item saved separately ("Change saved. Send for review in Publishing overview"), from
   `PLAY_DATA_SAFETY.md`. Verify each claim against the product before declaring it - the manifests and dependencies, not
   memory.
   - Privacy policy URL: the hosted page, which must answer 200 first.
   - Sign in details (formerly App access): "No" when no part is restricted. An app with a server-side feature has a
     restricted part: the console requires the "full access" checkbox, and the review login is entered by the owner.
     Target audience and the Data safety submit stay locked until Sign in details is saved. The agent never types the
     review login or password, so this is an owner step that blocks three items at once: say so up front and do the
     other declarations first. The "Any other information" field takes 500 characters; leave room in it for the owner's
     server address.
   - Ads: No.
   - Target audience: the owner's choice for this app, asked per app and never carried over from another app's answer.
     A choice that differs from the owner's latest stated decision was refused by the auto-mode safety classifier until
     the owner answered it explicitly. Answer it after the content rating: when the ESRB rating is Teen or higher, the
     console disables the groups under 13. On a brand-new app, before any questionnaire, the page already disables those
     groups: the unrated default is Teen or higher. When the app wants them, file the content rating questionnaire first.
     Then a summary step, then Save.
   - Advertising ID: No - after checking that no `AD_ID`, ads, Firebase or analytics is in the manifests or dependencies.
   - Government apps: No.
   - Financial features: "My app doesn't provide any financial features" (bottom of the list), Next, Save.
   - Health apps: "My app does not have any health features" - after checking there is no `BODY_SENSORS` permission, no
     `ACTIVITY_RECOGNITION` permission and no step-counter sensor in the manifests and dependencies - Next, Save. Health is
     not only body sensors: a phone step counter (steps and cadence tiles) is "Activity and fitness". A ticked feature
     opens a second step, "Regional requirements" (nothing was required on the 2026-11-13 account), then Save.
   - Data safety: Overview Next, then "Does your app collect or share any of the required user data types?" No, Next; the
     preview reads "No data collection declared / No data shared with third parties"; Save. The Data safety form is one form per app, with no form-factor choice: the phone and Wear OS share it, so a source that says to fill each form
     factor separately is wrong. When data is declared, the per-type questions (collected or shared, ephemeral, optional,
     purposes) open from "Open <type> questions"; the Data types step is an accordion that shows only the open section's
     checkboxes. "My app does not allow users to create an account" then asks whether users log in with outside accounts
     and how accounts are created. Ephemeral processing does not change the store preview: declaring precise location and
     in-app search history as collected, not shared, processed ephemerally still shows "No data collection declared / No
     data shared with third parties", because Play does not show ephemerally processed data on the listing. The deletion
     question is optional, and its third answer is "No, but user data is automatically deleted within 90 days". A "not
     collected" answer must hold by construction: the FastMediaSorter answer rests on a tile-quantized coordinate, and a
     full-precision fix sent to a third-party API is declared as collected - the owner's rule is to declare strictly by
     the facts.
   - Content rating: Start questionnaire; the product contact email; category "All Other App Types"; the IARC terms of use
     checkbox (ONE-WAY: ask); downloaded content No, user content sharing No, online content No, age-restricted products
     No; then Miscellaneous - location sharing No, digital purchases No, cash rewards or NFT No, web browser or search
     engine No, news or educational No; Save (Next stays disabled until Save), Next, Summary (Everyone, L for all ages on a
     device-information utility), Save. **A fresh questionnaire per app, never a copied rating id**
     ([SECURITY_AND_PRIVACY.md](../../../rules/SECURITY_AND_PRIVACY.md) section 5). An app that plays
     third-party content does not get the utility answers. "Online content: Yes" opens the violence, sexuality, language
     and controlled-substance branches, and each has follow-ups that appear as you answer: click each question, because
     answering by radio index misfires. Check the catalog for adult content before answering: "pornographic: Yes" puts
     the app outside Play policy. Measured on 2026-11-13 for an app with 37 audio stations in an adult rubric and no
     pornographic video, the result for the "can provide access" answers was ESRB Teen with "Diverse Content: Discretion Advised", PEGI Parental guidance, USK 16, ClassInd 16 and IARC 12+, not Mature. Answer honestly.
   - The overview then reads "You're all caught up".
4. **Store settings.** App category (a dropdown, the option is near the end - Tools for a utility), Save; the store listing
   contact details: the product email and the **website - the product landing, not the repository**, Save; with no landing
   yet (section 2) the website field stays empty; its `https://` placeholder is not a value, so leave it as it is. External marketing is left on.
5. **Default store listing** (`store-listings/default/edit`, reached from the dashboard "Set up your store listing"):
   - Set the short and full description with `form_input` on the field refs; the counters confirm the value registered.
   - App icon: "Add assets" opens a side panel whose single hidden `input[type=file]` is not multiple - **upload one file
     per call**: the icon first, then click the feature graphic's "Add assets" and upload the 1024x500 file. The side panel stays open over the form until its own close is clicked.
   - **Price words.** The console's automated check does not read "Free space" as a technical term: on the filler_mob run the
     title "Filler: Fill Free Space" and the short description "Fill a storage's free space .." were flagged under App quality guidance
     ("app name: Should not use keywords that indicate price or promotion"; the short description guideline). The
     flags show only in the listing editor, not at create-app. After the first listing save, read the editor for "App quality
     guidance" lines; a save of a clean text makes them disappear, and the replacement wording is the owner's to choose, so
     ask it with the other open inputs.
   - "Save as draft" (Next belongs to the review step).
   - Languages: the language chip, Manage languages, search and tick each shipped locale (`ru-RU`, `uk` on the reference
     product), Apply; fill each language's name, short and full description, "Next language", Save as draft. Graphics fall
     back to the default language. One "Save as draft" saves every language at once. A translated listing inherits the default
     language's screenshots, and the first edit copies them into that language (on the Tourist_mob run, 10 / 8 in `ru-RU`
     and `uk`, which blocked every save). Removing them returns the language to inheritance; uploading the language's own
     files then replaces the inherited set. Give localized captures distinct file names (`ru_01_<name>.png`,
     `uk_01_<name>.png`), because the panel identifies thumbnails by file name.
   - Phone screenshots (2 to 8, 16:9 or 9:16, 320 to 3840 px) are required to finish the listing and come from a real
     device check; the dashboard stays at 10 of 11 setup tasks until then. The screenshot panel's file input accepts several files, but they
     land in upload-completion order, not in the order given: drag the thumbnails in the section to reorder (a left-click
     drag works), or upload one file per call.
6. **Wear OS.** Test and release, the form factor chip, Manage form factors (Advanced settings, the Form factors tab), "Add
   form factor", Wear OS. The console then lists three steps: Wear OS screenshots for every listing, a Wear bundle on a
   testing track, and the opt-in to the Wear OS review policy (ONE-WAY: ask). The third step stays locked until the first two are done, so a
   pre-upload run never reaches it. Android XR shows as Active by Google's default;
   leave it - never shrink reach ([PLATFORM_OVERLAYS.md](../../../rules/PLATFORM_OVERLAYS.md) Overlay B). The asset side panel stays bound
   to the section it was opened for: a click on a collapsed section's hidden "Add assets" does not rebind it. Expand the
   section and click its visible "Add assets" first, or the Wear OS screenshots land in Phone screenshots ("10 / 8, Too many images", and the save fails).

## 4. Not part of this run

The upload keystore, the release bundles, the app signing key import at the first upload, any track release and any "Send
for review" - the release, with its pre-flight and its update-over-a-prior-install proof. Where section 3, step 1 found an earlier removed
app of the same product, the release reads that app's original notice first and checks the new listing against it before the
first "Send for review": a corrected new version is allowed, re-publishing the violation is not. The account-level "Declare your
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
