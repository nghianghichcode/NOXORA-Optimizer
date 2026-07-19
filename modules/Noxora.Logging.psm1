#Requires -Version 5.1
<#
.SYNOPSIS
    NOXORA Optimizer — Logging Module
.DESCRIPTION
    Structured logging with log levels, audit trail, log rotation,
    and strict prohibition on logging sensitive data.
.NOTES
    Author  : NOXORA Project
    Version : 1.0.0

    SECURITY: This module NEVER logs:
      - Passwords, hashes, or salts
      - Authentication tokens or cookies
      - Browser data or credentials
      - Any SecureString content
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region - Module State
$script:LogDirectory   = $null
$script:AuditDirectory = $null
$script:CurrentLogFile = $null
$script:AuditLogFile   = $null
$script:MaxLogSizeMB   = 10
$script:MaxLogFiles    = 10
$script:LogLevel       = 'Info'
$script:LogInitialized = $false

$script:LogLevelOrder = @{
    'Debug'   = 0
    'Info'    = 1
    'Pass'    = 2
    'Skip'    = 3
    'Warn'    = 4
    'Fail'    = 5
    'Error'   = 6
    'Backup'  = 2
    'Result'  = 2
    'Restore' = 2
    'Audit'   = 2
    'Action'  = 2
}
#endregion

#region - Public Functions

function Initialize-NoxoraLogging {
    <#
    .SYNOPSIS
        Initializes the NOXORA logging system.
    .DESCRIPTION
        Creates log directory, sets log file paths, applies rotation,
        and writes session start entry.
    .PARAMETER LogDirectory
        Path to the log directory.
    .PARAMETER AuditDirectory
        Path to the audit log directory.
    .PARAMETER LogLevel
        Minimum log level: Debug, Info, Warn, Error.
    .PARAMETER MaxLogSizeMB
        Maximum log file size in MB before rotation.
    .PARAMETER MaxLogFiles
        Maximum number of archived log files to retain.
    .OUTPUTS
        PSCustomObject with Success and Message.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$LogDirectory,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$AuditDirectory,

        [ValidateSet('Debug', 'Info', 'Warn', 'Error')]
        [string]$LogLevel = 'Info',

        [ValidateRange(1, 100)]
        [int]$MaxLogSizeMB = 10,

        [ValidateRange(1, 50)]
        [int]$MaxLogFiles = 10
    )

    $result = [PSCustomObject]@{
        Success = $false
        Message = ''
    }

    try {
        # Create directories if missing
        foreach ($dir in @($LogDirectory, $AuditDirectory)) {
            if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
                $null = New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop
            }
        }

        $script:LogDirectory   = $LogDirectory
        $script:AuditDirectory = $AuditDirectory
        $script:LogLevel       = $LogLevel
        $script:MaxLogSizeMB   = $MaxLogSizeMB
        $script:MaxLogFiles    = $MaxLogFiles

        # Build log file paths with timestamp
        $timestamp = Get-Date -Format 'yyyy-MM-dd'
        $script:CurrentLogFile = Join-Path -Path $LogDirectory -ChildPath "noxora-$timestamp.log"
        $script:AuditLogFile   = Join-Path -Path $AuditDirectory -ChildPath "audit-$timestamp.log"

        # Rotate logs if needed
        Invoke-NoxoraLogRotation

        $script:LogInitialized = $true

        # Write session start
        Write-NoxoraLog -Level 'Info' -Message "═══════════════════════════════════════"
        Write-NoxoraLog -Level 'Info' -Message "NOXORA OPTIMIZER — Session Started"
        Write-NoxoraLog -Level 'Info' -Message "Computer : $env:COMPUTERNAME"
        Write-NoxoraLog -Level 'Info' -Message "User     : $env:USERNAME"
        Write-NoxoraLog -Level 'Info' -Message "PSVersion: $($PSVersionTable.PSVersion)"
        Write-NoxoraLog -Level 'Info' -Message "═══════════════════════════════════════"

        $result.Success = $true
        $result.Message = "Logging initialized. Log: $($script:CurrentLogFile)"
    }
    catch {
        $result.Message = "Failed to initialize logging: $($_.Exception.Message)"
    }

    return $result
}

