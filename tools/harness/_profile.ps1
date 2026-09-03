#requires -Version 7.0
<#
.SYNOPSIS
    The one seam between the shipped harness and the project it runs in (S2402).

.DESCRIPTION
    Dot-source this file from any harness script. It answers four questions the scripts used
    to answer with a literal: where the project root is, what the project's paths, vocabulary
    and lock domains are, which environment prefix the project uses, and how a harness script
    is invoked from that project. Every answer comes from <project root>/.sza-profile.json,
    merged over the defaults below; a missing profile means the defaults, which describe the
    canon's own conventions (PLAN/, temp/, dev/CHANGELOG.md, the SZA_ prefix).

    The project root is resolved, in order, from:
      1. $env:SZA_PROJECT_ROOT - set by a project's forwarder or by a runner.
      2. the current directory, walking upward to the first .sza-profile.json.
      3. this file's own directory, walking upward the same way - true when the harness sits
         inside the project tree rather than in the plugin cache.
      4. the current directory, walking upward to the first .git.
    A root that cannot be resolved is a terminating error naming the four attempts, never a
    guess: a harness that silently ran against the wrong tree would write journals there.

    Exit codes: none - this is a dot-sourced library and never calls `exit`.

.EXAMPLE
    . (Join-Path $PSScriptRoot '..\_profile.ps1')
    $journal = Get-SzaPath 'journal'
    $id = Get-SzaEnv 'AGENT_ID'            # $env:<prefix>_AGENT_ID
    . (Get-SzaHarnessScript 'locks/agent-lock.ps1')
#>

Set-StrictMode -Version Latest

$Script:SzaHarnessRoot = $PSScriptRoot
if (-not $Script:SzaHarnessRoot) { $Script:SzaHarnessRoot = Split-Path -Parent $MyInvocation.MyCommand.Path }
$Script:SzaProfileFileName = '.sza-profile.json'
$Script:SzaProjectRootCache = $null
$Script:SzaProfileCache = $null

