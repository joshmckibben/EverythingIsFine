function Assert-IRTenant {
    <#
    .SYNOPSIS
        Throws unless the live Graph and Exchange Online sessions both belong to the tenant
        selected with Connect-IR.
    .DESCRIPTION
        Every collector and every containment action calls this first. It is the main protection
        against acting on the wrong client tenant (stale sessions, a second terminal, a mistyped
        domain).
    #>
    [CmdletBinding()]
    param()

    if (-not $script:IRContext) {
        throw 'Not connected to a tenant. Run Connect-IR first.'
    }

    $expected = $script:IRContext.TenantId
    $label = "$($script:IRContext.PrimaryDomain) ($expected)"

    $mg = Get-MgContext
    if (-not $mg -or $mg.TenantId -ne $expected) {
        $actual = if ($mg) { $mg.TenantId } else { 'no session' }
        throw "Tenant guard: Microsoft Graph session is '$actual' but the case tenant is $label. Stopping. Run Connect-IR again."
    }

    if (-not $script:IRContext.SkipExchange) {
        $exo = @(Get-ConnectionInformation | Where-Object { $_.State -eq 'Connected' })
        if ($exo.Count -eq 0) {
            throw "Tenant guard: no Exchange Online session. Case tenant is $label. Run Connect-IR again."
        }
        $wrong = @($exo | Where-Object { $_.TenantID -ne $expected })
        if ($wrong.Count -gt 0) {
            throw "Tenant guard: an Exchange Online session belongs to tenant '$($wrong[0].TenantID)', not $label. Stopping. Run Connect-IR again."
        }
    }
}
