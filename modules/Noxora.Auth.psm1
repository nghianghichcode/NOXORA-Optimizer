#Requires -Version 5.1
<#
.SYNOPSIS
    NOXORA Optimizer — Authentication Module
.DESCRIPTION
    Implements OWNER-only authentication with PBKDF2-SHA256 password hashing,
    lockout policy, session management, and audit logging.

    Security properties:
      - Passwords hashed with PBKDF2-SHA256, 100,000 iterations, 32-byte salt
      - Credential files protected by Windows ACL (Administrators + SYSTEM only)
      - No plain-text passwords stored anywhere
      - No passwords or hashes written to logs
      - Maximum 5 login attempts with exponential backoff
      - Session timeout with re-authentication
      - Secure password input via Read-Host -AsSecureString

    Architecture:
      - data/auth/owner.cred.json  — hashed credentials (ACL-protected)
      - data/auth/lockout.json     — lockout state (ACL-protected)
      - data/auth/session.json     — active session (ACL-protected)
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region — Module State
$script:AuthDirectory         = $null
$script:CredentialFile        = $null
$script:LockoutFile           = $null
$script:SessionFile           = $null
$script:MaxLoginAttempts      = 5
$script:LockoutDurationBase   = 30
$script:LockoutMultiplier     = 2
$script:SessionTimeoutMinutes = 60
$script:SessionWarningMinutes = 5
$script:PBKDF2Iterations      = 100000
$script:SaltLength            = 32

# In-memory session state
$script:CurrentSession = $null
#endregion

#region — Initialization

function Initialize-NoxoraAuth {
    <#
    .SYNOPSIS
        Initializes the authentication module with paths and configuration.
    .PARAMETER AuthDirectory
        Path to the data/auth directory (ACL-protected).
    .PARAMETER Config
        Settings object from Import-NoxoraConfig.
    .OUTPUTS
        PSCustomObject with Success and Message.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$AuthDirectory,

        [Parameter(Mandatory)]
        [PSCustomObject]$Config
    )

    $result = [PSCustomObject]@{
        Success = $false
        Message = ''
    }

    try {
        if (-not (Test-Path -LiteralPath $AuthDirectory -PathType Container)) {
            $null = New-Item -ItemType Directory -Path $AuthDirectory -Force -ErrorAction Stop
        }

        $script:AuthDirectory         = $AuthDirectory
        $script:CredentialFile        = Join-Path -Path $AuthDirectory -ChildPath 'owner.cred.json'
        $script:LockoutFile           = Join-Path -Path $AuthDirectory -ChildPath 'lockout.json'
        $script:SessionFile           = Join-Path -Path $AuthDirectory -ChildPath 'session.json'
        $script:MaxLoginAttempts      = $Config.auth.maxLoginAttempts
        $script:LockoutDurationBase   = $Config.auth.lockoutDurationBase
        $script:LockoutMultiplier     = $Config.auth.lockoutMultiplier
        $script:SessionTimeoutMinutes = $Config.auth.sessionTimeoutMinutes
        $script:SessionWarningMinutes = $Config.auth.sessionWarningMinutes
        $script:PBKDF2Iterations      = $Config.auth.pbkdf2Iterations
        $script:SaltLength            = $Config.auth.saltLength

        $result.Success = $true
        $result.Message = 'Auth module initialized.'
    }
    catch {
        $result.Message = "Auth initialization failed: $($_.Exception.Message)"
    }

    return $result
}

#endregion

#region — Owner Account Management

function Test-NoxoraOwnerExists {
    <#
    .SYNOPSIS
        Returns $true if an OWNER account has been created.
    .OUTPUTS
        Boolean
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    if ($null -eq $script:CredentialFile) { return $false }
    return (Test-Path -LiteralPath $script:CredentialFile -PathType Leaf)
}

