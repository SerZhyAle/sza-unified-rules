# ABOUT-PAGE - pointer

| Field | Value |
| --- | --- |
| Contract | `ABOUT-PAGE` |
| Version | 1.1, active |
| Home | the shared contracts catalog, domain `about-page/` (the path is in [CLAUDE.md](../../CLAUDE.md)) |
| Role | **consumer**: PQ Control Panel (`PQShell.exe`) and the `pq` command line. The owner is `shared` |

## What binds here

- Rules 1 to 5 bind the panel. It has no settings surface, so the **About** button of the top bar opens About as a
  dialog (rule 1): `tools/harness/portfolio/gui/src/FormAbout.vb`. English is its only shipped locale.
- Rule 6 binds `pq`: `pq -Help` (and a bare `pq`) prints the version and, in its description, the line
  `Author: Serhii Zhyhunenko - https://sza.od.ua`. `pq` has no `version` verb.
- Rule 7 does not apply: neither program has a watch app or a watch face.

## What this repo must do to stay conformant

- The panel's version is the build's own: `PQShell.vbproj` reads `CANON_VERSION` into `Version`. `pq` reads the same
  file at run time. Neither is typed by hand.
- The program page is the repository's front page - neither program has a row in `SITE-FAMILY-MAP` section 2 - and
  the documentation link is the portfolio guide on the same host. A row in that table, once there is one, replaces
  the program page.
- The author block carries the name and the site only.

## Evidence

Read statically and `pq -Help` run on 2026-11-27 (ticket `CANONR-0251`). Owed under section 4 until a build is
published: the capture of the panel's About, the check that its version equals the installed build's, and a click on
each link.
