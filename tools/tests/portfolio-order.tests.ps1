<# Fast tests for Get-PortfolioQueueOrder (tools/harness/spec_catalog/_portfolio-order.ps1; TASK-FLOW rules 18 and 44).
     1. A registered repository's rows come back in the reader's order (before the first heading, numbered packages
        as integers, then '--'); a slug, a comment and another repository's rows do not disturb it, a repeated id
        keeps the place of its first line in the file (S0003 stays in package 10 although package 2 repeats it),
        rows under 'hold' carry no order, and the path matches in another letter case with a trailing separator.
     2. An unregistered repository, and one the file names by a bare key only, get no order.
     3. A missing registry, an unreadable one, one without repos and a missing queue file give no order, no throw.
     4. The registry's paths.portfolioQueue (relative to the portfolio root) names the file that is read.
   A throwaway folder and direct calls with -PortfolioRoot: no real registry, queue file or repository is read, no
   process is spawned, no environment variable is changed. -KeepScratch leaves the folder for inspection. #>
[CmdletBinding()]
param([switch]$KeepScratch)
$ErrorActionPreference = 'Stop'
$SourceRoot = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent)
. (Join-Path $SourceRoot 'tools/harness/spec_catalog/_portfolio-order.ps1')
$run = 0; $passed = 0; $failed = 0
function Assert-That([bool]$Condition, [string]$Reason) { if (-not $Condition) { throw $Reason } }
function Test-Case([string]$Name, [scriptblock]$Body) {
    $script:run++
    Write-Host -NoNewline "CASE  $Name ... "
    try { & $Body; $script:passed++; Write-Host 'PASS' -ForegroundColor Green }
    catch { $script:failed++; Write-Host 'FAIL' -ForegroundColor Red; Write-Host "      $($_.Exception.Message)" -ForegroundColor DarkRed }
}
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('portfolio-order-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$repoA = Join-Path $scratch 'RepoA'; $repoB = Join-Path $scratch 'repo-b'; $repoC = Join-Path $scratch 'repo-c'
foreach ($d in @($repoA, $repoB, $repoC)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
function New-Root([string]$Name, $Registry, [string[]]$Queue, [string]$QueueName = 'PORTFOLIO_QUEUE.md') {
    $root = Join-Path $scratch $Name
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    if ($Registry -is [string]) { Set-Content -LiteralPath (Join-Path $root 'repos.json') -Value $Registry -Encoding utf8 }
    elseif ($null -ne $Registry) { $Registry | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $root 'repos.json') -Encoding utf8 }
    if ($null -ne $Queue) { Set-Content -LiteralPath (Join-Path $root $QueueName) -Value $Queue -Encoding utf8 }
    return $root
}
$repos = @(@{ key = 'alpha'; path = $repoA }, @{ key = 'beta'; path = $repoB })
$queue = @('alpha:S0009_first  26-11-18 10:00  Draft', 'ticket   changed   status', '10', 'alpha:S0003', 'beta:S0001_other', '2',
    'alpha:S0007_slug-here  26-11-18 10:00  Draft  # a note', 'alpha:S0009', 'alpha:S0003', 'beta', '--', 'alpha:S0001', 'hold', 'alpha:S0005', '3', 'alpha:S0004')
try {
    Test-Case 'rows come back in the reader''s order; hold, other repositories, slugs and repeats do not disturb it' {
        $root = New-Root 'r1' @{ repos = $repos } $queue
        $o = Get-PortfolioQueueOrder -ProjectRoot ($repoA.ToUpperInvariant() + '\') -PortfolioRoot $root
        Assert-That ($o.key -ceq 'alpha') "key is '$($o.key)'"
        Assert-That (($o.ids -join ',') -ceq 'S0009,S0007,S0004,S0003,S0001') "ids are '$($o.ids -join ',')'"
        Assert-That ($o.file -ceq (Join-Path $root 'PORTFOLIO_QUEUE.md')) "file is '$($o.file)'"
    }
    Test-Case 'an unregistered repository and a repository named by a bare key get no order' {
        $c = Get-PortfolioQueueOrder -ProjectRoot $repoC -PortfolioRoot (New-Root 'r2' @{ repos = $repos } $queue)
        Assert-That ($null -eq $c.key -and $c.ids.Count -eq 0) "unregistered: key '$($c.key)', ids '$($c.ids -join ',')'"
        $b = Get-PortfolioQueueOrder -ProjectRoot $repoB -PortfolioRoot (New-Root 'r2b' @{ repos = $repos } @('1', 'beta', 'beta:*', 'alpha:S0001'))
        Assert-That ($b.key -ceq 'beta' -and $b.ids.Count -eq 0) "bare key: ids '$($b.ids -join ',')'"
    }
    Test-Case 'a missing registry, an unreadable registry and a missing queue file give no order and do not throw' {
        foreach ($root in @((New-Root 'r3a' $null $queue), (New-Root 'r3b' '{ not json' $queue), (New-Root 'r3c' @{ repos = $repos } $null), (New-Root 'r3d' @{ other = 1 } $queue))) {
            $o = Get-PortfolioQueueOrder -ProjectRoot $repoA -PortfolioRoot $root
            Assert-That ($o.ids -is [string[]] -and $o.ids.Count -eq 0) "$root gave ids '$($o.ids -join ',')'"
        }
    }
    Test-Case 'the registry''s paths.portfolioQueue names the file that is read' {
        $root = New-Root 'r4' @{ repos = $repos; paths = @{ portfolioQueue = 'other-queue.md' } } @('1', 'alpha:S0042') 'other-queue.md'
        Set-Content -LiteralPath (Join-Path $root 'PORTFOLIO_QUEUE.md') -Value @('1', 'alpha:S0001') -Encoding utf8
        $o = Get-PortfolioQueueOrder -ProjectRoot $repoA -PortfolioRoot $root
        Assert-That (($o.ids -join ',') -ceq 'S0042') "ids are '$($o.ids -join ',')'"
    }
} finally {
    if (-not $KeepScratch) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
}
Write-Host ("RESULT  run={0}  passed={1}  failed={2}" -f $run, $passed, $failed)
if ($failed -gt 0) { exit 1 } else { exit 0 }
