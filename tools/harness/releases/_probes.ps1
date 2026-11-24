#requires -Version 7.0
<#
.SYNOPSIS
    Read-only channel probes of the release ledger (RELEASE-LEDGER rule 8, canon S0092).

.DESCRIPTION
    One adapter per probe kind. Every adapter only READS: a public page, a public API, or a read-only call of the
    channel's own tool (gh, msstore). None of them uploads, submits, commits, merges or tags. An adapter returns

        [pscustomobject]@{ ok; reason; observed = @( @{ version; state; at; ref; url; note; track; rollout } ); diagnostics = @( ... ) }

    ok = $false means "unverified" - the tool is missing, a credential is absent or refused, the page does not show a
    version without a script - and `reason` says which; the caller writes no event for it. `at` on an observation is
    the channel's own time when it gives one (used by `import`), else empty.

    `diagnostics` are readings that are printed and never written (RELEASE-LEDGER 0.2 rule 12): the Play probe reports
    the track configuration and the release lifecycle of one exact track there, and returns no observation at all.

    The parsers (ConvertFrom-Rl*) are pure functions over the channel's response text, so the fast suite checks them
    without the network. SZA_RELEASES_PROBE_STUB names a JSON file { "<channel key>": { ok, reason, observed } } that
    replaces every adapter call - the suite's way to drive the verbs end to end.

    Credentials: the Play probe reads a Google service account key from the file SZA_PLAY_SERVICE_ACCOUNT_JSON names,
    outside every repository; nothing a probe reads or receives is written to the ledger except the public facts.

    The Play probe opens a transient edit, which Play counts as the application's one edit and which can delete a
    publisher's: it takes the per-application lock of `_play-lock.ps1` around that read, tries once, and opens no edit when
    it cannot take it (GOOGLE-PLAY rule 19, CANONR-0174).

    Exit codes: none - a dot-sourced library.
#>

. (Join-Path $PSScriptRoot '_play-lock.ps1')

function New-RlProbeResult {
    param([bool]$Ok, [string]$Reason = '', [AllowNull()][AllowEmptyCollection()][object[]]$Observed = @(), [AllowNull()][AllowEmptyCollection()][object[]]$Diagnostics = @())
    $items = [object[]]@($Observed | Where-Object { $null -ne $_ })
    $readings = [object[]]@($Diagnostics | Where-Object { $null -ne $_ })
    return [pscustomobject]@{ ok = $Ok; reason = $Reason; observed = $items; diagnostics = $readings }
}

function New-RlObservation {
    param([Parameter(Mandatory)][string]$Version, [Parameter(Mandatory)][string]$State,
        [string]$At, [string]$Ref, [string]$Url, [string]$Note, [string]$Track, [object]$Rollout)
    return [pscustomobject]@{ version = $Version; state = $State; at = $At; ref = $Ref; url = $Url; note = $Note; track = $Track; rollout = $Rollout }
}

function Invoke-RlHttpGet {
    param([Parameter(Mandatory)][string]$Uri)
    $r = Invoke-WebRequest -Uri $Uri -UserAgent 'sza-release-ledger/1 (read-only probe)' -TimeoutSec 25 -MaximumRedirection 5 -ErrorAction Stop
    $c = $r.Content
    if ($c -is [byte[]]) { return [Text.Encoding]::UTF8.GetString($c) }
    return [string]$c
}

function Get-RlFirstLine {
    param([AllowNull()]$Text)
    $t = (@($Text) -join "`n").Trim()
    if (-not $t) { return 'no output' }
    return ($t -split "`r?`n")[0]
}

# ---- GitHub ----

function Get-RlGithubRepoFromRemote {
    param([Parameter(Mandatory)][string]$RepoRoot)
    $url = & git -C $RepoRoot remote get-url origin 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $url) { return $null }
    if ([string]$url -match 'github\.com[:/]([^/]+)/([^/\s]+?)(\.git)?\s*$') { return "$($Matches[1])/$($Matches[2])" }
    return $null
}

