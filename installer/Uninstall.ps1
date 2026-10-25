# RTSS Overlay Preset — удаление: возвращает файлы RTSS (и настройки оверлея MSI Afterburner) из самой ранней
# резервной копии установщика, то есть к состоянию до первой установки.
# Драйвер PawnIO не удаляется (он может быть нужен другим программам); удалить его можно в «Приложения» Windows.
param([ValidateSet('', 'ru', 'en')][string]$Lang = '')

$ErrorActionPreference = 'Stop'
$DataDir = Join-Path $env:ProgramData 'RTSS-Overlay-Preset'
$RU = $true
. (Join-Path $PSScriptRoot 'Common.ps1')

try {
    Say -Title 'RTSS Overlay Preset — uninstall'
    Select-Language $Lang

    $backup = Get-ChildItem (Join-Path $DataDir 'backup') -Directory -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -First 1
    if (-not $backup) { Fail (T 'Резервная копия не найдена — восстанавливать нечего.' 'No backup found — nothing to restore.') }
    $info = Get-Content (Join-Path $backup.FullName 'backup.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $rtssDir = $info.RtssDir
    Say (T "Восстановление из $($backup.FullName)" "Restoring from $($backup.FullName)")

    $wasRunning = Stop-Rtss
    $lhmDir = Join-Path $rtssDir 'Plugins\Client\LHMDataProvider'
    Get-ChildItem $lhmDir -File | Remove-Item -Force
    Copy-Item (Join-Path $backup.FullName 'LHMDataProvider\*') $lhmDir -Recurse -Force

    foreach ($f in 'Plugins\Client\OverlayEditor.cfg', 'Plugins\Client\HotkeyHandler.cfg', 'Plugins\Client\Overlays\rtss-overlay-preset.ovl', 'Plugins\Client\Overlays\I2HARD.ovl', 'Profiles\Global') {
        $saved = Join-Path $backup.FullName $f
        $target = Join-Path $rtssDir $f
        if (Test-Path $saved) { Copy-Item $saved $target -Force }
        elseif ($f -like '*rtss-overlay-preset.ovl' -and (Test-Path $target)) { Remove-Item $target -Force }
    }

    # настройки оверлея Afterburner — из первой копии, где они сохранены
    $abSaved = Get-ChildItem (Join-Path $DataDir 'backup') -Directory | Sort-Object Name |
               ForEach-Object { Join-Path $_.FullName 'MSI Afterburner\MSIAfterburner.cfg' } | Where-Object { Test-Path $_ } | Select-Object -First 1
    $ab = Find-Afterburner
    if ($abSaved -and $ab) {
        $abRunning = Get-Process MSIAfterburner -ErrorAction SilentlyContinue
        if ($abRunning) { $abRunning | ForEach-Object { [void]$_.CloseMainWindow() }; Start-Sleep 3; Get-Process MSIAfterburner -ErrorAction SilentlyContinue | Stop-Process -Force }
        Copy-Item $abSaved $ab.Cfg -Force
        if ($abRunning) { Start-Process (Join-Path $ab.Dir 'MSIAfterburner.exe') -WorkingDirectory $ab.Dir }
        Say (T '  MSI Afterburner: настройки его оверлея возвращены' '  MSI Afterburner: its on-screen display settings restored')
    }

    if ($wasRunning) { Start-Rtss $rtssDir }
    Say (T 'Готово: RTSS возвращён к состоянию до установки.' 'Done: RTSS restored to its state before the install.') -Color Green
    Say ((T 'Резервные копии остались в ' 'Backups are kept in ') + (Join-Path $DataDir 'backup'))
}
catch {
    Say ((T 'Ошибка: ' 'Error: ') + $_.Exception.Message) -Color Red
    $global:LASTEXITCODE = 1
}
