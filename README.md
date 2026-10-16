# EverythingIsFine

PowerShell 7 toolkit for Microsoft 365 business email compromise (BEC) response:
triage, containment, investigation and reporting, one client tenant at a time.

See [DESIGN.md](DESIGN.md) for the full design and roadmap. Current milestone: **M0 (skeleton)**.

## Requirements

- PowerShell 7.2+ (Windows, Linux or macOS)
- Modules:
  ```powershell
  Install-Module Microsoft.Graph.Authentication, Microsoft.Graph.Identity.DirectoryManagement, Microsoft.Graph.Users, ExchangeOnlineManagement -Scope CurrentUser
  ```
- An admin account in the client tenant. Read-only work needs Global Reader, Security Reader and View-Only Audit Logs.

## Quick start

```powershell
Import-Module ./src/EverythingIsFine/EverythingIsFine.psd1

Connect-IR -Tenant contoso.com          # read-only; add -Elevated for containment
New-IRCase -Reference T12345 -Subject jsmith@contoso.com
# ... collectors arrive in M2 ...
Close-IRCase
Disconnect-IR
```

`Connect-IR` always clears existing sessions first and checks that Graph and Exchange
Online are signed in to the tenant you asked for. The first time it sees a domain it pins
that domain's tenant ID, and it refuses to connect if the domain later resolves to a
different tenant.

## Where data goes

Case evidence and tenant profiles are written to `$env:EIF_DATA_ROOT`
(default `~/EverythingIsFine-Data`), **never to this repo**. Point it at encrypted storage:

```powershell
$env:EIF_DATA_ROOT = '/secure/eif-data'
```

```
Cases/<domain>/<utc-stamp>_<ref>/
  case.json  activity.jsonl  transcript.txt  manifest.csv
  raw/  snapshots/  reports/
```

## Development

```powershell
./tools/Invoke-Checks.ps1   # PSScriptAnalyzer + Pester (all Graph/EXO calls are mocked)
```
