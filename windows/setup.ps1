# -*- coding: utf-8 -*-
param(
    [switch]$SkipWingetInstall
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8

$ErrorActionPreference = "Stop"

# ── Locate repo root (this script lives in <repo>/windows/) ──────────────
$repoRoot = Split-Path (Split-Path $PSCommandPath -Parent) -Parent

# Symlink mapping: source (in repo) → target (on disk)
$profileSource = Join-Path $repoRoot "windows\Microsoft.PowerShell_profile.ps1"
$themeSource   = Join-Path $repoRoot "shared\agnosterplus.omp.json"

$profileTarget = Join-Path $HOME "Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1"
$themeTarget   = Join-Path $HOME ".config\oh-my-posh\agnosterplus.omp.json"

# Backup
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backupDir = Join-Path $HOME "profile-backups\$timestamp"

function Write-Step { param([string]$Message)
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Backup-IfExists { param([string]$Path)
    if (Test-Path $Path) {
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
        # Don't back up symlinks — they point to the repo, not user data
        $item = Get-Item $Path -Force
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            Write-Host "  Skipping symlink: $Path" -ForegroundColor DarkGray
            return
        }
        Copy-Item $Path (Join-Path $backupDir ([IO.Path]::GetFileName($Path))) -Force
    }
}

function Restore-IfBackedUp { param([string]$OriginalPath)
    $name = [IO.Path]::GetFileName($OriginalPath)
    $bak  = Join-Path $backupDir $name
    if (Test-Path $bak) {
        Copy-Item $bak $OriginalPath -Force
    } elseif (Test-Path $OriginalPath) {
        Remove-Item $OriginalPath -Force
    }
}

function Test-IsAdministrator {
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-HighestInstalledModule { param([Parameter(Mandatory)][string]$Name)
    Get-Module -ListAvailable -Name $Name | Sort-Object Version -Descending | Select-Object -First 1
}

function Ensure-Module {
    param(
        [Parameter(Mandatory)][string]$Name,
        [version]$MinimumVersion = [version]"0.0.0"
    )
    $installed = Get-HighestInstalledModule -Name $Name
    if ($installed -and $installed.Version -ge $MinimumVersion) {
        Write-Host "Module ok: $Name $($installed.Version)" -ForegroundColor DarkGray
        return
    }
    if ($Name -eq "PSReadLine") {
        if (-not (Test-IsAdministrator)) {
            throw @"
PSReadLine version is too old or missing. Please rerun this script in an elevated PowerShell window.
Recommended: Install-Module PSReadLine -Repository PSGallery -Scope AllUsers -Force -AllowClobber -SkipPublisherCheck
"@
        }
        Write-Host "Installing module: $Name (AllUsers, admin required)" -ForegroundColor Yellow
        Install-Module -Name $Name -Repository PSGallery -Scope AllUsers -Force -AllowClobber -SkipPublisherCheck
        return
    }
    Write-Host "Installing module: $Name" -ForegroundColor Yellow
    Install-Module -Name $Name -Scope CurrentUser -Repository PSGallery -Force -AllowClobber -SkipPublisherCheck
}

function New-Symlink {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Target
    )
    $targetDir = Split-Path $Target -Parent
    if (-not (Test-Path $targetDir)) {
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    }

    # Handle existing file at target
    if (Test-Path $Target) {
        $item = Get-Item $Target -Force
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            # Existing symlink — safe to remove
            Remove-Item $Target -Force
        } else {
            # Real file — rename to .old and warn
            $oldPath = "$Target.old"
            Move-Item $Target $oldPath -Force
            Write-Host "  Renamed existing config to: $oldPath" -ForegroundColor Yellow
        }
    }

    New-Item -ItemType SymbolicLink -Path $Target -Target $Source -Force | Out-Null
    Write-Host "  $Target -> $Source" -ForegroundColor Green
}

