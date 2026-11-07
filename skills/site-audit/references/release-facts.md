# release-facts lens - are version, download link and checksum build-time facts, or a browser call to `api.github.com`?

Checks the release facts a page states - version, download link, size, checksum, date - for being true today and
rendered from the release manifest at build time, as
[DOCUMENTATION_CONCEPT.md](../../../rules/DOCUMENTATION_CONCEPT.md) §4 "Release facts on a page are build-time facts"
requires, and its release-status prose against §5 "Published text is a shipped fact"; it proposes the render step
where they fail. Evidence, the finding line and the report follow [conventions](conventions.md) sections 3, 4 and 8.

## Inputs

- **`robot.json`**, per page: `versions` (version-like strings in the no-JS visible text, the first 8), `textNoJs`
  (its first 400 chars), `links.downloads` (`href`, `status`, `finalUrl`, `versioned`), `apiGithub`, `scripts[]`,
  `statusPhrases`, and `jsonld[]` - the `softwareApplication.has` flags and, in `raw`, the values of
  `softwareVersion`, `downloadUrl` and `installUrl`; a block cut at 3000 chars is re-read from a fresh GET of the
  page.
- **`ux_probe.json`**, per page and mode (`pages.<key>.desktop`, `.mobile`, and `.desktop-dark` on the first page):
  `probe.versionsInText`, `probe.firstCta`, `failed`, `consoleErrs`, and for a mode whose call failed its `shot`, a
  file in the screenshots folder the workflow names; top level, `apiGithubLoads` - each `api.github.com` call of the
  first page's loads and reloads, with its `load`, `mode` and `status`.
- **Missing evidence.** With `robot.json` missing, GET the stamp's pages (else the landing, the download page and
  "What's new") for their no-JS facts. With `ux_probe.json` missing, check 1 rests on the script and its failure
  branch, and the rendered values, the 403 count and the screenshots go under "Not measured".
