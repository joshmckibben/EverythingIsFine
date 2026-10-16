function Disconnect-IR {
    <#
    .SYNOPSIS
        Disconnects Microsoft Graph and Exchange Online and clears the tenant context.
    .DESCRIPTION
        Connect-IR calls this first so a session for another tenant can never carry over.
        Closes any open case first.
    #>
    [CmdletBinding()]
    param(
        [switch]$Quiet
    )

    if ($script:IRContext -and $script:IRContext.Case) {
        Close-IRCase
    }

    if (Get-Command Disconnect-MgGraph -ErrorAction SilentlyContinue) {
        Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
    }
    if (Get-Command Disconnect-ExchangeOnline -ErrorAction SilentlyContinue) {
        Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
    }

    if (-not $Quiet -and $script:IRContext) {
        Write-IRLog -Level Info -Message 'Disconnected from Microsoft Graph and Exchange Online.'
    }
    $script:IRContext = $null
}
