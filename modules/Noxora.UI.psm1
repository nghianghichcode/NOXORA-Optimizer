#Requires -Version 5.1
<#
.SYNOPSIS
    NOXORA Optimizer — UI Module
.DESCRIPTION
    Provides all terminal UI rendering: banner, menus, progress tables,
    color output, prompts, and adaptive layout for terminal width.

    Design principles:
      - Cyan as primary brand color
      - Green = success, Yellow = warning, Red = error/danger
      - Adapts to terminal width (>= 80 cols: full UI; < 80: simple mode)
      - No Clear-Host during active tasks
      - No arbitrary blinking or animation
      - All output goes through this module only
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region — UI Constants
$script:UIConfig = [PSCustomObject]@{
    MenuWidth          = 56
    AutoCenter         = $true
    SimpleMode         = $false
    SimpleModeThreshold = 80
    PrimaryColor       = 'Cyan'
    SuccessColor       = 'Green'
    WarningColor       = 'Yellow'
    ErrorColor         = 'Red'
    AccentColor        = 'Magenta'
    DimColor           = 'DarkGray'
    NormalColor        = 'White'
}

$script:StatusIcons = @{
    'Pass'           = '[PASS]'
    'Fail'           = '[FAIL]'
    'Skip'           = '[SKIP]'
    'Warn'           = '[WARN]'
    'Info'           = '[INFO]'
    'Running'        = '[...] '
    'Pending'        = '[    ]'
    'Applied'        = '[APPLY]'
    'Verified'       = '[VERF]'
    'RolledBack'     = '[RLBK]'
    'RequiresRestart'= '[RSTR]'
}

$script:StatusColors = @{
    'Pass'           = 'Green'
    'Fail'           = 'Red'
    'Skip'           = 'DarkGray'
    'Warn'           = 'Yellow'
    'Info'           = 'Cyan'
    'Running'        = 'Cyan'
    'Pending'        = 'DarkGray'
    'Applied'        = 'Green'
    'Verified'       = 'Green'
    'RolledBack'     = 'Yellow'
    'RequiresRestart'= 'Yellow'
}
#endregion

#region — Initialization

function Initialize-NoxoraUI {
    <#
    .SYNOPSIS
        Initializes UI settings from configuration.
    .PARAMETER Config
        The settings object from Import-NoxoraConfig.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Config
    )

    $script:UIConfig.MenuWidth           = $Config.ui.menuWidth
    $script:UIConfig.AutoCenter          = $Config.ui.autoCenter
    $script:UIConfig.SimpleMode          = $Config.ui.simpleMode
    $script:UIConfig.SimpleModeThreshold = $Config.ui.simpleModeThresholdWidth
    $script:UIConfig.PrimaryColor        = $Config.theme.primaryColor
    $script:UIConfig.SuccessColor        = $Config.theme.successColor
    $script:UIConfig.WarningColor        = $Config.theme.warningColor
    $script:UIConfig.ErrorColor          = $Config.theme.errorColor
    $script:UIConfig.AccentColor         = $Config.theme.accentColor
}

#endregion

#region — Layout Helpers

function Get-TerminalWidth {
    <#
    .SYNOPSIS
        Returns the current terminal buffer width, capped safely.
    .OUTPUTS
        Integer — terminal width in columns.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param()

    try {
        return [System.Console]::BufferWidth
    }
    catch {
        return 80
    }
}

function Test-SimpleMode {
    <#
    .SYNOPSIS
        Returns $true if the terminal is too narrow for full UI.
    .OUTPUTS
        Boolean
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    if ($script:UIConfig.SimpleMode) { return $true }
    return (Get-TerminalWidth) -lt $script:UIConfig.SimpleModeThreshold
}

