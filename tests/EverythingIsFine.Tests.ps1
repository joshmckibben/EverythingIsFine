#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    # Stub the Graph / EXO cmdlets (with the parameters we use) so Pester can mock them
    # on machines without those modules installed.
    $stubs = @{
        'Connect-MgGraph'           = { [CmdletBinding()] param($TenantId, [string[]]$Scopes, $ContextScope, [switch]$NoWelcome) }
        'Disconnect-MgGraph'        = { [CmdletBinding()] param() }
        'Get-MgContext'             = { [CmdletBinding()] param() }
        'Get-MgOrganization'        = { [CmdletBinding()] param() }
        'Get-MgSubscribedSku'       = { [CmdletBinding()] param([switch]$All) }
        'Connect-ExchangeOnline'    = { [CmdletBinding()] param($UserPrincipalName, [switch]$ShowBanner) }
        'Disconnect-ExchangeOnline' = { [CmdletBinding(SupportsShouldProcess)] param() }
        'Get-ConnectionInformation' = { [CmdletBinding()] param() }
        'Get-AdminAuditLogConfig'   = { [CmdletBinding()] param() }
    }
    foreach ($name in $stubs.Keys) {
        if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
            Set-Item -Path "function:global:$name" -Value $stubs[$name]
        }
    }

    Import-Module (Join-Path $PSScriptRoot '..' 'src' 'EverythingIsFine' 'EverythingIsFine.psd1') -Force

    $script:TenantA = '11111111-1111-1111-1111-111111111111'
    $script:TenantB = '22222222-2222-2222-2222-222222222222'
}

AfterAll {
    Remove-Module EverythingIsFine -ErrorAction SilentlyContinue
}

Describe 'ConvertTo-IRCapability' {
    It 'Business Standard: no Entra P1, so no Graph sign-in logs or Conditional Access' {
        InModuleScope EverythingIsFine {
            $cap = ConvertTo-IRCapability -ServicePlanName @('EXCHANGE_S_STANDARD')
            $cap.ExchangeOnline | Should -BeTrue
            $cap.EntraP1 | Should -BeFalse
            $cap.SignInLogsViaGraph | Should -BeFalse
            $cap.ConditionalAccess | Should -BeFalse
        }
    }

    It 'Business Premium: P1 and Defender for Office P1, but no P2 risk data' {
        InModuleScope EverythingIsFine {
            $cap = ConvertTo-IRCapability -ServicePlanName @('EXCHANGE_S_STANDARD', 'AAD_PREMIUM', 'ATP_ENTERPRISE')
            $cap.EntraP1 | Should -BeTrue
            $cap.ConditionalAccess | Should -BeTrue
            $cap.DefenderForOfficeP1 | Should -BeTrue
            $cap.IdentityProtectionRisk | Should -BeFalse
            $cap.ThreatExplorer | Should -BeFalse
        }
    }

    It 'P2 plans imply their P1 equivalents' {
        InModuleScope EverythingIsFine {
            $cap = ConvertTo-IRCapability -ServicePlanName @('AAD_PREMIUM_P2', 'THREAT_INTELLIGENCE')
            $cap.EntraP1 | Should -BeTrue
            $cap.IdentityProtectionRisk | Should -BeTrue
            $cap.DefenderForOfficeP1 | Should -BeTrue
            $cap.ThreatExplorer | Should -BeTrue
        }
    }

    It 'Handles a tenant with no service plans' {
        InModuleScope EverythingIsFine {
            $cap = ConvertTo-IRCapability -ServicePlanName @()
            $cap.ExchangeOnline | Should -BeFalse
            $cap.UnifiedAuditLogEnabled | Should -BeNullOrEmpty
        }
    }
}