function New-NoxoraOwner {
    <#
    .SYNOPSIS
        Creates the OWNER account on first run.
    .DESCRIPTION
        Prompts for username and password (with confirmation), hashes the
        password with PBKDF2-SHA256, and saves to the ACL-protected
        credential file. Never stores plain-text password.
    .PARAMETER Username
        The OWNER username (3-32 alphanumeric characters).
    .PARAMETER Password
        SecureString password. If not provided, prompts interactively.
    .PARAMETER ConfirmPassword
        SecureString confirmation. If not provided, prompts interactively.
    .OUTPUTS
        PSCustomObject with Success and Message.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^[a-zA-Z0-9_\-]{3,32}$')]
        [string]$Username,

        [Parameter(Mandatory)]
        [System.Security.SecureString]$Password,

        [Parameter(Mandatory)]
        [System.Security.SecureString]$ConfirmPassword
    )

    $result = [PSCustomObject]@{
        Success = $false
        Message = ''
    }

    try {
        # Verify passwords match
        $plainPass    = ConvertFrom-NoxoraSecureString -SecureString $Password
        $plainConfirm = ConvertFrom-NoxoraSecureString -SecureString $ConfirmPassword

        if ($plainPass -ne $plainConfirm) {
            # Clear from memory immediately
            $plainPass    = $null
            $plainConfirm = $null
            $result.Message = 'Passwords do not match. Please try again.'
            return $result
        }

        # Validate password strength
        $strengthResult = Test-PasswordStrength -PlainPassword $plainPass
        if (-not $strengthResult.IsStrong) {
            $plainPass    = $null
            $plainConfirm = $null
            $result.Message = "Password too weak: $($strengthResult.Reason)"
            return $result
        }

        # Generate salt and hash
        $salt       = New-CryptographicSalt -Length $script:SaltLength
        $hashResult = Invoke-PBKDF2Hash -PlainPassword $plainPass -Salt $salt -Iterations $script:PBKDF2Iterations

        # Clear plain-text password from memory
        $plainPass    = $null
        $plainConfirm = $null
        [System.GC]::Collect()

        if (-not $hashResult.Success) {
            $result.Message = "Failed to hash password: $($hashResult.Message)"
            return $result
        }

        # Build credential object (no plain text, no raw hash visible in JSON)
        $credObject = [PSCustomObject]@{
            Version    = '1.0'
            Username   = $Username
            Salt       = $salt
            Hash       = $hashResult.HashBase64
            Algorithm  = 'PBKDF2-SHA256'
            Iterations = $script:PBKDF2Iterations
            Created    = (Get-Date -Format 'o')
            LastLogin  = $null
        }

        # Verify ShouldProcess before writing
        if ($PSCmdlet.ShouldProcess($script:CredentialFile, 'Create OWNER credential file')) {
            $credJson = $credObject | ConvertTo-Json -Depth 5
            $credJson | Out-File -LiteralPath $script:CredentialFile -Encoding UTF8 -Force

            # Apply ACL restriction
            Set-NoxoraFileAcl -FilePath $script:CredentialFile

            $result.Success = $true
            $result.Message = "OWNER account '$Username' created successfully."
        }
    }
    catch {
        $result.Message = "Failed to create OWNER account: $($_.Exception.Message)"
    }

    return $result
}

#endregion

#region — Login / Logout

