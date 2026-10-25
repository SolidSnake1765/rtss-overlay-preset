# RTSS Overlay Preset — компактный вид в одну строку в стиле Steam Performance Monitor.
# Строится целиком из кода (без шаблона): вся строка — один слой гипертекста, как у Steam текст идёт
# сплошным потоком; части без датчика просто не попадают в строку. Build-Overlay кладёт его в тот же .ovl,
# что и большой вид, и переключает их клавишей (см. Add-CompactStyle в Build-Overlay.ps1).
#
# Генерация кадров (DLSS FG, FSR FG, AFMF, Smooth Motion): нативный FPS берётся из PresentMon (входит в RTSS) —
# CPUFrametime — время между началами кадров самой игры, сгенерированные кадры в него не попадают.
# Итоговый FPS — больший из «показанных» и «отправленных на экран» по PresentMon. Если итоговый в 1.5 раза
# и больше выше нативного, строка FPS становится «FPS 60 FG 120 ↓… ↑…».

$script:Steam = @{
    Fps = 'E8836B'; Cpu = 'E5C35C'; Gpu = '7DC75A'; Ram = 'B49DDB'; Fg = '6EC6FF'
    Value = 'FFFFFF'; Unit = 'A0A0A0'; Low = 'FF6B6B'; High = 'C8C8C8'; Graph = '7DC75A'
}

