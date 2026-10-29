#requires -Version 7.0
<#
.SYNOPSIS
    Cases for tools/harness/aliases/register-spec-commands.ps1 - the forwarders that make /spec-quiz /sq /spec-draft /sd
    /spec-next /sn /spec-all /sa work in every project.

.DESCRIPTION
    Runs the script over throwaway project folders and a throwaway portfolio root; the real registry and the real
    projects are never read or written. Starts no agent, so the whole file takes a few seconds.

      1. A fresh project gets exactly the eight files, nothing else; a re-run changes nothing.
      2. A forwarder carries the skill name, the literal $ARGUMENTS and the forwards_to marker.
      3. A hand-written command of the same name is kept byte for byte; the other seven are written.
      4. -Check writes nothing and exits 1 on a missing or stale file; a re-run repairs it; -Check then exits 0.
      5. -All walks the enabled registry projects minus -Skip, leaves a disabled one alone, and reports a missing folder.
      6. Refusals exit 2 (unknown project, no project at or above the folder); no argument uses the current project.
#>
[CmdletBinding()]
param([switch] $KeepScratch)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$SourceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$script_ = Join-Path $SourceRoot 'tools\harness\aliases\register-spec-commands.ps1'
$pwshExe = (Get-Command pwsh -CommandType Application | Select-Object -First 1).Source
$names = @('sa', 'sd', 'sn', 'spec-all', 'spec-draft', 'spec-next', 'spec-quiz', 'sq')

$run = 0; $passed = 0; $failed = 0
function Assert-That([bool] $Condition, [string] $Message) { if (-not $Condition) { throw $Message } }
function Run-Case([string] $Name, [scriptblock] $Body) {
    $script:run++
    Write-Host -NoNewline "CASE  $Name ... "
    try { & $Body; $script:passed++; Write-Host 'PASS' -ForegroundColor Green }
    catch { $script:failed++; Write-Host 'FAIL' -ForegroundColor Red; Write-Host "      $($_.Exception.Message)" -ForegroundColor DarkRed }
}

$scratch = Join-Path ([IO.Path]::GetTempPath()) ('register-cmds-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $scratch | Out-Null
$portfolio = Join-Path $scratch 'portfolio'
New-Item -ItemType Directory -Path $portfolio | Out-Null

function New-Project([string] $Key) {
    $root = Join-Path $scratch $Key
    New-Item -ItemType Directory -Path (Join-Path $root 'sub') -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $root '.sza-profile.json'), '{}')
    return $root
}
$pa = New-Project 'a'; $pb = New-Project 'b'; $pc = New-Project 'c'; $pf = New-Project 'f'
$d1 = New-Project 'd1'; $d2 = New-Project 'd2'; $d3 = New-Project 'd3'
$d4 = Join-Path $scratch 'd4-gone'
$bare = Join-Path $scratch 'no-project'
New-Item -ItemType Directory -Path $bare | Out-Null

# Project b already has its own spec-quiz command, written by hand.
$handFile = Join-Path $pb '.claude\commands\spec-quiz.md'
New-Item -ItemType Directory -Path (Split-Path $handFile) -Force | Out-Null
$handText = "---`ndescription: `"mine`"`n---`nhand-written body`n"
[IO.File]::WriteAllText($handFile, $handText, [Text.UTF8Encoding]::new($false))

$repos = foreach ($p in @(@('dd-one', $d1, $true, 10), @('dd-two', $d2, $false, 20), @('dd-three', $d3, $true, 30), @('dd-four', $d4, $true, 40))) {
    [ordered]@{ key = $p[0]; path = $p[1]; enabled = $p[2]; maxWorkers = 1; concurrent = $false; role = 'product'; permissionMode = 'bypassPermissions'; rank = $p[3] }
}
[IO.File]::WriteAllText((Join-Path $portfolio 'repos.json'), (ConvertTo-Json -InputObject ([ordered]@{ schemaVersion = '1.0'; repos = @($repos) }) -Depth 5))

