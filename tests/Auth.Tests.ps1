#Requires -Version 5.1
<#
.SYNOPSIS
    NOXORA — Authentication Module Tests (Pester)
.DESCRIPTION
    Tests for Noxora.Auth.psm1 covering:
      - PBKDF2 hashing correctness
      - Password strength validation
      - Constant-time comparison
      - Owner creation and credential persistence
      - Login success and failure flows
      - Lockout policy enforcement
      - Session creation and timeout
.NOTES
    Run with: Invoke-Pester .\tests\Auth.Tests.ps1 -Output Detailed
    Requires: Pester 5.0+
#>

BeforeAll {
    # Import the modules under test
    $script:ModulesPath = Join-Path -Path $PSScriptRoot -ChildPath '..\modules'
    $script:DataPath    = Join-Path -Path $PSScriptRoot -ChildPath '..\data'
    $script:TestAuthDir = Join-Path -Path $PSScriptRoot -ChildPath 'test-auth-temp'

    Import-Module (Join-Path $script:ModulesPath 'Noxora.Core.psm1')    -Force
    Import-Module (Join-Path $script:ModulesPath 'Noxora.Logging.psm1') -Force
    Import-Module (Join-Path $script:ModulesPath 'Noxora.Auth.psm1')    -Force

    # Create test auth directory
    if (-not (Test-Path $script:TestAuthDir)) {
        New-Item -ItemType Directory -Path $script:TestAuthDir -Force | Out-Null
    }

    # Load a minimal config for auth initialization
    $script:TestConfig = [PSCustomObject]@{
        auth = [PSCustomObject]@{
            maxLoginAttempts      = 5
            lockoutDurationBase   = 30
            lockoutMultiplier     = 2
            sessionTimeoutMinutes = 60
            sessionWarningMinutes = 5
            pbkdf2Iterations      = 1000  # Reduced for test speed
            saltLength            = 32
        }
    }

    Initialize-NoxoraAuth -AuthDirectory $script:TestAuthDir -Config $script:TestConfig
}

