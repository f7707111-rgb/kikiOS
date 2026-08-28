$Host.UI.RawUI.WindowTitle = "KikiOS Installer"
chcp 65001 | Out-Null
Clear-Host

function W($t,$c="White"){Write-Host $t -ForegroundColor $c}

function Type-Text($text, $color="Yellow", $delay=30) {
    foreach ($char in $text.ToCharArray()) {
        Write-Host -NoNewline $char -ForegroundColor $color
        Start-Sleep -Milliseconds $delay
    }
    Write-Host ""
}

function Spinner($job, $label) {
    $frames = @("⠋","⠙","⠹","⠸","⠼","⠴","⠦","⠧","⠇","⠏")
    $i = 0
    while (-not $job.IsCompleted) {
        Write-Host -NoNewline ("`r  " + $frames[$i % $frames.Length] + "  $label   ") -ForegroundColor Yellow
        $i++
        Start-Sleep -Milliseconds 80
    }
    Write-Host "`r  ✔  $label" -ForegroundColor Yellow
    Write-Host ""
}

$logo = @(
    "  ██╗  ██╗ ██╗ ██╗  ██╗ ██╗  ██████╗  ███████╗",
    "  ██║ ██╔╝ ██║ ██║ ██╔╝ ██║ ██╔═══██╗ ██╔════╝",
    "  █████╔╝  ██║ █████╔╝  ██║ ██║   ██║ ███████╗",
    "  ██╔═██╗  ██║ ██╔═██╗  ██║ ██║   ██║ ╚════██║",
    "  ██║  ██╗ ██║ ██║  ██╗ ██║ ╚██████╔╝ ███████║",
    "  ╚═╝  ╚═╝ ╚═╝ ╚═╝  ╚═╝ ╚═╝  ╚═════╝  ╚══════╝"
)

$colors = @("DarkYellow","DarkYellow","Yellow","Yellow","DarkYellow","DarkYellow")

W ""
W "  * Добро пожаловать в  KikiOS  PCBOOST Edition  *" "DarkYellow"
W ""
Start-Sleep -Milliseconds 200

foreach ($i in 0..5) {
    W $logo[$i] $colors[$i]
    Start-Sleep -Milliseconds 80
}

W ""
Start-Sleep -Milliseconds 150

$ln = "─" * 58
W "  $ln" "DarkGray"
W ("  Пользователь  : " + $env:USERNAME) "DarkGray"
W ("  Компьютер     : " + $env:COMPUTERNAME) "DarkGray"
W "  $ln" "DarkGray"
W ""

Type-Text "  Что произойдёт:" "Yellow" 25
Start-Sleep -Milliseconds 80
Type-Text "    1. Скачает portable 7-Zip" "DarkGray" 18
Type-Text "    2. Скачает архив с твиками" "DarkGray" 18
Type-Text "    3. Распакует в Desktop\KikiOS Tweaks" "DarkGray" 18
Type-Text "    4. Удалит все временные файлы" "DarkGray" 18

W ""
W "  $ln" "DarkGray"
W ""

$ac = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String("TE5LP2c7KFlrcyRfVzQw"))
$ok = $false
$att = 0
while ($att -lt 3 -and -not $ok) {
    $att++
    Write-Host -NoNewline "  Код доступа: " -ForegroundColor Yellow
    $s = Read-Host -AsSecureString
    $plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($s))
    if ($plain -eq $ac) { $ok = $true }
    else { W "  ✖  Неверный код. Осталось: $(3 - $att)" "DarkYellow" }
}
if (-not $ok) {
    W ""
    W "  ✖  Доступ закрыт." "DarkYellow"
    Start-Sleep 2; exit
}

W ""
Type-Text "  ✔  Код принят. Запускаю..." "Yellow" 20
W ""

$tmp = Join-Path $env:TEMP ("kiki_" + [guid]::NewGuid().ToString("N").Substring(0,8))
New-Item -ItemType Directory -Path $tmp | Out-Null
$sz  = Join-Path $tmp "7zr.exe"
$arc = Join-Path $tmp "pcboost.7z"
$dst = Join-Path ([Environment]::GetFolderPath("Desktop")) "KikiOS Tweaks"

function DL-Spin($url, $dest, $lbl) {
    $wc = New-Object System.Net.WebClient
    $task = $wc.DownloadFileTaskAsync([uri]$url, $dest)
    Spinner $task $lbl
    if ($task.IsFaulted) { throw $task.Exception.InnerException }
}

try { DL-Spin "https://www.7-zip.org/a/7zr.exe" $sz "Скачиваю 7-Zip..." }
catch { W "  ✖  Ошибка 7z: $_" "DarkYellow"; Remove-Item $tmp -Recurse -Force; Read-Host "  Enter"; exit }

try { DL-Spin "https://github.com/f7707111-rgb/kikiOS/releases/download/v1.0/PCBOOST.7z" $arc "Скачиваю архив..." }
catch { W "  ✖  Ошибка архива: $_" "DarkYellow"; Remove-Item $tmp -Recurse -Force; Read-Host "  Enter"; exit }

$frames2 = @("⠋","⠙","⠹","⠸","⠼","⠴","⠦","⠧","⠇","⠏")
if (-not (Test-Path $dst)) { New-Item -ItemType Directory -Path $dst | Out-Null }
$args7z = 'x "' + $arc + '" -o"' + $dst + '" -y'
$pr = Start-Process -FilePath $sz -ArgumentList $args7z -NoNewWindow -PassThru
$fi = 0
while (-not $pr.HasExited) {
    Write-Host -NoNewline ("`r  " + $frames2[$fi % $frames2.Length] + "  Распаковываю...   ") -ForegroundColor Yellow
    $fi++
    Start-Sleep -Milliseconds 80
}
Write-Host "`r  ✔  Распаковка завершена." -ForegroundColor Yellow
Write-Host ""

if ($pr.ExitCode -ne 0) {
    W "  ✖  Ошибка распаковки (код $($pr.ExitCode))" "DarkYellow"
    Remove-Item $tmp -Recurse -Force; Read-Host "  Enter"; exit
}

Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue

W "  $ln" "DarkGray"
W ""
Type-Text "  ✦  Установка завершена!  Папка: Desktop\KikiOS Tweaks" "Yellow" 15
W ""
W "  $ln" "DarkGray"
W ""
Write-Host -NoNewline "  Нажмите " -ForegroundColor DarkGray
Write-Host -NoNewline "Enter " -ForegroundColor Yellow
Write-Host "для выхода..." -ForegroundColor DarkGray
Read-Host
