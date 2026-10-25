# RTSS Overlay Preset — определение RTSS, железа и датчиков.
# Отдельно: .\Detect.ps1 -Export  → hardware-report.json рядом со скриптом
# (для отладки на чужом ПК: этот файл можно прислать автору). Install.ps1 запускает его отдельным процессом
# с -LibDir (папка LHM) и -Out (куда сохранить отчёт).
param([switch]$Export, [string]$LibDir, [string]$Out)

$ErrorActionPreference = 'Stop'
$script:Root = Split-Path -Parent $PSScriptRoot

#region RTSS / PawnIO -----------------------------------------------------------------------------

function Find-Rtss {
    $keys = 'HKLM:\SOFTWARE\WOW6432Node\Unwinder\RTSS', 'HKLM:\SOFTWARE\Unwinder\RTSS'
    foreach ($k in $keys) {
        $p = Get-ItemProperty $k -ErrorAction SilentlyContinue
        if ($p -and $p.InstallDir -and (Test-Path (Join-Path $p.InstallDir 'RTSS.exe'))) {
            return [pscustomobject]@{ Dir = $p.InstallDir; Version = [string]$p.ProductVersion }
        }
    }
    $u = Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\RTSS' -ErrorAction SilentlyContinue
    if ($u -and $u.UninstallString) {
        $dir = Split-Path -Parent ($u.UninstallString.Trim('"'))
        if (Test-Path (Join-Path $dir 'RTSS.exe')) { return [pscustomobject]@{ Dir = $dir; Version = [string]$u.DisplayVersion } }
    }
    foreach ($dir in "${env:ProgramFiles(x86)}\RivaTuner Statistics Server", "$env:ProgramFiles\RivaTuner Statistics Server") {
        if (Test-Path (Join-Path $dir 'RTSS.exe')) {
            return [pscustomobject]@{ Dir = $dir; Version = (Get-Item (Join-Path $dir 'RTSS.exe')).VersionInfo.ProductVersion }
        }
    }
    return $null
}

function Get-PawnIOVersion {
    $u = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\PawnIO' -ErrorAction SilentlyContinue
    if ($u -and $u.DisplayVersion -and (Test-Path (Join-Path $env:ProgramFiles 'PawnIO\PawnIOLib.dll'))) { return [version]$u.DisplayVersion }
    return $null
}

#endregion
#region CPU topology (P/E threads in Windows logical processor order) --------------------------------