- **The release record, at its public address**
  ([RELEASE_AND_DISTRIBUTION.md](../../../rules/RELEASE_AND_DISTRIBUTION.md) §6), for the `<owner>/<repo>` of the
  download links, else of `git -C <repo> remote get-url origin`. Every `curl` here carries
  `-A "Mozilla/5.0 (compatible; sza-site-audit/1; read-only)" --max-time 25` (conventions section 1).
  - The newest release per edition and per flavor (RELEASE_AND_DISTRIBUTION §5): editions and tag prefixes from the
    stamp's `editions` and `versionShape.editionTagPrefixes`, flavors from the asset names (`-standard-`, `-vr-`,
    `-wear-`). List the releases once with `gh api "repos/<owner>/<repo>/releases?per_page=100"` (authenticated, so
    it spends no per-IP quota), else page through `https://github.com/<owner>/<repo>/releases`; cross-check
    `git -C <repo> tag -l`, and prove each chosen release at its public tag page.
    `curl -sI https://github.com/<owner>/<repo>/releases/latest` names the release GitHub marks latest; a `location`
    ending in `/releases` means no release.
  - The tag page, `https://github.com/<owner>/<repo>/releases/tag/<tag>`, gives the date;
    `https://github.com/<owner>/<repo>/releases/expanded_assets/<tag>` lists the assets with their `sha256:`
    digests, the checksum to compare where a release ships no `.sha256` file (Android APKs).
  - `curl -sIL <asset url>` for status and size (the final `content-length`, not the redirect's 0), a ranged GET
    (`-r 0-0`, the total in `content-range`) where HEAD is refused, and `curl -sL <asset url>.sha256` for each
    checksum the page shows.
  - Each store or package link by HEAD, and by a ranged GET (`-r 0-0`) when HEAD answers 403 or 405
    (`apps.microsoft.com` refuses HEAD): the GET's status after redirects decides.
    `winget show --id <id> --exact --source winget` where winget exists; the channel's row in `RELEASE_STATE.md`
    where the repository keeps one.
- **The repository**, when there is one; with none, the `scripts[].src` files are read by GET.
  - The stamp, `.sza-canon.json`: `channels`, `editions`, `versionShape.tagRegex` and
    `versionShape.editionTagPrefixes`.
  - `git -C <repo> grep -n -E` over the served root for `api\.github\.com`, `raw\.githubusercontent\.com`,
    `releases/(latest|download)`, `fetch\(`, `XMLHttpRequest` and `softwareVersion`: per hit, the element it
    fills, its static fallback, and what the failure branch (`catch`, `!res.ok`) writes there.
  - The writer of each release fact: the release script, workflow step or site generator that renders it from the
    manifest (search `.github/`, `tools/`, `scripts/`), or none - typed by hand. How the file last changed:
    `git -C <repo> log -3 --format="%h %cs %s" -- <file>`.
  - The ledger and the "What's new" source, in the shape
    [DOCUMENTATION_CONCEPT.md](../../../rules/DOCUMENTATION_CONCEPT.md) §2 names. A local tag is a cross-check
    only; the public release page wins.
- **Budget**: at most 30 requests of its own, inside the caps of conventions section 1. No unauthenticated request
  to `api.github.com` - it spends the 60-an-hour quota of this machine's IP, which the collect stage's page loads
  share, and would skew the 403 count check 1 reports - and never a reload to provoke a 403.

## Inspect

Every page in `robot.json`, plus "What's new" and the download page by GET when it lacks them. Severity is
conventions section 4; the area is in parentheses. A site whose pages carry no download control and whose served
tree holds no archive or installer (`.zip`, `.exe`, `.msi`, `.apk`, `.msix`) - the hub today - runs checks 1, 3 and
6, and check 2 on any product version a card shows; kind `portfolio` alone exempts nothing (`universal-agent-kit`
is `portfolio` and ships `universal-agent-kit.zip`). A host with no repository (kind `external`) skips the
repository steps and says so under "Not measured".

1. **Runtime-only facts** (`version`, `download`). A version, link, size or checksum in the rendered page
   (`ux_probe.json` `probe.versionsInText`, `probe.firstCta.href`) but absent from the no-JS page (`robot.json`
   `versions`, `links.downloads`), or written by a script with `apiGithub` above 0. Evidence: the script line, the
   no-JS value, and "403 on N of M loads" from `apiGithubLoads`. MED - a crawler makes no call, so the indexed page
   carries no version (DOCUMENTATION_CONCEPT §4). HIGH when the no-JS page has no download `href` at all: a failed
   call leaves the visitor nothing to click. A call that only refines a rendered value is not a finding.
2. **The version shown is the latest release** (`version`). Every version the no-JS page presents as the product's
   current one (`versions`: hero, badge, download block, footer), against the newest release of its edition, or of
   the flavor whose asset it names - the tag without its edition prefix and leading `v`. Where the stamp's
   `versionShape.tagRegex` takes a shape `versions` cannot match (a separator-less `v2610211540`), a fresh GET of the
   page is searched with that pattern, anchors dropped and the `v` optional. Older: HIGH, a false version fact. None
   shown while a release exists: MED. A version-like string the page presents as the version and no tag matches:
   HIGH; one it does not present so (a build date-time, debug text) is the docs lens's check 9, no finding here. An
   unrendered placeholder - `<version>` (`&lt;version&gt;` in the source), `{{`, `${`, and their translations
   (`<версия>`, `<версія>`) - in `textNoJs`, a fresh GET or the served root's HTML outside scripts: MED, HIGH inside
   the download `href`. A release-notes entry that links its own version is not stale.
3. **Rendered or typed** (page `repo`, area `source`). Each fact that checks 2, 4 and 5 find correct today: when no
   code writes it from the manifest, LOW - it goes stale at the next release (DOCUMENTATION_CONCEPT §1 and §4,
   [INVARIANTS.md](../../../rules/INVARIANTS.md) 16). A live page whose release facts differ from its served-root
   file is a finding (conventions section 3), LOW, naming the cause - an unpushed change, a branch Pages does not
   build ([SITE_CONFIGURATION.md](../../../rules/SITE_CONFIGURATION.md) §4), or a stale deploy; a stale version on
   the live side is check 2's. A difference the release flow's own render explains is INFO, naming the render step.
4. **Download controls** (`download`). Every control in `links.downloads` and `firstCta`, and every store or package
   badge: its status after redirects, versioned or durable, and the facts printed beside it.
   - None on the landing or the download page while a release exists, or one answering 4xx or 5xx: HIGH - the
     visitor cannot get the product; with no release at all, Propose item 6.
   - A badge for a channel the product is not on - its public page answers 404 or does not name the product, or the
     channel is absent from the stamp's `channels` or `n/a` in `RELEASE_STATE.md` (wherever the repository keeps
     it, e.g. `DEV/RELEASE_STATE.md`) while no public page shows it: HIGH
     ([DOCUMENTATION_CONCEPT.md](../../../rules/DOCUMENTATION_CONCEPT.md) §5 bans it). `pending`, `submitted` and
     `blocked` describe the current release, not the listing (RELEASE_AND_DISTRIBUTION §6); with a live public
     page, that channel's version is check 2's question.
   - A versioned link to an asset of a release other than the newest one that carries that edition's or flavor's
     asset: as check 2.
   - A versioned link with no durable fallback beside it - `/releases/latest`, the package id, the store page
     ([SITE_CONFIGURATION.md](../../../rules/SITE_CONFIGURATION.md) §2): LOW.
   - A checksum unlike the release's `.sha256`, or its `expanded_assets` digest where it ships none: HIGH. A size
     unlike the asset's (the final `content-length` of a HEAD, or the total in `content-range` of a ranged GET):
     MED. A date more than one day off the release date read in the version's own clock (the date a `YY.MMDD.HHmm`
     tag encodes, else the tag page's `datetime`; for a file in the served root,
     `git log -1 --format=%cs -- <file>`): MED. None of the three: LOW.
   - An asset name without its version, or a binary committed into the served tree instead of a release asset: MED
     ([RELEASE_AND_DISTRIBUTION.md](../../../rules/RELEASE_AND_DISTRIBUTION.md) §5).
