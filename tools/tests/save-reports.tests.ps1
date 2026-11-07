#requires -Version 7.5
<#
.SYNOPSIS
    Cases for tools/site-audit/save-reports.ps1 - writing the reports a site-audit workflow returned as text.

.DESCRIPTION
    Runs the script over a throwaway git repository in a temp folder whose temp/ is ignored, with workflow outputs
    built here; the real repositories are never read or written and nothing goes to the network. Git runs without the
    global and the system configuration and never climbs above the temp folder.

      1. A notice's output file (the result under "result"): every site report, a lens report in saves[] and the
         portfolio are written with their exact text, exit 0.
      2. A path git would track, a path outside a run folder and a file name the workflow never writes are refused and
         not written, exit 3; the good item in the same result is still written.
      3. An existing report is kept without -Force and replaced with it; an item with no text is kept, not refused.
      4. A file that is not JSON, or JSON with no sites, is exit 2.
#>
[CmdletBinding()]
param([switch] $KeepScratch)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$SourceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$script_ = Join-Path $SourceRoot 'tools\site-audit\save-reports.ps1'
$pwshExe = (Get-Command pwsh -CommandType Application | Select-Object -First 1).Source

$run = 0; $passed = 0; $failed = 0
function Assert-That([bool] $Condition, [string] $Message) { if (-not $Condition) { throw $Message } }
function Run-Case([string] $Name, [scriptblock] $Body) {
    $script:run++
    Write-Host -NoNewline "CASE  $Name .. "
    try { & $Body; $script:passed++; Write-Host 'PASS' -ForegroundColor Green }
    catch { $script:failed++; Write-Host 'FAIL' -ForegroundColor Red; Write-Host "      $($_.Exception.Message)" -ForegroundColor DarkRed }
}
function Write-Text([string] $Path, [string] $Text) {
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path)) | Out-Null
    [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false))
}
function Read-Text([string] $Path) { [IO.File]::ReadAllText($Path) }
function Invoke-Save([string] $Json, [string[]] $Extra = @()) {
    $file = Join-Path $scratch ('out-' + [guid]::NewGuid().ToString('N').Substring(0, 6) + '.json')
    Write-Text $file $Json
    $text = & $pwshExe -NoProfile -File $script_ -Output $file @Extra 2>&1 | Out-String
    [pscustomobject]@{ code = $LASTEXITCODE; text = $text }
}

