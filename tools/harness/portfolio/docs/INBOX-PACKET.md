# INBOX-PACKET - the phone-ticket transport packet (S0045)

**Version:** 1 (frozen 2026-11-11)
**Consumers:** the phone writer (the FMS_A ticket filed by S0045 phase 5), the PC reader
(`lib/inbox-packet.ps1` here, the S0046 listener/ingest), the conformance vector
(`tools/tests/data/inbox-ticket-vector/`).
**Contract line:** the envelope is the DEVICE-EXCHANGE section 24 Drive packet (item CN,
`schemaVersion` 2) with the `TICKET` `payloadKind` proposed to its owner in
`PROPOSAL-2026-11-11-ticket-packet-kind.md`. Until the owner folds the proposal, this document
is the only normative text; nothing in the shipped contract was edited for it.

## 1. The channel and the inbox root

The v1 channel is a visible shared Drive folder synced onto this computer by Drive for desktop:

- **Inbox root:** `C:\GD\SZA\ticket-inbox\` (beside the existing `C:\GD\tc\SZA` and
  `C:\GD\FastMediaSorter Debug Logs`). Overridable by `publish-projects.ps1 -InboxRoot` and by
  the `SZA_INBOX_ROOT` environment variable.
- The phone uploads a packet folder into the root through the Drive app or FMS_A; the PC sees it
  on the next Drive-for-desktop sync and the reader's poll (60 s, mirroring DEVICE-EXCHANGE item
  CQ for a running program).
- A future `appDataFolder` `cross_device_transfer` relay can carry the identical manifest
  unchanged; the owner choice 1(c) keeps the manifest byte-compatible for exactly that move.

```
C:\GD\SZA\ticket-inbox\
    projects.json            the project picker list (section 3)
    new\<packetId>\          a packet as the phone wrote it; waiting for the reader
    processing\<packetId>\   claimed by the PC (S0046); rename, never copy
    done\<packetId>\         processed; result.json beside the manifest (section 5)
    failed\<packetId>\       refused; reason.json beside the manifest (section 5)
