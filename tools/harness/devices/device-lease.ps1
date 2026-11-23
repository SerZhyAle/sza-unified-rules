#requires -Version 7.0
<#
.SYNOPSIS
    Take, hold and give back a lease on a test target - a phone, a watch or an emulator - for the whole machine.

.DESCRIPTION
    Two sessions on one machine share the adb server, the attached devices and the emulator ports, whatever project each
    works in, and `adb devices` reports a target as online whether or not somebody is mid-run on it. A lease marks it as
    driven by one session, so a sibling is told to take a different target instead of replacing the APK, switching HOME or
    taking over the UI under a running scenario.

    The key is a plain name and nothing here talks to adb: an adb serial for a physical target (every serial it answers
    under - USB and wireless are two), avd:<name> for an emulator, claimed before the process starts. The store is outside
    every repository (<portfolio root>\devices, see _device-lease.ps1), so a session in one project sees the lease of a
    session in another. There is NO queue: a sibling's scenario has no bound, so a lost claim means a different target or a
    deferred device stage, never a wait. The lease is advisory; it coordinates consenting callers and does not stop a raw
    `adb` command.

.PARAMETER Verb
    Claim   - take the target. Atomic; idempotent for a lease this session already owns. Several keys are taken all or
              none; with -Any the first free key is taken.
    Release - give it back. Owner-checked: a lease of a live foreign session is refused. -All gives back every lease of
              this session.
    List    - the keys of the live leases, one per line (or a JSON array under -Json).
    Status  - who holds what: key, session, project, last activity, reason.
    Sweep   - drop stale leases and report which went.

.PARAMETER Id
    The key or keys, comma separated: emulator-5554, RFCR110NBQJ, 192.168.1.5:5555, avd:Pixel_9.

.PARAMETER Any
    Claim only. Take the first key of -Id that is free; exit 3 when every one is held.

.PARAMETER All
    Release only. Give back every lease this session holds.

.PARAMETER Reason
    Free text kept in the lease and shown by Status; name the scenario or the ticket.

.PARAMETER Json
    Print the machine-readable result instead of the text.

.EXAMPLE
    pwsh -NoProfile -File <harness>/devices/device-lease.ps1 -Verb Claim -Id avd:Pixel_9 -Reason "ticket 123 UI pass"
    Takes the Pixel_9 emulator before it is started. Exit 0 when taken, 3 when a live sibling got there first.

.EXAMPLE
    pwsh -NoProfile -File <harness>/devices/device-lease.ps1 -Verb Claim -Id avd:Pixel_9,avd:Pixel_6 -Any
    Takes whichever of the two emulators is free.

.EXAMPLE
    pwsh -NoProfile -File <harness>/devices/device-lease.ps1 -Verb Release -All
    Gives back everything this session holds; run it when the scenario ends, also on the failure path.

.NOTES
    Exit codes: 0 done (claimed, released, listed or swept); 1 error (bad key, missing argument, the store cannot be
    reached); 3 claim lost - a live foreign session holds a requested target; 4 release refused - a live foreign
    session owns a requested lease.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Claim', 'Release', 'List', 'Status', 'Sweep')][string]$Verb,
    [string[]]$Id,
    [switch]$Any,
    [switch]$All,
    [string]$Reason = 'device-lease',
    [switch]$Json
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)

. (Join-Path $PSScriptRoot '_device-lease.ps1')

try {
    $result = Invoke-DeviceLease -Verb $Verb -Id $Id -Any:$Any -All:$All -Reason $Reason
}
catch {
    [Console]::Error.WriteLine("device-lease: $($_.Exception.Message)")
    exit 1
}

if ($Json) {
    if ($null -eq $result.Data) { [pscustomobject]@{ outcome = $result.Outcome; message = $result.Text } | ConvertTo-Json -Compress }
    elseif ($Verb -in @('List', 'Status')) { ConvertTo-Json -InputObject @($result.Data) -Depth 4 -Compress }
    else { $result.Data | ConvertTo-Json -Depth 4 -Compress }
}
elseif ($result.Text) { Write-Output $result.Text }
exit $result.Exit
