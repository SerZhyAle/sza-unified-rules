# Release ledger - the harness writer

`release-ledger.ps1` keeps one repository's record of what it built and where each version is published. The format is
the `RELEASE-LEDGER` contract of the shared catalog; when each verb runs is
[RELEASE_AND_DISTRIBUTION.md](../../../rules/RELEASE_AND_DISTRIBUTION.md) §10. It never publishes: `probe` and `import`
only read the channels.

## The files

In `paths.releasesDir` of the repository's profile, `docs/releases` by default, tracked in git:

| File | Written by | Holds |
| --- | --- | --- |
| `channels.json` | `init`, then by hand | the packages and the channels each ships to, with the public identity each probe needs |
| `builds.json` | `build` | the last build of each package, flavor and kind |
| `history.jsonl` | `publish`, `confirm`, `probe`, `import` | every publication event, append-only |
| `RELEASES.md` | every write | the human view - a render target, never edited |

## The verbs

| Verb | Does |
| --- | --- |
| `init` | a starter `channels.json` from the stamp's `channels`, the GitHub repository from `origin` and the winget id from the committed manifests; never overwrites |
| `build -Package -Kind release\|test\|debug -Version [-Flavor] [-Artifact] [-Note]` | records the last build of that package, flavor and kind |
| `publish -Key -Version -State [-Ref] [-Url] [-Note] [-Track] [-Rollout] [-At]` | a publication event, `source: release` |
| `confirm` (same arguments) | the same, `source: manual` - a channel no probe can see, confirmed by hand with its URL |
| `show [-Key] [-Json]` | last builds, the live and in-flight version per channel, release builds no channel carries |
| `history [-Key] [-Package] [-Last n] [-Json]` | every event, newest first |
| `render` | rewrites `RELEASES.md` |
| `probe [-Key] [-DryRun]` | reads each channel and records only what differs; an invisible channel is reported `unverified` |
| `import [-Key] [-DryRun]` | backfill from the automatic sources, at the channel's own time where it gives one |

`-RepoRoot <dir>` works on another repository's ledger. Exit codes: 0 done, 1 the ledger could not be read or written,
2 invalid invocation.

## The probes

| Kind | Reads | Needs |
| --- | --- | --- |
| `github` | `gh release list` | `gh` signed in; `repo` or a github.com `origin`; `tagPrefix` (default `v`) |
| `winget` | the `microsoft/winget-pkgs` manifests folder and its open pull requests | `gh`; `id` |
| `msstore` | `msstore submission get <storeId>` - the only Store call the file can make | `msstore` configured; `storeId` |
| `play` | the Play Developer API, one track, through a transient edit that is deleted | `SZA_PLAY_SERVICE_ACCOUNT_JSON` naming a service account key file outside every repository; `id`, `track` |
| `chrome` | the public update service | `id` |
| `edge` | the public product details | `id` (the crx id) |
| `vscode` | the public gallery query | `id` (`publisher.name`) |
| `url` | the page as delivered, no script | `url`; `pattern` with one group, or a version the ledger already knows |
| `manual`, any other | nothing - `confirm` by hand | - |

## The build hook

The last step of a build script, after the artifact exists. A ledger failure is reported and never fails the build:

```powershell
$sza = ((Get-Content "$HOME/.claude/plugins/installed_plugins.json" -Raw | ConvertFrom-Json).plugins.'sza@sza-unified-rules' |
    Sort-Object lastUpdated -Descending | Select-Object -First 1).installPath
& pwsh -NoProfile -File (Join-Path $sza 'tools/harness/releases/release-ledger.ps1') build `
    -Package app -Flavor $flavor -Kind $kind -Version $version -Artifact $artifactPath
if ($LASTEXITCODE -ne 0) { Write-Warning "release ledger not updated (exit $LASTEXITCODE)" }
```

A repository with the task-flow forwarder calls `pwsh -NoProfile -File tools/harness.ps1 releases/release-ledger build ..`
instead.

The fast suite is `tools/tests/release-ledger.tests.ps1` in the canon checkout.
