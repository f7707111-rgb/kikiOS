#Requires -Version 5.1
<#
.SYNOPSIS
    KikiOS PCBOOST Edition installer.

.DESCRIPTION
    Claude Code style terminal installer: downloads portable 7-Zip,
    downloads the tweaks archive from GitHub Releases, extracts it to the
    desktop and removes temporary files.

    24-bit colors and the mascot animation require Windows 10+ (VT
    sequences). Legacy consoles fall back to basic colors and a text spinner.
#>

Set-StrictMode -Version 2.0

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

 $script:Config = @{
    WindowTitle       = 'KikiOS Installer'
    ProductName       = 'KikiOS'
    Edition           = 'PCBOOST Edition'
    Version           = '2.0.0'
    SourceRepo        = '7707111-rgb/kikiOS'
    SevenZipUrl       = 'https://www.7-zip.org/a/7zr.exe'
    # TODO: paste the full release asset URL (it was truncated in the source script).
    ArchiveUrl        = 'https://github.com/7707111-rgb/kikiOS/releases/download/v1.0/pcboost.7z'
    ArchiveName       = 'pcboost.7z'
    DestinationFolder = 'KikiOS Tweaks'
    AccessCodeEncoded = 'TE5LP2c7KFlrcyRfVzQw'
    MaxAccessAttempts = 3
}

# Palette: hex values for hosts with 24-bit color support, console color
# names as legacy fallback.
 $script:HexColors = @{
    Accent = 'D97757'   # Claude terracotta
    Text   = 'F0EEE4'
    Dim    = '9B968C'
    Faint  = '5F5B53'
    Error  = 'E5484D'
}

 $script:FallbackColors = @{
    Accent = 'DarkYellow'
    Text   = 'White'
    Dim    = 'Gray'
    Faint  = 'DarkGray'
    Error  = 'Red'
}

 $script:Esc           = [char]27
 $script:AnsiColors    = @{}
 $script:AnsiReset     = ''
 $script:AnsiClearLine = ''
 $script:VtEnabled     = $false

 $script:Steps = @(
    [pscustomobject]@{ Label = '7-Zip';   Status = 'Waiting' }
    [pscustomobject]@{ Label = 'Archive'; Status = 'Waiting' }
    [pscustomobject]@{ Label = 'Unpack';  Status = 'Waiting' }
    [pscustomobject]@{ Label = 'Cleanup'; Status = 'Waiting' }
)

 $script:StatusLabels = @{
    Waiting = 'waiting'
    Running = 'running'
    Done    = 'done'
    Failed  = 'error'
}

 $script:StatusColors = @{
    Waiting = 'Faint'
    Running = 'Accent'
    Done    = 'Text'
    Failed  = 'Error'
}

 $script:ActivityLog      = [System.Collections.Generic.List[object]]::new()
 $script:CurrentStepIndex = -1

 $script:SpinnerFrames   = @('⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏')
 $script:MascotCycle     = @('Ground', 'Air', 'Ground', 'Air', 'Ground', 'Blink', 'Air', 'Ground')
 $script:AnimationHeight = 8   # 7 mascot rows + 1 status row
 $script:AnimationIndent = '    '

# ---------------------------------------------------------------------------
# Console initialization
# ---------------------------------------------------------------------------

function ConvertTo-AnsiForeground {
    param([Parameter(Mandatory)][ValidatePattern('^[0-9A-Fa-f]{6}$')][string]$Hex)

    $red   = [Convert]::ToInt32($Hex.Substring(0, 2), 16)
    $green = [Convert]::ToInt32($Hex.Substring(2, 2), 16)
    $blue  = [Convert]::ToInt32($Hex.Substring(4, 2), 16)
    return ('{0}[38;2;{1};{2};{3}m' -f $script:Esc, $red, $green, $blue)
}

