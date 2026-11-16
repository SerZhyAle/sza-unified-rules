<#
.SYNOPSIS
    One headless pass of Mistral Vibe: the pass prompt in, the agent's progress on stdout, an exit code out.

.DESCRIPTION
    Mistral Vibe ships as a VS Code extension whose only binary is `vibe-acp.exe`, an Agent Client Protocol server
    (JSON-RPC over stdio) - there is no `vibe -p`. This script is the smallest ACP client that runs one prompt to its
    end: initialize, session/new in the current directory, the approve-everything mode, the model, session/prompt, and
    an answer to every permission request, so a repository pass never waits for a click. The sign-in is Vibe's own (the
    Windows Credential Manager entry the extension made); nothing is read or passed here.

    The portfolio queue launches it as the `mistral` agent record: `pwsh -File vibe-acp-pass.ps1 -Prompt {prompt}
    -Model {model} -Thinking {effort}`, with the repository as the working directory. Its stdout is the pass log, which
    the record's limitDetector pattern is matched against.

    Exit code: 0 the turn ended; 3 the provider answered with a usage or billing limit (402, 429, "Vibe budget
    exhausted"); 4 no message from the agent for -IdleMinutes; 1 any other failure.

.PARAMETER Prompt
    The pass prompt.
.PARAMETER Model
    A value of Vibe's `model` option (`glm-5-3`, `zai-glm-5-3-flash`, ..); empty keeps the owner's default.
.PARAMETER Thinking
    `low` or `high`; anything else (`default`) keeps the owner's default.
.PARAMETER Mode
    Vibe session mode; `auto-approve` runs every tool without asking.
.PARAMETER Exe
    The vibe-acp binary; by default the newest one of an installed Mistral Vibe extension, else `vibe-acp` on PATH.
.PARAMETER IdleMinutes
    Minutes without any message from the agent before the pass is ended.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Prompt,
    [string]$Model = '',
    [string]$Thinking = '',
    [string]$Mode = 'auto-approve',
    [string]$Exe = '',
    [int]$IdleMinutes = 30
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)

$limitPattern = '(?i)budget exhausted|billing_|payment required|\b402\b|\b429\b|rate limit|usage limit|check your subscription|quota'

function Find-VibeAcp {
    if ($Exe) { return $Exe }
    if ($env:VIBE_ACP_EXE) { return $env:VIBE_ACP_EXE }
    $found = foreach ($root in @('.vscode', '.vscode-insiders')) {
        $ext = Join-Path $HOME "$root\extensions"
        if (Test-Path -LiteralPath $ext) {
            Get-ChildItem -LiteralPath $ext -Directory -Filter 'mistralai.mistral-vibe-code-*' |
                ForEach-Object { Join-Path $_.FullName 'bin\vibe-acp.exe' } | Where-Object { Test-Path -LiteralPath $_ } |
                Get-Item
        }
    }
    $best = @($found) | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
    if ($best) { return $best.FullName }
    $cmd = Get-Command vibe-acp -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    throw 'vibe-acp not found: install the Mistral Vibe extension in VS Code, or set VIBE_ACP_EXE'
}

function Write-Log([string]$Text) { [Console]::Out.WriteLine($Text); [Console]::Out.Flush() }

$cwd = (Get-Location).ProviderPath
$psi = [Diagnostics.ProcessStartInfo]::new((Find-VibeAcp))
$psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
$psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.WorkingDirectory = $cwd
$utf8 = [Text.UTF8Encoding]::new($false)
$psi.StandardInputEncoding = $utf8; $psi.StandardOutputEncoding = $utf8; $psi.StandardErrorEncoding = $utf8
$proc = [Diagnostics.Process]::Start($psi)
$stderrTask = $proc.StandardError.ReadToEndAsync()
$proc.StandardInput.NewLine = "`n"

$script:nextId = 0
$script:pending = $null
$script:agentText = [Text.StringBuilder]::new()
$script:limitText = ''

function Send-Message($Object) {
    $proc.StandardInput.WriteLine(($Object | ConvertTo-Json -Depth 30 -Compress))
    $proc.StandardInput.Flush()
}

function Show-Update($Update) {
    $kind = [string]$Update.sessionUpdate
    switch ($kind) {
        'agent_message_chunk' {
            $text = ''
            if ($Update.content -and $Update.content.PSObject.Properties['text']) { $text = [string]$Update.content.text }
            [void]$script:agentText.Append($text)
            $s = $script:agentText.ToString()
            $cut = $s.LastIndexOf("`n")
            if ($cut -ge 0) {
                Write-Log $s.Substring(0, $cut).TrimEnd("`r")
                [void]$script:agentText.Clear(); [void]$script:agentText.Append($s.Substring($cut + 1))
            }
        }
        'tool_call' { Write-Log ("[tool] {0}" -f $Update.title) }
        'tool_call_update' {
            if ($Update.PSObject.Properties['status'] -and [string]$Update.status -ceq 'failed') { Write-Log ("[tool failed] {0}" -f $Update.toolCallId) }
        }
    }
}

