#Requires -Version 5.1
<#
.SYNOPSIS
    NOXORA Optimizer — Core Module
.DESCRIPTION
    Provides constants, environment validation, module loader,
    configuration management, and version information.
    This module must be loaded first before any other NOXORA module.
.NOTES
    Author  : NOXORA Project
    Version : 1.0.0
    License : Proprietary
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region — Module Metadata
$script:NoxoraCoreVersion = [PSCustomObject]@{
    Major      = 1
    Minor      = 0
    Patch      = 0
    Build      = '20260719'
    String     = '1.0.0'
    FullString = 'NOXORA OPTIMIZER v1.0.0 (Build 20260719)'
}

$script:NoxoraRootPath   = $null
$script:NoxoraConfig     = $null
$script:NoxoraConfigPath = $null
#endregion

#region — Constants
# Minimum supported Windows build (Windows 10 1903)
$script:MinWindowsBuild = 18362

# PowerShell version detection
$script:IsPSCore = ($PSVersionTable.PSEdition -eq 'Core')
$script:PSMajor  = $PSVersionTable.PSVersion.Major
#endregion

#region — Public Functions

function Initialize-NoxoraCore {
    <#
    .SYNOPSIS
        Initializes the NOXORA core engine.
    .DESCRIPTION
        Validates environment, sets root path, loads configuration,
        initializes all required directories. Must be called first.
    .PARAMETER RootPath
        Absolute path to the NOXORA-Optimizer directory.
    .OUTPUTS
        PSCustomObject with Success, Message, and Environment properties.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RootPath
    )

    $result = [PSCustomObject]@{
        Success     = $false
        Message     = ''
        Environment = $null
        Errors      = [System.Collections.Generic.List[string]]::new()
    }

    try {
        # Validate root path exists
        if (-not (Test-Path -LiteralPath $RootPath -PathType Container)) {
            $result.Errors.Add("Root path not found: $RootPath")
            $result.Message = 'Root path validation failed.'
            return $result
        }

        $script:NoxoraRootPath = $RootPath

        # Validate environment
        $envCheck = Test-NoxoraEnvironment
        if (-not $envCheck.Success) {
            foreach ($err in $envCheck.Errors) {
                $result.Errors.Add($err)
            }
            $result.Message = 'Environment validation failed.'
            return $result
        }

        # Load configuration
        $configResult = Import-NoxoraConfig -RootPath $RootPath
        if (-not $configResult.Success) {
            $result.Errors.Add($configResult.Message)
            $result.Message = 'Configuration load failed.'
            return $result
        }

        # Ensure required directories exist
        $dirResult = Initialize-NoxoraDirectories -RootPath $RootPath
        if (-not $dirResult.Success) {
            foreach ($err in $dirResult.Errors) {
                $result.Errors.Add($err)
            }
            $result.Message = 'Directory initialization failed.'
            return $result
        }

        $result.Success     = $true
        $result.Message     = 'NOXORA core initialized successfully.'
        $result.Environment = $envCheck.Environment
    }
    catch {
        $result.Errors.Add("Unhandled exception in Initialize-NoxoraCore: $($_.Exception.Message)")
        $result.Message = 'Critical initialization error.'
    }

    return $result
}

function Test-NoxoraEnvironment {
    <#
    .SYNOPSIS
        Validates the runtime environment for NOXORA.
    .DESCRIPTION
        Checks OS version, PowerShell version, Administrator privilege,
        architecture, and available CIM/WMI providers.
    .OUTPUTS
        PSCustomObject with Success, Environment, and Errors.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $result = [PSCustomObject]@{
        Success     = $false
        Environment = $null
        Errors      = [System.Collections.Generic.List[string]]::new()
        Warnings    = [System.Collections.Generic.List[string]]::new()
    }

    try {
        # Check OS
        $osInfo  = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $osBuild = [int]$osInfo.BuildNumber

        if ($osBuild -lt $script:MinWindowsBuild) {
            $result.Errors.Add(
                "Windows build $osBuild is below minimum required build $($script:MinWindowsBuild). " +
                "NOXORA requires Windows 10 1903 or later."
            )
        }

        # Check Administrator privilege
        $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal        = [Security.Principal.WindowsPrincipal]$currentIdentity
        $isAdmin          = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

        if (-not $isAdmin) {
            $result.Errors.Add('NOXORA must be run as Administrator.')
        }

        # Check PowerShell version
        if ($script:PSMajor -lt 5) {
            $result.Errors.Add(
                "PowerShell $($PSVersionTable.PSVersion) is not supported. " +
                "NOXORA requires PowerShell 5.1 or PowerShell 7+."
            )
        }

        # Check architecture
        $arch = if ([Environment]::Is64BitOperatingSystem) { 'x64' } else { 'x86' }
        if ($arch -eq 'x86') {
            $result.Warnings.Add('32-bit OS detected. Some hardware readings may be limited.')
        }

        # Check CIM availability
        $cimAvailable = $true
        try {
            $null = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        }
        catch {
            $cimAvailable = $false
            $result.Warnings.Add("CIM/WMI may be limited: $($_.Exception.Message)")
        }

        # Build environment object
        $result.Environment = [PSCustomObject]@{
            ComputerName      = $env:COMPUTERNAME
            OSCaption         = $osInfo.Caption
            OSVersion         = $osInfo.Version
            OSBuild           = $osBuild
            OSArchitecture    = $arch
            PSVersion         = $PSVersionTable.PSVersion.ToString()
            PSEdition         = $PSVersionTable.PSEdition
            IsPSCore          = $script:IsPSCore
            IsAdministrator   = $isAdmin
            CIMAvailable      = $cimAvailable
            SystemDrive       = $env:SystemDrive
            Username          = $env:USERNAME
            UserDomain        = $env:USERDOMAIN
            CheckTimestamp    = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        }

        # Only succeed if no errors
        $result.Success = ($result.Errors.Count -eq 0)
    }
    catch {
        $result.Errors.Add("Environment check failed: $($_.Exception.Message)")
    }

    return $result
}

