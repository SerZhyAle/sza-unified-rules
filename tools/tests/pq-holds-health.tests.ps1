#requires -Version 7.0
<#
    S0044: the hold, stamp and trust facts of the portfolio operator views - lib/health.ps1 called directly, and
    pq list / pq status end to end over a throwaway portfolio root.

    Cases:
      1. Whole-project hold rows ('<key>', '<key>:*') are held; a ticket row under hold and an active row are not.
      2. The hold flag: false, true (registry), queue (queue file), true+queue (both).
      3. A stale hold line - reason "no ticket queue" while the queue exists - is reported; a hold whose queue is
         still missing, a hold with another reason, a ticket-only hold and an unregistered key are not.
      4. Stamp freshness: an equal digest is current, a different one is stale since the recorded version, a
         missing stamp digest and an unavailable canon digest are unknown - never current.
      5. The canon digest equals the canonDigest check-compliance.ps1 computes over the same rules/.
      6. Trust: the key is the upper-case-drive, forward-slash path; trusted, untrusted, lower-case-drive-only and
         missing entries; an unreadable file is not ok; the check applies only with .claude/settings.json or hooks.
      7. pq list and pq status print hold=queue, hold=true and hold=true+queue (registry and queue at once).
         pq status also prints Frozen: (an enabled project whose own stop file exists) and Disabled:.
      8. The ticket queue path is the profile's paths.releaseQueue when that file exists, else the ledger, else the
         default name; a file under another name is never adopted and the default tree has no paths.queueCandidates.
      9. The wait words: the one 'held' count of the event splits into held and frozen, a disabled project is
         named and replaces 'none', every other count passes through, and the event counts are not touched.

    Touches: a scratch folder under the system temp directory only (removed unless -KeepScratch). Fast tier.
#>
param([switch]$KeepScratch)

$ErrorActionPreference = 'Stop'
$SourceRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$lib = Join-Path $SourceRoot 'tools/harness/portfolio/lib'
. (Join-Path $lib 'queue-file.ps1')
. (Join-Path $lib 'health.ps1')
. (Join-Path $lib 'rank.ps1')
. (Join-Path $lib 'waiting.ps1')
$pq = Join-Path $SourceRoot 'tools/harness/portfolio/pq.ps1'

$scratch = Join-Path ([IO.Path]::GetTempPath()) ("pq-holds-" + [Guid]::NewGuid().ToString('N').Substring(0, 8))
$null = New-Item -ItemType Directory -Path $scratch
$failed = 0

function Assert-That([bool]$Condition, [string]$Reason) { if (-not $Condition) { throw $Reason } }
function Test-Case([string]$Name, [scriptblock]$Body) {
    try { & $Body; Write-Host "PASS $Name" }
    catch { $script:failed++; Write-Host "FAIL $Name - $($_.Exception.Message)" }
}
function Write-Text([string]$Path, [string]$Text) {
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { $null = New-Item -ItemType Directory -Path $dir -Force }
    [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false))
}
function New-Repo([string]$Name, [switch]$Queue) {
    $d = Join-Path $scratch "repos/$Name"
    $null = New-Item -ItemType Directory -Path $d -Force
    if ($Queue) { Write-Text (Join-Path $d (Get-PqDefaultReleaseQueue)) "# queue`n" }
    return $d
}

