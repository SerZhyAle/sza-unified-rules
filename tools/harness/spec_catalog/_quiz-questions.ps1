# TASK-FLOW rule 7 question blocks are shared by quiz discovery and the status writer.
$script:QuizEntryPattern = '<!-- BlockQuestions entered: (\d{4}-\d{2}-\d{2}) -->'

function ConvertTo-QuizFlatText([string] $Text) {
    return [regex]::Replace([string]$Text, '\s+', ' ').Trim()
}

function Get-QuizQuestionBlocks {
    param([string[]] $Lines)

    $heading = [regex]'^### Questions \((v\d+), (\d{4}-\d{2}-\d{2})\)(.*)$'   # '### Questions (v1, 2026-11-12)'
    $edge = [regex]'^(#{1,3}(\s|$))'                                        # a heading of level 3 or above ends it
    $qText = [regex]'^-\s+Q:\s*(.+?)\s*$'                                   # '- Q: <question>?'

    $open = $null
    foreach ($line in $lines) {
        $m = $heading.Match($line)
        if ($m.Success) {
            $open = [pscustomobject]@{ version = $m.Groups[1].Value; date = $m.Groups[2].Value; answered = [regex]::Match($m.Groups[3].Value, '^\s+- answered (\d{4}-\d{2}-\d{2})\s*$').Groups[1].Value; questions = [Collections.Generic.List[string]]::new() }
            $open
            continue
        }
        if ($null -ne $open -and $edge.IsMatch($line)) { $open = $null; continue }
        if ($null -eq $open) { continue }
        $q = $qText.Match($line)
        if ($q.Success) { $open.questions.Add($q.Groups[1].Value) }
    }
}

function Get-QuizNoteQuestions([string] $Note) {
    foreach ($match in [regex]::Matches($Note, '(?<![A-Za-z0-9])Q:\s*([^?]*\?)')) {
        ConvertTo-QuizFlatText $match.Groups[1].Value
    }
}

function Get-QuizEntryDay([string] $Updated, [string[]] $Lines) {
    foreach ($line in $Lines) {
        if ($line -match "^$script:QuizEntryPattern$") { return $Matches[1] }
        if ($line -match '^##\s') { break }
    }
    # Legacy specs have no entry marker. Their ledger's last update is the existing quiz fallback.
    return [regex]::Match($Updated, '\d{4}-\d{2}-\d{2}').Value
}

# The comparison key of one question or owner action across tickets: ticket ids (bare, <key>:<id> or <id>_<slug>)
# become one word, so two tickets that name only themselves differently read the same. The prefixes come from the
# ledgers read, never from this file. Markdown emphasis, letter case, run-on white space and a final full stop do
# not count.
function Get-QuizShareKey([string] $Text, [string[]] $IdPrefixes) {
    $flat = $Text -replace '[`*]', ''
    if ($IdPrefixes) {
        $any = @($IdPrefixes | Sort-Object -Property Length -Descending | ForEach-Object { [regex]::Escape($_) }) -join '|'
        $flat = $flat -replace "(?<![A-Za-z0-9])(?:[a-z][a-z0-9_-]*:)?(?:$any)\d{3,}(?:_[a-z0-9-]+)?(?![A-Za-z0-9])", '<id>'
    }
    return (ConvertTo-QuizFlatText $flat).TrimEnd('.', ' ').ToLowerInvariant()
}

function Get-OpenQuizItems {
    param([string] $Note, [string] $Updated, [string[]] $Lines)

    $day = Get-QuizEntryDay $Updated $Lines
    $answered = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($block in (Get-QuizQuestionBlocks -Lines $Lines)) {
        if ($block.version -cne 'v1' -or -not $block.answered -or $block.date -lt $day -or $block.answered -lt $day) { continue }
        foreach ($question in $block.questions) {
            [void]$answered.Add((ConvertTo-QuizFlatText $question))
        }
    }
    foreach ($question in (Get-QuizNoteQuestions $Note)) {
        if (-not $answered.Contains($question)) { "Q: $question" }
    }

    $ownerLevel = 0
    $freshAction = $false
    foreach ($line in $Lines) {
        if ($line -match '^(#{1,6})\s+') {
            if ($Matches[1].Length -le $ownerLevel) { $ownerLevel = 0 }
            if ($line -match '^(#{2,4})\s+(?:\d+(?:\.\d+)*\.?\s+)?Owner inputs\b') {
                $ownerLevel = $Matches[1].Length
            }
        }
        if (-not $ownerLevel -or $line -cnotmatch '^\s*-\s+\*\*DO:\*\*\s*(.*?)\s*$') { continue }
        $action = $Matches[1]
        if ($action -cmatch ' - (?:done|dropped) (\d{4}-\d{2}-\d{2})(?::.*)?$') {
            if ($Matches[1] -ge $day) { $freshAction = $true }
        }
        else { "DO: $action" }
    }
    if (-not $freshAction -and $Note -cmatch '(?<![A-Za-z])DO:\s*(\S.*)') {
        "DO: $($Matches[1]) (requires a current done or dropped mark in Owner inputs)"
    }
}
