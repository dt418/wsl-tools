#Requires -Version 5.1

<#
WSL SAFE BACKUP / MOVE / RESTORE
================================

Target:
  Ubuntu-24.04 installed originally from Microsoft Store.

Safety model for MOVE:
  1. Detect current distro + VHDX.
  2. Export an independent archival backup.
  3. Verify archival backup.
  4. Export another VHDX to the desired LIVE location.
  5. Verify live VHDX.
  6. Confirm original distro still exists.
  7. Require explicit user confirmation.
  8. Unregister original distro.
  9. Import-in-place the new LIVE VHDX.
 10. Verify registration.
 11. Boot-test the restored distro.
 12. Restore default-distro setting when applicable.

IMPORTANT:
  - Archive backup and LIVE VHDX are NEVER the same file.
  - Existing files are NEVER silently overwritten.
  - If anything fails before unregister, unregister is NOT executed.
  - If import fails after unregister, the archive backup and exported
    live VHDX remain available for recovery.
#>

$ErrorActionPreference = "Stop"

# ============================================================
# CONFIG
# ============================================================

$Distro = "Ubuntu-24.04"

# Independent archival backups.
$BackupRoot = "E:\wsl-backup"

# Extra free-space margin.
$SpaceSafetyFactor = 1.20

# wsl.exe writes UTF-16LE to stdout. On Windows PowerShell 5.1 the
# console's OutputEncoding often doesn't match that, which corrupts
# every line captured from `wsl --list`, `wsl --help`, etc. (you'll
# see strings interleaved with null bytes, e.g. "U`0b`0u`0n`0t`0u").
# Forcing Unicode here fixes decoding of wsl.exe's output for the
# rest of the script.
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::Unicode
}
catch {
}


# ============================================================
# UI / ERROR HELPERS
# ============================================================

function Exit-Safely {
    param(
        [string]$Message = "Operation cancelled safely."
    )

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host " SAFE EXIT"
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host $Message
    Write-Host ""

    exit 0
}


function Stop-Script {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Red
    Write-Host " STOPPED"
    Write-Host "========================================" -ForegroundColor Red
    Write-Host ""
    Write-Host $Message -ForegroundColor Red
    Write-Host ""

    exit 1
}


function Format-Size {
    param(
        [long]$Bytes
    )

    if ($Bytes -ge 1TB) {
        return "{0:N2} TB" -f ($Bytes / 1TB)
    }

    if ($Bytes -ge 1GB) {
        return "{0:N2} GB" -f ($Bytes / 1GB)
    }

    if ($Bytes -ge 1MB) {
        return "{0:N2} MB" -f ($Bytes / 1MB)
    }

    return "$Bytes bytes"
}


# ============================================================
# PATH HELPERS
# ============================================================

function Get-NormalizedPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    return [System.IO.Path]::GetFullPath(
        [Environment]::ExpandEnvironmentVariables($Path)
    ).TrimEnd("\")
}


function Test-SamePath {
    param(
        [string]$Path1,
        [string]$Path2
    )

    try {
        $A = Get-NormalizedPath $Path1
        $B = Get-NormalizedPath $Path2

        return $A.Equals(
            $B,
            [System.StringComparison]::OrdinalIgnoreCase
        )
    }
    catch {
        return $false
    }
}


function Test-DirectoryWritable {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    try {
        if (!(Test-Path $Path)) {
            New-Item `
                -ItemType Directory `
                -Path $Path `
                -Force |
                Out-Null
        }

        if (!(Test-Path $Path -PathType Container)) {
            return $false
        }

        $TestFile = Join-Path `
            $Path `
            ".wsl-write-test-$([guid]::NewGuid().ToString('N')).tmp"

        Set-Content `
            -Path $TestFile `
            -Value "WSL write test" `
            -ErrorAction Stop

        Remove-Item `
            $TestFile `
            -Force `
            -ErrorAction Stop

        return $true
    }
    catch {
        return $false
    }
}


# ============================================================
# FILE VALIDATION
# ============================================================

function Test-ValidVhd {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [long]$MinimumSize = 1MB
    )

    if (!(Test-Path $Path -PathType Leaf)) {
        return $false
    }

    try {
        $Info = Get-Item $Path

        return ($Info.Length -ge $MinimumSize)
    }
    catch {
        return $false
    }
}


function Show-VhdInfo {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (!(Test-Path $Path -PathType Leaf)) {
        return
    }

    $Info = Get-Item $Path

    Write-Host "  File : $($Info.FullName)"
    Write-Host "  Size : $(Format-Size $Info.Length)"
    Write-Host "  Date : $($Info.LastWriteTime)"
}


# ============================================================
# WSL HELPERS
# ============================================================

function Get-WslDistros {
    try {
        return @(
            wsl --list --quiet |
            ForEach-Object {
                ($_ -replace "`0", "").Trim()
            } |
            Where-Object {
                $_
            }
        )
    }
    catch {
        Stop-Script "Cannot read the WSL distro list."
    }
}


