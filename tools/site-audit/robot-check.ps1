#requires -Version 7.0
<#
.SYNOPSIS
    Read a published site the way a robot reads it - no JavaScript, GET and HEAD only - and write the evidence as JSON.

.DESCRIPTION
    The collect step of the site audit's robot lens: what a search crawler that runs no script, a social-card
    scraper and an AI crawler receive from one site. It measures and judges nothing; the lenses read the JSON.

    Pages: the home page first, then -Pages and the key pages the home page links to - an internal link under the
    base whose path below the base, or whose anchor text, names as a whole word docs, documentation, guide, help,
    install, download, privacy, changelog, whats-new, release-notes, support, faq or trust. Key pages (declared ones
    first) come before the rest of -Pages, one discovered page of each kind (docs, install, privacy, changes,
    support, trust) before a second of any kind, at most -MaxPages in all. A page's kind is read from its last path
    segment first, then from its whole path below the base, then from its anchor text. Of the discovered pages, one
    without a query comes first, then one in the home page's language (the language of the anchor's data-l,
    data-lang, hreflang or lang, else of a two-letter path segment or file-name part below the base, such as ru/ or
    .ru.), then document order decides. A discovered page that differs from the home page, a declared page or a
    listed page only by its query or by such a language part is a copy, and is skipped.

    Requests: GET and HEAD only, no cookies, User-Agent "Mozilla/5.0 (compatible; sza-site-audit/1; read-only)",
    25 s for each URL with its redirects, redirects followed by hand (at most 10) so every hop is recorded, HEAD
    falling back to GET when it answers 400 or more, at most 8 at a time (ForEach-Object -Parallel), and a run budget
    of 90 s: a request the budget stops, before it is sent or while it waits, is listed under errors and is read as
    not measured. Links, downloads, the social image, robots.txt at the base and llms.txt are checked with HEAD;
    pages, hreflang targets, scripts, the host robots.txt, the sitemap and the 404 probe are read with GET; a sampled
    sitemap URL is read with GET and its body kept only when it is HTML, because its canonical is in the body.

    -Offline parses one saved page and sends nothing. Every field that needs an answer is then null or empty, except
    the hreflang entries that point at the page itself, which are read from the page.

.PARAMETER Url
    The base URL of the site; a path without a file name gets its trailing slash. With -Offline, the URL the saved
    page was served from.

.PARAMETER Pages
    Pages to audit besides the home page, relative to the base, comma-separated or repeated.

.PARAMETER MaxPages
    Pages in all, home included, at least 1. Default 6.

.PARAMETER MaxLinks
    Internal links checked per page: distinct, in document order, fragment dropped. Default 40.

.PARAMETER MaxSitemap
    Sitemap URLs checked, evenly spaced over the sitemap. Default 60.

.PARAMETER Out
    The JSON file to write, on a file-system drive. Its folder is created when missing. A folder, a name no file can
    have, or a path of another provider (Env:, HKCU:) is refused before any request.

.PARAMETER HtmlFile
    The saved page -Offline parses.

.PARAMETER Offline
    Parse -HtmlFile only; no request of any kind.

