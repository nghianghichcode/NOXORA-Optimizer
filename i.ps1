$InstallPath = "$env:USERPROFILE\NOXORA-Optimizer"
$NoPrompt = $false
$RepoUrl = 'https://github.com/nghianghichcode/NOXORA-Optimizer.git'
$ErrorActionPreference = 'Stop'

function Write-Step {
    param([string]$Msg, [string]$Color = 'Cyan')
    Write-Host "  >> $Msg" -ForegroundColor $Color
}

function Write-OK   { param([string]$Msg) Write-Host "  [OK] $Msg"   -ForegroundColor Green }
function Write-Fail { param([string]$Msg) Write-Host "  [!!] $Msg"   -ForegroundColor Red }
function Write-Info { param([string]$Msg) Write-Host "  [i] $Msg"    -ForegroundColor DarkGray }

Write-Host "=============================" -ForegroundColor DarkGray
Write-Host "  NOXORA OPTIMIZER INSTALLER " -ForegroundColor Cyan
Write-Host "=============================" -ForegroundColor DarkGray

# Check Administrator
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Fail 'Must be run as Administrator. Right-click PowerShell > Run as administrator.'
    exit
}
Write-OK 'Running as Administrator'

# Check prerequisites
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Fail 'Git is not installed. Install from https://git-scm.com/download/win'
    exit
}
$gitVersion = (git --version).Trim()
Write-OK "Git found: $gitVersion"

$psVer = $PSVersionTable.PSVersion
Write-OK "PowerShell $psVer"

# Install or Update
Write-Step "Install location: $InstallPath"

if (Test-Path $InstallPath) {
    Write-Fail "'$InstallPath' already exists."
    $choice = 'U'
    if (-not $NoPrompt) {
        $choice = Read-Host "    [U] Update (git pull)   [R] Remove and reinstall   [C] Cancel

    Choice"
    }

    switch ($choice) {
        'U' {
            Write-Step 'Updating existing installation...'
            Push-Location $InstallPath
            try {
                cmd.exe /c "git pull origin main 2>&1"
                Write-OK 'Update complete.'
            } catch {
                Write-Fail "Update failed: $($_.Exception.Message)"
                Pop-Location
                exit
            }
            Pop-Location
        }
        'R' {
            Write-Step 'Removing existing installation...'
            Remove-Item $InstallPath -Recurse -Force -ErrorAction Stop
            Write-OK 'Removed.'
        }
        default {
            Write-Info 'Cancelled.'
            exit
        }
    }
}

if (-not (Test-Path $InstallPath)) {
    Write-Step "Cloning from: $RepoUrl"
    Write-Step "          to: $InstallPath"
    try {
        cmd.exe /c "git clone $RepoUrl $InstallPath 2>&1"
        if (Test-Path $InstallPath) {
            Write-OK 'Clone complete.'
        } else {
            Write-Fail 'Clone failed: directory not created.'
            exit
        }
    } catch {
        Write-Fail "Clone failed: $($_.Exception.Message)"
        exit
    }
}

# Verify required files
$requiredFiles = @('Noxora.ps1', 'Start-Noxora.bat', 'Setup-Noxora.ps1', 'config\settings.json')
$allFound = $true
foreach ($f in $requiredFiles) {
    if (-not (Test-Path (Join-Path $InstallPath $f))) {
        Write-Fail "Missing required file: $f"
        $allFound = $false
    }
}
if (-not $allFound) {
    Write-Fail 'Installation appears incomplete or corrupted.'
    exit
}
Write-OK 'All required files verified.'

# Run pre-flight
Write-Step 'Running pre-flight environment check...'
$setupScript = Join-Path $InstallPath 'Setup-Noxora.ps1'
if (Test-Path $setupScript) {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $setupScript
}

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " NOXORA OPTIMIZER installed successfully! " -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  To launch:" -ForegroundColor White
Write-Host "    cd "$InstallPath"" -ForegroundColor Cyan
Write-Host "    .\Start-Noxora.bat" -ForegroundColor Cyan
Write-Host ""
Write-Host "  First run will ask you to CREATE your OWNER account." -ForegroundColor DarkGray
Write-Host ""
Write-Step 'Launching NOXORA...'
Start-Process (Join-Path $InstallPath 'Start-Noxora.bat') -Verb RunAs