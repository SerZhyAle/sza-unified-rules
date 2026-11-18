#requires -Version 7.0
<#
.SYNOPSIS
    Fast targeted tests for HARNESS-PROFILE section 3 rule 10 (S0078): the optional top-level `portfolio`
    object of a repository's profile (`console.quietMinutes`, `console.stallMinutes`, `analysis.thresholds`)
    overrides the portfolio registry's values for that repository, in the order profile, registry,
    built-in default.

      1. Console values resolve value by value: the profile's, else the registry's, else 5 / 15 / 30; the
         profile may override quietMinutes and stallMinutes only, graceSeconds stays the registry's.
      2. A value that is not a positive number is skipped, never guessed; an unreadable profile, a profile
         with no `portfolio` and a repository with no profile all read as "the profile says nothing".
      3. A name that is not a console setting throws (a typo is not "not configured").
      4. Analysis thresholds resolve profile, registry, then $null - there is no built-in default; an
         unknown name is ignored and a non-number is skipped.
      5. The registry's own defaults still fill `console` with 5 / 15 / 30 after the one copy of them moved
         into the resolver's module.
      6. The shipped default tree declares the paths (rule 4) with $null values, so a profile that names
         nothing masks nothing; a profile's value merges over them through Get-SzaProfileValue; and the
         names the portfolio may read from a profile are exactly the names the tree declares.
      7. HARNESS-PROFILE rule 15: the specs folder, the archive folder and the id pattern derive the eight
         dependent defaults, an explicit key wins, and the shipped default tree is never written into.

    Everything is a throwaway folder and a direct call of the changed functions; no registry or profile of
    a real repository is read, and no process is spawned. Designed to stay well under the 5 s line.
    Takes -KeepScratch to leave the throwaway folders for inspection.
#>
[CmdletBinding()]
param([switch]$KeepScratch)

$ErrorActionPreference = 'Stop'
$SourceRoot = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent)
$harness = Join-Path $SourceRoot 'tools/harness'

$run = 0; $passed = 0; $failed = 0
function Assert-That([bool]$Condition, [string]$Reason) { if (-not $Condition) { throw $Reason } }
function Test-Case([string]$Name, [scriptblock]$Body) {
    $script:run++
    Write-Host -NoNewline "CASE  $Name ... "
    try {
        & $Body
        $script:passed++
        Write-Host 'PASS' -ForegroundColor Green
    } catch {
        $script:failed++
        Write-Host 'FAIL' -ForegroundColor Red
        Write-Host "      $($_.Exception.Message)" -ForegroundColor DarkRed
    }
}

$scratch = Join-Path ([System.IO.Path]::GetTempPath()) ('s0078-rule10-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $scratch | Out-Null
$savedPortfolio = $env:SZA_PORTFOLIO_ROOT
$savedRoot = $env:SZA_PROJECT_ROOT
$savedProfile = $env:SZA_PROFILE_PATH
$env:SZA_PORTFOLIO_ROOT = Join-Path $scratch 'portfolio-root'
$env:SZA_PROFILE_PATH = $null

. (Join-Path $harness 'portfolio/lib/registry.ps1')

$script:repos = 0
function New-Repo($Profile, [switch]$RawText) {
    $script:repos++
    $path = Join-Path $scratch ("repo{0}" -f $script:repos)
    New-Item -ItemType Directory -Path $path | Out-Null
    if ($RawText) { Set-Content (Join-Path $path '.sza-profile.json') -Value $Profile -Encoding utf8 -NoNewline }
    elseif ($null -ne $Profile) { $Profile | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $path '.sza-profile.json') -Encoding utf8 }
    return $path
}

