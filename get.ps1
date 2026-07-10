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
        $env:OFFICE - any value -> also preinstall Office 2024 Home &
                     Business (64-bit) via the Office Deployment Tool.
                     Several-GB download; installs unlicensed - sign in
                     with the owning Microsoft account (or add a key)
                     after handover.
        $env:TVCUSTOM - TeamViewer custom module configuration id (from
                     Design & Deploy, e.g. 'a1b2c3d'). Installs your
                     customized full client instead of the winget package;
                     the module's own settings handle account assignment
                     and easy access on first start.

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
        [pscustomobject]@{ Name = 'Adobe Acrobat Reader';          Id = 'Adobe.Acrobat.Reader.64-bit';           Vendor = $null;
                           AltIds = @('Adobe.Acrobat.Reader.32-bit') }
        [pscustomobject]@{ Name = 'TeamViewer';                    Id = 'TeamViewer.TeamViewer';                 Vendor = $null;
                           Wow64Key = 'HKLM:\SOFTWARE\WOW6432Node\TeamViewer'; NativeKey = 'HKLM:\SOFTWARE\TeamViewer' }
        [pscustomobject]@{ Name = '.NET 8 Desktop Runtime (x64)';  Id = 'Microsoft.DotNet.DesktopRuntime.8.x64'; Vendor = 'Dell' }
        [pscustomobject]@{ Name = 'Dell Command Update';           Id = 'Dell.CommandUpdate';                    Vendor = 'Dell';
                           AltIds = @('Dell.CommandUpdate.Universal'); ReinstallOnFailedUpgrade = $true }
        [pscustomobject]@{ Name = 'Lenovo System Update';          Id = 'Lenovo.SystemUpdate';                   Vendor = 'Lenovo' }
        # --- Add future software below, e.g.: ---
        # [pscustomobject]@{ Name = 'Google Chrome';               Id = 'Google.Chrome';                         Vendor = $null }
        # [pscustomobject]@{ Name = 'Notepad++';                   Id = 'Notepad++.Notepad++';                   Vendor = $null }
    )

    # Custom TeamViewer module: when $env:TVCUSTOM holds a Design & Deploy
    # configuration id, the customized client is installed by its own function
    # instead of the plain winget package.
    if ($env:TVCUSTOM) {
        $Packages = @($Packages | Where-Object { $_.Id -ne 'TeamViewer.TeamViewer' })
    }

    # Some clients need the 32-bit Adobe Reader: $env:ADOBE32 swaps the package.
    # Either way the other architecture stays listed as an AltId, so a copy
    # that is already installed wins (gets upgraded) regardless of the flag -
    # the flag only decides what a fresh install gets.
    if ($env:ADOBE32) {
        $Packages | Where-Object { $_.Id -eq 'Adobe.Acrobat.Reader.64-bit' } | ForEach-Object {
            $_.Name   = 'Adobe Acrobat Reader (32-bit)'
            $_.Id     = 'Adobe.Acrobat.Reader.32-bit'
            $_.AltIds = @('Adobe.Acrobat.Reader.64-bit')
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

    function Test-Needs64BitSwap {
        # True when a package that declares Wow64Key/NativeKey is installed as
        # a 32-bit build on 64-bit Windows (WOW6432Node key present, native
        # key absent) and should be replaced with the 64-bit build. Once the
        # 64-bit build is in place the native key exists, so this cannot
        # re-trigger on later runs.
        param($pkg)
        if (-not $pkg.Wow64Key) { return $false }
        if (-not [Environment]::Is64BitOperatingSystem) { return $false }
        $wow = Get-ItemProperty $pkg.Wow64Key -ErrorAction SilentlyContinue
        if (-not ($wow -and $wow.InstallationDirectory)) { return $false }
        $native = Get-ItemProperty $pkg.NativeKey -ErrorAction SilentlyContinue
        return -not ($native -and $native.InstallationDirectory)
    }

    function Install-TeamViewerCustom {
        # Installs the customized TeamViewer full client for the Design &
        # Deploy configuration id in $env:TVCUSTOM. The module's own settings
        # handle account assignment and easy access on first start, so no
        # separate assignment step is needed.
        $name = "TeamViewer (custom module $($env:TVCUSTOM))"
        if (-not $debugMode) {
            Write-Host -NoNewline "[*] $name ... " -ForegroundColor Cyan
        }
        $status = 'Failed'
        try {
            # Already running the customized client? TeamViewer marks it with
            # a trailing "C" in the version (e.g. "15.79.4 C"). On 64-bit
            # Windows only the native (64-bit) install counts - a customized
            # 32-bit build still gets replaced below.
            $nativeTv = Get-ItemProperty 'HKLM:\SOFTWARE\TeamViewer' -ErrorAction SilentlyContinue
            if ($nativeTv -and $nativeTv.Version -match 'C\s*$') {
                $status = 'Already present (customized)'
            }
            else {
                # Remove any existing client first: the silent setup aborts
                # (exit 2) on a same-version over-install, and a 32-bit build
                # on 64-bit Windows must go anyway.
                foreach ($key in 'HKLM:\SOFTWARE\TeamViewer', 'HKLM:\SOFTWARE\WOW6432Node\TeamViewer') {
                    $dir = (Get-ItemProperty $key -ErrorAction SilentlyContinue).InstallationDirectory
                    if ($dir) {
                        $uninstaller = Join-Path $dir 'uninstall.exe'
                        if (Test-Path $uninstaller) {
                            Write-Step "Removing existing client: `"$uninstaller`" /S"
                            $null = Start-Process -FilePath $uninstaller -ArgumentList "/S _?=$dir" -Wait -PassThru
                        }
                    }
                }

                # 64-bit Windows gets the x64 build - the service's default
                # TeamViewer_Setup.exe is the 32-bit client.
                $setupFile = if ([Environment]::Is64BitOperatingSystem) { 'TeamViewer_Setup_x64.exe' }
                             else { 'TeamViewer_Setup.exe' }

                $work = Join-Path $env:TEMP 'SITSswinst-tv'
                $null = New-Item -ItemType Directory -Force -Path $work
                $exe  = Join-Path $work $setupFile

                # Resolve the download URL the same way the module's own
                # download button does, so the link keeps working when
                # TeamViewer bumps the client major version. Falls back to
                # the direct pattern.
                Write-Step "Resolving download for configuration id $($env:TVCUSTOM) ..."
                $dlUrl = $null
                $tvVersion = 15
                try {
                    $page = (Invoke-WebRequest -UseBasicParsing "https://custom.teamviewer.com/$($env:TVCUSTOM)").Content
                    $m = [regex]::Match($page, '"customizationData":(\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\})')
                    if ($m.Success) {
                        $cdJson = $m.Groups[1].Value -replace 'TeamViewer_Setup\.exe', $setupFile
                        try { $tvVersion = [int]($cdJson | ConvertFrom-Json).version } catch { }
                        $resp = Invoke-RestMethod "https://custom.teamviewer.com/custom-download-url?generationParams=$([uri]::EscapeDataString($cdJson))"
                        if ($resp.isSuccess -and $resp.data.url) { $dlUrl = $resp.data.url }
                    }
                }
                catch { }
                if (-not $dlUrl) {
                    $dlUrl = "https://customdesignservice.teamviewer.com/download/windows/v$tvVersion/$($env:TVCUSTOM)/$setupFile"
                }

                Write-Step "Downloading customized client (~80 MB) ..."
                Invoke-WebRequest -UseBasicParsing $dlUrl -OutFile $exe

                Write-Step "Installing silently ..."
                $p = Start-Process -FilePath $exe -ArgumentList '/S' -Wait -PassThru
                $code = $p.ExitCode
                $status = if ($code -eq 0) { 'Installed (assigned via custom module)' }
                          else { "Failed (exit $code)" }
            }
        }
        catch {
            Write-Step "$name failed: $($_.Exception.Message)"
            $status = 'Failed'
        }

        if (-not $debugMode) {
            $color = if ($status -like 'Failed*') { 'Red' } else { 'Green' }
            Write-Host $status.ToLower() -ForegroundColor $color
        }
        else {
            Write-Ok "${name}: $status"
        }

        return [pscustomobject]@{ Name = $name; Status = $status; Reason = $null }
    }

    function Install-Office2024 {
        # Office 2024 Home & Business is not in the winget catalog (winget only
        # carries Microsoft 365 Apps), so it is installed via the Click-to-Run
        # setup bootstrapper with a generated Office Deployment Tool XML.
        # Licensing is deliberately not handled here: Office installs fine and
        # asks for sign-in / product key on first launch.
        # (Future: wire $env:KEYS to a PIDKEY attribute in the XML.)
        $name = 'Office 2024 Home & Business (64-bit)'
        if (-not $debugMode) {
            Write-Host -NoNewline "[*] $name ... " -ForegroundColor Cyan
        }
        $status = 'Failed'
        try {
            # Click-to-Run registers installed Office products here (Office
            # 2019/2021/2024 and Microsoft 365 are all C2R-based).
            $c2r = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration' -ErrorAction SilentlyContinue
            $productIds = if ($c2r) { [string]$c2r.ProductReleaseIds } else { '' }
            if ($productIds -match 'HomeBusiness2024') {
                $status = 'Already present'
            }
            elseif ($productIds -match '2019|2021') {
                # Do not touch machines with an older perpetual Office - 2024
                # cannot coexist with it and the client may be licensed for it.
                $status = 'Skipped (Office 2019/2021 present)'
            }
            else {
                $work  = Join-Path $env:TEMP 'SITSswinst-office'
                $null  = New-Item -ItemType Directory -Force -Path $work
                $setup = Join-Path $work 'setup.exe'
                $xml   = Join-Path $work 'office2024hb.xml'

                Write-Step "Downloading Office setup bootstrapper from officecdn.microsoft.com ..."
                Invoke-WebRequest -UseBasicParsing 'https://officecdn.microsoft.com/pr/wsus/setup.exe' -OutFile $setup

                # 64-bit, OS display language (en-US fallback), fully silent.
                @"
<Configuration>
  <Add OfficeClientEdition="64">
    <Product ID="HomeBusiness2024Retail">
      <Language ID="MatchOS" Fallback="en-us" />
    </Product>
  </Add>
  <Display Level="None" AcceptEULA="TRUE" />
  <Updates Enabled="TRUE" />
</Configuration>
"@ | Set-Content -Path $xml -Encoding UTF8

                Write-Step "Running Office installer (several-GB download; 10-30 minutes) ..."
                if ($debugMode) { & $setup /configure $xml | Out-Host }
                else            { $null = & $setup /configure $xml 2>&1 }
                $code = $LASTEXITCODE

                if ($code -eq 0) { $status = 'Installed (unlicensed - activate later)' }
                else             { $status = "Failed (exit $code)" }
            }
        }
        catch {
            Write-Step "$name failed: $($_.Exception.Message)"
            $status = 'Failed'
        }

        if (-not $debugMode) {
            $color = if ($status -like 'Failed*') { 'Red' } else { 'Green' }
            Write-Host $status.ToLower() -ForegroundColor $color
        }
        else {
            Write-Ok "${name}: $status"
        }

        return [pscustomobject]@{ Name = $name; Status = $status; Reason = $null }
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

                if ($foundId -and (Test-Needs64BitSwap $pkg)) {
                    # e.g. a 32-bit TeamViewer client on 64-bit Windows:
                    # remove it and install the 64-bit build instead.
                    Write-Step "$($pkg.Name): 32-bit build on 64-bit Windows - replacing with the 64-bit build ..."
                    # Prefer the app's own NSIS uninstaller: winget --silent
                    # still shows TeamViewer's confirmation window, whereas
                    # uninstall.exe /S is truly silent. _?= pins the install
                    # dir and stops NSIS from forking to a temp copy, so
                    # -Wait actually waits for the uninstall to finish.
                    $installDir  = (Get-ItemProperty $pkg.Wow64Key -ErrorAction SilentlyContinue).InstallationDirectory
                    $uninstaller = $null
                    if ($installDir) { $uninstaller = Join-Path $installDir 'uninstall.exe' }
                    if ($uninstaller -and (Test-Path $uninstaller)) {
                        Write-Step "Running silent uninstall: `"$uninstaller`" /S"
                        $null = Start-Process -FilePath $uninstaller -ArgumentList "/S _?=$installDir" -Wait -PassThru
                    }
                    else {
                        $null = Invoke-Winget @(
                            'uninstall', '--id', $foundId, '--exact',
                            '--accept-source-agreements', '--silent')
                    }
                    $code = Invoke-Winget @(
                        'install', '--id', $pkg.Id, '--exact',
                        '--accept-package-agreements', '--accept-source-agreements', '--silent')
                    $status = if ($code -eq 0) { 'Reinstalled (64-bit)' }
                              else { "Failed (exit $code)" }
                }
                elseif ($foundId) {
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

        # Customized TeamViewer client (installs + assigns via the module).
        if ($env:TVCUSTOM) {
            $results += Install-TeamViewerCustom
        }

        # Opt-in Office 2024 preinstall (not a winget package - see function).
        if ($env:OFFICE) {
            $results += Install-Office2024
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
        if ($env:TVCUSTOM) {
            Write-Host "+ TeamViewer custom module $($env:TVCUSTOM) (replaces the winget TeamViewer package)" -ForegroundColor Cyan
        }
        if ($env:OFFICE) {
            Write-Host "+ Office 2024 Home & Business (64-bit) via Office Deployment Tool" -ForegroundColor Cyan
        }
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
