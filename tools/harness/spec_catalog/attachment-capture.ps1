# Attachment support shared by plain and catalog-backed draft capture.
function Resolve-DraftAttachments([string] $Attach) {
    $paths = [Collections.Generic.List[string]]::new()
    foreach ($part in ($Attach -split ';')) {
        if ([string]::IsNullOrWhiteSpace($part)) { continue }
        $path = [IO.Path]::GetFullPath($part.Trim())
        if (-not [IO.File]::Exists($path)) { throw "attachment '$path' does not exist" }
        $stream = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        $stream.Dispose()
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
        [IO.File]::Copy($path, $destination, $false)
        $label = $base.Replace('\\', '\\\\').Replace('[', '\[').Replace(']', '\]')
        $url = [uri]::EscapeDataString($ticketFolder) + '/attachments/' + [uri]::EscapeDataString($name)
        $links.Add("- [$label]($url)")
    }
    return $Newline + $Newline + '**Attachments:**' + $Newline + ($links -join $Newline) + $Newline
}
