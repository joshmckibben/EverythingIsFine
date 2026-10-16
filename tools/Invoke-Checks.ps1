#Requires -Version 7.2
<#
.SYNOPSIS
    Rebuilds dist/EverythingIsFine.ps1, then runs PSScriptAnalyzer and the Pester suite.
    Exits non-zero on any failure. CI runs this on Windows and Linux for every push.
.EXAMPLE
    ./tools/Invoke-Checks.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
# $PSScriptRoot is empty when the script is run without a file behind it
# (F8 / Run Selection in VS Code or ISE, pasted into a console, Invoke-Expression).
# Fall back to the current folder in that case.
$repo = if ($PSScriptRoot) { Split-Path $PSScriptRoot -Parent } else { (Get-Location).Path }
if (-not (Test-Path -LiteralPath (Join-Path $repo 'src' 'EverythingIsFine' 'EverythingIsFine.psd1'))) {
    throw "Can't find the EverythingIsFine repo at '$repo'. From the repo root, run: pwsh ./tools/Invoke-Checks.ps1"
}

foreach ($module in @{ Name = 'Pester'; Min = '5.5.0' }, @{ Name = 'PSScriptAnalyzer'; Min = '1.21.0' }) {
    if (-not (Get-Module -ListAvailable $module.Name | Where-Object Version -ge $module.Min)) {
        Write-Host "Installing $($module.Name)..." -ForegroundColor Yellow
        Install-Module $module.Name -MinimumVersion $module.Min -Scope CurrentUser -Force -SkipPublisherCheck
    }
}

Write-Host "`n== Paste build ==" -ForegroundColor Cyan
& (Join-Path $repo 'tools' 'Build-PasteFile.ps1')

Write-Host "`n== PSScriptAnalyzer ==" -ForegroundColor Cyan
$issues = Invoke-ScriptAnalyzer -Path (Join-Path $repo 'src') -Recurse -Settings (Join-Path $repo 'PSScriptAnalyzerSettings.psd1')
if ($issues) {
    $issues | Format-Table RuleName, Severity, ScriptName, Line, Message -AutoSize -Wrap
} else {
    Write-Host 'No issues.' -ForegroundColor Green
}

Write-Host "`n== Pester ==" -ForegroundColor Cyan
$config = New-PesterConfiguration
$config.Run.Path = Join-Path $repo 'tests'
$config.Run.PassThru = $true
$config.Output.Verbosity = 'Detailed'
$result = Invoke-Pester -Configuration $config

if ($issues -or $result.FailedCount -gt 0) { exit 1 }
