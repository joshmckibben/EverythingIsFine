#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    # Stubs (with the parameters we use) for every Graph / EXO cmdlet the lab code calls,
    # so Pester can mock them on machines without those modules installed.
    $stubs = [ordered]@{
        'Get-MgContext'                         = @()
        'Get-ConnectionInformation'             = @()
        'Get-MgOrganization'                    = @()
        'Get-MgUser'                            = @('UserId', 'Top', 'ConsistencyLevel', 'CountVariable')
        'Get-MgApplication'                     = @('Filter', 'All')
        'New-MgApplication'                     = @('DisplayName', 'SignInAudience', 'Tags', 'Notes')
        'Remove-MgApplication'                  = @('ApplicationId')
        'Add-MgApplicationPassword'             = @('ApplicationId', 'PasswordCredential')
        'New-MgServicePrincipal'                = @('AppId', 'Tags')
        'Get-MgServicePrincipal'                = @('Filter')
        'Remove-MgServicePrincipal'             = @('ServicePrincipalId')
        'New-MgOauth2PermissionGrant'           = @('BodyParameter')
        'Remove-MgOauth2PermissionGrant'        = @('OAuth2PermissionGrantId')
        'Get-MgUserAuthenticationPhoneMethod'   = @('UserId')
        'New-MgUserAuthenticationPhoneMethod'   = @('UserId', 'BodyParameter')
        'Remove-MgUserAuthenticationPhoneMethod' = @('UserId', 'PhoneAuthenticationMethodId')
        'Get-Mailbox'                           = @('Identity')
        'Set-Mailbox'                           = @('Identity', 'ForwardingSmtpAddress', 'DeliverToMailboxAndForward')
        'New-InboxRule'                         = @('Mailbox', 'Name', 'SubjectOrBodyContainsWords', 'MoveToFolder', 'MarkAsRead', 'StopProcessingRules', 'DeleteMessage', 'ForwardTo')
        'Remove-InboxRule'                      = @('Mailbox', 'Identity')
        'Get-MailboxFolderPermission'           = @('Identity', 'User')
        'Set-MailboxFolderPermission'           = @('Identity', 'User', 'AccessRights')
        'Add-MailboxPermission'                 = @('Identity', 'User', 'AccessRights', 'AutoMapping')
        'Remove-MailboxPermission'              = @('Identity', 'User', 'AccessRights')
        'Add-RecipientPermission'               = @('Identity', 'Trustee', 'AccessRights')
        'Remove-RecipientPermission'            = @('Identity', 'Trustee', 'AccessRights')
        'New-TransportRule'                     = @('Name', 'From', 'SubjectOrBodyContainsWords', 'BlindCopyTo')
        'Remove-TransportRule'                  = @('Identity')
    }
    foreach ($name in $stubs.Keys) {
        if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
            $params = ($stubs[$name] | ForEach-Object { if ($_ -eq 'All') { '[switch]$All' } else { "`$$_" } }) -join ', '
            Set-Item -Path "function:global:$name" -Value ([scriptblock]::Create("[CmdletBinding(SupportsShouldProcess)] param($params)"))
        }
    }

    Import-Module (Join-Path $PSScriptRoot '..' 'src' 'EverythingIsFine' 'EverythingIsFine.psd1') -ArgumentList Lab -Force
}

AfterAll {
    Remove-Module EverythingIsFine -ErrorAction SilentlyContinue
}

Describe 'Lab feature loading' {
    It 'Exports the lab commands only when imported with -ArgumentList Lab' {
        Get-Command Invoke-IRLabSeed -Module EverythingIsFine -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty

        $plain = & (Get-Process -Id $PID).Path -NoProfile -NonInteractive -Command @"
Import-Module '$(Join-Path $PSScriptRoot '..' 'src' 'EverythingIsFine' 'EverythingIsFine.psd1')'
[bool](Get-Command Invoke-IRLabSeed -ErrorAction SilentlyContinue)
"@
        "$plain".Trim() | Should -Be 'False'
    }

    It 'Is never included in the paste build' {
        $out = Join-Path $TestDrive 'paste.ps1'
        & (Join-Path $PSScriptRoot '..' 'tools' 'Build-PasteFile.ps1') -OutputPath $out 6>$null
        Get-Content $out -Raw | Should -Not -Match 'IRLab'
    }
}

