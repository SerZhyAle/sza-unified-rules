<#
check-compliance.ps1 - canon compliance gate. Runs INSIDE a target project repo and returns non-zero
when that repo violates the canon.

This is the mechanism that stops the drift. check-rules.ps1 validates the canon's own text; this one
validates a project against it. A rule that this script cannot assert will drift - that is a law, not a
shortcoming, so keep the checks mechanical and the false-positive rate at zero.

Groups:
  CANON  adoption stamp, staleness, mirror banners
  RULES  the agent-rules file: canon pointer, no restatement, no self-declared fork
  LAY    layout and ledger
  SEC    secrets and committed artifacts
  VER    version shape and channel manifests
  SURF   product surfaces: privacy page, SEO block, sitemap/robots
  STYLE  house text style in prose and user-visible UI text

Exit codes: 0 = clean; 1 = violations; 2 = internal error.

Usage:
  pwsh -File tools/check-compliance.ps1                      # target = repo at cwd
  pwsh -File tools/check-compliance.ps1 -RepoRoot P:\X -Strict
  pwsh -File tools/check-compliance.ps1 -Json | ConvertFrom-Json
  pwsh -File tools/check-compliance.ps1 -PrintDigest         # canon core digest, for a stamp
#>
[CmdletBinding()]
param(
    [string]$RepoRoot,
    [string]$CanonRoot,
    [switch]$Strict,
    [string[]]$Only,
    [string[]]$Skip,
    [switch]$Json,
    [switch]$PrintDigest
)

$ErrorActionPreference = 'Stop'

