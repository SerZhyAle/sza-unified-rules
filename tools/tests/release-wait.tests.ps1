#requires -Version 7.0
<#
.SYNOPSIS
    Cases for the release wait of a ticket (TASK-FLOW 0.24, rule 67): a ticket whose audit left only
    release-tier work is not offered again on the same code tree.

.DESCRIPTION
    Fast tier. The library batch/_release-wait.ps1 is loaded against a scratch project with a real git
    repository in it; no runner starts, no child agent runs, and nothing outside the scratch directory
    is written. The wiring into the runner, the picker and the ranker is checked as text, because
    running them needs a whole ledger.

      1. The `**Counts:**` line of the `## Last Audit` block is read in every spelling the audits use
         (bold, bullet, numbered heading) and answers $null for the shapes it cannot read.
      2. Release-only means FAIL 0, WARN 0 and RELEASE >= 1; MANUAL and UNCHECKABLE do not lift it.
      3. The project's own path rules decide which files the stamp leaves out.
      4. The stamp: stable on a clean tree and under writes to PLAN/, changed by an edit, a new file or
         a commit, absent outside a work tree.
      5. The newest journal row alone supplies the recorded stamp.
      6. Test-AwaitsRelease holds only when every condition holds, and ends the moment one fails.
      7. The runner writes the field, the picker names the reason, the ranker counts it.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\harness'))
$lib = Join-Path $root 'batch\_release-wait.ps1'
$idleLib = Join-Path $root 'batch\_idle-runs.ps1'

$run = 0; $passed = 0; $failed = 0
function Assert-That([bool] $Condition, [string] $Message) { if (-not $Condition) { throw $Message } }
function Run-Case([string] $Name, [scriptblock] $Body) {
    $script:run++
    Write-Host -NoNewline "CASE  $Name ... "
    try { & $Body; $script:passed++; Write-Host 'PASS' -ForegroundColor Green }
    catch { $script:failed++; Write-Host 'FAIL' -ForegroundColor Red; Write-Host "      $($_.Exception.Message)" -ForegroundColor DarkRed }
}

$clock = [Diagnostics.Stopwatch]::StartNew()
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('release-wait-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$proj = Join-Path $scratch 'proj'
$plain = Join-Path $scratch 'plain'
New-Item -ItemType Directory -Path (Join-Path $proj 'PLAN'), (Join-Path $proj 'src'), $plain | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)
function Write-File([string] $Path, [string] $Text) { [IO.File]::WriteAllText($Path, $Text, $utf8) }
function Invoke-Git([string[]] $GitArgs) {
    $out = & git -C $proj -c user.name=t -c user.email=t@t.invalid @GitArgs 2>&1
    if ($LASTEXITCODE -ne 0) { throw "git $($GitArgs -join ' ') failed: $out" }
}
function New-Spec([string] $Name, [string] $CountsLine, [string] $Heading = '## Last Audit', [string] $Status = 'Implemented') {
    $path = Join-Path $proj "PLAN\$Name.md"
    $body = "# $Name`n`n**Status:** $Status`n`n## 1. Problem`n`nText.`n`n$Heading`n`n$CountsLine`n`n- PASS x`n"
    Write-File $path $body
    return "PLAN/$Name.md"
}

$release3 = '**Counts:** PASS 8 | WARN 0 | FAIL 0 | MANUAL 0 | UNCHECKABLE 0 | EXEMPT 0 | RELEASE 3'

