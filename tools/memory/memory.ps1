<#
memory.ps1 - keep the agent's file memory in three scopes: one project, every project, or every project of one type.

Claude Code gives each project its own memory folder (<claude home>/projects/<project key>/memory). A lesson learned
in one project therefore stays there, and the next project learns it again - the same trap was found written down in
four projects. This script does the mechanics of a second and a third scope; which scope a lesson belongs to is the
agent's judgement, made when it writes the memory.

Layout (the memory root is SZA_MEMORY_ROOT, else <claude home>/memory; the claude home is CLAUDE_CONFIG_DIR, else
<user profile>/.claude):

  <root>/MEMORY.md                 index of the global memories - imported by the user's global CLAUDE.md, so it is
                                   in every session of every project
  <root>/<slug>.md                 one global memory
  <root>/types/<tag>/type.json     {"title": "...", "match": {"overlay": [...], "channels": [...], "site": [...],
                                   "role": [...]}} - a project matches when any listed value is in its .sza-canon.json
  <root>/types/<tag>/MEMORY.md     index of that type; the sza session-start hook injects it into a matching project
  <root>/types/<tag>/<slug>.md     one memory of that type
  <root>/.retired/<project>/       project copies replaced by a global or type memory (kept, not deleted)

Each memory carries `scope: global | type:<tag> | project` inside its metadata block.

Commands:
  audit   [-Json] [-Threshold 0.34]
          Duplicates across projects (description word overlap), index drift (a file not in its MEMORY.md, a line
          pointing at no file), memories with no scope, and per project the count of *-state memories older than
          -StaleDays (default 21) as cleanup candidates. Writes nothing.
  promote -Path <file>[,<file>..] -Scope global|type:<tag> [-Name <slug>]
          Gives a memory a wider scope. When <slug>.md does not exist at the target yet, the first -Path is moved
          there; every other -Path (or all of them, when the target exists) is retired as a duplicate. Each source
          index loses its line, the target index gains or keeps one, and the target's scope line is set.
  index   [-Folder <dir>] [-All]
          Syncs MEMORY.md with the files of a folder: keeps existing lines of present files as written, drops lines of
          missing files, appends a line for each unlisted file from its frontmatter. -All does every project folder,
          the global folder and every type folder.
  types   [-Cwd <dir>]
          Prints the type tags that match the repository holding -Cwd (default: the current directory).

Exit: 0 on success, 1 on a usage or file error. audit exits 0 even when it finds something - it is a report.
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0, Mandatory)][ValidateSet('audit', 'promote', 'index', 'types')][string]$Command,
    [string[]]$Path,
    [string]$Scope,
    [string]$Name,
    [string]$Folder,
    [switch]$All,
    [switch]$Json,
    [double]$Threshold = 0.34,
    [int]$StaleDays = 21,
    [string]$Cwd
)
$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding $false

function Get-ClaudeHome {
    if ($env:CLAUDE_CONFIG_DIR) { return $env:CLAUDE_CONFIG_DIR }
    return (Join-Path ([Environment]::GetFolderPath('UserProfile')) '.claude')
}
function Get-MemoryRoot {
    if ($env:SZA_MEMORY_ROOT) { return $env:SZA_MEMORY_ROOT }
    return (Join-Path (Get-ClaudeHome) 'memory')
}

function Read-Memory([string]$file) {
    $text = [IO.File]::ReadAllText($file, $utf8)
    $name = ''; $desc = ''; $type = ''; $scope = ''
    $m = [regex]::Match($text, '(?s)\A---\r?\n(.*?)\r?\n---')
    if ($m.Success) {
        foreach ($line in ($m.Groups[1].Value -split '\r?\n')) {
            if ($line -match '^name:\s*(.*)$') { $name = $Matches[1].Trim() }
            elseif ($line -match '^description:\s*(.*)$') { $desc = $Matches[1].Trim().Trim('"') }
            elseif ($line -match '^\s+type:\s*(.*)$') { $type = $Matches[1].Trim() }
            elseif ($line -match '^\s+scope:\s*(.*)$') { $scope = $Matches[1].Trim() }
        }
    }
    [pscustomobject]@{ File = $file; Name = $name; Description = $desc; Type = $type; Scope = $scope; Text = $text }
}

function Get-MemoryFiles([string]$dir) {
    if (-not (Test-Path -LiteralPath $dir)) { return @() }
    @(Get-ChildItem -LiteralPath $dir -File -Filter '*.md' | Where-Object Name -ne 'MEMORY.md')
}

