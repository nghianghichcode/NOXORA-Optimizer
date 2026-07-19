#Requires -Version 5.1
<#
.SYNOPSIS
    NOXORA — Safety Guard Tests (Pester)
.DESCRIPTION
    Tests that verify NOXORA's safety constraints are enforced:
      - Protected processes are never allowed to be killed
      - Protected services are never allowed to be stopped/disabled
      - Prohibited commands are not present in any module
      - Config files enforce safety settings
      - No plain-text credentials in any file
      - No dangerous wildcard operations
      - No inline Invoke-Expression or iex usage
.NOTES
    Run with: Invoke-Pester .\tests\Safety.Tests.ps1 -Output Detailed
    Requires: Pester 5.0+
#>

BeforeAll {
    $script:RootPath    = Join-Path -Path $PSScriptRoot -ChildPath '..'
    $script:ModulesPath = Join-Path -Path $script:RootPath -ChildPath 'modules'
    $script:ConfigPath  = Join-Path -Path $script:RootPath -ChildPath 'config'
    $script:TestsPath   = $PSScriptRoot

    # Load modules for testing
    Import-Module (Join-Path $script:ModulesPath 'Noxora.Core.psm1')    -Force
    Import-Module (Join-Path $script:ModulesPath 'Noxora.Logging.psm1') -Force
    Import-Module (Join-Path $script:ModulesPath 'Noxora.Auth.psm1')    -Force
    Import-Module (Join-Path $script:ModulesPath 'Noxora.UI.psm1')      -Force
    Import-Module (Join-Path $script:ModulesPath 'Noxora.Session.psm1') -Force

    # Load config files
    $script:ProtectedProcesses = Get-Content (Join-Path $script:ConfigPath 'protected-processes.json') -Raw | ConvertFrom-Json
    $script:ProtectedServices  = Get-Content (Join-Path $script:ConfigPath 'protected-services.json')  -Raw | ConvertFrom-Json
    $script:ProcessRules       = Get-Content (Join-Path $script:ConfigPath 'process-rules.json')       -Raw | ConvertFrom-Json
    $script:Settings           = Get-Content (Join-Path $script:ConfigPath 'settings.json')            -Raw | ConvertFrom-Json

    # Collect all module files
    $script:AllModuleFiles = Get-ChildItem -Path $script:ModulesPath -Filter '*.psm1' -Recurse
    $script:AllPSFiles     = Get-ChildItem -Path $script:RootPath -Recurse -Include '*.ps1','*.psm1' |
                             Where-Object { $_.FullName -notlike '*\.git*' }
}

# ─── Protected Processes Config ─────────────────────────────────────────────────

Describe 'Protected Processes Configuration' {

    It 'Protected processes list is not empty' {
        $script:ProtectedProcesses.protectedProcesses.Count | Should -BeGreaterThan 10
    }

    It 'Contains Windows core processes' {
        $names = $script:ProtectedProcesses.protectedProcesses.name
        $names | Should -Contain 'System'
        $names | Should -Contain 'csrss.exe'
        $names | Should -Contain 'lsass.exe'
        $names | Should -Contain 'services.exe'
    }

    It 'Contains security processes' {
        $names = $script:ProtectedProcesses.protectedProcesses.name
        $names | Should -Contain 'MsMpEng.exe'
    }

    It 'Contains DWM' {
        $names = $script:ProtectedProcesses.protectedProcesses.name
        $names | Should -Contain 'dwm.exe'
    }

    It 'Every protected process entry has a reason' {
        foreach ($p in $script:ProtectedProcesses.protectedProcesses) {
            $p.reason | Should -Not -BeNullOrEmpty -Because "Process '$($p.name)' must have a reason"
        }
    }

    It 'Every protected process entry has a category' {
        foreach ($p in $script:ProtectedProcesses.protectedProcesses) {
            $p.category | Should -Not -BeNullOrEmpty -Because "Process '$($p.name)' must have a category"
        }
    }
}

# ─── Protected Services Config ──────────────────────────────────────────────────