function Test-DistroExists {
    param(
        [string]$DistroName
    )

    return (
        $DistroName -in (Get-WslDistros)
    )
}


function Get-WslVersionForDistro {
    param(
        [string]$DistroName
    )

    $Output = wsl --list --verbose

    foreach ($Line in $Output) {
        $Clean = ($Line -replace "`0", "").Trim()

        if ($Clean.StartsWith("*")) {
            $Clean = $Clean.Substring(1).Trim()
        }

        if (
            $Clean -match "^$([regex]::Escape($DistroName))\s+"
        ) {
            $Parts = $Clean -split "\s+"

            if ($Parts.Count -ge 3) {
                try {
                    return [int]$Parts[-1]
                }
                catch {
                    return $null
                }
            }
        }
    }

    return $null
}


function Get-DefaultWslDistro {
    try {
        $Output = wsl --list --verbose

        foreach ($Line in $Output) {
            $Trimmed = ($Line -replace "`0", "").Trim()

            if ($Trimmed.StartsWith("*")) {
                $WithoutStar = $Trimmed.Substring(1).Trim()
                $Parts = $WithoutStar -split "\s+"

                if ($Parts.Count -gt 0) {
                    return $Parts[0]
                }
            }
        }
    }
    catch {
    }

    return $null
}


function Get-WslLocation {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DistroName
    )

    $LxssPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss"

    if (!(Test-Path $LxssPath)) {
        return $null
    }

    foreach (
        $Key in Get-ChildItem $LxssPath -ErrorAction SilentlyContinue
    ) {
        try {
            $Info = Get-ItemProperty `
                $Key.PSPath `
                -ErrorAction Stop

            if (
                $Info.DistributionName -eq $DistroName -and
                $Info.BasePath
            ) {
                $BasePath = [Environment]::ExpandEnvironmentVariables(
                    $Info.BasePath
                )

                return [PSCustomObject]@{
                    BasePath = $BasePath
                    VhdPath  = Join-Path $BasePath "ext4.vhdx"
                }
            }
        }
        catch {
            continue
        }
    }

    return $null
}


# ============================================================
# DISK SPACE
# ============================================================

function Get-FreeSpace {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    try {
        $FullPath = Get-NormalizedPath $Path
        $Root = [System.IO.Path]::GetPathRoot($FullPath)

        if ([string]::IsNullOrWhiteSpace($Root)) {
            return $null
        }

        $Drive = New-Object System.IO.DriveInfo($Root)

        if (!$Drive.IsReady) {
            return $null
        }

        return [long]$Drive.AvailableFreeSpace
    }
    catch {
        return $null
    }
}


function Assert-FreeSpace {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Destination,

        [Parameter(Mandatory = $true)]
        [long]$EstimatedBytes,

        [Parameter(Mandatory = $true)]
        [string]$Label
    )

    $Free = Get-FreeSpace $Destination

    if ($null -eq $Free) {
        Stop-Script (
            "Cannot determine free disk space for $Label.`n" +
            "Destination: $Destination"
        )
    }

    $Required = [long](
        [Math]::Ceiling(
            $EstimatedBytes * $SpaceSafetyFactor
        )
    )

    Write-Host ""
    Write-Host ("{0} disk-space check:" -f $Label) -ForegroundColor Cyan
    Write-Host "  Estimated : $(Format-Size $EstimatedBytes)"
    Write-Host "  Required  : $(Format-Size $Required)"
    Write-Host "  Free      : $(Format-Size $Free)"

    if ($Free -lt $Required) {
        Stop-Script (
            "Not enough free space for $Label."
        )
    }
}


# ============================================================
# WSL CAPABILITY CHECK
# ============================================================