function Import-NoxoraConfig {
    <#
    .SYNOPSIS
        Loads the NOXORA settings.json configuration file.
    .PARAMETER RootPath
        Absolute path to the NOXORA-Optimizer directory.
    .OUTPUTS
        PSCustomObject with Success, Config, and Message.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RootPath
    )

    $result = [PSCustomObject]@{
        Success = $false
        Config  = $null
        Message = ''
    }

    try {
        $configPath = Join-Path -Path $RootPath -ChildPath 'config\settings.json'

        if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
            $result.Message = "Configuration file not found: $configPath"
            return $result
        }

        $rawJson = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 -ErrorAction Stop
        $config  = $rawJson | ConvertFrom-Json -ErrorAction Stop

        $script:NoxoraConfig     = $config
        $script:NoxoraConfigPath = $configPath

        $result.Success = $true
        $result.Config  = $config
        $result.Message = 'Configuration loaded successfully.'
    }
    catch {
        $result.Message = "Failed to load configuration: $($_.Exception.Message)"
    }

    return $result
}

function Get-NoxoraConfig {
    <#
    .SYNOPSIS
        Returns the currently loaded NOXORA configuration object.
    .OUTPUTS
        PSCustomObject representing settings.json, or $null if not loaded.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    return $script:NoxoraConfig
}

function Get-NoxoraRootPath {
    <#
    .SYNOPSIS
        Returns the NOXORA root directory path.
    .OUTPUTS
        String path, or $null if not initialized.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    return $script:NoxoraRootPath
}

function Get-NoxoraVersion {
    <#
    .SYNOPSIS
        Returns the NOXORA version information object.
    .OUTPUTS
        PSCustomObject with version fields.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    return $script:NoxoraCoreVersion
}

function Initialize-NoxoraDirectories {
    <#
    .SYNOPSIS
        Ensures all required NOXORA data directories exist.
    .PARAMETER RootPath
        Absolute path to the NOXORA-Optimizer directory.
    .OUTPUTS
        PSCustomObject with Success and Errors.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RootPath
    )

    $result = [PSCustomObject]@{
        Success = $true
        Errors  = [System.Collections.Generic.List[string]]::new()
    }

    $requiredDirs = @(
        'data\auth',
        'data\logs',
        'data\logs\audit',
        'data\sessions',
        'data\sessions\game-profiles',
        'data\backups',
        'data\baselines',
        'data\reports',
        'data\quarantine'
    )

    foreach ($dir in $requiredDirs) {
        $fullPath = Join-Path -Path $RootPath -ChildPath $dir
        try {
            if (-not (Test-Path -LiteralPath $fullPath -PathType Container)) {
                $null = New-Item -ItemType Directory -Path $fullPath -Force -ErrorAction Stop
            }
        }
        catch {
            $result.Errors.Add("Failed to create directory '$fullPath': $($_.Exception.Message)")
            $result.Success = $false
        }
    }

    # Secure the auth directory
    $authDir = Join-Path -Path $RootPath -ChildPath 'data\auth'
    if (Test-Path -LiteralPath $authDir -PathType Container) {
        Set-NoxoraAuthDirectoryAcl -DirectoryPath $authDir
    }

    return $result
}

