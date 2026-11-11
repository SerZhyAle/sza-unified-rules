#requires -Version 7.0
<#
.SYNOPSIS
    Cases for resolve-ticket.ps1 (S0027) - which project and which reading the argument of /spec-all, /sa, /spec-next
    and /sn means, decided the same way every time.

.DESCRIPTION
    Runs the resolver over two throwaway projects (alpha, beta; each with a .sza-profile.json and a hand-written
    ledger) and a throwaway portfolio root with a hand-written repos.json. The real registry and ledgers are never
    read or written; no agent and no pq child starts. Each call runs in a fresh in-process runspace, so the whole file
    takes about a second.

      1. <key>:<id> resolves to the named project's ticket, from the other project's folder.
      2. The same id in both projects resolves to the NAMED one; a bare number is the id's trailing digits.
      3. A registered key with an id the project does not hold is refused and never falls back to the current project.
      4. A token before the colon that is not a registered key is not a project reference (idea, never a lookup).
      5. A bare registered key is the next ticket of that project (project-next).
      6. A bare key that is also a local slug, or the local id shape, is refused as ambiguous, naming both readings.
      7. The current project's id shape, a slug, an unknown hyphenated slug, free text and an empty argument.
      8. Next mode: no argument, a key, <key>:<id> refused, other text refused.
      9. A folder outside every project: local readings are refused, a <key>:<id> still resolves.
#>
[CmdletBinding()]
param([switch] $KeepScratch)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$SourceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$resolver = Join-Path $SourceRoot 'tools\harness\portfolio\resolve-ticket.ps1'

$run = 0; $passed = 0; $failed = 0
function Assert-That([bool] $Condition, [string] $Message) { if (-not $Condition) { throw $Message } }
function Run-Case([string] $Name, [scriptblock] $Body) {
    $script:run++
    Write-Host -NoNewline "CASE  $Name ... "
    try { & $Body; $script:passed++; Write-Host 'PASS' -ForegroundColor Green }
    catch { $script:failed++; Write-Host 'FAIL' -ForegroundColor Red; Write-Host "      $($_.Exception.Message)" -ForegroundColor DarkRed }
}

$scratch = Join-Path ([IO.Path]::GetTempPath()) ('ticket-resolve-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $scratch | Out-Null
$savedRoot = $env:SZA_PORTFOLIO_ROOT
$portfolio = Join-Path $scratch 'portfolio'
New-Item -ItemType Directory -Path $portfolio | Out-Null
$env:SZA_PORTFOLIO_ROOT = $portfolio

function Row([string] $Id, [string] $Name) {
    return (ConvertTo-Json -InputObject ([ordered]@{ id = $Id; name = $Name; status = 'Approved'; priority = 50; file = "PLAN/${Id}_$Name.md"; created = '2026-11-01'; updated = '2026-11-09 10:00' }) -Compress)
}
function New-Project([string] $Key, [string[]] $Rows) {
    $root = Join-Path $scratch $Key
    New-Item -ItemType Directory -Path (Join-Path $root 'PLAN') -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $root '.sza-profile.json'), '{}')
    [IO.File]::WriteAllText((Join-Path $root 'PLAN\spec-catalog.jsonl'), (($Rows -join "`n") + "`n"), [Text.UTF8Encoding]::new($false))
    return $root
}

# alpha and beta both hold S0021 (different tickets); only beta holds S0077; alpha has a ticket slugged "beta-notes"
# and a ticket slugged "gamma" (gamma is also a registered key below).
$alpha = New-Project 'alpha' @((Row 'S0021' 'alpha-own-21'), (Row 'S0030' 'beta-notes'), (Row 'S0031' 'gamma'))
$beta = New-Project 'beta' @((Row 'S0021' 'beta-own-21'), (Row 'S0077' 'beta-only-77'))
$gamma = New-Project 'gamma' @((Row 'S0005' 'gamma-five'))
$outside = Join-Path $scratch 'nowhere'
New-Item -ItemType Directory -Path $outside | Out-Null

$repos = foreach ($p in @(@('alpha', $alpha), @('beta', $beta), @('gamma', $gamma))) {
    [ordered]@{ key = $p[0]; path = $p[1]; enabled = $true; maxWorkers = 1; concurrent = $false; role = 'product'; permissionMode = 'bypassPermissions'; rank = 10 }
}
[IO.File]::WriteAllText((Join-Path $portfolio 'repos.json'), (ConvertTo-Json -InputObject ([ordered]@{ schemaVersion = '1.0'; repos = @($repos) }) -Depth 5))