function Enable-VirtualTerminal {
    $signature = @'
[DllImport("kernel32.dll", SetLastError = true)]
public static extern IntPtr GetStdHandle(int nStdHandle);

[DllImport("kernel32.dll", SetLastError = true)]
public static extern bool GetConsoleMode(IntPtr hConsoleHandle, out int lpMode);

[DllImport("kernel32.dll", SetLastError = true)]
public static extern bool SetConsoleMode(IntPtr hConsoleHandle, int dwMode);
'@

    try {
        $native = Add-Type -MemberDefinition $signature -Name 'NativeConsoleApi' -Namespace 'KikiOS.Installer' -PassThru
        $handle = $native::GetStdHandle(-11)
        [int]$mode = 0
        if (-not $native::GetConsoleMode($handle, [ref]$mode)) {
            return $false
        }
        return [bool]$native::SetConsoleMode($handle, $mode -bor 0x0004)
    }
    catch [System.ComponentModel.Win32Exception] {
        return $false
    }
    catch [System.InvalidOperationException] {
        # Compiler unavailable for Add-Type on hardened hosts.
        return $false
    }
    catch [System.Exception] {
        # Virtual terminal support is best-effort; legacy path stays usable.
        return $false
    }
}

function Initialize-Console {
    try {
        $Host.UI.RawUI.WindowTitle = $script:Config.WindowTitle
    }
    catch [System.Management.Automation.SetValueInvocationException] {
        # Host forbids title changes; not critical.
    }

    try {
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    }
    catch [System.IO.IOException] {
        # Legacy host without codepage switching; ASCII output stays readable.
    }

    $script:VtEnabled = Enable-VirtualTerminal

    if ($script:VtEnabled) {
        foreach ($name in $script:HexColors.Keys) {
            $script:AnsiColors[$name] = ConvertTo-AnsiForeground -Hex $script:HexColors[$name]
        }
        $script:AnsiReset     = ('{0}[0m' -f $script:Esc)
        $script:AnsiClearLine = ('{0}[2K' -f $script:Esc)
    }
}

function Test-ConsoleWidth {
    try {
        return ([Console]::WindowWidth -ge 70)
    }
    catch [System.IO.IOException] {
        # No interactive console attached (e.g. ISE); skip the check.
        return $true
    }
}

# ---------------------------------------------------------------------------
# Output layer
# ---------------------------------------------------------------------------

function New-Segment {
    param(
        [Parameter(Mandatory)][string]$Text,
        [ValidateSet('Accent', 'Text', 'Dim', 'Faint', 'Error')][string]$Color = 'Text'
    )
    return [pscustomobject]@{ Text = $Text; Color = $Color }
}

function Write-Segment {
    param([Parameter(Mandatory)][pscustomobject]$Segment)

    if ($script:VtEnabled) {
        Write-Host -NoNewline ($script:AnsiColors[$Segment.Color] + $Segment.Text + $script:AnsiReset)
    }
    else {
        Write-Host -NoNewline $Segment.Text -ForegroundColor $script:FallbackColors[$Segment.Color]
    }
}

function Write-Segments {
    param([pscustomobject[]]$Segments, [switch]$NoNewline)

    foreach ($segment in $Segments) { Write-Segment -Segment $segment }
    if (-not $NoNewline) { Write-Host '' }
}

function Add-RowPadding {
    param([pscustomobject[]]$Segments, [Parameter(Mandatory)][int]$Width)

    $visibleLength = 0
    foreach ($segment in $Segments) { $visibleLength += $segment.Text.Length }

    if ($visibleLength -ge $Width) { return $Segments }
    return $Segments + (New-Segment (' ' * ($Width - $visibleLength)))
}

function Format-Padded {
    param([Parameter(Mandatory)][string]$Text, [Parameter(Mandatory)][int]$Width)

    if ($Text.Length -ge $Width) { return $Text.Substring(0, $Width) }
    return $Text.PadRight($Width)
}

# ---------------------------------------------------------------------------
# Mascot
# ---------------------------------------------------------------------------

function Get-MascotBody {
    return @(
        ('  ' + ('▄' * 12) + '  ')
        ('█' * 16)
        '████  ████  ████'
        '████  ████  ████'
        ('█' * 16)
        ' ██  ██  ██  ██ '
    )
}

function Get-MascotFrame {
    param([Parameter(Mandatory)][ValidateSet('Ground', 'Air', 'Blink')][string]$Name)

    $body = Get-MascotBody

    switch ($Name) {
        'Air'   { return ($body + @('')) }
        'Blink' {
            $body[3] = '████▄▄████▄▄████'
            return (@('') + $body)
        }
        default { return (@('') + $body) }
    }
}

# ---------------------------------------------------------------------------
# Dashboard
# ---------------------------------------------------------------------------

