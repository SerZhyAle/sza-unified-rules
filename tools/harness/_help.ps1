# _help.ps1 - the one -Help implementation of the harness entry scripts. Dot-source it (a script that loads
# _profile.ps1 gets it from there); it needs no project and no profile, so -Help works from any folder.

function Show-SzaHelp {
    <#
    .SYNOPSIS
        Print a script's header comment and its parameter syntax - the -Help switch of a harness CLI.
    #>
    param([Parameter(Mandatory)][string]$Path)
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    # The header, ahead of the first function: a block comment above param(); else a block comment further down
    # that opens with .SYNOPSIS or the script's name; else the line comments the file starts with.
    $firstFunction = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    $limit = if ($firstFunction) { $firstFunction.Extent.StartOffset } else { [int]::MaxValue }
    $paramStart = if ($ast.ParamBlock) { $ast.ParamBlock.Extent.StartOffset } else { $limit }
    $blocks = @($tokens | Where-Object { "$($_.Kind)" -eq 'Comment' -and $_.Extent.StartOffset -lt $limit -and $_.Text.StartsWith('<#') })
    $opening = '^<#\s*(\.SYNOPSIS|' + [regex]::Escape((Split-Path $Path -Leaf)) + ')'
    $block = @($blocks | Where-Object { $_.Extent.StartOffset -lt $paramStart }) + @($blocks | Where-Object { $_.Text -match $opening }) |
        Select-Object -First 1
    if ($block) {
        Write-Host (($block.Text -replace '^<#', '' -replace '#>$', '').Trim("`r", "`n"))
    }
    else {
        foreach ($t in $tokens) {
            if ("$($t.Kind)" -eq 'NewLine') { continue }
            if ("$($t.Kind)" -ne 'Comment' -or $t.Text.StartsWith('<#')) { break }
            if ($t.Text -notmatch '^#requires') { Write-Host ($t.Text -replace '^#\s?', '') }
        }
    }
    Write-Host "`nSyntax:"
    Write-Host ((Get-Command -Name $Path -Syntax | Out-String).Trim())
}
