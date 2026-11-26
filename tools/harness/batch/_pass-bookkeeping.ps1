# Private handoff between the runner and its canon lifecycle child.

function Get-ManagedPassSkill([string]$Prompt) {
    if ($Prompt -match '^/sza:(spec-to-audit|spec-all)(?=\s|$)' -or
        $Prompt -match '^You have no slash commands\..* as the command /sza:(spec-to-audit|spec-all) would, with this argument string:') {
        return $Matches[1]
    }
}

function Initialize-PassBookkeeping([string]$Id, [string]$Root, [string]$TempDir) {
    $preambleScript = Get-SzaHarnessScript 'spec_catalog/spec-preamble.ps1'
    $lines = @(& $preambleScript -Id $Id -NoLease *>&1)
    if ($LASTEXITCODE -ne 0) { throw "spec-preamble exited ${LASTEXITCODE}: $($lines -join ' ')" }

    $dir = Join-Path (Join-Path $TempDir $Id) ('pass-' + [guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($dir)
    $preamble = Join-Path $dir 'preamble.txt'
    [IO.File]::WriteAllLines($preamble, [string[]]$lines)
    return @{
        preamble = [IO.Path]::GetRelativePath($Root, $preamble).Replace('\', '/')
        result   = [IO.Path]::GetRelativePath($Root, (Join-Path $dir 'result.json')).Replace('\', '/')
    }
}

function Add-PassBookkeepingPrompt([string]$Prompt, [string]$Skill, $Pass) {
    if ($Skill -ne 'spec-to-audit' -or -not $Pass) { return $Prompt }
    return "$Prompt Read the prepared ticket context at `"$($Pass.preamble)`". Query the document registry only if the ticket changes files under docs/. If you changed files, write the change summary and paths to `"$($Pass.result)`" using the unattended pass format."
}

function Clear-PassBookkeeping([string]$Root, $Pass) {
    try {
        $preamble = Join-Path $Root $Pass.preamble
        $directory = [IO.Path]::GetDirectoryName($preamble)
        [IO.File]::Delete($preamble)
        [IO.File]::Delete((Join-Path $Root $Pass.result))
        if ([IO.Directory]::Exists($directory) -and -not (Get-ChildItem -LiteralPath $directory -Force | Select-Object -First 1)) {
            [IO.Directory]::Delete($directory)
        }
    } catch {
        Write-Warning "run-spec-queue: could not clear pass files - $($_.Exception.Message)"
    }
}

function Complete-PassBookkeeping([string]$Id, [string]$StatusBefore, $Record, [string]$ResultPath) {
    $status = [string]$Record.status
    if (-not $status -or $status -eq $StatusBefore) { return 0 }

    $devLogs = @()
    $resultInvalid = $false
    if ([IO.File]::Exists($ResultPath)) {
        try {
            $result = [IO.File]::ReadAllText($ResultPath) | ConvertFrom-Json -AsHashtable -NoEnumerate -ErrorAction Stop
            if ($result -isnot [System.Collections.IDictionary] -or
                $result.summary -isnot [string] -or $result.summary -notmatch '\S' -or $result.summary -match '[\r\n]' -or
                $result.files -isnot [array]) {
                throw 'Expected a single-line summary and an array of repository-relative files.'
            }
            foreach ($file in $result.files) {
                if ($file -isnot [string] -or $file -notmatch '\S' -or
                    $file -match '[\x00-\x1f:]' -or $file -match '^[\\/]|(^|[\\/])\.\.([\\/]|$)') {
                    throw 'Expected a repository-relative file path.'
                }
            }
            $files = @($result.files | ForEach-Object { $_.Replace('\', '/') } | Select-Object -Unique)
            if ($files.Count -gt 0) {
                $description = $result.summary
                if ($files.Count -gt 1) { $description += " [set of $($files.Count): $($files -join ', ')]" }
                $devLogs += @{ file = $files[0]; target = $Id; desc = $description } | ConvertTo-Json -Compress
            }
        } catch {
            Write-Warning "run-spec-queue: invalid result for ${Id}: $($_.Exception.Message)"
            $resultInvalid = $true
        }
    }
    $devLogs += @{ file = [string]$Record.file; target = $Id; desc = "Status moved from $StatusBefore to $status." } | ConvertTo-Json -Compress
    $closeScript = Get-SzaHarnessScript 'spec_catalog/close-and-log.ps1'
    & $closeScript -Id $Id -Status $status -PostStatus -DevLogs $devLogs | Out-Host
    if ($LASTEXITCODE -ne 0 -or $resultInvalid) { return 1 }
    return 0
}

function Release-PassLease([string]$Id, [string]$LeaseScript, $Reservation) {
    if (-not (Test-Path -LiteralPath $LeaseScript)) { return }
    try {
        $releaseArgs = @{ Verb = 'Release'; Id = $Id; Force = $true }
        if ($Reservation.session_id) { $releaseArgs.ExpectedSessionId = [string]$Reservation.session_id }
        if ($Reservation.handoff_path) { $releaseArgs.Handoff = [string]$Reservation.handoff_path }
        & $LeaseScript @releaseArgs *> $null
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "run-spec-queue: could not release the lease for $Id (exit $LASTEXITCODE)."
            return
        }
        # Re-render only when a status write left this lease's marker in the plan.
        $planFile = Get-SzaPath 'releaseQueue'
        if ($planFile -and [IO.File]::Exists($planFile) -and
            ([IO.File]::ReadLines($planFile) | Where-Object { $_.StartsWith($Id) -and $_.Contains('[taken') } | Select-Object -First 1)) {
            & pwsh -NoProfile -File (Get-SzaHarnessScript 'spec_catalog/release-queue.ps1') -Reconcile *> $null
            if ($LASTEXITCODE -eq 1) {
                Write-Warning "run-spec-queue: the plan file still shows $Id as taken - run release-queue.ps1 -Reconcile."
            }
        }
    } catch {
        Write-Warning "run-spec-queue: lease cleanup for ${Id} failed - $($_.Exception.Message)"
    }
}
