#requires -Version 7.0
<#
    The suite of S0015 Phase 02: the read side of the portfolio under tools/harness/portfolio - lib/registry.ps1
    (repos.json, TASK-FLOW rules 41, 42 and 60), lib/queue-file.ps1 (PORTFOLIO_QUEUE.md, rules 44 and 64),
    lib/picker.ps1 (one repository's own head, rules 18 and 43), lib/rank.ps1 (the order across repositories and the
    fill policy, rules 45 and 63) and pq.ps1 (the verbs register, list, dry-run, queue, pin, hold, release, doctor).

    What this proves: each documented behaviour, case by case, against throwaway portfolio roots and throwaway
    repositories under the system temp directory. A fixture repository is built by the real
    scaffold/init-task-flow.ps1 and spec_catalog/capture-draft.ps1 (built once per shape, then copied), with a
    hand-written fixture stamp; its PLAN/RELEASE_QUEUE.md is removed unless a case keeps it, so the picker orders
    by the priority fallback of rule 18 and the priorities a case gives decide the head. Every case points
    SZA_PORTFOLIO_ROOT and USERPROFILE at scratch directories and restores them, so no case reads or writes the
    owner's %USERPROFILE%\.sza, and no case reads a real repository.

    What it does not prove: anything a later phase adds (passes, workers, the console), or anything a real agent
    does. No agent is started.

    A case that needs the shared contracts catalog is skipped (SKIP, counted in skipped, not in run) unless
    -CatalogRoot is given. A library that does not exist yet makes its cases FAIL with "library missing: lib/<file>";
    it never aborts the run.

    Exit codes: 0 every case that ran passed; 1 an assertion failed; 2 could not verify (setup failed, or the
    -Case filter matched no case to run).
#>
[CmdletBinding()]
param(
    [string]$SourceRoot = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent),
    # The library directory under test; a negative control points it at a mutated copy.
    [string]$LibRoot,
    # The shared contracts catalog (the directory that holds task-flow\); cases that read it are skipped without it.
    [string]$CatalogRoot,
    # Run only the cases whose name matches this regular expression.
    [Alias('Filter')][string]$Case,
    [switch]$KeepScratch
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $LibRoot) { $LibRoot = Join-Path $SourceRoot 'tools\harness\portfolio\lib' }
$harness = Join-Path $SourceRoot 'tools\harness'
$cliScript = Join-Path $harness 'portfolio\pq.ps1'

$run = 0
$failed = 0
$skipped = 0
$gaps = 0
$setupFailed = $false
$scratch = $null
$savedPortfolioRoot = $env:SZA_PORTFOLIO_ROOT
$savedUserProfile = $env:USERPROFILE
$savedProjectRoot = $env:SZA_PROJECT_ROOT
$savedAgent = $env:SZA_AGENT_ID
$FixtureCache = @{}
$Zeros = '0' * 64

function Assert-That([bool]$Condition, [string]$Reason) { if (-not $Condition) { throw $Reason } }

function New-Scratch([string]$Name = 'case') {
    $dir = Join-Path $script:scratch ($Name + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $dir | Out-Null
    return $dir
}

# The libraries keep their state in $script: variables named Pq*; dot-sourced from a case they land in this suite's
# script scope. Every case starts and ends with none, and an open log stream is disposed first.
function Reset-LibState {
    $logs = Get-Variable -Name PqLogs -Scope Script -ValueOnly -ErrorAction Ignore
    if ($null -ne $logs) {
        foreach ($h in @($logs.Values)) { try { $h.Stream.Dispose() } catch { } }
    }
    Get-Variable -Name 'Pq*' -Scope Script -ErrorAction Ignore | ForEach-Object {
        Remove-Variable -Name $_.Name -Scope Script -Force -ErrorAction Ignore
    }
}

function Test-Case([string]$Name, [scriptblock]$Body) {
    if ($Case -and $Name -notmatch $Case) { return }
    $script:run++
    $guard = New-Scratch 'guard'
    $env:SZA_PORTFOLIO_ROOT = Join-Path $guard 'portfolio'
    $env:USERPROFILE = Join-Path $guard 'home'
    Reset-LibState
    try {
        $null = & $Body
        "OK $Name"
    }
    catch { $script:failed++; "FAIL $Name - $($_.Exception.Message)" }
    finally {
        Reset-LibState
        $env:SZA_PORTFOLIO_ROOT = $savedPortfolioRoot
        $env:USERPROFILE = $savedUserProfile
        $env:SZA_PROJECT_ROOT = $savedProjectRoot
        $env:SZA_AGENT_ID = $savedAgent
    }
}

function Skip-Case([string]$Name, [string]$Reason) {
    if ($Case -and $Name -notmatch $Case) { return }
    $script:skipped++
    "SKIP $Name - $Reason"
}

function Get-LibPath([string]$File) {
    $path = Join-Path $LibRoot $File
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "library missing: lib/$File" }
    return $path
}

# `pwsh -NoProfile -File <script> @Arguments`, waited for; -Environment applies to the child only ($null removes).
function Invoke-Child([string]$Script, [string[]]$Arguments = @(), [hashtable]$Environment = @{}, [int]$TimeoutSeconds = 300, [string]$WorkingDirectory) {
    $psi = [System.Diagnostics.ProcessStartInfo]::new((Get-Command pwsh -CommandType Application | Select-Object -First 1).Source)
    foreach ($a in (@('-NoProfile', '-File', $Script) + $Arguments)) { $psi.ArgumentList.Add($a) }
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    if ($WorkingDirectory) { $psi.WorkingDirectory = $WorkingDirectory }
    foreach ($k in $Environment.Keys) {
        if ($null -eq $Environment[$k]) { [void]$psi.Environment.Remove($k) } else { $psi.Environment[$k] = [string]$Environment[$k] }
    }
    $proc = [System.Diagnostics.Process]::Start($psi)
    $out = $proc.StandardOutput.ReadToEndAsync()
    $err = $proc.StandardError.ReadToEndAsync()
    if (-not $proc.WaitForExit($TimeoutSeconds * 1000)) {
        try { $proc.Kill($true) } catch { }
        throw "child timed out after $TimeoutSeconds s: $Script"
    }
    $proc.WaitForExit()
    return @{ code = $proc.ExitCode; stdout = $out.Result; stderr = $err.Result; output = ($out.Result + $err.Result).Trim() }
}

# A harness tool run against one repository, SZA_PROJECT_ROOT on the child only; throws on a non-zero exit.
function Invoke-Tool([string]$Project, [string]$Tool, [string[]]$ToolArgs = @(), [hashtable]$Environment = @{}, [switch]$AllowFail) {
    $envs = @{ SZA_PROJECT_ROOT = $Project }
    foreach ($k in $Environment.Keys) { $envs[$k] = $Environment[$k] }
    $r = Invoke-Child (Join-Path $harness $Tool) $ToolArgs $envs 300 $Project
    if (-not $AllowFail -and $r.code -ne 0) { throw "$Tool $($ToolArgs -join ' ') exited $($r.code): $($r.output)" }
    return $r
}

# pq.ps1 in a child process with SZA_PORTFOLIO_ROOT set on the child.
function Invoke-Pq([string[]]$PqArgs, [hashtable]$Environment = @{}) {
    $envs = @{ SZA_PORTFOLIO_ROOT = $env:SZA_PORTFOLIO_ROOT; USERPROFILE = $env:USERPROFILE }
    foreach ($k in $Environment.Keys) { $envs[$k] = $Environment[$k] }
    return (Invoke-Child $cliScript $PqArgs $envs 600)
}

function Write-Text([string]$Path, [string]$Text, [switch]$Bom) {
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($Text)
    if ($Bom) { $bytes = [byte[]](@(0xEF, 0xBB, 0xBF) + $bytes) }
    [IO.File]::WriteAllBytes($Path, $bytes)
}

function Write-Json([string]$Path, $Object) { Write-Text $Path ((ConvertTo-Json -InputObject $Object -Depth 32) + "`n") }

function Get-Sha([string]$Path) { return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([IO.File]::ReadAllBytes($Path))).ToLowerInvariant() }

# Every file under the given directories: relative path, size, SHA-256 and write time; directories as names.
function Get-TreeHash([string[]]$Dirs) {
    $rows = foreach ($d in $Dirs) {
        if (-not (Test-Path -LiteralPath $d)) { "$d|absent"; continue }
        Get-ChildItem -LiteralPath $d -Recurse -Force | Sort-Object FullName | ForEach-Object {
            if ($_.PSIsContainer) { "$($_.FullName)|dir" }
            else { "$($_.FullName)|$($_.Length)|$(Get-Sha $_.FullName)|$($_.LastWriteTimeUtc.Ticks)" }
        }
    }
    return (@($rows) -join "`n")
}

function Get-Listing([string]$Dir) {
    if (-not (Test-Path -LiteralPath $Dir)) { return '' }
    return (@(Get-ChildItem -LiteralPath $Dir -Recurse -Force | Sort-Object FullName | ForEach-Object {
                $len = if ($_.PSIsContainer) { 'dir' } else { [string]$_.Length }
                "$($_.FullName)|$len|$($_.LastWriteTimeUtc.Ticks)"
            }) -join "`n")
}

