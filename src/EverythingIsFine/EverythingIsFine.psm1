# Optional features, passed with: Import-Module ./src/EverythingIsFine/EverythingIsFine.psd1 -ArgumentList Lab
#   Lab - lab tenant seeding / cleanup (src/EverythingIsFine/Lab). Never included in the paste build.
param(
    [string[]]$Feature = @()
)

Set-StrictMode -Version Latest

# Module-wide state. Set by Connect-IR, cleared by Disconnect-IR.
# Holds the tenant the operator is working on, its capabilities and the open case.
$script:IRContext = $null

# Recorded in case.json. The paste build (tools/Build-PasteFile.ps1) sets this in its header instead.
$script:IRVersion = (Import-PowerShellDataFile (Join-Path $PSScriptRoot 'EverythingIsFine.psd1')).ModuleVersion

$private = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Private') -Filter '*.ps1' -ErrorAction SilentlyContinue)
$public  = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public')  -Filter '*.ps1' -ErrorAction SilentlyContinue)

$lab = @()
if ($Feature -contains 'Lab') {
    $lab = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Lab') -Filter '*.ps1' -ErrorAction SilentlyContinue)
}

foreach ($file in @($private + $public + $lab)) {
    . $file.FullName
}

$exports = @($public.BaseName)
if ($lab.Count -gt 0) {
    $exports += 'Enable-IRLabTenant', 'Get-IRLabState', 'Invoke-IRLabSeed', 'Invoke-IRLabCleanup'
}
Export-ModuleMember -Function $exports
