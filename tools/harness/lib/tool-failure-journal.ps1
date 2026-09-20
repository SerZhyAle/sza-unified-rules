#requires -Version 7.0
<#
.SYNOPSIS
    The record behind a harness script's refusal - one row per refusing invocation.

.DESCRIPTION
    A tool result scrolls out of an agent's reach within a turn or two, so "what did that command
    actually say" stops being answerable moments after it is worth asking. The consuming project
    that raised this measured the shape of the gap: its gate-execution journal held 189 116 rows
    and 187 red verdicts over two days, written by three gate runners and read by nobody, while
    every harness CLI - the spec catalogue, the document registry, the ledger - left no trace at
    all when it refused. A refusal that leaves no record is a refusal nobody can look at a minute
    later, which is what makes it walkable-past.

    This library is the harness half of the cure. The project half is a hook that records a red
    exit from any script; this one records the refusals the harness itself issues, with the reason
    the CLI printed rather than merely the code. Both write the same row shape into the same
    journal, so one reader answers for both.

    Two properties are deliberate, and both are about not becoming the problem:

      1. Every IO operation is swallowed. A journal that throws would turn a mutator's own refusal
         into a second, unrelated failure inside the recorder that was only trying to note the
         first - and the refusal, which is the thing the operator has to read, would be buried.
      2. The file is trimmed to its last 500 rows on every write. The journal this one sits beside
         reached 30 MB unattended in the raising project; a record nobody prunes becomes a cost
         rather than an answer, and 500 rows is far more than one session's worth of refusals.

    The journal path is resolved from the CONSUMING project's root through `paths.toolFailures`,
    never from the harness root. A harness copy is shared by every project on the machine and
    lives in a versioned plugin cache: a journal beside it would mix several projects' refusals
    into one file and lose them all at the next plugin update.

.NOTES
    Dot-sourced library. It defines two functions and assigns nothing at script scope, because a
    dot-sourced file assigns into its CALLER's scope, where a stray variable collides with the
    caller's own parameters.

    Requires `_profile.ps1` to have been dot-sourced first - the caller is a harness script, which
    always has.

    Exit codes: none of its own. Dot-sourcing defines the functions and returns.
#>

function Get-SzaToolFailureJournalPath {
    <#
    .SYNOPSIS
        Absolute path of the failing-invocation journal for the consuming project.
    #>
    return (Get-SzaPath 'toolFailures')
}

function Write-SzaToolFailureRecord {
    <#
    .SYNOPSIS
        Appends one row describing a refusing invocation, then trims the journal.

    .PARAMETER Tool
        What produced the row - the harness cluster or the tool that ran the command.

    .PARAMETER Command
        The command line as invoked, so a later reader can recognise and re-run it.

    .PARAMETER ExitCode
        The code the invocation returned or is about to return. The caller decides which codes are
        worth recording; this writer records whatever it is handed.

    .PARAMETER OutputTail
        What the invocation printed. Kept from the END - a script states its reason last, right
        before it exits, so the tail is the half that carries the refusal.

    .PARAMETER WorkingDirectory
        Where the command ran. A relative path in the command line means nothing without it.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Tool,
        [Parameter(Mandatory = $true)][string]$Command,
        [Parameter(Mandatory = $true)][int]$ExitCode,
        [string]$OutputTail,
        [string]$WorkingDirectory
    )

    $maxOutputChars = 2000
    $maxRows = 500

    try {
        $path = Get-SzaToolFailureJournalPath
        $directory = Split-Path -Parent $path
        [System.IO.Directory]::CreateDirectory($directory) | Out-Null

        $tail = if ($OutputTail) { $OutputTail } else { '' }
        if ($tail.Length -gt $maxOutputChars) {
            $tail = $tail.Substring($tail.Length - $maxOutputChars)
        }

        $cwd = if ($WorkingDirectory) { $WorkingDirectory } else { (Get-Location).Path }

        $record = [ordered]@{
            timestampUtc = [DateTime]::UtcNow.ToString('o')
            sessionId    = [string]$env:CLAUDE_CODE_SESSION_ID
            tool         = $Tool
            command      = $Command
            exitCode     = $ExitCode
            outputTail   = $tail
            cwd          = [string]$cwd
        }

        [System.IO.File]::AppendAllText(
            $path,
            (($record | ConvertTo-Json -Compress) + [Environment]::NewLine)
        )

        $lines = [System.IO.File]::ReadAllLines($path)
        if ($lines.Length -gt $maxRows) {
            [System.IO.File]::WriteAllLines($path, $lines[($lines.Length - $maxRows)..($lines.Length - 1)])
        }
    }
    catch {
        # Recording a refusal must never become a second failure: the caller is already reporting
        # something that went wrong, and throwing here would bury the reason it printed.
    }
}
