---
name: device-lease
description: Take a lease on an Android phone, watch or emulator before touching it, so that two sessions - above all two sessions in different projects - never drive the same target at once; see who holds what, pick a free target, hand it back. Use before any adb install, launch, input, settings change, reboot or emulator start, before a device or emulator test pass, when the emulator or the phone is busy, when adb shows a device someone else may be using, or when a UI drive suddenly shows another app. Also on the Russian phrasings - "эмулятор занят", "устройство занято", "подключённый телефон", "не мешай другой сессии", "параллельные сеансы на одном устройстве", "возьми устройство", "поделить эмулятор между проектами", "кто сидит на эмуляторе".
---

# Device lease - one target, one session, the whole machine

Sessions of different projects share one adb server, the same attached phones and watch, and the same emulator ports.
`adb devices` says a target is online whether or not somebody is mid-run on it, so without a claim the collision is found
by breaking something: a sibling's APK replaced, its HOME switched, a running scenario taken over, and a false FAIL
written down by both sides. A lease says "this session is driving this target"; it lives in the portfolio root, outside
every repository, so a session in one project sees the lease of a session in another.

The rule is [TESTING_AND_QA.md](../../rules/TESTING_AND_QA.md) section 4; this skill is the procedure.

## Step 0 - Resolve the plugin root

The same resolution as [spec-all](../spec-all/SKILL.md) Step 0: print the resolved path and paste it literally. The tool is
a script, not a command on the path, and it runs from any folder:

```powershell
pwsh -NoProfile -File "<root>/tools/harness/devices/device-lease.ps1" -Verb <Claim|Release|List|Status|Sweep> <arguments>
```

## Step 1 - Look, then choose

Reading needs no claim. Run `adb devices` and `device-lease.ps1 -Verb Status` (who holds what: key, session, project, last
activity, reason). A target with no lease is not proof it is free - the lease is advisory, and a session that never
claimed leaves nothing: read what it is showing before the first touch, and leave it if a scenario is on the screen.

## Step 2 - Claim before the first touch

A touch is anything that changes the target or what it shows: install, uninstall, launch, input, a settings or density
change, clearing app data, `logcat -c`, a reboot, a port forward, starting or killing an emulator.

| You need | Claim |
| --- | --- |
| one named phone or watch | `-Verb Claim -Id <adb serial> -Reason "<ticket, scenario>"` |
| a phone or watch that answers under two serials (USB and wireless) | `-Id <serial one>,<serial two>` - all or none |
| any free emulator of a list | `-Id avd:<name one>,avd:<name two> -Any` - the first free one; read `id` of the answer |
| a running emulator you found | its AVD name first: `adb -s <serial> emu avd name` (the first line), then `-Id avd:<name>` |

The key of an emulator is `avd:<name>`, claimed **before** the process starts: its serial is a port and the port moves, and
the AVD name is what stays. Start the emulator only after the claim, keep the PID from the start call, stop that one and no
other. A key is a plain name (letters, digits, `.` `_` `:` `-`); nothing here talks to adb.

## Step 3 - Read the exit code

| Exit | Meaning | You do |
| --- | --- | --- |
| 0 | claimed, or already yours | go on; a repeated claim is harmless and counts as a sign of life |
| 3 | a live session of another project or ticket holds it | take a different target, or defer the device stage and do the work that needs no target first (build, static checks, specs); **never wait for it, poll it, or touch it** |
| 1 | a bad key, or the store cannot be reached | fix the call; the message says which |
| 4 | a release was refused - a live session owns that lease | leave it; it is not yours to give back |

A lost claim names the holder: session, project, last activity, reason. If the owner needs to know, say it in the answer;
do not delete the lease file. A lease whose session went quiet, or that outlived its ceiling, is swept by whoever reads
next; the numbers live in the `Device` row of `Get-AgentLockTimings` in `tools/harness/locks/agent-lock.ps1` and nowhere
else. A run longer than that claims again at each stage.

## Step 4 - Leave it as you found it, then release

Put back what the scenario changed - font scale, density, locale, orientation, permissions, the app's own data - or write
what is left behind into the ticket. Then, on the success path and on the failure path alike:

```powershell
pwsh -NoProfile -File "<root>/tools/harness/devices/device-lease.ps1" -Verb Release -All
```

`-All` gives back every lease of this session and no other. Release at the end of the scenario, not at the end of the
task: the research, the spec and the gates need no target, and everyone behind you waits for as long as you hold it.

## Subagents

A subagent shares its parent's session id, so the same claim answers "already mine" and it never needs a second target.
It must not release what the parent took. A subagent that must drive a device is handed the parent's target; one that does
not has no use for MCP or adb tools at all ([AI_USAGE.md](../../rules/AI_USAGE.md) section 3).

## What this does not do

- It does not stop a raw `adb` command. It coordinates sessions that claim.
- It has no queue. A sibling's scenario has no bound, so a wait would not end.
- It does not decide which device a product may use. The product's own device roster is that authority (the shared
  `TEST-LAB-ANDROID` profile names the fleet), and a lease grants no right to install, clear or reconfigure a target.
- A project that keeps its own repository-local lease script keeps using it for its own sessions - and claims here as well,
  until that script forwards to this tool; otherwise its lease is invisible to every other project.