```

The spool sub-folders are created by the PC side (S0046's install step); the phone writes only
`new\<packetId>\`. The layout freezes here so both sides name the same places.

## 2. The packet

One packet is one folder named by its `packetId`, under `new/` on arrival. The phone writes the
payload files first and `manifest.json` last: the manifest is the commit marker, and a folder
without one is invisible to the reader. A folder name, the file name `manifest.json` and the
order are frozen exactly as DEVICE-EXCHANGE item CN freezes them for Drive packets.

### 2.1 The manifest members

`manifest.json` is one UTF-8 JSON object (2-space indent, LF, a final newline, no BOM). Members:

| Member                | Required | Type / rule |
|-----------------------|----------|-------------|
| `schemaVersion`       | yes      | `2` |
| `payloadKind`         | yes      | `"TICKET"` |
| `packetId`            | yes      | the folder's name; `[A-Za-z0-9_-]{1,64}`, opaque |
| `createdAtEpochMs`    | yes      | the writer's clock, epoch ms, integer |
| `senderDeviceName`     | yes      | non-empty display name of the sending device |
| `senderDeviceId`      | no       | the sender's DEVICE-EXCHANGE `deviceId`, when it has one |
| `targetDeviceName`     | no       | display name or `null`; `null`/absent means any own device |
| `status`              | no       | `PENDING` when absent; `PENDING`/`CLAIMED`/`EXPIRED` |
| `fileNames`           | yes      | the payload names, equal to the `name` of `files[]` in order |
| `totalSizeBytes`      | yes      | equal to the sum of `files[].size` |
| `ttlSeconds`          | yes      | lifetime, positive integer; replaces the v1 `ttlDays` (7 days = 604800 recommended) |
| `files`               | yes      | one object per payload file; `[]` for a text-only ticket |
| `project`             | no       | a registry key (`^[a-z][a-z0-9-]*$`) or `null`; absent = `null` |
| `projects`            | no       | array of registry keys; combined with `project` as a union when both present |
| `text`                | no       | the ticket text inline; optional when `text.md` is a payload file |
| `auth`                | no       | reserved (section 6); ignored by the v1 reader |

A `files[]` entry is `{ name, size, sha256, mimeType, role }`:

- `name` - a base name, no `/`, `\` or control character, not `.`, `..` or `manifest.json`
  (the item CN rule; the reader refuses anything else as unsafe);
- `size` - bytes, non-negative integer;
- `sha256` - lower-case hex over the file's bytes;
- `mimeType` - a string (`application/octet-stream` when unknown);
- `role` - optional: `text`, `voice`, `screenshot`, `log`, `other`. The ingest (S0046) uses the
  role to place an attachment into the captured ticket.

A reader ignores a member it does not know - the same forward-compatibility rule as item CN. A
packet with no project and no `projects` files once into `canon` for triage; a key unknown to the
PC registry is accepted by the format (the ingest decides where it lands).

### 2.2 Limits

Mirroring DEVICE-EXCHANGE item CS in spirit, checked by the reader before ingest:

- the packet's total payload size is at most **200 MiB** and at most **50 files** (S0046 opens
  question 4's ceiling; over the cap the packet is refused whole - nothing ingested);
- a payload file above 5 MiB is uploaded by the phone with Drive's resumable upload, never whole
  in memory (item CN).

### 2.3 Expiry and garbage

On the PC's clock (a file system has no Drive `createdTime`, so the folder's write time stands in):

- a packet folder without a manifest, older than 7 days, is garbage-collected - a phone upload
  that never finished (mirrors item CR);
- a claimed packet past `createdAtEpochMs + ttlSeconds` is still ingested: once claimed the
  ticket files whole; expiry protects `new/` only.

## 3. projects.json - the phone's project picker

`publish-projects.ps1` (this harness) writes `projects.json` into the inbox root from the
portfolio registry (`repos.json`, TASK-FLOW rules 41/42/60); `pq list -Json` is the machine
output it reads from, so the file changes only when the registry does. Shape:

```json
{
  "schemaVersion": 1,
  "generatedAt": "2026-11-11T09:30:00Z",
  "projects": [
    { "key": "canon", "name": "sza-unified-rules" },
    { "key": "fms-a", "name": "FastMediaSorter_mob_v2" }
  ]
}
```

- `key` - the registry key, exactly as `pq list` prints it; `name` - the display name, the leaf
  folder name of the registry `path`.
- Order is the registry's project order (rule 44); a scheduled refresh (any
  `Register-ScheduledTask` run of the script, a manual call, or the S0046 watcher on start)
  keeps it current.
- A stale or missing `projects.json` makes the phone fall back to free text with `project: null`
  - the ticket still files, into `canon`.

## 4. Reader acceptance - the named reasons

`lib/inbox-packet.ps1` is the reader. Its accept/refuse matrix is part of this format: accept
exactly what section 2 defines, refuse everything else with a named reason, and never ingest a
byte of a refused packet. The reason names are frozen so the phone can show the owner one line:

| Reason                  | Condition |
|-------------------------|-----------|
| `FolderMissing`         | the packet folder path does not exist |
| `ManifestMissing`       | the folder has no `manifest.json` |
| `ManifestInvalidJson`   | `manifest.json` is not one parsable JSON object |
| `SchemaVersionUnsupported` | `schemaVersion` absent or not `2` |
| `PayloadKindNotTicket`  | `payloadKind` is not `"TICKET"` |
| `PacketIdInvalid`       | `packetId` fails the grammar, or is not the folder's name |
| `CreatedAtInvalid`      | `createdAtEpochMs` absent, not an integer |
| `SenderDeviceNameInvalid` | `senderDeviceName` absent, empty, not a string |
| `MemberInvalid`         | `senderDeviceId`/`targetDeviceName` present and neither a string nor `null` |
| `TtlInvalid`            | `ttlSeconds` absent, not a positive integer |
| `StatusInvalid`         | `status` present and not `PENDING`/`CLAIMED`/`EXPIRED` |
| `FilesMemberMissing`    | `files` absent (it may be `[]`) |
| `FileEntryInvalid`      | an entry misses `name`, `size`, `sha256` or `mimeType`, or a member has a wrong type |
| `FileNameUnsafe`        | a `name` fails the base-name rule of section 2.1 |
| `FileNamesMismatch`     | `fileNames` is not the `name` list of `files[]`, in order |
| `TotalSizeMismatch`     | `totalSizeBytes` is not the sum of `sizes` |
| `RoleInvalid`           | `role` present and outside the five-value set |
| `ProjectKeyInvalid`     | `project`/`projects` present a key that fails `^[a-z][a-z0-9-]*$` |
| `TextInvalid`           | `text` present and empty, whitespace-only or not a string |
| `FileMissing`           | a `files[]` name is not in the folder |
| `FileSizeMismatch`      | the file's bytes are fewer/more than `size` |
| `FileHashMismatch`      | the `sha256` does not match the bytes |
| `UnexpectedFile`       | the folder holds a file `files[]` does not list |
| `PacketTooLarge`       | total payload over 200 MiB |
| `TooManyFiles`         | more than 50 files |
| `AuthInvalid`           | `auth` present and neither `null` nor an object |

A packet folder may also carry `result.json` or `reason.json` beside the manifest (section 5) -
the reader treats them as it treats any unknown file only in `done/`/`failed/`; in `new/` they are
`UnexpectedFile`.

## 5. Marking the packet processed

The marking is owner choice 5(a): a move, not a message.

- A processed packet moves to `done\<packetId>\` with the payload preserved and a `result.json`
  beside the manifest:
  `{ "packetId", "tickets": ["<key>:<id>", ...], "verdict", "at" }` - the ticket ids the ingest
  created. After the inbox drain decides execution, it adds `execution` and `executions`: per-ticket
  outcomes and reasons; after it builds (S0048), the per-ticket `builds` rows. The ingest also marks what
  the owner's own words asked for, additively: `publishIntent` ("ms-store"|"github"|"winget", absent when
  the text names no channel) and `buildIntent` (true when the text asks for a build). The original fields
  and packet payload remain intact.
- A refused packet moves to `failed\<packetId>\` with `reason.json`: `{ "error", "detail }` -
  the `error` is a reason name of section 4.
- The phone reads `done/` on its next Drive sync and shows `processed: <key>:<id>`; deletion after
  receipt (item CR) stays the owner's manual call on the phone - the PC keeps the spool as the
  audit trail. A `REPLY`-shaped confirmation (item CO) is the later step, when the
  exchange-server channel joins.

## 6. Security and the reserved `auth` member

The inbox root is the owner's own Drive, and everything with access to that Drive can drop a
packet; v1 accepts that single-user trust boundary (owner choice 3(a), the canon's
SECURITY_AND_PRIVACY rule set) and the reader ingests nothing outside the inbox root - a payload
name is always a safe base name inside the packet folder. The `auth` member is reserved for the
HMAC-SHA256 option 3(b):

```json
{ "auth": { "algorithm": "HMAC-SHA256", "value": "<base64 over the manifest canonical bytes>" } }
```

A v1 reader validates its shape when present (an object or `null`) and ignores its value; the
shared-secret provisioning and the enforcement are a later, additive format version.

## 7. The conformance vector

`tools/tests/data/inbox-ticket-vector/` freezes one complete packet:

- `manifest.json` - the fixed manifest; its SHA-256 is recorded in `vector.json` and must never
  change;
- the four payload files (`text.md`, `voice-note.m4a`, `screenshot-01.png`, `app-log.txt`) with
  their SHA-256s recorded in `manifest.json` and `vector.json`;
- `vector.json` - the descriptor: the `packetId`, the per-file hashes, the manifest hash.

Two probes replay it byte for byte in `tools/tests/inbox-packet.tests.ps1`:

- **writer probe** - `Write-InboxPacketManifest` rebuilds the manifest from the ordered reference
  object and the live payload bytes; the result is byte-identical to the checked-in
  `manifest.json`;
- **reader probe** - `Test-InboxPacketFolder` accepts the folder as written, and every payload
  file hashes as `manifest.json` claims.

Any byte change to the vector is a new vector: a new `packetId`, new hashes in `vector.json`, and
a note naming the change. A second implementation (the FMS_A writer) replays the manifest
byte for byte against the same `manifest.json` before its first send, the rung the
`vectors/drive-packets-v1.json` corpus set for Drive packets.

## 8. Versioning

This document is format version 1 and only grows: a new version is backward compatible, an older
reader skips members it does not know, and `schemaVersion` inside the manifest stays `2` while
changes are additive to DEVICE-EXCHANGE item CN. The manifest is accepted by a shipped
Drive-packet reader the way any unknown kind is: skipped, never applied to the wrong subsystem.
