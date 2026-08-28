$Host.UI.RawUI.WindowTitle = "KikiOS Installer"
chcp 65001 | Out-Null
Clear-Host

function W($t,$c="White"){Write-Host $t -ForegroundColor $c}

W ""
W "  * Добро пожаловать в  KikiOS  PCBOOST Edition  *" "DarkYellow"
W ""

W "  ██╗  ██╗ ██╗ ██╗  ██╗ ██╗  ██████╗  ███████╗" "DarkYellow"
W "  ██║ ██╔╝ ██║ ██║ ██╔╝ ██║ ██╔═══██╗ ██╔════╝" "DarkYellow"
W "  █████╔╝  ██║ █████╔╝  ██║ ██║   ██║ ███████╗" "Yellow"
W "  ██╔═██╗  ██║ ██╔═██╗  ██║ ██║   ██║ ╚════██║" "Yellow"
W "  ██║  ██╗ ██║ ██║  ██╗ ██║ ╚██████╔╝ ███████║" "DarkYellow"
W "  ╚═╝  ╚═╝ ╚═╝ ╚═╝  ╚═╝ ╚═╝  ╚═════╝  ╚══════╝" "DarkYellow"
W ""

$ln = "─" * 58
W "  $ln" "DarkGray"
W ("  Пользователь  : " + $env:USERNAME) "DarkGray"
W ("  Компьютер     : " + $env:COMPUTERNAME) "DarkGray"
W "  $ln" "DarkGray"
W ""
W "  Что произойдёт:" "Yellow"
W "    1. Скачает portable 7-Zip" "DarkGray"
W "    2. Скачает архив с твиками" "DarkGray"
W "    3. Распакует в Desktop\KikiOS Tweaks" "DarkGray"
W "    4. Удалит все временные файлы" "DarkGray"
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
W "  ✔  Код принят. Запускаю..." "Yellow"
W ""

$tmp = Join-Path $env:TEMP ("kiki_" + [guid]::NewGuid().ToString("N").Substring(0,8))
New-Item -ItemType Directory -Path $tmp | Out-Null
$sz  = Join-Path $tmp "7zr.exe"
$arc = Join-Path $tmp "pcboost.7z"
$dst = Join-Path ([Environment]::GetFolderPath("Desktop")) "KikiOS Tweaks"

function DL {
    param($url, $dest, $lbl)
    W "  >> $lbl" "DarkYellow"
    try {
        $wc = New-Object System.Net.WebClient
        $wc.DownloadFile($url, $dest)
        W "  ✔  Готово." "Yellow"
        W ""
    } catch { throw $_ }
}

try { DL "https://www.7-zip.org/a/7zr.exe" $sz "Скачиваю 7-Zip..." }
catch { W "  ✖  Ошибка 7z: $_" "DarkYellow"; Remove-Item $tmp -Recurse -Force; Read-Host "  Enter"; exit }

try { DL "https://github.com/f7707111-rgb/kikiOS/releases/download/v1.0/PCBOOST.7z" $arc "Скачиваю архив..." }
catch { W "  ✖  Ошибка архива: $_" "DarkYellow"; Remove-Item $tmp -Recurse -Force; Read-Host "  Enter"; exit }

W "  >> Распаковываю..." "DarkYellow"
if (-not (Test-Path $dst)) { New-Item -ItemType Directory -Path $dst | Out-Null }
$args7z = 'x "' + $arc + '" -o"' + $dst + '" -y'
$pr = Start-Process -FilePath $sz -ArgumentList $args7z -NoNewWindow -Wait -PassThru
if ($pr.ExitCode -ne 0) {
    W "  ✖  Ошибка распаковки (код $($pr.ExitCode))" "DarkYellow"
    Remove-Item $tmp -Recurse -Force; Read-Host "  Enter"; exit
}
Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue

W "  ✔  Распаковка завершена." "Yellow"
W ""
W "  $ln" "DarkGray"
W ""
W "  ✦  Установка завершена!  Папка: Desktop\KikiOS Tweaks" "Yellow"
W ""
W "  $ln" "DarkGray"
W ""
Write-Host -NoNewline "  Нажмите " -ForegroundColor DarkGray
Write-Host -NoNewline "Enter " -ForegroundColor Yellow
Write-Host "для выхода..." -ForegroundColor DarkGray
Read-Host
