# EverythingIsFine

[![checks](https://github.com/joshmckibben/EverythingIsFine/actions/workflows/checks.yml/badge.svg)](https://github.com/joshmckibben/EverythingIsFine/actions/workflows/checks.yml)

PowerShell 7 toolkit for Microsoft 365 business email compromise (BEC) response:
triage, containment, investigation and reporting, one client tenant at a time.

See [DESIGN.md](DESIGN.md) for the full design and roadmap. Current milestone: **M0 (skeleton)**.

## Using it on a work device (copy and paste)

No `.ps1` files need to run. You paste one file into a PowerShell 7 console.

**One-time setup** (in PowerShell 7):
```powershell
Install-Module Microsoft.Graph.Authentication, Microsoft.Graph.Identity.DirectoryManagement, Microsoft.Graph.Users, ExchangeOnlineManagement -Scope CurrentUser
```

**Each time:**
1. Open **PowerShell 7** (Start → type `pwsh`). Check `$PSVersionTable.PSVersion` shows 7.x.
2. Open [dist/EverythingIsFine.ps1](dist/EverythingIsFine.ps1) and click **Raw**.
3. Select all (Ctrl+A) and copy (Ctrl+C).
4. Paste into the console (Ctrl+V or right-click). If Windows Terminal warns about pasting
   multiple lines, choose **Paste anyway**.
5. Wait for `EverythingIsFine v… loaded.`, then:

```powershell
Connect-IR -Tenant contoso.com          # read-only; add -Elevated for containment
New-IRCase -Reference T12345 -Subject jsmith@contoso.com
# ... collectors arrive in M2 ...
Close-IRCase
Disconnect-IR
```

The functions only exist in that console window. Open a new window and you paste again.
Pasting again in the same window (for example after an update) keeps your connection and
any open case.

`Connect-IR` always clears existing sessions first and checks that Graph and Exchange
Online are signed in to the tenant you asked for. The first time it sees a domain it pins
that domain's tenant ID, and it refuses to connect if the domain later resolves to a
different tenant.

## Where data goes

Case evidence and tenant profiles are written to `$env:EIF_DATA_ROOT`
(default `~/EverythingIsFine-Data`), **never to this repo**. To point it at encrypted
storage, set this before `Connect-IR`:

```powershell
$env:EIF_DATA_ROOT = 'D:\Secure\eif-data'
```

```
Cases/<domain>/<utc-stamp>_<ref>/
  case.json  activity.jsonl  transcript.txt  manifest.csv
  raw/  snapshots/  reports/
```

## Development

Source lives in `src/` as a normal module. **Don't edit `dist/` by hand.** It's generated.

```powershell
./tools/Invoke-Checks.ps1   # rebuild dist/, PSScriptAnalyzer, Pester (Graph/EXO calls mocked)
```

GitHub Actions runs the same checks on Windows and Linux for every push, and fails if
`dist/EverythingIsFine.ps1` wasn't rebuilt after a change to `src/`.
