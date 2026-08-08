#Requires -Version 5.1
<#
.SYNOPSIS
    Validates the syntax of wsl-safe-backup-restore.ps1 without executing it.
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validate-ps1.ps1
#>
$ErrorActionPreference = "Stop"

$Target = Join-Path $PSScriptRoot "..\wsl-safe-backup-restore.ps1"

if (!(Test-Path -LiteralPath $Target -PathType Leaf)) {
    Write-Host "[FAIL] Script not found: $Target" -ForegroundColor Red
    exit 1
}

$ErrorList = $null
$TokenList = $null

[System.Management.Automation.Language.Parser]::ParseFile(
    (Resolve-Path -LiteralPath $Target),
    [ref]$TokenList,
    [ref]$ErrorList
) | Out-Null

if ($ErrorList.Count -gt 0) {
    Write-Host "[FAIL] PowerShell syntax errors in $Target" -ForegroundColor Red
    foreach ($Item in $ErrorList) {
        Write-Host (
            "  Line {0}, Col {1}: {2}" -f
            $Item.Extent.StartLineNumber,
            $Item.Extent.StartColumnNumber,
            $Item.Message
        ) -ForegroundColor Red
    }
    exit 1
}

Write-Host "[OK] PowerShell syntax valid." -ForegroundColor Green
exit 0
