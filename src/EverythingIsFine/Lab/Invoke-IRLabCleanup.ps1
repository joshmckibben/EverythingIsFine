function Invoke-IRLabCleanup {
    <#
    .SYNOPSIS
        Removes every artefact recorded by Invoke-IRLabSeed from the LAB tenant, newest first.
    .DESCRIPTION
        Refuses to run unless Assert-IRLabTenant passes. Each artefact is removed from the state file
        as soon as it's cleaned up; anything that fails stays recorded so you can run cleanup again.
        Artefacts already gone (deleted by hand, or by the toolkit's containment) count as cleaned.

        -IncludeOrphans also deletes app registrations tagged EIF-LAB that aren't in the state file
        (e.g. from a seed run whose state file was lost). The marker app is never touched.
    .EXAMPLE
        Invoke-IRLabCleanup
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [switch]$IncludeOrphans
    )

    Assert-IRLabTenant

    $state = [System.Collections.Generic.List[object]]::new()
    foreach ($item in @(Get-IRLabState)) { $state.Add($item) }

    $orphans = @()
    if ($IncludeOrphans) {
        $known = @($state | Where-Object Type -eq 'Application' | ForEach-Object { $_.Data.Id })
        $orphans = @(Get-MgApplication -All -ErrorAction Stop | Where-Object {
                $_.Tags -contains $script:IRLabTag -and $_.Tags -notcontains $script:IRLabMarkerName -and $known -notcontains $_.Id
            })
    }

    if ($state.Count -eq 0 -and $orphans.Count -eq 0) {
        Write-IRLog -Level Info -Message 'Nothing to clean up.'
        return
    }

    $summary = "$($state.Count) recorded artefact(s)" + $(if ($orphans.Count) { " and $($orphans.Count) orphaned lab app(s)" } else { '' })
    if (-not $PSCmdlet.ShouldProcess("lab tenant $($script:IRContext.PrimaryDomain)", "Remove $summary")) {
        return
    }

    $isGone = { param($err) "$err" -match 'not found|does not exist|couldn''t be found|could not be found|Request_ResourceNotFound|ResourceNotFound|NotFound' }

    for ($i = $state.Count - 1; $i -ge 0; $i--) {
        $item = $state[$i]
        $d = $item.Data
        try {
            switch ($item.Type) {
                'InboxRule' { Remove-InboxRule -Mailbox $d.Mailbox -Identity $d.RuleIdentity -Confirm:$false -ErrorAction Stop }
                'MailboxForwarding' {
                    $previous = if ($d.PreviousForwardingSmtp) { $d.PreviousForwardingSmtp } else { $null }
                    Set-Mailbox -Identity $d.Mailbox -ForwardingSmtpAddress $previous -DeliverToMailboxAndForward ([bool]$d.PreviousDeliverAndForward) -ErrorAction Stop
                }
                'FolderPermission' {
                    $rights = @($d.PreviousAccessRights)
                    if ($rights.Count -eq 0) { $rights = @('None') }
                    Set-MailboxFolderPermission -Identity $d.Folder -User $d.User -AccessRights $rights -ErrorAction Stop
                }
                'MailboxPermission' { Remove-MailboxPermission -Identity $d.Mailbox -User $d.User -AccessRights FullAccess -Confirm:$false -ErrorAction Stop }
                'RecipientPermission' { Remove-RecipientPermission -Identity $d.Mailbox -Trustee $d.Trustee -AccessRights SendAs -Confirm:$false -ErrorAction Stop }
                'TransportRule' { Remove-TransportRule -Identity $d.Guid -Confirm:$false -ErrorAction Stop }
                'PhoneMethod' { Remove-MgUserAuthenticationPhoneMethod -UserId $d.UserId -PhoneAuthenticationMethodId $d.MethodId -ErrorAction Stop }
                'PermissionGrant' { Remove-MgOauth2PermissionGrant -OAuth2PermissionGrantId $d.Id -ErrorAction Stop }
                'ServicePrincipal' { Remove-MgServicePrincipal -ServicePrincipalId $d.Id -ErrorAction Stop }
                'Application' { Remove-MgApplication -ApplicationId $d.Id -ErrorAction Stop }
                default { throw "Unknown artefact type '$($item.Type)'." }
            }
            Write-IRLog -Level Action -Message "Cleaned: $($item.Description)"
            $state.RemoveAt($i)
        }
        catch {
            if (& $isGone $_.Exception.Message) {
                Write-IRLog -Level Info -Message "Already gone: $($item.Description)"
                $state.RemoveAt($i)
            }
            else {
                Write-IRLog -Level Error -Message "Cleanup failed ($($item.Description)): $($_.Exception.Message)"
            }
        }
        Save-IRLabState -Artefact @($state)
    }

    foreach ($app in $orphans) {
        try {
            Remove-MgApplication -ApplicationId $app.Id -ErrorAction Stop
            Write-IRLog -Level Action -Message "Cleaned orphaned lab app '$($app.DisplayName)' ($($app.AppId))."
        }
        catch {
            Write-IRLog -Level Error -Message "Failed to remove orphaned lab app '$($app.DisplayName)': $($_.Exception.Message)"
        }
    }

    if ($state.Count -gt 0) {
        Write-IRLog -Level Warn -Message "$($state.Count) artefact(s) could not be removed and are still recorded. Fix the errors above and run Invoke-IRLabCleanup again."
    }
    else {
        Write-IRLog -Level Info -Message 'Lab clean. Deleted app registrations sit in Entra ID deleted items for 30 days.'
    }
}
