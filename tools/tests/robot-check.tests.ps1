#requires -Version 7.0
<#
.SYNOPSIS
    Cases for tools/site-audit/robot-check.ps1 - the no-JavaScript crawl the site audit's robot lens reads.

.DESCRIPTION
    No request leaves the machine, so the whole file takes a few seconds. Three saved pages written to a throwaway
    folder are parsed with -Offline, and one run crawls a stub HTTP server on 127.0.0.1 that this file starts and
    stops.

    The main fixture carries a title with an emoji, a 170-character description, an absolute canonical, three
    hreflang links with x-default, two JSON-LD blocks (an @graph holding a nested SoftwareApplication, and one that
    does not parse), two h1 of which the first spans three languages, images without alt and without size, a new-tab
    link with a hint and one without, data-l spans in three languages, "coming soon" in the text and a version string
    beside an address and a date that are not versions; a comment and a style block hold text that must not count.
    The bare fixture has no title and no description, a canonical in the body, max-image-preview:none in its meta
    robots, an h1 of 345 characters in three languages, a "<!--" inside an attribute value and an unclosed <a name>,
    and a UTF-8 byte order mark ahead of a meta charset that names windows-1251. The cp1251 fixture is windows-1251
    bytes under the label cp1251.

    The stub site links its key pages beside their language copies and query variants, has hreflang targets on ?lang=
    URLs (one with max-image-preview:none, one answering "X-Robots-Tag: googlebot: noindex"), a download whose HEAD
    answers 404 and GET 200, a link into a redirect loop, a cookie set by the home page, a robots.txt, a sitemap.xml
    and an llms.txt that each redirect to an HTML page, and a 404 for the page the run declares with -Pages.

      1. Exit 0, one summary line, and exactly the documented keys in the documented order.
      2. The head: lang, dataLang, title, its length in text elements and its emoji, description, viewport,
         canonical, meta robots.
      3. hreflang: three entries, x-default, the self entries read from the page, the ?lang= entry unmeasured.
      4. Open Graph and Twitter, the social image on raw.githubusercontent.com.
      5. JSON-LD: the @graph block with its nested SoftwareApplication, and the block that does not parse.
      6. Headings: two h1, the first read with every language, role=heading counted, the commented h1 ignored.
      7. Images: alt, size, lazy, items.
      8. Links: counts, new-tab hints, noreferrer to an owner's host, downloads; no check offline.
      9. Language and text: spans per language, letters per script, the visible text, versions, status phrases.
     10. Scripts: the src list, rewrites, api.github.com and raw.githubusercontent.com counts.
     11. The site block offline: every answer null, www skipped, no error.
     12. Bad invocations exit 2 and write nothing: no -HtmlFile, a bad number, a relative URL, an unknown argument,
         an -Out that is a folder, an -Out on the Env: drive.
     13. A page without title or description reads null; the canonical in the body is ignored; max-image-preview:none
         is no noindex.
     14. The long h1 whole in h1NoJs and cut in h1[]; a "<!--" in an attribute and an unclosed <a name> hide nothing.
     15. Charsets: the byte order mark wins over the meta charset; cp1251 reads as windows-1251.
     16. The stub site: the pages chosen, one copy of each, no cookie sent back; a page that answers 404 reads null.
     17. The stub site: hreflang targets and their noindex, the download whose HEAD fails, the redirect loop.
     18. The stub site: robots.txt, sitemap.xml and llms.txt report their 301; the HTML page is no sitemap.
#>
[CmdletBinding()]
param([switch] $KeepScratch)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$clock = [Diagnostics.Stopwatch]::StartNew()
$SourceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$script_ = Join-Path $SourceRoot 'tools\site-audit\robot-check.ps1'
$pwshExe = (Get-Command pwsh -CommandType Application | Select-Object -First 1).Source

$run = 0; $passed = 0; $failed = 0
function Assert-That([bool] $Condition, [string] $Message) { if (-not $Condition) { throw $Message } }
function Assert-Equal($Actual, $Expected, [string] $What) { if (-not ($Actual -ceq $Expected)) { throw "${What}: expected [$Expected], got [$Actual]" } }
function Run-Case([string] $Name, [scriptblock] $Body) {
    $script:run++
    Write-Host -NoNewline "CASE  $Name .. "
    try { & $Body; $script:passed++; Write-Host 'PASS' -ForegroundColor Green }
    catch { $script:failed++; Write-Host 'FAIL' -ForegroundColor Red; Write-Host "      $($_.Exception.Message)" -ForegroundColor DarkRed }
}
function Get-Keys($Object) { return (@($Object.PSObject.Properties.Name) -join ',') }

