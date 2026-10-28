# The portfolio registry, repos.json (TASK-FLOW rules 41, 42 and 60; S0015 R9, R60, R63).
#
# Dot-source this file; it defines functions only, sets no preference and prints nothing. State: none.
# Validation never throws: every problem is an entry @{ name; where; message } of an errors (or warnings) array,
# all of them, not the first. Only I/O throws, and the write path turns its own failures into named errors.
#
#   Read-PqRegistry [-Path <file>] [-ProfileReader <sb>]
#                                   @{ ok; registry; document; errors; warnings; hash; path }. registry is a copy
#                                   with the documented defaults applied; document is the file as parsed (what a
#                                   writer edits and writes back, unknown keys and key order kept). A missing file
#                                   is ok $false with RegistryMissing and creates nothing.
#   Test-PqRegistry -Registry <doc> [-ProfileReader <sb>]
#                                   @{ ok; errors; warnings } for a parsed document (defaults are not applied to it).
#   Write-PqRegistry -Registry <doc> [-Path] [-ExpectedHash <h>]
#                                   @{ ok; error; message; hash }: 2-space JSON, UTF-8 without BOM, LF, a final
#                                   newline, through a temp file in the same directory (<file>.tmp) and a rename.
#                                   With -ExpectedHash the target must still hash to it, else RegistryChangedOnDisk
#                                   and nothing is written. A temp that cannot be written is RegistryWriteFailed.
#   Get-PqRegistryHash [-Path]      lowercase hex SHA-256 of the file bytes, $null when the file is absent.
#   Get-PqEffectiveRepo -Registry -Key
#                                   one repository record with permissionMode inherited, maxWorkers default 1,
#                                   concurrent default false, enabled/hold default false, rank default 100.
#   Get-PqDeclaredLockDomains -RepoPath
#                                   the count of locks.domains entries the repository's .sza-profile.json declares
#                                   as written (never the merged default tree); 0 when absent; a malformed file
#                                   throws 'ProfileUnreadable: <path>'.
#   Test-PqConcurrentCapable -RepoPath [-ProfileReader]
#                                   the one place that decides R63: declared lock domains above 0.
#   Add-PqRepo -Path <dir> [-Key] [-Enable] [-By cli|discovery|edit] [-Log] [-RegistryPath]
#                                   @{ ok; status (registered|already); key; error; message; hash }.
#   Set-PqRepoHold -Key -Hold <bool> [-By] [-Log] [-RegistryPath]
#                                   @{ ok; changed; error; message; hash }.
#   Get-PqRepoKeyFor -Path          a key from the folder name; throws 'RepoKeyInvalid: ..' when none results.

. (Join-Path $PSScriptRoot 'paths.ps1')
. (Join-Path $PSScriptRoot 'events.ps1')
. (Join-Path $PSScriptRoot '..\..\..\lib\schema-carrier.ps1')

$script:PqPermissionModes = @('acceptEdits', 'auto', 'bypassPermissions', 'manual', 'dontAsk', 'plan')
$script:PqRoles = @('product', 'canon-home', 'portfolio', 'internal')
$script:PqLevels = @('light', 'medium', 'hard')
$script:PqKeyPattern = '^[a-z][a-z0-9-]*$'

function Test-PqIntValue($Value) {
    return ($Value -is [int] -or $Value -is [long]) -and $Value -isnot [bool]
}

function Test-PqNumberValue($Value) {
    return ($Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [decimal]) -and $Value -isnot [bool]
}

function Test-PqKeyValue($Value) {
    if ($Value -isnot [string]) { return $false }
    if ($Value -cnotmatch $script:PqKeyPattern) { return $false }
    if ($Value.Length -gt 1 -and [char]::IsDigit($Value[1])) { return $false }
    return $true
}

function Test-PqHasKey($Object, [string]$Name) {
    if ($null -eq $Object) { return $false }
    if ($Object -is [Collections.IDictionary]) { return $Object.Contains($Name) }
    return $null -ne $Object.PSObject.Properties[$Name]
}

function Get-PqValue($Object, [string]$Name, $Default = $null) {
    if (Test-PqHasKey $Object $Name) { return $Object.$Name }
    return $Default
}