function Test-WslCapabilities {
    Write-Host ""
    Write-Host "Checking required WSL commands..." -ForegroundColor Cyan

    try {
        $HelpText = (
            (
                wsl --help 2>&1 |
                Out-String
            ) -replace "`0", ""
        )

        if (
            $HelpText -notmatch "--import-in-place"
        ) {
            Stop-Script (
                "This WSL version does not advertise " +
                "--import-in-place.`n" +
                "Update WSL before using MOVE / RESTORE."
            )
        }

        if (
            $HelpText -notmatch "--export"
        ) {
            Stop-Script (
                "This WSL version does not advertise --export."
            )
        }

        if (
            $HelpText -notmatch "--vhd"
        ) {
            Stop-Script (
                "This WSL version does not advertise " +
                "--vhd for export.`n" +
                "Update WSL before continuing."
            )
        }
    }
    catch {
        Stop-Script "Unable to verify WSL capabilities."
    }

    Write-Host "[OK] Required WSL commands detected." `
        -ForegroundColor Green
}


# ============================================================
# EXPORT VHD
# ============================================================

function Export-WslVhd {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Destination,

        [Parameter(Mandatory = $true)]
        [string]$Purpose
    )

    $Directory = Split-Path `
        $Destination `
        -Parent

    if ([string]::IsNullOrWhiteSpace($Directory)) {
        Stop-Script "Invalid export destination: $Destination"
    }

    if (!(Test-DirectoryWritable $Directory)) {
        Stop-Script (
            "Directory is not writable:`n$Directory"
        )
    }

    if (Test-Path $Destination) {
        Stop-Script (
            "$Purpose already exists:`n`n" +
            "$Destination`n`n" +
            "Nothing will be overwritten."
        )
    }

    Write-Host ""
    Write-Host "----------------------------------------"
    Write-Host $Purpose -ForegroundColor Cyan
    Write-Host "----------------------------------------"

    Write-Host ""
    Write-Host "Destination:"
    Write-Host "  $Destination"
    Write-Host ""

    wsl --export `
        $Distro `
        $Destination `
        --vhd

    $ExitCode = $LASTEXITCODE

    if ($ExitCode -ne 0) {
        if (Test-Path $Destination) {
            Write-Host ""
            Write-Host (
                "Removing incomplete export..."
            ) -ForegroundColor Yellow

            try {
                Remove-Item `
                    $Destination `
                    -Force `
                    -ErrorAction Stop
            }
            catch {
                Write-Host (
                    "WARNING: Could not remove incomplete file:"
                ) -ForegroundColor Yellow

                Write-Host "  $Destination"
            }
        }

        Stop-Script (
            "$Purpose failed. wsl --export exit code: $ExitCode"
        )
    }

    if (!(Test-ValidVhd $Destination)) {
        Stop-Script (
            "$Purpose finished but the VHDX is missing " +
            "or unexpectedly small."
        )
    }

    $Info = Get-Item $Destination

    Write-Host ""
    Write-Host "[OK] $Purpose" -ForegroundColor Green
    Show-VhdInfo $Destination

    return $Info
}


# ============================================================
# SELECT LIVE LOCATION
# ============================================================

