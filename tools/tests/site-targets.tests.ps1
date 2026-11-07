#requires -Version 7.5
<#
.SYNOPSIS
    Cases for tools/site-audit/site-targets.ps1 - the sites a site audit runs against, their base URLs and their run
    folders.

.DESCRIPTION
    Runs the script over throwaway git repositories and throwaway portfolio registries (SZA_PORTFOLIO_ROOT) in a temp
    folder; the real registry and the real repositories are never read or written. Nothing goes to the network: a
    base URL comes from a CNAME file or from the origin in the local git config. Git runs without the global and the
    system configuration and never climbs above the temp folder, so no ignore file and no repository outside it
    decides a case. The runs go side by side, so the whole file takes a few seconds.

      1. A CNAME in the served root gives https://<cname>/ (one outside it is not read); -Repo may name a subfolder.
      2. A GitHub origin gives https://<owner lowercased>.github.io/<repo>/ for root "." and for root "docs"; a
         registry path that ends in a separator still gives the registry key.
      3. A user-site repository <owner>.github.io gives the host root.
      4. A stamp with kind "none" is no target (exit 2); a site block with no root serves the repository root.
      5. A repository whose temp/ git would track is refused with exit 3 when it is the only target; nothing is written.
      6. -All walks the registry and skips the repositories with no site block or no folder; a refused one is listed.
      7. Two repositories with the same URL: the first is kept, the second refused.
      8. A second run on the same date gets <date>_2 and its prevDir is the first; _11 follows _10.
      9. A -Url host lands under the portfolio target's run folder in external/<host>, its host lowercased.
     10. -Mode prepublish, -Lens and -Baseline pass through, in the comma-list form the skill passes; an unknown lens
         is exit 2.
     11. A stamp that is not JSON is refused (REPO-STAMP rule 2), never skipped as one without a site; alone, exit 3.
     12. -Url: one URL per host, a port in the folder name, a page cut to its folder; a query is exit 2 before any
         repository is weighed.
     13. The previous run: prevFile names its report.md, else its baseline.md; a run of one lens is no yardstick for a
         full run, a baseline is; the run number follows the highest, never a deleted run's gap.
     14. -All goes in rank order over the stamp and profile cases: an unknown schemaVersion, a site with no kind or no
         object, a root outside the repository, a CNAME with a scheme, a folder git cannot open, a run folder asked
         about as a folder (*.md ignored only), paths.tempDir of the profile; an empty stamp is skipped.
     15. The refusals survive every exit: -Url with no target left is exit 3 with the reason; a -PortfolioKey that
         names a refused target is exit 2 with it.
     16. The registry: an unreadable one is exit 2 under -All with pq's error and a note under -Repo; a registry path
         that is a junction (a symbolic link off Windows) still gives the registry key.
     17. A relative -Baseline and -OutFile follow the current location; an -OutFile git would track is exit 2 and
         not written; -Date must be a real date.
#>
[CmdletBinding()]
param([switch] $KeepScratch)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$SourceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$script_ = Join-Path $SourceRoot 'tools\site-audit\site-targets.ps1'
$pwshExe = (Get-Command pwsh -CommandType Application | Select-Object -First 1).Source
$date = '2026-05-04'

$run = 0; $passed = 0; $failed = 0
function Assert-That([bool] $Condition, [string] $Message) { if (-not $Condition) { throw $Message } }
function Run-Case([string] $Name, [scriptblock] $Body) {
    $script:run++
    Write-Host -NoNewline "CASE  $Name .. "
    try { & $Body; $script:passed++; Write-Host 'PASS' -ForegroundColor Green }
    catch { $script:failed++; Write-Host 'FAIL' -ForegroundColor Red; Write-Host "      $($_.Exception.Message)" -ForegroundColor DarkRed }
}

function Write-Text([string] $Path, [string] $Text) {
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path)) | Out-Null
    [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false))
}