function Test-PqObjectValue($Value) {
    return $null -ne $Value -and ($Value -is [Management.Automation.PSCustomObject] -or $Value -is [Collections.IDictionary])
}

function ConvertTo-PqPathKey([string]$Path) {
    $p = $Path.Replace('/', '\').TrimEnd('\')
    if ($p.Length -eq 2 -and $p[1] -eq ':') { $p += '\' }
    return $p.ToLowerInvariant()
}

function Test-PqAbsolutePath($Value) {
    return $Value -is [string] -and $Value.Length -gt 0 -and [IO.Path]::IsPathFullyQualified($Value)
}

function Get-PqFileHash([byte[]]$Bytes) {
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes)).ToLowerInvariant()
}

function Get-PqRegistryHash {
    param([string]$Path)
    if (-not $Path) { $Path = Get-PqPath -Kind registry }
    if (-not [IO.File]::Exists($Path)) { return $null }
    return (Get-PqFileHash ([IO.File]::ReadAllBytes($Path)))
}

function New-PqProblem([string]$Name, [string]$Where, [string]$Message) {
    return [ordered]@{ name = $Name; where = $Where; message = $Message }
}

function Get-PqDeclaredLockDomains {
    param([Parameter(Mandatory)][string]$RepoPath)
    $file = Join-Path $RepoPath '.sza-profile.json'
    if (-not [IO.File]::Exists($file)) { return 0 }
    try { $doc = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($file)) -DateKind String }
    catch { throw "ProfileUnreadable: $file" }
    if (-not (Test-PqObjectValue $doc)) { throw "ProfileUnreadable: $file" }
    $locks = Get-PqValue $doc 'locks'
    if (-not (Test-PqObjectValue $locks)) { return 0 }
    $domains = Get-PqValue $locks 'domains'
    if ($null -eq $domains) { return 0 }
    return @($domains).Count
}

# R63: the one function that decides whether a repository may run several workers. Tightening the criterion
# (for example also requiring concurrency.maxSessions) is a change here and nowhere else.
function Test-PqConcurrentCapable {
    param([Parameter(Mandatory)][string]$RepoPath, [scriptblock]$ProfileReader)
    $count = if ($ProfileReader) { & $ProfileReader $RepoPath } else { Get-PqDeclaredLockDomains -RepoPath $RepoPath }
    return ([int]$count -gt 0)
}

