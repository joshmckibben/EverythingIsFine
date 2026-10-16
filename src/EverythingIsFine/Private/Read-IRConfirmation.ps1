function Read-IRConfirmation {
    <#
    .SYNOPSIS
        Asks the operator a yes/no question, always prefixed with the tenant domain. Defaults to No.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Message
    )

    $domain = if ($script:IRContext) { $script:IRContext.PrimaryDomain } else { 'NO TENANT' }
    $answer = Read-Host "[$domain] $Message (y/N)"
    $answer -match '^(y|yes)$'
}