.OUTPUTS
    The JSON file (UTF-8, no BOM) and one summary line on stdout. A field is null when the page lacks the item, or
    when nothing was fetched to measure it (-Offline, a failed request, a page that did not answer 2xx). Lengths
    are counted in text elements - the characters a reader sees, an emoji as one.

    tool, version        "robot-check", 1
    base                 the base URL, ending in "/"
    host                 scheme and authority of the base
    fetchedAt            the run's start, UTC, ISO 8601
    userAgent            the User-Agent every request sends
    elapsedMs            wall time of the run
    errors[]             "<role>: <url> - <reason>" for each request that got no usable answer (DNS, TLS, timeout,
                         more than 10 redirects, a body cut at the size cap) and for a home page that answered
                         other than 2xx, sorted by role; then each request the run budget stopped; at most 60 lines

    pages[], home first, each:
      url                the URL asked for
      status             the HTTP status where the redirects ended; null when no answer came
      finalUrl           the URL where the redirects ended
      redirects[]        each hop as {status, location}, location as the server sent it
      bytes              body size after decompression
      contentType        Content-Type of the final answer
      lang               the lang attribute of <html>
      dataLang           a data-lang or data-l attribute written on <html> or <body> in the HTML itself
      title, titleLength, titleHasEmoji
                         the <title> text, whitespace collapsed; all three null when the page has no title
      description, descriptionLength
                         meta name=description, whitespace collapsed; both null when the page has none
      viewport           meta name=viewport content
      canonical          the href of the rel=canonical link in the head, as written; one in the body is ignored,
                         as crawlers ignore it
      canonicalAbsolute  that href starts with http:// or https://
      canonicalSelf      the resolved canonical equals finalUrl, both read without index.html and the trailing slash
      metaRobots         meta name=robots content, in the head
      hreflang[]         each link rel=alternate with an hreflang, in the head:
        lang, href       as written
        status           the target's own answer; a redirect shows as its 3xx
        canonical        the target's rel=canonical href
        selfCanonical    that canonical equals the href (index.html and the trailing slash ignored)
        reciprocal       the target lists this page in its own hreflang links
        noindex          noindex or none among the directives of the target's meta robots or X-Robots-Tag header,
                         one scoped to a crawler ("googlebot: noindex") included; a value such as
                         max-image-preview:none is not one
        isParam          the href carries a query, such as ?lang=
      xDefault           an x-default entry exists
      og                 each meta property=og:* as {property: content}, the first of each
      ogLocale           og:locale
      ogLocaleAlternate[]  every og:locale:alternate
      ogImage            {url as written, status, host, contentType, bytes (Content-Length), onSite (same host as
                         the page), rawGithub (raw.githubusercontent.com or a GitHub /raw/ path)}, or null when the
                         page has no og:image
      twitter            each meta name=twitter:* (or property=twitter:*) as {name: content}
      jsonld[]           each script type=application/ld+json:
        index            0-based position among the page's blocks
        parseError       the strict JSON parser's message, or null; a block that does not parse reports no types
        types[]          every distinct @type, nested nodes and @graph members included
        topLevelTypes[]  the @type of the root node, of root array items and of @graph members
        hasGraph         the block holds an @graph
        softwareApplication
                         {present, topLevel, nestedIn (the @type of the node holding it), has: {name,
                         operatingSystem, applicationCategory, softwareVersion, downloadUrl, installUrl, offers,
                         aggregateRating, review, screenshot, author, license, softwareHelp, releaseNotes,
                         privacyPolicy: true when set and not empty}}; MobileApplication and WebApplication count,
                         and a top-level node is read before a nested one
        raw              the block's first 3000 characters
      headings           {h1[] (the text of each h1, its first 300 characters), h1Count, h1NoJs (the first h1 whole,
                         tags stripped and every language span in it, as a crawler without JavaScript reads it; cut
                         at 3000 characters only), h1HasEmoji (any h1), h2Count, h3Count, roleHeadingSpans
                         (elements with role=heading)}
      images             {count, noAlt (no alt attribute), emptyAlt (alt=""), noSize (width or height missing),
                         lazy (loading=lazy), items[] (the first 30 as {src, alt, width, height, loading})}
      links              anchors with an href; same-page #fragments, mailto:, tel: and javascript: are left out:
        internal, external   counted by host against the page's final host
        rawGithub        links to raw.githubusercontent.com or a GitHub /raw/ path
        githubBlob       links to a GitHub /blob/ file view
        newTab           links with a target other than _self, _parent or _top
        newTabNoHint     of those, links that say nothing of the new tab in their text, aria-label, title, an inner
                         alt or an icon class
        noreferrerOwnHost  rel=noreferrer on a link to this host or to a sibling site of the same owner: the same
                         registrable domain, a host named as the url of a Person, Organization or WebSite node of the
                         page's JSON-LD or by rel=me or rel=author, or <login>.github.io of a GitHub login the page's
                         host or its JSON-LD names
        checked[]        {url, status} of the first -MaxLinks distinct internal links, fragment dropped, query kept
        broken[]         {url, status, finalUrl} of the checked links that did not end in 2xx
        downloads[]      {href, text, status, finalUrl, versioned (a version number in the URL)} for links with a
                         download attribute, a package or archive file name, a GitHub releases path, or a store or
                         package-directory listing
      langSpans          {value: count} of the elements inside <body> carrying data-l, data-lang or lang (read in
                         that order), values lowercased
      cyrillicChars, latinChars
                         letters of each script in the visible text
      textNoJs           the first 400 characters of the visible text: <body> without scripts, styles and templates,
                         tags stripped, whitespace collapsed
      appShell           visible text under 200 characters, or a Loading placeholder (Loading, Загрузка or
                         Завантаження followed by dots or an ellipsis) on a page of under 100 words
      scripts[]          each script src as {src as written, sameOrigin, bytes, apiGithub, jsRewrites}; the last
                         three only for the first 5 same-origin scripts, which are fetched
      jsRewrites         document.title assignments, setAttribute('content' calls and .content assignments on a
                         queried meta element, in inline and fetched scripts
      apiGithub          occurrences of api.github.com in the HTML and in the fetched scripts
      rawGithubRefs      occurrences of raw.githubusercontent.com in the HTML
      versions[]         distinct version-like strings in the visible text (1.2.3, v1.2, "version 1.2"), first 8;
                         a d.m.yyyy date and a loopback, private or public-resolver address (127.0.0.1) are not
      statusPhrases[]    {phrase, context (60 characters around it)} for coming soon, in development, not released,
                         not yet, beta, experimental, скоро, в разработке, ещё не, экспериментально, у розробці,
                         ще не; at most 20

    site:                the status of robots, hostRobots, sitemap and llms[] is the first answer, so a redirect
                         shows as its 3xx; the host robots.txt and the sitemap are read where their redirects end
      robots             {url (base + robots.txt), status}
      hostRobots         the file crawlers obey: {url (host + /robots.txt), status, sitemaps[], userAgents[],
                         disallow[] ("<user-agents>: <path>"), aiCrawlers {GPTBot, ClaudeBot, PerplexityBot, CCBot,
                         Google-Extended: "blocked" (a group naming it disallows /), "allowed" (named, not blocked),
                         "unmentioned" (no group names it, so the * group applies), null when unread}, body (the
                         first 3000 characters)}
      sitemap            {url (base + sitemap.xml, or the Sitemap: line of the host robots.txt under the base when
                         that one does not end in 2xx or ends in an HTML page), status, urls, lastmodDistinct,
                         lastmodMissing, paramUrls (a query in loc), alternates (xhtml:link elements), sampled[]
                         ({url, status, finalUrl}, at most -MaxSitemap, evenly spaced), problems[] ({url, status,
                         note} for a sampled URL that redirects, does not answer 2xx, canonicalises elsewhere, is
                         noindex or leaves the host, for a sitemap index, whose child sitemaps are not followed, and
                         for an HTML page where the sitemap belongs, which is not parsed)}; the counts are null when
                         no sitemap was parsed
      llms[]             {url, status} of /llms.txt at the host root and llms.txt at the base
      notFound           {url (a path under the base that cannot exist), status (where the redirects end), bytes,
                         title}
      redirects          {http: {from (the base over http), chain[] ({status, location}), final (null when the chain
                         broke)}, www: the same for the www variant (the apex for a www host), or {skipped: reason}
                         for a hosting-platform subdomain, any other subdomain, an address that is not a domain
                         name, or -Offline}

.EXAMPLE
    pwsh -NoProfile -File tools/site-audit/robot-check.ps1 -Url https://example.org/app/ -Pages privacy.html -Out robot.json

.EXAMPLE
    pwsh -NoProfile -File tools/site-audit/robot-check.ps1 -HtmlFile saved.html -Url https://example.org/app/ -Out robot.json -Offline

Exit codes:
  0  the JSON was written
  1  the home page could not be fetched (no answer, or an answer other than 2xx); the JSON is still written and
     says why under "errors"
  2  bad invocation; nothing is written. A parameter given without its value fails in PowerShell's own binder before
     this script runs, and PowerShell then exits 1.
#>
[CmdletBinding(PositionalBinding = $false)]
param(
    [string]$Url = '',
    [string[]]$Pages = @(),
    [string]$MaxPages = '6',
    [string]$MaxLinks = '40',
    [string]$MaxSitemap = '60',
    [string]$Out = '',
    [string]$HtmlFile = '',
    [switch]$Offline,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Rest = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$clock = [Diagnostics.Stopwatch]::StartNew()
$fetchedAt = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture)
$userAgent = 'Mozilla/5.0 (compatible; sza-site-audit/1; read-only)'
$timeoutSec = 25
$maxHops = 10
$throttle = 8
$runBudgetSec = 90
$deadline = [DateTime]::UtcNow.AddSeconds($runBudgetSec).Ticks

function Write-Refusal([string]$Message) { [Console]::Error.WriteLine("robot-check: $Message") }

function Read-Count([string]$Value, [string]$Name, [int]$Min) {
    $n = 0
    if (-not [int]::TryParse($Value, [ref]$n) -or $n -lt $Min) { Write-Refusal "-$Name must be a whole number of at least $Min, got '$Value'"; exit 2 }
    return $n
}

# ---- invocation ---------------------------------------------------------------------------------------------------

if (@($Rest).Count) { Write-Refusal "unknown argument(s): $($Rest -join ' ')"; exit 2 }
$maxPagesN = Read-Count $MaxPages 'MaxPages' 1
$maxLinksN = Read-Count $MaxLinks 'MaxLinks' 0
$maxSitemapN = Read-Count $MaxSitemap 'MaxSitemap' 0
$pageArgs = @(@($Pages) | ForEach-Object { "$_" -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
if (-not $Url) { Write-Refusal '-Url is required: the base URL of the site, or with -Offline the URL the saved page came from'; exit 2 }
$inputUri = $null
if (-not [Uri]::TryCreate($Url.Trim(), [UriKind]::Absolute, [ref]$inputUri) -or $inputUri.Scheme -notin 'http', 'https') { Write-Refusal "-Url must be an absolute http(s) URL, got '$Url'"; exit 2 }
if (-not $Out) { Write-Refusal '-Out is required: the JSON file to write'; exit 2 }
if ($Offline -and -not $HtmlFile) { Write-Refusal '-Offline needs -HtmlFile, the saved page to parse'; exit 2 }
if ($HtmlFile -and -not $Offline) { Write-Refusal '-HtmlFile is parsed only with -Offline; add it, or drop -HtmlFile to fetch the live site'; exit 2 }
if ($Offline -and $pageArgs.Count) { Write-Refusal '-Pages has no effect with -Offline, which parses one saved page'; exit 2 }
if ($HtmlFile -and -not (Test-Path -LiteralPath $HtmlFile -PathType Leaf)) { Write-Refusal "saved page not found: $HtmlFile"; exit 2 }
# -Out is a file on a file-system drive, checked before any request: not a folder, not Env: or another provider.
$outPath = $null; $outProvider = $null
try { $outDrive = $null; $outPath = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Out, [ref]$outProvider, [ref]$outDrive) } catch { $outProvider = $null }
if ($null -eq $outProvider -or $outProvider.Name -ne 'FileSystem' -or -not [IO.Path]::GetFileName($outPath) -or [IO.Path]::GetFileName($outPath).IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0 -or (Test-Path -LiteralPath $outPath -PathType Container)) {
    Write-Refusal "-Out must name a file on a file-system drive, got '$Out'"; exit 2
}

# ---- patterns -----------------------------------------------------------------------------------------------------

# One attribute list as HTML writes it: name, name=value, name="value" or name='value'; a quoted value may hold '>'.
$AttrList = '(?:\s+[^\s"''>/=]+(?:\s*=\s*(?:"[^"]*"|''[^'']*''|[^\s"''=<>`]+))?)*'
$rxOpt = [Text.RegularExpressions.RegexOptions]'IgnoreCase, CultureInvariant'
$rxOptS = [Text.RegularExpressions.RegexOptions]'IgnoreCase, CultureInvariant, Singleline'
function New-Rx([string]$Pattern, [switch]$Singleline) { return [regex]::new($Pattern, $(if ($Singleline) { $rxOptS } else { $rxOpt })) }
function New-TagRx([string]$Name) { return New-Rx ('<' + $Name + '(?![\w:-])(' + $AttrList + ')\s*/?>') }
function New-ElementRx([string]$Name) { return New-Rx ('<' + $Name + '(?![\w:-])(' + $AttrList + ')\s*>(.*?)</' + $Name + '\s*>') -Singleline }

$rxAttr = New-Rx '([^\s"''>/=]+)(?:\s*=\s*(?:"([^"]*)"|''([^'']*)''|([^\s"''=<>`]+)))?'
# Comments and raw-text elements in document order, so a commented-out script is dropped, not read. Any other start
# tag is matched whole and kept, so a "<!--" inside an attribute value opens no comment.
$rxRaw = New-Rx ('<!--.*?-->|<(?<tag>script|style|template)(?![\w:-])(?<attrs>' + $AttrList + ')\s*/?>(?<body>.*?)</\k<tag>\s*>|(?<open><[a-zA-Z][\w:-]*' + $AttrList + '\s*/?>)') -Singleline
$rxHtmlTag = New-TagRx 'html'
$rxBodyTag = New-TagRx 'body'
$rxBaseTag = New-TagRx 'base'
$rxMetaTag = New-TagRx 'meta'
$rxLinkTag = New-TagRx 'link'
$rxImgTag = New-TagRx 'img'
$rxH1Tag = New-TagRx 'h1'
$rxH2Tag = New-TagRx 'h2'
$rxH3Tag = New-TagRx 'h3'
$rxTitle = New-ElementRx 'title'
$rxH1 = New-ElementRx 'h1'
# An anchor ends before the next one opens, so an unclosed <a name> swallows no link.
$rxA = New-Rx ('<a(?![\w:-])(' + $AttrList + ')\s*>((?:(?!<a(?![\w:-])).)*?)</a\s*>') -Singleline
$rxOpenTag = New-Rx ('<([a-zA-Z][\w:-]*)(' + $AttrList + ')\s*/?>')
$rxLangAttr = New-Rx '(?:^|\s)(?:data-lang|data-l|lang)\s*='
$rxRoleAttr = New-Rx '(?:^|\s)role\s*=\s*["'']?heading(?![\w-])'
$rxBlockTag = New-Rx ('</?(?:address|article|aside|blockquote|br|button|caption|dd|details|dialog|div|dl|dt|fieldset|figcaption|figure|footer|form|h[1-6]|header|hr|img|input|label|legend|li|main|nav|ol|option|p|pre|section|select|summary|table|tbody|td|textarea|tfoot|th|thead|tr|ul)(?![\w:-])' + $AttrList + '\s*/?>')
$rxAnyTag = New-Rx ('</?[a-zA-Z][\w:-]*' + $AttrList + '\s*/?>|<![^>]*>|<\?[^>]*>')
$rxSpace = [regex]::new('\s+')
$rxCyrillic = [regex]::new('[\p{IsCyrillic}\p{IsCyrillicSupplement}]')
$rxLatin = [regex]::new('[\p{L}-[^\p{IsBasicLatin}\p{IsLatin-1Supplement}\p{IsLatinExtended-A}\p{IsLatinExtended-B}]]')
$rxVersion = New-Rx '(?<![\w.])v?\d{1,4}\.\d{1,4}\.\d{1,5}(?:\.\d{1,5})?(?!\.?\d)|(?<![\w.])v\d{1,4}\.\d{1,4}(?!\.?\d)|(?<=\b(?:version|ver\.|версия|версии|версія|версії)\s{0,3})\d{1,4}\.\d{1,4}(?!\.?\d)'
$rxDateLike = [regex]::new('^\d{1,2}\.\d{1,2}\.(?:19|20)\d{2}$')
# A loopback, private, link-local or public-resolver address reads like a four-part version and is none.
$rxAddress = [regex]::new('^(?:(?:0|10|127|255)\.\d{1,3}\.\d{1,3}\.\d{1,3}|192\.168\.\d{1,3}\.\d{1,3}|172\.(?:1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3}|169\.254\.\d{1,3}\.\d{1,3}|1\.1\.1\.1|1\.0\.0\.1|8\.8\.[48]\.[48])$')
$rxStatus = New-Rx '(?<!\w)(?:coming soon|in development|not released|not yet|beta|experimental|скоро|в разработке|ещё не|еще не|экспериментально|у розробці|ще не)(?!\w)'
$rxRewrite = New-Rx ('document\.title\s*=(?!=)|setAttribute\(\s*[''"`]content[''"`]|querySelector\(\s*([''"`])meta\b[^\r\n]*?\1\s*\)\s*\.content\s*=(?!=)')
$rxApiGithub = New-Rx 'api\.github\.com'
$rxRawGithub = New-Rx 'raw\.githubusercontent\.com'
$rxHintAttr = New-Rx '(?:^|\s)(?:aria-label|title|alt|class)\s*=\s*(?:"(?<v>[^"]*)"|''(?<v>[^'']*)'')'
# Arrow glyphs that mark an outgoing link: north-east arrow, its double form, two joined squares, the heavy form.
$outArrows = -join @([char]0x2197, [char]0x21D7, [char]0x29C9, [char]0x2B08)
$rxNewTabHint = New-Rx ('(?:new|separate)\s+(?:tab|window)|opens?\s+(?:in\s+)?(?:a\s+)?new|external|нов(?:ой|ую|ом|ая|ое|ій|у|ому)\s+(?:вкладк|окн|вікн)|[' + $outArrows + ']|(?:^|\s)(?:ext-link|new-?tab|new-?window|bi-box-arrow-up-right)(?:\s|$)')
$rxDownloadFile = New-Rx '\.(?:exe|msi|msix|msixbundle|appx|appxbundle|appinstaller|zip|7z|rar|gz|tgz|bz2|xz|dmg|pkg|deb|rpm|apk|aab|appimage|jar|iso|whl|nupkg|vsix|xpi|crx|snap)$'
$rxListing = New-Rx '^https?://(?:www\.)?(?:github\.com/[^/]+/[^/]+/releases(?:/|$)|apps\.microsoft\.com/|microsoft\.com/(?:[a-z]{2}-[a-z]{2}/)?(?:store|p)/|play\.google\.com/store/apps|apps\.apple\.com/|f-droid\.org/(?:[a-z_-]+/)?packages/|marketplace\.visualstudio\.com/items|addons\.mozilla\.org/|chromewebstore\.google\.com/|chrome\.google\.com/webstore|community\.chocolatey\.org/packages|snapcraft\.io/|flathub\.org/apps|winget\.run/|winstall\.app/)'
$rxUrlVersion = New-Rx '(?<![0-9a-z])v?\d+\.\d+'
$rxPageFile = New-Rx '\.(?:html?|xhtml|php|aspx?|jsp|shtml)$'
$rxLoading = New-Rx ('(?<!\w)(?:loading|загрузка|завантаження)\s*(?:\.{2,}|' + [char]0x2026 + ')')

# Kinds of key pages, in the order one of each is taken; each names a whole word, so helpers.html is no help page.
$keyKinds = [ordered]@{
    docs    = New-Rx '(?<![a-z])(?:docs?|documentation|guides?|help)(?![a-z])'
    install = New-Rx '(?<![a-z])(?:install(?:ation|er|ing)?|downloads?)(?![a-z])'
    privacy = New-Rx '(?<![a-z])privacy(?![a-z])'
    changes = New-Rx ('(?<![a-z])(?:change[-_ ]?logs?|what[''' + [char]0x2019 + ']?s[-_ ]?new|release[-_ ]?notes)(?![a-z])')
    support = New-Rx '(?<![a-z])(?:support|faqs?)(?![a-z])'
    trust   = New-Rx '(?<![a-z])trust(?![a-z])'
}
# A language segment or file-name part of a path below the base: ru/ in ru/guide.html, .ru in guide.ru.html, pt-br/.
$rxLangPart = New-Rx '(?<=^|/)[a-z]{2}(?:-(?:[a-z]{2}|hans|hant|latn|cyrl))?(?:/|$)|\.[a-z]{2}(?:-(?:[a-z]{2}|hans|hant|latn|cyrl))?(?=\.[a-z]+$)'
# Charset labels as browsers read them (the WHATWG Encoding Standard) where .NET reads them otherwise or not at all;
# cp1250 to cp1258 and x-cp1250 to x-cp1258 are windows-1250 to windows-1258.
$charsetLabels = @{
    'utf8' = 'utf-8'; 'unicode11utf8' = 'utf-8'; 'unicode20utf8' = 'utf-8'; 'x-unicode20utf8' = 'utf-8'
    'ascii' = 'windows-1252'; 'us-ascii' = 'windows-1252'; 'ansi_x3.4-1968' = 'windows-1252'; 'iso-8859-1' = 'windows-1252'
    'iso8859-1' = 'windows-1252'; 'iso88591' = 'windows-1252'; 'iso_8859-1' = 'windows-1252'; 'iso-ir-100' = 'windows-1252'
    'latin1' = 'windows-1252'; 'l1' = 'windows-1252'; 'cp819' = 'windows-1252'; 'ibm819' = 'windows-1252'; 'csisolatin1' = 'windows-1252'
    '866' = 'ibm866'; 'csibm866' = 'ibm866'; 'koi8_r' = 'koi8-r'; 'iso8859-5' = 'iso-8859-5'; 'iso88595' = 'iso-8859-5'
    'csunicode' = 'utf-16le'; 'unicodefeff' = 'utf-16le'; 'x-gbk' = 'gbk'; 'windows-31j' = 'shift_jis'; 'ms932' = 'shift_jis'
    'windows-949' = 'euc-kr'; 'x-user-defined' = 'windows-1252'
}
$saTypes = @('SoftwareApplication', 'MobileApplication', 'WebApplication')
$saProps = @('name', 'operatingSystem', 'applicationCategory', 'softwareVersion', 'downloadUrl', 'installUrl', 'offers', 'aggregateRating', 'review', 'screenshot', 'author', 'license', 'softwareHelp', 'releaseNotes', 'privacyPolicy')
$aiBots = @('GPTBot', 'ClaudeBot', 'PerplexityBot', 'CCBot', 'Google-Extended')
# Each subdomain of these is its own site, so a shared suffix proves no common owner.
$platformSuffixes = @('github.io', 'gitlab.io', 'codeberg.page', 'netlify.app', 'vercel.app', 'pages.dev', 'web.app', 'firebaseapp.com', 'herokuapp.com', 'azurewebsites.net', 'azurestaticapps.net', 'onrender.com', 'fly.dev', 'surge.sh', 'glitch.me', 'neocities.org', 'blogspot.com', 'wordpress.com', 'readthedocs.io', 'sourceforge.io')
$roleOrder = @('home', 'page', 'robots.txt', 'host robots.txt', 'sitemap', 'sitemap url', 'llms.txt', '404 probe', 'http redirect', 'www redirect', 'hreflang', 'link', 'download', 'og:image', 'script')

# ---- text and URL helpers -----------------------------------------------------------------------------------------

function Get-Attrs([string]$Text) {
    $d = [ordered]@{}
    if (-not $Text) { return $d }
    foreach ($m in $rxAttr.Matches($Text)) {
        $name = $m.Groups[1].Value.ToLowerInvariant()
        if ($d.Contains($name)) { continue }   # HTML keeps the first of a repeated attribute
        $v = if ($m.Groups[2].Success) { $m.Groups[2].Value } elseif ($m.Groups[3].Success) { $m.Groups[3].Value } elseif ($m.Groups[4].Success) { $m.Groups[4].Value } else { '' }
        $d[$name] = [System.Net.WebUtility]::HtmlDecode($v)
    }
    return $d
}

# The text helpers take an untyped value: a [string] parameter turns $null into '', and a missing item is null.
function Format-Space($Text) { if ($null -eq $Text) { return $null }; return $rxSpace.Replace([string]$Text, ' ').Trim() }

# Visible text as a parser without scripting reads it: block tags break words, inline tags join them.
function Get-Text([string]$Fragment) {
    if (-not $Fragment) { return '' }
    $t = $rxBlockTag.Replace($Fragment, ' ')
    $t = $rxAnyTag.Replace($t, '')
    return Format-Space ([System.Net.WebUtility]::HtmlDecode($t))
}

function Get-Head($Text, [int]$Max) {
    if ($null -eq $Text) { return $null }
    $t = [string]$Text
    if ($t.Length -le $Max) { return $t }
    $n = $Max
    if ([char]::IsHighSurrogate($t[$n - 1])) { $n-- }
    return $t.Substring(0, $n)
}

function Get-TextLength($Text) { if ($null -eq $Text) { return $null }; return [Globalization.StringInfo]::new([string]$Text).LengthInTextElements }

function Test-Emoji([string]$Text) {
    if (-not $Text) { return $false }
    foreach ($r in $Text.EnumerateRunes()) {
        $v = $r.Value
        if (($v -ge 0x1F000 -and $v -le 0x1FAFF) -or ($v -ge 0x2600 -and $v -le 0x27BF) -or ($v -ge 0x2B00 -and $v -le 0x2BFF) -or ($v -ge 0x2300 -and $v -le 0x23FF) -or $v -eq 0xFE0F) { return $true }
    }
    return $false
}

function ConvertTo-Uri([string]$Text) {
    $u = $null
    if ($Text -and [Uri]::TryCreate($Text.Trim(), [UriKind]::Absolute, [ref]$u) -and $u.Scheme -in 'http', 'https') { return $u }
    return $null
}

function Resolve-Href([Uri]$Base, [string]$Href) {
    if ($null -eq $Href -or $null -eq $Base) { return $null }
    $h = $Href.Trim()
    if (-not $h -or $h -match '^(?i)(?:mailto|tel|sms|javascript|data|blob|about|file|ftp):') { return $null }
    $u = $null
    if (-not [Uri]::TryCreate($Base, $h, [ref]$u)) { return $null }
    if ($u.Scheme -ne 'http' -and $u.Scheme -ne 'https') { return $null }
    return $u
}

function Get-Bare([Uri]$U) { return $U.GetLeftPart([UriPartial]::Query) }

# The form two URLs are compared in: index.html and the trailing slash dropped, host lowercased, query kept.
function Get-UrlKey([string]$Text) {
    $u = ConvertTo-Uri $Text
    if (-not $u) { return $Text }
    $path = [regex]::Replace($u.AbsolutePath, '(?i)/index\.html?$', '/').TrimEnd('/')
    return $u.Scheme + '://' + $u.Authority.ToLowerInvariant() + $path + $u.Query
}

function Get-DirUrl([Uri]$U) {
    $path = $U.AbsolutePath
    if (-not $path.EndsWith('/')) {
        $cut = $path.LastIndexOf('/') + 1
        $path = if ($path.Substring($cut).Contains('.')) { $path.Substring(0, $cut) } else { "$path/" }
    }
    return $U.GetLeftPart([UriPartial]::Authority) + $path
}

function Get-SiteKey([string]$HostName) {
    $h = $HostName.ToLowerInvariant()
    foreach ($s in $platformSuffixes) { if ($h -eq $s -or $h.EndsWith(".$s")) { return $h } }
    $labels = $h.Split('.')
    if ($labels.Count -le 2) { return $h }
    # A short second level under a two-letter country code (co.uk, com.ua) keeps three labels.
    if ($labels[-1].Length -eq 2 -and $labels[-2].Length -le 3) { return ($labels[-3..-1] -join '.') }
    return ($labels[-2..-1] -join '.')
}

function Get-RelTokens($Attrs) { return @(([string]$Attrs['rel']).ToLowerInvariant() -split '\s+' | Where-Object { $_ }) }

# noindex or none among the directives of a meta robots content or an X-Robots-Tag header: comma-separated, each one
# optionally scoped to a crawler ("googlebot: noindex"). A directive with a value (max-image-preview:none) is not one.
function Test-NoIndex([string]$Text) {
    foreach ($t in ($Text -split ',')) {
        $v = $t.Trim().ToLowerInvariant()
        if ($v -match '^(?!max-|unavailable_after)[\w-]+\s*:\s*(.+)$') { $v = $Matches[1].Trim() }
        if ($v -match '^(?:max-|unavailable_after)') { continue }
        foreach ($w in ($v -split '\s+')) { if ($w -in 'noindex', 'none') { return $true } }
    }
    return $false
}

# The primary subtag of a language tag, lowercased: en-US reads en.
function Get-LangPrimary([string]$Tag) { return ($Tag.Trim() -split '[-_]')[0].ToLowerInvariant() }

# One key for a page and its copies - its query variants and its language copies (ru/guide.html, guide.ru.html) - and
# the language such a copy names. Only the path below the base is read for a language part.
function Get-Variant([Uri]$U, [string]$BasePath) {
    $head = ''
    $path = $U.AbsolutePath
    if ($path.StartsWith($BasePath, [StringComparison]::Ordinal)) { $head = $BasePath; $path = $path.Substring($BasePath.Length) }
    $m = $rxLangPart.Match($path)
    $path = [regex]::Replace($rxLangPart.Replace($path, ''), '(?i)(?:^|/)index\.html?$', '')
    return @{ key = $U.Authority.ToLowerInvariant() + $head + $path.TrimEnd('/'); lang = $(if ($m.Success) { $m.Value.Trim('/', '.') } else { '' }) }
}

function Get-Encoding([string]$Label) {
    $l = $Label.Trim('"', "'", ' ').ToLowerInvariant()
    if (-not $l) { return $null }
    $l = $charsetLabels[$l] ?? $l
    if ($l -match '^(?:x-)?cp(125\d)$') { $l = "windows-$($Matches[1])" }
    try { return [Text.Encoding]::GetEncoding($l) } catch { return $null }
}

# The encoding a browser picks: a byte order mark first, then the Content-Type charset, then a meta charset in the
# first 2048 bytes, else UTF-8. A label no browser knows is passed over, as browsers pass it over.
function ConvertFrom-Bytes([byte[]]$Bytes, [string]$Charset) {
    if ($null -eq $Bytes) { return $null }
    $enc = $null; $skip = 0
    if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF) { $enc = [Text.UTF8Encoding]::new($false); $skip = 3 }
    elseif ($Bytes.Length -ge 2 -and $Bytes[0] -eq 0xFF -and $Bytes[1] -eq 0xFE) { $enc = [Text.Encoding]::Unicode; $skip = 2 }
    elseif ($Bytes.Length -ge 2 -and $Bytes[0] -eq 0xFE -and $Bytes[1] -eq 0xFF) { $enc = [Text.Encoding]::BigEndianUnicode; $skip = 2 }
    if (-not $enc -and $Charset) { $enc = Get-Encoding $Charset }
    if (-not $enc) {
        $probe = [Text.Encoding]::ASCII.GetString($Bytes, 0, [Math]::Min(2048, $Bytes.Length))
        if ($probe -match '(?i)<meta[^>]+charset\s*=\s*["'']?\s*([\w.-]+)') { $enc = Get-Encoding $Matches[1] }
        # A meta charset naming UTF-16 was itself read as ASCII bytes, so the page is not UTF-16: browsers read UTF-8.
        if ($enc -and $enc.CodePage -in 1200, 1201) { $enc = [Text.Encoding]::UTF8 }
    }
    if (-not $enc) { $enc = [Text.Encoding]::UTF8 }
    $text = $enc.GetString($Bytes, $skip, $Bytes.Length - $skip)
    if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) { $text = $text.Substring(1) }
    return $text
}