function Test-PqRegistry {
    param([Parameter(Mandatory)][AllowNull()]$Registry, [scriptblock]$ProfileReader)
    $errors = [Collections.Generic.List[object]]::new()
    $warnings = [Collections.Generic.List[object]]::new()
    $add = { param($n, $w, $m) $errors.Add((New-PqProblem $n $w $m)) }
    if (-not (Test-PqObjectValue $Registry)) {
        & $add 'RegistryNotObject' '$' 'the registry is not a JSON object'
        return @{ ok = $false; errors = $errors.ToArray(); warnings = $warnings.ToArray() }
    }
    try { Assert-SzaSchemaCarrier $Registry 'schemaVersion' 'TASK-FLOW registry' }
    catch { & $add 'RegistryVersionUnsupported' 'schemaVersion' $_.Exception.Message }

    $top = 5
    if (Test-PqHasKey $Registry 'maxWorkers') {
        $v = $Registry.maxWorkers
        if (-not (Test-PqIntValue $v) -or $v -lt 1 -or $v -gt 5) { & $add 'MaxWorkersRange' 'maxWorkers' "maxWorkers '$v' is not an integer from 1 to 5" }
        else { $top = [int]$v }
    }
    if (Test-PqHasKey $Registry 'permissionMode') {
        $v = $Registry.permissionMode
        if ($v -isnot [string] -or $v -cnotin $script:PqPermissionModes) { & $add 'PermissionModeInvalid' 'permissionMode' "permissionMode '$v' is not one of $($script:PqPermissionModes -join ' ')" }
    }
    if (Test-PqHasKey $Registry 'fill') {
        $v = $Registry.fill
        if ($v -isnot [string] -or $v -cnotin @('depth', 'breadth')) { & $add 'FillInvalid' 'fill' "fill '$v' is not depth or breadth" }
    }
    if (Test-PqHasKey $Registry 'occupiedMinutes') {
        $v = $Registry.occupiedMinutes
        if (-not (Test-PqIntValue $v) -or $v -lt 1) { & $add 'OccupiedMinutesRange' 'occupiedMinutes' "occupiedMinutes '$v' is not an integer of at least 1" }
    }
    if (Test-PqHasKey $Registry 'pollSeconds') {
        $v = $Registry.pollSeconds
        if (-not (Test-PqIntValue $v) -or $v -lt 1) { & $add 'PollSecondsRange' 'pollSeconds' "pollSeconds '$v' is not an integer of at least 1" }
    }
    if (Test-PqHasKey $Registry 'resources') {
        $res = $Registry.resources
        if (-not (Test-PqObjectValue $res)) { & $add 'ResourceCapInvalid' 'resources' 'resources is not an object' }
        else {
            foreach ($n in @('build', 'emulator')) {
                if (Test-PqHasKey $res $n) {
                    $v = $res.$n
                    if (-not (Test-PqIntValue $v) -or $v -lt 1) { & $add 'ResourceCapInvalid' "resources.$n" "resources.$n '$v' is not a positive integer" }
                }
            }
            if (Test-PqHasKey $res 'device') { & $add 'ResourceDeviceNotAllowed' 'resources.device' 'a robot is never offered hardware: resources.device is refused' }
        }
    }
    if (Test-PqHasKey $Registry 'timing') {
        $t = $Registry.timing
        if (-not (Test-PqObjectValue $t)) { & $add 'TimingValueInvalid' 'timing' 'timing is not an object' }
        else {
            foreach ($p in $t.PSObject.Properties) {
                if (-not (Test-PqNumberValue $p.Value) -or $p.Value -le 0) { & $add 'TimingValueInvalid' "timing.$($p.Name)" "timing.$($p.Name) '$($p.Value)' is not a positive number" }
            }
        }
    }
    $analysis = Get-PqValue $Registry 'analysis'
    if ((Test-PqObjectValue $analysis) -and (Test-PqHasKey $analysis 'thresholds')) {
        $th = $analysis.thresholds
        if (-not (Test-PqObjectValue $th)) { & $add 'ThresholdValueInvalid' 'analysis.thresholds' 'analysis.thresholds is not an object' }
        else {
            foreach ($p in $th.PSObject.Properties) {
                if (-not (Test-PqNumberValue $p.Value)) { & $add 'ThresholdValueInvalid' "analysis.thresholds.$($p.Name)" "analysis.thresholds.$($p.Name) '$($p.Value)' is not a number" }
            }
        }
    }
    if (Test-PqHasKey $Registry 'discoveryRoots') {
        $i = 0
        foreach ($r in @($Registry.discoveryRoots)) {
            if (-not (Test-PqAbsolutePath $r)) { & $add 'DiscoveryRootNotAbsolute' "discoveryRoots[$i]" "discovery root '$r' is not an absolute path" }
            $i++
        }
    }

    # Agents (rule 42).
    $agentNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $hasAgents = Test-PqHasKey $Registry 'agents'
    if ($hasAgents) {
        $i = 0
        foreach ($a in @($Registry.agents)) {
            $w = "agents[$i]"
            $i++
            if (-not (Test-PqObjectValue $a)) { & $add 'AgentNameInvalid' $w 'an agent record is not an object'; continue }
            $name = Get-PqValue $a 'name'
            if (-not (Test-PqKeyValue $name)) { & $add 'AgentNameInvalid' "$w.name" "agent name '$name' does not match the key pattern of rule 41" }
            elseif (-not $agentNames.Add($name)) { & $add 'AgentNameDuplicate' "$w.name" "agent name '$name' is used twice" }
            $cmd = Get-PqValue $a 'command'
            if ($cmd -isnot [string] -or [string]::IsNullOrWhiteSpace($cmd)) { & $add 'AgentCommandMissing' "$w.command" "agent '$name' has no command" }
            $hasMap = Test-PqHasKey $a 'modelByComplexity'
            if ($name -ceq 'claude') {
                $map = Get-PqValue $a 'modelByComplexity'
                $complete = (Test-PqObjectValue $map)
                if ($complete) { foreach ($l in $script:PqLevels) { if ([string]::IsNullOrWhiteSpace([string](Get-PqValue $map $l))) { $complete = $false } } }
                if (-not $complete) { & $add 'AgentModelMapMissing' "$w.modelByComplexity" "agent 'claude' needs modelByComplexity with light, medium and hard" }
            }
            else {
                if ($hasMap) { & $add 'AgentModelMapNotAllowed' "$w.modelByComplexity" "agent '$name' is not claude and must not carry modelByComplexity" }
                foreach ($n in @('model', 'effort')) {
                    $v = Get-PqValue $a $n
                    if ($v -isnot [string] -or [string]::IsNullOrWhiteSpace($v)) { & $add 'AgentModelMissing' "$w.$n" "agent '$name' needs a fixed $n" }
                }
            }
            if (Test-PqHasKey $a 'promptForm') {
                $v = $a.promptForm
                if ($v -isnot [string] -or $v -cnotin @('slash', 'file')) { & $add 'AgentPromptFormInvalid' "$w.promptForm" "promptForm '$v' is not slash or file" }
            }
            if (Test-PqHasKey $a 'levels') {
                foreach ($l in @($a.levels)) {
                    if ($l -isnot [string] -or $l -cnotin $script:PqLevels) { & $add 'AgentLevelsInvalid' "$w.levels" "level '$l' is not light, medium or hard" }
                }
            }
            if (Test-PqHasKey $a 'maxParallel') {
                $v = $a.maxParallel
                if (-not (Test-PqIntValue $v) -or $v -lt 1) { & $add 'AgentMaxParallelRange' "$w.maxParallel" "maxParallel '$v' is not an integer of at least 1" }
            }
            if (Test-PqHasKey $a 'limitDetector') {
                $d = $a.limitDetector
                if (-not (Test-PqObjectValue $d)) { & $add 'LimitDetectorInvalid' "$w.limitDetector" 'limitDetector is not an object' }
                else {
                    $kind = Get-PqValue $d 'kind'
                    if ($kind -isnot [string] -or $kind -cnotin @('transcript', 'log', 'exitText')) { & $add 'LimitDetectorInvalid' "$w.limitDetector.kind" "limitDetector.kind '$kind' is not transcript, log or exitText" }
                    if (Test-PqHasKey $d 'status') {
                        $st = $d.status
                        if ($st -isnot [string] -or $st -cnotin @('proven', 'unproven')) { & $add 'LimitDetectorInvalid' "$w.limitDetector.status" "limitDetector.status '$st' is not proven or unproven" }
                    }
                }
            }
        }
    }
    else { $null = $agentNames.Add('claude') }
    if (Test-PqHasKey $Registry 'agentOrder') {
        $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($n in @($Registry.agentOrder)) {
            if (-not $agentNames.Contains([string]$n)) { & $add 'AgentOrderUnknownAgent' 'agentOrder' "agentOrder names '$n', which is not an agent record" }
            if (-not $seen.Add([string]$n)) { & $add 'AgentOrderDuplicate' 'agentOrder' "agentOrder names '$n' twice" }
        }
    }

    # Repositories (rules 41 and 60).
    if (-not (Test-PqHasKey $Registry 'repos') -or $Registry.repos -isnot [array]) {
        & $add 'ReposMissing' 'repos' 'the registry has no repos array'
    }
    else {
        $keys = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $paths = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $i = 0
        foreach ($r in @($Registry.repos)) {
            $w = "repos[$i]"
            $i++
            if (-not (Test-PqObjectValue $r)) { & $add 'RepoFieldType' $w 'a repository record is not an object'; continue }
            $key = Get-PqValue $r 'key'
            if (-not (Test-PqKeyValue $key)) { & $add 'RepoKeyInvalid' "$w.key" "key '$key' does not match ^[a-z][a-z0-9-]*`$ with a non-digit second character" }
            elseif (-not $keys.Add($key)) { & $add 'RepoKeyDuplicate' "$w.key" "key '$key' is used twice" }
            $where = if (Test-PqKeyValue $key) { "repos[$key]" } else { $w }
            $path = Get-PqValue $r 'path'
            $pathOk = Test-PqAbsolutePath $path
            if (-not $pathOk) { & $add 'RepoPathNotAbsolute' "$where.path" "path '$path' is not an absolute path" }
            elseif (-not $paths.Add((ConvertTo-PqPathKey $path))) { & $add 'RepoPathDuplicate' "$where.path" "path '$path' is registered twice" }
            if (-not (Test-PqHasKey $r 'enabled') -or $r.enabled -isnot [bool]) { & $add 'RepoFieldType' "$where.enabled" 'enabled is required and must be a boolean' }
            foreach ($n in @('hold', 'concurrent')) {
                if ((Test-PqHasKey $r $n) -and $r.$n -isnot [bool]) { & $add 'RepoFieldType' "$where.$n" "$n must be a boolean" }
            }
            if ((Test-PqHasKey $r 'rank') -and -not (Test-PqIntValue $r.rank)) { & $add 'RepoFieldType' "$where.rank" 'rank must be an integer' }
            if ((Test-PqHasKey $r 'permissionMode') -and ($r.permissionMode -isnot [string] -or $r.permissionMode -cnotin $script:PqPermissionModes)) {
                & $add 'PermissionModeInvalid' "$where.permissionMode" "permissionMode '$($r.permissionMode)' is not one of $($script:PqPermissionModes -join ' ')"
            }
            $mw = 1
            if (Test-PqHasKey $r 'maxWorkers') {
                if (-not (Test-PqIntValue $r.maxWorkers)) { & $add 'RepoFieldType' "$where.maxWorkers" 'maxWorkers must be an integer'; $mw = $null }
                elseif ($r.maxWorkers -lt 1 -or $r.maxWorkers -gt $top) { & $add 'RepoMaxWorkersRange' "$where.maxWorkers" "maxWorkers $($r.maxWorkers) is not from 1 to the top-level $top"; $mw = $null }
                else { $mw = [int]$r.maxWorkers }
            }
            $concurrent = (Get-PqValue $r 'concurrent') -eq $true
            if ($null -ne $mw -and $mw -gt 1 -and -not $concurrent) {
                & $add 'MaxWorkersRequiresConcurrent' "$where.maxWorkers" "maxWorkers $mw needs concurrent true (rule 60)"
            }
            elseif (($concurrent -or ($null -ne $mw -and $mw -gt 1)) -and $pathOk) {
                try {
                    if (-not (Test-PqConcurrentCapable -RepoPath $path -ProfileReader $ProfileReader)) {
                        & $add 'ConcurrentWithoutLockDomains' "$where.concurrent" "the profile of $path declares no locks.domains, so concurrent is refused (rule 60)"
                    }
                }
                catch { & $add 'ConcurrentProfileUnreadable' "$where.concurrent" "the profile of $path cannot be read: $($_.Exception.Message)" }
            }
            if (Test-PqHasKey $r 'role') {
                if ($r.role -isnot [string] -or $r.role -cnotin $script:PqRoles) {
                    $warnings.Add((New-PqProblem 'RoleUnknown' "$where.role" "role '$($r.role)' is unknown and reads as product"))
                }
            }
        }
    }
    return @{ ok = ($errors.Count -eq 0); errors = $errors.ToArray(); warnings = $warnings.ToArray() }
}

