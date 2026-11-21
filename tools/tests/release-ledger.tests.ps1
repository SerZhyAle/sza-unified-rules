#requires -Version 7.0
<#
.SYNOPSIS
    Fast tests for the release ledger (RELEASE-LEDGER 0.2, canon S0092 and CANONR-0165): tools/harness/releases.

      1. channels.json: a valid declaration reads; an unknown probe kind is kept and handled as manual; a bad key, a
         repeated key and a channel with no package where two are declared are errors (rules 2, 3).
      2. The schema carrier: absent and a higher minor read, a higher major is refused (section 3).
      3. builds.json keeps one row per package, flavor and kind, sorted, and keeps fields it does not know (rules 4, 11).
      4. history.jsonl is appended to, a missing final newline is supplied, and a bad line is skipped with a warning
         naming its number (rule 5).
      5. The fold: the live version is the newest live one, in flight is what is newer than it, the status prefers
         rejected/blocked over submitted, and a withdrawn live version falls back to the earlier live one (rule 7).
      6. Version matching across shapes: a v prefix, the MSIX remap and a Play release name.
      7. Built, not published: a release build no channel carries is listed; one carried in flight is not; a package
         with no channel is not.
      8. The render is deterministic, has its sections and never holds an absolute local path (rules 9, 10).
      9. The probe parsers over recorded channel responses: GitHub, winget, the Store, Play, Chrome, Edge, VS Code
         and a public page - no network.
     10. The CLI end to end with a probe stub: probe appends only what differs, a second probe writes nothing, an
         invalid state is exit 2.
     11. Closed since the last build (S0135): tickets at Implemented written in or after the minute of the newest
         build are counted, an unreadable date counts, no build gives no figure, and a repository with no ledger or
         no build says why.
     12. Empty GitHub probe/import (S0148): New-RlProbeResult keeps an empty [object[]] under StrictMode when
         parsers return nothing, and release-ledger probe/import exit 0 when gh release list returns [].
     13. A Play track reading (CANONR-0165, RELEASE-LEDGER 0.2 rule 12): an edit-based response with completed,
         inProgress, halted, draft and an unknown status keeps the exact track, release name, version codes and rollout,
         and makes no state and no claim; an empty response gives nothing.
     14. A Play lifecycle reading: IN_REVIEW, APPROVED_NOT_PUBLISHED, NOT_APPROVED, PUBLISHED and an unknown value are
         kept as reported, scoped to the track and the version codes, PUBLISHED is not public serving; a missing
         summary is no verdict.
     15. A schema-1 history with legacy Play API rows: the production key keeps its confirmed 1.0 (also against a
         legacy row on 1.0 itself), the tester key shows only its own confirmation, a github channel folds as without
         them, history.jsonl is byte-identical, and the writer's show, the render and the portfolio reader agree.
     16. The CLI over a Play channel: probe and import print readings and write nothing - twice, with an unavailable
         response, with an empty one, and with an adapter that returns an observation anyway.

    Cases 15 and 16 run the CLI in this process (the script's exit ends only the script), so the suite stays inside
    the 5 s line of the fast tier.

    Everything is a throwaway folder; no real repository, no network, pwsh child processes for CLI checks.
    Takes -KeepScratch to leave the throwaway folder for inspection.
#>
[CmdletBinding()]
param([switch]$KeepScratch)

$ErrorActionPreference = 'Stop'
$SourceRoot = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent)
$releases = Join-Path $SourceRoot 'tools/harness/releases'

$run = 0; $passed = 0; $failed = 0
function Assert-That([bool]$Condition, [string]$Reason) { if (-not $Condition) { throw $Reason } }
function Test-Case([string]$Name, [scriptblock]$Body) {
    $script:run++
    Write-Host -NoNewline "CASE  $Name ... "
    try {
        & $Body
        $script:passed++
        Write-Host 'PASS' -ForegroundColor Green
    } catch {
        $script:failed++
        Write-Host 'FAIL' -ForegroundColor Red
        Write-Host "      $($_.Exception.Message)" -ForegroundColor DarkRed
    }
}

