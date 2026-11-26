#requires -Version 7.0
# Tests for canon ticket S0139 (TASK-FLOW 0.32): the grade 0-9 of the `**Complexity:**` line, the agent routes and
# the ceiling, the registry checks of routes/raters/escalateBy, the rater's answer and its run, the header rewrite,
# and the escalation. Fast: no model is called - the rater runs are `cmd /c` stubs. Touches only a throwaway folder
# under the system temp directory (SZA_PORTFOLIO_ROOT points there while it runs).
#
# Cases:
#   1  parser: grades, pinned, words, Russian words, refusals
#   2  capture regex of capture-draft.ps1 and spec-draft.ps1 accepts a grade and refuses 10
#   3  routes: the row for a grade, the ceiling, no routes
#   4  Select-PqAgent: aboveCeiling, the order among the capable, the launch model and effort, claude arguments
#   5  registry: routes, raters and escalateBy problems; a clean registry stays clean
#   6  rater answer: valid, low confidence, invalid, out of range, empty
#   7  rater run: a stub answers, a stub times out, a missing command
#   8  header rewrite: replace (CRLF + BOM kept), insert, pinned untouched
#   9  escalation: raised on a failure, not on a word, a pinned line or a success; capped at 9
#  10  parallel (S0140): the spec flag, the route key on a build pass only, registry refusals, the runner's opt-in
#  11  settings write (S0141): pq agents -Apply's Set-PqAgentSettings - merge, unknown keys kept, refusal writes
#      nothing, empty removes, read back; the GUI dialog still calls -Settings and -Apply
#  12  one rating per ticket: a graded line is not asked about, a worker that waited asks nothing, a free one writes
#
# Canon ticket CANONR-0194 added to 1 the strict grade form, to 4 the audit pass that names no route, to 6 braces
# inside the answer's strings, to 7 an exit with no answer and a CLI that never reads its input, to 8 kept line ends
# and refused bytes, to 9 the neutral ends, the unmoved spelling and a grade the pass rewrote, to 10 the system prompt.
$ErrorActionPreference = 'Stop'
$harness = Join-Path (Split-Path $PSScriptRoot -Parent) 'harness'
$pqLib = Join-Path $harness 'portfolio/lib'
. (Join-Path $pqLib 'paths.ps1')
. (Join-Path $pqLib 'events.ps1')
. (Join-Path $pqLib 'registry.ps1')
. (Join-Path $pqLib 'loop.ps1')
. (Join-Path $pqLib 'ledger-watch.ps1')
. (Join-Path $pqLib 'agents.ps1')

$scratch = Join-Path ([IO.Path]::GetTempPath()) ('cx-grade-' + [guid]::NewGuid().ToString('N'))
$null = [IO.Directory]::CreateDirectory($scratch)
$origEnv = $env:SZA_PORTFOLIO_ROOT
$env:SZA_PORTFOLIO_ROOT = $scratch
$failed = 0
function Test-Case([string]$Name, [scriptblock]$Body) {
    try { & $Body; Write-Host "PASS $Name" -ForegroundColor Green }
    catch { $script:failed++; Write-Host "FAIL $Name - $($_.Exception.Message)" -ForegroundColor Red }
}
function Assert-Eq($Actual, $Expected, [string]$What) {
    if ("$Actual" -cne "$Expected") { throw "$What - expected '$Expected', got '$Actual'" }
}

