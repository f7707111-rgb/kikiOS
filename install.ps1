Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- configuration ---------------------------------------------------------

$script:Config = @{
    Title            = 'KikiOS Installer'
    PanelLabel       = 'KikiOS Tweaks v2.0'
    ExtractorUri     = 'https://www.7-zip.org/a/7zr.exe'
    ArchiveUri       = 'https://github.com/f7707111-rgb/kikiOS/releases/download/v1.0/PCBOOST.7z'
    DestinationName  = 'KikiOS Tweaks'
    AccessCodeBase64 = 'TE5LP2c7KFlrcyRfVzQw'
    MaxCodeAttempts  = 3
}

$script:Esc = [char]27

$script:Palette = @{
    Accent    = '217;119;87'
    AccentDim = '150;84;62'
    Text      = '235;229;222'
    Muted     = '134;134;134'
    Success   = '132;186;120'
    Danger    = '214;96;96'
}

$script:Layout = @{
    LeftWidth   = 28
    RightWidth  = 33
    StageHeight = 8
    StageIndent = 4
}

# Mascot sprite: identical silhouette in every pose so the hop reads as motion.
$script:MascotFrames = @{
    Idle  = @(
        ' ▄███████████▄ ',
        ' ███▀▀▀▀▀▀▀███ ',
        ' ██  █   █  ██ ',
        ' ███▄▄▄▄▄▄▄███ ',
        ' ▀▀█▀▀   ▀▀█▀▀ '
    )
    Blink = @(
        ' ▄███████████▄ ',
        ' ███▀▀▀▀▀▀▀███ ',
        ' ██  ▄   ▄  ██ ',
        ' ███▄▄▄▄▄▄▄███ ',
        ' ▀▀█▀▀   ▀▀█▀▀ '
    )
    Hop   = @(
        ' ▄███████████▄ ',
        ' ███▀▀▀▀▀▀▀███ ',
        ' ██  █   █  ██ ',
        ' ███▄▄▄▄▄▄▄███ ',
        ' ▀█▀▀     ▀▀█▀ '
    )
    Happy = @(
        ' ▄███████████▄ ',
        ' ███▀▀▀▀▀▀▀███ ',
        ' ██  ▀   ▀  ██ ',
        ' ███▄▄▄▄▄▄▄███ ',
        ' ▀█▀▀     ▀▀█▀ '
    )
}

$script:HopPattern = @(0, 1, 2, 2, 1, 0, 0, 0)

# --- console primitives ----------------------------------------------------

function Enable-VirtualTerminal {
    try {
        if (-not ('KikiOS.NativeConsole' -as [type])) {
            Add-Type -Namespace 'KikiOS' -Name 'NativeConsole' -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError = true)]
public static extern IntPtr GetStdHandle(int nStdHandle);

[DllImport("kernel32.dll", SetLastError = true)]
public static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);

[DllImport("kernel32.dll", SetLastError = true)]
public static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);
'@
        }

        $handle = [KikiOS.NativeConsole]::GetStdHandle(-11)
        $mode = [uint32]0
        if ([KikiOS.NativeConsole]::GetConsoleMode($handle, [ref]$mode)) {
            [void][KikiOS.NativeConsole]::SetConsoleMode($handle, $mode -bor 0x0004)
        }
    }
    catch [System.Exception] {
        # Legacy hosts without VT support still print the layout, only colors degrade.
    }
}

function Set-CursorVisible {
    param([bool]$Visible)

    try {
        [System.Console]::CursorVisible = $Visible
    }
    catch [System.Exception] {
        # Redirected hosts do not expose a cursor.
    }
}

