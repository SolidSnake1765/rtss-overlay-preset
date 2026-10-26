# RTSS Overlay Preset — общие функции установщика и удаления.

function T([string]$Ru, [string]$En) { if ($script:RU) { $Ru } else { $En } }

function Say([string]$Text = '', [string]$Color = '', [string]$Title = '') {
    if ($Title) { Write-Host ''; Write-Host "  $Title" -ForegroundColor Cyan; Write-Host ''; return }
    if ($Color) { Write-Host $Text -ForegroundColor $Color } else { Write-Host $Text }
}
function Warn([string]$Text) { Write-Host $Text -ForegroundColor Yellow }
function Fail([string]$Text) { throw $Text }

# язык: по умолчанию — язык Windows, можно сменить в начале установки
function Select-Language([string]$Lang) {
    if ($Lang) { $script:RU = $Lang -eq 'ru'; return }
    $script:RU = (Get-Culture).TwoLetterISOLanguageName -eq 'ru'
    Write-Host ''
    Write-Host '  1 - Русский'
    Write-Host '  2 - English'
    $default = if ($script:RU) { '1' } else { '2' }
    $answer = Read-Host "  Язык / Language [$default]"
    if ($answer -eq '1') { $script:RU = $true } elseif ($answer -eq '2') { $script:RU = $false }
}

#region RTSS ----------------------------------------------------------------------------------------

