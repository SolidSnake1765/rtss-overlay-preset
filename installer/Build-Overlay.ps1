# RTSS Overlay Preset — сборка .ovl из шаблона под конкретное железо.
# Шаблон: overlay\rtss-overlay-preset.template.ovl. Слои помечены тегами в поле Name:
#   cell:<роль>:value / cell:<роль>:unit — ячейка датчика (удаляется целиком, если датчика нет)
#   label.cpu / label.gpu / label.fps   — подписи блоков (цвет по производителю)
#   header, bars.p, bars.e, ram.timings — генерируются
# Файл .ovl хранится в cp1251 — читаем и пишем байт-в-байт через Latin-1.

$script:Latin1 = [Text.Encoding]::GetEncoding(28591)

function Read-Ovl([string]$Path) {
    $sections = New-Object System.Collections.Generic.List[object]
    foreach ($line in ($script:Latin1.GetString([IO.File]::ReadAllBytes($Path)) -split "`r`n")) {
        if ($line -match '^\[(.+)\]$') { $sections.Add([pscustomobject]@{ Name = $Matches[1]; Keys = New-Object System.Collections.Generic.List[object] }) }
        elseif ($line -and $sections.Count) {
            $i = $line.IndexOf('=')
            $sections[$sections.Count - 1].Keys.Add([pscustomobject]@{ K = $line.Substring(0, $i); V = $line.Substring($i + 1) })
        }
    }
    return $sections
}

function Write-Ovl($Sections, [string]$Path) {
    $sb = New-Object Text.StringBuilder
    foreach ($s in $Sections) {
        [void]$sb.Append("[$($s.Name)]`r`n")
        foreach ($p in $s.Keys) { [void]$sb.Append("$($p.K)=$($p.V)`r`n") }
    }
    [IO.File]::WriteAllBytes($Path, $script:Latin1.GetBytes($sb.ToString()))
}

function Get-Key($Section, [string]$Key) { ($Section.Keys | Where-Object K -eq $Key | Select-Object -First 1).V }
function Set-Key($Section, [string]$Key, [string]$Value) {
    $p = $Section.Keys | Where-Object K -eq $Key | Select-Object -First 1
    if ($p) { $p.V = $Value } else { $Section.Keys.Add([pscustomobject]@{ K = $Key; V = $Value }) }
}
# текст для .ovl: всё, что не помещается в cp1251, заменяем на '?'
function ConvertTo-OvlText([string]$Text) {
    $cp = [Text.Encoding]::GetEncoding(1251)
    $script:Latin1.GetString($cp.GetBytes($Text))
}

$script:Palette = @{
    CpuIntel = '6CCBFF'; CpuAmd = 'FF8A65'
    GpuNvidia = '8CD95A'; GpuAmd = 'FF8A65'; GpuIntel = '5AA9FF'; Fps = 'FFC94A'; Separator = '8C8C8C'
    Warn = 'FFD040'; Crit = 'FF4848'
}

function New-OvlSource([string]$Name, [string]$Provider, [string]$Id, [string]$Units, [string]$Format, [string]$Formula) {
    $s = [pscustomobject]@{ Name = 'Source?'; Keys = New-Object System.Collections.Generic.List[object] }
    foreach ($p in @(@('Name', $Name), @('Units', $Units), @('Format', $Format), @('Formula', $Formula), @('Provider', $Provider), @('ID', $Id))) {
        $s.Keys.Add([pscustomobject]@{ K = $p[0]; V = [string]$p[1] })
    }
    return $s
}

function Get-TempColor([string]$Source, [int]$Warn, [int]$Crit) {
    "FFFFFF,,$Warn,$($script:Palette.Warn),$Warn,$Crit,$($script:Palette.Crit),$Crit,($Source,0)"
}

