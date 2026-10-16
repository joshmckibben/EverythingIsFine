function Test-IRModuleDependency {
    <#
    .SYNOPSIS
        Returns the names of required modules that are missing or too old. Empty when all present.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param()

    $required = @(
        @{ Name = 'Microsoft.Graph.Authentication';               MinimumVersion = '2.0.0' }
        @{ Name = 'Microsoft.Graph.Identity.DirectoryManagement'; MinimumVersion = '2.0.0' }
        @{ Name = 'Microsoft.Graph.Users';                        MinimumVersion = '2.0.0' }
        @{ Name = 'ExchangeOnlineManagement';                     MinimumVersion = '3.4.0' }
    )

    foreach ($module in $required) {
        $found = Get-Module -ListAvailable -Name $module.Name |
            Where-Object { $_.Version -ge [version]$module.MinimumVersion } |
            Select-Object -First 1
        if (-not $found) { $module.Name }
    }
}
