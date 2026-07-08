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
| `$env:DEBUG` | Any value — verbose output (per-package progress + native winget output). Default is quiet: only the final summary table is shown. |
| `$env:KEYS` | If set, takes the "keys provided" branch (reserved for future licensing/activation). If unset, the software bundle is installed. |

```powershell
# install only VLC
$env:ONLY='VLC'; irm https://raw.githubusercontent.com/kuzius/SITSswinst/main/get.ps1 | iex

# preview the bundle without installing
$env:LIST='1'; irm https://raw.githubusercontent.com/kuzius/SITSswinst/main/get.ps1 | iex

# verbose run (full winget output)
$env:DEBUG='1'; irm https://raw.githubusercontent.com/kuzius/SITSswinst/main/get.ps1 | iex
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
| Adobe Acrobat Reader | `Adobe.Acrobat.Reader.64-bit` | |
| TeamViewer | `TeamViewer.TeamViewer` | |
| .NET 8 Desktop Runtime (x64) | `Microsoft.DotNet.DesktopRuntime.8.x64` | Dell only |
| Dell Command Update | `Dell.CommandUpdate` | Dell only |
| Lenovo System Update | `Lenovo.SystemUpdate` | Lenovo only |

**Vendor-specific packages** (marked above) install only on **matching
hardware**. The script checks `Win32_ComputerSystem.Manufacturer` at startup:
Dell packages install on Dell machines, Lenovo packages on Lenovo machines, and
everything else gets only the universal apps. Skipped packages are listed in the
final summary. Explicitly requesting one via `$env:ONLY` overrides the check.

> Note: winget always installs the **latest** version available — the bundle is
> not version-pinned, so it never needs a version refresh.

## Adding more software

Edit the `$Packages` list near the top of [`get.ps1`](get.ps1) and add a line:

```powershell
[pscustomobject]@{ Name = 'Google Chrome'; Id = 'Google.Chrome' }
```

Find the right `Id` with:

```powershell
winget search <name>
```
