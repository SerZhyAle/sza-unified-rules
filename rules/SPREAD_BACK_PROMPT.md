# Spread-back prompt - superseded

This was the prompt the owner copy-pasted into a session started in each repository to adopt the canon, plus
a table tracking which repos had done it. Both are gone, and both were replaced by something that cannot go
stale the same way.

**The prompt is now the [`adopt-canon`](../skills/adopt-canon/SKILL.md) skill.** Run it in a session started
in the target repo - one repo per session. It ships with the canon, so there is nothing to copy and nothing
to keep in sync with the docs it references.

**The adoption table is now the `.sza-canon.json` stamp** at each adopting repo's root. The old table was a
hand-maintained ledger in this folder, and by the time it was replaced it was wrong for six of nine repos:
five records documented a completed adoption the table still showed as pending, and one project had no row at
all. A stamp cannot drift from the repo it lives in, and `tools/check-compliance.ps1` reads it directly:

```powershell
pwsh -File tools/check-compliance.ps1 -RepoRoot <repo>
```

Historical note: the records under [contrib/](contrib/) refer to "SPREAD_BACK_PROMPT" because that is what
the flow was called when they were written. Those entries are accurate accounts of what happened; only the
mechanism changed.