# ---- JSON-LD ------------------------------------------------------------------------------------------------------

function ConvertFrom-JsonNode($El) {
    switch ($El.ValueKind.ToString()) {
        'Object' {
            $d = [System.Collections.Specialized.OrderedDictionary]::new([StringComparer]::Ordinal)
            foreach ($p in $El.EnumerateObject()) { $d[$p.Name] = ConvertFrom-JsonNode $p.Value }
            return $d
        }
        'Array' {
            $l = [System.Collections.Generic.List[object]]::new()
            foreach ($x in $El.EnumerateArray()) { $l.Add((ConvertFrom-JsonNode $x)) }
            return , $l
        }
        'String' { return $El.GetString() }
        'Number' { return $El.GetRawText() }
        'True' { return $true }
        'False' { return $false }
        default { return $null }
    }
}

function Read-JsonLd([string]$Text) {
    $t = [regex]::Replace($Text.Trim(), '^(?://\s*)?<!\[CDATA\[|(?://\s*)?\]\]>$', '').Trim()
    $block = @{ data = $null; error = $null; raw = (Get-Head $Text.Trim() 3000) }
    try {
        $jd = [System.Text.Json.JsonDocument]::Parse($t)
        try { $block.data = ConvertFrom-JsonNode $jd.RootElement } finally { $jd.Dispose() }
    }
    catch {
        $e = $_.Exception
        while ($null -ne $e.InnerException) { $e = $e.InnerException }
        $block.error = $e.Message
    }
    return $block
}

