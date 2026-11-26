<#
.SYNOPSIS
    Validate the document registry - the tracked one and, where the profile declares it, the local one - and the
    files they register.

.DESCRIPTION
    The tracked registry is paths.documentRegistry. paths.localDocumentRegistry (HARNESS-PROFILE rule 18) names the
    registry of the local, ignored corpus (DOC-INTERNAL-QUALITY item K). It is validated by the same record rules
    when the file exists and passed over in silence when it does not, because a clone does not carry an ignored
    file. A local record is never published, and an id is unique across both registries.

    DOC-INTERNAL-QUALITY item W: a record with generated true names its generator and its drift check in two
    fields, `generator` and `check`, each a command line; a `check` of `none`, optionally followed by its reason,
    says that no drift check exists yet and is printed as an advisory. A field that is present is always judged:
    it is a non-empty string, the first script it names (a token ending in .ps1, .py, .sh, .cmd, .bat, .js or .mjs)
    exists, a generated record that names one names the other, and a record that is not generated carries no
    `generator` (it may carry a `check`, the command that validates the source). A generated record that names
    neither is an advisory by default, because an adopter owes item W at its next alignment run and not before
    (the Decision of PROPOSAL-2026-10-27-maintained-corpus-and-generated-render.md); -Strict makes it an error.

    Exit codes: 0 = valid (advisories may be printed), 1 = validation errors, 2 = invalid invocation or
    unreadable registry.
#>
[CmdletBinding()]
param(
    [string] $RepoRoot = '',
    # Refuse a generated record that names neither `generator` nor `check` (DOC-INTERNAL-QUALITY item W).
    [switch] $Strict
)

. (Join-Path $PSScriptRoot '..\_profile.ps1')
if ([string]::IsNullOrWhiteSpace($RepoRoot)) { $RepoRoot = Get-SzaProjectRoot }

$ErrorActionPreference = 'Stop'

$Script:ScriptExtensions = @('.ps1', '.py', '.sh', '.cmd', '.bat', '.js', '.mjs')

function Get-Matches {
    param([string] $Pattern)
    $fullPattern = Join-Path $RepoRoot ($Pattern -replace '/', [IO.Path]::DirectorySeparatorChar)
    @(Get-ChildItem -Path $fullPattern -File -ErrorAction SilentlyContinue)
}

function Get-PagePermalink {
    param([string] $Path)
    $head = @(Get-Content -LiteralPath $Path -TotalCount 12 -Encoding utf8 -ErrorAction SilentlyContinue)
    if ($head.Count -eq 0) { return $null }
    foreach ($line in $head) {
        if ($line -match '^\s*permalink:\s*(\S+)\s*$') { return $Matches[1].Trim("'", '"') }
    }
    return $null
}

function Get-DeclaredAddresses {
    <#
        S1803: every address a record announces by hand - its entry point and its translated
        siblings. The expanded per-page addresses are not here: those come from the pages themselves
        and cannot point at a file that does not exist.
    #>
    param([object] $Record)
    $addresses = [System.Collections.Generic.List[string]]::new()
    if ($Record.url) { [void]$addresses.Add([string]$Record.url) }
    if ($Record.localized_urls) {
        foreach ($property in $Record.localized_urls.PSObject.Properties) { [void]$addresses.Add([string]$property.Value) }
    }
    return $addresses
}

function Get-LocalRegistryPath {
    <#
        HARNESS-PROFILE rule 18. Read through Get-SzaProfileValue rather than Get-SzaPath, because an
        empty value is the shipped default ("no local registry") and Get-SzaPath refuses an empty key.
    #>
    $value = [string](Get-SzaProfileValue 'paths.localDocumentRegistry')
    if ([string]::IsNullOrWhiteSpace($value)) { return $null }
    if ([IO.Path]::IsPathRooted($value)) { return $value }
    return (Join-Path $RepoRoot ($value -replace '/', [IO.Path]::DirectorySeparatorChar))
}

function Read-Registry {
    param([string] $Path, [string] $Label, $Errors)
    $records = [System.Collections.Generic.List[object]]::new()
    $lineNumber = 0
    foreach ($line in Get-Content -LiteralPath $Path -Encoding utf8) {
        $lineNumber++
        if (-not $line.Trim()) { continue }
        try {
            $records.Add([pscustomobject]@{ Record = ($line | ConvertFrom-Json); Label = $Label })
        } catch {
            $Errors.Add("${Label}L${lineNumber}: invalid JSON")
        }
    }
    return $records
}

