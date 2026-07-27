# New Project Checklist - the front door

The single ordered runbook for standing up product N+1. It does not re-explain the rules; it sequences
them and links to the doc that owns each step. Work top to bottom; skip only what genuinely doesn't
apply (a CLI tool has no site, a single-locale app skips localization).

## 0. Decide the shape

- Pick the **platform overlay** ([PLATFORM_OVERLAYS.md](PLATFORM_OVERLAYS.md)): Windows desktop /
  Android / Go CLI / browser extension, or draft a new overlay if none fits. This decides your source
  root, release-mechanics folder, version shape, and channels. A product may also combine one overlay's
  distribution with another's source shape, ship as several **editions**, co-ship several artifacts in
  one release, or carry a **companion editor extension** - the shapes and their parity mechanisms are
  all named in PLATFORM_OVERLAYS ("Editions", "Co-shipping shapes", "Companion editor / IDE extension")
  and DEVELOPMENT §12-14.
- **Windows product?** Choose the delivery shape (portable zip / Inno setup.exe / WiX MSI, + MSIX) via
  [WINDOWS_PACKAGING.md](WINDOWS_PACKAGING.md) before reserving anchors.

## 1. Skeleton

- Create the universal top-level shape ([REPOSITORY_LAYOUT.md](REPOSITORY_LAYOUT.md)): root files
  (`README`, `CHANGELOG`, `LICENSE`, agent-rules file), source root, `tests/`,
  `docs/{guides,specifications,roadmaps,contracts}/`, the overlay's release-mechanics folder, `tools/`.
- Point `.gitignore` at the platform's build-output dirs + the secret globs.

## 2. Agent operating setup

- Author the repo's agent-rules file ([AI_USAGE.md](AI_USAGE.md)): reference `CLAUDE.md` (+ `AGENTS.md`),
  the skill/command routing, and a memory folder.
- Load the owner profile ([AUTHOR.md](AUTHOR.md)) so tone, language, and the product compass are set
  from commit one.

## 3. Sources of truth

- Stand up the single sources of truth ([DOCUMENTATION_CONCEPT.md](DOCUMENTATION_CONCEPT.md) §1) - most
  start as empty files.
- Adopt the version + `CHANGELOG [Unreleased]` flow (§2) with the overlay's version shape.

## 4. Engineering discipline

- Set the layering, naming, size ceiling, comment/logging rules ([DEVELOPMENT.md](DEVELOPMENT.md)).
- Add the machine-generated-smell gate and any recurring-defect gates the platform needs.
- Define the ticket/spec lifecycle for the project (Sxxxx catalog, or `docs/specifications/`).
- Wire the gate & closure mechanics ([DEVELOPMENT.md](DEVELOPMENT.md) §15): ratchet baselines, a batched
  fast-gates runner, a one-call closure facade, and (for PowerShell) the reachable-exit-code contract.

## 5. Verification

- Adopt the flagship "no claim without evidence" rule + the evidence ladder
  ([TESTING_AND_QA.md](TESTING_AND_QA.md)).
- Script the pre-release sweep with a written verdict; write the persona happy-path check.

## 6. Git & release

- Set the git conventions ([GITHUB_INTERACTION.md](GITHUB_INTERACTION.md)): working-tree-is-truth,
  commit/PR shape, co-author/generator trailers, auth hygiene.
- Write the release runbook ([RELEASE_AND_DISTRIBUTION.md](RELEASE_AND_DISTRIBUTION.md)): the
  build/release boundary, the coverage-regression gate, the per-channel distribute list, post-release
  checks.
- Fill the project's rows of the per-channel reference ([CHANNEL_MATRIX.md](CHANNEL_MATRIX.md)): keep only
  the channels this project ships to, and wire each row's trigger/auth/listing-source into the release skill.

## 7. Product surfaces (as applicable)

- **Multi-language?** Adopt the localization workflow ([LOCALIZATION.md](LOCALIZATION.md)): which
  surfaces localize, the parity-enforced string tool, the shipped locales.
- **Store submission?** Fill the privacy/permissions posture
  ([SECURITY_AND_PRIVACY.md](SECURITY_AND_PRIVACY.md)): privacy page, data-safety declaration,
  permission justifications.
- **Has a web property?** Configure hosting/domain/deploy
  ([SITE_CONFIGURATION.md](SITE_CONFIGURATION.md)) and build pages from the web style kit + the SEO
  block.
- **Support path**: wire the issue tracker + contact email and the diagnostic-log intake
  ([SUPPORT_AND_FEEDBACK.md](SUPPORT_AND_FEEDBACK.md)).

## 8. Reserve the frozen anchors

- Reserve the overlay's **frozen anchors** (package id / identity / signing key / module path) - unique
  per product, never changed after first ship. Everything else can be reorganized later; these cannot.

## 9. First release dry-run

- Do a full build + pre-release sweep + a *dry-run* of the release operation (no push/upload) to prove
  the pipeline before the first real, one-way release.
