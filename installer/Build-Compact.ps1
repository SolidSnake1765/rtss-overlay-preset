# RTSS Overlay Preset — компактный вид в одну строку в стиле Steam Performance Monitor.
# Строится целиком из кода (без шаблона): вся строка — один слой гипертекста, как у Steam текст идёт
# сплошным потоком; части без датчика просто не попадают в строку. Build-Overlay кладёт его в тот же .ovl,
# что и большой вид, и переключает их клавишей (см. Add-CompactStyle в Build-Overlay.ps1).
#
# Генерация кадров — источники здесь, их же использует большой вид. Три признака:
#   1. драйверная генерация (AMD AFMF, NVIDIA Smooth Motion): на экран выводится в 1.5+ раза больше кадров, чем
#      отдала игра (PresentMon: FramerateDisplayed против FrameratePresented) — это измерение, реальный FPS точный;
#   2. у игры есть библиотека генерации (DLSS-G, FSR, XeSS-FG) — датчик /overlay-preset/fg/data/0 из Exporter.dll;
#   3. ритм кадров: каждый второй кадр гораздо легче для видеокарты. По буферу кадров PresentMon (buf(GpuActive,-1)
#      — последний кадр): средний скачок времени GPU между соседними кадрами — больше 25 % от среднего времени, а
#      через кадр значения почти совпадают (скачок между соседними в 2+ раза больше). Wukong, FSR 3: 0.6 и 5.9;
#      без генерации: 0.04 — разница в 15 раз; второе условие отсекает беспорядочные скачки (статтеры).
#   Генерацию внутри игры PresentMon не помечает, поэтому для неё нужны 2 и 3 вместе; реальный FPS — итоговый
#   пополам (оценка, в строке «FG≈»). Признак должен держаться несколько секунд подряд.

