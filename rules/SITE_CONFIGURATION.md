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

## 2. Custom domain

- A `CNAME` file at repo root holds the custom domain (hub example: `sza.od.ua`). One domain per Pages
  site.
- **Durable URLs only** in buttons and cross-links: `/releases/latest`, the package id, the store
  product page - never a hard-coded version, so a page never goes stale between releases.
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
2. Add `CNAME` (or wire the redirect repo if it shares the apex), enable Pages from root.
3. Copy the `deploy.bat` shape; point `origin` at the new repo.
4. Add the SEO block + mandatory pages (DOCUMENTATION_CONCEPT §3-4) and build from the style-guide
   components.
