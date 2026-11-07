# Site audit conventions - what every lens shares

Read by every lens of the [site-audit](../SKILL.md) skill and by its workflow's verify and report stages. A lens
file says *what* to inspect; this file says how every lens measures, reports, defers to the canon and stays
harmless.

## 1. Read-only, always

- **The live site:** GET and HEAD only. No form submit, no login, no comment, no click that changes state, no
  online validator or search-console call made on the owner's behalf. JSON-LD is parsed locally.
- **Requests:** at most 8 at a time per host, a 25 s timeout, the audit's own User-Agent
  (`Mozilla/5.0 (compatible; sza-site-audit/1; read-only)`), and a cap on link checks (40 per page, 60 per sitemap).
- **The repository:** nothing changes except the run folder. A fix is proposed as a diff or a numbered plan inside
  the lens report and never applied - applying it is a ticket's work, through the project's own flow.
- **Never** `git add`, commit, push, tag, deploy, or start a release.

## 2. Where a run writes

`<repo>/temp/site-audit/<YYYY-MM-DD>/` - a second run on the same day gets `<YYYY-MM-DD>_2`. The folder is chosen
by `tools/site-audit/site-targets.ps1`, which **refuses a folder git would track**: on a site served from the
repository root every tracked file is published ([SITE_CONFIGURATION.md](../../../rules/SITE_CONFIGURATION.md)
§1), so a report in a tracked folder is one `git add -A` away from the public site. `temp/` is the one folder
every site repository ignores today; the refusal keeps that from being assumed.

A host with no repository on this machine is written under the portfolio repository, in
`temp/site-audit/<date>/external/<host>/`.

| File | Written by | What it holds |
| --- | --- | --- |
| `robot.json` | `robot-check.ps1` | the no-JavaScript crawl: per-page heads, headings, images, links, JSON-LD, language spans; site-wide robots, sitemap, `llms.txt`, 404, redirects |
| `ux_probe.json`, `shots/` | `ux-probe.js` | rendered measurements at 1366 px (light and dark) and on a 390 px phone, with screenshots |
| `<lens>.md` | each lens | the lens report (section 8); a lens whose write is refused returns the text instead |
| `verify.md` | verify stage | one verdict line per HIGH and MED finding |
| `report.md` | the main session, from the report stage's returned text | the merged site report (section 9) |
| `portfolio.md` | the main session, from the portfolio stage's returned text | the cross-site summary, in the portfolio repository's folder |

The harness refuses report files from subagents, so no agent writes `report.md` or `portfolio.md`, and no agent
puts "report" in the name of any file it writes; `tools/site-audit/save-reports.ps1` saves the returned text.

The run folder is disposable evidence. The **durable record of a finding is the product's ticket** - its
promotion campaign ticket ([PROMOTION.md](../../../rules/PROMOTION.md) §8), which cites the report by path and
date.

## 3. Evidence

- Every claim is a **quoted fragment** (under 15 words) or a **measured number with its unit**, and names its
  source: `robot.json`, `ux_probe.json`, a fresh `curl` (give the command), a screenshot file, or
  `<repo-relative path>:<line>`. Never an adjective, never an estimate.
- Use the collected evidence first; re-measure only what it lacks or what looks wrong.
- A transient result is reported with its count: "403 on 3 of 10 loads", never "fails".
- **Live against source.** When the repository is present, compare the live page with the file in the served
  root. A difference is itself a finding: an unpushed change, a build step that rewrites, or a stale deploy.
- What could not be measured goes under "Not measured" with the reason. It is never guessed and never omitted.
- Search-engine claims (`site:` queries, rankings) are **directional** and marked so; proof of indexing is the
  console ([PROMOTION.md](../../../rules/PROMOTION.md) §3 "Proof of indexing").

## 4. The finding line

```text
[SEV][page][area] what is wrong - evidence - concrete fix
```

- **SEV** - `HIGH` blocks indexing, or leaves a visitor at a dead end: they cannot tell what the product is,
  cannot get it, cannot reach its help, or read a false fact (version, price, platform, release status). `MED` is a
  measurable loss - a signal crawlers or scrapers misread, friction counted in clicks, screens, bytes or failures.
  `LOW` is hygiene. `INFO` is an observation or an owner decision, not a defect.
- **page** - the path relative to the base URL (`/`, `/docs/install.html`), `site` for site-wide, `repo` for a
  finding only the source shows.
- **area** - one word: `status` `redirect` `title` `description` `canonical` `robots` `hreflang` `lang` `og`
  `twitter` `jsonld` `heading` `image` `link` `download` `version` `sitemap` `robots.txt` `llms.txt` `404` `perf`
  `a11y` `layout` `content` `positioning` `docs` `consent` `third-party` `source`.
- **fix** - concrete, and names the repository file when the source is known. A fix the canon decides cites the
  section that decides it.

## 5. The canon is the law

