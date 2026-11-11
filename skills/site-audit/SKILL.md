---
name: site-audit
description: Audit a published product site, or every site of the portfolio, the way a crawler without JavaScript and a first-time visitor meet it - read-only lenses for indexing (robots, sitemap, canonical, hreflang), the visitor's path on a laptop and a phone, release facts on the page, structured data and social cards, languages, and the help pages - every serious finding re-measured before it is reported, and the run compared with the previous one. Also the gate before pushing site changes (prepublish). Use on /site-audit, when asked to audit, check or review a site or its SEO, to see what a robot or a visitor sees, why a site is not found, or before publishing a site; or on the Russian phrasings - "аудит сайта", "проверь сайт", "проверь все сайты", "SEO аудит", "как робот видит сайт", "глазами посетителя", "почему сайт не находится", "проверка сайта перед публикацией".
---

# Site audit - what a robot and a visitor meet on a published site

The skill runs one workflow, [site-audit.workflow.js](site-audit.workflow.js), over the sites it resolves: per site,
two tools collect the mechanical evidence, six read-only lenses judge it, a skeptic re-measures every HIGH and MED
finding and drops what does not reproduce, and a report stage merges the rest and compares it with the previous run.
Several sites add a portfolio summary. The lenses share one contract, [conventions](references/conventions.md); the
canon decides wherever a lens and the canon differ ([SITE_CONFIGURATION.md](../../rules/SITE_CONFIGURATION.md) §7).

**Read-only, always.** GET and HEAD against the live site; nothing in a repository changes except its git-ignored
run folder, `temp/site-audit/<date>/`. A proposed fix stays a diff inside a report - applying it is a ticket's work.

| Lens | The question it answers | Proposes a patch |
| --- | --- | --- |
| [robot](references/robot.md) | What does a crawler without JavaScript see, and is it indexable? | no |
| [ux](references/ux.md) | What does a first-time visitor meet on a laptop and a phone, and where does the path stall? | no |
| [release-facts](references/release-facts.md) | Are version, download link and checksum build-time facts, or a browser call to `api.github.com`? | yes |
| [structured-data](references/structured-data.md) | Is the JSON-LD truthful and complete, and do the social cards render? | yes |
| [i18n](references/i18n.md) | Does every language have its own URL with reciprocal `hreflang`, or hide in one DOM? | yes |
| [docs](references/docs.md) | Do the help pages exist on the site, in a predictable shape, each with its own title and description? | yes |
| [prepublish](references/prepublish.md) | May these site changes be pushed? PASS / FAIL per line, from the source tree | no |

## Usage

```text
/site-audit                          the site of the current repository
/site-audit <key>|<path>             one registered project (a key from pq list) or a repository path
/site-audit --all [--url <url>..]    every registered project whose stamp declares a site, plus hosts with no repository
/site-audit --lens robot,i18n        a subset of the six audit lenses
/site-audit prepublish [<key>|<path>] the gate before a push: source only, blockers first
```

## Step 0 - Resolve the plugin root

```powershell
$sza = if ($env:CLAUDE_PLUGIN_ROOT) { $env:CLAUDE_PLUGIN_ROOT } else {
    ((Get-Content "$HOME/.claude/plugins/installed_plugins.json" -Raw | ConvertFrom-Json).plugins.'sza@sza-unified-rules' |
        Sort-Object lastUpdated -Descending | Select-Object -First 1).installPath
}
"$sza"
```

`CLAUDE_PLUGIN_ROOT` is not exported into a tool shell. **Print the resolved path and paste it literally** into the
commands below.

## Step 1 - Resolve the targets

```powershell
pwsh -NoProfile -File "<root>/tools/site-audit/site-targets.ps1" [-Repo <path> | -All] [-Url <url>,<url>] [-Lens <l>,<l>] [-Mode prepublish] [-Baseline <file>] -OutFile "<scratchpad>/site-audit-args.json"
```

A key from `pq list` resolves to its path first (`pwsh -NoProfile -File "<root>/tools/harness/portfolio/pq.ps1" list`).
The script reads each repository's `.sza-canon.json` `site` block, derives the base URL (the `CNAME` in the served
root, else `https://<owner>.github.io/<repo>/` from the origin remote), picks a fresh run folder and the previous run,
and **refuses a run folder git would track** - on a site served from the repository root, every tracked file is
published ([SITE_CONFIGURATION.md](../../rules/SITE_CONFIGURATION.md) §1). It creates nothing.

