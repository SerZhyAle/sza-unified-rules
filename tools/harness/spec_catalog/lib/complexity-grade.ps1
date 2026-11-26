# The `**Complexity:**` line of a spec file (TASK-FLOW rule 51, amended in 0.32 by canon ticket S0139).
#
# Dot-sourced, never invoked. Defines functions only, keeps no state and prints nothing. Compatible with
# PowerShell 5.1 and 7+ and safe under Set-StrictMode Latest; the Russian words are written as \u escapes so the
# file reads the same with or without a byte-order mark.
#
#   ConvertFrom-SzaComplexityValue -Value <text after the label>
#       @{ recognised; level; score; numeric; pinned; reason }. A grade is one digit 0-9 at the start, optionally
#       followed by the word `pinned`, and then the end of the value or ` - <reason>`; a word is light/medium/hard or
#       its Russian spelling. The level is the band of the grade (0-3 light, 4-6 medium, 7-9 hard); a word reads as
#       the grade 1, 5 or 8. Anything else (`5pinned`, `7-9`, `0/10`, `3 files`) is not recognised: level '' and
#       score -1, never a guess.
#   Get-SzaComplexityBand -Score <0-9>       the level word of a grade
#   Get-SzaComplexityWordScore -Level <word> the grade a level word reads as (1, 5, 8), or -1
#   Find-SzaComplexityLine -Lines <string[]> @{ index; value } of the line within the first 40 lines, index -1 if none
#   Format-SzaComplexityLine -Score -Reason [-Pinned]   the whole header line
#   Get-SzaParallelFlag -Lines <string[]>    @{ flagged; reason } of the `**Parallel:**` line (S0140)

$script:SzaComplexityHeaderWindow = 40

function Get-SzaComplexityBand([int]$Score) {
    if ($Score -lt 0 -or $Score -gt 9) { return '' }
    if ($Score -le 3) { return 'light' }
    if ($Score -le 6) { return 'medium' }
    return 'hard'
}

function Get-SzaComplexityWordScore([string]$Level) {
    switch ($Level) {
        'light' { return 1 }
        'medium' { return 5 }
        'hard' { return 8 }
    }
    return -1
}

function ConvertFrom-SzaComplexityValue([string]$Value) {
    $r = [pscustomobject]@{ recognised = $false; level = ''; score = -1; numeric = $false; pinned = $false; reason = '' }
    if ([string]::IsNullOrWhiteSpace($Value)) { return $r }
    $v = $Value.Trim()
    # A grade: one digit, an optional `pinned`, then nothing or ` - <reason>`. Anything glued to either is no grade.
    $m = [regex]::Match($v, '^(?<n>[0-9])(?:\s+(?<pin>pinned))?(?<rest>\s+-(?:\s.*)?)?$', 'IgnoreCase')
    if ($m.Success) {
        $r.recognised = $true
        $r.numeric = $true
        $r.score = [int]$m.Groups['n'].Value
        $r.level = Get-SzaComplexityBand $r.score
        $r.pinned = $m.Groups['pin'].Success
        $r.reason = ($m.Groups['rest'].Value -replace '^\s*-\s*', '').Trim()
        return $r
    }
    $words = @(
        @{ level = 'light'; pattern = '^(light|\u043B\u0451\u0433\u043A\u0438\u0439|\u043B\u0435\u0433\u043A\u0438\u0439)\b' },
        @{ level = 'medium'; pattern = '^(medium|\u0441\u0440\u0435\u0434\u043D\u0438\u0439)\b' },
        @{ level = 'hard'; pattern = '^(hard|\u0441\u043B\u043E\u0436\u043D\u044B\u0439)\b' }
    )
    foreach ($w in $words) {
        $wm = [regex]::Match($v, $w.pattern + '(?<rest>.*)$', 'IgnoreCase')
        if ($wm.Success) {
            $r.recognised = $true
            $r.level = $w.level
            $r.score = Get-SzaComplexityWordScore $w.level
            $r.reason = ($wm.Groups['rest'].Value -replace '^\s*-\s*', '').Trim()
            return $r
        }
    }
    return $r
}

function Find-SzaComplexityLine([string[]]$Lines) {
    $n = [Math]::Min(@($Lines).Count, $script:SzaComplexityHeaderWindow)
    for ($i = 0; $i -lt $n; $i++) {
        $m = [regex]::Match([string]$Lines[$i], '^\*\*Complexity:\*\*\s*(.+?)\s*$')
        if ($m.Success) { return @{ index = $i; value = $m.Groups[1].Value } }
    }
    return @{ index = -1; value = '' }
}

# The `**Parallel:**` line (S0140): the ticket's work splits into independent parts, written by the pass that plans
# them or by the owner, never by the rater. Present with a reason -> flagged; empty, `no` or `none` -> not flagged.
# Read within the same header window as the grade. @{ flagged; reason }.
function Get-SzaParallelFlag([string[]]$Lines) {
    $n = [Math]::Min(@($Lines).Count, $script:SzaComplexityHeaderWindow)
    for ($i = 0; $i -lt $n; $i++) {
        $m = [regex]::Match([string]$Lines[$i], '^\*\*Parallel:\*\*\s*(.*?)\s*$')
        if ($m.Success) {
            $v = $m.Groups[1].Value
            $off = [string]::IsNullOrWhiteSpace($v) -or [regex]::IsMatch($v, '^(no|none)\b', 'IgnoreCase')
            return @{ flagged = -not $off; reason = ($v -replace '^\s*(yes)?\s*-\s*', '').Trim() }
        }
    }
    return @{ flagged = $false; reason = '' }
}

function Format-SzaComplexityLine([int]$Score, [string]$Reason, [switch]$Pinned) {
    $text = ([string]$Reason -replace '[\r\n\t]+', ' ').Trim()
    if (-not $text) { $text = 'no reason given' }
    $pin = if ($Pinned) { ' pinned' } else { '' }
    return ('**Complexity:** {0}{1} - {2}' -f $Score, $pin, $text)
}
