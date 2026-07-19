#Requires -Version 5.1
<#
.SYNOPSIS
    NOXORA Optimizer — Session State Module
.DESCRIPTION
    Manages the current optimization session: state tracking, action history,
    pending changes, rollback registry, and session metadata.
    This is separate from Auth session management (Noxora.Auth.psm1).
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region — Module State
$script:CurrentOptimizationSession = $null
$script:ActionHistory              = [System.Collections.Generic.List[PSCustomObject]]::new()
$script:PendingActions             = [System.Collections.Generic.List[PSCustomObject]]::new()
#endregion

function New-NoxoraOptimizationSession {
    <#
    .SYNOPSIS
        Creates a new optimization session for tracking changes.
    .PARAMETER Category
        The optimization category (e.g., CPU, GPU, Services).
    .PARAMETER OwnerUsername
        The authenticated OWNER username.
    .PARAMETER SessionDirectory
        Path to the sessions directory.
    .OUTPUTS
        PSCustomObject representing the session.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('CPU','GPU','RAM','Process','Services','Startup','Debloat','Network','GameBoost','Thermal','Security','Backup','Custom')]
        [string]$Category,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$OwnerUsername,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$SessionDirectory
    )

    $sessionId = "NSS-$(Get-Date -Format 'yyyyMMdd-HHmmss')-$([Guid]::NewGuid().ToString('N').Substring(0,6).ToUpper())"

    $session = [PSCustomObject]@{
        SessionId       = $sessionId
        Category        = $Category
        Computer        = $env:COMPUTERNAME
        Owner           = $OwnerUsername
        StartTime       = (Get-Date -Format 'o')
        EndTime         = $null
        Status          = 'Active'
        Actions         = [System.Collections.Generic.List[PSCustomObject]]::new()
        Applied         = 0
        Skipped         = 0
        Warnings        = 0
        Failed          = 0
        RequiresRestart = $false
        SessionFile     = Join-Path -Path $SessionDirectory -ChildPath "$sessionId.json"
    }

    $script:CurrentOptimizationSession = $session
    $script:ActionHistory.Clear()
    $script:PendingActions.Clear()

    return $session
}

function Get-NoxoraOptimizationSession {
    <#
    .SYNOPSIS
        Returns the current active optimization session.
    .OUTPUTS
        PSCustomObject session or $null.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    return $script:CurrentOptimizationSession
}

function Add-NoxoraSessionAction {
    <#
    .SYNOPSIS
        Records an action in the current optimization session.
    .PARAMETER ActionId
        Unique action identifier.
    .PARAMETER ActionName
        Human-readable action name.
    .PARAMETER Category
        Action category.
    .PARAMETER Status
        Action status.
    .PARAMETER Description
        What the action does.
    .PARAMETER Reason
        Why this action is being taken.
    .PARAMETER Risk
        Risk level: Low, Medium, High, Critical.
    .PARAMETER OriginalValue
        Value before the change.
    .PARAMETER NewValue
        Value after the change.
    .PARAMETER RestoreCommand
        PowerShell command or function to restore this action.
    .PARAMETER RequiresRestart
        If $true, this action requires a system restart.
    .PARAMETER ErrorMessage
        Error message if action failed.
    .OUTPUTS
        The action PSCustomObject.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)][string]$ActionId,
        [Parameter(Mandatory)][string]$ActionName,
        [string]$Category        = '',
        [ValidateSet('Pending','Running','Applied','Verified','Skipped','Failed','RolledBack','RequiresRestart')]
        [string]$Status          = 'Pending',
        [string]$Description     = '',
        [string]$Reason          = '',
        [ValidateSet('Low','Medium','High','Critical')]
        [string]$Risk            = 'Low',
        [string]$OriginalValue   = '',
        [string]$NewValue        = '',
        [string]$RestoreCommand  = '',
        [bool]$RequiresRestart   = $false,
        [string]$ErrorMessage    = ''
    )

    $action = [PSCustomObject]@{
        ActionId        = $ActionId
        ActionName      = $ActionName
        Category        = $Category
        Status          = $Status
        Description     = $Description
        Reason          = $Reason
        Risk            = $Risk
        OriginalValue   = $OriginalValue
        NewValue        = $NewValue
        RestoreCommand  = $RestoreCommand
        RequiresRestart = $RequiresRestart
        ErrorMessage    = $ErrorMessage
        Timestamp       = (Get-Date -Format 'o')
    }

    $script:ActionHistory.Add($action)

    if ($null -ne $script:CurrentOptimizationSession) {
        $script:CurrentOptimizationSession.Actions.Add($action)

        switch ($Status) {
            'Applied'          { $script:CurrentOptimizationSession.Applied++ }
            'Verified'         { }  # Already counted in Applied
            'Skipped'          { $script:CurrentOptimizationSession.Skipped++ }
            'Failed'           { $script:CurrentOptimizationSession.Failed++ }
            'RolledBack'       { $script:CurrentOptimizationSession.Warnings++ }
            'RequiresRestart'  {
                $script:CurrentOptimizationSession.Warnings++
                $script:CurrentOptimizationSession.RequiresRestart = $true
            }
        }
    }

    return $action
}

