function Get-SpecDeviceCheck {
    param([Parameter(Mandatory)][string] $Path)

    foreach ($line in Get-Content -LiteralPath $Path -ErrorAction Stop) {
        if ($line -cmatch '^\*\*Device check:\*\*\s*(\S.*)$') {
            $Matches[1].TrimEnd()
        }
    }
}
