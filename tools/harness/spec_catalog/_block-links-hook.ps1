# The status tools' call into block-links.ps1 (TASK-FLOW rule 69), after the write has landed.
#
# Dot-sourced by update.ps1, bulk-update.ps1, close.ps1 and archive.ps1 after _lib.ps1; defines one function and
# sets nothing. It runs AFTER Exit-CatalogLock, because a release moves the waiting ticket through update.ps1 in a
# child process, and that child needs the catalog lock of its own repository - which may be this one.
#
# Best effort by contract: the move that triggered it has already landed and is never undone, so every failure is
# printed and swallowed, and the caller's exit code is never changed. A child process is started only when there is
# work: on entry into BlockByOtherTask, or on a status move of a ticket whose spec carries an open `- Blocks:` line.
# SZA_BLOCK_LINKS=0 switches the call off.

function Invoke-BlockLinksHook {
    param(
        [Parameter(Mandatory)][string] $Id,
        [string] $OldStatus,
        [Parameter(Mandatory)][string] $NewStatus,
        [switch] $NoteChanged
    )
    if ($env:SZA_BLOCK_LINKS -eq '0') { return }
    try {
        $tool = Join-Path $PSScriptRoot 'block-links.ps1'
        if (-not (Test-Path -LiteralPath $tool)) { return }
        $exe = [Environment]::ProcessPath
        if (-not $exe) { $exe = 'pwsh' }
        $moved = ($OldStatus -cne $NewStatus)
        if ($NewStatus -ceq 'BlockByOtherTask' -and ($moved -or $NoteChanged)) {
            $argv = @('-NoProfile', '-File', $tool, '-Link', '-Id', $Id)
            if ($OldStatus -and $OldStatus -notlike 'Block*' -and $OldStatus -cne 'Archived') { $argv += @('-Was', $OldStatus) }
            & $exe @argv | ForEach-Object { Write-Host $_ }
        }
        if ($moved) {
            $rec = Find-Record -Id $Id
            if ($null -eq $rec) { return }
            $fileProp = $rec.PSObject.Properties['file']
            if ($null -eq $fileProp -or -not $fileProp.Value) { return }
            $path = Resolve-SpecPath -PathRef ([string]$fileProp.Value)
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return }
            $text = [IO.File]::ReadAllText($path)
            # Cheap pre-check: an open line is a `- Blocks:` line without `released:` under the section heading.
            if ($text -notmatch '(?m)^##[ \t]+Blocked tickets[ \t]*\r?$') { return }
            if ($text -notmatch '(?m)^[ \t]*-[ \t]+Blocks:(?![^\r\n]*\|[ \t]*released:)') { return }
            & $exe -NoProfile -File $tool -Release -Id $Id | ForEach-Object { Write-Host $_ }
        }
    }
    catch {
        Write-Host ("block-links: skipped after {0}: {1}" -f $Id, $_.Exception.Message) -ForegroundColor Yellow
    }
}
