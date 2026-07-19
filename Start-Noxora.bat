@echo off
setlocal

rem ============================================================
rem NOXORA OPTIMIZER - Batch Launcher
rem Version : 1.0.0
rem Author  : NOXORA Project
rem ============================================================
rem This launcher only:
rem   1. Sets working directory to script location
rem   2. Checks for Administrator privilege
rem   3. Requests UAC elevation if needed
rem   4. Detects pwsh.exe vs powershell.exe
rem   5. Launches Noxora.ps1
rem ============================================================

title NOXORA OPTIMIZER

rem --- Change working directory to script location ---
cd /d "%~dp0"

rem --- Check Administrator privilege ---
fltmc >nul 2>&1
if errorlevel 1 (
    echo.
    echo  [!] NOXORA requires Administrator privileges.
    echo  [!] Requesting UAC elevation...
    echo.

    mshta "vbscript:CreateObject(\"Shell.Application\").ShellExecute(\"%ComSpec%\",\"/c \"\"%~f0\"\"\",\"%~dp0\",\"runas\",1)(window.close)"
    exit /b
)

rem --- Detect PowerShell engine ---
set "PS_EXE="
if exist "%ProgramFiles%\PowerShell\7\pwsh.exe" (
    set "PS_EXE=%ProgramFiles%\PowerShell\7\pwsh.exe"
    set "PS_VERSION=7+"
) else if exist "%ProgramFiles(x86)%\PowerShell\7\pwsh.exe" (
    set "PS_EXE=%ProgramFiles(x86)%\PowerShell\7\pwsh.exe"
    set "PS_VERSION=7+"
) else if exist "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" (
    set "PS_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
    set "PS_VERSION=5.1"
) else (
    echo.
    echo  [ERROR] No PowerShell executable found.
    echo  [ERROR] Install PowerShell 7+ from: https://aka.ms/powershell
    echo.
    pause
    exit /b 1
)

rem --- Verify Noxora.ps1 exists ---
if not exist "%~dp0Noxora.ps1" (
    echo.
    echo  [ERROR] Noxora.ps1 not found in:
    echo  [ERROR] %~dp0
    echo.
    pause
    exit /b 1
)

rem --- Launch NOXORA ---
rem -NoProfile     : Do not load user profile (clean environment)
rem -ExecutionPolicy Bypass : Scoped to this process only, not system-wide
rem -File          : Path to main script (literal path, no eval)
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