function Copy-PqJson($Value) {
    return (ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $Value -Depth 64) -DateKind String)
}

function Add-PqDefault($Object, [string]$Name, $Value) {
    if (-not (Test-PqHasKey $Object $Name)) { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value }
}

# The registry with the defaults of rules 41 and 42 applied, as a copy; the document itself is never changed.
function Get-PqRegistryWithDefaults($Document) {
    $r = Copy-PqJson $Document
    Add-PqDefault $r 'schemaVersion' '1.0'
    Add-PqDefault $r 'maxWorkers' 5
    Add-PqDefault $r 'autoEnable' $true
    Add-PqDefault $r 'pollSeconds' 60
    Add-PqDefault $r 'robotDraftCap' 20
    Add-PqDefault $r 'fill' 'depth'
    Add-PqDefault $r 'occupiedMinutes' 10
    if (-not (Test-PqHasKey $r 'resources')) { Add-PqDefault $r 'resources' ([pscustomobject][ordered]@{ build = 3; emulator = 1 }) }
    else {
        Add-PqDefault $r.resources 'build' 3
        Add-PqDefault $r.resources 'emulator' 1
    }
    if (-not (Test-PqHasKey $r 'console')) { Add-PqDefault $r 'console' ([pscustomobject][ordered]@{ quietMinutes = 5; stallMinutes = 15; graceSeconds = 30 }) }
    if (-not (Test-PqHasKey $r 'agents')) {
        $claude = [pscustomobject][ordered]@{
            name = 'claude'; command = 'claude'
            argsTemplate = @('-p', '{prompt}', '--permission-mode', '{permissionMode}', '--model', '{model}')
            headlessMatch = '(?i)\bclaude(\.exe)?\s.*(-p|--print)\b'; promptForm = 'slash'
            modelByComplexity = [pscustomobject][ordered]@{ light = 'haiku'; medium = 'sonnet'; hard = 'opus' }
            maxParallel = 5; levels = @('light', 'medium', 'hard'); contractFile = 'CLAUDE.md'; identityVar = 'SZA_AGENT_ID'
            halt = 'none'; limitPollMinutes = 30
        }
        Add-PqDefault $r 'agents' @($claude)
    }
    if (-not (Test-PqHasKey $r 'agentOrder')) { Add-PqDefault $r 'agentOrder' @(@($r.agents) | ForEach-Object { $_.name }) }
    if (-not (Test-PqHasKey $r 'repos') -or $null -eq $r.repos) { $r | Add-Member -NotePropertyName repos -NotePropertyValue @() -Force }
    foreach ($repo in @($r.repos)) {
        if (-not (Test-PqObjectValue $repo)) { continue }
        Add-PqDefault $repo 'enabled' $false
        Add-PqDefault $repo 'rank' 100
        Add-PqDefault $repo 'maxWorkers' 1
        Add-PqDefault $repo 'concurrent' $false
        Add-PqDefault $repo 'hold' $false
        if (-not (Test-PqHasKey $repo 'role') -or $repo.role -cnotin $script:PqRoles) { $repo | Add-Member -NotePropertyName role -NotePropertyValue 'product' -Force }
    }
    return $r
}

