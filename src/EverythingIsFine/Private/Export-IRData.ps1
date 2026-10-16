function Export-IRData {
    <#
    .SYNOPSIS
        Writes collected data into the open case as JSON (source of truth) and CSV (convenience),
        and records a SHA256 for each file in manifest.csv.
    .EXAMPLE
        Export-IRData -Category 'mailbox' -Name 'jsmith_inboxrules' -Source 'EXO:Get-InboxRule' -InputObject $rules
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^[\w\-]+$')]
        [string]$Category,

        [Parameter(Mandatory)]
        [ValidatePattern('^[\w\-\.@]+$')]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Source,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [AllowNull()]
        [object[]]$InputObject
    )

    if (-not ($script:IRContext -and $script:IRContext.Case)) {
        throw 'No case is open. Run New-IRCase first.'
    }

    $records = @($InputObject | Where-Object { $null -ne $_ })
    $dir = Join-Path $script:IRContext.Case.Path 'raw' $Category
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $jsonPath = Join-Path $dir "$Name.json"
    ConvertTo-Json -InputObject $records -Depth 10 | Set-Content -LiteralPath $jsonPath -Encoding utf8
    $written = @($jsonPath)

    if ($records.Count -gt 0) {
        $csvPath = Join-Path $dir "$Name.csv"
        $records | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding utf8
        $written += $csvPath
    }

    foreach ($file in $written) {
        Add-IRManifestEntry -Path $file -Source $Source -RecordCount $records.Count
    }

    Write-IRLog -Level Info -Message "Saved $($records.Count) record(s) to raw/$Category/$Name" -Data @{ Source = $Source }
    $written | ForEach-Object { Get-Item -LiteralPath $_ }
}

function Add-IRManifestEntry {
    <#
    .SYNOPSIS
        Appends a file's SHA256 and metadata to the case's manifest.csv.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [string]$Source = '',

        [int]$RecordCount = -1
    )

    $caseRoot = $script:IRContext.Case.Path
    $item = Get-Item -LiteralPath $Path
    [pscustomobject]@{
        RelativePath = [System.IO.Path]::GetRelativePath($caseRoot, $item.FullName)
        SHA256       = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash
        Bytes        = $item.Length
        RecordCount  = $RecordCount
        Source       = $Source
        HashedAtUtc  = (Get-Date).ToUniversalTime().ToString('o')
    } | Export-Csv -LiteralPath (Join-Path $caseRoot 'manifest.csv') -Append -NoTypeInformation -Encoding utf8
}
