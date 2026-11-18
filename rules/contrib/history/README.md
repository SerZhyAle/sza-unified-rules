# Project history

One file per project, named like its facts record one folder up: `rules/contrib/<project>.md` holds the
project's current facts ([TEMPLATE.md](../TEMPLATE.md)); `rules/contrib/history/<project>.md` holds what
happened to them and when.

- **Append-only.** A run that changes a project's record adds one dated section at the end of that project's
  file here - `## Canon adoption <YY-MM-DD HH:mm>`, `## Canon re-sync <date> - <subject>`,
  `## Spread-back applied <date>`, a campaign note. Nothing above the new section is edited or removed.
- **Read by no skill.** No skill and no rule doc sends a session here, so a fact that exists only in a
  history file does not exist for the next session. The fact goes into the facts record, rewritten in place;
  the history section says when it changed and why.
- **A new file starts with one line,** `# History: <project>`, followed by the first dated section.
- **Links are written from this folder:** a rule doc is `../../<DOC>.md`, a facts record is
  `../<project>.md`. `tools/check-rules.ps1` checks them. The house text style is not applied here: a section
  keeps the words of the day it was written.
- **Delivery.** A change here raises no plugin version - `deploy.ps1` exempts this folder. A change to a facts
  record does, because skills read it from the plugin cache.
