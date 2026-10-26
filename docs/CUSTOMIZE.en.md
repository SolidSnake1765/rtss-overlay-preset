[Русский](CUSTOMIZE.md) | **English**

# Customizing the overlay

The overlay is a regular RTSS file, `rtss-overlay-preset.ovl`, and can be changed in the overlay editor built into RTSS.

> **Before editing**, save a copy under your own name (**Overlays → Save as**, e.g. `rtss-overlay-preset-my.ovl`).
> Running `install.bat` again rebuilds `rtss-overlay-preset.ovl` and overwrites your changes in it.

## Opening the editor

RTSS → **Setup** → **Plugins** tab → select **OverlayEditor.dll** → **Setup**.
Mouse wheel zooms. The thin grey frames around every element are shown only in the editor, not in game.

## Basics

| I want to | Where |
|---|---|
| Move an element | drag it with the mouse (grid snapping: **View → Snap to grid**) |
| Change text, color, size | double-click a layer → **Layer properties**: **Hypertext**, **Custom text color**, **Text size, in percents** |
| Change the font | **Overlays → Edit** (Ctrl+Enter) → **Master settings** (the overlay keeps its own font while **Lock user settings** is on) |
| Remove an element | select the layer → Delete |
| Add your own sensor | **Sources → Edit** (Ctrl+D) → add a source → provider **LibreHardwareMonitor** or **Internal HAL** → pick the sensor; then write `%Source name%` in a layer's hypertext |
| Save | **Overlays → Save** (Ctrl+S) or **Save as** |
| Share | **Overlays → Export** — an `.ovx` file with all images embedded |

Menu names may differ slightly between RTSS versions and languages.

## Layer text

- `%CPU Package%` — the value of the data source with that name (see the **Sources** menu).
- `%CPU%`, `%GPU%`, `%RAM%`, `%Driver%` — built-in macros: CPU model, GPU model, RAM size, NVIDIA driver.
- `<FR>`, `<FT>`, `<FRAVG>`, `<FR10L>`, `<FR01L>` — FPS, frametime, average, 1% and 0.1% low.
- `<API>`, `<RES>` — the game's graphics API and resolution.
- `<G=Source name,width,height,margin,min,max,flags>` — a graph / bar (the per-thread bars are drawn this way).

## Warning colors

Temperatures and FPS change color at thresholds. It is the **Custom text color** field, like

```
FFFFFF,,85,FFD040,85,95,FF4848,95,(CPU Package,0)
```

— white below 85, yellow 85–95, red from 95, driven by the `CPU Package` source. Change the numbers to change the
thresholds.

| Sensor | Yellow | Red | Why |
|---|---|---|---|
| CPU | 85 °C | 95 °C | Intel 12th–14th gen limit is 100 °C; AMD Ryzen 7000/9000 run up to 95 °C by design |
| GPU (core) | 80 °C | 88 °C | clocks start to drop at about 83 °C |
| Hot Spot | NVIDIA/Intel 95, AMD 100 °C | NVIDIA/Intel 105, AMD 110 °C | AMD's Hot Spot limit is 110 °C |
| Video memory | NVIDIA 95, AMD/Intel 90 °C | NVIDIA 105, AMD/Intel 100 °C | GDDR6X ~105–110 °C, GDDR6 100 °C |
| Memory modules | 50 °C | 60 °C | overclocked memory gets unstable above that |
| FPS | < 60 | < 30 | |

## Compact line

The compact line is the file's last layer (`compact`): the whole line is RTSS hypertext in its **Text** field:
`<C=RRGGBB>` — color, `<S=48>…<S=80>` — small superscript units, `<I=6,7,0,0,32,32>` / `<I=6,7,32,0,32,32>` — the ↓ and ↑
arrows from `rtss-overlay-preset-icons.png`, `<G=…>` — the FPS graph and per-thread bars inline,
`<IF IsFG>…<ELSE>…<IF>` — the frame generation variant of the line. Block colors: FPS `E8836B`, CPU `E5C35C`,
GPU `7DC75A`, RAM `B49DDB`. To drop part of the line, delete it from the text; to move the line, move the layer.

## How style switching works

**Both styles are in one file.** `rtss-overlay-preset.ovl` holds all the full overlay layers and the compact line layer
(the last one, `compact`). Every layer has a **visibility source**: the layer is drawn only while that source is not
zero.

**Two helper sources decide** (the **Sources** menu):

| Source | Formula | Equals 1 when |
|---|---|---|
| `StyleFull` | `(key(0x91) & 1) == 0` | the press count is even (0, 2, 4…) — the full overlay is shown |
| `StyleCompact` | `(key(0x91) & 1) != 0` | the press count is odd (1, 3, 5…) — the compact line is shown |

