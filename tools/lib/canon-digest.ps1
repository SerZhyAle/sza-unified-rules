<# canon-digest.ps1 - the RULE-DELIVERY rule 3 digest, in one place. Dot-sourced by tools/check-compliance.ps1 and by
tools/harness/portfolio/lib/health.ps1 (pq doctor). Functions only: sets no preference, prints nothing, writes nothing.
ASCII only and no API newer than .NET Framework 4.x: check-compliance.ps1 -PrintDigest also runs under Windows PowerShell 5.1.
"Text" is the file read as UTF-8 with CRLF turned into LF, so any autocrlf checkout gives the same value. #>

function Get-SzaCanonRuleDocs([string]$RulesDir) {
    # [string[]] full paths of the digest-covered rule docs, in digest order. README.md, the spread prompt and
    # contrib/ stay outside: one project's record must never mark every repo stale.
    $excluded = @('README.md', 'SPREAD_BACK_PROMPT.md')
    return @(Get-ChildItem -LiteralPath $RulesDir -Filter *.md -File | Where-Object { $excluded -notcontains $_.Name } |
            Sort-Object Name | ForEach-Object { $_.FullName })
}

function Get-SzaCanonDocText([string]$Path) { return ([System.IO.File]::ReadAllText($Path)) -replace "`r`n", "`n" }

function ConvertTo-SzaSha256Label([byte[]]$Hash) { return 'sha256:' + (($Hash | ForEach-Object { $_.ToString('x2') }) -join '') }

function Get-SzaCanonCoreDigest([string]$RulesDir) {
    # canon.coreDigest: 'sha256:<hex>' over (file name + LF + text) of every covered doc, in order.
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $buffer = New-Object System.IO.MemoryStream
        foreach ($doc in @(Get-SzaCanonRuleDocs $RulesDir)) {
            $bytes = [System.Text.Encoding]::UTF8.GetBytes([System.IO.Path]::GetFileName($doc) + "`n" + (Get-SzaCanonDocText $doc))
            $buffer.Write($bytes, 0, $bytes.Length)
        }
        $buffer.Position = 0
        return (ConvertTo-SzaSha256Label $sha.ComputeHash($buffer))
    }
    finally { $sha.Dispose() }
}

function Get-SzaCanonDocDigests([string]$RulesDir) {
    # canon.docDigests: ordered map, file name -> 'sha256:<hex>' of that doc's text alone.
    $map = [ordered]@{}
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        foreach ($doc in @(Get-SzaCanonRuleDocs $RulesDir)) {
            [byte[]]$bytes = [System.Text.Encoding]::UTF8.GetBytes((Get-SzaCanonDocText $doc))
            $map[[System.IO.Path]::GetFileName($doc)] = ConvertTo-SzaSha256Label $sha.ComputeHash($bytes)
        }
    }
    finally { $sha.Dispose() }
    return $map
}
