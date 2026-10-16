function New-IRCase {
    <#
    .SYNOPSIS
        Opens a case folder for the connected tenant and starts the transcript.
    .PARAMETER Reference
        Ticket or incident reference, e.g. the PSA ticket number.
    .PARAMETER Subject
        Account(s) under investigation.
    .EXAMPLE
        New-IRCase -Reference T12345 -Subject jsmith@contoso.com -Notes 'Vendor reported changed bank details'
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$Reference,

        [string[]]$Subject = @(),

        [string]$Notes = ''
    )

    Assert-IRTenant

    if ($script:IRContext.Case) {
        throw "Case '$($script:IRContext.Case.Reference)' is already open. Run Close-IRCase first."
    }

    $stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss')
    $safeRef = $Reference -replace '[^\w\-]', '_'
    $path = Join-Path (Get-IRDataRoot) 'Cases' $script:IRContext.PrimaryDomain "$($stamp)_$safeRef"

    if (-not $PSCmdlet.ShouldProcess($path, 'Create case folder')) { return }

    foreach ($sub in 'raw', 'snapshots', 'reports') {
        New-Item -ItemType Directory -Path (Join-Path $path $sub) -Force | Out-Null
    }

    $case = [pscustomobject]@{
        Reference     = $Reference
        Subject       = @($Subject)
        Notes         = $Notes
        TenantId      = $script:IRContext.TenantId
        PrimaryDomain = $script:IRContext.PrimaryDomain
        TenantName    = $script:IRContext.DisplayName
        OpenedBy      = $script:IRContext.Account
        OpenedAtUtc   = (Get-Date).ToUniversalTime().ToString('o')
        ClosedAtUtc   = $null
        ToolVersion   = $script:IRVersion
        Capability    = $script:IRContext.Capability
        Path          = $path
    }
    $case | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $path 'case.json') -Encoding utf8

    Start-Transcript -LiteralPath (Join-Path $path 'transcript.txt') -UseMinimalHeader | Out-Null
    $script:IRContext.Case = $case

    Write-IRLog -Level Action -Message "Case opened: $Reference -> $path" -Data @{ Subject = @($Subject) }
    $case
}
