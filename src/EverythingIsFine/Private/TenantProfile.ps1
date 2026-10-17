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
        Writes a tenant profile. Values not passed are kept from any existing profile
        (first-seen time, notes, capability, lab flag).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$PrimaryDomain,

        [Parameter(Mandatory)]
        [string]$TenantId,

        [string]$DisplayName,

        [pscustomobject]$Capability,

        [bool]$IsLab
    )

    $path = Get-IRTenantProfilePath -PrimaryDomain $PrimaryDomain
    $existing = Get-IRTenantProfile -PrimaryDomain $PrimaryDomain

    # Capture the function's bound parameters: inside the script block below,
    # $PSBoundParameters would refer to the script block's own parameters.
    $bound = $PSBoundParameters
    $keep = {
        param($name, $default)
        if ($bound.ContainsKey($name)) { return $bound[$name] }
        if ($existing -and $existing.PSObject.Properties[$name]) { return $existing.$name }
        $default
    }

    $profileData = [ordered]@{
        PrimaryDomain  = $PrimaryDomain.ToLowerInvariant()
        TenantId       = $TenantId
        DisplayName    = & $keep 'DisplayName' ''
        FirstSeenUtc   = & $keep 'FirstSeenUtc' (Get-Date).ToUniversalTime().ToString('o')
        LastSeenUtc    = (Get-Date).ToUniversalTime().ToString('o')
        Capability     = & $keep 'Capability' $null
        IsLab          = [bool](& $keep 'IsLab' $false)
        Notes          = & $keep 'Notes' ''
    }

    if ($PSCmdlet.ShouldProcess($path, 'Write tenant profile')) {
        $profileData | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $path -Encoding utf8
    }
}