Describe 'Assert-IRTenant' {
    BeforeEach {
        InModuleScope EverythingIsFine -Parameters @{ Tid = $script:TenantA } {
            param($Tid)
            $script:IRContext = [pscustomobject]@{
                TenantId = $Tid; PrimaryDomain = 'contoso.com'; SkipExchange = $false; Case = $null
            }
        }
    }

    AfterEach {
        InModuleScope EverythingIsFine { $script:IRContext = $null }
    }

    It 'Throws when not connected' {
        InModuleScope EverythingIsFine {
            $script:IRContext = $null
            { Assert-IRTenant } | Should -Throw '*Connect-IR*'
        }
    }

    It 'Passes when Graph and EXO both match the case tenant' {
        InModuleScope EverythingIsFine -Parameters @{ Tid = $script:TenantA } {
            param($Tid)
            Mock Get-MgContext { [pscustomobject]@{ TenantId = '11111111-1111-1111-1111-111111111111' } }
            Mock Get-ConnectionInformation { [pscustomobject]@{ TenantID = '11111111-1111-1111-1111-111111111111'; State = 'Connected' } }
            { Assert-IRTenant } | Should -Not -Throw
        }
    }

    It 'Throws when the Graph session is for another tenant' {
        InModuleScope EverythingIsFine -Parameters @{ Other = $script:TenantB } {
            param($Other)
            Mock Get-MgContext { [pscustomobject]@{ TenantId = '22222222-2222-2222-2222-222222222222' } }
            { Assert-IRTenant } | Should -Throw '*Tenant guard*Graph*'
        }
    }

    It 'Throws when an Exchange Online session is for another tenant' {
        InModuleScope EverythingIsFine -Parameters @{ Tid = $script:TenantA; Other = $script:TenantB } {
            param($Tid, $Other)
            Mock Get-MgContext { [pscustomobject]@{ TenantId = '11111111-1111-1111-1111-111111111111' } }
            Mock Get-ConnectionInformation {
                [pscustomobject]@{ TenantID = '11111111-1111-1111-1111-111111111111'; State = 'Connected' }
                [pscustomobject]@{ TenantID = '22222222-2222-2222-2222-222222222222'; State = 'Connected' }
            }
            { Assert-IRTenant } | Should -Throw '*Tenant guard*Exchange Online*'
        }
    }

    It 'Throws when there is no Exchange Online session' {
        InModuleScope EverythingIsFine -Parameters @{ Tid = $script:TenantA } {
            param($Tid)
            Mock Get-MgContext { [pscustomobject]@{ TenantId = '11111111-1111-1111-1111-111111111111' } }
            Mock Get-ConnectionInformation { }
            { Assert-IRTenant } | Should -Throw '*no Exchange Online session*'
        }
    }

    It 'Skips the Exchange check when connected with -SkipExchange' {
        InModuleScope EverythingIsFine -Parameters @{ Tid = $script:TenantA } {
            param($Tid)
            $script:IRContext.SkipExchange = $true
            Mock Get-MgContext { [pscustomobject]@{ TenantId = '11111111-1111-1111-1111-111111111111' } }
            Mock Get-ConnectionInformation { throw 'should not be called' }
            { Assert-IRTenant } | Should -Not -Throw
        }
    }
}