# Each group is a chain of steps run in order; the groups run side by side so the file stays fast.
#   a = script arguments, w = working folder, append = @{file; text} done BEFORE the run
$groups = [ordered]@{
    fresh   = @( @{ a = @('-Project', $pa); w = $scratch }, @{ a = @('-Project', $pa); w = $scratch } )
    hand    = @( @{ a = @('-Project', $pb); w = $scratch } )
    stale   = @(
        @{ a = @('-Check', '-Project', $pc); w = $scratch },
        @{ a = @('-Project', $pc); w = $scratch },
        @{ a = @('-Check', '-Project', $pc); w = $scratch; append = @{ file = (Join-Path $pc '.claude\commands\sq.md'); text = "drift`n" } },
        @{ a = @('-Project', $pc); w = $scratch },
        @{ a = @('-Check', '-Project', $pc); w = $scratch }
    )
    all     = @( @{ a = @('-All', '-Skip', 'dd-three,dd-nothing'); w = $scratch; reg = $portfolio } )
    nokey   = @( @{ a = @('-Project', 'nope'); w = $scratch; reg = $portfolio } )
    nowhere = @( @{ a = @(); w = $bare; reg = $portfolio } )
    cwd     = @( @{ a = @(); w = (Join-Path $pf 'sub'); reg = $portfolio } )
}
$results = @{}
$groups.GetEnumerator() | ForEach-Object -ThrottleLimit 8 -Parallel {
    $outList = @()
    foreach ($s in $_.Value) {
        if ($s.ContainsKey('append')) { [IO.File]::AppendAllText($s.append.file, $s.append.text) }
        $psi = [Diagnostics.ProcessStartInfo]::new($using:pwshExe)
        foreach ($x in (@('-NoProfile', '-File', $using:script_) + $s.a)) { $psi.ArgumentList.Add([string] $x) }
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
        $psi.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
        $psi.WorkingDirectory = $s.w
        $psi.Environment['SZA_PORTFOLIO_ROOT'] = $(if ($s.ContainsKey('reg')) { $s.reg } else { $using:portfolio })
        $proc = [Diagnostics.Process]::Start($psi)
        $o = $proc.StandardOutput.ReadToEndAsync()
        $e = $proc.StandardError.ReadToEndAsync()
        if (-not $proc.WaitForExit(60000)) { $proc.Kill($true) }
        $proc.WaitForExit()
        $lines = @($o.Result -split '\r?\n' | Where-Object { $_.Trim() })
        $outList += [pscustomobject]@{ code = $proc.ExitCode; lines = $lines; text = ($lines -join "`n"); stderr = $e.Result; last = $(if ($lines.Count) { $lines[-1] } else { '' }) }
    }
    [pscustomobject]@{ name = $_.Key; steps = $outList }
} | ForEach-Object { $results[$_.name] = @($_.steps) }

