function Get-IRDataRoot {
    <#
    .SYNOPSIS
        Returns the root folder for tenant profiles and case evidence, creating it if needed.
    .DESCRIPTION
        Evidence must never live inside the git repo. Defaults to ~/EverythingIsFine-Data;
        override with the EIF_DATA_ROOT environment variable (e.g. an encrypted share).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $root = if ($env:EIF_DATA_ROOT) { $env:EIF_DATA_ROOT } else { Join-Path $HOME 'EverythingIsFine-Data' }
    if (-not (Test-Path -LiteralPath $root)) {
        New-Item -ItemType Directory -Path $root -Force | Out-Null
    }
    (Resolve-Path -LiteralPath $root).Path
}
