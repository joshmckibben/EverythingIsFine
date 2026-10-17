# Lab environment

How to build and use a dedicated Microsoft 365 test tenant for EverythingIsFine: create it,
plant fake compromise artefacts, simulate attacker activity, and reset.

> **The lab is never a client tenant and never your MSP's own tenant.** It exists only to be
> "compromised" on purpose.

Development and lab work run on the Ubuntu desktop (PowerShell 7). A Windows VM is only needed
later, to check the work-device paste experience (see the end of this file).

---

## 1. Create the tenant (about 30 minutes, then a few hours of provisioning)

**Before you start:**
- Use a **personal** email address as the sign-up contact, not your work one.
- Pick the tenant name carefully. It becomes `<name>.onmicrosoft.com` **permanently**. Use something
  neutral like `eiflab-jm`, never a client or MSP name.
- Have a payment card ready. The trial needs one.

**Steps:**
1. Go to the Microsoft 365 **Business Standard** product page and choose **Try free for one month**
   (or **Buy now**). The trial includes 25 licences for one month.
2. Enter your personal email, then choose **Set up account**.
3. Fill in your name, a company name (e.g. `EIF Lab`) and a company size of 1. Verify by text message.
4. **Create your business identity:** enter the tenant name from above. Then create the first username
   (e.g. `labadmin`) and a strong password, and store them in your password manager.
   This account is the tenant's **Global Administrator**.
5. Add the payment method and finish. Skip the "add your own domain" step; `onmicrosoft.com` is fine.
6. Sign in at **admin.microsoft.com** as `labadmin` and set up MFA when asked. New tenants have
   **security defaults** on, which enforces MFA. Leave them on.
7. **Set a calendar reminder** for a few days before the trial ends. Reduce to the licences you're
   keeping (section 2) so you aren't billed for 25.

## 2. Licences and cost

The lab only needs **one paid licence** long term:

| Account | Licence | Why |
|---|---|---|
| Victim user | Business Standard | Needs a mailbox and can sign in. Plays the compromised account |
| Executive | **None**: create it as a **shared mailbox** | Shared mailboxes are free and work for the delegation artefacts |
| Admin accounts | **None** | Admin roles work without a licence. Remove the licence the sign-up assigned to `labadmin` |

Check Microsoft's current pricing; Business Standard has been around US$12.50 per user per month.

**Testing other licence tiers later:** a Standard-only tenant is deliberately the default, because it's
the only way to test the toolkit's fallbacks when Premium features are missing. To test Premium or E3
behaviour, temporarily add a **Business Premium** (or Entra ID P1) trial. The toolkit's capability
summary should change accordingly. When the trial lapses, the tenant drops back to Standard.

## 3. Accounts to create

In **admin.microsoft.com**:

1. **Users → Active users → Add a user:**
   - `alex`, the victim. Assign the **Business Standard** licence. Sign in once as alex
     (private browser window) to set up MFA with the Authenticator app.
   - `eif-reader`, the read-only operator. **No licence.** Roles: **Global Reader** and
     **Security Reader**. Use this account for normal (non-`-Elevated`) toolkit runs. It tests the
     least-privilege role set, and we'll adjust the roles if a collector needs more.
   - Optional: 3–5 **unlicensed** users (e.g. `finance`, `hr`, `it`) so the directory isn't empty.
2. **Teams & groups → Shared mailboxes → Add a shared mailbox:** `ceo`, the executive.
3. Remove the licence from `labadmin` and assign it to alex (if the sign-up gave it to labadmin).

## 4. Wait for Exchange, check auditing

- Exchange Online can take a few hours to finish provisioning in a new tenant. It's ready when
  alex's mailbox opens at outlook.office.com.
- Run `Connect-IR` (section 6). The capability summary must show **Unified audit log ingestion: yes**.
  If it says NO, go to the **Microsoft Purview** portal → **Audit** and choose
  **Start recording user and admin activity**. Then wait up to a few hours.

## 5. One-time setup on Ubuntu

In `pwsh`:

```powershell
Install-Module Microsoft.Graph.Authentication, Microsoft.Graph.Identity.DirectoryManagement, Microsoft.Graph.Users, Microsoft.Graph.Applications, Microsoft.Graph.Identity.SignIns, ExchangeOnlineManagement -Scope CurrentUser
```

Keep your own lab notes (tenant name, account names, attacker IPs and times) in a file **outside
the repo**, for example `~/EverythingIsFine-Data/lab-notes.md`. The repo is public.

## 6. Mark the tenant as a lab (once)

From the repo folder:

```powershell
Import-Module ./src/EverythingIsFine/EverythingIsFine.psd1 -ArgumentList Lab -Force
Connect-IR -Tenant <name>.onmicrosoft.com -Elevated      # sign in as labadmin
Enable-IRLabTenant -ConfirmDomain <name>.onmicrosoft.com
```

- `-Elevated` asks for write permissions, so the consent screen lists more than in a read-only
  run. That's expected in the lab. Leave **Consent on behalf of your organization** unticked.