Where a lens's advice and the canon differ, **the canon wins**, and the lens names the section that decided. The
rules a site audit meets most:

| Question | Canon answer | Home |
| --- | --- | --- |
| Which `robots.txt` counts | only the host root's; a project's own file is harmless and never the fix | [PROMOTION.md](../../../rules/PROMOTION.md) §3 |
| Sitemap | generated; canonical URLs answering 200 only; `lastmod` is the source file's commit date; no `priority`, no `changefreq` | [PROMOTION.md](../../../rules/PROMOTION.md) §3 |
| Languages | `hreflang` reciprocal, absolute, with `x-default`; a language only a script switches on one URL is invisible to search | [PROMOTION.md](../../../rules/PROMOTION.md) §3 |
| Structured data | truthful or absent: no invented `aggregateRating` or `review`; `FAQPage` and `HowTo` are never added for reach; `WebSite` only at a domain root (the hub); `softwareVersion` only when rendered from the release manifest | [PROMOTION.md](../../../rules/PROMOTION.md) §3 |
| `<meta name="keywords">` | ignored by Google; never added | [PROMOTION.md](../../../rules/PROMOTION.md) §3 |
| Page head | title under ~60 chars, description ~150, absolute canonical, Open Graph + Twitter card with a >=1200x630 image, one `h1` stating the job, `h2` per feature area, JSON-LD | [DOCUMENTATION_CONCEPT.md](../../../rules/DOCUMENTATION_CONCEPT.md) §3 |
| Pages a product site must have | landing, privacy, how-to, what's new, support | [DOCUMENTATION_CONCEPT.md](../../../rules/DOCUMENTATION_CONCEPT.md) §4 |
| Version, download link, checksum on a page | build-time facts rendered from the release manifest; never typed, never fetched only by the browser; a durable link stays as the fallback | [DOCUMENTATION_CONCEPT.md](../../../rules/DOCUMENTATION_CONCEPT.md) §4 |
| Release status in prose | a page states shipped facts; "coming soon", "in development", "not yet", "beta" are defects | [DOCUMENTATION_CONCEPT.md](../../../rules/DOCUMENTATION_CONCEPT.md) §5 |
| Served tree | every tracked file under a served root is public, internal notes included | [SITE_CONFIGURATION.md](../../../rules/SITE_CONFIGURATION.md) §1 |
| Social image | a committed asset on the site, referenced absolutely | [SITE_CONFIGURATION.md](../../../rules/SITE_CONFIGURATION.md) §5 |
| Touch targets, contrast | 48 for touch, 32 for pointer; text 4.5:1, non-text 3:1, dark and light both | [UI_UX.md](../../../rules/UI_UX.md) |
| Language switch | a language is named in its own language, never by a flag | [UI_UX.md](../../../rules/UI_UX.md) |

The canon is silent on AI crawlers and `llms.txt`: a lens reports what it finds as `INFO` and leaves the decision
to the owner, through the hub's ticket.

## 6. Already good

Up to 8 lines per lens, each a fact with its evidence. They exist so the next run notices a regression; a line
without evidence is not kept.

## 7. Changed since

Compare with the earlier run file the workflow names: a previous run's `report.md`, or a `baseline.md` - an
imported audit, of which only the rows for this host count. With none named, every finding is New. Match by
**(page, area, defect)**, never by wording, and list:

- **Fixed** - with today's evidence that it is gone.
- **Still open** - with today's evidence.
- **New** - not in the earlier run.
- **Not re-measured** - in the earlier run, outside this run's reach; never silently dropped.

## 8. The lens report

`<run folder>/<lens>.md`, in English:

```markdown
# <lens> - <base url> - <YYYY-MM-DD>

Target, repository, served root, evidence files used.

## Findings
<finding lines, most severe first>

## Already good
## Proposed patches        (lenses that propose: a diff against the repository file, or a numbered plan)
## Not measured
## Changed since           (only when a previous run or a baseline exists)
```

The structured result a lens returns to the workflow carries the same findings, one object per line, the
"already good" lines and the "not measured" lines.

## 9. The site report

`report.md`, composed by the workflow's report stage from the lens results and the verdicts and returned as text:

1. Header - base URL, date, repository and served root, the lenses that ran, and the verification count
   (confirmed / refuted / unverifiable).
2. **Findings** - merged across lenses: the same (page, area, defect) once, at the highest surviving severity, with
   the lenses that saw it in parentheses and the verdict after it (`confirmed`, `unverifiable`, or `not checked`
   for LOW and INFO). A refuted finding is never listed here.
3. **Three jobs** - from the UX lens: job | clicks or screens to complete | where it stalls.
4. **Already good** - merged, up to 10 lines.
5. **Changed since** - section 7.
6. **Refuted on verification** - each with the evidence that refuted it.
7. **Not measured** - merged.
8. **Appendix** - page | status | bytes | title (len) | description len | canonical | h1 | JSON-LD types, from
   `robot.json`.
