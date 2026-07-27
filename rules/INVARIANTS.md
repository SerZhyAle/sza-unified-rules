# Hard invariants - the page that is always in context

Twenty lines. Each one is here because breaking it is **expensive, irreversible, or outward-facing**:
it publishes something public, spends money, orphans installed users, leaks a secret, or claims a result
that was never proven. Ordinary good practice is deliberately *not* here - it lives in the reference docs
and in the skills, so this page stays short enough to actually be read.

Ordered by cost of violation. The pointer after each line is the doc that expands it.

1. Never change a shipped **frozen anchor** - winget `PackageIdentifier`/`PackageName`, Inno `AppId` or
   WiX `UpgradeCode`, MSIX Identity `Name`+`Publisher`, Play `applicationId` + signing key, Chrome item id /
   Edge product id, VS Code `<publisher>.<name>`, Go module path. ([PLATFORM_OVERLAYS](PLATFORM_OVERLAYS.md),
   [SECURITY_AND_PRIVACY](SECURITY_AND_PRIVACY.md) §2, [CHANNEL_MATRIX](CHANNEL_MATRIX.md))
2. Never ship a release that **shrinks reach** - countries, age rating, minimum platform version,
   ABI/feature/device set - and check it per flavor. ([RELEASE_AND_DISTRIBUTION](RELEASE_AND_DISTRIBUTION.md) §3)
3. Never commit a **secret or signing material**; tokens stay ambient to the runner, certs stay outside the
   repo or the store re-signs. ([REPOSITORY_LAYOUT](REPOSITORY_LAYOUT.md), [SECURITY_AND_PRIVACY](SECURITY_AND_PRIVACY.md) §1)
4. Treat every release as **one-way** and never trigger one - a `v*` tag push, a store upload, a marketplace
   publish - unless the owner asked for that exact release. ([RELEASE_AND_DISTRIBUTION](RELEASE_AND_DISTRIBUTION.md) §1)
5. **Block the release on a red pre-flight**: the sweep ends in a written PASS/FAIL and a FAIL stops the ship.
   ([TESTING_AND_QA](TESTING_AND_QA.md) §5)
6. Prove every package/store release by **updating a real prior install**, not only by a fresh install.
   ([RELEASE_AND_DISTRIBUTION](RELEASE_AND_DISTRIBUTION.md) §6)
7. Claim nothing **done, fixed, or passing** without a fresh command run, its exit code, and its output cited.
   ([TESTING_AND_QA](TESTING_AND_QA.md) §1, [DEVELOPMENT](DEVELOPMENT.md) §5)
8. Derive the **version** mechanically, never hand-bump it, keep its shape frozen for the product's life, and
   pin the release build to the tag. ([RELEASE_AND_DISTRIBUTION](RELEASE_AND_DISTRIBUTION.md) §4)
9. Let a `--force`/`-y` flag skip the **prompt** but never the **safety checks** on a destructive path.
   ([TESTING_AND_QA](TESTING_AND_QA.md) §6)
10. Preserve **user-authored data** on every ingest of an external artifact, and change a shared contract only
    by a `schemaVersion` bump. ([PLATFORM_OVERLAYS](PLATFORM_OVERLAYS.md) "Cross-project contracts")
11. Ship any **listening-port or elevation** feature OFF, enabled only by an explicit, gated, auditable opt-in.
    ([SECURITY_AND_PRIVACY](SECURITY_AND_PRIVACY.md) §3)
12. Ship **`THIRD-PARTY-NOTICES.txt` inside every distributed package** when the artifact bundles third-party
    binaries. ([SECURITY_AND_PRIVACY](SECURITY_AND_PRIVACY.md) §6)
13. Declare only the **permissions** the runtime actually uses, each with a one-sentence user-visible
    justification. ([SECURITY_AND_PRIVACY](SECURITY_AND_PRIVACY.md) §3)
14. Keep the **privacy page, the permission list, and the store data-safety form** saying the same thing;
    claim "no telemetry" only if it is true. ([SECURITY_AND_PRIVACY](SECURITY_AND_PRIVACY.md) §4-5)
15. File a fresh **IARC questionnaire** whenever the app's content-exposure profile differs; never copy a
    portfolio rating id. ([SECURITY_AND_PRIVACY](SECURITY_AND_PRIVACY.md) §5)
16. Never hand-edit a **render target** - a store listing, a mirrored doc, a published site export, a generated
    catalog or spec journal; regenerate it from its one source of truth.
    ([DOCUMENTATION_CONCEPT](DOCUMENTATION_CONCEPT.md) §1)
17. Land a user-facing change in **every surface and every locale in one edit**, driven by the ship-together
    surfaces manifest. ([DOCUMENTATION_CONCEPT](DOCUMENTATION_CONCEPT.md) §5, [LOCALIZATION](LOCALIZATION.md))
18. **Commit or push only when asked**, never casually on the default branch (the site-publish flow is the one
    named exception), never `--no-verify` / `--force` / bypassed signing; agent commits carry the co-author
    trailer. ([GITHUB_INTERACTION](GITHUB_INTERACTION.md) §2-3)
19. **Chat in Russian; write every artifact in English** - files, code, comments, script and console output,
    commit messages, PR titles and bodies. ([AUTHOR](AUTHOR.md) "Language", [DEVELOPMENT](DEVELOPMENT.md) §4)
20. Apply the **house text style** to prose and UI only - `..` never `...`, plain hyphen, Russian `ё` - never in
    code, specs, commands, logs, or chat. ([DOCUMENTATION_CONCEPT](DOCUMENTATION_CONCEPT.md) §5)

## What is deliberately not here

Layering and naming rules, the evidence ladder's rungs, the test tiers, repository layout, the SEO block, every
channel-specific trap (winget CRLF manifests, MSIX `%ProgramData%` redirect, Partner Center CSV merge), CI cost
levers, memory discipline. Each is either cheap to fix, caught by review, or belongs to exactly one skill.
Carrying them everywhere is what made the canon unreadable in the first place - the reason this page exists.

The per-channel payload lives in the `store-publish` skill, the release order in `release`, the surface map in
`feature-to-site`, the task lifecycle in `spec-to-audit`. Load the skill, not the whole canon.
