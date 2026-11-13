# Site Configuration - hosting, domains, and deploy mechanics

How every SZA web property is hosted, named, and published. This is the *plumbing*; two neighbours own
the other layers and are not duplicated here:

- **Visual + content style** - `kit/SZA-WEB-STYLE-GUIDE.md` + `kit/sza-kit.css` (the Pine+Gold system,
  component order, site taxonomy by role). Any new page follows that kit.
- **SEO + mandatory pages** - [DOCUMENTATION_CONCEPT.md](DOCUMENTATION_CONCEPT.md) §3-4.

This file is only: where a site lives, how its domain resolves, and how a change goes live.

## 1. Hosting model

- **GitHub Pages, served from the repo root or `/docs`.** The live site is the root `index.html` + root
  `assets/`, **or** a `docs/`-served static site when Pages is set to the `/docs` source. A `docs/` tree is
  the live site or an unpublished staging copy depending on that setting - check which source Pages uses,
  never assume root and `docs/` HTML are meant to match.
- **One repo per property.** The hub (`sza.od.ua`), each app's marketing page, and each docs site
  (e.g. `universal-agent-kit`) are separate repos with their own Pages. The site taxonomy (which role a
  given property plays) is in the web style guide.
- **`.nojekyll`** at the served root (repo root, or `docs/.nojekyll` when serving from `/docs`) when the
  site is hand-authored HTML, so Pages serves files verbatim without Jekyll processing.
- **Every tracked file under the served root is public.** For a site served from the repository root that is
  the whole repository: a prompt, a spec, an audit report or a ticket workspace committed there is published
  and indexed - on 2026-11-03 the hub repository's `kit/prompts/*.md` outranked the hub itself for a product
  query. Internal material stays in a git-ignored folder ([REPOSITORY_LAYOUT.md](REPOSITORY_LAYOUT.md), the
  role map's rows marked **no**) or outside the served root, and a deploy that stages everything is only as
  safe as the `.gitignore` under it.

## 2. Custom domain

- A `CNAME` file at repo root holds the custom domain (hub example: `sza.od.ua`). One domain per Pages
  site.
- **Durable URLs** in cross-links, and as the fallback of every download button: `/releases/latest`, the
  package id, the store product page. A versioned link and the version beside it are rendered from the release
  manifest by the release flow, never hand-typed and never left to a browser-side API call
  ([DOCUMENTATION_CONCEPT.md](DOCUMENTATION_CONCEPT.md) §4).
- Cross-property links use the public domain, not a relative path into a sibling repo.

## 3. Redirects & bridges

- **Root/apex redirect repo pattern.** A dedicated redirect (e.g. `github-root-redirect/`, and the
  sibling `SerZhyAle.github.io` user-site) forwards a bare GitHub-Pages origin or apex to the canonical
  custom domain. Keep the redirect target pointed at the canonical URL so link equity and analytics
  don't split.
- **Google Sites bridge.** Where a property is authored in Google Sites and mirrored to the repo
  (`google-sites-publish/`, `embed.html`), the repo copy is the *published render* - edit the source,
  re-publish, then commit the export. Do not hand-edit the exported mirror in place.

## 4. Deploy flow

The reusable one-command publish (hub reference: `deploy.bat`):

1. **Clear an invalid `GITHUB_TOKEN`** from the environment first, so `git`'s credential helper /
   keyring auth wins instead of a stale token. This is the single most common cause of a failing push
   on these machines.
2. Ensure `git` is initialised and the `origin` remote points at the property's repo
   (`https://github.com/<user>/<repo>.git`), branch `main`.
3. Stage everything, commit with a dated auto-message (overridable by an argument), push to `main`.
4. Pages rebuilds on push; the custom domain updates within a minute.

**Live means built by the Pages workflow.** Content committed to a branch that the workflow does not build is
not live: verify the live URL after the trunk merge, never before. And a `paths-ignore` that spares docs from
CI also spares them from the only gate before Pages publishes - make the deploy job wait for the CI run of
the same SHA and require it green, or say plainly in the rules file that it does not, and run the doc and
site checks in the local build and the release pre-flight.

**A byte-exact render check on a Windows runner needs `core.autocrlf` off.** A `windows-latest` runner defaults to
`core.autocrlf=true` and rewrites LF-committed render targets to CRLF on checkout, so a `-Check` that compares the
committed bytes fails in CI while it passes locally. Run `git config --global core.autocrlf false` as a step **before**
`actions/checkout` in the check job (reference: `deviceinfo_mob`'s `pages.yml`, [its record](contrib/deviceinfo_mob.md)).

**The Pages workflow has a template.** [templates/github-pages.yml](../templates/github-pages.yml) is the workflow of a
repository whose `site/` Pages serves: it triggers on a push to `main` touching `site/**`, the site tooling or itself, a
`check` job on `windows-latest` runs the byte-exact render check (with the `core.autocrlf` step first), and a `deploy`
job on `ubuntu-latest` waits for it (`needs: check`) and publishes `site/` through `configure-pages`,
`upload-pages-artifact` and `deploy-pages`. Enable Pages once with the workflow build type
(`gh api -X POST repos/<owner>/<repo>/pages -f build_type=workflow`); the first push run may start before Pages exists, so
re-run it. The order of a new Android product's repository, site and console app is in the
[Google Play reference](../skills/store-publish/references/google-play.md).

Keep this script per-repo and identical in shape across properties, so "how do I publish?" has one
answer everywhere. For a *release* (versioned artifact) rather than a *site update*, use the project's
release flow instead - see [GITHUB_INTERACTION.md](GITHUB_INTERACTION.md) §4.

## 5. Assets & weight

- Favicons + touch icons + `site.webmanifest` at root, generated once from a single master and reused;
  don't hand-diverge sizes.
- Share/OG preview image (>=1200x630) is a real committed asset, referenced absolutely in the OG tags.
- No heavy JS library unless it earns its weight; system-font fallback; the page must render and be
  keyboard-navigable without waiting on the network (per the web style guide's performance principles).

## 6. Applying to a new site

1. New repo, root `index.html`, `assets/sza-kit.css` from the kit, `.nojekyll`.
2. Add `CNAME` (or wire the redirect repo if it shares the apex), enable Pages from root - or, for a `site/` folder
   built by a check, copy the workflow template (§4) and enable the workflow build type.
3. Copy the `deploy.bat` shape; point `origin` at the new repo.
4. Add the SEO block + mandatory pages (DOCUMENTATION_CONCEPT §3-4) and build from the style-guide
   components.
5. Run the [site-audit](../skills/site-audit/SKILL.md) skill against the live URL after the first publish (§7).

## 7. Auditing a live site

The [site-audit](../skills/site-audit/SKILL.md) skill measures a published site as a crawler without
JavaScript and a first-time visitor meet it, through read-only lenses - robot, UX, release facts, structured
data, languages, docs - re-measures every serious finding before it reports it, and compares the run with the
previous one. Its `prepublish` lens is the gate before a push to the branch Pages builds from. A run writes only
to the git-ignored `temp/site-audit/` (§1); the findings that matter go into the product's promotion ticket
([PROMOTION.md](PROMOTION.md) §8).
