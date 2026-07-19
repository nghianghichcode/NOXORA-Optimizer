@echo off
setlocal EnableDelayedExpansion

:: ============================================================
:: NOXORA OPTIMIZER — Batch Launcher
:: Version : 1.0.0
:: Author  : NOXORA Project
:: ============================================================
:: This launcher ONLY:
::   1. Sets working directory to script location
::   2. Checks for Administrator privilege
::   3. Requests UAC elevation if needed
::   4. Detects pwsh.exe vs powershell.exe
::   5. Launches Noxora.ps1
::
:: It does NOT:
::   - Store credentials
::   - Modify ExecutionPolicy system-wide
::   - Download or execute code from the Internet
::   - Run any tweak or optimization itself
:: ============================================================

title NOXORA OPTIMIZER

:: --- Change working directory to script location ---
cd /d "%~dp0"

:: --- Check Administrator privilege ---
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo.
    echo  [!] NOXORA requires Administrator privileges.
    echo  [!] Requesting UAC elevation...
    echo.

    :: Re-launch this script with elevation via PowerShell UAC trick
    :: (does not modify policy, does not download anything)
    set "SCRIPT=%~f0"
    powershell.exe -NoProfile -Command ^
        "Start-Process -FilePath '!SCRIPT!' -Verb RunAs"
    exit /b
)

:: --- Detect PowerShell engine ---
set "PS_EXE="
where pwsh.exe >nul 2>&1
if %errorlevel% equ 0 (
    set "PS_EXE=pwsh.exe"
    set "PS_VERSION=7+"
) else (
    where powershell.exe >nul 2>&1
    if %errorlevel% equ 0 (
        set "PS_EXE=powershell.exe"
        set "PS_VERSION=5.1"
    ) else (
        echo.
        echo  [ERROR] No PowerShell executable found.
        echo  [ERROR] Install PowerShell 7+ from: https://aka.ms/powershell
        echo.
        pause
        exit /b 1
    )
)

:: --- Verify Noxora.ps1 exists ---
if not exist "%~dp0Noxora.ps1" (
    echo.
    echo  [ERROR] Noxora.ps1 not found in:
    echo  [ERROR] %~dp0
    echo.
    pause
    exit /b 1
)

:: --- Launch NOXORA ---
:: -NoProfile     : Do not load user profile (clean environment)
:: -ExecutionPolicy Bypass : Scoped to this process only, not system-wide
:: -File          : Path to main script (literal path, no eval)
"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass ^
    -File "%~dp0Noxora.ps1"

set "EXIT_CODE=%errorlevel%"

if %EXIT_CODE% neq 0 (
    echo.
    echo  [NOXORA] Exited with code %EXIT_CODE%
    pause
)

endlocal
exit /b %EXIT_CODE%
