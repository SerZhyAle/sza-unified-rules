#requires -Version 7.0
<#
    document_registry/validate.ps1 and query.ps1 over a throwaway project (CANONR-0235): HARNESS-PROFILE rule 18,
    the local registry of DOC-INTERNAL-QUALITY item K, and the generator and check fields of item W.

    Cases:
      1. item W errors: a half declaration, a missing script, a generator of none, a non-string command and a
         generator on a source record are refused; a full declaration and a source record's own check are not.
      2. item W advisories: a generated record with neither field and a check of none pass with an advisory.
      3. -Strict refuses a generated record with neither field.
      4. a declared local registry is read: its records are counted, a published local record and an id held
         by both registries are refused.
      5. a declared local registry that is absent is passed over in silence.
      6. query.ps1 lists a local record as local:<id>; generate.ps1 never names the key.

    Builds one scratch project under the profile's tempDir and removes it (-KeepScratch leaves it).
    Exit 0 on success, 1 on a failed case.
#>
param([switch] $KeepScratch)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '../harness/_profile.ps1')

$validate = Join-Path $PSScriptRoot '../harness/document_registry/validate.ps1'
$query = Join-Path $PSScriptRoot '../harness/document_registry/query.ps1'
$generate = Join-Path $PSScriptRoot '../harness/document_registry/generate.ps1'
$failures = 0

function Assert-Case([bool] $Condition, [string] $Case, [string[]] $Output) {
    if ($Condition) {
        Write-Host "PASS $Case"
        return
    }
    Write-Host "FAIL $Case" -ForegroundColor Red
    $Output | ForEach-Object { Write-Host "    $_" }
    $script:failures++
}

function Write-Registry([string] $Path, [object[]] $Records) {
    $lines = @($Records | ForEach-Object { $_ | ConvertTo-Json -Compress -Depth 5 })
    [IO.File]::WriteAllText($Path, ($lines -join "`n") + "`n")
}

function New-Record([string] $Id, [hashtable] $Extra = @{}) {
    $record = [ordered]@{
        id = $Id; title = $Id; category = 'technical'; audience = 'developer'; paths = @('docs/page.md')
        published = $false; indexable = $false; product_areas = @('area'); update_triggers = @('trigger')
        generated = $false
    }
    foreach ($key in $Extra.Keys) { $record[$key] = $Extra[$key] }
    return [pscustomobject]$record
}

function Invoke-Tool([string] $Script, [string[]] $Arguments = @()) {
    $output = @(& pwsh -NoProfile -File $Script @Arguments 2>&1 | ForEach-Object { "$_".Trim() })
    return [pscustomobject]@{ Code = $LASTEXITCODE; Output = $output }
}

