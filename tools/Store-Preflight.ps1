[CmdletBinding()]
param(
    [string]$StoreId,
    [Parameter(Mandatory)][string]$ProductName,
    [string]$PackageVersion,
    [string]$Package,
    [string]$IdentityFile,
    [string[]]$ChannelSubmissionIds = @(),
    [string]$CredentialExpiry,
    [string]$ListingPath,
    [switch]$Json
)

# Read-only Microsoft Store submission preflight (S0050 part 1, extended by S0049).
#
# The only Store operation this script can ever issue is `msstore submission get <id>` - the
# allow-list inside Invoke-StoreRead refuses every other verb, so a write is blocked by the script
# itself and not only by policy. Exit codes: 0 the checks passed; 1 the channel refuses this run
# (proposal rules 23(a)-(f) and 25, UNVERIFIED until a first draft goes through): a pending
# submission, a channel-created draft that only the channel may touch, a mandatory update, a pricing
# object that is not Free, a candidate version not greater than every live package, a signed package,
# a missing or unusable identity file, a product with no live submission, or any state it cannot
# read; 2 the channel is unavailable (CLI missing or unconfigured, token refused, recorded credential
# expired) - the Store step is manual and a release continues. -Json prints the per-run evidence
# record without identifiers, arbitrary CLI fields or secrets. No draft, upload, commit or rollout is
# implemented here; committing a submission is the owner's act.

# Keep the executable boundary here: callers cannot pass an arbitrary CLI operation.
function Invoke-StoreRead {
    param([string[]]$Arguments)
    if ($Arguments.Count -ne 3 -or $Arguments[0] -cne 'submission' -or
        $Arguments[1] -cne 'get' -or $Arguments[2] -cnotmatch '^[A-Za-z0-9]{12}$') {
        throw 'Store operation is not allowed.'
    }
    $global:LASTEXITCODE = 0
    $output = & msstore @Arguments 2>&1
    return @{ Text = ($output -join "`n"); ExitCode = $LASTEXITCODE }
}

$script:LastEvidence = $null
function Set-StoreEvidence([hashtable]$Patch) {
    if ($null -eq $script:LastEvidence) { $script:LastEvidence = @{} }
    foreach ($key in $Patch.Keys) { $script:LastEvidence[$key] = $Patch[$key] }
}

function Get-SubmissionProp([object]$Object, [string]$Name) {
    # Case-insensitive read that stays null when the resource lacks the field.
    if ($null -eq $Object) { return $null }
    $p = $Object.PSObject.Properties[$Name]
    if ($null -eq $p) { return $null }
    return $p.Value
}

function Test-SignedStorePackage([string]$PackagePath) {
    # Rule 23(c): the packed archive must not carry a signature - the Store re-signs at certification.
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($PackagePath)
    try {
        foreach ($entry in $zip.Entries) {
            if ($entry.FullName -ieq 'AppxSignature.p7x') { return $true }
        }
    } finally {
        $zip.Dispose()
    }
    return $false
}