try {
    $qf = Join-Path $scratch 'PORTFOLIO_QUEUE.md'
    Write-Text $qf ("1`nact`nact2:S0001`n`nhold`nwhole`nstar:*`ntick:S0002`n")

    Test-Case 'whole-project hold rows are held, ticket and active rows are not' {
        $held = @(Get-PqQueueHeldRepos (Read-PqQueueFile -Path $qf))
        Assert-That (($held -join ',') -ceq 'whole,star') "held: $($held -join ',')"
    }

    Test-Case 'the hold flag names who holds' {
        $got = @((Format-PqHoldFlag $false $false), (Format-PqHoldFlag $true $false), (Format-PqHoldFlag $false $true), (Format-PqHoldFlag $true $true)) -join ','
        Assert-That ($got -ceq 'false,true,queue,true+queue') "flags: $got"
    }

    Test-Case 'a no-ticket-queue hold whose queue now exists is stale; the others are not' {
        $reg = [pscustomobject]@{ repos = @(
                [pscustomobject]@{ key = 'fixed'; path = (New-Repo 'fixed' -Queue) },
                [pscustomobject]@{ key = 'still'; path = (New-Repo 'still') },
                [pscustomobject]@{ key = 'other'; path = (New-Repo 'other' -Queue) },
                [pscustomobject]@{ key = 'tick'; path = (New-Repo 'tick' -Queue) }) }
        $f = Join-Path $scratch 'stale.md'
        Write-Text $f ("1`nhold`nfixed  # disabled: no ticket queue`nstill  # disabled: no ticket queue`nother  # owner pause`ntick:S0003  # disabled: no ticket queue`nghost  # disabled: no ticket queue`n")
        $s = @(Get-PqStaleHoldLines -Queue (Read-PqQueueFile -Path $f) -Registry $reg)
        Assert-That ($s.Count -eq 1 -and $s[0].repo -ceq 'fixed' -and $s[0].line -eq 3 -and $s[0].reason -ceq 'disabled: no ticket queue') "stale: $(ConvertTo-Json $s -Compress)"
    }

    Test-Case 'stamp freshness: current, stale, unknown' {
        $canon = @{ ok = $true; digest = 'sha256:aa'; version = '2026.11.15.1'; error = $null }
        $mk = { param($d) [pscustomobject]@{ canon = [pscustomobject]@{ version = '2026.10.17.1'; coreDigest = $d } } }
        $cur = Get-PqStampFreshness -Stamp (& $mk 'sha256:aa') -Canon $canon
        $old = Get-PqStampFreshness -Stamp (& $mk 'sha256:bb') -Canon $canon
        $none = Get-PqStampFreshness -Stamp (& $mk '') -Canon $canon
        $gone = Get-PqStampFreshness -Stamp (& $mk 'sha256:aa') -Canon @{ ok = $false; digest = $null; version = 'unknown'; error = 'no rules/' }
        Assert-That ($cur.state -ceq 'current') "equal: $($cur.state)"
        Assert-That ($old.state -ceq 'stale' -and $old.detail -match '^stale since 2026\.10\.17\.1 ') "differs: $($old.state) $($old.detail)"
        Assert-That ($none.state -ceq 'unknown' -and $gone.state -ceq 'unknown' -and $gone.detail -match 'no rules/') "unknown: $($none.state) $($gone.state) $($gone.detail)"
    }

    Test-Case 'the canon digest equals check-compliance canonDigest' {
        $mine = Get-PqCanonDigestInfo $SourceRoot
        $cc = & pwsh -NoProfile -File (Join-Path $SourceRoot 'tools/check-compliance.ps1') -RepoRoot $SourceRoot -Json 2>$null | Out-String
        $want = ([regex]::Match($cc, '"canonDigest"\s*:\s*"(sha256:[0-9a-f]{64})"')).Groups[1].Value
        Assert-That ($mine.ok -and $want -and $mine.digest -ceq $want) "mine $($mine.digest) vs check-compliance '$want'"
        Assert-That (-not (Get-PqCanonDigestInfo (Join-Path $scratch 'nowhere')).ok) 'a root without rules/ reported a digest'
    }

    Test-Case 'trust: the exact key, trusted and untrusted entries, scope' {
        Assert-That ((ConvertTo-PqTrustKey 'p:\WEB\Some_Repo\') -ceq 'P:/WEB/Some_Repo') "key: $(ConvertTo-PqTrustKey 'p:\WEB\Some_Repo\')"
        $cfg = Join-Path $scratch 'claude.json'
        Write-Text $cfg '{"projects":{"P:/A/yes":{"hasTrustDialogAccepted":true},"P:/A/no":{"hasTrustDialogAccepted":false},"p:/A/low":{"hasTrustDialogAccepted":true},"P:/A/bare":{}}}'
        $t = Read-PqClaudeTrust $cfg
        Assert-That ($t.ok -and $t.projects['P:/A/yes'] -and -not $t.projects['P:/A/no'] -and -not $t.projects['P:/A/bare']) 'trusted/untrusted entries'
        Assert-That (-not $t.projects.ContainsKey('P:/A/low') -and -not $t.projects.ContainsKey('P:/A/missing')) 'a lower-case drive key matched the exact key'
        Write-Text (Join-Path $scratch 'bad.json') '{not json'
        Assert-That (-not (Read-PqClaudeTrust (Join-Path $scratch 'bad.json')).ok -and -not (Read-PqClaudeTrust (Join-Path $scratch 'absent.json')).ok) 'an unreadable or absent file read as ok'
        $s = New-Repo 'withsettings'; Write-Text (Join-Path $s '.claude/settings.json') '{}'
        $h = New-Repo 'withhooks'; $null = New-Item -ItemType Directory -Path (Join-Path $h '.claude/hooks') -Force
        $c = New-Repo 'commandsonly'; $null = New-Item -ItemType Directory -Path (Join-Path $c '.claude/commands') -Force
        Assert-That ((Test-PqTrustNeeded $s) -and (Test-PqTrustNeeded $h) -and -not (Test-PqTrustNeeded $c)) 'trust scope'
    }

    Test-Case 'the ticket queue path is the profile path, else the ledger, else the default - no other name is tried' {
        Assert-That (-not (Get-PqProfileDefaults).paths.Contains('queueCandidates')) 'the default profile tree still declares paths.queueCandidates'
        $bare = New-Repo 'path-bare'
        Write-Text (Join-Path $bare 'tasks/README.md') "# tasks`n"
        Write-Text (Join-Path $bare 'docs/specifications/RELEASE_QUEUE.md') "# a hand file`n"
        $want = [IO.Path]::GetFullPath((Join-Path $bare (Get-PqDefaultReleaseQueue)))
        $got = Get-PqTicketQueuePath ([pscustomobject]@{ key = 'bare'; path = $bare })
        Assert-That ($got -ceq $want -and -not [IO.File]::Exists($got)) "no profile: '$got', expected the missing default '$want'"
        $led = New-Repo 'path-ledger'
        Write-Text (Join-Path $led '.sza-profile.json') '{"paths":{"releaseQueue":"PLAN/PQ_QUEUE.md"}}'
        Write-Text (Join-Path $led 'PLAN/spec-catalog.jsonl') "`n"
        Write-Text (Join-Path $led 'PLAN/RELEASE_QUEUE.md') "# a hand table beside the named file`n"
        $rec = [pscustomobject]@{ key = 'led'; path = $led }
        $got = Get-PqTicketQueuePath $rec
        Assert-That ($got -ceq [IO.Path]::GetFullPath((Join-Path $led 'PLAN/spec-catalog.jsonl'))) "a profile naming a missing file: '$got', expected the ledger"
        Write-Text (Join-Path $led 'PLAN/PQ_QUEUE.md') "# queue`n"
        $got = Get-PqTicketQueuePath $rec
        Assert-That ($got -ceq [IO.Path]::GetFullPath((Join-Path $led 'PLAN/PQ_QUEUE.md'))) "a profile naming an existing file: '$got'"
    }

    Test-Case 'pq list and pq status print hold=queue, hold=true and hold=true+queue' {
        $root = Join-Path $scratch 'portfolio'
        $null = New-Item -ItemType Directory -Path $root -Force
        $repos = @(foreach ($k in 'free', 'qonly', 'ronly', 'both', 'frz', 'off') {
                $d = New-Repo "list-$k"
                if ($k -in 'frz', 'off') { Write-Text (Join-Path $d ([string](Get-PqProfileDefaults).paths['queueStopFile'])) "stop`n" }
                [ordered]@{ key = $k; path = $d; enabled = ($k -cne 'off'); hold = ($k -in 'ronly', 'both') }
            })
        Write-Text (Join-Path $root 'repos.json') (ConvertTo-Json -Depth 8 ([ordered]@{ schemaVersion = '1.0'; repos = $repos }))
        Write-Text (Join-Path $root 'PORTFOLIO_QUEUE.md') ("1`nfree`n`nhold`nqonly  # owner pause`nboth`nfree:S0009`n")
        $saved = $env:SZA_PORTFOLIO_ROOT
        try {
            $env:SZA_PORTFOLIO_ROOT = $root
            $list = (& pwsh -NoProfile -File $pq list 2>&1 | Out-String)
            $status = (& pwsh -NoProfile -File $pq status 2>&1 | Out-String)
        }
        finally { $env:SZA_PORTFOLIO_ROOT = $saved }
        foreach ($want in 'free  enabled=true  hold=false ', 'qonly  enabled=true  hold=queue ', 'ronly  enabled=true  hold=true ', 'both  enabled=true  hold=true+queue ') {
            Assert-That ($list.Contains($want)) "pq list has no '$want': $list"
        }
        Assert-That ($status -match '(?m)^Held: qonly hold=queue, ronly hold=true, both hold=true\+queue\r?$') "pq status: $status"
        Assert-That ($status -match '(?m)^Frozen: frz - ') "pq status has no Frozen line naming frz alone: $status"
        Assert-That ($status -match '(?m)^Disabled: off - ') "pq status has no Disabled line naming off alone: $status"
    }

    Test-Case 'the wait words name held, frozen and disabled' {
        $rank = @{ skipped = @(@{ repo = 'a'; why = 'hold' }, @{ repo = 'b'; why = 'heldByQueue' }, @{ repo = 'c'; why = 'stopped' }, @{ repo = 'd'; why = 'disabled' }, @{ repo = 'e'; why = 'occupied' }) }
        $counts = [ordered]@{ held = 3; occupied = 1; dropped = 2 }
        $w = Get-PqWaitWords -Rank $rank -Why $counts
        $line = (@($w.Keys | ForEach-Object { "$_ $($w[$_])" }) -join ', ')
        Assert-That ($line -ceq 'held 2, frozen 1, occupied 1, dropped 2, disabled 1') "words: $line"
        Assert-That ($counts['held'] -eq 3 -and -not $counts.Contains('frozen') -and -not $counts.Contains('disabled')) 'the event counts were changed'
        $only = Get-PqWaitWords -Rank @{ skipped = @(@{ repo = 'c'; why = 'stopped' }) } -Why ([ordered]@{ held = 1 })
        Assert-That ($only.Count -eq 1 -and $only['frozen'] -eq 1) "a frozen project alone: $(ConvertTo-Json $only -Compress)"
        $off = Get-PqWaitWords -Rank @{ skipped = @(@{ repo = 'd'; why = 'disabled' }) } -Why ([ordered]@{ none = 1 })
        Assert-That ($off.Count -eq 1 -and $off['disabled'] -eq 1) "a disabled project alone: $(ConvertTo-Json $off -Compress)"
        $idle = Get-PqWaitWords -Rank @{ skipped = @() } -Why ([ordered]@{ none = 1 })
        Assert-That ($idle.Count -eq 1 -and $idle['none'] -eq 1) "nothing held back: $(ConvertTo-Json $idle -Compress)"
        Assert-That ((Get-PqSkipWord 'hold') -ceq 'held' -and (Get-PqSkipWord 'heldByQueue') -ceq 'held' -and (Get-PqSkipWord 'stopped') -ceq 'frozen' -and (Get-PqSkipWord 'disabled') -ceq 'disabled' -and (Get-PqSkipWord 'occupied') -ceq 'occupied') 'the skip words'
    }
}
finally {
    if ($KeepScratch) { Write-Host "scratch kept: $scratch" } else { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
}
if ($failed -gt 0) { Write-Host "$failed case(s) failed"; exit 1 }
Write-Host 'all cases passed'
exit 0
