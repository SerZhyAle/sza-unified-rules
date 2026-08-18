<#
guard-bash.ps1 - Claude Code PreToolUse hook (matcher: Bash), shipped by the sza plugin.

One script, five checks, one interpreter start. Each check refuses something that CANNOT WORK in the
Bash tool on a Windows machine - none of them is a convention:

  1. `find` with a disk-wide root, or without -maxdepth        (an orphaned scan floods OS handles)
  2. a `.ps1` in command-head position                          (bash cannot execute it, and still exits 0)
  3. a PowerShell `Verb-Noun` cmdlet in command-head position   (not a program on PATH: exit 127, no output)
  4. an interpreter name that resolves nowhere on this machine  (exit 127, no output)
  5. the PowerShell `& { .. }` batching idiom at command start  (bash backgrounds an empty group)

Plus one corruption check that is not a refusal of the head but of an argument:

  6. an argument value beginning with a slash that names a COMMAND rather than a path - MSYS rewrites
     `-Reason "/spec-dev .."` into `C:/Program Files/Git/spec-dev ..` silently, exit code 0, and the
     mangled text lands in whatever file that value was the only record in.

Canon home: GITHUB_INTERACTION.md section 6 "Bash / tooling safety", which states every one of these AND
that they must be enforced by a pre-tool hook rather than trusted as conventions. This file is that
enforcement.

WHY ONE SCRIPT AND NOT FIVE. Starting PowerShell costs 170-250 ms on Windows and a Bash guard pays it on
every call that trips its pre-filter. Five registrations on the same event would pay it up to five times
for one command. The canon's own rule - batch the fast gates into one process (DEVELOPMENT.md section 15)
- is what hooks.json already applies to the two prompt-submit advisories; this is the same rule applied to
the Bash event. The three checks that need quote-aware segmentation share one parse, which is the second
reason: five scripts would have carried five copies of it.

Applies in every repository, not only in canon adopters: every failure above is a property of the
operating system or of the harness, not of a project's conventions. Escape hatch: set SZA_HOOKS_OFF=1.

Contract:
  exit 2 = block the tool call (stderr is shown to Claude)
  exit 0 = allow
Fail-open on any parse error so a malformed payload never breaks Bash globally.

Exit codes (DEVELOPMENT.md section 15, reachable-exit-code contract):
  0  allow - nothing impossible found, or the payload could not be judged.
  2  block - one of the six above, named in the message with the working form to use instead.

Heredoc bodies are removed before segmentation for ALL checks, so a command quoted inside a heredoc body
is data and not a command head. That is a deliberate relaxation of the older stand-alone find guard,
which scanned the raw string: `cat <<EOF ... find / ... EOF` writes a document, it does not start a scan.
#>

function Allow { exit 0 }
function Deny([string]$msg) { [Console]::Error.WriteLine($msg); exit 2 }

if ($env:SZA_HOOKS_OFF -in @('1', 'true', 'TRUE')) { Allow }

# --------------------------------------------------------------------------- shared parsing

# Remove heredoc BODIES, keeping the line that opens them (that line is a real command).
# `<<TAG`, `<<'TAG'`, `<<"TAG"`, `<<-TAG` are all recognised; `<<<` (herestring) is not a heredoc and is
# left alone. An unterminated heredoc swallows the rest of the payload, which is the safe direction:
# fewer segments, so fewer chances to over-block.
function Remove-HeredocBodies([string]$text) {
    $lines = $text -split "`r?`n"
    $out = New-Object System.Collections.Generic.List[string]
    $tag = $null
    foreach ($line in $lines) {
        if ($null -ne $tag) {
            if ($line.Trim() -eq $tag) { $tag = $null }
            continue
        }
        $out.Add($line)
        $m = [regex]::Match($line, '(?<!<)<<-?\s*(?:''([^'']+)''|"([^"]+)"|([A-Za-z_][A-Za-z0-9_]*))(?!<)')
        if ($m.Success) {
            $tag = @($m.Groups[1].Value, $m.Groups[2].Value, $m.Groups[3].Value |
                Where-Object { $_ })[0]
        }
    }
    return ($out -join "`n")
}

