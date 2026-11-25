#requires -Version 7.0
<#
.SYNOPSIS
    Fast tests for memory.ps1 nested index links, measure-regulation-cost.ps1 .claude/rules accounting,
    install-agent-rules.ps1 idempotent global setup, and Get-PqAgentPrompt contractFile/.claude/rules routing.

.DESCRIPTION
    Runs exclusively against temporary scratch directories (never modifies live $HOME or ~/.claude).
    Exit codes: 0 all passed; 1 assertion failed.
#>
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$memoryScript = Join-Path $repoRoot 'tools/memory/memory.ps1'
$costScript = Join-Path $repoRoot 'tools/measure-regulation-cost.ps1'
$installScript = Join-Path $repoRoot 'tools/install-agent-rules.ps1'
$harness = Join-Path $repoRoot 'tools/harness'
$pqLib = Join-Path $harness 'portfolio/lib'
$utf8 = [System.Text.UTF8Encoding]::new($false)

$scratch = Join-Path ([IO.Path]::GetTempPath()) ('sza-memory-index-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $scratch -Force
$script:passed = 0
$script:failed = 0

function Write-Utf8([string]$Path, [string]$Text) {
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent)) { $null = New-Item -ItemType Directory -Path $parent -Force }
    [IO.File]::WriteAllText($Path, $Text, $utf8)
}

function Test-Case([string]$Name, [scriptblock]$Body) {
    try {
        & $Body
        $script:passed++
        Write-Host "PASS  $Name"
    }
    catch {
        $script:failed++
        Write-Host "FAIL  $Name - $_" -ForegroundColor Red
    }
}

function Assert([bool]$Cond, [string]$Msg) {
    if (-not $Cond) { throw $Msg }
}

$origClaudeDir = $env:CLAUDE_CONFIG_DIR
$origMemRoot = $env:SZA_MEMORY_ROOT

