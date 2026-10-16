@{
    Severity     = @('Error', 'Warning')

    # Write-Host is deliberate: Write-IRLog gives operators colour-coded console output,
    # and everything it prints is also written to the case's activity.jsonl.
    ExcludeRules = @('PSAvoidUsingWriteHost')

    Rules        = @{
        PSUseCompatibleSyntax = @{
            Enable         = $true
            TargetVersions = @('7.2')
        }
    }
}
