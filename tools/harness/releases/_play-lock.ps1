#requires -Version 7.0
<#
.SYNOPSIS
    The per-application Play lock of the release ledger's Play probe (GOOGLE-PLAY rule 19, canon ticket CANONR-0174).

.DESCRIPTION
    Google Play keeps one open edit per application, and a second `edits.insert` for the same application deletes the
    first. A product's publisher therefore holds a lock for its application id for as long as its edit lives, and any
    other process that opens an edit for that id - the release ledger's Play probe included - has to take the same lock
    first or stay out.

    The lock is the convention the product publishers already use, so the probe serializes with them without a change in
    any product:

        <repository root>/<paths.tempDir>/play-lock/<applicationId>.lock

    `paths.tempDir` is the repository's own profile value, read as written (HARNESS-PROFILE; the shipped default is `temp`).
    The publishers written so far hard-code `temp`, which is the value every profile in the portfolio keeps; a profile that
    moves the folder moves this lock with it, and its publisher has to follow. The lock is an open file handle
    (`FileMode.OpenOrCreate`, `FileAccess.ReadWrite`, `FileShare.None`): the operating system refuses every second open
    while the handle lives and drops it when the process ends, so a crashed run leaves no stale lock. The file stays on
    disk between runs; its text (`pid N since <time> (<who>)`) is a note for a person and cannot be read while the lock is
    held.

    Enter-RlPlayAppLock makes one try and never waits: a probe is a read that can be run again, and a wait would only stall
    the release flow that called it. It covers one machine and one checkout - a second checkout of the same repository has
    its own folder, and a Console write by a person is not a process; both stay the product's own serialization.

    Needs `_lib.ps1` loaded first (`Get-RlProp`, `ConvertFrom-RlJson` and the shipped profile defaults).

    Exit codes: none - a dot-sourced library.
#>

function Resolve-RlTempDirForRepo {
    # The repository's own paths.tempDir, else the shipped default. The profile is read as written, never through
    # _profile.ps1, which keeps one project per process (the same reading as Resolve-RlDirForRepo).
    param([Parameter(Mandatory)][string]$RepoRoot)
    $rel = [string]$script:RlProfileDefaults.paths.tempDir
    $profilePath = Join-Path $RepoRoot '.sza-profile.json'
    if (Test-Path -LiteralPath $profilePath -PathType Leaf) {
        try {
            $p = ConvertFrom-RlJson (Get-Content -LiteralPath $profilePath -Raw -Encoding utf8)
            $v = [string](Get-RlProp (Get-RlProp $p 'paths') 'tempDir')
            if (-not [string]::IsNullOrWhiteSpace($v)) { $rel = $v }
        } catch {
            Write-Verbose "release-ledger: '$profilePath' does not parse; the default temp folder is used"
        }
    }
    if ([IO.Path]::IsPathRooted($rel)) { return [IO.Path]::GetFullPath($rel) }
    return [IO.Path]::GetFullPath((Join-Path $RepoRoot $rel))
}

function Test-RlApplicationId {
    # An Android application id: two or more dot-separated segments, each a letter then letters, digits or underscores.
    # The id becomes a file name, so anything else (a path separator, `..`, a drive) is refused here.
    param([AllowNull()][AllowEmptyString()][string]$Id)
    return ($Id -cmatch '^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$')
}

function Get-RlPlayLockPath {
    param([Parameter(Mandatory)][string]$RepoRoot, [Parameter(Mandatory)][string]$AppId)
    return [IO.Path]::GetFullPath((Join-Path (Resolve-RlTempDirForRepo -RepoRoot $RepoRoot) (Join-Path 'play-lock' "$AppId.lock")))
}

function Enter-RlPlayAppLock {
    # Returns { held; path; reason; stream }. held = $false means the caller must open no edit; `reason` says why. The
    # caller releases a held lock with Exit-RlPlayAppLock in a finally block.
    param([Parameter(Mandatory)][string]$RepoRoot, [Parameter(Mandatory)][string]$AppId, [string]$Holder = 'release-ledger probe')
    $refused = { param([string]$Why, [string]$Where) [pscustomobject]@{ held = $false; path = $Where; reason = $Why; stream = $null } }
    if (-not (Test-RlApplicationId $AppId)) { return (& $refused "'$AppId' is not an application id" '') }
    $path = Get-RlPlayLockPath -RepoRoot $RepoRoot -AppId $AppId
    try { [void](New-Item -ItemType Directory -Force -Path ([IO.Path]::GetDirectoryName($path))) }
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
