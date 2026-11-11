#requires -Version 7.0
# S0049_store-submission-channel: the Store machine channel's refusals, fallback, evidence and
# credential hygiene, against a stubbed store (no network, no credential).
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$preflight = Join-Path $PSScriptRoot '..\Store-Preflight.ps1'
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('sza-store-channel-' + [guid]::NewGuid().ToString('N'))
$storeCalls = Join-Path $scratch 'store-calls.txt'
$script:reply = ''
$script:exitCode = 0
$script:cliPresent = $true
$script:calls = 0
function Assert-Channel($Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
try {
    $null = [IO.Directory]::CreateDirectory($scratch)
    . $preflight -StoreId 'ABCDEFGHIJKL' -ProductName 'Sample'
    function Get-Command {
        param([string]$Name, $ErrorAction)
        if ($Name -eq 'msstore') { if ($script:cliPresent) { return $true }; return $null }
        Microsoft.PowerShell.Core\Get-Command -Name $Name -ErrorAction $ErrorAction
    }
    function global:msstore {
        $script:calls++
        if (($args -join ' ') -cne 'submission get ABCDEFGHIJKL') { throw 'Unexpected operation' }
        [IO.File]::AppendAllText($storeCalls, ($args -join ' ') + "`n")
        $global:LASTEXITCODE = $script:exitCode
        $script:reply
    }
    # Builds a submission resource the way the CLI prints it: a leading status line and the JSON
    # console-wrapped at 80 columns, with an escaped CRLF inside a value and account identifiers that
    # must never reach any output.
    function Get-StoreReply {
        param([string]$Status = 'Published', [string]$Price = 'Free', [string]$Version = '1.0.0.0',
              [switch]$WithId, [switch]$Mandatory, [switch]$NoPrice, [string]$Raw = '', [int]$CliExit = 0)
        if ($Raw) { $script:exitCode = $CliExit; return $Raw }
        $obj = [ordered]@{ Status = $Status }
        if ($WithId) { $obj['Id'] = '11111111-2222-3333-4444-555555555555'; $obj['FriendlyName'] = "Submission 6`r`nsecond line" }
        $obj['sellerId'] = 'SELLER-SHOULD-NOT-ECHO-000'
        $obj['tenantId'] = 'TENANT-SHOULD-NOT-ECHO-000'
        $obj['clientId'] = 'CLIENT-SHOULD-NOT-ECHO-000'
        if (-not $NoPrice) { $obj['Pricing'] = @{ PriceId = $Price } }
        $pkg = @{ Version = $Version }
        if ($Mandatory) { $pkg['MandatoryUpdate'] = $true }
        $obj['ApplicationPackages'] = @($pkg)
        $json = ConvertTo-Json ([pscustomobject]$obj) -Depth 5 -Compress
        $wrapped = for ($i = 0; $i -lt $json.Length; $i += 80) { $json.Substring($i, [Math]::Min(80, $json.Length - $i)) }
        $script:exitCode = $CliExit
        return (@('Could not find a Pending Submission, but found the Last Published Submission') + @($wrapped)) -join "`n"
    }
    function Invoke-Case([string]$Name, [int]$Expected, [string]$Match, [string]$Candidate = '2.0.0.0', [hashtable]$Extra = @{}) {
        $answer = @(Invoke-StorePreflight 'ABCDEFGHIJKL' 'Sample' $Candidate @Extra)
        $code = $answer[-1]
        Assert-Channel ($code -eq $Expected) "$Name exited $code, expected $Expected : $($answer -join ' | ')"
        Assert-Channel (($answer -join ' ') -match $Match) "$Name message missing '$Match': $($answer -join ' | ')"
        return $answer
    }

    # --- refusals (a)-(f) plus rule 25, all non-zero (their exit code is 1), none manual ---
    $script:reply = Get-StoreReply -Status 'PendingCommit' -WithId
    Invoke-Case 'pending submission (a)' 1 'pending or non-published submission' | Out-Null
    Assert-Channel ($script:LastEvidence.refusal -ceq 'pending-submission') 'pending refusal not recorded'
    $answer = Invoke-Case 'channel-created draft (f)' 1 'created by the channel' '2.0.0.0' @{ ChannelSubmissionIds = @('11111111-2222-3333-4444-555555555555') }
    Assert-Channel ($script:LastEvidence.refusal -ceq 'mixed-edit') 'mixed-edit refusal not recorded'
    Assert-Channel (($answer -join ' ') -notmatch 'manual') 'mixed-edit reported as manual'
    Assert-Channel (($answer -join ' ') -notmatch '11111111-2222-3333-4444-555555555555') 'submission identifier leaked in the refusal'
    $script:reply = Get-StoreReply -Status 'Published' -Mandatory
    Invoke-Case 'mandatory update (e)' 1 'mandatory update' | Out-Null
    Assert-Channel ($script:LastEvidence.refusal -ceq 'mandatory-update') 'mandatory-update refusal not recorded'
    $script:reply = Get-StoreReply -Price 'Base'
    Invoke-Case 'paid pricing (d)' 1 'not confirmed Free' | Out-Null
    $script:reply = Get-StoreReply -Price ''
    Invoke-Case 'empty pricing (d)' 1 'not confirmed Free' | Out-Null
    $script:reply = Get-StoreReply -NoPrice
    Invoke-Case 'missing pricing (d)' 1 'not confirmed Free' | Out-Null
    $script:reply = Get-StoreReply
    Invoke-Case 'equal version (b)' 1 'not greater' '1.0.0.0' | Out-Null
    Invoke-Case 'older version (b)' 1 'not greater' '0.9.0.0' | Out-Null
    Assert-Channel ($script:LastEvidence.refusal -ceq 'version-not-greater') 'version refusal not recorded'
    $signed = Join-Path $scratch 'signed.msix'
    Add-Type -AssemblyName System.IO.Compression
    $fs = [IO.File]::Create($signed)
    $archive = New-Object IO.Compression.ZipArchive($fs, [IO.Compression.ZipArchiveMode]::Create)
    $null = $archive.CreateEntry('AppxSignature.p7x')
    $archive.Dispose(); $fs.Dispose()
    Invoke-Case 'signed package (c)' 1 'signed' '2.0.0.0' @{ PackagePath = $signed } | Out-Null
    Assert-Channel ($script:LastEvidence.refusal -ceq 'signed-package') 'signed-package refusal not recorded'
    Invoke-Case 'missing package (c)' 1 'package to stage is missing' '2.0.0.0' @{ PackagePath = (Join-Path $scratch 'no-such.msix') } | Out-Null
    $broken = Join-Path $scratch 'broken.msix'
    [IO.File]::WriteAllText($broken, 'not an archive')
    Invoke-Case 'unreadable package' 1 'cannot read the package' '2.0.0.0' @{ PackagePath = $broken } | Out-Null
    $script:reply = 'Could not find a pending submission or published submission'
    Invoke-Case 'no live submission (rule 25)' 1 'no live submission' | Out-Null
    $plain = Join-Path $scratch 'plain.msix'
    $fs2 = [IO.File]::Create($plain)
    $archive2 = New-Object IO.Compression.ZipArchive($fs2, [IO.Compression.ZipArchiveMode]::Create)
    $null = $archive2.CreateEntry('AppxManifest.xml')
    $archive2.Dispose(); $fs2.Dispose()
    $script:reply = Get-StoreReply
    Invoke-Case 'clean package passes (c)' 0 'preflight passed' '3.0.0.0' @{ PackagePath = $plain } | Out-Null

    # --- the manual fallback: one line, distinct code, the release exit code unchanged ---
    $script:reply = 'SellerId is not set'
    $before = $script:calls
    Invoke-Case 'unconfigured channel' 2 'manual' | Out-Null
    Assert-Channel ($script:calls -eq $before + 1) 'the unconfigured fallback did not probe the CLI exactly once'
    $unconfigured = @(@(Invoke-StorePreflight 'ABCDEFGHIJKL' 'Sample' '2.0.0.0') | Where-Object { $_ -is [string] })
    Assert-Channel ($unconfigured.Count -eq 1) 'unconfigured fallback printed more than one line'
    $script:reply = 'token request refused (401)'
    Invoke-Case 'token refused' 2 'manual' | Out-Null
    $script:cliPresent = $false
    Invoke-Case 'CLI missing' 2 'manual' | Out-Null
    $script:cliPresent = $true
    $before = $script:calls
    $expired = Invoke-StorePreflight 'ABCDEFGHIJKL' 'Sample' '2.0.0.0' -CredentialExpiry '2026-01-01'
    Assert-Channel ($expired[-1] -eq 2 -and ($expired -join ' ') -match 'manual.*expired') 'expired credential did not fall back to the manual path'
    Assert-Channel ($script:calls -eq $before) 'the expired-credential fallback talked to the CLI'
    Invoke-Case 'unparseable expiry' 1 'does not parse as a date' '2.0.0.0' @{ CredentialExpiry = 'not-a-date' } | Out-Null
    # The release convention: exit 0 and the manual exit 2 both continue; only a refusal (1) stops
    # the Store leg - so the fallback never changes the release's exit code.
    $releaseExit = 0
    $code = $expired[-1]
    if ($code -ne 0 -and $code -ne 2) { $releaseExit = $code }
    Assert-Channel ($releaseExit -eq 0) 'the manual fallback changed the release exit code'

    # --- the identity file (rule 19): the Store ID comes from the file the product pins ---
    $identityFile = Join-Path $scratch 'identity.json'
    [IO.File]::WriteAllText($identityFile, '{"IdentityName":"SZA.Sample","StoreId":"ABCDEFGHIJKL","PackageFamilyName":"SZA.Sample_hash"}')
    $script:reply = Get-StoreReply
    $fromFile = @(Invoke-StorePreflight -Id '' -Product 'Sample' -Candidate '2.0.0.0' -IdentityFile $identityFile)
    Assert-Channel ($fromFile[-1] -eq 0 -and ($fromFile -join ' ') -match 'preflight passed') "identity file did not resolve the Store ID: $($fromFile -join ' | ')"
    Assert-Channel ($script:LastEvidence.storeId -ceq 'ABCDEFGHIJKL') 'identity-file Store ID not used'
    [IO.File]::WriteAllText((Join-Path $scratch 'nostore.json'), '{"IdentityName":"SZA.Sample"}')
    $noStore = @(Invoke-StorePreflight -Id '' -Product 'Sample' -IdentityFile (Join-Path $scratch 'nostore.json'))
    Assert-Channel ($noStore[-1] -eq 1 -and ($noStore -join ' ') -match 'carries no StoreId') "an identity file without a StoreId did not refuse: $($noStore -join ' | ')"
    $gone = @(Invoke-StorePreflight -Id '' -Product 'Sample' -IdentityFile (Join-Path $scratch 'gone.json'))
    Assert-Channel ($gone[-1] -eq 1 -and ($gone -join ' ') -match 'identity file is missing') "a missing identity file did not refuse: $($gone -join ' | ')"

    # --- the evidence record (rule 26 shape): the required keys, never an account identifier ---
    $script:reply = Get-StoreReply -WithId
    $null = Invoke-StorePreflight 'ABCDEFGHIJKL' 'Sample' '2.0.0.0' -ListingPath 'store/listingData.csv'
    $ev = $script:LastEvidence
    foreach ($key in @('mode', 'storeId', 'checkedAt', 'status', 'statusValues', 'submissionId', 'pricing', 'candidateVersion', 'listingPath')) {
        Assert-Channel ($null -ne $ev[$key]) "evidence lacks $key"
    }
    Assert-Channel ($ev.mode -ceq 'ready' -and $ev.status -ceq 'Published' -and $ev.pricing -ceq 'Free') 'evidence state wrong'
    Assert-Channel ($ev.statusValues[0].status -ceq 'Published' -and $ev.statusValues[0].at) 'polled status values missing'
    $flat = ConvertTo-Json $ev -Depth 5 -Compress
    Assert-Channel ($flat -notmatch 'SHOULD-NOT-ECHO') 'an account identifier reached the evidence record'

    # --- process-level: real exit codes, single-line manual output, -Json, writes nothing.
    # The stub is an msstore.cmd on PATH so the preflight runs as a real process with -File, where
    # the script's exit code reaches the process (an invoked script's `exit` does not). ---
    $scriptPath = (Resolve-Path $preflight).Path
    $stubDir = Join-Path $scratch 'stub'
    $null = [IO.Directory]::CreateDirectory($stubDir)
    @'
@echo off
echo submission get %3 >> "%SZA_TEST_STORE_CALLS%"
type "%SZA_TEST_STORE_REPLY%"
exit /b %SZA_TEST_STORE_EXIT%
'@ | Set-Content -LiteralPath (Join-Path $stubDir 'msstore.cmd')
    $savedPath = $env:PATH
    function Invoke-Child([string]$Arguments, [string]$WorkingDirectory) {
        $replyFile = Join-Path $scratch ('reply-' + [guid]::NewGuid().ToString('N') + '.txt')
        [IO.File]::WriteAllText($replyFile, $script:reply)
        $env:SZA_TEST_STORE_REPLY = $replyFile
        $env:SZA_TEST_STORE_EXIT = "$($script:exitCode)"
        $env:SZA_TEST_STORE_CALLS = $storeCalls
        $env:PATH = "$stubDir;$savedPath"
        Push-Location $WorkingDirectory
        try {
            $sw = [Diagnostics.Stopwatch]::StartNew()
            $output = & pwsh -NoProfile -File $scriptPath ($Arguments -split ' ') 2>&1
            $sw.Stop()
            Assert-Channel ($sw.Elapsed.TotalSeconds -lt 5) "$Arguments ran $($sw.Elapsed.TotalSeconds)s"
            return ,@($output)
        } finally {
            Pop-Location
            $env:PATH = $savedPath
        }
    }
    $script:reply = Get-StoreReply -Status 'PendingCommit'
    $script:exitCode = 0
    $emptyDir = Join-Path $scratch ('cwd-' + [guid]::NewGuid().ToString('N'))
    $null = [IO.Directory]::CreateDirectory($emptyDir)
    $null = Invoke-Child '-StoreId ABCDEFGHIJKL -ProductName Sample' $emptyDir
    Assert-Channel ($LASTEXITCODE -eq 1) "a pending submission exited $LASTEXITCODE, expected 1"
    Assert-Channel (@([IO.Directory]::GetFileSystemEntries($emptyDir)).Count -eq 0) 'a refused run wrote into the working directory'
    $script:reply = 'SellerId is not set'
    $script:exitCode = 1
    $manual = Invoke-Child '-StoreId ABCDEFGHIJKL -ProductName Sample' $scratch
    Assert-Channel ($LASTEXITCODE -eq 2) "the manual fallback exited $LASTEXITCODE, expected 2"
    $manualLines = @($manual | Where-Object { "$_" })
    Assert-Channel ($manualLines.Count -eq 1 -and ($manualLines -join ' ') -match 'manual') "the manual fallback printed $($manualLines.Count) lines"
    $releaseExit = 0
    if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 2) { $releaseExit = $LASTEXITCODE }
    Assert-Channel ($releaseExit -eq 0) 'the manual fallback exit reached the release exit code'
    $script:reply = Get-StoreReply -WithId
    $script:exitCode = 0
    $jsonRun = Invoke-Child '-StoreId ABCDEFGHIJKL -ProductName Sample -PackageVersion 2.0.0.0 -ListingPath store/listingData.csv -Json' $scratch
    $jsonLines = @($jsonRun | Where-Object { "$_" })
    Assert-Channel ($LASTEXITCODE -eq 0 -and $jsonLines.Count -eq 1) "the -Json run printed $($jsonLines.Count) lines with exit $LASTEXITCODE"
    $evidence = $jsonLines[0] | ConvertFrom-Json
    Assert-Channel ($evidence.mode -ceq 'ready' -and $evidence.submission -ceq 'published' -and $evidence.pricing -ceq 'Free') 'the process evidence record is wrong'
    Assert-Channel (($jsonLines -join ' ') -notmatch 'SHOULD-NOT-ECHO|ABCDEFGHIJKL|11111111-2222-3333-4444-555555555555|listingData') 'an identifier or caller-supplied path reached the -Json output'
    $cliCalls = @(Get-Content $storeCalls -ErrorAction SilentlyContinue)
    Assert-Channel ($cliCalls.Count -ge 1 -and ($cliCalls -join "`n") -match 'submission get ABCDEFGHIJKL') 'the stub saw no read-only submission get call'

    # --- credential hygiene: no script runs a write verb or echoes configuration; no credential
    # value shape anywhere in the repo or PLAN/ ---
    $scripts = @(Get-ChildItem tools, hooks -Recurse -Filter '*.ps1' | Where-Object { $_.FullName -notmatch '\\(obj|bin|node_modules)\\' })
    foreach ($script in ($scripts | Where-Object { $_.Name -ne 'store-channel.tests.ps1' })) {
        $text = Get-Content $script.FullName -Raw
        Assert-Channel ($text -notmatch '(?im)^\s*&?\s*msstore\s+(info|reconfigure|publish|init|package|settings|delete|rollout|update)\b') "a write-verb msstore invocation sits in $($script.FullName)"
        Assert-Channel ($text -notmatch '(?i)msstore\s+info\b') "the info verb appears in $($script.FullName)"
    }
    $scanPaths = @(Get-ChildItem PLAN -Recurse -Filter '*.md') + $scripts + @(Get-ChildItem skills -Recurse -Filter '*.md')
    $shapes = @(
        '--(clientSecret|tenantId|sellerId|clientId)[= ][A-Za-z0-9+/=_-]{6,}',
        '(?i)(clientsecret|secret|credential)\s*[=:]\s*[''"][A-Za-z0-9+/=_-]{16,}[''"]',
        '[''"][A-Za-z0-9+/]{40,}={1,2}[''"]'
    )
    foreach ($shape in $shapes) {
        $hits = @($scanPaths | Where-Object { (Get-Content $_.FullName -Raw) -match $shape })
        if ($hits.Count -gt 0) {
            $details = foreach ($h in @($hits)) {
                $line = (Get-Content $h.FullName | Select-String -Pattern $shape | Select-Object -First 1)
                "$($h.FullName): $($line.Line.Trim().Substring(0, [Math]::Min(120, $line.Line.Trim().Length)))"
            }
            throw "credential-value shape '$shape' found in: $($details -join ' | ')"
        }
    }
    Write-Host 'PASS: refusals (a)-(f) and rule 25, manual fallback, identity file, evidence record, process exit codes, hygiene'
} finally {
    Remove-Item function:global:msstore -ErrorAction SilentlyContinue
    if ([IO.Directory]::Exists($scratch)) { [IO.Directory]::Delete($scratch, $true) }
}
