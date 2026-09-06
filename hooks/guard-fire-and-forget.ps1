<#
guard-fire-and-forget.ps1 - Claude Code PreToolUse hook (matcher: Bash), shipped by the sza plugin.

Blocks backgrounding a SHORT, VERDICT-BEARING command - a gate, a closure facade, a catalog mutator.
These finish far inside the harness's foreground timeout and their whole product is an exit code, so
dispatching one asynchronously is never an optimisation:

  - It does not save a turn, it ADDS one. The harness re-invokes the agent when the job finishes, and
    the agent that cannot wait quietly then hand-polls with cat/sleep. Measured on the reference
    corpus: ~1,297 polling turns and 81 minutes of literal sleep in a single month.
  - It converts a gate into an ungated rule. A check whose exit code nobody reads is not a check.
    Gated rules hold at ~99% in the reference measurement, ungated ones at 1-8%.
  - A backgrounded task's reported exit code is frequently the wrapper's, not the command's, so the
    failure mode is a false PASS - the same trap guard-ps1-in-bash exists for.

Canon home: AI_USAGE.md section 1, the foreground/background threshold bullet ("below it, backgrounding
is forbidden"). This hook is that sentence made mechanical.

Scope is deliberately a LITERAL deny-list, not a heuristic. A guard that over-blocks gets switched off
and then nothing is enforced, so the list names command shapes whose foreground cost is measured and
whose verdict is the point. A repository that does not have these commands cannot match them, which is
why shipping the reference repo's fast targets here is safe rather than parochial.

Override: if the same command line also carries a genuine long job (a gradle/maven/build invocation,
the full unit suite), backgrounding is REQUIRED by the same canon bullet and the call passes. A chained
long job dominates the pair.

Escape hatch: SZA_HOOKS_OFF=1.

Contract:
  exit 2 = block the tool call (stderr is shown to Claude)
  exit 0 = allow
Fail-open on any parse error so a malformed payload never breaks Bash globally.

Exit codes (DEVELOPMENT.md section 15, reachable-exit-code contract):
  0  allow - not a background call, no verdict-bearing command, a long job dominates, or unjudgeable.
  2  block - a short verdict-bearing command dispatched with run_in_background.
#>

function Allow { exit 0 }
function Deny([string]$msg) { [Console]::Error.WriteLine($msg); exit 2 }

if ($env:SZA_HOOKS_OFF -in @('1', 'true', 'TRUE')) { Allow }

try {
    $raw = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($raw)) { Allow }
    $payload = $raw | ConvertFrom-Json
    $bg = $payload.tool_input.run_in_background
    $cmd = [string]($payload.tool_input.command)
} catch {
    # Never break Bash on a malformed hook payload.
    Allow
}

# The field is absent on an ordinary foreground call and may be present-but-false; only true matters.
if ($bg -isnot [bool] -or -not $bg) { Allow }
if ([string]::IsNullOrWhiteSpace($cmd)) { Allow }

# A real long job on the same line makes backgrounding mandatory, not forbidden - it wins outright.
$longJob = @(
    '\bgradlew(\.bat)?\b'
    '\b(assemble|bundle|install)[A-Za-z]*(Debug|Release)\b'
    '\bmvn\b'
    '\bmsbuild\b'
    '\bdocker\s+(build|compose)\b'
    '\ba\.ps1\s+(d|db|dav|cd|nd|nl|r|fu)\b'
)
foreach ($pattern in $longJob) { if ($cmd -match "(?i)$pattern") { Allow } }

# Verdict-bearing shapes: the exit code IS the product, and each measured well inside the foreground
# timeout on the reference machine (fast gates 18.9 s, detekt gate 20.3 s, catalog CLI sub-second).
$verdictBearing = @(
    @{ Pattern = '\bpost-change\.ps1\b';                                    What = 'the closure facade' }
    @{ Pattern = '\bclose-and-log\.ps1\b';                                  What = 'the closure facade' }
    @{ Pattern = '\bassert-[A-Za-z0-9_.-]+\.ps1\b';                         What = 'a quality gate' }
    @{ Pattern = '\bcheck-compliance\.ps1\b';                               What = 'a compliance gate' }
    @{ Pattern = '\bsmoke-[A-Za-z0-9_.-]+\.ps1\b';                          What = 'a smoke test' }
    @{ Pattern = '[\\/](spec_catalog|document_registry|all_features)[\\/]'; What = 'a catalog mutator or query' }
    @{ Pattern = '\badd_to_dev_log\.ps1\b';                                 What = 'a journal mutator' }
    @{ Pattern = '\bcatalog_sync\.ps1\b';                                   What = 'an index rebuild' }
    @{ Pattern = '\ba\.ps1\s+(fk|fkn|fc|fr|fg|dq|ch|ss|bf|fw|fwr|fwu)\b';  What = 'a fast check' }
)

foreach ($entry in $verdictBearing) {
    if ($cmd -match ("(?i)" + $entry.Pattern)) {
        Deny(
            "Blocked by sza guard-fire-and-forget (canon AI_USAGE.md section 1): this is " + $entry.What +
            " dispatched with run_in_background. Below the harness's foreground timeout, backgrounding is " +
            "forbidden - it does not save a turn, it adds one (the completion notification re-invokes the " +
            "agent, and hand-polling with cat/sleep follows), and a verdict nobody reads in the same turn " +
            "is not a verdict: a gate whose exit code is never checked has become an ungated rule, which " +
            "holds at 1-8% instead of ~99%. Re-run it in the FOREGROUND and read its exit code and output " +
            "now. If this call genuinely exceeds the foreground timeout, run the long job itself in the " +
            "background and close with the gate afterwards, in the foreground."
        )
    }
}

Allow
