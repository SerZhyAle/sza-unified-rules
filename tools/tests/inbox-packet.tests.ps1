#requires -Version 7.0
<#
.SYNOPSIS
    Cases for lib/inbox-packet.ps1 (S0045), the conformance vector replay, and publish-projects.ps1.

.DESCRIPTION
    Everything runs in a scratch directory; the real inbox root, the real registry and any Drive folder are
    never touched. No agent, no watcher. The whole file is a few seconds.

      1. Accept/refuse matrix of the manifest validator: one case per frozen reason name of INBOX-PACKET.md
         section 4 - a valid packet accepted, every defined refusal refused with its own name and nothing
         trusted of a refused packet.
      2. Folder-level checks: missing payload, size mismatch, hash mismatch, unexpected file, the packet cap,
         a missing folder, and the accept that must survive: unknown manifest members ignored, a text-only
         packet (files []), a multi-project packet, a reserved auth object.
      3. The conformance vector (tools/tests/data/inbox-ticket-vector): the writer probe rebuilds
         manifest.json byte for byte from the ordered reference and the live payload bytes, the SHA-256 equal
         to the vector.json record; the reader probe accepts the packet folder as written.
      4. publish-projects.ps1 over a throwaway registry: projects.json parses, the keys and display names
         match the registry in order, the spool folders appear beside it, a missing registry refuses with the
         registry's own reason, a relative inbox root refuses with ArgumentInvalid.
#>
[CmdletBinding()]
param([switch] $KeepScratch)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$SourceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
. (Join-Path $SourceRoot 'tools\harness\portfolio\lib\inbox-packet.ps1')
$publish = Join-Path $SourceRoot 'tools\harness\portfolio\publish-projects.ps1'
$vectorRoot = Join-Path $SourceRoot 'tools\tests\data\inbox-ticket-vector'
$pwshExe = (Get-Command pwsh -CommandType Application | Select-Object -First 1).Source

$run = 0; $passed = 0; $failed = 0
function Assert-That([bool] $Condition, [string] $Message) { if (-not $Condition) { throw $Message } }
function Run-Case([string] $Name, [scriptblock] $Body) {
    $script:run++
    Write-Host -NoNewline "CASE  $Name ... "
    try { & $Body; $script:passed++; Write-Host 'PASS' -ForegroundColor Green }
    catch { $script:failed++; Write-Host 'FAIL' -ForegroundColor Red; Write-Host "      $($_.Exception.Message)" -ForegroundColor DarkRed }
}

$scratch = Join-Path ([IO.Path]::GetTempPath()) ('inbox-packet-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $scratch | Out-Null
$script:packetSeq = 0

function Assert-Reason($Result, [string]$Reason) {
    $names = @($Result.errors) | ForEach-Object { $_.name }
    Assert-That ($names -contains $Reason) "expected the refusal '$Reason', found: $($names -join ', ')"
}
function Assert-Ok($Result) {
    Assert-That $Result.ok "expected acceptance, refused by: $(@($Result.errors) | ForEach-Object { $_.name } | Select-Object -Unique)"
}

function New-BaseManifest ([string]$PacketId = '') {
    if (-not $PacketId) { $script:packetSeq++; $PacketId = 'pk-' + $script:packetSeq }
    $payload = Join-Path $scratch 'payload-write'
    if (-not [IO.Directory]::Exists($payload)) { $null = [IO.Directory]::CreateDirectory($payload) }
    $file = Join-Path $payload 'text.md'
    [IO.File]::WriteAllText($file, "Add a dark theme toggle to the export screen.`n", [Text.UTF8Encoding]::new($false))
    $size = [long]([IO.FileInfo]$file).Length
    $sha = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([IO.File]::ReadAllBytes($file))).ToLowerInvariant()
    return [ordered]@{
        schemaVersion      = 2
        payloadKind        = 'TICKET'
        packetId           = $PacketId
        createdAtEpochMs   = [long]1794389400000
        senderDeviceName   = 'Pixel 8'
        senderDeviceId     = 'dev-A_0123456789abcdef'
        targetDeviceName   = 'SZA-PC'
        status             = 'PENDING'
        fileNames          = @('text.md')
        totalSizeBytes     = $size
        ttlSeconds         = 604800
        files              = @([ordered]@{ name = 'text.md'; size = $size; sha256 = $sha; mimeType = 'text/markdown'; role = 'text' })
        project            = $null
        text               = 'Add a dark theme toggle to the export screen.'
    }
}
function Publish-Packet ($Manifest) {
    $dir = Join-Path $scratch ([string]$Manifest.packetId)
    if (-not [IO.Directory]::Exists($dir)) { $null = [IO.Directory]::CreateDirectory($dir) }
    Copy-Item -Path (Join-Path $scratch 'payload-write\*') -Destination $dir -Force
    $null = Write-InboxPacketManifest -Manifest $Manifest -Path (Join-Path $dir 'manifest.json')
    return $dir
}
function Refused([string]$Name, [string]$Reason, [scriptblock]$Mutate) {
    Run-Case $Name {
        $m = New-BaseManifest
        & $Mutate $m
        $dir = Publish-Packet $m
        $r = Test-InboxPacketFolder -Path $dir
        Assert-That (-not $r.ok) "expected a refusal with '$Reason', accepted instead"
        Assert-Reason $r $Reason
    }
}

