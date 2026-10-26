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

The compact line is the file's last two layers: `compact` and its copy `compact.bottom` (see below); the whole line is
RTSS hypertext in the **Text** field:
`<C=RRGGBB>` — color, `<S=48>…<S=80>` — small superscript units, `<I=6,7,0,0,32,32>` / `<I=6,7,32,0,32,32>` — the ↓ and ↑
arrows from `rtss-overlay-preset-icons.png`, `<G=…>` — the FPS graph and per-thread bars inline,
`<IF IsFG>…<ELSE>…<IF>` — the frame generation variant of the line. The FPS graph is `<G=FpsSec,…>`: one point per overlay update (500 ms), about 40 s of history. Thread bars turn yellow from 70 % and red from 90 % load (`Warm<n>`, `Hot<n>` sources). Block colors: FPS `E8836B`, CPU `E5C35C`,
GPU `7DC75A`, RAM `B49DDB`. To drop part of the line, delete it from the text; to move the line, move the layer.
Background: the layer has a fixed height of 11 with the text centred, and the line's last tag `<I=8,7,0,0,2,2>` is an
invisible spacer (a transparent corner of the arrow image): without it RTSS makes the background shorter than the
text and the last "GB" sticks out.
The bottom copy: RTSS anchors the bounding box of the whole overlay to the screen edge, and OverlayEditor passes it the
extents of the hidden full style layers too — the box is always as tall as the full style. When the overlay is at the
bottom edge (negative `PositionY` in the RTSS profile — sensor `/overlay-preset/osd/data/1`), `compact.bottom` is shown
at the bottom of the box (sources `OsdBottom`, `CompactTop`, `CompactBottom`). When you change the line's text, change
it in both layers.

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
  (or pick it as the main style when installing).
- **Your own layer** for one style only: set its visibility source to `StyleFull` or `StyleCompact`.

> Running `install.bat` again rebuilds the file and overwrites manual edits — keep your version under another name.

## Present Mode

The `fps.res` layer (the resolution line): `<RES>` plus the frame presentation mode. The `PresentMode` source is a
PresentMon counter (bundled with RTSS) holding the `PM_PRESENT_MODE` code (`SDK\Include\PresentMon\PresentMonAPI.h`
in the RTSS folder):

| Code | PresentMon mode | Source | In the overlay |
|---|---|---|---|
| 3 | Hardware: Independent Flip | `PmIFlip` | green `iFlip` |
| 8 | Hardware Composed: Independent Flip (MPO hardware plane) | `PmMpo` | green `iFlip MPO` |
| 4 | Composed: Flip (through DWM) | `PmComposed` | yellow `Composed` |
| 5, 6 | Composed: Copy with GPU / CPU GDI | `PmCopy` | red `Composed Copy` |
| 1 | Hardware: Legacy Flip (exclusive fullscreen) | `PmLegacyFlip` | green `Legacy Flip` |
| 2 | Hardware: Legacy Copy to front buffer | `PmLegacyCopy` | green `Legacy Copy` |

