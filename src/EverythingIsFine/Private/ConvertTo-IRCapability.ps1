function ConvertTo-IRCapability {
    <#
    .SYNOPSIS
        Derives capability flags from the tenant's enabled service plan names.
    .DESCRIPTION
        Pure function (no API calls) so the licence logic can be unit tested.
        Service plan names should be re-verified against real tenants of each tier (see DESIGN.md section 6).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$ServicePlanName,

        [AllowEmptyCollection()]
        [string[]]$SkuPartNumber = @()
    )

    $plans = [System.Collections.Generic.HashSet[string]]::new([string[]]$ServicePlanName, [System.StringComparer]::OrdinalIgnoreCase)

    $entraP2 = $plans.Contains('AAD_PREMIUM_P2')
    $entraP1 = $entraP2 -or $plans.Contains('AAD_PREMIUM')
    $mdoP2   = $plans.Contains('THREAT_INTELLIGENCE')
    $mdoP1   = $mdoP2 -or $plans.Contains('ATP_ENTERPRISE')

    [pscustomobject]@{
        SkuPartNumbers         = @($SkuPartNumber | Sort-Object -Unique)
        ExchangeOnline         = $plans.Contains('EXCHANGE_S_STANDARD') -or $plans.Contains('EXCHANGE_S_ENTERPRISE')
        EntraP1                = $entraP1
        EntraP2                = $entraP2
        DefenderForOfficeP1    = $mdoP1
        DefenderForOfficeP2    = $mdoP2
        AuditPremium           = $plans.Contains('M365_ADVANCED_AUDITING')

        # Derived: which data paths collectors may use.
        SignInLogsViaGraph     = $entraP1
        ConditionalAccess      = $entraP1
        IdentityProtectionRisk = $entraP2
        ThreatExplorer         = $mdoP2

        # Filled in by Get-IRCapability from live checks; $null = not checked / unknown.
        UnifiedAuditLogEnabled = $null
    }
}