Write-Host 'lib/inbox-packet.ps1 - the manifest matrix'

Run-Case 'accept-a-written-packet' {
    $m = New-BaseManifest
    $dir = Publish-Packet $m
    $r = Test-InboxPacketFolder -Path $dir
    Assert-Ok $r
    Assert-That ([string]$r.packet.packetId -ceq [string]$m.packetId) 'the packet did not come back'
    Assert-That (@($r.files).Count -eq 1) 'the validated files list is empty'
}
Refused 'refuse-absent-schema-version' 'SchemaVersionUnsupported' { param($m) $m.Remove('schemaVersion') }
Refused 'refuse-wrong-schema-version' 'SchemaVersionUnsupported' { param($m) $m.schemaVersion = 3 }
Refused 'refuse-wrong-payload-kind' 'PayloadKindNotTicket' { param($m) $m.payloadKind = 'SETTINGS' }
Refused 'refuse-bad-packet-id' 'PacketIdInvalid' { param($m) $m.packetId = 'has space!' }
Run-Case 'refuse-packet-id-folder-mismatch' {
    $m = New-BaseManifest
    $dir = Publish-Packet $m
    $renamed = Join-Path $scratch 'renamed-folder'
    [IO.Directory]::Move($dir, $renamed)
    $r = Test-InboxPacketFolder -Path $renamed
    Assert-That (-not $r.ok) 'expected a refusal, accepted instead'
    Assert-Reason $r 'PacketIdInvalid'
}
Refused 'refuse-absent-created-at' 'CreatedAtInvalid' { param($m) $m.Remove('createdAtEpochMs') }
Refused 'refuse-absent-sender-name' 'SenderDeviceNameInvalid' { param($m) $m.Remove('senderDeviceName') }
Refused 'refuse-malformed-sender-device-id' 'MemberInvalid' { param($m) $m.senderDeviceId = 5 }
Refused 'refuse-malformed-target-name' 'MemberInvalid' { param($m) $m.targetDeviceName = 5 }
Refused 'refuse-unknown-status' 'StatusInvalid' { param($m) $m.status = 'DONE' }
Refused 'refuse-absent-ttl' 'TtlInvalid' { param($m) $m.Remove('ttlSeconds') }
Refused 'refuse-zero-ttl' 'TtlInvalid' { param($m) $m.ttlSeconds = 0 }
Refused 'refuse-absent-files' 'FilesMemberMissing' { param($m) $m.Remove('files'); $m.fileNames = @(); $m.totalSizeBytes = 0 }
Refused 'refuse-bad-hash-format' 'FileEntryInvalid' { param($m) $m.files[0].sha256 = 'not-hex' }
Refused 'refuse-missing-mime' 'FileEntryInvalid' { param($m) $m.files[0].Remove('mimeType') }
Refused 'refuse-unsafe-file-name' 'FileNameUnsafe' { param($m) $m.files[0].name = '..\escape.txt'; $m.fileNames = @('..\escape.txt') }
Refused 'refuse-manifest-as-payload' 'FileNameUnsafe' { param($m) $m.files[0].name = 'manifest.json'; $m.fileNames = @('manifest.json') }
Refused 'refuse-file-names-order' 'FileNamesMismatch' { param($m) $m.files[0].name = 'b.md'; $m.fileNames = @('a.md') }
Refused 'refuse-total-size-off-by-one' 'TotalSizeMismatch' { param($m) $m.totalSizeBytes = $m.totalSizeBytes + 1 }
Refused 'refuse-unknown-role' 'RoleInvalid' { param($m) $m.files[0].role = 'video' }
Refused 'refuse-bad-project-key' 'ProjectKeyInvalid' { param($m) $m.project = 'FMS A' }
Refused 'refuse-bad-projects-entry' 'ProjectKeyInvalid' { param($m) $m.projects = @('fms-a', 'SHOUTING') }
Refused 'refuse-whitespace-text' 'TextInvalid' { param($m) $m.text = '   ' }
Refused 'refuse-malformed-auth' 'AuthInvalid' { param($m) $m.auth = 'nope' }

