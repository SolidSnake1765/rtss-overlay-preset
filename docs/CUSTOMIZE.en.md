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

Which style is shown is decided by the `StyleFull` and `StyleCompact` sources: the formula `(key(0x91) & 1) == 0`
means an even number of Scroll Lock presses (0x91 is the key code). Full-style layers use the `StyleFull` visibility,
the temperature layers use `Full0`, `Full1`… (their sensor, zeroed in compact mode), the compact line uses
`StyleCompact`.

## Data added by this preset

The preset's `Exporter.dll` adds a **Memory Timings** block to the RTSS LibreHardwareMonitor provider — you can use it
in your own layers:

| Source ID | What |
|---|---|
| `/overlay-preset/memory/clock/0` | effective memory data rate, MT/s |
| `/overlay-preset/memory/timing/tcl`, `trcd`, `trp`, `tras`, `trc`, `trfc` | primary timings |
| `/overlay-preset/memory/timing/tcwl`, `trefi`, `cr` | tCWL, tREFI, Command Rate (1/2) |
| `/overlay-preset/memory/data/1` | Gear (Intel) |

Timings are read straight from the memory controller: Intel Core 6th–14th gen, AMD Ryzen (Zen 2–5). Other CPUs show
the data rate only.
