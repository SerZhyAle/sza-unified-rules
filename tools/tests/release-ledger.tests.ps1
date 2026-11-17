#requires -Version 7.0
<#
.SYNOPSIS
    Fast tests for the release ledger (RELEASE-LEDGER 0.1, canon S0092): tools/harness/releases.

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

    Everything is a throwaway folder; no real repository, no network, three pwsh processes for case 10.
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

. (Join-Path $releases '_lib.ps1')
. (Join-Path $releases '_probes.ps1')

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
        Assert-That ($p.Count -eq 3 -and $p[0].state -ceq 'live' -and $p[0].rollout -eq 0.2 -and $p[1].rollout -eq $null -and $p[2].state -ceq 'withdrawn' -and $p[2].version -ceq '9') 'Play track'
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
} finally {
    $env:SZA_RELEASES_NOW = $savedNow
    $env:SZA_RELEASES_PROBE_STUB = $savedStub
    if ($KeepScratch) { Write-Host "scratch kept: $scratch" } else { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host ''
Write-Host "release-ledger tests: $passed of $run passed, $failed failed"
if ($failed -gt 0) { exit 1 }
exit 0