| Exit | Meaning | What to do |
| --- | --- | --- |
| 0 | targets resolved; refused ones, if any, are printed on stderr | Step 2, and name the refused ones in the report |
| 2 | bad invocation, no site block in the stamp, or an unreadable registry | quote the message; a repository with `site.kind` `none` has no site to audit |
| 3 | every target was refused | quote the reasons; adding `temp/` to a repository's `.gitignore` is the owner's call |

Then say in one line what will run: the sites, the lenses, the run folder, and the agent count - per site one
collector, one agent per lens, one skeptic and one reporter, plus one for a portfolio summary when there are several
sites (`--all` over the portfolio is several dozen agents).

## Step 2 - Run the workflow

Call the **Workflow** tool with `scriptPath` = `<root>/skills/site-audit/site-audit.workflow.js` and `args` = the
content of the JSON file from Step 1, passed as an object, not as a string. The owner invoking this skill is the
opt-in to that orchestration. Wait for the completion notice; do not poll.

Then save the reports. The harness refuses report files from subagents, so the report and portfolio stages return
their Markdown and this session writes it - into the git-ignored run folders only:

```powershell
pwsh -NoProfile -File "$sza/tools/site-audit/save-reports.ps1" -Output "<the output file the completion notice names>"
```

Exit 0 saved, 3 something refused (a path git would track or outside a run folder; the line names it), 2 the file is
no site-audit result. An existing file is kept; `-Force` replaces it.

Without a Workflow tool (another agent, an older harness), run the same stages yourself, site by site, in the
workflow's order and with the prompts it builds: collect, each lens, verify, report, then the portfolio summary.

The workflow needs PowerShell 7, network access, and for the UX lens Node with Playwright and Chromium.
`ux-probe.js` finds an installed Playwright on its own (`SZA_PLAYWRIGHT` names one explicitly); without one the UX
lens judges what the source shows and lists every rendered claim under "Not measured". Exit 4 means no page view
was measured; the JSON is saved after every visit, so a cut run still leaves what it measured.

## Step 3 - Report to the owner, in Russian

Read every `report.md` saved in Step 2, and `portfolio.md` when there is one. Per site: the HIGH and MED counts,
the top findings in plain words, what is fixed since the previous run, how many findings the skeptic refuted, and what
was not measured. Give the paths of the reports. Never call a finding fixed that this run did not re-measure, and say
plainly when a lens or a site produced nothing.

## Step 4 - Carry the findings, only when the owner asks

A finding lives in the product's **promotion campaign ticket** ([PROMOTION.md](../../rules/PROMOTION.md) §8) - one
campaign per product, found and extended through the [promote](../promote/SKILL.md) skill's Step 1, never a second
ticket beside it. The hub's ticket carries the portfolio items (the host-root `robots.txt`, the console property, a
host with no repository) and **every finding shared across products** (a portfolio-wide convention, shared map, or
policy choice that is not about one product alone): ask a shared question **once** in the hub's portfolio promotion
ticket, and have every affected product ticket cite that hub ticket (`Blocker: <hubKey>:<id>` when blocked on the
decision) rather than duplicating the question across N product tickets (S0042). Write the findings as acceptance
criteria that cite the report by path and date. An audit finding is never captured as a fresh Draft on the agent's
own initiative ([spec-draft](../spec-draft/SKILL.md) "What this skill never does").

## Prepublish

`/site-audit prepublish` runs only the [prepublish](references/prepublish.md) lens, over the source tree in the
served root: no evidence is collected and no skeptic runs, because each line is a mechanical PASS or FAIL. Any FAIL
in the blocker block means "do not push"; report the blockers first, then the warnings, then the command to re-run.

## What this skill never does

- Change a site file, apply a patch, commit, push, deploy, tag or release.
- Submit a form, log in, or call an online validator or a search console on the owner's behalf.
- Write a report into a folder git would track, or anywhere but the run folder.
- Claim a ranking or an indexing state as fact: search results are directional, the console is the proof
  ([PROMOTION.md](../../rules/PROMOTION.md) §3 "Proof of indexing").