function Rel-Files([string] $Root) {
    return @(Get-ChildItem -LiteralPath $Root -Recurse -File -Force | ForEach-Object { $_.FullName.Substring($Root.Length).TrimStart('\') } | Sort-Object)
}

try {
    Run-Case '1 fresh project, then a re-run' {
        $s = $results['fresh']
        Assert-That ($s[0].code -eq 0) "exit $($s[0].code): $($s[0].text) $($s[0].stderr)"
        Assert-That ($s[0].last -eq 'register-spec-commands: 1 project(s), wrote 8, unchanged 0, kept 0 hand-written') "first: $($s[0].last)"
        Assert-That ($s[1].last -eq 'register-spec-commands: 1 project(s), wrote 0, unchanged 8, kept 0 hand-written') "re-run: $($s[1].last)"
        $files = Rel-Files $pa
        $expected = @($names | ForEach-Object { ".claude\commands\$_.md" }) + '.sza-profile.json' | Sort-Object
        Assert-That (($files -join '|') -eq ($expected -join '|')) "files: $($files -join ', ')"
    }
    Run-Case '2 forwarder content' {
        $sq = [IO.File]::ReadAllText((Join-Path $pa '.claude\commands\sq.md'))
        Assert-That ($sq.StartsWith("---`n")) 'no frontmatter'
        Assert-That ($sq.Contains('forwards_to: sza:spec-quiz')) 'sq: marker or skill'
        Assert-That ($sq.Contains('passing `$ARGUMENTS` as its args')) 'sq: $ARGUMENTS not literal'
        Assert-That ($sq.Contains('disable-model-invocation: true')) 'sq: still model-invocable'
        Assert-That (-not $sq.Contains("`r")) 'sq: CR in the file'
        foreach ($pair in @(@('spec-draft', 'sza:spec-draft'), @('sd', 'sza:spec-draft'), @('spec-next', 'sza:spec-next'), @('sn', 'sza:spec-next'), @('spec-all', 'sza:spec-all'), @('sa', 'sza:spec-all'), @('spec-quiz', 'sza:spec-quiz'))) {
            $t = [IO.File]::ReadAllText((Join-Path $pa ".claude\commands\$($pair[0]).md"))
            Assert-That ($t.Contains("forwards_to: $($pair[1])")) "$($pair[0]) forwards to the wrong skill"
            Assert-That ($t.Contains("``/$($pair[0])`` runs")) "$($pair[0]) names itself wrongly"
        }
    }
    Run-Case '3 hand-written command kept' {
        $s = $results['hand'][0]
        Assert-That ($s.code -eq 0) "exit $($s.code): $($s.text)"
        Assert-That ($s.last -eq 'register-spec-commands: 1 project(s), wrote 7, unchanged 0, kept 1 hand-written') "result: $($s.last)"
        Assert-That ($s.text.Contains('kept hand-written: spec-quiz')) "kept line: $($s.text)"
        Assert-That ([IO.File]::ReadAllText($handFile) -eq $handText) 'the hand-written file changed'
    }
    Run-Case '4 check and repair' {
        $s = $results['stale']
        Assert-That ($s[0].code -eq 1 -and $s[0].last -eq 'register-spec-commands: 1 project(s), wrote 0, unchanged 0, kept 0 hand-written, drift 8') "check on empty: $($s[0].code) $($s[0].last)"
        Assert-That ($s[1].last -eq 'register-spec-commands: 1 project(s), wrote 8, unchanged 0, kept 0 hand-written') "write: $($s[1].last)"
        Assert-That ($s[2].code -eq 1 -and $s[2].text.Contains('DRIFT: sq')) "check on stale: $($s[2].code) $($s[2].text)"
        Assert-That ($s[3].last -eq 'register-spec-commands: 1 project(s), wrote 1, unchanged 7, kept 0 hand-written') "repair: $($s[3].last)"
        Assert-That ($s[4].code -eq 0 -and $s[4].last -eq 'register-spec-commands: 1 project(s), wrote 0, unchanged 8, kept 0 hand-written, drift 0') "check on clean: $($s[4].code) $($s[4].last)"
    }
    Run-Case '5 -All over the registry' {
        $s = $results['all'][0]
        Assert-That ($s.code -eq 1) "exit $($s.code) (a missing folder is exit 1): $($s.text) $($s.stderr)"
        Assert-That ($s.text.Contains('dd-one') -and $s.text.Contains('wrote 8')) "dd-one: $($s.text)"
        Assert-That ($s.text -match 'dd-four\s+MISSING folder') "missing folder not reported: $($s.text)"
        Assert-That (Test-Path -LiteralPath (Join-Path $d1 '.claude\commands\sa.md')) 'enabled project not written'
        Assert-That (-not (Test-Path -LiteralPath (Join-Path $d2 '.claude'))) 'disabled project was written'
        Assert-That (-not (Test-Path -LiteralPath (Join-Path $d3 '.claude'))) 'skipped project was written'
        Assert-That ($s.last -eq 'register-spec-commands: 2 project(s), wrote 8, unchanged 0, kept 0 hand-written') "summary: $($s.last)"
    }
    Run-Case '6 refusals and the current project' {
        Assert-That ($results['nokey'][0].code -eq 2) "unknown key exit $($results['nokey'][0].code)"
        Assert-That ($results['nowhere'][0].code -eq 2) "no project exit $($results['nowhere'][0].code)"
        $c = $results['cwd'][0]
        Assert-That ($c.code -eq 0 -and $c.last -eq 'register-spec-commands: 1 project(s), wrote 8, unchanged 0, kept 0 hand-written') "cwd: $($c.code) $($c.last)"
        Assert-That (Test-Path -LiteralPath (Join-Path $pf '.claude\commands\spec-all.md')) 'the current project was not written'
        Assert-That (-not (Test-Path -LiteralPath (Join-Path $pf 'sub\.claude'))) 'written into the subfolder'
    }
}
finally {
    if (-not $KeepScratch) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host ("register-spec-commands tests: {0} run, {1} passed, {2} failed" -f $run, $passed, $failed)
exit $(if ($failed -eq 0) { 0 } else { 1 })