Describe 'Lab guards' {
    BeforeEach {
        $env:EIF_DATA_ROOT = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        InModuleScope EverythingIsFine {
            $script:IRContext = [pscustomobject]@{
                TenantId = '11111111-1111-1111-1111-111111111111'; PrimaryDomain = 'eiflab.onmicrosoft.com'
                DisplayName = 'EIF Lab'; Account = 'admin@eiflab.onmicrosoft.com'; Elevated = $true
                SkipExchange = $false; Capability = $null; Case = $null
            }
            Mock Assert-IRTenant { }
            Mock Test-IRLabModuleDependency { }
            Mock Write-Host { }
            Mock Get-MgUser { $PSCmdlet.SessionState.PSVariable.Set($CountVariable, 5) } -ParameterFilter { $CountVariable }
            Mock Get-MgApplication { [pscustomobject]@{ Id = 'marker-id'; DisplayName = 'EIF-LAB-MARKER'; Tags = @('EIF-LAB-MARKER') } }
            Mock Get-MgOrganization {
                [pscustomobject]@{
                    DisplayName = 'EIF Lab'
                    VerifiedDomains = @([pscustomobject]@{ Name = 'eiflab.onmicrosoft.com'; IsInitial = $true; IsDefault = $true })
                }
            }
            Mock New-MgApplication { [pscustomobject]@{ Id = 'new-marker'; AppId = 'x' } }
        }
    }

    AfterEach {
        InModuleScope EverythingIsFine { $script:IRContext = $null }
        Remove-Item Env:EIF_DATA_ROOT -ErrorAction SilentlyContinue
    }

    It 'Refuses when the tenant is not marked as a lab locally' {
        InModuleScope EverythingIsFine {
            { Assert-IRLabTenant } | Should -Throw '*not marked as a lab*'
        }
    }

    It 'Refuses when the session is not elevated' {
        InModuleScope EverythingIsFine {
            $script:IRContext.Elevated = $false
            { Assert-IRLabTenant } | Should -Throw '*elevated*'
        }
    }

    It 'Refuses when the in-tenant marker app is missing, even if the local profile says lab' {
        InModuleScope EverythingIsFine {
            Set-IRTenantProfile -PrimaryDomain 'eiflab.onmicrosoft.com' -TenantId $script:IRContext.TenantId -IsLab $true
            Mock Get-MgApplication { }
            { Assert-IRLabTenant } | Should -Throw '*marker app is missing*'
        }
    }

    It 'Refuses when the tenant has more than 50 users' {
        InModuleScope EverythingIsFine {
            Set-IRTenantProfile -PrimaryDomain 'eiflab.onmicrosoft.com' -TenantId $script:IRContext.TenantId -IsLab $true
            Mock Get-IRLabUserCount { 51 }
            { Assert-IRLabTenant } | Should -Throw '*51 users*'
        }
    }

    It 'Passes for a marked lab with the marker and few users' {
        InModuleScope EverythingIsFine {
            Set-IRTenantProfile -PrimaryDomain 'eiflab.onmicrosoft.com' -TenantId $script:IRContext.TenantId -IsLab $true
            Mock Get-IRLabUserCount { 5 }
            { Assert-IRLabTenant } | Should -Not -Throw
        }
    }

    It 'Enable-IRLabTenant refuses a domain that is not the initial domain, and changes nothing' {
        InModuleScope EverythingIsFine {
            Mock Get-IRLabUserCount { 5 }
            { Enable-IRLabTenant -ConfirmDomain 'client.com' -Confirm:$false } | Should -Throw '*not this tenant*'
            Should -Invoke New-MgApplication -Times 0
            (Get-IRTenantProfile -PrimaryDomain 'eiflab.onmicrosoft.com') | Should -BeNullOrEmpty
        }
    }

    It 'Enable-IRLabTenant refuses a tenant with more than 50 users' {
        InModuleScope EverythingIsFine {
            Mock Get-IRLabUserCount { 300 }
            { Enable-IRLabTenant -ConfirmDomain 'eiflab.onmicrosoft.com' -Confirm:$false } | Should -Throw '*300 users*'
            Should -Invoke New-MgApplication -Times 0
        }
    }

    It 'Enable-IRLabTenant creates the marker and keeps existing profile data' {
        InModuleScope EverythingIsFine {
            Set-IRTenantProfile -PrimaryDomain 'eiflab.onmicrosoft.com' -TenantId $script:IRContext.TenantId -DisplayName 'EIF Lab' -Capability ([pscustomobject]@{ EntraP1 = $false })
            Mock Get-IRLabUserCount { 5 }
            Mock Get-MgApplication { }
            Enable-IRLabTenant -ConfirmDomain 'EIFLAB.onmicrosoft.com' -Confirm:$false
            Should -Invoke New-MgApplication -Times 1 -ParameterFilter { $DisplayName -eq 'EIF-LAB-MARKER' -and $Tags -contains 'EIF-LAB-MARKER' }
            $saved = Get-IRTenantProfile -PrimaryDomain 'eiflab.onmicrosoft.com'
            $saved.IsLab | Should -BeTrue
            $saved.DisplayName | Should -Be 'EIF Lab'
            $saved.Capability.EntraP1 | Should -BeFalse
        }
    }

    It 'Seeding refuses before touching anything when the guard fails' {
        InModuleScope EverythingIsFine {
            Mock New-InboxRule { }
            Mock New-MgApplication { }
            { Invoke-IRLabSeed -Victim 'alex@eiflab.onmicrosoft.com' -Executive 'ceo@eiflab.onmicrosoft.com' -Confirm:$false } | Should -Throw '*not marked as a lab*'
            Should -Invoke New-InboxRule -Times 0
            Should -Invoke New-MgApplication -Times 0
        }
    }
}