While the mode is unknown (0 — e.g. no game), the line shows only the resolution. The variants are chained as
`<IF PmIFlip>…<IF PmMpo>…<IF>`: `<IF>` blocks do not nest, each one closes the previous. What the modes mean — the
Present Mode section of the README and ["Presentation Model in Windows"](https://andrilaz.github.io/presentation-model) by Andrilaz (in Russian).

## Frame generation

With frame generation RTSS counts the generated frames too. The sources (the **Sources** menu):

| Source | Formula | Meaning |
|---|---|---|
| `FrameratePresented`, `FramerateDisplayed` | PresentMon | frames per second from the game and on screen |
| `TotalFPS` | the larger of the two | FPS with generation |
| `DrvFG` | `FramerateDisplayed >= FrameratePresented * 1.5` | driver-level generation (AFMF, Smooth Motion) |
| `FgLib` | sensor `/overlay-preset/fg/data/0` | 1 — the game has a frame generation library |
| `FgRhythm` | sensor `/overlay-preset/fgr/data/0` | rhythm: average GPU-time jump to the next frame / average time |
| `FgMul` | sensor `/overlay-preset/fgr/data/1` | multiplier: how many frames until the pattern repeats (2…8), 0 — it does not |
| `FgN` | sensor `/overlay-preset/fgr/data/2` | the most frequent multiplier of the last 5 s — for the real FPS |
| `GameFG` | `FgLib` and `FgRhythm >= 0.25` and `FgMul >= 2` | in-game frame generation |
| `IsFG` | `swavg(FgRaw,10) >= 0.6` | 1 — frame generation present for most of the last 5 s (10 updates of 500 ms) |
| `IsFGApprox` | not driver-level | show `≈` |
| `NativeFPS` | `DrvFG ? FrameratePresented : TotalFPS / FgN` (`FgN` below 2 — divide by 2) | the game's real FPS |
| `FgShowN` | `DrvFG ? round(FramerateDisplayed / FrameratePresented) : FgN` | the multiplier in the `FG≈×4` caption (the `×` icon is `<I=6,7,96,0,32,32>`) |

The rhythm and the multiplier are computed by `Exporter.dll` (`src\Exporter\FrameRhythm.cs`) from the game's last ~240
frames in PresentMon's shared memory (`PMDPSharedMemory`, format — `SDK\Include\PMDPSharedMemory.h` in the RTSS folder):
each frame's GPU busy time (`GPUBusy`), D(k) — the average absolute difference with the frame k back; rhythm =
D(1) / average, multiplier — the smallest k in 2…8 where D(k) is at most half of D(1). Overlay formulas cannot do this:
PresentMon delivers frames in batches and `buf()` in a formula sees only the end of the batch — the previous version was
wrong two times out of three at ×3.

Measurements (Witcher 3 + OptiScaler, FSR 3.1 FG, RTX 3080 Ti, 26.10.2026), 16–40 samples per mode:

| Mode | Rhythm | Multiplier | Real FPS / total |
|---|---|---|---|
| no frame generation | 0.06–0.08 | 0 | — |
| ×2 | 1.6–2.1 | 2 | ~67 / ~134 |
| ×3 | 1.61–1.64 | 3 | ~78 / ~235 |
| ×4 | 1.49–1.53 | 4 | ~73 / ~293 |
| ×5 | 1.39–1.46 | 5 | ~66 / ~330 |
| ×6 | 1.33–1.37 | 6 (OptiScaler sometimes inserts 4 frames instead of 5) | ~61 / ~370 |

The `0.25` rhythm threshold is in the `GameFG` formula. In the game menu the rhythm drowns in noise and the sign does not
hold — that is expected.

In layer text: `<IF IsFG>…<ELSE>…<IF>`; `<IF>` blocks do not nest (each one closes the previous), so `≈` is printed by
a separate `<IF IsFGApprox><I=6,7,64,0,32,32>` block — an icon from
`rtss-overlay-preset-icons.png`: RTSS draws a small `~` as a flat dash that looks like a minus.

## Data added by this preset

Sensors and the overlay update every 500 ms: `RefreshPeriod=500` in the overlay file, and Exporter.dll resets the
LHMDataProvider timer (hard-coded to 1000 ms in RTSS) to 500 ms on every call (`src\Exporter\UpdateTimer.cs`).
Graphs add a point per update, so their history is the graph width × 0.5 s.

The preset's `Exporter.dll` adds **Memory Timings** and **Frame Generation** blocks to the RTSS LibreHardwareMonitor provider — you can use them
in your own layers:

| Source ID | What |
|---|---|
| `/overlay-preset/memory/clock/0` | effective memory data rate, MT/s |
| `/overlay-preset/memory/timing/tcl`, `trcd`, `trp`, `tras`, `trc`, `trfc` | primary timings |
| `/overlay-preset/memory/timing/tcwl`, `trefi`, `cr` | tCWL, tREFI, Command Rate (1/2) |
| `/overlay-preset/memory/data/1` | Gear (Intel) |
| `/overlay-preset/fps/data/0` | the foreground game's FPS over the last half second — from the frame buffer in RTSS shared memory (the same calculation as RTSS itself); drives the compact line's smooth FPS graph |
| `/overlay-preset/fps/data/1` | the slowest frame of the last half second, ms — from RTSS's frame time buffer (not used by the overlay right now) |
| `/overlay-preset/fps/data/2`, `3`, `4`, `8` | AVG, 1% low, 0.1% low and max (best second) of the real frames: RTSS frame times summed by the frame generation multiplier (`NativeStats.cs`); RTSS's rules — lows in integral mode (the frame at which the sum of the slowest frames reaches 1% / 0.1% of the total time) or percentile per the RTSS `PercentileCalc` setting; reset together with RTSS statistics |
| `/overlay-preset/fps/data/5`, `6`, `7` | RTSS's own AVG, 1% low, 0.1% low (for the warning colours when there is no frame generation) |
| `/overlay-preset/osd/data/0`, `data/1` | the overlay position on screen — `PositionX`, `PositionY` from the RTSS profile (the game's profile if it sets them, otherwise Global); negative means from the right / bottom edge |
| `/overlay-preset/fg/data/1` | how the library was found (for the `-FgDebug` line): 1 loaded module, 2 DLL in the game folder, 3 FSR 3 inside the exe, 0 not found; +10 — module list closed (anti-cheat) |
| `/overlay-preset/fgr/data/0`, `1`, `2` | frame generation rhythm, multiplier (2…8, 0 — none) and the multiplier over 5 s — from PresentMon frames in shared memory |
| `/overlay-preset/fg/data/0` | 1 — the foreground game has a frame generation library (DLSS-G, FSR, XeSS-FG or built-in FSR 3); the executable scan result is cached in `%ProgramData%\RTSS-Overlay-Preset\fg-cache.txt` |

Timings are read straight from the memory controller: Intel Core 6th–14th gen, AMD Ryzen (Zen 2–5). Other CPUs show
the data rate only.