function Receive-Request([string]$Method, $Params, [string]$Id) {
    # The agent asks the client: only a permission request is understood, and the answer is always "allow".
    if ($Method -ceq 'session/request_permission') {
        $opts = @($Params.options)
        $pick = $opts | Where-Object { $_.kind -ceq 'allow_always' } | Select-Object -First 1
        if (-not $pick) { $pick = $opts | Where-Object { $_.kind -ceq 'allow_once' } | Select-Object -First 1 }
        if (-not $pick) { $pick = $opts | Select-Object -First 1 }
        Send-Message @{ jsonrpc = '2.0'; id = $Id; result = @{ outcome = @{ outcome = 'selected'; optionId = [string]$pick.optionId } } }
        return
    }
    Send-Message @{ jsonrpc = '2.0'; id = $Id; error = @{ code = -32601; message = "method not supported: $Method" } }
}

# One request, answered when the response with its id arrives; notifications and agent requests are served meanwhile.
function Invoke-Acp([string]$Method, $Params) {
    $script:nextId++
    $id = $script:nextId
    Send-Message @{ jsonrpc = '2.0'; id = $id; method = $Method; params = $Params }
    $idleMs = [Math]::Max(1, $IdleMinutes) * 60000
    $lastMessage = [DateTime]::UtcNow
    while ($true) {
        if (-not $script:pending) { $script:pending = $proc.StandardOutput.ReadLineAsync() }
        if (-not $script:pending.Wait(5000)) {
            if (([DateTime]::UtcNow - $lastMessage).TotalMilliseconds -gt $idleMs) { throw [TimeoutException]::new("no message from the agent for $IdleMinutes minutes") }
            continue
        }
        $line = $script:pending.Result
        $script:pending = $null
        if ($null -eq $line) { throw 'vibe-acp closed its output before answering' }
        if (-not $line.Trim()) { continue }
        $lastMessage = [DateTime]::UtcNow
        $m = $line | ConvertFrom-Json
        $has = { param($n) $m.PSObject.Properties[$n] -ne $null }
        if (& $has 'method') {
            if (& $has 'id') { Receive-Request ([string]$m.method) $m.params ([string]$m.id) }
            elseif ([string]$m.method -ceq 'session/update') { Show-Update $m.params.update }
            continue
        }
        if ((& $has 'id') -and [string]$m.id -ceq [string]$id) {
            if (& $has 'error') {
                $detail = ($m.error | ConvertTo-Json -Depth 10 -Compress)
                throw [InvalidOperationException]::new("$Method failed: $detail")
            }
            return $m.result
        }
    }
}

$exit = 0
try {
    $null = Invoke-Acp 'initialize' @{ protocolVersion = 1; clientCapabilities = @{ fs = @{ readTextFile = $false; writeTextFile = $false }; terminal = $false } }
    $session = Invoke-Acp 'session/new' @{ cwd = $cwd; mcpServers = @() }
    $sid = [string]$session.sessionId
    Write-Log "[vibe] session $sid in $cwd"
    $null = Invoke-Acp 'session/set_mode' @{ sessionId = $sid; modeId = $Mode }
    if ($Model) { $null = Invoke-Acp 'session/set_config_option' @{ sessionId = $sid; configId = 'model'; value = $Model } }
    if ($Thinking -cin @('low', 'high')) { $null = Invoke-Acp 'session/set_config_option' @{ sessionId = $sid; configId = 'thinking'; value = $Thinking } }
    $result = Invoke-Acp 'session/prompt' @{ sessionId = $sid; prompt = @(@{ type = 'text'; text = $Prompt }) }
    if ($script:agentText.Length) { Write-Log $script:agentText.ToString() }
    Write-Log "[vibe] stopReason $($result.stopReason)"
}
catch {
    $message = $_.Exception.Message
    if ($script:agentText.Length) { Write-Log $script:agentText.ToString() }
    # A limit gets its own marker line, so the record's limitDetector matches this and never a word of the agent's prose.
    if ($_.Exception -is [TimeoutException]) { $exit = 4; Write-Log "[vibe] ERROR: $message" }
    elseif ($message -match $limitPattern) { $exit = 3; Write-Log "[vibe] LIMIT reached: $message" }
    else { $exit = 1; Write-Log "[vibe] ERROR: $message" }
}
finally {
    try { $proc.StandardInput.Close() } catch { }
    if (-not $proc.WaitForExit(5000)) { try { $proc.Kill($true) } catch { } }
}
exit $exit
