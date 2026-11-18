---
name: sq
description: Short form of /spec-quiz - the same sitting with the same arguments. Kept for the PQShell "Answer questions" button and the "PQ Answer questions" shortcut, which start it as /sza:sq. Use only on /sq or /sza:sq; any other wording is spec-quiz.
---

# sq - /spec-quiz, short

The same command as [spec-quiz](../spec-quiz/SKILL.md), with the same arguments. Load that skill and follow it
from Step 0; nothing here differs.

This folder stays only because the PQShell build in use and the installed `PQ Answer questions` shortcut start
the sitting as `/sza:sq`. Their sources call `/sza:spec-quiz` (S0113); once PQShell is rebuilt and
`install-shortcuts.ps1` is run again, this folder is removed.