# Split on bash command separators that sit OUTSIDE single/double quotes, so a `find` inside a quoted
# grep pattern, or a cmdlet name inside a quoted string, is never mistaken for a command head.
# Separators: | ; & ( ) ` and newline (covers ||, &&, |, ;, &, $( ), subshells).
# { } are intentionally NOT separators - a .ps1 inside a pwsh `& { .. }` block must stay attached to its
# `pwsh` head so it is recognised as an interpreter argument.
function Split-UnquotedSegments([string]$text) {
    $segs = New-Object System.Collections.Generic.List[string]
    $sb = New-Object System.Text.StringBuilder
    $inS = $false; $inD = $false
    foreach ($c in $text.ToCharArray()) {
        $ch = [string]$c
        if ($inS) { if ($ch -eq "'") { $inS = $false }; [void]$sb.Append($ch); continue }
        if ($inD) { if ($ch -eq '"') { $inD = $false }; [void]$sb.Append($ch); continue }
        switch ($ch) {
            "'"  { $inS = $true; [void]$sb.Append($ch) }
            '"'  { $inD = $true; [void]$sb.Append($ch) }
            '|'  { [void]$segs.Add($sb.ToString()); [void]$sb.Clear() }
            ';'  { [void]$segs.Add($sb.ToString()); [void]$sb.Clear() }
            '&'  { [void]$segs.Add($sb.ToString()); [void]$sb.Clear() }
            '('  { [void]$segs.Add($sb.ToString()); [void]$sb.Clear() }
            ')'  { [void]$segs.Add($sb.ToString()); [void]$sb.Clear() }
            '`'  { [void]$segs.Add($sb.ToString()); [void]$sb.Clear() }
            "`n" { [void]$segs.Add($sb.ToString()); [void]$sb.Clear() }
            default { [void]$sb.Append($ch) }
        }
    }
    [void]$segs.Add($sb.ToString())
    return $segs
}

# --------------------------------------------------------------------------- payload

try {
    $raw = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($raw)) { Allow }
    $cmd = [string](($raw | ConvertFrom-Json).tool_input.command)
} catch {
    # Never break Bash on a malformed hook payload.
    Allow
}

if ([string]::IsNullOrWhiteSpace($cmd)) { Allow }

$scanned = Remove-HeredocBodies $cmd

# --------------------------------------------------------------------------- check 5: `& { .. }` head

