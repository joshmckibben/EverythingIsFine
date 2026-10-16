function Get-IRScopeSet {
    <#
    .SYNOPSIS
        Returns the Microsoft Graph delegated scopes for the requested permission tier.
    .DESCRIPTION
        ReadOnly is the default for triage and investigation. Elevated adds write scopes
        for containment and must be requested explicitly via Connect-IR -Elevated.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [switch]$Elevated
    )

    $readOnly = @(
        'Organization.Read.All'
        'Directory.Read.All'
        'User.Read.All'
        'AuditLog.Read.All'
        'Policy.Read.All'
        'UserAuthenticationMethod.Read.All'
        'Application.Read.All'
        'IdentityRiskEvent.Read.All'
        'IdentityRiskyUser.Read.All'
    )

    $write = @(
        'User.ReadWrite.All'
        'User.RevokeSessions.All'
        'UserAuthenticationMethod.ReadWrite.All'
        'Application.ReadWrite.All'
        'DelegatedPermissionGrant.ReadWrite.All'
        'Policy.ReadWrite.ConditionalAccess'
    )

    if ($Elevated) { $readOnly + $write } else { $readOnly }
}
