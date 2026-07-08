<#
    SITSswinst - remote quick installer

    Run on any Windows 10/11 machine with:

        irm https://raw.githubusercontent.com/kuzius/SITSswinst/main/get.ps1 | iex

    Default behaviour (NO keys provided): installs the software bundle
    (VLC, 7-Zip, Adobe Acrobat Reader, ...) via winget. Vendor-specific
    packages install only on matching hardware: Dell packages on Dell
    machines, Lenovo packages on Lenovo machines.

    Output is quiet by default - only the final summary table (and any
    fatal errors) is shown. Set $env:DEBUG for full verbose output.

    Because `irm | iex` cannot pass parameters, configuration is read from
    environment variables set before the call:

        $env:KEYS  - if set, takes the "keys provided" branch (see below).
                     If empty/unset, the software bundle is installed.
        $env:ONLY  - comma-separated filter, e.g. 'VLC,7-Zip' to install a subset.
        $env:LIST  - any value -> just print the bundle and exit (no install).
        $env:DEBUG - any value -> verbose output (per-package progress and
                     native winget output) instead of summary-only.

    Examples:
        # install everything (quiet, summary at the end)
        irm https://raw.githubusercontent.com/kuzius/SITSswinst/main/get.ps1 | iex

        # verbose run
        $env:DEBUG='1'; irm https://raw.githubusercontent.com/kuzius/SITSswinst/main/get.ps1 | iex

        # install only VLC
        $env:ONLY='VLC'; irm https://raw.githubusercontent.com/kuzius/SITSswinst/main/get.ps1 | iex

    The whole payload runs inside an immediately-invoked scriptblock so that,
    under `iex`, nothing leaks into the caller's session: no variables, no
    helper functions, no $ErrorActionPreference change, and the caller's
    Set-StrictMode setting cannot break the script.
#>

