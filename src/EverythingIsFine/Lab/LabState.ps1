# Lab feature: records every artefact the seeder creates so cleanup can remove exactly those.

function Get-IRLabStatePath {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $dir = Join-Path (Get-IRDataRoot) 'lab'
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    Join-Path $dir "$($script:IRContext.PrimaryDomain).json"
}

function Get-IRLabState {
    <#
    .SYNOPSIS
        Lists the lab artefacts currently recorded as seeded in the connected tenant.
    #>
    [CmdletBinding()]
    param()

    Assert-IRTenant
    $path = Get-IRLabStatePath
    if (Test-Path -LiteralPath $path) {
        @(Get-Content -LiteralPath $path -Raw | ConvertFrom-Json)
    }
}

function Save-IRLabState {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Artefact
    )

    $path = Get-IRLabStatePath
    if ($PSCmdlet.ShouldProcess($path, 'Write lab state')) {
        ConvertTo-Json -InputObject @($Artefact) -Depth 10 | Set-Content -LiteralPath $path -Encoding utf8
    }
}

function Add-IRLabArtefact {
    <#
    .SYNOPSIS
        Appends one artefact to the lab state file immediately, so a partial seed can still be cleaned up.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Type,

        [Parameter(Mandatory)]
        [string]$Description,

        [Parameter(Mandatory)]
        [hashtable]$Data
    )

    $state = @(Get-IRLabState)
    $state += [pscustomobject]@{
        Type         = $Type
        Description  = $Description
        Data         = [pscustomobject]$Data
        CreatedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    }
    Save-IRLabState -Artefact $state
    Write-IRLog -Level Action -Message "Seeded: $Description"
}