$scratch = Join-Path ([IO.Path]::GetTempPath()) ('robot-check-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $scratch | Out-Null

# ---- the fixture --------------------------------------------------------------------------------------------------

$rocket = [char]::ConvertFromUtf32(0x1F680)
$title = "$rocket Fixture Tool - check a drive before you trust it"
$desc = 'Know the real capacity, speed and readability of a USB stick, an SD card or a disk, find duplicate files and compare two folders before you trust a drive with your files.'
$pageUrl = 'https://fixture.example.org/tool/index.html'
$fixture = @'
<!doctype html>
<html lang="en" data-lang="en">
<head>
<meta charset="utf-8">
<title>{{TITLE}}</title>
<meta name="description" content="{{DESC}}">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="index, follow">
<link rel="canonical" href="https://fixture.example.org/tool/">
<link rel="alternate" hreflang="en" href="https://fixture.example.org/tool/">
<link rel="alternate" hreflang="ru" href="https://fixture.example.org/tool/?lang=ru">
<link rel="alternate" hreflang="x-default" href="https://fixture.example.org/tool/">
<meta property="og:title" content="Fixture Tool">
<meta property="og:locale" content="en_US">
<meta property="og:locale:alternate" content="ru_RU">
<meta property="og:locale:alternate" content="uk_UA">
<meta property="og:image" content="https://raw.githubusercontent.com/fixture-owner/tool/main/card.png">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="Fixture Tool">
<script type="application/ld+json">
{"@context": "https://schema.org", "@graph": [
  {"@type": "WebSite", "name": "Fixture", "url": "https://fixture.example.org/"},
  {"@type": "WebPage", "name": "Fixture Tool", "mainEntity": {
    "@type": "SoftwareApplication", "name": "Fixture Tool", "operatingSystem": "Windows 11",
    "applicationCategory": "UtilitiesApplication", "softwareVersion": "2.4.1",
    "downloadUrl": "https://github.com/fixture-owner/tool/releases/latest",
    "offers": {"@type": "Offer", "price": "0", "priceCurrency": "USD"},
    "author": {"@type": "Person", "name": "A. Author", "url": "https://author.example.net/"}
  }}
]}
</script>
<script type="application/ld+json">
{"@context": "https://schema.org", "@type": "FAQPage", "mainEntity": [ }
</script>
<script>document.title = 'Fixture'; document.querySelector('meta[name="description"]').setAttribute('content', 'x'); fetch('https://api.github.com/repos/fixture-owner/tool/releases/latest');</script>
<script src="/tool/app.js"></script>
<script src="https://cdn.example.com/lib.js"></script>
<style>.x { color: red } h1::after { content: "styled text" }</style>
</head>
<body>
<!-- a comment with <h1>no</h1>, and coming soon inside -->
<h1><span data-l="en">Fixture Tool</span><span data-l="ru">Проверка дисков</span>
<span data-l="uk">Перевірка дисків</span></h1>
<h1>Second heading</h1>
<h2>Features</h2>
<h3>Speed</h3>
<span role="heading" aria-level="2">Fake section</span>
<p data-l="en">Version 2.4.1 is out. The mobile app is coming soon.</p>
<p data-l="ru">Версия для Windows.</p>
<p data-l="uk">Версія для Windows.</p>
<p>It listens on 127.0.0.1 only; build of 29.10.2026.</p>
<img src="shot-a.png">
<img src="shot-b.png" alt="" width="10" height="10" loading="lazy">
<img src="shot-c.png" alt="Main window" width="640">
<a href="docs/index.html">Documentation</a>
<a href="privacy.html?from=home#top">Privacy</a>
<a href="#features">Features</a>
<a href="mailto:someone@example.org">Mail</a>
<a href="https://github.com/fixture-owner/tool" target="_blank" rel="noopener">Source <span class="sr-only">(opens in a new tab)</span></a>
<a href="https://other.example.com/" target="_blank" rel="noreferrer">Other site</a>
<a href="https://author.example.net/" rel="noopener noreferrer">Author</a>
<a href="https://github.com/fixture-owner/tool/releases/download/v2.4.1/tool-2.4.1.zip">Download 2.4.1</a>
<a href="https://raw.githubusercontent.com/fixture-owner/tool/main/README.md">Raw readme</a>
<a href="https://github.com/fixture-owner/tool/blob/main/README.md">Readme</a>
</body>
</html>
'@
$fixture = $fixture.Replace('{{TITLE}}', $title).Replace('{{DESC}}', $desc)
$fixtureFile = Join-Path $scratch 'page.html'
[IO.File]::WriteAllText($fixtureFile, $fixture, [Text.UTF8Encoding]::new($false))

# What a crawler without JavaScript reads in the body: tags gone, the comment and the style gone, and two inline
# spans with nothing between them read as one word.
$h1Read = 'Fixture ToolПроверка дисков Перевірка дисків'
$visible = @(
    $h1Read, 'Second heading', 'Features', 'Speed', 'Fake section',
    'Version 2.4.1 is out. The mobile app is coming soon.', 'Версия для Windows.', 'Версія для Windows.',
    'It listens on 127.0.0.1 only; build of 29.10.2026.', 'Documentation', 'Privacy', 'Features', 'Mail', 'Source (opens in a new tab)', 'Other site', 'Author',
    'Download 2.4.1', 'Raw readme', 'Readme'
) -join ' '
$pageKeys = 'url,status,finalUrl,redirects,bytes,contentType,lang,dataLang,title,titleLength,titleHasEmoji,description,descriptionLength,viewport,canonical,canonicalAbsolute,canonicalSelf,metaRobots,hreflang,xDefault,og,ogLocale,ogLocaleAlternate,ogImage,twitter,jsonld,headings,images,links,langSpans,cyrillicChars,latinChars,textNoJs,appShell,scripts,jsRewrites,apiGithub,rawGithubRefs,versions,statusPhrases'

# The bare fixture: what a page lacks reads null, and the parser's edge cases. Its bytes start with a UTF-8 byte order
# mark and its meta names windows-1251: the mark wins, so the Cyrillic reads right.
$ruH1 = 'Русский заголовок длинный ' * 8
$enH1 = 'English heading that is long ' * 4
$ukH1 = 'Український заголовок'
$longH1 = ($ruH1 + $enH1 + $ukH1 -replace '\s+', ' ').Trim()
$bare = @"
<!doctype html>
<html lang="en">
<head>
<meta charset="windows-1251">
<meta name="robots" content="index, follow, max-image-preview:none">
<link rel="alternate" hreflang="en" href="https://fixture.example.org/tool/">
</head>
<body>
<div title="see <!-- here">x</div>
<h1><span data-l="ru">$ruH1</span><span data-l="en">$enH1</span><span data-l="uk">$ukH1</span></h1>
<p>Body text --> tail.</p>
<a name="top"><a href="docs.html">Docs</a> <a href="privacy.html">Privacy</a>
<link rel="canonical" href="https://fixture.example.org/elsewhere/">
</body>
</html>
"@
$bareFile = Join-Path $scratch 'bare.html'
[IO.File]::WriteAllText($bareFile, $bare, [Text.UTF8Encoding]::new($true))
$cpTitle = 'Проверка дисков - Перевірка дисків'
$cpFile = Join-Path $scratch 'cp1251.html'
[IO.File]::WriteAllBytes($cpFile, [Text.Encoding]::GetEncoding('windows-1251').GetBytes("<!doctype html><html lang=""ru""><head><meta charset=""cp1251""><title>$cpTitle</title></head><body><h1>$cpTitle</h1></body></html>"))
$dirOut = Join-Path $scratch 'dir-out'
New-Item -ItemType Directory -Path $dirOut | Out-Null
$envName = 'robot-check-env-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.json'

# ---- the stub site ------------------------------------------------------------------------------------------------

# HTTP/1.1 on 127.0.0.1, one connection at a time and each closed after its answer, so the parallel requests of the
# crawler wait in the backlog. A page under *.html tells in its description whether the request sent a cookie.
$stubScript = {
    param($Listener, [string]$Site)
    $utf8 = [Text.UTF8Encoding]::new($false)
    function Get-Home([string]$Extra) {
        return @"
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Stub Tool - a loopback site</title>
<meta name="description" content="The site robot-check.tests.ps1 crawls.">
<link rel="canonical" href="$Site">
<link rel="alternate" hreflang="en" href="$Site">
<link rel="alternate" hreflang="ru" href="$($Site)?lang=ru">
<link rel="alternate" hreflang="uk" href="$($Site)?lang=uk">
<link rel="alternate" hreflang="x-default" href="$Site">
$Extra
</head>
<body>
<h1>Stub Tool</h1>
<a data-l="ru" href="ru/guide.html">Инструкции</a>
<a data-l="en" href="guide.html">Guides</a>
<a href="install.html?lang=ru">Установка</a>
<a href="install.html">Install</a>
<a href="helpers.html">Helpers</a>
<a href="supported.html">Supported formats</a>
<a href="trust.html">Windows warning</a>
<a href="privacy.html">Privacy</a>
<a href="files/app.zip" download>Download</a>
<a href="loop">Loop</a>
</body>
</html>
"@
    }
    while ($true) {
        try { $client = $Listener.AcceptTcpClient() } catch { break }
        try {
            $stream = $client.GetStream()
            $stream.ReadTimeout = 5000
            $buf = [byte[]]::new(16384)
            $req = ''
            while (-not $req.Contains("`r`n`r`n")) { $n = $stream.Read($buf, 0, $buf.Length); if ($n -le 0) { break }; $req += [Text.Encoding]::ASCII.GetString($buf, 0, $n) }
            $lines = $req -split "`r`n"
            $method, $target = @($lines[0] -split ' ')[0, 1]
            $path = ($target -split '\?')[0]
            $cookie = [bool]@($lines | Where-Object { $_ -match '^(?i)cookie\s*:' }).Count
            $code = 200; $type = 'text/html; charset=utf-8'; $body = ''; $extra = ''
            if ($target -eq '/') { $body = Get-Home ''; $extra = "Set-Cookie: visit=1; Path=/`r`n" }
            elseif ($target -eq '/?lang=ru') { $body = Get-Home '<meta name="robots" content="index, follow, max-image-preview:none">' }
            elseif ($target -eq '/?lang=uk') { $body = Get-Home ''; $extra = "X-Robots-Tag: googlebot: noindex`r`n" }
            elseif ($path -in '/robots.txt', '/sitemap.xml', '/llms.txt') { $code = 301; $extra = "Location: /moved.html`r`n" }
            elseif ($path -eq '/loop') { $code = 302; $extra = "Location: /loop`r`n" }
            elseif ($path -eq '/files/app.zip') { if ($method -eq 'HEAD') { $code = 404 } else { $type = 'application/zip'; $body = 'PK stub' } }
            elseif ($path -match '^/[\w/-]+\.html$') {
                $body = "<!doctype html><html lang=""en""><head><title>$path</title><meta name=""description"" content=""cookie $(if ($cookie) { 'sent' } else { 'none' })""></head><body><h1>$path</h1></body></html>"
            }
            else { $code = 404; $body = '<!doctype html><html><head><title>Not found</title></head><body><p>Not found.</p></body></html>' }
            $bytes = $utf8.GetBytes($body)
            $reason = @{ 200 = 'OK'; 301 = 'Moved Permanently'; 302 = 'Found'; 404 = 'Not Found' }[$code]
            $headBytes = [Text.Encoding]::ASCII.GetBytes("HTTP/1.1 $code $reason`r`nContent-Type: $type`r`nContent-Length: $($bytes.Length)`r`n$($extra)Connection: close`r`n`r`n")
            $stream.Write($headBytes, 0, $headBytes.Length)
            if ($method -ne 'HEAD') { $stream.Write($bytes, 0, $bytes.Length) }
            $stream.Flush()
        }
        catch { }
        finally { $client.Close() }
    }
}
$listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
$listener.Start()
$site = "http://127.0.0.1:$(([Net.IPEndPoint]$listener.LocalEndpoint).Port)/"
$stub = [powershell]::Create()
[void]$stub.AddScript($stubScript.ToString()).AddArgument($listener).AddArgument($site)
$stubRun = $stub.BeginInvoke()

# ---- runs, side by side -------------------------------------------------------------------------------------------

#   a = script arguments, out = the JSON path the run must (or must not) write; every run starts in $scratch
$runs = [ordered]@{
    offline = @{ a = @('-HtmlFile', $fixtureFile, '-Url', $pageUrl, '-Out', (Join-Path $scratch 'out\robot.json'), '-Offline'); out = (Join-Path $scratch 'out\robot.json') }
    bare    = @{ a = @('-HtmlFile', $bareFile, '-Url', 'https://fixture.example.org/tool/', '-Out', (Join-Path $scratch 'bare.json'), '-Offline'); out = (Join-Path $scratch 'bare.json') }
    cp1251  = @{ a = @('-HtmlFile', $cpFile, '-Url', 'https://fixture.example.org/tool/', '-Out', (Join-Path $scratch 'cp1251.json'), '-Offline'); out = (Join-Path $scratch 'cp1251.json') }
    live    = @{ a = @('-Url', $site, '-Pages', 'gone.htm', '-Out', (Join-Path $scratch 'live\robot.json')); out = (Join-Path $scratch 'live\robot.json') }
    nofile  = @{ a = @('-Url', $pageUrl, '-Out', (Join-Path $scratch 'r1.json'), '-Offline'); out = (Join-Path $scratch 'r1.json') }
    badnum  = @{ a = @('-HtmlFile', $fixtureFile, '-Url', $pageUrl, '-Out', (Join-Path $scratch 'r2.json'), '-Offline', '-MaxPages', 'abc'); out = (Join-Path $scratch 'r2.json') }
    relurl  = @{ a = @('-HtmlFile', $fixtureFile, '-Url', 'fixture.example.org/tool/', '-Out', (Join-Path $scratch 'r3.json'), '-Offline'); out = (Join-Path $scratch 'r3.json') }
    unknown = @{ a = @('-HtmlFile', $fixtureFile, '-Url', $pageUrl, '-Out', (Join-Path $scratch 'r4.json'), '-Offline', '-Bogus', '1'); out = (Join-Path $scratch 'r4.json') }
    outdir  = @{ a = @('-HtmlFile', $fixtureFile, '-Url', $pageUrl, '-Out', $dirOut, '-Offline'); out = (Join-Path $dirOut 'robot.json') }
    envout  = @{ a = @('-HtmlFile', $fixtureFile, '-Url', $pageUrl, '-Out', "Env:\$envName", '-Offline'); out = (Join-Path $scratch $envName) }
}
$results = @{}
try {
    $runs.GetEnumerator() | ForEach-Object -ThrottleLimit $runs.Count -Parallel {
        $psi = [Diagnostics.ProcessStartInfo]::new($using:pwshExe)
        foreach ($x in (@('-NoProfile', '-File', $using:script_) + $_.Value.a)) { $psi.ArgumentList.Add([string] $x) }
        $psi.WorkingDirectory = $using:scratch
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
        $psi.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
        $proc = [Diagnostics.Process]::Start($psi)
        $o = $proc.StandardOutput.ReadToEndAsync()
        $e = $proc.StandardError.ReadToEndAsync()
        if (-not $proc.WaitForExit(30000)) { $proc.Kill($true) }
        $proc.WaitForExit()
        [pscustomobject]@{ name = $_.Key; code = $proc.ExitCode; stdout = $o.Result.Trim(); stderr = $e.Result.Trim(); wrote = (Test-Path -LiteralPath $_.Value.out) }
    } | ForEach-Object { $results[$_.name] = $_ }
}
finally {
    $listener.Stop()
    [void]$stubRun.AsyncWaitHandle.WaitOne(3000)
    $stub.Dispose()
}

function Read-Run([string] $Name) {
    $r = $results[$Name]
    if (-not $r.wrote) { return $null }
    return [IO.File]::ReadAllText($runs[$Name].out) | ConvertFrom-Json
}
$off = $results['offline']
$raw = if ($off.wrote) { [IO.File]::ReadAllText($runs.offline.out) } else { '' }
$j = if ($raw) { $raw | ConvertFrom-Json } else { $null }
$p = if ($j) { @($j.pages)[0] } else { $null }
function Assert-Ran { Assert-That ($null -ne $p) "the offline run wrote no page: exit $($off.code) $($off.stdout) $($off.stderr)" }
$bj = Read-Run 'bare'; $bp = if ($bj) { @($bj.pages)[0] } else { $null }
$cj = Read-Run 'cp1251'; $cp = if ($cj) { @($cj.pages)[0] } else { $null }
$lj = Read-Run 'live'
function Assert-RanToo($Page, [string] $Name) { $r = $results[$Name]; Assert-That ($null -ne $Page) "the $Name run wrote no page: exit $($r.code) $($r.stdout) $($r.stderr)" }

try {
    Run-Case '1 exit 0 and the documented shape' {
        Assert-Equal $off.code 0 "exit ($($off.stderr))"
        Assert-That ($off.stdout -match '^robot-check: 1 page\(s\), 0 error\(s\), \d+ ms -> ') "summary: $($off.stdout)"
        Assert-Ran
        Assert-Equal (Get-Keys $j) 'tool,version,base,host,fetchedAt,userAgent,elapsedMs,errors,pages,site' 'top-level keys'
        Assert-Equal (Get-Keys $p) $pageKeys 'page keys'
        Assert-Equal (Get-Keys @($p.hreflang)[0]) 'lang,href,status,canonical,selfCanonical,reciprocal,noindex,isParam' 'hreflang keys'
        Assert-Equal (Get-Keys $p.ogImage) 'url,status,host,contentType,bytes,onSite,rawGithub' 'ogImage keys'
        Assert-Equal (Get-Keys @($p.jsonld)[0]) 'index,parseError,types,topLevelTypes,hasGraph,softwareApplication,raw' 'jsonld keys'
        Assert-Equal (Get-Keys @($p.jsonld)[0].softwareApplication) 'present,topLevel,nestedIn,has' 'softwareApplication keys'
        Assert-Equal (Get-Keys @($p.jsonld)[0].softwareApplication.has) 'name,operatingSystem,applicationCategory,softwareVersion,downloadUrl,installUrl,offers,aggregateRating,review,screenshot,author,license,softwareHelp,releaseNotes,privacyPolicy' 'has keys'
        Assert-Equal (Get-Keys $p.headings) 'h1,h1Count,h1NoJs,h1HasEmoji,h2Count,h3Count,roleHeadingSpans' 'headings keys'
        Assert-Equal (Get-Keys $p.images) 'count,noAlt,emptyAlt,noSize,lazy,items' 'images keys'
        Assert-Equal (Get-Keys @($p.images.items)[0]) 'src,alt,width,height,loading' 'image item keys'
        Assert-Equal (Get-Keys $p.links) 'internal,external,rawGithub,githubBlob,newTab,newTabNoHint,noreferrerOwnHost,checked,broken,downloads' 'links keys'
        Assert-Equal (Get-Keys @($p.links.downloads)[0]) 'href,text,status,finalUrl,versioned' 'download keys'
        Assert-Equal (Get-Keys @($p.scripts)[0]) 'src,sameOrigin,bytes,apiGithub,jsRewrites' 'script keys'
        Assert-Equal (Get-Keys @($p.statusPhrases)[0]) 'phrase,context' 'status phrase keys'
        Assert-Equal (Get-Keys $j.site) 'robots,hostRobots,sitemap,llms,notFound,redirects' 'site keys'
        Assert-Equal (Get-Keys $j.site.hostRobots) 'url,status,sitemaps,userAgents,disallow,aiCrawlers,body' 'hostRobots keys'
        Assert-Equal (Get-Keys $j.site.hostRobots.aiCrawlers) 'GPTBot,ClaudeBot,PerplexityBot,CCBot,Google-Extended' 'aiCrawlers keys'
        Assert-Equal (Get-Keys $j.site.sitemap) 'url,status,urls,lastmodDistinct,lastmodMissing,paramUrls,alternates,sampled,problems' 'sitemap keys'
        Assert-Equal (Get-Keys $j.site.notFound) 'url,status,bytes,title' 'notFound keys'
        Assert-Equal (Get-Keys $j.site.redirects.http) 'from,chain,final' 'http redirect keys'
        Assert-Equal $j.tool 'robot-check' 'tool'
        Assert-Equal $j.version 1 'version'
        Assert-Equal $j.base 'https://fixture.example.org/tool/' 'base'
        Assert-Equal $j.host 'https://fixture.example.org' 'host'
        Assert-That ($raw -match '"fetchedAt": "\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z"') 'fetchedAt is not UTC ISO 8601'
        Assert-Equal $j.userAgent 'Mozilla/5.0 (compatible; sza-site-audit/1; read-only)' 'userAgent'
        Assert-That ($j.elapsedMs -is [long] -and $j.elapsedMs -ge 0) "elapsedMs: $($j.elapsedMs)"
        Assert-Equal @($j.errors).Count 0 'errors'
        Assert-Equal @($j.pages).Count 1 'pages'
        Assert-Equal $p.url $pageUrl 'url'
        Assert-Equal $p.finalUrl $pageUrl 'finalUrl'
        Assert-That ($null -eq $p.status -and $null -eq $p.contentType -and @($p.redirects).Count -eq 0) 'offline status, content type or redirects not empty'
        Assert-Equal $p.bytes ([IO.File]::ReadAllBytes($fixtureFile).Length) 'bytes'
    }
    Run-Case '2 the head' {
        Assert-Ran
        Assert-Equal $p.lang 'en' 'lang'
        Assert-Equal $p.dataLang 'en' 'dataLang'
        Assert-Equal $p.title $title 'title'
        Assert-Equal $p.titleLength 50 'titleLength (the emoji is one text element)'
        Assert-Equal $p.titleHasEmoji $true 'titleHasEmoji'
        Assert-Equal $p.description $desc 'description'
        Assert-Equal $p.descriptionLength 170 'descriptionLength'
        Assert-Equal $p.viewport 'width=device-width, initial-scale=1' 'viewport'
        Assert-Equal $p.canonical 'https://fixture.example.org/tool/' 'canonical'
        Assert-Equal $p.canonicalAbsolute $true 'canonicalAbsolute'
        Assert-Equal $p.canonicalSelf $true 'canonicalSelf (index.html and the trailing slash normalised)'
        Assert-Equal $p.metaRobots 'index, follow' 'metaRobots'
    }
    Run-Case '3 hreflang' {
        Assert-Ran
        $h = @($p.hreflang)
        Assert-Equal $h.Count 3 'entries'
        Assert-Equal (($h | ForEach-Object { $_.lang }) -join ',') 'en,ru,x-default' 'langs'
        Assert-Equal $p.xDefault $true 'xDefault'
        foreach ($self in @($h[0], $h[2])) {
            Assert-Equal $self.href 'https://fixture.example.org/tool/' "$($self.lang) href"
            Assert-That ($null -eq $self.status) "$($self.lang) status should be null offline"
            Assert-Equal $self.canonical 'https://fixture.example.org/tool/' "$($self.lang) canonical"
            Assert-Equal $self.selfCanonical $true "$($self.lang) selfCanonical"
            Assert-Equal $self.reciprocal $true "$($self.lang) reciprocal"
            Assert-Equal $self.noindex $false "$($self.lang) noindex"
            Assert-Equal $self.isParam $false "$($self.lang) isParam"
        }
        Assert-Equal $h[1].href 'https://fixture.example.org/tool/?lang=ru' 'ru href'
        Assert-Equal $h[1].isParam $true 'ru isParam'
        Assert-That ($null -eq $h[1].status -and $null -eq $h[1].canonical -and $null -eq $h[1].selfCanonical -and $null -eq $h[1].reciprocal -and $null -eq $h[1].noindex) 'ru was measured with no network'
    }
    Run-Case '4 Open Graph and Twitter' {
        Assert-Ran
        Assert-Equal (Get-Keys $p.og) 'og:title,og:locale,og:locale:alternate,og:image' 'og keys'
        Assert-Equal $p.og.'og:title' 'Fixture Tool' 'og:title'
        Assert-Equal $p.ogLocale 'en_US' 'ogLocale'
        Assert-Equal (@($p.ogLocaleAlternate) -join ',') 'ru_RU,uk_UA' 'ogLocaleAlternate'
        Assert-Equal $p.ogImage.url 'https://raw.githubusercontent.com/fixture-owner/tool/main/card.png' 'ogImage.url'
        Assert-Equal $p.ogImage.host 'raw.githubusercontent.com' 'ogImage.host'
        Assert-Equal $p.ogImage.onSite $false 'ogImage.onSite'
        Assert-Equal $p.ogImage.rawGithub $true 'ogImage.rawGithub'
        Assert-That ($null -eq $p.ogImage.status -and $null -eq $p.ogImage.contentType -and $null -eq $p.ogImage.bytes) 'ogImage measured with no network'
        Assert-Equal (Get-Keys $p.twitter) 'twitter:card,twitter:title' 'twitter keys'
        Assert-Equal $p.twitter.'twitter:card' 'summary_large_image' 'twitter:card'
    }
    Run-Case '5 JSON-LD' {
        Assert-Ran
        $b = @($p.jsonld)
        Assert-Equal $b.Count 2 'blocks'
        $g = $b[0]
        Assert-Equal $g.index 0 'first index'
        Assert-That ($null -eq $g.parseError) "first block failed to parse: $($g.parseError)"
        Assert-Equal (@($g.types) -join ',') 'WebSite,WebPage,SoftwareApplication,Offer,Person' 'types (@graph walked)'
        Assert-Equal (@($g.topLevelTypes) -join ',') 'WebSite,WebPage' 'topLevelTypes'
        Assert-Equal $g.hasGraph $true 'hasGraph'
        $sa = $g.softwareApplication
        Assert-Equal $sa.present $true 'SoftwareApplication present'
        Assert-Equal $sa.topLevel $false 'SoftwareApplication topLevel'
        Assert-Equal $sa.nestedIn 'WebPage' 'SoftwareApplication nestedIn'
        $set = @($sa.has.PSObject.Properties | Where-Object { $_.Value } | ForEach-Object { $_.Name }) -join ','
        Assert-Equal $set 'name,operatingSystem,applicationCategory,softwareVersion,downloadUrl,offers,author' 'has'
        Assert-That ($g.raw.StartsWith('{"@context"')) "raw: $($g.raw.Substring(0, 20))"
        $bad = $b[1]
        Assert-Equal $bad.index 1 'second index'
        Assert-That ([bool]$bad.parseError) 'the broken block parsed'
        Assert-That (@($bad.types).Count -eq 0 -and @($bad.topLevelTypes).Count -eq 0 -and -not $bad.hasGraph -and -not $bad.softwareApplication.present) 'the broken block reported types'
        Assert-That ($bad.raw.Contains('"FAQPage"')) 'the broken block lost its raw text'
    }
    Run-Case '6 headings' {
        Assert-Ran
        $hd = $p.headings
        Assert-Equal (@($hd.h1) -join '|') "$h1Read|Second heading" 'h1'
        Assert-Equal $hd.h1Count 2 'h1Count (the commented h1 must not count)'
        Assert-Equal $hd.h1NoJs $h1Read 'h1NoJs (glued spans stay glued, a line break reads as a space)'
        Assert-Equal $hd.h1HasEmoji $false 'h1HasEmoji'
        Assert-Equal $hd.h2Count 1 'h2Count'
        Assert-Equal $hd.h3Count 1 'h3Count'
        Assert-Equal $hd.roleHeadingSpans 1 'roleHeadingSpans'
    }
    Run-Case '7 images' {
        Assert-Ran
        $im = $p.images
        Assert-Equal $im.count 3 'count'
        Assert-Equal $im.noAlt 1 'noAlt'
        Assert-Equal $im.emptyAlt 1 'emptyAlt'
        Assert-Equal $im.noSize 2 'noSize'
        Assert-Equal $im.lazy 1 'lazy'
        $items = @($im.items)
        Assert-Equal $items.Count 3 'items'
        Assert-That ($items[0].src -eq 'shot-a.png' -and $null -eq $items[0].alt -and $null -eq $items[0].width -and $null -eq $items[0].height -and $null -eq $items[0].loading) 'first item'
        Assert-That ($items[1].alt -eq '' -and $items[1].loading -eq 'lazy') 'second item'
        Assert-That ($items[2].alt -eq 'Main window' -and $items[2].width -eq '640' -and $null -eq $items[2].height) 'third item'
    }
    Run-Case '8 links' {
        Assert-Ran
        $l = $p.links
        Assert-Equal $l.internal 2 'internal (#fragment and mailto: left out)'
        Assert-Equal $l.external 6 'external'
        Assert-Equal $l.rawGithub 1 'rawGithub'
        Assert-Equal $l.githubBlob 1 'githubBlob'
        Assert-Equal $l.newTab 2 'newTab'
        Assert-Equal $l.newTabNoHint 1 'newTabNoHint'
        Assert-Equal $l.noreferrerOwnHost 1 'noreferrerOwnHost (the JSON-LD author host, not the stranger)'
        Assert-That (@($l.checked).Count -eq 0 -and @($l.broken).Count -eq 0) 'links were checked with no network'
        $d = @($l.downloads)
        Assert-Equal $d.Count 1 'downloads'
        Assert-Equal $d[0].href 'https://github.com/fixture-owner/tool/releases/download/v2.4.1/tool-2.4.1.zip' 'download href'
        Assert-Equal $d[0].text 'Download 2.4.1' 'download text'
        Assert-Equal $d[0].versioned $true 'download versioned'
        Assert-That ($null -eq $d[0].status -and $null -eq $d[0].finalUrl) 'download measured with no network'
    }
    Run-Case '9 language and text' {
        Assert-Ran
        Assert-Equal (Get-Keys $p.langSpans) 'en,ru,uk' 'langSpans keys'
        Assert-That ($p.langSpans.en -eq 2 -and $p.langSpans.ru -eq 2 -and $p.langSpans.uk -eq 2) "langSpans: $($p.langSpans | ConvertTo-Json -Compress)"
        Assert-Equal $p.textNoJs $visible.Substring(0, [Math]::Min(400, $visible.Length)) 'textNoJs'
        Assert-Equal $p.cyrillicChars ([regex]::Matches($visible, '[\p{IsCyrillic}]').Count) 'cyrillicChars'
        Assert-Equal $p.latinChars ([regex]::Matches($visible, '[A-Za-z]').Count) 'latinChars'
        Assert-Equal $p.appShell $false 'appShell'
        Assert-Equal (@($p.versions) -join ',') '2.4.1' 'versions (the address and the d.m.yyyy date are not)'
        $sp = @($p.statusPhrases)
        Assert-Equal $sp.Count 1 'statusPhrases (the commented one must not count)'
        Assert-Equal $sp[0].phrase 'coming soon' 'phrase'
        Assert-That ($sp[0].context.Contains('coming soon') -and $sp[0].context.Length -le 60) "context: $($sp[0].context)"
    }
    Run-Case '10 scripts' {
        Assert-Ran
        $s = @($p.scripts)
        Assert-Equal $s.Count 2 'script src entries'
        Assert-That ($s[0].src -eq '/tool/app.js' -and $s[0].sameOrigin -eq $true) "first script: $($s[0] | ConvertTo-Json -Compress)"
        Assert-That ($s[1].src -eq 'https://cdn.example.com/lib.js' -and $s[1].sameOrigin -eq $false) "second script: $($s[1] | ConvertTo-Json -Compress)"
        Assert-That ($null -eq $s[0].bytes -and $null -eq $s[0].apiGithub -and $null -eq $s[0].jsRewrites) 'a script was fetched with no network'
        Assert-Equal $p.jsRewrites 2 'jsRewrites (document.title and setAttribute content)'
        Assert-Equal $p.apiGithub 1 'apiGithub'
        Assert-Equal $p.rawGithubRefs 2 'rawGithubRefs'
    }
    Run-Case '11 the site block offline' {
        Assert-Ran
        $s = $j.site
        Assert-That ($s.robots.url -eq 'https://fixture.example.org/tool/robots.txt' -and $null -eq $s.robots.status) "robots: $($s.robots | ConvertTo-Json -Compress)"
        $hr = $s.hostRobots
        Assert-That ($hr.url -eq 'https://fixture.example.org/robots.txt' -and $null -eq $hr.status -and $null -eq $hr.body) "hostRobots: $($hr | ConvertTo-Json -Compress)"
        Assert-That (@($hr.sitemaps).Count -eq 0 -and @($hr.userAgents).Count -eq 0 -and @($hr.disallow).Count -eq 0) 'hostRobots lists not empty'
        Assert-That (@($hr.aiCrawlers.PSObject.Properties | Where-Object { $null -ne $_.Value }).Count -eq 0) 'aiCrawlers judged with no robots.txt read'
        $sm = $s.sitemap
        Assert-That ($sm.url -eq 'https://fixture.example.org/tool/sitemap.xml' -and $null -eq $sm.status -and $null -eq $sm.urls -and @($sm.sampled).Count -eq 0 -and @($sm.problems).Count -eq 0) "sitemap: $($sm | ConvertTo-Json -Compress)"
        Assert-Equal ((@($s.llms) | ForEach-Object { $_.url }) -join ',') 'https://fixture.example.org/llms.txt,https://fixture.example.org/tool/llms.txt' 'llms'
        Assert-That ($s.notFound.url.StartsWith('https://fixture.example.org/tool/robot-check-probe-') -and $null -eq $s.notFound.status) "notFound: $($s.notFound | ConvertTo-Json -Compress)"
        Assert-That ($s.redirects.http.from -eq 'http://fixture.example.org/tool/' -and @($s.redirects.http.chain).Count -eq 0 -and $null -eq $s.redirects.http.final) "http: $($s.redirects.http | ConvertTo-Json -Compress)"
        Assert-That ([string]$s.redirects.www.skipped -match 'offline') "www: $($s.redirects.www | ConvertTo-Json -Compress)"
    }
    Run-Case '12 bad invocations exit 2 and write nothing' {
        foreach ($name in @('nofile', 'badnum', 'relurl', 'unknown', 'outdir', 'envout')) {
            $r = $results[$name]
            Assert-Equal $r.code 2 "$name exit ($($r.stderr))"
            Assert-That ($r.stderr -match '^robot-check: ') "$name refusal line: $($r.stderr)"
            Assert-That (-not $r.wrote) "$name wrote its JSON"
        }
        Assert-Equal @(Get-ChildItem -LiteralPath $dirOut -Force).Count 0 'files in the folder -Out named'
    }
    Run-Case '13 what a page lacks reads null; the canonical in the body is ignored; a robots value is no noindex' {
        Assert-RanToo $bp 'bare'
        Assert-Equal $results['bare'].code 0 "exit ($($results['bare'].stderr))"
        Assert-That ($null -eq $bp.title -and $null -eq $bp.titleLength -and $null -eq $bp.titleHasEmoji) "title: [$($bp.title)] [$($bp.titleLength)] [$($bp.titleHasEmoji)]"
        Assert-That ($null -eq $bp.description -and $null -eq $bp.descriptionLength) "description: [$($bp.description)] [$($bp.descriptionLength)]"
        Assert-That ($null -eq $bp.canonical -and $null -eq $bp.canonicalAbsolute -and $null -eq $bp.canonicalSelf) "canonical read from the body: [$($bp.canonical)]"
        Assert-Equal $bp.metaRobots 'index, follow, max-image-preview:none' 'metaRobots'
        Assert-Equal @($bp.hreflang)[0].noindex $false 'noindex (max-image-preview:none is a value, not a directive)'
    }
    Run-Case '14 the long h1 whole, a "<!--" in an attribute, an unclosed <a name>' {
        Assert-RanToo $bp 'bare'
        $hd = $bp.headings
        Assert-Equal $hd.h1NoJs $longH1 'h1NoJs (every language of a 345-character h1)'
        Assert-Equal (@($hd.h1) -join '|') $longH1.Substring(0, 300) 'h1 (its first 300 characters)'
        Assert-Equal $hd.h1Count 1 'h1Count (the "<!--" in an attribute opens no comment)'
        Assert-That ($bp.textNoJs.StartsWith('x Русский') -and $bp.textNoJs.Contains('tail')) "textNoJs: $($bp.textNoJs)"
        Assert-Equal $bp.links.internal 2 'internal (an unclosed <a name> swallows no link)'
    }
    Run-Case '15 charsets: the byte order mark first, cp1251 as windows-1251' {
        Assert-RanToo $bp 'bare'
        Assert-That ("$($bp.headings.h1NoJs)".Contains($ukH1) -and $bp.cyrillicChars -gt 0) "the UTF-8 mark lost to the meta charset: $($bp.headings.h1NoJs)"
        Assert-RanToo $cp 'cp1251'
        Assert-Equal $cp.title $cpTitle 'title of the cp1251 page'
        Assert-Equal $cp.headings.h1NoJs $cpTitle 'h1 of the cp1251 page'
    }
    Run-Case '16 the stub site: the pages chosen, one copy of each, no cookie sent back, a 404 page unread' {
        $lr = $results['live']
        Assert-Equal $lr.code 0 "exit ($($lr.stderr))"
        Assert-That ($null -ne $lj) "the live run wrote no JSON: $($lr.stdout) $($lr.stderr)"
        $urls = @($lj.pages | ForEach-Object { $_.url }) -join ','
        Assert-Equal $urls ((@('', 'guide.html', 'install.html', 'privacy.html', 'trust.html', 'gone.htm') | ForEach-Object { $site + $_ }) -join ',') 'pages (no ru/ copy, no ?lang= variant, no helpers or supported, trust a kind of its own, the declared page without a kind last)'
        $hp = @($lj.pages)[0]
        Assert-Equal (Get-Keys $hp) $pageKeys 'page keys'
        Assert-Equal $hp.status 200 'home status'
        Assert-Equal @($lj.pages)[1].description 'cookie none' 'a page request carried the cookie the home page set'
        $gone = @($lj.pages)[5]
        Assert-Equal (Get-Keys $gone) $pageKeys 'page keys of the 404 page'
        Assert-That ($gone.status -eq 404 -and $gone.contentType -match 'html' -and $gone.bytes -gt 0) "the 404 page's answer: $($gone.status) $($gone.contentType) $($gone.bytes)"
        $parsed = @($gone.PSObject.Properties | Where-Object { $_.Name -notin 'url', 'status', 'finalUrl', 'redirects', 'bytes', 'contentType' -and $null -ne $_.Value } | ForEach-Object { $_.Name })
        Assert-Equal ($parsed -join ',') '' 'fields of the 404 page that are not null'
    }
    Run-Case '17 the stub site: hreflang targets, the download whose HEAD fails, the redirect loop' {
        Assert-That ($null -ne $lj) 'the live run wrote no JSON'
        $hp = @($lj.pages)[0]
        $h = @($hp.hreflang)
        Assert-Equal (($h | ForEach-Object { "$($_.lang)=$($_.status)" }) -join ',') 'en=200,ru=200,uk=200,x-default=200' 'hreflang statuses'
        Assert-That ($h[0].selfCanonical -eq $true -and $h[0].reciprocal -eq $true -and $h[0].noindex -eq $false -and $h[0].isParam -eq $false) "en: $($h[0] | ConvertTo-Json -Compress)"
        Assert-That ($h[1].canonical -eq $site -and $h[1].selfCanonical -eq $false -and $h[1].reciprocal -eq $true -and $h[1].isParam -eq $true) "ru: $($h[1] | ConvertTo-Json -Compress)"
        Assert-Equal $h[1].noindex $false 'ru noindex (max-image-preview:none)'
        Assert-Equal $h[2].noindex $true 'uk noindex (X-Robots-Tag: googlebot: noindex)'
        $d = @($hp.links.downloads)
        Assert-Equal $d.Count 1 'downloads'
        Assert-That ($d[0].status -eq 200 -and $d[0].finalUrl -eq "${site}files/app.zip") "download (HEAD 404, GET 200): $($d[0] | ConvertTo-Json -Compress)"
        Assert-Equal $hp.links.internal 10 'internal links'
        Assert-Equal @($hp.links.checked).Count 10 'checked links'
        $broken = @($hp.links.broken)
        Assert-That ($broken.Count -eq 1 -and $broken[0].url -eq "${site}loop" -and $broken[0].status -eq 302) "broken: $($broken | ConvertTo-Json -Compress)"
        Assert-Equal (@($lj.errors) -join ' | ') "link: ${site}loop - more than 10 redirects" 'errors'
    }
    Run-Case '18 the stub site: the site files report their 301, and the HTML page is no sitemap' {
        Assert-That ($null -ne $lj) 'the live run wrote no JSON'
        $s = $lj.site
        Assert-Equal $s.robots.status 301 'robots status'
        $hr = $s.hostRobots
        Assert-That ($hr.status -eq 301 -and @($hr.userAgents).Count -eq 0 -and "$($hr.body)".StartsWith('<!doctype html>')) "hostRobots: $($hr | ConvertTo-Json -Compress)"
        Assert-That (@($hr.aiCrawlers.PSObject.Properties | Where-Object { $_.Value -ne 'unmentioned' }).Count -eq 0) "aiCrawlers: $($hr.aiCrawlers | ConvertTo-Json -Compress)"
        $sm = $s.sitemap
        Assert-That ($sm.url -eq "${site}sitemap.xml" -and $sm.status -eq 301 -and $null -eq $sm.urls -and $null -eq $sm.lastmodDistinct -and @($sm.sampled).Count -eq 0) "sitemap: $($sm | ConvertTo-Json -Compress)"
        $pr = @($sm.problems)
        Assert-That ($pr.Count -eq 1 -and $pr[0].status -eq 200 -and $pr[0].note -eq "redirects to ${site}moved.html, an HTML page, not a sitemap") "sitemap problems: $($pr | ConvertTo-Json -Compress)"
        Assert-Equal ((@($s.llms) | ForEach-Object { "$($_.status) $($_.url)" }) -join ',') "301 ${site}llms.txt" 'llms'
        Assert-That ($s.notFound.status -eq 404 -and $s.notFound.title -eq 'Not found') "notFound: $($s.notFound | ConvertTo-Json -Compress)"
        Assert-That ([string]$s.redirects.www.skipped -match 'not a domain name') "www: $($s.redirects.www | ConvertTo-Json -Compress)"
    }
}
finally {
    if (-not $KeepScratch) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host ("robot-check tests: {0} run, {1} passed, {2} failed, {3:N1} s" -f $run, $passed, $failed, $clock.Elapsed.TotalSeconds)
exit $(if ($failed -eq 0) { 0 } else { 1 })
