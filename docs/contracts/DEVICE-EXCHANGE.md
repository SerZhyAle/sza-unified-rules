# DEVICE-EXCHANGE - pointer

| Field | Value |
| --- | --- |
| Contract | `DEVICE-EXCHANGE` |
| Version | 1.15, active |
| Home | the shared contracts catalog, domain `device-exchange/` (the path is in [CLAUDE.md](../../CLAUDE.md)) |
| Role | **receiver of one packet kind, partial**: the phone-ticket transport reads the `TICKET` kind of the Drive packet queue (section 24, items CN, FC and FD) and writes what the phone reads back (`projects.json`, `result.json`, `reason.json`). The owner is FastMediaSorter Android; this repository holds no record, server wire, sealed content or any other part of the contract |

## What this repo must do to stay conformant

- The reader is `tools/harness/portfolio/lib/inbox-packet.ps1` and its matrix is
  [INBOX-PACKET.md](../../tools/harness/portfolio/docs/INBOX-PACKET.md) section 4, whose reason names are item FC's
  frozen list; where that document and items FC and FD differ, the contract wins. A refused packet is refused
  whole and nothing of it is ingested; a member the reader does not know is ignored (item CN).
- The spool is `lib/inbox-spool.ps1`: `new/`, `processing/`, `done/` and `failed/` under the inbox root, a claim by
  rename and never by copy, `result.json` or `reason.json` beside the manifest, the payload and the manifest kept
  intact in `done/` and `failed/` (item FD). The filing is `lib/inbox-ingest.ps1` and the drain is
  `lib/inbox-drain.ps1`, which adds only members to `result.json` (`execution`, `executions`, `builds`; item FD
  says the PC adds some as its work proceeds). The watcher is `watch-inbox.ps1`, which polls every 60 s as item CQ
  gives a running Windows program.
- `publish-projects.ps1` writes `projects.json` in the registry's rank order (TASK-FLOW rule 44). It was written in
  array order until 2026-11-15 (S0081); on the real registry the two orders of 19 projects differ from the second
  place on (`pq-sandbox2`, `fms-web` and `tourist-mob` stood ahead of `canon` and `hub`), so the phone's picker did
  not follow the owner's rank.
- The vector `tools/tests/data/inbox-ticket-vector/` is the catalog's `vectors/ticket-packet-v1/` byte for byte
  (manifest SHA-256 `d24baab4..`, the four payload files and `vector.json` equal; compared on 2026-11-15). It is
  replayed, never filed, and a product never writes it into a real inbox.

## Read on 2026-11-15 (S0081)

Items CN, FC and FD read rule by rule against the files above. Held: the manifest members and their types, the 26
refusal names and their conditions, the limits (200 MiB, 50 files), size and hash checked before anything is filed,
an unknown project routed to the triage project with the several-keys cross-link, the reader executing nothing from
the packet itself (the drain's start of a filed ticket is the receiver's own policy, which item FC leaves to it).
Fixed in the pass: a project key, packet id or hash with a trailing line feed passed the grammar (`$`
matches before a final line feed in .NET; now `\z`), the limits were judged after every file was hashed and a file
past 2 GiB threw out of the hash instead of being refused (now judged on the declared sizes first), and
`projects.json` order. Open, each a dated exception in the catalog registry: manifest-less folders are never
deleted (S0085) and six points that the contract has to answer first (S0086) - what the PC does with an unclaimed
packet past its `ttlSeconds`, the filing-failure names in `reason.json`, `text` beside a text file, `null` for
`status` and `text`, the file-name characters Windows refuses, and the target members.

## Evidence

`tools/tests/inbox-packet.tests.ps1`: 50 cases, 2.3 s, exit 0 on 2026-11-15, the writer probe and the reader probe
of the vector among them. This suite is in the fast list; the inbox listener, drain and crash suites are release
tier and were not run, so the claim, recovery and drain paths are read, not executed. Not measured: a real Drive
for desktop folder, a packet written by the phone's own writer (its replay of the vector is not yet recorded in the
catalog).