# RTSS держит LHMDataProvider и хуки; редактор оверлея сразу перезапускает провайдер, поэтому останавливаем всё.
# Принудительное завершение ещё и не даёт RTSS перезаписать свои настройки при выходе.
function Stop-Rtss {
    # PresentMonDataProvider и консоль PresentMon переживают перезапуск RTSS — останавливаем и их, OverlayEditor
    # запустит их заново уже с настройками нового оверлея
    $names = 'RTSS', 'RTSSHooksLoader', 'RTSSHooksLoader64', 'EncoderServer', 'EncoderServer64', 'LHMDataProvider',
             'PresentMonDataProvider', 'PresentMon-*'
    $running = [bool](Get-Process RTSS -ErrorAction SilentlyContinue)
    if ($running) { Say (T 'Остановка RTSS...' 'Stopping RTSS...') }
    foreach ($n in $names) { Get-Process $n -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Seconds 1
    return $running
}

function Start-Rtss([string]$Dir) {
    Say (T 'Запуск RTSS...' 'Starting RTSS...')
    # сразу после принудительной остановки RTSS изредка падает при старте (хуки прошлого запуска ещё выгружаются),
    # поэтому ждём и при необходимости запускаем ещё раз
    for ($try = 1; $try -le 3; $try++) {
        Start-Sleep -Seconds 2
        Start-Process (Join-Path $Dir 'RTSS.exe') -ArgumentList '/s' -WorkingDirectory $Dir     # /s — свёрнутым в трей
        Start-Sleep -Seconds 5
        if (Get-Process RTSS -ErrorAction SilentlyContinue) { return }
    }
    Warn (T 'RTSS не запустился — запустите его вручную.' 'RTSS did not start — please start it manually.')
}

# Автозапуск RTSS с Windows — без него оверлея после перезагрузки не будет. RTSS сам делает так же:
# задача планировщика «RTSS», при входе пользователя, с наивысшими правами, RTSS.exe /s.
function Enable-RtssAutostart([string]$Dir) {
    if (Get-ScheduledTask -TaskName 'RTSS' -ErrorAction SilentlyContinue) { return $false }
    $action    = New-ScheduledTaskAction -Execute (Join-Path $Dir 'RTSS.exe') -Argument '/s'
    $trigger   = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
    $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest
    $settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 0
    Register-ScheduledTask -TaskName 'RTSS' -Action $action -Trigger $trigger -Principal $principal -Settings $settings | Out-Null
    Set-IniValue (Join-Path $Dir 'Profiles\Config') 'Settings' 'StartWithWindows' '1'
    return $true
}

# Настройки RTSS, без которых оверлей выглядит не так, как задуман.
function Set-RtssRequiredSettings([string]$Dir) {
    $global = Join-Path $Dir 'Profiles\Global'
    Set-IniValue $global 'OSD' 'EnableOSD' '1'               # «Show On-Screen Display»
    Set-IniValue $global 'OSD' 'IntegerFramerate' '1'        # FPS целым числом — иначе «61.3» не влезет в поле
    # Режим «Raster 3D» во всех рендерерах: только в нём RTSS берёт шрифт из оверлея (Unispace / Bahnschrift)
    $enc = [Text.Encoding]::GetEncoding(1251)
    $text = $enc.GetString([IO.File]::ReadAllBytes($global))
    $fixed = [regex]::Replace($text, '(?m)^Implementation=\d+', 'Implementation=2')
    if ($fixed -ne $text) { [IO.File]::WriteAllBytes($global, $enc.GetBytes($fixed)) }
    Set-IniValue (Join-Path $Dir 'Profiles\Config') 'Plugins' 'OverlayEditor.dll' '1'
    Set-IniValue (Join-Path $Dir 'Profiles\Config') 'Plugins' 'HotkeyHandler.dll' '1'
    Set-IniValue (Join-Path $Dir 'Profiles\Config') 'Settings' 'StartMinimized' '1'   # «Запускать в минимизированном состоянии»
}

#endregion
#region Горячие клавиши ---------------------------------------------------------------------------------
# HotkeyHandler.cfg: (модификаторы << 16) | код клавиши; Shift = 1, Ctrl = 2, Alt = 4, расширенная клавиша = 8.

$script:ExtendedKeys = 0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x28, 0x2D, 0x2E, 0x6F, 0x90   # PgUp…стрелки, Ins, Del, Num /, NumLock

function Format-Hotkey([int]$Value) {
    if ($Value -eq 0) { return (T 'не назначено' 'not set') }
    $mod = ($Value -shr 16) -band 0xF; $vk = $Value -band 0xFFFF
    $parts = @()
    if ($mod -band 2) { $parts += 'Ctrl' }; if ($mod -band 4) { $parts += 'Alt' }; if ($mod -band 1) { $parts += 'Shift' }
    $name = if ($vk -ge 0x60 -and $vk -le 0x69) { "Num $($vk - 0x60)" }
            elseif ($vk -ge 0x70 -and $vk -le 0x87) { "F$($vk - 0x6F)" }
            elseif ($vk -ge 0x30 -and $vk -le 0x5A) { [string][char]$vk }
            else { switch ($vk) { 0x6A { 'Num *' } 0x6B { 'Num +' } 0x6D { 'Num -' } 0x6E { 'Num .' } 0x6F { 'Num /' }
                                  0x2D { 'Insert' } 0x2E { 'Delete' } 0x24 { 'Home' } 0x23 { 'End' } 0x21 { 'Page Up' } 0x22 { 'Page Down' }
                                  0x2C { 'Print Screen' } 0x13 { 'Pause' } 0x91 { 'Scroll Lock' } 0x26 { 'Up' } 0x28 { 'Down' } 0x25 { 'Left' } 0x27 { 'Right' }
                                  default { ([ConsoleKey]$vk).ToString() } } }
    return (($parts + $name) -join '+')
}

# Сочетание из нажатия в окне (WinForms KeyEventArgs) или 0, если нажат только модификатор.
function ConvertFrom-KeyEvent($KeyCode, $Modifiers) {
    $vk = [int]$KeyCode
    if ($vk -in 0x10, 0x11, 0x12, 0x5B, 0x5C, 0xA0, 0xA1, 0xA2, 0xA3, 0xA4, 0xA5) { return 0 }    # Shift / Ctrl / Alt / Win
    $mod = 0
    if ($Modifiers -band [Windows.Forms.Keys]::Shift)   { $mod = $mod -bor 1 }
    if ($Modifiers -band [Windows.Forms.Keys]::Control) { $mod = $mod -bor 2 }
    if ($Modifiers -band [Windows.Forms.Keys]::Alt)     { $mod = $mod -bor 4 }
    if ($vk -in $script:ExtendedKeys) { $mod = $mod -bor 8 }
    return (($mod -shl 16) -bor $vk)
}

# Сочетание из текста: «Ctrl+Alt+Num 0», «Shift+F9», «Ctrl+Insert». '-' или «нет» — не назначать.
function ConvertFrom-HotkeyText([string]$Text) {
    $t = ($Text -replace '\s', '').ToLower()
    if ($t -in '-', 'нет', 'none', '0') { return 0 }
    $mod = 0; $vk = 0
    foreach ($p in $t.Split('+')) {
        switch -Regex ($p) {
            '^(ctrl|control)$'   { $mod = $mod -bor 2; continue }
            '^alt$'              { $mod = $mod -bor 4; continue }
            '^shift$'            { $mod = $mod -bor 1; continue }
            '^num(\d)$'          { $vk = 0x60 + [int]$Matches[1]; continue }
            '^num\*$'            { $vk = 0x6A; continue }
            '^num\+?$'           { $vk = 0x6B; continue }
            '^num-$'             { $vk = 0x6D; continue }
            '^num\.$'            { $vk = 0x6E; continue }
            '^num/$'             { $vk = 0x6F; continue }
            '^f(\d{1,2})$'       { $vk = 0x6F + [int]$Matches[1]; continue }
            '^[a-z0-9]$'         { $vk = [int][char]$p.ToUpper(); continue }
            '^(insert|ins)$'     { $vk = 0x2D; continue }
            '^(delete|del)$'     { $vk = 0x2E; continue }
            '^home$'             { $vk = 0x24; continue }
            '^end$'              { $vk = 0x23; continue }
            '^(pageup|pgup)$'    { $vk = 0x21; continue }
            '^(pagedown|pgdn)$'  { $vk = 0x22; continue }
            '^pause$'            { $vk = 0x13; continue }
            '^scrolllock$'       { $vk = 0x91; continue }
            default              { return -1 }
        }
    }
    if ($vk -eq 0) { return -1 }
    if ($vk -in $script:ExtendedKeys) { $mod = $mod -bor 8 }
    return (($mod -shl 16) -bor $vk)
}

# Окно с полями для сочетаний: в поле просто нажимается нужное сочетание (как в настройках самого RTSS).
# Консоль для этого не годится: Alt+цифры Numpad она превращает в ввод символа по коду и не отдаёт программе.
# Возвращает массив значений или $null, если окно показать не удалось.
function Show-HotkeyDialog($Items, [int[]]$Values) {
    try {
        Add-Type -AssemblyName System.Windows.Forms, System.Drawing
        [Windows.Forms.Application]::EnableVisualStyles()
    } catch { return $null }

    $form = New-Object Windows.Forms.Form
    $form.Text = T 'Горячие клавиши — RTSS Overlay Preset' 'Hotkeys — RTSS Overlay Preset'
    $form.FormBorderStyle = 'FixedDialog'; $form.MaximizeBox = $false; $form.MinimizeBox = $false
    $form.StartPosition = 'CenterScreen'; $form.TopMost = $true
    $form.Font = New-Object Drawing.Font('Segoe UI', 10)
    $form.ClientSize = New-Object Drawing.Size(560, 100)

    $hint = New-Object Windows.Forms.Label
    $hint.Text = T 'Щёлкните в поле и нажмите нужное сочетание клавиш. «Очистить» — не назначать.' 'Click a field and press the key combination. "Clear" leaves it unassigned.'
    $hint.SetBounds(16, 12, 528, 40)
    $form.Controls.Add($hint)

    $y = 56
    $boxes = @()
    for ($i = 0; $i -lt $Items.Count; $i++) {
        $title = New-Object Windows.Forms.Label
        $title.Text = $Items[$i].Title
        $title.Font = New-Object Drawing.Font('Segoe UI', 10, [Drawing.FontStyle]::Bold)
        $title.SetBounds(16, $y, 528, 22)
        $help = New-Object Windows.Forms.Label
        $help.Text = $Items[$i].Help
        $help.ForeColor = [Drawing.Color]::DimGray
        $help.SetBounds(16, $y + 22, 528, 40)
        $help.MaximumSize = New-Object Drawing.Size(528, 0); $help.AutoSize = $true
        $form.Controls.AddRange(@($title, $help))
        $y += 26 + $help.PreferredHeight

        $box = New-Object Windows.Forms.TextBox
        $box.ReadOnly = $true; $box.BackColor = [Drawing.Color]::White; $box.Cursor = 'Hand'
        $box.ShortcutsEnabled = $false
        $box.Tag = $Values[$i]; $box.Text = Format-Hotkey $Values[$i]
        if ($Items[$i].Single) { $box.AccessibleName = 'single' }      # одна клавиша: Ctrl/Alt/Shift отбрасываются
        $box.SetBounds(16, $y, 400, 28)
        $box.add_PreviewKeyDown({ param($s, $e) $e.IsInputKey = $true })      # Tab, стрелки и т.п. — тоже в поле
        $box.add_KeyDown({
            param($s, $e)
            $e.SuppressKeyPress = $true; $e.Handled = $true
            $v = ConvertFrom-KeyEvent $e.KeyCode $e.Modifiers
            if ($s.AccessibleName -eq 'single') { $v = $v -band 0xFF }
            if ($v) { $s.Tag = $v; $s.Text = Format-Hotkey $v }
        })
        $clear = New-Object Windows.Forms.Button
        $clear.Text = T 'Очистить' 'Clear'; $clear.Tag = $box
        $clear.SetBounds(424, $y - 1, 120, 30)
        $clear.add_Click({ param($s, $e) $s.Tag.Tag = 0; $s.Tag.Text = Format-Hotkey 0 })
        $form.Controls.AddRange(@($box, $clear))
        $boxes += $box
        $y += 46
    }

    $ok = New-Object Windows.Forms.Button
    $ok.Text = 'OK'; $ok.DialogResult = 'OK'
    $ok.SetBounds(424, $y + 4, 120, 32)
    $form.Controls.Add($ok); $form.AcceptButton = $null
    $form.ClientSize = New-Object Drawing.Size(560, ($y + 50))
    $form.add_Shown({ $form.Activate(); $ok.Focus() })

    [void]$form.ShowDialog()
    $result = @($boxes | ForEach-Object { [int]$_.Tag })
    $form.Dispose()
    return ,$result
}

# Запасной вариант без окна: сочетание вводится текстом.
function Read-HotkeyText([int]$Current) {
    while ($true) {
        $answer = Read-Host ("    [{0}]" -f (Format-Hotkey $Current))
        if (-not $answer) { return $Current }
        $v = ConvertFrom-HotkeyText $answer
        if ($v -ge 0) { return $v }
        Warn (T '    Не понял сочетание. Пример: Ctrl+Alt+Num 0, Shift+F9, Ctrl+Insert; «-» — не назначать.' '    Could not parse. Example: Ctrl+Alt+Num 0, Shift+F9, Ctrl+Insert; "-" leaves it unassigned.')
    }
}

# Назначает горячие клавиши. Клавиша переключения вида живёт не в HotkeyHandler.cfg, а в формуле оверлея
# (key(vk) — счётчик нажатий одной клавиши), поэтому её код возвращается в $script:StyleKey для Build-Overlay.
function Set-Hotkeys([string]$RtssDir, [switch]$Defaults) {
    $cfg = Join-Path $RtssDir 'Plugins\Client\HotkeyHandler.cfg'
    function Read-Cfg([string]$Key) {
        $line = if (Test-Path $cfg) { Select-String -Path $cfg -Pattern "^$Key=(.*)$" | Select-Object -First 1 } else { $null }
        if ($line) { $line.Matches[0].Groups[1].Value.Trim() } else { '' }
    }
    function Current([string]$Key, [int]$Fallback) {
        $v = Read-Cfg $Key
        $v = if ($v -match '^[0-9A-Fa-f]+$') { [Convert]::ToInt32($v, 16) } else { 0 }
        if ($v) { $v } else { $Fallback }
    }
    # текущая клавиша вида — из формулы уже установленного оверлея, иначе Scroll Lock
    $ovl = Join-Path $RtssDir 'Plugins\Client\Overlays\rtss-overlay-preset.ovl'
    $style = if (Test-Path $ovl) { Select-String -Path $ovl -Pattern 'key\(0x([0-9A-Fa-f]+)\)' | Select-Object -First 1 } else { $null }
    $style = if ($style) { [Convert]::ToInt32($style.Matches[0].Groups[1].Value, 16) } else { 0x91 }
    # версия 0.x переключала виды «программируемыми модификаторами» HotkeyHandler — убираем их
    foreach ($n in 1..4) {
        if ((Read-Cfg "OVM${n}Message") -eq 'Load' -and (Read-Cfg "OVM${n}Params") -like 'rtss-overlay-preset*.ovl') {
            foreach ($k in 'Desc', 'Message', 'Layer', 'Params') { Set-IniValue $cfg 'Settings' "OVM$n$k" '' }
            Set-IniValue $cfg 'Settings' "OVM${n}Hotkey" '00000000'
        }
    }
    $items = @(
        @{ Key = 'OSDToggleHotkey'; Default = 0x00060060
           Title = (T 'Показать / скрыть оверлей' 'Show / hide the overlay')
           Help  = (T 'Включает и выключает оверлей в игре.' 'Turns the overlay on and off in game.') },
        @{ Key = 'BenchmarkBeginHotkey'; Default = 0x00060061
           Title = (T 'Сброс статистики FPS' 'Reset FPS statistics')
           Help  = (T 'Средний FPS, 1% и 0.1% low считаются с момента запуска игры. Загрузки, ролики и меню их портят — нажмите после загрузки уровня, и статистика начнётся заново, только по геймплею. Первые секунды после сброса 1% и 0.1% показывают 0 — это нормально, данные набираются.' 'Average FPS, 1% and 0.1% low are counted from game start. Loading screens, cutscenes and menus skew them — press it after the level loads and the statistics restart from gameplay only. For the first seconds after a reset 1% and 0.1% show 0 — that is normal, data is being collected.') },
        @{ Key = 'ScreenCaptureHotkey'; Default = 0x00060062
           Title = (T 'Скриншот' 'Screenshot')
           Help  = (T 'Снимок экрана игры вместе с оверлеем.' 'Captures the game screen together with the overlay.') }
    )
    # Угол экрана: «модификаторы профиля» HotkeyHandler (PPM1..4). По нажатию PositionX или PositionY глобального
    # профиля RTSS XOR -2: 1 ↔ -1, а отрицательная координата — отступ от правого / нижнего края. RTSS применяет
    # сразу, без перезапуска. Слот — уже наш (то же свойство с XOR) или первый свободный.
    $free = @(1..4 | Where-Object { -not (Read-Cfg "PPM${_}Property") -and -not (Current "PPM${_}Hotkey" 0) })
    $corner = @(
        @{ Property = 'PositionX'; Default = 0x00060064; Desc = 'RTSS Overlay Preset: left <-> right'
           Title = (T 'Оверлей: левый ↔ правый край' 'Overlay: left ↔ right edge')
           Help  = (T 'Переносит оверлей к противоположному краю экрана. Вместе со следующей клавишей — в любой угол. Срабатывает сразу и запоминается для всех игр.' 'Moves the overlay to the opposite screen edge. Together with the next key — to any corner. Works instantly and is remembered for all games.') },
        @{ Property = 'PositionY'; Default = 0x00060068; Desc = 'RTSS Overlay Preset: top <-> bottom'
           Title = (T 'Оверлей: верх ↕ низ' 'Overlay: top ↕ bottom')
           Help  = (T 'Переносит оверлей к верхнему или нижнему краю экрана.' 'Moves the overlay to the top or bottom screen edge.') }
    )
    foreach ($c in $corner) {
        $slot = 1..4 | Where-Object { (Read-Cfg "PPM${_}Property") -eq $c.Property -and (Read-Cfg "PPM${_}Type") -eq '2' } | Select-Object -First 1
        if (-not $slot -and $free.Count) { $slot = $free[0]; $free = @($free | Select-Object -Skip 1) }
        if ($slot) { $items += $c + @{ Key = "PPM${slot}Hotkey"; Ppm = $slot } }
        else { Warn (T "  Все 4 «модификатора профиля» HotkeyHandler заняты — клавиша «$($c.Title)» не назначена." "  All 4 HotkeyHandler profile modifiers are taken — «$($c.Title)» is not assigned.") }
    }
    $items += @{ Key = ''; Default = $style; Single = $true
       Title = (T 'Переключить вид оверлея' 'Switch overlay style')
       Help  = (T 'По кругу: большой → компактная строка → большой. Только одна клавиша, без Ctrl/Alt — RTSS считает нажатия одной клавиши (они действуют и в сочетаниях). Удобна та, что в играх не нужна: Scroll Lock, Pause.' 'Cycles: full → compact line → full. A single key only, no Ctrl/Alt — RTSS counts presses of one key (presses inside combinations count too). Pick one games do not use: Scroll Lock, Pause.') }
    $values = @($items | ForEach-Object { if ($_.Single) { $_.Default } else { Current $_.Key $_.Default } })
    Say ''
    Say (T 'Горячие клавиши' 'Hotkeys') -Color Cyan
    if (-not $Defaults) {
        Say (T '  Откроется окно — нажмите в полях нужные сочетания и OK.' '  A window opens — press the combinations in its fields and click OK.')
        $picked = Show-HotkeyDialog $items $values
        if ($picked) { $values = $picked }
        else {
            # окна нет (например, нет рабочего стола) — ввод текстом
            Say (T '  Введите сочетание текстом (Ctrl+Alt+Num 0, Shift+F9 …). Enter — оставить, «-» — не назначать.' '  Type the combination (Ctrl+Alt+Num 0, Shift+F9 …). Enter keeps it, "-" leaves it unassigned.')
            for ($n = 0; $n -lt $items.Count; $n++) {
                Say "  $($items[$n].Title)"
                $values[$n] = Read-HotkeyText $values[$n]
                if ($items[$n].Single) { $values[$n] = $values[$n] -band 0xFF }
            }
        }
    }
    for ($n = 0; $n -lt $items.Count; $n++) {
        Say ''
        Say "  $($items[$n].Title): " -Color White
        Say ("    {0}" -f (Format-Hotkey $values[$n])) -Color Green
        Say "    $($items[$n].Help)" -Color DarkGray
        if ($items[$n].Single) { $script:StyleKey = $values[$n] -band 0xFF }
        else { Set-IniValue $cfg 'Settings' $items[$n].Key ('{0:X8}' -f $values[$n]) }
        if ($items[$n].Ppm) {
            # профиль '' — глобальный; тип 2 — XOR
            $p = "PPM$($items[$n].Ppm)"
            Set-IniValue $cfg 'Settings' "${p}Desc" $items[$n].Desc
            Set-IniValue $cfg 'Settings' "${p}Profile" ''
            Set-IniValue $cfg 'Settings' "${p}Property" $items[$n].Property
            Set-IniValue $cfg 'Settings' "${p}Type" '2'
            Set-IniValue $cfg 'Settings' "${p}Value" '-2'
        }
    }

    # скриншоты: формат и папка, если не настроены
    $folder = (Select-String -Path $cfg -Pattern '^ScreenCaptureFolder=(.+)$' -ErrorAction SilentlyContinue | Select-Object -First 1)
    $folder = if ($folder) { $folder.Matches[0].Groups[1].Value.Trim() } else { '' }
    if (-not $folder -or -not (Test-Path $folder)) {
        $folder = Join-Path ([Environment]::GetFolderPath('MyPictures')) 'RTSS Screenshots'
        New-Item -ItemType Directory -Force $folder | Out-Null
        Set-IniValue $cfg 'Settings' 'ScreenCaptureFolder' $folder
        Set-IniValue $cfg 'Settings' 'ScreenCaptureFormat' 'png'
        Set-IniValue $cfg 'Settings' 'CaptureOSD' '1'
    }
    Say ((T '  Скриншоты сохраняются в: ' '  Screenshots are saved to: ') + $folder) -Color DarkGray
}

#endregion
#region MSI Afterburner -------------------------------------------------------------------------------
# У Afterburner свой оверлей (через тот же RTSS): включённые в «Показывать в ОЭД» датчики рисуются поверх нашего.
# Выключаем только их вывод в оверлей (ShowInOSD=0) — разгон, вентиляторы и мониторинг Afterburner не трогаем.

function Find-Afterburner {
    $p = Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\MSI\Afterburner' -ErrorAction SilentlyContinue
    $dir = if ($p -and $p.InstallDir) { $p.InstallDir } else { "${env:ProgramFiles(x86)}\MSI Afterburner" }
    $cfg = Join-Path $dir 'Profiles\MSIAfterburner.cfg'
    if (Test-Path $cfg) { return [pscustomobject]@{ Dir = $dir; Cfg = $cfg } }
    return $null
}

function Disable-AfterburnerOsd($Afterburner, [string]$BackupDir) {
    $enc = [Text.Encoding]::GetEncoding(1251)
    $text = $enc.GetString([IO.File]::ReadAllBytes($Afterburner.Cfg))
    $count = ([regex]::Matches($text, '(?m)^ShowInOSD\s*=\s*1')).Count
    if ($count -eq 0) { return 0 }

    $exe = Join-Path $Afterburner.Dir 'MSIAfterburner.exe'
    $running = Get-Process MSIAfterburner -ErrorAction SilentlyContinue
    if ($running) {
        # Afterburner сохраняет настройки при выходе — закрываем его штатно, чтобы он не перезаписал правку
        $running | ForEach-Object { [void]$_.CloseMainWindow() }
        Start-Sleep -Seconds 3
        Get-Process MSIAfterburner -ErrorAction SilentlyContinue | Stop-Process -Force
        Start-Sleep -Seconds 1
        $text = $enc.GetString([IO.File]::ReadAllBytes($Afterburner.Cfg))
    }
    New-Item -ItemType Directory -Force (Join-Path $BackupDir 'MSI Afterburner') | Out-Null
    Copy-Item $Afterburner.Cfg (Join-Path $BackupDir 'MSI Afterburner\MSIAfterburner.cfg')

    $fixed = [regex]::Replace($text, '(?m)^(ShowInOSD\s*=\s*)1', '${1}0')
    [IO.File]::WriteAllBytes($Afterburner.Cfg, $enc.GetBytes($fixed))
    if ($running) { Start-Process $exe -WorkingDirectory $Afterburner.Dir }
    return $count
}

#endregion

# Запись ключа в INI-файл RTSS / Afterburner (ANSI), с созданием секции при необходимости.
function Set-IniValue([string]$Path, [string]$Section, [string]$Key, [string]$Value) {
    $enc = [Text.Encoding]::GetEncoding(1251)
    $lines = New-Object System.Collections.Generic.List[string]
    if (Test-Path $Path) { $lines.AddRange([string[]]($enc.GetString([IO.File]::ReadAllBytes($Path)) -split "`r?`n")) }
    while ($lines.Count -and $lines[$lines.Count - 1] -eq '') { $lines.RemoveAt($lines.Count - 1) }
    $start = $lines.IndexOf("[$Section]")
    if ($start -lt 0) { $lines.Add("[$Section]"); $lines.Add("$Key=$Value") }
    else {
        $i = $start + 1; $done = $false
        while ($i -lt $lines.Count -and $lines[$i] -notmatch '^\[') {
            if ($lines[$i] -match "^$([regex]::Escape($Key))=") { $lines[$i] = "$Key=$Value"; $done = $true; break }
            $i++
        }
        if (-not $done) { $lines.Insert($i, "$Key=$Value") }
    }
    [IO.File]::WriteAllBytes($Path, $enc.GetBytes(($lines -join "`r`n") + "`r`n"))
}
