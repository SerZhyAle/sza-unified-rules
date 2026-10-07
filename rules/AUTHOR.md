# Author - who you are collaborating with

The owner profile every agent should load before working, so explanations, defaults, and tone fit the
person actually driving the project. This is the *collaboration* profile; incidental personal-life
details are intentionally left out of this shared/source-of-truth doc. Tell me if you want more or less
here.

## Who

- **Serhii Zhyhunenko (SZA)** - solo owner and sole developer of a portfolio of small products
  (`sza.od.ua`). Wears every hat: architect, implementer, release manager, QA.
- Contact / tooling email: **serzhyale@gmail.com**.

## Technical background - drives how to explain things

- Comes from **SQL, VB.NET, data engineering** (ex-1C developer). **Not** a native
  Android/Kotlin or web developer - most app code is "vibecoded": the owner drives by *intent*, and the
  agent writes the code.
- **Therefore:**
  - Explain platform/framework concepts in **plain terms, and map them to SQL / .NET / data-engineering
    analogues** when it helps. Name a concept before using it; don't assume an idiom is known.
  - Don't dump raw code as an "explanation" - say what it does and why, then show code.
  - **The agent holds the architecture discipline.** Because the code is vibecoded, the owner relies on
    the agent to catch layer/convention/lifecycle violations, not the reverse.
- **Thinks in Windows-desktop metaphors**, not the target platform's: taskbar, tray, Start menu,
  shortcut-with-arguments, gadgets (from a 1C/VB.NET past). When the owner describes UI intent it often
  arrives in that model. **Mirror those analogies back** - they carry real signal - but check each
  against what the target platform actually allows and **name the mismatch explicitly** instead of
  quietly designing around it.

## Language

- **Chat in the owner's language (Russian); code, docs, logs, and commits in international English.**
- **English is the source language for documentation.** Translations render from that source; they are
  never independent specifications.
- **Ukrainian is supported everywhere a product exposes localizable text.** Ship it alongside English and
  Russian in UI, site, README and listing surfaces; do not make Ukrainian a second-class fallback.
- English is weak-but-improving (technical reading is OK). Keep any English the owner must read **short
  and simple**.
- **Text style**: the house standard (`..` not `...`; plain hyphen; `ё`; prose + UI only, never
  code/specs/commands/logs/chat) - one home: [DOCUMENTATION_CONCEPT.md](DOCUMENTATION_CONCEPT.md) §5.

## Portfolio defaults

- **Time zone:** `Europe/Malta` (Central European Time / Central European Summer Time). All human-facing
  project dates and times use local time in that zone, never an unlabelled host-local clock.
- **Date and time:** `YY-MM-DD HH:mm` (for example, `26-10-07 14:35`). A timestamp in a file name is
  `YY-MM-DD_HHm` (for example, `26-10-07_1435`).
- **Currency:** euro. Use the `EUR` ISO code in technical fields and the appropriate localized euro
  presentation in user-facing text.
- **Units:** SI (metric). Preserve a platform, legal, API or user-supplied unit only where its contract
  requires it; convert it for display when useful.
- **Version clock:** new product release streams use `YY.MMDD.HHmm` (for example, `26.1007.1435`). The
  timestamp is generated mechanically in the portfolio time zone. A released stream keeps its established
  version shape, because changing it can break updates; platform-specific channel versions derive from the
  authoritative value.

## Working style

- **Dry, concise. High autonomy.** Run searches/builds/queries/chores without asking; flag blockers up
  front; background long jobs. **No trailing "what I did" summaries** - the diff speaks.
- **Don't ask what the architecture already answers** - research the convention and recommend. Reserve
  questions for real forks (see [AI_USAGE.md](AI_USAGE.md) §1).
- Surface UI ambiguity before implementing. Push back once with evidence, then execute the owner's call.
- Ticket/spec lifecycle and generated catalogs are **sacred**: always go through the tool/CLI, never
  hand-edit the underlying journal.

## Product compass - who the products are *for*

- **Ordinary non-technical people, not power users.** The north-star personas the owner named: a
  grandmother opening her photos from the home PC to show the grandkids; a gym-goer streaming music off
  the home PC during a workout.
- **Implications, treated as defects when violated, not edge cases:**
  - **Zero jargon** in user-visible text (no "SMB share", "mount point", "RTSP", raw stack traces) -
    speak the persona's language ("Computer -> Photos").
  - **Zero mandatory configuration before first success** - defaults that just work; the happy path
    reaches a result with no setup maze.
  - **Every failure states a human next step** ("Computer is off or not on the same network"), never a
    bare error code.
  - **Robust on the real-world path** (weak Wi-Fi, screen lock, headset, dropped connections): graceful,
    no crashes, sane lock-screen controls.

## Priorities

- **Quality wins on conflict.** Primary focus: stability + new features.
- **Hard rule: never ship a release that regresses market/reach** - countries, age ratings, minimum
  platform version, ABI/feature/device coverage. A coverage regression stops a release (the enforcing
  gate: [RELEASE_AND_DISTRIBUTION.md](RELEASE_AND_DISTRIBUTION.md) §3).

See [AI_USAGE.md](AI_USAGE.md) for how these preferences turn into agent behaviour.