function Write-NoxoraLog {
    <#
    .SYNOPSIS
        Writes a structured log entry to the NOXORA log file.
    .PARAMETER Level
        Log level: Debug, Info, Pass, Skip, Warn, Fail, Error, Backup, Result, Restore, Action.
    .PARAMETER Message
        The log message. Must NOT contain passwords, hashes, or credentials.
    .PARAMETER Category
        Optional category tag (e.g., CPU, GPU, Auth, Security).
    .PARAMETER ActionId
        Optional Action ID to associate with this log entry.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Debug','Info','Pass','Skip','Warn','Fail','Error','Backup','Result','Restore','Audit','Action')]
        [string]$Level,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,

        [string]$Category = '',
        [string]$ActionId = ''
    )

    if (-not $script:LogInitialized) { return }

    # Filter by configured log level
    $currentLevelOrder = $script:LogLevelOrder[$script:LogLevel]
    $messageLevelOrder = $script:LogLevelOrder[$Level]
    if ($messageLevelOrder -lt $currentLevelOrder) { return }

    try {
        $timestamp   = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $levelPadded = $Level.ToUpper().PadRight(7)
        $categoryStr = if ($Category) { "[$Category] " } else { '' }
        $actionStr   = if ($ActionId) { "{$ActionId} " } else { '' }

        $line = "[$timestamp] [$levelPadded] $categoryStr$actionStr$Message"

        # Rotate before writing if needed
        if (Test-Path -LiteralPath $script:CurrentLogFile -PathType Leaf) {
            $size = (Get-Item -LiteralPath $script:CurrentLogFile).Length / 1MB
            if ($size -ge $script:MaxLogSizeMB) {
                Invoke-NoxoraLogRotation
            }
        }

        $line | Out-File -LiteralPath $script:CurrentLogFile -Append -Encoding UTF8
    }
    catch {
        # Log writes are non-fatal - silently continue
    }
}

function Write-NoxoraAuditLog {
    <#
    .SYNOPSIS
        Writes a security audit log entry.
    .DESCRIPTION
        Used for authentication events: login success, login failed, logout.
        NEVER logs passwords, hashes, salts, or credentials.
    .PARAMETER EventType
        Type of audit event: LoginSuccess, LoginFailed, Logout, SessionTimeout.
    .PARAMETER Username
        The username involved (not the password).
    .PARAMETER Details
        Additional details (no sensitive data).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('LoginSuccess', 'LoginFailed', 'Logout', 'SessionTimeout', 'LockoutActivated', 'FirstSetup')]
        [string]$EventType,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Username,

        [string]$Details = ''
    )

    if (-not $script:LogInitialized) { return }

    try {
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $computer  = $env:COMPUTERNAME
        $detailStr = if ($Details) { " | $Details" } else { '' }

        $line = "[$timestamp] [AUDIT  ] [$EventType] User=$Username Computer=$computer$detailStr"

        $line | Out-File -LiteralPath $script:AuditLogFile -Append -Encoding UTF8

        # Also write to main log at Info level
        Write-NoxoraLog -Level 'Audit' -Message "[$EventType] User=$Username$detailStr" -Category 'Auth'
    }
    catch {
        # Audit log writes are non-fatal
    }
}