# Defaults describe the canon's own conventions. A project overrides any subset in its profile;
# arrays replace, objects merge key by key.
$Script:SzaProfileDefaults = [ordered]@{
    version     = '1'
    projectName = ''
    envPrefix   = 'SZA'
    paths       = [ordered]@{
        journal          = 'PLAN/spec-catalog.jsonl'
        journalArchive   = 'PLAN/spec-catalog-archive.jsonl'
        burnedIds        = 'PLAN/spec-catalog-burned-ids.jsonl'
        specsDir         = 'PLAN'
        specArchiveDir   = 'PLAN/archive'
        releaseQueue     = 'PLAN/RELEASE_QUEUE.md'
        releaseReady     = 'PLAN/RELEASE_READY.md'
        releaseQueueDone = 'PLAN/RELEASE_QUEUE_DONE.md'
        tempDir          = 'temp'
        locksDir         = 'temp'
        leasesDir        = 'temp/SPEC-TICKET.LEASES'
        leaseHandoffDir  = 'temp/LEASE-HANDOFF'
        lockHandoffDir   = 'temp/LOCK-HANDOFF'
        agentChatDir     = 'temp/AGENT-CHAT'
        queueRunsDir     = 'temp/spec-queue'
        queueStopFile    = 'temp/STOP-SPEC-QUEUE'
        specAllQueueLock = 'temp/spec-all-queue.lock'
        skipCache        = 'temp/spec-next-skip-cache.json'
        migrateDoneDir   = 'temp/done'
        changelog        = 'dev/CHANGELOG.md'
        documentRegistry = 'docs/DOCUMENT_REGISTRY.jsonl'
        docsMap          = 'docs/DOCS_MAP.md'
        sitemap          = 'sitemap.xml'
        allFeatures      = 'docs/ALL_FEATURES.jsonl'
        allFeaturesPrivate = 'docs/ALL_FEATURES_private.jsonl'
        allFeaturesSchema  = 'docs/ALL_FEATURES.schema.json'
        featureMatrix    = ''
        commandsDir      = '.claude/commands'
        probeBaseline    = 'PLAN/probe-baseline.txt'
    }
    grammar     = [ordered]@{
        ticketIdPattern  = '^S\d{4}$'
        specFilePattern  = '^PLAN/(archive/)?S\d{4}_(?!spec_)'
        specFileTemplate = 'PLAN/{0}_{1}.md'
        statusVocabulary = @('Draft', 'Approved', 'Tactical', 'In Progress', 'Implemented', 'Verified',
            'Partial', 'Broken', 'BlockByOtherTask', 'BlockNeedUserTest', 'BlockQuestions', 'BlockExternal', 'Archived')
    }
    modules     = [ordered]@{
        default = 'main'
        names   = @('main')
    }
    locks       = [ordered]@{
        domains   = @(
            [ordered]@{ name = 'Build.Main'; type = 'Build'; rank = 1 }
            [ordered]@{ name = 'Code.Main'; type = 'Code'; rank = 2 }
            [ordered]@{ name = 'Code.Scripts'; type = 'Code'; rank = 3 }
        )
        # First matching rule wins. domain = a concrete domain, a bare type ("Code" = every
        # domain of that type, the fail-closed answer), or null (exempt: no domain at all).
        pathRules = @(
            [ordered]@{ pattern = '^PLAN/'; domain = $null }
            [ordered]@{ pattern = '^(scripts|dev|docs|\.claude|\.github)/'; domain = 'Code.Scripts' }
            [ordered]@{ pattern = '^(CLAUDE|AGENTS|README)\.md$'; domain = 'Code.Scripts' }
            [ordered]@{ pattern = '^src/'; domain = 'Code.Main' }
        )
        agentProcessNames = @('claude.exe', 'claude', 'codex.exe', 'codex')
    }
    probes      = [ordered]@{
        enabled      = $true
        # scanRoots: what the probe GATES walk (module roots). sourceRoots: what previews and
        # drift checks search (the source trees). Both project-relative.
        scanRoots    = @('src')
        sourceRoots  = @('src')
        sourceExtensions = @('.kt', '.java', '.py', '.ts', '.js', '.cs', '.go')
        openerRegex  = 'Timber\.(?<level>[iwed])\('
        formRegex    = '^Timber\.d\(\s*"S(?<num>\d{4}):'
        # {Id} is replaced with the regex-escaped ticket id.
        formRegexForId = '^Timber\.d\(\s*"{Id}:'
        # Per-line form of a probe, for a plain text search.
        tagRegex     = 'Timber\.d\("S\d{4}:'
        # Probe with its message captured, for the acceptance-probe contract (`ticket`, `message`).
        templateRegex = '^Timber\.d\(\s*"(?<ticket>S\d{4}):\s*(?<message>(?:\\.|[^"\\])*)"'
        callTemplate = 'Timber.d("{Id}: {Message}")'
        callName     = 'Timber.d'
    }
    hooks       = [ordered]@{
        # Each entry: { script, args } - args may carry {Module}. Run after a closing transition
        # that changed source, in order; a missing script is reported, not fatal.
        postClose        = @()
        deviceReady      = ''
        deviceReadyArgs  = @()
        # all_features/scan_surface.ps1: the class catalogue it joins against, per module.
        moduleCatalog    = ''
        moduleCatalogSync = ''
    }
    runner      = [ordered]@{
        command          = 'claude'
        promptTemplate   = '/spec-all {Id}'
        decisionStatuses = @('Draft', 'Approved', 'Tactical', 'In Progress', 'Partial', 'Broken', 'BlockQuestions')
        cheapStatuses    = @('Implemented', 'BlockNeedUserTest')
        cheapTierMax     = 3
    }
    commands    = [ordered]@{
        statusCommands = [ordered]@{
            'Draft'            = @('/spec-all {Id}')
            'Approved'         = @('/spec-tech {Id}', '/spec-dev {Id}')
            'Tactical'         = @('/spec-dev {Id}')
            'In Progress'      = @('/spec-dev {Id}')
            'Partial'          = @('/spec-fix {Id}', '/spec-check {Id}')
            'Broken'           = @('/spec-fix {Id}', '/spec-check {Id}')
            'BlockByOtherTask' = @('/spec-tech {Id}', '/spec-dev {Id}')
            'Implemented'      = @('/spec-test-device {Id}', '/spec-check {Id}')
        }
        aliases = @()
    }
    inventory   = [ordered]@{
        dimensionName        = 'dimensions'
        dimensions           = @()
        # Optional second dimension of a record: { name, values }. Empty name = none.
        secondary            = [ordered]@{ name = ''; values = @() }
        noChangePlaceholders = @('no changes', 'без изменений')
    }
    site        = [ordered]@{
        baseUrl       = ''
        locales       = @('en')
        defaultLocale = 'en'
    }
    harness     = [ordered]@{
        # How a harness script is spoken of in this project's hints: a map from a harness-relative
        # path (or "<cluster>/*") to the project-relative path the operator types. Absent entries
        # print the absolute harness path.
        entryPoints = [ordered]@{}
        invokePrefix = 'pwsh -NoProfile -File'
    }
}

