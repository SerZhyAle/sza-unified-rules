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
          -StaleDays (default 21) as cleanup candidates. Also every adopter repository (.sza-canon.json) with more
          than -ActiveSessions (default 5) session transcripts changed in the last -ActiveDays (default 7) days and
          no memory note in any of its project folders. Writes nothing.
  check   -Path <file>[,<file>..]
          Refuses a new project note that repeats a wider one: the same slug (file name or `name`, punctuation
          ignored) or the same first body line (20 characters or more) as a global or type note. Names that note.
          A file under the memory root is not a project note and passes.
  promote -Path <file>[,<file>..] -Scope global|type:<tag> [-Name <slug>]
          Gives a memory a wider scope. When <slug>.md does not exist at the target yet, the first -Path is moved
          there; every other -Path (or all of them, when the target exists) is retired as a duplicate. Each source
          index loses its line, the target index gains or keeps one, and the target's scope line is set.
  index   [-Folder <dir>] [-All]
          Syncs MEMORY.md with the files of a folder: keeps existing lines of present files as written, drops lines of
          missing files, appends a line for each unlisted file from its frontmatter. -All does every project folder,
          the global folder and every type folder. A new (unlisted) project note that `check` would refuse gets no
          line; the other notes are synced.
  types   [-Cwd <dir>]
          Prints the type tags that match the repository holding -Cwd (default: the current directory).

Exit: 0 on success; 1 on a usage or file error, or when check or index refuses a note. audit exits 0 even when it
finds something - it is a report.
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0, Mandatory)][ValidateSet('audit', 'check', 'promote', 'index', 'types')][string]$Command,
    [string[]]$Path,
    [string]$Scope,
    [string]$Name,
    [string]$Folder,
    [switch]$All,
    [switch]$Json,
    [double]$Threshold = 0.34,
    [int]$StaleDays = 21,
    [int]$ActiveDays = 7,
    [int]$ActiveSessions = 5,
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

# Letters and digits only, lower case: 'Never_undo - with git' and 'never-undo-with-git' are one key.
function Get-Key([string]$s) { ($s.ToLowerInvariant() -replace '[^\p{L}\p{N}]+', ' ').Trim() }

# What a note is recognised by: its slugs (file name and `name`) and its first body line.
function Get-NoteKeys([string]$file) {
    $m = Read-Memory $file
    $slugs = @(([IO.Path]::GetFileNameWithoutExtension($file)), $m.Name | ForEach-Object { Get-Key $_ } | Where-Object { $_ })
    $first = ''
    foreach ($line in ([regex]::Replace($m.Text, '(?s)\A---\r?\n.*?\r?\n---', '') -split '\r?\n')) {
        $first = Get-Key $line
        if ($first) { break }
    }
    [pscustomobject]@{ Slugs = $slugs; First = $first }
}

# The global and type notes, read once per run.
$script:wider = $null
function Get-WiderNotes {
    if ($null -ne $script:wider) { return $script:wider }
    $script:wider = @(foreach ($f in Get-AllFolders) {
            if ($f.Kind -eq 'project') { continue }
            foreach ($file in Get-MemoryFiles $f.Dir) {
                $k = Get-NoteKeys $file.FullName
                [pscustomobject]@{ Scope = $f.Label; Slug = $file.BaseName; File = $file.FullName; Slugs = $k.Slugs; First = $k.First }
            }
        })
    $script:wider
}

