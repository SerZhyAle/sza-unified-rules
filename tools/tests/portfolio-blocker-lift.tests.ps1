<#
  Fast tests for the lift of the root of a blocker chain (TASK-FLOW 0.38 section 16, the amendment of rule 52):
  Get-PqRank -HeadLift in tools/harness/portfolio/lib/rank.ps1 and Get-PqLiftTarget in lib/inbox.ps1.
     1. Without -HeadLift a refused ticket is only passed over (the walk of 0.37): no lift, the next row is the candidate.
     2. With it, the root of the chain is offered in the refused ticket's place: first candidate, rule and source
        'blockerLift', liftedFor naming the refused ticket, and a row of `lifts` with offered = true.
     3. Many tickets behind one root offer it once, and the root's own later row is skipped, not repeated.
     4. Every gate of a row still applies: a project on hold, a root the picker passes over (idle-hold) and a root in a
        status no robot works are not worked, each with its own word, and the picker is not asked about the last.
     5. -StopAfter 1 stays one candidate: the lifted root, not the refused ticket's repository's next head.
     6. A named start lifts nothing; a lift whose root is the refused ticket itself, and a hook that throws, change nothing.
     7. Get-PqLiftTarget: the root of the chain, why 'status' for a status no robot works, $null for a refusal that is not an
        open blocker or a chain that cycles, and one chain walk per blocker through -Memo.
  Stub provider, filter and lift hooks and a stubbed chain walk: no registry, queue file, ledger or repository is read, no
  process is spawned, nothing is written. #>
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$SourceRoot = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent)
$lib = Join-Path $SourceRoot 'tools/harness/portfolio/lib'
foreach ($f in 'paths', 'events', 'delivery', 'registry', 'queue-file', 'health', 'picker', 'rank', 'ledger-watch', 'xrepo', 'inbox') { . (Join-Path $lib "$f.ps1") }
$run = 0; $passed = 0; $failed = 0
function Assert-That([bool]$Condition, [string]$Reason) { if (-not $Condition) { throw $Reason } }
function Test-Case([string]$Name, [scriptblock]$Body) {
    $script:run++
    Write-Host -NoNewline "CASE  $Name ... "
    try { & $Body; $script:passed++; Write-Host 'PASS' -ForegroundColor Green }
    catch { $script:failed++; Write-Host 'FAIL' -ForegroundColor Red; Write-Host "      $($_.Exception.Message)" -ForegroundColor DarkRed }
}