function Test-CommandField {
    <#
        A command line is judged by the first script it names - the program the line runs. Later
        tokens are its arguments or a reader's note, and a command that names no script (`npm run`,
        a tool on PATH) is not refused: this gate catches a script that was moved or renamed.
        Returns $false when the value is `none`, optionally followed by its reason (`none yet: ..`).
    #>
    param([object] $Record, [string] $Field, [string] $Name, $Errors)
    $value = $Record.$Field
    if ($value -isnot [string] -or [string]::IsNullOrWhiteSpace($value)) {
        $Errors.Add("${Name}: '$Field' is not a command line - write the command as one non-empty string")
        return $true
    }
    if ($value.Trim() -match '^(?i)none\b') { return $false }
    foreach ($token in ($value -split '\s+')) {
        $candidate = $token.Trim("'", '"')
        if (-not $candidate) { continue }
        if ($Script:ScriptExtensions -notcontains ([IO.Path]::GetExtension($candidate)).ToLowerInvariant()) { continue }
        $scriptPath = if ([IO.Path]::IsPathRooted($candidate)) { $candidate } else {
            Join-Path $RepoRoot ($candidate -replace '/', [IO.Path]::DirectorySeparatorChar)
        }
        if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
            $Errors.Add("${Name}: '$Field' names a script that does not exist: $candidate")
        }
        break
    }
    return $true
}

function Test-RenderFields {
    <#
        DOC-INTERNAL-QUALITY item W, as FastMediaSorter Android records it (its S4895): `generator` and
        `check` are command lines, and `check` = `none` is the honest word for a render that has no drift
        check yet - listed on every run rather than hidden as free text. A source record may carry a
        `check` of its own (the command that validates it), so only `generator` is refused there.
    #>
    param([object] $Record, [string] $Name, $Errors, $Advisories)
    $names = @($Record.PSObject.Properties.Name)
    $present = @('generator', 'check' | Where-Object { $names -contains $_ })
    $isGenerated = ($names -contains 'generated') -and ($Record.generated -eq $true)
    if (-not $isGenerated) {
        if ($present -contains 'generator') {
            $Errors.Add("${Name}: carries 'generator' but is not generated - drop the field or set generated true")
        }
        if ($present -contains 'check') { [void](Test-CommandField -Record $Record -Field 'check' -Name $Name -Errors $Errors) }
        return
    }
    if ($present.Count -eq 0) {
        $message = "${Name}: generated record names no 'generator' and no 'check' (DOC-INTERNAL-QUALITY item W)"
        if ($Strict) { $Errors.Add($message) } else { $Advisories.Add($message) }
        return
    }
    foreach ($field in 'generator', 'check') {
        if ($present -notcontains $field) {
            $Errors.Add("${Name}: generated record has no '$field' field - name the command (DOC-INTERNAL-QUALITY item W)")
            continue
        }
        $isCommand = Test-CommandField -Record $Record -Field $field -Name $Name -Errors $Errors
        if ($isCommand) { continue }
        if ($field -eq 'check') {
            $Advisories.Add("${Name}: render has no drift check (check = none)")
        } else {
            $Errors.Add("${Name}: 'generator' cannot be none - a render without a generator is recorded as a source")
        }
    }
}