Describe 'Case folder and evidence' {
    BeforeEach {
        $env:EIF_DATA_ROOT = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        InModuleScope EverythingIsFine -Parameters @{ Tid = $script:TenantA } {
            param($Tid)
            $script:IRContext = [pscustomobject]@{
                TenantId = $Tid; PrimaryDomain = 'contoso.com'; DisplayName = 'Contoso'
                Account = 'admin@contoso.com'; SkipExchange = $false; Capability = $null; Case = $null
            }
            Mock Assert-IRTenant { }
            Mock Start-Transcript { }
            Mock Stop-Transcript { }
            Mock Write-Host { }
        }
    }

    AfterEach {
        InModuleScope EverythingIsFine { $script:IRContext = $null }
        Remove-Item Env:EIF_DATA_ROOT -ErrorAction SilentlyContinue
    }

    It 'New-IRCase creates the case folder structure under the data root, not the repo' {
        InModuleScope EverythingIsFine {
            $case = New-IRCase -Reference 'T-123/abc' -Subject 'jsmith@contoso.com'
            $case.Path | Should -BeLike "$($env:EIF_DATA_ROOT)*Cases*contoso.com*_T-123_abc"
            foreach ($sub in 'raw', 'snapshots', 'reports') {
                Join-Path $case.Path $sub | Should -Exist
            }
            $saved = Get-Content (Join-Path $case.Path 'case.json') -Raw | ConvertFrom-Json
            $saved.TenantId | Should -Be $script:IRContext.TenantId
            $saved.Subject | Should -Contain 'jsmith@contoso.com'
        }
    }

    It 'New-IRCase refuses to open a second case' {
        InModuleScope EverythingIsFine {
            New-IRCase -Reference 'first' | Out-Null
            { New-IRCase -Reference 'second' } | Should -Throw '*already open*'
        }
    }

    It 'Export-IRData writes JSON and CSV and records matching SHA256 hashes in the manifest' {
        InModuleScope EverythingIsFine {
            $case = New-IRCase -Reference 'hash'
            $rules = @(
                [pscustomobject]@{ Name = '.'; MoveToFolder = 'RSS Feeds' }
                [pscustomobject]@{ Name = 'invoice'; DeleteMessage = $true }
            )
            $files = Export-IRData -Category 'mailbox' -Name 'jsmith_inboxrules' -Source 'EXO:Get-InboxRule' -InputObject $rules

            $files.Count | Should -Be 2
            $manifest = Import-Csv (Join-Path $case.Path 'manifest.csv')
            $manifest.Count | Should -Be 2
            foreach ($entry in $manifest) {
                $actual = (Get-FileHash (Join-Path $case.Path $entry.RelativePath) -Algorithm SHA256).Hash
                $entry.SHA256 | Should -Be $actual
                $entry.RecordCount | Should -Be 2
            }
            @(Get-Content (Join-Path $case.Path 'raw' 'mailbox' 'jsmith_inboxrules.json') -Raw | ConvertFrom-Json).Count | Should -Be 2
        }
    }

    It 'Export-IRData records an empty collection as [] with no CSV' {
        InModuleScope EverythingIsFine {
            $case = New-IRCase -Reference 'empty'
            $files = @(Export-IRData -Category 'mailbox' -Name 'none' -Source 'test' -InputObject @())
            $files.Count | Should -Be 1
            (Get-Content (Join-Path $case.Path 'raw' 'mailbox' 'none.json') -Raw).Trim() | Should -Be '[]'
        }
    }

    It 'Export-IRData fails when no case is open' {
        InModuleScope EverythingIsFine {
            { Export-IRData -Category 'x' -Name 'y' -Source 'z' -InputObject @(1) } | Should -Throw '*No case is open*'
        }
    }

    It 'Close-IRCase hashes the activity log and stamps the close time' {
        InModuleScope EverythingIsFine {
            $case = New-IRCase -Reference 'close'
            $closed = Close-IRCase
            $closed.ClosedAtUtc | Should -Not -BeNullOrEmpty
            $script:IRContext.Case | Should -BeNullOrEmpty
            (Import-Csv (Join-Path $case.Path 'manifest.csv')).RelativePath | Should -Contain 'activity.jsonl'
        }
    }
}

Describe 'Tenant profile pinning' {
    BeforeEach {
        $env:EIF_DATA_ROOT = Join-Path $TestDrive ([guid]::NewGuid().ToString())
    }

    AfterEach {
        Remove-Item Env:EIF_DATA_ROOT -ErrorAction SilentlyContinue
    }

    It 'Keeps FirstSeen and Notes when a profile is updated' {
        InModuleScope EverythingIsFine -Parameters @{ Tid = $script:TenantA } {
            param($Tid)
            Set-IRTenantProfile -PrimaryDomain 'Contoso.com' -TenantId $Tid -DisplayName 'Contoso'
            $path = Get-IRTenantProfilePath -PrimaryDomain 'contoso.com'
            $first = Get-Content $path -Raw | ConvertFrom-Json
            $first.Notes = 'Primary contact: IT manager'
            $first | ConvertTo-Json | Set-Content $path

            Set-IRTenantProfile -PrimaryDomain 'contoso.com' -TenantId $Tid -DisplayName 'Contoso'
            $second = Get-IRTenantProfile -PrimaryDomain 'CONTOSO.COM'
            $second.FirstSeenUtc | Should -Be $first.FirstSeenUtc
            $second.Notes | Should -Be 'Primary contact: IT manager'
        }
    }
}