function Get-SzaHarnessRoot { return $Script:SzaHarnessRoot }

function Find-SzaMarkerUpward {
    param([Parameter(Mandatory)][string]$Start, [Parameter(Mandatory)][string]$Marker)
    if (-not (Test-Path -LiteralPath $Start)) { return $null }
    $dir = (Resolve-Path -LiteralPath $Start).Path
    if (Test-Path -LiteralPath $dir -PathType Leaf) { $dir = Split-Path -Parent $dir }
    while ($dir) {
        if (Test-Path -LiteralPath (Join-Path $dir $Marker)) { return $dir }
        $parent = Split-Path -Parent $dir
        if (-not $parent -or $parent -eq $dir) { break }
        $dir = $parent
    }
    return $null
}

function Get-SzaProjectRoot {
    <#
    .SYNOPSIS
        Absolute project root, resolved once per process by the four-step rule in the header.
    #>
    if ($Script:SzaProjectRootCache) { return $Script:SzaProjectRootCache }
    $explicit = $env:SZA_PROJECT_ROOT
    if (-not [string]::IsNullOrWhiteSpace($explicit)) {
        if (-not (Test-Path -LiteralPath $explicit -PathType Container)) {
            throw "sza-profile: SZA_PROJECT_ROOT points at '$explicit', which is not a directory."
        }
        $Script:SzaProjectRootCache = (Resolve-Path -LiteralPath $explicit).Path
        return $Script:SzaProjectRootCache
    }
    $cwd = (Get-Location).Path
    $found = Find-SzaMarkerUpward -Start $cwd -Marker $Script:SzaProfileFileName
    if (-not $found) { $found = Find-SzaMarkerUpward -Start $Script:SzaHarnessRoot -Marker $Script:SzaProfileFileName }
    if (-not $found) { $found = Find-SzaMarkerUpward -Start $cwd -Marker '.git' }
    if (-not $found) {
        throw ("sza-profile: cannot resolve the project root - SZA_PROJECT_ROOT is unset, no {0} above '{1}' " +
            "or above '{2}', and no .git above '{1}'. Run from inside the project or set SZA_PROJECT_ROOT.") -f
            $Script:SzaProfileFileName, $cwd, $Script:SzaHarnessRoot
    }
    $Script:SzaProjectRootCache = $found
    return $found
}

function Merge-SzaProfileNode {
    # Defaults are ordered hashtables; the profile arrives as PSCustomObject from ConvertFrom-Json.
    # Objects merge key by key, everything else (arrays, scalars, null) replaces.
    param($Default, $Override)
    if ($null -eq $Override) { return $Default }
    $defaultIsMap = ($Default -is [System.Collections.IDictionary])
    $overrideIsMap = ($Override -is [System.Collections.IDictionary]) -or ($Override -is [pscustomobject] -and -not ($Override -is [string]))
    if (-not ($defaultIsMap -and $overrideIsMap)) { return $Override }
    $out = [ordered]@{}
    foreach ($k in $Default.Keys) { $out[$k] = $Default[$k] }
    # An object with zero properties has no `.Properties.Name` to index under StrictMode - which is
    # exactly what an empty `{}` in a profile is, and what the template's own empty sections are.
    $overrideKeys = if ($Override -is [System.Collections.IDictionary]) { @($Override.Keys) } else { @($Override.PSObject.Properties | ForEach-Object { $_.Name }) }
    foreach ($k in $overrideKeys) {
        # Read with a plain assignment, never `$v = if (..) {..} else {..}`: the output of an `if`
        # EXPRESSION goes through the pipeline, which unrolls an empty array to nothing, so an
        # empty list in the profile would arrive as $null - and `@($null).Count` is 1, which is how
        # "this project declares no aliases" became one blank alias row. The same reason keeps the
        # array branch below out of a returned value: `[object[]]@(..)` stored by an expression is
        # the only shape that survives.
        $v = $null
        if ($Override -is [System.Collections.IDictionary]) { $v = $Override[$k] } else { $v = $Override.$k }
        if ($v -is [array]) { $out[$k] = [object[]]@($v); continue }
        if ($out.Contains($k)) { $out[$k] = Merge-SzaProfileNode -Default $out[$k] -Override $v }
        else { $out[$k] = $v }
    }
    return $out
}

