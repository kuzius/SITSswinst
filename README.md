# SITSswinst

Quick software installer for Windows. One command installs a curated set of
applications (VLC, 7-Zip, Adobe Acrobat Reader, and more over time) using
[winget](https://learn.microsoft.com/windows/package-manager/winget/) — the
Windows Package Manager built into Windows 10/11.

## Quick start (remote one-liner)

On any Windows 10/11 machine, in PowerShell:

```powershell
irm https://raw.githubusercontent.com/kuzius/SITSswinst/main/get.ps1 | iex
```

With **no keys provided**, this installs the full software bundle.

> Run PowerShell **as Administrator** for machine-wide installs.

## Requirements

- Windows 10 (1809+) or Windows 11
- `winget` / **App Installer** (preinstalled on current Windows; otherwise from
  the Microsoft Store)
- Internet connection

## Options (environment variables)

Because `irm | iex` can't take parameters, configuration is read from
environment variables set *before* the call:

| Variable | Effect |
| --- | --- |
| `$env:ONLY` | Comma-separated filter, e.g. `'VLC,7-Zip'` — install a subset only |
| `$env:LIST` | Any value — print the bundle and exit without installing |
| `$env:DEBUG` | Any value — verbose output with native winget progress. Default is quiet: one status line per package (`Installing X ... installed`) plus the final summary table. |
| `$env:ADOBE32` | Any value — install **32-bit** Adobe Acrobat Reader instead of the default 64-bit build. Only affects fresh installs: if either architecture is already on the machine, that copy is kept and upgraded — the other is never installed alongside. |
| `$env:OFFICE` | Any value — also preinstall **Office 2024 Home & Business (64-bit)**. Several-GB download (10–30 min); installs **unlicensed** — sign in with the owning Microsoft account (or enter a product key) after handover. |
| `$env:TVCUSTOM` | TeamViewer **custom module configuration id** — installs your customized (branded) full client instead of the plain winget package. See below. |
| `$env:TVASSIGN` | TeamViewer **assignment token** (Design & Deploy → Assignments) — after install, assigns the device to your account and grants easy access with no consent prompt. See below. |
| `$env:KEYS` | If set, takes the "keys provided" branch (reserved for future licensing/activation). If unset, the software bundle is installed. |

```powershell
# install only VLC
$env:ONLY='VLC'; irm https://raw.githubusercontent.com/kuzius/SITSswinst/main/get.ps1 | iex

# preview the bundle without installing
$env:LIST='1'; irm https://raw.githubusercontent.com/kuzius/SITSswinst/main/get.ps1 | iex

# verbose run (full winget output)
$env:DEBUG='1'; irm https://raw.githubusercontent.com/kuzius/SITSswinst/main/get.ps1 | iex

# full bundle + Office 2024 Home & Business preinstall
$env:OFFICE='1'; irm https://raw.githubusercontent.com/kuzius/SITSswinst/main/get.ps1 | iex
```

To clear an option afterwards: `Remove-Item Env:\ONLY` (or open a new shell).

## Run locally

You can also clone and run it directly:

```powershell
git clone https://github.com/kuzius/SITSswinst.git
cd SITSswinst
.\get.ps1
```

If PowerShell blocks the script, allow it for the current session:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
```

## Current bundle

| App | winget Id | Notes |
| --- | --- | --- |
| VLC media player | `VideoLAN.VLC` | |
| 7-Zip | `7zip.7zip` | |
| Adobe Acrobat Reader | `Adobe.Acrobat.Reader.64-bit` | 32-bit via `$env:ADOBE32` |
| TeamViewer | `TeamViewer.TeamViewer` | 32-bit client on 64-bit Windows is replaced with the 64-bit build |
| .NET 8 Desktop Runtime (x64) | `Microsoft.DotNet.DesktopRuntime.8.x64` | Dell only |
| Dell Command Update | `Dell.CommandUpdate` | Dell only |
| Lenovo System Update | `Lenovo.SystemUpdate` | Lenovo only |

**Vendor-specific packages** (marked above) install only on **matching
hardware**. The script checks `Win32_ComputerSystem.Manufacturer` at startup:
Dell packages install on Dell machines, Lenovo packages on Lenovo machines, and
everything else gets only the universal apps. Skipped packages are listed in the
final summary. Explicitly requesting one via `$env:ONLY` overrides the check.

> Note: winget always installs the **latest** version available — the bundle is
> not version-pinned, so it never needs a version refresh. Packages that are
> already installed (even at an older version) are **upgraded in place** rather
> than reinstalled; "already up to date" counts as success.

## TeamViewer: customized client + account assignment (opt-in)

Two independent, combinable steps:

**1. Install your customized (branded) client — `$env:TVCUSTOM`.** Create a
custom **Full Client** module in **Design & Deploy** and note its configuration
id (shown with the permanent link, e.g. `custom.teamviewer.com/a1b2c3d` → id
`a1b2c3d`). The script downloads that client from TeamViewer's design service
(the 64-bit build on 64-bit Windows) and installs it silently, removing any
existing client first.

**2. Assign to your account with easy access — `$env:TVASSIGN`.** A full
client's account assignment is otherwise an **interactive consent prompt** at
first launch, so easy access never turns on unattended. Provide an **assignment
token** — Management Console → **Design & Deploy → Assignments** → create one —
and the script runs `TeamViewer.exe assignment --id <token> --grant-easy-access`
after install, attaching the device and enabling easy access with no prompt.
After any successful TeamViewer step the script also ticks **Start TeamViewer
with Windows** (`AutoStartGUI`), so the client UI is present at logon.

> The assignment token is **not** the module's configuration id and **not** the
> deployment token embedded in the module page — it is the token from the
> Assignments page. Both token dialects work: classic `12345678-XXXX…` tokens
> (used with the legacy `assign --api-token` verb) and long `0001…` tokens
> (used with the newer `assignment --id` verb) — the script auto-detects.

```powershell
# customized client + non-interactive assignment & easy access
$env:TVCUSTOM='<your-config-id>'; $env:TVASSIGN='<assignment-token>'; irm https://raw.githubusercontent.com/kuzius/SITSswinst/main/get.ps1 | iex

# just assign an already-installed client (plain or custom)
$env:TVASSIGN='<assignment-token>'; irm https://raw.githubusercontent.com/kuzius/SITSswinst/main/get.ps1 | iex
```

> The assignment token grants devices into your account — treat it as a secret,
> keep it out of the public repo (pass it at runtime only), and prune unexpected
> devices in the Management Console.

## Office 2024 Home & Business (opt-in)

Office 2024 H&B is a retail perpetual SKU that winget does not carry, so
`$env:OFFICE='1'` installs it via the **Office Deployment Tool** instead: the
script downloads Microsoft's Click-to-Run bootstrapper from
`officecdn.microsoft.com`, generates a silent 64-bit configuration
(`HomeBusiness2024Retail`, OS display language with en-US fallback), and runs
it. Expect a several-GB download.

Licensing is intentionally not automated (yet): Office installs cleanly and
prompts for Microsoft-account sign-in or a product key on first launch. Note
that Office 2024 cannot coexist with Microsoft 365 apps on the same machine.

If the machine already has **Office 2019 or 2021** installed, the Office step
is **skipped entirely** (shown as `Skipped (Office 2019/2021 present)` in the
summary) — 2024 can't coexist with an older perpetual Office, and the existing
licensed installation is left untouched.

## Adding more software

Edit the `$Packages` list near the top of [`get.ps1`](get.ps1) and add a line:

```powershell
[pscustomobject]@{ Name = 'Google Chrome'; Id = 'Google.Chrome' }
```

Find the right `Id` with:

```powershell
winget search <name>
```