function Read-PqRegistry {
    param([string]$Path, [scriptblock]$ProfileReader)
    if (-not $Path) { $Path = Get-PqPath -Kind registry }
    $result = @{ ok = $false; registry = $null; document = $null; errors = @(); warnings = @(); hash = $null; path = $Path }
    if (-not [IO.File]::Exists($Path)) {
        $result.errors = @(New-PqProblem 'RegistryMissing' '$' "no registry at $Path")
        return $result
    }
    $bytes = [IO.File]::ReadAllBytes($Path)
    $result.hash = Get-PqFileHash $bytes
    $text = [Text.UTF8Encoding]::new($false).GetString($bytes)
    if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) { $text = $text.Substring(1) }
    try { $doc = ConvertFrom-Json -InputObject $text -DateKind String -NoEnumerate }
    catch {
        $result.errors = @(New-PqProblem 'RegistryNotJson' '$' "the registry is not JSON: $($_.Exception.Message)")
        return $result
    }
    if (-not (Test-PqObjectValue $doc)) {
        $result.errors = @(New-PqProblem 'RegistryNotObject' '$' 'the registry is not a JSON object')
        return $result
    }
    $check = Test-PqRegistry -Registry $doc -ProfileReader $ProfileReader
    $result.document = $doc
    $result.errors = $check.errors
    $result.warnings = $check.warnings
    $result.ok = $check.ok
    $result.registry = Get-PqRegistryWithDefaults $doc
    return $result
}