function ConvertTo-SzaProfileObject {
    # Ordered hashtables become PSCustomObjects so callers read `$p.paths.journal` uniformly.
    param($Node)
    if ($Node -is [System.Collections.IDictionary]) {
        $o = [ordered]@{}
        foreach ($k in $Node.Keys) {
            # Same rule as in Merge-SzaProfileNode: an array is built by an expression and stored,
            # never returned from a call, so an empty one survives as an empty one.
            $child = $Node[$k]
            if ($child -is [array]) { $o[$k] = [object[]]@($child | ForEach-Object { ConvertTo-SzaProfileObject $_ }); continue }
            $o[$k] = ConvertTo-SzaProfileObject $child
        }
        return [pscustomobject]$o
    }
    if ($Node -is [array]) { return [object[]]@($Node | ForEach-Object { ConvertTo-SzaProfileObject $_ }) }
    return $Node
}

function Get-SzaProfile {
    <#
    .SYNOPSIS
        The merged profile as one object tree, read once per process.
    #>
    if ($Script:SzaProfileCache) { return $Script:SzaProfileCache }
    $root = Get-SzaProjectRoot
    $path = Join-Path $root $Script:SzaProfileFileName
    # A test or a migration may point at another profile file without touching the project's.
    if (-not [string]::IsNullOrWhiteSpace($env:SZA_PROFILE_PATH)) {
        $path = $env:SZA_PROFILE_PATH
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "sza-profile: SZA_PROFILE_PATH points at '$path', which does not exist." }
    }
    $merged = $Script:SzaProfileDefaults
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        try {
            $json = Get-Content -LiteralPath $path -Raw -Encoding utf8 | ConvertFrom-Json
        } catch {
            throw "sza-profile: '$path' is not valid JSON - $($_.Exception.Message)"
        }
        $merged = Merge-SzaProfileNode -Default $Script:SzaProfileDefaults -Override $json
    }
    $Script:SzaProfileCache = ConvertTo-SzaProfileObject $merged
    return $Script:SzaProfileCache
}

function Test-SzaHasProperty {
    # StrictMode-safe: an object with zero properties has no `.Properties.Name` to index.
    param($Object, [Parameter(Mandatory)][string]$Name)
    if ($null -eq $Object) { return $false }
    if ($Object -is [System.Collections.IDictionary]) { return $Object.Contains($Name) }
    return ($null -ne $Object.PSObject.Properties[$Name])
}

function Get-SzaProfileValue {
    <#
    .SYNOPSIS
        One value by dotted path, e.g. 'grammar.ticketIdPattern'. Throws on an unknown key so a
        typo cannot read as "not configured".
    #>
    param([Parameter(Mandatory)][string]$Path)
    $node = Get-SzaProfile
    foreach ($part in ($Path -split '\.')) {
        if (-not (Test-SzaHasProperty -Object $node -Name $part)) {
            throw "sza-profile: no profile value at '$Path' (stopped at '$part')."
        }
        $node = $node.$part
    }
    # A bare return is correct for both shapes here, and the two idioms that look safer are not:
    # `@(f)` around a function returning an empty array is already 0, while `,$node` and
    # `Write-Output -NoEnumerate` both hand the caller a one-element wrapper instead of the list.
    return $node
}

function Get-SzaPath {
    <#
    .SYNOPSIS
        Absolute path for a `paths.<Key>` entry. A relative value is joined onto the project root;
        an absolute one is returned as is. Separators are normalised for this OS.
    .PARAMETER Relative
        Return the profile's own (project-relative) string instead - for messages and journals.
    #>
    param([Parameter(Mandatory)][string]$Key, [switch]$Relative)
    $value = [string](Get-SzaProfileValue "paths.$Key")
    if ([string]::IsNullOrWhiteSpace($value)) { throw "sza-profile: paths.$Key is empty in the profile." }
    if ($Relative) { return $value }
    if ([System.IO.Path]::IsPathRooted($value)) { return $value }
    $joined = Join-Path (Get-SzaProjectRoot) $value
    return $joined.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
}

function Get-SzaEnvName {
    <#
    .SYNOPSIS
        The full environment-variable name for a harness variable: '<envPrefix>_<Suffix>'.
    #>
    param([Parameter(Mandatory)][string]$Suffix)
    return ('{0}_{1}' -f (Get-SzaProfileValue 'envPrefix'), $Suffix)
}

function Get-SzaEnv {
    param([Parameter(Mandatory)][string]$Suffix)
    return [System.Environment]::GetEnvironmentVariable((Get-SzaEnvName $Suffix))
}

function Set-SzaEnv {
    # $null or '' removes the variable, matching `$env:X = $null`.
    param([Parameter(Mandatory)][string]$Suffix, [AllowNull()][AllowEmptyString()][string]$Value)
    [System.Environment]::SetEnvironmentVariable((Get-SzaEnvName $Suffix), $Value)
}