try {
    Test-Case '1. memory.ps1 preserves state/INDEX.md, drops broken/traversal links, reports >8k index' {
        $claudeHome = Join-Path $scratch 'claude-home'
        $memRoot = Join-Path $claudeHome 'memory'
        $projMem = Join-Path $claudeHome 'projects/p--demo/memory'
        $bigMem = Join-Path $claudeHome 'projects/p--big/memory'

        Write-Utf8 (Join-Path $memRoot 'MEMORY.md') "# Global`n"
        Write-Utf8 (Join-Path $projMem 'alpha.md') "---`nname: alpha`ndescription: alpha note`nmetadata:`n  scope: project`n---`nbody`n"
        Write-Utf8 (Join-Path $projMem 'unlisted.md') "---`nname: unlisted`ndescription: unlisted note`nmetadata:`n  scope: project`n---`nbody`n"
        Write-Utf8 (Join-Path $projMem 'beta.md') "---`nname: beta`ndescription: beta note`nmetadata:`n  scope: project`n---`nbody`n"
        Write-Utf8 (Join-Path $projMem 'state/INDEX.md') "# State index`n"
        Write-Utf8 (Join-Path $projMem 'state/snap.md') "---`nname: snap`ndescription: snap note`n---`nbody`n"
        $memBody = @(
            '# Memory'
            '- [Alpha](alpha.md) - kept'
            '- [Beta](../memory/beta.md) - hand summary'
            '- [State index](state/INDEX.md) - nested kept'
            '- [Missing nested](state/MISSING.md) - nested broken'
            '- [Escape](../outside.md) - traversal blocked'
            '- [External](https://example.invalid/doc.md) - external ignored'
        ) -join "`n"
        Write-Utf8 (Join-Path $projMem 'MEMORY.md') ($memBody + "`n")

        Write-Utf8 (Join-Path $bigMem 'one.md') "---`nname: one`ndescription: big`nmetadata:`n  scope: project`n---`nbody`n"
        Write-Utf8 (Join-Path $bigMem 'MEMORY.md') ("- [One](one.md) - " + ('x' * 8200) + "`n")

        $env:CLAUDE_CONFIG_DIR = $claudeHome
        $env:SZA_MEMORY_ROOT = $memRoot

        $preJson = (& pwsh -NoProfile -File $memoryScript audit -Json 2>&1) -join "`n"
        Assert ($LASTEXITCODE -eq 0) "pre-sync audit exit $LASTEXITCODE"
        $pre = $preJson | ConvertFrom-Json
        $driftFiles = @($pre.Drift | ForEach-Object { $_.File })
        Assert ($driftFiles -notcontains 'state/INDEX.md') "state/INDEX.md falsely flagged as drift: $($driftFiles -join ', ')"
        Assert ($driftFiles -notcontains 'state/snap.md') "nested state/snap.md should not be flagged as missing from root index"
        Assert ($driftFiles -contains 'state/MISSING.md') "missing nested link not flagged: $($driftFiles -join ', ')"
        Assert ($driftFiles -contains '../outside.md') "traversal link not flagged: $($driftFiles -join ', ')"
        Assert ($driftFiles -contains 'unlisted.md') "unlisted.md not flagged: $($driftFiles -join ', ')"
        Assert (@($pre.OverBudget).Count -eq 1 -and $pre.OverBudget[0].Folder -eq 'p--big') "expected p--big over 8000 chars"

        $syncOut = (& pwsh -NoProfile -File $memoryScript index -Folder $projMem 2>&1) -join "`n"
        Assert ($LASTEXITCODE -eq 0) "index exit $LASTEXITCODE : $syncOut"
        $syncedText = [IO.File]::ReadAllText((Join-Path $projMem 'MEMORY.md'), $utf8)
        Assert ($syncedText -match '\[State index\]\(state/INDEX\.md\)') "sync dropped state/INDEX.md"
        Assert ($syncedText -match '\[Alpha\]\(alpha\.md\)') "sync dropped alpha.md"
        Assert ($syncedText -match '\[External\]\(https://example\.invalid/doc\.md\)') "sync dropped external link"
        Assert ($syncedText -match 'unlisted\.md') "sync did not append unlisted.md"
        Assert ($syncedText -match 'hand summary' -and [regex]::Matches($syncedText, 'beta\.md').Count -eq 1) "sync lost or doubled the line that reaches beta.md through its folder: $syncedText"
        Assert ($syncedText -notmatch 'MISSING\.md') "sync kept broken nested link"
        Assert ($syncedText -notmatch '\.\./outside\.md') "sync kept traversal link"
        Assert ($syncedText -notmatch 'snap\.md') "sync unexpectedly added nested state/snap.md to root index"

        $postJson = (& pwsh -NoProfile -File $memoryScript audit -Json 2>&1) -join "`n"
        Assert ($LASTEXITCODE -eq 0) "post-sync audit exit $LASTEXITCODE"
        $post = $postJson | ConvertFrom-Json
        Assert (@($post.Drift).Count -eq 0) "expected 0 drift after sync, got: $($post.Drift | ConvertTo-Json -Compress)"
    }

    Test-Case '2. measure-regulation-cost.ps1 separates unscoped vs path-scoped .claude/rules' {
        $r = Join-Path $scratch 'cost-repo'
        $pRoot = Join-Path $scratch 'empty-portfolio'
        $null = New-Item -ItemType Directory -Path $pRoot -Force
        Write-Utf8 (Join-Path $r '.sza-canon.json') '{"canon":{"model":"reference"}}'
        Write-Utf8 (Join-Path $r 'CLAUDE.md') ('c' * 1200)
        Write-Utf8 (Join-Path $r 'AGENTS.md') ('a' * 400)
        # No paths: key in the frontmatter; the word in the body and a later --- line must not scope the file
        $trap = "---`ndescription: x`n---`nUse paths: here.`n`n---`n"
        Write-Utf8 (Join-Path $r '.claude/rules/always.md') ($trap + ('u' * (1000 - $trap.Length)))
        $scopedText = "---`npaths:`n  - `"src/**`"`n---`n" + ('s' * 1970)
        Write-Utf8 (Join-Path $r '.claude/rules/scoped.md') $scopedText

        $out = (& pwsh -NoProfile -File $costScript -RepoRoot $r -PortfolioRoot $pRoot 2>&1) -join "`n"
        Assert ($LASTEXITCODE -eq 0) "measure-regulation-cost exit $LASTEXITCODE : $out"
        Assert ($out -match '\.claude/rules \(1 unscoped, always loaded\)\s+claude\s+1000\b') "missing unscoped row: $out"
        Assert ($out -match "\.claude/rules \(1 path-scoped, on demand\)\s+on demand\s+$($scopedText.Length)\b") "missing path-scoped row: $out"
    }

    Test-Case '3. install-agent-rules.ps1 check, dry-run, apply, preserve unrelated sections, idempotent' {
        $fakeHome = Join-Path $scratch 'fake-home'
        Write-Utf8 (Join-Path $fakeHome '.codex/AGENTS.md') "# My Codex rules`n`n## Personal preferences`n`nKeep this intact.`n"
        Write-Utf8 (Join-Path $fakeHome '.gemini/GEMINI.md') "# Global`n`n## Project rules (every repository)`n`n- outdated bullet`n`n## Trailing notes`n`nKeep trailing intact.`n"

        $chk1 = (& pwsh -NoProfile -File $installScript -HomeDir $fakeHome -Check 2>&1) -join "`n"
        Assert ($LASTEXITCODE -eq 1) "expected exit 1 on drift check, got $LASTEXITCODE : $chk1"

        $dry = (& pwsh -NoProfile -File $installScript -HomeDir $fakeHome -DryRun 2>&1) -join "`n"
        Assert ($LASTEXITCODE -eq 0) "expected exit 0 on dry-run, got $LASTEXITCODE : $dry"
        Assert (-not (Test-Path -LiteralPath (Join-Path $fakeHome '.vibe/AGENTS.md'))) "dry-run created vibe file"

        $app1 = (& pwsh -NoProfile -File $installScript -HomeDir $fakeHome 2>&1) -join "`n"
        Assert ($LASTEXITCODE -eq 0) "expected exit 0 on apply, got $LASTEXITCODE : $app1"

        foreach ($rel in '.codex/AGENTS.md', '.gemini/GEMINI.md', '.zcode/AGENTS.md', '.vibe/AGENTS.md') {
            $fp = Join-Path $fakeHome $rel
            Assert (Test-Path -LiteralPath $fp) "missing installed file $rel"
            $bytes = [IO.File]::ReadAllBytes($fp)
            Assert (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)) "BOM written to $rel"
            $txt = [IO.File]::ReadAllText($fp, $utf8)
            Assert ($txt -match '## Project rules \(every repository\)' -and $txt -match 'budget 20,000 characters, hard limit 40,000') "canonical block missing in $rel"
        }

        $codexTxt = [IO.File]::ReadAllText((Join-Path $fakeHome '.codex/AGENTS.md'), $utf8)
        Assert ($codexTxt -match 'Keep this intact\.') "codex existing section lost"
        $geminiTxt = [IO.File]::ReadAllText((Join-Path $fakeHome '.gemini/GEMINI.md'), $utf8)
        Assert ($geminiTxt -match 'Keep trailing intact\.' -and $geminiTxt -notmatch 'outdated bullet') "gemini section update corrupted surrounding content"

        $app2 = (& pwsh -NoProfile -File $installScript -HomeDir $fakeHome 2>&1) -join "`n"
        Assert ($LASTEXITCODE -eq 0 -and $app2 -match 'changed=0') "second apply not idempotent: $app2"

        $chk2 = (& pwsh -NoProfile -File $installScript -HomeDir $fakeHome -Check 2>&1) -join "`n"
        Assert ($LASTEXITCODE -eq 0) "post-apply check exit $LASTEXITCODE : $chk2"

        $badTpl = (& pwsh -NoProfile -File $installScript -HomeDir $fakeHome -TemplatePath (Join-Path $scratch 'missing.md') 2>&1) -join "`n"
        Assert ($LASTEXITCODE -eq 2) "expected exit 2 on missing template, got $LASTEXITCODE : $badTpl"
    }

    Test-Case '4. Get-PqAgentPrompt reads contractFile and adds the .claude/rules reminder before the arguments; gemini uses AGENTS.md' {
        . (Join-Path $harness 'batch/_limit-hold.ps1')
        . (Join-Path $pqLib 'paths.ps1')
        . (Join-Path $pqLib 'events.ps1')
        . (Join-Path $pqLib 'registry.ps1')
        . (Join-Path $pqLib 'loop.ps1')
        . (Join-Path $pqLib 'ledger-watch.ps1')
        . (Join-Path $pqLib 'agents.ps1')
        function Find-PqProviderCli([string]$Id) { return @{ found = $true; command = 'stub.exe'; prefix = @(); note = '' } }

        $gemRec = (New-PqProviderRecord 'gemini').record
        Assert ($gemRec.contractFile -ceq 'AGENTS.md') "gemini contractFile is '$($gemRec.contractFile)', expected AGENTS.md"

        $rArea = Join-Path $scratch 'pq-area'
        Write-Utf8 (Join-Path $rArea 'CLAUDE.md') "# Core`n"
        Write-Utf8 (Join-Path $rArea 'AGENTS.md') "Read CLAUDE.md in full.`n"
        Write-Utf8 (Join-Path $rArea '.claude/rules/a.md') "---`npaths:`n  - `"src/**`"`n---`n"
        $codex = [pscustomobject]@{ name = 'codex'; promptForm = 'file'; contractFile = 'AGENTS.md' }
        $p1 = Get-PqAgentPrompt -Agent $codex -RepoPath $rArea
        Assert ($p1.ok -and $p1.template -match 'read CLAUDE\.md \(and AGENTS\.md\) in full' -and $p1.template -match '\.claude/rules/\*\.md') "unexpected prompt for repo with area rules: $($p1.template)"
        Assert ($p1.template.IndexOf('Before your first edit') -lt $p1.template.IndexOf('argument string:')) "reminder must precede the argument string: $($p1.template)"

        $rClaudeOnly = Join-Path $scratch 'pq-claude-only'
        Write-Utf8 (Join-Path $rClaudeOnly 'CLAUDE.md') "# Core`n"
        $p2 = Get-PqAgentPrompt -Agent $gemRec -RepoPath $rClaudeOnly
        Assert ($p2.ok -and $p2.template -match 'read CLAUDE\.md in full\.' -and $p2.template -notmatch '\.claude/rules') "unexpected prompt for CLAUDE-only repo: $($p2.template)"

        $rAgentsOnly = Join-Path $scratch 'pq-agents-only'
        Write-Utf8 (Join-Path $rAgentsOnly 'AGENTS.md') "# Core`n"
        $p3 = Get-PqAgentPrompt -Agent $codex -RepoPath $rAgentsOnly
        Assert ($p3.ok -and $p3.template -notmatch 'Before your first edit') "unexpected reminder for AGENTS-only repo without area rules: $($p3.template)"

        $claudeAgent = [pscustomobject]@{ name = 'claude'; promptForm = 'slash'; contractFile = 'CLAUDE.md' }
        $p4 = Get-PqAgentPrompt -Agent $claudeAgent -RepoPath $rArea
        Assert ($p4.ok -and $null -eq $p4.template) "slash agent should still return null template"
    }
}
finally {
    if ($null -eq $origClaudeDir) { Remove-Item Env:CLAUDE_CONFIG_DIR -ErrorAction SilentlyContinue } else { $env:CLAUDE_CONFIG_DIR = $origClaudeDir }
    if ($null -eq $origMemRoot) { Remove-Item Env:SZA_MEMORY_ROOT -ErrorAction SilentlyContinue } else { $env:SZA_MEMORY_ROOT = $origMemRoot }
    if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
}

if ($script:failed -gt 0) {
    Write-Host "memory-index.tests: FAILED ($($script:failed) failed, $($script:passed) passed)" -ForegroundColor Red
    exit 1
}
Write-Host "memory-index.tests: OK ($($script:passed) cases)" -ForegroundColor Green
exit 0