function Select-LiveLocation {
    param(
        $CurrentWsl
    )

    $DefaultDrive = $env:SystemDrive

    if ($null -ne $CurrentWsl) {
        try {
            $DetectedDrive = Split-Path `
                $CurrentWsl.BasePath `
                -Qualifier

            if (
                ![string]::IsNullOrWhiteSpace($DetectedDrive)
            ) {
                $DefaultDrive = $DetectedDrive
            }
        }
        catch {
        }
    }

    $DefaultDirectory = Join-Path `
        $DefaultDrive `
        "WSL\$Distro"

    while ($true) {
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host " LIVE WSL LOCATION"
        Write-Host "========================================" -ForegroundColor Cyan

        if ($null -ne $CurrentWsl) {
            Write-Host ""
            Write-Host "Current Store-managed location:"
            Write-Host "  $($CurrentWsl.BasePath)"
        }

        Write-Host ""
        Write-Host "Recommended location:"
        Write-Host "  $DefaultDirectory"

        Write-Host ""
        Write-Host "[1] Use recommended location"
        Write-Host "[2] Choose another location"
        Write-Host "[Q] Exit"
        Write-Host ""

        $Choice = (
            Read-Host "Select [1/2/Q]"
        ).Trim().ToUpper()

        switch ($Choice) {
            "1" {
                return $DefaultDirectory
            }

            "2" {
                Write-Host ""
                Write-Host "Examples:"
                Write-Host "  C:\WSL\$Distro"
                Write-Host "  D:\WSL\$Distro"
                Write-Host "  E:\WSL\$Distro"
                Write-Host ""

                $Path = (
                    Read-Host "Enter LIVE directory"
                ).Trim().Trim('"')

                if (
                    [string]::IsNullOrWhiteSpace($Path)
                ) {
                    continue
                }

                try {
                    $Path = Get-NormalizedPath $Path
                }
                catch {
                    Write-Host "Invalid path." `
                        -ForegroundColor Yellow

                    continue
                }

                Write-Host ""
                Write-Host "Selected LIVE directory:"
                Write-Host "  $Path"
                Write-Host ""

                $Confirm = (
                    Read-Host "Use this location? [Y/N/Q]"
                ).Trim().ToUpper()

                if ($Confirm -eq "Y") {
                    return $Path
                }

                if ($Confirm -eq "Q") {
                    Exit-Safely
                }
            }

            "Q" {
                Exit-Safely
            }
        }
    }
}


# ============================================================
# BACKUP ONLY
# ============================================================

function Start-BackupOnly {
    param(
        [long]$SourceSize
    )

    if (!(Test-DirectoryWritable $BackupRoot)) {
        Stop-Script (
            "Backup directory is not writable:`n$BackupRoot"
        )
    }

    Assert-FreeSpace `
        -Destination $BackupRoot `
        -EstimatedBytes $SourceSize `
        -Label "BACKUP"

    $Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

    $BackupFile = Join-Path `
        $BackupRoot `
        "$Distro-$Timestamp.vhdx"

    Write-Host ""
    Write-Host "Backup destination:"
    Write-Host "  $BackupFile"

    Write-Host ""
    Write-Host "[B] Start backup"
    Write-Host "[Q] Exit"
    Write-Host ""

    while ($true) {
        $Choice = (
            Read-Host "Select [B/Q]"
        ).Trim().ToUpper()

        if ($Choice -eq "Q") {
            Exit-Safely
        }

        if ($Choice -eq "B") {
            break
        }
    }

    Write-Host ""
    Write-Host "Shutdown WSL..." -ForegroundColor Cyan

    wsl --shutdown

    if ($LASTEXITCODE -ne 0) {
        Stop-Script "wsl --shutdown failed."
    }

    $BackupInfo = Export-WslVhd `
        -Destination $BackupFile `
        -Purpose "ARCHIVE BACKUP"

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host " BACKUP COMPLETED"
    Write-Host "========================================" -ForegroundColor Green

    Write-Host ""
    Show-VhdInfo $BackupInfo.FullName

    Write-Host ""
    Write-Host (
        "The original distro was NOT unregistered."
    ) -ForegroundColor Green

    Write-Host ""

    exit 0
}


# ============================================================
# MOVE / RESTORE
# ============================================================

function Start-SafeMove {
    param(
        $CurrentWsl,

        [long]$SourceSize,

        [string]$OriginalDefaultDistro
    )

    Test-WslCapabilities

    # --------------------------------------------------------
    # Choose LIVE target
    # --------------------------------------------------------

    $LiveDirectory = Select-LiveLocation `
        -CurrentWsl $CurrentWsl

    $LiveVhd = Join-Path `
        $LiveDirectory `
        "ext4.vhdx"

    # --------------------------------------------------------
    # Validate source / target
    # --------------------------------------------------------

    if (
        $null -ne $CurrentWsl -and
        (Test-SamePath $CurrentWsl.VhdPath $LiveVhd)
    ) {
        Stop-Script (
            "LIVE VHDX cannot be the same file as " +
            "the current Store-managed VHDX."
        )
    }

    if (Test-Path $LiveDirectory) {
        $Existing = Get-ChildItem `
            $LiveDirectory `
            -Force |
            Select-Object -First 1

        if ($null -ne $Existing) {
            Stop-Script (
                "LIVE directory is not empty:`n" +
                "$LiveDirectory`n`n" +
                "Choose a new/empty directory."
            )
        }
    }

    if (!(Test-DirectoryWritable $LiveDirectory)) {
        Stop-Script (
            "LIVE directory is not writable:`n" +
            $LiveDirectory
        )
    }

    if (!(Test-DirectoryWritable $BackupRoot)) {
        Stop-Script (
            "Backup directory is not writable:`n" +
            $BackupRoot
        )
    }

    # Backup and LIVE must not be same directory.
    if (Test-SamePath $BackupRoot $LiveDirectory) {
        Stop-Script (
            "Backup directory and LIVE directory " +
            "must be different."
        )
    }

    # --------------------------------------------------------
    # Disk-space preflight
    # --------------------------------------------------------

    Assert-FreeSpace `
        -Destination $BackupRoot `
        -EstimatedBytes $SourceSize `
        -Label "ARCHIVE BACKUP"

    Assert-FreeSpace `
        -Destination $LiveDirectory `
        -EstimatedBytes $SourceSize `
        -Label "LIVE EXPORT"

    # --------------------------------------------------------
    # Generate unique archive name
    # --------------------------------------------------------

    $Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

    $ArchiveBackup = Join-Path `
        $BackupRoot `
        "$Distro-$Timestamp.vhdx"

    # --------------------------------------------------------
    # Display complete plan
    # --------------------------------------------------------

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Yellow
    Write-Host " SAFE MOVE PLAN"
    Write-Host "========================================" -ForegroundColor Yellow

    Write-Host ""
    Write-Host "Distro:"
    Write-Host "  $Distro"

    Write-Host ""
    Write-Host "Original VHDX:"
    Write-Host "  $($CurrentWsl.VhdPath)"

    Write-Host ""
    Write-Host "Independent archive backup:"
    Write-Host "  $ArchiveBackup"

    Write-Host ""
    Write-Host "New LIVE VHDX:"
    Write-Host "  $LiveVhd"

    Write-Host ""
    Write-Host "Original default distro:"
    if ($OriginalDefaultDistro) {
        Write-Host "  $OriginalDefaultDistro"
    }
    else {
        Write-Host "  <not detected>"
    }

    Write-Host ""
    Write-Host "Before unregister there will be:"
    Write-Host "  1. Original Store VHDX"
    Write-Host "  2. Independent archive backup"
    Write-Host "  3. New LIVE VHDX"

    Write-Host ""
    Write-Host "[S] Start safe export process"
    Write-Host "[Q] Exit"
    Write-Host ""

    while ($true) {
        $Choice = (
            Read-Host "Select [S/Q]"
        ).Trim().ToUpper()

        if ($Choice -eq "Q") {
            Exit-Safely
        }

        if ($Choice -eq "S") {
            break
        }
    }

    # --------------------------------------------------------
    # Shutdown before exports
    # --------------------------------------------------------

    Write-Host ""
    Write-Host "Shutdown WSL..." -ForegroundColor Cyan

    wsl --shutdown

    if ($LASTEXITCODE -ne 0) {
        Stop-Script (
            "wsl --shutdown failed. Nothing was unregistered."
        )
    }

    # --------------------------------------------------------
    # STEP A - Independent archive backup
    # --------------------------------------------------------

    $ArchiveInfo = Export-WslVhd `
        -Destination $ArchiveBackup `
        -Purpose "INDEPENDENT ARCHIVE BACKUP"

    if (!(Test-ValidVhd $ArchiveBackup)) {
        Stop-Script (
            "Archive backup validation failed. " +
            "UNREGISTER IS BLOCKED."
        )
    }

    # --------------------------------------------------------
    # STEP B - Export future LIVE VHDX
    # --------------------------------------------------------

    $LiveInfo = Export-WslVhd `
        -Destination $LiveVhd `
        -Purpose "NEW LIVE VHDX EXPORT"

    if (!(Test-ValidVhd $LiveVhd)) {
        Stop-Script (
            "LIVE VHDX validation failed. " +
            "UNREGISTER IS BLOCKED."
        )
    }

    # --------------------------------------------------------
    # Ensure two exports are distinct
    # --------------------------------------------------------

    if (Test-SamePath $ArchiveBackup $LiveVhd) {
        Stop-Script (
            "Archive backup and LIVE VHDX unexpectedly " +
            "resolve to the same path. UNREGISTER IS BLOCKED."
        )
    }

    # --------------------------------------------------------
    # Original must still be registered
    # --------------------------------------------------------

    if (!(Test-DistroExists $Distro)) {
        Stop-Script (
            "Original distro is unexpectedly not registered. " +
            "UNREGISTER IS BLOCKED."
        )
    }

    # --------------------------------------------------------
    # Verify WSL2 again
    # --------------------------------------------------------

    $VersionBeforeUnregister = Get-WslVersionForDistro `
        -DistroName $Distro

    if ($VersionBeforeUnregister -ne 2) {
        Stop-Script (
            "Distro is no longer confirmed as WSL2. " +
            "UNREGISTER IS BLOCKED."
        )
    }

    # --------------------------------------------------------
    # Pre-flight passed
    # --------------------------------------------------------

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host " ALL PRE-FLIGHT CHECKS PASSED"
    Write-Host "========================================" -ForegroundColor Green

    Write-Host ""
    Write-Host "ARCHIVE BACKUP:" -ForegroundColor Green
    Show-VhdInfo $ArchiveBackup

    Write-Host ""
    Write-Host "NEW LIVE VHDX:" -ForegroundColor Green
    Show-VhdInfo $LiveVhd

    Write-Host ""
    Write-Host (
        "Original distro is still registered."
    ) -ForegroundColor Green

    # --------------------------------------------------------
    # Danger zone
    # --------------------------------------------------------

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Red
    Write-Host " DANGER ZONE"
    Write-Host "========================================" -ForegroundColor Red

    Write-Host ""
    Write-Host (
        "The NEXT destructive operation is:"
    ) -ForegroundColor Yellow

    Write-Host ""
    Write-Host "  wsl --unregister $Distro" `
        -ForegroundColor Red

    Write-Host ""
    Write-Host "Archive backup:"
    Write-Host "  $ArchiveBackup"

    Write-Host ""
    Write-Host "New LIVE VHDX:"
    Write-Host "  $LiveVhd"

    Write-Host ""
    Write-Host "[R] Continue to unregister + restore"
    Write-Host "[Q] EXIT and keep BOTH exported VHDX files"
    Write-Host ""

    while ($true) {
        $Choice = (
            Read-Host "Select [R/Q]"
        ).Trim().ToUpper()

        if ($Choice -eq "Q") {
            Exit-Safely (
                "Original distro was NOT unregistered.`n" +
                "Both exported VHDX files were preserved."
            )
        }

        if ($Choice -eq "R") {
            break
        }
    }

    Write-Host ""
    Write-Host "FINAL CONFIRMATION" -ForegroundColor Red
    Write-Host ""
    Write-Host "Type exactly:"
    Write-Host ""
    Write-Host "  RESTORE" -ForegroundColor Yellow
    Write-Host ""

    $Confirmation = Read-Host "Confirmation"

    if ($Confirmation -cne "RESTORE") {
        Exit-Safely (
            "Confirmation cancelled. Original distro remains registered."
        )
    }

    # ========================================================
    # LAST-SECOND CHECKS
    # ========================================================

    Write-Host ""
    Write-Host "Running last-second safety checks..." `
        -ForegroundColor Cyan

    if (!(Test-ValidVhd $ArchiveBackup)) {
        Stop-Script (
            "Archive backup disappeared or became invalid. " +
            "UNREGISTER CANCELLED."
        )
    }

    if (!(Test-ValidVhd $LiveVhd)) {
        Stop-Script (
            "LIVE VHDX disappeared or became invalid. " +
            "UNREGISTER CANCELLED."
        )
    }

    if (!(Test-DistroExists $Distro)) {
        Stop-Script (
            "Original distro is not registered anymore. " +
            "UNREGISTER CANCELLED."
        )
    }

    wsl --shutdown

    if ($LASTEXITCODE -ne 0) {
        Stop-Script (
            "Final WSL shutdown failed. " +
            "UNREGISTER CANCELLED."
        )
    }

    # Validate exports one final time AFTER shutdown.
    if (!(Test-ValidVhd $ArchiveBackup)) {
        Stop-Script (
            "Archive backup failed final validation. " +
            "UNREGISTER CANCELLED."
        )
    }

    if (!(Test-ValidVhd $LiveVhd)) {
        Stop-Script (
            "LIVE VHDX failed final validation. " +
            "UNREGISTER CANCELLED."
        )
    }

    Write-Host "[OK] Final safety checks passed." `
        -ForegroundColor Green

    # ========================================================
    # POINT OF NO RETURN - UNREGISTER
    # ========================================================

    Write-Host ""
    Write-Host "Unregistering $Distro..." `
        -ForegroundColor Yellow

    wsl --unregister $Distro

    $UnregisterExitCode = $LASTEXITCODE

    if ($UnregisterExitCode -ne 0) {
        Write-Host ""
        Write-Host (
            "Unregister returned an error."
        ) -ForegroundColor Red

        Write-Host ""
        Write-Host "DO NOT DELETE:"
        Write-Host "  $ArchiveBackup"
        Write-Host "  $LiveVhd"

        exit 1
    }

    # ========================================================
    # CONFIRM OLD REGISTRATION IS GONE
    # ========================================================

    if (Test-DistroExists $Distro) {
        Write-Host ""
        Write-Host (
            "WARNING: Distro still appears registered."
        ) -ForegroundColor Red

        Write-Host ""
        Write-Host "Archive backup remains:"
        Write-Host "  $ArchiveBackup"

        Write-Host ""
        Write-Host "LIVE VHDX remains:"
        Write-Host "  $LiveVhd"

        exit 1
    }

    Write-Host ""
    Write-Host "[OK] Old registration removed." `
        -ForegroundColor Green

    # ========================================================
    # IMPORT-IN-PLACE
    # ========================================================

    Write-Host ""
    Write-Host "Registering LIVE VHDX..." `
        -ForegroundColor Cyan

    Write-Host ""
    Write-Host (
        'wsl --import-in-place "{0}" "{1}"' -f
        $Distro,
        $LiveVhd
    )

    Write-Host ""

    wsl --import-in-place `
        $Distro `
        $LiveVhd

    $ImportExitCode = $LASTEXITCODE

    if ($ImportExitCode -ne 0) {
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Red
        Write-Host " IMPORT-IN-PLACE FAILED"
        Write-Host "========================================" -ForegroundColor Red

        Write-Host ""
        Write-Host "Your data copies are still available:" `
            -ForegroundColor Yellow

        Write-Host ""
        Write-Host "ARCHIVE BACKUP:"
        Write-Host "  $ArchiveBackup" `
            -ForegroundColor Green

        Write-Host ""
        Write-Host "LIVE VHDX:"
        Write-Host "  $LiveVhd" `
            -ForegroundColor Green

        Write-Host ""
        Write-Host "Retry registration with:"
        Write-Host ""

        Write-Host (
            'wsl --import-in-place "{0}" "{1}"' -f
            $Distro,
            $LiveVhd
        ) -ForegroundColor Cyan

        Write-Host ""

        exit 1
    }

    # ========================================================
    # VERIFY REGISTRATION
    # ========================================================

    if (!(Test-DistroExists $Distro)) {
        Write-Host ""
        Write-Host "Archive backup remains:"
        Write-Host "  $ArchiveBackup"

        Write-Host ""
        Write-Host "LIVE VHDX remains:"
        Write-Host "  $LiveVhd"

        Stop-Script (
            "Import completed but distro registration " +
            "could not be verified."
        )
    }

    $VersionAfter = Get-WslVersionForDistro `
        -DistroName $Distro

    if ($VersionAfter -ne 2) {
        Write-Host ""
        Write-Host (
            "WARNING: Registration exists but WSL2 " +
            "could not be confirmed."
        ) -ForegroundColor Yellow
    }
    else {
        Write-Host ""
        Write-Host "[OK] Registered as WSL2." `
            -ForegroundColor Green
    }

    # ========================================================
    # BOOT TEST
    # ========================================================

    Write-Host ""
    Write-Host "Testing restored distro..." `
        -ForegroundColor Cyan

    wsl `
        -d $Distro `
        -- `
        /bin/true

    $BootTestExitCode = $LASTEXITCODE

    if ($BootTestExitCode -ne 0) {
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Red
        Write-Host " BOOT TEST FAILED"
        Write-Host "========================================" -ForegroundColor Red

        Write-Host ""
        Write-Host (
            "The distro was registered, but the boot test failed."
        ) -ForegroundColor Yellow

        Write-Host ""
        Write-Host "DO NOT DELETE THE ARCHIVE BACKUP:"
        Write-Host "  $ArchiveBackup" `
            -ForegroundColor Green

        Write-Host ""
        Write-Host "LIVE VHDX:"
        Write-Host "  $LiveVhd"

        Write-Host ""

        exit 1
    }

    Write-Host "[OK] Boot test passed." `
        -ForegroundColor Green

    # ========================================================
    # RESTORE DEFAULT DISTRO SETTING
    # ========================================================

    if (
        $OriginalDefaultDistro -eq $Distro
    ) {
        Write-Host ""
        Write-Host "Restoring default distro..." `
            -ForegroundColor Cyan

        wsl --set-default $Distro

        if ($LASTEXITCODE -ne 0) {
            Write-Host (
                "WARNING: Could not restore default distro setting."
            ) -ForegroundColor Yellow
        }
        else {
            Write-Host "[OK] Default distro restored." `
                -ForegroundColor Green
        }
    }

    # ========================================================
    # FINAL LOCATION DETECTION
    # ========================================================

    $NewLocation = Get-WslLocation `
        -DistroName $Distro

    # ========================================================
    # SUCCESS
    # ========================================================

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host " MOVE / RESTORE SUCCESSFUL"
    Write-Host "========================================" -ForegroundColor Green

    Write-Host ""
    Write-Host "Distro:"
    Write-Host "  $Distro"

    Write-Host ""
    Write-Host "LIVE VHDX:"
    Write-Host "  $LiveVhd"

    if ($null -ne $NewLocation) {
        Write-Host ""
        Write-Host "Detected BasePath:"
        Write-Host "  $($NewLocation.BasePath)"
    }

    Write-Host ""
    Write-Host "INDEPENDENT ARCHIVE BACKUP:"
    Write-Host "  $ArchiveBackup" `
        -ForegroundColor Green

    Write-Host ""
    Write-Host "IMPORTANT:" -ForegroundColor Yellow
    Write-Host (
        "Keep the archive backup until you have fully " +
        "verified your files and applications."
    )

    Write-Host ""
    Write-Host "WSL status:"
    Write-Host ""

    wsl --list --verbose

    Write-Host ""
    Write-Host "Start Ubuntu:"
    Write-Host ""
    Write-Host "  wsl -d $Distro" `
        -ForegroundColor Cyan

    Write-Host ""
}


# ============================================================
# START
# ============================================================

Clear-Host

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " WSL SAFE BACKUP / MOVE / RESTORE"
Write-Host "========================================" -ForegroundColor Cyan

Write-Host ""
Write-Host "Distro:"
Write-Host "  $Distro"

Write-Host ""
Write-Host "Archive backup root:"
Write-Host "  $BackupRoot"


# ============================================================
# 1. CHECK WSL.EXE
# ============================================================

Write-Host ""
Write-Host "[1] Checking WSL..." `
    -ForegroundColor Cyan

if (!(Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
    Stop-Script "wsl.exe was not found."
}

Write-Host "[OK] wsl.exe found." `
    -ForegroundColor Green


# ============================================================
# 2. CHECK DISTRO
# ============================================================

Write-Host ""
Write-Host "[2] Checking distro..." `
    -ForegroundColor Cyan

if (!(Test-DistroExists $Distro)) {
    Write-Host ""
    wsl --list --verbose

    Stop-Script (
        "Distro '$Distro' was not found."
    )
}

Write-Host "[OK] $Distro found." `
    -ForegroundColor Green


# ============================================================
# 3. CHECK WSL2
# ============================================================

Write-Host ""
Write-Host "[3] Checking distro version..." `
    -ForegroundColor Cyan

$DistroVersion = Get-WslVersionForDistro `
    -DistroName $Distro

if ($DistroVersion -ne 2) {
    Stop-Script (
        "$Distro is not confirmed as WSL2. " +
        "This script will not continue."
    )
}

Write-Host "[OK] WSL2 confirmed." `
    -ForegroundColor Green


# ============================================================
# 4. DETECT CURRENT VHDX
# ============================================================

Write-Host ""
Write-Host "[4] Detecting current WSL storage..." `
    -ForegroundColor Cyan

$CurrentWsl = Get-WslLocation `
    -DistroName $Distro

if ($null -eq $CurrentWsl) {
    Stop-Script (
        "Cannot detect the current WSL BasePath.`n" +
        "For safety, this script will not guess.`n`n" +
        "Note: newer Microsoft Store-installed distros can use an " +
        "abstracted storage model where no ext4.vhdx is directly " +
        "accessible under the registry BasePath. If that's the case " +
        "here, `wsl --export ... --vhd` is still the supported way " +
        "to get a VHDX out of the distro; this script's own export " +
        "path does not depend on BasePath, only this pre-flight " +
        "detection step does."
    )
}

if (!(Test-Path $CurrentWsl.VhdPath -PathType Leaf)) {
    Stop-Script (
        "Current ext4.vhdx was not found:`n" +
        $CurrentWsl.VhdPath
    )
}

$SourceVhdInfo = Get-Item `
    $CurrentWsl.VhdPath

if ($SourceVhdInfo.Length -lt 1MB) {
    Stop-Script (
        "Current ext4.vhdx has an unexpected size."
    )
}

Write-Host "[OK] Current VHDX found." `
    -ForegroundColor Green

Write-Host ""
Write-Host "BasePath:"
Write-Host "  $($CurrentWsl.BasePath)"

Write-Host ""
Write-Host "VHDX:"
Write-Host "  $($CurrentWsl.VhdPath)"

Write-Host ""
Write-Host "Physical file size:"
Write-Host "  $(Format-Size $SourceVhdInfo.Length)"


# ============================================================
# 5. SAVE DEFAULT DISTRO
# ============================================================

$OriginalDefaultDistro = Get-DefaultWslDistro

Write-Host ""
Write-Host "[5] Current default distro:"

if ($OriginalDefaultDistro) {
    Write-Host "  $OriginalDefaultDistro"
}
else {
    Write-Host "  <not detected>" `
        -ForegroundColor Yellow
}


# ============================================================
# MAIN MENU
# ============================================================

Write-Host ""
Write-Host "========================================"
Write-Host " SELECT OPERATION"
Write-Host "========================================"

Write-Host ""
Write-Host "[1] BACKUP ONLY" `
    -ForegroundColor Green

Write-Host "    - Export independent VHDX backup"
Write-Host "    - Never unregister Ubuntu"

Write-Host ""
Write-Host "[2] SAFE MOVE / RESTORE" `
    -ForegroundColor Yellow

Write-Host "    - Create independent archive backup"
Write-Host "    - Export new LIVE VHDX"
Write-Host "    - Verify both"
Write-Host "    - Unregister original"
Write-Host "    - Import-in-place new LIVE VHDX"
Write-Host "    - Boot-test restored Ubuntu"

Write-Host ""
Write-Host "[Q] EXIT"
Write-Host ""

while ($true) {
    $MainChoice = (
        Read-Host "Select [1/2/Q]"
    ).Trim().ToUpper()

    switch ($MainChoice) {
        "1" {
            Start-BackupOnly `
                -SourceSize $SourceVhdInfo.Length

            break
        }

        "2" {
            Start-SafeMove `
                -CurrentWsl $CurrentWsl `
                -SourceSize $SourceVhdInfo.Length `
                -OriginalDefaultDistro $OriginalDefaultDistro

            break
        }

        "Q" {
            Exit-Safely
        }

        default {
            Write-Host ""
            Write-Host "Please select 1, 2 or Q." `
                -ForegroundColor Yellow
        }
    }

    if ($MainChoice -in @("1", "2")) {
        break
    }
}