# Four repositories in rank order a, b, c, d; a's rows are blocked by roots that live in b and c.
function New-Registry([hashtable]$Flags = @{}) {
    $repos = foreach ($k in 'a', 'b', 'c', 'd') {
        $r = [ordered]@{ key = $k; path = "C:\none\$k"; enabled = $true; hold = $false; rank = (10 * ([int][char]$k - 96)) }
        if ($Flags.ContainsKey($k)) { foreach ($p in $Flags[$k].Keys) { $r[$p] = $Flags[$k][$p] } }
        [pscustomobject]$r
    }
    return [pscustomobject]@{ repos = @($repos); maxWorkers = 5; fill = 'depth' }
}
function New-Queue([string[]]$Rows) {
    $n = 0
    $list = foreach ($r in $Rows) { $n++; $k, $i = $r -split ':', 2; [pscustomobject]@{ repo = $k; kind = 'ticket'; id = $i; line = $n; package = $null; text = $r } }
    return [pscustomobject]@{ rows = @($list); held = @(); bad = @() }
}
# The provider offers every id except those in $NotOffered (id -> why); it counts the ids it was asked for by force.
$script:Asked = [Collections.Generic.List[string]]::new()
function New-Provider([hashtable]$NotOffered = @{}) {
    # The list goes in through a plain variable: inside a closure `$script:` is the closure's own module scope.
    $asked = $script:Asked
    return {
        param($Repo, $Ids, $ForceId)
        if ($ForceId) {
            $asked.Add("$($Repo.key):$ForceId")
            if ($NotOffered.ContainsKey($ForceId)) { return @{ ok = $true; head = $null; payload = $null; why = [string]$NotOffered[$ForceId] } }
            return @{ ok = $true; head = @{ id = $ForceId; status = 'Draft'; priority = 50; title = "t $ForceId" }; payload = $null; why = $null }
        }
        return @{ ok = $true; head = $null; payload = $null; why = 'none' }
    }.GetNewClosure()
}
# The filter refuses the tickets of $Blocked (repo:id -> blocker pair), in rule 52's refusal shape.
function New-Filter([hashtable]$Blocked) {
    return { param($k, $i) if ($Blocked.ContainsKey("$k`:$i")) { return @{ blocker = [string]$Blocked["$k`:$i"]; state = 'open'; status = 'Draft'; why = "$($Blocked["$k`:$i"]) is open" } } return $null }.GetNewClosure()
}
# The lift hook: blocker pair -> root target (a hashtable with repo, id, status, why).
function New-Lift([hashtable]$Roots, [Collections.Generic.List[string]]$Calls = $null) {
    return { param($k, $i, $refusal) if ($null -ne $Calls) { $Calls.Add("$k`:$i") }; if ($Roots.ContainsKey([string]$refusal.blocker)) { return $Roots[[string]$refusal.blocker] } return $null }.GetNewClosure()
}
$rootB = @{ repo = 'b'; id = 'S9'; status = 'Draft'; why = '' }
$rootC = @{ repo = 'c'; id = 'S7'; status = 'Approved'; why = '' }

Test-Case 'without -HeadLift a refused ticket is only passed over, as in 0.37' {
    $script:Asked.Clear()
    $r = Get-PqRank -Registry (New-Registry) -Queue (New-Queue @('a:S1', 'a:S2')) -HeadProvider (New-Provider) -Slots 1 -StopAfter 1 `
        -HeadFilter (New-Filter @{ 'a:S1' = 'b:S9' })
    Assert-That (@($r.candidates).Count -eq 1 -and $r.candidates[0].id -ceq 'S2') "candidate is $($r.candidates | ForEach-Object { $_.repo + ':' + $_.id })"
    Assert-That (@($r.lifts).Count -eq 0) "lifts has $(@($r.lifts).Count) rows"
    Assert-That (@($r.headRefused).Count -eq 1 -and $r.candidates[0].rule -ceq 'queueFile') 'the refusal or the rule changed'
}

Test-Case 'the root is offered in the refused ticket''s place, with rule, source and the ticket it stands in for' {
    $script:Asked.Clear()
    $r = Get-PqRank -Registry (New-Registry) -Queue (New-Queue @('a:S1', 'a:S2')) -HeadProvider (New-Provider) -Slots 1 -StopAfter 1 `
        -HeadFilter (New-Filter @{ 'a:S1' = 'b:S9' }) -HeadLift (New-Lift @{ 'b:S9' = $rootB })
    $c = $r.candidates[0]
    Assert-That ("$($c.repo):$($c.id)" -ceq 'b:S9') "first candidate is $($c.repo):$($c.id)"
    Assert-That ($c.rule -ceq 'blockerLift' -and $c.source -ceq 'blockerLift') "rule $($c.rule), source $($c.source)"
    Assert-That ($c.liftedFor -ceq 'a:S1') "liftedFor is '$($c.liftedFor)'"
    Assert-That ($r.heads[0].source -ceq 'blockerLift') "rank.result heads source is '$($r.heads[0].source)'"
    $l = $r.lifts[0]
    Assert-That ($l.blocked -ceq 'a:S1' -and $l.root -ceq 'b:S9' -and $l.offered -and $l.blocker -ceq 'b:S9') "lifts row is $($l | ConvertTo-Json -Compress)"
    Assert-That ($script:Asked -contains 'b:S9') 'the root''s picker was not asked for exactly that id'
}

Test-Case 'many tickets behind one root offer it once, and the root''s own later row is skipped' {
    $r = Get-PqRank -Registry (New-Registry) -Queue (New-Queue @('a:S1', 'a:S2', 'b:S9', 'c:S3')) -HeadProvider (New-Provider) -Slots 5 `
        -HeadFilter (New-Filter @{ 'a:S1' = 'b:S9'; 'a:S2' = 'b:S9' }) -HeadLift (New-Lift @{ 'b:S9' = $rootB })
    $ids = @($r.candidates | ForEach-Object { "$($_.repo):$($_.id)" })
    Assert-That (($ids -join ',') -ceq 'b:S9,c:S3') "candidates are $($ids -join ',')"
    Assert-That (@($r.lifts).Count -eq 2 -and @($r.lifts | Where-Object { $_.offered }).Count -eq 2) "lifts: $($r.lifts | ConvertTo-Json -Compress)"
    $plan = @($r.plan | ForEach-Object { "$($_.repo):$($_.id)" })
    Assert-That (($plan -join ',') -ceq 'b:S9,c:S3') "plan is $($plan -join ',')"
    Assert-That ($r.plan[0].rule -ceq 'blockerLift') "plan rule is $($r.plan[0].rule)"
}

Test-Case 'a project on hold, an idle-held root and a root in a status no robot works are each not worked, with their own word' {
    # b is on hold in the registry; c's root is passed over by its picker; d's root is Block* (the hook says why = status).
    $reg = New-Registry @{ b = @{ hold = $true } }
    $script:Asked.Clear()
    $r = Get-PqRank -Registry $reg -Queue (New-Queue @('a:S1', 'a:S2', 'a:S3')) -HeadProvider (New-Provider @{ S7 = 'idle-hold' }) -Slots 1 -StopAfter 3 `
        -HeadFilter (New-Filter @{ 'a:S1' = 'b:S9'; 'a:S2' = 'c:S7'; 'a:S3' = 'd:S5' }) `
        -HeadLift (New-Lift @{ 'b:S9' = $rootB; 'c:S7' = $rootC; 'd:S5' = @{ repo = 'd'; id = 'S5'; status = 'BlockExternal'; why = 'status' } })
    $by = @{}; foreach ($l in $r.lifts) { $by[$l.blocked] = $l }
    Assert-That (-not $by['a:S1'].offered -and $by['a:S1'].why -ceq 'hold') "hold: $($by['a:S1'] | ConvertTo-Json -Compress)"
    Assert-That (-not $by['a:S2'].offered -and $by['a:S2'].why -ceq 'idle-hold') "idle-hold: $($by['a:S2'] | ConvertTo-Json -Compress)"
    Assert-That (-not $by['a:S3'].offered -and $by['a:S3'].why -ceq 'status') "status: $($by['a:S3'] | ConvertTo-Json -Compress)"
    Assert-That (@($r.candidates).Count -eq 0) "candidates: $($r.candidates | ForEach-Object { $_.repo + ':' + $_.id })"
    Assert-That ($script:Asked -contains 'c:S7') 'the idle-held root should have been asked of the picker'
    Assert-That (-not ($script:Asked -contains 'd:S5') -and -not ($script:Asked -contains 'b:S9')) "the picker was asked for a root it must not be asked for: $($script:Asked -join ',')"
}

Test-Case '-StopAfter 1 stays one candidate: the lifted root, not the refused ticket''s repository''s next head' {
    $r = Get-PqRank -Registry (New-Registry) -Queue (New-Queue @('a:S1', 'a:S2', 'b:S4')) -HeadProvider (New-Provider) -Slots 3 -StopAfter 1 `
        -HeadFilter (New-Filter @{ 'a:S1' = 'c:S7' }) -HeadLift (New-Lift @{ 'c:S7' = $rootC })
    Assert-That (@($r.candidates).Count -eq 1) "candidates: $($r.candidates | ForEach-Object { $_.repo + ':' + $_.id })"
    Assert-That ("$($r.candidates[0].repo):$($r.candidates[0].id)" -ceq 'c:S7') 'the first candidate is not the lifted root'
    # When the lifted root is transiently excluded (e.g. noAgent aboveCeiling) while the blocked ticket stays in the walk,
    # the walk passes over the excluded root to the next offerable ticket, and lifts the root again once its exclusion ends.
    $rSkip = Get-PqRank -Registry (New-Registry) -Queue (New-Queue @('a:S1', 'a:S2', 'b:S4')) -HeadProvider (New-Provider) -Exclude @('c:S7') -Slots 1 -StopAfter 1 `
        -HeadFilter (New-Filter @{ 'a:S1' = 'c:S7' }) -HeadLift (New-Lift @{ 'c:S7' = $rootC })
    Assert-That ("$($rSkip.candidates[0].repo):$($rSkip.candidates[0].id)" -ceq 'a:S2') "expected a:S2 when lifted root is excluded, got $($rSkip.candidates[0].repo):$($rSkip.candidates[0].id)"
    Assert-That (-not $rSkip.lifts[0].offered -and $rSkip.lifts[0].why -ceq 'excluded') "expected excluded lift why, got $($rSkip.lifts[0] | ConvertTo-Json -Compress)"
    $rAgain = Get-PqRank -Registry (New-Registry) -Queue (New-Queue @('a:S1', 'a:S2', 'b:S4')) -HeadProvider (New-Provider) -Slots 1 -StopAfter 1 `
        -HeadFilter (New-Filter @{ 'a:S1' = 'c:S7' }) -HeadLift (New-Lift @{ 'c:S7' = $rootC })
    Assert-That ("$($rAgain.candidates[0].repo):$($rAgain.candidates[0].id)" -ceq 'c:S7') 'the root was not lifted again on the next rank'
}

Test-Case 'a named start, a root that is the refused ticket itself, and a throwing hook lift nothing' {
    $calls = [Collections.Generic.List[string]]::new()
    $r = Get-PqRank -Registry (New-Registry) -Queue (New-Queue @('a:S1')) -HeadProvider (New-Provider) -NamedTicket 'a:S1' `
        -HeadFilter (New-Filter @{ 'a:S1' = 'b:S9' }) -HeadLift (New-Lift @{ 'b:S9' = $rootB } $calls)
    Assert-That ($calls.Count -eq 0 -and @($r.lifts).Count -eq 0) "named start called the lift hook $($calls.Count) times"
    $self = @{ repo = 'a'; id = 'S1'; status = 'Draft'; why = '' }
    $r2 = Get-PqRank -Registry (New-Registry) -Queue (New-Queue @('a:S1', 'a:S2')) -HeadProvider (New-Provider) -Slots 1 -StopAfter 1 `
        -HeadFilter (New-Filter @{ 'a:S1' = 'a:S1x' }) -HeadLift (New-Lift @{ 'a:S1x' = $self })
    Assert-That (@($r2.lifts).Count -eq 0 -and $r2.candidates[0].id -ceq 'S2') 'a root equal to the refused ticket was lifted'
    $r3 = Get-PqRank -Registry (New-Registry) -Queue (New-Queue @('a:S1', 'a:S2')) -HeadProvider (New-Provider) -Slots 1 -StopAfter 1 `
        -HeadFilter (New-Filter @{ 'a:S1' = 'b:S9' }) -HeadLift ({ param($k, $i, $x) throw 'boom' })
    Assert-That ($r3.candidates[0].id -ceq 'S2' -and @($r3.lifts).Count -eq 0) 'a throwing hook changed the walk'
}

Test-Case 'Get-PqLiftTarget: the root, why status, no lift for a non-open refusal or a cycle, one walk per blocker' {
    $script:Walks = 0
    $script:ChainState = 'open'
    $script:ChainPair = 'b:S3'
    $script:TicketStatus = 'Draft'
    function Get-PqInboxChainRoot { param($Registry, $ByKey, $Snaps, [string]$RepoKey, [string]$Id) $script:Walks++; return @{ pair = $script:ChainPair; state = $script:ChainState; why = 'x' } }
    function Get-PqXrepoTicket { param($Rec, $Id, $Cache) return @{ status = $script:TicketStatus; file = ''; statusNote = '' } }
    $reg = New-Registry
    $open = @{ blocker = 'b:S2'; state = 'open'; status = 'BlockByOtherTask'; why = 'w' }
    $t = Get-PqLiftTarget -Registry $reg -Refusal $open
    Assert-That ($t.repo -ceq 'b' -and $t.id -ceq 'S3' -and $t.status -ceq 'Draft' -and $t.why -ceq '') "target is $($t | ConvertTo-Json -Compress)"
    $script:TicketStatus = 'BlockExternal'
    $t = Get-PqLiftTarget -Registry $reg -Refusal $open
    Assert-That ($t.why -ceq 'status' -and $t.status -ceq 'BlockExternal') "BlockExternal target is $($t | ConvertTo-Json -Compress)"
    $script:TicketStatus = 'Verified'
    Assert-That ((Get-PqLiftTarget -Registry $reg -Refusal $open).why -ceq 'status') 'Verified is not a status a robot works'
    $script:TicketStatus = 'Approved'
    Assert-That ((Get-PqLiftTarget -Registry $reg -Refusal $open).why -ceq '') 'Approved should be askable'
    foreach ($bad in @('cycle', 'unknownKey', 'unreadable')) {
        Assert-That ($null -eq (Get-PqLiftTarget -Registry $reg -Refusal @{ blocker = 'b:S2'; state = $bad; why = 'w' })) "a '$bad' refusal was lifted"
    }
    $script:ChainState = 'cycle'
    Assert-That ($null -eq (Get-PqLiftTarget -Registry $reg -Refusal $open)) 'a cycling chain was lifted'
    $script:ChainState = 'open'
    $script:Walks = 0
    $memo = @{}
    $null = Get-PqLiftTarget -Registry $reg -Refusal $open -Memo $memo
    $null = Get-PqLiftTarget -Registry $reg -Refusal $open -Memo $memo
    Assert-That ($script:Walks -eq 1) "the chain was walked $($script:Walks) times for one blocker"
}

Write-Host ''
Write-Host "portfolio-blocker-lift: run=$run passed=$passed failed=$failed"
if ($failed -gt 0) { exit 1 }
exit 0