Describe 'Seeding and cleanup' {
    BeforeEach {
        $env:EIF_DATA_ROOT = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        InModuleScope EverythingIsFine {
            $script:IRContext = [pscustomobject]@{
                TenantId = '11111111-1111-1111-1111-111111111111'; PrimaryDomain = 'eiflab.onmicrosoft.com'
                DisplayName = 'EIF Lab'; Account = 'admin@eiflab.onmicrosoft.com'; Elevated = $true
                SkipExchange = $false; Capability = $null; Case = $null
            }
            Mock Assert-IRLabTenant { }
            Mock Assert-IRTenant { }
            Mock Write-Host { }

            Mock Get-MgUser { [pscustomobject]@{ Id = "id-$UserId" } }
            Mock Get-Mailbox { [pscustomobject]@{ ForwardingSmtpAddress = $null; DeliverToMailboxAndForward = $false } }
            Mock New-InboxRule { [pscustomobject]@{ RuleIdentity = "rule-$Name" } }
            Mock Set-Mailbox { }
            Mock Get-MailboxFolderPermission { [pscustomobject]@{ AccessRights = @('None') } }
            Mock Set-MailboxFolderPermission { }
            Mock Add-MailboxPermission { }
            Mock Add-RecipientPermission { }
            Mock New-TransportRule { [pscustomobject]@{ Guid = 'tr-guid' } }
            Mock Get-MgUserAuthenticationPhoneMethod { [pscustomobject]@{ PhoneType = 'mobile' } }
            Mock New-MgUserAuthenticationPhoneMethod { [pscustomobject]@{ Id = 'phone-id' } }
            Mock New-MgApplication { [pscustomobject]@{ Id = 'app-id'; AppId = 'app-appid' } }
            Mock Add-MgApplicationPassword { [pscustomobject]@{ SecretText = 'should-never-be-stored' } }
            Mock New-MgServicePrincipal { [pscustomobject]@{ Id = 'sp-id' } }
            Mock Get-MgServicePrincipal { [pscustomobject]@{ Id = 'graph-sp-id' } }
            Mock New-MgOauth2PermissionGrant { [pscustomobject]@{ Id = 'grant-id' } }

            Mock Remove-InboxRule { }
            Mock Remove-MailboxPermission { }
            Mock Remove-RecipientPermission { }
            Mock Remove-TransportRule { }
            Mock Remove-MgUserAuthenticationPhoneMethod { }
            Mock Remove-MgOauth2PermissionGrant { }
            Mock Remove-MgServicePrincipal { }
            Mock Remove-MgApplication { }
        }
    }

    AfterEach {
        InModuleScope EverythingIsFine { $script:IRContext = $null }
        Remove-Item Env:EIF_DATA_ROOT -ErrorAction SilentlyContinue
    }

    It 'Records all 10 artefacts, uses only reserved external addresses, and never stores the secret' {
        InModuleScope EverythingIsFine {
            $result = Invoke-IRLabSeed -Victim 'alex@eiflab.onmicrosoft.com' -Executive 'ceo@eiflab.onmicrosoft.com' -Confirm:$false
            @($result).Count | Should -Be 12   # 10 artefacts; the app adds app + service principal + grant
            @($result.Type | Sort-Object -Unique) | Should -Be @('Application', 'FolderPermission', 'InboxRule', 'MailboxForwarding', 'MailboxPermission', 'PermissionGrant', 'PhoneMethod', 'RecipientPermission', 'ServicePrincipal', 'TransportRule')

            Should -Invoke New-InboxRule -Times 0 -Exactly -ParameterFilter { $ForwardTo -and $ForwardTo -notlike '*@example.com' }
            Should -Invoke Set-Mailbox -Times 1 -Exactly -ParameterFilter { $ForwardingSmtpAddress -like '*@example.com' }
            Should -Invoke New-TransportRule -Times 1 -Exactly -ParameterFilter { $BlindCopyTo -like '*@example.com' }
            Should -Invoke New-MgUserAuthenticationPhoneMethod -Times 1 -Exactly -ParameterFilter { $BodyParameter.phoneType -eq 'alternateMobile' -and $BodyParameter.phoneNumber -like '+1 202555*' }

            (Get-Content (Get-IRLabStatePath) -Raw) | Should -Not -Match 'should-never-be-stored'
        }
    }

    It 'Refuses to seed twice without -Force' {
        InModuleScope EverythingIsFine {
            Invoke-IRLabSeed -Victim 'alex@eiflab.onmicrosoft.com' -Executive 'ceo@eiflab.onmicrosoft.com' -Confirm:$false | Out-Null
            { Invoke-IRLabSeed -Victim 'alex@eiflab.onmicrosoft.com' -Executive 'ceo@eiflab.onmicrosoft.com' -Confirm:$false } | Should -Throw '*already has*'
        }
    }

    It 'Keeps going when one step fails, and records only what was created' {
        InModuleScope EverythingIsFine {
            Mock New-TransportRule { throw 'Access denied' }
            Mock New-MgServicePrincipal { throw 'Throttled' }
            $result = Invoke-IRLabSeed -Victim 'alex@eiflab.onmicrosoft.com' -Executive 'ceo@eiflab.onmicrosoft.com' -Confirm:$false
            $result.Type | Should -Not -Contain 'TransportRule'
            $result.Type | Should -Contain 'Application'        # created before the failure, so must be cleaned up
            $result.Type | Should -Not -Contain 'ServicePrincipal'
            $result.Type | Should -Contain 'PhoneMethod'         # later steps still ran
        }
    }

    It 'Cleanup removes and restores everything, newest first, and empties the state' {
        InModuleScope EverythingIsFine {
            Invoke-IRLabSeed -Victim 'alex@eiflab.onmicrosoft.com' -Executive 'ceo@eiflab.onmicrosoft.com' -Confirm:$false | Out-Null
            $script:order = [System.Collections.Generic.List[string]]::new()
            Mock Remove-MgApplication { $script:order.Add('app') }
            Mock Remove-MgOauth2PermissionGrant { $script:order.Add('grant') }

            Invoke-IRLabCleanup -Confirm:$false

            Should -Invoke Remove-InboxRule -Times 3 -Exactly
            Should -Invoke Set-Mailbox -Times 1 -Exactly -ParameterFilter { $null -eq $ForwardingSmtpAddress -and $DeliverToMailboxAndForward -eq $false }
            Should -Invoke Set-MailboxFolderPermission -Times 1 -Exactly -ParameterFilter { $AccessRights -contains 'None' }
            Should -Invoke Remove-MailboxPermission -Times 1 -Exactly
            Should -Invoke Remove-RecipientPermission -Times 1 -Exactly
            Should -Invoke Remove-TransportRule -Times 1 -Exactly -ParameterFilter { $Identity -eq 'tr-guid' }
            Should -Invoke Remove-MgUserAuthenticationPhoneMethod -Times 1 -Exactly -ParameterFilter { $PhoneAuthenticationMethodId -eq 'phone-id' }
            Should -Invoke Remove-MgServicePrincipal -Times 1 -Exactly
            $script:order | Should -Be @('grant', 'app')
            @(Get-IRLabState) | Should -BeNullOrEmpty
        }
    }

    It 'Cleanup treats already-deleted artefacts as cleaned, and keeps real failures for a retry' {
        InModuleScope EverythingIsFine {
            Invoke-IRLabSeed -Victim 'alex@eiflab.onmicrosoft.com' -Executive 'ceo@eiflab.onmicrosoft.com' -Confirm:$false | Out-Null
            Mock Remove-TransportRule { throw "The operation couldn't be performed because object 'tr-guid' couldn't be found" }
            Mock Remove-MgApplication { throw 'Insufficient privileges to complete the operation.' }

            Invoke-IRLabCleanup -Confirm:$false

            $left = @(Get-IRLabState)
            $left.Count | Should -Be 1
            $left[0].Type | Should -Be 'Application'
        }
    }

    It 'Cleanup with -IncludeOrphans removes untracked lab apps but never the marker' {
        InModuleScope EverythingIsFine {
            Mock Get-MgApplication {
                [pscustomobject]@{ Id = 'marker'; AppId = 'm'; DisplayName = 'EIF-LAB-MARKER'; Tags = @('EIF-LAB-MARKER') }
                [pscustomobject]@{ Id = 'orphan'; AppId = 'o'; DisplayName = 'Mail Sync Pro'; Tags = @('EIF-LAB') }
                [pscustomobject]@{ Id = 'real'; AppId = 'r'; DisplayName = 'Some real app'; Tags = @() }
            }
            Invoke-IRLabCleanup -IncludeOrphans -Confirm:$false
            Should -Invoke Remove-MgApplication -Times 1 -Exactly -ParameterFilter { $ApplicationId -eq 'orphan' }
        }
    }
}