function Test-UnderMemoryRoot([string]$path) {
    $root = [IO.Path]::GetFullPath((Get-MemoryRoot)).TrimEnd('\', '/')
    $full = [IO.Path]::GetFullPath($path).TrimEnd('\', '/')
    $full -eq $root -or $full.StartsWith($root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
}

# The refusal text for a project note that repeats a wider one, else $null. A first line shorter than 20 characters
# ('# Notes') says nothing about the lesson.
function Find-WiderMatch([string]$file) {
    $k = Get-NoteKeys $file
    foreach ($w in Get-WiderNotes) {
        $by = if (@($k.Slugs | Where-Object { $w.Slugs -contains $_ }).Count) { 'slug' }
        elseif ($k.First.Length -ge 20 -and $k.First -eq $w.First) { 'first line' }
        if ($by) { return "refused $file - same $by as the $($w.Scope) note '$($w.Slug)' ($($w.File)); extend that note instead" }
    }
    $null
}

# Notes anywhere below a memory folder, state/ included; the indexes are not notes.
function Get-NoteCount([string]$dir) {
    if (-not (Test-Path -LiteralPath $dir)) { return 0 }
    @(Get-ChildItem -LiteralPath $dir -File -Filter '*.md' -Recurse | Where-Object Name -notin 'MEMORY.md', 'INDEX.md').Count
}

# The working directory a transcript was recorded in - the project folder name cannot be turned back into a path.
function Get-SessionDir($transcripts) {
    foreach ($t in $transcripts) {
        foreach ($line in (Get-Content -LiteralPath $t.FullName -TotalCount 50 -Encoding utf8)) {
            $m = [regex]::Match($line, '"cwd"\s*:\s*("(?:[^"\\]|\\.)*")')
            if ($m.Success) { return (ConvertFrom-Json $m.Groups[1].Value) }
        }
    }
    $null
}

function Get-EmptyAdopters {
    $projects = Join-Path (Get-ClaudeHome) 'projects'
    if (-not (Test-Path -LiteralPath $projects)) { return }
    $since = (Get-Date).AddDays(-$ActiveDays)
    $repos = @{}
    foreach ($p in Get-ChildItem -LiteralPath $projects -Directory) {
        $recent = @(Get-ChildItem -LiteralPath $p.FullName -File -Filter '*.jsonl' | Where-Object LastWriteTime -ge $since | Sort-Object LastWriteTime -Descending)
        $notes = Get-NoteCount (Join-Path $p.FullName 'memory')
        if (-not $recent.Count -and -not $notes) { continue }
        # A folder with notes and no recent session still counts for its repository.
        $all = if ($recent.Count) { $recent } else { @(Get-ChildItem -LiteralPath $p.FullName -File -Filter '*.jsonl' | Select-Object -First 3) }
        $sessionDir = Get-SessionDir ($all | Select-Object -First 3)
        if (-not $sessionDir) { continue }
        # A recorded directory on a drive that is gone must not end the report.
        $stamp = try { Find-Stamp $sessionDir } catch { $null }
        if (-not $stamp) { continue }
        $repo = Split-Path $stamp -Parent
        if (-not $repos.ContainsKey($repo)) { $repos[$repo] = [pscustomobject]@{ Repo = $repo; Sessions = 0; Notes = 0 } }
        $repos[$repo].Sessions += $recent.Count
        $repos[$repo].Notes += $notes
    }
    $repos.Values | Where-Object { $_.Notes -eq 0 -and $_.Sessions -gt $ActiveSessions } | Sort-Object Repo |
        ForEach-Object { [pscustomobject]@{ Repo = $_.Repo; Sessions = $_.Sessions } }
}

function Get-IndexLines([string]$dir) {
    $idx = Join-Path $dir 'MEMORY.md'
    if (-not (Test-Path -LiteralPath $idx)) { return , @() }
    , @([IO.File]::ReadAllLines($idx, $utf8))
}

function Get-LineTarget([string]$line) {
    $m = [regex]::Match($line, '\]\(([^)#?]+\.md)\)')
    if (-not $m.Success) { return $null }
    $raw = $m.Groups[1].Value.Trim().Replace('\', '/')
    if ($raw -match '^[a-zA-Z]+://') { return $null }
    return ($raw -replace '^\./', '')
}

function Test-NestedTarget([string]$dir, [string]$target) {
    if ($target.StartsWith('/') -or $target -match '(^|/)\.\.(/|$)') { return $false }
    $full = [IO.Path]::GetFullPath((Join-Path $dir $target))
    $rootFull = [IO.Path]::GetFullPath($dir).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if (-not $full.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)) { return $false }
    return [IO.File]::Exists($full)
}

# What an index line's target stands for in this folder: a file name or a nested path that exists, else $null. A link
# that names a file of this folder through the folder itself ('../memory/x.md', 'memory/x.md', an absolute path)
# stands for x.md, so a hand-written line is kept and the file is not listed twice.
function Resolve-LineTarget([string]$dir, [string]$target, [hashtable]$present) {
    if ($present.ContainsKey($target)) { return $target }
    $parts = $target -split '/'
    if ($parts.Count -lt 2) { return $null }
    if (Test-NestedTarget $dir $target) { return $target }
    if ($parts[-2] -eq (Split-Path $dir -Leaf) -and $present.ContainsKey($parts[-1])) { return $parts[-1] }
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
            $key = Resolve-LineTarget $dir $target $present
            if (-not $key -or $listed.ContainsKey($key)) { $dropped++; continue }
            $listed[$key] = $true
        }
        $out.Add($line)
    }
    $added = 0
    $refused = New-Object System.Collections.Generic.List[string]
    $isProject = -not (Test-UnderMemoryRoot $dir)
    foreach ($f in ($files | Sort-Object Name)) {
        if ($listed.ContainsKey($f.Name)) { continue }
        if ($isProject) {
            $why = Find-WiderMatch $f.FullName
            if ($why) { $refused.Add($why); continue }
        }
        $out.Add((New-IndexLine (Read-Memory $f.FullName))); $added++
    }
    while ($out.Count -gt 0 -and $out[$out.Count - 1] -eq '') { $out.RemoveAt($out.Count - 1) }
    if ($files.Count -gt 0 -or (Test-Path -LiteralPath (Join-Path $dir 'MEMORY.md'))) {
        [IO.File]::WriteAllText((Join-Path $dir 'MEMORY.md'), (($out -join "`n") + "`n"), $utf8)
    }
    [pscustomobject]@{ Folder = $dir; Added = $added; Dropped = $dropped; Lines = $out.Count; Refused = $refused.ToArray() }
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

$exitCode = 0
switch ($Command) {
    'check' {
        if (-not $Path) { throw 'check needs -Path' }
        foreach ($p in $Path) {
            $file = (Resolve-Path -LiteralPath $p).Path
            $why = if (-not (Test-UnderMemoryRoot $file)) { Find-WiderMatch $file }
            if ($why) { $why; $exitCode = 1 } else { "ok $file" }
        }
    }
    'index' {
        $dirs = if ($All) { (Get-AllFolders).Dir } elseif ($Folder) { @($Folder) } else { throw 'index needs -Folder <dir> or -All' }
        foreach ($d in $dirs) {
            $r = Sync-Index $d
            '{0}: +{1} -{2} ({3} lines)' -f $r.Folder, $r.Added, $r.Dropped, $r.Lines
            foreach ($why in $r.Refused) { $why; $exitCode = 1 }
        }
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
        $big = New-Object System.Collections.Generic.List[object]
        $cut = (Get-Date).AddDays(-$StaleDays)
        foreach ($f in $folders) {
            $files = Get-MemoryFiles $f.Dir
            # The index is the part every session loads (AI_USAGE.md section 4): 8,000 characters.
            $idxFile = Join-Path $f.Dir 'MEMORY.md'
            if (Test-Path -LiteralPath $idxFile) { $len = [IO.File]::ReadAllText($idxFile).Length; if ($len -gt 8000) { $big.Add([pscustomobject]@{ Folder = $f.Label; Characters = $len }) } }
            $present = @{}
            foreach ($file in $files) { $present[$file.Name] = $file }
            $listed = @{}
            $missing = @{}
            foreach ($line in (Get-IndexLines $f.Dir)) {
                $t = Get-LineTarget $line
                if (-not $t) { continue }
                $key = Resolve-LineTarget $f.Dir $t $present
                if ($key) { $listed[$key] = $true } else { $missing[$t] = $true }
            }
            foreach ($t in $missing.Keys) { $drift.Add([pscustomobject]@{ Folder = $f.Label; Issue = 'index line, no file'; File = $t }) }
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
            OverBudget = $big.ToArray()
            EmptyAdopters = @(Get-EmptyAdopters)
        }
        if ($Json) { $report | ConvertTo-Json -Depth 5; break }
        "memories: $($mems.Count) in $($folders.Count) folders (root $(Get-MemoryRoot))"
        "`nlikely duplicates across folders (word overlap >= $Threshold): $($dups.Count)"
        $report.Duplicates | ForEach-Object { '  {0:N2}  {1}  <>  {2}' -f $_.Score, $_.A, $_.B }
        "`nindex drift: $($drift.Count)"
        $drift | ForEach-Object { '  {0}: {1} - {2}' -f $_.Folder, $_.Issue, $_.File }
        "`nindexes over 8000 characters: $($big.Count)"
        $big | ForEach-Object { '  {0}: {1}' -f $_.Folder, $_.Characters }
        "`nmemories without a scope line, per folder:"
        $noScope.GetEnumerator() | Sort-Object Name | ForEach-Object { '  {0}: {1}' -f $_.Name, $_.Value }
        "`n*-state memories older than $StaleDays days (cleanup candidates):"
        $stale | ForEach-Object { '  {0}: {1}' -f $_.Folder, $_.OldStateMemories }
        "`nadopter repos with an empty memory folder and more than $ActiveSessions sessions in $ActiveDays days: $($report.EmptyAdopters.Count)"
        $report.EmptyAdopters | ForEach-Object { '  {0}: {1} sessions' -f $_.Repo, $_.Sessions }
    }
}
exit $exitCode
