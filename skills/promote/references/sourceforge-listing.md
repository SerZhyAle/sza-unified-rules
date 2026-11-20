# SourceForge listing - the procedure behind the `SOURCEFORGE-CHANNEL` contract

Reference for the [promote](../SKILL.md) skill. The contract `SOURCEFORGE-CHANNEL` (catalog domain `sourceforge/`) holds
what the site accepts, refuses and does by itself; read it first and cite it by id and rule number. This page holds how an
agent runs the steps: who acts, in what order, and where it stops. The first run was FileDO's R1 on 2026-11-20 (ticket
FILEDO-0166); a product that meets a form this page does not describe records what it saw, dated, and files a proposal
against the contract.

Executor tags are PROMOTION section 1 rule 9: **A** the agent, **A·GO** the agent after the owner's go naming that act,
**A→O** the agent up to a step that is the owner's, **O** the owner.

## Order

| # | Step | Tag | What it is |
| --- | --- | --- | --- |
| 0 | Eligibility | A | The public repository's `LICENSE` names an OSI licence (rule 1). Closed source: the contract's adoption row is "not applicable, declared" and the ticket's SourceForge row is refused with that reason. |
| 1 | Draft the texts | A | In the product's `outreach/sourceforge.md`, tree only: the URL name (the repository slug, lower case), a Short Summary under 70 bytes and a Full Description within 1000 characters (rule 12), the homepage, the support URL, the logo from the identity manifest, the categories, the default download file, the import tools (Files and Git; Tickets and Wiki only with a reason, rule 11) and the mount point `git` (rule 6). No competitor's name. |
| 2 | Session | A→O | Open `https://sourceforge.net/p/add_project`. A signed-in menu `Me` pointing at the author's profile is the session; a sign-in form is a stop. A password, a reCAPTCHA, an e-mail or SMS code and the phone PIN are the owner's (rules 2 and 5), and so is a new account unless the owner ordered the agent to make it. Name exactly what is left. |
| 3 | Create the project | A·GO | Quote the go in the go ledger first. Fill the project name and the URL name, untick Git, and stop before the Terms box and Create: ask the owner in chat, naming the box ("I have read and agree to the Terms of Use..", cut short) and the button, unless the go names them. Read back `https://sourceforge.net/p/<name>/admin/` and the tools the project holds (rule 6). |
| 4 | Import | A·GO | Admin > Import, by clicking the links (rule 8). Files: the link "the import form", never "Set up" (rule 9). Git: label "Source Code", mount point `git` when `code` exists (rule 6). Do not import Tickets or Wiki unless the go names them. After the Files import, compare the folder names with `gh release list` (rule 9). |
| 5 | Integrity | A | Rule 16 for every file of the newest release, then rule 17. The script below is the check. A stalled transfer is "integrity check not run"; hold the Full Description and every claim that the files are the published ones until a person's browser finishes the download. |
| 6 | Metadata | A·GO | Admin > Metadata with the step 1 texts, one save, then read the page back (rules 12 to 15). Never select a "Delete" control (rule 14). Project status stays Active. |
| 7 | Record | A | One dated outcome line in the ticket's channel outcomes, one go-ledger row per A·GO step, and the five items of the contract's section 4. |

## Stops

- Three importer HTTP 500s, or a second kind of refusal that repeats after one correction: stop that route and record it
  (rule 18; PROMOTION section 1 rule 9). A validation message on a form is not an attempt.
- A sign-in form, a password, a human check, a code in a mailbox the browser cannot open, the phone PIN, the Terms box
  without a go that names it, and any control that deletes a project or a tool.
- The ongoing GitHub integration ("Set up") and any change to the product's GitHub repository: not under the import's go.

## Browser notes

- A page reached by a typed address may redirect; a page reached by the click opens after about 3 seconds. Wait for the
  title before filling.
- An element reference goes stale when the page reloads or re-renders. A call that answers "element not found" means look
  at the page before repeating: the submit may already have happened in the owner's own browser, and the report says who
  did it.
- A form that refuses a field prints the reason under the field; read it, correct the one field, resubmit once.

## The integrity script

```powershell
param([Parameter(Mandatory)][string]$Downloaded, [Parameter(Mandatory)][ValidatePattern('^v\d{10}$')][string]$Tag, [string]$Repo = 'SerZhyAle/FileDO')
$ErrorActionPreference = 'Stop'
$name = Split-Path -Leaf $Downloaded
$url  = "https://github.com/$Repo/releases/download/$Tag/$name.sha256"
$pub  = (Invoke-WebRequest -UseBasicParsing -Uri $url).Content
if ($pub -is [byte[]]) { $pub = [Text.Encoding]::ASCII.GetString($pub) }
$want = ($pub.Trim() -split '\s+')[0].ToUpperInvariant()
$got  = (Get-FileHash -Algorithm SHA256 -LiteralPath $Downloaded).Hash.ToUpperInvariant()
if ($got -eq $want) { "MATCH    $got  $name"; exit 0 }
"MISMATCH downloaded=$got published=$want  $name"; exit 1
```

Run it from a fresh, empty folder that holds only the downloaded file with the name SourceForge gave it; `-Repo` is the
product's GitHub `<owner>/<repo>` and `-Tag` the `v<version>` of the file's release. A product whose tag shape is not
`v` and ten digits changes the pattern in its own copy and says so in the ticket.
