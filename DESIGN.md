# EverythingIsFine — Design

A PowerShell 7 toolkit for triaging, containing, investigating and reporting on
Microsoft 365 business email compromise (BEC), built for an MSP security team.

Status: **M0 (skeleton)**. Last updated 2026-10-16.

---

## 1. Goals

1. Give any engineer on the team a repeatable, guided BEC response that works the
   same way in every client tenant.
2. Never act on the wrong tenant.
3. Preserve evidence by default: collect before changing anything, snapshot before
   every change, never delete what an attacker created.
4. Degrade gracefully across licence tiers. Always tell the operator what the
   tenant can and cannot show.
5. Produce a report a client or insurer can read.

### Non-goals (for now)

- A GUI. Operators are M365-literate engineers, so a CLI with clear prompts is enough.
  Keep the module UI-agnostic (functions return objects) so a UI can be added later.
- Multi-tenant automation via GDAP or an app registration. We use per-tenant admin
  credentials.
- Endpoint forensics. This toolkit covers the cloud tenant only.
- Replacing a SIEM or Defender XDR where a client has one.

## 2. Constraints

| Constraint | Consequence |
|---|---|
| MSP, separate admin credentials per tenant | Interactive delegated auth, one tenant per session, strict tenant guard |
| Licences: Business Standard / Business Premium / E3 | No Entra ID P2 anywhere; Standard has no P1. Every collector needs a fallback |
| Built before an incident, not during one | Readiness scan comes first (M1) and runs against every client ahead of time |
| Operators are engineers | CLI, guided mode plus direct functions, `-WhatIf` on containment |
| Engineers use Windows and Linux | PowerShell 7 only, no WPF/WinForms, no Windows-only modules |

## 3. Dependencies

| Module | Purpose | Notes |
|---|---|---|
| `Microsoft.Graph.Authentication` + sub-modules | Entra ID, sign-ins, apps, MFA methods | Load only the sub-modules we need, not the `Microsoft.Graph` meta-module |
| `ExchangeOnlineManagement` ≥ 3.4 | Mailboxes, rules, message trace, audit log | `Connect-IPPSSession` (same module) for compliance search and purge |
| Pester 5, PSScriptAnalyzer | Tests and linting | Dev only |

Do not use: `MSOnline` or `AzureAD` (retired), or EXO v1 / basic-auth modules.

Check periodically for deprecations:
- `Get-MessageTrace` → `Get-MessageTraceV2`.
- `Search-UnifiedAuditLog` → the Graph audit log query API (`/security/auditLog/queries`).

The audit log collector should hide which backend it uses behind one function so we
can switch without changing callers.

## 4. Architecture

```
EverythingIsFine/                 (repo: code only, never evidence)
├── src/EverythingIsFine/
│   ├── EverythingIsFine.psd1/.psm1
│   ├── Public/                   exported functions (one per file)
│   └── Private/                  helpers
├── dist/EverythingIsFine.ps1      PASTE BUILD - what engineers actually run (generated)
├── tests/                        Pester, all external cmdlets mocked; paste build tested too
├── tools/Build-PasteFile.ps1     src/ -> dist/ paste build
├── tools/Invoke-Checks.ps1       build + lint + test
└── .github/workflows/checks.yml  CI on Windows + Linux for every push

$EIF_DATA_ROOT  (default ~/EverythingIsFine-Data — outside the repo)
├── tenants/<domain>.json         tenant profiles (pinned tenant ID, capabilities, notes)
└── Cases/<domain>/<utc-stamp>_<ref>/
    ├── case.json                 case metadata
    ├── activity.jsonl            everything the tool did, one JSON line per event
    ├── transcript.txt            PowerShell transcript
    ├── manifest.csv              SHA256 of every evidence file
    ├── raw/<category>/*.json|csv collected data
    ├── snapshots/                state captured before each containment action
    └── reports/                  generated HTML / timeline
```

Evidence and client identifiers **never** go into git. The data root lives outside
the repo on purpose.

### Distribution: paste build

Engineers can't run unsigned `.ps1` files on their work devices, and code pasted into a
console isn't subject to signing. So for now **the paste build is the product**:

1. Open `dist/EverythingIsFine.ps1` on GitHub (Raw), select all, copy.
2. Paste into a PowerShell 7 console. Every function is defined in that session.

How the paste file behaves:
- `tools/Build-PasteFile.ps1` concatenates `src/` into one dot-sourced script block,
  `. { ... }`. The console treats it as a single statement, so it all loads or none of it does.