try {
    $registry = [pscustomobject]@{
        console  = [pscustomobject]@{ quietMinutes = 7; stallMinutes = 20; graceSeconds = 45 }
        analysis = [pscustomobject]@{ thresholds = [pscustomobject]@{ stallRuns = 3 } }
    }

    Test-Case 'a console value resolves profile, then registry, then built-in, value by value' {
        $both = New-Repo @{ version = '1'; portfolio = @{ console = @{ quietMinutes = 30 } } }
        Assert-That ((Resolve-PqConsoleSetting -Name quietMinutes -Registry $registry -RepoPath $both) -eq 30) 'the profile did not win over the registry for quietMinutes'
        Assert-That ((Resolve-PqConsoleSetting -Name stallMinutes -Registry $registry -RepoPath $both) -eq 20) 'a value the profile omits did not come from the registry'
        Assert-That ((Resolve-PqConsoleSetting -Name graceSeconds -Registry $registry -RepoPath $both) -eq 45) 'graceSeconds did not come from the registry'
        # No registry value: the built-in default, for each of the three.
        $none = [pscustomobject]@{}
        Assert-That ((Resolve-PqConsoleSetting -Name quietMinutes -Registry $none -RepoPath $both) -eq 30) 'the profile did not win over the built-in default'
        Assert-That ((Resolve-PqConsoleSetting -Name stallMinutes -Registry $none -RepoPath $both) -eq 15) 'the built-in stallMinutes is not 15'
        Assert-That ((Resolve-PqConsoleSetting -Name graceSeconds -Registry $none -RepoPath $both) -eq 30) 'the built-in graceSeconds is not 30'
        Assert-That ((Resolve-PqConsoleSetting -Name quietMinutes) -eq 5) 'with no registry and no repository the built-in quietMinutes is not 5'
    }

    Test-Case 'a profile that says nothing, or cannot be read, leaves the registry in force' {
        $noKey = New-Repo @{ version = '1'; projectName = 'x' }
        $noProfile = New-Repo $null
        $broken = New-Repo '{ this is not json' -RawText
        $notObject = New-Repo '[1, 2]' -RawText
        $portfolioNotObject = New-Repo @{ version = '1'; portfolio = 'fast' }
        foreach ($repo in @($noKey, $noProfile, $broken, $notObject, $portfolioNotObject)) {
            Assert-That ((Resolve-PqConsoleSetting -Name quietMinutes -Registry $registry -RepoPath $repo) -eq 7) "$repo did not fall back to the registry's quietMinutes"
            Assert-That ($null -eq (Get-PqRepoPortfolioOverride -RepoPath $repo)) "$repo yielded an override object"
        }
        Assert-That ((Resolve-PqConsoleSetting -Name stallMinutes -Registry $registry -RepoPath (Join-Path $scratch 'no-such-folder')) -eq 20) 'a folder that does not exist did not fall back to the registry'
    }

    Test-Case 'a value that is not a positive number is skipped, and graceSeconds in a profile is not read' {
        $bad = New-Repo @{ version = '1'; portfolio = @{ console = @{ quietMinutes = 'soon'; stallMinutes = 0; graceSeconds = 99 } } }
        Assert-That ((Resolve-PqConsoleSetting -Name quietMinutes -Registry $registry -RepoPath $bad) -eq 7) 'a string in the profile was used'
        Assert-That ((Resolve-PqConsoleSetting -Name stallMinutes -Registry $registry -RepoPath $bad) -eq 20) 'a zero in the profile was used'
        Assert-That ((Resolve-PqConsoleSetting -Name graceSeconds -Registry $registry -RepoPath $bad) -eq 45) 'graceSeconds in the profile overrode the registry'
        $negativeRegistry = [pscustomobject]@{ console = [pscustomobject]@{ quietMinutes = -3; stallMinutes = 'x' } }
        Assert-That ((Resolve-PqConsoleSetting -Name quietMinutes -Registry $negativeRegistry) -eq 5) 'a negative registry value was used'
        Assert-That ((Resolve-PqConsoleSetting -Name stallMinutes -Registry $negativeRegistry) -eq 15) 'a non-number registry value was used'
        $fractional = New-Repo @{ version = '1'; portfolio = @{ console = @{ quietMinutes = 2.5 } } }
        Assert-That ((Resolve-PqConsoleSetting -Name quietMinutes -Registry $registry -RepoPath $fractional) -eq 2.5) 'a positive fractional minute was refused'
    }

    Test-Case 'a name that is not a console setting throws' {
        $threw = $false
        try { [void](Resolve-PqConsoleSetting -Name quietMinute -Registry $registry) } catch { $threw = $_.Exception.Message -match 'not a console setting' }
        Assert-That $threw 'a mistyped console name did not throw'
    }

    Test-Case 'a threshold resolves profile, then registry, then $null; an unknown name is ignored' {
        $repo = New-Repo @{ version = '1'; portfolio = @{ analysis = @{ thresholds = @{ stallRuns = 9; extraRuns = 4; junk = 'many' } } } }
        Assert-That ((Resolve-PqAnalysisThreshold -Name stallRuns -Registry $registry -RepoPath $repo) -eq 9) 'the profile threshold did not win'
        Assert-That ((Resolve-PqAnalysisThreshold -Name stallRuns -Registry $registry) -eq 3) 'the registry threshold was not read'
        Assert-That ((Resolve-PqAnalysisThreshold -Name extraRuns -Registry $registry -RepoPath $repo) -eq 4) 'a threshold only the profile names was not read'
        Assert-That ($null -eq (Resolve-PqAnalysisThreshold -Name junk -Registry $registry -RepoPath $repo)) 'a non-number threshold in the profile was used'
        Assert-That ($null -eq (Resolve-PqAnalysisThreshold -Name neverNamed -Registry $registry -RepoPath $repo)) 'an unknown threshold name did not answer $null'
        Assert-That ($null -eq (Resolve-PqAnalysisThreshold -Name stallRuns)) 'with no registry and no repository a threshold answered a value'
        $noThresholds = New-Repo @{ version = '1'; portfolio = @{ analysis = @{ thresholds = 'high' } } }
        Assert-That ((Resolve-PqAnalysisThreshold -Name stallRuns -Registry $registry -RepoPath $noThresholds) -eq 3) 'a thresholds value that is not an object hid the registry'
    }

    Test-Case 'the registry defaults still fill console with 5, 15 and 30, and keep what the registry sets' {
        $filled = Get-PqRegistryWithDefaults ([pscustomobject]@{ repos = @() })
        Assert-That ($filled.console.quietMinutes -eq 5 -and $filled.console.stallMinutes -eq 15 -and $filled.console.graceSeconds -eq 30) 'the filled console is not 5 / 15 / 30'
        Assert-That ((Resolve-PqConsoleSetting -Name stallMinutes -Registry $filled) -eq 15) 'the resolver disagrees with the filled registry'
        $own = Get-PqRegistryWithDefaults ([pscustomobject]@{ repos = @(); console = [pscustomobject]@{ quietMinutes = 11 } })
        Assert-That ($own.console.quietMinutes -eq 11) 'a console the registry sets was replaced by the default'
        Assert-That ((Resolve-PqConsoleSetting -Name stallMinutes -Registry $own) -eq 15) 'a console value the registry omits did not fall to the built-in default'
        # The default is a copy: changing one filled registry must not change the next.
        $filled.console.quietMinutes = 99
        $again = Get-PqRegistryWithDefaults ([pscustomobject]@{ repos = @() })
        Assert-That ($again.console.quietMinutes -eq 5) 'the built-in console default was shared between two registries'
    }

    Test-Case 'the shipped default tree declares the portfolio paths with $null, and the names match the resolver' {
        . (Join-Path $harness '_profile.ps1')
        $tree = $Script:SzaProfileDefaults.portfolio
        Assert-That ($null -ne $tree) 'the default tree has no portfolio object'
        $declared = @($tree.console.Keys)
        Assert-That ((($declared | Sort-Object) -join ',') -ceq (($script:PqProfileConsoleNames | Sort-Object) -join ',')) "the tree declares $($declared -join ',') but the resolver reads $($script:PqProfileConsoleNames -join ',')"
        foreach ($name in $declared) { Assert-That ($null -eq $tree.console[$name]) "the tree's console.$name is a value, not `$null: it would mask the registry" }
        Assert-That ($tree.analysis.thresholds.Count -eq 0) 'the tree declares threshold names'
        foreach ($name in $declared) { Assert-That ($script:PqConsoleDefaults.Contains($name)) "the tree declares console.$name, which the registry has no built-in default for" }

        # A project with no portfolio object reads the declared $null without a throw; one with a value reads it.
        $root = New-Repo @{ version = '1' }
        $env:SZA_PROJECT_ROOT = $root; $Script:SzaProfileCache = $null; $Script:SzaProjectRootCache = $null
        Assert-That ($null -eq (Get-SzaProfileValue 'portfolio.console.quietMinutes')) 'an undeclared-by-the-project quietMinutes was not $null'
        $root = New-Repo @{ version = '1'; portfolio = @{ console = @{ stallMinutes = 40 }; analysis = @{ thresholds = @{ stallRuns = 2 } } } }
        $env:SZA_PROJECT_ROOT = $root; $Script:SzaProfileCache = $null; $Script:SzaProjectRootCache = $null
        Assert-That ((Get-SzaProfileValue 'portfolio.console.stallMinutes') -eq 40) 'the merged tree did not carry the profile stallMinutes'
        Assert-That ($null -eq (Get-SzaProfileValue 'portfolio.console.quietMinutes')) 'the merged tree invented a quietMinutes'
        Assert-That ((Get-SzaProfileValue 'portfolio.analysis.thresholds').stallRuns -eq 2) 'the merged tree did not carry the profile threshold'
    }
    Test-Case 'rule 15: the specs folder, the archive folder and the id pattern derive eight defaults, and an explicit key wins' {
        . (Join-Path $harness '_profile.ps1')
        $tree = $Script:SzaProfileDefaults
        # The shipped tree derives to itself, so a repository with no profile reads what it always read.
        $self = Get-SzaDerivedDefaults -SpecsDir $tree.paths.specsDir -SpecArchiveDir $tree.paths.specArchiveDir -TicketIdPattern $tree.grammar.ticketIdPattern
        Assert-That (@($self.paths.Keys).Count -eq 6 -and @($self.grammar.Keys).Count -eq 2) "derived $(@($self.paths.Keys).Count) path keys and $(@($self.grammar.Keys).Count) grammar keys, expected 6 and 2"
        foreach ($k in $self.paths.Keys) { Assert-That ($self.paths[$k] -ceq [string]$tree.paths[$k]) "paths.$k derives to '$($self.paths[$k])', the tree says '$($tree.paths[$k])'" }
        foreach ($k in $self.grammar.Keys) { Assert-That ($self.grammar[$k] -ceq [string]$tree.grammar[$k]) "grammar.$k derives to '$($self.grammar[$k])', the tree says '$($tree.grammar[$k])'" }
        # Three facts and nothing else: the eight keys follow them, the probe baseline does not.
        $root = New-Repo @{ version = '1'; paths = @{ specsDir = 'tasks'; specArchiveDir = 'tasks/archive' }; grammar = @{ ticketIdPattern = '^TASK-\d{4}$' } }
        $env:SZA_PROJECT_ROOT = $root; $Script:SzaProfileCache = $null; $Script:SzaProjectRootCache = $null
        $want = [ordered]@{
            'paths.journal' = 'tasks/spec-catalog.jsonl'; 'paths.journalArchive' = 'tasks/spec-catalog-archive.jsonl'
            'paths.burnedIds' = 'tasks/spec-catalog-burned-ids.jsonl'; 'paths.releaseQueue' = 'tasks/RELEASE_QUEUE.md'
            'paths.releaseReady' = 'tasks/RELEASE_READY.md'; 'paths.releaseQueueDone' = 'tasks/RELEASE_QUEUE_DONE.md'
            'grammar.specFileTemplate' = 'tasks/{0}_{1}.md'; 'grammar.specFilePattern' = '^tasks/(archive/)?TASK-\d{4}_(?!spec_)'
            'paths.probeBaseline' = 'PLAN/probe-baseline.txt'
        }
        foreach ($k in $want.Keys) { Assert-That ([string](Get-SzaProfileValue $k) -ceq $want[$k]) "$k is '$(Get-SzaProfileValue $k)', expected '$($want[$k])'" }
        # An explicit key wins, whatever its letter case; a profile with no grammar object must not write into the shipped tree.
        $root = New-Repo @{ version = '1'; paths = @{ specArchiveDir = 'PLAN/DONE'; Journal = 'data/ledger.jsonl' } }
        $env:SZA_PROJECT_ROOT = $root; $Script:SzaProfileCache = $null; $Script:SzaProjectRootCache = $null
        Assert-That ([string](Get-SzaProfileValue 'paths.journal') -ceq 'data/ledger.jsonl') 'an explicit paths.journal lost to the derived default'
        Assert-That ([string](Get-SzaProfileValue 'grammar.specFilePattern') -ceq '^PLAN/(DONE/)?S\d{4}_(?!spec_)') "the pattern is '$(Get-SzaProfileValue 'grammar.specFilePattern')'"
        Assert-That ([string]$Script:SzaProfileDefaults.grammar.specFilePattern -ceq '^PLAN/(archive/)?S\d{4}_(?!spec_)') 'the derivation wrote into the shipped default tree'
        # Sibling folders, one folder for both, and no specs folder at all.
        Assert-That ((Get-SzaDerivedDefaults -SpecsDir 'tickets' -SpecArchiveDir 'archive' -TicketIdPattern '^S\d{4}$').grammar.specFilePattern -ceq '^(?:tickets|archive)/S\d{4}_(?!spec_)') 'sibling folders gave another pattern'
        Assert-That ((Get-SzaDerivedDefaults -SpecsDir 'PLAN' -SpecArchiveDir 'PLAN' -TicketIdPattern '^S\d{4}$').grammar.specFilePattern -ceq '^PLAN/S\d{4}_(?!spec_)') 'one folder for both gave another pattern'
        Assert-That (@((Get-SzaDerivedDefaults -SpecsDir '' -SpecArchiveDir 'x' -TicketIdPattern '^S\d{4}$').paths.Keys).Count -eq 0) 'an empty specs folder derived a path'
    }
} finally {
    $env:SZA_PORTFOLIO_ROOT = $savedPortfolio
    $env:SZA_PROJECT_ROOT = $savedRoot
    $env:SZA_PROFILE_PATH = $savedProfile
    if (-not $KeepScratch -and (Test-Path $scratch)) {
        Remove-Item -Path $scratch -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ''
Write-Host "Cases: $run | Passed: $passed | Failed: $failed"
if ($failed -gt 0) { exit 1 } else { exit 0 }