function Get-AllFolders {
    $list = New-Object System.Collections.Generic.List[object]
    $projects = Join-Path (Get-ClaudeHome) 'projects'
    if (Test-Path -LiteralPath $projects) {
        foreach ($p in Get-ChildItem -LiteralPath $projects -Directory) {
            $m = Join-Path $p.FullName 'memory'
            if ((Get-MemoryFiles $m).Count -gt 0) { $list.Add([pscustomobject]@{ Label = $p.Name; Dir = $m; Kind = 'project' }) }
        }
    }
    $root = Get-MemoryRoot
    if (Test-Path -LiteralPath $root) { $list.Add([pscustomobject]@{ Label = 'global'; Dir = $root; Kind = 'global' }) }
    $types = Join-Path $root 'types'
    if (Test-Path -LiteralPath $types) {
        foreach ($t in Get-ChildItem -LiteralPath $types -Directory) { $list.Add([pscustomobject]@{ Label = "type:$($t.Name)"; Dir = $t.FullName; Kind = 'type' }) }
    }
    $list
}

function Get-Words([string]$s) {
    $set = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($w in [regex]::Matches($s.ToLowerInvariant(), '[\p{L}\p{N}]{4,}')) { [void]$set.Add($w.Value) }
    , $set
}

function Get-IndexLines([string]$dir) {
    $idx = Join-Path $dir 'MEMORY.md'
    if (-not (Test-Path -LiteralPath $idx)) { return , @() }
    , @([IO.File]::ReadAllLines($idx, $utf8))
}

function Get-LineTarget([string]$line) {
    $m = [regex]::Match($line, '\]\(([^)]+\.md)\)')
    if ($m.Success) { return [IO.Path]::GetFileName($m.Groups[1].Value) }
    return $null
}

function New-IndexLine($mem) {
    $title = if ($mem.Name) { $mem.Name } else { [IO.Path]::GetFileNameWithoutExtension($mem.File) }
    $hook = $mem.Description
    if ($hook.Length -gt 150) { $hook = $hook.Substring(0, 147) + '..' }
    "- [$title]($([IO.Path]::GetFileName($mem.File))) — $hook"
}

function Sync-Index([string]$dir) {
    $files = Get-MemoryFiles $dir
    $present = @{}
    foreach ($f in $files) { $present[$f.Name] = $f }
    $out = New-Object System.Collections.Generic.List[string]
    $listed = @{}
    $dropped = 0
    foreach ($line in (Get-IndexLines $dir)) {
        $target = Get-LineTarget $line
        if ($target) {
            if (-not $present.ContainsKey($target) -or $listed.ContainsKey($target)) { $dropped++; continue }
            $listed[$target] = $true
        }
        $out.Add($line)
    }
    $added = 0
    foreach ($f in ($files | Sort-Object Name)) {
        if ($listed.ContainsKey($f.Name)) { continue }
        $out.Add((New-IndexLine (Read-Memory $f.FullName))); $added++
    }
    while ($out.Count -gt 0 -and $out[$out.Count - 1] -eq '') { $out.RemoveAt($out.Count - 1) }
    if ($files.Count -gt 0 -or (Test-Path -LiteralPath (Join-Path $dir 'MEMORY.md'))) {
        [IO.File]::WriteAllText((Join-Path $dir 'MEMORY.md'), (($out -join "`n") + "`n"), $utf8)
    }
    [pscustomobject]@{ Folder = $dir; Added = $added; Dropped = $dropped; Lines = $out.Count }
}

function Set-ScopeLine([string]$file, [string]$scope) {
    $text = [IO.File]::ReadAllText($file, $utf8)
    $m = [regex]::Match($text, '(?s)\A---\r?\n(.*?)\r?\n---')
    if (-not $m.Success) { throw "no frontmatter in $file" }
    $front = $m.Groups[1].Value
    if ($front -match '(?m)^\s+scope:') { $front = [regex]::Replace($front, '(?m)^(\s+)scope:.*$', "`${1}scope: $scope") }
    elseif ($front -match '(?m)^metadata:\s*$') { $front = [regex]::Replace($front, '(?m)^metadata:\s*$', "metadata:`n  scope: $scope") }
    else { $front = $front + "`nmetadata:`n  scope: $scope" }
    $text = "---`n$front`n---" + $text.Substring($m.Length)
    [IO.File]::WriteAllText($file, $text, $utf8)
}

