$Host.UI.RawUI.WindowTitle = "KikiOS Installer"
chcp 65001 | Out-Null
Clear-Host
Write-Host "  ██╗  ██╗██╗██╗  ██╗██╗ ██████╗ ███████╗" -ForegroundColor Magenta
Write-Host "  ██║ ██╔╝██║██║ ██╔╝██║██╔═══██╗██╔════╝" -ForegroundColor Magenta
Write-Host "  █████╔╝ ██║█████╔╝ ██║██║   ██║███████╗" -ForegroundColor DarkMagenta
Write-Host "  ██╔═██╗ ██║██╔═██╗ ██║██║   ██║╚════██║" -ForegroundColor DarkMagenta
Write-Host "  ██║  ██╗██║██║  ██╗██║╚██████╔╝███████║" -ForegroundColor Magenta
Write-Host "  ╚═╝  ╚═╝╚═╝╚═╝  ╚═╝╚═╝ ╚═════╝ ╚══════╝" -ForegroundColor Magenta
Write-Host ""
$w = try { $Host.UI.RawUI.WindowSize.Width } catch { 80 }
$t = "  ✦  PCBOOST Edition  v1.0.0  ✦"
Write-Host ((" " * [Math]::Max(0, [int](($w - $t.Length) / 2))) + $t) -ForegroundColor Cyan
Write-Host ""
$ln = "-" * 58
Write-Host "  $ln" -ForegroundColor DarkGray
Write-Host "  Пользователь  : $env:USERNAME" -ForegroundColor Gray
Write-Host "  Компьютер     : $env:COMPUTERNAME" -ForegroundColor Gray
Write-Host "  $ln" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Что произойдёт:" -ForegroundColor Yellow
Write-Host "    1. Скачает portable 7-Zip" -ForegroundColor Gray
Write-Host "    2. Скачает архив с твиками" -ForegroundColor Gray
Write-Host "    3. Распакует в Desktop\KikiOS Tweaks" -ForegroundColor Gray
Write-Host "    4. Удалит все временные файлы" -ForegroundColor Gray
Write-Host ""
Write-Host "  $ln" -ForegroundColor DarkGray
Write-Host ""
$ac = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String("TE5LP2c7KFlrcyRfVzQw"))
$ok = $false
$att = 0
while ($att -lt 3 -and -not $ok) {
    $att++
    Write-Host -NoNewline "  Код доступа: " -ForegroundColor White
    $s = Read-Host -AsSecureString
    $plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($s))
    if ($plain -eq $ac) { $ok = $true }
    else { Write-Host "  ✖ Неверный код. Осталось: $(3 - $att)" -ForegroundColor Red }
}
if (-not $ok) {
    Write-Host ""
    Write-Host "  ✖ Доступ закрыт." -ForegroundColor Red
    Start-Sleep 2
    exit
}
Write-Host ""
Write-Host "  ✔ Код принят. Запускаю..." -ForegroundColor Green
Write-Host ""
$tmp = Join-Path $env:TEMP ("kiki_" + [guid]::NewGuid().ToString("N").Substring(0,8))
New-Item -ItemType Directory -Path $tmp | Out-Null
$sz  = Join-Path $tmp "7zr.exe"
$arc = Join-Path $tmp "pcboost.7z"
$dst = Join-Path ([Environment]::GetFolderPath("Desktop")) "KikiOS Tweaks"
function DL {
    param($url, $dest, $lbl)
    Write-Host "  >> $lbl" -ForegroundColor Yellow
    $wc = New-Object System.Net.WebClient
    $script:dlDone = $false
    $script:dlPct  = -1
    $wc.DownloadProgressChanged += {
        $p = $_.ProgressPercentage
        if ($p -ne $script:dlPct) {
            $script:dlPct = $p
            $b = ("*" * [int](38 * $p / 100)).PadRight(38, ".")
            Write-Host -NoNewline ("`r  [$b] " + $p.ToString().PadLeft(3) + "%  ")
        }
    }
    $wc.DownloadFileCompleted += { $script:dlDone = $true }
    $wc.DownloadFileAsync([uri]$url, $dest)
    while (-not $script:dlDone) { Start-Sleep -Milliseconds 80 }
    Write-Host ""
    Write-Host "  ✔ Готово." -ForegroundColor Green
    Write-Host ""
}
try { DL "https://www.7-zip.org/a/7zr.exe" $sz "Скачиваю 7-Zip..." }
catch {
    Write-Host "  ✖ Ошибка 7z: $_" -ForegroundColor Red
    Remove-Item $tmp -Recurse -Force
    Read-Host "  Enter для выхода"
    exit
}
try { DL "https://github.com/f7707111-rgb/kikiOS/releases/download/v1.0/PCBOOST.7z" $arc "Скачиваю архив..." }
catch {
    Write-Host "  ✖ Ошибка архива: $_" -ForegroundColor Red
    Remove-Item $tmp -Recurse -Force
    Read-Host "  Enter для выхода"
    exit
}
Write-Host "  >> Распаковываю..." -ForegroundColor Yellow
if (-not (Test-Path $dst)) { New-Item -ItemType Directory -Path $dst | Out-Null }
$args7z = 'x "' + $arc + '" -o"' + $dst + '" -y'
$pr = Start-Process -FilePath $sz -ArgumentList $args7z -NoNewWindow -Wait -PassThru
if ($pr.ExitCode -ne 0) {
    Write-Host "  ✖ Ошибка распаковки (код $($pr.ExitCode))" -ForegroundColor Red
    Remove-Item $tmp -Recurse -Force
    Read-Host "  Enter для выхода"
    exit
}
Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "  ✔ Готово." -ForegroundColor Green
Write-Host ""
Write-Host "  $ln" -ForegroundColor DarkGray
$fin = "  ✦  Установка завершена!  ✦"
Write-Host ((" " * [Math]::Max(0, [int](($w - $fin.Length) / 2))) + $fin) -ForegroundColor Green
$sub = "Desktop\KikiOS Tweaks"
Write-Host ((" " * [Math]::Max(0, [int](($w - $sub.Length) / 2))) + $sub) -ForegroundColor Cyan
Write-Host "  $ln" -ForegroundColor DarkGray
Write-Host ""
Read-Host "  Нажмите Enter для выхода"