# Anchored at the start of the command or of a list element, so `cmd && { ... }` - a real bash brace
# group after `&&`, which is NOT command-head position - is left alone. Quoted spans are blanked first,
# so the idiom quoted as text (a doc line, an echo, a pwsh -Command string) is never mistaken for one
# being run: that is the same over-block the head checks below avoid by segmenting quote-aware.
$unquoted = [regex]::Replace($scanned, '''[^'']*''|"[^"]*"', ' ')
if ($unquoted -match '(?m)(?:^|;|\n)\s*&\s*\{') {
    Deny("Blocked by sza guard-bash (canon GITHUB_INTERACTION.md section 6): '& { .. }' is PowerShell's batching idiom and a syntax error in Bash - `$LASTEXITCODE is unset here and '& { .. }' backgrounds an empty group, so the chain reports success having run nothing. Hand it to the interpreter: pwsh -NoProfile -Command `"& { cmd1; cmd2 }`" , or call one script per step.")
}

# --------------------------------------------------------------------------- per-segment head checks

# A start path that maps to a disk-wide root (each matched against a single token).
$broadRoot = @(
    '^/$',                # POSIX root
    '^//$',               # UNC / MSYS double-slash root
    '^~/?$',              # home root
    '^[A-Za-z]:[\\/]?$',  # drive root: c:  c:/  c:\
    '^/[A-Za-z]/?$',      # MSYS drive root: /c  /c/
    '^//[^/\s]+/?$'       # UNC host root: //host  //host/
)
# Benign leading tokens that precede the real command head.
$prefixTokens = @('sudo', 'time', 'nice', 'command', 'env', 'builtin', 'exec', '\')
# Interpreters that legitimately take a .ps1 as an ARGUMENT (head is the interpreter).
$psInterpreters = @('pwsh', 'pwsh.exe', 'powershell', 'powershell.exe', 'pwsh-preview')
# Approved PowerShell verbs. The head must be Verb-Noun with BOTH parts capitalised and the verb on this
# list, which is what keeps a real hyphenated binary (docker-compose, pre-commit, x86_64-w64-mingw32-gcc)
# out of the net. A cmdlet is blocked because bash answers exit 127 and returns nothing at all.
$psVerbs = @(
    'Get', 'Set', 'New', 'Remove', 'Add', 'Clear', 'Copy', 'Move', 'Rename', 'Select', 'Where',
    'ForEach', 'Sort', 'Measure', 'Out', 'Write', 'Read', 'Test', 'Invoke', 'Start', 'Stop', 'Restart',
    'Import', 'Export', 'ConvertTo', 'ConvertFrom', 'Convert', 'Join', 'Split', 'Format', 'Group',
    'Compare', 'Resolve', 'Push', 'Pop', 'Enter', 'Exit', 'Update', 'Install', 'Uninstall', 'Find',
    'Save', 'Wait', 'Receive', 'Send', 'Show', 'Open', 'Close', 'Enable', 'Disable', 'Register',
    'Unregister', 'Expand', 'Compress'
)
# Interpreter NAMES that Git Bash does not ship, so a miss here is a genuine "not installed on this
# machine" and not a PATH difference between the two shells. Deliberately short: perl, awk, sed and tclsh
# DO ship with Git for Windows under /usr/bin, are invisible to Get-Command, and would be false blocks.
$fragileInterpreters = @('python', 'python3', 'node')
# POSIX first path segments that are real locations under MSYS, not commands. `/c`, `/d`.. are the MSYS
# drive roots, and a single letter is always one.
$posixRoots = @(
    'dev', 'tmp', 'usr', 'bin', 'sbin', 'etc', 'var', 'proc', 'sys', 'mnt', 'opt', 'home', 'root',
    'lib', 'run', 'srv', 'cygdrive'
)
# Command heads for which MSYS argument conversion actually fires: a native Windows executable. An
# MSYS-to-MSYS call converts nothing, so restricting the check to these keeps the false-positive rate at
# zero - a quoted grep pattern starting with a slash is not touched.
$nativeHeads = @('pwsh', 'pwsh.exe', 'powershell', 'powershell.exe', 'cmd', 'cmd.exe')

$findAdvice = 'Use the Glob or Grep tool, or the project''s own catalog/index query script where it has one.'

foreach ($seg in (Split-UnquotedSegments $scanned)) {
    if ([string]::IsNullOrWhiteSpace($seg)) { continue }
    $s = $seg.Trim().TrimStart('(', '{', ' ')
    if ($s -eq '') { continue }

    $tokens = @($s -split '\s+' | Where-Object { $_ -ne '' })
    if ($tokens.Count -eq 0) { continue }

    # Skip leading env-assignments (VAR=val) and benign command prefixes.
    $i = 0
    while ($i -lt $tokens.Count -and ($tokens[$i] -match '^[A-Za-z_]\w*=' -or $prefixTokens -contains $tokens[$i])) { $i++ }
    if ($i -ge $tokens.Count) { continue }

    $rawHead = $tokens[$i]
    # A quoted token in head position is a string literal, not a path bash would exec - blocking it is
    # the over-block this guard must not commit.
    if ($rawHead.StartsWith("'") -or $rawHead.StartsWith('"')) { continue }
    $head = $rawHead.Trim('"', "'")
    if ($head -eq '') { continue }

    $rest = @(if ($i + 1 -le $tokens.Count - 1) { $tokens[($i + 1)..($tokens.Count - 1)] } else { @() })
    $headLower = $head.ToLowerInvariant()

    # ---- check 1: find
    if ($head -match '(^|[\\/])find(\.exe)?$') {
        $broad = $false
        foreach ($t in $rest) {
            $p = $t.Trim('"', "'")
            foreach ($rx in $broadRoot) { if ($p -match $rx) { $broad = $true; break } }
            if ($broad) { break }
        }
        if ($broad) {
            Deny("Blocked by sza guard-bash (canon GITHUB_INTERACTION.md section 6): find with a disk-wide root path (/, ~, drive root, /c/, //host). On Windows/MSYS an orphaned find.exe from a dropped session keeps scanning the whole disk and floods handles. $findAdvice If you truly need find, give it a concrete non-root start path AND -maxdepth N.")
        }
        if (($rest -join ' ') -notmatch '(^|\s)-maxdepth(\s|=|$)') {
            Deny("Blocked by sza guard-bash (canon GITHUB_INTERACTION.md section 6): find without -maxdepth. An unbounded find can orphan on Windows/MSYS and scan the whole disk, flooding handles. $findAdvice If you truly need find, add -maxdepth N and a concrete start path.")
        }
    }

    # ---- check 2: a .ps1 as the executable
    # An interpreter head is fine - its .ps1 is an argument, not the executable.
    if ($head -match '(?i)\.ps1$' -and $psInterpreters -notcontains $headLower) {
        Deny("Blocked by sza guard-bash (canon GITHUB_INTERACTION.md section 6): '$head' is a PowerShell script run directly as a Bash command. Bash cannot execute a .ps1 - it chokes on the BOM + '<#' block ('syntax error near unexpected token newline') and a backgrounded task still reports exit 0, so a failed build/check looks like it passed. Run it through the interpreter: pwsh -NoProfile -File $head <args>  (bare 'pwsh' resolves via the Git Bash shim; run from the repo root). To READ a .ps1, use the Read tool or put a real command first (grep/head .. $head).")
    }

    # ---- check 3: a PowerShell cmdlet as the executable
    $cm = [regex]::Match($head, '^(?<verb>[A-Z][A-Za-z]*)-(?<noun>[A-Z][A-Za-z0-9]*)$')
    if ($cm.Success -and $psVerbs -contains $cm.Groups['verb'].Value) {
        Deny("Blocked by sza guard-bash (canon GITHUB_INTERACTION.md section 6): '$head' is a PowerShell cmdlet, not a program on PATH - Bash answers 'command not found' (exit 127) and returns nothing, so the turn produces no output at all. Either use the POSIX equivalent (head/tail/sed/sort/wc/grep), or issue the WHOLE line from the PowerShell tool. A cmdlet name is fine as an argument or inside quotes; only command-head position is the trap.")
    }

    # ---- check 4: an interpreter that resolves nowhere
    # Only a bare name is judged. An explicit path is the caller's own claim about where it lives, and a
    # name that can be MADE to work (a shim onto PATH) must not be refused - so this asks the machine.
    if ($fragileInterpreters -contains $headLower -and $head -notmatch '[\\/]') {
        $resolved = $null
        try { $resolved = Get-Command -Name $head -ErrorAction SilentlyContinue } catch { $resolved = $null }
        if (-not $resolved) {
            Deny("Blocked by sza guard-bash (canon GITHUB_INTERACTION.md section 6): '$head' resolves to nothing on this machine, so Bash would answer 'command not found' (exit 127) and return no output - and no hook can fix and retry a failed command. Put a shim for it on PATH (the canon's preference: make the name work rather than guard it), call the interpreter by its full path, or use one that is installed.")
        }
    }

    # ---- check 6: MSYS argument conversion on a slash-command value
    if ($nativeHeads -contains $headLower -or $headLower -match '\.exe$') {
        foreach ($qm in [regex]::Matches($s, '(["''])(?<val>[^"'']*)\1')) {
            $val = $qm.Groups['val'].Value
            $vm = [regex]::Match($val, '^/(?<first>[A-Za-z][\w.+-]*)(\s|$)')
            if (-not $vm.Success) { continue }
            $first = $vm.Groups['first'].Value
            if ($first.Length -eq 1) { continue }                       # /c , /d - MSYS drive roots
            if ($posixRoots -contains $first.ToLowerInvariant()) { continue }
            Deny("Blocked by sza guard-bash (canon GITHUB_INTERACTION.md section 6): the argument value '$val' begins with a slash and names a command rather than a path, and MSYS rewrites it SILENTLY - '/$first ..' becomes 'C:/Program Files/Git/$first ..', exit code 0, nothing fails, and the corrupted text lands in whatever record that value was written into. Three accepted forms: double the leading slash ('//$first ..'), prefix the call with MSYS2_ARG_CONV_EXCL='*', or issue the call from the PowerShell tool.")
        }
    }
}

Allow