function Invoke-StorePreflight {
    param([string]$Id, [string]$Product, [string]$Candidate,
          [string]$PackagePath, [string]$IdentityFile, [string[]]$ChannelSubmissionIds = @(),
          [string]$CredentialExpiry, [string]$ListingPath)
    $checkedAt = (Get-Date).ToString('o')
    $script:LastEvidence = @{ checkedAt = $checkedAt; productName = $Product; candidateVersion = $Candidate; listingPath = $ListingPath }
    if ($Product -cnotmatch '^[A-Za-z][A-Za-z0-9 ._-]{0,79}$') {
        Set-StoreEvidence @{ mode = 'refused'; refusal = 'invalid-input' }
        Write-Output 'Store preflight: invalid product name.'
        return 1
    }
    if ($CredentialExpiry) {
        $expiry = [datetime]::MinValue
        if (-not [datetime]::TryParse($CredentialExpiry, [ref]$expiry)) {
            Set-StoreEvidence @{ mode = 'refused'; refusal = 'credential-expiry'; detail = "the recorded credential expiry does not parse as a date: $CredentialExpiry" }
            Write-Output "$($Product): the recorded credential expiry does not parse as a date."
            return 1
        }
        if ((Get-Date).Date -gt $expiry.Date) {
            Set-StoreEvidence @{ mode = 'manual'; storeId = $Id; manualReason = "the channel credential expired $($expiry.ToString('yyyy-MM-dd'))" }
            Write-Output "$($Product): Store step is manual (channel credential expired $($expiry.ToString('yyyy-MM-dd')); rotation is the owner's act)."
            return 2
        }
    }
    if ($IdentityFile) {
        if (-not (Test-Path -LiteralPath $IdentityFile)) {
            Set-StoreEvidence @{ mode = 'refused'; refusal = 'identity-file'; detail = "the product's identity file is missing: $IdentityFile" }
            Write-Output "$($Product): the product's identity file is missing; the channel reads the Store ID from it (rule 19)."
            return 1
        }
        try { $identity = Get-Content -LiteralPath $IdentityFile -Raw | ConvertFrom-Json -ErrorAction Stop } catch {
            Set-StoreEvidence @{ mode = 'refused'; refusal = 'identity-file'; detail = 'the identity file does not parse' }
            Write-Output "$($Product): the identity file does not parse."
            return 1
        }
        $fileId = Get-SubmissionProp $identity 'StoreId'
        if (-not $fileId) {
            Set-StoreEvidence @{ mode = 'refused'; refusal = 'identity-file'; detail = 'the identity file carries no StoreId' }
            Write-Output "$($Product): the identity file carries no StoreId."
            return 1
        }
        if ($Id -and $Id -cne $fileId) {
            Set-StoreEvidence @{ mode = 'refused'; refusal = 'identity-file'; detail = 'the given Store ID disagrees with the identity file' }
            Write-Output "$($Product): the given Store ID disagrees with the identity file."
            return 1
        }
        $Id = $fileId
    }
    if ($Id -cnotmatch '^[A-Za-z0-9]{12}$' -or $Product -cnotmatch '^[A-Za-z][A-Za-z0-9 ._-]{0,79}$') {
        Set-StoreEvidence @{ mode = 'refused'; refusal = 'invalid-input'; detail = 'invalid product or Store ID' }
        Write-Output 'Store preflight: invalid product or Store ID.'
        return 1
    }
    Set-StoreEvidence @{ storeId = $Id }
    $candidateVersion = $null
    if ($Candidate) {
        $parsed = $null
        if ($Candidate -notmatch '^\d+\.\d+\.\d+\.\d+$' -or
            -not [version]::TryParse($Candidate, [ref]$parsed) -or
            @($Candidate.Split('.') | Where-Object { [long]$_ -gt 65535 }).Count -gt 0) {
            Set-StoreEvidence @{ mode = 'refused'; refusal = 'invalid-input'; detail = "invalid package version: $Candidate" }
            Write-Output "$($Product): invalid package version."
            return 1
        }
        $candidateVersion = $parsed
    }
    if ($PackagePath) {
        if (-not (Test-Path -LiteralPath $PackagePath)) {
            Set-StoreEvidence @{ mode = 'refused'; refusal = 'signed-package'; detail = "the package to stage is missing: $PackagePath" }
            Write-Output "$($Product): the package to stage is missing."
            return 1
        }
        try { $signed = Test-SignedStorePackage $PackagePath } catch {
            Set-StoreEvidence @{ mode = 'refused'; refusal = 'invalid-package' }
            Write-Output "$($Product): cannot read the package."
            return 1
        }
        if ($signed) {
            Set-StoreEvidence @{ mode = 'refused'; refusal = 'signed-package'; detail = 'the packed archive holds an AppxSignature.p7x entry' }
            Write-Output "$($Product): the package is signed (AppxSignature.p7x); the Store re-signs at certification - never upload a signed package."
            return 1
        }
    }
    if (-not (Get-Command msstore -ErrorAction SilentlyContinue)) {
        Set-StoreEvidence @{ mode = 'manual'; manualReason = 'the Store Developer CLI (msstore) is not on PATH' }
        Write-Output "$($Product): Store step is manual (channel unavailable)."
        return 2
    }
    try { $result = Invoke-StoreRead @('submission', 'get', $Id) }
    catch {
        Set-StoreEvidence @{ mode = 'manual'; manualReason = 'the channel call failed' }
        Write-Output "$($Product): Store step is manual (channel unavailable)."
        return 2
    }
    $raw = $result.Text
    if ($raw -match '(?i)(no|could not find|not found|does not have).{0,100}(published submission|live submission)' -and
        $raw -notmatch '(?i)found the last published submission') {
        Set-StoreEvidence @{ mode = 'refused'; refusal = 'no-live-submission'; detail = 'the product has no live submission; the first publication stays in the console' }
        Write-Output "$($Product): no live submission; use Partner Center for the first publication."
        return 1
    }
    if ($result.ExitCode -ne 0 -or ($raw -notmatch '{' -and
        $raw -match '(?i)(sellerid is not set|not configured|unauthorized|forbidden|authentication|token|credential|\b401\b|\b403\b)')) {
        Set-StoreEvidence @{ mode = 'manual'; manualReason = 'the channel call failed or the CLI is unconfigured' }
        Write-Output "$($Product): Store step is manual (channel unavailable)."
        return 2
    }
    $start = $raw.IndexOf('{')
    $end = $raw.LastIndexOf('}')
    if ($start -lt 0 -or $end -lt $start) {
        Set-StoreEvidence @{ mode = 'refused'; refusal = 'state-unreadable'; detail = 'no submission resource in the response' }
        Write-Output "$($Product): cannot determine submission state."
        return 1
    }
    try {
        # Trap 5 (proposal F17): the CLI wraps its JSON at console width; every real break inside a
        # value is the escaped \r\n, so removing the raw CR and LF loses nothing.
        $submission = ($raw.Substring($start, $end - $start + 1) -replace '[\r\n]', '') | ConvertFrom-Json -ErrorAction Stop
    } catch {
        Set-StoreEvidence @{ mode = 'refused'; refusal = 'state-unreadable'; detail = 'the submission resource did not parse after de-wrapping' }
        Write-Output "$($Product): cannot parse submission state."
        return 1
    }
    $status = [string](Get-SubmissionProp $submission 'Status')
    $submissionId = [string](Get-SubmissionProp $submission 'Id')
    $submissionName = [string](Get-SubmissionProp $submission 'FriendlyName')
    if (-not $status -or $status -isnot [string]) {
        Set-StoreEvidence @{ mode = 'refused'; refusal = 'state-unreadable'; detail = 'the submission resource carries no Status' }
        Write-Output "$($Product): submission status is missing."
        return 1
    }
    Set-StoreEvidence @{ submissionId = $submissionId; submissionName = $submissionName; status = $status; statusValues = @(@{ status = $status; at = $checkedAt }) }
    if ($status -cne 'Published') {
        if ($submissionId -and $ChannelSubmissionIds -ccontains $submissionId) {
            Set-StoreEvidence @{ mode = 'refused'; refusal = 'mixed-edit'; detail = "submission $submissionId was created by this channel; only the channel may change it until the owner commits or deletes it" }
            Write-Output "$($Product): pending or non-published submission; stop."
            Write-Output "$($Product): this submission was created by the channel; stop and leave it untouched."
            return 1
        }
        Set-StoreEvidence @{ mode = 'refused'; refusal = 'pending-submission'; detail = "status $status" }
        Write-Output "$($Product): pending or non-published submission; stop."
        return 1
    }
    if ($raw.Substring(0, $start) -notmatch '(?i)(could not find|no)\s+(a\s+)?pending submission.{0,100}found the last published submission') {
        Set-StoreEvidence @{ mode = 'refused'; refusal = 'state-unreadable'; detail = 'the Status and the CLI message disagree' }
        Write-Output "$($Product): conflicting submission state; stop."
        return 1
    }
    Write-Output "$($Product): last published submission (Published); no pending submission."
    $pricing = Get-SubmissionProp (Get-SubmissionProp $submission 'Pricing') 'PriceId'
    Set-StoreEvidence @{ pricing = [string]$pricing }
    if ($pricing -cne 'Free') {
        Set-StoreEvidence @{ mode = 'refused'; refusal = 'pricing'; detail = "the pricing object is not Free (observed: '$pricing'); the machine path never writes pricing" }
        Write-Output "$($Product): price is not confirmed Free."
        return 1
    }
    foreach ($packageEntry in @($submission.ApplicationPackages)) {
        if ($null -eq $packageEntry) { continue }
        if ((Get-SubmissionProp $packageEntry 'MandatoryUpdate') -eq $true) {
            Set-StoreEvidence @{ mode = 'refused'; refusal = 'mandatory-update'; detail = 'a live package carries a mandatory update; the machine path does not support it' }
            Write-Output "$($Product): a package carries a mandatory update; the machine path does not support it."
            return 1
        }
    }
    if ($candidateVersion) {
        $packages = @($submission.ApplicationPackages)
        if ($packages.Count -eq 0 -or $null -eq $packages[0]) {
            Set-StoreEvidence @{ mode = 'refused'; refusal = 'state-unreadable'; detail = 'no live package version could be read' }
            Write-Output "$($Product): live package version is missing."
            return 1
        }
        foreach ($package in $packages) {
            $live = $null
            $versionText = [string]$package.Version
            if ($versionText -notmatch '^\d+\.\d+\.\d+\.\d+$' -or
                -not [version]::TryParse($versionText, [ref]$live) -or
                @($versionText.Split('.') | Where-Object { [long]$_ -gt 65535 }).Count -gt 0) {
                Set-StoreEvidence @{ mode = 'refused'; refusal = 'state-unreadable'; detail = "the live package version is invalid or missing: $versionText" }
                Write-Output "$($Product): live package version is invalid or missing."
                return 1
            }
            if ($candidateVersion -le $live) {
                Set-StoreEvidence @{ mode = 'refused'; refusal = 'version-not-greater'; detail = "candidate $Candidate is not greater than the live package $versionText" }
                Write-Output "$($Product): package version is not greater than every live package version."
                return 1
            }
            Set-StoreEvidence @{ liveVersion = $versionText }
        }
    }
    Set-StoreEvidence @{ mode = 'ready' }
    Write-Output "$($Product): Store preflight passed."
    return 0
}

