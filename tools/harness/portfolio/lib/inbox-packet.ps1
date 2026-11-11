#requires -Version 7.0
# The reader and writer of the phone-ticket inbox packet (S0045, INBOX-PACKET.md v1).
#
# Dot-source this file; it defines functions only, sets no preference and prints nothing. State: none.
# Validation never throws: every problem is an entry @{ name; where; message } of an errors array,
# all of them, not the first - the shape of lib/registry.ps1. The reason names are frozen by
# INBOX-PACKET.md section 4, so the phone can show one line per refusal. Only I/O throws.
#
#   Read-InboxPacketJson -Raw <string>      @{ ok; document; errors } - parse one JSON object.
#   Read-InboxPacketManifest -Path <file>   @{ ok; document; errors } - read manifest.json bytes.
#   Test-InboxPacketManifest [-Manifest <doc>] [-ExpectedPacketId <id>]
#                                            @{ ok; errors } - the member rules of INBOX-PACKET 2.1.
#   Test-InboxPacketFileName -Name <string>
#                                            @{ ok; reason; message } - the base-name rule of INBOX-PACKET 2.1
#                                            (reason FileNameUnsafe, or $null when the name is safe).
#   Get-InboxFileSha256 -Path <file>         lower-case hex SHA-256, $null when the file is absent.
#   Test-InboxPacketFolder -Path <dir> [-MaxPacketBytes] [-MaxFiles]
#                                            @{ ok; packet; files; errors } - the full reader check of
#                                            INBOX-PACKET section 2: manifest, payload presence, size and
#                                            hash, folder content, limits. On any error packet is $null:
#                                            a refused packet is never partially trusted, and the caller
#                                            (S0046) ingests nothing.
#   Write-InboxPacketManifest -Manifest <doc> -Path <file>
#                                            byte shape of INBOX-PACKET 2.1: 2-space JSON, LF, a final
#                                            newline, UTF-8 without BOM, through a temp file and a rename.
#                                            Returns the manifest hash.
#
# Limits default to INBOX-PACKET 2.2: 200 MiB total, 50 files; the defaults live here once, and the S0046
# ingest passes them through.
#
# Member reads go through Get-InboxMember, never directly: a plain function return unrolls arrays
# (a one-entry files[] becomes its single element, an empty fileNames [] becomes $null), and a manifest
# full of arrays must be checked as it was parsed.

$script:InboxManifestName = 'manifest.json'
$script:InboxPacketIdPattern = '^[A-Za-z0-9_-]{1,64}$'
$script:InboxProjectKeyPattern = '^[a-z][a-z0-9-]*$'
$script:InboxSha256Pattern = '^[0-9a-f]{64}$'
$script:InboxRoles = @('text', 'voice', 'screenshot', 'log', 'other')
$script:InboxStatuses = @('PENDING', 'CLAIMED', 'EXPIRED')

function New-InboxProblem([string]$Name, [string]$Where, [string]$Message) {
    return [ordered]@{ name = $Name; where = $Where; message = $Message }
}

function Test-InboxHasKey($Object, [string]$Name) {
    if ($null -eq $Object) { return $false }
    if ($Object -is [Collections.IDictionary]) { return $Object.Contains($Name) }
    return $null -ne $Object.PSObject.Properties[$Name]
}

# One member as a node @{ has; value }: a hashtable is not enumerated by the pipeline, so the value
# crosses function returns intact - arrays stay arrays, absent stays absent, null stays null.
function Get-InboxMember($Object, [string]$Name) {
    $has = Test-InboxHasKey $Object $Name
    $value = $null
    if ($has) {
        $value = if ($Object -is [Collections.IDictionary]) { $Object[$Name] } else { $Object.PSObject.Properties[$Name].Value }
    }
    return @{ has = $has; value = $value }
}

# An array member (files) for iteration: $null when absent or empty-read, the value's elements as one
# object[] otherwise. Used where the caller iterates or counts, never where missing-versus-empty matters
# (the node does that); a one-entry array reads back as its single element and is wrapped here.
function Get-InboxArrayValue($Object, [string]$Name) {
    $node = Get-InboxMember $Object $Name
    if (-not $node.has -or $null -eq $node.value) { return @() }
    return @($node.value)
}