function Invoke-NoxoraLogin {
    <#
    .SYNOPSIS
        Authenticates the OWNER and creates a session if successful.
    .DESCRIPTION
        Validates credentials against the PBKDF2 hash, enforces lockout
        policy, creates a session with timeout, and writes audit log.
        Writes to audit log for all outcomes — never logs password/hash.
    .PARAMETER Username
        The OWNER username to authenticate.
    .PARAMETER Password
        SecureString password input.
    .OUTPUTS
        PSCustomObject with Success, Message, Session, and FailureCount.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Username,

        [Parameter(Mandatory)]
        [System.Security.SecureString]$Password
    )

    $result = [PSCustomObject]@{
        Success      = $false
        Message      = ''
        Session      = $null
        FailureCount = 0
        IsLockedOut  = $false
        LockoutUntil = $null
    }

    try {
        # Check lockout state
        $lockout = Get-LockoutState
        if ($lockout.IsLockedOut) {
            $remaining = [math]::Ceiling(($lockout.LockedUntil - (Get-Date)).TotalSeconds)
            $result.IsLockedOut  = $true
            $result.LockoutUntil = $lockout.LockedUntil
            $result.FailureCount = $lockout.FailureCount
            $result.Message      = "Account locked. Wait $remaining seconds before trying again."
            Write-NoxoraAuditLog -EventType 'LoginFailed' -Username $Username -Details "Attempted login during lockout"
            return $result
        }

        # Load credentials
        if (-not (Test-NoxoraOwnerExists)) {
            $result.Message = 'No OWNER account found. First-run setup required.'
            return $result
        }

        $cred = Get-Content -LiteralPath $script:CredentialFile -Raw -Encoding UTF8 |
                ConvertFrom-Json -ErrorAction Stop

        # Verify username (case-insensitive)
        if ($cred.Username -ne $Username) {
            $result = Update-FailureCount -CurrentResult $result -Username $Username
            return $result
        }

        # Hash the provided password with stored salt and compare
        $plainPass  = ConvertFrom-NoxoraSecureString -SecureString $Password
        $hashResult = Invoke-PBKDF2Hash -PlainPassword $plainPass -Salt $cred.Salt -Iterations $cred.Iterations

        # Clear plain-text immediately
        $plainPass = $null
        [System.GC]::Collect()

        if (-not $hashResult.Success) {
            $result.Message = "Hash verification failed: $($hashResult.Message)"
            return $result
        }

        # Constant-time comparison to prevent timing attacks
        $isValid = Compare-ConstantTime -A $hashResult.HashBase64 -B $cred.Hash

        if (-not $isValid) {
            $result = Update-FailureCount -CurrentResult $result -Username $Username
            return $result
        }

        # Authentication successful — create session
        $session = New-NoxoraSession -Username $Username

        # Reset lockout state
        Clear-LockoutState

        # Update last login in credential file
        $cred.LastLogin = Get-Date -Format 'o'
        ($cred | ConvertTo-Json -Depth 5) | Out-File -LiteralPath $script:CredentialFile -Encoding UTF8 -Force

        Write-NoxoraAuditLog -EventType 'LoginSuccess' -Username $Username

        $result.Success = $true
        $result.Message = "Welcome, $Username. Session started."
        $result.Session = $session
    }
    catch {
        $result.Message = "Login error: $($_.Exception.Message)"
    }

    return $result
}

function Invoke-NoxoraLogout {
    <#
    .SYNOPSIS
        Logs out the current OWNER session.
    .OUTPUTS
        PSCustomObject with Success and Message.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $result = [PSCustomObject]@{
        Success = $false
        Message = ''
    }

    try {
        if ($null -eq $script:CurrentSession) {
            $result.Message = 'No active session to log out from.'
            return $result
        }

        $username = $script:CurrentSession.Username
        Write-NoxoraAuditLog -EventType 'Logout' -Username $username

        # Clear session
        $script:CurrentSession = $null

        if (Test-Path -LiteralPath $script:SessionFile -PathType Leaf) {
            Remove-Item -LiteralPath $script:SessionFile -Force -ErrorAction SilentlyContinue
        }

        $result.Success = $true
        $result.Message = 'Logged out successfully.'
    }
    catch {
        $result.Message = "Logout error: $($_.Exception.Message)"
    }

    return $result
}

#endregion

#region — Session Management

function New-NoxoraSession {
    <#
    .SYNOPSIS
        Creates and persists a new authenticated session.
    .PARAMETER Username
        Authenticated OWNER username.
    .OUTPUTS
        PSCustomObject representing the session.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Username
    )

    $now     = Get-Date
    $session = [PSCustomObject]@{
        SessionId     = "NS-$(Get-Date -Format 'yyyyMMdd-HHmmss')-$([Guid]::NewGuid().ToString('N').Substring(0,6).ToUpper())"
        Username      = $Username
        Computer      = $env:COMPUTERNAME
        LoginTime     = $now.ToString('o')
        LastActivity  = $now.ToString('o')
        ExpiresAt     = $now.AddMinutes($script:SessionTimeoutMinutes).ToString('o')
        TimeoutMinutes = $script:SessionTimeoutMinutes
        IsActive      = $true
    }

    $script:CurrentSession = $session

    # Persist session (for crash recovery info only)
    try {
        ($session | ConvertTo-Json -Depth 5) |
            Out-File -LiteralPath $script:SessionFile -Encoding UTF8 -Force
        Set-NoxoraFileAcl -FilePath $script:SessionFile
    }
    catch {
        # Session file write is non-fatal
    }

    return $session
}