function Complete-NoxoraOptimizationSession {
    <#
    .SYNOPSIS
        Marks the current optimization session as complete and saves it to disk.
    .PARAMETER Status
        Final session status: Completed, CompletedWithWarnings, Failed, Cancelled.
    .OUTPUTS
        PSCustomObject with Success and SavedPath.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [ValidateSet('Completed','CompletedWithWarnings','Failed','Cancelled')]
        [string]$Status = 'Completed'
    )

    $result = [PSCustomObject]@{
        Success   = $false
        SavedPath = ''
    }

    if ($null -eq $script:CurrentOptimizationSession) {
        $result.Success = $true  # No session to complete
        return $result
    }

    try {
        $script:CurrentOptimizationSession.EndTime = Get-Date -Format 'o'
        $script:CurrentOptimizationSession.Status  = $Status

        $sessionDir = [System.IO.Path]::GetDirectoryName($script:CurrentOptimizationSession.SessionFile)
        if (-not (Test-Path -LiteralPath $sessionDir -PathType Container)) {
            $null = New-Item -ItemType Directory -Path $sessionDir -Force
        }

        $json = $script:CurrentOptimizationSession | ConvertTo-Json -Depth 10
        $json | Out-File -LiteralPath $script:CurrentOptimizationSession.SessionFile -Encoding UTF8 -Force

        $result.Success   = $true
        $result.SavedPath = $script:CurrentOptimizationSession.SessionFile
    }
    catch {
        $result.Success   = $false
    }

    return $result
}

function Get-NoxoraSessionSummary {
    <#
    .SYNOPSIS
        Returns a summary object for display in the progress table.
    .OUTPUTS
        PSCustomObject with Applied, Skipped, Warnings, Failed, RollbackId.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    if ($null -eq $script:CurrentOptimizationSession) {
        return [PSCustomObject]@{
            Applied    = 0
            Skipped    = 0
            Warnings   = 0
            Failed     = 0
            RollbackId = 'N/A'
        }
    }

    return [PSCustomObject]@{
        Applied    = $script:CurrentOptimizationSession.Applied
        Skipped    = $script:CurrentOptimizationSession.Skipped
        Warnings   = $script:CurrentOptimizationSession.Warnings
        Failed     = $script:CurrentOptimizationSession.Failed
        RollbackId = $script:CurrentOptimizationSession.SessionId
    }
}

Export-ModuleMember -Function @(
    'New-NoxoraOptimizationSession',
    'Get-NoxoraOptimizationSession',
    'Add-NoxoraSessionAction',
    'Complete-NoxoraOptimizationSession',
    'Get-NoxoraSessionSummary'
)