& {
    Set-StrictMode -Off
    $ErrorActionPreference = 'Stop'

    $debugMode = [bool]$env:DEBUG

    # -----------------------------------------------------------------------
    # Software bundle. Add new apps here. Id is the winget package identifier
    # (find one with:  winget search <name>).
    # Vendor = $null installs everywhere; 'Dell' / 'Lenovo' only on matching
    # hardware (unless explicitly requested via $env:ONLY).
    # -----------------------------------------------------------------------
    $Packages = @(
        [pscustomobject]@{ Name = 'VLC media player';              Id = 'VideoLAN.VLC';                          Vendor = $null }
        [pscustomobject]@{ Name = '7-Zip';                         Id = '7zip.7zip';                             Vendor = $null }
        [pscustomobject]@{ Name = 'Adobe Acrobat Reader';          Id = 'Adobe.Acrobat.Reader.64-bit';           Vendor = $null }
        [pscustomobject]@{ Name = 'TeamViewer';                    Id = 'TeamViewer.TeamViewer';                 Vendor = $null }
        [pscustomobject]@{ Name = '.NET 8 Desktop Runtime (x64)';  Id = 'Microsoft.DotNet.DesktopRuntime.8.x64'; Vendor = 'Dell' }
        [pscustomobject]@{ Name = 'Dell Command Update';           Id = 'Dell.CommandUpdate';                    Vendor = 'Dell' }
        [pscustomobject]@{ Name = 'Lenovo System Update';          Id = 'Lenovo.SystemUpdate';                   Vendor = 'Lenovo' }
        # --- Add future software below, e.g.: ---
        # [pscustomobject]@{ Name = 'Google Chrome';               Id = 'Google.Chrome';                         Vendor = $null }
        # [pscustomobject]@{ Name = 'Notepad++';                   Id = 'Notepad++.Notepad++';                   Vendor = $null }
    )

    function Write-Step  { param($m) if ($debugMode) { Write-Host "[*] $m" -ForegroundColor Cyan } }
    function Write-Ok    { param($m) if ($debugMode) { Write-Host "[+] $m" -ForegroundColor Green } }
    function Write-Warn2 { param($m) Write-Host "[!] $m" -ForegroundColor Yellow }
    function Write-Err   { param($m) Write-Host "[x] $m" -ForegroundColor Red }

    function Get-HardwareVendor {
        # Returns 'Dell', 'Lenovo', or $null for anything else.
        try {
            $m = (Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop).Manufacturer
        }
        catch {
            $m = (Get-CimInstance -ClassName Win32_BIOS -ErrorAction SilentlyContinue).Manufacturer
        }
        if     ($m -match 'Dell')   { return 'Dell' }
        elseif ($m -match 'Lenovo') { return 'Lenovo' }
        return $null
    }

    function Install-Bundle {
        param([object[]]$List, [object[]]$Skipped)

        if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
            Write-Err "winget (Windows Package Manager) was not found."
            Write-Warn2 "Install 'App Installer' from the Microsoft Store, then re-run."
            return
        }

        $isAdmin = ([Security.Principal.WindowsPrincipal] `
            [Security.Principal.WindowsIdentity]::GetCurrent()
        ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        if (-not $isAdmin) {
            Write-Warn2 "Not elevated - some apps may install per-user or fail. Run as Administrator for machine-wide installs."
        }

        $results = @()
        foreach ($pkg in $List) {
            Write-Step "Installing $($pkg.Name) ($($pkg.Id)) ..."
            try {
                if ($debugMode) {
                    winget install --id $pkg.Id --exact `
                        --accept-package-agreements `
                        --accept-source-agreements `
                        --silent
                }
                else {
                    # Quiet mode: swallow winget's progress/output entirely.
                    $null = winget install --id $pkg.Id --exact `
                        --accept-package-agreements `
                        --accept-source-agreements `
                        --silent 2>&1
                }
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
                    Write-Step "$($pkg.Name) finished with exit code $code."
                    $results += [pscustomobject]@{ Name = $pkg.Name; Status = "Failed (exit $code)" }
                }
            }
            catch {
                Write-Step "$($pkg.Name) failed: $($_.Exception.Message)"
                $results += [pscustomobject]@{ Name = $pkg.Name; Status = 'Failed' }
            }
        }

        foreach ($pkg in $Skipped) {
            $results += [pscustomobject]@{ Name = $pkg.Name; Status = "Skipped ($($pkg.Vendor) hardware only)" }
        }

        Write-Host ""
        Write-Host "Summary:" -ForegroundColor Cyan
        $results | Format-Table Name, Status -AutoSize | Out-Host
        if ($results | Where-Object { $_.Status -like 'Failed*' }) {
            Write-Warn2 "Some packages failed. Re-run with `$env:DEBUG='1' for full output."
        }
    }

    # -----------------------------------------------------------------------
    # Entry point
    # -----------------------------------------------------------------------
    Write-Step "SITSswinst quick installer"

    # Vendor check: Dell/Lenovo-specific packages install on matching hardware only.
    $vendor  = Get-HardwareVendor
    $skipped = @()

    $toInstall = $Packages
    if ($env:ONLY) {
        # Explicit selection - honoured as-is (vendor gate not applied).
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
    else {
        # Default bundle: drop packages tied to a different hardware vendor.
        $skipped   = @($Packages | Where-Object { $_.Vendor -and $_.Vendor -ne $vendor })
        $toInstall = @($Packages | Where-Object { -not $_.Vendor -or $_.Vendor -eq $vendor })
        if ($skipped) {
            Write-Step "Hardware vendor: $(if ($vendor) { $vendor } else { 'other' }) - skipping: $($skipped.Name -join ', ')"
        }
    }

    # -List style preview via $env:LIST
    if ($env:LIST) {
        Write-Host "Software bundle:" -ForegroundColor Cyan
        $toInstall | Format-Table Name, Id, Vendor -AutoSize | Out-Host
        return
    }

    if ($env:KEYS) {
        # --- Keys provided: reserved for future licensing/activation handling. ---
        Write-Warn2 "KEYS supplied, but key handling is not implemented yet."
        Write-Warn2 "Skipping the software bundle. (Define this branch when ready.)"
    }
    else {
        # --- No keys: install the software bundle (default behaviour). ---
        Install-Bundle -List $toInstall -Skipped $skipped
    }
}
