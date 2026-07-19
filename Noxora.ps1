#Requires -Version 5.1
<#
.SYNOPSIS
    NOXORA OPTIMIZER — Main Entry Point
.DESCRIPTION
    Entry point for the NOXORA OPTIMIZER.
    This script ONLY:
      1. Validates the runtime environment
      2. Verifies Administrator privilege
      3. Loads all modules
      4. Initializes logging
      5. Handles OWNER authentication (first run or login)
      6. Displays the main menu and dispatches to sub-modules
      7. Manages session timeout
      8. Handles graceful exit

    All optimization logic lives in the modules/ directory.
    This script must not contain inline tweaks or system modifications.

.NOTES
    Author     : NOXORA Project
    Version    : 1.0.0
    Requires   : PowerShell 5.1+ or PowerShell 7+
    Requires   : Windows 10 Build 18362+ / Windows 11
    Requires   : Administrator privilege
    RunAs      : Administrator

.EXAMPLE
    # Launch via the batch file (recommended):
    .\Start-Noxora.bat

    # Or directly via PowerShell:
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\Noxora.ps1"
    pwsh.exe       -NoProfile -ExecutionPolicy Bypass -File ".\Noxora.ps1"
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest

#region ── Bootstrap: Absolute Minimum Before Any Module Loads ──────────────────

# Determine the root directory (where Noxora.ps1 lives)
$script:NoxoraRoot = $PSScriptRoot

if ([string]::IsNullOrEmpty($script:NoxoraRoot)) {
    # Fallback for older PS versions
    $script:NoxoraRoot = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition
}

# Verify we can find the modules directory before doing anything else
$modulesPath = Join-Path -Path $script:NoxoraRoot -ChildPath 'modules'
if (-not (Test-Path -LiteralPath $modulesPath -PathType Container)) {
    Write-Host ''
    Write-Host "  [CRITICAL] NOXORA modules directory not found:" -ForegroundColor Red
    Write-Host "  [CRITICAL] $modulesPath" -ForegroundColor Red
    Write-Host ''
    Write-Host '  Ensure you are running from the NOXORA-Optimizer directory.' -ForegroundColor Yellow
    Write-Host ''
    if ($Host.Name -eq 'ConsoleHost') { $null = Read-Host 'Press Enter to exit' }
    exit 1
}

#endregion

#region ── Module Loading ────────────────────────────────────────────────────────

$moduleLoadOrder = @(
    'Noxora.Core.psm1',
    'Noxora.Logging.psm1',
    'Noxora.Auth.psm1',
    'Noxora.UI.psm1',
    'Noxora.Session.psm1'
)

