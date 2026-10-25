# Проверка установленной Exporter.dll: запускает её так же, как RTSS, и сообщает, что она отдаёт.
# Запускается отдельным процессом (чтобы установщик не держал DLL открытыми). Выводит JSON.
param([Parameter(Mandatory)][string]$Dir)

$ErrorActionPreference = 'Stop'
$result = [ordered]@{ Ok = $false; Sensors = 0; MemorySource = 0; HasTimings = $false; DataRate = 0; Error = '' }
try {
    # зависимости Exporter.dll .NET находит сам в той же папке (контекст LoadFrom)
    $type = [Reflection.Assembly]::LoadFrom((Join-Path $Dir 'Exporter.dll')).GetType('Exporter.ExportClass')
    $export = $type.GetMethod('ExportToXML')
    [void]$export.Invoke($null, @($false))
    $xml = [string]$export.Invoke($null, @($false))
    [void]$export.Invoke($null, @($true))

    $result.Sensors = ([regex]::Matches($xml, '<sensor>')).Count
    if ($xml -match '/overlay-preset/memory/data/0</id><name>Source</name><type>Data</type><value>([\d.]+)') { $result.MemorySource = [int][double]$Matches[1] }
    if ($xml -match '/overlay-preset/memory/clock/0</id><name>Data Rate</name><type>Clock</type><value>([\d.]+)') { $result.DataRate = [int][double]$Matches[1] }
    $result.HasTimings = $xml -match '/overlay-preset/memory/timing/tcl</id><name>tCL</name><type>Timing</type><value>([1-9]\d*)'
    $result.Ok = $result.Sensors -gt 0
} catch {
    $result.Error = $_.Exception.InnerException.Message + ' ' + $_.Exception.Message
}
$result | ConvertTo-Json -Compress