try {
    $registryPath = (Join-Path $RepoRoot (Get-SzaPath 'documentRegistry' -Relative))
    if (-not (Test-Path -LiteralPath $registryPath)) { throw "Registry not found: $registryPath" }
    $errors = [System.Collections.Generic.List[string]]::new()
    $advisories = [System.Collections.Generic.List[string]]::new()
    $entries = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in (Read-Registry -Path $registryPath -Label '' -Errors $errors)) { $entries.Add($entry) }
    $trackedCount = $entries.Count
    $localPath = Get-LocalRegistryPath
    $localRead = $false
    if ($localPath -and (Test-Path -LiteralPath $localPath -PathType Leaf)) {
        $localRead = $true
        foreach ($entry in (Read-Registry -Path $localPath -Label 'local:' -Errors $errors)) { $entries.Add($entry) }
    }
    $required = @('id', 'title', 'category', 'audience', 'paths', 'published', 'indexable', 'product_areas', 'update_triggers', 'generated')
    $seen = @{}
    foreach ($entry in $entries) {
        $record = $entry.Record
        $name = "$($entry.Label)$($record.id)"
        foreach ($field in $required) {
            if (-not ($record.PSObject.Properties.Name -contains $field)) { $errors.Add("${name}: missing $field") }
        }
        if ($record.id -notmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$') { $errors.Add("${name}: invalid id") }
        if ($seen.ContainsKey($record.id)) { $errors.Add("${name}: duplicate id") } else { $seen[$record.id] = $true }
        if ($entry.Label -and ($record.published -or $record.indexable)) {
            # The amendment of 2026-10-17 to DOC-INTERNAL-QUALITY: no index of files a reader cannot open.
            $errors.Add("${name}: a local registry record is never published - set published and indexable false")
        }
        if ($record.indexable -and (-not $record.published -or -not $record.url)) { $errors.Add("${name}: indexable record needs published=true and url") }
        Test-RenderFields -Record $record -Name $name -Errors $errors -Advisories $advisories
        foreach ($relativePath in @($record.paths)) {
            if ($relativePath -match '(^|/|\\)\.\.($|/|\\)' -or [IO.Path]::IsPathRooted($relativePath)) {
                $errors.Add("${name}: path escapes repo: $relativePath")
                continue
            }
            if ((Get-Matches -Pattern $relativePath).Count -eq 0) { $errors.Add("${name}: no file matches $relativePath") }
        }
        # S1803: a page withheld from the sitemap has to say why, in words a reader can re-judge in a
        # year - an exclusion list whose entries read "internal" becomes a place things disappear into.
        foreach ($exclusion in @($record.sitemap_exclude)) {
            if (-not $exclusion) { continue }
            if (-not $exclusion.path) {
                $errors.Add("${name}: sitemap_exclude entry without a path")
                continue
            }
            if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot $exclusion.path))) {
                $errors.Add("${name}: sitemap_exclude names a missing file: $($exclusion.path)")
            }
            $words = @(($exclusion.reason -split '\s+') | Where-Object { $_ })
            if ($words.Count -lt 4) {
                $errors.Add("${name}: sitemap_exclude reason too thin for $($exclusion.path)")
            }
        }
        $excludedPaths = @(@($record.sitemap_exclude) | Where-Object { $_ -and $_.path } |
            ForEach-Object { ([string]$_.path).Replace('\', '/') })
        # S1803: an address written by hand in the record can point at a page that was renamed or never
        # existed, and a sitemap entry that answers with an error is worse than an unannounced page.
        # Expanded addresses are exempt by construction - they are read off the page they belong to.
        if ($record.published -and $record.indexable) {
            $pages = @{}
            foreach ($relativePath in @($record.paths)) {
                foreach ($file in (Get-Matches -Pattern $relativePath)) {
                    $permalink = Get-PagePermalink -Path $file.FullName
                    if ($permalink) { $pages[$permalink] = $file.FullName }
                }
            }
            foreach ($address in (Get-DeclaredAddresses -Record $record)) {
                if ($pages.Count -eq 0) { continue }
                if (-not $pages.ContainsKey($address)) {
                    $errors.Add("${name}: declared address resolves to no page: $address")
                }
            }

            # S1803: the other half of the same contract. Adding a page to an existing group must not
            # require a registry edit for it to be announced - so a page that must NOT be announced can
            # only be caught here. A file under an indexable record has to be one of three things: it
            # declares its own address, it is named in sitemap_exclude with a reason, or it is the
            # source of an address the record itself declares. Anything else is a page nobody decided
            # about, which is how an internal note reaches a search engine.
            $recordAddresses = @(Get-DeclaredAddresses -Record $record)
            foreach ($relativePath in @($record.paths)) {
                foreach ($file in (Get-Matches -Pattern $relativePath)) {
                    $relative = $file.FullName.Substring($RepoRoot.Length).TrimStart('\', '/').Replace('\', '/')
                    if ($excludedPaths -contains $relative) { continue }
                    if (Get-PagePermalink -Path $file.FullName) { continue }
                    # A record-level address has no front matter to read: its source is the file whose
                    # name the address ends in, and the site root is backed by index.html / README.md.
                    $backsRecordAddress = $false
                    foreach ($address in $recordAddresses) {
                        if ($address -eq "/$($file.Name)") { $backsRecordAddress = $true; break }
                        if ($address -eq '/' -and $file.Name -in @('index.html', 'README.md')) {
                            $backsRecordAddress = $true; break
                        }
                    }
                    if ($backsRecordAddress) { continue }
                    $errors.Add("${name}: $relative is neither announced nor excluded - give it a " +
                        "permalink, or add it to sitemap_exclude with a reason saying what it is and who it is for")
                }
            }
        }
    }
    $counts = "$trackedCount record(s)"
    if ($localRead) { $counts += ", $($entries.Count - $trackedCount) local record(s)" }
    if ($advisories.Count -gt 0) { $counts += ", $($advisories.Count) advisory" }
    if ($errors.Count -gt 0) {
        Write-Host "Document registry FAILED: $($errors.Count) error(s)" -ForegroundColor Red
        $errors | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
        $advisories | ForEach-Object { Write-Host "  advisory: $_" -ForegroundColor Yellow }
        exit 1
    }
    Write-Host "Document registry PASS: $counts" -ForegroundColor Green
    $advisories | ForEach-Object { Write-Host "  advisory: $_" -ForegroundColor Yellow }
    exit 0
} catch {
    Write-Error $_.Exception.Message -ErrorAction Continue
    exit 2
}