try {
    Test-Case '1 parser' {
        $r = ConvertFrom-SzaComplexityValue '7 pinned - the owner'
        Assert-Eq "$($r.level)/$($r.score)/$($r.pinned)/$($r.numeric)/$($r.reason)" 'hard/7/True/True/the owner' '7 pinned'
        Assert-Eq (ConvertFrom-SzaComplexityValue '3 - x').level 'light' '3'
        Assert-Eq (ConvertFrom-SzaComplexityValue '4 - x').level 'medium' '4'
        Assert-Eq (ConvertFrom-SzaComplexityValue '6').level 'medium' '6'
        Assert-Eq (ConvertFrom-SzaComplexityValue '0 - typo').score 0 '0'
        Assert-Eq (ConvertFrom-SzaComplexityValue 'hard - x').score 8 'hard'
        Assert-Eq (ConvertFrom-SzaComplexityValue 'Light').score 1 'Light'
        Assert-Eq (ConvertFrom-SzaComplexityValue 'medium - not assessed at capture').score 5 'capture default'
        Assert-Eq (ConvertFrom-SzaComplexityValue ([regex]::Unescape('сложный'))).level 'hard' 'Russian hard'
        foreach ($bad in @('10 - x', '7.5 - x', 'Complex (spec)', '', 'lightweight', '5x - a', '7-9 - range', '3 files change', '0/10', '5pinned - o', '5 (medium) - x', '4 pinned: x')) {
            if ((ConvertFrom-SzaComplexityValue $bad).recognised) { throw "'$bad' was recognised" }
        }
        Assert-Eq "$((ConvertFrom-SzaComplexityValue '5 pinned').pinned)/$((ConvertFrom-SzaComplexityValue '5 -').score)/$((ConvertFrom-SzaComplexityValue '6 - a - b').reason)" 'True/5/a - b' 'bare forms'
        Assert-Eq (Format-SzaComplexityLine -Score 4 -Reason "a`nb" -Pinned) '**Complexity:** 4 pinned - a b' 'format'
    }

    Test-Case '1a Windows PowerShell 5.1 loads the ASCII reader and parses Russian words' {
        $readerPath = Join-Path $harness 'spec_catalog/lib/complexity-grade.ps1'
        $readerBytes = [IO.File]::ReadAllBytes($readerPath)
        if ($readerBytes | Where-Object { $_ -gt 127 }) { throw 'the reader source contains non-ASCII bytes' }
        if ($readerBytes.Length -ge 3 -and $readerBytes[0] -eq 0xEF -and $readerBytes[1] -eq 0xBB -and $readerBytes[2] -eq 0xBF) {
            throw 'the reader unexpectedly has a UTF-8 BOM'
        }

        $legacyHost = Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
        if (-not (Test-Path -LiteralPath $legacyHost)) { throw "Windows PowerShell 5.1 was not found at $legacyHost" }
        $probePath = Join-Path $scratch 'complexity-reader-ps51.ps1'
        $quotedReader = $readerPath.Replace("'", "''")
        $probe = @"
`$ErrorActionPreference = 'Stop'
. '$quotedReader'
`$cases = @(
    @{ Value = ([char[]](0x043B,0x0451,0x0433,0x043A,0x0438,0x0439) -join ''); Level = 'light' },
    @{ Value = ([char[]](0x0441,0x0440,0x0435,0x0434,0x043D,0x0438,0x0439) -join ''); Level = 'medium' },
    @{ Value = ([char[]](0x0441,0x043B,0x043E,0x0436,0x043D,0x044B,0x0439) -join ''); Level = 'hard' }
)
foreach (`$case in `$cases) {
    `$result = ConvertFrom-SzaComplexityValue `$case.Value
    if (-not `$result.recognised -or `$result.level -cne `$case.Level) { throw "Expected `$(`$case.Level), got `$(`$result.level)" }
}
Write-Output 'PS51 complexity reader: PASS'
"@
        [IO.File]::WriteAllText($probePath, $probe, [Text.Encoding]::ASCII)
        $output = @(& $legacyHost -NoProfile -File $probePath 2>&1)
        $exitCode = $LASTEXITCODE
        if ($exitCode -ne 0 -or $output -notcontains 'PS51 complexity reader: PASS') {
            throw "Windows PowerShell 5.1 probe exited ${exitCode}: $($output -join ' | ')"
        }
    }

    Test-Case '2 capture regex' {
        foreach ($f in @('spec_catalog/capture-draft.ps1', 'portfolio/spec-draft.ps1')) {
            $src = [IO.File]::ReadAllText((Join-Path $harness $f))
            if ($src -notmatch [regex]::Escape("'^\s*(light|medium|hard|[0-9](?:\s+pinned)?)\s+-\s+(\S.*?)\s*$'")) { throw "$f does not carry the grade regex" }
        }
        $rx = '^\s*(light|medium|hard|[0-9](?:\s+pinned)?)\s+-\s+(\S.*?)\s*$'
        foreach ($ok in @('7 - x', '7 pinned - x', 'hard - x')) { if ($ok -notmatch $rx) { throw "refused '$ok'" } }
        foreach ($no in @('10 - x', '7', 'x - y')) { if ($no -match $rx) { throw "accepted '$no'" } }
    }

    $zai = [pscustomobject]@{ name = 'zai'; command = 'claude'; model = 'glm'; effort = 'default'; maxParallel = 2; routes = @([pscustomobject]@{ max = 4 }) }
    $codex = [pscustomobject]@{ name = 'codex'; command = 'codex'; model = 'terra'; effort = 'xhigh'; maxParallel = 2; routes = @([pscustomobject]@{ max = 3; effort = 'medium' }, [pscustomobject]@{ max = 6 }) }
    $claude = [pscustomobject]@{ name = 'claude'; command = 'claude'; maxParallel = 5; modelByComplexity = [pscustomobject]@{ light = 'haiku'; medium = 'sonnet'; hard = 'opus' }
        routes = @([pscustomobject]@{ max = 2; model = 'haiku' }, [pscustomobject]@{ max = 5; model = 'sonnet'; effort = 'high' }, [pscustomobject]@{ max = 9; model = 'opus' }) }
    $plain = [pscustomobject]@{ name = 'gemini'; command = 'agy'; model = 'hydrogen'; effort = 'default'; maxParallel = 2 }
    $reg = [pscustomobject]@{ agents = @($zai, $codex, $claude, $plain); agentOrder = @('zai', 'codex', 'claude') }

    Test-Case '3 routes' {
        Assert-Eq (Get-PqAgentRoute $zai 4).ok $true 'zai 4'
        Assert-Eq (Get-PqAgentRoute $zai 5).ok $false 'zai 5'
        Assert-Eq (Get-PqAgentRoute $codex 2).effort 'medium' 'codex 2 effort'
        Assert-Eq (Get-PqAgentRoute $codex 5).max 6 'codex 5 row'
        Assert-Eq (Get-PqAgentRoute $plain 9).ok $true 'no routes takes 9'
        Assert-Eq (Get-PqAgentCeiling $codex) 6 'codex ceiling'
        Assert-Eq (Get-PqAgentCeiling $plain) 9 'plain ceiling'
        Assert-Eq (Get-PqSelectScore -1 'hard') 8 'word score'
        Assert-Eq (Get-PqSelectScore -1 '') 5 'no declaration'
    }

    Test-Case '4 Select-PqAgent' {
        $p = Select-PqAgent -Registry $reg -RepoPath $scratch -Level 'light' -Score 2
        Assert-Eq $p.agent 'zai' 'grade 2'
        $p = Select-PqAgent -Registry $reg -RepoPath $scratch -Level 'medium' -Score 5
        Assert-Eq $p.agent 'codex' 'grade 5'
        Assert-Eq (@($p.fallbacks | Where-Object { $_.why -ceq 'aboveCeiling' }).from -join ',') 'zai' 'aboveCeiling'
        $l = Get-PqPickLaunch $p
        Assert-Eq "$($l.model)/$($l.effort)" 'terra/xhigh' 'codex row 2 keeps the record'
        $a = Get-PqAgentPassArgs $p
        Assert-Eq $a[$a.IndexOf('-Model') + 1] 'terra' 'codex -Model'
        $p = Select-PqAgent -Registry $reg -RepoPath $scratch -Level 'light' -Score 3
        Assert-Eq $p.agent 'zai' 'grade 3 stays on zai'
        $p = Select-PqAgent -Registry $reg -RepoPath $scratch -Level 'hard' -Score 8
        Assert-Eq $p.agent 'claude' 'grade 8'
        $ca = @(Get-PqClaudePassArgs $p)
        Assert-Eq ($ca -join ' ') '-ModelPolicy fixed -Model opus' 'claude opus args'
        Assert-Eq (Get-PqPickModel $p) 'opus' 'pick model'
        Assert-Eq (@(Get-PqClaudePassArgs $p 'Implemented').Count) 0 'an Implemented audit keeps the shape cap'
        foreach ($audit in @('Implemented', 'BlockNeedUserTest')) {
            Assert-Eq "$(Get-PqPickModel $p $audit)/$((Get-PqPickLaunch $p $audit).effort)" '/' "the log of an $audit pass names no route"
        }
        Assert-Eq (Get-PqPickModel $p 'Approved') 'opus' 'a build pass names its route'
        $audited = @{ agent = 'codex'; record = $codex; route = (Get-PqAgentRoute $codex 2) }
        Assert-Eq (Get-PqPickLaunch $audited 'Implemented').effort 'medium' 'the exception is claude alone'
        $loopSrc = [IO.File]::ReadAllText((Join-Path $pqLib 'loop.ps1'))
        foreach ($need in @('Get-PqPickModel $pick ([string]$cand.status)', 'Get-PqPickLaunch $pick ([string]$cand.status)')) {
            if (-not $loopSrc.Contains($need)) { throw "loop.ps1 lost '$need'" }
        }
        $reg2 = [pscustomobject]@{ agents = @($zai, $codex, $claude); agentOrder = @('claude') }
        $p = Select-PqAgent -Registry $reg2 -RepoPath $scratch -Level 'medium' -Score 4
        $ca = @(Get-PqClaudePassArgs $p)
        if ($ca[0] -cne '-AgentJson' -or $ca[1] -notmatch '"effort":"high"' -or ($ca -join ' ') -notmatch '-Model sonnet') { throw "claude sonnet/high args: $($ca -join ' ')" }
        $reg3 = [pscustomobject]@{ agents = @($zai); agentOrder = @('zai') }
        $p = Select-PqAgent -Registry $reg3 -RepoPath $scratch -Level 'hard' -Score 9
        if ($null -ne $p.agent) { throw 'grade 9 ran below its ceiling' }
        $holdRes = Get-PqNoAgentHold -Pick $p -Registry $reg3
        Assert-Eq $holdRes.passOver $true 'zai is free for <= 4, so grade 9 is passed over'
        $untilIso = [DateTimeOffset]::UtcNow.AddMinutes(20).ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
        Set-PqAgentHold -Name 'claude' -Source 'runner' -Detector 'regex' -Until $untilIso
        try {
            $reg4 = [pscustomobject]@{ agents = @($zai, $claude); agentOrder = @('claude', 'zai') }
            $p4 = Select-PqAgent -Registry $reg4 -RepoPath $scratch -Level 'hard' -Score 8
            Assert-Eq $p4.agent $null 'claude on limit and zai ceiling 4 leaves grade 8 with no agent'
            $h4 = Get-PqNoAgentHold -Pick $p4 -Registry $reg4
            Assert-Eq $h4.passOver $true 'free zai passes grade 8 over so lower-grade tickets can run'
            Set-PqAgentHold -Name 'zai' -Source 'runner' -Detector 'regex' -Until $untilIso
            $pAll = Select-PqAgent -Registry $reg4 -RepoPath $scratch -Level 'hard' -Score 8
            $hAll = Get-PqNoAgentHold -Pick $pAll -Registry $reg4
            Assert-Eq $hAll.passOver $false 'when every provider is on limit, the worker waits in place'
        }
        finally {
            $null = Remove-PqAgentHold 'claude'
            $null = Remove-PqAgentHold 'zai'
        }
        $noRoutes = [pscustomobject]@{ name = 'claude'; command = 'claude'; maxParallel = 5 }
        $p = Select-PqAgent -Registry ([pscustomobject]@{ agents = @($noRoutes); agentOrder = @('claude') }) -RepoPath $scratch -Level 'hard'
        Assert-Eq (@(Get-PqClaudePassArgs $p).Count) 0 'claude without routes launches as before'
    }

    Test-Case '5 registry' {
        $base = [ordered]@{ agents = @($zai, $codex, $claude); agentOrder = @('zai', 'codex', 'claude'); repos = @() }
        $clean = Test-PqRegistry -Registry ([pscustomobject]$base)
        $codes = @($clean.errors | ForEach-Object { ($_ | ConvertTo-Json -Compress) }) -join ' '
        if ($codes -match 'Routes|Raters|EscalateBy') { throw "clean registry reports $codes" }
        $badAgent = [pscustomobject]@{ name = 'zai'; command = 'claude'; model = 'glm'; effort = 'default'; routes = @([pscustomobject]@{ max = 5 }, [pscustomobject]@{ max = 5 }, [pscustomobject]@{ max = 12; model = '' }) }
        $bad = [ordered]@{ agents = @($badAgent); agentOrder = @('zai'); repos = @(); escalateBy = 11
            raters = @([pscustomobject]@{ name = 'Bad Name'; command = ''; model = 'm' }, [pscustomobject]@{ name = 'h'; command = 'claude'; model = 'm'; timeoutSeconds = 5 }) }
        $res = Test-PqRegistry -Registry ([pscustomobject]$bad)
        $all = @($res.errors | ForEach-Object { ($_ | ConvertTo-Json -Compress) }) -join ' '
        foreach ($need in @('AgentRoutesInvalid', 'RatersInvalid', 'EscalateByRange')) { if ($all -notmatch $need) { throw "missing $need in $all" } }
        if (([regex]::Matches($all, 'AgentRoutesInvalid')).Count -lt 3) { throw "expected 3 route problems: $all" }
    }

    Test-Case '10 parallel (S0140)' {
        $f = Get-SzaParallelFlag @('# T', '**Complexity:** 8 - x', '**Parallel:** yes - three independent parsers')
        Assert-Eq "$($f.flagged)/$($f.reason)" 'True/three independent parsers' 'flag line'
        Assert-Eq (Get-SzaParallelFlag @('**Parallel:** no - one file')).flagged $false 'no'
        Assert-Eq (Get-SzaParallelFlag @('**Parallel:**')).flagged $false 'empty'
        Assert-Eq (Get-SzaParallelFlag @('# T', 'text')).flagged $false 'absent'
        $cp = [pscustomobject]@{ name = 'claude'; command = 'claude'; maxParallel = 5
            routes = @([pscustomobject]@{ max = 5; model = 'sonnet' }, [pscustomobject]@{ max = 9; model = 'opus'; parallel = 'ultracode' }) }
        $rp = [pscustomobject]@{ agents = @($cp); agentOrder = @('claude') }
        $p = Select-PqAgent -Registry $rp -RepoPath $scratch -Level 'hard' -Score 8
        Assert-Eq (@(Get-PqClaudePassArgs $p 'Approved' $true) -join ' ') '-Parallel ultracode -ModelPolicy fixed -Model opus' 'flagged build pass'
        Assert-Eq (@(Get-PqClaudePassArgs $p 'Approved' $false) -join ' ') '-ModelPolicy fixed -Model opus' 'unflagged'
        Assert-Eq (@(Get-PqClaudePassArgs $p 'Implemented' $true).Count) 0 'an audit stays single and shape'
        Assert-Eq (Get-PqClaudeParallel $p 'Draft' $true) '' 'a spec pass stays single'
        Assert-Eq (Get-PqClaudeParallel $p 'In Progress' $true) 'ultracode' 'In Progress'
        $p = Select-PqAgent -Registry $rp -RepoPath $scratch -Level 'medium' -Score 4
        Assert-Eq (Get-PqClaudeParallel $p 'Approved' $true) '' 'a row without the key'
        $bare = [pscustomobject]@{ name = 'claude'; command = 'claude'; maxParallel = 5; routes = @([pscustomobject]@{ max = 9; parallel = 'ultracode' }) }
        $p = Select-PqAgent -Registry ([pscustomobject]@{ agents = @($bare); agentOrder = @('claude') }) -RepoPath $scratch -Level 'hard' -Score 7
        Assert-Eq (@(Get-PqClaudePassArgs $p 'Tactical' $true) -join ' ') '-ModelPolicy shape -Parallel ultracode' 'parallel only, shape kept'
        Assert-Eq (@(Get-PqClaudePassArgs $p 'Tactical' $false).Count) 0 'unflagged bare row launches as before'
        $clean = Test-PqRegistry -Registry ([pscustomobject][ordered]@{ agents = @($cp); agentOrder = @('claude'); repos = @() })
        if ((@($clean.errors | ForEach-Object { $_ | ConvertTo-Json -Compress }) -join ' ') -match 'AgentRoutesInvalid') { throw 'a valid parallel row was refused' }
        $zp = [pscustomobject]@{ name = 'zai'; command = 'claude'; model = 'glm'; effort = 'default'; routes = @([pscustomobject]@{ max = 4; parallel = 'ultracode' }) }
        $cy = [pscustomobject]@{ name = 'claude'; command = 'claude'; routes = @([pscustomobject]@{ max = 9; parallel = 'yes' }) }
        $res = Test-PqRegistry -Registry ([pscustomobject][ordered]@{ agents = @($zp, $cy); agentOrder = @('zai', 'claude'); repos = @() })
        $all = @($res.errors | ForEach-Object { $_ | ConvertTo-Json -Compress }) -join ' '
        if (([regex]::Matches($all, 'AgentRoutesInvalid')).Count -ne 2) { throw "expected 2 parallel problems: $all" }
        # The runner carries the opt-in in the system prompt, never in the prompt (proof run, S0140 section 3.5).
        $runner = Join-Path $harness 'batch/run-spec-queue.ps1'
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($runner, [ref]$null, [ref]$null)
        $fn = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq 'Get-ParallelOptIn' }, $true) | Select-Object -First 1
        if ($null -eq $fn) { throw 'run-spec-queue.ps1 has no Get-ParallelOptIn' }
        . ([scriptblock]::Create($fn.Extent.Text))
        if ((Get-ParallelOptIn 'ultracode') -notmatch '^ultracode - .*Workflow tool') { throw 'the opt-in text lost its keyword or the tool name' }
        $fn = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq 'Add-ChildSystemPrompt' }, $true) | Select-Object -First 1
        if ($null -eq $fn) { throw 'run-spec-queue.ps1 has no Add-ChildSystemPrompt' }
        . ([scriptblock]::Create($fn.Extent.Text))
        Assert-Eq (@(Add-ChildSystemPrompt -ChildArgs @('-p', '/spec-all S1') -Lead 'L' -Tail 'T') -join '|') '-p|/spec-all S1|--append-system-prompt|L T' 'added, the prompt untouched'
        Assert-Eq (@(Add-ChildSystemPrompt -ChildArgs @('--append-system-prompt', 'house', '-p', 'x') -Lead 'L' -Tail 'T') -join '|') '--append-system-prompt|L house T|-p|x' 'merged with the template'
        Assert-Eq (@(Add-ChildSystemPrompt -ChildArgs @('--append-system-prompt=house') -Lead 'L') -join '|') '--append-system-prompt=L house' 'merged with the = form'
        Assert-Eq (@(Add-ChildSystemPrompt -ChildArgs @('-p', 'x')) -join '|') '-p|x' 'nothing to add'
        $src = [IO.File]::ReadAllText($runner)
        if (-not $src.Contains('Add-ChildSystemPrompt -ChildArgs $childArgs -Lead $optIn -Tail $gradeAsk')) { throw 'the runner does not append the opt-in' }
        if ($src -match '\$prompt \+=') { throw 'the runner still adds words after the prompt' }
    }

    Test-Case '11 settings write (S0141)' {
        $regFile = Join-Path $scratch 'settings-repos.json'
        $seed = [ordered]@{ schemaVersion = '1.0'; repos = @(); agentOrder = @('zai', 'claude')
            agents = @(
                [ordered]@{ name = 'zai'; command = 'claude'; model = 'glm'; effort = 'default'; maxParallel = 2; env = [ordered]@{ X = '%Y%' }; routes = @([ordered]@{ max = 4; note = 'kept' }) },
                [ordered]@{ name = 'claude'; command = 'claude'; maxParallel = 5; modelByComplexity = [ordered]@{ light = 'haiku'; medium = 'sonnet'; hard = 'opus' } })
            raters = @([ordered]@{ name = 'haiku'; command = 'claude'; model = 'm1'; argsTemplate = @('-p', '--model', '{model}') }) }
        [IO.File]::WriteAllText($regFile, (ConvertTo-Json -InputObject $seed -Depth 12))
        $pre = Test-PqRegistry -Registry ([IO.File]::ReadAllText($regFile) | ConvertFrom-Json)
        if (-not $pre.ok) { throw "seed registry invalid: $((@($pre.errors) | ForEach-Object { $_.name + ' ' + $_.message }) -join '; ')" }
        $edit = '{"routes":{"zai":[{"max":"4","model":""},{"max":6}],"claude":[{"max":5,"model":"sonnet"},{"max":9,"model":"opus","parallel":"ultracode"}]},"raters":[{"name":"haiku","command":"claude","model":"m2","timeoutSeconds":"90"}],"escalateBy":3}' | ConvertFrom-Json
        $r = Set-PqAgentSettings -Settings $edit -RegistryPath $regFile
        if (-not $r.ok -or -not $r.changed) { throw "apply: $($r.error) $($r.message)" }
        $doc = [IO.File]::ReadAllText($regFile) | ConvertFrom-Json
        $z = $doc.agents | Where-Object name -eq 'zai'
        Assert-Eq "$(@($z.routes).Count)/$($z.routes[0].max)/$($z.routes[0].note)/$($z.env.X)" '2/4/kept/%Y%' 'zai rows, unknown keys kept'
        $c = $doc.agents | Where-Object name -eq 'claude'
        Assert-Eq $c.routes[1].parallel 'ultracode' 'claude parallel row'
        Assert-Eq "$($doc.raters[0].model)/$($doc.raters[0].timeoutSeconds)/$($doc.raters[0].argsTemplate -join ' ')" 'm2/90/-p --model {model}' 'rater merged by name'
        Assert-Eq $doc.escalateBy 3 'escalateBy'
        Assert-Eq (Set-PqAgentSettings -Settings $edit -RegistryPath $regFile).changed $false 'same settings, no write'
        $hash = Get-PqRegistryHash -Path $regFile
        $bad = '{"routes":{"zai":[{"max":6},{"max":5}]}}' | ConvertFrom-Json
        $r = Set-PqAgentSettings -Settings $bad -RegistryPath $regFile
        if ($r.ok -or $r.error -cne 'AgentRoutesInvalid') { throw "a falling max was accepted: $($r.error)" }
        Assert-Eq (Get-PqRegistryHash -Path $regFile) $hash 'a refused edit writes nothing'
        Assert-Eq (Set-PqAgentSettings -Settings ('{"routes":{"nobody":[]}}' | ConvertFrom-Json) -RegistryPath $regFile).error 'UnknownAgent' 'unknown agent'
        $r = Set-PqAgentSettings -Settings ('{"routes":{"claude":[]},"raters":[],"escalateBy":null}' | ConvertFrom-Json) -RegistryPath $regFile
        if (-not $r.ok) { throw "remove: $($r.message)" }
        $doc = [IO.File]::ReadAllText($regFile) | ConvertFrom-Json
        $c = $doc.agents | Where-Object name -eq 'claude'
        Assert-Eq "$(Test-PqHasKey $c 'routes')/$(Test-PqHasKey $doc 'raters')/$(Test-PqHasKey $doc 'escalateBy')" 'False/False/False' 'empty removes the keys'
        $s = Get-PqAgentSettings -Registry $doc
        Assert-Eq "$($s.escalateBy)/$($s.escalateBySet)/$(@($s.agents).Count)/$(($s.agents | Where-Object name -eq 'zai').ceiling)" '2/False/2/6' 'settings read back'
        # The PQShell dialog calls these two verbs; keep them in pq.ps1.
        $pq = [IO.File]::ReadAllText((Join-Path $harness 'portfolio/pq.ps1'))
        foreach ($need in @('[switch]$Settings', '[string]$Apply', 'Set-PqAgentSettings -Settings $edit -Log')) { if (-not $pq.Contains($need)) { throw "pq.ps1 lost '$need'" } }
        $gui = [IO.File]::ReadAllText((Join-Path $harness 'portfolio/gui/src/FormProviderRoutes.vb'))
        foreach ($need in @('"-Settings", "-Json"', '"-Apply"')) { if (-not $gui.Contains($need)) { throw "FormProviderRoutes.vb lost $need" } }
    }

    Test-Case '6 rater answer' {
        $a = ConvertFrom-PqRaterAnswer "thinking..`n{`"score`": 6, `"reason`": `"two layers`", `"confidence`": `"high`"}"
        Assert-Eq "$($a.ok)/$($a.score)/$($a.confidence)/$($a.reason)" 'True/6/high/two layers' 'valid'
        Assert-Eq (ConvertFrom-PqRaterAnswer '{"score": 3, "reason": "x", "confidence": "low"}').score 4 'low +1'
        Assert-Eq (ConvertFrom-PqRaterAnswer '{"score": 9, "reason": "x", "confidence": "low"}').score 9 'cap 9'
        Assert-Eq (ConvertFrom-PqRaterAnswer '{"score": 1} then {"score": 7, "reason": "last wins"}').score 7 'last object'
        Assert-Eq (ConvertFrom-PqRaterAnswer '{"score": 12, "reason": "x"}').why 'invalid' 'range'
        Assert-Eq (ConvertFrom-PqRaterAnswer '{"score": 4, "confidence": "sure"}').why 'invalid' 'confidence'
        Assert-Eq (ConvertFrom-PqRaterAnswer 'no json here').why 'invalid' 'no json'
        Assert-Eq (ConvertFrom-PqRaterAnswer '').why 'noAnswer' 'empty'
        Assert-Eq (ConvertFrom-PqRaterAnswer '{"score":7,"reason":"touches the {id} template","confidence":"high"}').score 7 'brace in the reason'
        Assert-Eq (ConvertFrom-PqRaterAnswer '{"score":2,"reason":"draft"} then {"score":7,"reason":"fix {x}"}').score 7 'last object with a brace'
        Assert-Eq (ConvertFrom-PqRaterAnswer '{"score":5,"reason":"a \"}\" mark"} and a { stray').score 5 'escaped quote and stray brace'
        Assert-Eq (ConvertFrom-PqRaterAnswer '{"score":6,"detail":{"score":1}}').score 6 'the outer object'
        Assert-Eq (ConvertFrom-PqRaterAnswer '{"result":{"score":3}}').score 3 'a wrapped object'
    }

    Test-Case '7 rater run' {
        $ans = Join-Path $scratch 'answer.txt'
        [IO.File]::WriteAllText($ans, '{"score": 2, "reason": "one file", "confidence": "high"}')
        $ok = Invoke-PqRaterRecord -Rater ([pscustomobject]@{ name = 'stub'; command = 'cmd'; model = 'm'; argsTemplate = @('/c', 'type', $ans) }) -Prompt 'ignored'
        if (-not $ok.ok -or (ConvertFrom-PqRaterAnswer $ok.text).score -ne 2) { throw "stub answer: $($ok.why) [$($ok.text)]" }
        $sw = [Diagnostics.Stopwatch]::StartNew()
        # ping never reads its input, and the prompt is far larger than a pipe buffer: the write itself must time out.
        $slow = Invoke-PqRaterRecord -Rater ([pscustomobject]@{ name = 'slow'; command = 'cmd'; model = 'm'; timeoutSeconds = 1; argsTemplate = @('/c', 'ping', '-n', '5', '127.0.0.1') }) -Prompt ('x' * 300000)
        Assert-Eq $slow.why 'timeout' 'timeout'
        Assert-Eq (Invoke-PqRaterRecord -Rater ([pscustomobject]@{ name = 'out'; command = 'cmd'; model = 'm'; argsTemplate = @('/c', 'exit', '1') }) -Prompt '').why 'noAnswer' 'a non-zero exit with no answer'
        if ($sw.Elapsed.TotalSeconds -gt 3) { throw "timeout took $($sw.Elapsed.TotalSeconds) s" }
        Assert-Eq (Invoke-PqRaterRecord -Rater ([pscustomobject]@{ name = 'x'; command = 'no-such-rater-cmd'; model = 'm' }) -Prompt 'x').why 'launchFailed' 'missing command'
    }

    Test-Case '8 header rewrite' {
        $crlf = Join-Path $scratch 'S0001_crlf.md'
        $bom = [byte[]](0xEF, 0xBB, 0xBF)
        [IO.File]::WriteAllBytes($crlf, $bom + [Text.Encoding]::UTF8.GetBytes("# S0001`r`n`r`n**Status:** Draft`r`n**Complexity:** medium - not assessed at capture`r`n`r`n## 0. Owner`r`ntext`r`n"))
        if (-not (Set-PqSpecComplexity -SpecPath $crlf -Line '**Complexity:** 3 - rated by m (high): x')) { throw 'replace wrote nothing' }
        $b = [IO.File]::ReadAllBytes($crlf)
        if ($b[0] -ne 0xEF) { throw 'BOM lost' }
        $t = [Text.Encoding]::UTF8.GetString($b, 3, $b.Length - 3)
        if ($t -notmatch "\*\*Complexity:\*\* 3 - rated by m \(high\): x`r`n" -or $t -match "[^`r]`n") { throw "CRLF or line lost: [$t]" }
        $lf = Join-Path $scratch 'S0002_lf.md'
        [IO.File]::WriteAllText($lf, "# S0002`n`n**Status:** Draft`n**Created:** 2026-11-18`n`n## 0. Owner`ntext`n", [Text.UTF8Encoding]::new($false))
        $null = Set-PqSpecComplexity -SpecPath $lf -Line '**Complexity:** 5 - x'
        $lines = [IO.File]::ReadAllLines($lf)
        Assert-Eq $lines[4] '**Complexity:** 5 - x' 'inserted after the header'
        $pin = Join-Path $scratch 'S0003_pin.md'
        [IO.File]::WriteAllText($pin, "# S0003`n**Complexity:** 7 pinned - owner`n", [Text.UTF8Encoding]::new($false))
        if (Set-PqSpecComplexity -SpecPath $pin -Line '**Complexity:** 2 - x') { throw 'pinned line rewritten' }
        if ([IO.File]::ReadAllText($pin) -notmatch '7 pinned') { throw 'pinned file changed' }
        $mixed = Join-Path $scratch 'S0004_mixed.md'
        [IO.File]::WriteAllText($mixed, "# S0004`r`n**Complexity:** 2 - x`n`nbody`r`nlast`n", [Text.UTF8Encoding]::new($false))
        $null = Set-PqSpecComplexity -SpecPath $mixed -Line '**Complexity:** 4 - y'
        Assert-Eq ([IO.File]::ReadAllText($mixed)) "# S0004`r`n**Complexity:** 4 - y`n`nbody`r`nlast`n" 'mixed ends kept'
        $short = Join-Path $scratch 'S0005_short.md'
        [IO.File]::WriteAllText($short, "# S0005`n**Status:** Draft", [Text.UTF8Encoding]::new($false))
        $null = Set-PqSpecComplexity -SpecPath $short -Line '**Complexity:** 1 - z'
        Assert-Eq ([IO.File]::ReadAllText($short)) "# S0005`n**Status:** Draft`n**Complexity:** 1 - z" 'inserted after the last line'
        $ansi = Join-Path $scratch 'S0006_ansi.md'
        $raw = [Text.Encoding]::ASCII.GetBytes("# S0006`n**Complexity:** 2 - x`ncaf") + [byte[]](0xE9, 0x0A)
        [IO.File]::WriteAllBytes($ansi, $raw)
        if (Set-PqSpecComplexity -SpecPath $ansi -Line '**Complexity:** 4 - y') { throw 'a file that is not UTF-8 was rewritten' }
        Assert-Eq ([Convert]::ToHexString([IO.File]::ReadAllBytes($ansi))) ([Convert]::ToHexString($raw)) 'bytes untouched'
    }

    Test-Case '9 escalation' {
        $num = [pscustomobject]@{ numeric = $true; pinned = $false; score = 4; level = 'medium'; spec = '' }
        Assert-Eq (Get-PqEscalatedScore $num 'child-failed' 'In Progress' 2) 6 'failed +2'
        Assert-Eq (Get-PqEscalatedScore $num 'ok' 'Broken' 2) 6 'Broken +2'
        Assert-Eq (Get-PqEscalatedScore $num 'ok' 'Implemented' 2) -1 'success'
        Assert-Eq (Get-PqEscalatedScore $num 'timeout' '' 0) -1 'escalateBy 0'
        $num.score = 8
        Assert-Eq (Get-PqEscalatedScore $num 'no-progress' '' 2) 9 'cap'
        $num.score = 9
        Assert-Eq (Get-PqEscalatedScore $num 'no-progress' '' 2) -1 'already 9'
        Assert-Eq (Get-PqEscalatedScore ([pscustomobject]@{ numeric = $false; pinned = $false; score = 5 }) 'child-failed' '' 2) -1 'word grade'
        Assert-Eq (Get-PqEscalatedScore ([pscustomobject]@{ numeric = $true; pinned = $true; score = 5 }) 'child-failed' '' 2) -1 'pinned'
        $num.score = 3
        Assert-Eq (Get-PqEscalatedScore $num 'no-progress-or-claim-lost' 'In Progress' 2) 5 'a quick unmoved pass'
        Assert-Eq (ConvertTo-PqEscalationOutcome 'no-progress-or-claim-lost') 'no-progress' 'the spelling written'
        foreach ($neutral in @('limit-hit', 'launch-failed', 'claim-lost-before-launch', 'provider-error', 'killed', 'halted')) {
            Assert-Eq (Get-PqEscalatedScore $num $neutral 'Broken' 2) -1 "neutral $neutral on a Broken ticket"
        }
        $g6 = [pscustomobject]@{ numeric = $true; score = 6 }
        Assert-Eq (Test-PqGradeRewritten $g6 ([pscustomobject]@{ numeric = $true; score = 4 })) $true 'lowered inside the band'
        Assert-Eq (Test-PqGradeRewritten $g6 ([pscustomobject]@{ numeric = $true; score = 6 })) $false 'same grade'
        Assert-Eq (Test-PqGradeRewritten ([pscustomobject]@{ numeric = $false; score = 5 }) ([pscustomobject]@{ numeric = $true; score = 5 })) $true 'a word made a grade'
        if (-not [IO.File]::ReadAllText((Join-Path $pqLib 'loop.ps1')).Contains('if (-not (Test-PqGradeRewritten $levelInfo $afterInfo))')) { throw 'the worker does not ask whether the pass rewrote the grade' }
    }

    Test-Case '12 one rating per ticket' {
        $ans = Join-Path $scratch 'answer12.txt'
        [IO.File]::WriteAllText($ans, '{"score": 2, "reason": "one file", "confidence": "high"}')
        $regR = [pscustomobject]@{ raters = @([pscustomobject]@{ name = 'stub'; command = 'cmd'; model = 'm'; argsTemplate = @('/c', 'type', $ans) }) }
        $spec = Join-Path $scratch 'S0012_rate.md'
        $capture = "# S0012`n**Complexity:** medium - not assessed at capture`n"
        $info = [pscustomobject]@{ spec = $spec; level = 'medium'; numeric = $false; score = 5 }
        [IO.File]::WriteAllText($spec, "# S0012`n**Complexity:** 7 - written meanwhile`n")
        Assert-Eq (Invoke-PqTicketRating -Registry $regR -Info $info -RepoKey 'k' -TicketId 'S0012').ok $false 'graded since the info was read'
        if ([IO.File]::ReadAllText($spec) -notmatch '7 - written meanwhile') { throw 'a graded line was overwritten' }
        [IO.File]::WriteAllText($spec, $capture)
        $ready = [Threading.ManualResetEventSlim]::new($false)
        $other = [powershell]::Create()
        try {
            $null = $other.AddScript({ param($name, $ready) $m = [Threading.Mutex]::new($false, $name); $null = $m.WaitOne(); $ready.Set(); [Threading.Thread]::Sleep(250); $m.ReleaseMutex(); $m.Dispose() }).AddArgument((Get-PqRatingLockName 'k' 'S0012')).AddArgument($ready)
            $job = $other.BeginInvoke()
            if (-not $ready.Wait(2000)) { throw 'the other worker never took the lock' }
            Assert-Eq (Invoke-PqTicketRating -Registry $regR -Info $info -RepoKey 'k' -TicketId 'S0012').ok $false 'the one that waited'
            $null = $other.EndInvoke($job)
        }
        finally { $other.Dispose(); $ready.Dispose() }
        Assert-Eq ([IO.File]::ReadAllText($spec)) $capture 'the one that waited asked nothing'
        Assert-Eq (Invoke-PqTicketRating -Registry $regR -Info $info -RepoKey 'k' -TicketId 'S0012').score 2 'a free worker rates'
    }
}
finally {
    $env:SZA_PORTFOLIO_ROOT = $origEnv
    Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
}
if ($failed -gt 0) { Write-Host "$failed case(s) failed" -ForegroundColor Red; exit 1 }
Write-Host 'all cases passed' -ForegroundColor Green
exit 0