Describe 'Connect-IR tenant guard' {
    BeforeEach {
        $env:EIF_DATA_ROOT = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        InModuleScope EverythingIsFine -Parameters @{ Tid = $script:TenantA } {
            param($Tid)
            Mock Test-IRModuleDependency { }
            Mock Write-Host { }
            Mock Connect-MgGraph { }
            Mock Disconnect-MgGraph { }
            Mock Connect-ExchangeOnline { }
            Mock Disconnect-ExchangeOnline { }
            Mock Get-MgContext { [pscustomobject]@{ TenantId = '11111111-1111-1111-1111-111111111111'; Account = 'admin@contoso.com' } }
            Mock Get-MgOrganization {
                [pscustomobject]@{
                    Id = '11111111-1111-1111-1111-111111111111'; DisplayName = 'Contoso'
                    VerifiedDomains = @(
                        [pscustomobject]@{ Name = 'contoso.com'; IsDefault = $true }
                        [pscustomobject]@{ Name = 'contoso.onmicrosoft.com'; IsDefault = $false }
                    )
                }
            }
            Mock Get-ConnectionInformation { [pscustomobject]@{ TenantID = '11111111-1111-1111-1111-111111111111'; State = 'Connected' } }
            Mock Get-MgSubscribedSku { }
            Mock Get-AdminAuditLogConfig { [pscustomobject]@{ UnifiedAuditLogIngestionEnabled = $true } }
        }
    }

    AfterEach {
        InModuleScope EverythingIsFine { $script:IRContext = $null }
        Remove-Item Env:EIF_DATA_ROOT -ErrorAction SilentlyContinue
    }

    It 'Connects, pins the tenant and sets the context' {
        InModuleScope EverythingIsFine -Parameters @{ Tid = $script:TenantA } {
            param($Tid)
            $ctx = Connect-IR -Tenant 'contoso.com'
            $ctx.TenantId | Should -Be $Tid
            $ctx.PrimaryDomain | Should -Be 'contoso.com'
            $ctx.Capability.UnifiedAuditLogEnabled | Should -BeTrue
            (Get-IRTenantProfile -PrimaryDomain 'contoso.com').TenantId | Should -Be $Tid
        }
    }

    It 'Uses process-scoped tokens and read-only scopes by default' {
        InModuleScope EverythingIsFine {
            Connect-IR -Tenant 'contoso.com' | Out-Null
            Should -Invoke Connect-MgGraph -Times 1 -ParameterFilter {
                $ContextScope -eq 'Process' -and $Scopes -notcontains 'User.ReadWrite.All'
            }
        }
    }

    It 'Refuses when the requested domain is not in the signed-in tenant' {
        InModuleScope EverythingIsFine {
            { Connect-IR -Tenant 'fabrikam.com' } | Should -Throw '*Tenant guard*fabrikam.com*'
            $script:IRContext | Should -BeNullOrEmpty
        }
    }

    It 'Refuses when the domain is pinned to a different tenant ID' {
        InModuleScope EverythingIsFine -Parameters @{ Other = $script:TenantB } {
            param($Other)
            Set-IRTenantProfile -PrimaryDomain 'contoso.com' -TenantId $Other
            { Connect-IR -Tenant 'contoso.com' } | Should -Throw '*pinned*'
            $script:IRContext | Should -BeNullOrEmpty
        }
    }
}
