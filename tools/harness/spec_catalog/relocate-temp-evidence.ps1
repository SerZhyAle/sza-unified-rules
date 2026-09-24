[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $Id
)

. (Join-Path $PSScriptRoot '..\_profile.ps1')

# Repair step run by Assert-ClosingGates immediately before check-evidence-durable, on the
# Implemented / Verified branch only.
#
# Contract:
#   - For every citation of an existing FILE under the ticket's own scratch directory
#     (<tempDir>/<Id>/...) outside section 0 of the spec or anywhere in its phase files, copy the
#     file into <specsDir>/<Id>_<slug>/attachments/ and rewrite the citation to the copy.
#   - Only files up to 64 KB move - the cap check-evidence-durable states for durable evidence.
#     A larger file, a missing file and a bare directory citation are left untouched, and the gate
#     refuses them with its own remedy: those need a human choice (an extract, or a reproducing
#     command), which a copy cannot make.
#   - An attachment with the same name and identical content is reused; a different one gets a
#     numeric suffix. Nothing under the scratch directory is deleted.
#   - Why a repair and not a longer refusal: the refusal already spelled out the move step by step,
#     and the agent then performed exactly that move by hand and re-ran the transition (measured on
#     the consumer repository, 2026-09-24). A remedy with no judgement in it belongs to the tool.
#
# Exit codes: 0 = done (including nothing to move). 2 = bad invocation. The caller treats any exit
# as advisory: the gate that follows is what decides the transition.

. (Join-Path $PSScriptRoot '_lib.ps1')

if ($Id -notmatch '^S\d{4}$') {
    Write-Error "Invalid -Id '$Id' (must match S####)." -ErrorAction Continue
    exit 2
}

$record = $null
foreach ($r in (Read-Catalog)) { if ($r.id -eq $Id) { $record = $r; break } }
if (-not $record) { exit 0 }

$repoRoot = (Get-SzaProjectRoot)
$specPath = Join-Path $repoRoot ($record.file -replace '/', [IO.Path]::DirectorySeparatorChar)
if (-not (Test-Path -LiteralPath $specPath)) { exit 0 }

$maxBytes = 64KB
$tempRel = (Get-SzaPath 'tempDir' -Relative).TrimEnd('/')
# The citation grammar: the ticket's own scratch directory, then a relative path made of the
# characters a path token carries in Markdown prose - stops at whitespace, a backtick, a quote,
# a bracket or a closing parenthesis.
$citation = [regex]::new('(?<![\w/])' + [regex]::Escape("$tempRel/$Id/") + '(?<rest>[^\s`''"\)\]\[<>|,;]+)')

$specDirRel = ($record.file -replace '\\', '/') -replace '\.md$', ''
$attachDirRel = "$specDirRel/attachments"
$attachDir = Join-Path $repoRoot ($attachDirRel -replace '/', [IO.Path]::DirectorySeparatorChar)

$targets = @($specPath)
$specDir = Join-Path $repoRoot ($specDirRel -replace '/', [IO.Path]::DirectorySeparatorChar)
if (Test-Path -LiteralPath $specDir) {
    foreach ($f in (Get-ChildItem -LiteralPath $specDir -Filter '*.md' -Recurse -File)) { $targets += $f.FullName }
}

$moved = @{}

function Get-AttachmentFor([string]$SourceFull) {
    if ($moved.ContainsKey($SourceFull)) { return $moved[$SourceFull] }
    $name = [IO.Path]::GetFileName($SourceFull)
    $stem = [IO.Path]::GetFileNameWithoutExtension($name)
    $ext = [IO.Path]::GetExtension($name)
    $sourceHash = (Get-FileHash -LiteralPath $SourceFull -Algorithm SHA256).Hash
    $n = 1
    $candidate = $name
    while ($true) {
        $candidateFull = Join-Path $attachDir $candidate
        if (-not (Test-Path -LiteralPath $candidateFull)) {
            New-Item -ItemType Directory -Force -Path $attachDir | Out-Null
            Copy-Item -LiteralPath $SourceFull -Destination $candidateFull
            break
        }
        if ((Get-FileHash -LiteralPath $candidateFull -Algorithm SHA256).Hash -eq $sourceHash) { break }
        $n++
        $candidate = "$stem-$n$ext"
    }
    $moved[$SourceFull] = "$attachDirRel/$candidate"
    return $moved[$SourceFull]
}

foreach ($target in $targets) {
    $raw = [IO.File]::ReadAllText($target)
    $newline = if ($raw.Contains("`r`n")) { "`r`n" } else { "`n" }
    $lines = $raw -split '\r?\n'
    $changed = $false
    $inSectionZero = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        # Section 0 is verbatim captured material - the same exemption the gate applies.
        if ($line -match '^##\s+0\.') { $inSectionZero = $true; continue }
        if ($inSectionZero -and $line -match '^##\s+(?!0\.)') { $inSectionZero = $false }
        if ($inSectionZero) { continue }

        $rewritten = $citation.Replace($line, {
                param($m)
                $rest = $m.Groups['rest'].Value.TrimEnd('.', ':')
                $trail = $m.Groups['rest'].Value.Substring($rest.Length)
                $sourceRel = "$tempRel/$Id/$rest"
                $sourceFull = Join-Path $repoRoot ($sourceRel -replace '/', [IO.Path]::DirectorySeparatorChar)
                if (-not (Test-Path -LiteralPath $sourceFull -PathType Leaf)) { return $m.Value }
                if ((Get-Item -LiteralPath $sourceFull).Length -gt $maxBytes) { return $m.Value }
                $dest = Get-AttachmentFor $sourceFull
                Write-Host ("evidence: {0} -> {1}" -f $sourceRel, $dest)
                return $dest + $trail
            })
        if ($rewritten -ne $line) { $lines[$i] = $rewritten; $changed = $true }
    }
    if ($changed) {
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [IO.File]::WriteAllText($target, ($lines -join $newline), $utf8NoBom)
    }
}

exit 0