function Resolve-TargetDir([string]$scope) {
    $root = Get-MemoryRoot
    if ($scope -eq 'global') { return $root }
    if ($scope -match '^type:([a-z0-9-]+)$') {
        $dir = Join-Path (Join-Path $root 'types') $Matches[1]
        if (-not (Test-Path -LiteralPath (Join-Path $dir 'type.json'))) { throw "type '$($Matches[1])' has no type.json in $dir - create it first" }
        return $dir
    }
    throw "scope must be global or type:<tag>, got '$scope'"
}

function Get-ProjectLabel([string]$file) {
    $dir = Split-Path (Split-Path $file -Parent) -Parent
    Split-Path $dir -Leaf
}

function Find-Stamp([string]$start) {
    $dir = $start
    while ($dir) {
        $candidate = Join-Path $dir '.sza-canon.json'
        if (Test-Path -LiteralPath $candidate) { return $candidate }
        if (Test-Path -LiteralPath (Join-Path $dir '.git')) { return $null }
        $parent = Split-Path $dir -Parent
        if (-not $parent -or $parent -eq $dir) { return $null }
        $dir = $parent
    }
    $null
}

function Get-MatchingTypes([string]$stampFile) {
    $stamp = Get-Content -LiteralPath $stampFile -Raw | ConvertFrom-Json
    $have = @{
        overlay  = @($stamp.overlay)
        channels = @($stamp.channels)
        site     = @($stamp.site.kind)
        role     = @($stamp.role)
    }
    $types = Join-Path (Get-MemoryRoot) 'types'
    if (-not (Test-Path -LiteralPath $types)) { return @() }
    foreach ($t in Get-ChildItem -LiteralPath $types -Directory | Sort-Object Name) {
        $spec = Join-Path $t.FullName 'type.json'
        if (-not (Test-Path -LiteralPath $spec)) { continue }
        $def = Get-Content -LiteralPath $spec -Raw | ConvertFrom-Json
        $hit = $false
        foreach ($key in 'overlay', 'channels', 'site', 'role') {
            $want = @($def.match.$key)
            if ($want.Count -and @($want | Where-Object { $have[$key] -contains $_ }).Count) { $hit = $true }
        }
        if ($hit) { [pscustomobject]@{ Tag = $t.Name; Title = $def.title; Dir = $t.FullName } }
    }
}

