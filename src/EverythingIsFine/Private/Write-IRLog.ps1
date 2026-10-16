function Write-IRLog {
    <#
    .SYNOPSIS
        Writes a message to the console and, when a case is open, to the case's activity.jsonl.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('Info', 'Warn', 'Finding', 'Action', 'Error')]
        [string]$Level = 'Info',

        [hashtable]$Data
    )

    $colour = @{ Info = 'Gray'; Warn = 'Yellow'; Finding = 'Magenta'; Action = 'Cyan'; Error = 'Red' }[$Level]
    $prefix = if ($script:IRContext) { "[$($script:IRContext.PrimaryDomain)] " } else { '' }
    Write-Host "$prefix$($Level.ToUpper().PadRight(7)) $Message" -ForegroundColor $colour

    if ($script:IRContext -and $script:IRContext.Case) {
        $entry = [ordered]@{
            TimestampUtc = (Get-Date).ToUniversalTime().ToString('o')
            TenantId     = $script:IRContext.TenantId
            Operator     = $script:IRContext.Account
            Level        = $Level
            Message      = $Message
            Data         = $Data
        }
        $line = $entry | ConvertTo-Json -Depth 10 -Compress
        Add-Content -LiteralPath (Join-Path $script:IRContext.Case.Path 'activity.jsonl') -Value $line -Encoding utf8
    }
}