5. **JSON-LD `softwareVersion`** (`jsonld`). Different from the visible version or the newest release of its
   edition: MED, a value scrapers repeat. Correct, but not rendered from the manifest the visible version comes
   from: LOW (PROMOTION §3). Absent is no finding here; the structured-data lens owns completeness, and a pinned or
   failing `downloadUrl` or `installUrl` (its check 3).
6. **Release status in prose** (`content`). `statusPhrases` first, then the served pages, scripts, i18n strings and
   `data-*` labels searched, in every locale, for (a) the lists in DOCUMENTATION_CONCEPT §5 "Published text is a
   shipped fact" - the readiness hedges and the wordless forms such as a disabled control tagged "soon" included -
   and (b) present-tense claims about the release record - "no published", "no release", "build from source",
   "нет опубликованных", "немає опублікованих" and the like, in either word order - each compared with the release
   record. A claim the release record contradicts ("no published package" beside a live release): HIGH, a false
   release status. Any other hit of (a): MED ([INVARIANTS.md](../../../rules/INVARIANTS.md) 17). Not findings: the
   name of a store track the owner runs, a dated deprecation notice, an app state string, a limitation stated in
   the present tense.
7. **"What's new"** (`docs`). Its newest entry against the newest release of its edition: older is MED. Not linked
   from the landing: MED. A missing page, an undated entry and an `[Unreleased]` group are the docs lens's (its
   checks 1 and 4).

## Propose

Only for a repository on this machine: a diff against each named file, or a numbered plan when it would pass about
200 lines - never applied (conventions section 1). The patch holds what the findings call for:

1. **The render step**, in the file that cuts the release (its script or workflow): it writes the release manifest -
   version, date, per-asset URL, size, SHA-256 - and renders from it, on every release, the visible version, the
   download block and the JSON-LD `softwareVersion` of each page that shows them
   ([DOCUMENTATION_CONCEPT.md](../../../rules/DOCUMENTATION_CONCEPT.md) §4). It leaves the sitemap `lastmod` alone:
   that stays the source file's commit date ([PROMOTION.md](../../../rules/PROMOTION.md) §3).
2. **Its timing**, "generate, commit, then tag"
   ([RELEASE_AND_DISTRIBUTION.md](../../../rules/RELEASE_AND_DISTRIBUTION.md) §4): what is known before the tag is
   rendered and committed before it; a size or checksum known only after the publish is rendered by the deploy the
   release triggers, with nothing committed after the one-way step, or left off the page.
3. **The download block**: one line per asset the release carries (installer, MSI, portable ZIP), each with its own
   rendered URL, size and SHA-256 - `Download <name> <version> (<size>) - <date> - SHA-256 <hash>` - and beside the
   block the durable fallback - `/releases/latest`, the package id, the store page (SITE_CONFIGURATION §2); the
   JSON-LD `downloadUrl` takes the durable link.