Describe 'Protected Services Configuration' {

    It 'Protected services list is not empty' {
        $script:ProtectedServices.protectedServices.Count | Should -BeGreaterThan 10
    }

    It 'Contains RPC endpoint services' {
        $names = $script:ProtectedServices.protectedServices.name
        $names | Should -Contain 'RpcSs'
        $names | Should -Contain 'DcomLaunch'
        $names | Should -Contain 'RpcEptMapper'
    }

    It 'Contains Windows Defender' {
        $names = $script:ProtectedServices.protectedServices.name
        $names | Should -Contain 'WinDefend'
    }

    It 'Contains Windows Firewall' {
        $names = $script:ProtectedServices.protectedServices.name
        $names | Should -Contain 'MpsSvc'
    }

    It 'Contains audio services' {
        $names = $script:ProtectedServices.protectedServices.name
        $names | Should -Contain 'AudioSrv'
        $names | Should -Contain 'AudioEndpointBuilder'
    }

    It 'Contains network services' {
        $names = $script:ProtectedServices.protectedServices.name
        $names | Should -Contain 'Dhcp'
        $names | Should -Contain 'Dnscache'
    }

    It 'Every protected service has a reason' {
        foreach ($svc in $script:ProtectedServices.protectedServices) {
            $svc.reason | Should -Not -BeNullOrEmpty -Because "Service '$($svc.name)' must have a reason"
        }
    }
}

# ─── Process Rules Safety ───────────────────────────────────────────────────────

Describe 'Process Classification Rules' {

    It 'WindowsCore category has killAllowed = false' {
        $coreRules = $script:ProcessRules.classificationRules |
                     Where-Object { $_.category -eq 'WindowsCore' }
        foreach ($rule in $coreRules) {
            $rule.killAllowed | Should -BeFalse -Because "Windows core processes must not be killable"
        }
    }

    It 'Security category has killAllowed = false' {
        $secRules = $script:ProcessRules.classificationRules |
                    Where-Object { $_.category -eq 'Security' }
        foreach ($rule in $secRules) {
            $rule.killAllowed | Should -BeFalse -Because "Security processes must not be killable"
        }
    }

    It 'AntiCheat category has killAllowed = false' {
        $acRules = $script:ProcessRules.classificationRules |
                   Where-Object { $_.category -eq 'AntiCheat' }
        foreach ($rule in $acRules) {
            $rule.killAllowed | Should -BeFalse -Because "Anti-cheat processes must not be killable"
        }
    }

    It 'Unknown policy has killAllowed = false' {
        $script:ProcessRules.unknownPolicy.killAllowed | Should -BeFalse
    }

    It 'Unknown policy requires manual review' {
        $script:ProcessRules.unknownPolicy.requireManualReview | Should -BeTrue
    }
}

# ─── Safety Settings ────────────────────────────────────────────────────────────

Describe 'Settings Safety Defaults' {

    It 'neverDisableDefender is true' {
        $script:Settings.safety.neverDisableDefender | Should -BeTrue
    }

    It 'neverDisableFirewall is true' {
        $script:Settings.safety.neverDisableFirewall | Should -BeTrue
    }

    It 'neverDisableWindowsUpdate is true' {
        $script:Settings.safety.neverDisableWindowsUpdate | Should -BeTrue
    }

    It 'neverModifySystem32 is true' {
        $script:Settings.safety.neverModifySystem32 | Should -BeTrue
    }

    It 'neverModifyDriverStore is true' {
        $script:Settings.safety.neverModifyDriverStore | Should -BeTrue
    }

    It 'neverModifyWinSxS is true' {
        $script:Settings.safety.neverModifyWinSxS | Should -BeTrue
    }

    It 'requireBackupBeforeApply is true' {
        $script:Settings.safety.requireBackupBeforeApply | Should -BeTrue
    }

    It 'requireConfirmationForAllActions is true' {
        $script:Settings.safety.requireConfirmationForAllActions | Should -BeTrue
    }

    It 'dryRunDefault is true' {
        $script:Settings.safety.dryRunDefault | Should -BeTrue
    }

    It 'Auth maxLoginAttempts is 5' {
        $script:Settings.auth.maxLoginAttempts | Should -Be 5
    }

    It 'Auth PBKDF2 iterations is at least 100000' {
        $script:Settings.auth.pbkdf2Iterations | Should -BeGreaterOrEqual 100000
    }
}