switch ($Command) {
    'index' {
        $dirs = if ($All) { (Get-AllFolders).Dir } elseif ($Folder) { @($Folder) } else { throw 'index needs -Folder <dir> or -All' }
        foreach ($d in $dirs) { $r = Sync-Index $d; '{0}: +{1} -{2} ({3} lines)' -f $r.Folder, $r.Added, $r.Dropped, $r.Lines }
    }
    'types' {
        $start = if ($Cwd) { $Cwd } else { (Get-Location).Path }
        $stamp = Find-Stamp $start
        if (-not $stamp) { 'no .sza-canon.json above ' + $start; break }
        foreach ($t in Get-MatchingTypes $stamp) { '{0} - {1}' -f $t.Tag, $t.Title }
    }
    'promote' {
        if (-not $Path -or -not $Scope) { throw 'promote needs -Path and -Scope' }
        $targetDir = Resolve-TargetDir $Scope
        $first = (Resolve-Path -LiteralPath $Path[0]).Path
        $slug = if ($Name) { $Name } else { [IO.Path]::GetFileNameWithoutExtension($first) }
        $target = Join-Path $targetDir "$slug.md"
        $toRetire = New-Object System.Collections.Generic.List[string]
        $touched = @{}
        if (Test-Path -LiteralPath $target) {
            foreach ($p in $Path) { $toRetire.Add((Resolve-Path -LiteralPath $p).Path) }
        } else {
            Move-Item -LiteralPath $first -Destination $target
            $touched[(Split-Path $first -Parent)] = $true
            "moved   $first -> $target"
            foreach ($p in ($Path | Select-Object -Skip 1)) { $toRetire.Add((Resolve-Path -LiteralPath $p).Path) }
        }
        foreach ($src in $toRetire) {
            if ($src -eq $target) { continue }
            $bin = Join-Path (Join-Path (Get-MemoryRoot) '.retired') (Get-ProjectLabel $src)
            New-Item -ItemType Directory -Force -Path $bin | Out-Null
            Move-Item -LiteralPath $src -Destination (Join-Path $bin ([IO.Path]::GetFileName($src))) -Force
            $touched[(Split-Path $src -Parent)] = $true
            "retired $src (superseded by $slug)"
        }
        Set-ScopeLine $target $Scope
        foreach ($d in $touched.Keys) { [void](Sync-Index $d) }
        [void](Sync-Index $targetDir)
        "scope   $Scope on $target"
    }
    'audit' {
        $folders = Get-AllFolders
        $mems = New-Object System.Collections.Generic.List[object]
        $drift = New-Object System.Collections.Generic.List[object]
        $stale = New-Object System.Collections.Generic.List[object]
        $noScope = @{}
        $cut = (Get-Date).AddDays(-$StaleDays)
        foreach ($f in $folders) {
            $files = Get-MemoryFiles $f.Dir
            $listed = @{}
            foreach ($line in (Get-IndexLines $f.Dir)) { $t = Get-LineTarget $line; if ($t) { $listed[$t] = $true } }
            foreach ($t in $listed.Keys) { if (-not ($files.Name -contains $t)) { $drift.Add([pscustomobject]@{ Folder = $f.Label; Issue = 'index line, no file'; File = $t }) } }
            $old = 0
            foreach ($file in $files) {
                if (-not $listed.ContainsKey($file.Name)) { $drift.Add([pscustomobject]@{ Folder = $f.Label; Issue = 'file not in index'; File = $file.Name }) }
                $m = Read-Memory $file.FullName
                if (-not $m.Scope) { $noScope[$f.Label] = 1 + [int]$noScope[$f.Label] }
                if ($file.BaseName -match 'state$' -and $file.LastWriteTime -lt $cut) { $old++ }
                $mems.Add([pscustomobject]@{ Folder = $f.Label; Kind = $f.Kind; File = $file.Name; Words = (Get-Words "$($m.Name) $($m.Description)") })
            }
            if ($old) { $stale.Add([pscustomobject]@{ Folder = $f.Label; OldStateMemories = $old }) }
        }
        # Inverted index: word -> memories holding it, so only pairs that share a word are counted.
        $byWord = @{}
        for ($i = 0; $i -lt $mems.Count; $i++) {
            foreach ($w in $mems[$i].Words) {
                if (-not $byWord.ContainsKey($w)) { $byWord[$w] = New-Object System.Collections.Generic.List[int] }
                $byWord[$w].Add($i)
            }
        }
        $shared = @{}
        foreach ($list in $byWord.Values) {
            if ($list.Count -lt 2 -or $list.Count -gt 40) { continue }   # a word in 40+ memories says nothing
            for ($x = 0; $x -lt $list.Count; $x++) {
                for ($y = $x + 1; $y -lt $list.Count; $y++) {
                    $key = '{0},{1}' -f $list[$x], $list[$y]
                    $shared[$key] = 1 + [int]$shared[$key]
                }
            }
        }
        $dups = New-Object System.Collections.Generic.List[object]
        foreach ($kv in $shared.GetEnumerator()) {
            $ij = $kv.Key -split ','
            $a = $mems[[int]$ij[0]]; $b = $mems[[int]$ij[1]]
            if ($a.Folder -eq $b.Folder) { continue }
            $inter = [double]$kv.Value
            $score = $inter / ($a.Words.Count + $b.Words.Count - $inter)
            if ($score -ge $Threshold) { $dups.Add([pscustomobject]@{ Score = [math]::Round($score, 2); A = "$($a.Folder)/$($a.File)"; B = "$($b.Folder)/$($b.File)" }) }
        }
        $sortedDups = @($dups.ToArray() | Sort-Object -Property Score -Descending)
        $report = [pscustomobject]@{
            Folders    = $folders.Count
            Memories   = $mems.Count
            Duplicates = $sortedDups
            Drift      = $drift.ToArray()   # @() of an EMPTY generic List throws "Argument types do not match" here
            NoScope    = $noScope
            Stale      = $stale.ToArray()
        }
        if ($Json) { $report | ConvertTo-Json -Depth 5; break }
        "memories: $($mems.Count) in $($folders.Count) folders (root $(Get-MemoryRoot))"
        "`nlikely duplicates across folders (word overlap >= $Threshold): $($dups.Count)"
        $report.Duplicates | ForEach-Object { '  {0:N2}  {1}  <>  {2}' -f $_.Score, $_.A, $_.B }
        "`nindex drift: $($drift.Count)"
        $drift | ForEach-Object { '  {0}: {1} - {2}' -f $_.Folder, $_.Issue, $_.File }
        "`nmemories without a scope line, per folder:"
        $noScope.GetEnumerator() | Sort-Object Name | ForEach-Object { '  {0}: {1}' -f $_.Name, $_.Value }
        "`n*-state memories older than $StaleDays days (cleanup candidates):"
        $stale | ForEach-Object { '  {0}: {1}' -f $_.Folder, $_.OldStateMemories }
    }
}
exit 0