function Test-InboxPacketFileName([string]$Name) {
    if ([string]::IsNullOrEmpty($Name) -or $Name -eq '.' -or $Name -eq '..') {
        return @{ ok = $false; reason = 'FileNameUnsafe'; message = "the name '$Name' is not a base name" }
    }
    if ($Name.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0 -or $Name -cmatch '[\\/]') {
        return @{ ok = $false; reason = 'FileNameUnsafe'; message = "the name '$Name' has a separator or an invalid character" }
    }
    if ($Name -cmatch '\p{C}') {
        return @{ ok = $false; reason = 'FileNameUnsafe'; message = "the name '$Name' has a control character" }
    }
    if ([string]::Equals($Name, $script:InboxManifestName, [StringComparison]::OrdinalIgnoreCase)) {
        return @{ ok = $false; reason = 'FileNameUnsafe'; message = "the name '$Name' is reserved for the manifest" }
    }
    return @{ ok = $true; reason = $null; message = $null }
}

function Read-InboxPacketJson {
    param([Parameter(Mandatory)][string]$Raw)
    $result = @{ ok = $false; document = $null; errors = @() }
    if ([string]::IsNullOrWhiteSpace($Raw)) {
        $result.errors = @(New-InboxProblem 'ManifestInvalidJson' '$' 'the manifest is empty')
        return $result
    }
    try { $doc = ConvertFrom-Json -InputObject $Raw -DateKind String -NoEnumerate }
    catch {
        $result.errors = @(New-InboxProblem 'ManifestInvalidJson' '$' "the manifest is not JSON: $($_.Exception.Message)")
        return $result
    }
    if ($null -eq $doc -or ($doc -isnot [Management.Automation.PSCustomObject] -and $doc -isnot [Collections.IDictionary])) {
        $result.errors = @(New-InboxProblem 'ManifestInvalidJson' '$' 'the manifest is not one JSON object')
        return $result
    }
    $result.document = $doc
    $result.ok = $true
    return $result
}

function Read-InboxPacketManifest {
    param([Parameter(Mandatory)][string]$Path)
    $result = @{ ok = $false; document = $null; errors = @() }
    if (-not [IO.File]::Exists($Path)) {
        $result.errors = @(New-InboxProblem 'ManifestMissing' '$' "no manifest.json at $Path")
        return $result
    }
    $bytes = [IO.File]::ReadAllBytes($Path)
    $text = [Text.UTF8Encoding]::new($false, $true).GetString($bytes)
    if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) { $text = $text.Substring(1) }
    $parsed = Read-InboxPacketJson -Raw $text
    $result.ok = $parsed.ok
    $result.document = $parsed.document
    $result.errors = $parsed.errors
    return $result
}