function Get-CenterPad {
    <#
    .SYNOPSIS
        Returns a padding string to center content of given width.
    .PARAMETER ContentWidth
        Width of the content to center.
    .OUTPUTS
        String of spaces.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [int]$ContentWidth
    )

    if (-not $script:UIConfig.AutoCenter) { return '' }
    $termWidth = Get-TerminalWidth
    $pad       = [math]::Max(0, [math]::Floor(($termWidth - $ContentWidth) / 2))
    return ' ' * $pad
}

#endregion

#region — Color Output

function Write-NoxoraColor {
    <#
    .SYNOPSIS
        Writes colored text to the terminal.
    .PARAMETER Text
        Text to write.
    .PARAMETER Color
        Console color name.
    .PARAMETER NoNewLine
        If specified, does not append a newline.
    .PARAMETER Pad
        Optional leading padding string.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Text,

        [string]$Color = 'White',
        [switch]$NoNewLine,
        [string]$Pad = ''
    )

    if ($Pad) { Write-Host $Pad -NoNewline }

    if ($NoNewLine) {
        Write-Host $Text -ForegroundColor $Color -NoNewline
    }
    else {
        Write-Host $Text -ForegroundColor $Color
    }
}

function Write-NoxoraPrimary   { param([string]$Text, [switch]$NoNewLine) Write-NoxoraColor -Text $Text -Color $script:UIConfig.PrimaryColor -NoNewLine:$NoNewLine }
function Write-NoxoraSuccess   { param([string]$Text, [switch]$NoNewLine) Write-NoxoraColor -Text $Text -Color $script:UIConfig.SuccessColor -NoNewLine:$NoNewLine }
function Write-NoxoraWarning   { param([string]$Text, [switch]$NoNewLine) Write-NoxoraColor -Text $Text -Color $script:UIConfig.WarningColor -NoNewLine:$NoNewLine }
function Write-NoxoraError     { param([string]$Text, [switch]$NoNewLine) Write-NoxoraColor -Text $Text -Color $script:UIConfig.ErrorColor   -NoNewLine:$NoNewLine }
function Write-NoxoraDim       { param([string]$Text, [switch]$NoNewLine) Write-NoxoraColor -Text $Text -Color $script:UIConfig.DimColor      -NoNewLine:$NoNewLine }
function Write-NoxoraAccent    { param([string]$Text, [switch]$NoNewLine) Write-NoxoraColor -Text $Text -Color $script:UIConfig.AccentColor   -NoNewLine:$NoNewLine }

#endregion

#region — Banner

function Show-NoxoraBanner {
    <#
    .SYNOPSIS
        Displays the NOXORA ASCII art banner with version info.
    .PARAMETER Version
        Version string to display below the banner.
    #>
    [CmdletBinding()]
    param(
        [string]$Version = '1.0.0'
    )

        $banner = @(
        'NNNNN  OOO  X   X OOO  RRRR   A  ',
        'N NNNN O   O X X  O   O R   R A A ',
        'N  NNN O   O  X   O   O RRRR  AAA ',
        'N   NN O   O X X  O   O R R   A  A',
        'N    N  OOO  X   X OOO  R  R  A  A'
    )

    $bannerWidth = 54
    $pad         = Get-CenterPad -ContentWidth $bannerWidth

    Write-Host ''
    foreach ($line in $banner) {
        Write-NoxoraColor -Text $line -Color $script:UIConfig.PrimaryColor -Pad $pad
    }
    Write-Host ''
    Write-NoxoraColor -Text ('WINDOWS OPTIMIZER').PadLeft(37).PadRight(54) -Color $script:UIConfig.AccentColor -Pad $pad
    Write-NoxoraColor -Text ("VERSION $Version").PadLeft(35).PadRight(54) -Color $script:UIConfig.DimColor    -Pad $pad
    Write-Host ''
}

#endregion

#region — Box Drawing