function Write-PqRegistry {
    param([Parameter(Mandatory)]$Registry, [string]$Path, [string]$ExpectedHash)
    if (-not $Path) { $Path = Get-PqPath -Kind registry }
    $json = (ConvertTo-Json -InputObject $Registry -Depth 64).Replace("`r`n", "`n") + "`n"
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($json)
    $temp = "$Path.tmp"
    $dir = Split-Path -Parent $Path
    try {
        if (-not [IO.Directory]::Exists($dir)) { $null = [IO.Directory]::CreateDirectory($dir) }
        [IO.File]::WriteAllBytes($temp, $bytes)
    }
    catch {
        if ([IO.File]::Exists($temp)) { try { [IO.File]::Delete($temp) } catch { } }
        return @{ ok = $false; error = 'RegistryWriteFailed'; message = "cannot write $temp - $($_.Exception.Message)"; hash = (Get-PqRegistryHash -Path $Path) }
    }
    if ($PSBoundParameters.ContainsKey('ExpectedHash')) {
        $now = Get-PqRegistryHash -Path $Path
        if ($now -cne $ExpectedHash) {
            try { [IO.File]::Delete($temp) } catch { }
            return @{ ok = $false; error = 'RegistryChangedOnDisk'; message = "$Path changed on disk since it was read; nothing written"; hash = $now }
        }
    }
    try { [IO.File]::Move($temp, $Path, $true) }
    catch {
        try { [IO.File]::Delete($temp) } catch { }
        return @{ ok = $false; error = 'RegistryWriteFailed'; message = "cannot replace $Path - $($_.Exception.Message)"; hash = (Get-PqRegistryHash -Path $Path) }
    }
    return @{ ok = $true; error = $null; message = $null; hash = (Get-PqFileHash $bytes) }
}