function Test-InboxPacketManifest {
    param(
        [Parameter(Mandatory)]$Manifest,
        [string]$ExpectedPacketId
    )
    $errors = [Collections.Generic.List[object]]::new()

    $schema = Get-InboxMember $Manifest 'schemaVersion'
    if (-not $schema.has -or (($schema.value -isnot [long]) -and ($schema.value -isnot [int])) -or [long]$schema.value -ne 2) {
        $errors.Add((New-InboxProblem 'SchemaVersionUnsupported' 'schemaVersion' "expected 2, found $(if (-not $schema.has) { 'absent' } elseif ($null -eq $schema.value) { 'null' } else { "$($schema.value)" })"))
    }

    $kind = Get-InboxMember $Manifest 'payloadKind'
    if ($kind.value -cne 'TICKET') {
        $errors.Add((New-InboxProblem 'PayloadKindNotTicket' 'payloadKind' "expected TICKET, found $(if (-not $kind.has) { 'absent' } elseif ($null -eq $kind.value) { 'null' } else { "$($kind.value)" })"))
    }

    $packetNode = Get-InboxMember $Manifest 'packetId'
    $packetIdOk = $true
    if ($packetNode.value -isnot [string] -or $packetNode.value -cnotmatch $script:InboxPacketIdPattern) {
        $packetIdOk = $false
        $errors.Add((New-InboxProblem 'PacketIdInvalid' 'packetId' 'packetId is absent or fails [A-Za-z0-9_-]{1,64}'))
    }
    if ($packetIdOk -and $ExpectedPacketId -and $packetNode.value -cne $ExpectedPacketId) {
        $errors.Add((New-InboxProblem 'PacketIdInvalid' 'packetId' "packetId '$($packetNode.value)' is not the folder's name '$ExpectedPacketId'"))
    }

    $createdAt = Get-InboxMember $Manifest 'createdAtEpochMs'
    if (-not $createdAt.has -or (($createdAt.value -isnot [long]) -and ($createdAt.value -isnot [int]))) {
        $errors.Add((New-InboxProblem 'CreatedAtInvalid' 'createdAtEpochMs' 'createdAtEpochMs is absent or not an integer'))
    }

    $senderNode = Get-InboxMember $Manifest 'senderDeviceName'
    if ($senderNode.value -isnot [string] -or [string]::IsNullOrWhiteSpace($senderNode.value)) {
        $errors.Add((New-InboxProblem 'SenderDeviceNameInvalid' 'senderDeviceName' 'senderDeviceName is absent, empty or not a string'))
    }

    $senderId = Get-InboxMember $Manifest 'senderDeviceId'
    if ($senderId.has -and $null -ne $senderId.value -and $senderId.value -isnot [string]) {
        $errors.Add((New-InboxProblem 'MemberInvalid' 'senderDeviceId' 'senderDeviceId is present and neither a string nor null'))
    }
    $targetName = Get-InboxMember $Manifest 'targetDeviceName'
    if ($targetName.has -and $null -ne $targetName.value -and $targetName.value -isnot [string]) {
        $errors.Add((New-InboxProblem 'MemberInvalid' 'targetDeviceName' 'targetDeviceName is present and neither a string nor null'))
    }

    $status = Get-InboxMember $Manifest 'status'
    if ($status.has -and $null -ne $status.value -and ($status.value -isnot [string] -or $status.value -cnotin $script:InboxStatuses)) {
        $errors.Add((New-InboxProblem 'StatusInvalid' 'status' "status must be one of $($script:InboxStatuses -join ', ')"))
    }

    $ttl = Get-InboxMember $Manifest 'ttlSeconds'
    if (-not $ttl.has -or (($ttl.value -isnot [long]) -and ($ttl.value -isnot [int])) -or [long]$ttl.value -le 0) {
        $errors.Add((New-InboxProblem 'TtlInvalid' 'ttlSeconds' 'ttlSeconds is absent, not an integer or not positive'))
    }

    $filesNode = Get-InboxMember $Manifest 'files'
    if (-not $filesNode.has) {
        $errors.Add((New-InboxProblem 'FilesMemberMissing' 'files' 'files is absent (it may be an empty array)'))
        $fileEntries = @()
    }
    else {
        # a plain if-statement assignment: the if-expression form ($x = if ..) flattens a one-entry
        # array back to its element, and every array member here read fine as an array.
        $fileEntries = @()
        if ($null -ne $filesNode.value) { $fileEntries = @($filesNode.value) }
        if (@($fileEntries | Where-Object { $null -eq $_ -or ($_ -isnot [Management.Automation.PSCustomObject] -and $_ -isnot [Collections.IDictionary]) }).Count -gt 0) {
            $errors.Add((New-InboxProblem 'FileEntryInvalid' 'files' 'a files[] entry is not an object'))
        }
    }

    $safeEntries = [Collections.Generic.List[object]]::new()
    $totalDeclared = [long]0
    foreach ($entry in $fileEntries) {
        if ($null -eq $entry) { continue }
        $nameNode = Get-InboxMember $entry 'name'
        $sizeNode = Get-InboxMember $entry 'size'
        $hashNode = Get-InboxMember $entry 'sha256'
        $mimeNode = Get-InboxMember $entry 'mimeType'
        $roleNode = Get-InboxMember $entry 'role'
        $entryOk = $true
        if ($nameNode.value -isnot [string] -or [string]::IsNullOrEmpty($nameNode.value)) {
            $entryOk = $false
            $errors.Add((New-InboxProblem 'FileEntryInvalid' 'files[]' 'an entry has no name'))
        }
        if (($sizeNode.value -isnot [long]) -and ($sizeNode.value -isnot [int]) -or $sizeNode.value -lt 0) {
            $entryOk = $false
            $errors.Add((New-InboxProblem 'FileEntryInvalid' "files[$($nameNode.value)]" 'size is absent, not an integer or negative'))
        }
        if ($hashNode.value -isnot [string] -or $hashNode.value -cnotmatch $script:InboxSha256Pattern) {
            $entryOk = $false
            $errors.Add((New-InboxProblem 'FileEntryInvalid' "files[$($nameNode.value)]" 'sha256 is absent or not 64 lower-case hex digits'))
        }
        if ($mimeNode.value -isnot [string] -or [string]::IsNullOrEmpty($mimeNode.value)) {
            $entryOk = $false
            $errors.Add((New-InboxProblem 'FileEntryInvalid' "files[$($nameNode.value)]" 'mimeType is absent or not a string'))
        }
        if ($roleNode.has -and $null -ne $roleNode.value -and ($roleNode.value -isnot [string] -or $roleNode.value -cnotin $script:InboxRoles)) {
            $entryOk = $false
            $errors.Add((New-InboxProblem 'RoleInvalid' "files[$($nameNode.value)]" "role must be one of $($script:InboxRoles -join ', ')"))
        }
        if ($nameNode.value -is [string]) {
            $safe = Test-InboxPacketFileName $nameNode.value
            if (-not $safe.ok) {
                $entryOk = $false
                $errors.Add((New-InboxProblem $safe.reason "files[$($nameNode.value)]" $safe.message))
            }
        }
        if ($entryOk) {
            $totalDeclared += [long]$sizeNode.value
            $safeEntries.Add([ordered]@{ name = $nameNode.value; size = [long]$sizeNode.value; sha256 = $hashNode.value; mimeType = $mimeNode.value; role = $roleNode.value })
        }
    }

    $names = @($safeEntries | ForEach-Object { $_.name })
    $fileNamesNode = Get-InboxMember $Manifest 'fileNames'
    $fileValues = @()
    if ($null -ne $fileNamesNode.value) { $fileValues = @($fileNamesNode.value) }
    $fileNamesMatch = $fileNamesNode.has -and (@($fileValues).Count -eq @($names).Count)
    if ($fileNamesMatch) {
        for ($i = 0; $i -lt @($names).Count; $i++) {
            if ($fileValues[$i] -cne $names[$i]) { $fileNamesMatch = $false; break }
        }
    }
    if (-not $fileNamesMatch) {
        $errors.Add((New-InboxProblem 'FileNamesMismatch' 'fileNames' 'fileNames is not the name list of files[], in order'))
    }

    $totalNode = Get-InboxMember $Manifest 'totalSizeBytes'
    if (($totalNode.value -isnot [long]) -and ($totalNode.value -isnot [int]) -or [long]$totalNode.value -ne $totalDeclared) {
        $errors.Add((New-InboxProblem 'TotalSizeMismatch' 'totalSizeBytes' "totalSizeBytes must be the sum of files[] sizes ($totalDeclared)"))
    }

    $project = Get-InboxMember $Manifest 'project'
    if ($project.has -and $null -ne $project.value -and ($project.value -isnot [string] -or $project.value -cnotmatch $script:InboxProjectKeyPattern)) {
        $errors.Add((New-InboxProblem 'ProjectKeyInvalid' 'project' 'project is neither null nor a key of ^[a-z][a-z0-9-]*$'))
    }
    $projects = Get-InboxMember $Manifest 'projects'
    if ($projects.has -and $null -ne $projects.value) {
        foreach ($k in @($projects.value)) {
            if ($k -isnot [string] -or $k -cnotmatch $script:InboxProjectKeyPattern) {
                $errors.Add((New-InboxProblem 'ProjectKeyInvalid' 'projects[]' "the key '$k' fails ^[a-z][a-z0-9-]*$"))
            }
        }
    }

    $text = Get-InboxMember $Manifest 'text'
    if ($text.has -and $null -ne $text.value -and ($text.value -isnot [string] -or [string]::IsNullOrWhiteSpace($text.value))) {
        $errors.Add((New-InboxProblem 'TextInvalid' 'text' 'text is present and empty, whitespace-only or not a string'))
    }

    $auth = Get-InboxMember $Manifest 'auth'
    if ($auth.has -and $null -ne $auth.value -and ($auth.value -isnot [Management.Automation.PSCustomObject] -and $auth.value -isnot [Collections.IDictionary])) {
        $errors.Add((New-InboxProblem 'AuthInvalid' 'auth' 'auth is present and neither null nor an object (INBOX-PACKET 6 reserves it)'))
    }

    return @{ ok = $errors.Count -eq 0; errors = @($errors) }
}