$scratch = Join-Path ([IO.Path]::GetTempPath()) ('save-reports-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $scratch | Out-Null
$savedEnv = @{}
try {
    $gitEnv = [ordered]@{ GIT_CONFIG_GLOBAL = (Join-Path $scratch 'gitconfig'); GIT_CONFIG_NOSYSTEM = '1'; XDG_CONFIG_HOME = (Join-Path $scratch 'xdg'); GIT_CEILING_DIRECTORIES = $scratch }
    foreach ($k in $gitEnv.Keys) { $savedEnv[$k] = [Environment]::GetEnvironmentVariable($k); [Environment]::SetEnvironmentVariable($k, $gitEnv[$k]) }
    Write-Text $gitEnv.GIT_CONFIG_GLOBAL ''

    $repo = Join-Path $scratch 'repo'
    New-Item -ItemType Directory -Path $repo | Out-Null
    & git -C $repo init -q 2>$null
    Write-Text (Join-Path $repo '.gitignore') "temp/`n"
    $runDir = Join-Path $repo 'temp\site-audit\2026-05-04'
    $ext = Join-Path $runDir 'external\example.org'
    $tracked = Join-Path $repo 'audit\site-audit\2026-05-04'
    function Js($Object) { $Object | ConvertTo-Json -Depth 10 }

    Run-Case '1 a notice output: site reports, a lens report and the portfolio are written, exit 0' {
        $result = @{ result = @{ sites = @(
                    @{ key = 'a'; report = (Join-Path $runDir 'report.md'); markdown = "# A`nline .. two`n"
                       saves = @(@{ path = (Join-Path $runDir 'release-facts.md'); markdown = "# lens`n" }) }
                    @{ key = 'x'; report = (Join-Path $ext 'report.md'); markdown = "# X`n" })
                portfolio = @{ report = (Join-Path $runDir 'portfolio.md'); markdown = "# P`n" } } }
        $r = Invoke-Save (Js $result)
        Assert-That ($r.code -eq 0) "exit $($r.code): $($r.text)"
        Assert-That ((Read-Text (Join-Path $runDir 'report.md')) -ceq "# A`nline .. two`n") 'site report text differs'
        Assert-That ((Read-Text (Join-Path $runDir 'release-facts.md')) -ceq "# lens`n") 'lens report not written'
        Assert-That ((Read-Text (Join-Path $ext 'report.md')) -ceq "# X`n") 'external report not written'
        Assert-That ((Read-Text (Join-Path $runDir 'portfolio.md')) -ceq "# P`n") 'portfolio not written'
        Assert-That ($r.text -match '4 written, 0 refused') "summary line: $($r.text)"
    }

    Run-Case '2 tracked, outside a run folder, unknown name: refused and not written, exit 3' {
        $result = @{ sites = @(
                @{ key = 't'; report = (Join-Path $tracked 'report.md'); markdown = 'x' }
                @{ key = 'o'; report = (Join-Path $repo 'temp\report.md'); markdown = 'x' }
                @{ key = 'n'; report = (Join-Path $runDir 'notes.md'); markdown = 'x' }
                @{ key = 'g'; report = (Join-Path $runDir '_2\report.md'); markdown = 'x' }
                @{ key = 'ok'; report = (Join-Path $repo 'temp\site-audit\2026-05-04_2\report.md'); markdown = "# ok`n" }) }
        $r = Invoke-Save (Js $result)
        Assert-That ($r.code -eq 3) "exit $($r.code): $($r.text)"
        Assert-That (-not (Test-Path (Join-Path $tracked 'report.md'))) 'a tracked path was written'
        Assert-That (-not (Test-Path (Join-Path $repo 'temp\report.md'))) 'a path outside a run folder was written'
        Assert-That (-not (Test-Path (Join-Path $runDir 'notes.md'))) 'an unknown file name was written'
        Assert-That (-not (Test-Path (Join-Path $runDir '_2\report.md'))) 'a folder that is no run key was written'
        Assert-That ((Read-Text (Join-Path $repo 'temp\site-audit\2026-05-04_2\report.md')) -ceq "# ok`n") 'the good item was not written'
        Assert-That ($r.text -match 'git would track it' -and $r.text -match 'not inside a site-audit run folder' -and $r.text -match 'not a file name') "reasons: $($r.text)"
    }

    Run-Case '3 an existing report is kept without -Force and replaced with it; no text is kept, not refused' {
        $p = Join-Path $runDir 'report.md'
        Write-Text $p 'edited by hand'
        $result = @{ sites = @(@{ key = 'a'; report = $p; markdown = 'new' }, @{ key = 'e'; report = (Join-Path $ext 'report.md'); markdown = '' }) }
        $r = Invoke-Save (Js $result)
        Assert-That ($r.code -eq 0) "exit $($r.code): $($r.text)"
        Assert-That ((Read-Text $p) -ceq 'edited by hand') 'replaced without -Force'
        $r = Invoke-Save (Js $result) @('-Force')
        Assert-That ($r.code -eq 0) "exit $($r.code) with -Force: $($r.text)"
        Assert-That ((Read-Text $p) -ceq 'new') 'not replaced with -Force'
        Assert-That ($r.text -match 'carries no text') "no-text line: $($r.text)"
    }

    Run-Case '4 not JSON, or JSON with no sites: exit 2' {
        $r = Invoke-Save 'not json {'
        Assert-That ($r.code -eq 2) "not JSON gave exit $($r.code)"
        $r = Invoke-Save '{"mode":"audit"}'
        Assert-That ($r.code -eq 2) "no sites gave exit $($r.code)"
    }
}
finally {
    foreach ($k in $savedEnv.Keys) { [Environment]::SetEnvironmentVariable($k, $savedEnv[$k]) }
    if (-not $KeepScratch) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host "save-reports tests: $run run, $passed passed, $failed failed"
if ($failed) { exit 1 }
exit 0
