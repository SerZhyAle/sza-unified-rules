---
name: promote
description: 'Plan free product promotion, positioning, SEO, indexing (robots.txt, sitemap, Search Console, Bing, IndexNow), directories, 4PDA threads and launch. Use to advertise or get a product found. «реклама», «рекламная кампания», «продвижение», «раскрутка», «4pda», «индексация», «позиционирование», «SEO», «чтобы нас находили».'
---

# Promote - make a finished product findable without spending money

The canon is [PROMOTION.md](../../rules/PROMOTION.md); this skill is its procedure. It writes **tickets and
tree files**, and runs **read-only** measurements. Every outward act - a push that publishes a site, a `gh`
write, a form submit, a pull request to someone else's repository, a product thread create/update - is an
**A·GO** step that waits for the owner's go naming it (PROMOTION §1 rule 9). Unprompted community posts and
human-voice replies stay the owner's (**O**).

Boundary: [feature-to-site](../feature-to-site/SKILL.md) keeps surfaces current per feature;
[release](../release/SKILL.md) and [store-publish](../store-publish/SKILL.md) publish versions. This skill
makes the product **found** and keeps the campaign's record.

---

## Step 0 - Classify the repo

- **No remote, or the contrib record says internal** -> no ticket. Record "internal - no promotion ticket" in
  the contrib record and stop.
- **Not yet public** (no release, no listing, owner decisions on distribution open) -> a ticket gated on those
  decisions: positioning worksheet and channel plan now, every outward step blocked by the release ticket.
- **Public product** -> the full procedure.
- **The hub** (`sza.od.ua`) -> the full procedure plus the **portfolio items**: the host-root `robots.txt` and
  Search Console property through the user-site repository (`SerZhyAle/SerZhyAle.github.io`, sourced from the
  hub tree), the hub's own head and indexing. Product tickets depend on this one.

## Step 1 - Find the ticket store and any existing campaign

Read the repo's agent-rules file and its spec-lifecycle doc: the ticket folder, id scheme, filename pattern,
header lines, index file, status vocabulary, and whether ids are allocated by a CLI (a spec catalog written only
through its tool - never hand-edit the journal). List **every** existing id, `done/` included, before taking
one; a duplicate id is a defect to fix, not to repeat.

Search the store for an existing promotion, SEO, positioning, directory or listing ticket. **One campaign per
product**: correct and extend the existing ticket rather than opening a second; a superseded or mis-numbered one
is withdrawn through the store's own rule.

## Step 2 - Measure the baseline (read-only, every number read, none estimated)

- `gh api repos/<o>/<n> --jq '{description,homepage,topics,stargazers_count,forks_count}'` and GraphQL
  `usesCustomOpenGraphImage` (gh runs in PowerShell).
- Release asset `download_count` per release, checksum files excluded; the traffic API if the token allows it.
- The site: Pages config (`gh api repos/<o>/<n>/pages`), generator or hand-written, the served root.
- Every page head: title, description, canonical, Open Graph with the image's real pixel size, Twitter card,
  JSON-LD types - flag any `aggregateRating`, `review` or retyped version - `hreflang` reciprocity and
  `x-default`, locales that exist only as script-switched spans, sitemap URL count and `lastmod` source,
  `robots.txt` location, any console verification token.
- Live: `https://serzhyale.github.io/robots.txt` status, the product sitemap status.
- Channels with ids; listing fields; forbidden-terms lists; positioning sources.

A number that cannot be read is written "unknown". Never a range, never an estimate, never a competitor's star
count from memory.

The page-head, sitemap, `robots.txt` and mandatory-page items are the [site-audit](../site-audit/SKILL.md) skill's
measurement: cite its latest `temp/site-audit/<date>/report.md`, or run it, instead of measuring them a second way.

## Step 3 - Positioning worksheet

Find the existing positioning source (a `POSITIONING.md`, a positioning JSON bound by `SITE-REPRESENTATION`, a
store listing deck). Fill PROMOTION §2's worksheet against it - alternatives from real issues and reviews,
attributes with code pointers, value, persona, category - and derive the field table. If none exists, writing it
is the ticket's first step, and an owner decision where the persona or category is a real fork.

## Step 4 - Write or correct the ticket

Use the store's header format and PROMOTION §8's sections. In particular:

- The baseline from Step 2, dated.
- Channels: every row of PROMOTION §5 that fits the shape, each planned, deferred with a revisit condition, or
  refused with the reason. Re-read a channel's rules page before relying on it; mark what could not be read
  `[unverified]`.
- A **SourceForge** row (an open-source product, PROMOTION §5): read the catalog contract `SOURCEFORGE-CHANNEL` and plan
  the row from [references/sourceforge-listing.md](references/sourceforge-listing.md), which carries the executor tags,
  the order, the stops and the integrity script; cite the contract by id and rule number, never by path.
- A **4PDA** row (Android or Windows product, PROMOTION §5): follow [references/4pda-threads.md](references/4pda-threads.md)
  for section mapping (`Android - Программы` via Мастер тем vs `Компьютеры и периферия -> Софт`), icon and compact
  Russian screenshot rules, BBCode templates, duplicate checks, `A→O` sign-in (`SZA`) and `A·GO` thread creation/updates.
- Acceptance criteria: PROMOTION §8's list as static predicates for this repo (the gate command, the API
  field, the file); criteria the shape voids are listed void with the reason.
- The portfolio dependency: the hub ticket owns the host-root `robots.txt` and console property; cite it by repo
  and id, do not repeat the work.
- Facts specific to this product: store policy terms, privacy promises, the compass conflict for its jargon,
  AI-assistance disclosure for communities that ask.
- Add the index row the store requires. Write in English (canon AUTHOR "Language").

If the owner approves the ticket, write the tactical folder: phases in dependency order with executor tags and a
go ledger (PROMOTION §8 item 8).

## Step 5 - Record and report

- Write one line into the repo's facts record (`rules/contrib/<project>.md`) in place: the campaign ticket id
  and its state. That record is the only canon file a project session may touch.
- Report to the owner: the ticket path, the baseline numbers, the decisions the ticket needs from the owner, and
  the first A·GO steps that would run after a go.

## Checklist

- [ ] Ticket store, id scheme and next id read from the repo, `done/` included; no duplicate id.
- [ ] One campaign ticket per product; an earlier one corrected, not duplicated.
- [ ] Every baseline number read and dated; "unknown" where unreadable.
- [ ] No rating, review, download or traffic figure invented anywhere, structured data included.
- [ ] Indexing per PROMOTION §3: host-root dependency named, sitemap to a console, no meta keywords, no blocked
      assets, reciprocal hreflang, truthful JSON-LD.
- [ ] Channels by shape with refusals recorded; no wrapper portal; AI rules of each venue respected.
- [ ] Every outward step tagged A·GO, A→O or O; nothing outward executed without a go.
- [ ] No telemetry, analytics or redirector planned.
- [ ] Contrib record line added.