function Get-LocalType([string]$Type) { return ($Type -split '[/#:]')[-1] }

function Get-NodeTypes($Node) {
    if ($Node -isnot [System.Collections.IDictionary] -or -not $Node.Contains('@type')) { return @() }
    $t = $Node['@type']
    if ($t -is [string]) { return @($t) }
    if ($t -is [System.Collections.IList]) { return @($t | Where-Object { $_ -is [string] }) }
    return @()
}

function Get-Strings($Value) {
    if ($Value -is [string]) { return @($Value) }
    if ($Value -is [System.Collections.IList]) { return @($Value | Where-Object { $_ -is [string] }) }
    return @()
}

function Step-JsonLd($Node, $Parent, [bool]$Top, $State) {
    if ($Node -is [System.Collections.IList]) { foreach ($x in $Node) { Step-JsonLd $x $Parent $Top $State }; return }
    if ($Node -isnot [System.Collections.IDictionary]) { return }
    $types = @(Get-NodeTypes $Node)
    foreach ($t in $types) {
        if (-not $State.types.Contains($t)) { $State.types.Add($t) }
        if ($Top -and -not $State.top.Contains($t)) { $State.top.Add($t) }
    }
    $State.nodes.Add($Node)
    if (@($types | Where-Object { (Get-LocalType $_) -cin $saTypes }).Count) { $State.sa.Add(@{ node = $Node; top = $Top; parent = $Parent }) }
    $self = if ($types.Count) { $types[0] } else { $Parent }
    foreach ($k in @($Node.Keys)) {
        # @graph members are top-level nodes of the block; every other value is nested in this node.
        if ($k -ceq '@graph') { $State.graph = $true; Step-JsonLd $Node[$k] $null $Top $State }
        elseif ($k -cne '@context' -and $k -cne '@type') { Step-JsonLd $Node[$k] $self $false $State }
    }
}

function Test-Filled($Value) {
    if ($null -eq $Value) { return $false }
    if ($Value -is [string]) { return [bool]$Value.Trim() }
    if ($Value -is [System.Collections.ICollection]) { return $Value.Count -gt 0 }
    return $true
}

function Get-JsonLdState($Block) {
    $state = @{
        types = [System.Collections.Generic.List[string]]::new()
        top   = [System.Collections.Generic.List[string]]::new()
        nodes = [System.Collections.Generic.List[object]]::new()
        sa    = [System.Collections.Generic.List[object]]::new()
        graph = $false
    }
    if ($null -ne $Block.data) { Step-JsonLd $Block.data $null $true $state }
    return $state
}

# ---- page parsing -------------------------------------------------------------------------------------------------

# Append(string, int, int) called from PowerShell costs the whole string's length on every call, so each gap is
# appended as a Substring: an offline run on a 1.5 MB page took 14 s the first way and 3.4 s this way.
function Remove-RawText([string]$Html) {
    $scripts = [System.Collections.Generic.List[object]]::new()
    $sb = [Text.StringBuilder]::new($Html.Length)
    $pos = 0
    foreach ($m in $rxRaw.Matches($Html)) {
        if ($m.Groups['open'].Success) { continue }   # a start tag stays as written, its attribute values with it
        [void]$sb.Append($Html.Substring($pos, $m.Index - $pos))
        $pos = $m.Index + $m.Length
        $tag = $m.Groups['tag']
        if (-not $tag.Success) { continue }   # a comment is dropped
        $name = $tag.Value.ToLowerInvariant()
        $attrs = $m.Groups['attrs'].Value
        if ($name -eq 'script') { $scripts.Add(@{ attrs = (Get-Attrs $attrs); body = $m.Groups['body'].Value }) }
        [void]$sb.Append('<').Append($name).Append($attrs).Append('></').Append($name).Append('>')
    }
    [void]$sb.Append($Html.Substring($pos))
    return @{ clean = $sb.ToString(); scripts = $scripts }
}

function Test-ScriptType($Attrs, [string]$Kind) {
    $type = ([string]$Attrs['type']).Split(';')[0].Trim().ToLowerInvariant()
    if ($Kind -eq 'ld') { return $type -eq 'application/ld+json' }
    return (-not $type) -or $type -eq 'module' -or $type -match '^(?:text|application)/(?:x-)?(?:java|ecma)script$'
}

function Get-OwnHosts([Uri]$PageUri, $States, $Links, $Anchors) {
    $own = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    if (-not $PageUri) { return , $own }
    [void]$own.Add($PageUri.Host)
    $logins = [System.Collections.Generic.List[string]]::new()
    if ($PageUri.Host -match '^([a-z0-9-]+)\.github\.io$') { $logins.Add($Matches[1]) }
    foreach ($st in $States) {
        foreach ($n in $st.nodes) {
            $local = @(Get-NodeTypes $n | ForEach-Object { Get-LocalType $_ })
            if (-not @($local | Where-Object { $_ -cin 'Person', 'Organization', 'WebSite' }).Count) { continue }
            foreach ($v in @(Get-Strings $n['url']) + @(Get-Strings $n['sameAs'])) {
                $u = ConvertTo-Uri $v
                if (-not $u) { continue }
                if ($u.Host -match '^(?:www\.)?github\.com$') { if ($u.AbsolutePath -match '^/([A-Za-z0-9-]+)/?$') { $logins.Add($Matches[1]) } }
                elseif (@(Get-Strings $n['url']) -ccontains $v) { [void]$own.Add($u.Host) }
            }
        }
    }
    foreach ($attrs in @($Links) + @($Anchors | ForEach-Object { $_.attrs })) {
        $rel = Get-RelTokens $attrs
        if ($rel -ccontains 'me' -or $rel -ccontains 'author') {
            $u = Resolve-Href $PageUri ([string]$attrs['href'])
            if ($u) { [void]$own.Add($u.Host) }
        }
    }
    foreach ($l in $logins) { [void]$own.Add($l.ToLowerInvariant() + '.github.io') }
    return , $own
}

function Test-NewTabHint($Anchor) {
    $bits = [System.Collections.Generic.List[string]]::new()
    foreach ($v in @($Anchor.text, $Anchor.attrs['aria-label'], $Anchor.attrs['title'], $Anchor.attrs['class'])) { if ($v) { $bits.Add([string]$v) } }
    foreach ($m in $rxHintAttr.Matches($Anchor.inner)) { $bits.Add($m.Groups['v'].Value) }
    return $rxNewTabHint.IsMatch(($bits -join ' '))
}

function Get-LinkFacts($Anchors, [Uri]$BaseUri, [Uri]$PageUri, $Own) {
    $f = @{
        internal = 0; external = 0; rawGithub = 0; githubBlob = 0; newTab = 0; newTabNoHint = 0; noreferrerOwnHost = 0
        checks = [System.Collections.Generic.List[string]]::new(); downloads = [System.Collections.Generic.List[object]]::new()
    }
    if (-not $PageUri) { return $f }
    $seenCheck = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $seenDl = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $siteKey = Get-SiteKey $PageUri.Host
    foreach ($a in $Anchors) {
        if (-not $a.attrs.Contains('href')) { continue }
        $href = ([string]$a.attrs['href']).Trim()
        if (-not $href -or $href.StartsWith('#')) { continue }
        $u = Resolve-Href $BaseUri $href
        if (-not $u) { continue }
        $isInternal = $u.Host -eq $PageUri.Host
        if ($isInternal) { $f.internal++ } else { $f.external++ }
        if ($u.Host -eq 'raw.githubusercontent.com' -or ($u.Host -eq 'github.com' -and $u.AbsolutePath -match '^/[^/]+/[^/]+/raw/')) { $f.rawGithub++ }
        if ($u.Host -eq 'github.com' -and $u.AbsolutePath -match '^/[^/]+/[^/]+/blob/') { $f.githubBlob++ }
        $target = ([string]$a.attrs['target']).Trim().ToLowerInvariant()
        if ($target -and ($target -notin '_self', '_parent', '_top')) {
            $f.newTab++
            if (-not (Test-NewTabHint $a)) { $f.newTabNoHint++ }
        }
        if ((Get-RelTokens $a.attrs) -ccontains 'noreferrer' -and ($Own.Contains($u.Host) -or (Get-SiteKey $u.Host) -eq $siteKey)) { $f.noreferrerOwnHost++ }
        $bare = Get-Bare $u
        if ($isInternal -and $f.checks.Count -lt $maxLinksN -and $seenCheck.Add($bare)) { $f.checks.Add($bare) }
        if (($a.attrs.Contains('download') -or $rxDownloadFile.IsMatch($u.AbsolutePath) -or $rxListing.IsMatch($u.AbsoluteUri)) -and $seenDl.Add($bare)) {
            $f.downloads.Add(@{ href = $href; text = $a.text; url = $bare; versioned = $rxUrlVersion.IsMatch($u.PathAndQuery) })
        }
    }
    return $f
}