Write-Host 'the folder on disk'

Run-Case 'refuse-missing-manifest' {
    $dir = Join-Path $scratch 'bare-packet'
    $null = [IO.Directory]::CreateDirectory($dir)
    Copy-Item -Path (Join-Path $scratch 'payload-write\*') -Destination $dir -Force
    $r = Test-InboxPacketFolder -Path $dir
    Assert-That (-not $r.ok) 'expected a refusal, accepted instead'
    Assert-Reason $r 'ManifestMissing'
}
Run-Case 'refuse-corrupt-manifest-json' {
    $dir = Join-Path $scratch 'corrupt-manifest'
    $null = [IO.Directory]::CreateDirectory($dir)
    Copy-Item -Path (Join-Path $scratch 'payload-write\*') -Destination $dir -Force
    [IO.File]::WriteAllBytes((Join-Path $dir 'manifest.json'), [byte[]][char[]]'{"schemaVersion": 2,')
    $r = Test-InboxPacketFolder -Path $dir
    Assert-That (-not $r.ok) 'expected a refusal, accepted instead'
    Assert-Reason $r 'ManifestInvalidJson'
    Assert-That ($null -eq $r.packet) 'a refused packet must not carry a document'
}
Run-Case 'refuse-missing-folder' {
    $r = Test-InboxPacketFolder -Path (Join-Path $scratch 'no-such-packet')
    Assert-That (-not $r.ok) 'expected a refusal, accepted instead'
    Assert-Reason $r 'FolderMissing'
}
Run-Case 'refuse-missing-payload-file' {
    $dir = Publish-Packet (New-BaseManifest)
    [IO.File]::Delete((Join-Path $dir 'text.md'))
    $r = Test-InboxPacketFolder -Path $dir
    Assert-That (-not $r.ok) 'expected a refusal, accepted instead'
    Assert-Reason $r 'FileMissing'
}
Run-Case 'refuse-size-mismatch' {
    $dir = Publish-Packet (New-BaseManifest)
    [IO.File]::WriteAllText((Join-Path $dir 'text.md'), "one byte longer`n", [Text.UTF8Encoding]::new($false))
    $r = Test-InboxPacketFolder -Path $dir
    Assert-That (-not $r.ok) 'expected a refusal, accepted instead'
    Assert-Reason $r 'FileSizeMismatch'
}
Run-Case 'refuse-hash-mismatch' {
    $dir = Publish-Packet (New-BaseManifest)
    $file = Join-Path $dir 'text.md'
    $bytes = [IO.File]::ReadAllBytes($file)
    $bytes[0] = if ($bytes[0] -eq 65) { [byte]66 } else { [byte]65 }
    [IO.File]::WriteAllBytes($file, $bytes)
    $r = Test-InboxPacketFolder -Path $dir
    Assert-That (-not $r.ok) 'expected a refusal, accepted instead'
    Assert-Reason $r 'FileHashMismatch'
}
Run-Case 'refuse-unexpected-file' {
    $dir = Publish-Packet (New-BaseManifest)
    [IO.File]::WriteAllText((Join-Path $dir 'extra.bin'), 'not listed', [Text.UTF8Encoding]::new($false))
    $r = Test-InboxPacketFolder -Path $dir
    Assert-That (-not $r.ok) 'expected a refusal, accepted instead'
    Assert-Reason $r 'UnexpectedFile'
}
Run-Case 'refuse-packet-over-cap' {
    $dir = Publish-Packet (New-BaseManifest)
    $r = Test-InboxPacketFolder -Path $dir -MaxPacketBytes 3
    Assert-That (-not $r.ok) 'expected a refusal, accepted instead'
    Assert-Reason $r 'PacketTooLarge'
}

