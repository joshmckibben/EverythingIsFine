# Lab feature: guards that stop seeding / cleanup from ever running against a real client tenant.
# Loaded only with: Import-Module ./src/EverythingIsFine/EverythingIsFine.psd1 -ArgumentList Lab

$script:IRLabMarkerName = 'EIF-LAB-MARKER'
$script:IRLabTag = 'EIF-LAB'
$script:IRLabMaxUsers = 50

function Test-IRLabModuleDependency {
    <#
    .SYNOPSIS
        Throws with an install hint if the extra Graph modules the lab tools use are missing.
    #>
    [CmdletBinding()]
    param()

    $missing = @('Microsoft.Graph.Applications', 'Microsoft.Graph.Identity.SignIns') |
        Where-Object { -not (Get-Module -ListAvailable -Name $_) }
    if ($missing.Count -gt 0) {
        throw "Lab tools need: $($missing -join ', '). Install with: Install-Module $($missing -join ', ') -Scope CurrentUser"
    }
}

function Get-IRLabUserCount {
    [CmdletBinding()]
    [OutputType([int])]
    param()

    $count = 0
    Get-MgUser -Top 1 -ConsistencyLevel eventual -CountVariable count -ErrorAction Stop | Out-Null
    [int]$count
}

function Get-IRLabMarker {
    <#
    .SYNOPSIS
        Returns the in-tenant lab marker app registration, or $null.
    #>
    [CmdletBinding()]
    param()

    Get-MgApplication -Filter "displayName eq '$($script:IRLabMarkerName)'" -ErrorAction Stop |
        Where-Object { $_.Tags -contains $script:IRLabMarkerName } |
        Select-Object -First 1
}

function Assert-IRLabTenant {
    <#
    .SYNOPSIS
        Throws unless the connected tenant is a confirmed lab: elevated session, local profile marked
        IsLab, marker app present in the tenant, and no more than 50 users.
    #>
    [CmdletBinding()]
    param()

    Test-IRLabModuleDependency
    Assert-IRTenant
    $domain = $script:IRContext.PrimaryDomain

    if (-not $script:IRContext.Elevated) {
        throw "Lab guard: lab tools need an elevated session. Run: Connect-IR -Tenant $domain -Elevated"
    }

    $profileData = Get-IRTenantProfile -PrimaryDomain $domain
    if (-not ($profileData -and $profileData.PSObject.Properties['IsLab'] -and $profileData.IsLab)) {
        throw "Lab guard: $domain is not marked as a lab tenant. If (and only if) it is your lab, run Enable-IRLabTenant."
    }

    if (-not (Get-IRLabMarker)) {
        throw "Lab guard: the '$($script:IRLabMarkerName)' marker app is missing from tenant $domain. Refusing to continue."
    }

    $users = Get-IRLabUserCount
    if ($users -gt $script:IRLabMaxUsers) {
        throw "Lab guard: $domain has $users users (limit $($script:IRLabMaxUsers)). That doesn't look like a lab. Refusing to continue."
    }
}

function Enable-IRLabTenant {
    <#
    .SYNOPSIS
        Marks the connected tenant as a lab, after you type its onmicrosoft.com domain to confirm.
    .DESCRIPTION
        Creates the EIF-LAB-MARKER app registration in the tenant (no permissions, no credentials)
        and sets IsLab in the local tenant profile. Both are required before seeding or cleanup will run.
    .PARAMETER ConfirmDomain
        The tenant's initial domain, e.g. eiflab.onmicrosoft.com. Must be typed, not tab-completed from history.
    .EXAMPLE
        Connect-IR -Tenant eiflab.onmicrosoft.com -Elevated
        Enable-IRLabTenant -ConfirmDomain eiflab.onmicrosoft.com
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]
        [string]$ConfirmDomain
    )

    Test-IRLabModuleDependency
    Assert-IRTenant
    if (-not $script:IRContext.Elevated) {
        throw "Enable-IRLabTenant needs an elevated session. Run: Connect-IR -Tenant $($script:IRContext.PrimaryDomain) -Elevated"
    }

    $org = Get-MgOrganization -ErrorAction Stop | Select-Object -First 1
    $initial = ($org.VerifiedDomains | Where-Object { $_.IsInitial } | Select-Object -First 1).Name
    if (-not $initial -or $ConfirmDomain.ToLowerInvariant() -ne $initial.ToLowerInvariant()) {
        throw "Lab guard: '$ConfirmDomain' is not this tenant's initial domain. Nothing changed."
    }

    $users = Get-IRLabUserCount
    if ($users -gt $script:IRLabMaxUsers) {
        throw "Lab guard: tenant has $users users (limit $($script:IRLabMaxUsers)). Not marking it as a lab."
    }

    if (-not $PSCmdlet.ShouldProcess("$initial ($($org.DisplayName), $users users)", 'Mark tenant as an EverythingIsFine LAB')) {
        return
    }

    $marker = Get-IRLabMarker
    if (-not $marker) {
        $marker = New-MgApplication -DisplayName $script:IRLabMarkerName -SignInAudience 'AzureADMyOrg' `
            -Tags @($script:IRLabMarkerName) -Notes 'Marks this tenant as an EverythingIsFine lab. No permissions, no credentials. Deleting it disables the lab tools.' `
            -ErrorAction Stop
        Write-IRLog -Level Action -Message "Created lab marker app $($script:IRLabMarkerName) ($($marker.Id))."
    }

    Set-IRTenantProfile -PrimaryDomain $script:IRContext.PrimaryDomain -TenantId $script:IRContext.TenantId -IsLab $true
    Write-IRLog -Level Action -Message "Tenant $initial is now marked as a lab."
}