if ($MyInvocation.InvocationName -ne '.') {
    $messages = @(Invoke-StorePreflight -Id $StoreId -Product $ProductName -Candidate $PackageVersion `
        -PackagePath $Package -IdentityFile $IdentityFile -ChannelSubmissionIds $ChannelSubmissionIds `
        -CredentialExpiry $CredentialExpiry -ListingPath $ListingPath)
    $code = $messages[-1]
    if ($Json) {
        # Only fixed, non-identifying values may cross the output boundary. CLI fields and caller
        # input can contain arbitrary text, so do not serialize the internal evidence wholesale.
        $evidence = [ordered]@{ mode = $script:LastEvidence.mode; checkedAt = $script:LastEvidence.checkedAt }
        if ($script:LastEvidence.refusal) { $evidence.refusal = $script:LastEvidence.refusal }
        if ($script:LastEvidence.status) {
            $evidence.submission = if ($script:LastEvidence.status -ceq 'Published') { 'published' } else { 'non-published' }
        }
        if ($script:LastEvidence.pricing) {
            $evidence.pricing = if ($script:LastEvidence.pricing -ceq 'Free') { 'Free' } else { 'other' }
        }
        ConvertTo-Json $evidence -Depth 5 -Compress | Write-Output
    } else {
        $messages | Select-Object -SkipLast 1 | Write-Output
    }
    exit $code
}