function Get-InboxFileSha256 {
    param([Parameter(Mandatory)][string]$Path)
    if (-not [IO.File]::Exists($Path)) { return $null }
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([IO.File]::ReadAllBytes($Path))).ToLowerInvariant()
}

function Test-InboxPacketFolder {
    param(
        [Parameter(Mandatory)][string]$Path,
        [long]$MaxPacketBytes = 209715200,
        [int]$MaxFiles = 50
    )
    $result = @{ ok = $false; packet = $null; files = $null; errors = @() }
    $errors = [Collections.Generic.List[object]]::new()
    if (-not [IO.Directory]::Exists($Path)) {
        $errors.Add((New-InboxProblem 'FolderMissing' '$' "no packet folder at $Path"))
        $result.errors = @($errors)
        return $result
    }
    $leaf = Split-Path -Leaf $Path
    $manifestPath = Join-Path $Path $script:InboxManifestName
    $read = Read-InboxPacketManifest -Path $manifestPath
    if (-not $read.ok) {
        $errors.AddRange($read.errors)
        $result.errors = @($errors)
        return $result
    }
    $check = Test-InboxPacketManifest -Manifest $read.document -ExpectedPacketId $leaf
    $errors.AddRange($check.errors)
    if (-not $check.ok) {
        $result.errors = @($errors)
        return $result
    }

    $fileEntries = @(Get-InboxArrayValue $read.document 'files')
    $files = @()
    $total = [long]0
    $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($entry in $fileEntries) {
        $entryName = (Get-InboxMember $entry 'name').value
        $file = Join-Path $Path ([string]$entryName)
        if (-not [IO.File]::Exists($file)) {
            $errors.Add((New-InboxProblem 'FileMissing' "files[$entryName]" "the payload file '$entryName' is not in the folder"))
            continue
        }
        if (-not $names.Add([string]$entryName)) {
            $errors.Add((New-InboxProblem 'FileEntryInvalid' "files[$entryName]" 'the name appears twice in files[]'))
            continue
        }
        $length = [long]([IO.FileInfo]$file).Length
        $sizeNode = Get-InboxMember $entry 'size'
        if ($length -ne [long]$sizeNode.value) {
            $errors.Add((New-InboxProblem 'FileSizeMismatch' "files[$entryName]" "expected $($($sizeNode.value)) bytes, found $length"))
            continue
        }
        $hashNode = Get-InboxMember $entry 'sha256'
        $hash = Get-InboxFileSha256 -Path $file
        if ($hash -cne [string]$hashNode.value) {
            $errors.Add((New-InboxProblem 'FileHashMismatch' "files[$entryName]" "sha256 mismatch: the manifest claims $($hashNode.value), the bytes hash to $hash"))
            continue
        }
        $total += $length
    }

    if (@($fileEntries).Count -gt $MaxFiles) {
        $errors.Add((New-InboxProblem 'TooManyFiles' 'files' "the packet has $(@($fileEntries).Count) files, the cap is $MaxFiles"))
    }
    if ($total -gt $MaxPacketBytes) {
        $errors.Add((New-InboxProblem 'PacketTooLarge' 'files' "the payload is $total bytes, the cap is $MaxPacketBytes"))
    }

    foreach ($found in ([IO.Directory]::EnumerateFiles($Path) | ForEach-Object { Split-Path -Leaf $_ })) {
        if ([string]::Equals($found, $script:InboxManifestName, [StringComparison]::OrdinalIgnoreCase)) { continue }
        if (-not $names.Contains($found)) {
            $errors.Add((New-InboxProblem 'UnexpectedFile' $found "the folder holds '$found', which files[] does not list"))
        }
    }

    if ($errors.Count -gt 0) {
        $result.errors = @($errors)
        return $result
    }
    $result.files = @(foreach ($entry in $fileEntries) {
        [ordered]@{
            name     = (Get-InboxMember $entry 'name').value
            size     = [long](Get-InboxMember $entry 'size').value
            sha256   = (Get-InboxMember $entry 'sha256').value
            mimeType = (Get-InboxMember $entry 'mimeType').value
            role     = (Get-InboxMember $entry 'role').value
        }
    })
    $result.packet = $read.document
    $result.ok = $true
    return $result
}

function Write-InboxPacketManifest {
    param(
        [Parameter(Mandatory)]$Manifest,
        [Parameter(Mandatory)][string]$Path
    )
    $json = (ConvertTo-Json -InputObject $Manifest -Depth 64).Replace("`r`n", "`n") + "`n"
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($json)
    $temp = "$Path.tmp"
    $dir = Split-Path -Parent $Path
    if (-not [IO.Directory]::Exists($dir)) { $null = [IO.Directory]::CreateDirectory($dir) }
    try {
        [IO.File]::WriteAllBytes($temp, $bytes)
        [IO.File]::Move($temp, $Path, $true)
    }
    catch {
        if ([IO.File]::Exists($temp)) { try { [IO.File]::Delete($temp) } catch { } }
        throw "InboxManifestWriteFailed: $($_.Exception.Message)"
    }
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
}