function Get-NoxoraSession {
    <#
    .SYNOPSIS
        Returns the current session object, or $null if no session is active.
    .OUTPUTS
        PSCustomObject session, or $null.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    return $script:CurrentSession
}

function Test-NoxoraSessionValid {
    <#
    .SYNOPSIS
        Validates the current session has not expired.
    .OUTPUTS
        PSCustomObject with IsValid, IsExpired, MinutesRemaining, NeedsWarning.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $result = [PSCustomObject]@{
        IsValid          = $false
        IsExpired        = $true
        MinutesRemaining = 0
        NeedsWarning     = $false
    }

    if ($null -eq $script:CurrentSession) {
        return $result
    }

    $now       = Get-Date
    $expiresAt = [datetime]::Parse($script:CurrentSession.ExpiresAt)
    $remaining = ($expiresAt - $now).TotalMinutes

    $result.MinutesRemaining = [math]::Max(0, [math]::Round($remaining, 1))
    $result.IsExpired        = ($remaining -le 0)
    $result.IsValid          = (-not $result.IsExpired)
    $result.NeedsWarning     = ($remaining -gt 0 -and $remaining -le $script:SessionWarningMinutes)

    if ($result.IsExpired -and $script:CurrentSession.IsActive) {
        Write-NoxoraAuditLog -EventType 'SessionTimeout' -Username $script:CurrentSession.Username
        $script:CurrentSession = $null
    }

    return $result
}

function Update-NoxoraSessionActivity {
    <#
    .SYNOPSIS
        Updates the LastActivity timestamp and extends session expiry.
    #>
    [CmdletBinding()]
    param()

    if ($null -eq $script:CurrentSession) { return }

    $now = Get-Date
    $script:CurrentSession.LastActivity = $now.ToString('o')
    $script:CurrentSession.ExpiresAt    = $now.AddMinutes($script:SessionTimeoutMinutes).ToString('o')
}

#endregion

#region — Private Helper Functions

function ConvertFrom-NoxoraSecureString {
    <#
    .SYNOPSIS
        Converts a SecureString to a plain string in memory for hashing only.
    .NOTES
        The caller is responsible for zeroing the returned string immediately after use.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [System.Security.SecureString]$SecureString
    )

    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

function New-CryptographicSalt {
    <#
    .SYNOPSIS
        Generates a cryptographically random salt of the specified byte length.
    .PARAMETER Length
        Length in bytes (default: 32).
    .OUTPUTS
        Base64-encoded salt string.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [ValidateRange(16, 64)]
        [int]$Length = 32
    )

    $bytes = [byte[]]::new($Length)
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
    return [Convert]::ToBase64String($bytes)
}

function Invoke-PBKDF2Hash {
    <#
    .SYNOPSIS
        Hashes a password using PBKDF2 with SHA-256.
    .PARAMETER PlainPassword
        The plain-text password to hash. Should be zeroed after calling.
    .PARAMETER Salt
        Base64-encoded salt string.
    .PARAMETER Iterations
        Number of PBKDF2 iterations (default: 100000).
    .OUTPUTS
        PSCustomObject with Success, HashBase64, and Message.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$PlainPassword,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Salt,

        [ValidateRange(10000, 1000000)]
        [int]$Iterations = 100000
    )

    $result = [PSCustomObject]@{
        Success    = $false
        HashBase64 = ''
        Message    = ''
    }

    try {
        $saltBytes  = [Convert]::FromBase64String($Salt)
        $passBytes  = [System.Text.Encoding]::UTF8.GetBytes($PlainPassword)

        $pbkdf2 = [System.Security.Cryptography.Rfc2898DeriveBytes]::new(
            $passBytes,
            $saltBytes,
            $Iterations,
            [System.Security.Cryptography.HashAlgorithmName]::SHA256
        )

        try {
            $hashBytes = $pbkdf2.GetBytes(32)
            $result.HashBase64 = [Convert]::ToBase64String($hashBytes)
            $result.Success    = $true
        }
        finally {
            $pbkdf2.Dispose()
            # Zero password bytes
            [Array]::Clear($passBytes, 0, $passBytes.Length)
        }
    }
    catch {
        $result.Message = "PBKDF2 hashing failed: $($_.Exception.Message)"
    }

    return $result
}