function Initialize-Console {
    $Host.UI.RawUI.WindowTitle = $script:Config.Title

    try {
        [System.Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        & chcp.com 65001 | Out-Null
    }
    catch [System.Exception] {
        # Encoding switch is best effort.
    }

    Enable-VirtualTerminal
    Clear-Host
    Set-CursorVisible -Visible $false
}

function Format-Styled {
    param(
        [string]$Text,
        [string]$ColorKey = 'Text'
    )

    "$($script:Esc)[38;2;$($script:Palette[$ColorKey])m$Text$($script:Esc)[0m"
}

function Write-Styled {
    param(
        [string]$Text = '',
        [string]$ColorKey = 'Text',
        [switch]$NoNewline
    )

    if ($NoNewline) {
        Write-Host -NoNewline (Format-Styled -Text $Text -ColorKey $ColorKey)
        return
    }

    Write-Host (Format-Styled -Text $Text -ColorKey $ColorKey)
}

function Format-Centered {
    param(
        [string]$Text,
        [int]$Width
    )

    if ($Text.Length -ge $Width) {
        return $Text.Substring(0, $Width)
    }

    $leftPad = [math]::Floor(($Width - $Text.Length) / 2)
    (' ' * $leftPad) + $Text + (' ' * ($Width - $Text.Length - $leftPad))
}

function New-Cell {
    param(
        [string]$Text = '',
        [string]$ColorKey = 'Text'
    )

    [pscustomobject]@{ Text = $Text; ColorKey = $ColorKey; Kind = 'Text' }
}

function New-DividerCell {
    [pscustomobject]@{ Text = ''; ColorKey = 'AccentDim'; Kind = 'Divider' }
}

# --- panel rendering -------------------------------------------------------

function Write-PanelTop {
    param([string]$Label)

    $leftSpan = $script:Layout.LeftWidth + 2
    $rightSpan = $script:Layout.RightWidth + 2
    $fillLength = [math]::Max(0, $leftSpan - ("─ $Label ").Length)

    Write-Styled -Text '╭─ ' -ColorKey 'AccentDim' -NoNewline
    Write-Styled -Text $Label -ColorKey 'Accent' -NoNewline
    Write-Styled -Text (' ' + ('─' * $fillLength)) -ColorKey 'AccentDim' -NoNewline
    Write-Styled -Text ('┬' + ('─' * $rightSpan) + '╮') -ColorKey 'AccentDim'
}

function Write-PanelBottom {
    $border = '╰' + ('─' * ($script:Layout.LeftWidth + 2)) + '┴' + ('─' * ($script:Layout.RightWidth + 2)) + '╯'
    Write-Styled -Text $border -ColorKey 'AccentDim'
}

function Write-PanelRow {
    param(
        [pscustomobject]$Left,
        [pscustomobject]$Right
    )

    $middleBorder = if ($Right.Kind -eq 'Divider') { '├' } else { '│' }

    Write-Styled -Text '│ ' -ColorKey 'AccentDim' -NoNewline
    Write-Styled -Text $Left.Text.PadRight($script:Layout.LeftWidth) -ColorKey $Left.ColorKey -NoNewline
    Write-Styled -Text " $middleBorder " -ColorKey 'AccentDim' -NoNewline

    if ($Right.Kind -eq 'Divider') {
        Write-Styled -Text (('─' * ($script:Layout.RightWidth + 1)) + '┤') -ColorKey 'AccentDim'
        return
    }

    Write-Styled -Text $Right.Text.PadRight($script:Layout.RightWidth) -ColorKey $Right.ColorKey -NoNewline
    Write-Styled -Text ' │' -ColorKey 'AccentDim'
}

function Get-LeftColumn {
    param(
        [string]$UserName,
        [string]$DestinationPath
    )

    $width = $script:Layout.LeftWidth
    $rows = New-Object System.Collections.Generic.List[object]

    $rows.Add((New-Cell))
    $rows.Add((New-Cell -Text (Format-Centered -Text "Welcome back, $UserName!" -Width $width) -ColorKey 'Text'))
    $rows.Add((New-Cell))

    foreach ($spriteLine in $script:MascotFrames.Idle) {
        $rows.Add((New-Cell -Text (Format-Centered -Text $spriteLine -Width $width) -ColorKey 'Accent'))
    }

    $rows.Add((New-Cell))
    $rows.Add((New-Cell -Text (Format-Centered -Text 'PCBOOST Edition' -Width $width) -ColorKey 'Muted'))
    $rows.Add((New-Cell -Text (Format-Centered -Text $DestinationPath -Width $width) -ColorKey 'Muted'))

    $rows
}

function Get-RightColumn {
    param(
        [string]$UserName,
        [string]$MachineName
    )

    $rows = New-Object System.Collections.Generic.List[object]

    $rows.Add((New-Cell -Text 'What happens next' -ColorKey 'Accent'))
    $rows.Add((New-Cell -Text '1  Fetch portable 7-Zip' -ColorKey 'Text'))
    $rows.Add((New-Cell -Text '2  Fetch the tweak archive' -ColorKey 'Text'))
    $rows.Add((New-Cell -Text '3  Unpack onto your Desktop' -ColorKey 'Text'))
    $rows.Add((New-Cell -Text '4  Sweep every temporary file' -ColorKey 'Muted'))
    $rows.Add((New-DividerCell))
    $rows.Add((New-Cell -Text 'This machine' -ColorKey 'Accent'))
    $rows.Add((New-Cell -Text ('User      ' + $UserName) -ColorKey 'Text'))
    $rows.Add((New-Cell -Text ('Computer  ' + $MachineName) -ColorKey 'Text'))
    $rows.Add((New-Cell -Text ('Shell     PowerShell ' + $PSVersionTable.PSVersion) -ColorKey 'Muted'))
    $rows.Add((New-Cell -Text ('Target    Desktop\' + $script:Config.DestinationName) -ColorKey 'Muted'))

    $rows
}

function Show-Dashboard {
    param(
        [string]$UserName,
        [string]$MachineName,
        [string]$DestinationPath
    )

    $left = Get-LeftColumn -UserName $UserName -DestinationPath $DestinationPath
    $right = Get-RightColumn -UserName $UserName -MachineName $MachineName
    $rowCount = [math]::Max($left.Count, $right.Count)

    Write-Host ''
    Write-PanelTop -Label $script:Config.PanelLabel

    for ($index = 0; $index -lt $rowCount; $index++) {
        $leftCell = if ($index -lt $left.Count) { $left[$index] } else { New-Cell }
        $rightCell = if ($index -lt $right.Count) { $right[$index] } else { New-Cell }
        Write-PanelRow -Left $leftCell -Right $rightCell
        Start-Sleep -Milliseconds 45
    }

    Write-PanelBottom
    Write-Host ''
}

function Write-Notice {
    param(
        [string]$Message,
        [string]$ColorKey = 'Accent'
    )

    $innerWidth = $Message.Length + 2

    Write-Styled -Text ('╭' + ('─' * $innerWidth) + '╮') -ColorKey $ColorKey
    Write-Styled -Text '│ ' -ColorKey $ColorKey -NoNewline
    Write-Styled -Text $Message -ColorKey 'Text' -NoNewline
    Write-Styled -Text ' │' -ColorKey $ColorKey
    Write-Styled -Text ('╰' + ('─' * $innerWidth) + '╯') -ColorKey $ColorKey
}

# --- mascot narration ------------------------------------------------------

function Show-MascotLine {
    param(
        [string]$Message,
        [string]$ColorKey = 'Text',
        [int]$CharacterDelayMs = 14
    )

    Write-Styled -Text (' ' * $script:Layout.StageIndent) -NoNewline
    Write-Styled -Text '(█ █) ' -ColorKey 'Accent' -NoNewline

    foreach ($character in $Message.ToCharArray()) {
        Write-Styled -Text ([string]$character) -ColorKey $ColorKey -NoNewline
        if ($CharacterDelayMs -gt 0) {
            Start-Sleep -Milliseconds $CharacterDelayMs
        }
    }

    Write-Host ''
}

function Start-MascotStage {
    for ($index = 0; $index -lt $script:Layout.StageHeight; $index++) {
        Write-Host ''
    }
}

function Update-MascotStage {
    param(
        [int]$HopOffset = 0,
        [string]$FrameKey = 'Idle',
        [string]$Speech = '',
        [string]$SpeechColorKey = 'Text'
    )

    $indent = ' ' * $script:Layout.StageIndent
    $rows = New-Object System.Collections.Generic.List[object]

    for ($index = 0; $index -lt (2 - $HopOffset); $index++) {
        $rows.Add((New-Cell))
    }

    foreach ($spriteLine in $script:MascotFrames[$FrameKey]) {
        $rows.Add((New-Cell -Text ($indent + $spriteLine) -ColorKey 'Accent'))
    }

    for ($index = 0; $index -lt $HopOffset; $index++) {
        $rows.Add((New-Cell))
    }

    $rows.Add((New-Cell -Text ($indent + '"' + $Speech + '"') -ColorKey $SpeechColorKey))

    Write-Host -NoNewline ("$($script:Esc)[{0}A" -f $script:Layout.StageHeight)
    foreach ($row in $rows) {
        Write-Host -NoNewline "$($script:Esc)[2K"
        Write-Styled -Text $row.Text -ColorKey $row.ColorKey
    }
}

function Wait-WithMascot {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$IsCompleted,
        [Parameter(Mandatory = $true)][string[]]$SpeechLines,
        [Parameter(Mandatory = $true)][string]$DoneSpeech
    )

    $frame = 0
    while (-not (& $IsCompleted)) {
        $hopOffset = $script:HopPattern[$frame % $script:HopPattern.Length]
        $frameKey = if ($hopOffset -gt 0) { 'Hop' } elseif ($frame % 17 -eq 0) { 'Blink' } else { 'Idle' }
        $speech = $SpeechLines[[math]::Floor($frame / 14) % $SpeechLines.Length]

        Update-MascotStage -HopOffset $hopOffset -FrameKey $frameKey -Speech $speech
        $frame++
        Start-Sleep -Milliseconds 90
    }

    Update-MascotStage -HopOffset 0 -FrameKey 'Happy' -Speech $DoneSpeech -SpeechColorKey 'Success'
}

# --- installer steps -------------------------------------------------------

function Test-AccessCode {
    param([Parameter(Mandatory = $true)][System.Security.SecureString]$Secret)

    $expected = [System.Text.Encoding]::UTF8.GetString(
        [System.Convert]::FromBase64String($script:Config.AccessCodeBase64))
    $pointer = [System.IntPtr]::Zero

    try {
        $pointer = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secret)
        $plainText = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
        return [string]::Equals($plainText, $expected, [System.StringComparison]::Ordinal)
    }
    finally {
        if ($pointer -ne [System.IntPtr]::Zero) {
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
        }
    }
}

function Request-AccessCode {
    Show-MascotLine -Message 'Drop the access code and I will handle the boring parts.'
    Write-Host ''

    for ($attempt = 1; $attempt -le $script:Config.MaxCodeAttempts; $attempt++) {
        Write-Styled -Text (' ' * $script:Layout.StageIndent) -NoNewline
        Write-Styled -Text 'Access code: ' -ColorKey 'Accent' -NoNewline

        Set-CursorVisible -Visible $true
        $secret = Read-Host -AsSecureString
        Set-CursorVisible -Visible $false

        if (Test-AccessCode -Secret $secret) {
            Write-Host ''
            Show-MascotLine -Message 'Code accepted. Sit back, I am on it.' -ColorKey 'Success'
            return $true
        }

        $remaining = $script:Config.MaxCodeAttempts - $attempt
        Write-Host ''
        Show-MascotLine -Message "That is not it. Tries left: $remaining" -ColorKey 'Danger'
    }

    return $false
}

function Invoke-MonitoredDownload {
    param(
        [Parameter(Mandatory = $true)][uri]$Uri,
        [Parameter(Mandatory = $true)][string]$Destination,
        [Parameter(Mandatory = $true)][string[]]$SpeechLines,
        [Parameter(Mandatory = $true)][string]$DoneSpeech
    )

    $client = New-Object System.Net.WebClient
    try {
        $downloadTask = $client.DownloadFileTaskAsync($Uri, $Destination)
        Wait-WithMascot -IsCompleted { $downloadTask.IsCompleted } -SpeechLines $SpeechLines -DoneSpeech $DoneSpeech

        if ($downloadTask.IsFaulted) {
            throw $downloadTask.Exception.GetBaseException()
        }
    }
    finally {
        $client.Dispose()
    }
}

function Expand-TweakArchive {
    param(
        [Parameter(Mandatory = $true)][string]$ExtractorPath,
        [Parameter(Mandatory = $true)][string]$ArchivePath,
        [Parameter(Mandatory = $true)][string]$Destination,
        [Parameter(Mandatory = $true)][string[]]$SpeechLines,
        [Parameter(Mandatory = $true)][string]$DoneSpeech
    )

    if (-not (Test-Path -LiteralPath $Destination)) {
        New-Item -ItemType Directory -Path $Destination | Out-Null
    }

    $arguments = @('x', ('"' + $ArchivePath + '"'), ('-o"' + $Destination + '"'), '-y')
    $process = Start-Process -FilePath $ExtractorPath -ArgumentList $arguments -NoNewWindow -PassThru

    Wait-WithMascot -IsCompleted { $process.HasExited } -SpeechLines $SpeechLines -DoneSpeech $DoneSpeech

    $process.WaitForExit()
    if ($process.ExitCode -ne 0) {
        throw [System.InvalidOperationException]::new("Extraction failed with exit code $($process.ExitCode).")
    }
}

function Remove-WorkingDirectory {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
        return
    }

    try {
        Remove-Item -LiteralPath $Path -Recurse -Force
    }
    catch [System.IO.IOException] {
        # A locked temp file is not worth failing the install over.
    }
}

function Wait-ForExitKey {
    Write-Host ''
    Show-MascotLine -Message 'Press Enter and I will get out of your way.' -ColorKey 'Muted'
    Set-CursorVisible -Visible $true
    [void](Read-Host)
}

function Invoke-Installer {
    $workingDirectory = $null

    try {
        Initialize-Console

        $destination = Join-Path ([System.Environment]::GetFolderPath('Desktop')) $script:Config.DestinationName
        Show-Dashboard -UserName $env:USERNAME -MachineName $env:COMPUTERNAME -DestinationPath ('Desktop\' + $script:Config.DestinationName)

        if (-not (Request-AccessCode)) {
            Write-Host ''
            Write-Notice -Message 'Access denied. Nothing was installed.' -ColorKey 'Danger'
            Start-Sleep -Seconds 2
            return 1
        }

        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

        $workingDirectory = Join-Path $env:TEMP ('kikios_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path $workingDirectory | Out-Null

        $extractorPath = Join-Path $workingDirectory '7zr.exe'
        $archivePath = Join-Path $workingDirectory 'pcboost.7z'

        Write-Host ''
        Start-MascotStage

        Invoke-MonitoredDownload -Uri $script:Config.ExtractorUri -Destination $extractorPath -SpeechLines @(
            'First I grab a tiny unpacker.',
            'One megabyte, do not blink.',
            'Almost have it.'
        ) -DoneSpeech 'Unpacker is mine.'

        Invoke-MonitoredDownload -Uri $script:Config.ArchiveUri -Destination $archivePath -SpeechLines @(
            'Now pulling your tweak pack.',
            'This one is bigger, hold on.',
            'Still coming down, I will keep hopping.'
        ) -DoneSpeech 'Pack downloaded.'

        Expand-TweakArchive -ExtractorPath $extractorPath -ArchivePath $archivePath -Destination $destination -SpeechLines @(
            'Shaking everything out of the box.',
            'Sorting your tweaks onto the Desktop.',
            'Last few files, promise.'
        ) -DoneSpeech 'Everything is in place.'

        Write-Host ''
        Write-Notice -Message ('Done. Your tweaks live in Desktop\' + $script:Config.DestinationName) -ColorKey 'Success'
        return 0
    }
    catch [System.Net.WebException] {
        Write-Host ''
        Write-Notice -Message 'Download failed. Check the connection and run me again.' -ColorKey 'Danger'
        return 2
    }
    catch [System.InvalidOperationException] {
        Write-Host ''
        Write-Notice -Message 'The archive would not open. Run me again.' -ColorKey 'Danger'
        return 3
    }
    catch [System.IO.IOException] {
        Write-Host ''
        Write-Notice -Message 'A file was locked on disk. Close other apps and retry.' -ColorKey 'Danger'
        return 4
    }
    catch [System.Exception] {
        Write-Host ''
        Write-Notice -Message ('Unexpected error: ' + $_.Exception.Message) -ColorKey 'Danger'
        return 5
    }
    finally {
        Remove-WorkingDirectory -Path $workingDirectory
        Wait-ForExitKey
        Set-CursorVisible -Visible $true
    }
}

exit (Invoke-Installer)