- The header refuses to load under Windows PowerShell 5.1 or ConstrainedLanguage mode
  (AppLocker/WDAC), with a clear message.
- Pasting it again (e.g. after an update) keeps the current tenant context and open case.
- The output has no timestamps, so it's deterministic. CI fails if the committed `dist/`
  file doesn't match `src/`.

Rules this puts on source code:
- No reliance on `$PSScriptRoot`, `$MyInvocation.MyCommand.Module` or other module or
  script-file context inside functions. Module state lives in `$script:` variables, which
  resolve to the global scope when pasted.
- Here-strings are fine (lines are copied verbatim).
- `tests/PasteBuild.Tests.ps1` loads the build in a fresh `pwsh` (global scope, no module)
  and runs a case end to end.

**Long term:** when this moves to a private repo in the MSP's organisation, sign the module
with the organisation's code-signing certificate and import it normally. Keep the paste build
as a fallback.

Avoid `iex (irm <url>)` loaders. EDR flags them, and they run whatever is live on GitHub
rather than a version the engineer chose.

### Conventions

- Prefix all public functions with `IR` (`Get-IRInboxRule`, `Disable-IRUser`, ...).
- Collectors return objects **and** write them to the case through `Export-IRData`,
  which stores JSON (source of truth) plus CSV (convenience) and adds hashes to the
  manifest.
- Store all timestamps in UTC, ISO 8601.
- Each collector records its `Source`, e.g. `Graph:auditLogs/signIns` or
  `UAL:UserLoggedIn`, so the report can say which data path was used.
- Console output goes through `Write-IRLog`, which also writes to `activity.jsonl`.

## 5. Authentication and the tenant guard

The main operational risk for an MSP is acting on the wrong client.

1. `Connect-IR -Tenant <domain|id>` always calls `Disconnect-IR` first, so no stale
   Graph or EXO session can carry over.
2. Graph connects with `-ContextScope Process`, so tokens aren't cached across
   PowerShell sessions.
3. After connecting, it resolves the organisation and checks that the requested domain
   or ID belongs to that tenant.
4. It connects EXO with the same account, then checks that
   `Get-ConnectionInformation` reports the same tenant ID.
5. **Trust on first use:** on first connect, the tenant ID is pinned in
   `tenants/<domain>.json`. A later connect where the domain resolves to a different
   tenant ID is refused.
6. `Assert-IRTenant` runs at the start of every collector and every containment
   action. It re-checks the live Graph and EXO sessions against the case's tenant.
7. Every confirmation prompt is prefixed with the tenant domain:
   `[contoso.com] Disable 3 inbox rules for jsmith@contoso.com? (y/N)`.

**Permission tiers:**

- **ReadOnly** (default): read scopes only. Suits Global Reader + Security Reader +
  View-Only Audit Logs.
- **Elevated** (`-Elevated`): adds write scopes for containment. You must reconnect
  explicitly, so nobody slides into write access by accident.

Use interactive browser sign-in. Avoid device code flow: it's often blocked by
Conditional Access, and attackers abuse it in phishing.

The "Microsoft Graph Command Line Tools" enterprise app needs admin consent once per
tenant. The readiness scan (M1) takes care of that before an incident.

## 6. Licence capability model

At connect time, `Get-IRCapability` reads subscribed SKUs and service plans and
derives capability flags. Every collector picks its data source from these flags and
records which one it used.

| Capability | Detected by (service plan) | Std | Prem | E3 | Fallback when absent |
|---|---|---|---|---|---|
| Entra ID P1 | `AAD_PREMIUM` | ✗ | ✓ | ✓ | — |
| Sign-in logs via Graph (30d) | P1 | ✗ | ✓ | ✓ | UAL `UserLoggedIn` / `UserLoginFailed` (~180d, less detail) |
| Conditional Access | P1 | ✗ | ✓ | ✓ | Per-user block + session revoke; security defaults |
| Entra ID P2 / risk data | `AAD_PREMIUM_P2` | ✗ | ✗ | ✗ | Our own heuristics (ASN, geo, user agent, impossible travel) |
| Defender for Office 365 P1 | `ATP_ENTERPRISE` | ✗ | ✓ | ✗ | EOP only |
| Defender for Office 365 P2 (Explorer) | `THREAT_INTELLIGENCE` | ✗ | ✗ | ✗ | Message trace |
| Audit (Premium) | `M365_ADVANCED_AUDITING` | ✗ | ✗ | ✗ | Audit Standard (180d) |
| Unified audit log ingestion | `Get-AdminAuditLogConfig` | ? | ? | ? | **Nothing.** If it's off, flag it as critical |
| `MailItemsAccessed` present | Probe the UAL for recent events | ? | ? | ? | Report as "not available" |