function Compare-ConstantTime {
    <#
    .SYNOPSIS
        Performs a constant-time string comparison to prevent timing attacks.
    .PARAMETER A
        First string.
    .PARAMETER B
        Second string.
    .OUTPUTS
        Boolean — $true if strings are equal.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$A,

        [Parameter(Mandatory)]
        [string]$B
    )

    if ($A.Length -ne $B.Length) { return $false }

    $result = 0
    for ($i = 0; $i -lt $A.Length; $i++) {
        $result = $result -bor ([int][char]$A[$i] -bxor [int][char]$B[$i])
    }

    return ($result -eq 0)
}

function Test-PasswordStrength {
    <#
    .SYNOPSIS
        Validates password meets minimum security requirements.
    .PARAMETER PlainPassword
        Plain-text password to evaluate.
    .OUTPUTS
        PSCustomObject with IsStrong and Reason.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$PlainPassword
    )

    if ($PlainPassword.Length -lt 8) {
        return [PSCustomObject]@{ IsStrong = $false; Reason = 'Password must be at least 8 characters.' }
    }
    if ($PlainPassword.Length -gt 128) {
        return [PSCustomObject]@{ IsStrong = $false; Reason = 'Password must not exceed 128 characters.' }
    }
    if ($PlainPassword -notmatch '[A-Z]') {
        return [PSCustomObject]@{ IsStrong = $false; Reason = 'Password must contain at least one uppercase letter.' }
    }
    if ($PlainPassword -notmatch '[a-z]') {
        return [PSCustomObject]@{ IsStrong = $false; Reason = 'Password must contain at least one lowercase letter.' }
    }
    if ($PlainPassword -notmatch '[0-9]') {
        return [PSCustomObject]@{ IsStrong = $false; Reason = 'Password must contain at least one digit.' }
    }

    return [PSCustomObject]@{ IsStrong = $true; Reason = '' }
}

function Get-LockoutState {
    <#
    .SYNOPSIS
        Reads and evaluates the current lockout state.
    .OUTPUTS
        PSCustomObject with IsLockedOut, FailureCount, and LockedUntil.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $state = [PSCustomObject]@{
        IsLockedOut  = $false
        FailureCount = 0
        LockedUntil  = $null
    }

    if (-not (Test-Path -LiteralPath $script:LockoutFile -PathType Leaf)) {
        return $state
    }

    try {
        $data = Get-Content -LiteralPath $script:LockoutFile -Raw -Encoding UTF8 |
                ConvertFrom-Json -ErrorAction Stop

        $state.FailureCount = [int]$data.FailureCount

        if ($null -ne $data.LockedUntil) {
            $lockedUntil       = [datetime]::Parse($data.LockedUntil)
            $state.LockedUntil = $lockedUntil
            $state.IsLockedOut = ((Get-Date) -lt $lockedUntil)
        }
    }
    catch {
        # Corrupt lockout file — treat as no lockout
    }

    return $state
}

function Update-FailureCount {
    <#
    .SYNOPSIS
        Increments the failure count and activates lockout if threshold exceeded.
    .PARAMETER CurrentResult
        The login result object to update.
    .PARAMETER Username
        Username for audit logging.
    .OUTPUTS
        Updated PSCustomObject result.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$CurrentResult,

        [Parameter(Mandatory)]
        [string]$Username
    )

    $lockout       = Get-LockoutState
    $newCount      = $lockout.FailureCount + 1
    $CurrentResult.FailureCount = $newCount

    Write-NoxoraAuditLog -EventType 'LoginFailed' -Username $Username -Details "Attempt $newCount of $($script:MaxLoginAttempts)"

    if ($newCount -ge $script:MaxLoginAttempts) {
        # Exponential backoff: base * multiplier^(failures - maxAttempts)
        $overage  = $newCount - $script:MaxLoginAttempts
        $duration = $script:LockoutDurationBase * [math]::Pow($script:LockoutMultiplier, $overage)
        $duration = [math]::Min($duration, 3600)  # Cap at 1 hour
        $until    = (Get-Date).AddSeconds($duration)

        Save-LockoutState -FailureCount $newCount -LockedUntil $until

        Write-NoxoraAuditLog -EventType 'LockoutActivated' -Username $Username -Details "Duration: $duration seconds"

        $CurrentResult.IsLockedOut  = $true
        $CurrentResult.LockoutUntil = $until
        $CurrentResult.Message      = "Too many failed attempts. Account locked for $([math]::Round($duration)) seconds."
    }
    else {
        Save-LockoutState -FailureCount $newCount -LockedUntil $null

        $remaining = $script:MaxLoginAttempts - $newCount
        $CurrentResult.Message = "Invalid credentials. $remaining attempt(s) remaining."
    }

    return $CurrentResult
}

