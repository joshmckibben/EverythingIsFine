function Get-IRCapability {
    <#
    .SYNOPSIS
        Detects what the connected tenant's licensing and configuration let us see.
    .DESCRIPTION
        Reads subscribed SKUs and their enabled service plans, derives capability flags,
        and checks that unified audit log ingestion is on. Prints a summary unless -Quiet.
    #>
    [CmdletBinding()]
    param(
        [switch]$Quiet
    )

    Assert-IRTenant

    $skus = @(Get-MgSubscribedSku -All | Where-Object { $_.CapabilityStatus -eq 'Enabled' })
    $plans = @(
        $skus |
            ForEach-Object { $_.ServicePlans } |
            Where-Object { $_.ProvisioningStatus -eq 'Success' } |
            ForEach-Object { $_.ServicePlanName } |
            Sort-Object -Unique
    )

    $cap = ConvertTo-IRCapability -ServicePlanName $plans -SkuPartNumber @($skus | ForEach-Object { $_.SkuPartNumber })

    if (-not $script:IRContext.SkipExchange) {
        try {
            # Must run in Exchange Online PowerShell; Security & Compliance PowerShell reports False.
            $cap.UnifiedAuditLogEnabled = [bool](Get-AdminAuditLogConfig -ErrorAction Stop).UnifiedAuditLogIngestionEnabled
        }
        catch {
            Write-IRLog -Level Warn -Message "Could not read audit log config: $($_.Exception.Message)"
        }
    }

    if (-not $Quiet) { Show-IRCapability -Capability $cap }
    $cap
}

function Show-IRCapability {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Capability
    )

    $mark = { param($v) if ($null -eq $v) { '?' } elseif ($v) { 'yes' } else { 'NO' } }

    Write-IRLog -Level Info -Message "Licences: $($Capability.SkuPartNumbers -join ', ')"
    $rows = @(
        @{ Name = 'Unified audit log ingestion'; Value = $Capability.UnifiedAuditLogEnabled; Fallback = 'NONE - no audit history. Critical finding.' }
        @{ Name = 'Sign-in logs via Graph (P1)'; Value = $Capability.SignInLogsViaGraph;     Fallback = 'Using UAL UserLoggedIn events (less detail).' }
        @{ Name = 'Conditional Access (P1)';     Value = $Capability.ConditionalAccess;      Fallback = 'Containment uses per-user block + session revoke.' }
        @{ Name = 'Identity Protection (P2)';    Value = $Capability.IdentityProtectionRisk; Fallback = 'Using toolkit heuristics instead of risk scores.' }
        @{ Name = 'Threat Explorer (MDO P2)';    Value = $Capability.ThreatExplorer;         Fallback = 'Using message trace.' }
        @{ Name = 'Audit (Premium)';             Value = $Capability.AuditPremium;           Fallback = 'Audit Standard retention (180 days).' }
    )

    foreach ($row in $rows) {
        $state = & $mark $row.Value
        $level = if ($row.Value) { 'Info' } elseif ($row.Name -like 'Unified audit*' -and $row.Value -eq $false) { 'Error' } else { 'Warn' }
        $message = "{0,-30} {1,-4}" -f $row.Name, $state
        if (-not $row.Value) { $message += "  -> $($row.Fallback)" }
        Write-IRLog -Level $level -Message $message
    }
}