function New-PanelTop {
    param([Parameter(Mandatory)][string]$Title, [Parameter(Mandatory)][int]$Width)

    $dashCount = $Width - $Title.Length - 5
    return @(
        (New-Segment ('╭─ {0} ' -f $Title) 'Accent'),
        (New-Segment ('─' * $dashCount) 'Accent'),
        (New-Segment '╮' 'Accent')
    )
}

function New-PanelBottom {
    param([Parameter(Mandatory)][int]$Width)
    return @((New-Segment ('╰' + ('─' * ($Width - 2)) + '╯') 'Accent'))
}

function New-StepRow {
    param([Parameter(Mandatory)][pscustomobject]$Step, [Parameter(Mandatory)][int]$Width)

    return @(
        (New-Segment '│ ' 'Accent'),
        (New-Segment (Format-Padded -Text $Step.Label -Width 12) 'Text'),
        (New-Segment ($script:StatusLabels[$Step.Status].PadLeft($Width - 16)) $script:StatusColors[$Step.Status]),
        (New-Segment ' │' 'Accent')
    )
}

function New-InfoRow {
    param([Parameter(Mandatory)][string]$Text, [Parameter(Mandatory)][int]$Width)

    return @(
        (New-Segment '│ ' 'Accent'),
        (New-Segment (Format-Padded -Text $Text -Width ($Width - 4)) 'Dim'),
        (New-Segment ' │' 'Accent')
    )
}

function New-DashboardLines {
    $boxInnerWidth = 62
    $leftWidth     = 26
    $rightWidth    = 30
    $rowCount      = 13

    $title           = ('{0} · {1} v{2}' -f $script:Config.ProductName, $script:Config.Edition, $script:Config.Version)
    $borderDashCount = $boxInnerWidth - $title.Length - 3

    $topRow = @(
        (New-Segment '╭─ ' 'Accent'),
        (New-Segment $title 'Accent'),
        (New-Segment (' ' + ('─' * $borderDashCount)) 'Accent'),
        (New-Segment '╮' 'Accent')
    )

    $bottomRow = @((New-Segment ('╰' + ('─' * $boxInnerWidth) + '╯') 'Accent'))

    # Left column: greeting, mascot, machine info.
    $userName = $env:USERNAME
    if ([string]::IsNullOrWhiteSpace($userName)) { $userName = 'unknown' }
    $welcome = if ($userName.Length -le 9) { 'Welcome back, {0}!' -f $userName } else { 'Welcome back!' }

    $leftLines = @()
    $leftLines += ,@()
    $leftLines += ,@(New-Segment ('  ' + $welcome) 'Text')
    $leftLines += ,@()
    foreach ($line in (Get-MascotBody)) {
        $leftLines += ,@(New-Segment ('     ' + $line) 'Accent')
    }
    $leftLines += ,@()
    $leftLines += ,@(New-Segment ('  User:  ' + $userName) 'Dim')
    $leftLines += ,@(New-Segment ('  PC:    ' + $env:COMPUTERNAME) 'Dim')
    $leftLines += ,@()

    # Right column: setup steps and info panels.
    $rightLines = @()
    $rightLines += ,@()
    $rightLines += ,(New-PanelTop -Title 'Setup' -Width $rightWidth)
    foreach ($step in $script:Steps) {
        $rightLines += ,(New-StepRow -Step $step -Width $rightWidth)
    }
    $rightLines += ,(New-PanelBottom -Width $rightWidth)
    $rightLines += ,@()
    $rightLines += ,(New-PanelTop -Title 'Info' -Width $rightWidth)

    $infoLines = @(
        ('v{0} · {1}' -f $script:Config.Version, $script:Config.Edition)
        ('· {0}' -f $script:Config.SourceRepo)
        ('Desktop\{0}' -f $script:Config.DestinationFolder)
    )
    foreach ($infoLine in $infoLines) {
        $rightLines += ,(New-InfoRow -Text $infoLine -Width $rightWidth)
    }
    $rightLines += ,(New-PanelBottom -Width $rightWidth)

    $rows = @()
    $edgeLeft  = @((New-Segment '│' 'Accent'), (New-Segment '  ' 'Text'))
    $gap       = @((New-Segment '  ' 'Text'))
    $edgeRight = @((New-Segment '  ' 'Text'), (New-Segment '│' 'Accent'))

    for ($i = 0; $i -lt $rowCount; $i++) {
        $leftCell  = Add-RowPadding -Segments $leftLines[$i]  -Width $leftWidth
        $rightCell = Add-RowPadding -Segments $rightLines[$i] -Width $rightWidth
        $rows += ,($edgeLeft + $leftCell + $gap + $rightCell + $gap + $edgeRight)
    }

    $allRows = @($topRow) + $rows + @($bottomRow)
    return ,$allRows
}

