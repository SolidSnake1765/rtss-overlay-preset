# RTSS Overlay Preset — установщик.
# Запуск: install.bat (сам попросит права администратора).
# Параметры: -Lang ru|en, -Font Bahnschrift|Unispace, -Style Full|Compact (какой оверлей основной; без них — вопросы),
#            -Defaults (горячие клавиши без вопросов), -NoRestart,
#            -FgDebug (справа от оверлея — строка с сырыми признаками генерации кадров, для отчёта о проблеме)
param(
    [ValidateSet('', 'ru', 'en')][string]$Lang = '',
    [ValidateSet('', 'Bahnschrift', 'Unispace')][string]$Font = '',
    [ValidateSet('', 'Full', 'Compact')][string]$Style = '',
    [switch]$Defaults,
    [switch]$NoRestart,
    [switch]$FgDebug
)

$ErrorActionPreference = 'Stop'
$Product   = 'RTSS Overlay Preset'
$Version   = '1.1'
$Root      = Split-Path -Parent $PSScriptRoot
$Payload   = Join-Path $Root 'payload'
$DataDir   = Join-Path $env:ProgramData 'RTSS-Overlay-Preset'
$Stamp     = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
$BackupDir = Join-Path $DataDir "backup\$Stamp"
$LogFile   = Join-Path $DataDir 'install.log'
$MinRtss   = [version]'7.3.7'
$MinPawnIO = [version]'2.2.0'
$RU = $true

. (Join-Path $PSScriptRoot 'Detect.ps1')
. (Join-Path $PSScriptRoot 'Build-Overlay.ps1')
. (Join-Path $PSScriptRoot 'Build-Compact.ps1')
. (Join-Path $PSScriptRoot 'Common.ps1')

# ранние версии пресета хранили бэкапы в %ProgramData%\I2HARD-Overlay — переносим, чтобы uninstall их видел
$legacyDir = Join-Path $env:ProgramData 'I2HARD-Overlay'
if ((Test-Path $legacyDir) -and -not (Test-Path $DataDir)) { Move-Item $legacyDir $DataDir }
New-Item -ItemType Directory -Force $DataDir | Out-Null
Start-Transcript -Path $LogFile -Append | Out-Null