$scratch = Join-Path (Get-SzaPath 'tempDir') ('document-registry-tests-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$priorRoot = $env:SZA_PROJECT_ROOT
try {
    foreach ($folder in 'docs', 'dev', 'tools') { New-Item -ItemType Directory -Force -Path (Join-Path $scratch $folder) | Out-Null }
    [IO.File]::WriteAllText((Join-Path $scratch 'docs/page.md'), "# Page`n")
    [IO.File]::WriteAllText((Join-Path $scratch 'dev/note.md'), "# Note`n")
    [IO.File]::WriteAllText((Join-Path $scratch 'tools/gen.ps1'), "exit 0`n")
    $profilePath = Join-Path $scratch '.sza-profile.json'
    [IO.File]::WriteAllText($profilePath, '{"version":"1"}')
    $env:SZA_PROJECT_ROOT = $scratch
    $tracked = Join-Path $scratch 'docs/DOCUMENT_REGISTRY.jsonl'
    $local = Join-Path $scratch 'dev/DOCUMENT_REGISTRY.jsonl'
    $generator = 'pwsh -NoProfile -File tools/gen.ps1'

    # 1. Item W errors.
    Write-Registry $tracked @(
        (New-Record 'gen-ok' @{ generated = $true; generator = $generator; check = "$generator -Check" })
        (New-Record 'gen-half' @{ generated = $true; generator = $generator })
        (New-Record 'gen-missing-script' @{ generated = $true; generator = 'pwsh -File tools/missing.ps1 and tools/gen.ps1'; check = $generator })
        (New-Record 'gen-generator-none' @{ generated = $true; generator = 'none'; check = $generator })
        (New-Record 'gen-not-string' @{ generated = $true; generator = $generator; check = 5 })
        (New-Record 'src-generator' @{ generator = $generator })
        (New-Record 'src-check' @{ check = 'tools/gen.ps1' })
    )
    $run = Invoke-Tool $validate
    $text = $run.Output -join "`n"
    Assert-Case ($run.Code -eq 1) 'item W errors exit 1' $run.Output
    Assert-Case ($text.Contains("gen-half: generated record has no 'check' field")) 'a half declaration is refused' $run.Output
    Assert-Case ($text.Contains("gen-missing-script: 'generator' names a script that does not exist: tools/missing.ps1")) 'a missing first script is refused' $run.Output
    Assert-Case ($text.Contains("gen-generator-none: 'generator' cannot be none")) 'a generator of none is refused' $run.Output
    Assert-Case ($text.Contains("gen-not-string: 'check' is not a command line")) 'a non-string command is refused' $run.Output
    Assert-Case ($text.Contains("src-generator: carries 'generator' but is not generated")) 'a generator on a source is refused' $run.Output
    Assert-Case (-not ($text -match '(?m)^(gen-ok|src-check):')) 'a full declaration and a source check pass' $run.Output
    Assert-Case ($text.Contains('Document registry FAILED: 5 error(s)')) 'exactly the five refusals' $run.Output

    # 2. Item W advisories.
    Write-Registry $tracked @(
        (New-Record 'gen-ok' @{ generated = $true; generator = $generator; check = "$generator -Check" })
        (New-Record 'gen-bare' @{ generated = $true })
        (New-Record 'gen-check-none' @{ generated = $true; generator = $generator; check = 'none yet: rerun by hand' })
    )
    $run = Invoke-Tool $validate
    $text = $run.Output -join "`n"
    Assert-Case ($run.Code -eq 0 -and $text.Contains('Document registry PASS: 3 record(s), 2 advisory')) 'advisories keep the pass' $run.Output
    Assert-Case ($text.Contains("advisory: gen-bare: generated record names no 'generator' and no 'check'")) 'neither field is an advisory' $run.Output
    Assert-Case ($text.Contains('advisory: gen-check-none: render has no drift check')) 'a check of none with its reason is an advisory' $run.Output

    # 3. -Strict.
    $run = Invoke-Tool $validate @('-Strict')
    $text = $run.Output -join "`n"
    Assert-Case ($run.Code -eq 1 -and $text.Contains('Document registry FAILED: 1 error(s)') -and
        $text.Contains("gen-bare: generated record names no 'generator'")) '-Strict refuses neither field, keeps none an advisory' $run.Output

    # 4. A declared local registry is read.
    [IO.File]::WriteAllText($profilePath, '{"version":"1","paths":{"localDocumentRegistry":"dev/DOCUMENT_REGISTRY.jsonl"}}')
    Write-Registry $tracked @((New-Record 'tracked-page'))
    Write-Registry $local @(
        (New-Record 'local-note' @{ paths = @('dev/note.md'); product_areas = @('local-area') })
        (New-Record 'tracked-page' @{ paths = @('dev/note.md') })
        (New-Record 'local-published' @{ paths = @('dev/note.md'); published = $true })
    )
    $run = Invoke-Tool $validate
    $text = $run.Output -join "`n"
    Assert-Case ($run.Code -eq 1 -and $text.Contains('Document registry FAILED: 2 error(s)')) 'local registry errors exit 1' $run.Output
    Assert-Case ($text.Contains('local:tracked-page: duplicate id')) 'an id held by both registries is refused' $run.Output
    Assert-Case ($text.Contains('local:local-published: a local registry record is never published')) 'a published local record is refused' $run.Output
    Write-Registry $local @((New-Record 'local-note' @{ paths = @('dev/note.md'); product_areas = @('local-area') }))
    $run = Invoke-Tool $validate
    Assert-Case ($run.Code -eq 0 -and ($run.Output -join "`n").Contains('Document registry PASS: 1 record(s), 1 local record(s)')) 'local records are counted' $run.Output

    # 6. query.ps1 reads the local registry; generate.ps1 never does.
    $run = Invoke-Tool $query @('-ProductArea', 'local-area')
    Assert-Case ($run.Code -eq 0 -and ($run.Output -join "`n").Contains('local:local-note | local-note | areas=local-area')) 'query lists a local record as local:<id>' $run.Output
    Assert-Case (-not (Select-String -LiteralPath $generate -Pattern 'localDocumentRegistry' -SimpleMatch -Quiet)) 'generate.ps1 never reads the local registry' @()

    # 5. A declared local registry that is absent.
    Remove-Item -LiteralPath $local -Force
    $run = Invoke-Tool $validate
    Assert-Case ($run.Code -eq 0 -and ($run.Output -join "`n") -eq 'Document registry PASS: 1 record(s)') 'an absent local registry is passed over in silence' $run.Output
} finally {
    if ($null -eq $priorRoot) { Remove-Item Env:SZA_PROJECT_ROOT -ErrorAction SilentlyContinue } else { $env:SZA_PROJECT_ROOT = $priorRoot }
    if (-not $KeepScratch -and (Test-Path -LiteralPath $scratch)) { Remove-Item -LiteralPath $scratch -Recurse -Force }
}

if ($failures -gt 0) {
    Write-Host "document-registry.tests: $failures case(s) failed" -ForegroundColor Red
    exit 1
}
Write-Host 'document-registry.tests: all cases passed' -ForegroundColor Green
exit 0
