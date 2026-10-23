#requires -Version 7.0
<# Replay generated catalog vectors and registry-reader negatives. Codes: 0 pass, 1 fail, 2 unavailable. #>
[CmdletBinding()]
param(
    [string]$SourceRoot = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent),
    [string]$CatalogRoot,
    [string]$ExportDirectory
)
$ErrorActionPreference = 'Stop'
$run = 0
$failed = 0
$savedRoot = $env:SZA_PROJECT_ROOT
$savedProfile = $env:SZA_PROFILE_PATH
function Assert-That([bool]$Condition, [string]$Reason) { if (-not $Condition) { throw $Reason } }
function Test-Case([string]$Name, [scriptblock]$Body) {
    $script:run++
    try { & $Body; "OK $Name" }
    catch { $script:failed++; "FAIL $Name - $($_.Exception.Message)" }
}
# Source files are fingerprinted with CRLF read as LF: the same file checked out under a different
# autocrlf setting - which is how an installed plugin copy differs from the working tree - is the same
# source (the core digest normalizes newlines for the same reason, RULE-DELIVERY rule 3).
function Get-TextHash([string]$Path) {
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $normalized = [System.Text.Encoding]::Latin1.GetBytes([System.Text.Encoding]::Latin1.GetString($bytes).Replace("`r`n", "`n"))
    [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::HashData($normalized)).Replace('-', '')
}
function Invoke-Child([string]$Path, [string[]]$Arguments) {
    $output = & pwsh -NoProfile -File $Path @Arguments 2>&1 | Out-String
    [pscustomobject]@{ code = $LASTEXITCODE; output = $output.Trim() }
}
function Write-Json([string]$Path, $Value) {
    $Value | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $Path -Encoding utf8
}
try {
    $sources = @('tools/check-compliance.ps1', 'tools/harness/_profile.ps1', 'tools/lib/schema-carrier.ps1',
        'tools/lib/registry-tables.ps1', 'tools/check-contracts.ps1', 'tools/contract-lag.ps1',
        'templates/.sza-canon.json', 'tools/tests/contract-reader.tests.ps1')
    foreach ($file in $sources) {
        if (-not (Test-Path (Join-Path $SourceRoot $file))) { throw "Missing prerequisite: $file" }
    }
    $scratch = Join-Path $PSScriptRoot ('../../temp/S0011_contract-reader-follow-up/readers-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force $scratch | Out-Null
    $env:SZA_PROFILE_PATH = $null
    $gate = Join-Path $SourceRoot 'tools/check-compliance.ps1'
    $profile = Join-Path $SourceRoot 'tools/harness/_profile.ps1'
    $loader = Join-Path $scratch 'load.ps1'
    @'
param($Harness)
$ErrorActionPreference = 'Stop'
try { . $Harness; Get-SzaProfile | ConvertTo-Json -Depth 30 -Compress; exit 0 }
catch { Write-Output $_.Exception.Message; exit 2 }
'@ | Set-Content $loader
    $digestRun = Invoke-Child $gate @('-PrintDigest')
    Assert-That ($digestRun.code -eq 0 -and $digestRun.output -match 'sha256:[0-9a-f]{64}') 'Digest unavailable'
    $digest = $Matches[0]
    if ($CatalogRoot) {
        $vectorDir = Join-Path $CatalogRoot 'rule-adoption/vectors'
        $manifest = Get-Content (Join-Path $vectorDir 'manifest.json') -Raw | ConvertFrom-Json
        Assert-That ($manifest.contracts.'REPO-STAMP' -eq '0.13' -and $manifest.contracts.'HARNESS-PROFILE' -eq '0.13') 'Stale catalog versions'
        Assert-That ($manifest.files.Count -eq 2 -and $manifest.sources.Count -eq $sources.Count) 'Incomplete artifact manifest'
        foreach ($entry in $manifest.files) {
            Assert-That ($entry.path -in @('reader-cases.json', 'reader-verdicts.json')) 'Unexpected vector artifact path'
            Assert-That ((Get-FileHash (Join-Path $vectorDir $entry.path) -Algorithm SHA256).Hash -eq $entry.sha256) "Vector hash mismatch: $($entry.path)"
        }
        Assert-That ($manifest.PSObject.Properties.Name -contains 'sourceHash') 'Manifest predates newline-normalized source hashes; regenerate artifacts with the owner implementation'
        foreach ($entry in $manifest.sources) {
            Assert-That ($entry.path -in $sources) 'Unexpected source artifact path'
            Assert-That ((Get-TextHash (Join-Path $SourceRoot $entry.path)) -eq $entry.sha256) "Source hash mismatch: $($entry.path); regenerate artifacts with the owner implementation"
        }
        $cases = @(Get-Content (Join-Path $vectorDir 'reader-cases.json') -Raw | ConvertFrom-Json -AsHashtable)
        Assert-That ($cases.Count -ge 31) 'Incomplete catalog reader cases'
        $expectedVerdicts = @(Get-Content (Join-Path $vectorDir 'reader-verdicts.json') -Raw | ConvertFrom-Json)
        Assert-That ($expectedVerdicts.Count -eq $cases.Count) 'Incomplete observed verdicts'
    } else {
        $cases = [System.Collections.Generic.List[object]]::new()
        foreach ($kind in @('stamp', 'profile')) {
            $key = if ($kind -eq 'stamp') { 'schemaVersion' } else { 'version' }
            foreach ($carrier in @('absent', '1', '1.0', '1.999999999999999999999', '2.0', '999999999999999999.0', '0.9', 'bad', '01.0', '1.0.1', '', $null, 1)) {
                $inputData = @{}
                if ($carrier -cne 'absent') { $inputData[$key] = $carrier }
                if ($kind -eq 'profile') { $inputData['future'] = 42; $inputData['modules'] = @{ names = @() }; $inputData['paths'] = @{ changelog = $null } }
                $accepted = $carrier -in @('absent', '1', '1.0', '1.999999999999999999999') -and $carrier -is [string]
                $type = if ($null -eq $carrier) { 'null' } else { $carrier.GetType().Name }
                $cases.Add(@{ name = "$kind carrier [$carrier] ($type)"; kind = $kind; input = $inputData; accepted = $accepted })
            }
            foreach ($raw in @('null', '[]', 'false', '"text"')) {
                $cases.Add(@{ name = "$kind non-object $raw"; kind = $kind; input = @{}; raw = $raw; accepted = $false })
            }
        }
        $cases.Add(@{ name = 'unknown role and unknown key'; kind = 'stamp'; input = @{ role = 'prodcut'; future = 42 }; accepted = $true; unknownRole = $true })
        $cases.Add(@{ name = 'maximal stamp'; kind = 'stamp'; input = (Get-Content (Join-Path $SourceRoot 'templates/.sza-canon.json') -Raw | ConvertFrom-Json -AsHashtable); accepted = $true; maximal = $true })
        foreach ($age in @('old', 'reconciled', 'unknown')) {
            $cases.Add(@{ name = "delivery age $age"; kind = 'stamp'; input = @{}; accepted = $true; age = $age })
        }
    }
    $observed = [System.Collections.Generic.List[object]]::new()
    foreach ($case in $cases) {
        Test-Case $case.name {
            $root = Join-Path $scratch "case-$run"
            New-Item -ItemType Directory $root | Out-Null
            $env:SZA_PROJECT_ROOT = $root
            $stamp = @{ canon = @{ version = '2026.01.01.1'; coreDigest = $digest; model = 'reference' }; overlay = @(); ledgerShape = 'none'; role = 'canon-home' }
            if ($case.kind -eq 'stamp') {
                foreach ($k in $case.input.Keys) { $stamp[$k] = $case.input[$k] }
                if ($case.maximal) { $stamp.canon.coreDigest = $digest }
            } else { Write-Json (Join-Path $root '.sza-profile.json') $case.input }
            if ($case.age) {
                $stamp.canon.coreDigest = 'sha256:old'
                if ($case.age -ne 'unknown') { $stamp.canon.adoptedOn = '2000-01-01' }
                if ($case.age -eq 'reconciled') { $stamp.canon.reconciledOn = (Get-Date).ToString('yyyy-MM-dd') }
            }
            Write-Json (Join-Path $root '.sza-canon.json') $stamp
            if ($case.raw) {
                $fileName = if ($case.kind -eq 'stamp') { '.sza-canon.json' } else { '.sza-profile.json' }
                $case.raw | Set-Content (Join-Path $root $fileName)
            }
            if ($case.kind -eq 'stamp') {
                $result = Invoke-Child $gate @('-RepoRoot', $root, '-Json')
                Assert-That ($result.code -ne 2) $result.output
                $findings = @(($result.output | ConvertFrom-Json).findings)
                $refusals = @($findings | Where-Object { $_.id -eq 'SZA-CANON02' -and $_.message -match 'REPO-STAMP' })
                Assert-That (($refusals.Count -eq 0) -eq [bool]$case.accepted) $result.output
                if (-not $case.accepted) { Assert-That ($findings.Count -eq 1 -and $refusals[0].message -match 'update') 'Refusal applied partial checks or omitted update remedy' }
                if ($case.unknownRole) {
                    Assert-That (@($findings | Where-Object id -eq 'SZA-CANON08').Count -eq 1) 'Missing role diagnostic'
                    Assert-That (@($findings | Where-Object id -eq 'SZA-CANON04').Count -eq 1) 'Unknown role bypassed product overlay check'
                }
                if ($case.age) {
                    $ageFinding = @($findings | Where-Object id -eq 'SZA-CANON03')
                    $expected = if ($case.age -eq 'reconciled') { 'warn' } else { 'error' }
                    Assert-That ($ageFinding.Count -eq 1 -and $ageFinding[0].severity -eq $expected) $result.output
                }
                # The harness's stamp reader must refuse before deriving even an explicit path.
                $loaded = Invoke-Child $loader @($profile)
                Assert-That (($loaded.code -eq 0) -eq [bool]$case.accepted) $loaded.output
            } else {
                $result = Invoke-Child $loader @($profile)
                Assert-That (($result.code -eq 0) -eq [bool]$case.accepted) $result.output
                if ($case.accepted) {
                    $p = $result.output | ConvertFrom-Json
                    Assert-That ($p.modules.names.Count -eq 0 -and $null -eq $p.paths.changelog -and $p.future -eq 42) 'Payload replacement changed'
                } else { Assert-That ($result.output -match '^HARNESS-PROFILE:.*update' -and $result.output -notmatch '"paths"') $result.output }
            }
            Assert-That (-not (Test-Path (Join-Path $root 'dev'))) 'Reader wrote data'
            $observed.Add(@{ name = $case.name; accepted = [bool]$case.accepted; result = 'PASS'; writes = 0 })
        }
    }
    if ($CatalogRoot) {
        Test-Case 'catalog observed verdict replay' {
            Assert-That ($observed.Count -eq $expectedVerdicts.Count) 'Some catalog cases did not produce a verdict'
            for ($i = 0; $i -lt $observed.Count; $i++) {
                $a = $observed[$i]; $b = $expectedVerdicts[$i]
                Assert-That ($a.name -ceq $b.name -and $a.accepted -eq $b.accepted -and $b.result -eq 'PASS' -and $b.writes -eq 0) "Observed verdict differs: $($a.name)"
            }
        }
    }
    foreach ($order in @('original', 'reordered')) {
        foreach ($expired in @($false, $true)) {
            Test-Case "registry $order expired=$expired" {
                $catalog = Join-Path $scratch "catalog-$run"
                New-Item -ItemType Directory -Force (Join-Path $catalog '_meta'), (Join-Path $catalog 'fixture') | Out-Null
                foreach ($name in @('RULES.md', 'VERSIONING.md', 'CONTRACT_TEMPLATE.md', 'PROJECT_PROMPT.md')) { 'Fixture' | Set-Content (Join-Path $catalog "_meta/$name") }
                @'
```contract
id: FIXTURE
version: 0.1
status: draft
owner: fixture
since: 2026-10-23
wire: none
consumers: fixture
artifacts: none
```
'@ | Set-Content (Join-Path $catalog 'fixture/README.md')
                $until = if ($expired) { '2000-01-01' } else { '2999-01-01' }
                $tables = @(
                    @{ heading = 'Contracts'; headers = @('Id','Folder','Version','Status','Future'); cells = @('`FIXTURE`','[`fixture/`](../fixture/README.md)','0.1','draft','unknown') },
                    @{ heading = 'Adoption'; headers = @('Contract','Product','Role','Implements','Reads','Verified','Future'); cells = @('`FIXTURE`','fixture','C','-','0.1','pending','unknown') },
                    @{ heading = 'Exceptions'; headers = @('Contract','Product','Deviation','Reason','Until','Future'); cells = @('`FIXTURE`','fixture','fixture','fixture',$until,'unknown') }
                )
                $lines = @()
                $n = 0
                foreach ($table in $tables) {
                    $n++
                    $indices = @(0..($table.headers.Count-1))
                    if ($order -eq 'reordered') { [array]::Reverse($indices) }
                    $lines += "## $n. $($table.heading)", '', ('| ' + (($indices | ForEach-Object { $table.headers[$_] }) -join ' | ') + ' |'),
                        ('| ' + (($indices | ForEach-Object { '---' }) -join ' | ') + ' |'),
                        ('| ' + (($indices | ForEach-Object { $table.cells[$_] }) -join ' | ') + ' |'), ''
                }
                $registryFile = Join-Path $catalog '_meta/REGISTRY.md'
                $lines | Set-Content $registryFile
                $result = Invoke-Child (Join-Path $SourceRoot 'tools/check-contracts.ps1') @('-CatalogRoot', $catalog, '-Json')
                Assert-That ($result.code -eq $(if ($expired) { 1 } else { 0 })) $result.output
                $findings = @($result.output | ConvertFrom-Json)
                Assert-That ((@($findings | Where-Object id -eq 'CTR-EXPIRE').Count -eq 1) -eq $expired) $result.output
                Assert-That (@($findings | Where-Object id -eq 'CTR-STALE').Count -eq 1) 'Pending column missed'
                $lag = Invoke-Child (Join-Path $SourceRoot 'tools/contract-lag.ps1') @('-CatalogRoot', $catalog, '-Json')
                Assert-That ($lag.code -eq 0) $lag.output
                $report = $lag.output | ConvertFrom-Json
                Assert-That ($report.rows.Count -eq 1 -and $report.rows[0].state -eq 'pending' -and $report.rows[0].current -eq '0.1') $lag.output
                # Missing required header is an unavailable read, never a clean empty registry.
                ($lines -replace '\bVerified\b', 'Renamed') | Set-Content $registryFile
                foreach ($script in @('tools/contract-lag.ps1', 'tools/check-contracts.ps1')) {
                    $bad = Invoke-Child (Join-Path $SourceRoot $script) @('-CatalogRoot', $catalog)
                    Assert-That ($bad.code -eq 2 -and $bad.output -match "missing 'Verified'") $bad.output
                }
            }
        }
    }
    if ($run -eq 0) { throw 'No cases executed' }
    if ($ExportDirectory -and $failed -eq 0) {
        New-Item -ItemType Directory -Force $ExportDirectory | Out-Null
        $file = Join-Path $ExportDirectory 'reader-cases.json'
        Write-Json $file @($cases.ToArray())
        $verdictFile = Join-Path $ExportDirectory 'reader-verdicts.json'
        Write-Json $verdictFile @($observed.ToArray())
        $sourceHashes = foreach ($source in $sources) { @{ path = $source; sha256 = (Get-TextHash (Join-Path $SourceRoot $source)) } }
        Write-Json (Join-Path $ExportDirectory 'manifest.json') @{
            contracts = @{ 'REPO-STAMP' = '0.13'; 'HARNESS-PROFILE' = '0.13'; 'RULE-DELIVERY' = '0.12' }
            command = 'pwsh -NoProfile -File tools/tests/export-contract-vectors.ps1 -CatalogRoot <catalog>'
            sourceHash = 'SHA-256 of the source file with CRLF read as LF, so a checkout under any autocrlf setting matches; the files below are catalog-resident and hashed as stored'
            sources = @($sourceHashes); files = @(
                @{ path = 'reader-cases.json'; sha256 = (Get-FileHash $file -Algorithm SHA256).Hash },
                @{ path = 'reader-verdicts.json'; sha256 = (Get-FileHash $verdictFile -Algorithm SHA256).Hash })
            scope = 'Stamp/profile readers and delivery age ladder only; no real delivery, full layout or live-agent claim.'
        }
        "Artifacts written: $ExportDirectory"
    }
    $verdict = if ($failed) { 'FAIL' } else { 'PASS' }
    "contract-reader-tests: $verdict (run=$run skipped=0)"
    exit $(if ($failed) { 1 } else { 0 })
} catch {
    $_.Exception.Message
    "contract-reader-tests: COULD NOT VERIFY (run=$run skipped=0)"
    exit 2
} finally { $env:SZA_PROJECT_ROOT = $savedRoot; $env:SZA_PROFILE_PATH = $savedProfile }