try {
    Say -Title "$Product $Version"
    Select-Language $Lang

    # архив с GitHub помечен «из интернета» — .NET не загрузит такие DLL, снимаем пометку
    Get-ChildItem $Root -Recurse -File | Unblock-File

    # 1. RTSS ----------------------------------------------------------------------------------------
    $rtss = Find-Rtss
    if (-not $rtss) { Fail (T 'RivaTuner Statistics Server не найден. Установите RTSS 7.3.7 или новее (guru3d.com) и запустите установщик снова.' 'RivaTuner Statistics Server not found. Install RTSS 7.3.7 or newer (guru3d.com) and run the installer again.') }
    $ver = [version](($rtss.Version -replace '[^\d.]', '').Trim('.'))
    $lhmDir = Join-Path $rtss.Dir 'Plugins\Client\LHMDataProvider'
    if ($ver -lt $MinRtss -or -not (Test-Path (Join-Path $lhmDir 'LHMDataProvider.exe'))) {
        Fail (T "Нужен RTSS $MinRtss или новее (найден $($rtss.Version)). Обновите RTSS и запустите установщик снова." "RTSS $MinRtss or newer is required (found $($rtss.Version)). Update RTSS and run the installer again.")
    }
    Say ''
    Say "RTSS $($rtss.Version): $($rtss.Dir)"

    # 2. Вопросы: шрифт, основной вид и горячие клавиши (всё интерактивное — в начале) ----------------
    if (-not $Font) {
        Say ''
        Say (T 'Шрифт оверлея:' 'Overlay font:') -Color Cyan
        Say '  1 - Bahnschrift'
        Say '  2 - Unispace'
        $Font = if ((Read-Host (T '  Выберите 1 или 2 [1]' '  Choose 1 or 2 [1]')) -eq '2') { 'Unispace' } else { 'Bahnschrift' }
    }
    if (-not $Style) {
        # ставятся оба вида, вопрос только о том, какой показан после запуска RTSS
        Say ''
        Say (T 'Основной вид оверлея (второй всегда под рукой — клавиша переключения вида):' 'Main overlay style (the other one is always a key press away):') -Color Cyan
        Say (T '  1 - большой (все датчики, графики FPS и frametime)' '  1 - full (all sensors, FPS and frametime graphs)')
        Say (T '  2 - компактная строка в стиле Steam' '  2 - compact Steam-style line')
        $Style = if ((Read-Host (T '  Выберите 1 или 2 [1]' '  Choose 1 or 2 [1]')) -eq '2') { 'Compact' } else { 'Full' }
    }

    # бэкап до любых изменений
    New-Item -ItemType Directory -Force $BackupDir | Out-Null
    Copy-Item $lhmDir (Join-Path $BackupDir 'LHMDataProvider') -Recurse
    foreach ($f in 'Plugins\Client\OverlayEditor.cfg', 'Plugins\Client\HotkeyHandler.cfg', 'Plugins\Client\Overlays\rtss-overlay-preset.ovl', 'Plugins\Client\Overlays\I2HARD.ovl',
               'Plugins\Client\Overlays\rtss-overlay-preset-compact.ovl', 'Plugins\Client\Overlays\rtss-overlay-preset-icons.png', 'Profiles\Config', 'Profiles\Global') {
        $src = Join-Path $rtss.Dir $f
        if (Test-Path $src) {
            $dst = Join-Path $BackupDir $f
            New-Item -ItemType Directory -Force (Split-Path $dst) | Out-Null
            Copy-Item $src $dst
        }
    }
    [pscustomobject]@{ Version = $Version; RtssDir = $rtss.Dir; Date = $Stamp; Font = $Font; Style = $Style } | ConvertTo-Json | Set-Content (Join-Path $BackupDir 'backup.json') -Encoding UTF8

    Set-Hotkeys $rtss.Dir -Defaults:$Defaults
    Say ''
    Say (T "Резервная копия: $BackupDir" "Backup: $BackupDir") -Color DarkGray

    # 3. PawnIO --------------------------------------------------------------------------------------
    $pawn = Get-PawnIOVersion
    if (-not $pawn -or $pawn -lt $MinPawnIO) {
        Say (T 'Установка драйвера PawnIO (нужен для датчиков платы, процессора и памяти)...' 'Installing the PawnIO driver (needed for motherboard, CPU and memory sensors)...')
        $p = Start-Process (Join-Path $Payload 'pawnio\PawnIO_setup.exe') -ArgumentList '-install', '-silent' -Wait -PassThru
        $pawn = Get-PawnIOVersion
        if (-not $pawn) { Warn (T "PawnIO не установился (код $($p.ExitCode)). Часть датчиков будет недоступна." "PawnIO failed to install (code $($p.ExitCode)). Some sensors will be unavailable.") }
    }
    if ($pawn) { Say "PawnIO $pawn" }

    # 4. Файлы ---------------------------------------------------------------------------------------
    [void](Stop-Rtss)
    Say (T 'Копирование файлов...' 'Copying files...')
    Copy-Item (Join-Path $Payload 'lhm\*') $lhmDir -Force
    Copy-Item (Join-Path $Payload 'exporter\Exporter.dll') $lhmDir -Force
    Copy-Item (Join-Path $Payload 'pawnio\IntelMCHBAR.bin') $lhmDir -Force
    Copy-Item (Join-Path $Payload 'pawnio\AMDFamily17.bin') $lhmDir -Force

    # 5. Железо --------------------------------------------------------------------------------------
    Say (T 'Определение железа и датчиков...' 'Detecting hardware and sensors...')
    $reportFile = Join-Path $DataDir 'hardware-report.json'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Detect.ps1') -LibDir $lhmDir -Out $reportFile | Out-Null
    $report = Get-Content $reportFile -Raw -Encoding UTF8 | ConvertFrom-Json
    $probe = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Probe-Exporter.ps1') -Dir $lhmDir | ConvertFrom-Json
    if (-not $probe.Ok) { Warn "Exporter: $($probe.Error)" }

    Say ("  CPU:   {0} ({1} {2})" -f $report.Cpu.FullName, $report.Cpu.Threads, (T 'потоков' 'threads'))
    Say ("  GPU:   {0}" -f $report.Gpu.Name)
    Say ("  Board: {0}" -f $report.Board.Title)
    Say ("  RAM:   {0} GB {1} {2} MT/s{3}" -f $report.Memory.SizeGB, $report.Memory.Type, $probe.DataRate, $(if ($probe.HasTimings) { T ' + тайминги' ' + timings' } else { '' }))

    # 6. Оверлей -------------------------------------------------------------------------------------
    $ovlFile = Join-Path $rtss.Dir 'Plugins\Client\Overlays\rtss-overlay-preset.ovl'
    $legacyOvl = Join-Path $rtss.Dir 'Plugins\Client\Overlays\I2HARD.ovl'      # файл ранних версий пресета (он в бэкапе)
    if (Test-Path $legacyOvl) { Remove-Item $legacyOvl -Force }
    # оба вида в одном файле (большой + компактная строка в стиле Steam), переключаются клавишей $StyleKey;
    # рядом — картинка со стрелками ↓↑ для компактной строки
    $log = @(Build-Overlay (Join-Path $Root 'overlay\rtss-overlay-preset.template.ovl') $report @{
        Font = $Font; HasTimings = [bool]$probe.HasTimings; StyleKey = $script:StyleKey; MainStyle = $Style; FgDebug = [bool]$FgDebug; Version = $Version } $ovlFile)
    Copy-Item (Join-Path $Root 'overlay\rtss-overlay-preset-icons.png') (Split-Path $ovlFile) -Force
    $oldCompact = Join-Path $rtss.Dir 'Plugins\Client\Overlays\rtss-overlay-preset-compact.ovl'    # отдельный файл версии 0.x (он в бэкапе)
    if (Test-Path $oldCompact) { Remove-Item $oldCompact -Force }
    foreach ($l in $log) { Say "  - $l" }
    Set-IniValue (Join-Path $rtss.Dir 'Plugins\Client\OverlayEditor.cfg') 'Settings' 'Layout' 'rtss-overlay-preset.ovl'

    # 7. Настройки RTSS ------------------------------------------------------------------------------
    Set-RtssRequiredSettings $rtss.Dir
    Say (T '  RTSS: оверлей включён, режим Raster 3D, FPS целым числом, плагины OverlayEditor и HotkeyHandler включены' '  RTSS: OSD on, Raster 3D mode, integer FPS, OverlayEditor and HotkeyHandler plugins enabled')
    if (Enable-RtssAutostart $rtss.Dir) { Say (T '  RTSS: включён автозапуск с Windows (без него после перезагрузки оверлея не будет)' '  RTSS: start with Windows enabled (without it the overlay is gone after a reboot)') }

    # 8. MSI Afterburner -----------------------------------------------------------------------------
    $ab = Find-Afterburner
    if ($ab) {
        $n = Disable-AfterburnerOsd $ab $BackupDir
        if ($n) { Say (T "  MSI Afterburner: выключен вывод $n датчиков в оверлей, чтобы он не накладывался на этот. Разгон и вентиляторы работают как раньше." "  MSI Afterburner: turned off $n sensors in its on-screen display so it does not overlap this one. Overclocking and fan control work as before.") }
        else { Say (T '  MSI Afterburner: свой оверлей не использует — ничего не меняли' '  MSI Afterburner: its on-screen display is not used — nothing changed') }
    }

    # 9. Запуск --------------------------------------------------------------------------------------
    if (-not $NoRestart) { Start-Rtss $rtss.Dir }
    Say ''
    Say (T "Готово. Оверлей включён (шрифт $Font). Журнал: $LogFile" "Done. The overlay is enabled (font $Font). Log: $LogFile") -Color Green
    Say ((T 'Два вида — большой и компактная строка в стиле Steam; переключение в игре: ' 'Two styles — full and a compact Steam-style line; switch in game with ') + (Format-Hotkey $script:StyleKey))
    Say ((T 'Основной вид (после запуска RTSS): ' 'Main style (after RTSS starts): ') + $(if ($Style -eq 'Compact') { T 'компактная строка' 'compact line' } else { T 'большой' 'full' }))
    if ($FgDebug) {
        Say ''
        Say (T 'Включены отладочные строки справа от оверлея. Запустите игру, в которой что-то не так, сделайте скриншот (Ctrl+Alt+Num 2) и приложите его к issue на GitHub. Обычный вид вернёт install.bat.' 'Debug lines are on, to the right of the overlay. Start the game where something is wrong, take a screenshot (Ctrl+Alt+Num 2) and attach it to a GitHub issue. install.bat brings back the normal view.') -Color Yellow
    }
    Say (T 'Удалить и вернуть как было: uninstall.bat' 'To remove and restore: uninstall.bat')
}
catch {
    Say ''
    Say ((T 'Ошибка: ' 'Error: ') + $_.Exception.Message) -Color Red
    Say (T "Подробности в журнале: $LogFile" "Details in the log: $LogFile")
    if ($BackupDir -and (Test-Path $BackupDir)) { Say (T 'Вернуть файлы из резервной копии: uninstall.bat' 'Restore files from the backup: uninstall.bat') }
    $global:LASTEXITCODE = 1
}
finally {
    Stop-Transcript | Out-Null
}
