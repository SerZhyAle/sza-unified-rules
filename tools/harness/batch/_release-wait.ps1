# The release wait of a ticket (TASK-FLOW 0.24, rule 67).
#
# Dot-sourced, never invoked. Holds one process-scope cache and nothing else mutable.
#
# THE PROBLEM IT ANSWERS. An audit is static and re-derives its verdict from the spec and the files,
# so a second audit of the same files cannot say anything the first did not. A ticket whose audit
# left nothing but release-tier work (FAIL 0, WARN 0, RELEASE >= 1) is still `Implemented` - the
# 5-second line forbids the runs that would move it - and the picker offered it again anyway. On
# 2026-11-12 four StreamsPlayer tickets cost about 4.2 USD in eight such passes before the idle hold
# (batch/_idle-runs.ps1) stopped each of them after two.
#
# THE SHAPE. The runner stamps the code tree after a pass that ended in that state and writes the
# stamp into the pass's journal row (`awaitsRelease`). The picker withholds the ticket while the
# stamp taken now equals the newest row's - and offers it again the moment the tree differs, because
# a changed tree is what a new audit can legitimately find. Nothing is stored beside the journal.
#
# THE STAMP ERRS TOWARDS "CHANGED". It is equal for two readings only when this code can tell the
# code tree did not move. No git, not a work tree, a failed call -> no stamp at all, so no row
# carries the field and nothing is held. A path no `locks.pathRules` rule names stays in the stamp.
# The only files left out are the ones the project's own rules exempt from a code domain (by
# default `PLAN/`: tickets, queue files and the ledger, which every pass writes).
#
# Compatible with PowerShell 5.1 and 7+, and safe to load under Set-StrictMode Latest.

. (Join-Path $PSScriptRoot '..\_profile.ps1')
. (Join-Path $PSScriptRoot '..\spec_catalog\_research-items.ps1')
. (Join-Path $PSScriptRoot '..\locks\agent-lock-domains.ps1')

$script:CodeTreeStampCache = $null

function Get-AuditCounts {
    <#
    .SYNOPSIS
        The numbers of a ticket's `**Counts:**` line, or $null when they cannot be read.
    .DESCRIPTION
        The line the audit writes in the `## Last Audit` block (skills/spec-to-audit/references/
        audit-verdict.md): `PASS n | WARN n | FAIL n | MANUAL n | UNCHECKABLE n | EXEMPT n | RELEASE n`.
        Read from the FIRST such line of the block. A block without the line, a line that lacks WARN,
        FAIL or RELEASE, or a file that cannot be read all answer $null - unknown, which no caller
        may take for "nothing is open".
    #>
    param([Parameter(Mandatory)][string] $SpecPath)
    $abs = Resolve-ResearchSpecPath -PathRef $SpecPath
    if (-not (Test-Path -LiteralPath $abs -PathType Leaf)) { return $null }
    $lines = @()
    try { $lines = @(Get-Content -LiteralPath $abs -Encoding UTF8 -ErrorAction Stop) } catch { return $null }
    $section = @(Get-SpecSectionLines -Lines $lines -HeadingPattern (Get-AuditSectionHeadingPattern))
    foreach ($entry in $section) {
        if ($entry.Text -notmatch '(?i)^\s*(?:[-*]\s+)?\*{0,2}Counts\s*:\*{0,2}\s*(?<rest>.+)$') { continue }
        $counts = @{}
        foreach ($m in [regex]::Matches($Matches['rest'], '(?i)\b(PASS|WARN|FAIL|MANUAL|UNCHECKABLE|EXEMPT|RELEASE)\s*[:=]?\s*(\d+)')) {
            $counts[$m.Groups[1].Value.ToUpperInvariant()] = [int] $m.Groups[2].Value
        }
        if ($counts.ContainsKey('FAIL') -and $counts.ContainsKey('WARN') -and $counts.ContainsKey('RELEASE')) { return $counts }
        return $null
    }
    return $null
}

function Test-AuditReleaseOnly {
    <#
    .SYNOPSIS
        True when the audit left nothing a robot can work: FAIL 0, WARN 0, RELEASE of at least one.
    .DESCRIPTION
        MANUAL and UNCHECKABLE do not lift the answer: a robot can close neither, so a re-audit
        cannot either. A WARN is a robot's work (a Partial's fix pass), and a FAIL even more so.
    #>
    param([Parameter(Mandatory)][string] $SpecPath)
    $counts = Get-AuditCounts -SpecPath $SpecPath
    if ($null -eq $counts) { return $false }
    return ($counts['FAIL'] -eq 0 -and $counts['WARN'] -eq 0 -and $counts['RELEASE'] -ge 1)
}