function Show-Dashboard {
    Clear-Host
    Write-Host ''

    foreach ($row in (New-DashboardLines)) { Write-Segments -Segments $row }
    Write-Host ''

    foreach ($entry in $script:ActivityLog) { Write-Segments -Segments $entry }
}

function Set-StepStatus {
    param(
        [Parameter(Mandatory)][ValidateRange(0, 3)][int]$Index,
        [Parameter(Mandatory)][ValidateSet('Waiting', 'Running', 'Done', 'Failed')][string]$Status,
        [switch]$SkipRender
    )

    $script:Steps[$Index].Status = $Status
    $script:CurrentStepIndex     = $Index
    if (-not $SkipRender) { Show-Dashboard }
}

# ---------------------------------------------------------------------------
# Animated work block (mascot hop + spinner)
# ---------------------------------------------------------------------------

function Write-AnimationFrame {
    param(
        [Parameter(Mandatory)][string[]]$MascotLines,
        [Parameter(Mandatory)][string]$SpinnerChar,
        [Parameter(Mandatory)][string]$Activity,
        [Parameter(Mandatory)][bool]$IsFirstRender
    )

    if ($script:VtEnabled) {
        if (-not $IsFirstRender) {
            [Console]::Write(('{0}[{1}A' -f $script:Esc, $script:AnimationHeight))
        }
        foreach ($line in $MascotLines) {
            [Console]::Write("`r" + $script:AnsiClearLine + $script:AnsiColors['Accent'] + $script:AnimationIndent + $line + $script:AnsiReset + "`r`n")
        }
        [Console]::Write("`r" + $script:AnsiClearLine + $script:AnsiColors['Accent'] + $script:AnimationIndent + $SpinnerChar + ' ' + $script:AnsiColors['Text'] + $Activity + $script:AnsiReset)
    }
    else {
        Write-Host -NoNewline ("`r{0}{1} {2}   " -f $script:AnimationIndent, $SpinnerChar, $Activity) -ForegroundColor $script:FallbackColors['Accent']
    }
}

function Clear-AnimationBlock {
    if (-not $script:VtEnabled) { return }

    [Console]::Write(('{0}[{1}A' -f $script:Esc, $script:AnimationHeight))
    for ($i = 0; $i -lt $script:AnimationHeight - 1; $i++) {
        [Console]::Write("`r" + $script:AnsiClearLine + "`r`n")
    }
    [Console]::Write("`r" + $script:AnsiClearLine)
}