4. **The runtime call**, where one stays: it refines a rendered value and on failure leaves it as it was; the static
   markup is complete without it.
5. **The prose**: each banned line rewritten as a present-tense fact, or removed (DOCUMENTATION_CONCEPT §5); an
   ordered part that no package carries is named as the catalog's `SITE-REPRESENTATION` rule 4a says.
6. **No release at all**: the plan's step is "the owner cuts a release through the project's release flow", and the
   page then links that release's asset; the patch never tags ([INVARIANTS.md](../../../rules/INVARIANTS.md) 4).
7. **A manifest another repository reads** (the hub showing product versions) is a shared format: the plan starts in
   the catalog, where `UPDATE-MANIFEST` rule 2 already carries these fields, and never invents a per-site shape
   ([CONTRACTS.md](../../../rules/CONTRACTS.md) §1).
8. **Acceptance checks**, for the ticket that applies the patch, at the public address (RELEASE_AND_DISTRIBUTION
   §6): `curl -s <page url>` carries, with no JavaScript, the newest release's version of each edition and flavor
   (its tag without the `v`) and that release's asset `href`; JSON-LD `softwareVersion` equals that version; each
   versioned asset answers 200 after redirects and its checksum equals `curl -sL <asset url>.sha256` (or, where the
   release ships none, its `expanded_assets` digest); every durable fallback (`/releases/latest`, the package id,
   the store page) resolves; no script the download control needs calls `api.github.com`.

## Output

On top of the conventions section 8 report:

- `## Release facts`, after "Findings": one row per page, edition and fact (version, link, size, checksum, date,
  status line) - page | edition | fact | no-JS | rendered | JSON-LD | release record | written by
  (`<file>:<line>`, `typed`, or `runtime: <host>`). Each finding's evidence carries its own command and both
  measured values (the no-JS value and the release record's), because the skeptic receives only the finding line;
  the table serves the reader and the report stage, and the structured result carries no extra field.
- "Proposed patches": the Propose items in their order, each diff fenced as `diff` under the repository path it
  changes, then the acceptance checks.

## Canon differences

Changes from the prompt-pack source `site-release-facts.md`, each with the section that forced it:

- **Provoking the failure is dropped** - no reload until 403. A crawler makes no call, so the defect is a fact with no
  rendered source, shown by the no-JS page and the script (DOCUMENTATION_CONCEPT §4); the failure branch is read.
- **A matching version can still be a finding**: typed by hand is a defect (DOCUMENTATION_CONCEPT §1 and §4,
  INVARIANTS 16), and the comparison reads the public release page, not a local tag (RELEASE_AND_DISTRIBUTION §6),
  per edition and per flavor rather than one `releases/latest` (RELEASE_AND_DISTRIBUTION §5).
- **`softwareVersion` follows PROMOTION §3**: present only when rendered from the manifest of the visible page, so
  its absence is no defect, and "equals the tag" became "equals the visible version, both rendered, and the visible
  version equals the release's tag".
- **`releases/latest` is not a weaker download** but the durable fallback every versioned link keeps
  (DOCUMENTATION_CONCEPT §4, SITE_CONFIGURATION §2) and the JSON-LD `downloadUrl` (PROMOTION §3); a badge for a
  channel the product is not on is added as a defect (DOCUMENTATION_CONCEPT §5).
- **Release-status prose is a defect by its wording** (MED), and HIGH when the release record contradicts it
  (DOCUMENTATION_CONCEPT §5, INVARIANTS 17).
- **The render belongs to the release flow**, from the release manifest on every release, not a Pages job querying
  `releases/latest`; it leaves the sitemap `lastmod` alone (PROMOTION §3) and keeps RELEASE_AND_DISTRIBUTION §4 timing.
- **The site-root `release.json` "for the hub"** became a catalog step: a format another repository reads is a
  contract (CONTRACTS.md §1), so `UPDATE-MANIFEST` is cited instead of a new shape.
- **"Tag releases"** for a project with none became the owner's release through the project's flow (INVARIANTS 4),
  the binary a release asset, never a file committed into the served tree (RELEASE_AND_DISTRIBUTION §5).