try {
    # ---------------------------------------------------------------- setup

    if (-not $CanonRoot) { $CanonRoot = Split-Path $PSScriptRoot -Parent }
    $rulesDir = Join-Path $CanonRoot 'rules'
    if (-not (Test-Path -LiteralPath $rulesDir)) { throw "canon rules/ not found under '$CanonRoot'" }

    # The core digest covers the RULE DOCS ONLY. README.md, the contrib records and templates are
    # excluded on purpose: a change to one project's own record must never mark every repo stale.
    function Get-CanonCoreDigest {
        param([string]$Dir)
        $excluded = @('README.md', 'SPREAD_BACK_PROMPT.md')
        $docs = Get-ChildItem -Path $Dir -Filter *.md -File |
                Where-Object { $excluded -notcontains $_.Name } |
                Sort-Object Name
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try {
            $buffer = New-Object System.IO.MemoryStream
            foreach ($doc in $docs) {
                $text = [System.IO.File]::ReadAllText($doc.FullName)
                $text = $text -replace "`r`n", "`n"
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($doc.Name + "`n" + $text)
                $buffer.Write($bytes, 0, $bytes.Length)
            }
            $buffer.Position = 0
            $hash = $sha.ComputeHash($buffer)
            return 'sha256:' + (($hash | ForEach-Object { $_.ToString('x2') }) -join '')
        }
        finally { $sha.Dispose() }
    }

    $canonVersionFile = Join-Path $CanonRoot 'CANON_VERSION'
    $canonVersion = if (Test-Path -LiteralPath $canonVersionFile) {
        (Get-Content -LiteralPath $canonVersionFile -Raw).Trim()
    } else { 'unknown' }
    $canonDigest = Get-CanonCoreDigest -Dir $rulesDir

    if ($PrintDigest) {
        Write-Host "canon version: $canonVersion"
        Write-Host "coreDigest:    $canonDigest"
        exit 0
    }

    if (-not $RepoRoot) {
        $top = & git rev-parse --show-toplevel 2>$null
        $RepoRoot = if ($LASTEXITCODE -eq 0 -and $top) { $top.Trim() } else { (Get-Location).Path }
    }
    $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
    if (-not (Test-Path -LiteralPath $RepoRoot)) { throw "repo root '$RepoRoot' does not exist" }

    $findings = New-Object System.Collections.Generic.List[object]
    $script:Exemptions = @()

    function Add-Finding {
        param(
            [Parameter(Mandatory)][string]$Id,
            [Parameter(Mandatory)][string]$Severity,   # error | warn
            [string]$Path = '',
            [int]$Line = 0,
            [Parameter(Mandatory)][string]$Message,
            [string]$Fix = ''
        )
        if ($Only -and $Only -notcontains $Id) { return }
        if ($Skip -and $Skip -contains $Id) { return }
        # A declared exemption suppresses the finding. It carries a reason, and where it is temporary an
        # `until` date past which it stops applying - so an exemption cannot quietly become permanent.
        foreach ($ex in $script:Exemptions) {
            if ($ex.id -ne $Id) { continue }
            if ($ex.path -and $Path -notlike $ex.path) { continue }
            if ($ex.until) {
                $untilDate = [datetime]::MinValue
                if ([datetime]::TryParse($ex.until, [ref]$untilDate) -and (Get-Date) -gt $untilDate) { continue }
            }
            return
        }
        $sev = if ($Strict -and $Severity -eq 'warn') { 'error' } else { $Severity }
        $findings.Add([pscustomobject]@{
            id = $Id; severity = $sev; path = $Path; line = $Line; message = $Message; fix = $Fix
        })
    }

    function Test-Enabled {
        param([string]$Id)
        if ($Only -and $Only -notcontains $Id) { return $false }
        if ($Skip -and $Skip -contains $Id) { return $false }
        return $true
    }

    function Format-Lines {
        param($Lines)
        $sorted = @($Lines | Sort-Object)
        if ($sorted.Count -le 8) { return ($sorted -join ', ') }
        return (($sorted | Select-Object -First 8) -join ', ') + ", +$($sorted.Count - 8) more"
    }

    function Join-RepoPath { param([string]$Relative) Join-Path $RepoRoot $Relative }
    function Test-RepoPath { param([string]$Relative) Test-Path -LiteralPath (Join-RepoPath $Relative) }

    # Tracked files, when this is a git repo. Everything git-scoped degrades to N/A otherwise.
    $isGit = Test-Path -LiteralPath (Join-Path $RepoRoot '.git')
    $tracked = @()
    if ($isGit) {
        $tracked = @(& git -C $RepoRoot ls-files 2>$null)
        if ($LASTEXITCODE -ne 0) { $tracked = @() }
    }

    # ------------------------------------------------------- group CANON

    $stampPath = Join-RepoPath '.sza-canon.json'
    $stamp = $null
    if (-not (Test-Path -LiteralPath $stampPath)) {
        Add-Finding -Id 'SZA-CANON01' -Severity 'error' -Path '.sza-canon.json' `
            -Message 'no canon adoption stamp' `
            -Fix 'Run the adopt-canon skill, or copy <canon>/templates/.sza-canon.json and fill it.'
    }
    else {
        try { $stamp = Get-Content -LiteralPath $stampPath -Raw | ConvertFrom-Json }
        catch {
            Add-Finding -Id 'SZA-CANON02' -Severity 'error' -Path '.sza-canon.json' `
                -Message "stamp is not valid JSON: $_" -Fix 'See <canon>/templates/.sza-canon.json.'
        }
    }

    if ($stamp) {
        if ($stamp.exemptions) { $script:Exemptions = @($stamp.exemptions) }
        foreach ($key in @('canon', 'overlay', 'ledgerShape')) {
            if ($null -eq $stamp.$key) {
                Add-Finding -Id 'SZA-CANON02' -Severity 'error' -Path '.sza-canon.json' `
                    -Message "stamp missing key '$key'" -Fix 'See <canon>/templates/.sza-canon.json.'
            }
        }
        foreach ($key in @('version', 'coreDigest', 'model')) {
            if ($stamp.canon -and $null -eq $stamp.canon.$key) {
                Add-Finding -Id 'SZA-CANON02' -Severity 'error' -Path '.sza-canon.json' `
                    -Message "stamp missing key 'canon.$key'" -Fix 'See <canon>/templates/.sza-canon.json.'
            }
        }

        # SZA-CANON03 - staleness ladder. The digest, not a git SHA: a SHA fires on every repo
        # whenever any contrib record changes, which is a 100% false-positive rate.
        if ($stamp.canon.coreDigest -and $stamp.canon.coreDigest -ne $canonDigest) {
            $adopted = $null
            if ($stamp.canon.adoptedOn) { [void][datetime]::TryParse($stamp.canon.adoptedOn, [ref]$adopted) }
            $ageDays = if ($adopted) { ((Get-Date) - $adopted).Days } else { 0 }
            $sev = if ($ageDays -gt 180) { 'error' } else { 'warn' }
            Add-Finding -Id 'SZA-CANON03' -Severity $sev -Path '.sza-canon.json' `
                -Message "adoption is stale: stamp digest $($stamp.canon.coreDigest) vs canon $canonDigest (canon $canonVersion, adopted $($stamp.canon.adoptedOn))" `
                -Fix 'Re-read the changed rule docs, reconcile, then update canon.version and canon.coreDigest.'
        }

        # SZA-CANON04 - the core plus exactly one overlay. A canon home or a portfolio page ships no
        # product, so it has no overlay to declare.
        $overlays = @($stamp.overlay)
        $needsOverlay = -not ($stamp.role -in @('canon-home', 'portfolio'))
        if ($overlays.Count -eq 0 -and $needsOverlay) {
            Add-Finding -Id 'SZA-CANON04' -Severity 'error' -Path '.sza-canon.json' `
                -Message 'no overlay declared' -Fix 'Declare one of A B C D - see PLATFORM_OVERLAYS.md.'
        }
        elseif ($overlays.Count -gt 1 -and -not (@($stamp.editions).Count -or @($stamp.shapes).Count)) {
            Add-Finding -Id 'SZA-CANON04' -Severity 'error' -Path '.sza-canon.json' `
                -Message "more than one overlay ($($overlays -join ', ')) without an editions or shapes entry" `
                -Fix 'A project reads the core then exactly one overlay. Several overlays means editions - declare them.'
        }

        # SZA-CANON06 - the contrib record resolves.
        if ($stamp.canon.contribRecord) {
            $rec = Join-Path $rulesDir $stamp.canon.contribRecord
            if (-not (Test-Path -LiteralPath $rec)) {
                Add-Finding -Id 'SZA-CANON06' -Severity 'warn' -Path '.sza-canon.json' `
                    -Message "contribRecord '$($stamp.canon.contribRecord)' does not resolve under the canon" `
                    -Fix 'Create it from rules/contrib/TEMPLATE.md.'
            }
        }
    }

    # SZA-CANON05 - a mirrored canon doc must carry the sync banner. An unmarked copy is a silent fork.
    if (Test-Enabled 'SZA-CANON05') {
        $canonDocNames = (Get-ChildItem -Path $rulesDir -Filter *.md -File | ForEach-Object { $_.Name })
        $guidesDir = Join-RepoPath 'docs/guides'
        if (Test-Path -LiteralPath $guidesDir) {
            foreach ($copy in (Get-ChildItem -Path $guidesDir -Filter *.md -File)) {
                if ($canonDocNames -notcontains $copy.Name) { continue }
                $head = (Get-Content -LiteralPath $copy.FullName -TotalCount 3) -join "`n"
                if ($head -notmatch '(?i)mirror' -or $head -notmatch '(?i)unified[ _]rules') {
                    Add-Finding -Id 'SZA-CANON05' -Severity 'error' -Path "docs/guides/$($copy.Name)" -Line 1 `
                        -Message 'copy of a canon doc without a sync banner' `
                        -Fix 'Add the banner, or delete the copy and link the canon instead.'
                }
                elseif ($head -notmatch 'digest:') {
                    Add-Finding -Id 'SZA-CANON05' -Severity 'warn' -Path "docs/guides/$($copy.Name)" -Line 1 `
                        -Message 'mirror banner uses the old SHA form, not digest:' `
                        -Fix "Re-stamp: <!-- Mirrored from Unified_Rules @ $canonVersion digest:$($canonDigest.Substring(7,12)) on <date>. Edit the canonical copy, not this. -->"
                }
            }
        }
    }

    # ------------------------------------------------------- group RULES

    $agentFiles = @('CLAUDE.md', 'AGENTS.md', 'GEMINI.md') | Where-Object { Test-RepoPath $_ }

    if ($agentFiles.Count -eq 0) {
        Add-Finding -Id 'SZA-RULES01' -Severity 'error' -Path '.' `
            -Message 'no agent-instructions file at the repo root' `
            -Fix 'Add CLAUDE.md and/or AGENTS.md - see NEW_PROJECT_CHECKLIST.md.'
    }

    # Split a markdown file into bullet/heading/table blocks with their continuations.
    # Line granularity gives false positives from wrapped prose; whole paragraphs over-suppress list
    # items. Bullet granularity is the level that actually separates the two.
    function Get-MarkdownBlocks {
        param([string]$FullPath)
        $blocks = @()
        $cur = $null
        $curLine = 0
        $inFence = $false
        $n = 0
        foreach ($line in (Get-Content -LiteralPath $FullPath)) {
            $n++
            if ($line -match '^\s*```') {
                if ($cur) { $blocks += [pscustomobject]@{ line = $curLine; text = $cur }; $cur = $null }
                $inFence = -not $inFence
                continue
            }
            if ($inFence) { continue }
            if ($line -match '^\s*$') {
                if ($cur) { $blocks += [pscustomobject]@{ line = $curLine; text = $cur }; $cur = $null }
                continue
            }
            $isNew = $line -match '^\s*([-*+]|\d+\.)\s' -or $line -match '^#{1,6}\s' -or $line -match '^\s*\|'
            if ($isNew) {
                if ($cur) { $blocks += [pscustomobject]@{ line = $curLine; text = $cur } }
                $cur = $line
                $curLine = $n
                # A heading with no body text must never score - it is a section label, not a rule.
                if ($line -match '^#{1,6}\s') {
                    $blocks += [pscustomobject]@{ line = $n; text = ''; }
                    $cur = $null
                }
            }
            elseif ($cur) { $cur = "$cur $line" }
            else { $cur = $line; $curLine = $n }
        }
        if ($cur) { $blocks += [pscustomobject]@{ line = $curLine; text = $cur } }
        return $blocks
    }

    # Each entry is a rule with exactly one home in the canon. Restating it locally is the drift.
    $canonPhrases = @(
        @{ id = 'GI1';   home = 'GITHUB_INTERACTION';   re = '(?i)working tree is (the )?(source of truth|the authority|truth|authoritative)' }
        @{ id = 'GI2a';  home = 'GITHUB_INTERACTION';   re = '(?i)(commit|push)[^.\n]{0,40}only when the user (asks|requests)' }
        @{ id = 'GI2b';  home = 'GITHUB_INTERACTION';   re = '(?i)never commit (on|to) the (default|main) branch' }
        @{ id = 'GI2c';  home = 'GITHUB_INTERACTION';   re = '(?i)(--no-verify|skip hooks|bypass signing)' }
        @{ id = 'GI3a';  home = 'GITHUB_INTERACTION';   re = '(?i)co-authored-by' }
        @{ id = 'GI3b';  home = 'GITHUB_INTERACTION';   re = '(?i)commit(s| messages)?[^.\n]{0,60}\bEnglish\b' }
        @{ id = 'GI5';   home = 'GITHUB_INTERACTION';   re = '(?i)stale .{0,20}GITHUB_TOKEN' }
        @{ id = 'GI6';   home = 'GITHUB_INTERACTION';   re = '(?i)never run .{0,10}find|disk-wide root' }
        @{ id = 'RL1';   home = 'REPOSITORY_LAYOUT';    re = '(?i)(no secret is ever committed|never commit(ed)? (a )?secret)' }
        @{ id = 'RL2';   home = 'REPOSITORY_LAYOUT';    re = '(?i)binaries are build output|never stores a compiled release' }
        @{ id = 'DC2a';  home = 'DOCUMENTATION_CONCEPT'; re = '(?i)keep[- ]a[- ]changelog|\[Unreleased\]' }
        @{ id = 'DC2b';  home = 'DOCUMENTATION_CONCEPT'; re = '(?i)never hand-bump|derived mechanically' }
        @{ id = 'DC2c';  home = 'DOCUMENTATION_CONCEPT'; re = '(?i)(a )?local build is (never|not) a release|build is not a release' }
        @{ id = 'DC5';   home = 'DOCUMENTATION_CONCEPT'; re = '(?i)(no long dashes|em[- ]dash|ellipsis */ *dash)' }
        @{ id = 'AU1';   home = 'AUTHOR';               re = "(?i)chat( with me)?:? (in )?(the owner.{0,3}s language|russian|RU\b)" }
        @{ id = 'TQ1';   home = 'TESTING_AND_QA';       re = '(?i)no claim without evidence|evidence[- ]led|evidence ladder' }
        @{ id = 'AI1';   home = 'AI_USAGE';             re = "(?i)no trailing .{0,4}what I did" }
    )

    # Pointing AT a rule is correct; re-authoring it is the drift. This is what tells them apart.
    $canonRefRe = '(?i)Unified[ _]Rules|\bcanon\b|GITHUB_INTERACTION|DOCUMENTATION_CONCEPT|REPOSITORY_LAYOUT|AI_USAGE|AUTHOR\.md|TESTING_AND_QA|SECURITY_AND_PRIVACY|PLATFORM_OVERLAYS|RELEASE_AND_DISTRIBUTION|CHANNEL_MATRIX|DEVELOPMENT\.md|INVARIANTS|§|canon-ok|docs/[A-Z_]+\.md'

    $forkRes = @(
        '(?i)(deliberately|intentionally|on purpose|by design)[^.]{0,120}(restat|duplicat|mirror|repeat|cop(y|ies|ied))'
        '(?i)(restat|duplicat)[a-z]*[^.]{0,60}\b(in-repo|here|locally|in this file)\b'
        '(?i)(so|to keep)[^.]{0,40}(the )?(repo|repository|file)[^.]{0,40}(stays |remains |is )?self-contained'
    )
    # A block telling you NOT to restate is the opposite of a confession. Without this guard the
    # exemplary line "Reference it, do not restate it here" scores as a fork.
    $forkNegationRe = "(?i)((do not|don't|does not|never|rather than|instead of|without|no need to)\s+(re-?)?(state|stat\w*|duplicat\w*|cop(y|ying)|mirror\w*|author)|(nothing|none of it|no rule\w*)\s+(is|are|was|were)\s+(re-?)?(stated|duplicated|copied|mirrored))"

    foreach ($af in $agentFiles) {
        $full = Join-RepoPath $af
        $text = Get-Content -LiteralPath $full -Raw
        $lineCount = (Get-Content -LiteralPath $full).Count

        # SZA-RULES02 - the file must point at the canon and name its consumption model.
        if ($text -notmatch '(?i)Unified[ _]Rules|sza-unified-rules') {
            Add-Finding -Id 'SZA-RULES02' -Severity 'error' -Path $af `
                -Message 'no canon pointer' `
                -Fix 'Add the pointer block: canon plugin, overlay, consumption model, contrib record.'
        }
        elseif ($text -notmatch '(?i)\b(reference|mirror)\b') {
            Add-Finding -Id 'SZA-RULES02' -Severity 'warn' -Path $af `
                -Message 'canon pointer does not name the consumption model' `
                -Fix 'State "reference" or "mirror" explicitly.'
        }

        $blocks = Get-MarkdownBlocks -FullPath $full
        $hitIds = @{}
        foreach ($b in $blocks) {
            if (-not $b.text) { continue }
            if ($b.text -match 'canon-ok') { continue }
            if ($b.text -match $canonRefRe) { continue }
            foreach ($p in $canonPhrases) {
                if ($b.text -match $p.re) {
                    if (-not $hitIds.ContainsKey($p.id)) { $hitIds[$p.id] = @{ line = $b.line; home = $p.home } }
                }
            }
        }
        if ($hitIds.Count -gt 0) {
            $sev = if ($hitIds.Count -ge 3) { 'error' } else { 'warn' }
            $detail = ($hitIds.Keys | Sort-Object | ForEach-Object { "$_ -> $($hitIds[$_].home).md:L$($hitIds[$_].line)" }) -join ', '
            Add-Finding -Id 'SZA-RULES03' -Severity $sev -Path $af `
                -Message "$($hitIds.Count) canon-owned rule(s) restated locally: $detail" `
                -Fix 'These have one home in the canon. Delete the local copy and keep the pointer, or mark a genuine repo delta with <!-- canon-ok: reason -->.'
        }

        # SZA-RULES04 - a repo that has decided to fork the canon says so out loud. No threshold.
        foreach ($b in $blocks) {
            if (-not $b.text) { continue }
            if ($b.text -match $forkNegationRe) { continue }
            foreach ($re in $forkRes) {
                if ($b.text -match $re) {
                    Add-Finding -Id 'SZA-RULES04' -Severity 'error' -Path $af -Line $b.line `
                        -Message 'self-declared duplication of the canon' `
                        -Fix 'A self-contained restatement is a fork, not a mirror. Delete the restated rules and keep the pointer, or convert them to marked mirrors under docs/guides/ and re-sync. Record the choice as a DIVERGE delta.'
                    break
                }
            }
        }

        # SZA-RULES05 - informational only. Size is not the signal; RULES03 is the real gate.
        if ($lineCount -gt 400) {
            Add-Finding -Id 'SZA-RULES05' -Severity 'warn' -Path $af `
                -Message "$lineCount lines" `
                -Fix 'Check the bulk is repo-specific architecture, not process. Size alone is not a violation.'
        }
    }

    # --------------------------------------------------------- group LAY

    if (-not (Test-RepoPath 'README.md')) {
        Add-Finding -Id 'SZA-LAY01' -Severity 'error' -Path 'README.md' -Message 'missing' -Fix 'Add it.'
    }
    if (-not (@('LICENSE', 'LICENSE.md', 'LICENSE.txt') | Where-Object { Test-RepoPath $_ })) {
        Add-Finding -Id 'SZA-LAY01' -Severity 'error' -Path 'LICENSE' -Message 'missing' -Fix 'Add it.'
    }

    if ($stamp -and $null -ne $stamp.ledgerShape) {
        $shape = $stamp.ledgerShape
        switch ("$shape") {
            '1' {
                $cl = Join-RepoPath 'CHANGELOG.md'
                if (-not (Test-Path -LiteralPath $cl)) {
                    Add-Finding -Id 'SZA-LAY02' -Severity 'error' -Path 'CHANGELOG.md' `
                        -Message 'ledgerShape 1 declared but no root CHANGELOG.md' -Fix 'Add it, or declare another shape.'
                }
                elseif ((Get-Content -LiteralPath $cl -Raw) -notmatch '(?m)^##\s*\[Unreleased\]') {
                    Add-Finding -Id 'SZA-LAY02' -Severity 'error' -Path 'CHANGELOG.md' `
                        -Message 'ledgerShape 1 declared but the file is not Keep-a-Changelog (no "## [Unreleased]")' `
                        -Fix 'Fix the format, or declare ledgerShape 2 and move it to DEV/CHANGELOG.md.'
                }
            }
            '2' {
                if (-not (Test-RepoPath 'DEV/CHANGELOG.md')) {
                    Add-Finding -Id 'SZA-LAY02' -Severity 'error' -Path 'DEV/CHANGELOG.md' `
                        -Message 'ledgerShape 2 declared but the dev-log is missing' -Fix 'Add it, or declare another shape.'
                }
            }
            '3' {
                if (-not $stamp.ledgerFile -or -not (Test-RepoPath $stamp.ledgerFile)) {
                    Add-Finding -Id 'SZA-LAY02' -Severity 'error' -Path '.sza-canon.json' `
                        -Message 'ledgerShape 3 declared but ledgerFile is missing or does not resolve' -Fix 'Name the inventory file.'
                }
            }
            '4' {
                if (Test-RepoPath 'CHANGELOG.md') {
                    Add-Finding -Id 'SZA-LAY02' -Severity 'error' -Path 'CHANGELOG.md' `
                        -Message 'ledgerShape 4 declared (no standalone ledger) but a root CHANGELOG.md exists - two ledgers is drift' `
                        -Fix 'Delete one. Exactly one ledger is authoritative.'
                }
                $wf = Join-RepoPath '.github/workflows'
                $hasAuto = $false
                if (Test-Path -LiteralPath $wf) {
                    $hasAuto = @(Get-ChildItem -Path $wf -Filter *.yml -File -ErrorAction SilentlyContinue |
                        Where-Object { (Get-Content -LiteralPath $_.FullName -Raw) -match 'generate_release_notes' }).Count -gt 0
                }
                if (-not $hasAuto) {
                    Add-Finding -Id 'SZA-LAY02' -Severity 'warn' -Path '.github/workflows' `
                        -Message 'ledgerShape 4 declared but no workflow sets generate_release_notes' `
                        -Fix 'Shape 4 is git history plus auto-generated release notes. Prove it, or declare another shape.'
                }
            }
        }
    }

    $docsDir = Join-RepoPath 'docs'
    if ((Test-Path -LiteralPath $docsDir) -and
        (@(Get-ChildItem -Path $docsDir -Filter *.md -File -ErrorAction SilentlyContinue).Count -ge 3) -and
        -not (Test-RepoPath 'docs/README.md')) {
        Add-Finding -Id 'SZA-LAY03' -Severity 'warn' -Path 'docs/README.md' `
            -Message 'docs/ holds 3+ markdown files but has no index' -Fix 'Add docs/README.md - the index of this tree.'
    }

    # --------------------------------------------------------- group SEC

    if ($isGit) {
        $secretRes = @(
            '\.(pfx|snk|jks|keystore|p12|pem|cer)$'
            '(^|/)\.env$'
            'local\.properties$'
            'cws-key.*\.json$'
            'secrets?\.(json|ya?ml|txt)$'
        )
        foreach ($f in $tracked) {
            foreach ($re in $secretRes) {
                if ($f -match $re) {
                    Add-Finding -Id 'SZA-SEC01' -Severity 'error' -Path $f `
                        -Message 'secret or signing material is tracked' `
                        -Fix 'git rm --cached it, add the glob to .gitignore, and rotate the credential.'
                    break
                }
            }
        }

        $gi = Join-RepoPath '.gitignore'
        if (Test-Path -LiteralPath $gi) {
            $giText = (Get-Content -LiteralPath $gi -Raw)
            $missing = @('*.pfx', '*.snk', '*.jks', '*.keystore', '.env', 'token', 'secret') |
                Where-Object { $giText -notmatch [regex]::Escape($_) }
            if ($missing.Count -gt 0) {
                Add-Finding -Id 'SZA-SEC02' -Severity 'warn' -Path '.gitignore' `
                    -Message "missing leak globs: $($missing -join ', ')" `
                    -Fix 'Add them. The globs pre-empt the leak instead of catching it afterwards.'
            }
        }
        else {
            Add-Finding -Id 'SZA-SEC02' -Severity 'warn' -Path '.gitignore' -Message 'no .gitignore' -Fix 'Add one with the leak globs.'
        }

        # SZA-SEC03 - a committed binary needs a narrow negation AND a why-comment.
        # Restored dependency trees are vendored tooling, not a decision to commit a build artifact.
        # Without this default a single NuGet packages/ tree buries every other finding under hundreds
        # of lines, and a gate nobody can read is a gate nobody runs.
        $vendorDefault = @('packages/*', 'node_modules/*', 'vendor/*', 'third_party/*', '.nuget/*', 'Pods/*')
        $vendorAllow = $vendorDefault + $(if ($stamp -and $stamp.vendorAllow) { @($stamp.vendorAllow) } else { @() })
        $binRe = '\.(exe|dll|msi|msix|appx|aab|apk|zip|7z)$'
        $sec03Hits = New-Object System.Collections.Generic.List[string]
        foreach ($f in ($tracked | Where-Object { $_ -match $binRe })) {
            $exempt = $false
            foreach ($allow in $vendorAllow) { if ($f -like $allow -or $f -like "*/$allow") { $exempt = $true; break } }
            if ($exempt) { continue }
            $hasWhy = $false
            if (Test-Path -LiteralPath $gi) {
                $giLines = @(Get-Content -LiteralPath $gi)
                for ($i = 0; $i -lt $giLines.Count; $i++) {
                    if ($giLines[$i] -match '^!' ) {
                        $neg = $giLines[$i].TrimStart('!').Trim()
                        $negPattern = $neg -replace '\*\*', '*'
                        if ($f -like $negPattern -or $f -like "$negPattern*") {
                            # The why-comment heads the whole ignore/negate group, not necessarily the
                            # line touching the negation. Scan up to the group's blank-line boundary.
                            for ($j = $i - 1; $j -ge 0 -and $j -ge $i - 8; $j--) {
                                if ($giLines[$j] -match '^\s*$') { break }
                                if ($giLines[$j] -match '^\s*#') { $hasWhy = $true; break }
                            }
                            if (-not $hasWhy -and $i -lt $giLines.Count - 1 -and $giLines[$i + 1] -match '^\s*#') {
                                $hasWhy = $true
                            }
                        }
                    }
                }
            }
            if (-not $hasWhy) { $sec03Hits.Add($f) }
        }
        # Report per directory, not per file: one restored dependency tree is one decision, not 400.
        foreach ($grp in ($sec03Hits | Group-Object { (Split-Path $_ -Parent) -replace '\\', '/' })) {
            $where = if ($grp.Name) { $grp.Name } else { '.' }
            $sample = ($grp.Group | Select-Object -First 3 | ForEach-Object { Split-Path $_ -Leaf }) -join ', '
            $more = if ($grp.Count -gt 3) { " (+$($grp.Count - 3) more)" } else { '' }
            Add-Finding -Id 'SZA-SEC03' -Severity 'error' -Path $where `
                -Message "$($grp.Count) committed binary file(s) without a narrow negation carrying a why-comment: $sample$more" `
                -Fix 'Add "!path/to/file" to .gitignore with a # comment saying who produces it and why a clone needs it - or, if this is a restored dependency tree, add its glob to vendorAllow in the stamp.'
        }

        # SZA-SEC04 - live credential literals. Fixed prefixes only, so the FP rate stays zero.
        $credRes = @(
            'ghp_[A-Za-z0-9]{36}'
            'github_pat_[A-Za-z0-9_]{40,}'
            'AKIA[0-9A-Z]{16}'
            'xox[baprs]-[A-Za-z0-9-]{10,}'
            '-----BEGIN [A-Z ]*PRIVATE KEY-----'
            'AIza[0-9A-Za-z_-]{35}'
        )
        # Vendored trees are excluded: a JWK library legitimately contains the PEM header as a string
        # constant, and flagging it teaches the owner to ignore this check.
        $vendorPathRe = '(^|/)(node_modules|packages|vendor|third_party|Pods|\.nuget)/'
        $textExt = '\.(md|ps1|yml|yaml|json|cs|vb|go|kt|bat|js|ts|html)$'
        foreach ($f in ($tracked | Where-Object { $_ -match $textExt -and $_ -notmatch $vendorPathRe })) {
            $p = Join-RepoPath $f
            if (-not (Test-Path -LiteralPath $p)) { continue }
            $content = Get-Content -LiteralPath $p -Raw -ErrorAction SilentlyContinue
            if (-not $content) { continue }
            foreach ($re in $credRes) {
                if ($content -match $re) {
                    Add-Finding -Id 'SZA-SEC04' -Severity 'error' -Path $f `
                        -Message 'live credential literal' -Fix 'Rotate the credential, then untrack it.'
                    break
                }
            }
        }
    }

    # --------------------------------------------------------- group VER

    if ($isGit -and $stamp) {
        $tags = @(& git -C $RepoRoot tag --sort=-creatordate 2>$null)
        if ($LASTEXITCODE -ne 0) { $tags = @() }
        $tagRegex = $stamp.versionShape.tagRegex
        $prefixes = if ($stamp.versionShape.editionTagPrefixes) { @($stamp.versionShape.editionTagPrefixes) } else { @() }

        if ($tags.Count -gt 0) {
            if (-not $tagRegex) {
                Add-Finding -Id 'SZA-VER01' -Severity 'error' -Path '.sza-canon.json' `
                    -Message "repo has tags (latest '$($tags[0])') but versionShape.tagRegex is not declared" `
                    -Fix 'Take the regex from the release script or CI - never from prose.'
            }
            else {
                $latest = $tags[0]
                foreach ($pre in $prefixes) { if ($latest.StartsWith($pre)) { $latest = $latest.Substring($pre.Length); break } }
                if ($latest -notmatch $tagRegex) {
                    Add-Finding -Id 'SZA-VER01' -Severity 'error' -Path '.' `
                        -Message "latest tag '$($tags[0])' does not match the declared shape '$tagRegex'" `
                        -Fix 'The shape orders every future update against the installed one. Fix the tag, or - if the shape truly changed - that is a frozen-anchor break needing an owner decision. An edition on its own clock belongs in editionTagPrefixes.'
                }
            }
        }

        foreach ($ch in @($stamp.channels)) {
            $ok = switch ($ch) {
                'winget'  { @($tracked | Where-Object { $_ -match '(^|/)(publishing/)?winget/.*\.yaml$' }).Count -gt 0 }
                'msstore' { @($tracked | Where-Object { $_ -match '(^|/)(publishing/)?msix/.*AppxManifest\.xml$' }).Count -gt 0 }
                'installer' { @($tracked | Where-Object { $_ -match '\.(iss|wxs)$' }).Count -gt 0 }
                'play'    { @($tracked | Where-Object { $_ -match 'build\.gradle(\.kts)?$' }).Count -gt 0 }
                'chrome'  { @($tracked | Where-Object { $_ -match 'manifest\.json$' }).Count -gt 0 }
                'edge'    { @($tracked | Where-Object { $_ -match 'manifest\.json$' }).Count -gt 0 }
                'vscode'  { @($tracked | Where-Object { $_ -match 'vscode-extension/package\.json$' }).Count -gt 0 }
                'github'  { $true }
                default   { $true }
            }
            if (-not $ok) {
                Add-Finding -Id 'SZA-VER03' -Severity 'error' -Path '.sza-canon.json' `
                    -Message "declared channel '$ch' has no committed manifest folder" `
                    -Fix 'Manifests are committed source; submissions are generated from them.'
            }
        }
    }

    # -------------------------------------------------------- group SURF

    if ($stamp) {
        $storeChannels = @('msstore', 'play', 'chrome', 'edge')
        $hasStore = @($stamp.channels | Where-Object { $storeChannels -contains $_ }).Count -gt 0
        $isProductSite = $stamp.site -and $stamp.site.kind -eq 'product'

        if ($hasStore -or $isProductSite) {
            $carve = $stamp.privacy -and $stamp.privacy.carveOut -eq 'zero-data' -and
                     (-not $isProductSite) -and -not $stamp.privacy.sensitiveAccess
            if (-not $carve) {
                if (-not ($stamp.privacy -and $stamp.privacy.page -and (Test-RepoPath $stamp.privacy.page))) {
                    Add-Finding -Id 'SZA-SURF01' -Severity 'error' -Path ($(if ($stamp.privacy) { $stamp.privacy.page } else { '' })) `
                        -Message 'store-listed or site-bearing product with no hosted privacy page' `
                        -Fix 'Host one. The zero-data carve-out needs no site; a local-but-sensitive tool (keyboard hook, clipboard, capture) hosts it anyway.'
                }
            }
        }

        foreach ($page in @($stamp.site.pages)) {
            $rel = if ($stamp.site.root -and $stamp.site.root -ne '.') { "$($stamp.site.root)/$page" } else { $page }
            if (-not (Test-RepoPath $rel)) {
                Add-Finding -Id 'SZA-SURF02' -Severity 'error' -Path $rel -Message 'declared site page does not exist' -Fix 'Fix the stamp or add the page.'
                continue
            }
            $html = Get-Content -LiteralPath (Join-RepoPath $rel) -Raw
            # Match "<title" not "<title>": a localized page carries attributes on the tag.
            $required = @{
                '<title'            = '<title[\s>]'
                'meta description'  = '<meta[^>]*name=["'']description'
                'canonical'         = '<link[^>]*rel=["'']canonical'
            }
            foreach ($k in $required.Keys) {
                if ($html -notmatch $required[$k]) {
                    Add-Finding -Id 'SZA-SURF02' -Severity 'error' -Path $rel -Message "SEO block missing: $k" `
                        -Fix 'A page without these is invisible to crawlers even when live.'
                }
            }
            $h1 = ([regex]::Matches($html, '<h1[\s>]')).Count
            if ($h1 -ne 1) {
                Add-Finding -Id 'SZA-SURF02' -Severity 'error' -Path $rel -Message "expected exactly one <h1>, found $h1" -Fix 'One h1 per page.'
            }
            $optional = @{ 'og:title' = 'og:title'; 'og:description' = 'og:description'; 'og:image' = 'og:image'
                           'og:url' = 'og:url'; 'twitter:card' = 'twitter:card'; 'JSON-LD' = 'application/ld\+json' }
            $missingOpt = $optional.Keys | Where-Object { $html -notmatch $optional[$_] }
            if ($missingOpt) {
                Add-Finding -Id 'SZA-SURF02' -Severity 'warn' -Path $rel `
                    -Message "SEO block missing: $(($missingOpt | Sort-Object) -join ', ')" `
                    -Fix 'og:image and twitter:card are what break link previews.'
            }
            # SZA-VER04 - a hard-coded version in a CTA goes stale on the next release.
            if ($html -match '/download/v?\d+[\d.]*\d/') {
                Add-Finding -Id 'SZA-VER04' -Severity 'warn' -Path $rel `
                    -Message 'hard-coded version in a link' `
                    -Fix 'Point at /releases/latest, the package id, or the store page.'
            }
        }

        if ($stamp.site -and $stamp.site.root) {
            $siteRoot = if ($stamp.site.root -eq '.') { '' } else { "$($stamp.site.root)/" }
            foreach ($f in @('sitemap.xml', 'robots.txt')) {
                if (-not (Test-RepoPath "$siteRoot$f")) {
                    Add-Finding -Id 'SZA-SURF03' -Severity 'warn' -Path "$siteRoot$f" -Message 'missing' `
                        -Fix 'Add it, listing every public page.'
                }
            }
        }

        # Pairs a repo maintains byte-identical by hand, declared in the stamp so the gate can enforce it.
        foreach ($pair in @($stamp.byteIdenticalPairs)) {
            if (@($pair).Count -ne 2) { continue }
            $a = Join-RepoPath $pair[0]; $b = Join-RepoPath $pair[1]
            if (-not (Test-Path -LiteralPath $a) -or -not (Test-Path -LiteralPath $b)) {
                Add-Finding -Id 'SZA-LAY06' -Severity 'error' -Path $pair[0] -Message "declared byte-identical pair is missing a file" -Fix 'Fix the stamp or restore the file.'
                continue
            }
            $ha = (Get-FileHash -LiteralPath $a -Algorithm SHA256).Hash
            $hb = (Get-FileHash -LiteralPath $b -Algorithm SHA256).Hash
            if ($ha -ne $hb) {
                Add-Finding -Id 'SZA-LAY06' -Severity 'error' -Path $pair[1] `
                    -Message "must be byte-identical to $($pair[0]) but differs ($($ha.Substring(0,8)) vs $($hb.Substring(0,8)))" `
                    -Fix 'Re-apply the edit to both files before deploying.'
            }
        }
    }

    # ------------------------------------------------------- group STYLE

    # Prose scoping is what makes this usable: a raw grep reports an order of magnitude more hits,
    # nearly all of them inside code spans, fences and link targets.
    if ($isGit -and (Test-Enabled 'SZA-STYLE01')) {
        # The canon scopes house style to prose and user-visible UI - never code, SPECS, commands, logs
        # or vendored files. Planning trees, dev logs and agent/skill definitions are specs, so they are
        # out of scope here; including them buries the real hits under internal churn.
        $skipRe = '(^|/)(PLAN/|tasks/|docs/specifications/|specs?/|DEV/|dev-notes/|\.claude/|\.agents/|\.github/prompts/|temp/|tmp/|node_modules|packages/|vendor/|third_party/)|THIRD.?PARTY'
        foreach ($f in ($tracked | Where-Object { $_ -match '\.md$' -and $_ -notmatch $skipRe })) {
            $p = Join-RepoPath $f
            if (-not (Test-Path -LiteralPath $p)) { continue }
            $head = (Get-Content -LiteralPath $p -TotalCount 3 -ErrorAction SilentlyContinue) -join "`n"
            if ($head -match '(?i)mirror.*unified[ _]rules') { continue }
            $inFence = $false
            $n = 0
            $dashLines = New-Object System.Collections.Generic.List[int]
            $dotsLines = New-Object System.Collections.Generic.List[int]
            foreach ($line in (Get-Content -LiteralPath $p)) {
                $n++
                if ($line -match '^\s*```') { $inFence = -not $inFence; continue }
                if ($inFence) { continue }
                $prose = [regex]::Replace($line, '`[^`]*`', '')
                $prose = [regex]::Replace($prose, '\]\([^)]*\)', ']()')
                if ($prose -match '[\u2013\u2014\u2015]') { $dashLines.Add($n) }
                if ($prose -match '\.{3,}' -or $prose -match '\u2026') { $dotsLines.Add($n) }
            }
            # One finding per file, not per line. A style backlog is one job; listing it line by line
            # buries every other check under it and the gate stops being read.
            if ($dashLines.Count -gt 0) {
                Add-Finding -Id 'SZA-STYLE01' -Severity 'error' -Path $f -Line $dashLines[0] `
                    -Message "$($dashLines.Count) em/en-dash(es) in prose, line(s) $(Format-Lines $dashLines)" `
                    -Fix "House style: plain hyphen '-'."
            }
            if ($dotsLines.Count -gt 0) {
                Add-Finding -Id 'SZA-STYLE02' -Severity 'warn' -Path $f -Line $dotsLines[0] `
                    -Message "$($dotsLines.Count) '...' in prose, line(s) $(Format-Lines $dotsLines)" `
                    -Fix "House style: '..'. Warn-only - a quoted real UI string or a CLI placeholder is legitimate."
            }
        }
    }

    # Same rule on the user-visible metadata of a site page - the surface that actually reaches readers.
    if ($stamp -and $stamp.site) {
        foreach ($page in @($stamp.site.pages)) {
            $rel = if ($stamp.site.root -and $stamp.site.root -ne '.') { "$($stamp.site.root)/$page" } else { $page }
            if (-not (Test-RepoPath $rel)) { continue }
            $html = Get-Content -LiteralPath (Join-RepoPath $rel) -Raw
            foreach ($m in [regex]::Matches($html, '(?is)<title[^>]*>(.*?)</title>|content=["'']([^"'']*)["'']')) {
                $val = if ($m.Groups[1].Success) { $m.Groups[1].Value } else { $m.Groups[2].Value }
                if ($val -match '[\u2013\u2014\u2015]') {
                    Add-Finding -Id 'SZA-STYLE01' -Severity 'error' -Path $rel `
                        -Message "em/en-dash in user-visible page metadata: '$($val.Trim())'" -Fix "House style: plain hyphen '-'."
                    break
                }
            }
        }
    }

    # ------------------------------------------------------------ report

    $errors = @($findings | Where-Object severity -eq 'error')
    $warns  = @($findings | Where-Object severity -eq 'warn')

    if ($Json) {
        [pscustomobject]@{
            repo = $RepoRoot; canonVersion = $canonVersion; canonDigest = $canonDigest
            errors = $errors.Count; warnings = $warns.Count; findings = $findings
        } | ConvertTo-Json -Depth 6
        exit ($(if ($errors.Count -gt 0) { 1 } else { 0 }))
    }

    foreach ($f in ($findings | Sort-Object @{e={$_.severity}}, id, path)) {
        $loc = if ($f.line -gt 0) { "$($f.path):$($f.line)" } elseif ($f.path) { $f.path } else { '.' }
        $tag = if ($f.severity -eq 'error') { 'FAIL' } else { 'WARN' }
        Write-Host "$tag $($f.id) ${loc}: $($f.message)"
        if ($f.fix) { Write-Host "     fix: $($f.fix)" }
    }

    $overlayText = if ($stamp -and $stamp.overlay) { ($stamp.overlay -join ',') } else { '?' }
    Write-Host "check-compliance: $(Split-Path $RepoRoot -Leaf) - $($errors.Count) error(s), $($warns.Count) warning(s) (overlay $overlayText, canon $canonVersion)"

    if ($errors.Count -gt 0) {
        Write-Error "check-compliance: $($errors.Count) error(s)" -ErrorAction Continue
        exit 1
    }
    exit 0
}
catch {
    Write-Error "check-compliance: internal error: $_" -ErrorAction Continue
    exit 2
}
