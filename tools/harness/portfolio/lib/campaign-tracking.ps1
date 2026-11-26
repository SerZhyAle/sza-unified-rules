function Invoke-CampaignCheck([string] $Executable, [string] $Check, [string] $Root) {
    $start = [Diagnostics.ProcessStartInfo]::new($Executable)
    $start.UseShellExecute = $false
    $start.WorkingDirectory = $Root
    $start.Environment['SZA_PROJECT_ROOT'] = $Root
    foreach ($argument in @('-NoProfile', '-NonInteractive', '-File', $Check)) {
        $start.ArgumentList.Add($argument)
    }

    $process = [Diagnostics.Process]::Start($start)
    try {
        if (-not $process.WaitForExit(5000)) {
            try { $process.Kill($true) }
            catch [InvalidOperationException] { if (-not $process.HasExited) { throw } }
            $process.WaitForExit()
            return 124
        }
        return $process.ExitCode
    }
    finally { $process.Dispose() }
}

function ConvertTo-CampaignTable($Rows) {
    $lines = @(
        '## Campaign checklist'
        ''
        '| Repo | Needs work? | Check | Done |'
        '| --- | --- | --- | --- |'
    )
    foreach ($row in $Rows) {
        $lines += "| $($row.key) | $($row.work) | $($row.check) | $($row.done) |"
    }
    return $lines
}

function Read-CampaignTable([string] $Body) {
    $section = [regex]::Match($Body, '(?m)^## Campaign checklist\r?\n(?:\r?\n)?\| Repo \| Needs work\? \| Check \| Done \|\r?\n\| --- \| --- \| --- \| --- \|(?:\r?\n\|[^\r\n]*)+')
    if (-not $section.Success) { throw 'The spec has no campaign checklist table.' }
    foreach ($line in ($section.Value -split '\r?\n' | Select-Object -Skip 4)) {
        if ($line -notmatch '^\| ([a-zA-Z0-9-]+) \| (yes|no|unknown) \| (PASS|FAIL|pending) \| (yes|no|no \([a-zA-Z0-9:_-]+\)|yes \([a-zA-Z0-9:_-]+\)) \|$') {
            throw "Invalid campaign checklist row: $line"
        }
        [pscustomobject]@{ key = $Matches[1]; work = $Matches[2]; check = $Matches[3]; done = $Matches[4] }
    }
}

function Write-CampaignTable([string] $Path, $Rows, [switch] $Create, [string] $ExpectedBody) {
    $pathKey = [IO.Path]::GetFullPath($Path)
    if ($IsWindows) { $pathKey = $pathKey.ToUpperInvariant() }
    $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($pathKey)))
    $mutex = [Threading.Mutex]::new($false, "sza-campaign-$hash")
    $held = $false
    $temporary = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        try { $held = $mutex.WaitOne(1000) }
        catch [Threading.AbandonedMutexException] { $held = $true }
        if (-not $held) { throw 'Another campaign update is writing the spec. Retry the check.' }
        $reader = [IO.StreamReader]::new($Path, [Text.UTF8Encoding]::new($false), $true)
        try { $body = $reader.ReadToEnd(); $encoding = $reader.CurrentEncoding }
        finally { $reader.Dispose() }
        if ($PSBoundParameters.ContainsKey('ExpectedBody') -and $body -cne $ExpectedBody) {
            throw 'The spec changed while checks ran. Retry the check.'
        }
        $eol = if ($body.Contains("`r`n")) { "`r`n" } else { "`n" }
        $table = (ConvertTo-CampaignTable $Rows) -join $eol
        if ($Create) {
            if ($body -match '(?m)^## Campaign checklist\r?$') { throw 'The spec already has a campaign checklist.' }
            $updated = $body + $eol + $table + $eol
        }
        else {
            [void]@(Read-CampaignTable $body)
            $pattern = [regex]::new('(?m)^## Campaign checklist\r?\n(?:\r?\n)?(?:\|[^\r\n]*(?:\r?\n|\z))+')
            $updated = $pattern.Replace($body, [Text.RegularExpressions.MatchEvaluator]{ param($match) $table + $eol }, 1)
        }
        [IO.File]::WriteAllText($temporary, $updated, $encoding)
        if ([IO.File]::ReadAllText($Path) -cne $body) { throw 'The spec changed while checks ran. Retry the check.' }
        [IO.File]::Move($temporary, $Path, $true)
    }
    finally {
        try { [IO.File]::Delete($temporary) }
        finally {
            if ($held) { $mutex.ReleaseMutex() }
            $mutex.Dispose()
        }
    }
}

function Set-CampaignCheckResult($Row, [int] $Code) {
    $child = $Row.done -replace '^(?:yes|no)', ''
    $Row.check = if ($Code -eq 0) { 'PASS' } else { 'FAIL' }
    if ($Code -eq 1) { $Row.work = 'yes' }
    if ($Code -eq 0 -and $Row.work -eq 'unknown') { $Row.work = 'no' }
    if ($Code -eq 0) { $Row.done = "yes$child" }
    else { $Row.done = "no$child" }
}

function Update-CampaignChecks($Rows, $Repos, [string] $Executable, [string] $Check) {
    $failed = $false
    foreach ($row in $Rows) {
        $target = $Repos | Where-Object key -ceq $row.key
        try {
            if (-not $target) { throw 'repository is no longer registered' }
            $code = Invoke-CampaignCheck $Executable $Check $target.path
        }
        catch {
            Write-Host "$($row.key): $($_.Exception.Message)"
            $code = 125
        }
        Set-CampaignCheckResult $row $code
        Write-Host "$($row.check) $($row.key) (exit $code)"
        if ($code -ne 0) { $failed = $true }
    }
    return $failed
}
