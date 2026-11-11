#requires -Version 7.0
# S0048 build-deliver tests: a sandbox repo whose build is a stub script - the delivered artifact, its .sha256
# sidecar, the LATEST pointer, the build.delivered event, the ticket note through the project's own tooling,
# the refusals (exit 2; version refused, exit 4), token contention, the ingest publish/build intents, the
# store staging dry run (no upload invoked, BlockExternal spelled out) and the drain's -After build trigger.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$harness = Join-Path $PSScriptRoot '..\harness\portfolio'
. (Join-Path $harness 'lib\events.ps1')   # Read-PqDay (the event assertions)
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('sza-build-deliver-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$portfolio = Join-Path $scratch 'portfolio'
$inbox = Join-Path $scratch 'inbox'
$delivery = Join-Path $scratch 'app'

$savedPortfolioRoot = $env:SZA_PORTFOLIO_ROOT
$savedInboxRoot = $env:SZA_INBOX_ROOT
$savedSpecDraft = $env:SZA_SPEC_DRAFT
$savedDeliveryRoot = $env:SZA_DELIVERY_ROOT

function Assert-Bd($Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Invoke-Bd([string]$File, [string[]]$Arguments) {
    $out = & (Get-Process -Id $PID).Path -NoProfile -File $File @Arguments 2>&1
    return @{ code = $LASTEXITCODE; lines = @($out | ForEach-Object { [string]$_ }) }
}

try {
    foreach ($d in @($portfolio, (Join-Path $portfolio 'log'), $inbox, (Join-Path $scratch 'delivery'))) {
        $null = [IO.Directory]::CreateDirectory($d)
    }
    $env:SZA_PORTFOLIO_ROOT = $portfolio
    $env:SZA_INBOX_ROOT = $inbox
    $env:SZA_DELIVERY_ROOT = $delivery    # the drain's build half resolves the root through the variable
    $tokenDir = Join-Path $portfolio 'resourcesuild'

    # Sandbox projects, all registered once: 'stub' (a build and a stamped tag), 'bare' (nothing at all,
    # for refusals), 'msixproj' (the store staging sandbox), 'plain' (a build without any stamp) and
    # 'ledgered' (a real-shaped ledger for the drain's -After half).
    $stubRepo = Join-Path $scratch 'stubrepo'
    $bareRepo = Join-Path $scratch 'barerepo'
    $plainRepo = Join-Path $scratch 'plainrepo'
    $msixRepo = Join-Path $scratch 'msixrepo'
    $ledgerRepo = Join-Path $scratch 'ledgerrepo'
    foreach ($d in @(
            $stubRepo, (Join-Path $stubRepo 'dist'), (Join-Path $stubRepo 'PLAN'), (Join-Path $stubRepo 'scripts\spec_catalog'),
            $bareRepo, (Join-Path $bareRepo 'PLAN'),
            $plainRepo,
            (Join-Path $msixRepo 'msix\dist'),
            $ledgerRepo, (Join-Path $ledgerRepo 'PLAN'), (Join-Path $ledgerRepo 'scripts\spec_catalog'))) {
        $null = [IO.Directory]::CreateDirectory($d)
    }
    $repos = @(
        [ordered]@{ key = 'stub'; path = $stubRepo; enabled = $true; maxWorkers = 1; concurrent = $false; role = 'product'; permissionMode = 'bypassPermissions'; rank = 10 },
        [ordered]@{ key = 'bare'; path = $bareRepo; enabled = $true; maxWorkers = 1; concurrent = $false; role = 'product'; permissionMode = 'bypassPermissions'; rank = 20 },
        [ordered]@{ key = 'msixproj'; path = $msixRepo; enabled = $true; maxWorkers = 1; concurrent = $false; role = 'product'; permissionMode = 'bypassPermissions'; rank = 30 },
        [ordered]@{ key = 'plain'; path = $plainRepo; enabled = $true; maxWorkers = 1; concurrent = $false; role = 'product'; permissionMode = 'bypassPermissions'; rank = 40 },
        [ordered]@{ key = 'ledgered'; path = $ledgerRepo; enabled = $true; maxWorkers = 1; concurrent = $false; role = 'product'; permissionMode = 'bypassPermissions'; rank = 50 }
    )
    [IO.File]::WriteAllText((Join-Path $portfolio 'repos.json'),
        (ConvertTo-Json -InputObject ([ordered]@{ schemaVersion = '1.0'; repos = $repos }) -Depth 5), [Text.UTF8Encoding]::new($false))

    function New-Stamp([string]$Path, [string]$TagRegex) {
        $stamp = [ordered]@{
            canon   = [ordered]@{ version = '2026.10.17.1' }
            role    = 'product'
            versionShape = [ordered]@{ tagRegex = $TagRegex; editionTagPrefixes = @() }
        }
        [IO.File]::WriteAllText((Join-Path $Path '.sza-canon.json'), (ConvertTo-Json -InputObject $stamp -Depth 6), [Text.UTF8Encoding]::new($false))
    }

    # ---- the stub build: an exe-like blob under dist/, a cheap version stamp source via a git tag ----
    New-Stamp $stubRepo '^v\d+\.\d+\.\d+$'
    [IO.File]::WriteAllText((Join-Path $stubRepo 'build.ps1'), @'
"stub build"
$dir = Join-Path $PSScriptRoot 'dist'
if (-not (Test-Path $dir)) { New-Item -ItemType Directory $dir | Out-Null }
Start-Sleep -Milliseconds 200
[IO.File]::WriteAllBytes((Join-Path $dir 'stubapp.exe'), [byte[]](1, 2, 3, 4, 5, 6))
"stub build done"
exit 0
'@, [Text.UTF8Encoding]::new($false))
    & git -C $stubRepo init -q
    $null = & git -C $stubRepo -c user.email=t@t -c user.name=t commit --allow-empty -q -m init 2>&1
    $null = & git -C $stubRepo tag v1.2.3 2>&1
    Assert-Bd (@(& git -C $stubRepo tag -l) -contains 'v1.2.3') 'the sandbox tag was not written'

    # The project's own update tooling: records the call, exits 0 (the S0048 note path).
    $updateCalls = Join-Path $scratch 'update-calls.jsonl'
    [IO.File]::WriteAllText((Join-Path $stubRepo 'scripts\spec_catalog\update.ps1'), @'
param([string]$Id, [string]$Status, [string]$StatusNote)
[ordered]@{ id = $Id; status = $Status; note = $StatusNote } | ConvertTo-Json -Compress | Add-Content -LiteralPath ($env:SZA_BD_UPDATE_CALLS)
exit 0
'@, [Text.UTF8Encoding]::new($false))
    $env:SZA_BD_UPDATE_CALLS = $updateCalls

    # ---- case 1: build + deliver: artifact, sidecar, LATEST, event, ticket note, -Json ----
    $bd = Join-Path $harness 'build-deliver.ps1'
    $r = Invoke-Bd $bd @('-Project', 'stub', '-Ticket', 'SR0001', '-Json', '-DeliveryRoot', $delivery)
    Assert-Bd ($r.code -eq 0) "case 1 exit $($r.code): $($r.lines -join ' | ')"
    $record = ConvertFrom-Json -InputObject ($r.lines -join "`n") -DateKind String -AsHashtable
    $version = [string]$record['version']
    Assert-Bd ($version -ceq '1.2.3') "the tag stamp did not resolve (got '$version')"
    Assert-Bd ($record['versionSource'] -ceq 'tag') "the version source is not the tag"
    $dir = Join-Path (Join-Path $delivery 'stub') $version
    $exe = Join-Path $dir 'stubapp.exe'
    Assert-Bd ([IO.File]::Exists($exe)) 'the artifact was not delivered'
    $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([IO.File]::ReadAllBytes($exe))).ToLowerInvariant()
    $sidecar = [IO.File]::ReadAllText("$exe.sha256")
    Assert-Bd ($sidecar -ceq "$hash  stubapp.exe") "the sidecar does not match (got '$sidecar')"
    Assert-Bd ((Get-Content -LiteralPath (Join-Path (Join-Path $delivery 'stub') 'LATEST') -Raw).Trim() -ceq $version) 'LATEST does not name the delivered version'
    $events = @(Get-ChildItem -LiteralPath (Join-Path $portfolio 'log') -Filter 'events-*.jsonl' | ForEach-Object {
        (Read-PqDay -Path $_.FullName).events
    } | Where-Object { $_.ev -ceq 'build.delivered' })
    Assert-Bd ($events.Count -eq 1) 'the build.delivered event was not written once'
    Assert-Bd ([string]$events[0].d.project -ceq 'stub' -and [string]$events[0].d.version -ceq '1.2.3') 'the event does not name project and version'
    Assert-Bd ([string]$events[0].id -ceq 'SR0001') 'the event does not carry the ticket id'
    Assert-Bd ([string]$events[0].d.sha256[0] -ceq $hash) 'the event hash does not match the sidecar'
    $updateRows = @(Get-Content -LiteralPath $updateCalls | Where-Object { $_ })
    Assert-Bd ($updateRows.Count -eq 1) 'the ticket note was not written once through the project tooling'
    $updateRow = ConvertFrom-Json -InputObject $updateRows[0] -AsHashtable
    Assert-Bd ($updateRow['id'] -ceq 'SR0001' -and $updateRow['note'] -match 'build 1\.2\.3 delivered') 'the note does not record the delivery'

    # ---- case 2: refusals: unknown project, no build command, version refused ----
    $r = Invoke-Bd $bd @('-Project', 'nope', '-Json')
    Assert-Bd ($r.code -eq 2 -and ($r.lines -join '') -match 'ProjectUnknown') 'unknown project did not exit 2'
    $r = Invoke-Bd $bd @('-Project', 'bare', '-Json', '-DeliveryRoot', $delivery)
    Assert-Bd ($r.code -eq 2 -and ($r.lines -join '') -match 'BuildCommandMissing') 'a repo without a build command did not exit 2'
    # no tag, no override, no artifact stamp: the version is refused, not guessed
    [IO.File]::WriteAllText((Join-Path $plainRepo 'build.ps1'), @'
$dir = Join-Path $PSScriptRoot 'out'
if (-not (Test-Path $dir)) { New-Item -ItemType Directory $dir | Out-Null }
[IO.File]::WriteAllBytes((Join-Path $dir 'plainapp.exe'), [byte[]](9, 9))
exit 0
'@, [Text.UTF8Encoding]::new($false))
    New-Stamp $plainRepo $null
    $r = Invoke-Bd $bd @('-Project', 'plain', '-Json', '-DeliveryRoot', $delivery)
    Assert-Bd ($r.code -eq 4 -and ($r.lines -join '') -match 'VersionUnresolved') 'an unstampable version was not refused with exit 4'
    # the same build with -Version is delivered: the override is the explicit stamp
    $r = Invoke-Bd $bd @('-Project', 'plain', '-Version', '26.1102.0300', '-Json', '-DeliveryRoot', $delivery)
    Assert-Bd ($r.code -eq 0) "the -Version override was refused: $($r.lines -join ' | ')"
    Assert-Bd ([IO.File]::Exists((Join-Path (Join-Path (Join-Path $delivery 'plain') '26.1102.0300') 'plainapp.exe'))) 'the override version was not delivered'

    # ---- case 3: DeliverOnly / BuildOnly ----
    $r = Invoke-Bd $bd @('-Project', 'stub', '-DeliverOnly', '-Artifact', (Join-Path $stubRepo 'dist\stubapp.exe'), '-Version', '2.0.0', '-Json', '-DeliveryRoot', $delivery)
    Assert-Bd ($r.code -eq 0) "DeliverOnly failed: $($r.lines -join ' | ')"
    Assert-Bd ((Get-Content -LiteralPath (Join-Path (Join-Path $delivery 'stub') 'LATEST') -Raw).Trim() -ceq '2.0.0') 'DeliverOnly did not move LATEST'
    $before = (Get-ChildItem -LiteralPath $delivery -Recurse -File).Count
    $r = Invoke-Bd $bd @('-Project', 'stub', '-BuildOnly', '-Json', '-DeliveryRoot', $delivery)
    Assert-Bd ($r.code -eq 0) "BuildOnly failed: $($r.lines -join ' | ')"
    Assert-Bd ((Get-ChildItem -LiteralPath $delivery -Recurse -File).Count -eq $before) 'BuildOnly delivered something'
    $r = Invoke-Bd $bd @('-Project', 'stub', '-BuildOnly', '-DeliverOnly', '-Json')
    Assert-Bd ($r.code -eq 2) 'the conflicting switches did not exit 2'

    # ---- case 4: the build token - a same-repo token held by a live foreign process is waited out ----
    $sleeper = Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList @('-NoProfile', '-Command', 'Start-Sleep -Seconds 10') -PassThru -WindowStyle Hidden
    try {
        $tokenDir = Join-Path $portfolio 'resources\build'
        $null = [IO.Directory]::CreateDirectory($tokenDir)
        $token = [ordered]@{
            token = 'build'; repo = 'stub'; id = 'SR0999'; pid = $sleeper.Id
            procStart = (Get-Process -Id $sleeper.Id).StartTime.ToUniversalTime().ToString('o')
            pass = 'other'; at = [DateTimeOffset]::UtcNow.ToString('o')
        }
        [IO.File]::WriteAllText((Join-Path $tokenDir 'stub__SR0999.json'), (ConvertTo-Json -InputObject $token -Compress))
        $r = Invoke-Bd $bd @('-Project', 'stub', '-Json', '-DeliveryRoot', $delivery, '-TokenWaitSeconds', '1')
        Assert-Bd ($r.code -eq 3 -and ($r.lines -join '') -match 'BuildTokenNotObtained') "a build racing a live same-repo token was not refused (exit $($r.code))"
    }
    finally {
        $null = Stop-Process -Id $sleeper.Id -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath (Join-Path $tokenDir 'stub__SR0999.json') -Force -ErrorAction SilentlyContinue
    }
    # two concurrent invocations serialize on the same ticket id and both deliver
    $p1 = Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList @('-NoProfile', '-File', $bd, '-Project', 'stub', '-Ticket', 'SR0002', '-Json', '-DeliveryRoot', $delivery) -RedirectStandardOutput (Join-Path $scratch 'p1.out') -RedirectStandardError (Join-Path $scratch 'p1.err') -PassThru -WindowStyle Hidden
    $p2 = Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList @('-NoProfile', '-File', $bd, '-Project', 'stub', '-Ticket', 'SR0002', '-Json', '-DeliveryRoot', $delivery) -RedirectStandardOutput (Join-Path $scratch 'p2.out') -RedirectStandardError (Join-Path $scratch 'p2.err') -PassThru -WindowStyle Hidden
    $p1.WaitForExit(); $p2.WaitForExit()
    Assert-Bd ($p1.ExitCode -eq 0 -and $p2.ExitCode -eq 0) "the two concurrent builds did not both succeed ($($p1.ExitCode)/$($p2.ExitCode))"
    $w1 = [double](ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $scratch 'p1.out'))) -DateKind String -AsHashtable)['tokenWaited']
    $w2 = [double](ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $scratch 'p2.out'))) -DateKind String -AsHashtable)['tokenWaited']
    Assert-Bd ( ($w1 -gt 0) -or ($w2 -gt 0) ) "the second build did not wait for the first ($w1/$w2)"
    Assert-Bd (-not [IO.File]::Exists((Join-Path $portfolio "resources\build\stub__SR0002.json"))) 'a build token was left behind'
    $events = @(Get-ChildItem -LiteralPath (Join-Path $portfolio 'log') -Filter 'events-*.jsonl' | ForEach-Object {
        (Read-PqDay -Path $_.FullName).events
    } | Where-Object { $_.ev -ceq 'build.delivered' })
    Assert-Bd ($events.Count -eq 5) "the five deliveries did not all write their event ($($events.Count))"

    # ---- case 5: the ingest recognizer (text -> publishIntent / buildIntent, notes in the drafted ticket) ----
    . (Join-Path $harness 'lib\inbox-spool.ps1')
    . (Join-Path $harness 'lib\inbox-packet.ps1')
    . (Join-Path $harness 'lib\inbox-ingest.ps1')
    Assert-Bd ((Get-InboxPublishIntent 'опубликуй MyProject in MS Store') -ceq 'ms-store') '"опубликуй in MS Store" was not recognized as ms-store'
    Assert-Bd ((Get-InboxPublishIntent 'выложи в стор новое') -ceq 'ms-store') '"выложи в стор" was not recognized as ms-store'
    Assert-Bd ((Get-InboxPublishIntent 'обнови, пожалуйста, winget') -ceq 'winget') 'the winget mention was not recognized'
    Assert-Bd ($null -eq (Get-InboxPublishIntent 'пофикси баг в кнопке')) 'a plain ticket was given an intent'
    Assert-Bd (Test-InboxBuildIntent 'собери новую версию, я проверю с телефона') '"собери" was not recognized as a build ask'
    Assert-Bd (-not (Test-InboxBuildIntent 'поменяй цвет кнопки')) 'a plain ticket was flagged as a build ask'

    # through the real ingest: a packet of the owner's own words -> result.json fields + the notes in the ticket
    $specDraft = Join-Path $scratch 'spec-draft.ps1'
    [IO.File]::WriteAllText($specDraft, @'
param([string]$Project, [string]$TextFile, [string]$Attach, [string]$DedupQuery)
$ErrorActionPreference = 'Stop'
$text = if (Test-Path -LiteralPath $TextFile) { [IO.File]::ReadAllText($TextFile, [Text.Encoding]::UTF8) } else { '' }
[ordered]@{ project = $Project; text = $text } | ConvertTo-Json -Depth 3 -Compress | Add-Content -LiteralPath $env:SZA_BD_CAPTURE_LOG
Write-Output "spec-draft(stub): captured $Project"
Write-Output "drafted ${Project}:S0501 file=PLAN/S0501_x.md priority=50 pq=dispatchable position=1/1"
exit 0
'@, [Text.UTF8Encoding]::new($false))
    $env:SZA_SPEC_DRAFT = $specDraft
    $captureLog = Join-Path $scratch 'capture.jsonl'
    $env:SZA_BD_CAPTURE_LOG = $captureLog
    $ownerWords = "Опубликуй MyProject in MS Store, собери новую версию, я проверю с телефона."
    $ingest = Join-Path $harness 'ingest-inbox.ps1'
    $manifest = [ordered]@{
        schemaVersion = 2; payloadKind = 'TICKET'; packetId = 'pk-intent-1'
        createdAtEpochMs = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds(); senderDeviceName = 'Pixel 8 (test)'
        fileNames = @('text.md'); totalSizeBytes = [long]0; ttlSeconds = 604800
        files = @(); projects = @('stub'); text = $ownerWords
    }
    $null = Initialize-InboxSpool $inbox
    $packetDir = Join-Path (Join-Path $inbox 'new') 'pk-intent-1'
    $null = [IO.Directory]::CreateDirectory($packetDir)
    $textFile = Join-Path $packetDir 'text.md'
    [IO.File]::WriteAllText($textFile, "$ownerWords`n", [Text.UTF8Encoding]::new($false))
    $bytes = [IO.File]::ReadAllBytes($textFile)
    $manifest['files'] = @([ordered]@{ name = 'text.md'; size = [long]$bytes.Length; sha256 = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant(); mimeType = 'text/markdown'; role = 'text' })
    $manifest['totalSizeBytes'] = [long]$bytes.Length
    $null = Write-InboxPacketManifest -Manifest $manifest -Path (Join-Path $packetDir 'manifest.json')
    $r = Invoke-Bd $ingest @('-Packet', (Join-Path $inbox 'new\pk-intent-1'), '-InboxRoot', $inbox)
    Assert-Bd ($r.code -eq 0) "the intent ingest failed: $($r.lines -join ' | ')"
    $result = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path (Join-Path $inbox 'done\pk-intent-1') 'result.json'))) -DateKind String -AsHashtable
    Assert-Bd ([string]$result['publishIntent'] -ceq 'ms-store') 'publishIntent did not land in result.json'
    Assert-Bd ([bool]$result['buildIntent']) 'buildIntent did not land in result.json'
    $captured = ConvertFrom-Json -InputObject (@(Get-Content -LiteralPath $captureLog | Where-Object { $_ })[-1]) -AsHashtable
    $ticketText = [string]$captured['text']
    Assert-Bd ($ticketText -match 'skills/store-publish') 'the publish-intent note is missing from the drafted ticket'
    Assert-Bd ($ticketText -match 'build-deliver') 'the build-intent note is missing from the drafted ticket'
    Assert-Bd ($ticketText.StartsWith($ownerWords)) 'the owner words are not byte for byte above the machine lines'

    # ---- case 6: pq status prints the last builds ----
    $pq = Join-Path $harness 'pq.ps1'
    $r = Invoke-Bd $pq @('status')
    Assert-Bd ($r.code -eq 0) "pq status failed: $($r.lines -join ' | ')"
    Assert-Bd (($r.lines -join "`n") -match 'delivered: stub 1\.2\.3') 'pq status does not show the last delivered build'
    $r = Invoke-Bd $pq @('status', '-Json')
    $statusJson = ConvertFrom-Json -InputObject ($r.lines -join "`n") -DateKind String -AsHashtable
    $stubBuild = @($statusJson['lastBuilds'] | Where-Object { $_['project'] -ceq 'stub' })
    Assert-Bd ($stubBuild.Count -eq 1 -and [string]$stubBuild[0]['version'] -eq '1.2.3') 'pq status -Json does not carry the last build'

    # ---- case 7: the store staging dry run - no upload invoked, the manual step spelled out ----
    $msixRepo = Join-Path $scratch 'msixrepo'
    $null = [IO.Directory]::CreateDirectory((Join-Path $msixRepo 'msix\dist'))
    New-Stamp $msixRepo $null
    [IO.File]::WriteAllText((Join-Path $msixRepo 'STORE_PUBLISHING.md'), @'
# Publishing to the Microsoft Store

## Reserved identity (permanent - supply on every submission)

| Field | Value |
| --- | --- |
| `Package/Identity/Name` | `SZA.TestApp` |
| `Package/Identity/Publisher` | `CN=F98ACEDB-1E22-4C39-AF63-F9FCFE807DCD` |
| `Package/Properties/PublisherDisplayName` | `SZA` |
'@, [Text.UTF8Encoding]::new($false))
    $msixCalls = Join-Path $scratch 'msix-calls.jsonl'
    $null = [IO.Directory]::CreateDirectory((Join-Path (Join-Path $msixRepo 'scripts') 'spec_catalog'))
    Copy-Item -LiteralPath (Join-Path (Join-Path $stubRepo 'scripts') (Join-Path 'spec_catalog' 'update.ps1')) -Destination (Join-Path (Join-Path (Join-Path $msixRepo 'scripts') 'spec_catalog') 'update.ps1')
    $env:SZA_BD_MSIX_CALLS = $msixCalls
    [IO.File]::WriteAllText((Join-Path $msixRepo 'msix\build-msix.ps1'), @'
param([string]$IdentityName, [string]$Publisher, [string]$PublisherDisplayName, [switch]$SelfSign)
$ErrorActionPreference = 'Stop'
[ordered]@{ identityName = $IdentityName; publisher = $Publisher; publisherDisplayName = $PublisherDisplayName; selfSign = [bool]$SelfSign } |
    ConvertTo-Json -Compress | Add-Content -LiteralPath $env:SZA_BD_MSIX_CALLS
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$msix = Join-Path $PSScriptRoot 'dist\TestApp.msix'
if (Test-Path $msix) { Remove-Item $msix -Force }
$zip = [IO.Compression.ZipFile]::Open($msix, 'Create')
try {
    $entry = $zip.CreateEntry('AppxManifest.xml')
    $w = [IO.StreamWriter]::new($entry.Open())
    try {
        $w.Write('<Package><Identity Name="' + $IdentityName + '" Publisher="' + $Publisher + '" Version="26.1111.1010.0" /></Package>')
    } finally { $w.Dispose() }
} finally { $zip.Dispose() }
exit 0
'@, [Text.UTF8Encoding]::new($false))
    $stage = Join-Path $harness 'stage-store-publish.ps1'
    $r = Invoke-Bd $stage @('-Project', 'msixproj', '-Version', '26.1111.1010.0', '-Json')
    Assert-Bd ($r.code -eq 0) "the staging failed: $($r.lines -join ' | ')"
    $staged = ConvertFrom-Json -InputObject ($r.lines -join "`n") -DateKind String -AsHashtable
    Assert-Bd ($staged['uploaded'] -eq $false) 'the staging record claims an upload'
    $stageDir = [string]$staged['outDir']
    $stagedMsix = [string]$staged['staged'][0]
    Assert-Bd ([IO.File]::Exists($stagedMsix) -and [IO.File]::Exists("$stagedMsix.sha256") -and [IO.File]::Exists([string]$staged['report'])) 'the staged artifact set is incomplete'
    $report = [IO.File]::ReadAllText([string]$staged['report'])
    Assert-Bd ($report -cmatch 'CN=F98ACEDB-1E22-4C39-AF63-F9FCFE807DCD') 'the report does not name the frozen Publisher anchor'
    Assert-Bd ($report -cmatch 'NOTHING WAS UPLOADED') 'the report does not say the upload never ran'
    Assert-Bd ($report -cmatch 'BlockExternal') 'the report does not stop the ticket at BlockExternal'
    Assert-Bd ($report -cmatch 'Partner Center') 'the report does not spell the manual Partner Center step'
    $msixCall = ConvertFrom-Json -InputObject (([IO.File]::ReadAllLines($msixCalls))[-1]) -AsHashtable
    Assert-Bd ([string]$msixCall['identityName'] -ceq 'SZA.TestApp' -and [string]$msixCall['publisher'] -ceq 'CN=F98ACEDB-1E22-4C39-AF63-F9FCFE807DCD') 'the frozen identity was not passed to the msix build'
    Assert-Bd (-not $msixCall['selfSign']) 'the staging asked for a self-signed package'
    $allCalls = ([IO.File]::ReadAllText($msixCalls) -join ' ')
    Assert-Bd ($allCalls -cnotmatch 'msstore|wingetcreate|gh release|upload') 'an upload-like command was invoked'
    Assert-Bd ([IO.File]::Exists((Join-Path $stageDir 'WACK-COMMAND.txt'))) 'the WACK manual command was not staged'
    # a staged report gives the verdict row; the -SetStatus half records the BlockExternal move
    [IO.File]::WriteAllText((Join-Path $stageDir 'WACKReport.xml'), '<REPORT OVERALL_RESULT="PASS" />', [Text.UTF8Encoding]::new($false))
    $r = Invoke-Bd $stage @('-Project', 'msixproj', '-Version', '26.1111.1010.0', '-OutDir', $stageDir, '-Json', '-Ticket', 'SM0001', '-SetStatus')
    Assert-Bd ($r.code -eq 0) "the re-staging with a WACK report failed: $($r.lines -join ' | ')"
    $staged2 = ConvertFrom-Json -InputObject ($r.lines -join "`n") -DateKind String -AsHashtable
    Assert-Bd ([string]$staged2['wack'] -ceq 'PASS') 'the WACK verdict did not read PASS from the staged report'
    $wackStep = @($staged2['steps'] | Where-Object { $_['step'] -ceq 'wack' })
    Assert-Bd ($wackStep.Count -eq 1 -and [string]$wackStep[0]['outcome'] -ceq 'ok') 'the WACK step did not pass'
    $updateRows = @(Get-Content -LiteralPath $updateCalls | Where-Object { $_ })
    $lastUpdate = ConvertFrom-Json -InputObject $updateRows[-1] -AsHashtable
    Assert-Bd ($lastUpdate['id'] -ceq 'SM0001' -and [string]$lastUpdate['status'] -ceq 'BlockExternal') 'the ticket was not stopped at BlockExternal through the project tooling'

    # ---- case 8: the drain builds after a ran ticket (-After and buildIntent alike) ----
    $ledgerRepo = Join-Path $scratch 'ledgerrepo'
    Copy-Item -LiteralPath (Join-Path $stubRepo 'build.ps1') -Destination $ledgerRepo
    Copy-Item -LiteralPath (Join-Path $stubRepo '.sza-canon.json') -Destination $ledgerRepo
    Copy-Item -LiteralPath (Join-Path (Join-Path $stubRepo 'scripts') (Join-Path 'spec_catalog' 'update.ps1')) -Destination (Join-Path (Join-Path $ledgerRepo 'scripts') (Join-Path 'spec_catalog' 'update.ps1'))
    & git -C $ledgerRepo init -q
    $null = & git -C $ledgerRepo -c user.email=t@t -c user.name=t commit --allow-empty -q -m init 2>&1
    $null = & git -C $ledgerRepo tag v1.2.3 2>&1
    $ledgerFile = Join-Path (Join-Path $ledgerRepo 'PLAN') 'spec-catalog.jsonl'
    $ingestStub = Join-Path $scratch 'ingest-stub.ps1'
    [IO.File]::WriteAllText($ingestStub, 'exit 3' + [char]10, [Text.UTF8Encoding]::new($false))
    $pqStub = Join-Path $scratch 'pq-stub.ps1'
    $pqStubBody = @'
param([string]$Verb, [string]$Ticket)
$row1 = '{"id":"SB0001","name":"t-SB0001","status":"Implemented","priority":50,"file":"PLAN/SB0001_x.md","created":"2026-11-11","updated":"2026-11-11 10:00"}'
$row2 = '{"id":"SB0002","name":"t-SB0002","status":"In Progress","priority":50,"file":"PLAN/SB0002_x.md","created":"2026-11-11","updated":"2026-11-11 10:00"}'
if ($Verb -ceq 'start' -and $Ticket -ceq 'ledgered:SB0001') {
    [IO.File]::WriteAllText($env:SZA_BD_LEDGER, $row1 + [char]10 + $row2 + [char]10, [Text.UTF8Encoding]::new($false))
    exit 0
}
if ($Verb -ceq 'start' -and $Ticket -ceq 'ledgered:SB0002') { exit 0 }
Write-Output "pq: ticket $Ticket not run - unknown"
exit 3
'@
    [IO.File]::WriteAllText($pqStub, $pqStubBody + [char]10, [Text.UTF8Encoding]::new($false))
    $env:SZA_BD_LEDGER = $ledgerFile
    function New-DrainPacket([string]$Id, [string]$Ticket, [bool]$BuildIntent) {
        $null = Initialize-InboxSpool $inbox
        $dir = Join-Path (Join-Path $inbox 'done') $Id
        $null = [IO.Directory]::CreateDirectory($dir)
        $result = [ordered]@{ packetId = $Id; tickets = @($Ticket); verdict = 'dispatchable'; at = '2026-11-11T09:00:00Z'; execution = 'file-only' }
        if ($BuildIntent) { $result['buildIntent'] = $true }
        [IO.File]::WriteAllText((Join-Path $dir 'result.json'), (ConvertTo-Json -InputObject $result -Depth 6), [Text.UTF8Encoding]::new($false))
        # the manifest names the project, so the drain runs the ticket instead of leaving it for triage
        $manifest = [ordered]@{
            schemaVersion = 2; payloadKind = 'TICKET'; packetId = $Id
            createdAtEpochMs = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds(); senderDeviceName = 'Pixel 8 (test)'
            fileNames = @(); totalSizeBytes = [long]0; ttlSeconds = 604800; files = @(); project = 'ledgered'
        }
        $null = Write-InboxPacketManifest -Manifest $manifest -Path (Join-Path $dir 'manifest.json')
    }
    $drain = Join-Path $harness 'drain-inbox.ps1'
    New-DrainPacket 'dk-b1' 'ledgered:SB0001' $true
    $r = Invoke-Bd $drain @('-InboxRoot', $inbox, '-PqScript', $pqStub, '-IngestScript', $ingestStub)
    Assert-Bd ($r.code -eq 0) "the drain failed: $($r.lines -join ' | ')"
    $b1 = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path (Join-Path (Join-Path $inbox 'done') 'dk-b1') 'result.json'))) -DateKind String -AsHashtable
    $buildRow = @($b1['builds'] | Where-Object { $_['ticket'] -ceq 'ledgered:SB0001' })
    Assert-Bd ($buildRow.Count -eq 1) 'the build decision did not land in result.json'
    Assert-Bd ([string]$buildRow[0]['outcome'] -ceq 'delivered') "the build did not deliver: $($buildRow[0]['outcome']) $($buildRow[0]['reason'])"
    $deliveredVersion = [string]($buildRow[0]['version'])
    $deliveredPath = Join-Path (Join-Path (Join-Path $delivery 'ledgered') $deliveredVersion) 'stubapp.exe'
    Assert-Bd ([IO.File]::Exists($deliveredPath)) ("the drain build was not delivered to the folder (expected $deliveredPath, row dir $($buildRow[0]['dir']), root $env:SZA_DELIVERY_ROOT)")
    # a ticket whose pass left it not-ready: no build, the reason recorded; -After refusal shapes
    New-DrainPacket 'dk-b2' 'ledgered:SB0002' $true
    $r = Invoke-Bd $drain @('-InboxRoot', $inbox, '-PqScript', $pqStub, '-IngestScript', $ingestStub)
    Assert-Bd ($r.code -eq 0) "the second drain failed: $($r.lines -join ' | ')"
    $b2 = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path (Join-Path (Join-Path $inbox 'done') 'dk-b2') 'result.json'))) -DateKind String -AsHashtable
    $buildRow2 = @($b2['builds'] | Where-Object { $_['ticket'] -ceq 'ledgered:SB0002' })
    Assert-Bd ($buildRow2.Count -eq 1 -and [string]$buildRow2[0]['outcome'] -ceq 'not-built' -and ([string]$buildRow2[0]['reason']) -match 'In Progress') 'a not-ready ticket was built anyway'
    $r = Invoke-Bd $drain @('-InboxRoot', $inbox, '-After', 'ledgered', '-PqScript', $pqStub, '-IngestScript', $ingestStub)
    Assert-Bd ($r.code -eq 2) 'a malformed -After tag did not exit 2'
    Write-Host 'PASS: deliver, sidecar, LATEST, event, note, refusals (2), version refused (4), token wait + serialization, intents at ingest, status fragment, store staging dry run, drain -After'
}
finally {
    $env:SZA_PORTFOLIO_ROOT = $savedPortfolioRoot
    $env:SZA_INBOX_ROOT = $savedInboxRoot
    $env:SZA_SPEC_DRAFT = $savedSpecDraft
    $env:SZA_DELIVERY_ROOT = $savedDeliveryRoot
    if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
}
