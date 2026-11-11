# Attachment support shared by plain and catalog-backed draft capture.
function Resolve-DraftAttachments([string] $Attach) {
    $paths = [Collections.Generic.List[string]]::new()
    foreach ($part in ($Attach -split ';')) {
        if ([string]::IsNullOrWhiteSpace($part)) { continue }
        $path = [IO.Path]::GetFullPath($part.Trim())
        if ([IO.Directory]::Exists($path)) { throw "attachment '$path' is a folder; attach the files inside it" }
        if (-not [IO.File]::Exists($path)) { throw "attachment '$path' does not exist" }
        foreach ($seen in $paths) {
            if ([string]::Equals($seen, $path, [StringComparison]::OrdinalIgnoreCase)) { throw "attachment '$path' is given twice" }
        }
        try {
            $stream = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
            $stream.Dispose()
        }
        catch { throw "attachment '$path' cannot be read: $($_.Exception.Message)" }
        $paths.Add($path)
    }
    return $paths.ToArray()
}

function Copy-DraftAttachments([string[]] $Paths, [string] $SpecPath, [string] $Newline) {
    if (-not $Paths.Count) { return '' }
    $parent = [IO.Path]::GetDirectoryName($SpecPath)
    $ticketFolder = [IO.Path]::GetFileNameWithoutExtension($SpecPath)
    $dir = Join-Path (Join-Path $parent $ticketFolder) 'attachments'
    [IO.Directory]::CreateDirectory($dir) | Out-Null
    $links = [Collections.Generic.List[string]]::new()
    foreach ($path in $Paths) {
        $base = [IO.Path]::GetFileName($path)
        $n = 1
        do {
            $name = '{0:D2}__{1}' -f $n, $base
            $destination = Join-Path $dir $name
            $n++
        } while ([IO.File]::Exists($destination))
        try { [IO.File]::Copy($path, $destination, $false) }
        catch { throw "could not copy '$path' to '$destination': $($_.Exception.Message)" }
        $label = $base.Replace('\', '\\').Replace('[', '\[').Replace(']', '\]')
        $url = [uri]::EscapeDataString($ticketFolder) + '/attachments/' + [uri]::EscapeDataString($name)
        $links.Add("- [$label]($url)")
    }
    return $Newline + $Newline + '**Attachments:**' + $Newline + ($links -join $Newline) + $Newline
}

# A project-owned capture script that takes no -Attach: the ticket it wrote gets the files afterwards, linked right
# after the first verbatim copy of the request text, so the text itself is never touched.
function Add-DraftAttachmentLinks([string[]] $Paths, [string] $SpecPath, [string] $RequestText) {
    if (-not $Paths.Count) { return }
    if (-not [IO.File]::Exists($SpecPath)) { throw "the spec file $SpecPath does not exist" }
    $body = [IO.File]::ReadAllText($SpecPath, [Text.Encoding]::UTF8)
    $request = $RequestText.TrimEnd()
    $at = if ($request) { $body.IndexOf($request, [StringComparison]::Ordinal) } else { -1 }
    if ($at -lt 0) { throw "the request text was not found verbatim in $SpecPath, so the links have no place in section 0" }
    $eol = if ($body.Contains("`r`n")) { "`r`n" } else { "`n" }
    $block = Copy-DraftAttachments -Paths $Paths -SpecPath $SpecPath -Newline $eol
    $end = $at + $request.Length
    [IO.File]::WriteAllText($SpecPath, $body.Substring(0, $end) + $block.TrimEnd() + $body.Substring($end), [Text.UTF8Encoding]::new($false))
}
