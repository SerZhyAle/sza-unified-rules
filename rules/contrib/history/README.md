# Project history

Frozen since 2026-11-26: no session appends to a file here and no new file is created. The existing files stay as
they are. A project's current facts are in `rules/contrib/<project>.md` ([TEMPLATE.md](../TEMPLATE.md)); what
changed and when is in git history and in the ticket that changed it.

- **Read by no skill.** No skill and no rule doc sends a session here, so a fact that exists only in a
  history file does not exist for the next session.
- **Links are written from this folder:** a rule doc is `../../<DOC>.md`, a facts record is
  `../<project>.md`. `tools/check-rules.ps1` checks them. The house text style is not applied here.
- **Delivery.** A change here raises no plugin version - `deploy.ps1` exempts this folder.
