#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# Engineers load the toolkit by pasting dist/EverythingIsFine.ps1 into a console, not by importing
# the module. These tests build the paste file from the current source and load it in a fresh pwsh
# process (no module, global scope) to catch anything that only works inside a module.

BeforeAll {
    $script:PasteFile = Join-Path $TestDrive 'EverythingIsFine.ps1'
    & (Join-Path $PSScriptRoot '..' 'tools' 'Build-PasteFile.ps1') -OutputPath $script:PasteFile 6>$null

    $script:Pwsh = (Get-Process -Id $PID).Path

    # Runs $Body in a new pwsh after "pasting" the build. Stub Graph/EXO cmdlets are defined first.
    # Returns the object the body emits as its final line of JSON.
    function Invoke-InPastedSession {
        param(
            [Parameter(Mandatory)][string]$Body,
            [string]$BeforePaste = ''
        )

        $dataRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $script = Join-Path $TestDrive "$([guid]::NewGuid()).ps1"
        @"
`$ErrorActionPreference = 'Stop'
`$env:EIF_DATA_ROOT = '$dataRoot'
function Get-MgContext { [pscustomobject]@{ TenantId = '11111111-1111-1111-1111-111111111111'; Account = 'admin@contoso.com' } }
function Get-ConnectionInformation { [pscustomobject]@{ TenantID = '11111111-1111-1111-1111-111111111111'; State = 'Connected' } }
$BeforePaste
Invoke-Expression (Get-Content -LiteralPath '$($script:PasteFile)' -Raw)
$Body
"@ | Set-Content -LiteralPath $script -Encoding utf8

        # Dot-source via -Command so everything runs in the global scope, as it does in a console.
        $output = & $script:Pwsh -NoProfile -NonInteractive -Command ". '$script'" 2>&1
        $json = @($output | ForEach-Object { "$_" } | Where-Object { $_.StartsWith('{') }) | Select-Object -Last 1
        if (-not $json) { throw "No JSON result from pasted session. Output:`n$($output -join "`n")" }
        $json | ConvertFrom-Json
    }
}

Describe 'Paste build' {
    It 'Defines every public command' {
        $result = Invoke-InPastedSession -Body @'
$names = 'Connect-IR', 'Disconnect-IR', 'Get-IRContext', 'Get-IRCapability', 'Assert-IRTenant', 'New-IRCase', 'Close-IRCase'
[pscustomobject]@{ Missing = @($names | Where-Object { -not (Get-Command $_ -ErrorAction SilentlyContinue) }) } | ConvertTo-Json -Compress
'@
        @($result.Missing) | Should -BeNullOrEmpty
    }

    It 'Runs a case end to end outside a module, with the tool version recorded' {
        $result = Invoke-InPastedSession -Body @'
$script:IRContext = [pscustomobject]@{
    TenantId = '11111111-1111-1111-1111-111111111111'; PrimaryDomain = 'contoso.com'; DisplayName = 'Contoso'
    Account = 'admin@contoso.com'; SkipExchange = $false; Capability = $null; Case = $null
}
New-IRCase -Reference 'paste-test' | Out-Null
Export-IRData -Category 'mailbox' -Name 'rules' -Source 'test' -InputObject @([pscustomobject]@{ Name = '.' }) | Out-Null
$closed = Close-IRCase
[pscustomobject]@{
    ToolVersion = $closed.ToolVersion
    Manifest    = @(Import-Csv (Join-Path $closed.Path 'manifest.csv')).RelativePath
} | ConvertTo-Json -Compress
'@
        $result.ToolVersion | Should -Be (Import-PowerShellDataFile (Join-Path $PSScriptRoot '..' 'src' 'EverythingIsFine' 'EverythingIsFine.psd1')).ModuleVersion
        $result.Manifest | Should -Contain 'activity.jsonl'
        $result.Manifest | Should -Contain 'transcript.txt'
        ($result.Manifest -match 'rules\.json$').Count | Should -Be 1
    }

    It 'Keeps the tenant context when pasted a second time' {
        $result = Invoke-InPastedSession -Body @'
$script:IRContext = [pscustomobject]@{ TenantId = 'kept'; PrimaryDomain = 'contoso.com'; Case = $null }
Invoke-Expression (Get-Content -LiteralPath $env:EIF_PASTE_FILE -Raw)
[pscustomobject]@{ TenantId = (Get-IRContext).TenantId } | ConvertTo-Json -Compress
'@ -BeforePaste "`$env:EIF_PASTE_FILE = '$($script:PasteFile)'"
        $result.TenantId | Should -Be 'kept'
    }

    It 'Refuses to load in ConstrainedLanguage mode' {
        $result = Invoke-InPastedSession -BeforePaste '$ExecutionContext.SessionState.LanguageMode = ''ConstrainedLanguage''' -Body @'
@{ Loaded = [bool](Get-Command Connect-IR -ErrorAction SilentlyContinue) } | ConvertTo-Json -Compress
'@
        $result.Loaded | Should -BeFalse
    }
}

Describe 'Committed paste file' {
    It 'Is up to date with src/ (run tools/Build-PasteFile.ps1)' {
        $committed = Join-Path $PSScriptRoot '..' 'dist' 'EverythingIsFine.ps1'
        $committed | Should -Exist
        (Get-Content -LiteralPath $committed -Raw).Replace("`r`n", "`n") |
            Should -BeExactly (Get-Content -LiteralPath $script:PasteFile -Raw).Replace("`r`n", "`n")
    }
}