function Write-NoxoraBoxTop {
    <#
    .SYNOPSIS
        Draws the top border of a menu box.
    .PARAMETER Title
        Title text to display centered in the top border.
    .PARAMETER Width
        Box width in characters.
    #>
    [CmdletBinding()]
    param(
        [string]$Title = '',
        [int]$Width = 56
    )

    $pad = Get-CenterPad -ContentWidth ($Width + 2)

    if ($Title) {
        $inner   = $Width - 2
        $padLeft = [math]::Floor(($inner - $Title.Length) / 2)
        $padRight = $inner - $Title.Length - $padLeft
        $top     = '+' + ('=' * ($padLeft)) + ' ' + $Title + ' ' + ('=' * ($padRight - 2 + 1)) + '+'
        # Safer: just build it properly
        $titleLine = " $Title "
        $remaining  = $Width - $titleLine.Length
        $leftPad    = [math]::Floor($remaining / 2)
        $rightPad   = $remaining - $leftPad
        $top        = $script:BoxChars.TopLeft + ($script:BoxChars.Horizontal * $leftPad) + $titleLine + ($script:BoxChars.Horizontal * $rightPad) + $script:BoxChars.TopRight
    }
    else {
        $top = $script:BoxChars.TopLeft + ($script:BoxChars.Horizontal * $Width) + $script:BoxChars.TopRight
    }

    Write-NoxoraColor -Text $top -Color $script:UIConfig.PrimaryColor -Pad $pad
}

function Write-NoxoraBoxDivider {
    <#
    .SYNOPSIS
        Draws a divider line inside a menu box.
    #>
    [CmdletBinding()]
    param([int]$Width = 56)

    $pad = Get-CenterPad -ContentWidth ($Width + 2)
    Write-NoxoraColor -Text ($script:BoxChars.DivLeft + ($script:BoxChars.Horizontal * $Width) + $script:BoxChars.DivRight) -Color $script:UIConfig.PrimaryColor -Pad $pad
}

function Write-NoxoraBoxRow {
    <#
    .SYNOPSIS
        Draws a single row inside a menu box.
    .PARAMETER Content
        The text content of the row.
    .PARAMETER ContentColor
        Color for the content text.
    .PARAMETER Width
        Box width.
    #>
    [CmdletBinding()]
    param(
        [string]$Content      = '',
        [string]$ContentColor = 'White',
        [int]$Width           = 56
    )

    $pad       = Get-CenterPad -ContentWidth ($Width + 2)
    $inner     = $Width
    $truncated = if ($Content.Length -gt $inner) { $Content.Substring(0, $inner) } else { $Content }
    $padded    = $truncated.PadRight($inner)

    if ($pad) { Write-Host $pad -NoNewline }
    Write-Host $script:BoxChars.Vertical -ForegroundColor $script:UIConfig.PrimaryColor -NoNewline
    Write-Host $padded -ForegroundColor $ContentColor -NoNewline
    Write-Host '|' -ForegroundColor $script:UIConfig.PrimaryColor
}

function Write-NoxoraBoxBottom {
    <#
    .SYNOPSIS
        Draws the bottom border of a menu box.
    #>
    [CmdletBinding()]
    param([int]$Width = 56)

    $pad = Get-CenterPad -ContentWidth ($Width + 2)
    Write-NoxoraColor -Text ($script:BoxChars.DivLeft + ($script:BoxChars.Horizontal * $Width) + $script:BoxChars.DivRight) -Color $script:UIConfig.PrimaryColor -Pad $pad
}

function Write-NoxoraEmptyRow {
    [CmdletBinding()]
    param([int]$Width = 56)
    Write-NoxoraBoxRow -Content '' -Width $Width
}

#endregion

#region — Authentication Screen

