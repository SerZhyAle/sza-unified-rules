<#
on-user-prompt.ps1 - Claude Code UserPromptSubmit hook, shipped by the sza plugin.

Two advisories the canon asks for by name, in ONE process. Both fire on the same event and each is a
sub-second string check, so spawning two interpreters to run them would pay the ~170-250 ms PowerShell
startup twice per prompt for no reason - the canon's own "batch the fast gates into one process"
(DEVELOPMENT.md section 15) applies to its own hooks first.

  1. CONTEXT SIZE (canon: AI_USAGE.md section 3, "put the context warning where the human can act on it
     - at prompt submit, not only in the statusline"). Reads the tail of the session transcript, recovers
     the last request's token total, and warns past 250k / 400k.

  2. TASK RUNG (canon: AI_USAGE.md section 5, "a size-tier ordering written as prose does not route
     anything - put the nudge on the prompt-submit event"; the rung ladder itself is the spec-to-audit
     skill, stage 0). Matches the prompt against a short, high-precision micro-task pattern list, vetoes
     on a real-work list, drops anything past a length ceiling, and names the cheap rung.

Why this event, and why advisory. Routing is decided the moment the owner types, which is exactly when
UserPromptSubmit runs - the canon records the opposite verdict for a context-PRICING hook on this same
event (timing-blind, because that tax accrues inside autonomous blocks where no prompt is submitted), so
the boundary is written down in AI_USAGE.md section 5 and must not be re-litigated in either direction.
Both advisories are deliberately non-blocking: a false fire that refused a prompt would cost more than
the miss it prevents, and the owner stays free to say "no, this is bigger than it looks".

Precision over recall by design. A nudge on real feature work trains the reader to ignore it, so the
trigger list stays short and obviously-small, a negative list vetoes anything that smells like real work,
and a length ceiling drops long briefs before either list runs. Same reasoning sets the context
thresholds above the measured median: a warning on every second prompt trains the reader to ignore it.

Applies in every repository, not only in canon adopters: both costs are charged by the harness. Escape
hatches: SZA_HOOKS_OFF=1 disables the file; SZA_NO_CONTEXT_WARN=1 and SZA_NO_RUNG_NUDGE=1 disable one
advisory each.

Contract:
  exit 0 always - a prompt must never fail to submit because of this hook.
  stdout is either empty (nothing to say) or one compact JSON object carrying additionalContext.

Exit codes (DEVELOPMENT.md section 15, reachable-exit-code contract):
  0  always, whether or not an advisory was emitted, and on any internal failure.
#>

$SoftContext = 250000
$HardContext = 400000
$TailBytes = 512KB

# Anything longer than this is a brief, not a one-liner - checked before the pattern lists so a long
# prompt that merely mentions a colour never fires.
$MaxPromptChars = 200

# Small, high-confidence micro-task signals. RU first because the owner writes RU; EN for pasted text.
$MicroTaskPatterns = @(
    'опечатк', 'очепятк', '\btypo\b'
    'переименуй', '\brename\b'
    '(помен|смени|измени|поправ|подкрут)\w*\s+(цвет|отступ|размер|шрифт|текст|надпис|иконк|подпис)'
    '(подвинь|сдвинь|выровняй|отцентр)'
    'убери\s+(лишн|пробел|точк|запят)'
    '(текст|надпись|подпись)\s+(кнопк|заголовк|подсказк|тултип)'
    'одн(у|ой)\s+(строк|строчк|букв)'
    '\bмелоч', 'по\s+мелоч'
    '(быстр\w*|просто)\s+(поправ|фикс|исправ|помен)'
    'one[- ]liner', 'single (string|line|colour|color|label)'
    '(change|fix|tweak|adjust)\s+(the\s+)?(colour|color|padding|margin|label|caption|wording|font size)'
)

# Vetoes. Each of these means the request is real work no matter how short it is phrased.
$RealWorkPatterns = @(
    'крэш', 'краш', 'падает', 'вылетает', '\bcrash\b', '\bANR\b'
    'миграц', 'migration'
    'рефактор', 'refactor'
    '(нов|добав)\w*\s+(функци|фич|экран|настройк|возможност)'
    '\bfeature\b', 'new screen'
    'релиз', 'зарелиз', 'release', 'publish', 'store'
    'спек', '\bspec\b', '\bS\d{4}\b'
    'тест', '\btest\b'
    'замер', 'измер', 'аудит', 'audit'
    'архитектур', 'architecture'
    'секрет', 'secret', 'token', 'signing'
)

function Read-StdinUtf8 {
    # The prompt is Cyrillic and the console code page on the reference machine is cp1251, so decoding
    # through the default reader corrupts it and every pattern silently misses. Decode the raw stream.
    try {
        $stream = [Console]::OpenStandardInput()
        $reader = New-Object System.IO.StreamReader($stream, (New-Object System.Text.UTF8Encoding $false))
        return $reader.ReadToEnd()
    }
    catch {
        return ''
    }
}

function Get-ContextAdvisory([string]$transcript) {
    if ($env:SZA_NO_CONTEXT_WARN -in @('1', 'true', 'TRUE')) { return $null }
    if ([string]::IsNullOrWhiteSpace($transcript)) { return $null }
    if (-not (Test-Path -LiteralPath $transcript -PathType Leaf)) { return $null }

    # Read the last chunk only - transcripts routinely reach hundreds of MB and this runs on every prompt.
    $tail = ''
    try {
        $fs = [System.IO.File]::Open($transcript, 'Open', 'Read', 'ReadWrite')
        try {
            $start = [math]::Max(0, $fs.Length - $TailBytes)
            [void]$fs.Seek($start, 'Begin')
            $reader = New-Object System.IO.StreamReader($fs)
            $tail = $reader.ReadToEnd()
        }
        finally { $fs.Dispose() }
    }
    catch { return $null }

    if ([string]::IsNullOrWhiteSpace($tail)) { return $null }

    # Walk backwards to the most recent usage block - the last one written is the closest estimate of
    # what the next request will carry.
    $lines = $tail -split "`n"
    $total = 0
    for ($i = $lines.Length - 1; $i -ge 0; $i--) {
        $line = $lines[$i]
        if ($line.IndexOf('"cache_read_input_tokens"') -lt 0) { continue }
        $sum = 0
        foreach ($field in @('cache_read_input_tokens', 'cache_creation_input_tokens', 'input_tokens')) {
            $m = [regex]::Match($line, ('"{0}":(\d+)' -f $field))
            if ($m.Success) { $sum += [int]$m.Groups[1].Value }
        }
        if ($sum -gt 0) { $total = $sum; break }
    }

    if ($total -lt $SoftContext) { return $null }
    $k = [math]::Round($total / 1000)

    if ($total -ge $HardContext) {
        return (
            "CONTEXT $k k - past the point where the conversation, not the task, sets the response time. " +
            "Unless this prompt genuinely needs the earlier turns, run /clear now and restate the task in " +
            "one message; use /compact only if the history is still load-bearing. Offload raw artifacts " +
            "(build logs, dumps, whole-file reads) to the project's scratch dir and read back a targeted " +
            "slice instead of carrying them."
        )
    }

    return (
        "CONTEXT $k k - above the 250k band. At the next task or phase boundary run /compact, and /clear " +
        "outright when switching tickets. Keep raw artifacts in the project's scratch dir rather than in " +
        "the conversation."
    )
}

function Get-RungAdvisory([string]$prompt) {
    if ($env:SZA_NO_RUNG_NUDGE -in @('1', 'true', 'TRUE')) { return $null }
    if ([string]::IsNullOrWhiteSpace($prompt)) { return $null }

    $trimmed = $prompt.Trim()

    # The owner already picked a route - never second-guess an explicit slash command.
    if ($trimmed.StartsWith('/')) { return $null }
    if ($trimmed.Length -gt $MaxPromptChars) { return $null }

    $hit = $false
    foreach ($p in $MicroTaskPatterns) {
        if ($trimmed -imatch $p) { $hit = $true; break }
    }
    if (-not $hit) { return $null }

    foreach ($p in $RealWorkPatterns) {
        if ($trimmed -imatch $p) { return $null }
    }

    return (@(
        'RUNG CHECK (canon spec-to-audit stage 0) - this request matched the micro-task shape: short,'
        'and about a string, a colour, a rename or a nudge of one element. Start at the cheapest rung'
        'that can do it - a quick edit needs no spec and no build gate, and a narrow understood fix needs'
        'no spec. If this repo has its own smallest-tier command, use that one; do NOT open the full'
        'spec -> plan -> implement -> audit pipeline for this. Measured across the reference repo''s'
        'transcript corpus, the cheapest tier was chosen 0 times in 434 command invocations while the'
        'full pipeline took 91, so the default reach is the wrong one and this is the correction. If the'
        'work turns out to need a build, a spec, or more than one file, say so in one line and escalate -'
        'this is a reminder, not a rule to obey against evidence.'
    ) -join ' ')
}

if ($env:SZA_HOOKS_OFF -in @('1', 'true', 'TRUE')) { exit 0 }

try {
    $raw = Read-StdinUtf8
    if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }

    $payload = $raw | ConvertFrom-Json -ErrorAction Stop

    $notes = @(
        (Get-ContextAdvisory ([string]$payload.transcript_path)),
        (Get-RungAdvisory ([string]$payload.prompt))
    ) | Where-Object { $_ }

    if ($notes.Count -eq 0) { exit 0 }

    $out = [ordered]@{
        hookSpecificOutput = [ordered]@{
            hookEventName     = 'UserPromptSubmit'
            additionalContext = ($notes -join "`n`n")
        }
    }
    Write-Output ($out | ConvertTo-Json -Compress -Depth 5)
}
catch {
    # A malformed payload or a parser change must never cost the owner a prompt. Report on stderr so the
    # failure is visible in --debug, then submit exactly as before.
    [Console]::Error.WriteLine("sza on-user-prompt: skipped - $_")
}

exit 0