# Head facts every fetched page gets; -HeadOnly stops there (hreflang targets, sitemap samples).
function Read-Html([string]$Html, [string]$FinalUrl, [switch]$HeadOnly) {
    if ($null -eq $Html) { $Html = '' }
    $uri = ConvertTo-Uri $FinalUrl
    $split = Remove-RawText $Html
    $clean = $split.clean
    $mb = $rxBodyTag.Match($clean)
    if ($mb.Success) { $headPart = $clean.Substring(0, $mb.Index); $bodyPart = $clean.Substring($mb.Index) }
    else {
        $ih = $clean.IndexOf('</head', [StringComparison]::OrdinalIgnoreCase)
        if ($ih -ge 0) { $headPart = $clean.Substring(0, $ih); $bodyPart = $clean.Substring($ih) } else { $headPart = $clean; $bodyPart = $clean }
    }
    $baseUri = $uri
    $mBase = $rxBaseTag.Match($headPart)
    if ($mBase.Success -and $uri) {
        $bu = Resolve-Href $uri ([string](Get-Attrs $mBase.Groups[1].Value)['href'])
        if ($bu) { $baseUri = $bu }
    }
    $metas = @(foreach ($m in $rxMetaTag.Matches($clean)) { Get-Attrs $m.Groups[1].Value })
    $links = @(foreach ($m in $rxLinkTag.Matches($clean)) { Get-Attrs $m.Groups[1].Value })
    # Crawlers read the canonical, hreflang and meta robots in the head only.
    $headLinks = @(foreach ($m in $rxLinkTag.Matches($headPart)) { Get-Attrs $m.Groups[1].Value })
    $headMetas = @(foreach ($m in $rxMetaTag.Matches($headPart)) { Get-Attrs $m.Groups[1].Value })

    $canonical = $null; $canonicalUri = $null
    foreach ($l in $headLinks) {
        if ((Get-RelTokens $l) -ccontains 'canonical' -and $l.Contains('href')) { $canonical = ([string]$l['href']).Trim(); $canonicalUri = Resolve-Href $baseUri $canonical; break }
    }
    $hreflang = [System.Collections.Generic.List[object]]::new()
    foreach ($l in $headLinks) {
        if (-not $l.Contains('hreflang') -or (Get-RelTokens $l) -cnotcontains 'alternate') { continue }
        $href = ([string]$l['href']).Trim()
        $hreflang.Add(@{ lang = ([string]$l['hreflang']).Trim(); href = $href; uri = (Resolve-Href $baseUri $href) })
    }
    $robots = $null
    foreach ($m in $headMetas) { if (([string]$m['name']).Trim() -eq 'robots') { $robots = ([string]$m['content']).Trim(); break } }

    $doc = @{
        finalUrl = $FinalUrl; uri = $uri; baseUri = $baseUri; metas = $metas; links = $links
        canonical = $canonical; canonicalUri = $canonicalUri; hreflang = $hreflang; robots = $robots; full = -not $HeadOnly
    }
    if ($HeadOnly) { return $doc }

    $mh = $rxHtmlTag.Match($clean)
    $doc.htmlAttrs = if ($mh.Success) { Get-Attrs $mh.Groups[1].Value } else { [ordered]@{} }
    $doc.bodyAttrs = if ($mb.Success) { Get-Attrs $mb.Groups[1].Value } else { [ordered]@{} }
    $mt = $rxTitle.Match($headPart)
    if (-not $mt.Success) { $mt = $rxTitle.Match($clean) }
    $doc.title = if ($mt.Success) { Format-Space ([System.Net.WebUtility]::HtmlDecode($mt.Groups[2].Value)) } else { $null }

    $doc.h1 = @(foreach ($m in $rxH1.Matches($bodyPart)) { Get-Head (Get-Text $m.Groups[2].Value) 300 })
    # The first h1 whole, so every language span in it is read; the cap bounds only a malformed h1 that runs on.
    $m1 = $rxH1.Match($bodyPart)
    $doc.h1NoJs = if ($m1.Success) { Get-Head (Get-Text $m1.Groups[2].Value) 3000 } else { $null }
    $doc.h1Count = $rxH1Tag.Matches($bodyPart).Count
    $doc.h2Count = $rxH2Tag.Matches($bodyPart).Count
    $doc.h3Count = $rxH3Tag.Matches($bodyPart).Count
    $doc.images = @(foreach ($m in $rxImgTag.Matches($bodyPart)) { Get-Attrs $m.Groups[1].Value })

    $langSpans = [ordered]@{}
    $roleHeadings = 0
    $skip = $mb.Success   # the first open tag of the body part is <body> itself
    foreach ($m in $rxOpenTag.Matches($bodyPart)) {
        if ($skip) { $skip = $false; continue }
        $attrText = $m.Groups[2].Value
        if (-not $attrText) { continue }
        if ($rxRoleAttr.IsMatch($attrText)) { $roleHeadings++ }
        if (-not $rxLangAttr.IsMatch($attrText)) { continue }
        $a = Get-Attrs $attrText
        $v = if ($a.Contains('data-l')) { $a['data-l'] } elseif ($a.Contains('data-lang')) { $a['data-lang'] } else { $a['lang'] }
        $v = ([string]$v).Trim().ToLowerInvariant()
        if ($v) { $langSpans[$v] = 1 + [int]$langSpans[$v] }
    }
    $doc.langSpans = $langSpans
    $doc.roleHeadings = $roleHeadings

    $doc.anchors = @(foreach ($m in $rxA.Matches($bodyPart)) {
            $a = Get-Attrs $m.Groups[1].Value
            $inner = $m.Groups[2].Value
            $text = Get-Text $inner
            if (-not $text) {
                $mi = $rxImgTag.Match($inner)
                $alt = if ($mi.Success) { (Get-Attrs $mi.Groups[1].Value)['alt'] } else { $null }
                $text = @($a['aria-label'], $a['title'], $alt) | Where-Object { $_ } | Select-Object -First 1
            }
            @{ attrs = $a; inner = $inner; text = [string]$text }
        })
    $doc.text = Get-Text $bodyPart

    $doc.jsonld = @(foreach ($s in $split.scripts) { if (Test-ScriptType $s.attrs 'ld') { Read-JsonLd $s.body } })
    $doc.jsonldStates = @(foreach ($b in $doc.jsonld) { Get-JsonLdState $b })
    $inline = 0
    foreach ($s in $split.scripts) { if (-not $s.attrs.Contains('src') -and (Test-ScriptType $s.attrs 'js')) { $inline += $rxRewrite.Matches($s.body).Count } }
    $doc.inlineRewrites = $inline
    $scriptText = ($split.scripts | ForEach-Object { $_.body }) -join "`n"
    $doc.apiGithub = $rxApiGithub.Matches($clean).Count + $rxApiGithub.Matches($scriptText).Count
    $doc.rawGithubRefs = $rxRawGithub.Matches($clean).Count + $rxRawGithub.Matches($scriptText).Count
    $doc.scriptSrcs = @(foreach ($s in $split.scripts) {
            if (-not $s.attrs.Contains('src')) { continue }
            $su = Resolve-Href $baseUri ([string]$s.attrs['src'])
            @{ src = [string]$s.attrs['src']; uri = $su; sameOrigin = [bool]($su -and $uri -and $su.GetLeftPart([UriPartial]::Authority) -eq $uri.GetLeftPart([UriPartial]::Authority)) }
        })
    $doc.fetchScripts = @($doc.scriptSrcs | Where-Object { $_.sameOrigin } | ForEach-Object { Get-Bare $_.uri } | Select-Object -Unique | Select-Object -First 5)

    $doc.og = [ordered]@{}
    $doc.ogAlternate = [System.Collections.Generic.List[string]]::new()
    $doc.twitter = [ordered]@{}
    foreach ($m in $metas) {
        $prop = ([string]$m['property']).Trim().ToLowerInvariant()
        $name = ([string]$m['name']).Trim().ToLowerInvariant()
        $content = if ($m.Contains('content')) { ([string]$m['content']).Trim() } else { $null }
        if ($prop.StartsWith('og:')) {
            if ($prop -eq 'og:locale:alternate' -and $content) { $doc.ogAlternate.Add($content) }
            if (-not $doc.og.Contains($prop)) { $doc.og[$prop] = $content }
        }
        $tw = if ($name.StartsWith('twitter:')) { $name } elseif ($prop.StartsWith('twitter:')) { $prop } else { '' }
        if ($tw -and -not $doc.twitter.Contains($tw)) { $doc.twitter[$tw] = $content }
    }
    $doc.ogImage = $doc.og['og:image'] ?? $doc.og['og:image:url']
    $doc.ogImageUri = if ($doc.ogImage) { Resolve-Href $baseUri $doc.ogImage } else { $null }

    $own = Get-OwnHosts $uri $doc.jsonldStates $links $doc.anchors
    $doc.linkFacts = Get-LinkFacts $doc.anchors $baseUri $uri $own
    return $doc
}

function Get-MetaContent($Doc, [string]$Name) {
    foreach ($m in $Doc.metas) { if (([string]$m['name']).Trim() -eq $Name) { return Format-Space ([string]$m['content']) } }
    return $null
}

# ---- fetching -----------------------------------------------------------------------------------------------------

