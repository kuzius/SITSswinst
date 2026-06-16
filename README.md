# SITSswinst

Quick software installer for Windows. Installs a curated set of applications
(VLC, 7-Zip, Adobe Acrobat Reader, and more over time) in one shot using
[winget](https://learn.microsoft.com/windows/package-manager/winget/) — the
Windows Package Manager built into Windows 10/11.

## Requirements

- Windows 10 (1809+) or Windows 11
- `winget` / **App Installer** (preinstalled on current Windows; otherwise grab it
  from the Microsoft Store)
- Internet connection
- Run from an **elevated** PowerShell prompt for machine-wide installs

## Usage

```powershell
# Install everything in the list
.\Install-Software.ps1

# See what would be installed, without installing
.\Install-Software.ps1 -List

# Install only specific apps (matches Name or winget Id)
.\Install-Software.ps1 -Only VLC,7-Zip
```

If PowerShell blocks the script, allow it for the current session:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
```

## Currently installed

| App | winget Id |
| --- | --- |
| VLC media player | `VideoLAN.VLC` |
| 7-Zip | `7zip.7zip` |
| Adobe Acrobat Reader | `Adobe.Acrobat.Reader.64-bit` |

## Adding more software

Edit the `$Packages` list near the top of
[`Install-Software.ps1`](Install-Software.ps1) and add a line:

```powershell
[pscustomobject]@{ Name = 'Google Chrome'; Id = 'Google.Chrome' }
```

Find the right `Id` with:

```powershell
winget search <name>
```
