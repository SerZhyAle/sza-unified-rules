# The picker adapter: asks one repository's own authority for its head (TASK-FLOW rules 18, 22, 29 and 43; S0015 R2).
#
# Dot-source this file; it defines functions only, sets no preference and prints nothing. State: none.
# Everything here is read-only: the shipped picker runs with -NoDrift and never with its claim switch (a dispatcher
# worker claims through the repository's own runner), in a child process whose environment alone carries
# SZA_PROJECT_ROOT and from which every <NAME>_AGENT_ID is removed (rule 29: a dispatcher started from an agent
# session must not make that session's leases look like its own).
#
#   Invoke-PqPicker -RepoPath <dir> [-Exclude <string[]>] [-TimeoutSeconds <int>] [-HarnessRoot <dir>]
#                   [-ScriptPath <file>]
#       @{ ok; payload; code; error; ms }: error PickerFailed (non-zero exit, nothing parseable; message holds the
#       first 300 characters of stderr) or PickerTimeout (the child and its tree are killed). Never throws.
#   Get-PqPickerHead -RepoPath [-Exclude] [-ForceId <id>] [-HarnessRoot] [-TimeoutSeconds]
#       @{ ok; head; payload; why; error; ms }. Without -ForceId head is payload.selected. With it, head is that
#       ticket when the picker would offer it once the ids ranked above it are excluded, else $null and why is
#       leased, excluded, notRanked, malformed or the picker's auto-skip reason.
#   Get-PqTicketRecord -RepoPath -Id [-HarnessRoot]
#       the ledger record (archive included) through select.ps1, or $null.
#
# Cost: one child process per call, two for a -ForceId that is not the head (S0015 Phase 02 evidence,
# picker-latency.json).

function Get-PqHarnessRoot([string]$HarnessRoot) {
    if ($HarnessRoot) { return $HarnessRoot }
    return [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
}

# Runs `pwsh -NoProfile -File <Script> @Arguments` for one repository. Returns @{ code; stdout; stderr; timedOut; ms }.
function Invoke-PqRepoChild {
    param([string]$RepoPath, [string]$Script, [string[]]$Arguments, [int]$TimeoutSeconds = 300)
    $pwsh = (Get-Command pwsh -CommandType Application | Select-Object -First 1).Source
    $psi = [Diagnostics.ProcessStartInfo]::new($pwsh)
    foreach ($a in (@('-NoProfile', '-File', $Script) + @($Arguments))) { $psi.ArgumentList.Add([string]$a) }
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.WorkingDirectory = $RepoPath
    $psi.Environment['SZA_PROJECT_ROOT'] = $RepoPath
    [void]$psi.Environment.Remove('SZA_PROFILE_PATH')
    foreach ($name in @($psi.Environment.Keys)) {
        if ($name -cmatch '^[A-Z0-9]+_AGENT_ID$') { [void]$psi.Environment.Remove($name) }
    }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $proc = [Diagnostics.Process]::Start($psi)
    $out = $proc.StandardOutput.ReadToEndAsync()
    $err = $proc.StandardError.ReadToEndAsync()
    if (-not $proc.WaitForExit($TimeoutSeconds * 1000)) {
        $null = & taskkill.exe /PID $proc.Id /T /F 2>&1
        $null = $proc.WaitForExit(10000)
        $sw.Stop()
        return @{ code = $null; stdout = ''; stderr = ''; timedOut = $true; ms = [int]$sw.ElapsedMilliseconds }
    }
    $proc.WaitForExit()
    $sw.Stop()
    return @{ code = $proc.ExitCode; stdout = $out.Result; stderr = $err.Result; timedOut = $false; ms = [int]$sw.ElapsedMilliseconds }
}

function ConvertFrom-PqLastJsonLine([string]$Text, [switch]$Array) {
    $start = if ($Array) { '[' } else { '{' }
    $lines = @($Text -split '\r?\n' | Where-Object { $_.Trim().Length -gt 0 })
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        $l = $lines[$i].Trim()
        if (-not $l.StartsWith($start)) { continue }
        try { return @{ ok = $true; value = (ConvertFrom-Json -InputObject $l -DateKind String -NoEnumerate) } } catch { }
    }
    return @{ ok = $false; value = $null }
}