`key(0x91)` is a built-in RTSS function: the press counter of the key with code `0x91` (Scroll Lock). The counting is
done by the **HotkeyHandler** plugin, so it must be enabled. `& 1` is the counter's last bit, i.e. even / odd.
The counter tracks one key and does not see Ctrl/Alt, so a combination cannot be used. After RTSS restarts the counter
is 0 again and the main style is shown.

**Layers are bound to them:** full-style layers use `StyleFull` visibility, the compact line uses `StyleCompact`.
Temperature cells already hid themselves when the sensor is silent, so they have their own sources `Full0`, `Full1`… —
a copy of the sensor with the formula `(StyleFull) ? (x) : 0`: the sensor value in full style, 0 in compact.

### Changing it

- **Easiest** — run `install.bat` again: the hotkey window has a "Switch overlay style" item.
- **Another key by hand:** in the `StyleFull` and `StyleCompact` formulas replace `0x91` with the code of your key:

  | Key | Code | | Key | Code |
  |---|---|---|---|---|
  | Scroll Lock | `0x91` | | Insert | `0x2D` |
  | Pause | `0x13` | | Home | `0x24` |
  | F12 | `0x7B` | | Num 0 … Num 9 | `0x60` … `0x69` |

  The rest are in Microsoft's
  [Virtual-Key Codes](https://learn.microsoft.com/windows/win32/inputdev/virtual-key-codes) table.
- **Make the compact style the main one:** swap `== 0` and `!= 0` in these two formulas
  (or install with `install.bat -Style Compact`).
- **Your own layer** for one style only: set its visibility source to `StyleFull` or `StyleCompact`.

> Running `install.bat` again rebuilds the file and overwrites manual edits — keep your version under another name.

## Frame generation

With frame generation RTSS counts the generated frames too. The sources (the **Sources** menu):

| Source | Formula | Meaning |
|---|---|---|
| `FrameratePresented`, `FramerateDisplayed` | PresentMon | frames per second from the game and on screen |
| `TotalFPS` | the larger of the two | FPS with generation |
| `DrvFG` | `FramerateDisplayed >= FrameratePresented * 1.5` | driver-level generation (AFMF, Smooth Motion) |
| `FgLib` | sensor `/overlay-preset/fg/data/0` | 1 — the game has a frame generation library |
| `GpuActive` | PresentMon `msGpuActive` | GPU time spent on a frame |
| `GpuJump1`, `GpuJump2` | absolute `buf(GpuActive,-1) - buf(GpuActive,-2)` and `…-3)` | jump to the next frame and to the one after |
| `GpuAlt` | `swavg(GpuJump1,64) / swavg(GpuActive,64)` | jump size relative to the average time |
| `GpuAltRatio` | `swavg(GpuJump1,64) / swavg(GpuJump2,64)` | the jumps alternate every frame rather than at random |
| `GameFG` | `FgLib` and `GpuAlt >= 0.25` and `GpuAltRatio >= 2` | in-game frame generation |
| `IsFG` | `swavg(FgRaw,3) > 0.9` | 1 — frame generation held for 3 s |
| `IsFGApprox` | not driver-level | show `~` |
| `NativeFPS` | `DrvFG ? FrameratePresented : TotalFPS / 2` | the game's real FPS |

Measured in Black Myth: Wukong (FSR 3): `GpuAlt` 0.43–0.6 with frame generation, 0.04–0.07 without; `GpuAltRatio`
4–6 and about 1. The `0.25` and `2` thresholds are in the `GameFG` formula. `buf(Name,-1)` is the last frame in the
PresentMon buffer; `buf(x,…)` does not work inside PresentMon source formulas — only by source name.

In layer text: `<IF IsFG>…<ELSE>…<IF>`; `<IF>` blocks do not nest (each one closes the previous), so `~` is printed by
a separate `<IF IsFGApprox>~` block.

## Data added by this preset

The preset's `Exporter.dll` adds **Memory Timings** and **Frame Generation** blocks to the RTSS LibreHardwareMonitor provider — you can use them
in your own layers:

| Source ID | What |
|---|---|
| `/overlay-preset/memory/clock/0` | effective memory data rate, MT/s |
| `/overlay-preset/memory/timing/tcl`, `trcd`, `trp`, `tras`, `trc`, `trfc` | primary timings |
| `/overlay-preset/memory/timing/tcwl`, `trefi`, `cr` | tCWL, tREFI, Command Rate (1/2) |
| `/overlay-preset/memory/data/1` | Gear (Intel) |
| `/overlay-preset/fg/data/0` | 1 — the foreground game has a frame generation library (DLSS-G, FSR, XeSS-FG or built-in FSR 3); the executable scan result is cached in `%ProgramData%\RTSS-Overlay-Preset\fg-cache.txt` |

Timings are read straight from the memory controller: Intel Core 6th–14th gen, AMD Ryzen (Zen 2–5). Other CPUs show
the data rate only.