function Show-NoxoraAuthScreen {
    <#
    .SYNOPSIS
        Displays the OWNER authentication screen and returns credentials.
    .PARAMETER EnvInfo
        PSCustomObject from Test-NoxoraEnvironment with system info.
    .PARAMETER FailureCount
        Number of previous failed attempts (0 = first try).
    .PARAMETER ErrorMessage
        Error message from previous attempt to display.
    .PARAMETER IsFirstRun
        If $true, shows account creation flow.
    .OUTPUTS
        PSCustomObject with Username (string) and Password (SecureString).
        Returns $null if user presses Ctrl+C or exits.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$EnvInfo,

        [int]$FailureCount = 0,
        [string]$ErrorMessage = '',
        [switch]$IsFirstRun
    )

    $w = $script:UIConfig.MenuWidth

    Clear-Host
    Show-NoxoraBanner

    $title = if ($IsFirstRun) { 'INITIAL SETUP — CREATE OWNER' } else { 'OWNER AUTHENTICATION' }

    Write-NoxoraBoxTop    -Title $title    -Width $w
    Write-NoxoraBoxDivider                 -Width $w
    Write-NoxoraBoxRow -Content " Device     : $($EnvInfo.ComputerName)"          -ContentColor 'White'   -Width $w
    Write-NoxoraBoxRow -Content " Windows    : $($EnvInfo.OSCaption -replace 'Microsoft ','')" -ContentColor 'White' -Width $w
    Write-NoxoraBoxRow -Content " Privilege  : $(if ($EnvInfo.IsAdministrator) {'Administrator'} else {'LIMITED — Admin Required'})" -ContentColor (if ($EnvInfo.IsAdministrator) {'Green'} else {'Red'}) -Width $w

    if ($IsFirstRun) {
        Write-NoxoraBoxRow -Content " Tool Status: First Run Setup"                  -ContentColor 'Yellow'  -Width $w
    }
    else {
        $toolStatusText  = if ($FailureCount -eq 0) { 'Locked' } else { "Locked - $FailureCount failed attempt(s)" }
        $toolStatusColor = if ($FailureCount -gt 0) { 'Yellow' } else { 'Red' }
        Write-NoxoraBoxRow -Content " Tool Status: $toolStatusText" -ContentColor $toolStatusColor -Width $w
    }

    Write-NoxoraBoxDivider -Width $w

    if ($ErrorMessage) {
        Write-NoxoraBoxRow -Content '' -Width $w
        Write-NoxoraBoxRow -Content " ! $ErrorMessage" -ContentColor 'Red' -Width $w
    }

    Write-NoxoraBoxRow -Content '' -Width $w

    if ($IsFirstRun) {
        Write-NoxoraBoxRow -Content ' No OWNER account detected.' -ContentColor 'Yellow' -Width $w
        Write-NoxoraBoxRow -Content ' Create your OWNER account to continue.' -ContentColor 'White' -Width $w
        Write-NoxoraBoxRow -Content '' -Width $w
        Write-NoxoraBoxRow -Content ' Password requirements:' -ContentColor 'DarkGray' -Width $w
        Write-NoxoraBoxRow -Content '  - Minimum 8 characters' -ContentColor 'DarkGray' -Width $w
        Write-NoxoraBoxRow -Content '  - At least one uppercase letter' -ContentColor 'DarkGray' -Width $w
        Write-NoxoraBoxRow -Content '  - At least one lowercase letter' -ContentColor 'DarkGray' -Width $w
        Write-NoxoraBoxRow -Content '  - At least one digit' -ContentColor 'DarkGray' -Width $w
    }

    Write-NoxoraBoxBottom -Width $w
    Write-Host ''

    $pad = Get-CenterPad -ContentWidth $w

    # Collect username
    Write-Host "${pad} Username : " -ForegroundColor Cyan -NoNewline
    $username = Read-Host

    if ([string]::IsNullOrWhiteSpace($username)) {
        return $null
    }

    # Collect password (hidden)
    Write-Host "${pad} Password : " -ForegroundColor Cyan -NoNewline
    $password = Read-Host -AsSecureString

    if ($IsFirstRun) {
        Write-Host ''
        Write-Host "${pad} Confirm  : " -ForegroundColor Cyan -NoNewline
        $confirm = Read-Host -AsSecureString
        Write-Host ''
        return [PSCustomObject]@{
            Username         = $username.Trim()
            Password         = $password
            ConfirmPassword  = $confirm
        }
    }

    Write-Host ''
    return [PSCustomObject]@{
        Username = $username.Trim()
        Password = $password
    }
}

