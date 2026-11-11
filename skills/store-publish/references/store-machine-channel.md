# Microsoft Store machine channel

Reference for `store-publish` and `release`. The Store Developer CLI and submission API can read an existing
product through an Entra application. The default Store submission flow remains manual in Partner Center.
The proposed submission-channel rules in `PROPOSAL-2026-11-11-store-submission-interface`, domain
`windows-store/`, are pending and **UNVERIFIED**: no submission has gone through the machine path. They are
not contract requirements until the contract owner accepts them. A first publication and age rating use
Partner Center.

## Owner setup and rotation

1. Associate the tenant in Partner Center using a native work account with tenant administrator authority and
   MFA. A personal Microsoft account cannot perform the association. Security defaults require MFA on the new
   work account before sign-in. After association, User management still asks for an Entra sign-in; sign in
   with the work account to manage the application.
2. Register an Entra application in Partner Center and give it a working Windows role. Manager (Windows) was
   used; a narrower role has not been proven. Prefer a certificate to a client secret. The owner keeps the
   credential and account identifiers outside repositories, agent chats and logs.
3. The owner configures `msstore` in their own terminal. With version 0.3.9.7, interactive
   `msstore reconfigure` stalled at organization discovery; the working route supplied `--tenantId`,
   `--sellerId`, `--clientId`, and `--clientSecret` or a certificate option such as
   `--certificateThumbprint`. Do not paste values into agent chat or shared files. A command-line secret may
   remain in shell history: clear the session and persistent shell history after configuration, using that
   shell's own history controls. Avoid exposing the command in a transcript or log.
4. Record the credential's expiry date and role in the owner's expiry list, and set a reminder in advance
   (30 days is the proposal). Rotate before expiry: create the replacement, configure and verify it with a
   read-only call, then remove the old credential. A key pasted into an agent chat is exposed: rotate it and
   remove the old key, even if no agent used it. Never record its value.

## Read-only preflight

The owner can verify access with `msstore apps list`, `msstore submission status <Store ID>` and
`msstore submission get <Store ID>`. Do not print configuration or raw submission JSON: it can contain
sensitive URLs and account data. A `get` returns the last published submission when no submission is pending;
read the status and the CLI's message, not the existence of JSON. The CLI wraps JSON at console width, even
inside an escape sequence. Remove raw CR and LF before parsing; escaped `\r\n` in values must remain intact.

For a configured channel, before the release tag read the product's Store ID from its identity file and run:

```powershell
pwsh -NoProfile -File "$env:CLAUDE_PLUGIN_ROOT/tools/Store-Preflight.ps1" `
    -StoreId $storeId -ProductName $productName -PackageVersion $msixVersion
```

The product name is a display name, never an account identifier. The optional `PackageVersion` is the
four-part MSIX version about to be built; provide it for a release to compare it with every live package.
The script calls only `submission get` through an internal allow-list. It never displays the CLI response or
configuration. Exit codes: `0` means the checks passed; `1` means pending/non-published submission, no live
submission, invalid or missing data, non-Free pricing, or a candidate version that is not greater than every
live package version; `2` means the CLI is missing or the channel call failed and the Store step is manual.
An ambiguous or malformed successful response is exit `1`, not a pass. The preflight does not prove a write
will succeed or verify credential expiry; check the owner's expiry record separately. After a tag, report a
channel failure and continue the other release channels.

## Prepare and publish

Prepare the unsigned package and listing, verify both, and use the manual Partner Center flow by default.
Preparing a machine draft, if later implemented, changes the live Store state; it is not a dry run. Never
modify a console-created submission through the machine path. The owner handles that submission in Partner
Center. A machine-created submission must stay on the machine path until the owner commits or deletes it.

Publish means committing a submission to certification. It is a separate owner act, requiring the owner's
explicit typed confirmation naming the Store ID and package version. The shared preflight implements no draft,
upload, commit, delete or rollout. The first machine write needs the owner's explicit instruction naming the
product and version and belongs to a real release, not this preflight.

## The evidence a release keeps

For every channel run the release record holds, in the repository and without any account identifier or
secret: the Store ID, the package version, the submission id the Store returned, the status values polled
with their time (`PendingCommit`, `CommitStarted`, `PreProcessing`, `Certification`, `Release`, `Published`,
or the `*Failed` value with its `statusDetails` text), and which listing path was used (the CSV export-merge
flow or the submission-JSON metadata path - one per release). The preflight's `-Json` output is that record
for a preflight run: `mode`, `storeId`, `checkedAt`, `status`, `statusValues`, `submissionId`, `pricing`,
`candidateVersion`, `liveVersion`, `listingPath`, and `refusal`/`detail` or `manualReason` when the run did
not pass. A `*Failed` submission is reported to the owner with its `statusDetails` text and is never retried.
Rotation of an exposed or expired credential is recorded by date only - never the value.