foreach ($moduleName in $moduleLoadOrder) {
    $modulePath = Join-Path -Path $modulesPath -ChildPath $moduleName
    if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) {
        Write-Host "  [CRITICAL] Required module not found: $modulePath" -ForegroundColor Red
        exit 1
    }
    try {
        Import-Module -Name $modulePath -Force -ErrorAction Stop
    }
    catch {
        Write-Host "  [CRITICAL] Failed to load module '$moduleName': $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

#endregion

#region ── Core Initialization ──────────────────────────────────────────────────

$coreInit = Initialize-NoxoraCore -RootPath $script:NoxoraRoot

if (-not $coreInit.Success) {
    Write-Host ''
    Write-Host '  [CRITICAL] NOXORA core initialization failed:' -ForegroundColor Red
    foreach ($err in $coreInit.Errors) {
        Write-Host "    - $err" -ForegroundColor Red
    }
    Write-Host ''
    if ($Host.Name -eq 'ConsoleHost') { $null = Read-Host 'Press Enter to exit' }
    exit 1
}

$script:EnvInfo = $coreInit.Environment
$script:Config  = Get-NoxoraConfig

#endregion

#region ── Logging Initialization ───────────────────────────────────────────────

$logDir   = Get-NoxoraDataPath -SubPath 'logs'
$auditDir = Get-NoxoraDataPath -SubPath 'logs\audit'

$logInit = Initialize-NoxoraLogging `
    -LogDirectory   $logDir `
    -AuditDirectory $auditDir `
    -LogLevel       $script:Config.logging.logLevel `
    -MaxLogSizeMB   $script:Config.logging.maxLogFileSizeMB `
    -MaxLogFiles    $script:Config.logging.maxLogFiles

if (-not $logInit.Success) {
    Write-Host "  [WARN] Logging initialization failed: $($logInit.Message)" -ForegroundColor Yellow
    # Non-fatal — continue without logging
}

#endregion

#region ── UI Initialization ────────────────────────────────────────────────────

Initialize-NoxoraUI -Config $script:Config

#endregion

#region ── Auth Initialization ──────────────────────────────────────────────────

$authDir  = Get-NoxoraDataPath -SubPath 'auth'
$authInit = Initialize-NoxoraAuth -AuthDirectory $authDir -Config $script:Config

if (-not $authInit.Success) {
    Write-NoxoraLog -Level 'Error' -Message "Auth initialization failed: $($authInit.Message)" -Category 'Auth'
    Show-NoxoraErrorMessage -Title 'Authentication Init Failed' -Message $authInit.Message
    exit 1
}

#endregion

#region ── Helper: Run First-Time Owner Setup ───────────────────────────────────

function Invoke-FirstRunSetup {
    <#
    .SYNOPSIS
        Guides the OWNER through account creation on first launch.
    .OUTPUTS
        $true if setup succeeded, $false if cancelled or failed.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $maxAttempts = 3
    $attempt     = 0

    while ($attempt -lt $maxAttempts) {
        $attempt++

        $credentials = Show-NoxoraAuthScreen `
            -EnvInfo    $script:EnvInfo `
            -IsFirstRun `
            -ErrorMessage (if ($attempt -gt 1) { "Setup failed. Attempt $attempt of $maxAttempts." } else { '' })

        if ($null -eq $credentials) {
            Write-NoxoraLog -Level 'Info' -Message 'First-run setup cancelled by user.' -Category 'Auth'
            return $false
        }

        # Validate username
        if ($credentials.Username -notmatch '^[a-zA-Z0-9_\-]{3,32}$') {
            $errorMsg = 'Username must be 3-32 characters (letters, digits, _ or -).'
            continue
        }

        $createResult = New-NoxoraOwner `
            -Username        $credentials.Username `
            -Password        $credentials.Password `
            -ConfirmPassword $credentials.ConfirmPassword `
            -Confirm:$false

        if ($createResult.Success) {
            Write-NoxoraLog -Level 'Info' -Message "OWNER account created: $($credentials.Username)" -Category 'Auth'

            Clear-Host
            Show-NoxoraBanner
            $w = ($script:Config.ui.menuWidth)
            Write-NoxoraBoxTop    -Title 'SETUP COMPLETE' -Width $w
            Write-NoxoraBoxRow    -Content " OWNER account created successfully."        -ContentColor 'Green'  -Width $w
            Write-NoxoraBoxRow    -Content " Username: $($credentials.Username)"         -ContentColor 'White'  -Width $w
            Write-NoxoraBoxRow    -Content ''                                             -Width $w
            Write-NoxoraBoxRow    -Content ' You can now log in with your credentials.'  -ContentColor 'DarkGray' -Width $w
            Write-NoxoraBoxBottom -Width $w
            Write-Host ''
            Show-NoxoraContinuePrompt
            return $true
        }
        else {
            Write-NoxoraLog -Level 'Warn' -Message "Owner creation failed: $($createResult.Message)" -Category 'Auth'
        }
    }

    Show-NoxoraErrorMessage -Title 'Setup Failed' -Message "Failed after $maxAttempts attempts. Please restart NOXORA."
    return $false
}

#endregion

#region ── Authentication Loop ──────────────────────────────────────────────────