- `Enable-IRLabTenant` only works if you type the tenant's `onmicrosoft.com` domain exactly and the
  tenant has 50 users or fewer. It creates an app registration called **EIF-LAB-MARKER** (no
  permissions, no credentials) and marks the tenant as a lab in your local profile.

The lab tools refuse to run unless **all** of these are true:
1. the session is `-Elevated`;
2. the local profile is marked as a lab;
3. the EIF-LAB-MARKER app exists in the tenant;
4. the tenant has 50 users or fewer.

Deleting the marker app disables the lab tools for that tenant.

## 7. Seed the compromise

```powershell
Invoke-IRLabSeed -Victim alex@<name>.onmicrosoft.com -Executive ceo@<name>.onmicrosoft.com
Get-IRLabState        # what's currently planted
```

What gets planted, and when the toolkit should find it:

| # | Artefact | Toolkit should detect it in |
|---|---|---|
| 1 | Inbox rule `.`: invoice/payment mail moved to **RSS Feeds**, marked read | M2 user triage, M3 sweep |
| 2 | Inbox rule `..`: security/password warnings **deleted** | M2, M3 |
| 3 | Inbox rule `Inbox`: remittance mail **forwarded** to `ap-collect@example.com` | M2, M3 |
| 4 | Mailbox forwarding to `mailsync@example.com`, keeping a copy | M1 readiness (if org forwarding allowed), M2, M3 |
| 5 | Victim's **Inbox shared with Default** (everyone) as Reviewer | M2 |
| 6 | Victim granted **FullAccess** on the `ceo` mailbox | M2, M3 |
| 7 | Victim granted **SendAs** on the `ceo` mailbox | M2, M3 |
| 8 | Transport rule **Compliance Archive** BCC'ing victim's payment mail to `archive@example.com` | M3 |
| 9 | Extra **phone MFA method** (+1 202 555 0143) on the victim | M2 |
| 10 | App **Mail Sync Pro** with a client secret, plus a delegated **consent grant** (Mail.ReadWrite, Mail.Send, offline_access) for the victim | M2, M3 |

- `example.com` is reserved and can't receive mail. Nothing leaves the lab to a real third party.
- The 555-01xx phone range is reserved for fiction.
- If a step fails, the rest still run. Anything created is recorded, so cleanup handles partial runs.
- Seeding refuses to run twice; clean up first, or use `-Force` to add a second set.

## 8. Simulate the attacker (manual, about 15 minutes)

Scripts can create the artefacts, but realistic **sign-in and mailbox activity logs** need a real
person in a browser. Do this after seeding:

1. **Change network** so the "attacker" has a different IP: a commercial VPN exiting in another
   country, your phone's hotspot (with your desktop's normal connection off), or a cheap cloud VM.
   Write down the public IP (search "what is my IP") and the time.
2. In a **private browser window**, sign in to **outlook.office.com** as alex. MFA prompts are
   fine; we're simulating the attacker's actions, not the bypass.
3. Open a few messages. **Search** for `invoice`, `payment` and `bank details`.
4. Send 5–10 messages from alex with subjects like `Updated bank details for invoice 1043`, to the
   `ceo` mailbox and to `test@example.com`. (The `example.com` ones will bounce. That's fine, and it
   looks like a real phishing burst.)
5. Sign out. Record the IP, time and browser in your lab notes. These become your **IOCs** for
   testing the M3 IP pivot.
6. Back on your normal network, send alex a message containing `invoice` from another account.
   Rule `.` should move it to **RSS Feeds**, which proves the rule works.

Audit events can take **30 minutes to 24 hours** to appear, so run the toolkit's log-based checks the
next day.

## 9. Reset

```powershell
Invoke-IRLabCleanup                  # removes / restores everything recorded, newest first
Invoke-IRLabCleanup -IncludeOrphans  # also deletes untracked EIF-LAB apps (never the marker)
```

- Anything that fails stays recorded, so just run cleanup again after fixing the cause.
- Artefacts already removed (by hand, or later by the toolkit's containment) count as cleaned.
- Logs can't be undone: past sign-ins and audit events stay in the tenant. That's fine; old incidents
  are realistic too. Keep your lab notes up to date so you know which activity was which run.

## 10. Windows VM (later, for the work-device experience)

Only needed to check the Windows sign-in prompt, pasting into Windows Terminal, and Windows paths.

- **Hypervisor:** `virt-manager` (KVM), or **quickemu**. `quickget windows 11` downloads the ISO and
  sets up TPM and Secure Boot.
- **Licence:** Windows 11 Enterprise 90-day evaluation (Microsoft Evaluation Center), or an MSP licence.
- **Size:** 4 vCPU, 8 GB RAM, 80 GB disk. Install PowerShell 7 and the modules, then take a **clean snapshot**.
- **Test:** paste `dist/EverythingIsFine.ps1` from GitHub Raw and run `Connect-IR` as `eif-reader`.