# The complete lines of every event file under <root>\log, parsed (ts stays a string).
function Get-RootEvents([string]$Root) {
    $dir = Join-Path $Root 'log'
    if (-not (Test-Path -LiteralPath $dir)) { return @() }
    $events = foreach ($f in @(Get-ChildItem -LiteralPath $dir -File -Filter 'events-*.jsonl' | Sort-Object Name)) {
        $fs = [IO.FileStream]::new($f.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        try { $ms = [IO.MemoryStream]::new(); $fs.CopyTo($ms) } finally { $fs.Dispose() }
        foreach ($l in ([Text.Encoding]::UTF8.GetString($ms.ToArray()) -split "`n")) {
            if ($l.Trim()) { ConvertFrom-Json -InputObject $l -DateKind String }
        }
    }
    # Several cli-<pid> files: time order, not file-name order.
    return @($events | Sort-Object -Stable -Property @{ Expression = { [string]$_.ts } })
}

function Get-Names($Problems) { return @(@($Problems) | ForEach-Object { [string]$_.name }) }

# A fixture stamp: a hand-written minimal REPO-STAMP, not an adoption.
function Write-FixtureStamp([string]$Dir, [string]$Role = 'product') {
    $stamp = [ordered]@{ schemaVersion = '1.0'; canon = [ordered]@{ version = '2026.10.27.1'; coreDigest = "sha256:$Zeros"; model = 'reference' } }
    if ($Role) { $stamp.role = $Role }
    $stamp.overlay = @()
    $stamp.ledgerShape = 'none'
    Write-Json (Join-Path $Dir '.sza-canon.json') $stamp
}

# The three default lock domains of the shipped profile, declared in the file.
function Add-FixtureDomains([string]$Dir) {
    $file = Join-Path $Dir '.sza-profile.json'
    $doc = if (Test-Path -LiteralPath $file) { Get-Content -Raw -LiteralPath $file | ConvertFrom-Json } else { [pscustomobject]@{ version = '1' } }
    $domains = @(
        [ordered]@{ name = 'Build.Main'; type = 'Build'; rank = 1 }
        [ordered]@{ name = 'Code.Main'; type = 'Code'; rank = 2 }
        [ordered]@{ name = 'Code.Scripts'; type = 'Code'; rank = 3 }
    )
    $doc | Add-Member -NotePropertyName locks -NotePropertyValue ([pscustomobject]@{ domains = $domains }) -Force
    Write-Json $file $doc
}

# A cheap directory holding only a stamp and, optionally, a profile (Add-PqRepo and the R63 test read nothing else).
function New-StampDir([string]$Name, [string]$Role = 'product', [switch]$Domains, [string]$Parent, [switch]$NoStamp) {
    if (-not $Parent) { $Parent = New-Scratch 'stamps' }
    $dir = Join-Path $Parent $Name
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    if (-not $NoStamp) { Write-FixtureStamp $dir $Role }
    if ($Domains) { Add-FixtureDomains $dir }
    return $dir
}

# A throwaway repository: init-task-flow, one capture per slug, the fixture stamp. Built once per shape, then copied.
function New-FixtureRepo {
    param(
        [string]$Name,
        [string[]]$Slugs = @('one', 'two', 'three'),
        [int[]]$Priorities = @(),
        [string[]]$Texts = @(),
        [switch]$Domains,
        [string]$Role = 'product',
        [switch]$KeepReleaseQueue,
        [string]$Parent
    )
    $sig = "$($Slugs -join ',')|$($Priorities -join ',')|$($Texts -join '|')"
    if (-not $script:FixtureCache.ContainsKey($sig)) {
        $t = Join-Path (New-Scratch 'template') 'repo'
        New-Item -ItemType Directory -Path $t | Out-Null
        $null = Invoke-Tool $t 'scaffold/init-task-flow.ps1' @('-Root', $t)
        for ($i = 0; $i -lt $Slugs.Count; $i++) {
            $text = if ($i -lt $Texts.Count -and $Texts[$i]) { $Texts[$i] } else { "the owner's words for $($Slugs[$i])" }
            $prio = if ($i -lt $Priorities.Count) { $Priorities[$i] } else { 50 }
            $null = Invoke-Tool $t 'spec_catalog/capture-draft.ps1' @('-Slug', "task-$($Slugs[$i])", '-Text', $text, '-Priority', [string]$prio)
        }
        $script:FixtureCache[$sig] = $t
    }
    if (-not $Parent) { $Parent = New-Scratch 'repos' }
    $dir = Join-Path $Parent $Name
    Copy-Item -LiteralPath $script:FixtureCache[$sig] -Destination $dir -Recurse
    if (-not $KeepReleaseQueue) { Remove-Item -LiteralPath (Join-Path $dir 'PLAN\RELEASE_QUEUE.md') -Force -ErrorAction Ignore }
    Write-FixtureStamp $dir $Role
    if ($Domains) { Add-FixtureDomains $dir }
    return $dir
}

function New-SiblingLease([string]$Repo, [string]$Id) {
    $null = Invoke-Tool $Repo 'locks/ticket-lease.ps1' @('-Verb', 'Claim', '-Id', $Id, '-Reason', 'fixture', '-Json') @{ SZA_AGENT_ID = 'sibling-session-0001' }
}

function Set-FixtureStatus([string]$Repo, [string]$Id, [string]$Status) {
    $null = Invoke-Tool $Repo 'spec_catalog/update.ps1' @('-Id', $Id, '-Status', $Status)
}

# A registry document in memory or on disk. Repos are hashtables of record keys (key, path, enabled and the rest).
function New-RegistryDoc([object[]]$Repos = @(), [hashtable]$Top = @{}) {
    $doc = [ordered]@{ schemaVersion = '1.0' }
    foreach ($k in $Top.Keys) { $doc[$k] = $Top[$k] }
    $doc.repos = @(foreach ($r in $Repos) { $o = [ordered]@{}; foreach ($k in $r.Keys) { $o[$k] = $r[$k] }; $o })
    return $doc
}

function Write-Registry($Doc) {
    $path = Join-Path $env:SZA_PORTFOLIO_ROOT 'repos.json'
    Write-Json $path $Doc
    return $path
}

# Read-PqRegistry over a JSON text written to a scratch file; returns the result.
function Read-RegistryText([string]$Json, [scriptblock]$ProfileReader) {
    $file = Join-Path (New-Scratch 'reg') 'repos.json'
    Write-Text $file $Json
    if ($ProfileReader) { return (Read-PqRegistry -Path $file -ProfileReader $ProfileReader) }
    return (Read-PqRegistry -Path $file)
}

function Assert-ErrorName($Result, [string]$Name, [string]$Row) {
    $names = Get-Names $Result.errors
    Assert-That (-not $Result.ok) "$Row - read ok, expected $Name"
    Assert-That ($names -ccontains $Name) "$Row - errors [$($names -join ', ')], expected $Name"
}

function Get-ValidAgents {
    return @(
        [ordered]@{ name = 'codex'; command = 'codex'; promptForm = 'file'; model = 'example-max-model'; effort = 'high'; maxParallel = 2; levels = @('light', 'medium', 'hard')
            limitDetector = [ordered]@{ kind = 'exitText'; pattern = '(?i)usage limit'; status = 'unproven' } }
        [ordered]@{ name = 'claude'; command = 'claude'; promptForm = 'slash'; modelByComplexity = [ordered]@{ light = 'haiku'; medium = 'sonnet'; hard = 'opus' }; maxParallel = 3
            limitDetector = [ordered]@{ kind = 'transcript'; pattern = '(?i)usage limit reached'; status = 'proven' } }
    )
}

# ---- queue and rank helpers ----

function Join-Lines([string[]]$Lines, [string]$Eol = "`n") { return (($Lines -join $Eol) + $Eol) }

function New-QueueFile([string[]]$Lines, [switch]$Crlf, [switch]$Bom) {
    $file = Join-Path (New-Scratch 'queue') 'PORTFOLIO_QUEUE.md'
    $eol = if ($Crlf) { "`r`n" } else { "`n" }
    Write-Text $file (Join-Lines $Lines $eol) -Bom:$Bom
    return $file
}

function Read-QueueLines([string[]]$Lines, [hashtable]$ReadArgs = @{}) {
    $file = New-QueueFile $Lines
    return (Read-PqQueueFile -Path $file @ReadArgs)
}

function Get-RowKeys($Rows) {
    return (@(@($Rows) | ForEach-Object { if ($null -eq $_.id) { $_.repo } else { "$($_.repo):$($_.id)" } }) -join ' ')
}

function Get-FileLines([string]$Path) {
    $text = [Text.UTF8Encoding]::new($false).GetString([IO.File]::ReadAllBytes($Path)).TrimStart([char]0xFEFF)
    $lines = [regex]::Split($text, '\r?\n')
    if ($lines.Length -gt 0 -and $lines[-1] -eq '') { $lines = $lines[0..($lines.Length - 2)] }
    return [string[]]$lines
}

# An in-memory registry for Get-PqRank (no validation).
function New-RankRepo([string]$Key, [int]$Rank = 100, [bool]$Enabled = $true, [bool]$Concurrent = $false, [int]$MaxWorkers = 1, [bool]$Hold = $false) {
    return [pscustomobject][ordered]@{ key = $Key; path = "C:\pq-fixture\$Key"; enabled = $Enabled; rank = $Rank; maxWorkers = $MaxWorkers
        concurrent = $Concurrent; hold = $Hold; role = 'product' }
}

function New-RankRegistry([object[]]$Repos, [int]$MaxWorkers = 5, [string]$Fill = 'depth') {
    return [pscustomobject][ordered]@{ maxWorkers = $MaxWorkers; fill = $Fill; repos = @($Repos) }
}

# A picker-shaped fake: $Table is key -> ordered tickets ('S0001:80' = id and priority), the repository's own order.
# -Leased key -> ids; -AutoSkip key -> @{ id = reason }; -Fail keys whose picker fails; -Calls a List[string] log.
function New-FakeProvider([hashtable]$Table, [hashtable]$Leased = @{}, [hashtable]$AutoSkip = @{}, [string[]]$Fail = @(), $Calls = $null) {
    return {
        param($Repo, $Exclude, $ForceId)
        $k = [string]$Repo.key
        $ex = @($Exclude | Where-Object { $_ })
        if ($null -ne $Calls) { $Calls.Add("$k|$($ex -join ',')|$ForceId") }
        if ($Fail -contains $k) { return @{ ok = $false; head = $null; payload = $null; why = 'pickerFailed' } }
        $all = @(foreach ($t in @($Table[$k])) {
                if (-not $t) { continue }
                $parts = $t.Split(':')
                [pscustomobject][ordered]@{ id = $parts[0]; name = "title $($parts[0])"; status = 'Draft'; priority = [int]$parts[1] }
            })
        $lease = @($Leased[$k] | Where-Object { $_ })
        $skips = if ($AutoSkip.ContainsKey($k)) { $AutoSkip[$k] } else { @{} }
        $ranked = @($all | Where-Object { $ex -notcontains $_.id -and $lease -notcontains $_.id })
        $auto = @()
        $sel = $null
        foreach ($t in $ranked) {
            if ($skips.ContainsKey($t.id)) { $auto += [pscustomobject]@{ id = $t.id; reason = $skips[$t.id]; detail = '' } }
            else { $sel = $t; break }
        }
        $none = $null
        if ($null -eq $sel) {
            $none = if ($all.Count -eq 0 -or ($ranked.Count -eq 0 -and $lease.Count -eq 0)) { 'queue-exhausted' } elseif ($ranked.Count -eq 0) { 'all-leased' } else { 'no-candidate' }
        }
        $payload = [pscustomobject][ordered]@{ selected = $sel; ranked = $ranked; leased_ids = @($lease | ForEach-Object { [pscustomobject]@{ id = $_ } })
            excluded_ids = $ex; auto_skipped = $auto; malformed = @(); selected_none_reason = $none }
        if (-not $ForceId) { return @{ ok = $true; head = $sel; payload = $payload; why = $null } }
        if ($lease -contains $ForceId) { return @{ ok = $true; head = $null; payload = $payload; why = 'leased' } }
        if ($ex -contains $ForceId) { return @{ ok = $true; head = $null; payload = $payload; why = 'excluded' } }
        $hit = @($all | Where-Object { $_.id -eq $ForceId })
        if ($hit.Count -eq 0) { return @{ ok = $true; head = $null; payload = $payload; why = 'notRanked' } }
        if ($skips.ContainsKey($ForceId)) { return @{ ok = $true; head = $null; payload = $payload; why = $skips[$ForceId] } }
        return @{ ok = $true; head = $hit[0]; payload = $payload; why = $null }
    }.GetNewClosure()
}

function Get-PlanKeys($Rank) { return (@(@($Rank.plan) | ForEach-Object { "$($_.repo):$($_.id)" }) -join ' ') }
function Get-CandidateKeys($Rank) { return (@(@($Rank.candidates) | ForEach-Object { "$($_.repo):$($_.id)" }) -join ' ') }

function Import-Libs([string[]]$Files) { foreach ($f in $Files) { $null = Get-LibPath $f } }

$validWhy = @('lowerPackage', 'laterRow', 'lowerPriority', 'laterRepoRank', 'fillCap', 'slotsFull')

try {
    if (-not $IsWindows) { throw 'Windows only: the picker cases use taskkill and Windows paths' }
    foreach ($required in @('scaffold\init-task-flow.ps1', 'spec_catalog\capture-draft.ps1', 'spec_catalog\spec-next-preflight.ps1', 'locks\ticket-lease.ps1')) {
        if (-not (Test-Path -LiteralPath (Join-Path $harness $required))) { throw "Missing prerequisite: tools\harness\$required" }
    }
    $scratch = Join-Path ([System.IO.Path]::GetTempPath()) ('s0015-queue-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $scratch | Out-Null
    $sep = [IO.Path]::DirectorySeparatorChar
    $vectorDir = if ($CatalogRoot) { Join-Path $CatalogRoot "task-flow${sep}vectors${sep}portfolio" } else { $null }

    # ---------------------------------------------------------------- fixture
    Test-Case 'fixture: a throwaway repository built by init-task-flow with three captured tickets, a stamp and a profile validates and is picked' {
        $repo = New-FixtureRepo -Name 'fx' -Priorities @(40, 80, 60)
        $v = Invoke-Tool $repo 'spec_catalog/validate.ps1' -AllowFail
        Assert-That ($v.code -eq 0) "validate.ps1 exited $($v.code): $($v.output)"
        $p = Invoke-Tool $repo 'spec_catalog/spec-next-preflight.ps1' @('-NoDrift', '-Format', 'json')
        $line = @($p.stdout -split '\r?\n' | Where-Object { $_.StartsWith('{') })[-1]
        $payload = ConvertFrom-Json -InputObject $line -DateKind String
        # Draft is selectable by the shipped picker (verified when this suite was written; no status move needed).
        Assert-That ($null -ne $payload.selected) "the picker selected nothing: $line"
        Assert-That ($payload.selected.id -ceq 'S0002') "the picker selected $($payload.selected.id), expected S0002 (priority 80, the highest)"
        Assert-That ($payload.selected.status -ceq 'Draft') "the selected ticket is $($payload.selected.status), expected Draft"
        Assert-That (Test-Path -LiteralPath (Join-Path $repo 'r0.ps1')) 'r0.ps1 is not at the fixture root'
        Assert-That (Test-Path -LiteralPath (Join-Path $repo '.sza-canon.json')) 'no fixture stamp'
        Assert-That (Test-Path -LiteralPath (Join-Path $repo '.sza-profile.json')) 'no profile'
    }

    # ---------------------------------------------------------------- registry
    Test-Case 'registry: a minimal valid registry reads with the documented defaults' {
        . (Get-LibPath 'registry.ps1')
        $root = $env:SZA_PORTFOLIO_ROOT
        Write-Text (Join-Path $root 'repos.json') '{"repos":[]}'
        $r = Read-PqRegistry
        Assert-That $r.ok "a minimal registry did not read clean: $((Get-Names $r.errors) -join ', ')"
        $g = $r.registry
        Assert-That ($g.maxWorkers -eq 5 -and $g.autoEnable -eq $true -and $g.pollSeconds -eq 60 -and $g.robotDraftCap -eq 20) "top defaults maxWorkers $($g.maxWorkers) autoEnable $($g.autoEnable) pollSeconds $($g.pollSeconds) robotDraftCap $($g.robotDraftCap)"
        Assert-That ($g.fill -ceq 'depth' -and $g.occupiedMinutes -eq 10) "fill $($g.fill) occupiedMinutes $($g.occupiedMinutes)"
        Assert-That ($g.resources.build -eq 3 -and $g.resources.emulator -eq 1) "resources build $($g.resources.build) emulator $($g.resources.emulator)"
        Assert-That (@($g.agents).Count -eq 1 -and $g.agents[0].name -ceq 'claude' -and $null -ne $g.agents[0].modelByComplexity) 'no built-in claude record with modelByComplexity'
        Assert-That ((@($g.agentOrder) -join ',') -ceq 'claude') "agentOrder is [$(@($g.agentOrder) -join ',')], expected [claude]"
        Assert-That ($null -eq $r.document.PSObject.Properties['maxWorkers']) 'the defaults were applied to the document, not to a copy'
        $path = Join-Path $root 'repos.json'
        Write-Text $path ('{"repos":[{"key":"alpha","path":' + (ConvertTo-Json 'C:\pq-fixture\alpha') + '}]}')
        $before = Get-Sha $path
        $r = Read-PqRegistry
        $repo = $r.registry.repos[0]
        Assert-That ($repo.enabled -eq $false -and $repo.rank -eq 100 -and $repo.maxWorkers -eq 1 -and $repo.concurrent -eq $false -and $repo.hold -eq $false) "repository defaults enabled $($repo.enabled) rank $($repo.rank) maxWorkers $($repo.maxWorkers) concurrent $($repo.concurrent) hold $($repo.hold)"
        Assert-That ((Get-Names $r.errors) -ccontains 'RepoFieldType') 'a record without enabled was accepted (enabled is required)'
        Assert-That ((Get-Sha $path) -ceq $before) 'reading changed the file'
    }

    if ($vectorDir) {
        Test-Case 'registry: the vector portfolio-repos-sample.json reads clean' {
            . (Get-LibPath 'registry.ps1')
            $file = Join-Path $vectorDir 'portfolio-repos-sample.json'
            Assert-That (Test-Path -LiteralPath $file) "the catalog has no $file"
            # Its concurrent record names a path that does not exist here; the seam answers "declared".
            $r = Read-PqRegistry -Path $file -ProfileReader { param($p) 3 }
            Assert-That $r.ok "the sample did not read clean: $(@($r.errors | ForEach-Object { "$($_.name) $($_.where)" }) -join '; ')"
            Assert-That (@($r.warnings).Count -eq 0) "the sample gave warnings: $((Get-Names $r.warnings) -join ', ')"
            $none = Read-PqRegistry -Path $file -ProfileReader { param($p) 0 }
            Assert-That ((Get-Names $none.errors) -ccontains 'ConcurrentWithoutLockDomains') 'the concurrent record was accepted with no declared domains'
        }
        Test-Case 'registry: every case of portfolio-repos-invalid.json is rejected with a named error' {
            . (Get-LibPath 'registry.ps1')
            $file = Join-Path $vectorDir 'portfolio-repos-invalid.json'
            Assert-That (Test-Path -LiteralPath $file) "the catalog has no $file"
            $map = @{ 'key-pattern' = 'RepoKeyInvalid'; 'key-duplicate' = 'RepoKeyDuplicate'; 'path-not-absolute' = 'RepoPathNotAbsolute'
                'path-duplicate' = 'RepoPathDuplicate'; 'maxWorkers-range' = 'MaxWorkersRange'; 'repo-maxWorkers-range' = 'RepoMaxWorkersRange'
                'permissionMode-unknown' = 'PermissionModeInvalid'; 'agentOrder-unknown' = 'AgentOrderUnknownAgent'; 'agent-model-split' = 'AgentModelMapNotAllowed'
                'agent-model-missing' = 'AgentModelMissing'; 'schemaVersion-unsupported' = 'RegistryVersionUnsupported'; 'fill-unknown' = 'FillInvalid'
                'occupiedMinutes-range' = 'OccupiedMinutesRange'; 'resources-range' = 'ResourceCapInvalid'; 'resources-device' = 'ResourceDeviceNotAllowed'
                'repo-maxWorkers-needs-concurrent' = 'MaxWorkersRequiresConcurrent' }
            $cases = @(Get-Content -Raw -LiteralPath $file | ConvertFrom-Json -DateKind String)
            Assert-That ($cases.Count -eq 17) "the invalid vector has $($cases.Count) cases, expected 17"
            foreach ($c in $cases) {
                Assert-That $map.ContainsKey([string]$c.expect) "case '$($c.name)': unmapped expect '$($c.expect)'"
                $r = Test-PqRegistry -Registry $c.doc -ProfileReader { param($p) 3 }
                $names = Get-Names $r.errors
                Assert-That (-not $r.ok) "case '$($c.name)' was accepted"
                Assert-That ($names -ccontains $map[[string]$c.expect]) "case '$($c.name)': errors [$($names -join ', ')], expected $($map[[string]$c.expect])"
            }
        }
    }
    else {
        Skip-Case 'registry: the vector portfolio-repos-sample.json reads clean' 'needs -CatalogRoot'
        Skip-Case 'registry: every case of portfolio-repos-invalid.json is rejected with a named error' 'needs -CatalogRoot'
    }

    Test-Case 'registry: top-level defects raise their named error' {
        . (Get-LibPath 'registry.ps1')
        $rows = @(
            ,@('not JSON', '{"repos": [', 'RegistryNotJson')
            ,@('an array', '[]', 'RegistryNotObject')
            ,@('schemaVersion 2.0', '{"schemaVersion":"2.0","repos":[]}', 'RegistryVersionUnsupported')
            ,@('schemaVersion 1 (a number)', '{"schemaVersion":1,"repos":[]}', 'RegistryVersionUnsupported')
            ,@('schemaVersion x', '{"schemaVersion":"x","repos":[]}', 'RegistryVersionUnsupported')
            ,@('no repos', '{}', 'ReposMissing')
            ,@('maxWorkers 0', '{"repos":[],"maxWorkers":0}', 'MaxWorkersRange')
            ,@('maxWorkers 6', '{"repos":[],"maxWorkers":6}', 'MaxWorkersRange')
            ,@('permissionMode yolo', '{"repos":[],"permissionMode":"yolo"}', 'PermissionModeInvalid')
            ,@('fill sideways', '{"repos":[],"fill":"sideways"}', 'FillInvalid')
            ,@('occupiedMinutes 0', '{"repos":[],"occupiedMinutes":0}', 'OccupiedMinutesRange')
            ,@('resources.build 0', '{"repos":[],"resources":{"build":0}}', 'ResourceCapInvalid')
            ,@('resources.emulator -1', '{"repos":[],"resources":{"emulator":-1}}', 'ResourceCapInvalid')
            ,@('resources.device', '{"repos":[],"resources":{"device":1}}', 'ResourceDeviceNotAllowed')
            ,@('pollSeconds 0', '{"repos":[],"pollSeconds":0}', 'PollSecondsRange')
            ,@('timing.tickMs -5', '{"repos":[],"timing":{"tickMs":-5}}', 'TimingValueInvalid')
            ,@('analysis.thresholds.stallMinutes x', '{"repos":[],"analysis":{"thresholds":{"stallMinutes":"x"}}}', 'ThresholdValueInvalid')
            ,@('a relative discovery root', '{"repos":[],"discoveryRoots":["repos\\here"]}', 'DiscoveryRootNotAbsolute')
            ,@('agentOrder names an unknown agent', '{"repos":[],"agentOrder":["nobody"]}', 'AgentOrderUnknownAgent')
            ,@('agentOrder names one twice', '{"repos":[],"agentOrder":["claude","claude"]}', 'AgentOrderDuplicate')
        )
        foreach ($row in $rows) { Assert-ErrorName (Read-RegistryText $row[1]) $row[2] $row[0] }
    }

    Test-Case 'registry: repository defects raise their named error' {
        . (Get-LibPath 'registry.ps1')
        $p = 'C:\pq-fixture\one'
        $reg = { param($repos, $top = @{}) Test-PqRegistry -Registry (ConvertTo-Json -InputObject (New-RegistryDoc $repos $top) -Depth 10 | ConvertFrom-Json -DateKind String) }
        foreach ($bad in @('FMS-A', '1abc', 'f1x', '')) {
            $r = & $reg @(@{ key = $bad; path = $p; enabled = $true })
            Assert-That ((Get-Names $r.errors) -ccontains 'RepoKeyInvalid') "key '$bad' - errors [$((Get-Names $r.errors) -join ', ')], expected RepoKeyInvalid"
        }
        $r = & $reg @(@{ key = 'a--'; path = $p; enabled = $true })
        Assert-That $r.ok "key 'a--' was refused: $((Get-Names $r.errors) -join ', ')"
        $rows = @(
            ,@('duplicate key', @(@{ key = 'dup'; path = 'C:\pq-fixture\a'; enabled = $true }, @{ key = 'dup'; path = 'C:\pq-fixture\b'; enabled = $true }), 'RepoKeyDuplicate')
            ,@('relative path', @(@{ key = 'rel'; path = 'repos\rel'; enabled = $true }), 'RepoPathNotAbsolute')
            ,@('the same path in another spelling', @(@{ key = 'one'; path = 'C:\Work\Repo'; enabled = $true }, @{ key = 'two'; path = 'c:/work/repo/'; enabled = $true }), 'RepoPathDuplicate')
            ,@('enabled "yes"', @(@{ key = 'one'; path = $p; enabled = 'yes' }), 'RepoFieldType')
            ,@('hold 1', @(@{ key = 'one'; path = $p; enabled = $true; hold = 1 }), 'RepoFieldType')
            ,@('rank "high"', @(@{ key = 'one'; path = $p; enabled = $true; rank = 'high' }), 'RepoFieldType')
            ,@('maxWorkers "2"', @(@{ key = 'one'; path = $p; enabled = $true; maxWorkers = '2' }), 'RepoFieldType')
            ,@('maxWorkers 0', @(@{ key = 'one'; path = $p; enabled = $true; maxWorkers = 0 }), 'RepoMaxWorkersRange')
        )
        foreach ($row in $rows) {
            $r = & $reg $row[1]
            Assert-That ((Get-Names $r.errors) -ccontains $row[2]) "$($row[0]) - errors [$((Get-Names $r.errors) -join ', ')], expected $($row[2])"
        }
        $r = & $reg @(@{ key = 'one'; path = $p; enabled = $true; maxWorkers = 3; concurrent = $true }) @{ maxWorkers = 2 }
        Assert-That ((Get-Names $r.errors) -ccontains 'RepoMaxWorkersRange') "maxWorkers above the top-level value - errors [$((Get-Names $r.errors) -join ', ')]"
    }

    Test-Case 'registry: agent defects raise their named error' {
        . (Get-LibPath 'registry.ps1')
        $check = {
            param([scriptblock]$Mutate, [string]$Expect, [string]$Row)
            $agents = Get-ValidAgents
            & $Mutate $agents
            $doc = ConvertTo-Json -InputObject (New-RegistryDoc @() @{ agents = $agents; agentOrder = @('codex', 'claude') }) -Depth 10 | ConvertFrom-Json -DateKind String
            $r = Test-PqRegistry -Registry $doc
            Assert-That ((Get-Names $r.errors) -ccontains $Expect) "$Row - errors [$((Get-Names $r.errors) -join ', ')], expected $Expect"
        }
        $ok = ConvertTo-Json -InputObject (New-RegistryDoc @() @{ agents = (Get-ValidAgents); agentOrder = @('codex', 'claude') }) -Depth 10 | ConvertFrom-Json -DateKind String
        $r = Test-PqRegistry -Registry $ok
        Assert-That $r.ok "the valid agents were refused: $((Get-Names $r.errors) -join ', ')"
        & $check { param($a) $a[0].name = 'Codex!' } 'AgentNameInvalid' 'bad name'
        & $check { param($a) $a[1].name = 'codex'; $a[1].Remove('modelByComplexity'); $a[1].model = 'm'; $a[1].effort = 'e' } 'AgentNameDuplicate' 'duplicate name'
        & $check { param($a) $a[0].Remove('command') } 'AgentCommandMissing' 'no command'
        & $check { param($a) $a[0].Remove('model') } 'AgentModelMissing' 'non-Claude without model'
        & $check { param($a) $a[0].modelByComplexity = [ordered]@{ light = 'x'; medium = 'y'; hard = 'z' } } 'AgentModelMapNotAllowed' 'non-Claude with modelByComplexity'
        & $check { param($a) $a[1].Remove('modelByComplexity') } 'AgentModelMapMissing' 'claude without modelByComplexity'
        & $check { param($a) $a[0].promptForm = 'x' } 'AgentPromptFormInvalid' 'promptForm x'
        & $check { param($a) $a[0].levels = @('light', 'extreme') } 'AgentLevelsInvalid' 'levels with extreme'
        & $check { param($a) $a[0].maxParallel = 0 } 'AgentMaxParallelRange' 'maxParallel 0'
        & $check { param($a) $a[0].limitDetector.status = 'maybe' } 'LimitDetectorInvalid' 'limitDetector.status maybe'
        & $check { param($a) $a[0].limitDetector.kind = 'x' } 'LimitDetectorInvalid' 'limitDetector.kind x'
    }

    Test-Case 'registry: concurrent and a maxWorkers above 1 are accepted only for a repository whose profile declares lock domains' {
        . (Get-LibPath 'registry.ps1')
        $dir = New-StampDir 'domains' -Domains
        Assert-That ((Get-PqDeclaredLockDomains -RepoPath $dir) -eq 3) "Get-PqDeclaredLockDomains read $(Get-PqDeclaredLockDomains -RepoPath $dir), expected 3"
        foreach ($mw in 3, 1) {
            $r = Read-RegistryText (ConvertTo-Json -InputObject (New-RegistryDoc @(@{ key = 'dom'; path = $dir; enabled = $true; concurrent = $true; maxWorkers = $mw })) -Depth 10)
            Assert-That $r.ok "concurrent true with maxWorkers $mw was refused: $((Get-Names $r.errors) -join ', ')"
        }
    }

    Test-Case 'registry: concurrent and a maxWorkers above 1 are refused without declared lock domains, each with its named error' {
        . (Get-LibPath 'registry.ps1')
        $parent = New-Scratch 'r63'
        $noProfile = New-StampDir 'noprofile' -Parent $parent
        $noLocks = New-StampDir 'nolocks' -Parent $parent
        Write-Text (Join-Path $noLocks '.sza-profile.json') '{"version":"1","projectName":"x"}'
        $empty = New-StampDir 'empty' -Parent $parent
        Write-Text (Join-Path $empty '.sza-profile.json') '{"version":"1","locks":{"domains":[]}}'
        $bad = New-StampDir 'bad' -Parent $parent
        Write-Text (Join-Path $bad '.sza-profile.json') '{"version":'
        $dom = New-StampDir 'dom' -Domains -Parent $parent
        $rows = @(
            ,@('no profile file', $noProfile, $true, 2, 'ConcurrentWithoutLockDomains')
            ,@('a profile with no locks key', $noLocks, $true, 2, 'ConcurrentWithoutLockDomains')
            ,@('locks.domains [] (the merged default tree has three and must not count)', $empty, $true, 2, 'ConcurrentWithoutLockDomains')
            ,@('concurrent with maxWorkers 1 and no domains', $noLocks, $true, 1, 'ConcurrentWithoutLockDomains')
            ,@('a malformed profile', $bad, $true, 2, 'ConcurrentProfileUnreadable')
            ,@('maxWorkers 2 without concurrent, domains declared', $dom, $false, 2, 'MaxWorkersRequiresConcurrent')
        )
        foreach ($row in $rows) {
            $rec = @{ key = 'one'; path = $row[1]; enabled = $true; maxWorkers = $row[3] }
            if ($row[2]) { $rec.concurrent = $true }
            Assert-ErrorName (Read-RegistryText (ConvertTo-Json -InputObject (New-RegistryDoc @($rec)) -Depth 10)) $row[4] $row[0]
        }
    }

    Test-Case 'registry: a missing registry reads as ok=false with RegistryMissing and a read never creates it' {
        . (Get-LibPath 'registry.ps1')
        $root = $env:SZA_PORTFOLIO_ROOT
        $r = Read-PqRegistry
        Assert-That (-not $r.ok) 'a missing registry read ok'
        Assert-That ((Get-Names $r.errors) -ccontains 'RegistryMissing') "errors [$((Get-Names $r.errors) -join ', ')], expected RegistryMissing"
        Assert-That (-not (Test-Path -LiteralPath $root)) 'the read created the portfolio root'
        Assert-That ($null -eq (Get-PqRegistryHash)) 'Get-PqRegistryHash of a missing file is not $null'
    }

    Test-Case 'registry: unknown keys and an unknown role survive a rewrite, and an unknown role is a warning not an error' {
        . (Get-LibPath 'registry.ps1')
        $path = Join-Path $env:SZA_PORTFOLIO_ROOT 'repos.json'
        $doc = [ordered]@{ futureKey = [ordered]@{ x = 1 }; schemaVersion = '1.0'; repos = @([ordered]@{ key = 'one'; path = 'C:\pq-fixture\one'; enabled = $true; role = 'mystery'; note = 'kept' }); zLast = 'end' }
        Write-Json $path $doc
        $r = Read-PqRegistry
        Assert-That $r.ok "the registry with unknown keys did not read clean: $((Get-Names $r.errors) -join ', ')"
        Assert-That ((Get-Names $r.warnings) -ccontains 'RoleUnknown') "warnings [$((Get-Names $r.warnings) -join ', ')], expected RoleUnknown"
        Assert-That ($r.registry.repos[0].role -ceq 'product') "an unknown role reads as $($r.registry.repos[0].role), expected product"
        $keysBefore = (@($r.document.PSObject.Properties.Name) -join ' ')
        $w = Write-PqRegistry -Registry $r.document -ExpectedHash $r.hash
        Assert-That $w.ok "the rewrite failed: $($w.error) $($w.message)"
        $back = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json -DateKind String
        Assert-That ((@($back.PSObject.Properties.Name) -join ' ') -ceq $keysBefore) "key order after the rewrite is '$(@($back.PSObject.Properties.Name) -join ' ')', expected '$keysBefore'"
        Assert-That ($back.futureKey.x -eq 1 -and $back.zLast -ceq 'end') 'an unknown top-level key was lost'
        Assert-That ($back.repos[0].note -ceq 'kept' -and $back.repos[0].role -ceq 'mystery') 'an unknown repository key or the written role was lost'
        $text = [IO.File]::ReadAllText($path)
        Assert-That (-not $text.Contains("`r")) 'the rewrite is not LF'
        Assert-That ($text.EndsWith("`n")) 'the rewrite has no final newline'
        Assert-That ($text -match '(?m)^  "repos"') 'the rewrite is not indented by two spaces'
    }

    Test-Case 'registry: the hash is the SHA-256 of the bytes on disk in lowercase hex' {
        . (Get-LibPath 'registry.ps1')
        $path = Join-Path $env:SZA_PORTFOLIO_ROOT 'repos.json'
        Write-Text $path '{"repos":[]}' -Bom
        $expected = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([IO.File]::ReadAllBytes($path))).ToLowerInvariant()
        $r = Read-PqRegistry
        Assert-That $r.ok 'a registry with a BOM did not read'
        Assert-That ($r.hash -ceq $expected) "Read-PqRegistry hash $($r.hash), expected $expected"
        Assert-That ((Get-PqRegistryHash) -ceq $expected) "Get-PqRegistryHash $(Get-PqRegistryHash), expected $expected"
    }

    Test-Case 'registry: a write is atomic - an occupied temp name leaves the old file intact and no temp file behind' {
        . (Get-LibPath 'registry.ps1')
        $path = Join-Path $env:SZA_PORTFOLIO_ROOT 'repos.json'
        Write-Text $path '{"repos":[]}'
        $before = Get-Sha $path
        New-Item -ItemType Directory -Path "$path.tmp" | Out-Null
        $r = Read-PqRegistry
        $w = Write-PqRegistry -Registry $r.document -ExpectedHash $r.hash
        Assert-That (-not $w.ok) 'the write succeeded with its temp name occupied'
        Assert-That ((Get-Sha $path) -ceq $before) 'the old file changed'
        $files = @(Get-ChildItem -LiteralPath $env:SZA_PORTFOLIO_ROOT -File | ForEach-Object Name)
        Assert-That (($files -join ',') -ceq 'repos.json') "files after the failed write: $($files -join ', ')"
        Remove-Item -LiteralPath "$path.tmp" -Force
        $w = Write-PqRegistry -Registry $r.document -ExpectedHash $r.hash
        Assert-That $w.ok "the write failed with the temp name free: $($w.error)"
        $files = @(Get-ChildItem -LiteralPath $env:SZA_PORTFOLIO_ROOT -Force | ForEach-Object Name)
        Assert-That (($files -join ',') -ceq 'repos.json') "entries after a good write: $($files -join ', ')"
    }

    Test-Case 'registry: a write refuses with RegistryChangedOnDisk when the file changed since it was read, and writes nothing' {
        . (Get-LibPath 'registry.ps1')
        $path = Join-Path $env:SZA_PORTFOLIO_ROOT 'repos.json'
        Write-Text $path '{"repos":[]}'
        $r = Read-PqRegistry
        Write-Text $path '{"repos":[],"pollSeconds":30}'
        $changed = Get-Sha $path
        $w = Write-PqRegistry -Registry $r.document -ExpectedHash $r.hash
        Assert-That (-not $w.ok -and $w.error -ceq 'RegistryChangedOnDisk') "the write returned ok $($w.ok) error $($w.error), expected RegistryChangedOnDisk"
        Assert-That ((Get-Sha $path) -ceq $changed) 'the file the owner changed was overwritten'
        Assert-That (-not (Test-Path -LiteralPath "$path.tmp")) 'a temp file stayed'
    }

    Test-Case 'registry: Get-PqEffectiveRepo inherits the registry permissionMode, defaults maxWorkers to 1 and concurrent to false' {
        . (Get-LibPath 'registry.ps1')
        $reg = ConvertTo-Json -InputObject (New-RegistryDoc @(@{ key = 'one'; path = 'C:\pq-fixture\one'; enabled = $true }, @{ key = 'two'; path = 'C:\pq-fixture\two'; enabled = $true; permissionMode = 'plan' }) @{ permissionMode = 'auto' }) -Depth 10 | ConvertFrom-Json -DateKind String
        $one = Get-PqEffectiveRepo -Registry $reg -Key 'one'
        Assert-That ($one.permissionMode -ceq 'auto') "permissionMode $($one.permissionMode), expected auto (inherited)"
        Assert-That ($one.maxWorkers -eq 1 -and $one.concurrent -eq $false) "maxWorkers $($one.maxWorkers) concurrent $($one.concurrent)"
        $two = Get-PqEffectiveRepo -Registry $reg -Key 'two'
        Assert-That ($two.permissionMode -ceq 'plan') "a repository's own permissionMode was overridden: $($two.permissionMode)"
        Assert-That ($null -eq (Get-PqEffectiveRepo -Registry $reg -Key 'nope')) 'an unknown key returned a record'
        Assert-That ($null -eq $reg.repos[0].PSObject.Properties['maxWorkers']) 'Get-PqEffectiveRepo changed the registry object'
    }

    Test-Case 'registry: Add-PqRepo registers a repository disabled with maxWorkers 1 and concurrent false whatever its profile declares, role from the stamp, key from the folder name, and emits registry.changed with by, added, removed and hash' {
        . (Get-LibPath 'registry.ps1')
        $dir = New-StampDir 'My_Repo.Name' -Role 'internal' -Domains
        $r = Add-PqRepo -Path $dir -Log
        Assert-That ($r.ok -and $r.status -ceq 'registered' -and $r.key -ceq 'my-repo-name') "Add-PqRepo returned ok $($r.ok) status $($r.status) key $($r.key) error $($r.error)"
        $read = Read-PqRegistry
        Assert-That $read.ok "the written registry does not read clean: $((Get-Names $read.errors) -join ', ')"
        $rec = $read.document.repos[0]
        Assert-That ($rec.enabled -eq $false -and $rec.maxWorkers -eq 1 -and $rec.concurrent -eq $false) "record enabled $($rec.enabled) maxWorkers $($rec.maxWorkers) concurrent $($rec.concurrent)"
        Assert-That ($rec.role -ceq 'internal') "role $($rec.role), expected internal (from the stamp)"
        Assert-That ($rec.path -ceq $dir) "path $($rec.path), expected $dir"
        $noRole = New-StampDir 'plain' -Role ''
        $r2 = Add-PqRepo -Path $noRole -Enable
        Assert-That $r2.ok "the second registration failed: $($r2.error)"
        $rec2 = (Read-PqRegistry).document.repos[1]
        Assert-That ($rec2.role -ceq 'product' -and $rec2.enabled -eq $true) "a stamp without role gave role $($rec2.role) enabled $($rec2.enabled)"
        $null = Close-PqLog
        $ev = @(Get-RootEvents $env:SZA_PORTFOLIO_ROOT | Where-Object { $_.ev -ceq 'registry.changed' })
        Assert-That ($ev.Count -eq 1) "$($ev.Count) registry.changed events, expected 1 (the second call had no -Log)"
        $d = $ev[0].d
        Assert-That ($d.by -ceq 'cli' -and (@($d.added) -join ',') -ceq 'my-repo-name' -and @($d.removed).Count -eq 0) "registry.changed d: $(ConvertTo-Json $d -Compress)"
        Assert-That ($d.hash -ceq $r.hash) "registry.changed hash $($d.hash), expected $($r.hash)"
    }

    Test-Case 'registry: Add-PqRepo is idempotent for the same path and refuses a taken key with RepoKeyTaken and a path without a readable stamp with StampMissing' {
        . (Get-LibPath 'registry.ps1')
        $dir = New-StampDir 'same'
        $r = Add-PqRepo -Path $dir
        $hash = Get-PqRegistryHash
        $again = Add-PqRepo -Path ($dir.ToUpperInvariant() + '\')
        Assert-That ($again.ok -and $again.status -ceq 'already' -and $again.key -ceq 'same') "a second registration returned ok $($again.ok) status $($again.status)"
        Assert-That ((Get-PqRegistryHash) -ceq $hash) 'an idempotent registration rewrote the file'
        $other = New-StampDir 'same'
        $t = Add-PqRepo -Path $other
        Assert-That (-not $t.ok -and $t.error -ceq 'RepoKeyTaken') "a taken key returned ok $($t.ok) error $($t.error)"
        $noStamp = New-StampDir 'nostamp' -NoStamp
        $s = Add-PqRepo -Path $noStamp
        Assert-That (-not $s.ok -and $s.error -ceq 'StampMissing') "no stamp returned ok $($s.ok) error $($s.error)"
        $badStamp = New-StampDir 'badstamp' -NoStamp
        Write-Text (Join-Path $badStamp '.sza-canon.json') '{"canon":'
        $b = Add-PqRepo -Path $badStamp
        Assert-That (-not $b.ok -and $b.error -ceq 'StampMissing') "an unreadable stamp returned ok $($b.ok) error $($b.error)"
        Assert-That ((Get-PqRegistryHash) -ceq $hash) 'a refused registration changed the file'
    }

    Test-Case 'registry: Set-PqRepoHold sets and clears the flag atomically, preserves everything else and emits registry.changed' {
        . (Get-LibPath 'registry.ps1')
        $path = Write-Registry ([ordered]@{ schemaVersion = '1.0'; extra = 'x'; repos = @([ordered]@{ key = 'one'; path = 'C:\pq-fixture\one'; enabled = $true; note = 'n' }, [ordered]@{ key = 'two'; path = 'C:\pq-fixture\two'; enabled = $false }) })
        $before = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json -DateKind String
        $r = Set-PqRepoHold -Key 'one' -Hold $true -Log
        Assert-That ($r.ok -and $r.changed) "the hold returned ok $($r.ok) changed $($r.changed) error $($r.error)"
        $mid = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json -DateKind String
        Assert-That ($mid.repos[0].hold -eq $true) 'hold is not true'
        $mid.repos[0].PSObject.Properties.Remove('hold')
        Assert-That ((ConvertTo-Json $mid -Depth 10 -Compress) -ceq (ConvertTo-Json $before -Depth 10 -Compress)) 'something else changed with the hold'
        $r = Set-PqRepoHold -Key 'one' -Hold $false -Log
        Assert-That ($r.ok -and $r.changed) 'clearing the hold failed'
        Assert-That ((Get-Content -Raw -LiteralPath $path | ConvertFrom-Json).repos[0].hold -eq $false) 'hold is not false after the clear'
        $u = Set-PqRepoHold -Key 'nope' -Hold $true
        Assert-That (-not $u.ok -and $u.error -ceq 'UnknownRepoKey') "an unknown key returned $($u.error)"
        $null = Close-PqLog
        $ev = @(Get-RootEvents $env:SZA_PORTFOLIO_ROOT | Where-Object { $_.ev -ceq 'registry.changed' })
        Assert-That ($ev.Count -eq 2) "$($ev.Count) registry.changed events, expected 2"
        Assert-That ($ev[1].d.hash -ceq (Get-Sha $path)) 'the second event does not carry the new hash'
        Assert-That (@(Get-ChildItem -LiteralPath $env:SZA_PORTFOLIO_ROOT -File -Filter '*.tmp').Count -eq 0) 'a temp file stayed'
    }

    Test-Case 'registry: timing keys are accepted, must be positive numbers, and are preserved on a rewrite' {
        . (Get-LibPath 'registry.ps1')
        $timing = [ordered]@{ tickMs = 250; beatSeconds = 5; passBeatSeconds = 30; resSampleSeconds = 10; ceilingMinutes = 90; hardCeilingFactor = 1.5 }
        $path = Write-Registry ([ordered]@{ repos = @(); timing = $timing })
        $r = Read-PqRegistry
        Assert-That $r.ok "valid timing keys were refused: $((Get-Names $r.errors) -join ', ')"
        foreach ($bad in @('0', '-1', '"x"')) {
            Assert-ErrorName (Read-RegistryText ('{"repos":[],"timing":{"tickMs":' + $bad + '}}')) 'TimingValueInvalid' "timing.tickMs $bad"
        }
        $dir = New-StampDir 'timed'
        $a = Add-PqRepo -Path $dir
        Assert-That $a.ok "Add-PqRepo failed: $($a.error)"
        $back = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json -DateKind String
        Assert-That ((ConvertTo-Json $back.timing -Compress) -ceq (ConvertTo-Json ([pscustomobject]$timing) -Compress)) "timing after the rewrite: $(ConvertTo-Json $back.timing -Compress)"
    }

    # ---------------------------------------------------------------- queue-read
    Test-Case 'queue-read: numbered packages ascending by integer value, then the -- package' {
        . (Get-LibPath 'queue-file.ps1')
        $q = Read-QueueLines @('--', 'z', '2', 'b', '10', 'c', '1', 'a')
        Assert-That ((Get-RowKeys $q.rows) -ceq 'a b c z') "order '$(Get-RowKeys $q.rows)', expected 'a b c z'"
        Assert-That ((@($q.rows | ForEach-Object { $_.packageText }) -join ',') -ceq '1,2,10,--') 'packageText is not 1,2,10,--'
        Assert-That ($q.rows[2].package -eq 10 -and $q.rows[3].package -gt 10) 'package values are not integers with -- last'
    }

    Test-Case 'queue-read: line order inside a package, and a repeated package number keeps file order' {
        . (Get-LibPath 'queue-file.ps1')
        $q = Read-QueueLines @('2', 'w', '1', 'x', 'y', '2', 'v', '1', 'z')
        Assert-That ((Get-RowKeys $q.rows) -ceq 'x y z w v') "order '$(Get-RowKeys $q.rows)', expected 'x y z w v'"
    }

    # Decision of rule 44 (owner to confirm): the rows before the first heading are a package that sorts first.
    Test-Case 'queue-read: rows before the first heading form an implicit package that sorts first' {
        . (Get-LibPath 'queue-file.ps1')
        $q = Read-QueueLines @('# header', 'pre', '0', 'zero', '1', 'a')
        Assert-That ((Get-RowKeys $q.rows) -ceq 'pre zero a') "order '$(Get-RowKeys $q.rows)', expected 'pre zero a' (implicit before package 0)"
        Assert-That ($null -eq $q.rows[0].packageText -and $q.rows[0].package -lt 0) 'the implicit package is not before every numbered package'
    }

    # Decision of rule 44 (owner to confirm): hold governs until the next heading.
    Test-Case 'queue-read: a hold heading in any case takes rows out of reach until the next heading' {
        . (Get-LibPath 'queue-file.ps1')
        $q = Read-QueueLines @('1', 'a', 'HOLD', 'b', 'c:S0001', '2', 'd', 'Hold', 'e', '--', 'f')
        Assert-That ((Get-RowKeys $q.rows) -ceq 'a d f') "active '$(Get-RowKeys $q.rows)', expected 'a d f'"
        Assert-That ((Get-RowKeys $q.held) -ceq 'b c:S0001 e') "held '$(Get-RowKeys $q.held)', expected 'b c:S0001 e'"
        Assert-That (@($q.held | Where-Object { $_.packageText -cne 'hold' }).Count -eq 0) 'a held row does not say hold'
    }

    Test-Case 'queue-read: key, key:* and key:ID rows are read, and text after the first token is a comment' {
        . (Get-LibPath 'queue-file.ps1')
        $q = Read-QueueLines @('1', 'fms-a   # own head', 'tourist-mob:*  the same, spelled out', 'fms-web:S0028 any words here', 'epub-2-html:SP-0166')
        Assert-That ((Get-RowKeys $q.rows) -ceq 'fms-a tourist-mob fms-web:S0028 epub-2-html:SP-0166') "rows '$(Get-RowKeys $q.rows)'"
        Assert-That ((@($q.rows | ForEach-Object { $_.kind }) -join ',') -ceq 'head,head,ticket,ticket') 'kinds are not head,head,ticket,ticket'
        Assert-That ($null -eq $q.rows[1].id) 'key:* carries an id'
        Assert-That (@($q.bad).Count -eq 0) "bad rows: $(@($q.bad | ForEach-Object { $_.text }) -join '; ')"
    }

    Test-Case 'queue-read: comments and blank lines are skipped, and a # inside a row ends it' {
        . (Get-LibPath 'queue-file.ps1')
        $q = Read-QueueLines @('# a comment', '', '   ', '1', '  # indented comment', 'fms-a#tail', 'fms-b:S0002#tail', '')
        Assert-That ((Get-RowKeys $q.rows) -ceq 'fms-a fms-b:S0002') "rows '$(Get-RowKeys $q.rows)'"
        Assert-That (@($q.bad).Count -eq 0) 'a comment or a blank line was reported'
    }

    Test-Case 'queue-read: a BOM and CRLF read the same order as plain LF' {
        . (Get-LibPath 'queue-file.ps1')
        $lines = @('# c', 'pre', '2', 'b', '1', 'a:S0001', 'hold', 'h')
        $lf = Read-PqQueueFile -Path (New-QueueFile $lines)
        $crlf = Read-PqQueueFile -Path (New-QueueFile $lines -Crlf -Bom)
        Assert-That ($crlf.bom -and $crlf.eol -ceq "`r`n") "bom $($crlf.bom) eol $([int][char]$crlf.eol[0])"
        Assert-That (-not $lf.bom -and $lf.eol -ceq "`n") 'the LF file reads as BOM or CRLF'
        $show = { param($q) ConvertTo-Json -InputObject @($q.rows + $q.held) -Depth 5 -Compress }
        Assert-That ((& $show $lf) -ceq (& $show $crlf)) "CRLF+BOM read $(& $show $crlf), LF read $(& $show $lf)"
    }

    Test-Case 'queue-read: an unknown repository key is bad with kind unknownRepo and a queue.row payload of at most 80 characters' {
        . (Get-LibPath 'queue-file.ps1')
        $long = 'zz-unknown   # ' + ('x' * 120)
        $q = Read-QueueLines @('1', 'fms-a', $long) @{ KnownRepos = @('fms-a') }
        Assert-That ((Get-RowKeys $q.rows) -ceq 'fms-a') "rows '$(Get-RowKeys $q.rows)'"
        Assert-That (@($q.bad).Count -eq 1 -and $q.bad[0].kind -ceq 'unknownRepo' -and $q.bad[0].line -eq 3) "bad: $(ConvertTo-Json $q.bad -Compress)"
        Assert-That ($q.bad[0].text.Length -le 80 -and $q.bad[0].text.StartsWith('zz-unknown')) "text is $($q.bad[0].text.Length) characters"
    }

    Test-Case 'queue-read: an unknown ticket is unknownTicket and a closed ticket is closed, and the queue goes on' {
        . (Get-LibPath 'queue-file.ps1')
        $lookup = { param($repo, $id) switch ($id) { 'S0404' { @{ exists = $false; closed = $false } } 'S0009' { @{ exists = $true; closed = $true } } default { @{ exists = $true; closed = $false } } } }
        $q = Read-QueueLines @('1', 'a:S0404', 'a:S0009', 'a:S0001', 'b') @{ TicketLookup = $lookup }
        Assert-That ((Get-RowKeys $q.rows) -ceq 'a:S0001 b') "rows '$(Get-RowKeys $q.rows)'"
        Assert-That ((@($q.bad | ForEach-Object { "$($_.kind)@$($_.line)" }) -join ',') -ceq 'unknownTicket@2,closed@3') "bad: $(@($q.bad | ForEach-Object { "$($_.kind)@$($_.line)" }) -join ',')"
    }

    Test-Case 'queue-read: a duplicate row counts once at its first place and is reported once as duplicate' {
        . (Get-LibPath 'queue-file.ps1')
        $q = Read-QueueLines @('2', 'a', '1', 'b', 'a:*', 'c:S1', '3', 'c:S1')
        # The first place is the first in the file: 'a' stays in package 2, its 'a:*' repeat in package 1 is the duplicate.
        Assert-That ((Get-RowKeys $q.rows) -ceq 'b c:S1 a') "rows '$(Get-RowKeys $q.rows)', expected 'b c:S1 a' (a at its first place in the file, package 2)"
        $dups = @($q.bad | Where-Object { $_.kind -ceq 'duplicate' })
        Assert-That ($dups.Count -eq 2 -and $dups[0].line -eq 5 -and $dups[1].line -eq 8) "duplicates: $(@($dups | ForEach-Object { $_.line }) -join ',')"
    }

    # The catalog (rule 44) reads any text after the first token as a comment, so "fms web" is the row fms; a line
    # whose first token is not a row is what does not parse.
    Test-Case 'queue-read: an unparsable line (":S0001", "fms web", "fms-web:") is reported as unparsable and never stops the queue' {
        . (Get-LibPath 'queue-file.ps1')
        $q = Read-QueueLines @('1', ':S0001', 'fms-web:', 'FMS-web', 'a', 'fms web', '2', 'b')
        Assert-That ((Get-RowKeys $q.rows) -ceq 'a fms b') "rows '$(Get-RowKeys $q.rows)', expected 'a fms b'"
        $u = @($q.bad | Where-Object { $_.kind -ceq 'unparsable' } | ForEach-Object { $_.line })
        Assert-That (($u -join ',') -ceq '2,3,4') "unparsable lines: $($u -join ',')"
    }

    Test-Case 'queue-read: the same text read twice gives the same order' {
        . (Get-LibPath 'queue-file.ps1')
        $file = New-QueueFile @('3', 'c', '1', 'a', 'b:S1', '--', 'd', 'hold', 'e')
        $one = ConvertTo-Json -InputObject (Read-PqQueueFile -Path $file) -Depth 6 -Compress
        $two = ConvertTo-Json -InputObject (Read-PqQueueFile -Path $file) -Depth 6 -Compress
        Assert-That ($one -ceq $two) 'two reads of the same text differ'
    }

    Test-Case 'queue-read: an edit between two reads changes the order with no restart' {
        . (Get-LibPath 'queue-file.ps1')
        $file = New-QueueFile @('1', 'a', 'b')
        $one = Read-PqQueueFile -Path $file
        Write-Text $file (Join-Lines @('1', 'b', 'a'))
        $two = Read-PqQueueFile -Path $file
        Assert-That ((Get-RowKeys $one.rows) -ceq 'a b' -and (Get-RowKeys $two.rows) -ceq 'b a') "first '$(Get-RowKeys $one.rows)', second '$(Get-RowKeys $two.rows)'"
        Assert-That ($one.hash -cne $two.hash) 'the hash did not change with the text'
    }

    Test-Case 'queue-read: the reader never writes - bytes, mtime and the directory listing are unchanged' {
        . (Get-LibPath 'queue-file.ps1')
        $file = New-QueueFile @('1', 'a', 'zz', 'hold', 'b') -Crlf -Bom
        $dir = Split-Path -Parent $file
        [IO.File]::SetLastWriteTimeUtc($file, [datetime]::new(2020, 1, 1, 0, 0, 0, [DateTimeKind]::Utc))
        $before = Get-Listing $dir
        $sha = Get-Sha $file
        # Another process holding the file open for writing must not stop the read.
        $fs = [IO.FileStream]::new($file, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::ReadWrite)
        try { $q = Read-PqQueueFile -Path $file -KnownRepos @('a', 'b') -TicketLookup { param($r, $i) @{ exists = $true; closed = $false } } }
        finally { $fs.Dispose() }
        Assert-That ((Get-RowKeys $q.rows) -ceq 'a') 'the read did not happen'
        Assert-That ((Get-Sha $file) -ceq $sha) 'the bytes changed'
        Assert-That ((Get-Listing $dir) -ceq $before) 'the directory listing or the mtime changed'
    }

    if ($vectorDir) {
        Test-Case 'queue-read: portfolio-queue-expected.json agrees for the LF sample and the CRLF+BOM sample' {
            . (Get-LibPath 'queue-file.ps1')
            $expected = @(Get-Content -Raw -LiteralPath (Join-Path $vectorDir 'portfolio-queue-expected.json') | ConvertFrom-Json -DateKind String)
            foreach ($sample in @('PORTFOLIO_QUEUE.sample.md', 'PORTFOLIO_QUEUE.crlf-bom.sample.md')) {
                $file = Join-Path $vectorDir $sample
                Assert-That (Test-Path -LiteralPath $file) "the catalog has no $sample"
                $q = Read-PqQueueFile -Path $file
                if ($sample -like '*crlf*') { Assert-That ($q.bom -and $q.eol -ceq "`r`n") "$sample does not read as BOM and CRLF" }
                # Active rows and the bad rows of the active part in effective order, then the held part in line order.
                $activeBad = @($q.bad | Where-Object { -not $_.held })
                $act = @(@($q.rows | ForEach-Object { [pscustomobject]@{ package = $_.package; packageText = $_.packageText; repo = $_.repo; id = $_.id; kind = $_.kind; held = $false; line = $_.line; status = 'ok' } }) +
                    @($activeBad | ForEach-Object { [pscustomobject]@{ package = $_.package; packageText = $_.packageText; repo = $_.repo; id = $_.id; kind = $_.rowKind; held = $false; line = $_.line; status = $_.kind } }))
                $act = @($act | Sort-Object -Stable -Property package, line)
                $hold = @(@($q.held | ForEach-Object { [pscustomobject]@{ packageText = 'hold'; repo = $_.repo; id = $_.id; kind = $_.kind; held = $true; line = $_.line; status = 'ok' } }) +
                    @($q.bad | Where-Object { $_.held } | ForEach-Object { [pscustomobject]@{ packageText = 'hold'; repo = $_.repo; id = $_.id; kind = $_.rowKind; held = $true; line = $_.line; status = $_.kind } }))
                $hold = @($hold | Sort-Object -Property line)
                $got = @($act) + @($hold)
                Assert-That ($got.Count -eq $expected.Count) "$sample read $($got.Count) entries, the expected file has $($expected.Count)"
                for ($i = 0; $i -lt $expected.Count; $i++) {
                    $e = $expected[$i]; $g = $got[$i]
                    $want = "$($e.package)|$($e.repo)|$($e.id)|$($e.kind)|$($e.held)|$($e.line)|$($e.status)"
                    $have = "$($g.packageText)|$($g.repo)|$($g.id)|$($g.kind)|$($g.held)|$($g.line)|$($g.status)"
                    Assert-That ($want -ceq $have) "$sample entry $($i + 1): read '$have', expected '$want'"
                }
            }
        }
    }
    else { Skip-Case 'queue-read: portfolio-queue-expected.json agrees for the LF sample and the CRLF+BOM sample' 'needs -CatalogRoot' }

    Test-Case 'queue-read: an absent file reads as an empty queue with present false and is not created' {
        . (Get-LibPath 'queue-file.ps1')
        $file = Join-Path (New-Scratch 'absent') 'PORTFOLIO_QUEUE.md'
        $q = Read-PqQueueFile -Path $file
        Assert-That (-not $q.present -and @($q.rows).Count -eq 0 -and @($q.held).Count -eq 0 -and @($q.bad).Count -eq 0) 'an absent file did not read as an empty queue'
        Assert-That (-not (Test-Path -LiteralPath $file)) 'the read created the file'
    }

    # ---------------------------------------------------------------- queue-write
    Test-Case 'queue-write: pin inserts the row directly under the heading of the lowest numbered package' {
        . (Get-LibPath 'queue-file.ps1')
        $file = New-QueueFile @('2', 'b', '1', 'a', '1', 'c')
        $r = Add-PqQueuePin -Path $file -Ticket 'x:S0001'
        Assert-That ($r.ok -and $r.changed) "pin returned ok $($r.ok) error $($r.error)"
        Assert-That (((Get-FileLines $file) -join '|') -ceq '2|b|1|x:S0001|a|1|c') "file after pin: $((Get-FileLines $file) -join '|')"
        Assert-That ((Get-RowKeys (Read-PqQueueFile -Path $file).rows) -ceq 'x:S0001 a c b') 'the pinned row is not first in effective order'
    }

    Test-Case 'queue-write: pin, hold and release on an absent file are refused with QueueFileMissing and create nothing' {
        . (Get-LibPath 'queue-file.ps1')
        $dir = New-Scratch 'absent'
        $file = Join-Path $dir 'PORTFOLIO_QUEUE.md'
        foreach ($r in @((Add-PqQueuePin -Path $file -Ticket 'a:S1'), (Set-PqQueueHold -Path $file -Target 'a'), (Remove-PqQueueHold -Path $file -Target 'a'))) {
            Assert-That (-not $r.ok -and $r.error -ceq 'QueueFileMissing') "returned ok $($r.ok) error $($r.error), expected QueueFileMissing"
        }
        Assert-That (@(Get-ChildItem -LiteralPath $dir -Force).Count -eq 0) 'something was created'
    }

    Test-Case 'queue-write: pin on a file with no numbered package inserts a 1 heading and the row before the first existing heading and changes nothing else' {
        . (Get-LibPath 'queue-file.ps1')
        $file = New-QueueFile @('# owner notes', '', '--', 'e', 'hold', 'h')
        $r = Add-PqQueuePin -Path $file -Ticket 'x:S0001'
        Assert-That $r.ok "pin failed: $($r.error)"
        Assert-That (((Get-FileLines $file) -join '|') -ceq '# owner notes||1|x:S0001||--|e|hold|h') "file after pin: $((Get-FileLines $file) -join '|')"
        $empty = New-QueueFile @('# only a comment')
        $r = Add-PqQueuePin -Path $empty -Ticket 'x:S0001'
        Assert-That (((Get-FileLines $empty) -join '|') -ceq '# only a comment|1|x:S0001|') "comment-only file after pin: $((Get-FileLines $empty) -join '|')"
    }

    Test-Case 'queue-write: pin leaves every other line byte-identical' {
        . (Get-LibPath 'queue-file.ps1')
        $lines = @('# Owner:  keep   my   spacing  ', '', '3', '   c   # odd indent', '1', 'a  # first', 'b:S0002', '', '--', 'z', 'hold', 'h # why')
        $file = New-QueueFile $lines
        $r = Add-PqQueuePin -Path $file -Ticket 'x:S0009'
        Assert-That $r.ok "pin failed: $($r.error)"
        $after = [Collections.Generic.List[string]]::new([string[]](Get-FileLines $file))
        $at = $after.IndexOf('x:S0009')
        Assert-That ($at -eq 5) "the pinned row is at line $($at + 1), expected 6 (under heading 1)"
        $after.RemoveAt($at)
        Assert-That (($after -join "`n") -ceq ($lines -join "`n")) 'another line changed'
    }

    Test-Case 'queue-write: pin of a row already present leaves the old line and the row counts once at the new top' {
        . (Get-LibPath 'queue-file.ps1')
        $file = New-QueueFile @('1', 'a', 'x:S1')
        $null = Add-PqQueuePin -Path $file -Ticket 'x:S1'
        Assert-That (((Get-FileLines $file) -join '|') -ceq '1|x:S1|a|x:S1') "file after pin: $((Get-FileLines $file) -join '|')"
        $q = Read-PqQueueFile -Path $file
        Assert-That ((Get-RowKeys $q.rows) -ceq 'x:S1 a') "rows '$(Get-RowKeys $q.rows)'"
        Assert-That (@($q.bad | Where-Object { $_.kind -ceq 'duplicate' }).Count -eq 1) 'the old line is not reported once as duplicate'
    }

    Test-Case 'queue-write: hold moves an existing row under the hold heading, adding the heading at the end when absent, and moves nothing else' {
        . (Get-LibPath 'queue-file.ps1')
        $file = New-QueueFile @('1', 'a', 'b  # note', '2', 'c')
        $r = Set-PqQueueHold -Path $file -Target 'b'
        Assert-That ($r.ok -and $r.changed) "hold failed: $($r.error)"
        Assert-That (((Get-FileLines $file) -join '|') -ceq '1|a|2|c||hold|b  # note') "file after hold: $((Get-FileLines $file) -join '|')"
        $file2 = New-QueueFile @('1', 'a', 'b', 'hold', 'z', '2', 'c')
        $null = Set-PqQueueHold -Path $file2 -Target 'a'
        Assert-That (((Get-FileLines $file2) -join '|') -ceq '1|b|hold|a|z|2|c') "file after hold with a heading: $((Get-FileLines $file2) -join '|')"
        $again = Set-PqQueueHold -Path $file2 -Target 'a'
        Assert-That ($again.ok -and -not $again.changed) 'holding a held row changed the file'
    }

    Test-Case 'queue-write: hold of a repository key adds the key under hold' {
        . (Get-LibPath 'queue-file.ps1')
        $file = New-QueueFile @('1', 'a', 'k:S0001')
        $r = Set-PqQueueHold -Path $file -Target 'k'
        Assert-That ($r.ok -and $r.changed) "hold failed: $($r.error)"
        Assert-That (((Get-FileLines $file) -join '|') -ceq '1|a|k:S0001||hold|k') "file after hold: $((Get-FileLines $file) -join '|')"
        $q = Read-PqQueueFile -Path $file
        Assert-That ((Get-RowKeys $q.held) -ceq 'k') "held '$(Get-RowKeys $q.held)'"
    }

    Test-Case 'queue-write: release removes the row from under hold and adds it nowhere else, and a row not held is reported NotHeld' {
        . (Get-LibPath 'queue-file.ps1')
        $file = New-QueueFile @('1', 'a', 'hold', 'b', 'c:S1')
        $r = Remove-PqQueueHold -Path $file -Target 'b'
        Assert-That ($r.ok -and $r.changed) "release failed: $($r.error)"
        Assert-That (((Get-FileLines $file) -join '|') -ceq '1|a|hold|c:S1') "file after release: $((Get-FileLines $file) -join '|')"
        $sha = Get-Sha $file
        $n = Remove-PqQueueHold -Path $file -Target 'a'
        Assert-That ($n.ok -and -not $n.changed -and $n.error -ceq 'NotHeld') "release of a row not held returned ok $($n.ok) changed $($n.changed) error $($n.error)"
        Assert-That ((Get-Sha $file) -ceq $sha) 'NotHeld changed the file'
    }

    Test-Case "queue-write: a BOM and the file's line endings are kept (CRLF stays CRLF, LF stays LF)" {
        . (Get-LibPath 'queue-file.ps1')
        $crlf = New-QueueFile @('1', 'a', 'hold', 'b') -Crlf -Bom
        $null = Add-PqQueuePin -Path $crlf -Ticket 'x:S1'
        $null = Set-PqQueueHold -Path $crlf -Target 'a'
        $null = Remove-PqQueueHold -Path $crlf -Target 'b'
        $bytes = [IO.File]::ReadAllBytes($crlf)
        Assert-That ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) 'the BOM was dropped'
        $text = [Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3)
        Assert-That ($text -ceq "1`r`nx:S1`r`nhold`r`na`r`n") "CRLF file after three writes: $($text.Replace("`r", '\r').Replace("`n", '\n'))"
        $lf = New-QueueFile @('1', 'a')
        $null = Add-PqQueuePin -Path $lf -Ticket 'x:S1'
        $b2 = [IO.File]::ReadAllBytes($lf)
        Assert-That ($b2[0] -ne 0xEF) 'a BOM was added'
        Assert-That ([Text.Encoding]::UTF8.GetString($b2) -ceq "1`nx:S1`na`n") 'the LF file did not stay LF'
    }

    Test-Case 'queue-write: a write is atomic, no temp file stays, and it refuses with QueueChangedOnDisk when the file changed between the read and the rename' {
        . (Get-LibPath 'queue-file.ps1')
        $file = New-QueueFile @('1', 'a')
        $dir = Split-Path -Parent $file
        $r = Add-PqQueuePin -Path $file -Ticket 'x:S1' -BeforeRename { Write-Text $file (Join-Lines @('1', 'owner', 'edit')) }
        Assert-That (-not $r.ok -and $r.error -ceq 'QueueChangedOnDisk') "returned ok $($r.ok) error $($r.error), expected QueueChangedOnDisk"
        Assert-That (((Get-FileLines $file) -join '|') -ceq '1|owner|edit') "the owner's edit was overwritten: $((Get-FileLines $file) -join '|')"
        $ok = Set-PqQueueHold -Path $file -Target 'owner'
        Assert-That $ok.ok "a clean write failed: $($ok.error)"
        $names = @(Get-ChildItem -LiteralPath $dir -Force | ForEach-Object Name)
        Assert-That (($names -join ',') -ceq 'PORTFOLIO_QUEUE.md') "entries after the writes: $($names -join ', ')"
    }

    Test-Case 'queue-write: a key not in -KnownRepos is refused with UnknownRepoKey, and an unknown ticket id is never refused' {
        . (Get-LibPath 'queue-file.ps1')
        $file = New-QueueFile @('1', 'a')
        $sha = Get-Sha $file
        foreach ($r in @((Add-PqQueuePin -Path $file -Ticket 'zz:S1' -KnownRepos @('a')), (Set-PqQueueHold -Path $file -Target 'zz' -KnownRepos @('a')))) {
            Assert-That (-not $r.ok -and $r.error -ceq 'UnknownRepoKey') "returned ok $($r.ok) error $($r.error), expected UnknownRepoKey"
        }
        Assert-That ((Get-Sha $file) -ceq $sha) 'a refused write changed the file'
        $u = Add-PqQueuePin -Path $file -Ticket 'a:S9999' -KnownRepos @('a')
        Assert-That ($u.ok -and $u.changed) "an unknown ticket id was refused: $($u.error)"
    }

    Test-Case 'queue-write: every successful write emits queue.edited with hash, rows and hold' {
        . (Get-LibPath 'queue-file.ps1')
        $file = New-QueueFile @('1', 'a', 'b')
        $hashes = @()
        $r = Add-PqQueuePin -Path $file -Ticket 'x:S1' -Log; $hashes += $r.hash
        $r = Set-PqQueueHold -Path $file -Target 'b' -Log; $hashes += $r.hash
        $r = Remove-PqQueueHold -Path $file -Target 'b' -Log; $hashes += $r.hash
        $n = Remove-PqQueueHold -Path $file -Target 'b' -Log
        $null = Close-PqLog
        $ev = @(Get-RootEvents $env:SZA_PORTFOLIO_ROOT | Where-Object { $_.ev -ceq 'queue.edited' })
        Assert-That ($ev.Count -eq 3) "$($ev.Count) queue.edited events, expected 3 (a NotHeld release writes nothing)"
        $got = @($ev | ForEach-Object { "$($_.d.rows)/$($_.d.hold)" }) -join ','
        Assert-That ($got -ceq '3/0,2/1,2/0') "rows/hold of the events: $got"
        Assert-That ((@($ev | ForEach-Object { $_.d.hash }) -join ',') -ceq ($hashes -join ',')) 'the event hashes are not the written hashes'
        Assert-That ($hashes[-1] -ceq (Get-Sha $file)) 'the last hash is not the hash of the file'
    }

    Test-Case 'queue-write: comments and blank lines are never touched' {
        . (Get-LibPath 'queue-file.ps1')
        $file = New-QueueFile @('# top comment', '', '1', 'a  # note on a', '', '# mid comment', '2', 'c', 'hold', 'b # held because')
        $null = Add-PqQueuePin -Path $file -Ticket 'x:S1'
        $null = Set-PqQueueHold -Path $file -Target 'a'
        $null = Remove-PqQueueHold -Path $file -Target 'b'
        $after = Get-FileLines $file
        Assert-That (($after -join '|') -ceq '# top comment||1|x:S1||# mid comment|2|c|hold|a  # note on a') "file after three writes: $($after -join '|')"
    }

    Test-Case 'queue-write: a pin or a hold on a ticket id containing a hyphen (SP-0166) and on a key:* target is parsed and written whole' {
        . (Get-LibPath 'queue-file.ps1')
        $file = New-QueueFile @('1', 'a')
        $null = Add-PqQueuePin -Path $file -Ticket 'sp-mob:SP-0166'
        $null = Set-PqQueueHold -Path $file -Target 'tk:*'
        $null = Set-PqQueueHold -Path $file -Target 'sp-mob:SP-0166'
        Assert-That (((Get-FileLines $file) -join '|') -ceq '1|a||hold|sp-mob:SP-0166|tk:*') "file: $((Get-FileLines $file) -join '|')"
        $r = Remove-PqQueueHold -Path $file -Target 'tk'
        Assert-That ($r.ok -and $r.changed) 'release of tk did not match the tk:* row'
        Assert-That ((Get-RowKeys (Read-PqQueueFile -Path $file).held) -ceq 'sp-mob:SP-0166') 'the hyphenated id was not read whole'
    }

    # ---------------------------------------------------------------- picker
    Test-Case 'picker: returns the documented keys for a fixture with three tickets' {
        . (Get-LibPath 'picker.ps1')
        $repo = New-FixtureRepo -Name 'pk' -Priorities @(40, 80, 60)
        $r = Invoke-PqPicker -RepoPath $repo -HarnessRoot $harness
        Assert-That ($r.ok -and $r.code -eq 0 -and $r.ms -ge 0) "the picker returned ok $($r.ok) code $($r.code) error $($r.error) $($r.message)"
        $names = @($r.payload.PSObject.Properties.Name)
        foreach ($k in @('total', 'eligible_count', 'order_source', 'current_release', 'ranked', 'skip_cache', 'skip_cached_ids', 'skip_cache_overridden_ids',
                'excluded_ids', 'leased_ids', 'auto_skipped', 'malformed', 'claim_lost', 'claimed', 'selected', 'selected_none_reason')) {
            Assert-That ($names -ccontains $k) "the payload has no '$k' (it has $($names -join ' '))"
        }
        Assert-That ($r.payload.total -eq 3 -and @($r.payload.ranked).Count -eq 3) "total $($r.payload.total) ranked $(@($r.payload.ranked).Count)"
        foreach ($k in 'id', 'name', 'status', 'priority', 'updated') { Assert-That ($null -ne $r.payload.ranked[0].PSObject.Properties[$k]) "a ranked row has no $k" }
    }

    Test-Case "picker: SZA_PROJECT_ROOT is set for the child only and the caller's environment is unchanged" {
        . (Get-LibPath 'picker.ps1')
        $dir = New-Scratch 'envprobe'
        $probe = Join-Path $dir 'probe.ps1'
        Write-Text $probe @'
$o = [ordered]@{ root = $env:SZA_PROJECT_ROOT; agent = $env:SZA_AGENT_ID; codex = $env:CODEX_AGENT_ID; other = $env:PQ_PROBE_KEEP; cwd = (Get-Location).Path; args = @($args) }
'noise before the payload'
$o | ConvertTo-Json -Compress
'@
        $repo = New-StampDir 'envrepo'
        $env:SZA_PROJECT_ROOT = 'C:\caller\root'
        $env:SZA_AGENT_ID = 'leaked-session'
        $env:CODEX_AGENT_ID = 'leaked-codex'
        $env:PQ_PROBE_KEEP = 'kept'
        try {
            $r = Invoke-PqPicker -RepoPath $repo -ScriptPath $probe -Exclude @('S0001', 'S0002')
            Assert-That $r.ok "the probe failed: $($r.error) $($r.message)"
            $p = $r.payload
            Assert-That ($p.root -ceq $repo) "the child saw SZA_PROJECT_ROOT '$($p.root)', expected '$repo'"
            Assert-That ($null -eq $p.agent -and $null -eq $p.codex) "the child saw SZA_AGENT_ID '$($p.agent)' CODEX_AGENT_ID '$($p.codex)'"
            Assert-That ($p.other -ceq 'kept') 'an unrelated variable did not reach the child'
            Assert-That ((@($p.args) -join ' ') -ceq '-NoDrift -Format json -Exclude S0001,S0002') "the child's arguments: $(@($p.args) -join ' ')"
            Assert-That ($env:SZA_PROJECT_ROOT -ceq 'C:\caller\root' -and $env:SZA_AGENT_ID -ceq 'leaked-session' -and $env:CODEX_AGENT_ID -ceq 'leaked-codex') "the caller's environment changed"
        }
        finally { $env:CODEX_AGENT_ID = $null; $env:PQ_PROBE_KEEP = $null }
    }

    Test-Case 'picker: -Exclude ids are passed and come back in excluded_ids' {
        . (Get-LibPath 'picker.ps1')
        $repo = New-FixtureRepo -Name 'pk' -Priorities @(40, 80, 60)
        $r = Invoke-PqPicker -RepoPath $repo -HarnessRoot $harness -Exclude @('S0002', 'S0003')
        Assert-That $r.ok "the picker failed: $($r.message)"
        Assert-That ((@($r.payload.excluded_ids) -join ',') -ceq 'S0002,S0003') "excluded_ids [$(@($r.payload.excluded_ids) -join ',')]"
        Assert-That ($r.payload.selected.id -ceq 'S0001') "selected $($r.payload.selected.id), expected S0001"
    }

    Test-Case 'picker: an empty repository returns selected null with selected_none_reason queue-exhausted' {
        . (Get-LibPath 'picker.ps1')
        $repo = New-FixtureRepo -Name 'empty' -Slugs @()
        $r = Invoke-PqPicker -RepoPath $repo -HarnessRoot $harness
        Assert-That $r.ok "the picker failed: $($r.message)"
        Assert-That ($null -eq $r.payload.selected -and $r.payload.selected_none_reason -ceq 'queue-exhausted') "selected $($r.payload.selected) reason $($r.payload.selected_none_reason)"
    }

    Test-Case 'picker: a ticket leased by a sibling is in leased_ids and is not selected' {
        . (Get-LibPath 'picker.ps1')
        $repo = New-FixtureRepo -Name 'pk' -Priorities @(40, 80, 60)
        New-SiblingLease $repo 'S0002'
        $r = Invoke-PqPicker -RepoPath $repo -HarnessRoot $harness
        Assert-That $r.ok "the picker failed: $($r.message)"
        $leased = @($r.payload.leased_ids | ForEach-Object { if ($_ -is [string]) { $_ } else { $_.id } })
        Assert-That ($leased -ccontains 'S0002') "leased_ids [$($leased -join ',')]"
        Assert-That ($r.payload.selected.id -ceq 'S0003') "selected $($r.payload.selected.id), expected S0003 (the next by priority)"
    }

    Test-Case 'picker: never claims (claimed is false) and writes nothing in the repository' {
        . (Get-LibPath 'picker.ps1')
        $repo = New-FixtureRepo -Name 'pk' -Priorities @(40, 80, 60)
        $before = Get-TreeHash @($repo)
        $r = Invoke-PqPicker -RepoPath $repo -HarnessRoot $harness
        $h = Get-PqPickerHead -RepoPath $repo -HarnessRoot $harness -ForceId 'S0001'
        Assert-That ($r.ok -and $r.payload.claimed -eq $false) "claimed is $($r.payload.claimed)"
        Assert-That ($h.ok -and $null -ne $h.head) 'the forced head was not offered'
        $after = Get-TreeHash @($repo)
        if ($after -cne $before) {
            $diff = Compare-Object ($before -split "`n") ($after -split "`n") | ForEach-Object { "$($_.SideIndicator) $($_.InputObject)" }
            throw "the repository changed: $($diff -join '; ')"
        }
    }

    Test-Case 'picker: with no queue file the higher priority ticket is selected first' {
        . (Get-LibPath 'picker.ps1')
        $repo = New-FixtureRepo -Name 'pk' -Priorities @(40, 80, 60)
        Assert-That (-not (Test-Path -LiteralPath (Join-Path $repo 'PLAN\RELEASE_QUEUE.md'))) 'the fixture has a queue file'
        $h = Get-PqPickerHead -RepoPath $repo -HarnessRoot $harness
        Assert-That ($h.ok -and $h.head.id -ceq 'S0002') "head $($h.head.id), expected S0002 (priority 80)"
        Assert-That ((@($h.payload.ranked | ForEach-Object { $_.id }) -join ',') -ceq 'S0002,S0003,S0001') "ranked [$(@($h.payload.ranked | ForEach-Object { $_.id }) -join ',')]"
    }

    Test-Case 'picker: Get-PqTicketRecord finds a ticket in the archive through select.ps1 -IncludeArchived -Format json' {
        . (Get-LibPath 'picker.ps1')
        $repo = New-FixtureRepo -Name 'pk' -Priorities @(40, 80, 60)
        $null = Invoke-Tool $repo 'spec_catalog/archive.ps1' @('-Id', 'S0001')
        $rec = Get-PqTicketRecord -RepoPath $repo -Id 'S0001' -HarnessRoot $harness
        Assert-That ($null -ne $rec -and $rec.id -ceq 'S0001' -and $rec.status -ceq 'Archived') "the archived record: $(ConvertTo-Json $rec -Compress)"
        $live = Get-PqTicketRecord -RepoPath $repo -Id 'S0002' -HarnessRoot $harness
        Assert-That ($null -ne $live -and $live.status -ceq 'Draft') 'an active record was not found'
        Assert-That ($null -eq (Get-PqTicketRecord -RepoPath $repo -Id 'S0099' -HarnessRoot $harness)) 'an absent id returned a record'
    }

    Test-Case 'picker: Get-PqPickerHead -ForceId selects exactly that id when it is offerable and says why when not' {
        . (Get-LibPath 'picker.ps1')
        $repo = New-FixtureRepo -Name 'pk' -Slugs @('one', 'two', 'three', 'gated') -Priorities @(80, 60, 40, 70) -Texts @('', '', '', 'owner directive: the owner starts this one by hand')
        $deep = Get-PqPickerHead -RepoPath $repo -HarnessRoot $harness -ForceId 'S0003'
        Assert-That ($deep.ok -and $deep.head.id -ceq 'S0003') "a deeper ticket was not offered: head $($deep.head.id) why $($deep.why)"
        New-SiblingLease $repo 'S0002'
        $l = Get-PqPickerHead -RepoPath $repo -HarnessRoot $harness -ForceId 'S0002'
        Assert-That ($null -eq $l.head -and $l.why -ceq 'leased') "a leased ticket: head $($l.head) why $($l.why)"
        $g = Get-PqPickerHead -RepoPath $repo -HarnessRoot $harness -ForceId 'S0004'
        Assert-That ($null -eq $g.head -and $g.why -ceq 'owner-gate') "an owner-gated ticket: head $($g.head) why $($g.why)"
        $x = Get-PqPickerHead -RepoPath $repo -HarnessRoot $harness -ForceId 'S0001' -Exclude @('S0001')
        Assert-That ($null -eq $x.head -and $x.why -ceq 'excluded') "an excluded ticket: why $($x.why)"
        $a = Get-PqPickerHead -RepoPath $repo -HarnessRoot $harness -ForceId 'S0099'
        Assert-That ($null -eq $a.head -and $a.why -ceq 'notRanked') "an absent ticket: why $($a.why)"
    }

    Test-Case 'picker: a non-zero exit or unparsable output gives PickerFailed and never throws' {
        . (Get-LibPath 'picker.ps1')
        $dir = New-Scratch 'failprobe'
        $exit3 = Join-Path $dir 'exit3.ps1'
        Write-Text $exit3 "'some text'`n[Console]::Error.WriteLine('broken picker')`n'{""selected"":null}'`nexit 3`n"
        $junk = Join-Path $dir 'junk.ps1'
        Write-Text $junk "'not json at all'`n'{not json either'`n"
        $repo = New-StampDir 'failrepo'
        $r = Invoke-PqPicker -RepoPath $repo -ScriptPath $exit3
        Assert-That (-not $r.ok -and $r.error -ceq 'PickerFailed' -and $r.code -eq 3) "exit 3 gave ok $($r.ok) error $($r.error) code $($r.code)"
        Assert-That ($r.message -match 'broken picker') "stderr was not kept: '$($r.message)'"
        $j = Invoke-PqPicker -RepoPath $repo -ScriptPath $junk
        Assert-That (-not $j.ok -and $j.error -ceq 'PickerFailed') "unparsable output gave ok $($j.ok) error $($j.error)"
        $missing = Invoke-PqPicker -RepoPath $repo -ScriptPath (Join-Path $dir 'nope.ps1')
        Assert-That (-not $missing.ok -and $missing.error -ceq 'PickerFailed') 'a missing script did not give PickerFailed'
    }

    Test-Case 'picker: a child that outlives -TimeoutSeconds is killed with its process tree and gives PickerTimeout' {
        . (Get-LibPath 'picker.ps1')
        $dir = New-Scratch 'slowprobe'
        $pids = Join-Path $dir 'pids.txt'
        $slow = Join-Path $dir 'slow.ps1'
        $pwsh = (Get-Command pwsh -CommandType Application | Select-Object -First 1).Source
        Write-Text $slow @"
`$g = Start-Process -FilePath '$pwsh' -ArgumentList '-NoProfile','-Command','Start-Sleep -Seconds 120' -PassThru -WindowStyle Hidden
Set-Content -LiteralPath '$pids' -Value "`$PID `$(`$g.Id)"
Start-Sleep -Seconds 120
"@
        $repo = New-StampDir 'slowrepo'
        $r = Invoke-PqPicker -RepoPath $repo -ScriptPath $slow -TimeoutSeconds 5
        Assert-That (-not $r.ok -and $r.error -ceq 'PickerTimeout') "returned ok $($r.ok) error $($r.error), expected PickerTimeout"
        Assert-That (Test-Path -LiteralPath $pids) 'the slow child never started its grandchild'
        $ids = @((Get-Content -LiteralPath $pids -Raw).Trim() -split '\s+' | ForEach-Object { [int]$_ })
        $deadline = [DateTime]::UtcNow.AddSeconds(10)
        do {
            $alive = @($ids | Where-Object { $null -ne (Get-Process -Id $_ -ErrorAction Ignore) })
            if ($alive.Count -eq 0) { break }
            Start-Sleep -Milliseconds 200
        } while ([DateTime]::UtcNow -lt $deadline)
        foreach ($id in $alive) { try { Stop-Process -Id $id -Force } catch { } }
        Assert-That ($alive.Count -eq 0) "still alive after the timeout: $($alive -join ', ') (child $($ids[0]), grandchild $($ids[1]))"
    }

    # ---------------------------------------------------------------- rank
    $five = @{ big = @('S0001:50', 'S0002:50', 'S0003:50', 'S0004:50'); r1 = @('S0001:50', 'S0002:50'); r2 = @('S0001:50', 'S0002:50')
        r3 = @('S0001:50', 'S0002:50'); r4 = @('S0001:50', 'S0002:50') }
    $fiveQueue = @('1', 'big', 'r1', 'r2', 'r3', 'r4')
    $fiveRepos = { param([bool]$Concurrent = $true) @((New-RankRepo 'big' -Concurrent $Concurrent -MaxWorkers 3), (New-RankRepo 'r1'), (New-RankRepo 'r2'), (New-RankRepo 'r3'), (New-RankRepo 'r4')) }

    Test-Case 'rank: queue file rows come first, by package and then line order' {
        . (Get-LibPath 'queue-file.ps1'); . (Get-LibPath 'rank.ps1')
        $reg = New-RankRegistry @((New-RankRepo 'a'), (New-RankRepo 'b'), (New-RankRepo 'c'))
        $prov = New-FakeProvider @{ a = @('S0001:90'); b = @('S0001:50'); c = @('S0001:10') }
        $r = Get-PqRank -Registry $reg -Queue (Read-QueueLines @('2', 'a', '1', 'c', 'b')) -HeadProvider $prov
        Assert-That ((Get-CandidateKeys $r) -ceq 'c:S0001 b:S0001 a:S0001') "order '$(Get-CandidateKeys $r)'"
        Assert-That (@($r.candidates | Where-Object { $_.rule -cne 'queueFile' }).Count -eq 0) 'a listed candidate does not carry rule queueFile'
        Assert-That ((@($r.candidates | ForEach-Object { $_.score }) -join ',') -ceq '1,2,3') 'the score of a file row is not its ordinal'
    }

    Test-Case "rank: a key row and a key:* row take the repository's own head, and a key:ID row takes that ticket even when it is not the head" {
        . (Get-LibPath 'queue-file.ps1'); . (Get-LibPath 'rank.ps1')
        $reg = New-RankRegistry @((New-RankRepo 'a'), (New-RankRepo 'b'), (New-RankRepo 'c'))
        $prov = New-FakeProvider @{ a = @('S0001:50'); b = @('S0001:50', 'S0002:50'); c = @('S0001:90', 'S0002:50', 'S0003:10') }
        $r = Get-PqRank -Registry $reg -Queue (Read-QueueLines @('1', 'a', 'b:*', 'c:S0003')) -HeadProvider $prov
        Assert-That ((Get-CandidateKeys $r) -ceq 'a:S0001 b:S0001 c:S0003') "order '$(Get-CandidateKeys $r)'"
    }

    Test-Case 'rank: repositories the file does not list follow all of it, by head priority descending' {
        . (Get-LibPath 'queue-file.ps1'); . (Get-LibPath 'rank.ps1')
        $reg = New-RankRegistry @((New-RankRepo 'c' -Rank 1), (New-RankRepo 'a' -Rank 50), (New-RankRepo 'b' -Rank 99))
        $prov = New-FakeProvider @{ a = @('S0001:10'); b = @('S0001:90'); c = @('S0001:50') }
        $r = Get-PqRank -Registry $reg -Queue (Read-QueueLines @('1', 'a')) -HeadProvider $prov
        Assert-That ((Get-CandidateKeys $r) -ceq 'a:S0001 b:S0001 c:S0001') "order '$(Get-CandidateKeys $r)', expected the file first, then b (90) before c (50) whatever the ranks"
        Assert-That ((@($r.candidates | ForEach-Object { "$($_.rule)/$($_.source)/$($_.score)" }) -join ',') -ceq 'queueFile/queueFile/1,priority/priority/90,priority/priority/50') "rule/source/score: $(@($r.candidates | ForEach-Object { "$($_.rule)/$($_.source)/$($_.score)" }) -join ',')"
    }

    Test-Case 'rank: equal head priority is broken by registry rank ascending and then array order' {
        . (Get-LibPath 'queue-file.ps1'); . (Get-LibPath 'rank.ps1')
        $reg = New-RankRegistry @((New-RankRepo 'b' -Rank 2), (New-RankRepo 'c' -Rank 1), (New-RankRepo 'd' -Rank 2))
        $prov = New-FakeProvider @{ b = @('S0001:50'); c = @('S0001:50'); d = @('S0001:50') }
        $r = Get-PqRank -Registry $reg -HeadProvider $prov
        Assert-That ((Get-CandidateKeys $r) -ceq 'c:S0001 b:S0001 d:S0001') "order '$(Get-CandidateKeys $r)'"
        Assert-That ((@($r.candidates | ForEach-Object { "$($_.rule)/$($_.source)/$($_.score)" }) -join ',') -ceq 'repoRank/repoOrder/1,repoRank/repoOrder/2,repoRank/repoOrder/2') 'a tie is not reported as repoRank with the registry rank as score'
    }

    Test-Case 'rank: rows under hold, a registry hold, and enabled false are excluded and counted under held' {
        . (Get-LibPath 'queue-file.ps1'); . (Get-LibPath 'rank.ps1')
        $reg = New-RankRegistry @((New-RankRepo 'a'), (New-RankRepo 'b' -Hold $true), (New-RankRepo 'c' -Enabled $false), (New-RankRepo 'd'))
        $prov = New-FakeProvider @{ a = @('S0001:50', 'S0002:40'); b = @('S0001:50'); c = @('S0001:50'); d = @('S0001:50') }
        $r = Get-PqRank -Registry $reg -Queue (Read-QueueLines @('1', 'a', 'd', 'b', 'hold', 'd', 'a:S0001')) -HeadProvider $prov
        Assert-That ((Get-CandidateKeys $r) -ceq 'a:S0002') "candidates '$(Get-CandidateKeys $r)', expected 'a:S0002'"
        $sk = (@($r.skipped | ForEach-Object { "$($_.repo)=$($_.why)" }) -join ',')
        Assert-That ($sk -ceq 'b=hold,c=disabled,d=heldByQueue') "skipped: $sk"
        Assert-That ($r.excluded.held -eq 4) "excluded.held $($r.excluded.held), expected 4"
    }

    Test-Case 'rank: a row for a ticket the picker does not offer is skipped for now and the next row is used' {
        . (Get-LibPath 'queue-file.ps1'); . (Get-LibPath 'rank.ps1')
        $reg = New-RankRegistry @((New-RankRepo 'x'), (New-RankRepo 'a'), (New-RankRepo 'b'))
        $prov = New-FakeProvider @{ x = @('S0001:50'); a = @('S0001:50', 'S0002:50'); b = @('S0001:50') } -Leased @{ a = @('S0001') }
        $r = Get-PqRank -Registry $reg -Queue (Read-QueueLines @('1', 'x', 'a:S0001', 'b')) -HeadProvider $prov
        Assert-That ((Get-CandidateKeys $r) -ceq 'x:S0001 b:S0001') "candidates '$(Get-CandidateKeys $r)'"
        $alt = (@($r.candidates[0].alt | ForEach-Object { "$($_.repo):$($_.id)=$($_.why)" }) -join ',')
        Assert-That ($alt -ceq 'a:S0001=notOffered:leased,b:S0001=laterRow') "alt of the first candidate: $alt"
    }

    Test-Case 'rank: an unknown key, an unknown ticket and a closed ticket produce queue.row payloads and are skipped' {
        . (Get-LibPath 'queue-file.ps1'); . (Get-LibPath 'rank.ps1')
        $reg = New-RankRegistry @((New-RankRepo 'a'))
        $prov = New-FakeProvider @{ a = @('S0001:50', 'S0002:50') }
        $lookup = { param($repo, $id) switch ($id) { 'S0404' { @{ exists = $false; closed = $false } } 'S0002' { @{ exists = $true; closed = $true } } default { @{ exists = $true; closed = $false } } } }
        $q = Read-QueueLines @('1', 'zz', 'a:S0404', 'a:S0002', 'a') @{ KnownRepos = @('a'); TicketLookup = $lookup }
        $r = Get-PqRank -Registry $reg -Queue $q -HeadProvider $prov
        $rows = @($r.events | Where-Object { $_.ev -ceq 'queue.row' })
        Assert-That ((@($rows | ForEach-Object { "$($_.d.kind)@$($_.d.line)" }) -join ',') -ceq 'unknownRepo@2,unknownTicket@3,closed@4') "queue.row payloads: $(@($rows | ForEach-Object { "$($_.d.kind)@$($_.d.line)" }) -join ',')"
        Assert-That ((@($rows[0].d.Keys) -join ',') -ceq 'kind,line,text') 'a queue.row payload is not kind, line, text'
        Assert-That ($r.queueBad -eq 3 -and (Get-CandidateKeys $r) -ceq 'a:S0001') "queueBad $($r.queueBad) candidates '$(Get-CandidateKeys $r)'"
        $loose = Get-PqRank -Registry $reg -Queue (Read-QueueLines @('1', 'zz', 'a')) -HeadProvider $prov
        $lr = @($loose.events | Where-Object { $_.ev -ceq 'queue.row' })
        Assert-That ($lr.Count -eq 1 -and $lr[0].d.kind -ceq 'unknownRepo') 'a key the registry does not know was not reported when the reader had no -KnownRepos'
    }

    Test-Case 'rank: the -- package sorts after the numbered packages and before the unlisted repositories' {
        . (Get-LibPath 'queue-file.ps1'); . (Get-LibPath 'rank.ps1')
        $reg = New-RankRegistry @((New-RankRepo 'a'), (New-RankRepo 'b'), (New-RankRepo 'c'))
        $prov = New-FakeProvider @{ a = @('S0001:10'); b = @('S0001:99'); c = @('S0001:10') }
        $r = Get-PqRank -Registry $reg -Queue (Read-QueueLines @('--', 'c', '1', 'a')) -HeadProvider $prov
        Assert-That ((Get-CandidateKeys $r) -ceq 'a:S0001 c:S0001 b:S0001') "order '$(Get-CandidateKeys $r)'"
    }

    Test-Case 'rank: every candidate carries rule and source, and alt holds the top three rejected candidates each with a why from the documented list' {
        . (Get-LibPath 'queue-file.ps1'); . (Get-LibPath 'rank.ps1')
        $reg = New-RankRegistry @((New-RankRepo 'r1'), (New-RankRepo 'r2'), (New-RankRepo 'r3'), (New-RankRepo 'r4'), (New-RankRepo 'r5'), (New-RankRepo 'u'))
        $prov = New-FakeProvider @{ r1 = @('S0001:50'); r2 = @('S0001:50'); r3 = @('S0001:50'); r4 = @('S0001:50'); r5 = @('S0001:50'); u = @('S0001:70') }
        $r = Get-PqRank -Registry $reg -Queue (Read-QueueLines @('1', 'r1', 'r2', '2', 'r3', 'r4', 'r5')) -HeadProvider $prov -Slots 6
        Assert-That (@($r.candidates).Count -eq 6) "$(@($r.candidates).Count) candidates, expected 6"
        foreach ($c in $r.candidates) {
            Assert-That ($c.rule -cin @('queueFile', 'priority', 'repoRank') -and $c.source -cin @('queueFile', 'priority', 'repoOrder')) "$($c.repo): rule $($c.rule) source $($c.source)"
            Assert-That (@($c.alt).Count -le 3) "$($c.repo) has $(@($c.alt).Count) alternatives"
            foreach ($a in $c.alt) { Assert-That ($a.why -cin $validWhy -or $a.why -like 'notOffered:*') "$($c.repo): why '$($a.why)' is not documented" }
        }
        $first = (@($r.candidates[0].alt | ForEach-Object { "$($_.repo)=$($_.why)" }) -join ',')
        Assert-That ($first -ceq 'r2=laterRow,r3=lowerPackage,r4=lowerPackage') "alt of r1: $first"
        $last = (@($r.candidates[4].alt | ForEach-Object { "$($_.repo)=$($_.why)" }) -join ',')
        Assert-That ($last -ceq 'u=lowerPackage') "alt of r5 (the unlisted u below the file): $last"
        Assert-That (@($r.candidates[5].alt).Count -eq 0) 'the last candidate has alternatives'
    }

    Test-Case 'rank: the rank.result payload has heads, the excluded counts (occupied, resource and deviceLevel included), fill, ms, queueRows, queueBad and autoSkipReasons' {
        . (Get-LibPath 'queue-file.ps1'); . (Get-LibPath 'rank.ps1')
        $reg = New-RankRegistry @((New-RankRepo 'a'), (New-RankRepo 'b'))
        $prov = New-FakeProvider @{ a = @('S0001:50', 'S0002:50', 'S0003:50'); b = @('S0001:50') } -Leased @{ b = @('S0009') } -AutoSkip @{ a = @{ S0001 = 'owner-gate'; S0002 = 'blocker-not-verified' } }
        $r = Get-PqRank -Registry $reg -Queue (Read-QueueLines @('1', 'a', 'zz:S1')) -HeadProvider $prov -Fill breadth
        $res = @($r.events | Where-Object { $_.ev -ceq 'rank.result' })
        Assert-That ($res.Count -eq 1) "$($res.Count) rank.result payloads"
        $d = $res[0].d
        Assert-That ((@($d.Keys) -join ',') -ceq 'heads,excluded,autoSkipReasons,fill,ms,queueRows,queueBad') "rank.result keys: $(@($d.Keys) -join ',')"
        $ex = (@($d.excluded.Keys) -join ',')
        Assert-That ($ex -ceq 'blocked,leased,dropped,held,gated,malformed,idleHold,xrepo,settling,levelNotAllowed,occupied,resource,deviceLevel') "excluded keys: $ex"
        Assert-That ($d.excluded.gated -eq 1 -and $d.excluded.blocked -eq 1 -and $d.excluded.leased -eq 1) "gated $($d.excluded.gated) blocked $($d.excluded.blocked) leased $($d.excluded.leased)"
        Assert-That ($d.autoSkipReasons['owner-gate'] -eq 1 -and $d.autoSkipReasons['blocker-not-verified'] -eq 1) "autoSkipReasons: $(ConvertTo-Json $d.autoSkipReasons -Compress)"
        Assert-That ($d.fill -ceq 'breadth' -and $d.queueRows -eq 2 -and $d.queueBad -eq 1 -and $d.ms -ge 0) "fill $($d.fill) queueRows $($d.queueRows) queueBad $($d.queueBad)"
        Assert-That ((@($d.heads | ForEach-Object { "$($_.repo):$($_.id)/$($_.source)/$($_.score)" }) -join ',') -ceq 'a:S0003/queueFile/1,b:S0001/priority/50') "heads: $(@($d.heads | ForEach-Object { "$($_.repo):$($_.id)/$($_.source)/$($_.score)" }) -join ',')"
        Assert-That ((@($d.heads[0].Keys) -join ',') -ceq 'repo,id,source,score') 'a head is not repo, id, source, score'
    }

    Test-Case "rank: -Exclude repo:id yields the repository's next head, and -SkipRepos leaves the repository out" {
        . (Get-LibPath 'queue-file.ps1'); . (Get-LibPath 'rank.ps1')
        $reg = New-RankRegistry @((New-RankRepo 'a'), (New-RankRepo 'b'))
        $prov = New-FakeProvider @{ a = @('S0001:50', 'S0002:50'); b = @('S0001:40') }
        $r = Get-PqRank -Registry $reg -HeadProvider $prov -Exclude @('a:S0001') -SkipRepos @('b')
        Assert-That ((Get-CandidateKeys $r) -ceq 'a:S0002') "candidates '$(Get-CandidateKeys $r)'"
        Assert-That (@($r.skipped | Where-Object { $_.repo -ceq 'b' }).Count -eq 0) 'a skipped repository is listed in skipped'
    }

    Test-Case 'rank: the same inputs give the same order, and nothing is written - no file, no event' {
        . (Get-LibPath 'queue-file.ps1'); . (Get-LibPath 'rank.ps1')
        $reg = & $fiveRepos
        $q = Read-QueueLines @('1', 'r2', 'big', '2', 'r1')
        $root = $env:SZA_PORTFOLIO_ROOT
        $tmp = [IO.Path]::GetTempPath()
        $show = {
            param($r)
            $o = [ordered]@{ c = $r.candidates; p = $r.plan; s = $r.skipped; e = $r.excluded; ev = @($r.events | Where-Object { $_.ev -cne 'rank.result' }) }
            ConvertTo-Json -InputObject $o -Depth 8 -Compress
        }
        $one = Get-PqRank -Registry (New-RankRegistry $reg) -Queue $q -HeadProvider (New-FakeProvider $five)
        $two = Get-PqRank -Registry (New-RankRegistry $reg) -Queue $q -HeadProvider (New-FakeProvider $five)
        Assert-That ((& $show $one) -ceq (& $show $two)) 'two ranks of the same inputs differ'
        Assert-That (-not (Test-Path -LiteralPath $root)) 'the rank created the portfolio root'
        $logs = Get-Variable -Name PqLogs -Scope Script -ValueOnly -ErrorAction Ignore
        Assert-That ($null -eq $logs -or $logs.Count -eq 0) 'the rank opened a log'
    }

    Test-Case 'rank-integration: two fixture repositories and a queue file that lists the lower-priority repository first - the real picker, the file wins' {
        . (Get-LibPath 'queue-file.ps1'); . (Get-LibPath 'rank.ps1'); . (Get-LibPath 'picker.ps1')
        $parent = New-Scratch 'repos'
        $lo = New-FixtureRepo -Name 'lo' -Slugs @('one') -Priorities @(10) -Parent $parent
        $hi = New-FixtureRepo -Name 'hi' -Slugs @('one') -Priorities @(90) -Parent $parent
        $reg = New-RankRegistry @([pscustomobject]@{ key = 'hi'; path = $hi; enabled = $true; rank = 1 }, [pscustomobject]@{ key = 'lo'; path = $lo; enabled = $true; rank = 2 })
        $prov = { param($Repo, $Exclude, $ForceId) Get-PqPickerHead -RepoPath $Repo.path -Exclude $Exclude -ForceId $ForceId -HarnessRoot $harness }
        $r = Get-PqRank -Registry $reg -Queue (Read-QueueLines @('1', 'lo', 'hi')) -HeadProvider $prov
        Assert-That ((Get-CandidateKeys $r) -ceq 'lo:S0001 hi:S0001') "with the file: '$(Get-CandidateKeys $r)', expected lo first"
        $n = Get-PqRank -Registry $reg -HeadProvider $prov
        Assert-That ((Get-CandidateKeys $n) -ceq 'hi:S0001 lo:S0001') "without the file: '$(Get-CandidateKeys $n)', expected hi first (priority 90)"
        Assert-That ($n.candidates[0].priority -eq 90 -and $n.candidates[0].status -ceq 'Draft' -and $n.candidates[0].title -ceq 'task-one') 'the head fields did not come from the real picker'
    }

    Test-Case 'rank: fill depth - a concurrent repository with maxWorkers 3 at the top and four one-worker repositories, five slots, gives the plan 3 + 1 + 1' {
        . (Get-LibPath 'queue-file.ps1'); . (Get-LibPath 'rank.ps1')
        $r = Get-PqRank -Registry (New-RankRegistry (& $fiveRepos)) -Queue (Read-QueueLines $fiveQueue) -HeadProvider (New-FakeProvider $five) -Slots 5 -Fill depth
        Assert-That ((Get-PlanKeys $r) -ceq 'big:S0001 big:S0002 big:S0003 r1:S0001 r2:S0001') "plan '$(Get-PlanKeys $r)'"
        Assert-That ((@($r.plan | ForEach-Object { $_.slot }) -join ',') -ceq '1,2,3,4,5') 'slots are not numbered 1-5'
        $alt = (@($r.candidates[0].alt | ForEach-Object { "$($_.repo)=$($_.why)" }) -join ',')
        Assert-That ($alt -ceq 'r1=laterRow,r2=laterRow,r3=slotsFull') "alt of big: $alt"
    }

    Test-Case 'rank: fill breadth - the same inputs give one worker to each of the first five rows' {
        . (Get-LibPath 'queue-file.ps1'); . (Get-LibPath 'rank.ps1')
        $r = Get-PqRank -Registry (New-RankRegistry (& $fiveRepos)) -Queue (Read-QueueLines $fiveQueue) -HeadProvider (New-FakeProvider $five) -Slots 5 -Fill breadth
        Assert-That ((Get-PlanKeys $r) -ceq 'big:S0001 r1:S0001 r2:S0001 r3:S0001 r4:S0001') "plan '$(Get-PlanKeys $r)'"
        $r7 = Get-PqRank -Registry (New-RankRegistry (& $fiveRepos)) -Queue (Read-QueueLines $fiveQueue) -HeadProvider (New-FakeProvider $five) -Slots 7 -Fill breadth
        Assert-That ((Get-PlanKeys $r7) -ceq 'big:S0001 r1:S0001 r2:S0001 r3:S0001 r4:S0001 big:S0002 big:S0003') "seven slots: '$(Get-PlanKeys $r7)'"
    }

    Test-Case 'rank: depth with fewer slots than the cap gives the top repository every slot' {
        . (Get-LibPath 'queue-file.ps1'); . (Get-LibPath 'rank.ps1')
        $r = Get-PqRank -Registry (New-RankRegistry (& $fiveRepos)) -Queue (Read-QueueLines $fiveQueue) -HeadProvider (New-FakeProvider $five) -Slots 2 -Fill depth
        Assert-That ((Get-PlanKeys $r) -ceq 'big:S0001 big:S0002') "plan '$(Get-PlanKeys $r)'"
    }

    Test-Case 'rank: workers already busy count against the cap (-Busy)' {
        . (Get-LibPath 'queue-file.ps1'); . (Get-LibPath 'rank.ps1')
        $r = Get-PqRank -Registry (New-RankRegistry (& $fiveRepos)) -Queue (Read-QueueLines $fiveQueue) -HeadProvider (New-FakeProvider $five) -Slots 5 -Fill depth -Busy @{ big = 2 }
        Assert-That ((Get-PlanKeys $r) -ceq 'big:S0001 r1:S0001 r2:S0001 r3:S0001 r4:S0001') "plan '$(Get-PlanKeys $r)'"
        $full = Get-PqRank -Registry (New-RankRegistry (& $fiveRepos)) -Queue (Read-QueueLines $fiveQueue) -HeadProvider (New-FakeProvider $five) -Slots 5 -Fill depth -Busy @{ big = 3; r1 = 1 }
        Assert-That ((Get-PlanKeys $full) -ceq 'r2:S0001 r3:S0001 r4:S0001') "busy at the cap: '$(Get-PlanKeys $full)'"
    }

    Test-Case 'rank: a repository that is not concurrent never gets a second worker whatever its tickets' {
        . (Get-LibPath 'queue-file.ps1'); . (Get-LibPath 'rank.ps1')
        foreach ($fill in 'depth', 'breadth') {
            $r = Get-PqRank -Registry (New-RankRegistry (& $fiveRepos $false)) -Queue (Read-QueueLines $fiveQueue) -HeadProvider (New-FakeProvider $five) -Slots 5 -Fill $fill
            Assert-That ((Get-PlanKeys $r) -ceq 'big:S0001 r1:S0001 r2:S0001 r3:S0001 r4:S0001') "$fill plan '$(Get-PlanKeys $r)'"
        }
    }

    Test-Case 'rank: an unlisted repository ranks after the whole file under both policies' {
        . (Get-LibPath 'queue-file.ps1'); . (Get-LibPath 'rank.ps1')
        $reg = New-RankRegistry @((New-RankRepo 'u' -Concurrent $true -MaxWorkers 2 -Rank 1), (New-RankRepo 'f1'), (New-RankRepo 'f2'))
        $table = @{ u = @('S0001:99', 'S0002:99'); f1 = @('S0001:10', 'S0002:10'); f2 = @('S0001:10', 'S0002:10') }
        foreach ($fill in 'depth', 'breadth') {
            $r = Get-PqRank -Registry $reg -Queue (Read-QueueLines @('1', 'f1', 'f2')) -HeadProvider (New-FakeProvider $table) -Slots 5 -Fill $fill
            Assert-That ((Get-CandidateKeys $r) -ceq 'f1:S0001 f2:S0001 u:S0001') "$fill candidates '$(Get-CandidateKeys $r)'"
            Assert-That ((Get-PlanKeys $r) -ceq 'f1:S0001 f2:S0001 u:S0001 u:S0002') "$fill plan '$(Get-PlanKeys $r)'"
        }
    }

    Test-Case 'rank: -Occupied repositories and -TicketBlocked tickets are skipped and counted under occupied, resource and deviceLevel' {
        . (Get-LibPath 'queue-file.ps1'); . (Get-LibPath 'rank.ps1')
        $reg = New-RankRegistry @((New-RankRepo 'a'), (New-RankRepo 'b'), (New-RankRepo 'c'))
        $prov = New-FakeProvider @{ a = @('S0001:50', 'S0002:50'); b = @('S0001:50'); c = @('S0001:50', 'S0002:50') }
        $r = Get-PqRank -Registry $reg -HeadProvider $prov -Occupied @('b') -TicketBlocked @{ 'a:S0001' = 'resource'; 'c:S0001' = 'deviceLevel' }
        Assert-That ((Get-CandidateKeys $r) -ceq 'a:S0002 c:S0002') "candidates '$(Get-CandidateKeys $r)'"
        Assert-That ((@($r.skipped | ForEach-Object { "$($_.repo)=$($_.why)" }) -join ',') -ceq 'b=occupied') "skipped: $(@($r.skipped | ForEach-Object { "$($_.repo)=$($_.why)" }) -join ',')"
        Assert-That ($r.excluded.occupied -eq 1 -and $r.excluded.resource -eq 1 -and $r.excluded.deviceLevel -eq 1) "occupied $($r.excluded.occupied) resource $($r.excluded.resource) deviceLevel $($r.excluded.deviceLevel)"
    }

    # ---------------------------------------------------------------- pq
    Test-Case 'pq: register writes the record - enabled false, maxWorkers 1, concurrent false, role from the stamp, key from the folder name - and is idempotent for the same path' {
        $dir = New-StampDir 'Some.Repo' -Role 'portfolio' -Domains
        $r = Invoke-Pq @('register', '-Path', $dir)
        Assert-That ($r.code -eq 0 -and $r.stdout.Trim() -ceq 'registered some-repo') "register exited $($r.code): $($r.output)"
        $path = Join-Path $env:SZA_PORTFOLIO_ROOT 'repos.json'
        $rec = (Get-Content -Raw -LiteralPath $path | ConvertFrom-Json).repos[0]
        Assert-That ($rec.key -ceq 'some-repo' -and $rec.enabled -eq $false -and $rec.maxWorkers -eq 1 -and $rec.concurrent -eq $false -and $rec.role -ceq 'portfolio') "record: $(ConvertTo-Json $rec -Compress)"
        $sha = Get-Sha $path
        $again = Invoke-Pq @('register', '-Path', $dir)
        Assert-That ($again.code -eq 0 -and $again.stdout.Trim() -ceq 'already registered some-repo') "second register exited $($again.code): $($again.output)"
        Assert-That ((Get-Sha $path) -ceq $sha) 'the second register changed the registry'
    }

    Test-Case 'pq: register refuses a taken key with RepoKeyTaken and a path without a readable stamp with StampMissing, exit 2 and the registry unchanged' {
        $one = New-StampDir 'dup'
        $two = New-StampDir 'dup'
        $none = New-StampDir 'nostamp' -NoStamp
        $null = Invoke-Pq @('register', '-Path', $one)
        $path = Join-Path $env:SZA_PORTFOLIO_ROOT 'repos.json'
        $sha = Get-Sha $path
        $t = Invoke-Pq @('register', '-Path', $two)
        Assert-That ($t.code -eq 2 -and $t.stderr -match '^pq: RepoKeyTaken - ') "a taken key exited $($t.code): $($t.output)"
        $s = Invoke-Pq @('register', '-Path', $none)
        Assert-That ($s.code -eq 2 -and $s.stderr -match '^pq: StampMissing - ') "no stamp exited $($s.code): $($s.output)"
        Assert-That ((Get-Sha $path) -ceq $sha) 'a refused register changed the registry'
        $k = Invoke-Pq @('register', '-Path', $two, '-Key', 'dup-two')
        Assert-That ($k.code -eq 0 -and $k.stdout.Trim() -ceq 'registered dup-two') "-Key did not resolve the clash: $($k.output)"
    }

    Test-Case 'pq: register -Enable writes enabled true' {
        $dir = New-StampDir 'enabled-one'
        $r = Invoke-Pq @('register', '-Path', $dir, '-Enable')
        Assert-That ($r.code -eq 0) "register -Enable exited $($r.code): $($r.output)"
        $rec = (Get-Content -Raw -LiteralPath (Join-Path $env:SZA_PORTFOLIO_ROOT 'repos.json') | ConvertFrom-Json).repos[0]
        Assert-That ($rec.enabled -eq $true -and $rec.maxWorkers -eq 1) "record: $(ConvertTo-Json $rec -Compress)"
    }

    Test-Case 'pq: list prints key, enabled, hold, rank, maxWorkers and path, and -Json is the registry' {
        $dir = New-StampDir 'listed'
        $null = Invoke-Pq @('register', '-Path', $dir, '-Enable')
        $r = Invoke-Pq @('list')
        $line = "listed  enabled=true  hold=false  rank=100  maxWorkers=1  $dir"
        Assert-That ($r.code -eq 0 -and $r.stdout.Trim() -ceq $line) "list printed '$($r.stdout.Trim())', expected '$line'"
        $j = Invoke-Pq @('list', '-Json')
        $doc = $j.stdout | ConvertFrom-Json
        Assert-That ($j.code -eq 0 -and $doc.repos[0].key -ceq 'listed' -and $doc.repos[0].path -ceq $dir) "list -Json: $($j.output)"
    }

    Test-Case 'pq: pin, hold and release call the queue writers, exit 0, and write owner.action and queue.edited to the cli event file' {
        $dir = New-StampDir 'qa'
        $null = Invoke-Pq @('register', '-Path', $dir, '-Enable')
        $init = Invoke-Pq @('queue', '-Init', '-NoOpen')
        Assert-That ($init.code -eq 0) "queue -Init exited $($init.code): $($init.output)"
        foreach ($v in @(@('pin', 'qa:S0001'), @('hold', 'qa:S0001'), @('release', 'qa:S0001'))) {
            $r = Invoke-Pq $v
            Assert-That ($r.code -eq 0) "$($v -join ' ') exited $($r.code): $($r.output)"
        }
        $q = Join-Path $env:SZA_PORTFOLIO_ROOT 'PORTFOLIO_QUEUE.md'
        $tail = ((Get-FileLines $q) | Select-Object -Skip 4) -join '|'
        Assert-That ($tail -ceq '1|qa  # role: product||hold') "the queue file after pin, hold and release ends '$tail'"
        $ev = @(Get-RootEvents $env:SZA_PORTFOLIO_ROOT)
        $files = @(Get-ChildItem -LiteralPath (Join-Path $env:SZA_PORTFOLIO_ROOT 'log') -File | ForEach-Object Name)
        Assert-That (@($files | Where-Object { $_ -notmatch '^events-\d{4}-\d{2}-\d{2}\.cli-\d+\.jsonl$' }).Count -eq 0) "event files: $($files -join ', ')"
        $actions = @($ev | Where-Object { $_.ev -ceq 'owner.action' } | ForEach-Object { $_.d.verb })
        Assert-That (($actions -join ',') -ceq 'register,queue,pin,hold,release') "owner.action verbs: $($actions -join ',')"
        Assert-That (@($ev | Where-Object { $_.ev -ceq 'queue.edited' }).Count -eq 4) "$(@($ev | Where-Object { $_.ev -ceq 'queue.edited' }).Count) queue.edited events, expected 4 (init, pin, hold, release)"
        Assert-That (@($ev | Where-Object { $_.wr -cne 'cli' }).Count -eq 0) 'an event was not written by the cli writer'
    }

    Test-Case 'pq: queue -NoOpen prints the path of an existing file, and with the file absent exits 2 with the -Init hint and creates nothing' {
        $dir = New-StampDir 'qq'
        $null = Invoke-Pq @('register', '-Path', $dir)
        $q = Join-Path $env:SZA_PORTFOLIO_ROOT 'PORTFOLIO_QUEUE.md'
        $r = Invoke-Pq @('queue', '-NoOpen')
        Assert-That ($r.code -eq 2 -and $r.stderr -match "pq: QueueFileMissing - run 'pq queue -Init'") "absent file: exit $($r.code) $($r.output)"
        Assert-That (-not (Test-Path -LiteralPath $q)) 'queue without -Init created the file'
        foreach ($v in @(@('pin', 'qq:S0001'), @('hold', 'qq'), @('release', 'qq'))) {
            $w = Invoke-Pq $v
            Assert-That ($w.code -eq 2 -and $w.stderr -match 'QueueFileMissing') "$($v -join ' ') on an absent file exited $($w.code): $($w.output)"
        }
        Assert-That (-not (Test-Path -LiteralPath $q)) 'a writer created the file'
        $null = Invoke-Pq @('queue', '-Init', '-NoOpen')
        $p = Invoke-Pq @('queue', '-NoOpen')
        Assert-That ($p.code -eq 0 -and $p.stdout.Trim() -ceq $q) "queue -NoOpen printed '$($p.stdout.Trim())', expected '$q'"
    }

    Test-Case 'pq: an unknown verb exits 2 and lists the verbs, and a verb of a later phase (watch, report) exits 2 with "not available in this build"' {
        $r = Invoke-Pq @('bogus')
        Assert-That ($r.code -eq 2 -and $r.stderr -match "unknown verb 'bogus'" -and $r.stderr -match 'dry-run' -and $r.stderr -match 'doctor') "bogus: exit $($r.code) $($r.output)"
        foreach ($v in 'watch', 'report') {
            $x = Invoke-Pq @($v)
            Assert-That ($x.code -eq 2 -and $x.stderr -match "verb '$v' is not available in this build") "${v}: exit $($x.code) $($x.output)"
        }
        Assert-That (-not (Test-Path -LiteralPath $env:SZA_PORTFOLIO_ROOT)) 'a refused verb created the portfolio root'
    }

    Test-Case 'pq: pin of a key the registry does not know exits 2 with UnknownRepoKey and writes nothing' {
        $dir = New-StampDir 'known'
        $null = Invoke-Pq @('register', '-Path', $dir)
        $null = Invoke-Pq @('queue', '-Init', '-NoOpen')
        $q = Join-Path $env:SZA_PORTFOLIO_ROOT 'PORTFOLIO_QUEUE.md'
        $sha = Get-Sha $q
        $r = Invoke-Pq @('pin', 'zz:S0001')
        Assert-That ($r.code -eq 2 -and $r.stderr -match '^pq: UnknownRepoKey - ') "pin zz exited $($r.code): $($r.output)"
        Assert-That ((Get-Sha $q) -ceq $sha) 'the refused pin changed the queue file'
        $pins = @(Get-RootEvents $env:SZA_PORTFOLIO_ROOT | Where-Object { $_.ev -ceq 'owner.action' -and $_.d.verb -ceq 'pin' })
        Assert-That ($pins.Count -eq 0) 'a refused pin was logged as an owner action'
    }

    Test-Case 'pq: owner.action carries parameter names only, never values' {
        $dir = New-StampDir 'secret-folder-name'
        $null = Invoke-Pq @('register', '-Path', $dir, '-Key', 'hidden-key', '-Enable')
        $null = Invoke-Pq @('queue', '-Init', '-NoOpen')
        $null = Invoke-Pq @('pin', 'hidden-key:S0042')
        $null = Invoke-Pq @('hold', 'hidden-key')
        $ev = @(Get-RootEvents $env:SZA_PORTFOLIO_ROOT | Where-Object { $_.ev -ceq 'owner.action' })
        Assert-That ($ev.Count -eq 4) "$($ev.Count) owner.action events, expected 4"
        $names = @('Target', 'Path', 'Key', 'Slots', 'Enable', 'All', 'Init', 'Json', 'NoOpen', 'Help')
        foreach ($e in $ev) {
            foreach ($a in @($e.d.args)) { Assert-That ($names -ccontains [string]$a) "owner.action $($e.d.verb) args holds '$a', not a parameter name" }
            $text = ConvertTo-Json $e -Depth 6 -Compress
            foreach ($secret in 'secret-folder-name', 'hidden-key', 'S0042') { Assert-That (-not $text.Contains($secret)) "owner.action $($e.d.verb) carries the value '$secret'" }
        }
        Assert-That ((@($ev[0].d.args) -join ',') -ceq 'Path,Key,Enable') "register args: $(@($ev[0].d.args) -join ',')"
    }

    # ---------------------------------------------------------------- queue-init
    $initRegistry = {
        Write-Registry (New-RegistryDoc @(
                @{ key = 'fms-web'; path = 'C:\pq-fixture\FastMediaSorter_WEB'; enabled = $true; rank = 999; role = 'product' }
                @{ key = 'epub-2-html'; path = 'C:\pq-fixture\EPUB_2_HTML'; enabled = $false; role = 'product' }
                @{ key = 'fms-win'; path = 'C:\pq-fixture\FastMediaSorter_Lite'; enabled = $true; rank = 2; role = 'product' }
                @{ key = 'fms-a'; path = 'C:\pq-fixture\FastMediaSorter_mob_v2'; enabled = $true; rank = 1; role = 'product' }
                @{ key = 'tourist-mob'; path = 'C:\pq-fixture\Tourist_mob'; enabled = $true; role = 'internal' }
            ))
    }
    $initExpected = @("# PORTFOLIO_QUEUE.md - the owner's file.", '# The order of the lines IS the priority of the projects: top = most important.',
        "# Written once by 'pq queue -Init'. Edit it by hand; only pq pin, pq hold and pq release change it afterwards.", '', '1',
        'fms-a  # role: product', 'fms-win  # role: product', 'epub-2-html  # role: product', 'tourist-mob  # role: internal', 'fms-web  # role: product')

    # Rule 64: the order is the registry rank ascending, then array order; the owner's first order (fms-a and
    # fms-win first, fms-web last) is stated through the ranks of this registry.
    Test-Case 'queue-init: queue -Init -NoOpen writes a first file only when none exists - fms-a, fms-win first, fms-web last, the others between in registry order - each repository line commented with its role' {
        $null = & $initRegistry
        $r = Invoke-Pq @('queue', '-Init', '-NoOpen')
        $q = Join-Path $env:SZA_PORTFOLIO_ROOT 'PORTFOLIO_QUEUE.md'
        Assert-That ($r.code -eq 0 -and $r.stdout.Trim() -ceq "written $q") "queue -Init exited $($r.code): $($r.output)"
        $bytes = [IO.File]::ReadAllBytes($q)
        Assert-That ($bytes[0] -ne 0xEF) 'the first file has a BOM'
        $text = [Text.Encoding]::UTF8.GetString($bytes)
        Assert-That (-not $text.Contains("`r")) 'the first file is not LF'
        Assert-That ($text -ceq (($initExpected -join "`n") + "`n")) "the first file:`n$text"
    }

    Test-Case 'queue-init: a second run changes nothing and exits 0 (bytes and mtime equal)' {
        $null = & $initRegistry
        $null = Invoke-Pq @('queue', '-Init', '-NoOpen')
        $q = Join-Path $env:SZA_PORTFOLIO_ROOT 'PORTFOLIO_QUEUE.md'
        $before = "$(Get-Sha $q)|$((Get-Item -LiteralPath $q).LastWriteTimeUtc.Ticks)"
        $r = Invoke-Pq @('queue', '-Init', '-NoOpen')
        Assert-That ($r.code -eq 0 -and $r.stdout -match '^exists ') "second run exited $($r.code): $($r.output)"
        Assert-That ("$(Get-Sha $q)|$((Get-Item -LiteralPath $q).LastWriteTimeUtc.Ticks)" -ceq $before) 'the second run touched the file'
    }

    Test-Case 'queue-init: an existing file written by the owner is never touched, and no other verb creates the file' {
        $null = & $initRegistry
        $q = Join-Path $env:SZA_PORTFOLIO_ROOT 'PORTFOLIO_QUEUE.md'
        foreach ($v in @(@('pin', 'fms-a:S0001'), @('hold', 'fms-a'), @('release', 'fms-a'), @('queue', '-NoOpen'), @('list'), @('dry-run'), @('doctor'))) {
            $null = Invoke-Pq $v
            Assert-That (-not (Test-Path -LiteralPath $q)) "$($v -join ' ') created the queue file"
        }
        Write-Text $q "# mine`r`n2`r`nfms-web`r`n" -Bom
        $before = "$(Get-Sha $q)|$((Get-Item -LiteralPath $q).LastWriteTimeUtc.Ticks)"
        $r = Invoke-Pq @('queue', '-Init', '-NoOpen')
        Assert-That ($r.code -eq 0) "-Init over the owner's file exited $($r.code): $($r.output)"
        Assert-That ("$(Get-Sha $q)|$((Get-Item -LiteralPath $q).LastWriteTimeUtc.Ticks)" -ceq $before) "the owner's file was touched"
    }

    Test-Case 'queue-init: the file it writes reads back with no bad row and one row per registered repository, and an empty registry writes only the comment header and package 1' {
        . (Get-LibPath 'queue-file.ps1')
        $null = & $initRegistry
        $null = Invoke-Pq @('queue', '-Init', '-NoOpen')
        $q = Join-Path $env:SZA_PORTFOLIO_ROOT 'PORTFOLIO_QUEUE.md'
        $read = Read-PqQueueFile -Path $q -KnownRepos @('fms-web', 'epub-2-html', 'fms-win', 'fms-a', 'tourist-mob')
        Assert-That (@($read.bad).Count -eq 0 -and @($read.rows).Count -eq 5) "bad $(@($read.bad).Count) rows $(@($read.rows).Count)"
        Remove-Item -LiteralPath $q
        Write-Registry (New-RegistryDoc @()) | Out-Null
        $r = Invoke-Pq @('queue', '-Init', '-NoOpen')
        Assert-That ($r.code -eq 0) "-Init on an empty registry exited $($r.code): $($r.output)"
        Assert-That (([IO.File]::ReadAllText($q)) -ceq (($initExpected[0..4] -join "`n") + "`n")) "the empty-registry file:`n$([IO.File]::ReadAllText($q))"
    }

    # ---------------------------------------------------------------- dry-run
    Test-Case 'dry-run: prints the global order with rule, priority and the top-3 alternatives, exit 0' {
        $parent = New-Scratch 'repos'
        $a = New-FixtureRepo -Name 'a' -Slugs @('one', 'two') -Priorities @(40, 80) -Parent $parent
        $b = New-FixtureRepo -Name 'b' -Slugs @('one') -Priorities @(90) -Parent $parent
        $null = Write-Registry (New-RegistryDoc @(@{ key = 'a'; path = $a; enabled = $true }, @{ key = 'b'; path = $b; enabled = $true }))
        Write-Text (Join-Path $env:SZA_PORTFOLIO_ROOT 'PORTFOLIO_QUEUE.md') (Join-Lines @('1', 'a', 'b'))
        $r = Invoke-Pq @('dry-run')
        Assert-That ($r.code -eq 0) "dry-run exited $($r.code): $($r.output)"
        $lines = @($r.stdout -split '\r?\n' | Where-Object { $_ })
        $want = @('pq dry-run: fill=depth slots=5 enabled=2 candidates=2', ' 1. a:S0002  rule=queueFile  pri=80  Draft  task-two', '      alt b:S0001 - laterRow',
            ' 2. b:S0001  rule=queueFile  pri=90  Draft  task-one', 'slot 1: a:S0002', 'slot 2: b:S0001')
        Assert-That (($lines -join "`n") -ceq ($want -join "`n")) "dry-run printed:`n$($lines -join "`n")"
    }

    Test-Case 'dry-run: prints the slot plan for -Slots under the fill in force' {
        $parent = New-Scratch 'repos'
        $big = New-FixtureRepo -Name 'big' -Slugs @('one', 'two', 'three', 'four') -Priorities @(80, 70, 60, 50) -Domains -Parent $parent
        $rx = New-FixtureRepo -Name 'rx' -Slugs @('one') -Priorities @(90) -Parent $parent
        $ry = New-FixtureRepo -Name 'ry' -Slugs @('one') -Priorities @(90) -Parent $parent
        $null = Write-Registry (New-RegistryDoc @(@{ key = 'big'; path = $big; enabled = $true; concurrent = $true; maxWorkers = 3 }, @{ key = 'rx'; path = $rx; enabled = $true }, @{ key = 'ry'; path = $ry; enabled = $true }))
        Write-Text (Join-Path $env:SZA_PORTFOLIO_ROOT 'PORTFOLIO_QUEUE.md') (Join-Lines @('1', 'big', 'rx', 'ry'))
        $r = Invoke-Pq @('dry-run', '-Slots', '5')
        Assert-That ($r.code -eq 0) "dry-run exited $($r.code): $($r.output)"
        $slots = @($r.stdout -split '\r?\n' | Where-Object { $_ -match '^slot ' })
        Assert-That (($slots -join '|') -ceq 'slot 1: big:S0001|slot 2: big:S0002|slot 3: big:S0003|slot 4: rx:S0001|slot 5: ry:S0001') "slots: $($slots -join '|')"
        Assert-That ($r.stdout -match '(?m)^pq dry-run: fill=depth slots=5 enabled=3 ') 'the first line does not say fill=depth slots=5 enabled=3'
    }

    Test-Case 'dry-run: -Json prints the rank object with candidates, plan, skipped, excluded and fill' {
        $a = New-FixtureRepo -Name 'a' -Slugs @('one', 'two') -Priorities @(40, 80)
        $null = Write-Registry (New-RegistryDoc @(@{ key = 'a'; path = $a; enabled = $true }, @{ key = 'off'; path = 'C:\pq-fixture\off'; enabled = $false }))
        $r = Invoke-Pq @('dry-run', '-Json')
        Assert-That ($r.code -eq 0) "dry-run -Json exited $($r.code): $($r.output)"
        $o = $r.stdout | ConvertFrom-Json
        foreach ($k in 'candidates', 'plan', 'skipped', 'excluded', 'fill') { Assert-That ($null -ne $o.PSObject.Properties[$k]) "the JSON has no $k" }
        Assert-That ($o.candidates[0].id -ceq 'S0002' -and $o.candidates[0].rule -ceq 'priority' -and $o.plan[0].id -ceq 'S0002' -and $o.fill -ceq 'depth') "JSON: $($r.stdout)"
        Assert-That ($o.skipped[0].repo -ceq 'off' -and $o.skipped[0].why -ceq 'disabled') 'the disabled repository is not in skipped'
    }

    Test-Case 'dry-run: launches nothing and writes nothing - the portfolio root and every repository tree are byte-identical afterwards and log/ is not created' {
        $parent = New-Scratch 'repos'
        $a = New-FixtureRepo -Name 'a' -Slugs @('one', 'two') -Priorities @(40, 80) -Parent $parent
        $b = New-FixtureRepo -Name 'b' -Slugs @('one') -Priorities @(90) -Parent $parent
        $marker = Join-Path (New-Scratch 'marker') 'launched.txt'
        foreach ($repo in $a, $b) { Write-Text (Join-Path $repo 'r0.ps1') "Set-Content -LiteralPath '$marker' -Value launched`n" }
        $null = Write-Registry (New-RegistryDoc @(@{ key = 'a'; path = $a; enabled = $true }, @{ key = 'b'; path = $b; enabled = $true }))
        Write-Text (Join-Path $env:SZA_PORTFOLIO_ROOT 'PORTFOLIO_QUEUE.md') (Join-Lines @('1', 'b:S0001', 'a', 'zz'))
        $before = Get-TreeHash @($env:SZA_PORTFOLIO_ROOT, $a, $b)
        $r = Invoke-Pq @('dry-run')
        Assert-That ($r.code -eq 0) "dry-run exited $($r.code): $($r.output)"
        $after = Get-TreeHash @($env:SZA_PORTFOLIO_ROOT, $a, $b)
        if ($after -cne $before) {
            $diff = Compare-Object ($before -split "`n") ($after -split "`n") | ForEach-Object { "$($_.SideIndicator) $($_.InputObject)" }
            throw "the dry run changed files: $($diff -join '; ')"
        }
        Assert-That (-not (Test-Path -LiteralPath (Join-Path $env:SZA_PORTFOLIO_ROOT 'log'))) 'log/ was created'
        Assert-That (-not (Test-Path -LiteralPath $marker)) 'a launcher ran'
    }

    Test-Case 'dry-run: an empty registry prints "no enabled repositories" and exits 0, and a missing registry exits 2' {
        $null = Write-Registry (New-RegistryDoc @())
        $r = Invoke-Pq @('dry-run')
        Assert-That ($r.code -eq 0 -and $r.stdout -match '(?m)^no enabled repositories\r?$') "an empty registry: exit $($r.code) $($r.output)"
        $other = Join-Path (New-Scratch 'noreg') 'portfolio'
        $m = Invoke-Pq @('dry-run') @{ SZA_PORTFOLIO_ROOT = $other }
        Assert-That ($m.code -eq 2 -and $m.stderr -match 'RegistryMissing') "a missing registry: exit $($m.code) $($m.output)"
        Assert-That (-not (Test-Path -LiteralPath $other)) 'the dry run created the portfolio root'
    }

    Test-Case 'dry-run: lists skipped repositories with the reason - disabled, hold, heldByQueue, exhausted, allLeased' {
        $parent = New-Scratch 'repos'
        $dis = New-StampDir 'dis' -Parent $parent
        $hld = New-StampDir 'hld' -Parent $parent
        $hq = New-StampDir 'hq' -Parent $parent
        $ex = New-FixtureRepo -Name 'ex' -Slugs @() -Parent $parent
        $al = New-FixtureRepo -Name 'al' -Slugs @('one') -Parent $parent
        $ok = New-FixtureRepo -Name 'ok' -Slugs @('one') -Parent $parent
        New-SiblingLease $al 'S0001'
        $null = Write-Registry (New-RegistryDoc @(@{ key = 'dis'; path = $dis; enabled = $false }, @{ key = 'hld'; path = $hld; enabled = $true; hold = $true },
                @{ key = 'hq'; path = $hq; enabled = $true }, @{ key = 'ex'; path = $ex; enabled = $true }, @{ key = 'al'; path = $al; enabled = $true }, @{ key = 'ok'; path = $ok; enabled = $true }))
        Write-Text (Join-Path $env:SZA_PORTFOLIO_ROOT 'PORTFOLIO_QUEUE.md') (Join-Lines @('1', 'ok', 'hold', 'hq'))
        $r = Invoke-Pq @('dry-run')
        Assert-That ($r.code -eq 0) "dry-run exited $($r.code): $($r.output)"
        $skips = @($r.stdout -split '\r?\n' | Where-Object { $_ -match '^skip ' })
        Assert-That (($skips -join '|') -ceq 'skip dis - disabled|skip hld - hold|skip hq - heldByQueue|skip ex - exhausted|skip al - allLeased') "skip lines: $($skips -join '|')"
        Assert-That ($r.stdout -match '(?m)^slot 1: ok:S0001\r?$') 'the one offerable repository is not planned'
    }

    # ---------------------------------------------------------------- doctor
    Test-Case 'doctor: a healthy fixture repository passes every check, exit 0' {
        $a = New-FixtureRepo -Name 'a' -Slugs @('one')
        $null = Write-Registry (New-RegistryDoc @(@{ key = 'a'; path = $a; enabled = $true }))
        Write-Text (Join-Path $env:SZA_PORTFOLIO_ROOT 'PORTFOLIO_QUEUE.md') (Join-Lines @('1', 'a'))
        $r = Invoke-Pq @('doctor')
        Assert-That ($r.code -eq 0) "doctor exited $($r.code): $($r.output)"
        $lines = @($r.stdout -split '\r?\n' | Where-Object { $_ })
        foreach ($c in 'path', 'stamp', 'profile', 'ledger', 'launcher') { Assert-That (@($lines | Where-Object { $_ -match "^PASS a $c - " }).Count -eq 1) "no 'PASS a $c' line" }
        Assert-That (@($lines | Where-Object { $_ -match '^PASS registry - ' }).Count -eq 1 -and @($lines | Where-Object { $_ -match '^PASS queue - ' }).Count -eq 1) 'no PASS registry or PASS queue line'
        Assert-That ($lines[-1] -ceq 'pq doctor: 1 repositories, 0 FAIL, 0 WARN') "last line '$($lines[-1])'"
    }

    Test-Case 'doctor: each defect fails with its check name and exit 1' {
        $parent = New-Scratch 'repos'
        $defects = [ordered]@{
            da = @('path', { param($d) Remove-Item -LiteralPath $d -Recurse -Force })
            db = @('stamp', { param($d) Remove-Item -LiteralPath (Join-Path $d '.sza-canon.json') })
            dc = @('stamp', { param($d) Write-Text (Join-Path $d '.sza-canon.json') '{"canon":' })
            dd = @('stamp', { param($d) $s = Get-Content -Raw (Join-Path $d '.sza-canon.json') | ConvertFrom-Json; $s.canon.PSObject.Properties.Remove('version'); Write-Json (Join-Path $d '.sza-canon.json') $s })
            de = @('stamp', { param($d) $s = Get-Content -Raw (Join-Path $d '.sza-canon.json') | ConvertFrom-Json; $s.schemaVersion = '2.0'; Write-Json (Join-Path $d '.sza-canon.json') $s })
            df = @('profile', { param($d) Remove-Item -LiteralPath (Join-Path $d '.sza-profile.json') })
            dg = @('profile', { param($d) Write-Text (Join-Path $d '.sza-profile.json') '{"version":' })
            dh = @('profile', { param($d) Write-Text (Join-Path $d '.sza-profile.json') '{"version":"2"}' })
            di = @('ledger', { param($d) [IO.File]::AppendAllText((Join-Path $d 'PLAN\spec-catalog.jsonl'), '{"id":"S00') })
        }
        $repos = foreach ($k in $defects.Keys) {
            $dir = New-FixtureRepo -Name $k -Slugs @('one') -Parent $parent
            & $defects[$k][1] $dir
            @{ key = $k; path = $dir; enabled = $true }
        }
        $null = Write-Registry (New-RegistryDoc @($repos))
        $r = Invoke-Pq @('doctor')
        Assert-That ($r.code -eq 1) "doctor exited $($r.code), expected 1: $($r.output)"
        foreach ($k in $defects.Keys) {
            $check = $defects[$k][0]
            Assert-That ($r.stdout -match "(?m)^FAIL $k $check - ") "no 'FAIL $k $check' line in:`n$($r.stdout)"
        }
    }

    Test-Case 'doctor: a missing launcher, an absent queue file and bad queue rows are warnings, exit 0' {
        $a = New-FixtureRepo -Name 'a' -Slugs @('one')
        Remove-Item -LiteralPath (Join-Path $a 'r0.ps1')
        $null = Write-Registry (New-RegistryDoc @(@{ key = 'a'; path = $a; enabled = $true }))
        $r = Invoke-Pq @('doctor')
        Assert-That ($r.code -eq 0) "doctor exited $($r.code): $($r.output)"
        Assert-That ($r.stdout -match '(?m)^WARN a launcher - ') 'no WARN for the missing launcher'
        Assert-That ($r.stdout -match "(?m)^WARN queue - .*pq queue -Init") 'no WARN with the -Init hint for the absent queue file'
        Write-Text (Join-Path $env:SZA_PORTFOLIO_ROOT 'PORTFOLIO_QUEUE.md') (Join-Lines @('1', 'a', 'zz', ':bad'))
        $b = Invoke-Pq @('doctor')
        Assert-That ($b.code -eq 0 -and $b.stdout -match '(?m)^WARN queue - 2 bad rows\r?$') "bad rows: exit $($b.code) $($b.output)"
        Assert-That ($b.stdout -match '(?m)^pq doctor: 1 repositories, 0 FAIL, 2 WARN\r?$') 'the summary does not count two warnings'
    }

    Test-Case 'doctor: only enabled repositories are checked unless -All' {
        $parent = New-Scratch 'repos'
        $en = New-FixtureRepo -Name 'en' -Slugs @('one') -Parent $parent
        $dis = New-StampDir 'dis' -Parent $parent
        $null = Write-Registry (New-RegistryDoc @(@{ key = 'en'; path = $en; enabled = $true }, @{ key = 'dis'; path = $dis; enabled = $false }))
        $r = Invoke-Pq @('doctor')
        Assert-That ($r.stdout -match '(?m)^PASS en path' -and $r.stdout -notmatch '(?m)^\w+ dis ') "without -All: $($r.stdout)"
        Assert-That ($r.stdout -match '(?m)^pq doctor: 1 repositories') 'the summary does not count one repository'
        $all = Invoke-Pq @('doctor', '-All')
        Assert-That ($all.stdout -match '(?m)^PASS dis path' -and $all.stdout -match '(?m)^FAIL dis profile') "with -All: $($all.stdout)"
        Assert-That ($all.code -eq 1 -and $all.stdout -match '(?m)^pq doctor: 2 repositories') "with -All: exit $($all.code)"
    }

    Test-Case 'doctor: it writes nothing' {
        $a = New-FixtureRepo -Name 'a' -Slugs @('one', 'two')
        $null = Write-Registry (New-RegistryDoc @(@{ key = 'a'; path = $a; enabled = $true }))
        Write-Text (Join-Path $env:SZA_PORTFOLIO_ROOT 'PORTFOLIO_QUEUE.md') (Join-Lines @('1', 'a'))
        $before = Get-TreeHash @($env:SZA_PORTFOLIO_ROOT, $a)
        $r = Invoke-Pq @('doctor', '-All')
        Assert-That ($r.code -eq 0) "doctor exited $($r.code): $($r.output)"
        $after = Get-TreeHash @($env:SZA_PORTFOLIO_ROOT, $a)
        if ($after -cne $before) {
            $diff = Compare-Object ($before -split "`n") ($after -split "`n") | ForEach-Object { "$($_.SideIndicator) $($_.InputObject)" }
            throw "doctor changed files: $($diff -join '; ')"
        }
    }

    # R49: nothing in the portfolio needs Python, which is installed on the owner's machine (3.10 and 3.12).
    Test-Case 'doctor: it runs with every directory that holds a python executable removed from PATH, exits 0, and its output never mentions python' {
        $a = New-FixtureRepo -Name 'a' -Slugs @('one')
        $null = Write-Registry (New-RegistryDoc @(@{ key = 'a'; path = $a; enabled = $true }))
        Write-Text (Join-Path $env:SZA_PORTFOLIO_ROOT 'PORTFOLIO_QUEUE.md') (Join-Lines @('1', 'a'))
        $kept = @($env:PATH -split ';' | Where-Object { $_ -and -not ((Test-Path -LiteralPath (Join-Path $_ 'python.exe')) -or (Test-Path -LiteralPath (Join-Path $_ 'python3.exe')) -or (Test-Path -LiteralPath (Join-Path $_ 'py.exe'))) })
        $pwshDir = Split-Path -Parent (Get-Command pwsh -CommandType Application | Select-Object -First 1).Source
        if ($kept -notcontains $pwshDir) { $kept += $pwshDir }
        $r = Invoke-Pq @('doctor') @{ PATH = ($kept -join ';') }
        Assert-That ($r.code -eq 0) "doctor without python on PATH exited $($r.code): $($r.output)"
        Assert-That ($r.output -notmatch '(?i)python') 'the output mentions python'
    }

    if ($run -eq 0) { throw 'No test cases executed' }
}
catch {
    if ($_.Exception.Message -eq 'No test cases executed') { 'No test cases executed' }
    else { "FAIL setup - $($_.Exception.Message)" }
    $setupFailed = $true
}
finally {
    $env:SZA_PORTFOLIO_ROOT = $savedPortfolioRoot
    $env:USERPROFILE = $savedUserProfile
    $env:SZA_PROJECT_ROOT = $savedProjectRoot
    $env:SZA_AGENT_ID = $savedAgent
    if ($scratch -and -not $KeepScratch -and (Test-Path -LiteralPath $scratch)) {
        Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($setupFailed) { "portfolio-queue-tests: COULD NOT VERIFY (run=$run skipped=$skipped gaps=$gaps)"; exit 2 }
if ($failed -gt 0) { "portfolio-queue-tests: FAIL (run=$run skipped=$skipped gaps=$gaps)"; exit 1 }
"portfolio-queue-tests: PASS (run=$run skipped=$skipped gaps=$gaps)"
exit 0