function Set-NoxoraAuthDirectoryAcl {
    <#
    .SYNOPSIS
        Restricts the auth directory to Administrators and SYSTEM only.
    .PARAMETER DirectoryPath
        Path to the auth directory.
    .NOTES
        Silently skips if ACL operations are not available.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$DirectoryPath
    )

    try {
        $acl = Get-Acl -LiteralPath $DirectoryPath -ErrorAction Stop

        # Disable inheritance and remove existing rules
        $acl.SetAccessRuleProtection($true, $false)

        # Remove all existing access rules
        foreach ($rule in @($acl.Access)) {
            $acl.RemoveAccessRule($rule) | Out-Null
        }

        # Add Administrators — Full Control
        $adminSid   = [Security.Principal.SecurityIdentifier]::new(
            [Security.Principal.WellKnownSidType]::BuiltinAdministratorsSid, $null)
        $adminRule  = [System.Security.AccessControl.FileSystemAccessRule]::new(
            $adminSid,
            [System.Security.AccessControl.FileSystemRights]::FullControl,
            [System.Security.AccessControl.InheritanceFlags]'ContainerInherit,ObjectInherit',
            [System.Security.AccessControl.PropagationFlags]::None,
            [System.Security.AccessControl.AccessControlType]::Allow
        )
        $acl.AddAccessRule($adminRule)

        # Add SYSTEM — Full Control
        $systemSid  = [Security.Principal.SecurityIdentifier]::new(
            [Security.Principal.WellKnownSidType]::LocalSystemSid, $null)
        $systemRule = [System.Security.AccessControl.FileSystemAccessRule]::new(
            $systemSid,
            [System.Security.AccessControl.FileSystemRights]::FullControl,
            [System.Security.AccessControl.InheritanceFlags]'ContainerInherit,ObjectInherit',
            [System.Security.AccessControl.PropagationFlags]::None,
            [System.Security.AccessControl.AccessControlType]::Allow
        )
        $acl.AddAccessRule($systemRule)

        Set-Acl -LiteralPath $DirectoryPath -AclObject $acl -ErrorAction Stop
    }
    catch {
        # ACL restriction is best-effort; log but do not fail initialization
        Write-Verbose "ACL setup for auth directory skipped: $($_.Exception.Message)"
    }
}

function Import-NoxoraConfigFile {
    <#
    .SYNOPSIS
        Loads any JSON config file from the config directory.
    .PARAMETER FileName
        The filename (e.g., 'protected-processes.json').
    .OUTPUTS
        PSCustomObject parsed from JSON, or $null on failure.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$FileName
    )

    try {
        if ($null -eq $script:NoxoraRootPath) {
            throw 'NOXORA core not initialized. Call Initialize-NoxoraCore first.'
        }

        $filePath = Join-Path -Path $script:NoxoraRootPath -ChildPath "config\$FileName"

        if (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) {
            Write-Warning "Config file not found: $filePath"
            return $null
        }

        $rawJson = Get-Content -LiteralPath $filePath -Raw -Encoding UTF8 -ErrorAction Stop
        return ($rawJson | ConvertFrom-Json -ErrorAction Stop)
    }
    catch {
        Write-Warning "Failed to load config file '$FileName': $($_.Exception.Message)"
        return $null
    }
}

function Test-Administrator {
    <#
    .SYNOPSIS
        Returns $true if the current process is running as Administrator.
    .OUTPUTS
        Boolean
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $id        = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]$id
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-NoxoraDataPath {
    <#
    .SYNOPSIS
        Returns the full path to a subdirectory under data/.
    .PARAMETER SubPath
        Relative path under data/ (e.g., 'logs', 'auth', 'backups').
    .OUTPUTS
        String — full path.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$SubPath
    )

    if ($null -eq $script:NoxoraRootPath) {
        throw 'NOXORA core not initialized.'
    }
    return Join-Path -Path $script:NoxoraRootPath -ChildPath "data\$SubPath"
}

function New-NoxoraActionId {
    <#
    .SYNOPSIS
        Generates a unique Action ID in the format NX-YYYYMMDD-NNNN.
    .OUTPUTS
        String — unique action ID.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $date   = Get-Date -Format 'yyyyMMdd'
    $random = Get-Random -Minimum 1000 -Maximum 9999
    return "NX-$date-$random"
}

function New-NoxoraSessionId {
    <#
    .SYNOPSIS
        Generates a unique Session ID in the format NSS-YYYYMMDD-HHmmss-GUID.
    .OUTPUTS
        String — unique session ID.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $guid      = [Guid]::NewGuid().ToString('N').Substring(0, 8).ToUpper()
    return "NSS-$timestamp-$guid"
}

#endregion

Export-ModuleMember -Function @(
    'Initialize-NoxoraCore',
    'Test-NoxoraEnvironment',
    'Import-NoxoraConfig',
    'Get-NoxoraConfig',
    'Get-NoxoraRootPath',
    'Get-NoxoraVersion',
    'Initialize-NoxoraDirectories',
    'Import-NoxoraConfigFile',
    'Test-Administrator',
    'Get-NoxoraDataPath',
    'New-NoxoraActionId',
    'New-NoxoraSessionId'
)
