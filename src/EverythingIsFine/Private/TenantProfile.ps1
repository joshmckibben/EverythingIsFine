function Get-IRTenantProfilePath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$PrimaryDomain
    )

    $dir = Join-Path (Get-IRDataRoot) 'tenants'
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    Join-Path $dir "$($PrimaryDomain.ToLowerInvariant()).json"
}

function Get-IRTenantProfile {
    <#
    .SYNOPSIS
        Returns the saved profile for a tenant, or $null if none exists yet.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PrimaryDomain
    )

    $path = Get-IRTenantProfilePath -PrimaryDomain $PrimaryDomain
    if (Test-Path -LiteralPath $path) {
        Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    }
}

function Set-IRTenantProfile {
    <#
    .SYNOPSIS
        Writes a tenant profile. Merges with any existing profile so notes are preserved.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$PrimaryDomain,

        [Parameter(Mandatory)]
        [string]$TenantId,

        [string]$DisplayName,

        [pscustomobject]$Capability
    )

    $path = Get-IRTenantProfilePath -PrimaryDomain $PrimaryDomain
    $existing = Get-IRTenantProfile -PrimaryDomain $PrimaryDomain

    $profileData = [ordered]@{
        PrimaryDomain  = $PrimaryDomain.ToLowerInvariant()
        TenantId       = $TenantId
        DisplayName    = $DisplayName
        FirstSeenUtc   = if ($existing) { $existing.FirstSeenUtc } else { (Get-Date).ToUniversalTime().ToString('o') }
        LastSeenUtc    = (Get-Date).ToUniversalTime().ToString('o')
        Capability     = $Capability
        Notes          = if ($existing) { $existing.Notes } else { '' }
    }

    if ($PSCmdlet.ShouldProcess($path, 'Write tenant profile')) {
        $profileData | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $path -Encoding utf8
    }
}
