# NOXORA OPTIMIZER — Setup Script
# Run this on first install to prepare the environment.
# Noxora.ps1 handles first-run setup automatically, but this script
# can be used for pre-flight checks and environment preparation.

#Requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$CheckOnly,
    [switch]$Verbose
)

Set-StrictMode -Version Latest

$script:Root = $PSScriptRoot
$ok = $true

function Write-Status {
    param([string]$Label, [bool]$Pass, [string]$Detail = '')
    $icon  = if ($Pass) { '[OK]  ' } else { '[FAIL]' }
    $color = if ($Pass) { 'Green' } else { 'Red' }
    $line  = "  $icon $Label"
    if ($Detail) { $line += " - $Detail" }
    Write-Host $line -ForegroundColor $color
    return $Pass
}

Write-Host ''
Write-Host '  NOXORA OPTIMIZER — Environment Setup Check' -ForegroundColor Cyan
Write-Host '  ===========================================' -ForegroundColor DarkGray
Write-Host ''

# Check PowerShell version
$psOk = $PSVersionTable.PSVersion.Major -ge 5
$ok = $ok -and (Write-Status 'PowerShell version' $psOk "Found: $($PSVersionTable.PSVersion)")

# Check Administrator privilege
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
$ok = $ok -and (Write-Status 'Administrator privilege' $isAdmin)

# Check Windows build
$build = [int](Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').CurrentBuild
$buildOk = $build -ge 18362
$ok = $ok -and (Write-Status 'Windows build' $buildOk "Build $build (min: 18362)")

# Check required files
$requiredFiles = @(
    'Noxora.ps1',
    'modules\Noxora.Core.psm1',
    'modules\Noxora.Logging.psm1',
    'modules\Noxora.Auth.psm1',
    'modules\Noxora.UI.psm1',
    'modules\Noxora.Session.psm1',
    'config\settings.json',
    'config\protected-processes.json',
    'config\protected-services.json'
)

foreach ($file in $requiredFiles) {
    $exists = Test-Path (Join-Path $script:Root $file)
    $ok = $ok -and (Write-Status "File: $file" $exists)
}

# Check CIM/WMI
try {
    $null = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    $ok = $ok -and (Write-Status 'CIM/WMI access' $true)
}
catch {
    $ok = $ok -and (Write-Status 'CIM/WMI access' $false $_.Exception.Message)
}

Write-Host ''
if ($ok) {
    Write-Host '  RESULT: Environment is ready. Run Start-Noxora.bat to launch.' -ForegroundColor Green
} else {
    Write-Host '  RESULT: Prerequisites not met. Fix the issues above before running.' -ForegroundColor Red
}
Write-Host ''
