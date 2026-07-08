<#
    SITSswinst - remote quick installer

    Run on any Windows 10/11 machine with:

        irm https://raw.githubusercontent.com/kuzius/SITSswinst/main/get.ps1 | iex

    Default behaviour (NO keys provided): installs the software bundle
    (VLC, 7-Zip, Adobe Acrobat Reader, ...) via winget. Vendor-specific
    packages install only on matching hardware: Dell packages on Dell
    machines, Lenovo packages on Lenovo machines.

    Output is quiet by default - one live status line per package plus the
    final summary table (and any fatal errors). Set $env:DEBUG for full
    verbose output including native winget progress.

    Packages already present are upgraded rather than reinstalled (winget
    install errors on packages installed by a different technology, e.g.
    an older Dell Command Update); "no newer version" counts as success.

    Because `irm | iex` cannot pass parameters, configuration is read from
    environment variables set before the call:

        $env:KEYS  - if set, takes the "keys provided" branch (see below).
                     If empty/unset, the software bundle is installed.
        $env:ONLY  - comma-separated filter, e.g. 'VLC,7-Zip' to install a subset.
        $env:LIST  - any value -> just print the bundle and exit (no install).
        $env:DEBUG - any value -> verbose output (per-package progress and
                     native winget output) instead of summary-only.
        $env:ADOBE32 - any value -> install 32-bit Adobe Acrobat Reader
                     instead of the default 64-bit build.

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
    # AltIds: other winget ids the same product may be installed under
    # (checked during detection so an existing copy is upgraded, not clobbered).
    # ReinstallOnFailedUpgrade: if an in-place upgrade fails with an installer
    # error, uninstall the old copy and install fresh (needed for Dell Command
    # Update 4.x -> 5.x, whose installer refuses silent in-place upgrades).
    # -----------------------------------------------------------------------
    $Packages = @(
        [pscustomobject]@{ Name = 'VLC media player';              Id = 'VideoLAN.VLC';                          Vendor = $null }
        [pscustomobject]@{ Name = '7-Zip';                         Id = '7zip.7zip';                             Vendor = $null }
        [pscustomobject]@{ Name = 'Adobe Acrobat Reader';          Id = 'Adobe.Acrobat.Reader.64-bit';           Vendor = $null }
        [pscustomobject]@{ Name = 'TeamViewer';                    Id = 'TeamViewer.TeamViewer';                 Vendor = $null }
        [pscustomobject]@{ Name = '.NET 8 Desktop Runtime (x64)';  Id = 'Microsoft.DotNet.DesktopRuntime.8.x64'; Vendor = 'Dell' }
        [pscustomobject]@{ Name = 'Dell Command Update';           Id = 'Dell.CommandUpdate';                    Vendor = 'Dell';
                           AltIds = @('Dell.CommandUpdate.Universal'); ReinstallOnFailedUpgrade = $true }
        [pscustomobject]@{ Name = 'Lenovo System Update';          Id = 'Lenovo.SystemUpdate';                   Vendor = 'Lenovo' }
        # --- Add future software below, e.g.: ---
        # [pscustomobject]@{ Name = 'Google Chrome';               Id = 'Google.Chrome';                         Vendor = $null }
        # [pscustomobject]@{ Name = 'Notepad++';                   Id = 'Notepad++.Notepad++';                   Vendor = $null }
    )

    # Some clients need the 32-bit Adobe Reader: $env:ADOBE32 swaps the package.
    if ($env:ADOBE32) {
        $Packages | Where-Object { $_.Id -eq 'Adobe.Acrobat.Reader.64-bit' } | ForEach-Object {
            $_.Name = 'Adobe Acrobat Reader (32-bit)'
            $_.Id   = 'Adobe.Acrobat.Reader.32-bit'
        }
    }

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

        # Runs winget with the given arguments; shows native output only in
        # debug mode. Returns the winget exit code. Output must go through
        # Out-Host, never the success stream, or it would pollute the
        # returned exit code.
        function Invoke-Winget {
            param([string[]]$Arguments)
            if ($debugMode) { winget @Arguments | Out-Host }
            else { $null = winget @Arguments 2>&1 }
            return $LASTEXITCODE
        }

        # winget exit codes we recognise:
        #   0           success
        #  -1978335189  UPDATE_NOT_APPLICABLE  - no newer version available
        #  -1978335135  PACKAGE_ALREADY_INSTALLED
        # Known failure codes translated to a human explanation after the
        # summary (most notably: the Windows Installer service being busy).
        $ExitReasons = @{
            -1978334974 = 'another installation is in progress (Windows Installer is busy, e.g. Windows Update or another setup running). Wait for it to finish, then re-run'
            1618        = 'another installation is in progress (Windows Installer is busy, e.g. Windows Update or another setup running). Wait for it to finish, then re-run'
            -1978334975 = 'the package is currently in use. Close the application, then re-run'
            -1978334973 = 'needed files are in use by another process. Close open applications, then re-run'
            -1978334967 = 'a reboot is required to finish a previous installation. Reboot, then re-run'
            -1978334966 = 'the installation requires a reboot to complete'
            -1978335226 = 'the package''s own installer failed to run. Try again from an elevated (Administrator) PowerShell'
        }
        $results = @()
        foreach ($pkg in $List) {
            $code = $null
            # Live status line so a long download never looks hung.
            if (-not $debugMode) {
                Write-Host -NoNewline "[*] $($pkg.Name) ... " -ForegroundColor Cyan
            }
            try {
                # Detect first: `winget install` errors on packages that are
                # already present (e.g. installed by a different technology),
                # so upgrade existing packages instead of reinstalling. The
                # product may be installed under an alternate id (AltIds).
                $foundId = $null
                foreach ($id in (@($pkg.Id) + @($pkg.AltIds | Where-Object { $_ }))) {
                    $null = winget list --id $id --exact --accept-source-agreements 2>&1
                    if ($LASTEXITCODE -eq 0) { $foundId = $id; break }
                }

                if ($foundId) {
                    Write-Step "$($pkg.Name) is present as $foundId - checking for updates ..."
                    $code = Invoke-Winget @(
                        'upgrade', '--id', $foundId, '--exact', '--include-unknown',
                        '--accept-package-agreements', '--accept-source-agreements', '--silent')
                    switch ($code) {
                        0            { $status = 'Updated' }
                        -1978335189  { $status = 'Up to date' }
                        -1978335135  { $status = 'Up to date' }
                        default      {
                            if ($pkg.ReinstallOnFailedUpgrade) {
                                # e.g. Dell Command Update 4.x -> 5.x: the new
                                # installer refuses a silent in-place upgrade.
                                Write-Step "In-place upgrade failed (exit $code) - uninstalling $foundId and reinstalling ..."
                                $null = Invoke-Winget @(
                                    'uninstall', '--id', $foundId, '--exact',
                                    '--accept-source-agreements', '--silent')
                                $code = Invoke-Winget @(
                                    'install', '--id', $pkg.Id, '--exact',
                                    '--accept-package-agreements', '--accept-source-agreements', '--silent')
                                $status = if ($code -eq 0) { 'Reinstalled (was outdated)' }
                                          else { "Failed (exit $code)" }
                            }
                            else { $status = "Failed (exit $code)" }
                        }
                    }
                }
                else {
                    Write-Step "Installing $($pkg.Name) ($($pkg.Id)) ..."
                    $code = Invoke-Winget @(
                        'install', '--id', $pkg.Id, '--exact',
                        '--accept-package-agreements', '--accept-source-agreements', '--silent')
                    switch ($code) {
                        0            { $status = 'Installed' }
                        -1978335135  { $status = 'Up to date' }
                        default      { $status = "Failed (exit $code)" }
                    }
                }
            }
            catch {
                $status = 'Failed'
                Write-Step "$($pkg.Name) failed: $($_.Exception.Message)"
            }

            # Translate known failure codes into a human explanation.
            $reason = $null
            if ($status -like 'Failed*' -and $null -ne $code -and $ExitReasons.ContainsKey([int]$code)) {
                $reason = $ExitReasons[[int]$code]
            }

            if (-not $debugMode) {
                # Complete the live status line.
                $color = if ($status -like 'Failed*') { 'Red' } else { 'Green' }
                Write-Host $status.ToLower() -ForegroundColor $color
            }
            else {
                Write-Ok "$($pkg.Name): $status"
            }
            $results += [pscustomobject]@{ Name = $pkg.Name; Status = $status; Reason = $reason }
        }

        foreach ($pkg in $Skipped) {
            $results += [pscustomobject]@{ Name = $pkg.Name; Status = "Skipped ($($pkg.Vendor) hardware only)"; Reason = $null }
        }

        Write-Host ""
        Write-Host "Summary:" -ForegroundColor Cyan
        $results | Format-Table Name, Status -AutoSize | Out-Host
        $failed = @($results | Where-Object { $_.Status -like 'Failed*' })
        if ($failed) {
            foreach ($f in ($failed | Where-Object { $_.Reason })) {
                Write-Warn2 "$($f.Name): $($f.Reason)."
            }
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