> Verify the service plan names and licence mappings against a real tenant of each
> tier during M1. Microsoft changes these over time.

## 7. Functional scope by phase

### Phase 0: Preflight (M0)
- `Connect-IR` / `Disconnect-IR`: tenant guard, capability detection, dependency check.
- `New-IRCase` / `Close-IRCase`: case folder, transcript, manifest.
- `Get-IRCapability`.

### Phase 1: Readiness scan (M1, run proactively against every client)
`Invoke-IRReadiness` writes a tenant profile and a findings report:
- Unified audit log enabled; audit retention; mailbox auditing on by default.
- Outbound spam policy: automatic external forwarding blocked.
- MFA: security defaults or Conditional Access coverage; legacy auth blocked.
- User consent to apps restricted; admin consent workflow.
- SMTP AUTH, POP and IMAP status (org-level and per mailbox).
- Admin role holders: count, and whether they're licensed or shared mailboxes.
- DKIM signing enabled; DMARC and SPF records (DNS lookup).
- External sender tagging.
- Licence tier and capability profile, i.e. what we'll be blind to in an incident.

### Phase 2: Single-user triage (M2, read-only)
`Invoke-IRUserTriage -User <upn> [-Days n]` collects:
- **Sign-ins:** IP, country, ASN, user agent, client app, legacy auth, success or
  failure. Graph when P1, otherwise UAL.
- **Authentication methods:** registered methods and when they were added.
  Flag anything added during the suspected window.
- **Inbox rules, including hidden rules:**
  - Flag names like `.` / `..` / single characters.
  - Flag actions that move mail to RSS Feeds, Archive, Conversation History or
    Deleted Items, or that delete it.
  - Flag keywords such as invoice, payment, wire, bank, remittance, or the CEO's name.
- **Mailbox config:** `ForwardingSmtpAddress`, `ForwardingAddress`,
  `DeliverToMailboxAndForward`, FullAccess / SendAs / SendOnBehalf, folder permissions.
- **Mobile devices and EAS partnerships.**
- **Message trace:** outbound volume per day, external recipients, and spikes that
  suggest a phishing blast.
- **UAL for the user**, filtered to the key operations:
  - Rules: `New-InboxRule`, `Set-InboxRule`, `UpdateInboxRules`.
  - Mailbox changes: `Set-Mailbox`, `Add-MailboxPermission`, `Add-RecipientPermission`.
  - Mail access and sending: `MailItemsAccessed`, `Send`, `SendAs`,
    `SearchQueryInitiatedExchange`.
  - Files: `FileDownloaded`, `FileAccessed`, `AnonymousLinkCreated`, `SharingSet`.
  - Apps and accounts: `Consent to application`,
    `Add delegated permission grant`, `Reset user password`,
    `User registered security info`.

### Phase 3: Tenant sweep and IOC pivot (M3, read-only)
- Inbox rules and forwarding across **every** mailbox, using the same heuristics.
- Transport rules, connectors, accepted and remote domains.
- **OAuth apps:**
  - Consent grants and service principals created or changed recently.
  - App credentials added recently.
  - A maintained watchlist of apps commonly abused in BEC (eM Client, PERFECTDATA
    SOFTWARE, Newsletter Software Supermailer, SigParser, rclone, ...).
- **Directory audit log:** new users, role assignments, CA policy changes, named
  locations, domain federation changes, and changes to app or service principal
  credentials.
- **IOC pivot:** `Find-IRIndicator -IPAddress ... -UserAgent ...` lists every
  account and operation touched by those indicators.

### Phase 4: Analysis and reporting (M4)
- **Timeline:** merge sign-ins, UAL, directory audit and message trace into one
  UTC timeline (CSV + HTML).
- **IP enrichment:** country and ASN, and whether it's a hosting provider or VPN.
  Offline MaxMind GeoLite2 by default; an online API is optional.
- **Impossible travel** computed from sign-in pairs.
- **Rule-based scoring:** each finding gets a severity (Info / Suspicious /
  Likely malicious / Confirmed) and a short explanation of why.
- **HTML report:** executive summary, scope, timeline, findings, actions taken (from
  `activity.jsonl`), capability gaps, and the evidence manifest.

