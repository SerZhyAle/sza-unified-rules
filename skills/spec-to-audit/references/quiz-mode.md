# Quiz mode - draining the owner's questions

Reference for the `spec-to-audit` skill ([SKILL.md](../SKILL.md)), moved out of the always-read text. A quiz sitting is started by the owner with `/spec-quiz`; a queue pass working one ticket never runs it.

A ticket enters `BlockQuestions` in one line; this is how it leaves. Like Sweep mode it is a **sitting, not
an interruption**: the block exists so the questions wait for an owner who is ready to answer them. The owner
starts it with `/spec-quiz` (`/sq`) - the [spec-quiz](../../spec-quiz/SKILL.md) skill finds the waiting tickets in
any project and carries the mechanics; the procedure below is its authority.

1. **Resolve each ticket from its authoritative record**, never from a filename. Only `BlockQuestions`
   clears here. `BlockNeedUserTest` needs a post-implementation device run (Sweep mode), `BlockExternal`
   needs the party outside the portfolio, and `BlockByOtherTask` clears on its local or cross-repo
   (`Blocker: <repoKey>:<id>`) blocker's status - unless the owner picks a fallback that removes the
   dependency, which is a question like any other. Report the rest and mutate nothing.
2. **Extract the decision points**: the questions (`Q: ..?`) and pre-implementation owner actions
   (`DO: <action>`) in the block's reason note, plus every open research item and unfilled owner input
   (including `- **DO:** <action>` lines in `### 3.3 Owner inputs (Approval gate)`) that note points at. On request (`--assumed`) the sitting also lists the
   ticket's `### Assumed (unattended, <date>)` and `### Assumed (attended, <date>)` entries - each with what was taken, the alternative it was
   weighed against and the date - so the owner can review and overrule them in the same sitting. An
   overrule is an answer of step 5's kind: the entry is marked `overruled <date>` with the owner's answer,
   the owner's value is written into the owner input or research item the assumption settled, and where a
   pass already built on the assumption the rework is captured as a fresh `Draft` and reported as parked.
   Unoverruled entries stay as they are.
3. **Research each one before asking - unless the ticket asks from a current question block.** A pass that
   parked the ticket wrote its researched questions into the spec file as a `### Questions (v1, <date>)` block
   (Stage 3, TASK-FLOW rule 7): the newest block that is not stamped `- answered <date>` on its heading is
   current while its date is not earlier than the day the ticket entered `BlockQuestions` and every `Q:` text
   of the note appears in it. **A current block replaces the research of this step**: its questions, options,
   consequences and recommendations are what gets asked, as they stand - the sitting does not re-research the
   ticket. A block that is missing, stale, of another version, malformed or already answered is not read:
   research exactly as below and leave the old block where it stands. Whatever the architecture, the code, a contract or a decision
   already recorded settles is **not asked**: fill it in and list it in the report as *resolved without
   asking*, with what settled it ([AI_USAGE.md](../../../rules/AI_USAGE.md) §1). Only a genuine owner call -
   scope, product intent, priority, wording, platform reach, build versus buy - or a pre-implementation
   owner `DO:` action (device, desk, or outside console account step) goes to the owner. In the
   reference sitting this settled 5 of 20 decision points without a word to the owner. Nothing left to
   ask -> write the fills and go to step 6.
4. **Ask multiple choice (and present `DO:` actions).** Each question specific, 2-4 options, each with its one-line consequence, the
   researched recommendation **listed first** and marked recommended. For a `- **DO:** <action>` item,
   show the exact action line to the owner and take the result (completed with the observed output/value,
   or an alternative/skip decision) as the owner input (S0042). Most-blocking first, in rounds where
   the runtime caps a round, never more than unblocking needs. A ticket with several questions may first be
   shown as one table - question, recommended answer, consequence - with one owner choice over it: accept all,
   pick the exceptions, or one by one (S0026). Accepting the table is the owner's answer to every row, given
   by the owner's click; nothing is accepted without it. The questions that arrive here are the
   owner-owned ones only: since S0039 (S0153 for attended passes) every pass takes a researched,
   ticket-reversible recommendation itself and records it under `### Assumed (...)`, so a reversible default
   no longer reaches this sitting as a question. What does arrive is still answered by the owner - in the
   reference sitting the owner chose something other than the default in 3 of 15 answers - and the
   recommendation never replaces a question that earned its place here. **After each round, re-apply the
   owner's own standing rules to the chosen option.** Where one of them contradicts the choice, show the
   collision once, with both outcomes, and let the owner pick - the menu was at fault, not the answer.
5. **Write back before any status move.** Each answer goes into the ticket's own record - the input
   filled, the research item resolved - plus a dated decisions block: question, chosen answer, one-line
   reason. A block that was asked from is stamped by appending ` - answered <yyyy-MM-dd>` to its heading,
   never deleted, once its items are settled. If the sitting had no current block, write and stamp a new
   block for the settled questions. Mark each settled owner-input action ` - done <yyyy-MM-dd>` or
   ` - dropped <yyyy-MM-dd>`, optionally followed by `: <result or reason>` (TASK-FLOW rule 7).
   An interrupted sitting can then leave answered tickets still blocked,
   never moved tickets whose answers exist nowhere.
6. **Restore one level.** The ticket returns to the status it would have had without the block, inferred
   from what exists: a plan with progress -> `In Progress`; a plan without progress -> `Tactical`; settled
   owner inputs and no plan -> `Approved`; otherwise `Draft`. Two equally plausible -> ask one more
   question. The move goes through the ticket's tool and runs whatever gate guards the restored status; a
   refusal keeps the block and names the residue, including any open `Q:` and `DO:` items. Then stop - continuing the pipeline is a separate,
   explicit request, and a quiz writes no code and runs no build.
7. **A skipped answer is never invented.** The input stays unfilled, the gate that needs it stays closed,
   the ticket stays in `BlockQuestions` with its reason note narrowed to what is still open. The answers
   that did arrive are still written back.
8. **Report per ticket**: start -> end status; asked (question -> answer); resolved without asking
   (decision -> value -> what settled it); assumed listed and any overrule (entry -> the owner's answer);
   outstanding.

**Several tickets in one sitting are allowed - with one write-back and one status move per ticket.** What
the block defers is the owner's attention, and that is paid per sitting, not per ticket: the reference
sitting cleared three tickets with 15 questions in 5 rounds, where three single-ticket sittings would have
cost three context loads and three interruptions for the same answers. What stays per ticket is what makes
a ticket auditable on its own - its decisions live in its own record, its move is judged on its own
evidence, and a question two tickets share is asked once and written into both. Rounds may mix tickets;
each question names the ticket it settles. "One ticket at a time" confuses the unit of conversation with
the unit of record.