function Invoke-ReleaseWaitGit {
    # One git call, stdout decoded as UTF-8 whatever the console code page is (a path with a
    # non-ASCII letter must come back as the file's real name, or its length and time are never read
    # and a change to it is invisible - the unsafe direction). $null on any failure.
    param([Parameter(Mandatory)][string] $Root, [Parameter(Mandatory)][string] $Arguments)
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = 'git'
        $psi.Arguments = $Arguments
        $psi.WorkingDirectory = $Root
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
        $process = [System.Diagnostics.Process]::Start($psi)
        $errTask = $process.StandardError.ReadToEndAsync()
        $out = $process.StandardOutput.ReadToEnd()
        $process.WaitForExit()
        [void] $errTask.Result
        if ($process.ExitCode -ne 0) { return $null }
        return $out
    } catch {
        return $null
    }
}

function Get-CodeTreeStamp {
    <#
    .SYNOPSIS
        An opaque stamp of the project's code tree, or $null when none can be taken.
    .DESCRIPTION
        `git1:` + SHA-1 over the commit HEAD and, for every file git lists as modified or untracked
        and not ignored, its path, length and last write time - except the files the project's own
        locks.pathRules exempt from a code domain. Length and time, not content: a file touched
        without a change reads as changed, which only ever offers a ticket one more time.
        -Refresh re-reads; without it the first reading of this process is reused, which is right
        for a picker (one ranking, one process) and wrong for the runner, whose pass just ended.
    #>
    param([string] $Root = '', [switch] $Refresh)
    try {
        if ([string]::IsNullOrWhiteSpace($Root)) { $Root = (Get-SzaProjectRoot) }
        if (-not $Refresh -and $null -ne $script:CodeTreeStampCache -and $script:CodeTreeStampCache.Root -eq $Root) {
            return $script:CodeTreeStampCache.Stamp
        }
        $stamp = $null
        $head = Invoke-ReleaseWaitGit -Root $Root -Arguments 'rev-parse HEAD'
        $listing = $null
        if ($null -ne $head) {
            $listing = Invoke-ReleaseWaitGit -Root $Root -Arguments '-c core.quotepath=off ls-files -m -o --exclude-standard -z'
        }
        if ($null -ne $head -and $null -ne $listing) {
            $rows = New-Object System.Collections.Generic.List[string]
            foreach ($path in ($listing -split "`0")) {
                if ([string]::IsNullOrWhiteSpace($path)) { continue }
                if (Test-AgentLockPathExempt -Path $path) { continue }
                $info = New-Object System.IO.FileInfo (Join-Path $Root $path)
                if ($info.Exists) {
                    $rows.Add(('{0}|{1}|{2}' -f $path, $info.Length, $info.LastWriteTimeUtc.Ticks))
                } else {
                    $rows.Add(('{0}|gone' -f $path))
                }
            }
            $sorted = $rows.ToArray()
            [System.Array]::Sort($sorted, [System.StringComparer]::Ordinal)
            $text = $head.Trim() + "`n" + ($sorted -join "`n")
            $sha = [System.Security.Cryptography.SHA1]::Create()
            try {
                $hash = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($text))
            } finally {
                $sha.Dispose()
            }
            $stamp = 'git1:' + (($hash | ForEach-Object { $_.ToString('x2') }) -join '')
        }
        $script:CodeTreeStampCache = [pscustomobject]@{ Root = $Root; Stamp = $stamp }
        return $stamp
    } catch {
        return $null
    }
}

function Get-AwaitsReleaseStamp {
    <#
    .SYNOPSIS
        What the runner writes as `awaitsRelease` for a pass that has just ended: the tree stamp when
        the ticket ended at Implemented with nothing left but release work, else ''.
    #>
    param([Parameter(Mandatory)][string] $SpecPath, [Parameter(Mandatory)][AllowEmptyString()][string] $StatusAfter)
    if ($StatusAfter -cne 'Implemented') { return '' }
    if (-not (Test-AuditReleaseOnly -SpecPath $SpecPath)) { return '' }
    $stamp = Get-CodeTreeStamp -Refresh
    if ([string]::IsNullOrWhiteSpace($stamp)) { return '' }
    return $stamp
}

function Test-AwaitsRelease {
    <#
    .SYNOPSIS
        True when the picker must withhold this ticket: it is Implemented, its newest journal row
        stamped a tree, the audit still reads as release-only, and the tree is the one stamped.
    .PARAMETER RecordedStamp
        The `awaitsRelease` of the ticket's newest journal row (Get-IdleRunSeries .LastAwaitsRelease).
    #>
    param(
        [Parameter(Mandatory)][string] $SpecPath,
        [Parameter(Mandatory)][AllowEmptyString()][string] $Status,
        [AllowEmptyString()][string] $RecordedStamp = '',
        # Re-read the tree instead of reusing this process's first reading (see Get-CodeTreeStamp).
        [switch] $Refresh
    )
    if ($Status -cne 'Implemented') { return $false }
    if ([string]::IsNullOrWhiteSpace($RecordedStamp)) { return $false }
    if (-not (Test-AuditReleaseOnly -SpecPath $SpecPath)) { return $false }
    $now = Get-CodeTreeStamp -Refresh:$Refresh
    if ([string]::IsNullOrWhiteSpace($now)) { return $false }
    return ($now -ceq $RecordedStamp)
}