$script:Steam = @{
    Fps = 'E8836B'; Cpu = 'E5C35C'; Gpu = '7DC75A'; Ram = 'B49DDB'; Fg = '6EC6FF'
    Value = 'FFFFFF'; Unit = 'A0A0A0'; Low = 'FF6B6B'; High = 'C8C8C8'; Graph = '7DC75A'; Warn = 'FFD040'; Hot = 'FF5A5A'
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

    # значки — спрайт rtss-overlay-preset-icons.png (↓ в 0,0; ↑ в 32,0; ≈ в 64,0), красятся цветом слоя.
    # «≈» — картинкой: символ «~» мелким шрифтом RTSS рисует плоской чёрточкой, и «FG~103» читалось как «FG-103»
    $down = '<I=6,7,0,0,32,32>'; $up = '<I=6,7,32,0,32,32>'

    # --- источники -----------------------------------------------------------------------------------
    # генерация кадров (см. шапку файла); порог 10 FPS — на рабочем столе и в меню кадры единичные
    Src 'FrameratePresented' 'PresentMon' 'FrameratePresented' 'FPS'
    Src 'FramerateDisplayed' 'PresentMon' 'FramerateDisplayed' 'FPS'
    Src 'TotalFPS' 'HAL' 'Stub' 'FPS' '%.0f' '(FramerateDisplayed > FrameratePresented) ? FramerateDisplayed : FrameratePresented'
    # скачки считаются формулой источника PresentMon — на каждом кадре; buf(x,-1) там не работает, только по имени
    $abs = { param($e) "(($e) > 0) ? ($e) : (0 - ($e))" }
    Src 'GpuActive' 'PresentMon' 'msGpuActive' 'ms' '%.1f'
    Src 'GpuJump1' 'PresentMon' 'msGpuActive' 'ms' '%.1f' (& $abs 'buf(GpuActive,-1) - buf(GpuActive,-2)')
    Src 'GpuJump2' 'PresentMon' 'msGpuActive' 'ms' '%.1f' (& $abs 'buf(GpuActive,-1) - buf(GpuActive,-3)')
    Src 'GpuAlt' 'HAL' 'Stub' '' '%.2f' 'swavg(GpuJump1,64) / swavg(GpuActive,64)'
    Src 'GpuAltRatio' 'HAL' 'Stub' '' '%.1f' 'swavg(GpuJump1,64) / swavg(GpuJump2,64)'
    Src 'FgLib' 'LHM' '/overlay-preset/fg/data/0'
    Src 'DrvFG' 'HAL' 'Stub' '' '' '(FrameratePresented >= 10) ? (FramerateDisplayed >= FrameratePresented * 1.5) : 0'
    Src 'GameFG' 'HAL' 'Stub' '' '' '((FgLib > 0) * (TotalFPS >= 20)) ? ((GpuAlt >= 0.25) * (GpuAltRatio >= 1.5)) : 0'
    Src 'FgRaw' 'HAL' 'Stub' '' '' '(DrvFG + GameFG) > 0'
    # признак «мигает» (в Witcher 3 с модом GpuAltRatio гуляет около 2) — FG, если он был большую часть последних 5 с
    Src 'IsFG' 'HAL' 'Stub' '' '' 'swavg(FgRaw,10) >= 0.6'    # 10 обновлений оверлея по 500 мс = 5 с
    Src 'IsFGApprox' 'HAL' 'Stub' '' '' '(IsFG) ? (DrvFG == 0) : 0'
    Src 'NativeFPS' 'HAL' 'Stub' 'FPS' '%.0f' '(DrvFG) ? FrameratePresented : (TotalFPS / 2)'
    # Present Mode — как кадры игры попадают на экран (PresentMon, PM_PRESENT_MODE в SDK\Include\PresentMon\PresentMonAPI.h):
    # 3 — Hardware: Independent Flip (мимо рабочего стола Windows, минимальная задержка), 8 — то же через аппаратный
    # слой MPO, 1/2 — Hardware: Legacy Flip / Copy (эксклюзивный полный экран, тоже минимальная задержка),
    # 4 — Composed: Flip (через рабочий стол, DWM, +1 кадр), 5/6 — Composed: Copy (BitBlt через GDI, +1 кадр и копия).
    # Показывается в большом виде рядом с разрешением (Build-Overlay.ps1). Подробно о режимах — гайд Andrilaz
    # https://andrilaz.github.io/presentation-model
    Src 'PresentMode' 'PresentMon' 'PresentMode' '' '%.0f'
    Src 'PmIFlip' 'HAL' 'Stub' '' '' 'PresentMode == 3'
    Src 'PmMpo' 'HAL' 'Stub' '' '' 'PresentMode == 8'
    Src 'PmComposed' 'HAL' 'Stub' '' '' 'PresentMode == 4'
    Src 'PmCopy' 'HAL' 'Stub' '' '' '(PresentMode == 5) + (PresentMode == 6)'
    Src 'PmLegacyFlip' 'HAL' 'Stub' '' '' 'PresentMode == 1'
    Src 'PmLegacyCopy' 'HAL' 'Stub' '' '' 'PresentMode == 2'

    Src 'CPU usage' 'HAL' 'CPU usage' '%'
    Src 'CPU usage max' 'HAL' 'CPU usage max' '%'
    $threads = @($cpu.PThreads) + @($cpu.EThreads) | Where-Object { $_ } | Sort-Object
    foreach ($t in $threads) {
        Src "Thread $t" 'HAL' "CPU$t usage" '%'
        # цвет полоски по загрузке потока: жёлтая от 70 %, красная от 90 % (одна полоска — один цвет, верх
        # отдельно не перекрасить)
        Src "Warm$t" 'HAL' "CPU$t usage" '' '' 'x >= 70'
        Src "Hot$t" 'HAL' "CPU$t usage" '' '' 'x >= 90'
    }
    # FPS за последние полсекунды из буфера кадров RTSS (Exporter.dll читает общую память RTSS) — для плавного графика за ~40 с
    Src 'FpsSec' 'LHM' '/overlay-preset/fps/data/0' 'FPS' '%.0f'
    # оверлей у нижнего края экрана (PositionY < 0 в профиле RTSS, Exporter.dll) — строка переезжает вниз рамки
    # оверлея (CompactTop / CompactBottom, Build-Overlay.ps1)
    Src 'OsdY' 'LHM' '/overlay-preset/osd/data/1'
    Src 'OsdBottom' 'HAL' 'Stub' '' '' 'OsdY < 0'
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
    # <IF> не вкладываются: каждый следующий <IF> закрывает предыдущий, поэтому «≈» — отдельным блоком
    $parts.Add("<C=$($P.Fps)>FPS <C=$($P.Value)><IF IsFG>%NativeFPS% <C=$($P.Fg)>FG<IF IsFGApprox><I=6,7,64,0,32,32><IF IsFG> <C=$($P.Value)>%TotalFPS%<ELSE><FR><IF>" +
               " <C=$($P.Low)>$down<C=$($P.Value)><FR10L> <C=$($P.High)>$up<C=$($P.Value)><FRMAX>")
    # график FPS: линия с автомасштабом на тёмной подложке
    # график FPS: точка на каждое обновление оверлея, 500 мс (FpsSec), 40 единиц ≈ последние 40 с — плавно, как у Steam; встроенный
    # <G=Framerate> добавлял точку на каждый кадр и при 150 FPS показывал полсекунды
    $parts.Add("<C=$($P.Graph)><G=FpsSec,40,9,1,0,0,90><C=$($P.Value)>")
    # CPU: «CPU 36%/↑91% ▮▮▮ 52°C 5.03/↑5.42 GHz»
    $cpuText = "<C=$($P.Cpu)>CPU <C=$($P.Value)>%CPU usage%$(& $u '%')/<C=$($P.High)>$up<C=$($P.Value)>%CPU usage max%$(& $u '%')"
    if ($threads.Count) {
        # <IF> не вкладываются, поэтому цвет — двумя блоками подряд: зелёный → жёлтый (Warm) → красный (Hot)
        $bars = $threads | ForEach-Object { "<C=$($P.Graph)><IF Warm$_><C=$($P.Warn)><IF Hot$_><C=$($P.Hot)><IF><G=Thread $_,1,9,0,0,100,38>" }
        $cpuText += ' ' + ($bars -join '') + "<C=$($P.Value)>"
    }
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

    # подложка: по ширине RTSS считает её по тексту, не учитывая мелкие единицы <S=48> — последнее «GB» вылезало
    # справа, поэтому в конце невидимая вставка — прозрачный угол спрайта стрелок (пробелы RTSS обрезает, у <C> альфа не работает); высота — явно, 11 единиц, текст по центру (ExtentOrigin 3): авто-высота
    # срезала низ текста, а отступы (Margin*) только сдвигают текст, не увеличивая подложку
    Lay (($parts -join '  ') + '<I=8,7,0,0,2,2>') @{ ExtentY = 11; ExtentOrigin = 3; BgndColor = 'A0101010'; MarginLeft = 3 }

    foreach ($x in ($sources.ToArray() + $layers.ToArray())) { foreach ($p in $x.Keys) { $p.V = ConvertTo-OvlText $p.V } }    # «°» — в cp1251
    $log.Add("компактный вид: источников $($sources.Count)")
    return @{ Sources = $sources; Layers = $layers; Log = $log }
}

function Test-SourceName($Sources, [string]$Name) { [bool]($Sources | Where-Object { (Get-Key $_ 'Name') -eq $Name }) }