AfterAll {
    # Clean up test directory
    if (Test-Path $script:TestAuthDir) {
        Remove-Item -LiteralPath $script:TestAuthDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ─── PBKDF2 Hashing ────────────────────────────────────────────────────────────

Describe 'PBKDF2 Hashing' {

    It 'Generates a salt of expected base64 length' {
        # 32 bytes = 44 chars in base64
        $salt = & (Get-Module Noxora.Auth) { New-CryptographicSalt -Length 32 }
        [Convert]::FromBase64String($salt).Length | Should -Be 32
    }

    It 'Produces a deterministic hash for the same password and salt' {
        $salt  = & (Get-Module Noxora.Auth) { New-CryptographicSalt -Length 32 }
        $hash1 = & (Get-Module Noxora.Auth) { Invoke-PBKDF2Hash -PlainPassword 'TestPass1!' -Salt $using:salt -Iterations 1000 }
        $hash2 = & (Get-Module Noxora.Auth) { Invoke-PBKDF2Hash -PlainPassword 'TestPass1!' -Salt $using:salt -Iterations 1000 }

        $hash1.Success    | Should -BeTrue
        $hash2.Success    | Should -BeTrue
        $hash1.HashBase64 | Should -Be $hash2.HashBase64
    }

    It 'Produces different hashes for different passwords with same salt' {
        $salt  = & (Get-Module Noxora.Auth) { New-CryptographicSalt -Length 32 }
        $hash1 = & (Get-Module Noxora.Auth) { Invoke-PBKDF2Hash -PlainPassword 'Password1!'  -Salt $using:salt -Iterations 1000 }
        $hash2 = & (Get-Module Noxora.Auth) { Invoke-PBKDF2Hash -PlainPassword 'Different1!' -Salt $using:salt -Iterations 1000 }

        $hash1.HashBase64 | Should -Not -Be $hash2.HashBase64
    }

    It 'Produces different hashes for same password with different salts' {
        $salt1  = & (Get-Module Noxora.Auth) { New-CryptographicSalt -Length 32 }
        $salt2  = & (Get-Module Noxora.Auth) { New-CryptographicSalt -Length 32 }
        $hash1  = & (Get-Module Noxora.Auth) { Invoke-PBKDF2Hash -PlainPassword 'SamePass1!' -Salt $using:salt1 -Iterations 1000 }
        $hash2  = & (Get-Module Noxora.Auth) { Invoke-PBKDF2Hash -PlainPassword 'SamePass1!' -Salt $using:salt2 -Iterations 1000 }

        $hash1.HashBase64 | Should -Not -Be $hash2.HashBase64
    }
}

# ─── Constant-Time Comparison ───────────────────────────────────────────────────

Describe 'Constant-Time Comparison' {

    It 'Returns true for identical strings' {
        $result = & (Get-Module Noxora.Auth) { Compare-ConstantTime -A 'abc123' -B 'abc123' }
        $result | Should -BeTrue
    }

    It 'Returns false for different strings of same length' {
        $result = & (Get-Module Noxora.Auth) { Compare-ConstantTime -A 'abc123' -B 'abc124' }
        $result | Should -BeFalse
    }

    It 'Returns false for strings of different length' {
        $result = & (Get-Module Noxora.Auth) { Compare-ConstantTime -A 'abc' -B 'abcd' }
        $result | Should -BeFalse
    }

    It 'Returns false for empty vs non-empty string' {
        $result = & (Get-Module Noxora.Auth) { Compare-ConstantTime -A '' -B 'abc' }
        $result | Should -BeFalse
    }

    It 'Returns true for two empty strings' {
        $result = & (Get-Module Noxora.Auth) { Compare-ConstantTime -A '' -B '' }
        $result | Should -BeTrue
    }
}

# ─── Password Strength ─────────────────────────────────────────────────────────

Describe 'Password Strength Validation' {

    It 'Rejects passwords shorter than 8 characters' {
        $result = & (Get-Module Noxora.Auth) { Test-PasswordStrength -PlainPassword 'Ab1' }
        $result.IsStrong | Should -BeFalse
        $result.Reason   | Should -Match '8 characters'
    }

    It 'Rejects passwords without uppercase' {
        $result = & (Get-Module Noxora.Auth) { Test-PasswordStrength -PlainPassword 'password123' }
        $result.IsStrong | Should -BeFalse
        $result.Reason   | Should -Match 'uppercase'
    }

    It 'Rejects passwords without lowercase' {
        $result = & (Get-Module Noxora.Auth) { Test-PasswordStrength -PlainPassword 'PASSWORD123' }
        $result.IsStrong | Should -BeFalse
        $result.Reason   | Should -Match 'lowercase'
    }

    It 'Rejects passwords without digits' {
        $result = & (Get-Module Noxora.Auth) { Test-PasswordStrength -PlainPassword 'PasswordOnly' }
        $result.IsStrong | Should -BeFalse
        $result.Reason   | Should -Match 'digit'
    }

    It 'Accepts a strong password meeting all requirements' {
        $result = & (Get-Module Noxora.Auth) { Test-PasswordStrength -PlainPassword 'Noxora2026!' }
        $result.IsStrong | Should -BeTrue
        $result.Reason   | Should -BeNullOrEmpty
    }

    It 'Rejects passwords exceeding 128 characters' {
        $longPass = 'Aa1' + ('x' * 130)
        $result   = & (Get-Module Noxora.Auth) { Test-PasswordStrength -PlainPassword $using:longPass }
        $result.IsStrong | Should -BeFalse
        $result.Reason   | Should -Match '128'
    }
}

# ─── Owner Account ─────────────────────────────────────────────────────────────

Describe 'Owner Account Management' {

    BeforeEach {
        # Ensure clean state
        $credFile = Join-Path $script:TestAuthDir 'owner.cred.json'
        if (Test-Path $credFile) { Remove-Item $credFile -Force }
    }

    It 'Reports no owner before account creation' {
        Test-NoxoraOwnerExists | Should -BeFalse
    }

    It 'Creates owner account successfully with valid credentials' {
        $password = ConvertTo-SecureString 'Noxora2026!' -AsPlainText -Force
        $result   = New-NoxoraOwner -Username 'owner' -Password $password -ConfirmPassword $password -Confirm:$false

        $result.Success | Should -BeTrue
        Test-NoxoraOwnerExists | Should -BeTrue
    }

    It 'Stores credentials without plain-text password' {
        $password = ConvertTo-SecureString 'Noxora2026!' -AsPlainText -Force
        $null     = New-NoxoraOwner -Username 'owner' -Password $password -ConfirmPassword $password -Confirm:$false

        $credFile = Join-Path $script:TestAuthDir 'owner.cred.json'
        $content  = Get-Content $credFile -Raw

        # Must not contain the plain password
        $content | Should -Not -Match 'Noxora2026'
        # Must contain algorithm field
        $content | Should -Match 'PBKDF2-SHA256'
        # Must contain salt and hash fields
        $content | Should -Match '"Salt"'
        $content | Should -Match '"Hash"'
    }

    It 'Rejects account creation when passwords do not match' {
        $pass1  = ConvertTo-SecureString 'Noxora2026!'  -AsPlainText -Force
        $pass2  = ConvertTo-SecureString 'Different1!'  -AsPlainText -Force
        $result = New-NoxoraOwner -Username 'owner' -Password $pass1 -ConfirmPassword $pass2 -Confirm:$false

        $result.Success | Should -BeFalse
        $result.Message | Should -Match 'do not match'
    }

    It 'Rejects account creation with a weak password' {
        $weak   = ConvertTo-SecureString 'password' -AsPlainText -Force
        $result = New-NoxoraOwner -Username 'owner' -Password $weak -ConfirmPassword $weak -Confirm:$false

        $result.Success | Should -BeFalse
        $result.Message | Should -Match 'weak'
    }
}

# ─── Login ────────────────────────────────────────────────────────────────────

Describe 'Login Flow' {

    BeforeAll {
        # Create a fresh owner for login tests
        $credFile = Join-Path $script:TestAuthDir 'owner.cred.json'
        if (Test-Path $credFile) { Remove-Item $credFile -Force }
        $lockFile = Join-Path $script:TestAuthDir 'lockout.json'
        if (Test-Path $lockFile) { Remove-Item $lockFile -Force }

        $password = ConvertTo-SecureString 'Noxora2026!' -AsPlainText -Force
        New-NoxoraOwner -Username 'testowner' -Password $password -ConfirmPassword $password -Confirm:$false | Out-Null
    }

    It 'Authenticates successfully with correct credentials' {
        $password = ConvertTo-SecureString 'Noxora2026!' -AsPlainText -Force
        $result   = Invoke-NoxoraLogin -Username 'testowner' -Password $password

        $result.Success | Should -BeTrue
        $result.Session | Should -Not -BeNullOrEmpty
        $result.Session.Username | Should -Be 'testowner'
    }

    It 'Fails authentication with wrong password' {
        $wrong  = ConvertTo-SecureString 'WrongPassword1!' -AsPlainText -Force
        $result = Invoke-NoxoraLogin -Username 'testowner' -Password $wrong

        $result.Success | Should -BeFalse
        $result.Message | Should -Match 'Invalid'
    }

    It 'Fails authentication with wrong username' {
        $password = ConvertTo-SecureString 'Noxora2026!' -AsPlainText -Force
        $result   = Invoke-NoxoraLogin -Username 'nobody' -Password $password

        $result.Success | Should -BeFalse
    }

    It 'Creates a session with IsActive set to true on success' {
        $lockFile = Join-Path $script:TestAuthDir 'lockout.json'
        if (Test-Path $lockFile) { Remove-Item $lockFile -Force }

        $password = ConvertTo-SecureString 'Noxora2026!' -AsPlainText -Force
        $result   = Invoke-NoxoraLogin -Username 'testowner' -Password $password

        $result.Session.IsActive | Should -BeTrue
        $result.Session.Username | Should -Be 'testowner'
    }
}

# ─── Session Management ────────────────────────────────────────────────────────

Describe 'Session Management' {

    It 'Returns null session before login' {
        $null = Invoke-NoxoraLogout  # Ensure no active session
        Get-NoxoraSession | Should -BeNullOrEmpty
    }

    It 'Reports session as valid immediately after login' {
        $lockFile = Join-Path $script:TestAuthDir 'lockout.json'
        if (Test-Path $lockFile) { Remove-Item $lockFile -Force }

        $password = ConvertTo-SecureString 'Noxora2026!' -AsPlainText -Force
        $null     = Invoke-NoxoraLogin -Username 'testowner' -Password $password

        $validity = Test-NoxoraSessionValid
        $validity.IsValid | Should -BeTrue
        $validity.IsExpired | Should -BeFalse
        $validity.MinutesRemaining | Should -BeGreaterThan 0
    }

    It 'Clears session after logout' {
        $null     = Invoke-NoxoraLogout
        $session  = Get-NoxoraSession
        $session  | Should -BeNullOrEmpty
    }
}
