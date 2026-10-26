# RTSS Overlay Preset — только собрать rtss-overlay-preset.ovl под этот ПК, ничего не меняя в системе (для ручной установки).
# Запуск от администратора (иначе не видны датчики платы и процессора):
#   powershell -ExecutionPolicy Bypass -File installer\Make-Overlay.ps1 [-Font Bahnschrift|Unispace] [-Style Full|Compact] [-Key 0x91] [-Path путь.ovl]
# В файле оба вида — большой и компактная строка; -Style — какой показан сразу, -Key — код клавиши переключения
# (по умолчанию Scroll Lock). Рядом с .ovl кладётся rtss-overlay-preset-icons.png (значки ↓↑≈).
param([ValidateSet('Bahnschrift', 'Unispace')][string]$Font = 'Bahnschrift', [ValidateSet('Full', 'Compact')][string]$Style = 'Full',
      [int]$Key = 0x91, [string]$Path = '', [switch]$FgDebug)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'Build-Overlay.ps1')
. (Join-Path $PSScriptRoot 'Build-Compact.ps1')
. (Join-Path $PSScriptRoot 'Detect.ps1')

Get-ChildItem $Root -Recurse -File | Unblock-File
if (-not $Path) { $Path = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'rtss-overlay-preset.ovl' }

# (параметр называется Path: Detect.ps1 подключается через точку и сам объявляет $Out)
# LHM из RTSS, если он уже обновлён, иначе из архива
$rtss = Find-Rtss
$lhm = if ($rtss -and (Test-Path (Join-Path $rtss.Dir 'Plugins\Client\LHMDataProvider\BlackSharp.Core.dll'))) { Join-Path $rtss.Dir 'Plugins\Client\LHMDataProvider' } else { Join-Path $Root 'payload\lhm' }

$report = Join-Path $env:TEMP 'rtss-overlay-preset-report.json'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Detect.ps1') -LibDir $lhm -Out $report | Out-Null
$data = Get-Content $report -Raw -Encoding UTF8 | ConvertFrom-Json

# тайминги: проверяем Exporter.dll из архива вместе с модулями PawnIO во временной папке
$probeDir = Join-Path $env:TEMP 'rtss-overlay-preset-probe'
Remove-Item $probeDir -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory $probeDir | Out-Null
Copy-Item (Join-Path $Root 'payload\lhm\*'), (Join-Path $Root 'payload\exporter\Exporter.dll'), (Join-Path $Root 'payload\pawnio\*.bin') $probeDir
$probe = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Probe-Exporter.ps1') -Dir $probeDir | ConvertFrom-Json

New-Item -ItemType Directory -Force (Split-Path $Path) | Out-Null
$log = Build-Overlay (Join-Path $Root 'overlay\rtss-overlay-preset.template.ovl') $data @{ Font = $Font; HasTimings = [bool]$probe.HasTimings; StyleKey = $Key; MainStyle = $Style; FgDebug = [bool]$FgDebug } $Path
Copy-Item (Join-Path $Root 'overlay\rtss-overlay-preset-icons.png') (Split-Path $Path) -Force
$log | ForEach-Object { Write-Host "  - $_" }
Write-Host "OK: $Path" -ForegroundColor Green
