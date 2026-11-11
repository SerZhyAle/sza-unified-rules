$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/../Store-Preflight.ps1" -StoreId 'ABCDEFGHIJKL' -ProductName 'Sample'
$script:reply = ''
$script:exitCode = 0
$script:calls = 0
$script:cliPresent = $true
function Get-Command {
    param([string]$Name, $ErrorAction)
    if ($Name -eq 'msstore') { if ($script:cliPresent) { return $true }; return $null }
    Microsoft.PowerShell.Core\Get-Command -Name $Name -ErrorAction $ErrorAction
}
function global:msstore {
    $script:calls++
    if (($args -join ' ') -cne 'submission get ABCDEFGHIJKL') { throw 'Unexpected operation' }
    $global:LASTEXITCODE = $script:exitCode
    $script:reply
}
function Check([string]$Name, [int]$Expected, [string]$Message, [string]$Candidate = '2.0.0.0') {
    $answer = @(Invoke-StorePreflight 'ABCDEFGHIJKL' 'Sample' $Candidate)
    if ($answer[-1] -ne $Expected -or ($answer -join ' ') -notmatch $Message) { throw "$Name failed: $answer" }
}
function Make-Reply([string]$Status = 'Published', [string]$Price = 'Free', [string]$Version = '1.0.0.0') {
    return "Could not find a Pending Submission, but found the Last Published Submission`n{`"Status`":`"$Status`",`"Pricing`":{`"PriceId`":`"$Price`"},`"ApplicationPackages`": [{`"Version`":`"$Version`"}]}"
}
try {
    $script:reply = Make-Reply
    Check 'published' 0 'last published.*passed'
    Check 'optional version' 0 'passed' ''
    $script:reply = (Make-Reply).Replace('{"Version":"1.0.0.0"}', '{"Version":"1.0.0.0"},{"Version":"3.0.0.0"}')
    Check 'multiple packages' 1 'not greater'
    $script:reply = Make-Reply
    Check 'equal' 1 'not greater' '1.0.0.0'
    Check 'older' 1 'not greater' '0.9.0.0'
    Check 'bad version' 1 'invalid package version' '2.0'
    $script:reply = Make-Reply -Status 'PendingCommit'
    Check 'pending' 1 'pending or non-published submission'
    $script:reply = Make-Reply -Status 'Certification'
    Check 'certification' 1 'pending or non-published submission'
    $script:reply = (Make-Reply).Replace('Could not find a Pending Submission, but found the Last Published Submission', 'Found pending submission')
    Check 'conflicting state' 1 'conflicting submission state'
    $script:reply = Make-Reply -Price 'Base'
    Check 'paid' 1 'not confirmed Free'
    $script:reply = Make-Reply -Price ''
    Check 'empty price' 1 'not confirmed Free'
    $script:reply = Make-Reply -Version 'bad'
    Check 'bad live version' 1 'live package version'
    $script:reply = (Make-Reply).Replace('"Pricing":{"PriceId":"Free"}', '"Pricing":{}')
    Check 'missing price' 1 'not confirmed Free'
    $script:reply = (Make-Reply).Replace('1.0.0.0', "1.0.`r`n0.0")
    Check 'wrapped JSON' 0 'passed'
    $script:reply = 'Could not find a pending submission or published submission'
    Check 'first publication' 1 'no live submission'
    $script:reply = 'SellerId is not set'
    Check 'unconfigured' 2 'manual'
    $script:reply = 'credential secret should never appear'
    $script:exitCode = 1
    $answer = @(Invoke-StorePreflight 'ABCDEFGHIJKL' 'Sample' '2.0.0.0')
    if ($answer[-1] -ne 2 -or ($answer -join ' ') -match 'secret|ABCDEFGHIJKL') { throw 'Unavailable channel leaked output or returned wrong code' }
    $before = $script:calls
    try { Invoke-StoreRead @('submission', 'delete', 'ABCDEFGHIJKL'); throw 'allow-list accepted delete' } catch { if ($_.Exception.Message -ne 'Store operation is not allowed.') { throw } }
    if ($script:calls -ne $before) { throw 'disallowed verb reached CLI' }
    $script:cliPresent = $false
    Check 'missing CLI' 2 'manual'
    $scriptPath = (Resolve-Path "$PSScriptRoot/../Store-Preflight.ps1").Path.Replace("'", "''")
    $child = @'
function global:msstore {
    $global:LASTEXITCODE = 0
    'Could not find a Pending Submission, but found the Last Published Submission'
    '{"Status":"Published","Pricing":{"PriceId":"Free"},"ApplicationPackages":[{"Version":"1.0.0.0"}]}'
}
& '__SCRIPT__' -StoreId ABCDEFGHIJKL -ProductName Sample -PackageVersion 2.0.0.0
'@.Replace('__SCRIPT__', $scriptPath)
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($child))
    $output = & pwsh -NoProfile -EncodedCommand $encoded 2>&1
    if ($LASTEXITCODE -ne 0 -or ($output -join ' ') -notmatch 'preflight passed' -or ($output -join ' ') -match 'ABCDEFGHIJKL') {
        throw 'CLI entry point failed or leaked the Store ID'
    }
    Write-Output 'Store preflight stub checks passed.'
} finally { Remove-Item function:global:msstore -ErrorAction SilentlyContinue }
