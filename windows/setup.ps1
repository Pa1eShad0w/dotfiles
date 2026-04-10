param(
    [switch]$SkipWingetInstall
)

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
            Write-Host "  已将原配置重命名为: $oldPath" -ForegroundColor Yellow
        }
    }

    New-Item -ItemType SymbolicLink -Path $Target -Target $Source -Force | Out-Null
    Write-Host "  $Target -> $Source" -ForegroundColor Green
}

try {
    Write-Step "备份现有配置"
    Backup-IfExists -Path $profileTarget
    Backup-IfExists -Path $themeTarget

    Write-Step "确保 NuGet Provider 可用"
    if (-not (Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue)) {
        Install-PackageProvider -Name NuGet -Scope CurrentUser -Force -SkipPublisherCheck | Out-Null
    }

    Write-Step "安装/确认 oh-my-posh"
    $ompCmd = Get-Command oh-my-posh -ErrorAction SilentlyContinue
    if (-not $ompCmd) {
        if ($SkipWingetInstall) {
            Write-Host "Skip winget install by flag. 请手动安装 oh-my-posh。" -ForegroundColor Yellow
        } else {
            $wingetCmd = Get-Command winget -ErrorAction SilentlyContinue
            if ($wingetCmd) {
                Write-Host "Installing oh-my-posh via winget..." -ForegroundColor Yellow
                winget install JanDeDobbeleer.OhMyPosh -s winget --accept-package-agreements --accept-source-agreements
            } else {
                Write-Host "winget 不可用，请手动安装 oh-my-posh: https://ohmyposh.dev/docs/installation/windows" -ForegroundColor Yellow
            }
        }
    } else {
        Write-Host "oh-my-posh exists." -ForegroundColor DarkGray
    }

    Write-Step "安装/确认 zoxide + fzf"
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
        Write-Host "winget 不可用，请手动安装 zoxide 和 fzf" -ForegroundColor Yellow
    }

    Write-Step "安装/确认 PowerShell 模块"
    Ensure-Module -Name PSReadLine    -MinimumVersion ([version]"2.2.6")
    Ensure-Module -Name posh-git
    Ensure-Module -Name Terminal-Icons
    Ensure-Module -Name PSFzf -MinimumVersion ([version]"2.5.0")
    $psfzfMod = Get-HighestInstalledModule -Name PSFzf
    if ($psfzfMod) {
        Write-Host "PSFzf ready: $($psfzfMod.Version) [$($psfzfMod.ModuleBase)]" -ForegroundColor DarkGray
    }

    Write-Step "校验 PSReadLine 版本"
    $psReadLine = Get-HighestInstalledModule -Name PSReadLine
    if (-not $psReadLine) { throw "PSReadLine 未安装成功。" }
    if ($psReadLine.Version -lt [version]"2.2.6") {
        throw "PSReadLine 版本过低: $($psReadLine.Version)，需要 >= 2.2.6"
    }
    Write-Host "PSReadLine ready: $($psReadLine.Version) [$($psReadLine.ModuleBase)]" -ForegroundColor DarkGray

    Write-Step "创建 symlink"
    New-Symlink -Source $profileSource -Target $profileTarget
    New-Symlink -Source $themeSource   -Target $themeTarget

    Write-Step "快速校验"
    if (-not (Test-Path $profileTarget)) { throw "Profile symlink 不存在。" }
    if (-not (Test-Path $themeTarget))   { throw "Theme symlink 不存在。" }
    $ompCmd2 = Get-Command oh-my-posh -ErrorAction SilentlyContinue
    if (-not $ompCmd2) {
        Write-Host "警告: oh-my-posh 仍不可用，可能需要重开终端后 PATH 才生效。" -ForegroundColor Yellow
    }

    Write-Host "`nSetup 完成。" -ForegroundColor Green
    Write-Host "Repo:    $repoRoot" -ForegroundColor DarkGray
    Write-Host "备份目录: $backupDir" -ForegroundColor DarkGray
    Write-Host "请重启 PowerShell 使配置生效。" -ForegroundColor Yellow
}
catch {
    Write-Host "`nSetup 失败: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "正在回滚..." -ForegroundColor Yellow
    Restore-IfBackedUp -OriginalPath $profileTarget
    Restore-IfBackedUp -OriginalPath $themeTarget
    Write-Host "回滚完成，已恢复到之前状态。" -ForegroundColor Yellow
    exit 1
}