# ─── Prohibited Command Patterns in Source ──────────────────────────────────────

Describe 'Prohibited Commands Not Present in Source' {

    It 'No Invoke-Expression in any module' {
        foreach ($file in $script:AllModuleFiles) {
            $content = Get-Content -LiteralPath $file.FullName -Raw
            $content | Should -Not -Match 'Invoke-Expression' -Because "$($file.Name) must not use Invoke-Expression"
        }
    }

    It 'No iex alias in any module' {
        foreach ($file in $script:AllModuleFiles) {
            $content = Get-Content -LiteralPath $file.FullName -Raw
            # Allow 'iex' only as part of another word (e.g., 'complex'), match standalone
            $content | Should -Not -Match '(?<![a-zA-Z])iex\s*\(' -Because "$($file.Name) must not use iex"
        }
    }

    It 'No EncodedCommand in any module' {
        foreach ($file in $script:AllModuleFiles) {
            $content = Get-Content -LiteralPath $file.FullName -Raw
            $content | Should -Not -Match '-EncodedCommand' -Because "$($file.Name) must not use encoded commands"
        }
    }

    It 'No DownloadString in any module' {
        foreach ($file in $script:AllModuleFiles) {
            $content = Get-Content -LiteralPath $file.FullName -Raw
            $content | Should -Not -Match 'DownloadString' -Because "$($file.Name) must not download and execute code"
        }
    }

    It 'No taskkill /F /IM * in any module' {
        foreach ($file in $script:AllModuleFiles) {
            $content = Get-Content -LiteralPath $file.FullName -Raw
            $content | Should -Not -Match 'taskkill.*\/IM\s+\*' -Because "$($file.Name) must not use wildcard taskkill"
        }
    }

    It 'No Set-MpPreference -DisableRealtimeMonitoring' {
        foreach ($file in $script:AllPSFiles) {
            $content = Get-Content -LiteralPath $file.FullName -Raw
            $content | Should -Not -Match 'DisableRealtimeMonitoring\s*\$true' -Because "$($file.Name) must not disable Defender real-time monitoring"
        }
    }

    It 'No Set-NetFirewallProfile -Enabled False' {
        foreach ($file in $script:AllPSFiles) {
            $content = Get-Content -LiteralPath $file.FullName -Raw
            $content | Should -Not -Match 'Set-NetFirewallProfile.*Enabled.*False' -Because "$($file.Name) must not disable the firewall"
        }
    }

    It 'No Remove-Item on System32' {
        foreach ($file in $script:AllPSFiles) {
            $content = Get-Content -LiteralPath $file.FullName -Raw
            $content | Should -Not -Match 'Remove-Item.*System32' -Because "$($file.Name) must not delete System32 files"
        }
    }

    It 'No Remove-Item on DriverStore' {
        foreach ($file in $script:AllPSFiles) {
            $content = Get-Content -LiteralPath $file.FullName -Raw
            $content | Should -Not -Match 'Remove-Item.*DriverStore' -Because "$($file.Name) must not delete DriverStore files"
        }
    }

    It 'No Remove-Item on WinSxS' {
        foreach ($file in $script:AllPSFiles) {
            $content = Get-Content -LiteralPath $file.FullName -Raw
            $content | Should -Not -Match 'Remove-Item.*WinSxS' -Because "$($file.Name) must not delete WinSxS files"
        }
    }
}

# ─── No Credentials in Source ───────────────────────────────────────────────────