function Invoke-AuthenticationLoop {
    <#
    .SYNOPSIS
        Handles the full authentication flow: first run or repeat login.
    .OUTPUTS
        PSCustomObject session on success, or $null if user cancels.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    # Check if OWNER account exists; if not, run first-time setup
    if (-not (Test-NoxoraOwnerExists)) {
        $setupOk = Invoke-FirstRunSetup
        if (-not $setupOk) {
            return $null
        }
    }

    $failureCount = 0
    $maxAttempts  = $script:Config.auth.maxLoginAttempts
    $errorMessage = ''

    while ($true) {
        $credentials = Show-NoxoraAuthScreen `
            -EnvInfo      $script:EnvInfo `
            -FailureCount $failureCount `
            -ErrorMessage $errorMessage

        if ($null -eq $credentials) {
            Write-NoxoraLog -Level 'Info' -Message 'Login cancelled by user.' -Category 'Auth'
            return $null
        }

        $loginResult = Invoke-NoxoraLogin `
            -Username $credentials.Username `
            -Password $credentials.Password

        if ($loginResult.IsLockedOut) {
            $errorMessage = $loginResult.Message
            $failureCount = $loginResult.FailureCount

            # Show locked screen with countdown
            Show-NoxoraAuthScreen `
                -EnvInfo      $script:EnvInfo `
                -FailureCount $failureCount `
                -ErrorMessage $errorMessage | Out-Null

            if ($null -ne $loginResult.LockoutUntil) {
                $secondsLeft = [math]::Ceiling(($loginResult.LockoutUntil - (Get-Date)).TotalSeconds)
                Write-NoxoraLog -Level 'Warn' -Message "Account locked for $secondsLeft seconds." -Category 'Auth'

                $pad = Get-CenterPad -ContentWidth $script:Config.ui.menuWidth
                Write-Host ''
                Write-Host "${pad}  Waiting for lockout to expire..." -ForegroundColor Yellow

                # Wait in 5-second intervals, showing remaining time
                while ((Get-Date) -lt $loginResult.LockoutUntil) {
                    $remaining = [math]::Ceiling(($loginResult.LockoutUntil - (Get-Date)).TotalSeconds)
                    Write-Host "`r${pad}  Lockout expires in $remaining second(s)...   " -NoNewline -ForegroundColor Yellow
                    Start-Sleep -Seconds 5
                }
                Write-Host ''
            }
            continue
        }

        if ($loginResult.Success) {
            return $loginResult.Session
        }
        else {
            $failureCount = $loginResult.FailureCount
            $errorMessage = $loginResult.Message

            if ($failureCount -ge $maxAttempts) {
                # Will be handled as lockout on next iteration
                continue
            }
        }
    }
}

#endregion

#region ── Main Menu Dispatch ───────────────────────────────────────────────────

