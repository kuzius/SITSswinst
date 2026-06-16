<#
    SITSswinst - remote quick installer

    Run on any Windows 10/11 machine with:

        irm https://raw.githubusercontent.com/kuzius/SITSswinst/main/get.ps1 | iex

    Default behaviour (NO keys provided): installs the software bundle
    (VLC, 7-Zip, Adobe Acrobat Reader, ...) via winget.

    Because `irm | iex` cannot pass parameters, configuration is read from
    environment variables set before the call:

        $env:KEYS  - if set, takes the "keys provided" branch (see below).
                     If empty/unset, the software bundle is installed.
        $env:ONLY  - comma-separated filter, e.g. 'VLC,7-Zip' to install a subset.
        $env:LIST  - any value -> just print the bundle and exit (no install).

    Examples:
        # install everything
        irm https://raw.githubusercontent.com/kuzius/SITSswinst/main/get.ps1 | iex

        # install only VLC
        $env:ONLY='VLC'; irm https://raw.githubusercontent.com/kuzius/SITSswinst/main/get.ps1 | iex
#>

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Software bundle. Add new apps here. Id is the winget package identifier
# (find one with:  winget search <name>).
# ---------------------------------------------------------------------------
$Packages = @(
    [pscustomobject]@{ Name = 'VLC media player';     Id = 'VideoLAN.VLC' }
    [pscustomobject]@{ Name = '7-Zip';                Id = '7zip.7zip' }
    [pscustomobject]@{ Name = 'Adobe Acrobat Reader'; Id = 'Adobe.Acrobat.Reader.64-bit' }
    [pscustomobject]@{ Name = '.NET 8 Desktop Runtime (x64)'; Id = 'Microsoft.DotNet.DesktopRuntime.8.x64'; DellOnly = $true }
    [pscustomobject]@{ Name = 'Dell Command Update'; Id = 'Dell.CommandUpdate'; DellOnly = $true }
    # --- Add future software below, e.g.: ---
    # [pscustomobject]@{ Name = 'Google Chrome';      Id = 'Google.Chrome' }
    # [pscustomobject]@{ Name = 'Notepad++';          Id = 'Notepad++.Notepad++' }
)

function Write-Step  { param($m) Write-Host "[*] $m" -ForegroundColor Cyan }
function Write-Ok    { param($m) Write-Host "[+] $m" -ForegroundColor Green }
function Write-Warn2 { param($m) Write-Host "[!] $m" -ForegroundColor Yellow }
function Write-Err   { param($m) Write-Host "[x] $m" -ForegroundColor Red }

function Test-IsDell {
    # True only on genuine Dell hardware (Manufacturer reports "Dell Inc.").
    try {
        $m = (Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop).Manufacturer
    }
    catch {
        $m = (Get-CimInstance -ClassName Win32_BIOS -ErrorAction SilentlyContinue).Manufacturer
    }
    return ($m -match 'Dell')
}

function Install-Bundle {
    param([object[]]$List)

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Err "winget (Windows Package Manager) was not found."
        Write-Warn2 "Install 'App Installer' from the Microsoft Store, then re-run."
        return
    }

    $isAdmin = ([Security.Principal.WindowsPrincipal] `
        [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Warn2 "Not elevated - some apps may install per-user or fail."
        Write-Warn2 "For machine-wide installs, run PowerShell as Administrator."
    }

    $results = @()
    foreach ($pkg in $List) {
        Write-Step "Installing $($pkg.Name) ($($pkg.Id)) ..."
        try {
            winget install --id $pkg.Id --exact `
                --accept-package-agreements `
                --accept-source-agreements `
                --silent
            $code = $LASTEXITCODE
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

    Write-Host ""
    Write-Step "Summary:"
    $results | Format-Table Name, Status -AutoSize | Out-Host
    Write-Ok "Done."
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
Write-Step "SITSswinst quick installer"

# Manufacturer check: Dell-only packages auto-install on Dell hardware only.
$isDell = Test-IsDell

$toInstall = $Packages
if ($env:ONLY) {
    # Explicit selection - honoured as-is (manufacturer gate not applied).
    $queries  = $env:ONLY -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    $toInstall = $Packages | Where-Object {
        $p = $_
        ($queries | Where-Object { $p.Id -like "*$_*" -or $p.Name -like "*$_*" }).Count -gt 0
    }
    if (-not $toInstall) {
        Write-Err "No packages matched ONLY='$($env:ONLY)'."
        return
    }
}
elseif (-not $isDell) {
    # Default bundle on non-Dell hardware: drop Dell-only packages.
    $skipped   = $Packages | Where-Object { $_.DellOnly }
    $toInstall = $Packages | Where-Object { -not $_.DellOnly }
    if ($skipped) {
        Write-Warn2 "Non-Dell hardware detected - skipping Dell-only package(s): $($skipped.Name -join ', ')"
    }
}

# -List style preview via $env:LIST
if ($env:LIST) {
    Write-Step "Software bundle:"
    $toInstall | Format-Table Name, Id -AutoSize | Out-Host
    return
}

if ($env:KEYS) {
    # --- Keys provided: reserved for future licensing/activation handling. ---
    Write-Warn2 "KEYS supplied, but key handling is not implemented yet."
    Write-Warn2 "Skipping the software bundle. (Define this branch when ready.)"
}
else {
    # --- No keys: install the software bundle (default behaviour). ---
    Install-Bundle -List $toInstall
}