function Wait-AnimatedWork {
    param(
        [Parameter(Mandatory)][ScriptBlock]$IsBusy,
        [Parameter(Mandatory)][string]$Activity
    )

    $frameIndex    = 0
    $isFirstRender = $true
    $hasRendered   = $false

    while (& $IsBusy) {
        $frameName   = $script:MascotCycle[$frameIndex % $script:MascotCycle.Count]
        $spinnerChar = $script:SpinnerFrames[$frameIndex % $script:SpinnerFrames.Count]

        Write-AnimationFrame -MascotLines (Get-MascotFrame -Name $frameName) `
            -SpinnerChar $spinnerChar -Activity $Activity -IsFirstRender $isFirstRender

        $isFirstRender = $false
        $hasRendered   = $true
        $frameIndex++
        Start-Sleep -Milliseconds 130
    }

    if ($hasRendered) { Clear-AnimationBlock }
}

# ---------------------------------------------------------------------------
# Operations
# ---------------------------------------------------------------------------

function Format-StepDuration {
    param([Parameter(Mandatory)][System.Diagnostics.Stopwatch]$Stopwatch)

    $seconds = $Stopwatch.Elapsed.TotalSeconds
    return ('{0}s' -f $seconds.ToString('F1', [System.Globalization.CultureInfo]::InvariantCulture))
}

function Invoke-DownloadStep {
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$DestinationPath,
        [Parameter(Mandatory)][string]$Activity
    )

    $client    = New-Object System.Net.WebClient
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $task = $client.DownloadFileTaskAsync($Url, $DestinationPath)
        Wait-AnimatedWork -IsBusy { -not $task.IsCompleted } -Activity $Activity

        if ($task.IsFaulted) { throw $task.Exception.InnerException }
        if ($task.IsCanceled) { throw [System.OperationCanceledException]::new('Download was cancelled.') }
    }
    finally {
        $client.Dispose()
        $stopwatch.Stop()
    }

    return (Format-StepDuration -Stopwatch $stopwatch)
}

function Invoke-ExtractionStep {
    param(
        [Parameter(Mandatory)][string]$SevenZipPath,
        [Parameter(Mandatory)][string]$ArchivePath,
        [Parameter(Mandatory)][string]$DestinationPath,
        [Parameter(Mandatory)][string]$LogDirectory,
        [Parameter(Mandatory)][string]$Activity
    )

    if (-not (Test-Path -LiteralPath $DestinationPath)) {
        New-Item -ItemType Directory -Path $DestinationPath -Force | Out-Null
    }

    # Redirect 7-Zip output to files so it does not corrupt the animation.
    $arguments     = 'x "{0}" -o"{1}" -y' -f $ArchivePath, $DestinationPath
    $stdoutLogPath = Join-Path $LogDirectory '7z-stdout.log'
    $stderrLogPath = Join-Path $LogDirectory '7z-stderr.log'

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $process = Start-Process -FilePath $SevenZipPath -ArgumentList $arguments `
        -NoNewWindow -PassThru `
        -RedirectStandardOutput $stdoutLogPath -RedirectStandardError $stderrLogPath

    Wait-AnimatedWork -IsBusy { -not $process.HasExited } -Activity $Activity
    $stopwatch.Stop()

    if ($process.ExitCode -ne 0) {
        throw ('7-Zip exited with code {0}' -f $process.ExitCode)
    }

    return (Format-StepDuration -Stopwatch $stopwatch)
}

# ---------------------------------------------------------------------------
# Access code
# ---------------------------------------------------------------------------

function ConvertFrom-SecureStringToPlain {
    param([Parameter(Mandatory)][System.Security.SecureString]$SecureString)

    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
    try {
        return [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
    }
    finally {
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

function Test-AccessCode {
    param([Parameter(Mandatory)][string]$Code)

    $expected = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($script:Config.AccessCodeEncoded))
    return ($Code -ceq $expected)
}

function Request-AccessCode {
    param([Parameter(Mandatory)][ValidateRange(1, 10)][int]$MaxAttempts)

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        Show-Dashboard

        Write-Segments -Segments @(
            (New-Segment '  > ' 'Text'),
            (New-Segment 'enter access code ' 'Dim'),
            (New-Segment ('({0} left)' -f ($MaxAttempts - $attempt + 1)) 'Faint')
        ) -NoNewline

        $secureCode = Read-Host -AsSecureString
        $plainCode  = ConvertFrom-SecureStringToPlain -SecureString $secureCode

        if (Test-AccessCode -Code $plainCode) {
            Write-Segments -Segments @(
                (New-Segment '  ✔ ' 'Accent'),
                (New-Segment 'access granted' 'Text')
            )
            Start-Sleep -Milliseconds 700
            return $true
        }

        $attemptsLeft = $MaxAttempts - $attempt
        $wrongText = if ($attemptsLeft -gt 0) { 'wrong code, {0} attempts left' -f $attemptsLeft } else { 'wrong code' }
        Write-Segments -Segments @(
            (New-Segment '  ✖ ' 'Error'),
            (New-Segment $wrongText 'Error')
        )
    }

    return $false
}

# ---------------------------------------------------------------------------
# Activity log
# ---------------------------------------------------------------------------

function Add-ActivityEntry {
    param([Parameter(Mandatory)][pscustomobject[]]$Segments)

    $script:ActivityLog.Add($Segments)
    Show-Dashboard
}

function Add-SuccessEntry {
    param([Parameter(Mandatory)][string]$Message, [AllowEmptyString()][string]$Duration = '')

    $segments = [System.Collections.Generic.List[pscustomobject]]::new()
    $segments.Add((New-Segment '  ✔ ' 'Accent'))
    $segments.Add((New-Segment $Message 'Text'))
    if ($Duration -ne '') {
        $segments.Add((New-Segment (' · {0}' -f $Duration) 'Faint'))
    }
    Add-ActivityEntry -Segments $segments.ToArray()
}

function Add-SummaryEntry {
    param([Parameter(Mandatory)][string]$Message)

    Add-ActivityEntry -Segments @(
        (New-Segment '  ✦ ' 'Accent'),
        (New-Segment $Message 'Text')
    )
}

function Wait-ExitKey {
    Write-Segments -Segments @(
        (New-Segment '  > ' 'Text'),
        (New-Segment 'press Enter to exit' 'Dim')
    ) -NoNewline
    [void][System.Console]::ReadLine()
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

function Invoke-Installer {
    Initialize-Console

    if (-not (Test-ConsoleWidth)) {
        Add-ActivityEntry -Segments @(
            (New-Segment '  !  ' 'Accent'),
            (New-Segment 'console is too narrow, 70+ columns recommended' 'Dim')
        )
    }

    if (-not (Request-AccessCode -MaxAttempts $script:Config.MaxAccessAttempts)) {
        Show-Dashboard
        Write-Segments -Segments @(
            (New-Segment '  ✖ ' 'Error'),
            (New-Segment 'access denied' 'Error')
        )
        Wait-ExitKey
        exit 1
    }

    # GitHub rejects legacy TLS defaults on Windows PowerShell 5.1.
    [System.Net.ServicePointManager]::SecurityProtocol =
        [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

    $tempRoot        = Join-Path ([System.IO.Path]::GetTempPath()) ('kikios_' + [System.Guid]::NewGuid().ToString('N').Substring(0, 8))
    $sevenZipPath    = Join-Path $tempRoot '7zr.exe'
    $archivePath     = Join-Path $tempRoot $script:Config.ArchiveName
    $destinationPath = Join-Path ([Environment]::GetFolderPath('Desktop')) $script:Config.DestinationFolder

    try {
        New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

        Set-StepStatus -Index 0 -Status 'Running'
        $sevenZipDuration = Invoke-DownloadStep -Url $script:Config.SevenZipUrl -DestinationPath $sevenZipPath -Activity 'Downloading 7-Zip...'
        Set-StepStatus -Index 0 -Status 'Done' -SkipRender
        Add-SuccessEntry -Message '7-Zip downloaded' -Duration $sevenZipDuration

        Set-StepStatus -Index 1 -Status 'Running'
        $archiveDuration = Invoke-DownloadStep -Url $script:Config.ArchiveUrl -DestinationPath $archivePath -Activity 'Downloading tweaks archive...'
        Set-StepStatus -Index 1 -Status 'Done' -SkipRender
        Add-SuccessEntry -Message 'Tweaks archive downloaded' -Duration $archiveDuration

        Set-StepStatus -Index 2 -Status 'Running'
        $extractDuration = Invoke-ExtractionStep -SevenZipPath $sevenZipPath -ArchivePath $archivePath -DestinationPath $destinationPath -LogDirectory $tempRoot -Activity 'Unpacking tweaks...'
        Set-StepStatus -Index 2 -Status 'Done' -SkipRender
        Add-SuccessEntry -Message ('Unpacked to Desktop\{0}' -f $script:Config.DestinationFolder) -Duration $extractDuration

        Set-StepStatus -Index 3 -Status 'Running'
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        Set-StepStatus -Index 3 -Status 'Done' -SkipRender
        Add-SuccessEntry -Message 'Temporary files removed'
    }
    catch {
        if ($script:CurrentStepIndex -ge 0) {
            Set-StepStatus -Index $script:CurrentStepIndex -Status 'Failed' -SkipRender
        }
        Add-ActivityEntry -Segments @(
            (New-Segment '  ✖ ' 'Error'),
            (New-Segment $_.Exception.Message 'Error')
        )
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        Wait-ExitKey
        exit 1
    }

    Add-SummaryEntry -Message ('KikiOS is ready: {0}' -f $destinationPath)
    Wait-ExitKey
    exit 0
}

Invoke-Installer