# Сборка. $Report — результат Get-HardwareReport (Detect.ps1), $Options: Font = 'Unispace'|'Bahnschrift', HasTimings = bool,
# StyleKey — код клавиши переключения вида (0 — без переключения), MainStyle = 'Full'|'Compact' — вид после запуска RTSS.
# В файл кладутся оба вида: большой (из шаблона) и компактная строка (Build-Compact.ps1).
function Build-Overlay([string]$Template, $Report, $Options, [string]$OutFile) {
    $ovl = Read-Ovl $Template
    $layers  = @($ovl | Where-Object { $_.Name -like 'Layer*' })
    $sources = @($ovl | Where-Object { $_.Name -like 'Source*' })
    $drop = New-Object System.Collections.Generic.HashSet[object]
    $log = New-Object System.Collections.Generic.List[string]

    function Layer([string]$Tag) { $layers | Where-Object { (Get-Key $_ 'Name') -eq $Tag } }
    function Source([string]$Name) { $sources | Where-Object { (Get-Key $_ 'Name') -eq $Name } }
    function Drop-Cell([string]$Role, [string]$Why) {
        foreach ($l in $layers) { if ((Get-Key $l 'Name') -like "cell:${Role}:*") { [void]$drop.Add($l) } }
        $log.Add("скрыто: $Role ($Why)")
    }

    $cpu = $Report.Cpu; $gpu = $Report.Gpu; $ids = $Report.Sensors

    # --- датчики LHM: роль → имя источника в шаблоне ---------------------------------------------
    $roles = [ordered]@{
        'cpu.temp' = 'CPU Package'; 'cpu.temp2' = 'E-core 11'; 'cpu.clock' = 'P-core 0 Clock'; 'cpu.clock2' = 'E-core 8 Clock'
        'cpu.power' = 'CPU power'; 'cpu.vcore' = 'Vcore'; 'ram.voltage' = 'DRAM'; 'ram.temp' = 'DIMM Temperature'
        'gpu.hotspot' = 'GPU Hot Spot Temperature'; 'gpu.memtemp' = 'GPU Memory Junction Temperature'; 'gpu.voltage' = 'GPU Core Voltage'
    }
    foreach ($role in $roles.Keys) {
        $src = Source $roles[$role]
        $id = $ids.$role
        if ($id) { Set-Key $src 'ID' $id }
        else {
            [void]$drop.Add($src)
            if ($role -notin 'cpu.temp2', 'cpu.clock2') { Drop-Cell $role 'датчик не найден' }
        }
    }

    # частота CPU и температура: P/E для гибридных Intel, одно значение для остальных
    $clock = Layer 'cell:cpu.clock:value'
    if ($ids.'cpu.clock') {
        Set-Key $clock 'Text' $(if ($ids.'cpu.clock2') { '%P-core 0 Clock%/%E-core 8 Clock%' } else { '%P-core 0 Clock%' })
    }
    $temp = Layer 'cell:cpu.temp:value'
    if ($ids.'cpu.temp') {
        Set-Key $temp 'Text' $(if ($ids.'cpu.temp2') { '%CPU Package%/%E-core 11%' } else { '%CPU Package%' })
    }

    # --- видеокарта: LHM (по точному имени карты) + HAL RTSS как запасной -----------------------------
    # Два источника с одним именем: редактор берёт последний в списке, у которого есть данные, поэтому
    # источник LHM ставится после HAL. Без датчика LHM у встройки и Intel ячейка убирается (HAL там ненадёжен).
    $gpuHal = [ordered]@{
        'gpu.clock' = 'GPU Clock'; 'gpu.fan' = 'GPU1 fan tachometer'; 'gpu.temp' = 'GPU temperature'
        'gpu.memclock' = 'GPU1 memory clock'; 'gpu.memused' = 'GPU Memory Usage'; 'gpu.power' = 'GPU1 power'; 'gpu.usage' = 'GPU1 usage'
    }
    $halReliable = -not $gpu.Integrated -and $gpu.Vendor -in 'NVIDIA', 'AMD'
    $lhmGpuSources = New-Object System.Collections.Generic.List[object]
    foreach ($role in $gpuHal.Keys) {
        $hal = Source $gpuHal[$role]
        if ($ids.$role) {
            $lhmGpuSources.Add((New-OvlSource $gpuHal[$role] 'LHM' $ids.$role (Get-Key $hal 'Units') (Get-Key $hal 'Format') (Get-Key $hal 'Formula')))
        } elseif (-not $halReliable -and $role -ne 'gpu.usage') {
            Drop-Cell $role 'у этой видеокарты нет датчика'
        }
    }

    # --- пороги перегрева: от пределов производителей -----------------------------------------------
    # CPU: Intel 12-14 gen TjMax 100 °C, AMD Ryzen 7000/9000 TjMax 95 °C (работа у 95 — штатная)
    # GPU: ядро — буст снижается с ~83 °C; Hot Spot AMD — предел 110 °C, NVIDIA/Intel — ~105 °C;
    #      память GDDR6X (NVIDIA) — ~105-110 °C, GDDR6 (AMD/Intel) — Tj max 100 °C
    # DIMM: 50/60 °C — выше разогнанная память начинает сбоить (JEDEC допускает до 85 °C)
    $cpuT = 85, 95      # Intel: 5 °C до TjMax 100; AMD: красный ровно на TjMax 95
    $hot  = if ($gpu.Vendor -eq 'AMD') { 100, 110 } else { 95, 105 }
    $mem  = if ($gpu.Vendor -eq 'NVIDIA') { 95, 105 } else { 90, 100 }
    if ($ids.'cpu.temp')    { Set-Key $temp 'TextColor' (Get-TempColor 'CPU Package' $cpuT[0] $cpuT[1]) }
    Set-Key (Layer 'cell:gpu.temp:value') 'TextColor' (Get-TempColor 'GPU temperature' 80 88)
    if ($ids.'gpu.hotspot') { Set-Key (Layer 'cell:gpu.hotspot:value') 'TextColor' (Get-TempColor 'GPU Hot Spot Temperature' $hot[0] $hot[1]) }
    if ($ids.'gpu.memtemp') { Set-Key (Layer 'cell:gpu.memtemp:value') 'TextColor' (Get-TempColor 'GPU Memory Junction Temperature' $mem[0] $mem[1]) }

    # подпись третьей строки GPU — по тому, что в ней осталось
    $row3 = if ($ids.'gpu.voltage' -and $ids.'gpu.hotspot') { 'VRM/Hot Spot' }
            elseif ($ids.'gpu.hotspot') { 'Power/Hot Spot' } elseif ($ids.'gpu.voltage') { 'VRM/Power' } else { 'Power' }
    Set-Key (Layer 'label.gpu.row3') 'Text' $row3

    # страховка в рантайме: ячейка прячется, если датчик пропал. RTSS проверяет (int)значение != 0, поэтому
    # только температуры — напряжения меньше 1 В (0.9 V GPU, Vcore в простое) спрятались бы
    foreach ($role in 'cpu.temp', 'ram.temp', 'gpu.hotspot', 'gpu.memtemp') {
        if (-not $ids.$role) { continue }
        foreach ($l in $layers) { if ((Get-Key $l 'Name') -like "cell:${role}:*") { Set-Key $l 'VisibilitySource' $roles[$role] } }
    }

    # --- тайминги ОЗУ -------------------------------------------------------------------------------
    if (-not $Options.HasTimings) {
        [void]$drop.Add((Layer 'ram.timings'))
        foreach ($n in 'Tcas', 'Trcd', 'Trp', 'Tras', 'Trc', 'Trfc') { [void]$drop.Add((Source $n)) }
        $log.Add('скрыто: тайминги ОЗУ (контроллер памяти этого CPU пока не поддерживается)')
    }

    # --- цвета подписей по производителю ------------------------------------------------------------
    $cpuColor = if ($cpu.Vendor -eq 'AMD') { $script:Palette.CpuAmd } else { $script:Palette.CpuIntel }
    $gpuColor = switch ($gpu.Vendor) { 'AMD' { $script:Palette.GpuAmd } 'Intel' { $script:Palette.GpuIntel } default { $script:Palette.GpuNvidia } }
    foreach ($l in $layers) {
        switch -Wildcard (Get-Key $l 'Name') {
            'label.cpu'   { Set-Key $l 'TextColor' $cpuColor }
            'label.gpu*'  { Set-Key $l 'TextColor' $gpuColor }
        }
    }

    # --- заголовок ----------------------------------------------------------------------------------
    # плата — белым, объём ОЗУ — цветом процессора, драйвер — цветом видеокарты, разделители — серым;
    # строка лежит на светлой полосе, чтобы читалась как заголовок
    $sep = "<C=$($script:Palette.Separator)> | "
    $memType = if ($Report.Memory.Type -and $Report.Board.Title -notmatch $Report.Memory.Type) { ' ' + $Report.Memory.Type } else { '' }
    $header = "<C=FFFFFF>$($Report.Board.Title)$sep<C=$cpuColor>%RAM%$memType"
    if ($gpu.Vendor -eq 'NVIDIA') { $header += "$sep<C=$gpuColor>%Driver%" }
    $headerLayer = Layer 'header'
    Set-Key $headerLayer 'Text' (ConvertTo-OvlText $header)

    # --- полоски загрузки потоков -------------------------------------------------------------------
    $tmplSource = Source 'CPU usage'
    $newSources = New-Object System.Collections.Generic.List[object]
    $newSources.AddRange($lhmGpuSources)
    function Add-ThreadSource([int]$n) {
        $newSources.Add((New-OvlSource "Thread $n" 'HAL' "CPU$n usage" (Get-Key $tmplSource 'Units') '' ''))
    }
    # <G=источник,ширина,высота,отступ,мин,макс,флаги>: столбик шириной «ширина» с промежутком 1
    function Set-Bars($Layer, [int[]]$Threads, [int]$Width, [int]$MaxSlot = 0) {
        $slot = [math]::Max(2, [math]::Floor($Width / [math]::Max(1, $Threads.Count)))
        if ($MaxSlot -gt 0) { $slot = [math]::Min($slot, $MaxSlot) }
        $text = ($Threads | ForEach-Object { Add-ThreadSource $_; "<G=Thread $_,$slot,0,1,0,100,38>" }) -join ''
        Set-Key $Layer 'Text' $text
        Set-Key $Layer 'ExtentX' ([string]($slot * $Threads.Count))
        return $slot
    }
    $barsP = Layer 'bars.p'; $barsE = Layer 'bars.e'
    if ($cpu.Hybrid) {
        $pSlot = Set-Bars $barsP $cpu.PThreads 128
        # E-ядра — маленькие: столбики заметно тоньше P (около 60%); блок прижат к P (X=132, зазор 4 px),
        # как в исходной раскладке, а не по центру своей области
        [void](Set-Bars $barsE $cpu.EThreads 87 ([math]::Max(3, [math]::Ceiling($pSlot * 0.6))))
    } else {
        [void](Set-Bars $barsP ($cpu.PThreads + $cpu.EThreads) 219)
        [void]$drop.Add($barsE)
    }

    # --- графики FPS и frametime --------------------------------------------------------------------
    # флаги RTSS: 1 — заливка, 0x80 — автомасштаб. FPS: залитая область с автомасштабом — видно и уровень,
    # и просадки при любом FPS (раньше шкала 0..500 прижимала 60 FPS к самому низу).
    # Frametime: линия с автомасштабом — каждый фриз виден пиком на любой частоте кадров.
    # графики по кадрам, как у RTSS (пробовали точку раз в секунду — пики frametime превращались в ровные полки)
    Set-Key (Layer 'fps.graph') 'Text' '<G=Framerate,0,0,-1,0,500,81>'
    Set-Key (Layer 'fps.graph') 'TextColor' "60$($script:Palette.Fps)"
    Set-Key (Layer 'ft.graph') 'Text' '<G=Frametime,0,0,-1,0,50,80>'
    Set-Key (Layer 'ft.graph') 'TextColor' $script:Palette.Fps

    # --- генерация кадров -------------------------------------------------------------------------
    # RTSS считает и сгенерированные кадры. При генерации (IsFG и др. — источники из Get-CompactParts, Build-Compact.ps1)
    # крупное число — реальный FPS игры, а итоговый с генерацией — в подписи над графиком: «Native Framerate  FG 120»;
    # «FG≈» — генерация внутри игры, реальный FPS оценён как итоговый пополам (≈ — значок из спрайта, Build-Compact.ps1)
    Set-Key (Layer 'fps.cur') 'Text' '<IF IsFG>%NativeFPS%<ELSE><FR><IF>'
    $curLabel = $layers | Where-Object { (Get-Key $_ 'Name') -eq 'label.fps' -and (Get-Key $_ 'Text') -eq 'Current Framerate' }
    Set-Key $curLabel 'Text' '<IF IsFG>Native Framerate  <C=6EC6FF>FG<IF IsFGApprox><I=6,7,64,0,32,32><IF IsFG><I=6,7,96,0,32,32>%FgShowN% %TotalFPS%<ELSE>Current Framerate<IF>'
    # Present Mode (источники Pm* — Build-Compact.ps1) — после разрешения: зелёный — кадры идут мимо рабочего стола
    # (iFlip, iFlip MPO, Legacy Flip/Copy — эксклюзивный полный экран), жёлтый — через рабочий стол (Composed),
    # красный — копированием (Composed Copy).
    # Блоки <IF> не вкладываются: каждый закрывает предыдущий, поэтому варианты идут цепочкой
    Set-Key (Layer 'fps.res') 'Text' ('<RES>  <IF PmIFlip><C=7DC75A>iFlip<IF PmMpo><C=7DC75A>iFlip MPO<IF PmComposed><C=FFD040>Composed' +
        '<IF PmCopy><C=FF5A5A>Composed Copy<IF PmLegacyFlip><C=7DC75A>Legacy Flip<IF PmLegacyCopy><C=7DC75A>Legacy Copy<IF>')
    # GPU Usage: залитая область цвета вендора видеокарты, шкала фиксированная 0..100 % — высота сразу читается
    # как загрузка (автомасштаб тут вреден: 20 % растягивались бы на всю высоту)
    Set-Key (Layer 'gpu.usage.graph') 'Text' '<G=GPU1 usage,0,0,-1,0,100,1>'
    Set-Key (Layer 'gpu.usage.graph') 'TextColor' "80$gpuColor"

    # --- стресс-тест разметки: самые длинные правдоподобные значения вместо датчиков -----------------
    if ($Options.Stress) {
        $samples = @{
            'cell:cpu.clock:value' = $(if ($ids.'cpu.clock2') { '6200/4600' } else { '6200' }); 'cell:cpu.vcore:value' = '1.555'
            'cell:cpu.temp:value' = $(if ($ids.'cpu.temp2') { '105/100' } else { '105' }); 'cell:cpu.usagemax:value' = '100'
            'cell:cpu.usage:value' = '100'; 'cell:cpu.power:value' = '400'
            'cell:ram.rate:value' = '8400'; 'ram.timings' = '48-48-48-128-176-1050'; 'cell:ram.used:value' = '65536'
            'cell:ram.temp:value' = '65'; 'cell:ram.voltage:value' = '1.450'
            'cell:gpu.clock:value' = '3105'; 'cell:gpu.fan:value' = '3500'; 'cell:gpu.temp:value' = '100'
            'cell:gpu.memclock:value' = '28000'; 'cell:gpu.memused:value' = '32768'; 'cell:gpu.memtemp:value' = '110'
            'cell:gpu.voltage:value' = '1.100'; 'cell:gpu.power:value' = '600'; 'cell:gpu.hotspot:value' = '110'
            'gpu.usage.value' = '100'; 'fps.avg' = '1888'; 'fps.low1' = '1888'; 'fps.low01' = '1888'
            'fps.cur' = '1888'; 'fps.ft' = '250.0'
        }
        foreach ($l in $layers) { $tag = Get-Key $l 'Name'; if ($samples.ContainsKey($tag)) { Set-Key $l 'Text' $samples[$tag] } }
    }

    # --- шрифт --------------------------------------------------------------------------------------
    $master = $ovl | Where-Object Name -eq 'Master'
    $settings = $ovl | Where-Object Name -eq 'Settings'
    Set-Key $master 'FontFace' $Options.Font
    Set-Key $settings 'LockUserSettings' '1'      # шрифт из оверлея, а не из общих настроек RTSS
    if ($ids.'cpu.temp2') {
        # «105/100» шире колонки — две температуры чуть мельче, чтобы не наезжать на «V» соседней ячейки
        Set-Key (Layer 'cell:cpu.temp:value') 'Size' '74'
    }
    if ($Options.Font -eq 'Bahnschrift') {
        # у Bahnschrift при той же высоте шрифта глифы заметно мельче Unispace — поднимаем базовую высоту;
        # он ещё и уже, так что поля, рассчитанные под Unispace, вмещают его и так
        Set-Key $master 'FontHeight' '-10'
    }

    # --- сборка: удаление, новые источники, перенумерация ------------------------------------------
    $result = New-Object System.Collections.Generic.List[object]
    $nSrc = 0; $nLay = 0; $lastSource = -1
    foreach ($s in $ovl) {
        if ($drop.Contains($s)) { continue }
        if ($s.Name -like 'Source*') { $s.Name = "Source$nSrc"; $nSrc++; $result.Add($s); $lastSource = $result.Count - 1; continue }
        if ($s.Name -like 'Layer*')  { $s.Name = "Layer$nLay";  $nLay++ }
        $result.Add($s)
    }
    foreach ($s in $newSources) { $s.Name = "Source$nSrc"; $nSrc++; $lastSource++; $result.Insert($lastSource, $s) }
    $general = $result | Where-Object Name -eq 'General'
    Set-Key $general 'Sources' ([string]$nSrc)
    Set-Key $general 'Layers' ([string]$nLay)

    $result = Add-CompactStyle $result $Report $Options $log
    Write-Ovl $result $OutFile
    return $log
}