# One resolver call in a fresh runspace (the script's `exit` ends that runspace's script, not this one).
function Resolve-It([string] $Arg, [string] $From = $alpha, [string] $Mode = 'ticket') {
    $ps = [powershell]::Create()
    try {
        $null = $ps.AddScript('param($s, $a, $f, $m) $out = & $s -Arg $a -CurrentProject $f -Mode $m; [pscustomobject]@{ code = $LASTEXITCODE; out = ($out -join "`n") }').
            AddArgument($resolver).AddArgument($Arg).AddArgument($From).AddArgument($Mode)
        $r = $ps.Invoke() | Select-Object -First 1
        if ($ps.Streams.Error.Count -gt 0) { throw "resolver raised: $($ps.Streams.Error | Select-Object -First 1)" }
        $o = ConvertFrom-Json -InputObject $r.out
        return [pscustomobject]@{ code = [int]$r.code; kind = $o.kind; project = $o.project; root = $o.root; id = $o.id; slug = $o.slug; reason = $o.reason }
    }
    finally { $ps.Dispose() }
}

try {
    $sw = [Diagnostics.Stopwatch]::StartNew()

    Run-Case '1. <key>:<id> from another project resolves to that project' {
        $r = Resolve-It 'beta:S0077'
        Assert-That ($r.code -eq 0 -and $r.kind -eq 'ticket' -and $r.project -eq 'beta' -and $r.id -eq 'S0077' -and $r.root -eq $beta) "got $($r | ConvertTo-Json -Compress)"
        Assert-That ($r.slug -eq 'beta-only-77') "slug $($r.slug)"
    }
    Run-Case '2. the same id in both projects resolves to the NAMED one; a bare number matches trailing digits' {
        $r = Resolve-It 'beta:S0021' $alpha
        Assert-That ($r.kind -eq 'ticket' -and $r.project -eq 'beta' -and $r.slug -eq 'beta-own-21') "named beta, got $($r | ConvertTo-Json -Compress)"
        $r = Resolve-It 'alpha:S0021' $beta
        Assert-That ($r.kind -eq 'ticket' -and $r.project -eq 'alpha' -and $r.slug -eq 'alpha-own-21') "named alpha, got $($r | ConvertTo-Json -Compress)"
        $r = Resolve-It 'S0021' $beta
        Assert-That ($r.kind -eq 'local-id' -and $r.project -eq 'beta' -and $r.slug -eq 'beta-own-21') "local from beta, got $($r | ConvertTo-Json -Compress)"
        $r = Resolve-It 'beta:77'
        Assert-That ($r.kind -eq 'ticket' -and $r.id -eq 'S0077') "bare number, got $($r | ConvertTo-Json -Compress)"
    }
    Run-Case '3. a failed lookup is refused and never falls back to the current project' {
        $r = Resolve-It 'beta:S0030'          # S0030 exists in alpha (the current project), not in beta
        Assert-That ($r.code -eq 2 -and $r.kind -eq 'refused' -and $r.project -eq 'beta' -and $null -eq $r.id) "got $($r | ConvertTo-Json -Compress)"
        Assert-That ($r.reason -like 'no such ticket in beta*') "reason: $($r.reason)"
        $r = Resolve-It 'beta:S0099'
        Assert-That ($r.code -eq 2 -and $r.kind -eq 'refused' -and $r.reason -like 'no such ticket in beta*') "got $($r | ConvertTo-Json -Compress)"
    }
    Run-Case '4. an unregistered token before the colon is not a project reference' {
        $r = Resolve-It 'zeta:S0021'
        Assert-That ($r.code -eq 0 -and $r.kind -eq 'idea' -and $r.project -eq 'alpha' -and $null -eq $r.id) "got $($r | ConvertTo-Json -Compress)"
        $r = Resolve-It 'Beta:S0077'          # a key is exact and case-sensitive
        Assert-That ($r.kind -eq 'idea') "Beta: got $($r | ConvertTo-Json -Compress)"
        $r = Resolve-It 'beta:S0077 and more words'
        Assert-That ($r.kind -eq 'idea') "several words are an idea, got $($r | ConvertTo-Json -Compress)"
    }
    Run-Case '5. a bare registered key is the next ticket of that project' {
        $r = Resolve-It 'beta'
        Assert-That ($r.code -eq 0 -and $r.kind -eq 'project-next' -and $r.project -eq 'beta' -and $r.root -eq $beta -and $null -eq $r.id) "got $($r | ConvertTo-Json -Compress)"
        $r = Resolve-It 'alpha' $beta
        Assert-That ($r.kind -eq 'project-next' -and $r.project -eq 'alpha') "alpha from beta, got $($r | ConvertTo-Json -Compress)"
    }
    Run-Case '6. a key that is also a local slug is refused as ambiguous, naming both readings' {
        $r = Resolve-It 'gamma'               # registered key, and the slug of alpha:S0031
        Assert-That ($r.code -eq 2 -and $r.kind -eq 'ambiguous') "got $($r | ConvertTo-Json -Compress)"
        Assert-That ($r.reason -like '*registered project gamma*' -and $r.reason -like '*S0031*' -and $r.reason -like '*gamma:<id>*') "reason: $($r.reason)"
        $r = Resolve-It 'gamma' $beta         # beta has no such slug: unambiguous there
        Assert-That ($r.code -eq 0 -and $r.kind -eq 'project-next' -and $r.project -eq 'gamma') "from beta, got $($r | ConvertTo-Json -Compress)"
    }
    Run-Case '7. local id, slug, unknown slug, free text, empty argument' {
        $r = Resolve-It 'S0030'
        Assert-That ($r.code -eq 0 -and $r.kind -eq 'local-id' -and $r.project -eq 'alpha' -and $r.id -eq 'S0030') "id, got $($r | ConvertTo-Json -Compress)"
        $r = Resolve-It 'S0999'
        Assert-That ($r.code -eq 0 -and $r.kind -eq 'local-id' -and $r.id -eq 'S0999') "absent id stays local, got $($r | ConvertTo-Json -Compress)"
        $r = Resolve-It 'beta-notes'          # the slug of alpha:S0030; beta is not a registered key for this token
        Assert-That ($r.code -eq 0 -and $r.kind -eq 'local-slug' -and $r.id -eq 'S0030' -and $r.project -eq 'alpha') "slug, got $($r | ConvertTo-Json -Compress)"
        $r = Resolve-It 'no-such-slug'
        Assert-That ($r.code -eq 2 -and $r.kind -eq 'refused' -and $r.reason -like 'unknown slug*') "unknown slug, got $($r | ConvertTo-Json -Compress)"
        $r = Resolve-It 'fix the crash on rotate'
        Assert-That ($r.code -eq 0 -and $r.kind -eq 'idea' -and $r.project -eq 'alpha') "idea, got $($r | ConvertTo-Json -Compress)"
        $r = Resolve-It ''
        Assert-That ($r.code -eq 2 -and $r.kind -eq 'refused' -and $r.reason -like 'no ticket and no idea*') "empty, got $($r | ConvertTo-Json -Compress)"
    }
    Run-Case '8. next mode: no argument, a key, a ticket refused, other text refused' {
        $r = Resolve-It '' $alpha 'next'
        Assert-That ($r.code -eq 0 -and $r.kind -eq 'project-next' -and $r.project -eq 'alpha' -and $r.root -eq $alpha) "no arg, got $($r | ConvertTo-Json -Compress)"
        $r = Resolve-It 'beta' $alpha 'next'
        Assert-That ($r.code -eq 0 -and $r.kind -eq 'project-next' -and $r.project -eq 'beta') "key, got $($r | ConvertTo-Json -Compress)"
        $r = Resolve-It 'gamma' $alpha 'next'  # no ambiguity in next mode: it takes no ticket or slug
        Assert-That ($r.code -eq 0 -and $r.kind -eq 'project-next' -and $r.project -eq 'gamma') "gamma, got $($r | ConvertTo-Json -Compress)"
        $r = Resolve-It 'beta:S0077' $alpha 'next'
        Assert-That ($r.code -eq 2 -and $r.kind -eq 'refused' -and $r.reason -like '*takes no ticket*') "ticket, got $($r | ConvertTo-Json -Compress)"
        $r = Resolve-It 'S0030' $alpha 'next'
        Assert-That ($r.code -eq 2 -and $r.kind -eq 'refused' -and $r.reason -like '*takes no argument or a project key*') "other, got $($r | ConvertTo-Json -Compress)"
    }
    Run-Case '9. outside every project: local readings refused, <key>:<id> and a key still resolve' {
        $r = Resolve-It 'S0021' $outside
        Assert-That ($r.code -eq 2 -and $r.kind -eq 'refused' -and $r.reason -like 'no project here*') "local, got $($r | ConvertTo-Json -Compress)"
        $r = Resolve-It 'beta:S0077' $outside
        Assert-That ($r.code -eq 0 -and $r.kind -eq 'ticket' -and $r.project -eq 'beta') "named, got $($r | ConvertTo-Json -Compress)"
        $r = Resolve-It 'beta' $outside
        Assert-That ($r.code -eq 0 -and $r.kind -eq 'project-next') "key, got $($r | ConvertTo-Json -Compress)"
        $r = Resolve-It '' $outside 'next'
        Assert-That ($r.code -eq 2 -and $r.kind -eq 'refused') "next, got $($r | ConvertTo-Json -Compress)"
    }

    $sw.Stop()
    Write-Host ("`n{0} cases, {1} passed, {2} failed, {3:N1} s" -f $run, $passed, $failed, $sw.Elapsed.TotalSeconds)
}
finally {
    if ($null -eq $savedRoot) { Remove-Item Env:SZA_PORTFOLIO_ROOT -ErrorAction SilentlyContinue } else { $env:SZA_PORTFOLIO_ROOT = $savedRoot }
    if (-not $KeepScratch) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
}
if ($failed -gt 0) { exit 1 }
exit 0