#endregion

#region — Main Menu

function Show-NoxoraMainMenu {
    <#
    .SYNOPSIS
        Displays the NOXORA main menu and returns the user's selection.
    .PARAMETER SessionInfo
        Current session for header display.
    .PARAMETER EnvInfo
        System environment info.
    .OUTPUTS
        String — the user's selection (e.g., '1', '2', 'L', '0').
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$SessionInfo,

        [Parameter(Mandatory)]
        [PSCustomObject]$EnvInfo
    )

    $w = $script:UIConfig.MenuWidth

    Clear-Host
    Show-NoxoraBanner

    # Session info header
    $sessionValidity = Test-NoxoraSessionValid
    $expiryStr       = if ($sessionValidity.IsValid) { "$([math]::Round($sessionValidity.MinutesRemaining)) min remaining" } else { 'EXPIRED' }
    $timeStr         = Get-Date -Format 'HH:mm:ss'

    Write-NoxoraBoxTop -Title 'SESSION' -Width $w
    Write-NoxoraBoxRow -Content " OWNER   : $($SessionInfo.Username)" -ContentColor 'Green'  -Width $w
    Write-NoxoraBoxRow -Content " Machine : $($EnvInfo.ComputerName)" -ContentColor 'White'  -Width $w
    Write-NoxoraBoxRow -Content " Session : $expiryStr" -ContentColor $(if ($sessionValidity.NeedsWarning) {'Yellow'} else {'White'}) -Width $w
    Write-NoxoraBoxRow -Content " Time    : $timeStr" -ContentColor 'DarkGray' -Width $w
    Write-NoxoraBoxBottom -Width $w
    Write-Host ''

    Write-NoxoraBoxTop -Title 'MAIN MENU' -Width $w
    Write-NoxoraBoxDivider -Width $w
    Write-NoxoraBoxRow -Content ' [1]  System Dashboard'              -ContentColor 'White' -Width $w
    Write-NoxoraBoxRow -Content ' [2]  CPU Performance Optimization'  -ContentColor 'White' -Width $w
    Write-NoxoraBoxRow -Content ' [3]  GPU Performance Optimization'  -ContentColor 'White' -Width $w
    Write-NoxoraBoxRow -Content ' [4]  Process Optimizer'             -ContentColor 'White' -Width $w
    Write-NoxoraBoxRow -Content ' [5]  System Debloater'              -ContentColor 'White' -Width $w
    Write-NoxoraBoxRow -Content ' [6]  Services Optimizer'            -ContentColor 'White' -Width $w
    Write-NoxoraBoxRow -Content ' [7]  Startup Optimizer'             -ContentColor 'White' -Width $w
    Write-NoxoraBoxRow -Content ' [8]  Network Optimizer'             -ContentColor 'White' -Width $w
    Write-NoxoraBoxRow -Content ' [9]  RAM and Memory Optimizer'      -ContentColor 'White' -Width $w
    Write-NoxoraBoxRow -Content ' [10] Smart Game Boost'              -ContentColor 'Cyan'  -Width $w
    Write-NoxoraBoxRow -Content ' [11] Thermal Analysis'              -ContentColor 'White' -Width $w
    Write-NoxoraBoxRow -Content ' [12] Security Center'               -ContentColor 'Yellow'-Width $w
    Write-NoxoraBoxRow -Content ' [13] Backup and Restore'            -ContentColor 'White' -Width $w
    Write-NoxoraBoxRow -Content ' [14] Reports'                       -ContentColor 'White' -Width $w
    Write-NoxoraBoxDivider -Width $w
    Write-NoxoraBoxRow -Content ' [L]  Logout'                        -ContentColor 'Yellow'-Width $w
    Write-NoxoraBoxRow -Content ' [0]  Exit'                          -ContentColor 'Red'   -Width $w
    Write-NoxoraBoxBottom -Width $w
    Write-Host ''

    $pad = Get-CenterPad -ContentWidth $w
    Write-Host "${pad}" -NoNewline
    Write-Host 'NOXORA:\SYSTEM> ' -ForegroundColor Cyan -NoNewline
    $selection = Read-Host
    return $selection.Trim()
}

