@{
    RootModule           = 'EverythingIsFine.psm1'
    ModuleVersion        = '0.1.0'
    GUID                 = 'b1c73de5-cb56-4765-9677-7bb7225be460'
    Author               = 'Josh McKibben'
    Description          = 'Microsoft 365 business email compromise triage, containment and investigation toolkit.'
    CompatiblePSEditions = @('Core')
    PowerShellVersion    = '7.2'

    # Graph / EXO modules are checked at Connect-IR time rather than declared here,
    # so the module (and its tests) can load on machines without them.
    FunctionsToExport    = @(
        'Connect-IR'
        'Disconnect-IR'
        'Get-IRContext'
        'Get-IRCapability'
        'Assert-IRTenant'
        'New-IRCase'
        'Close-IRCase'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()

    PrivateData          = @{
        PSData = @{
            Tags = @('Microsoft365', 'IncidentResponse', 'BEC', 'Security')
        }
    }
}
