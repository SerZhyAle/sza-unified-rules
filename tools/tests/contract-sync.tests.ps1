#requires -Version 7.0
<#
    Exercise the contract readers against generated throwaway projects, without Git writes.
    Exit codes: 0 all cases passed; 1 an assertion failed; 2 prerequisites/setup unavailable.
    SourceRoot permits replay against another checkout, including the pre-change readers.
#>
[CmdletBinding()]
param([string]$SourceRoot = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent))

$ErrorActionPreference = 'Stop'
$run = 0
$failed = 0
$savedRoot = $env:SZA_PROJECT_ROOT
$savedProfile = $env:SZA_PROFILE_PATH

function Assert-That {
    param([bool]$Condition, [string]$Reason)
    if (-not $Condition) { throw $Reason }
}

function Test-Case {
    param([string]$Name, [scriptblock]$Body)
    $script:run++
    try { & $Body; Write-Output "OK $Name" }
    catch { $script:failed++; Write-Output "FAIL $Name - $($_.Exception.Message)" }
}

function Invoke-Child {
    param([string]$Script, [string[]]$Arguments = @())
    $output = & pwsh -NoProfile -File $Script @Arguments 2>&1 | Out-String
    return [pscustomobject]@{ code = $LASTEXITCODE; output = $output.Trim() }
}

function Write-Json {
    param([string]$Path, $Value)
    $Value | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path -Encoding utf8
}