$scratch = Join-Path ([IO.Path]::GetTempPath()) ('site-targets-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $scratch | Out-Null

$savedEnv = @{}
try {
    # Git without the owner's global and system configuration, and never above the scratch folder, here and in every
    # child process, which inherits it.
    $gitEnv = [ordered]@{ GIT_CONFIG_GLOBAL = (Join-Path $scratch 'gitconfig'); GIT_CONFIG_NOSYSTEM = '1'; XDG_CONFIG_HOME = (Join-Path $scratch 'xdg'); GIT_CEILING_DIRECTORIES = $scratch }
    foreach ($k in $gitEnv.Keys) { $savedEnv[$k] = [Environment]::GetEnvironmentVariable($k); [Environment]::SetEnvironmentVariable($k, $gitEnv[$k]) }
    Write-Text $gitEnv.GIT_CONFIG_GLOBAL ''

    # One fresh .git, copied into every repository: a git init per repository would cost more than all the copies.
    $template = Join-Path $scratch 'git-template'
    git init -q --template= $template 2>$null
    if ($LASTEXITCODE -ne 0) { throw "git init failed in $template" }

    # A throwaway repository: the copied .git, then the origin, the .gitignore, the stamp and the profile it is given.
    function New-Repo([string] $Folder, [string] $Origin, $Site, [string] $Ignore = "temp/`n", [string] $RawStamp = '', [string] $ProfileJson = '', [switch] $NoGit) {
        $root = Join-Path $scratch $Folder
        New-Item -ItemType Directory -Path $root | Out-Null
        if (-not $NoGit) { Copy-Item -LiteralPath (Join-Path $template '.git') -Destination (Join-Path $root '.git') -Recurse -Force }
        if ($Origin) { [IO.File]::AppendAllText((Join-Path $root '.git\config'), "[remote `"origin`"]`n`turl = $Origin`n`tfetch = +refs/heads/*:refs/remotes/origin/*`n") }
        if ($Ignore) { Write-Text (Join-Path $root '.gitignore') $Ignore }
        if ($RawStamp) { Write-Text (Join-Path $root '.sza-canon.json') $RawStamp }
        elseif ($null -ne $Site) {
            $stamp = [ordered]@{ canon = [ordered]@{ version = '2026.05.01'; coreDigest = 'sha256:00'; model = 'reference' }; overlay = @(); ledgerShape = 'none'; site = $Site }
            Write-Text (Join-Path $root '.sza-canon.json') (ConvertTo-Json -InputObject $stamp -Depth 5)
        }
        if ($ProfileJson) { Write-Text (Join-Path $root '.sza-profile.json') $ProfileJson }
        return $root
    }
    function New-Runs([string] $Root, [string[]] $Files) { foreach ($f in $Files) { Write-Text (Join-Path $Root "temp\site-audit\$f") "# $f`n" } }
    $product = [ordered]@{ kind = 'product'; root = '.'; pages = @() }
    $alpha = New-Repo 'Alpha-Site' 'https://github.com/SerZhyAle/Alpha-Site.git' ([ordered]@{ kind = 'product'; root = '.'; pages = @('index.html', 'privacy.html') })
    $bravo = New-Repo 'Bravo-Docs' 'git@github.com:SerZhyAle/BravoDocs.git' ([ordered]@{ kind = 'product'; root = 'docs'; pages = @('index.html') })
    $charlie = New-Repo 'Site-Cname' 'https://github.com/SerZhyAle/Site-Cname.git' ([ordered]@{ kind = 'product'; root = 'docs'; pages = @('index.html', 'guide.html') })
    Write-Text (Join-Path $charlie 'docs\CNAME') "  docs.example.org  `n"
    Write-Text (Join-Path $charlie 'CNAME') "wrong.example.org`n"
    $userSite = New-Repo 'SerZhyAle.github.io' 'https://github.com/SerZhyAle/SerZhyAle.GitHub.io' ([ordered]@{ kind = 'portfolio'; root = '.'; pages = @('index.html') })
    $quiet = New-Repo 'Quiet' 'https://github.com/SerZhyAle/Quiet.git' ([ordered]@{ kind = 'none'; root = $null; pages = @() })
    $plain = New-Repo 'Plain' 'https://github.com/SerZhyAle/Plain.git' $null
    $noRoot = New-Repo 'Foxtrot' 'https://github.com/SerZhyAle/Foxtrot.git' ([ordered]@{ kind = 'product'; pages = @('index.html') })
    $tracked = New-Repo 'Tracked' 'https://github.com/SerZhyAle/Tracked.git' $product -Ignore "bin/`n"
    $broken = New-Repo 'Broken' 'https://github.com/SerZhyAle/Broken.git' $null -RawStamp '{ "site": { "kind": "product", '
    $dupeOne = New-Repo 'Dupe-One' 'https://github.com/SerZhyAle/Dupe-One.git' $product
    $dupeTwo = New-Repo 'Dupe-Two' 'https://github.com/SerZhyAle/Dupe-Two.git' $product
    foreach ($r in @($dupeOne, $dupeTwo)) { Write-Text (Join-Path $r 'CNAME') "same.example.org`n" }
    # Delta: an earlier run left a report. Echo-Site: runs _2 to _10 on the same date, and a later date.
    $delta = New-Repo 'Delta' 'https://github.com/SerZhyAle/Delta.git' $product
    New-Runs $delta @('2026-05-01\report.md')
    $echoRepo = New-Repo 'Echo-Site' 'https://github.com/SerZhyAle/Echo-Site.git' $product
    New-Item -ItemType Directory -Path (Join-Path $echoRepo 'docs') | Out-Null
    foreach ($n in @($date) + @(2..10 | ForEach-Object { "${date}_$_" }) + @('2026-05-05', 'notes')) {
        New-Item -ItemType Directory -Path (Join-Path $echoRepo "temp\site-audit\$n") -Force | Out-Null
    }
    New-Runs $echoRepo @("${date}_9\report.md", "${date}_10\report.md", '2026-05-05\report.md')
    # Hub: the portfolio site on a custom domain, with an earlier report of one external host.
    $hub = New-Repo 'Hub' 'https://github.com/SerZhyAle/Hub.git' ([ordered]@{ kind = 'portfolio'; root = '.'; pages = @('index.html') })
    Write-Text (Join-Path $hub 'CNAME') "hub.example.org`n"
    New-Runs $hub @('2026-05-02\external\example.org\report.md')
    $baseline = Join-Path $scratch 'baseline.md'
    Write-Text $baseline "# baseline`n"

    # Golf: a baseline, a full run, two robot-only runs and a failed one, the plain date gone, and a name that is no
    # run; the registry reaches it through a junction. Hotel: a baseline, then a robot-only run.
    $allLenses = @('robot', 'ux', 'release-facts', 'structured-data', 'i18n', 'docs')
    $golf = New-Repo 'Golf-Site' 'https://github.com/SerZhyAle/Golf-Site.git' $product
    New-Runs $golf (@('2026-05-01\baseline.md', '2026-05-02\report.md') + @($allLenses | ForEach-Object { "2026-05-02\$_.md" }) +
        @('2026-05-03\report.md', '2026-05-03\robot.md', "${date}_3\report.md", "${date}_3\robot.md"))
    foreach ($n in @("${date}_2", "${date}_99999999999")) { New-Item -ItemType Directory -Path (Join-Path $golf "temp\site-audit\$n") | Out-Null }
    $golfLink = Join-Path $scratch 'golf-link'
    New-Item -ItemType $(if ($IsWindows) { 'Junction' } else { 'SymbolicLink' }) -Path $golfLink -Target $golf | Out-Null
    $hotel = New-Repo 'Hotel' 'https://github.com/SerZhyAle/Hotel.git' $product
    New-Runs $hotel @('2026-05-01\baseline.md', '2026-05-02\report.md', '2026-05-02\robot.md')
    # The stamp and profile cases of -All.
    $kilo = New-Repo 'Kilo' 'https://github.com/SerZhyAle/Kilo.git' $product -Ignore ".scratch/`n" -ProfileJson '{ "version": "1", "paths": { "tempDir": ".scratch" } }'
    $lima = New-Repo 'Lima' 'https://github.com/SerZhyAle/Lima.git' $product -ProfileJson '{ "version": "1", "paths": { "tempDir": "../outside" } }'
    $mike = New-Repo 'Mike' 'https://github.com/SerZhyAle/Mike.git' $product -ProfileJson '{ "version": "2.0" }'
    $nada = New-Repo 'Nada' 'https://github.com/SerZhyAle/Nada.git' $null -RawStamp '{}'
    $noKind = New-Repo 'No-Kind' 'https://github.com/SerZhyAle/No-Kind.git' $null -RawStamp '{ "site": { "root": "docs", "pages": ["index.html"] } }'
    $emptySite = New-Repo 'Empty-Site' 'https://github.com/SerZhyAle/Empty-Site.git' $null -RawStamp '{ "site": {} }'
    $strSite = New-Repo 'Str-Site' 'https://github.com/SerZhyAle/Str-Site.git' $null -RawStamp '{ "site": "docs" }'
    $future = New-Repo 'Future' 'https://github.com/SerZhyAle/Future.git' $null -RawStamp '{ "schemaVersion": "2.0", "canon": { "version": "x", "coreDigest": "sha256:00", "model": "reference" }, "overlay": [], "ledgerShape": "none", "site": { "kind": "product", "root": ".", "pages": [] } }'
    $outside = New-Repo 'Outside' 'https://github.com/SerZhyAle/Outside.git' ([ordered]@{ kind = 'product'; root = '../elsewhere'; pages = @() })
    $noGit = New-Repo 'No-Git' '' $product -NoGit
    $noGitQuiet = New-Repo 'No-Git-Quiet' '' $null -NoGit
    $scheme = New-Repo 'Scheme' 'https://github.com/SerZhyAle/Scheme.git' $product
    Write-Text (Join-Path $scheme 'CNAME') "https://www.example.org`n"
    $mdOnly = New-Repo 'Md-Only' 'https://github.com/SerZhyAle/Md-Only.git' $product -Ignore "*.md`n"
    # The current location of an in-process call, apart from the process folder.
    $relDir = Join-Path $scratch 'rel-dir'
    Write-Text (Join-Path $relDir 'base.md') "# baseline`n"

    # The paths the script prints come from git, so the expected ones do too: an 8.3 temp path must not fail a case.
    $gitScratch = Split-Path -Parent ([IO.Path]::GetFullPath((git -C $alpha rev-parse --show-toplevel)))
    function Top([string] $Folder) { return (Join-Path $gitScratch $Folder) }

    # Entries are @(key, path[, rank[, enabled]]); the rank defaults to 10 per position.
    function New-Registry([string] $Name, [object[]] $Entries, [string] $Raw = '') {
        $root = Join-Path $scratch $Name
        New-Item -ItemType Directory -Path $root | Out-Null
        if ($Raw) { Write-Text (Join-Path $root 'repos.json') $Raw }
        elseif ($Entries) {
            $i = 0
            $repos = foreach ($e in $Entries) {
                $i++
                [ordered]@{ key = $e[0]; path = $e[1]; enabled = $(if ($e.Count -gt 3) { [bool]$e[3] } else { $true }); rank = $(if ($e.Count -gt 2) { [int]$e[2] } else { 10 * $i }) }
            }
            Write-Text (Join-Path $root 'repos.json') (ConvertTo-Json -InputObject ([ordered]@{ schemaVersion = '1.0'; repos = @($repos) }) -Depth 5)
        }
        return $root
    }
    $regAll = New-Registry 'reg-all' @(@('alpha', ($alpha + [IO.Path]::DirectorySeparatorChar)), @('quiet', $quiet), @('bravo', $bravo), @('plain', $plain), @('charlie', $charlie),
        @('gone', (Join-Path $scratch 'Gone')), @('tracked', $tracked), @('usersite', $userSite))
    $regDupe = New-Registry 'reg-dupe' @(@('dupe-one', $dupeOne), @('dupe-two', $dupeTwo))
    $regExt = New-Registry 'reg-ext' @(@('alpha', $alpha), @('hub', $hub))
    $regBroken = New-Registry 'reg-broken' @(@('broken', $broken), @('alpha', $alpha))
    # File order is not rank order; hotel is disabled.
    $regEdge = New-Registry 'reg-edge' @(@('golf', $golfLink, 50), @('hotel', $hotel, 40, $false), @('kilo', $kilo, 30), @('nada', $nada, 100),
        @('lima', $lima, 110), @('mike', $mike, 120), @('no-kind', $noKind, 130), @('empty-site', $emptySite, 140), @('str-site', $strSite, 150),
        @('future', $future, 160), @('outside', $outside, 170), @('no-git', $noGit, 180), @('no-git-quiet', $noGitQuiet, 190), @('scheme', $scheme, 200),
        @('md-only', $mdOnly, 210))
    $regBad = New-Registry 'reg-bad' @() -Raw '{ "schemaVersion": "1.0", "repos": [ '
    # No repos.json at all: the registry is missing, so a key is the folder name, lowercased.
    $regNone = New-Registry 'reg-none' @()

    $allFile = Join-Path $scratch 'all.json'
    $trackedFile = Join-Path $scratch 'tracked.json'
    $trackedOut = Join-Path $alpha 'site-audit-args.json'
    # Each group is a chain of steps run in order; the groups run side by side so the file stays fast.
    #   a = script arguments (-Date is always added, from date when the step names one), w = working folder,
    #   reg = SZA_PORTFOLIO_ROOT, make = a report.md written BEFORE the step, the one trace a finished run leaves for
    #   the next, cmd = a -Command line run instead of the script, for an in-process call
    $groups = [ordered]@{
        cname     = @( @{ a = @('-Repo', (Join-Path $charlie 'docs')); w = $scratch; reg = $regAll } )
        ghroot    = @( @{ a = @('-Repo', $alpha); w = $scratch; reg = $regAll } )
        ghdocs    = @( @{ a = @('-Repo', $bravo); w = $scratch; reg = $regNone } )
        usersite  = @( @{ a = @('-Repo', $userSite); w = $scratch; reg = $regAll } )
        none      = @( @{ a = @('-Repo', $quiet); w = $scratch; reg = $regAll } )
        noroot    = @( @{ a = @('-Repo', $noRoot); w = $scratch; reg = $regNone } )
        tracked   = @( @{ a = @('-Repo', $tracked, '-OutFile', $trackedFile); w = $scratch; reg = $regAll } )
        all       = @( @{ a = @('-All', '-OutFile', $allFile); w = $scratch; reg = $regAll } )
        dupe      = @( @{ a = @('-All'); w = $scratch; reg = $regDupe } )
        again     = @(
            @{ a = @('-Repo', $delta); w = $scratch; reg = $regNone },
            @{ a = @('-Repo', $delta); w = $scratch; reg = $regNone; make = (Join-Path $delta "temp\site-audit\$date\report.md") }
        )
        many      = @( @{ a = @(); w = (Join-Path $echoRepo 'docs'); reg = $regNone } )
        ext       = @( @{ a = @('-All', '-Url', 'https://Example.ORG/start,http://other.example.net,https://serzhyale.github.io/Alpha-Site'); w = $scratch; reg = $regExt } )
        modes     = @( @{ a = @('-Repo', $alpha, '-Mode', 'prepublish', '-Lens', 'robot,i18n', '-Baseline', $baseline); w = $scratch; reg = $regAll } )
        capitals  = @( @{ a = @('-Repo', $alpha, '-Mode', 'Prepublish', '-Lens', 'Robot,robot'); w = $scratch; reg = $regAll } )
        badlens   = @( @{ a = @('-Repo', $alpha, '-Lens', 'robot,seo'); w = $scratch; reg = $regAll } )
        broken    = @( @{ a = @('-All'); w = $scratch; reg = $regBroken }, @{ a = @('-Repo', $broken); w = $scratch; reg = $regBroken } )
        urls      = @( @{ a = @('-Repo', $hub, '-Url', 'https://example.org/,https://example.org/en/,http://LOCALHOST:8080/,https://example.net/docs/index.html'); w = $scratch; reg = $regExt } )
        urlquery  = @( @{ a = @('-Repo', $tracked, '-Url', 'https://example.net/?lang=ru'); w = $scratch; reg = $regAll } )
        urlnorepo = @( @{ a = @('-Repo', $tracked, '-Url', 'https://example.org/'); w = $scratch; reg = $regAll } )
        pkey      = @( @{ a = @('-All', '-PortfolioKey', 'tracked'); w = $scratch; reg = $regAll } )
        edge      = @( @{ a = @('-All'); w = $scratch; reg = $regEdge } )
        lensrun   = @( @{ a = @('-Repo', $golf, '-Lens', 'robot'); w = $scratch; reg = $regEdge } )
        regbad    = @(
            @{ a = @('-All'); w = $scratch; reg = $regBad },
            @{ cmd = "Set-Location -LiteralPath '$relDir'; & '$script_' -Date $date -Repo '$alpha' -Baseline base.md -OutFile rel-out.json; exit `$LASTEXITCODE"; w = $scratch; reg = $regBad }
        )
        outfile   = @( @{ a = @('-Repo', $alpha, '-OutFile', $trackedOut); w = $scratch; reg = $regAll } )
        baddate   = @( @{ a = @('-Repo', $alpha); date = '2026-13-45'; w = $scratch; reg = $regAll } )
    }
    $results = @{}
    $groups.GetEnumerator() | ForEach-Object -ThrottleLimit 16 -Parallel {
        $outList = @()
        foreach ($s in $_.Value) {
            if ($s.ContainsKey('make')) {
                [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($s.make)) | Out-Null
                [IO.File]::WriteAllText($s.make, "# report`n")
            }
            $psi = [Diagnostics.ProcessStartInfo]::new($using:pwshExe)
            $argv = if ($s.ContainsKey('cmd')) { @('-NoProfile', '-Command', $s.cmd) }
            else { @('-NoProfile', '-File', $using:script_, '-Date', $(if ($s.ContainsKey('date')) { $s.date } else { $using:date })) + $s.a }
            foreach ($x in $argv) { $psi.ArgumentList.Add([string] $x) }
            $psi.UseShellExecute = $false
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true
            $psi.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
            $psi.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
            $psi.WorkingDirectory = $s.w
            $psi.Environment['SZA_PORTFOLIO_ROOT'] = $s.reg
            $proc = [Diagnostics.Process]::Start($psi)
            $o = $proc.StandardOutput.ReadToEndAsync()
            $e = $proc.StandardError.ReadToEndAsync()
            if (-not $proc.WaitForExit(60000)) { $proc.Kill($true) }
            $proc.WaitForExit()
            $outList += [pscustomobject]@{ code = $proc.ExitCode; out = $o.Result; err = $e.Result }
        }
        [pscustomobject]@{ name = $_.Key; steps = $outList }
    } | ForEach-Object { $results[$_.name] = @($_.steps) }

    # The parsed JSON of a step that must have exited 0.
    function Get-Doc([string] $Group, [int] $Step = 0) {
        $s = $results[$Group][$Step]
        Assert-That ($s.code -eq 0) "$Group exit $($s.code): $($s.err.Trim()) $($s.out.Trim())"
        return (ConvertFrom-Json -InputObject $s.out -DateKind String)
    }
    function Get-Target($Doc, [string] $Key) {
        $hit = @($Doc.targets | Where-Object { $_.key -ceq $Key })
        Assert-That ($hit.Count -eq 1) "target '$Key' found $($hit.Count) time(s) among: $(@($Doc.targets | ForEach-Object { $_.key }) -join ', ')"
        return $hit[0]
    }
    function Get-Keys($List) { return (@($List | ForEach-Object { $_.key }) -join ',') }
    function Test-SamePath($A, $B) {
        if ($null -eq $A -or $null -eq $B) { return ($null -eq $A -and $null -eq $B) }
        return [string]::Equals([IO.Path]::GetFullPath([string] $A), [IO.Path]::GetFullPath([string] $B), [StringComparison]::OrdinalIgnoreCase)
    }

    Run-Case '1 a CNAME in the served root gives https://<cname>/' {
        $t = Get-Target (Get-Doc 'cname') 'charlie'
        Assert-That ($t.url -ceq 'https://docs.example.org/') "url $($t.url) (docs/CNAME, not the root CNAME)"
        Assert-That ($t.cname -ceq 'docs.example.org') "cname $($t.cname)"
        Assert-That ($t.siteRoot -ceq 'docs') "siteRoot $($t.siteRoot)"
        Assert-That (Test-SamePath $t.repo (Top 'Site-Cname')) "repo $($t.repo) (-Repo named its docs subfolder)"
        Assert-That ((@($t.pages) -join '|') -ceq 'index.html|guide.html') "pages $(@($t.pages) -join '|')"
        Assert-That ($t.run -ceq $date -and (Test-SamePath $t.outDir (Join-Path (Top 'Site-Cname') "temp\site-audit\$date"))) "run $($t.run), outDir $($t.outDir)"
        Assert-That ($null -eq $t.prevDir -and $null -eq $t.prevFile) "prevDir $($t.prevDir), prevFile $($t.prevFile)"
    }
    Run-Case '2 a GitHub origin gives https://<owner>.github.io/<repo>/ for root . and root docs' {
        # alpha's registry path ends in a separator: the key is still the registry's, not the folder name.
        $t = Get-Target (Get-Doc 'ghroot') 'alpha'
        Assert-That ($t.url -ceq 'https://serzhyale.github.io/Alpha-Site/') "root .: url $($t.url)"
        Assert-That ($null -eq $t.cname -and $t.siteRoot -ceq '.' -and $t.kind -ceq 'product') "root .: cname $($t.cname), siteRoot $($t.siteRoot), kind $($t.kind)"
        $t = Get-Target (Get-Doc 'ghdocs') 'bravo-docs'
        Assert-That ($t.url -ceq 'https://serzhyale.github.io/BravoDocs/') "root docs (an ssh origin): url $($t.url)"
        Assert-That ($null -eq $t.cname -and $t.siteRoot -ceq 'docs') "root docs: cname $($t.cname), siteRoot $($t.siteRoot)"
    }
    Run-Case '3 a user-site repository <owner>.github.io gives the host root' {
        $t = Get-Target (Get-Doc 'usersite') 'usersite'
        Assert-That ($t.url -ceq 'https://serzhyale.github.io/') "url $($t.url)"
        Assert-That ($t.kind -ceq 'portfolio') "kind $($t.kind)"
    }
    Run-Case '4 kind none is no target; a site block with no root serves the repository root' {
        $s = $results['none'][0]
        Assert-That ($s.code -eq 2) "kind none: exit $($s.code) $($s.err.Trim())"
        Assert-That ($s.err.Contains('has no site block') -and -not $s.out.Trim()) "kind none: stdout '$($s.out.Trim())', stderr '$($s.err.Trim())'"
        $t = Get-Target (Get-Doc 'noroot') 'foxtrot'
        Assert-That ($t.siteRoot -ceq '.' -and $t.url -ceq 'https://serzhyale.github.io/Foxtrot/') "no root: siteRoot $($t.siteRoot), url $($t.url)"
    }
    Run-Case '5 temp/ that git would track: refused, exit 3, nothing written' {
        $s = $results['tracked'][0]
        Assert-That ($s.code -eq 3) "exit $($s.code): $($s.err.Trim())"
        Assert-That ($s.err.Contains("refused tracked: git would track temp/site-audit/$date/ - add temp/ to .gitignore first")) "stderr: $($s.err.Trim())"
        Assert-That (-not $s.out.Trim()) "stdout: $($s.out.Trim())"
        Assert-That (-not (Test-Path -LiteralPath $trackedFile)) 'the -OutFile was written'
        Assert-That (-not (Test-Path -LiteralPath (Join-Path $tracked 'temp'))) 'a temp folder was created'
    }
    Run-Case '6 -All walks the registry and skips the repositories with no site block' {
        $s = $results['all'][0]
        Assert-That ($s.code -eq 0) "exit $($s.code): $($s.err.Trim())"
        Assert-That ($s.out.Trim() -ceq "site-targets: 4 target(s), 1 refused -> $allFile") "stdout: $($s.out.Trim())"
        $bytes = [IO.File]::ReadAllBytes($allFile)
        Assert-That (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)) 'the -OutFile starts with a BOM'
        $d = ConvertFrom-Json -InputObject ([Text.UTF8Encoding]::new($false).GetString($bytes)) -DateKind String
        Assert-That ((Get-Keys $d.targets) -ceq 'alpha,bravo,charlie,usersite') "targets: $(Get-Keys $d.targets) (quiet has kind none, plain no stamp, gone no folder)"
        Assert-That ((Get-Keys $d.refused) -ceq 'tracked' -and $s.err.Contains('refused tracked:')) "refused: $(Get-Keys $d.refused); stderr: $($s.err.Trim())"
        $t = Get-Target $d 'bravo'
        Assert-That ($t.url -ceq 'https://serzhyale.github.io/BravoDocs/') "bravo (the registry key): url $($t.url)"
    }
    Run-Case '7 two repositories with the same URL: the first is kept' {
        $d = Get-Doc 'dupe'
        Assert-That ((Get-Keys $d.targets) -ceq 'dupe-one' -and (Get-Target $d 'dupe-one').url -ceq 'https://same.example.org/') "targets: $(Get-Keys $d.targets)"
        $r = @($d.refused)
        Assert-That ($r.Count -eq 1 -and $r[0].key -ceq 'dupe-two' -and $r[0].reason -ceq 'same URL as dupe-one: https://same.example.org/') "refused: $(ConvertTo-Json -InputObject $r -Compress)"
        Assert-That (Test-SamePath $r[0].repo (Top 'Dupe-Two')) "refused repo $($r[0].repo)"
        Assert-That ($results['dupe'][0].err.Contains('refused dupe-two: same URL as dupe-one')) "stderr: $($results['dupe'][0].err.Trim())"
    }
    Run-Case '8 a second run on the same date gets <date>_2, and its prevDir is the first' {
        $base = Join-Path (Top 'Delta') 'temp\site-audit'
        $t = Get-Target (Get-Doc 'again' 0) 'delta'
        Assert-That ($t.run -ceq $date -and (Test-SamePath $t.outDir (Join-Path $base $date))) "first: run $($t.run), outDir $($t.outDir)"
        Assert-That ((Test-SamePath $t.prevDir (Join-Path $base '2026-05-01')) -and (Test-SamePath $t.prevFile (Join-Path $base '2026-05-01\report.md'))) "first: prevDir $($t.prevDir), prevFile $($t.prevFile)"
        $t = Get-Target (Get-Doc 'again' 1) 'delta'
        Assert-That ($t.run -ceq "${date}_2" -and (Test-SamePath $t.outDir (Join-Path $base "${date}_2"))) "second: run $($t.run), outDir $($t.outDir)"
        Assert-That (Test-SamePath $t.prevDir (Join-Path $base $date)) "second: prevDir $($t.prevDir)"
        # No -Repo: the current folder, a subfolder of Echo-Site; runs up to _10 exist, _9 and _10 left a report.
        $t = Get-Target (Get-Doc 'many') 'echo-site'
        Assert-That ($t.run -ceq "${date}_11") "after _10: run $($t.run)"
        Assert-That (Test-SamePath $t.prevDir (Join-Path (Top 'Echo-Site') "temp\site-audit\${date}_10")) "after _10: prevDir $($t.prevDir) (not _9, not the later 2026-05-05)"
    }
    Run-Case '9 a -Url host lands under the portfolio target''s run folder in external/<host>' {
        $d = Get-Doc 'ext'
        $runDir = Join-Path (Top 'Hub') "temp\site-audit\$date"
        $h = Get-Target $d 'hub'
        Assert-That ((Test-SamePath $h.outDir $runDir) -and $null -eq $h.prevDir) "hub: outDir $($h.outDir), prevDir $($h.prevDir) (an external report is not the hub's own)"
        Assert-That (Test-SamePath $d.portfolioOut (Join-Path $runDir 'portfolio.md')) "portfolioOut $($d.portfolioOut) (the portfolio target on a custom domain, though alpha comes first)"
        $t = Get-Target $d 'example.org'
        Assert-That ($t.kind -ceq 'external' -and $t.url -ceq 'https://example.org/start/') "example.org: kind $($t.kind), url $($t.url) (the host lowercased, the path kept)"
        Assert-That ((Test-SamePath $t.outDir (Join-Path $runDir 'external\example.org')) -and $t.run -ceq $date) "example.org: outDir $($t.outDir), run $($t.run)"
        Assert-That ($null -eq $t.repo -and $null -eq $t.cname -and $null -eq $t.siteRoot -and @($t.pages).Count -eq 0) "example.org: repo $($t.repo), cname $($t.cname), siteRoot $($t.siteRoot)"
        $prev = Join-Path (Top 'Hub') 'temp\site-audit\2026-05-02\external\example.org'
        Assert-That ((Test-SamePath $t.prevDir $prev) -and (Test-SamePath $t.prevFile (Join-Path $prev 'report.md'))) "example.org: prevDir $($t.prevDir), prevFile $($t.prevFile)"
        $t = Get-Target $d 'other.example.net'
        Assert-That ($t.url -ceq 'http://other.example.net/' -and (Test-SamePath $t.outDir (Join-Path $runDir 'external\other.example.net'))) "other.example.net: url $($t.url), outDir $($t.outDir)"
        Assert-That ($null -eq $t.prevDir) "other.example.net: prevDir $($t.prevDir)"
        Assert-That ((Get-Keys $d.targets) -ceq 'alpha,hub,example.org,other.example.net') "targets: $(Get-Keys $d.targets) (alpha's own URL given again with -Url is no second target)"
    }
    Run-Case '10 -Mode prepublish, -Lens and -Baseline pass through' {
        $d = Get-Doc 'ghroot'
        Assert-That ($d.mode -ceq 'audit' -and @($d.lenses).Count -eq 0 -and $d.baseline -ceq '') "defaults: mode $($d.mode), lenses '$(@($d.lenses) -join ',')', baseline '$($d.baseline)'"
        $d = Get-Doc 'modes'
        Assert-That ($d.mode -ceq 'prepublish') "mode $($d.mode)"
        Assert-That ((@($d.lenses) -join ',') -ceq 'robot,i18n') "lenses $(@($d.lenses) -join ',')"
        Assert-That (Test-SamePath $d.baseline $baseline) "baseline $($d.baseline)"
        Assert-That ($d.date -ceq $date -and (Test-SamePath $d.pluginRoot $SourceRoot)) "date $($d.date), pluginRoot $($d.pluginRoot)"
        # The workflow compares mode and lens names case-sensitively, so the script hands them over in its spelling.
        $d = Get-Doc 'capitals'
        Assert-That ($d.mode -ceq 'prepublish' -and (@($d.lenses) -join ',') -ceq 'robot') "-Mode Prepublish -Lens Robot,robot: mode $($d.mode), lenses $(@($d.lenses) -join ',')"
        $s = $results['badlens'][0]
        Assert-That ($s.code -eq 2 -and $s.err.Contains("'seo'")) "unknown lens: exit $($s.code) $($s.err.Trim())"
    }
    Run-Case '11 a stamp that is not JSON is refused, never skipped as one without a site' {
        $d = Get-Doc 'broken'
        Assert-That ((Get-Keys $d.targets) -ceq 'alpha') "targets: $(Get-Keys $d.targets)"
        $r = @($d.refused)
        Assert-That ($r.Count -eq 1 -and $r[0].key -ceq 'broken' -and $r[0].reason -match 'not valid JSON') "refused: $(ConvertTo-Json -InputObject $r -Compress)"
        $s = $results['broken'][1]
        Assert-That ($s.code -eq 3 -and $s.err.Contains('refused broken: the stamp .sza-canon.json is not valid JSON')) "-Repo alone: exit $($s.code) $($s.err.Trim())"
    }
    Run-Case '12 -Url: one URL per host, a port in the folder name, a page cut to its folder; a query is exit 2' {
        $d = Get-Doc 'urls'
        $runDir = Join-Path (Top 'Hub') "temp\site-audit\$date"
        Assert-That ((Get-Keys $d.targets) -ceq 'hub,example.org,localhost_8080,example.net') "targets: $(Get-Keys $d.targets)"
        $t = Get-Target $d 'example.org'
        Assert-That ($t.url -ceq 'https://example.org/' -and (Test-SamePath $t.outDir (Join-Path $runDir 'external\example.org'))) "example.org: url $($t.url), outDir $($t.outDir)"
        $r = @($d.refused)
        Assert-That ($r.Count -eq 1 -and $r[0].key -ceq 'example.org' -and $r[0].reason -ceq 'same host as https://example.org/: one external/example.org folder per run') "refused: $(ConvertTo-Json -InputObject $r -Compress) (two URLs on one host would share one folder)"
        $t = Get-Target $d 'localhost_8080'
        Assert-That ($t.url -ceq 'http://localhost:8080/' -and (Test-SamePath $t.outDir (Join-Path $runDir 'external\localhost_8080'))) "port: url $($t.url), outDir $($t.outDir) (no ':' in a folder name)"
        $t = Get-Target $d 'example.net'
        Assert-That ($t.url -ceq 'https://example.net/docs/') "page: url $($t.url) (index.html cut, the folder kept)"
        $s = $results['urlquery'][0]
        Assert-That ($s.code -eq 2 -and $s.err.Contains('give the base URL, not a page') -and -not $s.err.Contains('refused')) "query: exit $($s.code) $($s.err.Trim()) (judged before the tracked repository is weighed)"
    }
    Run-Case '13 the previous run: report.md, else baseline.md; a one-lens run is no yardstick for a full run' {
        $d = Get-Doc 'edge'
        $base = Join-Path (Top 'Golf-Site') 'temp\site-audit'
        $t = Get-Target $d 'golf'
        Assert-That ($t.run -ceq "${date}_4") "golf: run $($t.run) (one after _3: the plain date is gone, _2 failed, _99999999999 is no run)"
        Assert-That ((Test-SamePath $t.prevDir (Join-Path $base '2026-05-02')) -and (Test-SamePath $t.prevFile (Join-Path $base '2026-05-02\report.md'))) "golf full run: prevDir $($t.prevDir), prevFile $($t.prevFile) (the newest run with every lens report, not the robot-only _3)"
        $t = Get-Target (Get-Doc 'lensrun') 'golf'
        Assert-That ($t.run -ceq "${date}_4" -and (Test-SamePath $t.prevFile (Join-Path $base "${date}_3\report.md"))) "golf robot run: run $($t.run), prevFile $($t.prevFile) (the newest run that holds robot.md)"
        $base = Join-Path (Top 'Hotel') 'temp\site-audit'
        $t = Get-Target $d 'hotel'
        Assert-That ((Test-SamePath $t.prevDir (Join-Path $base '2026-05-01')) -and (Test-SamePath $t.prevFile (Join-Path $base '2026-05-01\baseline.md'))) "hotel: prevDir $($t.prevDir), prevFile $($t.prevFile) (a baseline is a whole audit; the newer run holds only robot.md)"
    }
    Run-Case '14 -All in rank order over the stamp and profile cases' {
        $s = $results['edge'][0]
        $d = Get-Doc 'edge'
        Assert-That ((Get-Keys $d.targets) -ceq 'kilo,hotel,golf') "targets: $(Get-Keys $d.targets) (rank order, not file order; hotel is disabled and still audited)"
        $t = Get-Target $d 'kilo'
        Assert-That (Test-SamePath $t.outDir (Join-Path (Top 'Kilo') ".scratch\site-audit\$date")) "kilo: outDir $($t.outDir) (paths.tempDir of its profile, the folder it ignores)"
        Assert-That (Test-SamePath (Get-Target $d 'golf').repo (Top 'Golf-Site')) "golf: repo $((Get-Target $d 'golf').repo) (the registry names a link to it)"
        $expect = [ordered]@{
            'lima'       = "paths.tempDir '../outside' in .sza-profile.json is not a folder inside the repository"
            'mike'       = "HARNESS-PROFILE: unsupported or malformed 'version'"
            'no-kind'    = 'the site block of the stamp has no kind'
            'empty-site' = 'the site block of the stamp has no kind'
            'str-site'   = 'the site of the stamp is not an object'
            'future'     = "REPO-STAMP: unsupported or malformed 'schemaVersion'"
            'outside'    = "site.root '../elsewhere' is not a folder inside the repository"
            'no-git'     = 'git cannot open the folder'
            'scheme'     = "the CNAME in the served root holds 'https://www.example.org', not a bare host name"
            'md-only'    = "git would track temp/site-audit/$date/"
        }
        Assert-That ((Get-Keys $d.refused) -ceq (@($expect.Keys) -join ',')) "refused: $(Get-Keys $d.refused) (nada's stamp {} and no-git-quiet with no stamp are skipped without a word)"
        foreach ($k in $expect.Keys) {
            $r = @($d.refused | Where-Object { $_.key -ceq $k })[0]
            Assert-That ($r.reason.Contains($expect[$k])) "${k}: $($r.reason)"
        }
        Assert-That ($s.err.Contains('refused md-only: git would track') -and $s.err.Contains('refused future: REPO-STAMP')) "stderr: $($s.err.Trim())"
    }
    Run-Case '15 the refusals survive every exit' {
        $s = $results['urlnorepo'][0]
        Assert-That ($s.code -eq 3 -and -not $s.out.Trim()) "-Url with no target left: exit $($s.code), stdout '$($s.out.Trim())'"
        Assert-That ($s.err.Contains('-Url https://example.org/ needs a repository target') -and $s.err.Contains("refused tracked: git would track temp/site-audit/$date/")) "-Url with no target left: stderr $($s.err.Trim())"
        $s = $results['pkey'][0]
        Assert-That ($s.code -eq 2 -and $s.err.Contains("-PortfolioKey 'tracked' is not among the targets") -and $s.err.Contains('refused tracked: git would track')) "-PortfolioKey of a refused target: exit $($s.code) $($s.err.Trim())"
    }
    Run-Case '16 an unreadable registry is exit 2 under -All, a note under -Repo; a linked registry path keeps its key' {
        $s = $results['regbad'][0]
        Assert-That ($s.code -eq 2 -and $s.err.Contains('the portfolio registry cannot be read: RegistryNotJson')) "-All: exit $($s.code) $($s.err.Trim())"
        $s = $results['regbad'][1]
        Assert-That ($s.code -eq 0 -and $s.err.Contains('note: no registry key (RegistryNotJson') -and $s.err.Contains('named after its folder: alpha-site')) "-Repo: exit $($s.code) $($s.err.Trim())"
        # -Repo names Golf-Site and the registry the link to it: found by the folder git reports, not the folder name.
        $t = Get-Target (Get-Doc 'lensrun') 'golf'
        Assert-That (Test-SamePath $t.repo (Top 'Golf-Site')) "golf through the link: repo $($t.repo)"
    }
    Run-Case '17 relative -Baseline and -OutFile follow the current location; a tracked -OutFile and a false -Date are exit 2' {
        $s = $results['regbad'][1]
        $relOut = Join-Path $relDir 'rel-out.json'
        Assert-That (Test-Path -LiteralPath $relOut -PathType Leaf) "no $relOut; stdout '$($s.out.Trim())', stderr '$($s.err.Trim())'"
        $prefix = 'site-targets: 1 target(s), 0 refused -> '
        Assert-That ($s.out.Trim().StartsWith($prefix) -and (Test-SamePath $s.out.Trim().Substring($prefix.Length) $relOut)) "stdout: $($s.out.Trim())"
        $d = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($relOut)) -DateKind String
        Assert-That ((Test-SamePath $d.baseline (Join-Path $relDir 'base.md')) -and (Get-Keys $d.targets) -ceq 'alpha-site') "baseline $($d.baseline), targets $(Get-Keys $d.targets)"
        $s = $results['outfile'][0]
        Assert-That ($s.code -eq 2 -and $s.err.Contains('git would track it') -and -not (Test-Path -LiteralPath $trackedOut)) "-OutFile in a tracked folder: exit $($s.code) $($s.err.Trim())"
        $s = $results['baddate'][0]
        Assert-That ($s.code -eq 2 -and $s.err.Contains("got '2026-13-45'")) "-Date 2026-13-45: exit $($s.code) $($s.err.Trim())"
    }
}
finally {
    foreach ($k in $savedEnv.Keys) { [Environment]::SetEnvironmentVariable($k, $savedEnv[$k]) }
    if (-not $KeepScratch) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host ("site-targets tests: {0} run, {1} passed, {2} failed" -f $run, $passed, $failed)
exit $(if ($failed -eq 0) { 0 } else { 1 })