# Self-contained, so ForEach-Object -Parallel can rebuild it in every runspace from its text.
# Modes: head = HEAD (GET when HEAD answers 400 or more), no body; html = GET, body kept only for an HTML answer;
# get = GET with body. One timeout covers the URL, its redirects and that retry, and none outlasts the run budget
# ($Deadline, UTC ticks): a request the budget stops comes back "skipped", so it reads as not measured.
$FetchBlock = {
    param($Client, [string]$Url, [string]$Mode, [int]$MaxHops, [int]$TimeoutSec, [long]$Deadline)
    $r = [ordered]@{ url = $Url; mode = $Mode; status = $null; finalUrl = $null; redirects = [System.Collections.Generic.List[object]]::new(); bytes = $null; contentType = $null; charset = $null; robotsTag = $null; data = $null; text = $null; error = $null; skipped = $false }
    $left = if ($Deadline -gt 0) { [TimeSpan]::FromTicks($Deadline - [DateTime]::UtcNow.Ticks) } else { [TimeSpan]::MaxValue }
    if ($left -le [TimeSpan]::Zero) { $r.skipped = $true; $r.error = 'not sent, the run budget ran out'; return $r }
    $wait = if ($left.TotalSeconds -lt $TimeoutSec) { $left } else { [TimeSpan]::FromSeconds($TimeoutSec) }
    $verb = if ($Mode -eq 'head') { 'HEAD' } else { 'GET' }
    $limit = if ($Mode -eq 'html') { 2MB } else { 16MB }
    $current = $Url
    $cts = [System.Threading.CancellationTokenSource]::new($wait)
    try {
        while ($true) {
            $again = $false
            $resp = $null
            try {
                $req = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::new($verb), $current)
                [void]$req.Headers.TryAddWithoutValidation('Accept', $(if ($Mode -eq 'head') { '*/*' } else { 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8' }))
                $resp = $Client.SendAsync($req, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead, $cts.Token).GetAwaiter().GetResult()
                $code = [int]$resp.StatusCode
                $loc = $resp.Headers.Location
                # Some servers answer HEAD with an error the GET of the same URL does not give.
                if ($verb -eq 'HEAD' -and $code -ge 400) { $verb = 'GET'; $again = $true }
                elseif ($code -ge 300 -and $code -lt 400 -and $null -ne $loc) {
                    if ($r.redirects.Count -ge $MaxHops) { $r.status = $code; $r.finalUrl = $current; $r.error = "more than $MaxHops redirects" }
                    else {
                        $next = if ($loc.IsAbsoluteUri) { $loc } else { [Uri]::new([Uri]$current, $loc) }
                        $r.redirects.Add([ordered]@{ status = $code; location = $loc.OriginalString })
                        $current = $next.AbsoluteUri
                        $again = $true
                    }
                }
                else {
                    $r.status = $code
                    $r.finalUrl = $current
                    $ct = $resp.Content.Headers.ContentType
                    if ($null -ne $ct) { $r.contentType = $ct.ToString(); $r.charset = $ct.CharSet }
                    $tagValues = $null
                    if ($resp.Headers.TryGetValues('X-Robots-Tag', [ref]$tagValues)) { $r.robotsTag = @($tagValues) -join ', ' }
                    $wantBody = $Mode -eq 'get' -or ($Mode -eq 'html' -and $null -ne $ct -and "$($ct.MediaType)" -match 'html')
                    if ($verb -eq 'GET' -and $wantBody) {
                        $stream = $resp.Content.ReadAsStreamAsync($cts.Token).GetAwaiter().GetResult()
                        $ms = [IO.MemoryStream]::new()
                        $buf = [byte[]]::new(81920)
                        while ($true) {
                            $n = $stream.ReadAsync($buf, 0, $buf.Length, $cts.Token).GetAwaiter().GetResult()
                            if ($n -le 0) { break }
                            $ms.Write($buf, 0, $n)
                            if ($ms.Length -ge $limit) { $r.error = "body cut at $limit bytes"; break }
                        }
                        $r.data = $ms.ToArray()
                        $r.bytes = $r.data.Length
                    }
                    elseif ($null -ne $resp.Content.Headers.ContentLength) { $r.bytes = [long]$resp.Content.Headers.ContentLength }
                }
            }
            catch {
                $e = $_.Exception
                while ($null -ne $e.InnerException) { $e = $e.InnerException }
                $r.finalUrl = $current
                if (-not $cts.IsCancellationRequested) { $r.error = $e.Message }
                elseif ($wait.TotalSeconds -lt $TimeoutSec) { $r.skipped = $true; $r.error = 'cut, the run budget ran out' }
                else { $r.error = "no answer within $TimeoutSec s" }
            }
            finally {
                if ($null -ne $resp) { $resp.Dispose() }
            }
            if (-not $again) { break }
        }
    }
    finally { $cts.Dispose() }
    return $r
}
$fetchText = $FetchBlock.ToString()

$cache = [System.Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
$roles = [System.Collections.Generic.Dictionary[string, string]]::new([StringComparer]::Ordinal)
$headDocs = [System.Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
# The requests the run budget stopped, with the reason; they stay out of the cache, so they read as not measured.
$budgetMissed = [System.Collections.Generic.Dictionary[string, string]]::new([StringComparer]::Ordinal)
$modeRank = @{ head = 1; html = 2; get = 3 }
$client = $null

function Get-Cached([string]$Key) { $v = $null; if ($Key -and $cache.TryGetValue($Key, [ref]$v)) { return $v }; return $null }
function Test-Ok($R) { return $null -ne $R -and $null -ne $R.status -and $R.status -ge 200 -and $R.status -lt 300 }
# The first answer to a request: a redirect shows as its 3xx.
function Get-FirstStatus($R) { if ($null -eq $R) { return $null }; if (@($R.redirects).Count) { return $R.redirects[0].status }; return $R.status }
# A sitemap answer worth parsing: 2xx, and not an HTML page in its place (a redirect to a home page, a soft 404).
function Test-SitemapRes($R) {
    if (-not (Test-Ok $R)) { return $false }
    if ("$($R.contentType)" -notmatch '(?i)html') { return $true }
    return [bool]((Get-ResText $R) -match '(?i)<(?:urlset|sitemapindex)\b')
}
function Get-ResText($R) {
    if ($null -eq $R) { return $null }
    if ($null -eq $R.text -and $null -ne $R.data) { $R.text = ConvertFrom-Bytes $R.data $R.charset }
    return $R.text
}
function Get-ResField($R, [string]$Name) { if ($null -eq $R) { return $null }; return $R[$Name] }

function New-Need { return [System.Collections.Generic.Dictionary[string, string]]::new([StringComparer]::Ordinal) }

function Request-Url($Need, [string]$Target, [string]$Mode, [string]$Role) {
    if (-not $Target) { return }
    $hit = Get-Cached $Target
    if ($hit -and $modeRank[$hit.mode] -ge $modeRank[$Mode]) { return }
    $have = $null
    if (-not $Need.TryGetValue($Target, [ref]$have) -or $modeRank[$Mode] -gt $modeRank[$have]) { $Need[$Target] = $Mode }
    if (-not $roles.ContainsKey($Target)) { $roles[$Target] = $Role }
}

function Save-Result($R) {
    if ($R.skipped) { $budgetMissed[$R.url] = $R.error }
    else { $cache[$R.url] = $R; [void]$budgetMissed.Remove($R.url) }
}

function Invoke-Single([string]$Target, [string]$Mode, [string]$Role) {
    $r = & $FetchBlock $client $Target $Mode $maxHops $timeoutSec $deadline
    Save-Result $r
    if (-not $roles.ContainsKey($Target)) { $roles[$Target] = $Role }
    return $r
}

function Invoke-Need($Need) {
    if ($Need.Count -eq 0) { return }
    $jobs = @(foreach ($kv in $Need.GetEnumerator()) { @{ url = $kv.Key; mode = $kv.Value } })
    $code = $fetchText; $c = $client; $hops = $maxHops; $wait = $timeoutSec; $end = $deadline
    $results = @($jobs | ForEach-Object -ThrottleLimit $throttle -Parallel {
            $fetch = [scriptblock]::Create($using:code)
            & $fetch $using:c $_.url $_.mode $using:hops $using:wait $using:end
        })
    foreach ($r in $results) { Save-Result $r }
}

function Get-HeadDoc([string]$Key, $R) {
    if (-not (Test-Ok $R)) { return $null }
    $text = Get-ResText $R
    if ($null -eq $text) { return $null }
    $d = $null
    if (-not $headDocs.TryGetValue($Key, [ref]$d)) { $d = Read-Html $text $R.finalUrl -HeadOnly; $headDocs[$Key] = $d }
    return $d
}

function New-PageContext([string]$PageUrl, $R) {
    $ok = $null -ne $R -and $null -ne $R.data -and ($Offline -or (Test-Ok $R))
    $final = if ($R -and $R.finalUrl) { $R.finalUrl } else { $PageUrl }
    $doc = Read-Html $(if ($ok) { Get-ResText $R } else { '' }) $final
    return @{ url = $PageUrl; res = $R; doc = $doc; ok = $ok }
}

# ---- page list ----------------------------------------------------------------------------------------------------

# The last path segment names a page more precisely than its folder (guides/install.html is an install page).
function Get-Kind([string]$Path, [string]$Text) {
    $leaf = (($Path -split '\?')[0].TrimEnd('/') -split '/')[-1]
    foreach ($part in @($leaf, $Path, $Text)) {
        if (-not $part) { continue }
        foreach ($k in $keyKinds.Keys) { if ($keyKinds[$k].IsMatch($part)) { return $k } }
    }
    return $null
}

function Get-PageList($HomeCtx, [string]$BaseUrl) {
    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    [void]$seen.Add((Get-UrlKey $HomeCtx.url))
    [void]$seen.Add((Get-UrlKey $HomeCtx.doc.finalUrl))
    $baseUri = [Uri]$BaseUrl
    $basePath = $baseUri.AbsolutePath
    # Variant keys of the pages a discovered copy is skipped against: the home page and the declared pages first.
    $copies = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($h in @($HomeCtx.url, $HomeCtx.doc.finalUrl)) { $hu = ConvertTo-Uri $h; if ($hu) { [void]$copies.Add((Get-Variant $hu $basePath).key) } }
    $declared = @(foreach ($p in $pageArgs) {
            $u = Resolve-Href $baseUri $p.TrimStart('/')
            if ($u) { @{ url = (Get-Bare $u); kind = (Get-Kind $p ''); key = (Get-Variant $u $basePath).key; rank = 0; declared = $true } }
        })
    foreach ($d in $declared) { [void]$copies.Add($d.key) }
    $found = [System.Collections.Generic.List[object]]::new()
    $homeUri = $HomeCtx.doc.uri
    $homeLang = Get-LangPrimary ([string]$HomeCtx.doc.htmlAttrs['lang'])
    if ($homeUri) {
        $under = Get-DirUrl $homeUri
        foreach ($a in $HomeCtx.doc.anchors) {
            if (-not $a.attrs.Contains('href') -or $a.attrs.Contains('download')) { continue }
            $u = Resolve-Href $HomeCtx.doc.baseUri ([string]$a.attrs['href'])
            if (-not $u -or $u.Host -ne $homeUri.Host -or -not $u.AbsoluteUri.StartsWith($under, [StringComparison]::Ordinal)) { continue }
            $leaf = $u.AbsolutePath.Substring($u.AbsolutePath.LastIndexOf('/') + 1)
            if ($leaf.Contains('.') -and -not $rxPageFile.IsMatch($leaf)) { continue }
            $rel = $u.AbsolutePath.Substring([Math]::Min($u.AbsolutePath.Length, ([Uri]$under).AbsolutePath.Length)) + $u.Query
            $kind = Get-Kind $rel $a.text
            if (-not $kind) { continue }
            # Rank 0 is the page itself: no query, and the home page's language, read from the anchor, else the path.
            $variant = Get-Variant $u $basePath
            $lang = ''
            foreach ($n in 'data-l', 'data-lang', 'hreflang', 'lang') { $lang = ([string]$a.attrs[$n]).Trim(); if ($lang) { break } }
            if (-not $lang) { $lang = $variant.lang }
            $rank = $(if ($u.Query) { 2 } else { 0 }) + $(if ($lang -and (Get-LangPrimary $lang) -ne $homeLang) { 1 } else { 0 })
            $found.Add(@{ url = (Get-Bare $u); kind = $kind; key = $variant.key; rank = $rank; declared = $false })
        }
    }
    $ordered = [System.Collections.Generic.List[object]]::new()
    foreach ($d in $declared) { if ($d.kind) { $ordered.Add($d) } }
    # One page of each kind: the lowest rank, document order breaking a tie.
    $taken = [System.Collections.Generic.HashSet[int]]::new()
    foreach ($k in $keyKinds.Keys) {
        $best = -1
        for ($i = 0; $i -lt $found.Count; $i++) {
            $f = $found[$i]
            if ($f.kind -ne $k -or $copies.Contains($f.key) -or $seen.Contains((Get-UrlKey $f.url))) { continue }
            if ($best -lt 0 -or $f.rank -lt $found[$best].rank) { $best = $i }
        }
        if ($best -ge 0) { $ordered.Add($found[$best]); [void]$taken.Add($best) }
    }
    foreach ($level in 0..3) { for ($i = 0; $i -lt $found.Count; $i++) { if (-not $taken.Contains($i) -and $found[$i].rank -eq $level) { $ordered.Add($found[$i]) } } }
    foreach ($d in $declared) { if (-not $d.kind) { $ordered.Add($d) } }
    $list = [System.Collections.Generic.List[string]]::new()
    foreach ($c in $ordered) {
        if ($list.Count -ge $maxPagesN - 1) { break }
        if (-not $c.declared -and $copies.Contains($c.key)) { continue }   # a copy of a page already listed
        if ($seen.Add((Get-UrlKey $c.url))) { $list.Add($c.url); [void]$copies.Add($c.key) }
    }
    return $list
}

# ---- site files ---------------------------------------------------------------------------------------------------

function Read-Robots([string]$Text) {
    $groups = [System.Collections.Generic.List[object]]::new()
    $sitemaps = [System.Collections.Generic.List[string]]::new()
    $current = $null
    $inAgents = $false
    foreach ($raw in ($Text -split '\r?\n')) {
        $line = ($raw -replace '#.*$', '').Trim()
        if ($line -notmatch '^([A-Za-z-]+)\s*:\s*(.*)$') { continue }
        $field = $Matches[1].ToLowerInvariant()
        $value = $Matches[2].Trim()
        if ($field -eq 'user-agent') {
            if (-not $inAgents -or $null -eq $current) { $current = @{ agents = [System.Collections.Generic.List[string]]::new(); rules = [System.Collections.Generic.List[object]]::new() }; $groups.Add($current) }
            $current.agents.Add($value)
            $inAgents = $true
            continue
        }
        $inAgents = $false
        if ($field -eq 'sitemap') { if ($value) { $sitemaps.Add($value) } }
        elseif (($field -in 'allow', 'disallow') -and $null -ne $current) { $current.rules.Add(@{ kind = $field; path = $value }) }
    }
    $agents = [System.Collections.Generic.List[string]]::new()
    $disallow = [System.Collections.Generic.List[string]]::new()
    foreach ($g in $groups) {
        foreach ($a in $g.agents) { if (-not ($agents -contains $a)) { $agents.Add($a) } }
        foreach ($rule in $g.rules) { if ($rule.kind -eq 'disallow' -and $rule.path) { $disallow.Add(($g.agents -join ', ') + ': ' + $rule.path) } }
    }
    $ai = [ordered]@{}
    foreach ($bot in $aiBots) {
        $mine = @($groups | Where-Object { $_.agents -contains $bot })
        if (-not $mine.Count) { $ai[$bot] = 'unmentioned'; continue }
        $rules = @($mine | ForEach-Object { $_.rules })
        $all = '/', '/*', '*'
        $blocked = @($rules | Where-Object { $_.kind -eq 'disallow' -and $_.path -in $all }).Count -and -not @($rules | Where-Object { $_.kind -eq 'allow' -and $_.path -in $all }).Count
        $ai[$bot] = if ($blocked) { 'blocked' } else { 'allowed' }
    }
    return @{ sitemaps = $sitemaps; agents = $agents; disallow = $disallow; ai = $ai }
}

function Read-Sitemap([string]$Xml) {
    $x = [regex]::Replace($Xml, '(?s)<!--.*?-->', '')
    $clean = { param($v) [System.Net.WebUtility]::HtmlDecode(([regex]::Replace($v, '^\s*<!\[CDATA\[|\]\]>\s*$', '')).Trim()) }
    $sm = @{ index = $x -match '(?i)<sitemapindex\b'; locs = [System.Collections.Generic.List[string]]::new(); lastmods = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal); missing = 0; alternates = 0; children = 0 }
    if ($sm.index) { $sm.children = [regex]::Matches($x, '(?is)<sitemap\b[^>]*>.*?</sitemap\s*>').Count }
    foreach ($m in [regex]::Matches($x, '(?is)<url\b[^>]*>(.*?)</url\s*>')) {
        $inner = $m.Groups[1].Value
        $loc = [regex]::Match($inner, '(?is)<loc\b[^>]*>(.*?)</loc\s*>')
        if ($loc.Success) { $sm.locs.Add((& $clean $loc.Groups[1].Value)) }
        $lm = [regex]::Match($inner, '(?is)<lastmod\b[^>]*>(.*?)</lastmod\s*>')
        if ($lm.Success -and (& $clean $lm.Groups[1].Value)) { [void]$sm.lastmods.Add((& $clean $lm.Groups[1].Value)) } else { $sm.missing++ }
        $sm.alternates += [regex]::Matches($inner, '(?i)<[A-Za-z][\w-]*:link\b').Count
    }
    return $sm
}

function Get-Sample($Items, [int]$Max) {
    $all = @($Items)
    if ($all.Count -le $Max) { return $all }
    return @(for ($i = 0; $i -lt $Max; $i++) { $all[[int][Math]::Floor($i * $all.Count / $Max)] })
}

# ---- output -------------------------------------------------------------------------------------------------------

function Format-Page($Ctx) {
    $doc = $Ctx.doc
    $res = $Ctx.res
    $pageUri = $doc.uri
    $pageHost = if ($pageUri) { $pageUri.Host } else { '' }
    $pageKeys = @((Get-UrlKey $Ctx.url), (Get-UrlKey $doc.finalUrl))

    $hreflang = @(foreach ($h in $doc.hreflang) {
            $tUrl = if ($h.uri) { Get-Bare $h.uri } else { $null }
            $tRes = Get-Cached $tUrl
            $tDoc = $null
            if ($tRes) { $tDoc = Get-HeadDoc $tUrl $tRes }
            elseif ($tUrl -and (Get-UrlKey $tUrl) -cin $pageKeys -and $Ctx.ok) { $tRes = $res; $tDoc = $doc }   # the page itself, read from the page
            [ordered]@{
                lang          = $h.lang
                href          = $h.href
                status        = Get-FirstStatus $tRes
                canonical     = if ($tDoc) { $tDoc.canonical } else { $null }
                selfCanonical = if ($tDoc) { [bool]($tDoc.canonicalUri -and (Get-UrlKey (Get-Bare $tDoc.canonicalUri)) -ceq (Get-UrlKey $tUrl)) } else { $null }
                reciprocal    = if ($tDoc) { [bool]@($tDoc.hreflang | Where-Object { $_.uri -and (Get-UrlKey (Get-Bare $_.uri)) -cin $pageKeys }).Count } else { $null }
                noindex       = if ($tDoc) { Test-NoIndex "$($tDoc.robots),$(Get-ResField $tRes 'robotsTag')" } else { $null }
                isParam       = [bool]($h.uri -and $h.uri.Query)
            }
        })

    $ogImage = $null
    if ($doc.ogImage) {
        $iu = $doc.ogImageUri
        $ir = if ($iu) { Get-Cached (Get-Bare $iu) } else { $null }
        $ogImage = [ordered]@{
            url         = $doc.ogImage
            status      = Get-ResField $ir 'status'
            host        = if ($iu) { $iu.Host } else { $null }
            contentType = Get-ResField $ir 'contentType'
            bytes       = Get-ResField $ir 'bytes'
            onSite      = [bool]($iu -and $iu.Host -eq $pageHost)
            rawGithub   = [bool]($iu -and ($iu.Host -eq 'raw.githubusercontent.com' -or ($iu.Host -eq 'github.com' -and $iu.AbsolutePath -match '^/[^/]+/[^/]+/raw/')))
        }
    }

    $jsonld = @(for ($i = 0; $i -lt $doc.jsonld.Count; $i++) {
            $b = $doc.jsonld[$i]
            $st = $doc.jsonldStates[$i]
            $pick = @(@($st.sa | Where-Object { $_.top }) + @($st.sa)) | Select-Object -First 1
            $has = [ordered]@{}
            foreach ($p in $saProps) { $has[$p] = [bool]($pick -and $pick.node.Contains($p) -and (Test-Filled $pick.node[$p])) }
            [ordered]@{
                index               = $i
                parseError          = $b.error
                types               = @($st.types)
                topLevelTypes       = @($st.top)
                hasGraph            = $st.graph
                softwareApplication = [ordered]@{
                    present  = [bool]$pick
                    topLevel = [bool]($pick -and $pick.top)
                    nestedIn = if ($pick -and -not $pick.top) { $pick.parent } else { $null }
                    has      = $has
                }
                raw                 = $b.raw
            }
        })

    $images = @($doc.images)
    $facts = $doc.linkFacts
    $checked = @(foreach ($l in $facts.checks) { $r = Get-Cached $l; if ($r) { [ordered]@{ url = $l; status = $r.status } } })
    $broken = @(foreach ($l in $facts.checks) { $r = Get-Cached $l; if ($r -and -not (Test-Ok $r)) { [ordered]@{ url = $l; status = $r.status; finalUrl = $r.finalUrl } } })
    $downloads = @(foreach ($d in $facts.downloads) {
            $r = Get-Cached $d.url
            [ordered]@{ href = $d.href; text = $d.text; status = Get-ResField $r 'status'; finalUrl = Get-ResField $r 'finalUrl'; versioned = $d.versioned }
        })

    $scriptRewrites = 0; $scriptApi = 0
    $scripts = @(foreach ($s in $doc.scriptSrcs) {
            $r = $null
            if ($s.sameOrigin -and $s.uri) { $bare = Get-Bare $s.uri; if ($doc.fetchScripts -ccontains $bare) { $r = Get-Cached $bare } }
            $body = if (Test-Ok $r) { Get-ResText $r } else { $null }
            $rw = if ($null -ne $body) { $rxRewrite.Matches($body).Count } else { $null }
            $api = if ($null -ne $body) { $rxApiGithub.Matches($body).Count } else { $null }
            if ($null -ne $rw) { $scriptRewrites += $rw; $scriptApi += $api }
            [ordered]@{ src = $s.src; sameOrigin = $s.sameOrigin; bytes = Get-ResField $r 'bytes'; apiGithub = $api; jsRewrites = $rw }
        })

    $text = [string]$doc.text
    $versions = [System.Collections.Generic.List[string]]::new()
    foreach ($m in $rxVersion.Matches($text)) {
        if ($versions.Count -ge 8) { break }
        $v = $m.Value
        if (-not $rxDateLike.IsMatch($v) -and -not $rxAddress.IsMatch($v) -and -not $versions.Contains($v)) { $versions.Add($v) }
    }
    $phrases = @(foreach ($m in @(@($rxStatus.Matches($text)) | Select-Object -First 20)) {
            $start = [Math]::Max(0, $m.Index - [int][Math]::Floor((60 - $m.Length) / 2))
            [ordered]@{ phrase = $m.Value.ToLowerInvariant(); context = (Get-Head $text.Substring($start) 60) }
        })
    $words = @($text -split '\s+' | Where-Object { $_ }).Count
    $title = $doc.title
    $desc = Get-MetaContent $doc 'description'
    $dataLang = $null
    foreach ($attrs in @($doc.htmlAttrs, $doc.bodyAttrs)) {
        if ($null -eq $dataLang -and $attrs.Contains('data-lang')) { $dataLang = $attrs['data-lang'] }
        if ($null -eq $dataLang -and $attrs.Contains('data-l')) { $dataLang = $attrs['data-l'] }
    }

    $rec = [ordered]@{
        url               = $Ctx.url
        status            = Get-ResField $res 'status'
        finalUrl          = $doc.finalUrl
        redirects         = @(if ($res) { $res.redirects })
        bytes             = Get-ResField $res 'bytes'
        contentType       = Get-ResField $res 'contentType'
        lang              = $doc.htmlAttrs['lang']
        dataLang          = $dataLang
        title             = $title
        titleLength       = Get-TextLength $title
        titleHasEmoji     = if ($null -ne $title) { Test-Emoji $title } else { $null }
        description       = $desc
        descriptionLength = Get-TextLength $desc
        viewport          = Get-MetaContent $doc 'viewport'
        canonical         = $doc.canonical
        canonicalAbsolute = if ($null -ne $doc.canonical) { $doc.canonical -match '^(?i)https?://' } else { $null }
        canonicalSelf     = if ($null -ne $doc.canonical) { [bool]($doc.canonicalUri -and (Get-UrlKey (Get-Bare $doc.canonicalUri)) -ceq (Get-UrlKey $doc.finalUrl)) } else { $null }
        metaRobots        = $doc.robots
        hreflang          = $hreflang
        xDefault          = [bool]@($doc.hreflang | Where-Object { $_.lang -eq 'x-default' }).Count
        og                = $doc.og
        ogLocale          = $doc.og['og:locale']
        ogLocaleAlternate = @($doc.ogAlternate)
        ogImage           = $ogImage
        twitter           = $doc.twitter
        jsonld            = $jsonld
        headings          = [ordered]@{
            h1               = @($doc.h1)
            h1Count          = $doc.h1Count
            h1NoJs           = $doc.h1NoJs
            h1HasEmoji       = [bool]@($doc.h1 | Where-Object { Test-Emoji $_ }).Count
            h2Count          = $doc.h2Count
            h3Count          = $doc.h3Count
            roleHeadingSpans = $doc.roleHeadings
        }
        images            = [ordered]@{
            count    = $images.Count
            noAlt    = @($images | Where-Object { -not $_.Contains('alt') }).Count
            emptyAlt = @($images | Where-Object { $_.Contains('alt') -and -not ([string]$_['alt']).Trim() }).Count
            noSize   = @($images | Where-Object { -not ($_.Contains('width') -and $_.Contains('height')) }).Count
            lazy     = @($images | Where-Object { ([string]$_['loading']).Trim() -eq 'lazy' }).Count
            items    = @($images | Select-Object -First 30 | ForEach-Object { [ordered]@{ src = $_['src']; alt = $_['alt']; width = $_['width']; height = $_['height']; loading = $_['loading'] } })
        }
        links             = [ordered]@{
            internal          = $facts.internal
            external          = $facts.external
            rawGithub         = $facts.rawGithub
            githubBlob        = $facts.githubBlob
            newTab            = $facts.newTab
            newTabNoHint      = $facts.newTabNoHint
            noreferrerOwnHost = $facts.noreferrerOwnHost
            checked           = $checked
            broken            = $broken
            downloads         = $downloads
        }
        langSpans         = $doc.langSpans
        cyrillicChars     = $rxCyrillic.Matches($text).Count
        latinChars        = $rxLatin.Matches($text).Count
        textNoJs          = Get-Head $text 400
        appShell          = ($text.Length -lt 200) -or ($words -lt 100 -and $rxLoading.IsMatch($text))
        scripts           = $scripts
        jsRewrites        = $doc.inlineRewrites + $scriptRewrites
        apiGithub         = $doc.apiGithub + $scriptApi
        rawGithubRefs     = $doc.rawGithubRefs
        versions          = @($versions)
        statusPhrases     = $phrases
    }
    # A page that did not answer 2xx is not parsed: what it would have said is unknown, not empty. Only what the
    # answer itself carries stays: url, status, finalUrl, redirects, bytes, contentType.
    if (-not $Ctx.ok) {
        foreach ($k in @($rec.Keys)) { if ($k -notin 'url', 'status', 'finalUrl', 'redirects', 'bytes', 'contentType') { $rec[$k] = $null } }
    }
    return $rec
}

function Format-Chain([string]$From) {
    $r = Get-Cached $From
    return [ordered]@{
        from  = $From
        chain = @(if ($r) { $r.redirects })
        final = if ($r -and -not $r.error) { $r.finalUrl } else { $null }
    }
}

# ---- run ----------------------------------------------------------------------------------------------------------

$baseUrl = Get-DirUrl $inputUri
$baseUriObj = [Uri]$baseUrl
$hostUrl = $inputUri.GetLeftPart([UriPartial]::Authority)
$robotsUrl = $baseUrl + 'robots.txt'
$hostRobotsUrl = $hostUrl + '/robots.txt'
$sitemapUrl = $baseUrl + 'sitemap.xml'
$llmsUrls = @(@(($hostUrl + '/llms.txt'), ($baseUrl + 'llms.txt')) | Select-Object -Unique)
$probeUrl = $baseUrl + 'robot-check-probe-' + [guid]::NewGuid().ToString('N').Substring(0, 10)
$httpFrom = 'http://' + $baseUriObj.Authority + $baseUriObj.AbsolutePath
$wwwFrom = $null
$wwwSkip = $null
$hostName = $baseUriObj.Host
if ($Offline) { $wwwSkip = 'offline: no request is sent' }
elseif ($baseUriObj.HostNameType -ne [UriHostNameType]::Dns -or -not $hostName.Contains('.')) { $wwwSkip = "not a domain name: $hostName" }
else {
    $platform = $platformSuffixes | Where-Object { $hostName -eq $_ -or $hostName.EndsWith(".$_") } | Select-Object -First 1
    if ($platform) { $wwwSkip = "a subdomain of the hosting platform $platform has no www variant" }
    elseif (-not $hostName.StartsWith('www.') -and (Get-SiteKey $hostName) -ne $hostName.ToLowerInvariant()) { $wwwSkip = "a subdomain has no www variant: $hostName" }
    elseif ($hostName.StartsWith('www.')) { $wwwFrom = $baseUriObj.Scheme + '://' + $hostName.Substring(4) + $baseUriObj.AbsolutePath }
    else { $wwwFrom = $baseUriObj.Scheme + '://www.' + $hostName + $baseUriObj.AbsolutePath }
}

$homeOk = $true
$sitemapUsed = $sitemapUrl
$sampled = @()
if ($Offline) {
    $pageUrl = $inputUri.GetLeftPart([UriPartial]::Query)
    $bytes = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $HtmlFile).Path)
    $saved = [ordered]@{ url = $pageUrl; mode = 'get'; status = $null; finalUrl = $pageUrl; redirects = @(); bytes = $bytes.Length; contentType = $null; charset = $null; robotsTag = $null; data = $bytes; text = $null; error = $null }
    $contexts = @(New-PageContext $pageUrl $saved)
}
else {
    $handler = [System.Net.Http.SocketsHttpHandler]::new()
    $handler.AllowAutoRedirect = $false
    $handler.UseCookies = $false   # a crawler sends none back
    $handler.AutomaticDecompression = [System.Net.DecompressionMethods]::All
    $handler.MaxConnectionsPerServer = $throttle
    $handler.ConnectTimeout = [TimeSpan]::FromSeconds($timeoutSec)
    $client = [System.Net.Http.HttpClient]::new($handler)
    $client.Timeout = [System.Threading.Timeout]::InfiniteTimeSpan
    [void]$client.DefaultRequestHeaders.TryAddWithoutValidation('User-Agent', $userAgent)

    $p = $inputUri.AbsolutePath
    $homeUrl = if ($p.EndsWith('/') -or $p.Substring($p.LastIndexOf('/') + 1).Contains('.')) { $inputUri.GetLeftPart([UriPartial]::Query) } else { $baseUrl + $inputUri.Query }
    $homeRes = Invoke-Single $homeUrl 'get' 'home'
    $homeCtx = New-PageContext $homeUrl $homeRes
    $homeOk = $homeCtx.ok
    $pageUrls = if ($homeOk) { @(Get-PageList $homeCtx $baseUrl) } else { @() }

    $need = New-Need
    foreach ($u in $pageUrls) { Request-Url $need $u 'get' 'page' }
    Request-Url $need $hostRobotsUrl 'get' 'host robots.txt'
    Request-Url $need $robotsUrl 'head' 'robots.txt'
    Request-Url $need $sitemapUrl 'get' 'sitemap'
    foreach ($u in $llmsUrls) { Request-Url $need $u 'head' 'llms.txt' }
    Request-Url $need $probeUrl 'get' '404 probe'
    Request-Url $need $httpFrom 'head' 'http redirect'
    if ($wwwFrom) { Request-Url $need $wwwFrom 'head' 'www redirect' }
    Invoke-Need $need

    $contexts = @($homeCtx) + @(foreach ($u in $pageUrls) { New-PageContext $u (Get-Cached $u) })

    if (-not (Test-SitemapRes (Get-Cached $sitemapUrl)) -and (Test-Ok (Get-Cached $hostRobotsUrl))) {
        $declaredMaps = (Read-Robots (Get-ResText (Get-Cached $hostRobotsUrl))).sitemaps
        $alt = @($declaredMaps | Where-Object { $_.StartsWith($baseUrl, [StringComparison]::Ordinal) -and $_ -cne $sitemapUrl }) | Select-Object -First 1
        if ($alt) { [void](Invoke-Single $alt 'get' 'sitemap'); $sitemapUsed = $alt }
    }
    $smRes = Get-Cached $sitemapUsed
    if (Test-SitemapRes $smRes) {
        $locs = @((Read-Sitemap (Get-ResText $smRes)).locs | Where-Object { ConvertTo-Uri $_ })
        $sampled = @(Get-Sample $locs $maxSitemapN)
    }

    $need = New-Need
    foreach ($c in $contexts) {
        if (-not $c.ok) { continue }
        foreach ($h in $c.doc.hreflang) { if ($h.uri) { Request-Url $need (Get-Bare $h.uri) 'get' 'hreflang' } }
        foreach ($l in $c.doc.linkFacts.checks) { Request-Url $need $l 'head' 'link' }
        foreach ($d in $c.doc.linkFacts.downloads) { Request-Url $need $d.url 'head' 'download' }
        if ($c.doc.ogImageUri) { Request-Url $need (Get-Bare $c.doc.ogImageUri) 'head' 'og:image' }
        foreach ($s in $c.doc.fetchScripts) { Request-Url $need $s 'get' 'script' }
    }
    foreach ($s in $sampled) { Request-Url $need $s 'html' 'sitemap url' }
    Invoke-Need $need
}

$pagesOut = @(foreach ($c in $contexts) { Format-Page $c })

# Site-wide block.
$hostRobotsRes = Get-Cached $hostRobotsUrl
$hr = if (Test-Ok $hostRobotsRes) { Read-Robots (Get-ResText $hostRobotsRes) } else { $null }
$aiState = [ordered]@{}
foreach ($bot in $aiBots) {
    $aiState[$bot] = if ($hr) { $hr.ai[$bot] }
    elseif ($hostRobotsRes -and $null -ne $hostRobotsRes.status -and $hostRobotsRes.status -ge 400 -and $hostRobotsRes.status -lt 500) { 'unmentioned' }
    else { $null }
}
$smRes = Get-Cached $sitemapUsed
$sm = if (Test-SitemapRes $smRes) { Read-Sitemap (Get-ResText $smRes) } else { $null }
$problems = [System.Collections.Generic.List[object]]::new()
if ($sm -and $sm.index) { $problems.Add([ordered]@{ url = $sitemapUsed; status = $smRes.status; note = "a sitemap index of $($sm.children) child sitemap(s), not followed" }) }
elseif (-not $sm -and (Test-Ok $smRes)) {
    $where = if (@($smRes.redirects).Count) { "redirects to $($smRes.finalUrl), " } else { '' }
    $problems.Add([ordered]@{ url = $sitemapUsed; status = $smRes.status; note = "${where}an HTML page, not a sitemap" })
}
foreach ($s in $sampled) {
    $r = Get-Cached $s
    if (-not $r) { continue }
    $notes = [System.Collections.Generic.List[string]]::new()
    if ($r.error) { $notes.Add($r.error) }
    if (@($r.redirects).Count) { $notes.Add("redirects to $($r.finalUrl)") }
    if ($null -ne $r.status -and -not (Test-Ok $r)) { $notes.Add("answers $($r.status)") }
    $d = Get-HeadDoc $s $r
    if ($d) {
        if ($d.canonicalUri -and (Get-UrlKey (Get-Bare $d.canonicalUri)) -cne (Get-UrlKey $s)) { $notes.Add("canonical points to $($d.canonical)") }
        if (Test-NoIndex "$($d.robots),$($r.robotsTag)") { $notes.Add('noindex') }
    }
    $su = ConvertTo-Uri $s
    if ($su -and $su.Host -ne $baseUriObj.Host) { $notes.Add("outside the host $($baseUriObj.Host)") }
    if ($notes.Count) { $problems.Add([ordered]@{ url = $s; status = $r.status; note = ($notes -join '; ') }) }
}
$probeRes = Get-Cached $probeUrl
$probeTitle = $null
if ($probeRes -and $null -ne $probeRes.data -and "$($probeRes.contentType)" -match 'html') {
    $mt = $rxTitle.Match((Get-ResText $probeRes))
    if ($mt.Success) { $probeTitle = Format-Space ([System.Net.WebUtility]::HtmlDecode($mt.Groups[2].Value)) }
}

$site = [ordered]@{
    robots     = [ordered]@{ url = $robotsUrl; status = Get-FirstStatus (Get-Cached $robotsUrl) }
    hostRobots = [ordered]@{
        url        = $hostRobotsUrl
        status     = Get-FirstStatus $hostRobotsRes
        sitemaps   = @(if ($hr) { $hr.sitemaps })
        userAgents = @(if ($hr) { $hr.agents })
        disallow   = @(if ($hr) { $hr.disallow })
        aiCrawlers = $aiState
        body       = if ($hr) { Get-Head (Get-ResText $hostRobotsRes) 3000 } else { $null }
    }
    sitemap    = [ordered]@{
        url             = $sitemapUsed
        status          = Get-FirstStatus $smRes
        urls            = if ($sm) { $sm.locs.Count } else { $null }
        lastmodDistinct = if ($sm) { $sm.lastmods.Count } else { $null }
        lastmodMissing  = if ($sm) { $sm.missing } else { $null }
        paramUrls       = if ($sm) { @($sm.locs | Where-Object { $_.Contains('?') }).Count } else { $null }
        alternates      = if ($sm) { $sm.alternates } else { $null }
        sampled         = @(foreach ($s in $sampled) { $r = Get-Cached $s; [ordered]@{ url = $s; status = Get-ResField $r 'status'; finalUrl = Get-ResField $r 'finalUrl' } })
        problems        = @($problems)
    }
    llms       = @(foreach ($u in $llmsUrls) { [ordered]@{ url = $u; status = Get-FirstStatus (Get-Cached $u) } })
    notFound   = [ordered]@{ url = $probeUrl; status = Get-ResField $probeRes 'status'; bytes = Get-ResField $probeRes 'bytes'; title = $probeTitle }
    redirects  = [ordered]@{
        http = Format-Chain $httpFrom
        www  = if ($wwwSkip) { [ordered]@{ skipped = $wwwSkip } } else { Format-Chain $wwwFrom }
    }
}

# Errors: requests that got no usable answer, a home page that answered other than 2xx first; then the requests the
# run budget stopped.
function Get-ErrorLines($Items) {
    $rows = @(foreach ($it in $Items) {
            $role = $roles[$it.url] ?? 'request'
            $rank = [array]::IndexOf($roleOrder, $role)
            [pscustomobject]@{ rank = $(if ($rank -ge 0) { $rank } else { 99 }); url = $it.url; line = "${role}: $($it.url) - $($it.reason)" }
        })
    return @($rows | Sort-Object rank, url | ForEach-Object { $_.line })
}
$errors = [System.Collections.Generic.List[string]]::new()
foreach ($line in @(Get-ErrorLines @(foreach ($kv in $cache.GetEnumerator()) { if ($kv.Value.error) { @{ url = $kv.Key; reason = $kv.Value.error } } }))) { $errors.Add($line) }
if (-not $Offline -and -not $homeOk -and -not $homeRes.error) { $errors.Insert(0, "home: $homeUrl - answered $($homeRes.status), not 2xx") }
foreach ($line in @(Get-ErrorLines @(foreach ($kv in $budgetMissed.GetEnumerator()) { @{ url = $kv.Key; reason = "$($kv.Value) ($runBudgetSec s)" } }))) { $errors.Add($line) }
if ($errors.Count -gt 60) { $more = $errors.Count - 59; $errors.RemoveRange(59, $errors.Count - 59); $errors.Add("and $more more request errors") }

$doc = [ordered]@{
    tool      = 'robot-check'
    version   = 1
    base      = $baseUrl
    host      = $hostUrl
    fetchedAt = $fetchedAt
    userAgent = $userAgent
    elapsedMs = [int]$clock.ElapsedMilliseconds
    errors    = @($errors)
    pages     = $pagesOut
    site      = $site
}
$json = ConvertTo-Json -InputObject $doc -Depth 32
$outDir = Split-Path -Parent $outPath
if ($outDir -and -not (Test-Path -LiteralPath $outDir -PathType Container)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
[IO.File]::WriteAllText($outPath, $json, [Text.UTF8Encoding]::new($false))
if ($client) { $client.Dispose() }
"robot-check: $($pagesOut.Count) page(s), $($errors.Count) error(s), $($doc.elapsedMs) ms -> $outPath"
exit $(if ($homeOk) { 0 } else { 1 })