Describe 'No Hardcoded Credentials in Source' {

    It 'No hardcoded password string in any PS file' {
        foreach ($file in $script:AllPSFiles) {
            $content = Get-Content -LiteralPath $file.FullName -Raw
            # Look for common hardcoded password patterns
            $content | Should -Not -Match '(?i)password\s*=\s*["\x27][^"\x27]{3,}' -Because "$($file.Name) must not contain hardcoded passwords"
        }
    }

    It 'Auth credential file (if exists) does not contain plain-text passwords' {
        $credFile = Join-Path $script:RootPath 'data\auth\owner.cred.json'
        if (Test-Path $credFile) {
            $content = Get-Content $credFile -Raw
            # The file should contain Hash and Salt but not Algorithm with a plaintext value
            $content | Should -Not -Match '"Password"\s*:'
        }
    }
}

# ─── Module Structure ───────────────────────────────────────────────────────────

Describe 'Module Structure Requirements' {

    It 'Each module exports functions (not empty)' {
        foreach ($file in $script:AllModuleFiles) {
            $content = Get-Content -LiteralPath $file.FullName -Raw
            $content | Should -Match 'Export-ModuleMember' -Because "$($file.Name) must have Export-ModuleMember"
        }
    }

    It 'Each module has Set-StrictMode' {
        foreach ($file in $script:AllModuleFiles) {
            $content = Get-Content -LiteralPath $file.FullName -Raw
            $content | Should -Match 'Set-StrictMode' -Because "$($file.Name) must use Set-StrictMode"
        }
    }

    It 'Each module has error action preference set' {
        foreach ($file in $script:AllModuleFiles) {
            $content = Get-Content -LiteralPath $file.FullName -Raw
            $content | Should -Match 'ErrorActionPreference' -Because "$($file.Name) must set ErrorActionPreference"
        }
    }

    It 'Auth module does not export private helper functions' {
        # Private functions like New-CryptographicSalt should not be in exported list
        $authModule = Import-Module (Join-Path $script:ModulesPath 'Noxora.Auth.psm1') -Force -PassThru
        $exported   = $authModule.ExportedCommands.Keys

        $exported | Should -Not -Contain 'New-CryptographicSalt'    -Because 'Internal crypto functions must not be exported'
        $exported | Should -Not -Contain 'Invoke-PBKDF2Hash'        -Because 'Internal crypto functions must not be exported'
        $exported | Should -Not -Contain 'Compare-ConstantTime'     -Because 'Internal security functions must not be exported'
        $exported | Should -Not -Contain 'ConvertFrom-NoxoraSecureString' -Because 'SecureString conversion must not be exported'
    }
}

# ─── Config File Validity ───────────────────────────────────────────────────────

Describe 'Config Files Are Valid JSON' {

    It 'settings.json is valid JSON' {
        { Get-Content (Join-Path $script:ConfigPath 'settings.json') -Raw | ConvertFrom-Json } |
            Should -Not -Throw
    }

    It 'protected-processes.json is valid JSON' {
        { Get-Content (Join-Path $script:ConfigPath 'protected-processes.json') -Raw | ConvertFrom-Json } |
            Should -Not -Throw
    }

    It 'protected-services.json is valid JSON' {
        { Get-Content (Join-Path $script:ConfigPath 'protected-services.json') -Raw | ConvertFrom-Json } |
            Should -Not -Throw
    }

    It 'optional-services.json is valid JSON' {
        { Get-Content (Join-Path $script:ConfigPath 'optional-services.json') -Raw | ConvertFrom-Json } |
            Should -Not -Throw
    }

    It 'process-rules.json is valid JSON' {
        { Get-Content (Join-Path $script:ConfigPath 'process-rules.json') -Raw | ConvertFrom-Json } |
            Should -Not -Throw
    }

    It 'package-rules.json is valid JSON' {
        { Get-Content (Join-Path $script:ConfigPath 'package-rules.json') -Raw | ConvertFrom-Json } |
            Should -Not -Throw
    }

    It 'startup-rules.json is valid JSON' {
        { Get-Content (Join-Path $script:ConfigPath 'startup-rules.json') -Raw | ConvertFrom-Json } |
            Should -Not -Throw
    }

    It 'security-rules.json is valid JSON' {
        { Get-Content (Join-Path $script:ConfigPath 'security-rules.json') -Raw | ConvertFrom-Json } |
            Should -Not -Throw
    }
}