try {
    foreach ($required in @('tools/harness/_profile.ps1', 'tools/check-compliance.ps1', 'tools/contract-lag.ps1')) {
        if (-not (Test-Path -LiteralPath (Join-Path $SourceRoot $required))) { throw "Missing prerequisite: $required" }
    }
    $scratch = Join-Path $SourceRoot ('temp/S0008_contract-sync-implementation/run-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $scratch -Force | Out-Null
    $env:SZA_PROFILE_PATH = $null
    $loader = Join-Path $scratch 'read-profile.ps1'
    @'
param($Harness)
$ErrorActionPreference = 'Stop'
try {
    . $Harness
    Get-SzaProfile | ConvertTo-Json -Depth 15 -Compress
    exit 0
} catch { Write-Output $_.Exception.Message; exit 2 }
'@ | Set-Content -LiteralPath $loader -Encoding utf8
    $profileReader = Join-Path $SourceRoot 'tools/harness/_profile.ps1'
    $gate = Join-Path $SourceRoot 'tools/check-compliance.ps1'
    $lag = Join-Path $SourceRoot 'tools/contract-lag.ps1'
    $digestResult = Invoke-Child $gate @('-PrintDigest')
    Assert-That ($digestResult.code -eq 0) $digestResult.output
    Assert-That ($digestResult.output -match 'sha256:[0-9a-f]{64}') 'No core digest in reader output'
    $digest = $Matches[0]

    foreach ($shape in @('1', '2', '3', '4', 'none')) {
        foreach ($mode in @('omitted', 'explicit', 'empty', 'null')) {
            Test-Case "ledger $shape / $mode" {
                $root = Join-Path $scratch "shape-$shape-$mode"
                New-Item -ItemType Directory -Path $root | Out-Null
                $env:SZA_PROJECT_ROOT = $root
                Write-Json (Join-Path $root '.sza-canon.json') @{ ledgerShape = $shape; ledgerFile = 'ledger/original.md'; future = 42 }
                $expected = if ($shape -eq '2') { 'ledger/original.md' } elseif ($shape -in @('4', 'none')) { '' } else { 'dev/CHANGELOG.md' }
                if ($mode -ne 'omitted') {
                    $value = switch ($mode) { explicit { 'engineering/log.md' }; empty { '' }; null { $null } }
                    Write-Json (Join-Path $root '.sza-profile.json') @{ paths = @{ changelog = $value } }
                    $expected = [string]$value
                }
                $result = Invoke-Child $loader @($profileReader)
                Assert-That ($result.code -eq 0) $result.output
                $actual = ($result.output | ConvertFrom-Json).paths.changelog
                Assert-That ([string]$actual -ceq $expected) "Expected '$expected', got '$actual'"
                Assert-That (-not (Test-Path (Join-Path $root 'dev'))) 'Reader created a dev directory'
            }
        }
    }

    foreach ($kind in @('no-stamp', 'shape2-no-file', 'malformed-stamp', 'malformed-profile')) {
        Test-Case $kind {
            $root = Join-Path $scratch $kind
            New-Item -ItemType Directory -Path $root | Out-Null
            $env:SZA_PROJECT_ROOT = $root
            if ($kind -eq 'shape2-no-file') { Write-Json (Join-Path $root '.sza-canon.json') @{ ledgerShape = '2' } }
            if ($kind -eq 'malformed-stamp') { '{' | Set-Content (Join-Path $root '.sza-canon.json') }
            if ($kind -eq 'malformed-profile') { '{' | Set-Content (Join-Path $root '.sza-profile.json') }
            $result = Invoke-Child $loader @($profileReader)
            if ($kind -like 'malformed-*') {
                Assert-That ($result.code -eq 2 -and $result.output -match 'not valid JSON') $result.output
            } else {
                Assert-That ($result.code -eq 0) $result.output
                Assert-That (($result.output | ConvertFrom-Json).paths.changelog -eq 'dev/CHANGELOG.md') 'Default changed'
            }
        }
    }

    Test-Case 'merge by name, empty arrays, null and unknown keys' {
        $root = Join-Path $scratch 'merge'
        New-Item -ItemType Directory -Path $root | Out-Null
        $env:SZA_PROJECT_ROOT = $root
        Write-Json (Join-Path $root '.sza-profile.json') @{ version = '1.999'; future = 42; paths = @{ changelog = $null }; modules = @{ names = @() } }
        $result = Invoke-Child $loader @($profileReader)
        Assert-That ($result.code -eq 0) $result.output
        $profile = $result.output | ConvertFrom-Json
        Assert-That ($null -eq $profile.paths.changelog -and $profile.paths.journal -eq 'PLAN/spec-catalog.jsonl') 'Null replacement or sibling default lost'
        Assert-That ($profile.modules.names.Count -eq 0 -and $profile.future -eq 42) 'Empty array or unknown key lost'
        # HARNESS-PROFILE rule 6 explicitly records this outstanding carrier hole.
        Assert-That ($profile.version -eq '1.999') 'Higher minor carrier was not preserved'
    }

    foreach ($shape in @('4', 'none')) {
        Test-Case "writer disabled by shape $shape" {
            $root = Join-Path $scratch "writer-$shape"
            New-Item -ItemType Directory -Path $root | Out-Null
            $env:SZA_PROJECT_ROOT = $root
            Write-Json (Join-Path $root '.sza-canon.json') @{ ledgerShape = $shape }
            $result = Invoke-Child (Join-Path $SourceRoot 'tools/harness/devlog/add_to_dev_log.ps1') @('a.ps1', 'fixture', 'Preserve data', '-Branch', 'fixture')
            Assert-That ($result.code -eq 0 -and $result.output -match 'NOT APPLICABLE') $result.output
            Assert-That (-not (Test-Path (Join-Path $root 'dev'))) 'Disabled writer created a dev-log'
        }
    }

    foreach ($shape in @('1', '2', '3')) {
        Test-Case "writer preserves ledger shape $shape" {
            $root = Join-Path $scratch "writer-$shape"
            New-Item -ItemType Directory -Path $root | Out-Null
            $env:SZA_PROJECT_ROOT = $root
            $ledger = Join-Path $root 'CHANGELOG.md'
            'User-authored ledger bytes' | Set-Content $ledger
            $before = (Get-FileHash $ledger).Hash
            Write-Json (Join-Path $root '.sza-canon.json') @{ ledgerShape = $shape; ledgerFile = 'CHANGELOG.md' }
            Write-Json (Join-Path $root '.sza-profile.json') @{ paths = @{ changelog = 'engineering/changes.md' } }
            $writer = Join-Path $SourceRoot 'tools/harness/devlog/add_to_dev_log.ps1'
            $result = Invoke-Child $writer @('a.ps1', 'fixture', 'Preserve data', '-Branch', 'fixture')
            Assert-That ($result.code -eq 0) $result.output
            Assert-That ((Get-FileHash $ledger).Hash -eq $before) 'Original ledger was modified'
            $log = Join-Path $root 'engineering/changes.md'
            Assert-That ((Get-Content $log -Raw) -match 'Preserve data') 'Explicit dev-log missing'
            $logHash = (Get-FileHash $log).Hash
            $repeat = Invoke-Child $writer @('a.ps1', 'fixture', 'Preserve data', '-Branch', 'fixture')
            Assert-That ($repeat.code -eq 0 -and (Get-FileHash $log).Hash -eq $logHash) 'Duplicate changed log'
        }
    }

    foreach ($configured in @($false, $true)) {
        Test-Case "complete with dev-log configured $configured" {
            $root = Join-Path $scratch "complete-$configured"
            New-Item -ItemType Directory -Path (Join-Path $root 'PLAN') -Force | Out-Null
            $env:SZA_PROJECT_ROOT = $root
            Write-Json (Join-Path $root '.sza-canon.json') @{ ledgerShape = 'none' }
            if ($configured) {
                Write-Json (Join-Path $root '.sza-profile.json') @{ paths = @{ changelog = 'engineering/log.md' } }
            }
            foreach ($store in @('spec-catalog', 'spec-catalog-archive', 'spec-catalog-burned-ids')) {
                New-Item -ItemType File -Path (Join-Path $root "PLAN/$store.jsonl") | Out-Null
            }
            "# Fixture`nStatus: Draft" | Set-Content (Join-Path $root 'PLAN/S0001_fixture.md')
            $insert = Invoke-Child (Join-Path $SourceRoot 'tools/harness/spec_catalog/insert.ps1') @('-Id', 'S0001', '-Name', 'fixture', '-File', 'PLAN/S0001_fixture.md')
            Assert-That ($insert.code -eq 0) $insert.output
            $result = Invoke-Child (Join-Path $SourceRoot 'tools/harness/spec_catalog/complete.ps1') @('-Id', 'S0001', '-Status', 'Archived', '-SkipValidate')
            Assert-That ($result.code -eq 0) $result.output
            if ($configured) {
                Assert-That ($result.output -match 'engineering/log.md not found') 'Configured log check was skipped'
            } else {
                Assert-That ($result.output -match 'dev-log: NOT APPLICABLE') 'Disabled log prevented closure'
            }
            Assert-That (-not (Test-Path (Join-Path $root 'dev'))) 'Completion created an unwanted dev-log'
        }
    }

    $today = (Get-Date).ToString('yyyy-MM-dd')
    $old = (Get-Date).AddDays(-181).ToString('yyyy-MM-dd')
    $boundary = (Get-Date).AddDays(-180).ToString('yyyy-MM-dd')
    $dateCases = @(
        @{ name = 'missing'; adopted = $null; reconciled = $null; severity = 'error' },
        @{ name = 'invalid'; adopted = 'invalid'; reconciled = 'invalid'; severity = 'error' },
        @{ name = 'invalid-reconciled-old-adopted'; adopted = $old; reconciled = 'invalid'; severity = 'error' },
        @{ name = 'invalid-reconciled-recent-adopted'; adopted = $today; reconciled = 'invalid'; severity = 'warn' },
        @{ name = 'recent-reconciliation'; adopted = $old; reconciled = $today; severity = 'warn' },
        @{ name = 'old-reconciliation'; adopted = $today; reconciled = $old; severity = 'error' },
        @{ name = 'recent-adoption'; adopted = $today; reconciled = $null; severity = 'warn' },
        @{ name = 'boundary'; adopted = $boundary; reconciled = $null; severity = 'warn' }
    )
    foreach ($dates in $dateCases) {
        foreach ($equal in @($false, $true)) {
            Test-Case "age $($dates.name) / equal digest $equal" {
                $root = Join-Path $scratch ("age-$($dates.name)-$equal")
                New-Item -ItemType Directory -Path $root | Out-Null
                $stamp = @{ canon = @{ version = '2026.01.01.1'; coreDigest = $(if ($equal) { $digest } else { 'sha256:old' }); model = 'reference' }; overlay = @(); ledgerShape = 'none' }
                if ($null -ne $dates.adopted) { $stamp.canon.adoptedOn = $dates.adopted }
                if ($null -ne $dates.reconciled) { $stamp.canon.reconciledOn = $dates.reconciled }
                Write-Json (Join-Path $root '.sza-canon.json') $stamp
                $result = Invoke-Child $gate @('-RepoRoot', $root, '-Only', 'SZA-CANON03', '-Json')
                $report = $result.output | ConvertFrom-Json
                $finding = @($report.findings | Where-Object id -eq 'SZA-CANON03')
                if ($equal) {
                    Assert-That ($result.code -eq 0 -and $finding.Count -eq 0) $result.output
                } else {
                    $expectedCode = if ($dates.severity -eq 'error') { 1 } else { 0 }
                    Assert-That ($result.code -eq $expectedCode -and $finding.Count -eq 1 -and $finding[0].severity -eq $dates.severity) $result.output
                    Assert-That ($finding[0].message -match 'from canon\.|unknown age') 'Date provenance missing'
                    Assert-That ($finding[0].fix -match $(if ($expectedCode) { 'in full' } else { 'reconcile' })) 'Wrong remedy'
                }
            }
        }
    }

    Test-Case 'generated specs retain rights and complete row inventory' {
        $catalog = Join-Path $scratch 'catalog'
        New-Item -ItemType Directory -Path (Join-Path $catalog '_meta'), (Join-Path $catalog 'fixture') | Out-Null
        @'
## 1. Contracts
| Id | Folder | Version | Status |
| --- | --- | --- | --- |
| `FIXTURE` | [`fixture/`](../fixture/README.md) | 0.2 | draft |
## 2. Adoption
| Contract | Product | Role | Implements | Reads | Verified |
| --- | --- | --- | --- | --- | --- |
| `FIXTURE` | fixture behind | C | - | 0.1 | 2026-10-01 |
| `FIXTURE` | fixture partial | C | partial 0.2 | - | 2026-10-01 |
| `FIXTURE` | fixture pending | C | - | - | pending |
| `FIXTURE` | fixture unreadable | C | garbage | - | 2026-10-01 |
| `FIXTURE` | fixture not-bound | - | - | - | 2026-10-01 |
| `FIXTURE` | fixture ahead | C | - | 0.3 | 2026-10-01 |
| `FIXTURE` | fixture current | C | - | 0.2 | 2026-10-01 |
'@ | Set-Content (Join-Path $catalog '_meta/REGISTRY.md')
        @'
| Date | Version | Kind | What changed |
| --- | --- | --- | --- |
| 2026-10-17 | 0.2 | breaking | Fixture reader changed. |
'@ | Set-Content (Join-Path $catalog 'fixture/README.md')
        $result = Invoke-Child $lag @('-CatalogRoot', $catalog, '-Product', 'fixture', '-EmitSpec')
        Assert-That ($result.code -eq 0) $result.output
        foreach ($text in @('without prior owner approval', 'responsible project', 'permanent supported variant', 'PROPOSAL-', 'security or data-safety', 'unverified work', 'MUST adapt or declare', 'fixture not-bound', 'fixture ahead', 'fixture current', 'fixture pending', 'fixture unreadable', 'fixture partial')) {
            Assert-That ($result.output.Contains($text)) "Missing generated instruction: $text"
        }
        $onlyPending = Invoke-Child $lag @('-CatalogRoot', $catalog, '-Product', 'fixture pending', '-EmitSpec')
        Assert-That ($onlyPending.code -eq 0 -and $onlyPending.output -notmatch 'Every readable row is on') 'Pending row reported as current'
    }

    if ($run -eq 0) { throw 'No test cases executed' }
    $verdict = if ($failed) { 'FAIL' } else { 'PASS' }
    Write-Output "contract-sync-tests: $verdict (run=$run skipped=0)"
    exit $(if ($failed) { 1 } else { 0 })
} catch {
    Write-Output $_.Exception.Message
    Write-Output "contract-sync-tests: COULD NOT VERIFY (run=$run skipped=0)"
    exit 2
} finally {
    $env:SZA_PROJECT_ROOT = $savedRoot
    $env:SZA_PROFILE_PATH = $savedProfile
}