function Get-SzaHarnessScript {
    <#
    .SYNOPSIS
        Absolute path of a sibling harness script by its harness-relative path.
    #>
    param([Parameter(Mandatory)][string]$RelativePath)
    $p = Join-Path $Script:SzaHarnessRoot ($RelativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { throw "sza-profile: harness script '$RelativePath' is missing at '$p'." }
    return $p
}

function Get-SzaInvocation {
    <#
    .SYNOPSIS
        How the operator invokes a harness script in THIS project, for hints and messages:
        the profile's entry point when one is mapped, the absolute harness path otherwise.
    #>
    param([Parameter(Mandatory)][string]$RelativePath, [string]$Arguments = '')
    $map = Get-SzaProfileValue 'harness.entryPoints'
    $prefix = [string](Get-SzaProfileValue 'harness.invokePrefix')
    $target = $null
    if (Test-SzaHasProperty -Object $map -Name $RelativePath) { $target = [string]$map.$RelativePath }
    if (-not $target) {
        $cluster = ($RelativePath -split '/')[0]
        $wild = "$cluster/*"
        if (Test-SzaHasProperty -Object $map -Name $wild) {
            $target = ([string]$map.$wild) -replace '\*$', (Split-Path $RelativePath -Leaf)
        }
    }
    if (-not $target) { $target = Join-Path $Script:SzaHarnessRoot $RelativePath }
    $line = "$prefix $target"
    if ($Arguments) { $line += " $Arguments" }
    return $line
}

function Get-SzaHook {
    <#
    .SYNOPSIS
        Absolute path of a project hook script named in `hooks.<Key>`, or $null when unset.
    #>
    param([Parameter(Mandatory)][string]$Key)
    $value = Get-SzaProfileValue "hooks.$Key"
    if ($null -eq $value -or [string]::IsNullOrWhiteSpace([string]$value)) { return $null }
    $s = [string]$value
    if ([System.IO.Path]::IsPathRooted($s)) { return $s }
    return (Join-Path (Get-SzaProjectRoot) $s)
}

function Show-SzaHelp {
    <#
    .SYNOPSIS
        Print a script's comment-based help - the -Help switch every harness CLI carries.
    #>
    param([Parameter(Mandatory)][string]$Path)
    Get-Help -Name $Path -Detailed | Out-String -Width 120 | Write-Host
}

function Test-SzaStatusName {
    param([Parameter(Mandatory)][string]$Status)
    return ((Get-SzaProfileValue 'grammar.statusVocabulary') -contains $Status)
}

function Get-SzaAgentProcesses {
    <#
    .SYNOPSIS
        Live agent-runtime processes (locks.agentProcessNames), with CommandLine, or @().
        Windows-only by construction (Win32_Process); elsewhere it answers empty and the callers
        that read it treat "no headless child" as the honest answer.
    #>
    $names = @((Get-SzaProfileValue 'locks.agentProcessNames') | ForEach-Object { [string]$_ })
    if ($names.Count -eq 0) { return @() }
    if (-not (Get-Command Get-CimInstance -ErrorAction SilentlyContinue)) { return @() }
    $filter = ($names | ForEach-Object { "Name = '$($_.Replace("'", "''"))'" }) -join ' OR '
    try {
        return @(Get-CimInstance Win32_Process -Filter $filter -ErrorAction SilentlyContinue)
    } catch {
        return @()
    }
}

function Get-SzaTicketIdFragment {
    <#
    .SYNOPSIS
        The ticket-id pattern without its ^ and $ anchors, for embedding in a larger regex.
    #>
    $p = [string](Get-SzaProfileValue 'grammar.ticketIdPattern')
    return ($p -replace '^\^', '') -replace '\$$', ''
}

function Get-SzaProbeFormRegexForId {
    <#
    .SYNOPSIS
        The profile's probe form pinned to one ticket id (probes.formRegexForId with {Id} filled).
    #>
    param([Parameter(Mandatory)][string]$Id)
    $template = [string](Get-SzaProfileValue 'probes.formRegexForId')
    return [regex]($template.Replace('{Id}', [regex]::Escape($Id)))
}

function Get-SzaProbeCallExample {
    <#
    .SYNOPSIS
        A probe call as the operator would write it for this ticket, from probes.callTemplate.
    #>
    param([Parameter(Mandatory)][string]$Id, [string]$Message = '..')
    $template = [string](Get-SzaProfileValue 'probes.callTemplate')
    return $template.Replace('{Id}', $Id).Replace('{Message}', $Message)
}