function Get-PqEffectiveRepo {
    param([Parameter(Mandatory)]$Registry, [Parameter(Mandatory)][string]$Key)
    $repo = @($Registry.repos) | Where-Object { (Get-PqValue $_ 'key') -ceq $Key } | Select-Object -First 1
    if ($null -eq $repo) { return $null }
    $e = Copy-PqJson $repo
    Add-PqDefault $e 'enabled' $false
    Add-PqDefault $e 'hold' $false
    Add-PqDefault $e 'rank' 100
    Add-PqDefault $e 'maxWorkers' 1
    Add-PqDefault $e 'concurrent' $false
    Add-PqDefault $e 'permissionMode' (Get-PqValue $Registry 'permissionMode')
    if (-not (Test-PqHasKey $e 'role') -or $e.role -cnotin $script:PqRoles) { $e | Add-Member -NotePropertyName role -NotePropertyValue 'product' -Force }
    return $e
}

function Get-PqRepoKeyFor {
    param([Parameter(Mandatory)][string]$Path)
    $name = Split-Path -Leaf ($Path.TrimEnd('\', '/'))
    $key = ([regex]::Replace($name.ToLowerInvariant(), '[^a-z0-9]+', '-')).Trim('-')
    if (-not (Test-PqKeyValue $key)) { throw "RepoKeyInvalid: no key can be made from the folder name '$name'; pass -Key" }
    return $key
}

# Opens the cli writer when no log is open, so a library -Log call always has a destination (fail-open).
function Write-PqLibEvent([string]$Ev, $D) {
    if ($null -eq $script:PqDefaultLog) { $null = Open-PqLog -Writer cli }
    return (Write-PqEvent -Ev $Ev -D $D)
}

function Read-PqRegistryForWrite([string]$RegistryPath) {
    if (-not [IO.File]::Exists($RegistryPath)) {
        return @{ ok = $true; document = [pscustomobject][ordered]@{ schemaVersion = '1.0'; repos = @() }; hash = $null; fresh = $true }
    }
    $read = Read-PqRegistry -Path $RegistryPath
    if (-not $read.ok) {
        $first = @($read.errors)[0]
        return @{ ok = $false; error = $first.name; message = "the registry is invalid: $($first.where) - $($first.message)" }
    }
    return @{ ok = $true; document = $read.document; hash = $read.hash; fresh = $false }
}

function Add-PqRepo {
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$Key,
        [switch]$Enable,
        [ValidateSet('cli', 'discovery', 'edit')][string]$By = 'cli',
        [switch]$Log,
        [string]$RegistryPath
    )
    if (-not $RegistryPath) { $RegistryPath = Get-PqPath -Kind registry }
    $fail = { param($n, $m) @{ ok = $false; status = $null; key = $Key; error = $n; message = $m; hash = (Get-PqRegistryHash -Path $RegistryPath) } }
    if (-not [IO.Path]::IsPathFullyQualified($Path)) { return (& $fail 'RepoPathNotAbsolute' "path '$Path' is not absolute") }
    $full = ConvertTo-PqFullPath $Path
    $stampFile = Join-Path $full '.sza-canon.json'
    $stamp = $null
    if ([IO.File]::Exists($stampFile)) {
        try { $stamp = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($stampFile)) -DateKind String } catch { $stamp = $null }
    }
    if (-not (Test-PqObjectValue $stamp)) { return (& $fail 'StampMissing' "no readable .sza-canon.json in $full") }
    $role = [string](Get-PqValue $stamp 'role' 'product')
    if ($role -cnotin $script:PqRoles) { $role = 'product' }
    if (-not $Key) {
        try { $Key = Get-PqRepoKeyFor -Path $full } catch { return (& $fail 'RepoKeyInvalid' $_.Exception.Message) }
    }
    elseif (-not (Test-PqKeyValue $Key)) { return (& $fail 'RepoKeyInvalid' "key '$Key' does not match the key pattern of rule 41") }
    $cur = Read-PqRegistryForWrite $RegistryPath
    if (-not $cur.ok) { return (& $fail $cur.error $cur.message) }
    $doc = $cur.document
    $pathKey = ConvertTo-PqPathKey $full
    foreach ($r in @($doc.repos)) {
        if ((Test-PqAbsolutePath (Get-PqValue $r 'path')) -and (ConvertTo-PqPathKey $r.path) -ceq $pathKey) {
            return @{ ok = $true; status = 'already'; key = [string]$r.key; error = $null; message = $null; hash = $cur.hash }
        }
    }
    foreach ($r in @($doc.repos)) {
        if ((Get-PqValue $r 'key') -ceq $Key) { return (& $fail 'RepoKeyTaken' "key '$Key' is registered for $($r.path)") }
    }
    # R63: a repository that joins is always one worker and not concurrent, whatever its profile declares.
    $record = [pscustomobject][ordered]@{ key = $Key; path = $full; enabled = [bool]$Enable; maxWorkers = 1; concurrent = $false; role = $role }
    $doc.repos = @(@($doc.repos) + $record)
    $w = if ($cur.fresh) { Write-PqRegistry -Registry $doc -Path $RegistryPath } else { Write-PqRegistry -Registry $doc -Path $RegistryPath -ExpectedHash $cur.hash }
    if (-not $w.ok) { return (& $fail $w.error $w.message) }
    if ($Log) { $null = Write-PqLibEvent 'registry.changed' ([ordered]@{ by = $By; added = @($Key); removed = @(); hash = $w.hash }) }
    return @{ ok = $true; status = 'registered'; key = $Key; error = $null; message = $null; hash = $w.hash }
}

