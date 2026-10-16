function Connect-IR {
    <#
    .SYNOPSIS
        Connects to one client tenant (Graph + Exchange Online) with the tenant guard and capability check.
    .DESCRIPTION
        1. Disconnects any existing Graph / EXO session.
        2. Signs in to Graph (interactive browser, process-scoped token cache).
        3. Verifies the requested domain or tenant ID belongs to the tenant signed in to.
        4. Pins the tenant ID on first use; refuses if the domain later resolves to another tenant.
        5. Connects Exchange Online as the same account and verifies its tenant.
        6. Detects licence capabilities and prints what the tenant can and cannot show.
    .PARAMETER Tenant
        Primary or verified domain (contoso.com) or tenant ID (GUID).
    .PARAMETER Elevated
        Requests write scopes for containment. Read-only by default.
    .PARAMETER SkipExchange
        Graph only. Most collectors need Exchange Online; use for troubleshooting.
    .EXAMPLE
        Connect-IR -Tenant contoso.com
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Tenant,

        [switch]$Elevated,

        [switch]$SkipExchange
    )

    $missing = @(Test-IRModuleDependency)
    if ($missing.Count -gt 0) {
        throw "Missing required module(s): $($missing -join ', '). Install with: Install-Module $($missing -join ', ') -Scope CurrentUser"
    }

    Disconnect-IR -Quiet

    $tier = if ($Elevated) { 'ELEVATED (read/write)' } else { 'read-only' }
    Write-IRLog -Level Info -Message "Connecting to Microsoft Graph for '$Tenant' ($tier). Sign in with this client's admin account."

    Connect-MgGraph -TenantId $Tenant -Scopes (Get-IRScopeSet -Elevated:$Elevated) -ContextScope Process -NoWelcome -ErrorAction Stop
    $mg = Get-MgContext
    $org = Get-MgOrganization -ErrorAction Stop | Select-Object -First 1

    $verifiedDomains = @($org.VerifiedDomains | ForEach-Object { $_.Name.ToLowerInvariant() })
    $primaryDomain = ($org.VerifiedDomains | Where-Object { $_.IsDefault } | Select-Object -First 1).Name.ToLowerInvariant()

    $isGuid = $null -ne ($Tenant -as [guid])
    $matchesRequest = if ($isGuid) { $mg.TenantId -eq $Tenant } else { $verifiedDomains -contains $Tenant.ToLowerInvariant() }
    if ($org.Id -ne $mg.TenantId -or -not $matchesRequest) {
        Disconnect-IR -Quiet
        throw "Tenant guard: requested '$Tenant' but signed in to '$($org.DisplayName)' ($($mg.TenantId)). Disconnected."
    }

    $pinned = Get-IRTenantProfile -PrimaryDomain $primaryDomain
    if ($pinned -and $pinned.TenantId -ne $mg.TenantId) {
        Disconnect-IR -Quiet
        throw "Tenant guard: $primaryDomain is pinned to tenant $($pinned.TenantId) but this sign-in is tenant $($mg.TenantId). Disconnected. Investigate before continuing."
    }

    $script:IRContext = [pscustomobject]@{
        TenantId      = $mg.TenantId
        PrimaryDomain = $primaryDomain
        DisplayName   = $org.DisplayName
        Account       = $mg.Account
        Elevated      = [bool]$Elevated
        SkipExchange  = [bool]$SkipExchange
        ConnectedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
        Capability    = $null
        Case          = $null
    }

    if (-not $SkipExchange) {
        Write-IRLog -Level Info -Message "Connecting to Exchange Online as $($mg.Account)."
        Connect-ExchangeOnline -UserPrincipalName $mg.Account -ShowBanner:$false -ErrorAction Stop
    }

    # Verifies the EXO session landed in the same tenant as Graph.
    try { Assert-IRTenant }
    catch { Disconnect-IR -Quiet; throw }

    Write-IRLog -Level Info -Message "Connected: $($org.DisplayName) [$primaryDomain] tenant $($mg.TenantId) as $($mg.Account)."

    $script:IRContext.Capability = Get-IRCapability
    Set-IRTenantProfile -PrimaryDomain $primaryDomain -TenantId $mg.TenantId -DisplayName $org.DisplayName -Capability $script:IRContext.Capability

    $script:IRContext
}
