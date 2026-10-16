function Get-IRContext {
    <#
    .SYNOPSIS
        Returns the current tenant context (tenant, operator, capabilities, open case), or $null.
    #>
    [CmdletBinding()]
    param()

    $script:IRContext
}