Write-Host 'accepts that must hold'

Run-Case 'unknown-member-ignored' {
    $m = New-BaseManifest
    $m.someFutureMember = @{ x = 1 }
    $r = Test-InboxPacketFolder -Path (Publish-Packet $m)
    Assert-Ok $r
}
Run-Case 'text-only-packet' {
    $m = [ordered]@{
        schemaVersion      = 2
        payloadKind        = 'TICKET'
        packetId           = 'pk-empty'
        createdAtEpochMs   = [long]1794389400000
        senderDeviceName   = 'Pixel 8'
        fileNames          = @()
        totalSizeBytes     = [long]0
        ttlSeconds         = 604800
        files              = @()
        project            = $null
        text               = 'No attachments, just words.'
    }
    $null = Write-InboxPacketManifest -Manifest $m -Path (Join-Path $scratch 'pk-empty\manifest.json')
    Assert-Ok (Test-InboxPacketFolder -Path (Join-Path $scratch 'pk-empty'))
}
Run-Case 'multi-project-packet' {
    $m = New-BaseManifest
    $m.projects = @('fms-a', 'canon')
    Assert-Ok (Test-InboxPacketFolder -Path (Publish-Packet $m))
}
Run-Case 'reserved-auth-object-accepted' {
    $m = New-BaseManifest
    $m.auth = [ordered]@{ algorithm = 'HMAC-SHA256'; value = 'AAECAwQ=' }
    Assert-Ok (Test-InboxPacketFolder -Path (Publish-Packet $m))
}

Write-Host 'the conformance vector (writer probe, reader probe)'

Run-Case 'vector-writer-probe-byte-for-byte' {
    $dir = Join-Path $vectorRoot 'ticket-vector-s0045-a'
    $vector = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $vectorRoot 'vector.json'))) -DateKind String
    $files = @()
    $total = [long]0
    foreach ($entry in @($vector.files)) {
        $bytes = [IO.File]::ReadAllBytes((Join-Path $dir ([string]$entry.name)))
        $sha = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
        Assert-That ($sha -ceq [string]$entry.sha256) "the payload file '$($entry.name)' does not hash as the vector records"
        $total += $bytes.Length
        $files += [ordered]@{ name = [string]$entry.name; size = $bytes.Length; sha256 = $sha; mimeType = [string]$entry.mimeType; role = [string]$entry.role }
    }
    $rebuilt = [ordered]@{
        schemaVersion      = 2
        payloadKind        = 'TICKET'
        packetId           = [string]$vector.packetId
        createdAtEpochMs   = [long]1794389400000
        senderDeviceName   = 'Pixel 8'
        senderDeviceId     = 'dev-A_0123456789abcdef'
        targetDeviceName   = 'SZA-PC'
        status             = 'PENDING'
        fileNames          = @($files | ForEach-Object { $_.name })
        totalSizeBytes     = $total
        ttlSeconds         = 604800
        files              = $files
        project            = 'fms-a'
        text               = 'Conformance vector packet for the phone-ticket transport (S0045). Replay it; never file it. If it arrives as a real ticket, it leaked out of tools/tests/data/inbox-ticket-vector.'
    }
    $out = Join-Path $scratch 'rebuilt-manifest.json'
    $hash = Write-InboxPacketManifest -Manifest $rebuilt -Path $out
    Assert-That ($hash -ceq [string]$vector.manifestSha256) "the rebuilt manifest hashes to $hash, the vector froze $($vector.manifestSha256)"
    $frozen = [IO.File]::ReadAllBytes((Join-Path $dir 'manifest.json'))
    $live = [IO.File]::ReadAllBytes($out)
    Assert-That ($frozen.Length -eq $live.Length) 'the rebuilt manifest is a different length than the frozen one'
    $diff = $false
    for ($i = 0; $i -lt $frozen.Length; $i++) { if ($frozen[$i] -ne $live[$i]) { $diff = $true; break } }
    Assert-That (-not $diff) 'the rebuilt manifest differs from the frozen one byte for byte'
    Assert-That ($total -eq [long]$vector.totalSizeBytes) 'the payload total drifted from the vector record'
}
Run-Case 'vector-reader-probe' {
    $r = Test-InboxPacketFolder -Path (Join-Path $vectorRoot 'ticket-vector-s0045-a')
    Assert-Ok $r
    Assert-That (@($r.files).Count -eq 4) 'the vector packet must carry four payload files'
    $expectedRoles = @('text', 'voice', 'screenshot', 'log')
    Assert-That (@($r.files | Where-Object { $_.role -cin $expectedRoles }).Count -eq 4) 'a payload file lost its role'
}

