<#
.SYNOPSIS
    Quick software installer using winget.

.DESCRIPTION
    Installs a curated list of applications (VLC, 7-Zip, Adobe Acrobat Reader,
    and any others added to the $Packages list below) via the Windows Package
    Manager (winget). Designed to be run once on a fresh machine.

    Add future software by appending to the $Packages array. Find winget IDs with:
        winget search <name>

.PARAMETER List
    Show the packages that would be installed, then exit without installing.

.PARAMETER Only
    Install only the packages whose Id or Name matches the supplied value(s).
    Example: .\Install-Software.ps1 -Only VLC,7-Zip

.EXAMPLE
    .\Install-Software.ps1
    Installs every package in the list.

.EXAMPLE
    .\Install-Software.ps1 -List
    Prints the package list without installing.

.NOTES
    Requires Windows 10/11 with winget (App Installer) and an internet connection.
    Run from an elevated PowerShell prompt for machine-wide installs.
#>

[CmdletBinding()]
param(
    [switch]$List,
    [string[]]$Only
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Package list. Add new software here. Id is the winget package identifier.
# ---------------------------------------------------------------------------
$Packages = @(
    [pscustomobject]@{ Name = 'VLC media player';      Id = 'VideoLAN.VLC' }
    [pscustomobject]@{ Name = '7-Zip';                 Id = '7zip.7zip' }
    [pscustomobject]@{ Name = 'Adobe Acrobat Reader';  Id = 'Adobe.Acrobat.Reader.64-bit' }
    # --- Add future software below, e.g.: ---
    # [pscustomobject]@{ Name = 'Google Chrome';       Id = 'Google.Chrome' }
    # [pscustomobject]@{ Name = 'Notepad++';           Id = 'Notepad++.Notepad++' }
    # [pscustomobject]@{ Name = 'Mozilla Firefox';     Id = 'Mozilla.Firefox' }
)

function Write-Step  { param($m) Write-Host "[*] $m" -ForegroundColor Cyan }
function Write-Ok    { param($m) Write-Host "[+] $m" -ForegroundColor Green }
function Write-Warn2 { param($m) Write-Host "[!] $m" -ForegroundColor Yellow }
function Write-Err   { param($m) Write-Host "[x] $m" -ForegroundColor Red }

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Err "winget (Windows Package Manager) was not found."
    Write-Warn2 "Install 'App Installer' from the Microsoft Store, then re-run this script."
    exit 1
}

# Filter the list if -Only was supplied
$toInstall = $Packages
if ($Only) {
    $toInstall = $Packages | Where-Object {
        foreach ($q in $Only) {
            if ($_.Id -like "*$q*" -or $_.Name -like "*$q*") { return $true }
        }
        return $false
    }
    if (-not $toInstall) {
        Write-Err "No packages matched: $($Only -join ', ')"
        exit 1
    }
}

# ---------------------------------------------------------------------------
# -List mode: just print and exit
# ---------------------------------------------------------------------------
if ($List) {
    Write-Step "Packages in this installer:"
    $toInstall | Format-Table Name, Id -AutoSize
    exit 0
}

# Warn if not elevated (machine-wide installs need admin)
$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Warn2 "Not running as Administrator - some packages may fail or install per-user."
    Write-Warn2 "For best results, run PowerShell as Administrator and re-run this script."
}

# ---------------------------------------------------------------------------
# Install loop
# ---------------------------------------------------------------------------
$results = @()
foreach ($pkg in $toInstall) {
    Write-Step "Installing $($pkg.Name) ($($pkg.Id)) ..."
    try {
        winget install --id $pkg.Id --exact `
            --accept-package-agreements `
            --accept-source-agreements `
            --silent
        $code = $LASTEXITCODE

        # winget: 0 = success, -1978335189 = already installed / no upgrade
        if ($code -eq 0) {
            Write-Ok "$($pkg.Name) installed."
            $results += [pscustomobject]@{ Name = $pkg.Name; Status = 'Installed' }
        }
        elseif ($code -eq -1978335189) {
            Write-Ok "$($pkg.Name) already installed / up to date."
            $results += [pscustomobject]@{ Name = $pkg.Name; Status = 'Already present' }
        }
        else {
            Write-Warn2 "$($pkg.Name) finished with exit code $code."
            $results += [pscustomobject]@{ Name = $pkg.Name; Status = "Exit $code" }
        }
    }
    catch {
        Write-Err "$($pkg.Name) failed: $($_.Exception.Message)"
        $results += [pscustomobject]@{ Name = $pkg.Name; Status = 'Failed' }
    }
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Write-Host ""
Write-Step "Summary:"
$results | Format-Table Name, Status -AutoSize
Write-Ok "Done."