#endregion

#region — Sub-Menu Template

function Show-NoxoraSubMenuHeader {
    <#
    .SYNOPSIS
        Displays a sub-menu header with title and back option reminder.
    .PARAMETER Title
        The sub-menu title.
    .PARAMETER Subtitle
        Optional subtitle line.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Title,
        [string]$Subtitle = ''
    )

    $w = $script:UIConfig.MenuWidth

    Write-Host ''
    Write-NoxoraBoxTop -Title $Title -Width $w
    if ($Subtitle) {
        Write-NoxoraBoxRow -Content " $Subtitle" -ContentColor 'DarkGray' -Width $w
        Write-NoxoraBoxDivider -Width $w
    }
}

function Show-NoxoraSubMenuFooter {
    <#
    .SYNOPSIS
        Closes a sub-menu box.
    #>
    [CmdletBinding()]
    param()

    $w = $script:UIConfig.MenuWidth
    Write-NoxoraBoxBottom -Width $w
    Write-Host ''
}

function Read-NoxoraMenuSelection {
    <#
    .SYNOPSIS
        Prompts for a menu selection and returns the trimmed input.
    .PARAMETER Prompt
        Custom prompt text. Defaults to 'NOXORA:\> Select option'.
    .OUTPUTS
        String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string]$Prompt = 'NOXORA:\> Select option'
    )

    $pad = Get-CenterPad -ContentWidth $script:UIConfig.MenuWidth
    Write-Host "${pad}" -NoNewline
    Write-Host "$Prompt : " -ForegroundColor Cyan -NoNewline
    return (Read-Host).Trim()
}

#endregion

#region — Action Progress Table

function Show-NoxoraProgressTable {
    <#
    .SYNOPSIS
        Displays a formatted progress table for action execution results.
    .PARAMETER Title
        Table title.
    .PARAMETER Actions
        Array of PSCustomObjects with: Status (string), Message (string).
    .PARAMETER Summary
        PSCustomObject with Applied, Skipped, Warnings, Failed, RollbackId fields.
    .PARAMETER FinalStatus
        Final status string: SUCCESS, COMPLETED WITH WARNINGS, FAILED.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Title,

        [Parameter(Mandatory)]
        [PSCustomObject[]]$Actions,

        [Parameter(Mandatory)]
        [PSCustomObject]$Summary,

        [ValidateSet('SUCCESS', 'COMPLETED WITH WARNINGS', 'FAILED', 'PARTIAL')]
        [string]$FinalStatus = 'SUCCESS'
    )

    $w = $script:UIConfig.MenuWidth

    Write-Host ''
    Write-NoxoraBoxTop -Title $Title -Width $w
    Write-NoxoraBoxDivider -Width $w

    foreach ($action in $Actions) {
        $icon  = if ($script:StatusIcons.ContainsKey($action.Status)) { $script:StatusIcons[$action.Status] } else { "[$($action.Status)]" }
        $color = if ($script:StatusColors.ContainsKey($action.Status)) { $script:StatusColors[$action.Status] } else { 'White' }
        $msg   = " $icon $($action.Message)"

        Write-NoxoraBoxRow -Content $msg -ContentColor $color -Width $w
    }

    Write-NoxoraBoxDivider -Width $w
    Write-NoxoraBoxRow -Content " Applied     : $($Summary.Applied)"      -ContentColor 'Green'    -Width $w
    Write-NoxoraBoxRow -Content " Skipped     : $($Summary.Skipped)"      -ContentColor 'DarkGray' -Width $w
    Write-NoxoraBoxRow -Content " Warnings    : $($Summary.Warnings)"     -ContentColor 'Yellow'   -Width $w
    Write-NoxoraBoxRow -Content " Failed      : $($Summary.Failed)"       -ContentColor $(if ($Summary.Failed -gt 0) {'Red'} else {'DarkGray'}) -Width $w
    Write-NoxoraBoxRow -Content " Rollback ID : $($Summary.RollbackId)"   -ContentColor 'DarkGray' -Width $w
    Write-NoxoraBoxDivider -Width $w

    $statusColor = switch ($FinalStatus) {
        'SUCCESS'                  { 'Green' }
        'COMPLETED WITH WARNINGS'  { 'Yellow' }
        'FAILED'                   { 'Red' }
        default                    { 'Yellow' }
    }

    Write-NoxoraBoxRow -Content " Status: $FinalStatus" -ContentColor $statusColor -Width $w
    Write-NoxoraBoxBottom -Width $w
    Write-Host ''
}