Write-Host 'publish-projects.ps1'

Run-Case 'publish-round-trip' {
    $inbox = Join-Path $scratch 'inbox'
    $registry = Join-Path $scratch 'repos.json'
    [IO.File]::WriteAllText($registry, (@'
{
  "schemaVersion": "1.0",
  "repos": [
    { "key": "canon", "path": "P:\\WEB\\sza-unified-rules", "enabled": true, "rank": 10 },
    { "key": "fms-a", "path": "p:\\ANDROID\\FastMediaSorter_mob_v2", "enabled": true, "rank": 50 }
  ]
}
'@ -replace "`r`n", "`n"), [Text.UTF8Encoding]::new($false))
    $out = & $pwshExe -NoProfile -File $publish -InboxRoot $inbox -RegistryPath $registry
    Assert-That ($LASTEXITCODE -eq 0) "publish failed: $out"
    Assert-That (@($out)[-1] -cmatch '^published 2 project\(s\) to ') "the result line did not print: $out"
    $doc = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $inbox 'projects.json'))) -DateKind String
    Assert-That ([long]$doc.schemaVersion -eq 1) 'projects.json lost its schemaVersion'
    Assert-That (@($doc.projects).Count -eq 2) 'projects.json carried the wrong project count'
    Assert-That ([string]$doc.projects[0].key -ceq 'canon' -and [string]$doc.projects[0].name -ceq 'sza-unified-rules') 'the first key/name pair drifted'
    Assert-That ([string]$doc.projects[1].key -ceq 'fms-a' -and [string]$doc.projects[1].name -ceq 'FastMediaSorter_mob_v2') 'the second key/name pair drifted'
    foreach ($d in @('new', 'processing', 'done', 'failed')) {
        Assert-That ([IO.Directory]::Exists((Join-Path $inbox $d))) "the $d spool folder was not created"
    }
    Assert-That ([string]$doc.generatedAt -cmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$') 'generatedAt is not RFC 3339 UTC'
}
Run-Case 'publish-refuses-missing-registry' {
    $out = & $pwshExe -NoProfile -File $publish -InboxRoot (Join-Path $scratch 'inbox-x') -RegistryPath (Join-Path $scratch 'no-registry.json') 2>&1
    Assert-That ($LASTEXITCODE -eq 2) 'a missing registry must exit 2'
    Assert-That ("$out" -cmatch 'RegistryMissing') "the refusal was not named: $out"
}
Run-Case 'publish-refuses-relative-root' {
    $out = & $pwshExe -NoProfile -File $publish -InboxRoot 'relative/inbox' 2>&1
    Assert-That ($LASTEXITCODE -eq 2) 'a relative inbox root must exit 2'
    Assert-That ("$out" -cmatch 'ArgumentInvalid') "the refusal was not named: $out"
}

if ($KeepScratch) { Write-Host "scratch kept: $scratch" } else { try { Remove-Item -Recurse -Force $scratch } catch { } }
Write-Host ''
Write-Host "pass $passed of $run, failed $failed"
exit ([int]($failed -gt 0))