function Invoke-PqPicker {
    param(
        [Parameter(Mandatory)][string]$RepoPath,
        [string[]]$Exclude,
        [int]$TimeoutSeconds = 300,
        [string]$HarnessRoot,
        [string]$ScriptPath
    )
    $HarnessRoot = Get-PqHarnessRoot $HarnessRoot
    if (-not $ScriptPath) { $ScriptPath = Join-Path $HarnessRoot 'spec_catalog\spec-next-preflight.ps1' }
    # Read-only: -NoDrift, and never the picker's claim switch (R2).
    $arguments = @('-NoDrift', '-Format', 'json')
    $ids = @(@($Exclude) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($ids.Count -gt 0) { $arguments += @('-Exclude', ($ids -join ',')) }
    try { $r = Invoke-PqRepoChild -RepoPath $RepoPath -Script $ScriptPath -Arguments $arguments -TimeoutSeconds $TimeoutSeconds }
    catch { return @{ ok = $false; payload = $null; code = $null; error = 'PickerFailed'; message = $_.Exception.Message; ms = 0 } }
    if ($r.timedOut) { return @{ ok = $false; payload = $null; code = $null; error = 'PickerTimeout'; message = "the picker outlived $TimeoutSeconds s and was killed"; ms = $r.ms } }
    $stderr = [string]$r.stderr
    if ($stderr.Length -gt 300) { $stderr = $stderr.Substring(0, 300) }
    $parsed = ConvertFrom-PqLastJsonLine $r.stdout
    if ($r.code -ne 0 -or -not $parsed.ok) {
        return @{ ok = $false; payload = $null; code = $r.code; error = 'PickerFailed'; message = $stderr; ms = $r.ms }
    }
    return @{ ok = $true; payload = $parsed.value; code = $r.code; error = $null; message = $null; ms = $r.ms }
}

function Get-PqPayloadIds($Items) {
    return @(foreach ($x in @($Items)) {
            if ($null -eq $x) { continue }
            if ($x -is [string]) { $x } elseif ($null -ne $x.PSObject.Properties['id']) { [string]$x.id }
        })
}

function Get-PqAutoSkipReason($Payload, [string]$Id) {
    foreach ($s in @($Payload.auto_skipped)) {
        if ($null -ne $s -and [string]$s.id -ceq $Id) { return [string]$s.reason }
    }
    return $null
}

function Get-PqPickerHead {
    param(
        [Parameter(Mandatory)][string]$RepoPath,
        [string[]]$Exclude,
        [string]$ForceId,
        [string]$HarnessRoot,
        [int]$TimeoutSeconds = 300
    )
    $first = Invoke-PqPicker -RepoPath $RepoPath -Exclude $Exclude -HarnessRoot $HarnessRoot -TimeoutSeconds $TimeoutSeconds
    if (-not $first.ok) { return @{ ok = $false; head = $null; payload = $null; why = 'pickerFailed'; error = $first.error; ms = $first.ms } }
    $payload = $first.payload
    if (-not $ForceId) { return @{ ok = $true; head = $payload.selected; payload = $payload; why = $null; error = $null; ms = $first.ms } }
    $ms = $first.ms
    if ($null -ne $payload.selected -and [string]$payload.selected.id -ceq $ForceId) {
        return @{ ok = $true; head = $payload.selected; payload = $payload; why = $null; error = $null; ms = $ms }
    }
    if ((Get-PqPayloadIds $payload.leased_ids) -ccontains $ForceId) { return @{ ok = $true; head = $null; payload = $payload; why = 'leased'; error = $null; ms = $ms } }
    if ((Get-PqPayloadIds $payload.excluded_ids) -ccontains $ForceId) { return @{ ok = $true; head = $null; payload = $payload; why = 'excluded'; error = $null; ms = $ms } }
    $ranked = Get-PqPayloadIds $payload.ranked
    $at = [array]::IndexOf([string[]]$ranked, $ForceId)
    if ($at -lt 0) {
        $why = if ((Get-PqPayloadIds $payload.malformed) -ccontains $ForceId) { 'malformed' } else { 'notRanked' }
        return @{ ok = $true; head = $null; payload = $payload; why = $why; error = $null; ms = $ms }
    }
    $above = if ($at -gt 0) { $ranked[0..($at - 1)] } else { @() }
    $second = Invoke-PqPicker -RepoPath $RepoPath -Exclude (@($Exclude) + @($above)) -HarnessRoot $HarnessRoot -TimeoutSeconds $TimeoutSeconds
    $ms += $second.ms
    if (-not $second.ok) { return @{ ok = $false; head = $null; payload = $payload; why = 'pickerFailed'; error = $second.error; ms = $ms } }
    $p2 = $second.payload
    if ($null -ne $p2.selected -and [string]$p2.selected.id -ceq $ForceId) {
        return @{ ok = $true; head = $p2.selected; payload = $payload; why = $null; error = $null; ms = $ms }
    }
    $why = Get-PqAutoSkipReason $p2 $ForceId
    if (-not $why) { $why = Get-PqAutoSkipReason $payload $ForceId }
    if (-not $why) { $why = if ((Get-PqPayloadIds $p2.malformed) -ccontains $ForceId) { 'malformed' } else { 'notOffered' } }
    return @{ ok = $true; head = $null; payload = $payload; why = $why; error = $null; ms = $ms }
}

function Get-PqTicketRecord {
    param([Parameter(Mandatory)][string]$RepoPath, [Parameter(Mandatory)][string]$Id, [string]$HarnessRoot, [int]$TimeoutSeconds = 120)
    $HarnessRoot = Get-PqHarnessRoot $HarnessRoot
    $script = Join-Path $HarnessRoot 'spec_catalog\select.ps1'
    try { $r = Invoke-PqRepoChild -RepoPath $RepoPath -Script $script -Arguments @('-Id', $Id, '-IncludeArchived', '-Format', 'json') -TimeoutSeconds $TimeoutSeconds }
    catch { return $null }
    if ($r.timedOut -or $r.code -ne 0) { return $null }
    $text = ([string]$r.stdout).Trim()
    if ($text.Length -eq 0) { return $null }
    try { $value = ConvertFrom-Json -InputObject $text -DateKind String -NoEnumerate } catch { return $null }
    foreach ($x in @($value)) { if ($null -ne $x -and [string]$x.id -ceq $Id) { return $x } }
    return $null
}