function ConvertFrom-RlGithubReleases {
    # gh release list --json tagName,isDraft,isPrerelease,publishedAt,createdAt. A draft is pending (not visible to a
    # visitor); a prerelease is live with a note. Only tags of the form <prefix><digit>.. are this package's releases,
    # so an edition's own tags (ext-cws-v26..) never pass as the app's.
    param([Parameter(Mandatory)][string]$Json, [Parameter(Mandatory)][string]$Repo, [string]$TagPrefix = 'v')
    $out = [System.Collections.Generic.List[object]]::new()
    foreach ($r in @(ConvertFrom-RlJson $Json)) {
        if ($null -eq $r) { continue }
        $tag = [string](Get-RlProp $r 'tagName')
        if (-not $tag.StartsWith($TagPrefix, [StringComparison]::Ordinal)) { continue }
        $version = $tag.Substring($TagPrefix.Length)
        if ($version -notmatch '^\d') { continue }
        $draft = [bool](Get-RlProp $r 'isDraft')
        $pre = [bool](Get-RlProp $r 'isPrerelease')
        $at = [string](Get-RlProp $r 'publishedAt')
        if (-not $at -or $at -like '0001-*') { $at = [string](Get-RlProp $r 'createdAt') }
        $out.Add((New-RlObservation -Version $version -State $(if ($draft) { 'pending' } else { 'live' }) -At $at -Ref $tag `
                    -Url "https://github.com/$Repo/releases/tag/$tag" -Note $(if ($draft) { 'draft release' } elseif ($pre) { 'prerelease' } else { '' })))
    }
    return [object[]]$out.ToArray()
}

function Invoke-RlProbeGithub {
    param($Spec, [Parameter(Mandatory)][string]$RepoRoot, [int]$Limit = 10)
    $repo = [string](Get-RlProp $Spec 'repo')
    if (-not $repo) { $repo = Get-RlGithubRepoFromRemote $RepoRoot }
    if (-not $repo) { return (New-RlProbeResult -Ok $false -Reason 'no repo in channels.json and no github.com origin remote') }
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { return (New-RlProbeResult -Ok $false -Reason 'gh is not on PATH') }
    $prefix = [string](Get-RlProp $Spec 'tagPrefix')
    if (-not (Test-RlHasProp $Spec 'tagPrefix')) { $prefix = 'v' }
    $out = & gh release list -R $repo --limit $Limit --json 'tagName,isDraft,isPrerelease,publishedAt,createdAt' 2>&1
    if ($LASTEXITCODE -ne 0) { return (New-RlProbeResult -Ok $false -Reason "gh release list failed: $(Get-RlFirstLine $out)") }
    return (New-RlProbeResult -Ok $true -Observed @(ConvertFrom-RlGithubReleases -Json (@($out) -join "`n") -Repo $repo -TagPrefix $prefix))
}

function Test-RlHasProp {
    param($Object, [Parameter(Mandatory)][string]$Name)
    if ($null -eq $Object) { return $false }
    if ($Object -is [System.Collections.IDictionary]) { return $Object.Contains($Name) }
    return ($null -ne $Object.PSObject.Properties[$Name])
}

# ---- winget (the microsoft/winget-pkgs repository is the source of truth) ----

function Get-RlWingetManifestPath {
    param([Parameter(Mandatory)][string]$Id)
    return ('manifests/{0}/{1}' -f $Id.Substring(0, 1).ToLowerInvariant(), ($Id.Split('.') -join '/'))
}

function ConvertFrom-RlWingetVersions {
    # The contents listing of manifests/<l>/<Publisher>/<Name>: each folder that starts with a digit is a merged
    # version, live once the source index refreshes. A nested package's folder starts with a letter and is skipped.
    param([Parameter(Mandatory)][string]$Json, [Parameter(Mandatory)][string]$Id)
    $path = Get-RlWingetManifestPath $Id
    $out = [System.Collections.Generic.List[object]]::new()
    foreach ($e in @(ConvertFrom-RlJson $Json)) {
        if ($null -eq $e -or [string](Get-RlProp $e 'type') -cne 'dir') { continue }
        $name = [string](Get-RlProp $e 'name')
        if ($name -notmatch '^\d') { continue }
        $out.Add((New-RlObservation -Version $name -State 'live' -Url "https://github.com/microsoft/winget-pkgs/tree/master/$path/$name"))
    }
    return [object[]]@(Sort-RlVersions $out.ToArray())
}

function ConvertFrom-RlWingetPulls {
    # Open pull requests whose title names the identifier: "New version: SZA.App version 26.1117.1450".
    param([Parameter(Mandatory)][string]$Json, [Parameter(Mandatory)][string]$Id)
    $out = [System.Collections.Generic.List[object]]::new()
    foreach ($p in @(ConvertFrom-RlJson $Json)) {
        if ($null -eq $p) { continue }
        $title = [string](Get-RlProp $p 'title')
        if ($title -notmatch ('(?i)(^|[\s:])' + [regex]::Escape($Id) + '(\s|$)')) { continue }
        $m = [regex]::Matches($title, '(?<![\w.])(\d+(?:\.\d+)+)(?![\w.])')
        if ($m.Count -eq 0) { continue }
        $n = [string](Get-RlProp $p 'number')
        $out.Add((New-RlObservation -Version $m[$m.Count - 1].Value -State 'submitted' -Ref "PR#$n" -Url ([string](Get-RlProp $p 'url')) -Note 'winget-pkgs pull request open'))
    }
    return [object[]]$out.ToArray()
}

function Sort-RlVersions {
    # Oldest first: a dotted numeric version by its numbers, anything else after them by text.
    param([AllowEmptyCollection()][object[]]$Items = @())
    return [object[]]@($Items | Sort-Object -Property @{ Expression = {
                $core = ConvertTo-RlVersionCore $_.version
                if ($core -match '^\d+(\.\d+)*$') { (($core.Split('.') | ForEach-Object { $_.PadLeft(12, '0') }) -join '.') } else { 'z' + $core }
            } })
}

function Invoke-RlProbeWinget {
    param($Spec, [switch]$All)
    $id = [string](Get-RlProp $Spec 'id')
    if (-not $id) { return (New-RlProbeResult -Ok $false -Reason 'no PackageIdentifier (id) in channels.json') }
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { return (New-RlProbeResult -Ok $false -Reason 'gh is not on PATH') }
    $path = Get-RlWingetManifestPath $id
    $listing = & gh api "repos/microsoft/winget-pkgs/contents/$path" 2>&1
    $observed = [System.Collections.Generic.List[object]]::new()
    if ($LASTEXITCODE -ne 0) {
        if ((@($listing) -join ' ') -notmatch '404|Not Found') { return (New-RlProbeResult -Ok $false -Reason "gh api failed: $(Get-RlFirstLine $listing)") }
    } else {
        $versions = @(ConvertFrom-RlWingetVersions -Json (@($listing) -join "`n") -Id $id)
        if (-not $All -and $versions.Count -gt 0) { $versions = @($versions[-1]) }
        foreach ($v in $versions) { $observed.Add($v) }
    }
    $pulls = & gh pr list -R microsoft/winget-pkgs --state open --search "$id in:title" --json 'number,title,url' --limit 20 2>&1
    if ($LASTEXITCODE -eq 0) { foreach ($p in @(ConvertFrom-RlWingetPulls -Json (@($pulls) -join "`n") -Id $id)) { $observed.Add($p) } }
    return (New-RlProbeResult -Ok $true -Observed @($observed.ToArray()))
}

# ---- Microsoft Store (msstore, the same read-only call as tools/Store-Preflight.ps1) ----

function Invoke-RlStoreRead {
    # The executable boundary: `msstore submission get <12-char id>` is the only Store call this file can make.
    param([Parameter(Mandatory)][string]$StoreId)
    if ($StoreId -cnotmatch '^[A-Za-z0-9]{12}$') { throw 'Store operation is not allowed.' }
    $global:LASTEXITCODE = 0
    $output = & msstore submission get $StoreId 2>&1
    return @{ Text = (@($output) -join "`n"); ExitCode = $LASTEXITCODE }
}

function ConvertFrom-RlStoreSubmission {
    # The CLI's text around one submission resource. Published -> live; a *Failed status -> rejected; any other
    # status is a submission in flight (certification, pre-processing, release) -> submitted. The version is the
    # highest package version of the resource.
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Raw, [Parameter(Mandatory)][string]$StoreId)
    if ($Raw -match '(?i)(no|could not find|not found|does not have).{0,100}(published submission|live submission)' -and
        $Raw -notmatch '(?i)found the last published submission') {
        return (New-RlProbeResult -Ok $true -Reason 'no live submission yet')
    }
    $start = $Raw.IndexOf('{'); $end = $Raw.LastIndexOf('}')
    if ($start -lt 0 -or $end -lt $start) { return (New-RlProbeResult -Ok $false -Reason 'no submission resource in the msstore output') }
    try { $s = ($Raw.Substring($start, $end - $start + 1) -replace '[\r\n]', '') | ConvertFrom-Json -ErrorAction Stop }
    catch { return (New-RlProbeResult -Ok $false -Reason 'the submission resource does not parse') }
    $status = [string](Get-RlProp $s 'Status')
    if (-not $status) { return (New-RlProbeResult -Ok $false -Reason 'the submission resource carries no Status') }
    $best = $null; $bestText = $null
    foreach ($p in @(Get-RlProp $s 'ApplicationPackages')) {
        $t = [string](Get-RlProp $p 'Version'); $v = $null
        if ([version]::TryParse($t, [ref]$v) -and ($null -eq $best -or $v -gt $best)) { $best = $v; $bestText = $t }
    }
    if (-not $bestText) { return (New-RlProbeResult -Ok $false -Reason "submission status $status carries no package version") }
    $state = if ($status -ceq 'Published') { 'live' } elseif ($status -match 'Failed$') { 'rejected' } else { 'submitted' }
    return (New-RlProbeResult -Ok $true -Observed @(New-RlObservation -Version $bestText -State $state -Ref ([string](Get-RlProp $s 'FriendlyName')) `
                -Url "https://apps.microsoft.com/detail/$StoreId" -Note "Store status $status"))
}

function Invoke-RlProbeMsstore {
    param($Spec)
    $storeId = [string](Get-RlProp $Spec 'storeId')
    if ($storeId -cnotmatch '^[A-Za-z0-9]{12}$') { return (New-RlProbeResult -Ok $false -Reason 'no twelve-character storeId in channels.json') }
    if (-not (Get-Command msstore -ErrorAction SilentlyContinue)) { return (New-RlProbeResult -Ok $false -Reason 'msstore is not on PATH') }
    try { $r = Invoke-RlStoreRead $storeId } catch { return (New-RlProbeResult -Ok $false -Reason 'the msstore call failed') }
    if ($r.ExitCode -ne 0 -and $r.Text -notmatch '{') { return (New-RlProbeResult -Ok $false -Reason 'msstore is not configured or the token was refused') }
    return (ConvertFrom-RlStoreSubmission -Raw $r.Text -StoreId $storeId)
}

# ---- Google Play (Play Developer API through a service account; a transient edit is opened and deleted) ----

function ConvertTo-RlBase64Url {
    param([Parameter(Mandatory)][byte[]]$Bytes)
    return [Convert]::ToBase64String($Bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

function Get-RlGoogleAccessToken {
    param([Parameter(Mandatory)][string]$KeyFile, [Parameter(Mandatory)][string]$Scope)
    $sa = Get-Content -LiteralPath $KeyFile -Raw -Encoding utf8 | ConvertFrom-Json
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $header = ConvertTo-RlBase64Url ([Text.Encoding]::UTF8.GetBytes('{"alg":"RS256","typ":"JWT"}'))
    $claims = [ordered]@{ iss = [string]$sa.client_email; scope = $Scope; aud = 'https://oauth2.googleapis.com/token'; iat = $now; exp = $now + 3600 }
    $payload = ConvertTo-RlBase64Url ([Text.Encoding]::UTF8.GetBytes(($claims | ConvertTo-Json -Compress)))
    $rsa = [Security.Cryptography.RSA]::Create()
    try {
        $rsa.ImportFromPem([string]$sa.private_key)
        $sig = $rsa.SignData([Text.Encoding]::UTF8.GetBytes("$header.$payload"), [Security.Cryptography.HashAlgorithmName]::SHA256, [Security.Cryptography.RSASignaturePadding]::Pkcs1)
    } finally { $rsa.Dispose() }
    $jwt = "$header.$payload.$(ConvertTo-RlBase64Url $sig)"
    $resp = Invoke-RestMethod -Method Post -Uri 'https://oauth2.googleapis.com/token' -Body @{ grant_type = 'urn:ietf:params:oauth:grant-type:jwt-bearer'; assertion = $jwt } -TimeoutSec 25
    return [string]$resp.access_token
}

# The documented values of ReleaseLifecycleState of applications.tracks.releases.list, without the
# RELEASE_LIFECYCLE_STATE_ prefix; anything else is kept as reported and read as unrecognised.
$script:RlPlayLifecycle = [ordered]@{
    UNSPECIFIED            = 'the release has no state yet'
    DRAFT                  = 'a release that can still be edited'
    NOT_SENT_FOR_REVIEW    = 'a release ready to be sent for review, waiting for the developer'
    IN_REVIEW              = 'submitted and in review'
    APPROVED_NOT_PUBLISHED = 'passed review and waits for the developer to publish it'
    NOT_APPROVED           = 'rejected in review'
    PUBLISHED              = 'available to users on this track, a partial or a resumable halted rollout included - not proof of public serving'
}

function ConvertFrom-RlPlayTrack {
    # One edits.tracks resource (RELEASE-LEDGER rule 12): the configuration of ONE track, kept as the API reports it -
    # the release name, the status, the version codes and the rollout fraction. It is a reading, not a publication:
    # no state, no serving, withdrawal or review claim comes out of it, whatever the status says.
    param([Parameter(Mandatory)]$Track, [Parameter(Mandatory)][string]$TrackName, [Parameter(Mandatory)][string]$AppId)
    $out = [System.Collections.Generic.List[object]]::new()
    foreach ($r in @(Get-RlProp $Track 'releases')) {
        if ($null -eq $r) { continue }
        $codes = [string[]]@(@(Get-RlProp $r 'versionCodes') | Where-Object { $_ } | ForEach-Object { [string]$_ })
        $name = [string](Get-RlProp $r 'name')
        if (-not $name -and $codes.Count -eq 0) { continue }
        $out.Add([pscustomobject]@{
                kind = 'play-track'; app = $AppId; track = $TrackName; release = $name; status = [string](Get-RlProp $r 'status')
                versionCodes = $codes; rollout = (Get-RlProp $r 'userFraction'); claim = 'none'
            })
    }
    return [object[]]$out.ToArray()
}

function ConvertFrom-RlPlayLifecycle {
    # An applications.tracks.releases.list body (up to 20 non-obsolete releases of ONE track): the lifecycle of each
    # release as Play reports it, scoped to that track and to the versionCode of its activeArtifacts. PUBLISHED is a
    # track lifecycle value - it includes a partial or halted rollout - so it never confirms public serving, and a
    # release's review state is no app-wide review or policy verdict. A body with no release gives nothing.
    param([AllowNull()]$Response, [Parameter(Mandatory)][string]$TrackName, [string]$AppId = '')
    $out = [System.Collections.Generic.List[object]]::new()
    foreach ($r in @(Get-RlProp $Response 'releases')) {
        if ($null -eq $r) { continue }
        $raw = [string](Get-RlProp $r 'releaseLifecycleState')
        $state = $raw -replace '^RELEASE_LIFECYCLE_STATE_', ''
        $codes = [string[]]@(@(Get-RlProp $r 'activeArtifacts') | Where-Object { $null -ne $_ } | ForEach-Object { [string](Get-RlProp $_ 'versionCode') } | Where-Object { $_ })
        $known = ($script:RlPlayLifecycle.Keys -ccontains $state)
        $track = [string](Get-RlProp $r 'track'); if (-not $track) { $track = $TrackName }
        $out.Add([pscustomobject]@{
                kind = 'play-lifecycle'; app = $AppId; track = $track; release = [string](Get-RlProp $r 'releaseName'); lifecycle = $state
                known = $known; meaning = $(if ($known) { [string]$script:RlPlayLifecycle[$state] } else { 'a value this reader does not know' })
                versionCodes = $codes; claim = 'none'
            })
    }
    return [object[]]$out.ToArray()
}

function New-RlPlayGap {
    # A read that returned nothing, or could not be made: reported as it is, never as a negative verdict.
    param([Parameter(Mandatory)][string]$Track, [Parameter(Mandatory)][string]$What, [Parameter(Mandatory)][string]$Reason)
    return [pscustomobject]@{ kind = 'play-gap'; track = $Track; what = $What; reason = $Reason; claim = 'none' }
}

function Format-RlProbeDiagnostic {
    # One output line for a probe reading; the claim it makes is always none (RELEASE-LEDGER rule 12).
    param([Parameter(Mandatory)][string]$Key, [Parameter(Mandatory)]$Diagnostic)
    $d = $Diagnostic
    $bits = [System.Collections.Generic.List[string]]::new()
    $tail = ''
    switch ([string](Get-RlProp $d 'kind')) {
        'play-track' {
            $bits.Add("track $($d.track)")
            if ($d.release) { $bits.Add("release '$($d.release)'") }
            $bits.Add("status $(if ($d.status) { $d.status } else { 'not reported' })")
            if (@($d.versionCodes).Count -gt 0) { $bits.Add("versionCodes $(@($d.versionCodes) -join ',')") }
            if ($null -ne $d.rollout -and "$($d.rollout)" -ne '') { $bits.Add("rollout $($d.rollout)") }
            $tail = 'track configuration only - no serving, withdrawal or review claim'
        }
        'play-lifecycle' {
            $bits.Add("track $($d.track)")
            if ($d.release) { $bits.Add("release '$($d.release)'") }
            $bits.Add("lifecycle $(if ($d.lifecycle) { $d.lifecycle } else { 'not reported' })$(if (-not $d.known) { ' (unrecognised)' })")
            if (@($d.versionCodes).Count -gt 0) { $bits.Add("versionCodes $(@($d.versionCodes) -join ',')") }
            $tail = "$($d.meaning); scoped to this track and these version codes, not public serving and not an app-wide review verdict"
        }
        'play-gap' {
            $bits.Add("track $($d.track)")
            $bits.Add("$($d.what): $($d.reason)")
            $tail = 'no verdict, positive or negative'
        }
        default { $bits.Add("reading $([string](Get-RlProp $d 'kind'))"); $tail = 'no publication claim' }
    }
    return ("reading     {0,-14} {1} - {2}" -f $Key, ($bits -join ', '), $tail)
}

function Invoke-RlProbePlay {
    param($Spec, [Parameter(Mandatory)][string]$RepoRoot)
    $appId = [string](Get-RlProp $Spec 'id')
    if (-not $appId) { return (New-RlProbeResult -Ok $false -Reason 'no applicationId (id) in channels.json') }
    if (-not (Test-RlApplicationId $appId)) { return (New-RlProbeResult -Ok $false -Reason "'$appId' in channels.json is not an application id") }
    $track = [string](Get-RlProp $Spec 'track'); if (-not $track) { $track = 'production' }
    $keyFile = [string]$env:SZA_PLAY_SERVICE_ACCOUNT_JSON
    if (-not $keyFile -or -not (Test-Path -LiteralPath $keyFile -PathType Leaf)) {
        return (New-RlProbeResult -Ok $false -Reason 'no Play Developer API credential (SZA_PLAY_SERVICE_ACCOUNT_JSON names no file)')
    }
    $base = "https://androidpublisher.googleapis.com/androidpublisher/v3/applications/$appId"
    try { $token = Get-RlGoogleAccessToken -KeyFile $keyFile -Scope 'https://www.googleapis.com/auth/androidpublisher' }
    catch { return (New-RlProbeResult -Ok $false -Reason 'the service account token request was refused') }
    $h = @{ Authorization = "Bearer $token" }
    # RELEASE-LEDGER rule 12: both reads are readings of one exact track. They are reported as diagnostics and no
    # event comes out of either, so a track that reads completed, published or halted never becomes live, withdrawn
    # or in review in the ledger.
    $diag = [System.Collections.Generic.List[object]]::new()
    $lifecycleOk = $false
    $trackOk = $false
    $failed = [System.Collections.Generic.List[string]]::new()
    # 1. The release lifecycle: a plain GET that opens no edit, so it cannot disturb another publisher.
    try {
        $lc = Invoke-RestMethod -Method Get -Uri "$base/tracks/$track/releases" -Headers $h -TimeoutSec 25
        $lifecycleOk = $true
        $rows = @(ConvertFrom-RlPlayLifecycle -Response $lc -TrackName $track -AppId $appId)
        foreach ($d in $rows) { $diag.Add($d) }
        if ($rows.Count -eq 0) { $diag.Add((New-RlPlayGap -Track $track -What 'release lifecycle' -Reason 'no release is listed for the track')) }
    } catch {
        $failed.Add("the Play API did not return the release lifecycle of track '$track'")
        $diag.Add((New-RlPlayGap -Track $track -What 'release lifecycle' -Reason 'the read did not answer; nothing is known from it'))
    }
    # 2. The track configuration: an edit is opened for the read and deleted again. Play keeps one edit per application,
    # so the application's lock (GOOGLE-PLAY rule 19) is held from before the edit opens until it is deleted. One try, no
    # wait: when a publisher or another probe holds it, no edit is opened and the gap says so.
    $lock = Enter-RlPlayAppLock -RepoRoot $RepoRoot -AppId $appId
    if (-not $lock.held) {
        $lockName = if ($lock.path) { ConvertTo-RlRepoPath -RepoRoot $RepoRoot -Path $lock.path } else { "of $appId" }
        $failed.Add("no edit was opened for $appId because its Play lock $lockName is not ours ($($lock.reason))")
        $diag.Add((New-RlPlayGap -Track $track -What 'track configuration' -Reason "no read edit was opened, so as not to delete another edit: the Play lock $lockName is not ours ($($lock.reason)); nothing is known from it"))
    } else {
        try {
            $edit = $null
            try { $edit = Invoke-RestMethod -Method Post -Uri "$base/edits" -Headers $h -ContentType 'application/json' -Body '{}' -TimeoutSec 25 }
            catch {
                $failed.Add("the Play API refused to open a read edit for $appId (no access, or the app does not exist)")
                $diag.Add((New-RlPlayGap -Track $track -What 'track configuration' -Reason 'no read edit could be opened; nothing is known from it'))
            }
            if ($null -ne $edit) {
                try {
                    $t = Invoke-RestMethod -Method Get -Uri "$base/edits/$($edit.id)/tracks/$track" -Headers $h -TimeoutSec 25
                    $trackOk = $true
                    $rows = @(ConvertFrom-RlPlayTrack -Track $t -TrackName $track -AppId $appId)
                    foreach ($d in $rows) { $diag.Add($d) }
                    if ($rows.Count -eq 0) { $diag.Add((New-RlPlayGap -Track $track -What 'track configuration' -Reason 'the track lists no release')) }
                } catch {
                    $failed.Add("the Play API did not return track '$track'")
                    $diag.Add((New-RlPlayGap -Track $track -What 'track configuration' -Reason 'the read did not answer; nothing is known from it'))
                } finally {
                    try { Invoke-RestMethod -Method Delete -Uri "$base/edits/$($edit.id)" -Headers $h -TimeoutSec 25 | Out-Null } catch { Write-Verbose 'the transient edit expires by itself' }
                }
            }
        } finally {
            Exit-RlPlayAppLock $lock
        }
    }
    if (-not $lifecycleOk -and -not $trackOk) { return (New-RlProbeResult -Ok $false -Reason ($failed -join '; ')) }
    return (New-RlProbeResult -Ok $true -Diagnostics $diag.ToArray())
}

# ---- Chrome Web Store, Edge Add-ons, VS Code Marketplace (public endpoints, live version only) ----

function ConvertFrom-RlChromeUpdate {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Xml, [Parameter(Mandatory)][string]$Id)
    $m = [regex]::Match($Xml, '<updatecheck\b[^>]*\bversion="([^"]+)"')
    if (-not $m.Success) {
        $s = [regex]::Match($Xml, '<updatecheck\b[^>]*\bstatus="([^"]+)"')
        return (New-RlProbeResult -Ok $false -Reason "the update service shows no version for $Id$(if ($s.Success) { " (status $($s.Groups[1].Value))" })")
    }
    return (New-RlProbeResult -Ok $true -Observed @(New-RlObservation -Version $m.Groups[1].Value -State 'live' -Url "https://chromewebstore.google.com/detail/$Id"))
}

function Invoke-RlProbeChrome {
    param($Spec)
    $id = [string](Get-RlProp $Spec 'id')
    if ($id -cnotmatch '^[a-p]{32}$') { return (New-RlProbeResult -Ok $false -Reason 'no 32-letter Chrome item id in channels.json') }
    $uri = 'https://clients2.google.com/service/update2/crx?response=updatecheck&acceptformat=crx3&prodversion=200.0&x=' + [uri]::EscapeDataString("id=$id&uc")
    try { $xml = Invoke-RlHttpGet $uri } catch { return (New-RlProbeResult -Ok $false -Reason "the Chrome update service did not answer: $($_.Exception.Message)") }
    return (ConvertFrom-RlChromeUpdate -Xml $xml -Id $id)
}

function ConvertFrom-RlEdgeDetails {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Json, [Parameter(Mandatory)][string]$Id)
    try { $d = ConvertFrom-RlJson $Json } catch { return (New-RlProbeResult -Ok $false -Reason 'the Edge product details do not parse') }
    $v = [string](Get-RlProp $d 'version')
    if (-not $v) { return (New-RlProbeResult -Ok $false -Reason "the Edge product details show no version for $Id") }
    return (New-RlProbeResult -Ok $true -Observed @(New-RlObservation -Version $v -State 'live' -Url "https://microsoftedge.microsoft.com/addons/detail/$Id"))
}

function Invoke-RlProbeEdge {
    param($Spec)
    $id = [string](Get-RlProp $Spec 'id')
    if ($id -cnotmatch '^[a-p]{32}$') { return (New-RlProbeResult -Ok $false -Reason 'no 32-letter Edge crx id in channels.json') }
    try { $json = Invoke-RlHttpGet "https://microsoftedge.microsoft.com/addons/getproductdetailsbycrxid/$id" }
    catch { return (New-RlProbeResult -Ok $false -Reason "the Edge product details did not answer: $($_.Exception.Message)") }
    return (ConvertFrom-RlEdgeDetails -Json $json -Id $id)
}

function ConvertFrom-RlVscodeQuery {
    # extensionquery with IncludeVersions: versions[] newest first; the newest is live, the rest were live before.
    param([Parameter(Mandatory)]$Response, [Parameter(Mandatory)][string]$Id, [switch]$All)
    $ext = @(@(Get-RlProp (@(Get-RlProp $Response 'results') | Select-Object -First 1) 'extensions') | Select-Object -First 1)
    if ($ext.Count -eq 0 -or $null -eq $ext[0]) { return (New-RlProbeResult -Ok $true -Reason "the Marketplace does not list $Id") }
    $versions = @(Get-RlProp $ext[0] 'versions' | Where-Object { $null -ne $_ })
    if (-not $All -and $versions.Count -gt 0) { $versions = @($versions[0]) }
    $out = foreach ($v in $versions) {
        # Invoke-RestMethod turns the ISO string into a DateTime; write it back as ISO, never in the console's culture.
        $lu = Get-RlProp $v 'lastUpdated'
        $at = if ($lu -is [datetime]) { ([DateTimeOffset]$lu).ToString("yyyy-MM-dd'T'HH:mm:sszzz", [Globalization.CultureInfo]::InvariantCulture) } else { [string]$lu }
        New-RlObservation -Version ([string](Get-RlProp $v 'version')) -State 'live' -At $at -Url "https://marketplace.visualstudio.com/items?itemName=$Id"
    }
    return (New-RlProbeResult -Ok $true -Observed @($out | Where-Object { $null -ne $_ }))
}

function Invoke-RlProbeVscode {
    param($Spec, [switch]$All)
    $id = [string](Get-RlProp $Spec 'id')
    if ($id -notmatch '^[\w-]+\.[\w-]+$') { return (New-RlProbeResult -Ok $false -Reason 'no publisher.name id in channels.json') }
    $body = @{ filters = @(@{ criteria = @(@{ filterType = 7; value = $id }); pageSize = 1 }); flags = 1 } | ConvertTo-Json -Depth 6 -Compress
    try {
        $resp = Invoke-RestMethod -Method Post -Uri 'https://marketplace.visualstudio.com/_apis/public/gallery/extensionquery' -ContentType 'application/json' `
            -Headers @{ Accept = 'application/json;api-version=3.0-preview.1' } -Body $body -TimeoutSec 25
    } catch { return (New-RlProbeResult -Ok $false -Reason "the Marketplace query failed: $($_.Exception.Message)") }
    return (ConvertFrom-RlVscodeQuery -Response $resp -Id $id -All:$All)
}

# ---- any public page: a forum post, a VR store listing, a catalogue entry ----

function ConvertFrom-RlPublicPage {
    # With a pattern, its first group is the version the page shows. Without one, the page confirms the first
    # candidate (a version the ledger already knows for this channel) whose text it contains. A page that shows
    # its version only after a script runs is unverified here, never guessed.
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text, [string]$Pattern, [AllowEmptyCollection()][string[]]$Candidates = @(), [string]$Url)
    if ($Pattern) {
        $m = [regex]::Match($Text, $Pattern)
        if (-not $m.Success -or $m.Groups.Count -lt 2 -or -not $m.Groups[1].Value) { return (New-RlProbeResult -Ok $false -Reason 'the pattern does not match the page as delivered') }
        return (New-RlProbeResult -Ok $true -Observed @(New-RlObservation -Version $m.Groups[1].Value -State 'live' -Url $Url))
    }
    foreach ($c in $Candidates) {
        if ($c -and $Text.Contains($c)) { return (New-RlProbeResult -Ok $true -Observed @(New-RlObservation -Version $c -State 'live' -Url $Url)) }
    }
    return (New-RlProbeResult -Ok $false -Reason 'no recorded version appears on the page as delivered (add a pattern to channels.json)')
}

function Invoke-RlProbeUrl {
    param($Spec, [AllowEmptyCollection()][string[]]$Candidates = @())
    $url = [string](Get-RlProp $Spec 'url')
    if ($url -notmatch '^https?://') { return (New-RlProbeResult -Ok $false -Reason 'no http(s) url in channels.json') }
    try { $text = Invoke-RlHttpGet $url } catch { return (New-RlProbeResult -Ok $false -Reason "the page did not answer: $($_.Exception.Message)") }
    return (ConvertFrom-RlPublicPage -Text $text -Pattern ([string](Get-RlProp $Spec 'pattern')) -Candidates $Candidates -Url $url)
}

# ---- dispatch ----

function Invoke-RlProbe {
    # $Channel is a Read-RlChannels entry; $Candidates are versions the ledger knows for it (the url probe's input).
    param([Parameter(Mandatory)]$Channel, [Parameter(Mandatory)][string]$RepoRoot, [AllowEmptyCollection()][string[]]$Candidates = @(), [switch]$All)
    $stubFile = [string]$env:SZA_RELEASES_PROBE_STUB
    if ($stubFile) {
        $stub = Get-RlProp (ConvertFrom-RlJson (Get-Content -LiteralPath $stubFile -Raw -Encoding utf8)) $Channel.key
        if ($null -eq $stub) { return (New-RlProbeResult -Ok $false -Reason 'no stub for this channel') }
        $obs = @(@(Get-RlProp $stub 'observed') | Where-Object { $null -ne $_ } | ForEach-Object {
                New-RlObservation -Version ([string]$_.version) -State ([string]$_.state) -At ([string](Get-RlProp $_ 'at')) -Ref ([string](Get-RlProp $_ 'ref')) `
                    -Url ([string](Get-RlProp $_ 'url')) -Note ([string](Get-RlProp $_ 'note')) -Track ([string](Get-RlProp $_ 'track')) -Rollout (Get-RlProp $_ 'rollout')
            })
        return (New-RlProbeResult -Ok ([bool](Get-RlProp $stub 'ok')) -Reason ([string](Get-RlProp $stub 'reason')) -Observed $obs `
                -Diagnostics @(@(Get-RlProp $stub 'diagnostics') | Where-Object { $null -ne $_ }))
    }
    $spec = $Channel.spec
    switch ($Channel.kind) {
        'github' { return (Invoke-RlProbeGithub -Spec $spec -RepoRoot $RepoRoot -Limit $(if ($All) { 100 } else { 5 })) }
        'winget' { return (Invoke-RlProbeWinget -Spec $spec -All:$All) }
        'msstore' { return (Invoke-RlProbeMsstore -Spec $spec) }
        'play' { return (Invoke-RlProbePlay -Spec $spec -RepoRoot $RepoRoot) }
        'chrome' { return (Invoke-RlProbeChrome -Spec $spec) }
        'edge' { return (Invoke-RlProbeEdge -Spec $spec) }
        'vscode' { return (Invoke-RlProbeVscode -Spec $spec -All:$All) }
        'url' { return (Invoke-RlProbeUrl -Spec $spec -Candidates $Candidates) }
        default {
            return (New-RlProbeResult -Ok $false -Reason "confirmed by hand: release-ledger confirm -Key $($Channel.key) -Version <v> -State live -Url <where>")
        }
    }
}