try {
    # The libraries resolve the project root when they load, so it is set first.
    $env:SZA_PROJECT_ROOT = $proj
    . $idleLib
    . $lib

    Invoke-Git @('init', '-q')
    Write-File (Join-Path $proj 'src\a.cs') "class A {}`n"
    Invoke-Git @('add', '-A')
    Invoke-Git @('commit', '-q', '-m', 'seed')

    Run-Case '1. the Counts line is read bold, as a bullet and under a numbered heading' {
        $c = Get-AuditCounts -SpecPath (New-Spec 's1' $release3)
        Assert-That ($null -ne $c -and $c['RELEASE'] -eq 3 -and $c['FAIL'] -eq 0 -and $c['WARN'] -eq 0 -and $c['PASS'] -eq 8) 'bold line not read'
        $c = Get-AuditCounts -SpecPath (New-Spec 's1b' ('- ' + $release3) '## 6. Last Audit')
        Assert-That ($null -ne $c -and $c['RELEASE'] -eq 3) 'bullet line under a numbered heading not read'
    }

    Run-Case '1. shapes that cannot be read answer $null: no Counts line, a line without RELEASE, a Counts line in another section, no file' {
        Assert-That ($null -eq (Get-AuditCounts -SpecPath (New-Spec 's1c' '- **Verdict:** Implemented - owed to the release.'))) 'a block with no Counts line must be unknown'
        Assert-That ($null -eq (Get-AuditCounts -SpecPath (New-Spec 's1d' '**Counts:** PASS 8 | WARN 0 | FAIL 0'))) 'a line without RELEASE must be unknown'
        Assert-That ($null -eq (Get-AuditCounts -SpecPath (New-Spec 's1e' $release3 '## Notes'))) 'a Counts line outside the audit block must be ignored'
        Assert-That ($null -eq (Get-AuditCounts -SpecPath 'PLAN/absent.md')) 'a missing file must be unknown'
    }

    Run-Case '2. release-only is FAIL 0, WARN 0 and RELEASE >= 1; MANUAL and UNCHECKABLE do not lift it' {
        Assert-That (Test-AuditReleaseOnly -SpecPath (New-Spec 's2a' $release3)) 'FAIL 0 WARN 0 RELEASE 3 is release-only'
        Assert-That (Test-AuditReleaseOnly -SpecPath (New-Spec 's2b' '**Counts:** PASS 9 | WARN 0 | FAIL 0 | MANUAL 2 | UNCHECKABLE 1 | EXEMPT 1 | RELEASE 3')) 'MANUAL and UNCHECKABLE must not lift the hold'
        Assert-That (-not (Test-AuditReleaseOnly -SpecPath (New-Spec 's2c' '**Counts:** PASS 8 | WARN 0 | FAIL 0 | MANUAL 0 | UNCHECKABLE 0 | EXEMPT 0 | RELEASE 0'))) 'RELEASE 0 leaves nothing to wait for'
        Assert-That (-not (Test-AuditReleaseOnly -SpecPath (New-Spec 's2d' '**Counts:** PASS 8 | WARN 1 | FAIL 0 | MANUAL 0 | UNCHECKABLE 0 | EXEMPT 0 | RELEASE 3'))) 'a WARN is a robot''s work'
        Assert-That (-not (Test-AuditReleaseOnly -SpecPath (New-Spec 's2e' '**Counts:** PASS 8 | WARN 0 | FAIL 1 | MANUAL 0 | UNCHECKABLE 0 | EXEMPT 0 | RELEASE 3'))) 'a FAIL is a robot''s work'
        Assert-That (-not (Test-AuditReleaseOnly -SpecPath (New-Spec 's2f' '- no counts here'))) 'unknown is never release-only'
    }

    Run-Case '3. the project''s path rules decide: PLAN/ exempt, src/ not, an unnamed path not, either slash' {
        Assert-That (Test-AgentLockPathExempt -Path 'PLAN/S0001_x.md') 'PLAN/ is exempt by default'
        Assert-That (Test-AgentLockPathExempt -Path 'PLAN\DONE\S0001_x.md') 'a backslash path is read the same'
        Assert-That (-not (Test-AgentLockPathExempt -Path 'src/a.cs')) 'src/ is code'
        Assert-That (-not (Test-AgentLockPathExempt -Path 'unnamed/dir/file.bin')) 'a path no rule names stays in (fail closed)'
    }

    $base = Get-CodeTreeStamp -Refresh
    Run-Case '4. the stamp exists in a work tree, is repeatable, and ignores writes under PLAN/' {
        Assert-That (-not [string]::IsNullOrWhiteSpace($base) -and $base -match '^git1:[0-9a-f]{40}$') "stamp shape: '$base'"
        Assert-That ((Get-CodeTreeStamp -Refresh) -ceq $base) 'a second reading of an untouched tree must be equal'
        Write-File (Join-Path $proj 'PLAN\ticket.md') "bookkeeping`n"
        Assert-That ((Get-CodeTreeStamp -Refresh) -ceq $base) 'a new file under PLAN/ must not move the stamp'
    }

    Run-Case '4. the stamp moves on an edit, on a new file, and on a commit' {
        Write-File (Join-Path $proj 'src\a.cs') "class A { int x; }`n"
        $edited = Get-CodeTreeStamp -Refresh
        Assert-That ($edited -cne $base) 'an edit of a tracked file must move the stamp'
        Write-File (Join-Path $proj 'src\b.cs') "class B {}`n"
        $added = Get-CodeTreeStamp -Refresh
        Assert-That ($added -cne $edited) 'a new untracked file must move the stamp'
        Invoke-Git @('add', '-A')
        Invoke-Git @('commit', '-q', '-m', 'second')
        Assert-That ((Get-CodeTreeStamp -Refresh) -cne $added) 'a commit moves HEAD and must move the stamp'
    }

    Run-Case '4. outside a work tree no stamp is taken' {
        Assert-That ($null -eq (Get-CodeTreeStamp -Root $plain -Refresh)) 'no git work tree must mean no stamp'
    }

    Run-Case '5. the newest journal row alone supplies the recorded stamp' {
        $runs = Join-Path $proj 'temp\spec-queue'
        New-Item -ItemType Directory -Path $runs -Force | Out-Null
        $rows = @(
            '{"id":"T1","statusBefore":"Implemented","statusAfter":"Implemented","moved":false,"outcome":"ok","finishedAt":"2026-11-12T10:00:00","awaitsRelease":"git1:old"}',
            '{"id":"T1","statusBefore":"Implemented","statusAfter":"Implemented","moved":false,"outcome":"ok","finishedAt":"2026-11-12T11:00:00"}',
            '{"id":"T2","statusBefore":"Approved","statusAfter":"Implemented","moved":true,"outcome":"ok","finishedAt":"2026-11-12T10:00:00"}',
            '{"id":"T2","statusBefore":"Implemented","statusAfter":"Implemented","moved":false,"outcome":"ok","finishedAt":"2026-11-12T11:00:00","awaitsRelease":"git1:newest"}'
        )
        [IO.File]::WriteAllLines((Join-Path $runs 'runs-a.jsonl'), $rows, $utf8)
        Assert-That ((Get-IdleRunSeries -Id 'T1' -Refresh).LastAwaitsRelease -ceq '') 'a newer row without the field must read as nothing awaits'
        Assert-That ((Get-IdleRunSeries -Id 'T2' -Refresh).LastAwaitsRelease -ceq 'git1:newest') 'the newest row''s stamp must be read'
        Assert-That ((Get-IdleRunSeries -Id 'NEVER' -Refresh).LastAwaitsRelease -ceq '') 'an unknown ticket reads as nothing awaits'
    }

    Run-Case '6. Get-AwaitsReleaseStamp writes a stamp only for Implemented with a release-only audit' {
        $spec = New-Spec 's6' $release3
        $stamp = Get-AwaitsReleaseStamp -SpecPath $spec -StatusAfter 'Implemented'
        Assert-That ($stamp -ceq (Get-CodeTreeStamp -Refresh)) 'the stamp written must be the tree now'
        Assert-That ((Get-AwaitsReleaseStamp -SpecPath $spec -StatusAfter 'Draft') -ceq '') 'another status writes nothing'
        Assert-That ((Get-AwaitsReleaseStamp -SpecPath (New-Spec 's6b' '- nothing') -StatusAfter 'Implemented') -ceq '') 'an unreadable audit writes nothing'
        Assert-That ((Get-AwaitsReleaseStamp -SpecPath (New-Spec 's6c' '**Counts:** PASS 1 | WARN 0 | FAIL 1 | MANUAL 0 | UNCHECKABLE 0 | EXEMPT 0 | RELEASE 1') -StatusAfter 'Implemented') -ceq '') 'a FAIL writes nothing'
    }

    Run-Case '6. Test-AwaitsRelease holds only while every condition holds' {
        $spec = New-Spec 's6d' $release3
        $stamp = Get-CodeTreeStamp -Refresh
        Assert-That (Test-AwaitsRelease -SpecPath $spec -Status 'Implemented' -RecordedStamp $stamp) 'all four conditions hold: withheld'
        Assert-That (-not (Test-AwaitsRelease -SpecPath $spec -Status 'Verified' -RecordedStamp $stamp)) 'a moved status ends the hold'
        Assert-That (-not (Test-AwaitsRelease -SpecPath $spec -Status 'Implemented' -RecordedStamp '')) 'no recorded stamp: not withheld'
        Assert-That (-not (Test-AwaitsRelease -SpecPath (New-Spec 's6e' '**Counts:** PASS 8 | WARN 1 | FAIL 0 | MANUAL 0 | UNCHECKABLE 0 | EXEMPT 0 | RELEASE 3') -Status 'Implemented' -RecordedStamp $stamp)) 'an audit that now reads WARN ends the hold'
        Write-File (Join-Path $proj 'src\a.cs') "class A { int y; }`n"
        Assert-That (-not (Test-AwaitsRelease -SpecPath $spec -Status 'Implemented' -RecordedStamp $stamp -Refresh)) 'a changed tree ends the hold'
    }

    Run-Case '7. the runner writes the field, the picker names the reason, the ranker counts and words it' {
        $runner = Get-Content -LiteralPath (Join-Path $root 'batch\run-spec-queue.ps1') -Raw
        $pre = Get-Content -LiteralPath (Join-Path $root 'spec_catalog\spec-next-preflight.ps1') -Raw
        $rank = Get-Content -LiteralPath (Join-Path $root 'portfolio\lib\rank.ps1') -Raw
        Assert-That ($runner -match "_release-wait\.ps1'\)") 'the runner does not load the library'
        Assert-That ($runner -match "NotePropertyName 'awaitsRelease'") 'the runner never writes awaitsRelease'
        Assert-That ($runner -match '-AwaitsRelease \$passAwaitsRelease') 'the runner does not pass the stamp to the row'
        Assert-That ($pre -match "batch/_release-wait\.ps1'") 'the picker does not load the library'
        Assert-That ($pre -match "reason = 'awaits-release'") 'the picker does not name the reason'
        Assert-That ($pre -match 'Test-AwaitsRelease') 'the picker never asks'
        Assert-That ($rank -match [regex]::Escape("'awaits-release' { `$excluded.idleHold++ }")) 'the ranker does not count the reason with idle-hold'
        Assert-That ($rank -match [regex]::Escape("'awaits-release' { return")) 'the ranker has no words for the reason'
    }
}
finally {
    Remove-Item Env:\SZA_PROJECT_ROOT -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host ("release-wait: {0} case(s), {1} passed, {2} failed, {3} s" -f $run, $passed, $failed, [math]::Round($clock.Elapsed.TotalSeconds, 1))
if ($failed -gt 0) { exit 1 }
exit 0