function Set-PqRepoHold {
    param(
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][bool]$Hold,
        [ValidateSet('cli', 'discovery', 'edit')][string]$By = 'cli',
        [switch]$Log,
        [string]$RegistryPath
    )
    if (-not $RegistryPath) { $RegistryPath = Get-PqPath -Kind registry }
    if (-not [IO.File]::Exists($RegistryPath)) { return @{ ok = $false; changed = $false; error = 'RegistryMissing'; message = "no registry at $RegistryPath"; hash = $null } }
    $cur = Read-PqRegistryForWrite $RegistryPath
    if (-not $cur.ok) { return @{ ok = $false; changed = $false; error = $cur.error; message = $cur.message; hash = (Get-PqRegistryHash -Path $RegistryPath) } }
    $repo = @($cur.document.repos) | Where-Object { (Get-PqValue $_ 'key') -ceq $Key } | Select-Object -First 1
    if ($null -eq $repo) { return @{ ok = $false; changed = $false; error = 'UnknownRepoKey'; message = "no repository '$Key' in the registry"; hash = $cur.hash } }
    if ((Get-PqValue $repo 'hold' $false) -eq $Hold) { return @{ ok = $true; changed = $false; error = $null; message = $null; hash = $cur.hash } }
    if (Test-PqHasKey $repo 'hold') { $repo.hold = $Hold } else { $repo | Add-Member -NotePropertyName hold -NotePropertyValue $Hold }
    $w = Write-PqRegistry -Registry $cur.document -Path $RegistryPath -ExpectedHash $cur.hash
    if (-not $w.ok) { return @{ ok = $false; changed = $false; error = $w.error; message = $w.message; hash = $w.hash } }
    if ($Log) { $null = Write-PqLibEvent 'registry.changed' ([ordered]@{ by = $By; added = @(); removed = @(); hash = $w.hash }) }
    return @{ ok = $true; changed = $true; error = $null; message = $null; hash = $w.hash }
}
