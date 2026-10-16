Set-StrictMode -Version Latest

# Module-wide state. Set by Connect-IR, cleared by Disconnect-IR.
# Holds the tenant the operator is working on, its capabilities and the open case.
$script:IRContext = $null

$private = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Private') -Filter '*.ps1' -ErrorAction SilentlyContinue)
$public  = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public')  -Filter '*.ps1' -ErrorAction SilentlyContinue)

foreach ($file in @($private + $public)) {
    . $file.FullName
}

Export-ModuleMember -Function $public.BaseName