#endregion

#region — Confirmation Prompt

function Invoke-NoxoraConfirm {
    <#
    .SYNOPSIS
        Displays a confirmation prompt and returns $true if user confirms.
    .PARAMETER Title
        Title of the action requiring confirmation.
    .PARAMETER Description
        What the action will do.
    .PARAMETER Risk
        Risk level: Low, Medium, High, Critical.
    .PARAMETER RequiresRestart
        If $true, shows restart warning.
    .OUTPUTS
        Boolean — $true if confirmed.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Title,

        [string]$Description   = '',
        [ValidateSet('Low', 'Medium', 'High', 'Critical')]
        [string]$Risk          = 'Low',
        [switch]$RequiresRestart
    )

    $w = $script:UIConfig.MenuWidth

    $riskColor = switch ($Risk) {
        'Low'      { 'Green' }
        'Medium'   { 'Yellow' }
        'High'     { 'Red' }
        'Critical' { 'Red' }
        default    { 'White' }
    }

    Write-Host ''
    Write-NoxoraBoxTop -Title 'CONFIRMATION REQUIRED' -Width $w
    Write-NoxoraBoxRow -Content " Action : $Title"             -ContentColor 'White'    -Width $w
    if ($Description) {
        Write-NoxoraBoxRow -Content " Info   : $Description"   -ContentColor 'DarkGray' -Width $w
    }
    Write-NoxoraBoxRow -Content " Risk   : $Risk"              -ContentColor $riskColor -Width $w
    if ($RequiresRestart) {
        Write-NoxoraBoxRow -Content ' ! Requires system restart'  -ContentColor 'Yellow' -Width $w
    }
    Write-NoxoraBoxDivider -Width $w
    Write-NoxoraBoxRow -Content ' [Y] Yes — Apply this change'  -ContentColor 'Green'   -Width $w
    Write-NoxoraBoxRow -Content ' [N] No — Cancel'              -ContentColor 'Red'     -Width $w
    Write-NoxoraBoxBottom -Width $w

    $pad = Get-CenterPad -ContentWidth $w
    Write-Host "${pad}" -NoNewline
    Write-Host 'Confirm [Y/N]: ' -ForegroundColor Yellow -NoNewline
    $answer = (Read-Host).Trim().ToUpper()

    return ($answer -eq 'Y')
}

#endregion

#region — Info Display Helpers

function Write-NoxoraSection {
    <#
    .SYNOPSIS
        Writes a section header line.
    .PARAMETER Title
        Section title.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Title)

    Write-Host ''
    Write-Host "  ── $Title ──" -ForegroundColor Cyan
    Write-Host ''
}