function Write-NoxoraActionLog {
    <#
    .SYNOPSIS
        Writes a detailed action log entry for system changes.
    .PARAMETER ActionId
        The Action ID (from New-NoxoraActionId).
    .PARAMETER ActionName
        Human-readable name of the action.
    .PARAMETER Status
        Action status: Pending, Running, Applied, Verified, Skipped, Failed, RolledBack, RequiresRestart.
    .PARAMETER Category
        Category (e.g., CPU, Services, Startup).
    .PARAMETER Details
        Additional details about the action.
    .PARAMETER OriginalValue
        The value before the change.
    .PARAMETER NewValue
        The value after the change.
    .PARAMETER ErrorMessage
        Error message if the action failed.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ActionId,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ActionName,

        [Parameter(Mandatory)]
        [ValidateSet('Pending','Running','Applied','Verified','Skipped','Failed','RolledBack','RequiresRestart')]
        [string]$Status,

        [string]$Category     = '',
        [string]$Details      = '',
        [string]$OriginalValue = '',
        [string]$NewValue      = '',
        [string]$ErrorMessage  = ''
    )

    $level = switch ($Status) {
        'Applied'         { 'Pass'   }
        'Verified'        { 'Pass'   }
        'Skipped'         { 'Skip'   }
        'Failed'          { 'Fail'   }
        'RolledBack'      { 'Warn'   }
        'RequiresRestart' { 'Warn'   }
        default           { 'Action' }
    }

    $parts = [System.Collections.Generic.List[string]]::new()
    $parts.Add("[$Status] $ActionName")
    if ($Details)       { $parts.Add("Details: $Details") }
    if ($OriginalValue) { $parts.Add("Before: $OriginalValue") }
    if ($NewValue)      { $parts.Add("After: $NewValue") }
    if ($ErrorMessage)  { $parts.Add("Error: $ErrorMessage") }

    $message = $parts -join ' | '

    Write-NoxoraLog -Level $level -Message $message -Category $Category -ActionId $ActionId
}

function Get-NoxoraLogPath {
    <#
    .SYNOPSIS
        Returns the current main log file path.
    .OUTPUTS
        String — path to current log file, or empty string if not initialized.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    return if ($null -ne $script:CurrentLogFile) { $script:CurrentLogFile } else { '' }
}

function Get-NoxoraAuditLogPath {
    <#
    .SYNOPSIS
        Returns the current audit log file path.
    .OUTPUTS
        String — path to audit log file, or empty string if not initialized.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    return if ($null -ne $script:AuditLogFile) { $script:AuditLogFile } else { '' }
}

#endregion

#region - Private Functions

function Invoke-NoxoraLogRotation {
    <#
    .SYNOPSIS
        Archives the current log file if it exceeds the size limit,
        and removes old archives beyond the retention count.
    #>

    if ($null -eq $script:CurrentLogFile) { return }
    if (-not (Test-Path -LiteralPath $script:CurrentLogFile -PathType Leaf)) { return }

    $size = (Get-Item -LiteralPath $script:CurrentLogFile).Length / 1MB
    if ($size -lt $script:MaxLogSizeMB) { return }

    try {
        $archiveName = $script:CurrentLogFile -replace '\.log$', "-$(Get-Date -Format 'HHmmss').log.bak"
        Rename-Item -LiteralPath $script:CurrentLogFile -NewName $archiveName -ErrorAction Stop

        # Remove old archives if beyond retention
        $logDir    = [System.IO.Path]::GetDirectoryName($script:CurrentLogFile)
        $baseName  = [System.IO.Path]::GetFileNameWithoutExtension($script:CurrentLogFile)
        $archives  = Get-ChildItem -LiteralPath $logDir -Filter "$baseName*.log.bak" |
                     Sort-Object -Property LastWriteTime -Descending

        if ($archives.Count -gt $script:MaxLogFiles) {
            $archives | Select-Object -Skip $script:MaxLogFiles | Remove-Item -LiteralPath { $_.FullName } -Force -ErrorAction SilentlyContinue
        }
    }
    catch {
        # Rotation is non-fatal
    }
}

#endregion

Export-ModuleMember -Function @(
    'Initialize-NoxoraLogging',
    'Write-NoxoraLog',
    'Write-NoxoraAuditLog',
    'Write-NoxoraActionLog',
    'Get-NoxoraLogPath',
    'Get-NoxoraAuditLogPath'
)