$scratch = Join-Path ([System.IO.Path]::GetTempPath()) ('s0092-ledger-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $scratch | Out-Null
$savedNow = $env:SZA_RELEASES_NOW
$savedStub = $env:SZA_RELEASES_PROBE_STUB
$savedPath = $env:PATH

. (Join-Path $releases '_lib.ps1')
. (Join-Path $releases '_probes.ps1')
. (Join-Path $SourceRoot 'tools/harness/portfolio/lib/releases.ps1')

$script:n = 0
function New-Ledger([string]$Channels) {
    $script:n++
    $dir = Join-Path $scratch "l$($script:n)"
    New-Item -ItemType Directory -Path $dir | Out-Null
    if ($Channels) { [IO.File]::WriteAllText((Join-Path $dir 'channels.json'), $Channels) }
    return $dir
}
function Add-Line([string]$Dir, [string]$Line) { [IO.File]::AppendAllText((Join-Path $Dir 'history.jsonl'), $Line + "`n") }
$twoChannels = '{"schema":"1","packages":[{"id":"app"}],"channels":[{"key":"github","channel":"github","repo":"o/r"},{"key":"forum-x","channel":"url","url":"https://f.example/t"}]}'

try {
    Test-Case 'channels.json reads; an unknown kind is manual; bad declarations are errors' {
        $d = New-Ledger '{"packages":[{"id":"app"}],"channels":[{"key":"gh","channel":"github"},{"key":"meta","channel":"meta-horizon","title":"Meta"}]}'
        $c = Read-RlChannels $d
        Assert-That ($c.errors.Count -eq 0) "unexpected errors: $($c.errors -join '; ')"
        Assert-That ($c.channels.Count -eq 2 -and $c.channels[0].package -ceq 'app') 'the single package is not the default'
        Assert-That ($c.channels[1].channel -ceq 'meta-horizon' -and $c.channels[1].kind -ceq 'manual') 'an unknown kind is not kept as manual'
        $bad = New-Ledger '{"packages":[{"id":"a"},{"id":"b"}],"channels":[{"key":"Bad Key","channel":"github","package":"a"},{"key":"x","channel":"github"},{"key":"y","channel":"github","package":"a"},{"key":"y","channel":"edge","package":"a"}]}'
        $e = (Read-RlChannels $bad).errors -join ' | '
        Assert-That ($e -match "Bad Key") 'a bad key is not reported'
        Assert-That ($e -match "'x' names no package and the file declares 2") 'a missing package is not reported'
        Assert-That ($e -match "'y' is declared twice") 'a repeated key is not reported'
    }

    Test-Case 'the schema carrier: absent and 1.1 read, 2 is refused' {
        $d = New-Ledger '{"schema":"1.1","packages":[{"id":"app"}],"channels":[]}'
        Assert-That ((Read-RlChannels $d).exists) '1.1 did not read'
        $d2 = New-Ledger '{"schema":"2","packages":[],"channels":[]}'
        $threw = $false
        try { Read-RlChannels $d2 | Out-Null } catch { $threw = ($_.Exception.Message -match 'schema 1.x') }
        Assert-That $threw 'a higher major was not refused with its reason'
    }

    Test-Case 'builds.json: one row per package, flavor and kind, sorted, unknown fields kept' {
        $d = New-Ledger ''
        $env:SZA_RELEASES_NOW = '2026-11-17T10:00:00+02:00'
        Set-RlBuild -Dir $d -Build ([ordered]@{ package = 'app'; flavor = 'x64'; kind = 'release'; version = '1.0'; builtAt = (Get-RlNow) })
        Set-RlBuild -Dir $d -Build ([ordered]@{ package = 'app'; flavor = 'x64'; kind = 'debug'; version = '1.1'; builtAt = (Get-RlNow) })
        Set-RlBuild -Dir $d -Build ([ordered]@{ package = 'app'; flavor = 'arm64'; kind = 'release'; version = '1.0'; builtAt = (Get-RlNow) })
        $raw = Get-Content (Join-Path $d 'builds.json') -Raw | ConvertFrom-Json -DateKind String
        $raw.builds[0] | Add-Member -NotePropertyName custom -NotePropertyValue 'kept'
        $raw | Add-Member -NotePropertyName extra -NotePropertyValue 7
        [IO.File]::WriteAllText((Join-Path $d 'builds.json'), ($raw | ConvertTo-Json -Depth 8))
        Set-RlBuild -Dir $d -Build ([ordered]@{ package = 'app'; flavor = 'x64'; kind = 'release'; version = '2.0'; builtAt = (Get-RlNow) })
        $b = (Read-RlBuilds $d)
        $rows = @($b.builds)
        Assert-That ($rows.Count -eq 3) "expected 3 rows, got $($rows.Count)"
        Assert-That ((($rows | ForEach-Object { "$($_.flavor)/$($_.kind)" }) -join ',') -ceq 'arm64/release,x64/debug,x64/release') 'the rows are not sorted by package, flavor, kind'
        Assert-That (($rows | Where-Object { $_.flavor -ceq 'x64' -and $_.kind -ceq 'release' }).version -ceq '2.0') 'the release row was not replaced'
        Assert-That ($rows[0].custom -ceq 'kept' -and $b.raw.extra -eq 7) 'a field the writer does not own was dropped'
        Assert-That ([string]$rows[0].builtAt -ceq '2026-11-17T10:00:00+02:00') 'builtAt was reformatted'
    }

    Test-Case 'history.jsonl: appended, newline supplied, a bad line skipped by number' {
        $d = New-Ledger $twoChannels
        [IO.File]::WriteAllText((Join-Path $d 'history.jsonl'), '{"at":"2026-11-01T10:00:00+02:00","key":"github","package":"app","version":"1.0","state":"live","source":"import"}')
        Add-RlEvents -Dir $d -Events @(New-RlEvent -Key github -Package app -Version '1.1' -State submitted -Source release -At '2026-11-02T10:00:00+02:00')
        Add-Line $d 'not json'
        Add-Line $d '{"at":"2026-11-03T10:00:00+02:00","key":"github","package":"app","state":"live","source":"manual"}'
        $h = Read-RlHistory $d
        Assert-That ($h.events.Count -eq 2) "expected 2 events, got $($h.events.Count)"
        Assert-That (($h.warnings -join ' ') -match 'line 3: does not parse' -and ($h.warnings -join ' ') -match 'line 4: lacks version') "warnings: $($h.warnings -join '; ')"
        Assert-That (-not (Test-Path (Join-Path $d '.release-ledger.lock'))) 'the lock file was left behind'
    }

    Test-Case 'the fold: live, in flight, status precedence, a withdrawn version' {
        $d = New-Ledger $twoChannels
        Add-Line $d '{"at":"2026-11-01T10:00:00+02:00","key":"github","package":"app","version":"1.0","state":"live","source":"import"}'
        Add-Line $d '{"at":"2026-11-05T10:00:00+02:00","key":"github","package":"app","version":"1.2","state":"live","source":"release"}'
        Add-Line $d '{"at":"2026-11-06T10:00:00+02:00","key":"github","package":"app","version":"1.3","state":"submitted","source":"release"}'
        Add-Line $d '{"at":"2026-11-06T11:00:00+02:00","key":"github","package":"app","version":"1.4","state":"rejected","source":"probe"}'
        Add-Line $d '{"at":"2026-11-04T10:00:00+02:00","key":"github","package":"app","version":"0.9","state":"submitted","source":"release"}'
        $s = (Get-RlSnapshot $d).channels | Where-Object key -ceq 'github'
        Assert-That ($s.live.version -ceq '1.2') "live is $($s.live.version)"
        Assert-That ((($s.inFlight | ForEach-Object version) -join ',') -ceq '1.4,1.3') "in flight is $(($s.inFlight | ForEach-Object version) -join ',')"
        Assert-That ($s.status -ceq 'rejected') "status is $($s.status)"
        Add-Line $d '{"at":"2026-11-07T10:00:00+02:00","key":"github","package":"app","version":"1.2","state":"withdrawn","source":"manual"}'
        $s2 = (Get-RlSnapshot $d).channels | Where-Object key -ceq 'github'
        Assert-That ($s2.live.version -ceq '1.0') "after the withdrawal live is $($s2.live.version)"
    }

    Test-Case 'version matching across shapes' {
        Assert-That (Test-RlVersionMatch 'v26.1117.1450' '26.1117.1450') 'a v prefix'
        Assert-That (Test-RlVersionMatch '26.0723.0959' '26.723.959.0') 'the MSIX remap'
        Assert-That (Test-RlVersionMatch '2.61.1117.1351 (261117135)' '2.61.1117.1351') 'a Play release name'
        Assert-That (-not (Test-RlVersionMatch '26.1117.1450' '26.1117.1451')) 'two versions matched'
    }

    Test-Case 'built, not published' {
        $d = New-Ledger '{"packages":[{"id":"app"},{"id":"tool"}],"channels":[{"key":"github","channel":"github","package":"app"}]}'
        $env:SZA_RELEASES_NOW = '2026-11-10T10:00:00+02:00'
        Set-RlBuild -Dir $d -Build ([ordered]@{ package = 'app'; flavor = 'x64'; kind = 'release'; version = '2.0'; builtAt = '2026-11-07T10:00:00+02:00' })
        Set-RlBuild -Dir $d -Build ([ordered]@{ package = 'app'; flavor = 'x64'; kind = 'debug'; version = '2.1'; builtAt = '2026-11-07T10:00:00+02:00' })
        Set-RlBuild -Dir $d -Build ([ordered]@{ package = 'tool'; flavor = 'default'; kind = 'release'; version = '5'; builtAt = '2026-11-07T10:00:00+02:00' })
        $u = @((Get-RlSnapshot $d).unpublished)
        Assert-That ($u.Count -eq 1 -and $u[0].version -ceq '2.0' -and $u[0].days -eq 3) "unpublished: $(($u | ForEach-Object { "$($_.package) $($_.version) $($_.days)" }) -join '; ')"
        Add-Line $d '{"at":"2026-11-08T10:00:00+02:00","key":"github","package":"app","version":"v2.0","state":"submitted","source":"release"}'
        Assert-That (@((Get-RlSnapshot $d).unpublished).Count -eq 0) 'a build carried in flight is still listed'
    }

    Test-Case 'closed since the last build: counted from ticket rows, no figure without a build' {
        # No offset on purpose: builtAt and a ticket's updated are both read as local time, so this holds in any zone.
        $builds = @(
            [pscustomobject]@{ package = 'app'; flavor = 'x64'; kind = 'release'; version = '1.0'; builtAt = '2026-11-10T12:00:00' },
            [pscustomobject]@{ package = 'app'; flavor = 'x64'; kind = 'debug'; version = '1.1'; builtAt = '2026-11-12T12:00:40' },
            [pscustomobject]@{ package = 'tool'; flavor = 'default'; kind = 'release'; version = '5'; builtAt = 'not a date' }
        )
        $tickets = @(
            [pscustomobject]@{ repo = 'a'; id = 'S1'; status = 'Implemented'; updated = '2026-11-12 11:59' },
            [pscustomobject]@{ repo = 'a'; id = 'S2'; status = 'Implemented'; updated = '2026-11-12 12:00' },
            [pscustomobject]@{ repo = 'a'; id = 'S3'; status = 'Implemented'; updated = '' },
            [pscustomobject]@{ repo = 'a'; id = 'S4'; status = 'Verified'; updated = '2026-11-13 10:00' },
            [pscustomobject]@{ repo = 'c'; id = 'S1'; status = 'Implemented'; updated = '2026-11-13 10:00' }
        )
        $f = Get-RlClosedSinceBuild -Builds $builds -Tickets @($tickets | Where-Object { $_.repo -ceq 'a' })
        Assert-That ($f.lastBuiltAt -ceq '2026-11-12T12:00:40' -and $f.atStatus -eq 3 -and $f.sinceBuild -eq 2) "newest build of any kind, its minute counts, 2 of 3: $($f.lastBuiltAt) $($f.sinceBuild) of $($f.atStatus)"
        $n = Get-RlClosedSinceBuild -Builds @() -Tickets $tickets
        Assert-That ($n.lastBuiltAt -ceq '' -and $null -eq $n.sinceBuild -and $n.atStatus -eq 4) 'no build must give no figure, never zero'
        $rel = [pscustomobject]@{ repos = @(
                [pscustomobject]@{ key = 'a'; hasLedger = $true; error = $null; builds = $builds },
                [pscustomobject]@{ key = 'b'; hasLedger = $false; error = $null; builds = @() },
                [pscustomobject]@{ key = 'c'; hasLedger = $true; error = $null; builds = @() },
                [pscustomobject]@{ key = 'e'; hasLedger = $true; error = $null; builds = $builds }
            ) }
        $c = Get-PqClosedUnbuilt -Releases $rel -Tickets $tickets -Skipped @('e - boom')
        Assert-That ($c.a.available -and $c.a.sinceBuild -eq 2 -and $c.a.implemented -eq 3) "repository a: $($c.a.sinceBuild) of $($c.a.implemented)"
        Assert-That (-not $c.b.available -and $c.b.why -ceq 'no release ledger') "repository b: $($c.b.why)"
        Assert-That (-not $c.c.available -and $c.c.why -ceq 'no build recorded' -and $c.c.implemented -eq 1 -and $null -eq $c.c.sinceBuild) "repository c: $($c.c.why)"
        Assert-That (-not $c.e.available -and $c.e.why -ceq 'ticket ledger not read') "repository e: $($c.e.why)"
    }

    Test-Case 'the render is deterministic, sectioned and holds no local path' {
        $d = New-Ledger $twoChannels
        Set-RlBuild -Dir $d -Build ([ordered]@{ package = 'app'; flavor = 'default'; kind = 'release'; version = '1.0'; builtAt = '2026-11-07T10:00:00+02:00'; artifact = 'dist/app.zip' })
        Add-Line $d '{"at":"2026-11-08T10:00:00+02:00","key":"github","package":"app","version":"1.0","state":"live","source":"release","ref":"v1.0","url":"https://github.com/o/r/releases/tag/v1.0"}'
        Assert-That (Write-RlRender $d) 'the first render wrote nothing'
        Assert-That (-not (Write-RlRender $d)) 'a second render with no change rewrote the file'
        $t = Get-Content (Join-Path $d 'RELEASES.md') -Raw
        foreach ($h in '# Releases', '## Channels', '## Last builds', '## History', 'Do not edit') { Assert-That ($t.Contains($h)) "missing '$h'" }
        Assert-That ($t.Contains('[v1.0](https://github.com/o/r/releases/tag/v1.0)')) 'the ref link is missing'
        Assert-That (-not $t.Contains($scratch)) 'the render holds the local scratch path'
        Assert-That ((ConvertTo-RlRepoPath -RepoRoot $scratch -Path 'C:\elsewhere\x.apk') -ceq 'x.apk') 'a path outside the repository is not cut to its name'
    }

    Test-Case 'the probe parsers over recorded responses' {
        $gh = '[{"tagName":"v2.0","isDraft":false,"isPrerelease":false,"publishedAt":"2026-11-02T10:00:00Z","createdAt":"2026-11-02T09:00:00Z"},{"tagName":"v2.1","isDraft":true,"isPrerelease":false,"publishedAt":"0001-01-01T00:00:00Z","createdAt":"2026-11-03T09:00:00Z"},{"tagName":"ext-cws-v2.0","isDraft":false,"isPrerelease":false,"publishedAt":"2026-11-02T10:00:00Z","createdAt":"2026-11-02T10:00:00Z"}]'
        $g = @(ConvertFrom-RlGithubReleases -Json $gh -Repo 'o/r')
        Assert-That ($g.Count -eq 2 -and $g[0].state -ceq 'live' -and $g[1].state -ceq 'pending' -and $g[1].at -ceq '2026-11-03T09:00:00Z') 'GitHub: drafts, prefixes or times'
        $wv = @(ConvertFrom-RlWingetVersions -Json '[{"name":"26.1113.22","type":"dir"},{"name":"26.1117.1450","type":"dir"},{"name":"Nested","type":"dir"},{"name":"x.yaml","type":"file"}]' -Id 'Pub.App')
        Assert-That ($wv.Count -eq 2 -and $wv[-1].version -ceq '26.1117.1450' -and $wv[0].url -match 'manifests/p/Pub/App/26.1113.22') 'winget versions'
        $wp = @(ConvertFrom-RlWingetPulls -Json '[{"number":5,"title":"New version: Pub.App version 26.1118.0100","url":"https://github.com/microsoft/winget-pkgs/pull/5"},{"number":6,"title":"New version: Pub.AppOther version 1.0","url":"u"}]' -Id 'Pub.App')
        Assert-That ($wp.Count -eq 1 -and $wp[0].version -ceq '26.1118.0100' -and $wp[0].ref -ceq 'PR#5' -and $wp[0].state -ceq 'submitted') 'winget pulls'
        $live = ConvertFrom-RlStoreSubmission -StoreId '9ABCDEFGHJKL' -Raw "Could not find a pending submission. Found the last published submission.`n{""Id"":""1"",""Status"":""Published"",""FriendlyName"":""Submission 3"",""ApplicationPackages"":[{""Version"":""26.1117.1450.0""},{""Version"":""26.1113.22.0""}]}"
        Assert-That ($live.ok -and $live.observed[0].version -ceq '26.1117.1450.0' -and $live.observed[0].state -ceq 'live') 'Store live'
        $cert = ConvertFrom-RlStoreSubmission -StoreId '9ABCDEFGHJKL' -Raw '{"Id":"2","Status":"CertificationFailed","ApplicationPackages":[{"Version":"26.1118.1.0"}]}'
        Assert-That ($cert.observed[0].state -ceq 'rejected') 'Store failed'
        $none = ConvertFrom-RlStoreSubmission -StoreId '9ABCDEFGHJKL' -Raw 'The app does not have a published submission.'
        Assert-That ($none.ok -and $none.observed.Count -eq 0) 'Store with no live submission'
        $track = '{"track":"production","releases":[{"name":"2.61.1117","versionCodes":["261117"],"status":"inProgress","userFraction":0.2},{"name":"2.60.1","versionCodes":["260001"],"status":"completed"},{"versionCodes":["9"],"status":"halted"}]}' | ConvertFrom-Json
        $p = @(ConvertFrom-RlPlayTrack -Track $track -TrackName 'production' -AppId 'com.x')
        Assert-That ($p.Count -eq 3 -and $p[0].rollout -eq 0.2 -and $p[1].rollout -eq $null -and $p[2].release -ceq '' -and ($p[2].versionCodes -join ',') -ceq '9') 'Play track readings'
        Assert-That ($null -eq $p[0].PSObject.Properties['state'] -and $p[0].claim -ceq 'none') 'a Play track reading carries a state or a claim'
        $c = ConvertFrom-RlChromeUpdate -Id ('a' * 32) -Xml '<gupdate><app appid="x"><updatecheck codebase="u" version="26.1117.1543" status="ok"/></app></gupdate>'
        Assert-That ($c.ok -and $c.observed[0].version -ceq '26.1117.1543') 'Chrome'
        Assert-That (-not (ConvertFrom-RlChromeUpdate -Id ('a' * 32) -Xml '<updatecheck status="error-unknownApplication"/>').ok) 'Chrome unknown is not unverified'
        $e = ConvertFrom-RlEdgeDetails -Id ('b' * 32) -Json '{"name":"x","version":"26.1021.41"}'
        Assert-That ($e.ok -and $e.observed[0].version -ceq '26.1021.41') 'Edge'
        $vs = '{"results":[{"extensions":[{"versions":[{"version":"1.2.0","lastUpdated":"2026-11-06T14:02:26.87Z"},{"version":"1.1.0","lastUpdated":"2026-10-01T10:00:00Z"}]}]}]}' | ConvertFrom-Json -DateKind String
        Assert-That ((ConvertFrom-RlVscodeQuery -Response $vs -Id 'p.n').observed.Count -eq 1 -and (ConvertFrom-RlVscodeQuery -Response $vs -Id 'p.n' -All).observed.Count -eq 2) 'VS Code newest and all'
        $pg = ConvertFrom-RlPublicPage -Text '<p>Version 3.4.5 is out</p>' -Pattern 'Version (\d+\.\d+\.\d+)' -Url 'https://f.example'
        Assert-That ($pg.ok -and $pg.observed[0].version -ceq '3.4.5') 'a public page with a pattern'
        Assert-That ((ConvertFrom-RlPublicPage -Text 'see 2.0 here' -Candidates @('1.0', '2.0')).observed[0].version -ceq '2.0') 'a public page by candidates'
        Assert-That (-not (ConvertFrom-RlPublicPage -Text '<div id=app></div>' -Candidates @('2.0')).ok) 'a script-only page is not unverified'
    }

    Test-Case 'the CLI: probe appends only what differs, twice is a no-op, a bad state is exit 2' {
        $repo = Join-Path $scratch 'repo'
        New-Item -ItemType Directory -Path (Join-Path $repo 'docs/releases') -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $repo 'docs/releases/channels.json'), $twoChannels)
        Add-Line (Join-Path $repo 'docs/releases') '{"at":"2026-11-01T10:00:00+02:00","key":"github","package":"app","version":"1.0","state":"live","source":"release"}'
        Add-Line (Join-Path $repo 'docs/releases') '{"at":"2026-11-02T10:00:00+02:00","key":"forum-x","package":"app","version":"1.0","state":"submitted","source":"manual"}'
        $stub = Join-Path $scratch 'stub.json'
        [IO.File]::WriteAllText($stub, '{"github":{"ok":true,"observed":[{"version":"1.0","state":"live"},{"version":"1.1","state":"pending"}]},"forum-x":{"ok":true,"observed":[{"version":"v1.0","state":"live"}]}}')
        $env:SZA_RELEASES_PROBE_STUB = $stub
        $env:SZA_RELEASES_NOW = '2026-11-10T10:00:00+02:00'
        $rl = Join-Path $releases 'release-ledger.ps1'
        $out1 = & pwsh -NoProfile -File $rl probe -RepoRoot $repo 2>&1
        Assert-That ($LASTEXITCODE -eq 0) "probe exit $LASTEXITCODE`n$($out1 -join "`n")"
        $h = @(Get-Content (Join-Path $repo 'docs/releases/history.jsonl') | Where-Object { $_ })
        Assert-That ($h.Count -eq 4) "expected 4 rows after the probe, got $($h.Count)"
        $forum = $h[-1] | ConvertFrom-Json -DateKind String
        Assert-That ($forum.key -ceq 'forum-x' -and $forum.version -ceq '1.0' -and $forum.state -ceq 'live' -and $forum.source -ceq 'probe' -and $forum.note -match 'channel shows v1.0') "the forum row is $($h[-1])"
        $out2 = & pwsh -NoProfile -File $rl probe -RepoRoot $repo 2>&1
        Assert-That (@(Get-Content (Join-Path $repo 'docs/releases/history.jsonl') | Where-Object { $_ }).Count -eq 4) "a second probe wrote rows`n$($out2 -join "`n")"
        Assert-That (Test-Path (Join-Path $repo 'docs/releases/RELEASES.md')) 'RELEASES.md was not rendered'
        & pwsh -NoProfile -File $rl publish -RepoRoot $repo -Key github -Version 1.2 -State done 2>$null | Out-Null
        Assert-That ($LASTEXITCODE -eq 2) "an invalid state gave exit $LASTEXITCODE"
    }

    Test-Case 'empty GitHub probe and import keep observed as an array under StrictMode' {
        & {
            Set-StrictMode -Version Latest
            $rNull = New-RlProbeResult -Ok $true -Observed $null
            Assert-That ($null -ne $rNull.observed -and $rNull.observed.Count -eq 0) 'New-RlProbeResult -Observed $null returned null'
            $rGh = New-RlProbeResult -Ok $true -Observed (ConvertFrom-RlGithubReleases -Json '[]' -Repo 'o/r')
            Assert-That ($null -ne $rGh.observed -and $rGh.observed.Count -eq 0) 'empty GitHub releases returned null observed'
            $rWp = New-RlProbeResult -Ok $true -Observed (ConvertFrom-RlWingetPulls -Json '[]' -Id 'Pub.App')
            Assert-That ($null -ne $rWp.observed -and $rWp.observed.Count -eq 0) 'empty winget pulls returned null observed'
            $rPlay = New-RlProbeResult -Ok $true -Diagnostics (ConvertFrom-RlPlayTrack -Track ([pscustomobject]@{}) -TrackName 'production' -AppId 'com.x')
            Assert-That ($null -ne $rPlay.observed -and $rPlay.observed.Count -eq 0 -and $null -ne $rPlay.diagnostics -and $rPlay.diagnostics.Count -eq 0) 'empty Play track returned null observed or diagnostics'
            $rLc = New-RlProbeResult -Ok $true -Diagnostics (ConvertFrom-RlPlayLifecycle -Response ([pscustomobject]@{}) -TrackName 'production')
            Assert-That ($null -ne $rLc.diagnostics -and $rLc.diagnostics.Count -eq 0) 'an empty lifecycle response returned null diagnostics'
        }
        $emptyRepo = Join-Path $scratch 'empty-gh'
        New-Item -ItemType Directory -Path (Join-Path $emptyRepo 'docs/releases') -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $emptyRepo 'docs/releases/channels.json'), '{"schema":"1","packages":[{"id":"app"}],"channels":[{"key":"github","channel":"github","repo":"o/r"}]}')
        $stubBin = Join-Path $scratch 'gh-stub-bin'
        New-Item -ItemType Directory -Path $stubBin -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $stubBin 'gh.cmd'), "@echo off`r`necho []`r`nexit /b 0`r`n")
        $env:SZA_RELEASES_PROBE_STUB = ''
        $env:PATH = "$stubBin;$savedPath"
        $rl = Join-Path $releases 'release-ledger.ps1'
        $outProbe = & pwsh -NoProfile -File $rl probe -RepoRoot $emptyRepo -Key github 2>&1
        Assert-That ($LASTEXITCODE -eq 0) "probe exit $LASTEXITCODE`n$($outProbe -join "`n")"
        Assert-That ((@($outProbe) -join "`n") -match 'seen\s+github\s+nothing published') "unexpected probe output: $($outProbe -join "`n")"
        $outImport = & pwsh -NoProfile -File $rl import -RepoRoot $emptyRepo -Key github 2>&1
        Assert-That ($LASTEXITCODE -eq 0) "import exit $LASTEXITCODE`n$($outImport -join "`n")"
        Assert-That ((@($outImport) -join "`n") -match 'seen\s+github\s+nothing published') "unexpected import output: $($outImport -join "`n")"
        Assert-That (-not (Test-Path (Join-Path $emptyRepo 'docs/releases/history.jsonl'))) 'empty probe/import wrote history.jsonl'
    }

    Test-Case 'a Play track reading keeps the exact track, artifacts and rollout and claims nothing' {
        $track = '{"track":"production","releases":[{"name":"2.0","versionCodes":["200"],"status":"completed"},{"name":"3.0","versionCodes":["300","301"],"status":"inProgress","userFraction":0.2},{"name":"4.0","versionCodes":["400"],"status":"halted","userFraction":0.5},{"versionCodes":["500"],"status":"draft"},{"name":"6.0","versionCodes":["600"],"status":"statusUnspecified"},{"status":"completed"}]}' | ConvertFrom-Json
        $p = @(ConvertFrom-RlPlayTrack -Track $track -TrackName 'production' -AppId 'com.x')
        Assert-That ($p.Count -eq 5) "expected 5 readings (a release with no name and no code is skipped), got $($p.Count)"
        foreach ($r in $p) {
            Assert-That ($r.track -ceq 'production' -and $r.claim -ceq 'none' -and $r.kind -ceq 'play-track') "a reading lost its track or carries a claim: $($r | ConvertTo-Json -Compress)"
            Assert-That ($null -eq $r.PSObject.Properties['state'] -and $null -eq $r.PSObject.Properties['version']) 'a reading carries a state or a version, which would make it an observation'
        }
        Assert-That (($p | ForEach-Object status) -join ',' -ceq 'completed,inProgress,halted,draft,statusUnspecified') "statuses: $(($p | ForEach-Object status) -join ',')"
        Assert-That (($p[1].versionCodes -join ',') -ceq '300,301' -and $p[1].rollout -eq 0.2 -and $p[2].rollout -eq 0.5 -and $null -eq $p[0].rollout) 'artifact ids or rollout details were not kept'
        Assert-That ($p[3].release -ceq '' -and ($p[3].versionCodes -join ',') -ceq '500') 'a release known by its code only lost it'
        $res = New-RlProbeResult -Ok $true -Diagnostics $p
        Assert-That ($res.observed.Count -eq 0 -and $res.diagnostics.Count -eq 5) 'the readings became observations'
        $line = Format-RlProbeDiagnostic -Key 'play' -Diagnostic $p[1]
        Assert-That ($line -match "track production, release '3.0', status inProgress, versionCodes 300,301, rollout 0.2" -and $line -match 'no serving, withdrawal or review claim') "the printed line: $line"
        Assert-That (@(ConvertFrom-RlPlayTrack -Track ([pscustomobject]@{}) -TrackName 'production' -AppId 'com.x').Count -eq 0) 'an empty response gave readings'
        Assert-That (@(ConvertFrom-RlPlayTrack -Track ('{"track":"production"}' | ConvertFrom-Json) -TrackName 'production' -AppId 'com.x').Count -eq 0) 'a track with no releases gave readings'
    }

    Test-Case 'a Play lifecycle reading is scoped to its track and artifacts and is no serving or verdict' {
        $lc = '{"releases":[{"releaseName":"2.0","track":"production","activeArtifacts":[{"versionCode":200}],"releaseLifecycleState":"RELEASE_LIFECYCLE_STATE_IN_REVIEW"},{"releaseName":"3.0","track":"production","activeArtifacts":[{"versionCode":300},{"versionCode":301}],"releaseLifecycleState":"RELEASE_LIFECYCLE_STATE_APPROVED_NOT_PUBLISHED"},{"releaseName":"4.0","activeArtifacts":[{"versionCode":400}],"releaseLifecycleState":"RELEASE_LIFECYCLE_STATE_NOT_APPROVED"},{"releaseName":"5.0","track":"internal","activeArtifacts":[{"versionCode":500}],"releaseLifecycleState":"RELEASE_LIFECYCLE_STATE_PUBLISHED"},{"releaseName":"6.0","activeArtifacts":[{"versionCode":600}],"releaseLifecycleState":"RELEASE_LIFECYCLE_STATE_SOMETHING_NEW"}]}' | ConvertFrom-Json
        $l = @(ConvertFrom-RlPlayLifecycle -Response $lc -TrackName 'production' -AppId 'com.x')
        Assert-That ($l.Count -eq 5) "expected 5 readings, got $($l.Count)"
        Assert-That ((($l | ForEach-Object lifecycle) -join ',') -ceq 'IN_REVIEW,APPROVED_NOT_PUBLISHED,NOT_APPROVED,PUBLISHED,SOMETHING_NEW') "lifecycles: $(($l | ForEach-Object lifecycle) -join ',')"
        Assert-That ((($l | ForEach-Object known) -join ',') -ceq 'True,True,True,True,False') 'the unknown value was read as known, or a known one was not'
        Assert-That ((($l | ForEach-Object track) -join ',') -ceq 'production,production,production,internal,production') "tracks: $(($l | ForEach-Object track) -join ',')"
        Assert-That (($l[1].versionCodes -join ',') -ceq '300,301' -and $l[3].versionCodes[0] -ceq '500') 'artifact version codes were not read as strings'
        foreach ($r in $l) { Assert-That ($r.claim -ceq 'none' -and $null -eq $r.PSObject.Properties['state']) 'a lifecycle reading carries a claim' }
        $pub = Format-RlProbeDiagnostic -Key 'play' -Diagnostic $l[3]
        Assert-That ($pub -match 'lifecycle PUBLISHED' -and $pub -match 'not proof of public serving' -and $pub -match 'not an app-wide review verdict' -and $pub -match 'scoped to this track') "PUBLISHED line: $pub"
        Assert-That ((Format-RlProbeDiagnostic -Key 'play' -Diagnostic $l[4]) -match 'lifecycle SOMETHING_NEW \(unrecognised\)') 'an unknown lifecycle was not marked unrecognised'
        Assert-That (@(ConvertFrom-RlPlayLifecycle -Response ([pscustomobject]@{}) -TrackName 'production').Count -eq 0 -and @(ConvertFrom-RlPlayLifecycle -Response $null -TrackName 'production').Count -eq 0) 'a missing summary gave readings'
        Assert-That ((Format-RlProbeDiagnostic -Key 'play' -Diagnostic (New-RlPlayGap -Track 'production' -What 'release lifecycle' -Reason 'no release is listed for the track')) -match 'no verdict, positive or negative') 'a gap was printed as a verdict'
        Assert-That ((New-RlProbeResult -Ok $true -Diagnostics $l).observed.Count -eq 0) 'a lifecycle reading became an observation'
    }

    # The registry library is not loaded here; the two helpers Get-PqReleases needs are replaced by their plain form.
    function Get-PqValue($Object, [string]$Name, $Default = $null) { $p = $Object.PSObject.Properties[$Name]; if ($null -eq $p) { return $Default }; return $p.Value }
    function Get-PqRepoOrder($Registry) { $i = 0; @(foreach ($r in @($Registry.repos)) { [pscustomobject]@{ key = [string]$r.key; rank = 100; index = $i }; $i++ }) }
    $rlCli = Join-Path $releases 'release-ledger.ps1'
    function Invoke-RlCli([hashtable]$Arguments) {
        $out = & $rlCli @Arguments 2>&1
        return [pscustomobject]@{ code = $LASTEXITCODE; text = (@($out | ForEach-Object { "$_" }) -join "`n") }
    }
    function Get-FileSha([string]$Path) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }

    Test-Case 'schema-1 history with legacy Play API rows: the publication view keeps what was confirmed' {
        $channels = '{"schema":"1","packages":[{"id":"app"}],"channels":[{"key":"play","channel":"play","id":"com.x","track":"production"},{"key":"play-internal","channel":"play","id":"com.x","track":"internal"},{"key":"github","channel":"github","repo":"o/r"}]}'
        $githubRows = @(
            '{"at":"2026-11-01T10:00:00+02:00","key":"github","package":"app","version":"9.0","state":"live","source":"release"}',
            '{"at":"2026-11-02T10:00:00+02:00","key":"github","package":"app","version":"9.1","state":"submitted","source":"probe","note":"Play status completed"}'
        )
        $playRows = @(
            '{"at":"2026-11-01T10:00:00+02:00","key":"play","package":"app","version":"1.0","state":"live","source":"manual","url":"https://play.google.com/store/apps/details?id=com.x"}',
            '{"at":"2026-11-02T10:00:00+02:00","key":"play","package":"app","version":"2.0","state":"live","source":"probe","track":"production","note":"Play status completed, versionCodes 20"}',
            '{"at":"2026-11-03T10:00:00+02:00","key":"play","package":"app","version":"3.0","state":"live","source":"probe","track":"production","rollout":0.2,"note":"Play status inProgress, versionCodes 30"}',
            '{"at":"2026-11-04T10:00:00+02:00","key":"play","package":"app","version":"4.0","state":"submitted","source":"import","track":"production","note":"channel shows 4.0 (40); Play status statusUnspecified, versionCodes 40"}',
            '{"at":"2026-11-05T10:00:00+02:00","key":"play","package":"app","version":"1.0","state":"withdrawn","source":"probe","track":"production","note":"Play status halted, versionCodes 10"}'
        )
        $testerRows = @(
            '{"at":"2026-11-06T10:00:00+02:00","key":"play-internal","package":"app","version":"1.5","state":"live","source":"manual","track":"internal","note":"installed from the internal testing link"}',
            '{"at":"2026-11-07T10:00:00+02:00","key":"play-internal","package":"app","version":"1.6","state":"live","source":"probe","track":"internal","note":"Play status completed, versionCodes 16"}',
            '{"at":"2026-11-08T10:00:00+02:00","key":"play-internal","package":"app","version":"1.7","state":"submitted","source":"release","track":"internal","note":"Play status completed"}'
        )
        $repo = Join-Path $scratch 'legacy-repo'
        $rd = Join-Path $repo 'docs/releases'
        New-Item -ItemType Directory -Path $rd -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $rd 'channels.json'), $channels)
        foreach ($line in @($githubRows + $playRows + $testerRows)) { Add-Line $rd $line }
        $histPath = Join-Path $rd 'history.jsonl'
        $before = Get-FileSha $histPath

        $snap = Get-RlSnapshot $rd
        $play = @($snap.channels | Where-Object key -ceq 'play')[0]
        Assert-That ($play.live.version -ceq '1.0' -and $play.status -ceq 'live' -and @($play.inFlight).Count -eq 0) "production: live $($play.live.version), status $($play.status), in flight $(@($play.inFlight).Count)"
        Assert-That ($play.legacyApi -eq 4 -and $play.events -eq 1 -and -not $play.versions.Contains('2.0') -and -not $play.versions.Contains('1.5')) "production counts: legacy $($play.legacyApi), events $($play.events)"
        $tester = @($snap.channels | Where-Object key -ceq 'play-internal')[0]
        Assert-That ($tester.live.version -ceq '1.5' -and (($tester.inFlight | ForEach-Object version) -join ',') -ceq '1.7' -and $tester.legacyApi -eq 1) "tester: live $($tester.live.version), in flight $(($tester.inFlight | ForEach-Object version) -join ','), legacy $($tester.legacyApi)"
        $gh = @($snap.channels | Where-Object key -ceq 'github')[0]
        $alone = New-Ledger $channels
        foreach ($line in $githubRows) { Add-Line $alone $line }
        $ghAlone = @((Get-RlSnapshot $alone).channels | Where-Object key -ceq 'github')[0]
        Assert-That ($gh.legacyApi -eq 0 -and $gh.live.version -ceq '9.0' -and (($gh.inFlight | ForEach-Object version) -join ',') -ceq '9.1') 'a github row with the Play note text was not counted'
        Assert-That (($gh | ConvertTo-Json -Depth 8) -ceq ($ghAlone | ConvertTo-Json -Depth 8)) "another channel's fold changed"
        Assert-That ((Read-RlHistory $rd).events.Count -eq 10 -and @((Read-RlHistory $rd).events | Where-Object { [string]$_.event.key -ceq 'play' }).Count -eq 5) 'raw history lost rows'

        Assert-That (Write-RlRender $rd) 'the render wrote nothing'
        $md = Get-Content (Join-Path $rd 'RELEASES.md') -Raw
        Assert-That ($md -match '(?m)^\| app \| play \| play \| 1\.0 \| 2026-11-01 \| - \|') 'the rendered channel row does not show the confirmed 1.0'
        Assert-That ([regex]::Matches($md, [regex]::Escape('not counted (legacy Play API reading)')).Count -eq 5) 'the rendered history does not mark exactly the five legacy rows'

        $show = (Invoke-RlCli @{ Verb = 'show'; RepoRoot = $repo; Json = $true })
        Assert-That ($show.code -eq 0) "show exit $($show.code)`n$($show.text)"
        $showPlay = @(($show.text | ConvertFrom-Json).channels | Where-Object key -ceq 'play')[0]
        Assert-That ($showPlay.live.version -ceq '1.0' -and $showPlay.legacyApi -eq 4) 'the CLI show -Json does not agree with the fold'
        Assert-That ((Invoke-RlCli @{ Verb = 'show'; RepoRoot = $repo }).text -match '4 legacy Play API row\(s\) not counted') 'the CLI show text does not say that rows are not counted'
        $hist = (Invoke-RlCli @{ Verb = 'history'; RepoRoot = $repo; Key = 'play'; Json = $true }).text | ConvertFrom-Json
        Assert-That (@($hist).Count -eq 5 -and (@($hist | Where-Object { $_.source -ceq 'probe' -or $_.source -ceq 'import' }).Count -eq 4)) 'the CLI history is not the raw history'

        $reg = [pscustomobject]@{ repos = @([pscustomobject]@{ key = 'legacy'; path = $repo }) }
        $pq = (Get-PqReleases $reg).repos[0]
        $pqPlay = @($pq.channels | Where-Object key -ceq 'play')[0]
        Assert-That ($pq.hasLedger -and $pqPlay.live.version -ceq '1.0' -and $pqPlay.legacyApi -eq 4) 'the portfolio reader does not agree with the fold'
        Assert-That ((Format-PqReleaseChannel $pqPlay) -match 'live 1\.0.*4 legacy Play API row\(s\) not counted') 'the portfolio line does not say that rows are not counted'

        Assert-That ((Get-FileSha $histPath) -ceq $before) 'history.jsonl changed while it was only read'
    }

    Test-Case 'the CLI over a Play channel: probe and import print readings and write nothing' {
        $repo = Join-Path $scratch 'play-repo'
        $rd = Join-Path $repo 'docs/releases'
        New-Item -ItemType Directory -Path $rd -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $rd 'channels.json'), '{"schema":"1","packages":[{"id":"app"}],"channels":[{"key":"play","channel":"play","id":"com.x","track":"production"}]}')
        Add-Line $rd '{"at":"2026-11-01T10:00:00+02:00","key":"play","package":"app","version":"1.0","state":"live","source":"manual"}'
        Add-Line $rd '{"at":"2026-11-02T10:00:00+02:00","key":"play","package":"app","version":"2.0","state":"live","source":"probe","note":"Play status completed, versionCodes 20"}'
        $histPath = Join-Path $rd 'history.jsonl'
        $h0 = Get-FileSha $histPath
        $stub = Join-Path $scratch 'play-stub.json'
        $env:SZA_RELEASES_PROBE_STUB = $stub
        $env:SZA_RELEASES_NOW = '2026-11-10T10:00:00+02:00'

        [IO.File]::WriteAllText($stub, '{"play":{"ok":true,"observed":[],"diagnostics":[{"kind":"play-track","app":"com.x","track":"production","release":"2.0","status":"completed","versionCodes":["200"],"rollout":null,"claim":"none"},{"kind":"play-lifecycle","app":"com.x","track":"production","release":"2.0","lifecycle":"PUBLISHED","known":true,"meaning":"available to users on this track, not proof of public serving","versionCodes":["200"],"claim":"none"}]}}')
        foreach ($verb in 'probe', 'probe', 'import') {
            $r = Invoke-RlCli @{ Verb = $verb; RepoRoot = $repo }
            Assert-That ($r.code -eq 0) "$verb exit $($r.code)`n$($r.text)"
            Assert-That ($r.text -match "reading\s+play\s+track production, release '2\.0', status completed, versionCodes 200 - track configuration only") "$verb printed no track reading`n$($r.text)"
            Assert-That ($r.text -match 'lifecycle PUBLISHED' -and $r.text -match 'readings only, no publication recorded') "$verb printed no lifecycle reading or recorded something`n$($r.text)"
            Assert-That ((Get-FileSha $histPath) -ceq $h0) "$verb changed history.jsonl"
        }

        [IO.File]::WriteAllText($stub, '{"play":{"ok":false,"reason":"no Play Developer API credential"}}')
        $r = Invoke-RlCli @{ Verb = 'probe'; RepoRoot = $repo }
        Assert-That ($r.code -eq 0 -and $r.text -match 'unverified\s+play\s+no Play Developer API credential' -and (Get-FileSha $histPath) -ceq $h0) "an unavailable response: exit $($r.code), history changed or no unverified line`n$($r.text)"

        [IO.File]::WriteAllText($stub, '{"play":{"ok":true,"observed":[],"diagnostics":[]}}')
        $r = Invoke-RlCli @{ Verb = 'import'; RepoRoot = $repo }
        Assert-That ($r.code -eq 0 -and $r.text -match 'seen\s+play\s+nothing published' -and (Get-FileSha $histPath) -ceq $h0) "an empty response: exit $($r.code), history changed`n$($r.text)"

        [IO.File]::WriteAllText($stub, '{"play":{"ok":true,"observed":[{"version":"7.0","state":"live","track":"production"}]}}')
        $r = Invoke-RlCli @{ Verb = 'probe'; RepoRoot = $repo }
        Assert-That ($r.code -eq 0 -and $r.text -match 'ignored\s+play\s+1 Play observation\(s\)' -and (Get-FileSha $histPath) -ceq $h0) "an adapter observation was written or not reported`n$($r.text)"
        Assert-That (-not (Test-Path (Join-Path $rd 'RELEASES.md'))) 'a probe that wrote nothing rendered RELEASES.md'
    }
} finally {
    $env:SZA_RELEASES_NOW = $savedNow
    $env:SZA_RELEASES_PROBE_STUB = $savedStub
    $env:PATH = $savedPath
    if ($KeepScratch) { Write-Host "scratch kept: $scratch" } else { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host ''
Write-Host "release-ledger tests: $passed of $run passed, $failed failed"
if ($failed -gt 0) { exit 1 }
exit 0
