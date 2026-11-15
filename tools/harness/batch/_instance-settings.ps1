# The settings of one runner instance (HARNESS-PROFILE section 3, rules 8 and 9).
#
# Dot-sourced, never invoked. Defines functions only and keeps no state.
#
# THE CHAIN. One field of the child invocation resolves, first match wins:
#   1. the pass's agent record (TASK-FLOW rule 42), when the portfolio handed one in for this invocation;
#   2. runner.instances.<instance>.<field>;
#   3. runner.<field>, which the shipped default tree declares - so a project that names no instances gets
#      exactly what it got before instances existed, and an instance absent from a non-empty map does too.
# The portfolio never writes the instance keys: its record is for one invocation and outranks both.
#
# Rule 4: a value read by a name nothing declares is an error. The shared read goes through
# Get-SzaProfileValue, which throws on an unknown path, so a field read here must be declared under
# runner in the shipped default tree (_profile.ps1); the instance and the record are read with
# Test-SzaHasProperty and never throw on an absent field.
#
# Compatible with PowerShell 5.1 and 7+, and safe to load under Set-StrictMode Latest.

. (Join-Path $PSScriptRoot '..\_profile.ps1')

function Get-SzaInstanceSetting {
    <#
    .SYNOPSIS
        One field of the child invocation, resolved record first, then the instance, then the shared value.
    .PARAMETER Field
        The field name, as it is spelled under runner (command, argsTemplate, headlessMatch,
        promptTemplate, complexityModels, effortByModel).
    .PARAMETER Instance
        The runner instance name; empty skips the instance step.
    .PARAMETER Record
        The pass's agent record, or $null.
    #>
    param(
        [Parameter(Mandatory)][string] $Field,
        [string] $Instance = '',
        $Record = $null
    )

    if ($null -ne $Record -and (Test-SzaHasProperty -Object $Record -Name $Field)) { return $Record.$Field }
    if (-not [string]::IsNullOrEmpty($Instance)) {
        $map = Get-SzaProfileValue 'runner.instances'
        if (Test-SzaHasProperty -Object $map -Name $Instance) {
            $entry = $map.$Instance
            if (Test-SzaHasProperty -Object $entry -Name $Field) { return $entry.$Field }
        }
    }
    return (Get-SzaProfileValue ("runner.{0}" -f $Field))
}

function Get-SzaComplexityModel {
    <#
    .SYNOPSIS
        The model alias a declared complexity level launches, by the same chain, or '' when the map names none.
    .DESCRIPTION
        The chain picks the map - the instance's own, else runner.complexityModels (rule 9) - and the map
        answers. The fallback is by field, not by level, as it is for effortByModel: an instance that
        carries a map owns the whole map, so a level it omits is not looked up in the shared one. A level
        the chosen map does not name answers '' and the caller treats it as no declaration, exactly as an
        unknown level always was.
    #>
    param(
        [Parameter(Mandatory)][string] $Level,
        [string] $Instance = '',
        $Record = $null
    )

    try {
        $map = Get-SzaInstanceSetting -Field 'complexityModels' -Instance $Instance -Record $Record
        if (Test-SzaHasProperty -Object $map -Name $Level) { return [string]$map.$Level }
    } catch {
        # An unreadable map is an absence, not a failure: the ticket then takes the default model.
        return ''
    }
    return ''
}