### Phase 5: Containment (M5, elevated)
Every action follows the same pattern:

1. `Assert-IRTenant`
2. Snapshot the current state to `snapshots/`
3. Confirm, with the tenant domain in the prompt (`ConfirmImpact = 'High'`,
   `-WhatIf` supported)
4. Act
5. Log the action to `activity.jsonl` with the information needed to undo it

Actions:
- **Account:**
  - Revoke sessions, reset password, block sign-in.
  - Remove MFA methods added by the attacker.
  - Note: revoking does **not** invalidate access tokens already issued (up to about
    an hour without CAE), and AiTM token theft can survive a password reset unless
    sessions are revoked as well.
- **Mailbox:**
  - Disable malicious inbox rules (export them first; never delete).
  - Remove forwarding and rogue delegates.
  - Temporarily disable OWA, EWS, POP, IMAP or ActiveSync for the mailbox.
- **Apps:** revoke OAuth grants; disable the malicious service principal.
- **Network and mail flow:**
  - Block IPs with a CA named location (P1 only).
  - Block a sender or domain in the Tenant Allow/Block List.
- **Mail cleanup:** search and purge internally delivered phishing
  (`New-ComplianceSearch` + `New-ComplianceSearchAction -Purge`), with a
  confirmation step that shows the hit count before purging.

### Phase 6: Guided mode (alongside M2–M5)
`Start-IRCase` is a numbered menu that walks through the phases: Connect → Open case
→ Triage user(s) → Sweep → Review findings → Contain → Report → Close.

Every step calls the same public functions, so experienced engineers can skip the
menu entirely.

## 8. Data handling rules

- The tool never deletes attacker artefacts. It exports, then disables.
- Write JSON with `-Depth 10` and store the raw API output, not reshaped objects.
  Do the reshaping in analysis.
- Hash every evidence file into `manifest.csv` as it's written. `Close-IRCase` hashes
  the transcript and the activity log last.
- Case folders contain client personal data (email subjects, IPs, names). Store them
  on encrypted disks and follow the MSP's retention policy. Never commit them.

## 9. Testing strategy

- **Unit (Pester 5):** every function, with all Graph and EXO cmdlets mocked. The
  focus is the tenant guard, capability derivation, heuristics (rule flagging,
  scoring) and evidence writing.
- **Fixtures:** sanitised JSON samples of real API output under
  `tests/fixtures/`, used to test parsers and heuristics.
- **Lab tenant:** a dedicated Business Standard tenant (see [LAB.md](LAB.md)).
  The lab feature (`Import-Module ... -ArgumentList Lab`, never in the paste build) plants
  10 fake compromise artefacts and removes them again. It's guarded by an elevated session,
  a local IsLab flag, an in-tenant marker app and a 50-user limit. Attacker sign-ins and
  mailbox activity are simulated manually from another network.
- **Lint:** PSScriptAnalyzer with `PSScriptAnalyzerSettings.psd1`.
- `tools/Invoke-Checks.ps1` rebuilds the paste file, then runs lint and tests.
- **CI** (GitHub Actions) runs the same checks on `windows-latest` and `ubuntu-latest` for
  every push, and checks the committed paste file is current. Engineers don't need to run
  tests on their work devices.

## 10. Roadmap

| # | Milestone | Exit criteria |
|---|---|---|
| M0 | Skeleton | Connect, tenant guard, capability check, case folder, evidence writer, tests pass |
| M0.5 | Lab tenant tooling | `Enable-IRLabTenant`, `Invoke-IRLabSeed`, `Invoke-IRLabCleanup` with lab guards; lab tenant built per LAB.md |
| M1 | Readiness scan | Run against every client tenant; tenant profiles and readiness reports produced |
| M2 | Single-user triage | All Phase 2 collectors, with fallbacks, validated in the lab tenant |
| M3 | Tenant sweep + IOC pivot | Planted lab artefacts all detected |
| M4 | Timeline + report | HTML report produced from a lab case |
| M5 | Containment | Every action snapshotted, confirmed, logged and undoable in the lab |
| M6 | Runbook + tabletop | Written BEC runbook; team drill run in the lab tenant |

## 11. Open questions

- IP enrichment: is offline GeoLite2 alone enough, or do we want an online API key?
- Where do case folders live: each engineer's laptop or a shared encrypted location?
- Should the readiness scan output feed into client reporting or QBRs?
- Report branding: MSP-branded or neutral?