# Возвращает @{ Sources; Layers; Log } — источники и единственный слой компактной строки
function Get-CompactParts($Report) {
    $ids = $Report.Sensors; $cpu = $Report.Cpu; $gpu = $Report.Gpu
    $log = New-Object System.Collections.Generic.List[string]
    $sources = New-Object System.Collections.Generic.List[object]
    $layers = New-Object System.Collections.Generic.List[object]
    $P = $script:Steam

    function Src([string]$Name, [string]$Provider, [string]$Id, [string]$Units = '', [string]$Format = '', [string]$Formula = '') {
        $sources.Add((New-OvlSource $Name $Provider $Id $Units $Format $Formula))
    }
    # слой в левом верхнем углу; ширина и высота — по тексту
    function Lay([string]$Text, [hashtable]$Extra = @{}) {
        $s = [pscustomobject]@{ Name = 'Layer?'; Keys = New-Object System.Collections.Generic.List[object] }
        $kv = [ordered]@{ Name = 'compact'; Text = $Text; PositionX = 0; PositionY = 0; ExtentX = 0; ExtentY = 0; ExtentOrigin = 0; Size = 80; TextColor = $P.Value }
        foreach ($k in $Extra.Keys) { $kv[$k] = $Extra[$k] }
        foreach ($k in $kv.Keys) { $s.Keys.Add([pscustomobject]@{ K = $k; V = [string]$kv[$k] }) }
        $layers.Add($s)
    }

    # стрелки — спрайт rtss-overlay-preset-icons.png (↓ в 0,0; ↑ в 32,0), красятся цветом слоя
    $down = '<I=6,7,0,0,32,32>'; $up = '<I=6,7,32,0,32,32>'

    # --- источники -----------------------------------------------------------------------------------
    # PresentMon: нативный и итоговый FPS, признак генерации кадров
    Src 'CPUFrametime' 'PresentMon' 'CPUFrametime' 'ms' '%.1f'
    Src 'FrameratePresented' 'PresentMon' 'FrameratePresented' 'FPS'
    Src 'FramerateDisplayed' 'PresentMon' 'FramerateDisplayed' 'FPS'
    Src 'NativeFPS' 'HAL' 'Stub' 'FPS' '%.0f' '1000/CPUFrametime'
    Src 'TotalFPS' 'HAL' 'Stub' 'FPS' '%.0f' '(FramerateDisplayed > FrameratePresented) ? FramerateDisplayed : FrameratePresented'
    # порог 10 FPS: на рабочем столе и в меню PresentMon ловит единичные кадры, и 1 против 3 — не генерация
    Src 'IsFG' 'HAL' 'Stub' '' '' '(NativeFPS >= 10) ? (TotalFPS >= NativeFPS * 1.5) : 0'

    Src 'CPU usage' 'HAL' 'CPU usage' '%'
    Src 'CPU usage max' 'HAL' 'CPU usage max' '%'
    $threads = @($cpu.PThreads) + @($cpu.EThreads) | Where-Object { $_ } | Sort-Object
    foreach ($t in $threads) { Src "Thread $t" 'HAL' "CPU$t usage" '%' }
    if ($ids.'cpu.temp') { Src 'CPU temperature' 'LHM' $ids.'cpu.temp' 'C' }
    $clocks = @(if ($ids.'cpu.clocks') { $ids.'cpu.clocks' -split ',' })
    if ($clocks.Count) {
        for ($i = 0; $i -lt $clocks.Count; $i++) { Src "Clk$i" 'LHM' $clocks[$i] 'MHz' }
        $names = 0..($clocks.Count - 1) | ForEach-Object { "Clk$_" }
        # сумма — цепочкой Sm1..SmN (короткие формулы); делить один раз: «a / b / c» редактор не считает
        $sum = $names[0]
        for ($i = 1; $i -lt $names.Count; $i++) { Src "Sm$i" 'HAL' 'Stub' 'MHz' '' "$sum + $($names[$i])"; $sum = "Sm$i" }
        Src 'CPU clock avg' 'HAL' 'Stub' 'GHz' '%.2f' "$sum / $($clocks.Count * 1000)"
        # максимум: функции max в формулах RTSS нет — цепочка промежуточных источников Mx1..MxN
        $prev = $names[0]
        for ($i = 1; $i -lt $names.Count; $i++) { Src "Mx$i" 'HAL' 'Stub' 'MHz' '' "($($names[$i]) > $prev) ? $($names[$i]) : $prev"; $prev = "Mx$i" }
        Src 'CPU clock max' 'HAL' 'Stub' 'GHz' '%.2f' "$prev / 1000"
    }

    Src 'GPU usage' $(if ($ids.'gpu.usage') { 'LHM' } else { 'HAL' }) $(if ($ids.'gpu.usage') { $ids.'gpu.usage' } else { 'GPU1 usage' }) '%'
    if ($ids.'gpu.temp') { Src 'GPU temperature' 'LHM' $ids.'gpu.temp' 'C' }
    elseif (-not $gpu.Integrated) { Src 'GPU temperature' 'HAL' 'GPU1 temperature' 'C' }
    if ($ids.'gpu.memused') { Src 'VramUsed' 'LHM' $ids.'gpu.memused' 'GB' '%.1f' 'x / 1024' }
    if ($ids.'gpu.memtotal') { Src 'VramTotal' 'LHM' $ids.'gpu.memtotal' 'GB' '%.1f' 'x / 1024' }
    # имена источников, которые участвуют в формулах, — без пробелов
    if ($ids.'ram.usedgb') { Src 'RamUsed' 'LHM' $ids.'ram.usedgb' 'GB' '%.1f' }
    if ($ids.'ram.usedgb' -and $ids.'ram.freegb') {
        Src 'RamFree' 'LHM' $ids.'ram.freegb' 'GB' '%.1f'
        Src 'RamTotal' 'HAL' 'Stub' 'GB' '%.1f' 'RamUsed + RamFree'
    } elseif (-not $ids.'ram.usedgb') { Src 'RamUsed' 'HAL' 'RAM usage' 'GB' '%.1f' 'x / 1024' }

    # --- строка: один слой гипертекста, как у Steam текст идёт сплошным потоком ----------------------
    # мелкая единица надстрочно; <S=n> — в процентах от шрифта (не от Size слоя), голый <S> вернул бы 100 %,
    # поэтому размер строки (80) восстанавливается явно
    $u = { param($t) "<S=48><C=$($P.Unit)>$t<S=80><C=$($P.Value)>" }
    $parts = New-Object System.Collections.Generic.List[string]
    # FPS: «FPS 225 ↓28 ↑419», при генерации кадров «FPS 60 FG 120 ↓95 ↑130»
    $parts.Add("<C=$($P.Fps)>FPS <C=$($P.Value)><IF IsFG>%NativeFPS% <C=$($P.Fg)>FG <C=$($P.Value)>%TotalFPS%<ELSE><FR><IF>" +
               " <C=$($P.Low)>$down<C=$($P.Value)><FR10L> <C=$($P.High)>$up<C=$($P.Value)><FRMAX>")
    # график FPS: линия с автомасштабом на тёмной подложке
    $parts.Add("<C=$($P.Graph)><G=Framerate,40,0,1,0,0,90><C=$($P.Value)>")
    # CPU: «CPU 36%/↑91% ▮▮▮ 52°C 5.03/↑5.42 GHz»
    $cpuText = "<C=$($P.Cpu)>CPU <C=$($P.Value)>%CPU usage%$(& $u '%')/<C=$($P.High)>$up<C=$($P.Value)>%CPU usage max%$(& $u '%')"
    if ($threads.Count) { $cpuText += " <C=$($P.Graph)>" + (($threads | ForEach-Object { "<G=Thread $_,1,0,0,0,100,38>" }) -join '') + "<C=$($P.Value)>" }
    if ($ids.'cpu.temp') { $cpuText += " %CPU temperature%$(& $u '°C')" } else { $log.Add('компактный: нет температуры CPU') }
    if ($clocks.Count) { $cpuText += " %CPU clock avg%/<C=$($P.High)>$up<C=$($P.Value)>%CPU clock max%$(& $u 'GHz')" }
    $parts.Add($cpuText)
    # GPU: «GPU 70% 56°C 6.0/11.8 GB»
    $gpuText = "<C=$($P.Gpu)>GPU <C=$($P.Value)>%GPU usage%$(& $u '%')"
    if (Test-SourceName $sources 'GPU temperature') { $gpuText += " %GPU temperature%$(& $u '°C')" }
    if ($ids.'gpu.memused') { $gpuText += " %VramUsed%$(if ($ids.'gpu.memtotal') { '/%VramTotal%' })$(& $u 'GB')" }
    $parts.Add($gpuText)
    # RAM: «RAM 21.6/31.9 GB»
    $parts.Add("<C=$($P.Ram)>RAM <C=$($P.Value)>%RamUsed%$(if (Test-SourceName $sources 'RamTotal') { '/%RamTotal%' })$(& $u 'GB')")

    Lay ($parts -join '  ') @{ BgndColor = 'A0101010'; MarginLeft = 3; MarginTop = 1; MarginRight = 3; MarginBottom = 1 }

    foreach ($x in ($sources.ToArray() + $layers.ToArray())) { foreach ($p in $x.Keys) { $p.V = ConvertTo-OvlText $p.V } }    # «°» — в cp1251
    $log.Add("компактный вид: источников $($sources.Count)")
    return @{ Sources = $sources; Layers = $layers; Log = $log }
}

function Test-SourceName($Sources, [string]$Name) { [bool]($Sources | Where-Object { (Get-Key $_ 'Name') -eq $Name }) }
