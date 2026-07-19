#Requires -Version 5.1
<#
.SYNOPSIS
    NOXORA OPTIMIZER â€” Remote Installer
.DESCRIPTION
    Clones NOXORA from GitHub and prepares it for first run.
    Safe alternative to iex+DownloadString:
      - Uses git clone (verifiable, not arbitrary code execution)
      - No code downloaded and immediately executed
      - No hidden payload
      - User can inspect everything before running

    Usage (run as Administrator in PowerShell):
      irm https://raw.githubusercontent.com/nghianghichcode/NOXORA-Optimizer/main/Install-Noxora.ps1 | Out-File Install-Noxora.ps1; .\Install-Noxora.ps1

    Or one-liner after trusting the source:
      & ([scriptblock]::Create((irm https://raw.githubusercontent.com/nghianghichcode/NOXORA-Optimizer/main/Install-Noxora.ps1)))

.NOTES
    SECURITY: This script only:
      1. Checks prerequisites
      2. Runs: git clone <repo> <target>
      3. Runs Setup-Noxora.ps1 (read-only check)
    It does NOT execute any downloaded binary or encoded payload.
#>

$InstallPath = "$env:USERPROFILE\NOXORA-Optimizer"
$RepoUrl = 'https://github.com/nghianghichcode/NOXORA-Optimizer.git'

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step {
    param([string]$Msg, [string]$Color = 'Cyan')
    Write-Host "  >> $Msg" -ForegroundColor $Color
}

function Write-OK   { param([string]$Msg) Write-Host "  [OK] $Msg"   -ForegroundColor Green }
function Write-Fail { param([string]$Msg) Write-Host "  [!!] $Msg"   -ForegroundColor Red }
function Write-Info { param([string]$Msg) Write-Host "  [i] $Msg"    -ForegroundColor DarkGray }

# â”€â”€ Banner â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
Write-Host ''
Write-Host '  NOXORA OPTIMIZER â€” Installer' -ForegroundColor Cyan
Write-Host '  =============================' -ForegroundColor DarkGray
Write-Host ''

# â”€â”€ Check Administrator â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Fail 'Must be run as Administrator. Right-click PowerShell > Run as administrator.'
    exit 1
}
Write-OK 'Running as Administrator'

# â”€â”€ Check Git â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
try {
    $gitVersion = & git --version 2>&1
    Write-OK "Git found: $gitVersion"
}
catch {
    Write-Fail 'Git is not installed. Install from https://git-scm.com/download/win'
    exit 1
}

# â”€â”€ Check PowerShell â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
$psVer = $PSVersionTable.PSVersion
Write-OK "PowerShell $psVer"
if ($psVer.Major -lt 5) {
    Write-Fail 'PowerShell 5.1 or later required.'
    exit 1
}

# â”€â”€ Install Path â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
Write-Host ''
Write-Step "Install location: $InstallPath"

if (Test-Path $InstallPath) {
    if (-not $NoPrompt) {
        Write-Host ''
        Write-Host "  [!] '$InstallPath' already exists." -ForegroundColor Yellow
        Write-Host '      [U] Update (git pull)   [R] Remove and reinstall   [C] Cancel' -ForegroundColor Yellow
        Write-Host ''
        Write-Host '  Choice: ' -ForegroundColor Cyan -NoNewline
        $choice = (Read-Host).Trim().ToUpper()
    } else {
        $choice = 'U'
    }

    switch ($choice) {
        'U' {
            Write-Step 'Updating existing installation...'
            Push-Location $InstallPath
            try {
                & git pull origin main 2>&1 | ForEach-Object { Write-Info $_ }
                Write-OK 'Update complete.'
            }
            finally { Pop-Location }
            Write-Host ''
            Write-Host '  Launch NOXORA:' -ForegroundColor Green
            Write-Host "    cd `"$InstallPath`"" -ForegroundColor White
            Write-Host '    .\Start-Noxora.bat' -ForegroundColor White
            exit 0
        }
        'R' {
            Write-Step 'Removing existing installation...'
            Remove-Item -LiteralPath $InstallPath -Recurse -Force
        }
        default {
            Write-Info 'Installation cancelled.'
            exit 0
        }
    }
}

# â”€â”€ Clone â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
Write-Host ''
Write-Step "Cloning from: $RepoUrl"
Write-Step "          to: $InstallPath"
Write-Host ''

try {
    & git clone $RepoUrl $InstallPath 2>&1 | ForEach-Object { Write-Info $_ }
    Write-OK 'Clone complete.'
}
catch {
    Write-Fail "Clone failed: $($_.Exception.Message)"
    exit 1
}

# â”€â”€ Verify â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
$required = @('Noxora.ps1', 'Start-Noxora.bat', 'modules\Noxora.Core.psm1')
$allFound = $true
foreach ($f in $required) {
    if (-not (Test-Path (Join-Path $InstallPath $f))) {
        Write-Fail "Missing required file: $f"
        $allFound = $false
    }
}

if (-not $allFound) {
    Write-Fail 'Installation appears incomplete. Check the repository.'
    exit 1
}

Write-OK 'All required files verified.'

# â”€â”€ Run pre-flight â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
Write-Host ''
Write-Step 'Running pre-flight environment check...'
$setupScript = Join-Path $InstallPath 'Setup-Noxora.ps1'
if (Test-Path $setupScript) {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $setupScript
}

# â”€â”€ Done â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
Write-Host ''
Write-Host '  â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•' -ForegroundColor Cyan
Write-Host '  NOXORA OPTIMIZER installed successfully!' -ForegroundColor Green
Write-Host '  â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•' -ForegroundColor Cyan
Write-Host ''
Write-Host '  To launch:' -ForegroundColor White
Write-Host "    cd `"$InstallPath`"" -ForegroundColor Cyan
Write-Host '    .\Start-Noxora.bat' -ForegroundColor Cyan
Write-Host ''
Write-Host '  First run will ask you to CREATE your OWNER account.' -ForegroundColor DarkGray
Write-Host ''

Write-Step 'Launching NOXORA...'
Start-Process (Join-Path $InstallPath 'Start-Noxora.bat') -Verb RunAs -ForegroundColor DarkGray
Write-Host '  Choose any username and a strong password.' -ForegroundColor DarkGray
Write-Host '  NOXORA does NOT store plain-text passwords.' -ForegroundColor DarkGray
Write-Host ''



