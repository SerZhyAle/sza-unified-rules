#requires -Version 7.0
<#
.SYNOPSIS
    The machine-wide per-application lock of the Play probe (GOOGLE-PLAY 0.5 section 9).

.DESCRIPTION
    The probe and publisher take the same lock across checkouts before opening an edit for an application id. They
    hold it until they commit, delete or abandon the edit. The lock path is shared by all repositories for the OS user.

        Windows  %LOCALAPPDATA%\sza\play-publishing\<applicationId>.lock
        Other    ~/.local/state/sza/play-publishing/<applicationId>.lock

    The probe opens the file with FileMode.OpenOrCreate, FileAccess.ReadWrite and FileShare.None. On Windows the
    no-sharing open also fails while the publisher's byte-lock handle is open. The OS drops the hold when the process
    ends. The file stays on disk between runs, and its holder note is diagnostic only.

    Enter-RlPlayAppLock tries once and reports refusal when it cannot open the file. Tests can set the script-scoped
    RlPlayLockDirOverride after loading the library to isolate their lock files.

    Exit codes: none - a dot-sourced library.
#>

$script:RlPlayLockDirOverride = $null

function Test-RlApplicationId {
    # An Android application id: two or more dot-separated segments, each a letter then letters, digits or underscores.
    # The id becomes a file name, so anything else (a path separator, `..`, a drive) is refused here.
    param([AllowNull()][AllowEmptyString()][string]$Id)
    return ($Id -cmatch '^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+\z')
}

function Get-RlPlayLockPath {
    param([Parameter(Mandatory)][string]$AppId)
    $lockDir = $script:RlPlayLockDirOverride
    if (-not $lockDir) {
        $stateRoot = if ($IsWindows) { $env:LOCALAPPDATA } else { [IO.Path]::Combine($HOME, '.local', 'state') }
        if (-not [IO.Path]::IsPathFullyQualified([string]$stateRoot)) { throw 'the Play state directory is missing or relative' }
        $lockDir = [IO.Path]::Combine($stateRoot, 'sza', 'play-publishing')
    }
    return [IO.Path]::GetFullPath([IO.Path]::Combine($lockDir, "$AppId.lock"))
}

function Enter-RlPlayAppLock {
    # Returns { held; path; reason; stream }. held = $false means the caller must open no edit; `reason` says why. The
    # caller releases a held lock with Exit-RlPlayAppLock in a finally block.
    param([Parameter(Mandatory)][string]$AppId, [string]$Holder = 'release-ledger probe')
    $refused = { param([string]$Why, [string]$Where) [pscustomobject]@{ held = $false; path = $Where; reason = $Why; stream = $null } }
    if (-not (Test-RlApplicationId $AppId)) { return (& $refused "'$AppId' is not an application id" '') }
    try { $path = Get-RlPlayLockPath -AppId $AppId }
    catch { return (& $refused "the lock path cannot be resolved: $($_.Exception.Message)" '') }
    try { [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path)) }
    catch { return (& $refused "the lock folder cannot be created: $($_.Exception.Message)" $path) }
    $stream = $null
    try { $stream = [IO.File]::Open($path, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None) }
    catch [System.IO.IOException] {
        # 32 is ERROR_SHARING_VIOLATION and 33 ERROR_LOCK_VIOLATION: somebody else holds it. Any other I/O error (a path
        # that is too long, a failing disk) is not contention and is worded as what it is.
        if (($_.Exception.HResult -band 0xFFFF) -in 32, 33) { return (& $refused 'another publisher or probe holds it' $path) }
        return (& $refused "the lock file cannot be opened: $($_.Exception.Message)" $path)
    }
    catch { return (& $refused "the lock file cannot be opened: $($_.Exception.Message)" $path) }
    try {
        $note = [Text.Encoding]::UTF8.GetBytes("pid $PID since $([DateTime]::Now.ToString('o')) ($Holder)")
        $stream.SetLength(0); $stream.Write($note, 0, $note.Length); $stream.Flush()
    } catch { Write-Verbose 'the holder note is not written; the lock itself is held' }
    return [pscustomobject]@{ held = $true; path = $path; reason = ''; stream = $stream }
}

function Exit-RlPlayAppLock {
    param($Lock)
    if ($null -ne $Lock -and $null -ne $Lock.stream) {
        try { $Lock.stream.Dispose() } catch { Write-Verbose 'the handle is already closed' }
        $Lock.stream = $null
    }
}
