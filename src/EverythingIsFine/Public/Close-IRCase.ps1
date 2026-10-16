function Close-IRCase {
    <#
    .SYNOPSIS
        Closes the open case: stops the transcript, hashes the transcript and activity log, stamps case.json.
    #>
    [CmdletBinding()]
    param()

    if (-not ($script:IRContext -and $script:IRContext.Case)) {
        Write-IRLog -Level Warn -Message 'No case is open.'
        return
    }

    $case = $script:IRContext.Case
    Write-IRLog -Level Action -Message "Case closed: $($case.Reference)"

    try { Stop-Transcript | Out-Null } catch { Write-Verbose 'No transcript was running.' }

    foreach ($file in 'transcript.txt', 'activity.jsonl') {
        $full = Join-Path $case.Path $file
        if (Test-Path -LiteralPath $full) {
            Add-IRManifestEntry -Path $full -Source 'EverythingIsFine'
        }
    }

    $case.ClosedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    $case | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $case.Path 'case.json') -Encoding utf8

    $script:IRContext.Case = $null
    $case
}