function Invoke-MainMenuLoop {
    <#
    .SYNOPSIS
        Runs the main menu event loop until the user exits or logs out.
    .OUTPUTS
        String — 'logout' or 'exit'.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    while ($true) {
        # Check session validity before each menu display
        $sessionCheck = Test-NoxoraSessionValid
        if (-not $sessionCheck.IsValid) {
            Write-NoxoraLog -Level 'Warn' -Message 'Session expired. Returning to login.' -Category 'Auth'
            return 'logout'
        }

        if ($sessionCheck.NeedsWarning) {
            Write-NoxoraLog -Level 'Warn' -Message "Session expiring in $($sessionCheck.MinutesRemaining) minutes." -Category 'Auth'
        }

        $session = Get-NoxoraSession
        if ($null -eq $session) { return 'logout' }

        $selection = Show-NoxoraMainMenu -SessionInfo $session -EnvInfo $script:EnvInfo

        # Refresh session on any activity
        Update-NoxoraSessionActivity

        switch ($selection.ToUpper()) {
            '1'  { Invoke-SystemDashboard }
            '2'  { Show-NoxoraNotAvailableMessage -FeatureName 'CPU Performance Optimization' -Phase '3' }
            '3'  { Show-NoxoraNotAvailableMessage -FeatureName 'GPU Performance Optimization' -Phase '3' }
            '4'  { Show-NoxoraNotAvailableMessage -FeatureName 'Process Optimizer'             -Phase '3' }
            '5'  { Show-NoxoraNotAvailableMessage -FeatureName 'System Debloater'              -Phase '4' }
            '6'  { Show-NoxoraNotAvailableMessage -FeatureName 'Services Optimizer'            -Phase '3' }
            '7'  { Show-NoxoraNotAvailableMessage -FeatureName 'Startup Optimizer'             -Phase '3' }
            '8'  { Show-NoxoraNotAvailableMessage -FeatureName 'Network Optimizer'             -Phase '4' }
            '9'  { Show-NoxoraNotAvailableMessage -FeatureName 'RAM and Memory Optimizer'      -Phase '3' }
            '10' { Show-NoxoraNotAvailableMessage -FeatureName 'Smart Game Boost'              -Phase '5' }
            '11' { Show-NoxoraNotAvailableMessage -FeatureName 'Thermal Analysis'              -Phase '5' }
            '12' { Show-NoxoraNotAvailableMessage -FeatureName 'Security Center'               -Phase '6' }
            '13' { Show-NoxoraNotAvailableMessage -FeatureName 'Backup and Restore'            -Phase '4' }
            '14' { Show-NoxoraNotAvailableMessage -FeatureName 'Reports'                       -Phase '2' }
            'L'  {
                Write-NoxoraLog -Level 'Info' -Message 'User initiated logout.' -Category 'Auth'
                $null = Invoke-NoxoraLogout
                return 'logout'
            }
            '0'  {
                $confirmed = Invoke-NoxoraConfirm `
                    -Title       'Exit NOXORA' `
                    -Description 'Close the NOXORA Optimizer.' `
                    -Risk        'Low'
                if ($confirmed) {
                    Write-NoxoraLog -Level 'Info' -Message 'User initiated exit.' -Category 'Auth'
                    $null = Invoke-NoxoraLogout
                    return 'exit'
                }
            }
            default {
                # Invalid option — silently re-display menu
                Write-NoxoraLog -Level 'Debug' -Message "Invalid menu selection: '$selection'" -Category 'UI'
            }
        }

        # Show continue prompt for "not available" screens
        if ($selection -notin @('0', 'L') -and $selection -match '^([2-9]|1[0-4])$') {
            Show-NoxoraContinuePrompt
        }
    }
}

#endregion

#region ── Phase 1 System Dashboard (Minimal Version) ───────────────────────────

function Invoke-SystemDashboard {
    <#
    .SYNOPSIS
        Displays a basic system dashboard with available system information.
        Full implementation in Phase 2 (Noxora.System.psm1).
    #>
    [CmdletBinding()]
    param()

    $w = $script:Config.ui.menuWidth

    Clear-Host
    Show-NoxoraBanner

    Write-NoxoraLog -Level 'Info' -Message 'System dashboard viewed.' -Category 'Dashboard'

    Write-NoxoraBoxTop -Title 'SYSTEM DASHBOARD' -Width $w
    Write-NoxoraBoxDivider -Width $w
    Write-NoxoraBoxRow -Content " Computer    : $($script:EnvInfo.ComputerName)"                              -ContentColor 'White'    -Width $w
    Write-NoxoraBoxRow -Content " Windows     : $($script:EnvInfo.OSCaption -replace 'Microsoft ','')"       -ContentColor 'White'    -Width $w
    Write-NoxoraBoxRow -Content " Build       : $($script:EnvInfo.OSBuild)"                                   -ContentColor 'White'    -Width $w
    Write-NoxoraBoxRow -Content " Architecture: $($script:EnvInfo.OSArchitecture)"                           -ContentColor 'White'    -Width $w
    Write-NoxoraBoxRow -Content " PowerShell  : $($script:EnvInfo.PSVersion) ($($script:EnvInfo.PSEdition))" -ContentColor 'White'    -Width $w
    Write-NoxoraBoxRow -Content " Privilege   : Administrator"                                                 -ContentColor 'Green'    -Width $w
    Write-NoxoraBoxDivider -Width $w

    # Try to get basic CPU info
    try {
        $cpu = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop | Select-Object -First 1
        Write-NoxoraBoxRow -Content " CPU         : $($cpu.Name.Trim())"        -ContentColor 'Cyan' -Width $w
        Write-NoxoraBoxRow -Content " Cores       : $($cpu.NumberOfCores)"      -ContentColor 'White' -Width $w
        Write-NoxoraBoxRow -Content " Threads     : $($cpu.NumberOfLogicalProcessors)" -ContentColor 'White' -Width $w
        Write-NoxoraBoxRow -Content " CPU Load    : $($cpu.LoadPercentage)%"    -ContentColor $(if ($cpu.LoadPercentage -gt 80) {'Red'} elseif ($cpu.LoadPercentage -gt 50) {'Yellow'} else {'Green'}) -Width $w
    }
    catch {
        Write-NoxoraBoxRow -Content ' CPU         : Not available'  -ContentColor 'DarkGray' -Width $w
    }

    Write-NoxoraBoxDivider -Width $w

    # Try to get basic RAM info
    try {
        $os    = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $total = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
        $free  = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
        $used  = [math]::Round($total - $free, 1)
        $usePct = [math]::Round(($used / $total) * 100, 0)

        Write-NoxoraBoxRow -Content " RAM Total   : $total GB"                    -ContentColor 'White'  -Width $w
        Write-NoxoraBoxRow -Content " RAM Used    : $used GB ($usePct%)"          -ContentColor $(if ($usePct -gt 85) {'Red'} elseif ($usePct -gt 65) {'Yellow'} else {'Green'}) -Width $w
        Write-NoxoraBoxRow -Content " RAM Free    : $free GB"                     -ContentColor 'Green'  -Width $w
    }
    catch {
        Write-NoxoraBoxRow -Content ' RAM         : Not available'  -ContentColor 'DarkGray' -Width $w
    }

    Write-NoxoraBoxDivider -Width $w
    Write-NoxoraBoxRow -Content ' Full dashboard available in Phase 2.'  -ContentColor 'DarkGray' -Width $w
    Write-NoxoraBoxRow -Content ' Hardware detection (CPU/GPU) in Phase 2.' -ContentColor 'DarkGray' -Width $w
    Write-NoxoraBoxBottom -Width $w

    Show-NoxoraContinuePrompt
}

#endregion

#region ── Main Program ─────────────────────────────────────────────────────────

try {
    Write-NoxoraLog -Level 'Info' -Message "NOXORA starting. Root: $script:NoxoraRoot" -Category 'Main'

    $exitLoop = $false

    while (-not $exitLoop) {
        # Authentication loop — returns session or $null (user cancelled)
        $authSession = Invoke-AuthenticationLoop

        if ($null -eq $authSession) {
            Write-NoxoraLog -Level 'Info' -Message 'Authentication cancelled. Exiting.' -Category 'Main'
            $exitLoop = $true
            break
        }

        Write-NoxoraLog -Level 'Info' -Message "Session started: $($authSession.SessionId)" -Category 'Main'

        # Main menu loop — runs until logout or exit
        $menuResult = Invoke-MainMenuLoop

        Write-NoxoraLog -Level 'Info' -Message "Menu loop ended with: $menuResult" -Category 'Main'

        if ($menuResult -eq 'exit') {
            $exitLoop = $true
        }
        # If 'logout', loop back to authentication
    }
}
catch {
    $errorMsg = "Unhandled exception in main program: $($_.Exception.Message)"
    Write-NoxoraLog -Level 'Error' -Message $errorMsg -Category 'Main'

    try {
        Show-NoxoraErrorMessage -Title 'Critical Error' -Message $errorMsg
    }
    catch {
        Write-Host "  [CRITICAL] $errorMsg" -ForegroundColor Red
    }
    exit 1
}
finally {
    Write-NoxoraLog -Level 'Info' -Message 'NOXORA session ended.' -Category 'Main'
}

exit 0
#endregion