function Write-NoxoraKeyValue {
    <#
    .SYNOPSIS
        Writes a key-value pair with aligned formatting.
    .PARAMETER Key
        Label text.
    .PARAMETER Value
        Value text.
    .PARAMETER ValueColor
        Color for the value.
    .PARAMETER KeyWidth
        Width to pad the key to (default 20).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$Value,
        [string]$ValueColor = 'White',
        [int]$KeyWidth      = 20
    )

    $pad     = Get-CenterPad -ContentWidth ($KeyWidth + 30)
    $keyStr  = "  $($Key.PadRight($KeyWidth)): "

    Write-Host "${pad}$keyStr" -ForegroundColor DarkGray -NoNewline
    Write-Host $Value -ForegroundColor $ValueColor
}

function Show-NoxoraContinuePrompt {
    <#
    .SYNOPSIS
        Displays a "Press Enter to continue" prompt.
    .PARAMETER Message
        Custom message. Defaults to standard.
    #>
    [CmdletBinding()]
    param([string]$Message = 'Press Enter to continue...')

    $pad = Get-CenterPad -ContentWidth $script:UIConfig.MenuWidth
    Write-Host ''
    Write-Host "${pad}  $Message" -ForegroundColor DarkGray
    $null = Read-Host
}

function Show-NoxoraErrorMessage {
    <#
    .SYNOPSIS
        Displays a formatted error message box.
    .PARAMETER Title
        Error title.
    .PARAMETER Message
        Error description.
    #>
    [CmdletBinding()]
    param(
        [string]$Title   = 'ERROR',
        [string]$Message = 'An unexpected error occurred.'
    )

    $w = $script:UIConfig.MenuWidth
    Write-Host ''
    Write-NoxoraBoxTop -Title "! $Title" -Width $w
    Write-NoxoraBoxRow -Content " $Message" -ContentColor 'Red' -Width $w
    Write-NoxoraBoxBottom -Width $w
    Write-Host ''
}

function Show-NoxoraNotAvailableMessage {
    <#
    .SYNOPSIS
        Displays a "feature not yet available" placeholder for Phase 2+ features.
    .PARAMETER FeatureName
        Name of the feature.
    .PARAMETER Phase
        Phase in which this feature will be implemented.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FeatureName,
        [string]$Phase = '2'
    )

    $w = $script:UIConfig.MenuWidth
    Write-Host ''
    Write-NoxoraBoxTop -Title 'COMING SOON' -Width $w
    Write-NoxoraBoxRow -Content " Feature  : $FeatureName"  -ContentColor 'White'   -Width $w
    Write-NoxoraBoxRow -Content " Status   : Planned Phase $Phase" -ContentColor 'Yellow' -Width $w
    Write-NoxoraBoxRow -Content '' -Width $w
    Write-NoxoraBoxRow -Content ' This feature will be available in a future update.' -ContentColor 'DarkGray' -Width $w
    Write-NoxoraBoxBottom -Width $w
}

#endregion

Export-ModuleMember -Function @(
    'Initialize-NoxoraUI',
    'Get-TerminalWidth',
    'Test-SimpleMode',
    'Get-CenterPad',
    'Write-NoxoraColor',
    'Write-NoxoraPrimary',
    'Write-NoxoraSuccess',
    'Write-NoxoraWarning',
    'Write-NoxoraError',
    'Write-NoxoraDim',
    'Write-NoxoraAccent',
    'Show-NoxoraBanner',
    'Write-NoxoraBoxTop',
    'Write-NoxoraBoxDivider',
    'Write-NoxoraBoxRow',
    'Write-NoxoraBoxBottom',
    'Write-NoxoraEmptyRow',
    'Show-NoxoraAuthScreen',
    'Show-NoxoraMainMenu',
    'Show-NoxoraSubMenuHeader',
    'Show-NoxoraSubMenuFooter',
    'Read-NoxoraMenuSelection',
    'Show-NoxoraProgressTable',
    'Invoke-NoxoraConfirm',
    'Write-NoxoraSection',
    'Write-NoxoraKeyValue',
    'Show-NoxoraContinuePrompt',
    'Show-NoxoraErrorMessage',
    'Show-NoxoraNotAvailableMessage'
)