if (-not ('RtssPreset.Topology' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
namespace RtssPreset {
    public static class Topology {
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool GetLogicalProcessorInformationEx(int relationship, IntPtr buffer, ref int length);

        // returns one entry per logical processor of group 0: efficiency class of its core (higher = faster)
        public static int[] EfficiencyClasses() {
            int length = 0;
            GetLogicalProcessorInformationEx(0, IntPtr.Zero, ref length);   // RelationProcessorCore
            IntPtr buffer = Marshal.AllocHGlobal(length);
            try {
                if (!GetLogicalProcessorInformationEx(0, buffer, ref length)) return new int[0];
                var map = new SortedDictionary<int, int>();
                int offset = 0;
                while (offset < length) {
                    IntPtr item = IntPtr.Add(buffer, offset);
                    int size = Marshal.ReadInt32(item, 4);
                    int efficiency = Marshal.ReadByte(item, 9);
                    int groupCount = Marshal.ReadInt16(item, 30);
                    for (int g = 0; g < groupCount; g++) {
                        IntPtr affinity = IntPtr.Add(item, 32 + g * 16);
                        long mask = Marshal.ReadInt64(affinity);
                        int group = Marshal.ReadInt16(affinity, 8);
                        if (group != 0) continue;
                        for (int bit = 0; bit < 64; bit++)
                            if ((mask & (1L << bit)) != 0) map[bit] = efficiency;
                    }
                    offset += size;
                }
                var result = new int[map.Count];
                int i = 0;
                foreach (var kv in map) result[i++] = kv.Value;
                return result;
            } finally { Marshal.FreeHGlobal(buffer); }
        }
    }
}
'@
}

function Get-CpuInfo {
    $p = Get-CimInstance Win32_Processor | Select-Object -First 1
    $vendor = switch -Regex ($p.Manufacturer) { 'Intel' { 'Intel' } 'AMD' { 'AMD' } default { 'Other' } }
    $classes = [RtssPreset.Topology]::EfficiencyClasses()
    $max = ($classes | Measure-Object -Maximum).Maximum
    $pThreads = @(); $eThreads = @()
    for ($i = 0; $i -lt $classes.Count; $i++) {
        # HAL numbers logical processors from 1 in Windows order
        if ($classes[$i] -eq $max) { $pThreads += ($i + 1) } else { $eThreads += ($i + 1) }
    }
    $name = ($p.Name -replace '\(R\)|\(TM\)|CPU|Processor|\d+-Core|\s+@.*$', '' -replace '\s+', ' ').Trim()
    $name = $name -replace '^(\d+th|\d+rd|\d+nd|\d+st) Gen ', '' -replace '^Intel Core ', '' -replace '^AMD ', ''
    [pscustomobject]@{
        Vendor   = $vendor
        Name     = $name
        FullName = $p.Name.Trim()
        Cores    = [int]$p.NumberOfCores
        Threads  = [int]$p.NumberOfLogicalProcessors
        Hybrid   = ($eThreads.Count -gt 0)
        PThreads = $pThreads
        EThreads = $eThreads
    }
}

#endregion
#region GPU / board / memory -------------------------------------------------------------------------

function Get-GpuInfo {
    $all = foreach ($g in Get-CimInstance Win32_VideoController) {
        if ($g.PNPDeviceID -notmatch 'PCI\\VEN_([0-9A-F]{4})') { continue }   # виртуальные адаптеры
        $vendor = switch ($Matches[1]) { '10DE' { 'NVIDIA' } '1002' { 'AMD' } '8086' { 'Intel' } default { $null } }
        if (-not $vendor) { continue }
        $integrated = ($vendor -eq 'Intel' -and $g.Name -notmatch 'Arc') -or ($vendor -eq 'AMD' -and $g.Name -match 'Radeon\(TM\) Graphics|Vega \d+ Graphics|Radeon Graphics$')
        [pscustomobject]@{ Vendor = $vendor; Name = $g.Name.Trim(); Integrated = $integrated; Driver = $g.DriverVersion }
    }
    # дискретная видеокарта важнее встроенной; NVIDIA/AMD/Intel Arc в порядке перечисления
    $all | Sort-Object Integrated | Select-Object -First 1
}

function Get-BoardInfo {
    $b = Get-CimInstance Win32_BaseBoard | Select-Object -First 1
    $maker = switch -Regex ($b.Manufacturer) {
        'Micro-Star|MSI' { 'MSI' } 'ASUS' { 'ASUS' } 'Gigabyte' { 'GIGABYTE' } 'ASRock' { 'ASRock' }
        'Biostar' { 'BIOSTAR' } 'EVGA' { 'EVGA' } 'NZXT' { 'NZXT' } default { ($b.Manufacturer -split '\s')[0] }
    }
    $model = ($b.Product -replace '\s*\([^)]*\)\s*$', '').Trim()     # "PRO Z690-A WIFI DDR4(MS-7D25)" → без кода платы
    if ($model -match [regex]::Escape($maker)) { $maker = '' }
    [pscustomobject]@{ Maker = $maker; Model = $model; Title = ("$maker $model").Trim() }
}

function Get-MemoryInfo {
    $mods = @(Get-CimInstance Win32_PhysicalMemory)
    $type = switch (($mods | Select-Object -First 1).SMBIOSMemoryType) { 26 { 'DDR4' } 34 { 'DDR5' } 24 { 'DDR3' } 35 { 'LPDDR5' } default { '' } }
    $rate = ($mods | ForEach-Object { if ($_.ConfiguredClockSpeed) { $_.ConfiguredClockSpeed } else { $_.Speed } } | Measure-Object -Maximum).Maximum
    [pscustomobject]@{ Type = $type; Modules = $mods.Count; SizeGB = [math]::Round(($mods | Measure-Object Capacity -Sum).Sum / 1GB); Rate = [int]$rate }
}

#endregion
#region LibreHardwareMonitor sensors -------------------------------------------------------------------

function Get-LhmSensors([string]$LibDir) {
    $lib = Join-Path $LibDir 'LibreHardwareMonitorLib.dll'
    # зависимости LHM .NET находит сам в той же папке (контекст LoadFrom)
    [void][Reflection.Assembly]::LoadFrom($lib)

    $c = New-Object LibreHardwareMonitor.Hardware.Computer
    $c.IsCpuEnabled = $true; $c.IsGpuEnabled = $true; $c.IsMemoryEnabled = $true; $c.IsMotherboardEnabled = $true
    $c.Open()
    $list = New-Object System.Collections.Generic.List[object]
    $walk = {
        param($h, $top)
        $h.Update()
        foreach ($s in $h.Sensors) {
            $list.Add([pscustomobject]@{
                Hw = [string]$top.HardwareType; HwId = [string]$h.Identifier; HwName = $h.Name
                Id = [string]$s.Identifier; Name = $s.Name; Type = [string]$s.SensorType; Value = $s.Value
            })
        }
        foreach ($sub in $h.SubHardware) { & $walk $sub $top }
    }
    foreach ($h in $c.Hardware) { $h.Update() }
    Start-Sleep -Milliseconds 1200          # второе чтение: у загрузок и частот появляются значения
    foreach ($h in $c.Hardware) { & $walk $h $h }
    $c.Close()
    return $list
}

# Первый датчик, подходящий под правило. Правило: тип железа (regex), тип датчика, список regex имён по приоритету.
function Find-Sensor($Sensors, [string]$Hw, [string]$Type, [string[]]$Names, [switch]$All) {
    foreach ($n in $Names) {
        $m = @($Sensors | Where-Object { $_.Hw -match $Hw -and $_.Type -eq $Type -and $_.Name -match $n -and $null -ne $_.Value })
        if ($m.Count) { if ($All) { return $m } else { return $m[0] } }
    }
    return $null
}

function Resolve-Roles($Sensors, $Cpu, $Gpu) {
    $cpuHw = 'Cpu'; $sio = 'Motherboard'
    $gpuHw = switch ($Gpu.Vendor) { 'NVIDIA' { 'GpuNvidia' } 'AMD' { 'GpuAmd' } 'Intel' { 'GpuIntel' } default { 'Gpu' } }

    $r = [ordered]@{}
    $r['cpu.temp']    = Find-Sensor $Sensors $cpuHw 'Temperature' '^CPU Package$', '^Core \(Tctl/Tdie\)$', '^Core \(Tctl\)$', '^Tctl', '^Package$', '^Core Max$', '^Core Average$'
    $r['cpu.temp2']   = if ($Cpu.Hybrid) { Find-Sensor $Sensors $cpuHw 'Temperature' '^E-Core #1$' } else { $null }
    $r['cpu.clock']   = Find-Sensor $Sensors $cpuHw 'Clock' '^P-Core #1$', '^CPU Core #1$', '^Core #1$', '^Cores \(Average\)$'
    $r['cpu.clock2']  = if ($Cpu.Hybrid) { Find-Sensor $Sensors $cpuHw 'Clock' '^E-Core #1$' } else { $null }
    $r['cpu.power']   = Find-Sensor $Sensors $cpuHw 'Power' '^CPU Package$', '^Package$'
    $r['cpu.vcore']   = Find-Sensor $Sensors $sio 'Voltage' '^Vcore$', '^CPU Core$', '^CPU Vcore$', '^VCore$', '^CPU VCORE$'
    if (-not $r['cpu.vcore']) {
        $r['cpu.vcore'] = Find-Sensor $Sensors $cpuHw 'Voltage' '^CPU Core$', '^Core \(SVI3 TFN\)$', '^Core \(SVI2 TFN\)$', '^Core #1 VID$'
    }
    $r['ram.voltage'] = Find-Sensor $Sensors $sio 'Voltage' '^DRAM$', '^DIMM$', '^VDIMM$', '^DRAM Voltage$', '^Memory$', '^VDDQ$', '^DIMM [A-Z]'
    $r['ram.temp']    = Find-Sensor $Sensors 'Memory' 'Temperature' '^DIMM #\d+$' -All
    # датчики только той видеокарты, что выбрана в Get-GpuInfo (встройка и дискретная могут быть одного вендора)
    $gpuAll = @($Sensors | Where-Object { $_.Hw -match $gpuHw })
    $gpuOwn = @($gpuAll | Where-Object { $_.HwName -eq $Gpu.Name })
    if (-not $gpuOwn.Count -and $gpuAll.Count) { $first = $gpuAll[0].HwId; $gpuOwn = @($gpuAll | Where-Object { $_.HwId -eq $first }) }
    $g = '.'
    $r['gpu.clock']   = Find-Sensor $gpuOwn $g 'Clock' '^GPU Core$', '^GPU Shader$', '^GPU$'
    $r['gpu.memclock']= Find-Sensor $gpuOwn $g 'Clock' '^GPU Memory$'
    $r['gpu.temp']    = Find-Sensor $gpuOwn $g 'Temperature' '^GPU Core$', '^GPU Temperature$', '^GPU Edge$', '^GPU$'
    $r['gpu.hotspot'] = Find-Sensor $gpuOwn $g 'Temperature' '^GPU Hot ?Spot$'
    $r['gpu.memtemp'] = Find-Sensor $gpuOwn $g 'Temperature' '^GPU Memory Junction$', '^GPU Memory$', '^GPU VRAM$'
    $r['gpu.voltage'] = Find-Sensor $gpuOwn $g 'Voltage' '^GPU Core Voltage$', '^GPU Core$', '^GPU Voltage$'
    $r['gpu.fan']     = Find-Sensor $gpuOwn $g 'Fan' '^GPU Fan( 1)?$', '^GPU Fan'
    $r['gpu.power']   = Find-Sensor $gpuOwn $g 'Power' '^GPU Package$', '^GPU Power$', '^GPU Total$', '^GPU Core$'
    $r['gpu.memused'] = Find-Sensor $gpuOwn $g 'SmallData' '^GPU Memory Used$', '^D3D Dedicated Memory Used$'
    $r['gpu.usage']   = Find-Sensor $gpuOwn $g 'Load' '^GPU Core$', '^D3D 3D$', '^GPU$'
    return $r
}

#endregion
#region Полный отчёт ---------------------------------------------------------------------------------

function Get-HardwareReport([string]$LibDir) {
    $cpu = Get-CpuInfo; $gpu = Get-GpuInfo
    $sensors = @()
    try { $sensors = Get-LhmSensors $LibDir } catch { Write-Warning "LibreHardwareMonitor: $_" }
    $roles = Resolve-Roles $sensors $cpu $gpu
    $ids = [ordered]@{}
    foreach ($k in $roles.Keys) {
        $v = $roles[$k]
        $ids[$k] = if ($null -eq $v) { $null } elseif ($v -is [array]) { ($v | ForEach-Object Id) -join ',' } else { $v.Id }
    }
    [pscustomobject]@{
        Cpu = $cpu; Gpu = $gpu; Board = Get-BoardInfo; Memory = Get-MemoryInfo
        Rtss = Find-Rtss; PawnIO = [string](Get-PawnIOVersion)
        Sensors = $ids
        AllSensors = $sensors
    }
}

if ($Export -or $Out) {
    if (-not $LibDir) { $LibDir = Join-Path $script:Root 'payload\lhm' }
    if (-not $Out) { $Out = Join-Path $PSScriptRoot 'hardware-report.json' }
    $report = Get-HardwareReport $LibDir
    $report | ConvertTo-Json -Depth 5 | Set-Content -Path $Out -Encoding UTF8
    if ($Export) {
        Write-Host "Saved: $Out"
        $report | Select-Object Cpu, Gpu, Board, Memory, Rtss, PawnIO | Format-List
        $report.Sensors | Format-Table -AutoSize
    }
}

#endregion
