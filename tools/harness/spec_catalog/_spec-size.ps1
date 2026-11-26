# The size of a spec file, where the bytes are, and whether it names its evidence log. Dot-source; the functions only
# read.

# TASK-FLOW 0.53: above this size a spec enters Implemented, Verified or BlockNeedUserTest only with an evidence link.
# A function, not a variable: the file is dot-sourced inside a function too.
function Get-SpecSizeLimit { return 40960 }

function Find-SpecEvidenceLink {
    # -> the target of the first evidence link of the spec file, or '' (TASK-FLOW 0.53). A line that starts, after an
    # optional list marker and bold mark, with `Evidence:` and holds a Markdown link to an existing file under the
    # ticket's own evidence/ folder - the folder beside the spec that carries the spec file's name (rules 19 and 70).
    # The target is relative to the spec file; a rooted path, a URL and a path holding '..' are none. A line inside a
    # fenced code block is text.
    param([Parameter(Mandatory)][string] $Path)

    $full = [IO.Path]::GetFullPath($Path)
    $dir = [IO.Path]::GetDirectoryName($full)
    $under = [IO.Path]::GetFileNameWithoutExtension($full) + '/evidence/'
    $fence = ''
    foreach ($line in [IO.File]::ReadAllLines($full)) {
        if ($line -match '^\s*(`{3,}|~{3,})') {
            $mark = $Matches[1]
            if (-not $fence) { $fence = $mark }
            elseif ($mark[0] -eq $fence[0] -and $mark.Length -ge $fence.Length) { $fence = '' }
            continue
        }
        if ($fence -or $line -notmatch '^\s*(?:(?:\d+\.|[-*+])\s+)?(?:\*\*|__)?Evidence:') { continue }
        foreach ($m in [regex]::Matches($line, '\[[^\]]*\]\(\s*<?([^()<>\s]+)>?(?:\s+"[^"]*")?\s*\)')) {
            $target = $m.Groups[1].Value
            $relative = (($target -split '#')[0] -replace '\\', '/') -replace '^(\./)+', ''
            if ($relative.Contains('..') -or -not $relative.StartsWith($under, [StringComparison]::OrdinalIgnoreCase)) { continue }
            if (Test-Path -LiteralPath (Join-Path $dir $relative) -PathType Leaf) { return $target }
        }
    }
    return ''
}

function Get-SpecSizeReport {
    # -> Bytes (the file) and Sections (heading, bytes), largest first. A section runs from a level-1 or level-2
    # heading to the next one; the lines above the first level-2 heading belong to the heading that opens them, or
    # to '(header)'. A heading inside a fenced code block is text. Section bytes are UTF-8 bytes with line ends.
    param([Parameter(Mandatory)][string] $Path)

    $raw = [IO.File]::ReadAllBytes($Path)
    $text = [Text.Encoding]::UTF8.GetString($raw).TrimStart([char]0xFEFF)
    $sections = [Collections.Generic.List[object]]::new()
    $heading = '(header)'
    $bytes = 0
    $fence = ''
    foreach ($m in [regex]::Matches($text, '[^\n]*\n|[^\n]+$')) {
        $line = $m.Value
        if ($line -match '^\s*(`{3,}|~{3,})') {
            $mark = $Matches[1]
            if (-not $fence) { $fence = $mark }
            elseif ($mark[0] -eq $fence[0] -and $mark.Length -ge $fence.Length) { $fence = '' }
        }
        elseif (-not $fence -and $line -match '^#{1,2}\s+\S') {
            if ($bytes -gt 0) { $sections.Add([pscustomobject]@{ Heading = $heading; Bytes = $bytes }) }
            $heading = $line.Trim()
            $bytes = 0
        }
        $bytes += [Text.Encoding]::UTF8.GetByteCount($line)
    }
    if ($bytes -gt 0) { $sections.Add([pscustomobject]@{ Heading = $heading; Bytes = $bytes }) }
    return [pscustomobject]@{
        Bytes    = $raw.Length
        Sections = @($sections | Sort-Object -Property Bytes -Descending -Stable)
    }
}