# Компактная строка в том же файле. Какой вид показан, решает счётчик нажатий клавиши StyleKey: key(vk) из
# HotkeyHandler, бит 0 меняется при каждом нажатии (Ctrl/Alt не учитываются — RTSS считает нажатия одной клавиши).
# Чётное число нажатий — основной вид, нечётное — второй. После перезапуска RTSS счётчик с нуля → основной вид.
function Add-CompactStyle($Sections, $Report, $Options, $Log) {
    $parts = Get-CompactParts $Report
    foreach ($l in $parts.Log) { $Log.Add($l) }
    $head    = @($Sections | Where-Object { $_.Name -notlike 'Source*' -and $_.Name -notlike 'Layer*' })
    $sources = @($Sections | Where-Object { $_.Name -like 'Source*' })
    $layers  = @($Sections | Where-Object { $_.Name -like 'Layer*' })

    $key = 'key(0x{0:X2})' -f ([int]$Options.StyleKey -band 0xFF)
    $even = "($key & 1) == 0"; $odd = "($key & 1) != 0"
    $full, $compact = if ($Options.MainStyle -eq 'Compact') { $odd, $even } else { $even, $odd }
    $new = New-Object System.Collections.Generic.List[object]
    $new.Add((New-OvlSource 'StyleFull' 'HAL' 'Stub' '' '' $full))
    $new.Add((New-OvlSource 'StyleCompact' 'HAL' 'Stub' '' '' $compact))

    # слоям большого вида — видимость StyleFull; у слоёв со своей видимостью (температуры: ячейка прячется,
    # если датчик молчит) — копия их источника, обнулённая, когда показан компактный вид
    $n = 0
    foreach ($l in $layers) {
        $vis = Get-Key $l 'VisibilitySource'
        if (-not $vis) { Set-Key $l 'VisibilitySource' 'StyleFull'; continue }
        $src = $sources | Where-Object { (Get-Key $_ 'Name') -eq $vis } | Select-Object -Last 1
        $f = Get-Key $src 'Formula'; if (-not $f) { $f = 'x' }
        $new.Add((New-OvlSource "Full$n" (Get-Key $src 'Provider') (Get-Key $src 'ID') '' '' "(StyleFull) ? ($f) : 0"))
        Set-Key $l 'VisibilitySource' "Full$n"; $n++
    }
    # источники компактной строки: одноимённые уже есть в большом виде — те же данные
    $names = @($sources | ForEach-Object { Get-Key $_ 'Name' })
    foreach ($s in $parts.Sources) { if ((Get-Key $s 'Name') -notin $names) { $new.Add($s) } }

    # RTSS прижимает к краю экрана рамку всего оверлея, а OverlayEditor передаёт ему и размеры скрытых слоёв —
    # рамка всегда высотой с большой вид. Поэтому, когда оверлей у нижнего края, компактная строка рисуется копией
    # у низа этой рамки.
    $height = ($layers | ForEach-Object {
        $w = [int](Get-Key $_ 'ExtentX'); $h = [int](Get-Key $_ 'ExtentY')
        if ($w -and $h) { [int](Get-Key $_ 'PositionY') + $h } } | Measure-Object -Maximum).Maximum
    $new.Add((New-OvlSource 'CompactTop' 'HAL' 'Stub' '' '' '(StyleCompact) ? (OsdBottom == 0) : 0'))
    $new.Add((New-OvlSource 'CompactBottom' 'HAL' 'Stub' '' '' '(StyleCompact) ? (OsdBottom != 0) : 0'))
    $compactLayers = New-Object System.Collections.Generic.List[object]
    foreach ($l in $parts.Layers) {
        Set-Key $l 'VisibilitySource' 'CompactTop'
        $b = [pscustomobject]@{ Name = 'Layer?'; Keys = New-Object System.Collections.Generic.List[object] }
        foreach ($k in $l.Keys) { $b.Keys.Add([pscustomobject]@{ K = $k.K; V = $k.V }) }
        Set-Key $b 'Name' ((Get-Key $l 'Name') + '.bottom')
        Set-Key $b 'PositionY' ([string]($height - [int](Get-Key $l 'ExtentY')))
        Set-Key $b 'VisibilitySource' 'CompactBottom'
        $compactLayers.Add($l); $compactLayers.Add($b)
    }

    $allSources = [object[]]$sources + $new.ToArray(); $allLayers = [object[]]$layers + $compactLayers.ToArray()
    for ($i = 0; $i -lt $allSources.Count; $i++) { $allSources[$i].Name = "Source$i" }
    for ($i = 0; $i -lt $allLayers.Count; $i++) { $allLayers[$i].Name = "Layer$i" }
    $general = $head | Where-Object Name -eq 'General'
    Set-Key $general 'Sources' ([string]$allSources.Count)
    Set-Key $general 'Layers' ([string]$allLayers.Count)
    Set-Key ($head | Where-Object Name -eq 'Settings') 'EmbeddedImage' 'rtss-overlay-preset-icons.png'    # значки ↓↑≈×
    if ($Options.FgDebug) {
        # отладка генерации кадров: сырые признаки справа от оверлея (install.bat -FgDebug, Make-Overlay -FgDebug)
        $kv = [ordered]@{ Name = 'fg.debug'; PositionX = 232; PositionY = 0; ExtentX = 0; ExtentY = 0; ExtentOrigin = 0; Size = 60; TextColor = 'FFFFFF'; BgndColor = 'C0000000'
            Text = 'lib %FgLib% how %FgHow%  rhythm %FgRhythm% mul %FgMul% x%FgN%   ' +
                   'pres %FrameratePresented% disp %FramerateDisplayed%  drv %DrvFG% game %GameFG% raw %FgRaw% fg %IsFG%  native %NativeFPS%  pm %PresentMode%' }
        $dbg = [pscustomobject]@{ Name = 'Layer?'; Keys = New-Object System.Collections.Generic.List[object] }
        foreach ($k in $kv.Keys) { $dbg.Keys.Add([pscustomobject]@{ K = $k; V = [string]$kv[$k] }) }
        $allLayers += $dbg; $dbg.Name = "Layer$($allLayers.Count - 1)"
        Set-Key $general 'Layers' ([string]$allLayers.Count)
    }
    return @($head) + $allSources + $allLayers
}