try {
    Write-Step "Backing up existing config"
    Backup-IfExists -Path $profileTarget
    Backup-IfExists -Path $themeTarget

    Write-Step "Ensuring NuGet provider"
    if (-not (Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue)) {
        Install-PackageProvider -Name NuGet -Scope CurrentUser -Force -SkipPublisherCheck | Out-Null
    }

    Write-Step "Installing/verifying oh-my-posh"
    $ompCmd = Get-Command oh-my-posh -ErrorAction SilentlyContinue
    if (-not $ompCmd) {
        if ($SkipWingetInstall) {
            Write-Host "Skip winget install by flag. Please install oh-my-posh manually." -ForegroundColor Yellow
        } else {
            $wingetCmd = Get-Command winget -ErrorAction SilentlyContinue
            if ($wingetCmd) {
                Write-Host "Installing oh-my-posh via winget..." -ForegroundColor Yellow
                winget install JanDeDobbeleer.OhMyPosh -s winget --accept-package-agreements --accept-source-agreements
            } else {
                Write-Host "winget not available. Please install oh-my-posh manually: https://ohmyposh.dev/docs/installation/windows" -ForegroundColor Yellow
            }
        }
    } else {
        Write-Host "oh-my-posh exists." -ForegroundColor DarkGray
    }

    Write-Step "Installing/verifying zoxide + fzf"
    $wingetCmd = Get-Command winget -ErrorAction SilentlyContinue
    if ($wingetCmd) {
        foreach ($pkg in @("ajeetdsouza.zoxide", "junegunn.fzf")) {
            $installed = winget list --id $pkg --accept-source-agreements 2>$null | Select-String $pkg
            if (-not $installed) {
                Write-Host "Installing $pkg via winget..." -ForegroundColor Yellow
                winget install $pkg -s winget --accept-package-agreements --accept-source-agreements
            } else {
                Write-Host "Already installed: $pkg" -ForegroundColor DarkGray
            }
        }
    } else {
        Write-Host "winget not available. Please install zoxide and fzf manually." -ForegroundColor Yellow
    }

    Write-Step "Installing/verifying PowerShell modules"
    Ensure-Module -Name PSReadLine    -MinimumVersion ([version]"2.2.6")
    Ensure-Module -Name posh-git
    Ensure-Module -Name Terminal-Icons
    Ensure-Module -Name PSFzf -MinimumVersion ([version]"2.5.0")
    $psfzfMod = Get-HighestInstalledModule -Name PSFzf
    if ($psfzfMod) {
        Write-Host "PSFzf ready: $($psfzfMod.Version) [$($psfzfMod.ModuleBase)]" -ForegroundColor DarkGray
    }

    Write-Step "Verifying PSReadLine version"
    $psReadLine = Get-HighestInstalledModule -Name PSReadLine
    if (-not $psReadLine) { throw "PSReadLine installation failed." }
    if ($psReadLine.Version -lt [version]"2.2.6") {
        throw "PSReadLine version too old: $($psReadLine.Version), requires >= 2.2.6"
    }
    Write-Host "PSReadLine ready: $($psReadLine.Version) [$($psReadLine.ModuleBase)]" -ForegroundColor DarkGray

    Write-Step "Creating symlinks"
    New-Symlink -Source $profileSource -Target $profileTarget
    New-Symlink -Source $themeSource   -Target $themeTarget

    Write-Step "Quick verification"
    if (-not (Test-Path $profileTarget)) { throw "Profile symlink missing." }
    if (-not (Test-Path $themeTarget))   { throw "Theme symlink missing." }
    $ompCmd2 = Get-Command oh-my-posh -ErrorAction SilentlyContinue
    if (-not $ompCmd2) {
        Write-Host "Warning: oh-my-posh still not found. You may need to restart the terminal for PATH changes to take effect." -ForegroundColor Yellow
    }

    Write-Host "`nSetup complete." -ForegroundColor Green
    Write-Host "Repo:    $repoRoot" -ForegroundColor DarkGray
    Write-Host "Backup:  $backupDir" -ForegroundColor DarkGray
    Write-Host "Please restart PowerShell for changes to take effect." -ForegroundColor Yellow
}
catch {
    Write-Host "`nSetup failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Rolling back..." -ForegroundColor Yellow
    Restore-IfBackedUp -OriginalPath $profileTarget
    Restore-IfBackedUp -OriginalPath $themeTarget
    Write-Host "Rollback complete, restored previous state." -ForegroundColor Yellow
    exit 1
}