function Save-LockoutState {
    <#
    .SYNOPSIS
        Persists lockout state to disk.
    #>
    [CmdletBinding()]
    param(
        [int]$FailureCount = 0,
        [nullable[datetime]]$LockedUntil = $null
    )

    try {
        $data = [PSCustomObject]@{
            FailureCount = $FailureCount
            LockedUntil  = if ($null -ne $LockedUntil) { $LockedUntil.ToString('o') } else { $null }
            UpdatedAt    = (Get-Date -Format 'o')
        }

        ($data | ConvertTo-Json -Depth 3) |
            Out-File -LiteralPath $script:LockoutFile -Encoding UTF8 -Force

        Set-NoxoraFileAcl -FilePath $script:LockoutFile
    }
    catch {
        # Lockout persistence is best-effort
    }
}

function Clear-LockoutState {
    <#
    .SYNOPSIS
        Resets lockout state after successful login.
    #>
    [CmdletBinding()]
    param()

    try {
        if (Test-Path -LiteralPath $script:LockoutFile -PathType Leaf) {
            Remove-Item -LiteralPath $script:LockoutFile -Force -ErrorAction SilentlyContinue
        }
    }
    catch { }
}

function Set-NoxoraFileAcl {
    <#
    .SYNOPSIS
        Restricts a file to Administrators and SYSTEM only.
    .PARAMETER FilePath
        Path to the file to protect.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$FilePath
    )

    try {
        $acl = Get-Acl -LiteralPath $FilePath -ErrorAction Stop
        $acl.SetAccessRuleProtection($true, $false)

        foreach ($rule in @($acl.Access)) {
            $acl.RemoveAccessRule($rule) | Out-Null
        }

        $adminSid  = [Security.Principal.SecurityIdentifier]::new(
            [Security.Principal.WellKnownSidType]::BuiltinAdministratorsSid, $null)
        $adminRule = [System.Security.AccessControl.FileSystemAccessRule]::new(
            $adminSid,
            [System.Security.AccessControl.FileSystemRights]::FullControl,
            [System.Security.AccessControl.InheritanceFlags]::None,
            [System.Security.AccessControl.PropagationFlags]::None,
            [System.Security.AccessControl.AccessControlType]::Allow
        )
        $acl.AddAccessRule($adminRule)

        $systemSid  = [Security.Principal.SecurityIdentifier]::new(
            [Security.Principal.WellKnownSidType]::LocalSystemSid, $null)
        $systemRule = [System.Security.AccessControl.FileSystemAccessRule]::new(
            $systemSid,
            [System.Security.AccessControl.FileSystemRights]::FullControl,
            [System.Security.AccessControl.InheritanceFlags]::None,
            [System.Security.AccessControl.PropagationFlags]::None,
            [System.Security.AccessControl.AccessControlType]::Allow
        )
        $acl.AddAccessRule($systemRule)

        Set-Acl -LiteralPath $FilePath -AclObject $acl -ErrorAction Stop
    }
    catch {
        Write-Verbose "ACL restriction skipped for '$FilePath': $($_.Exception.Message)"
    }
}

#endregion

Export-ModuleMember -Function @(
    'Initialize-NoxoraAuth',
    'Test-NoxoraOwnerExists',
    'New-NoxoraOwner',
    'Invoke-NoxoraLogin',
    'Invoke-NoxoraLogout',
    'New-NoxoraSession',
    'Get-NoxoraSession',
    'Test-NoxoraSessionValid',
    'Update-NoxoraSessionActivity'
)
