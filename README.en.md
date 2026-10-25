[Русский](README.md) | **English**

# RTSS Overlay Preset

A ready-made monitoring overlay for **RivaTuner Statistics Server**: CPU, memory with live timings, GPU, per-thread
load, FPS / 1% / 0.1% low / frametime. Installs with one file and adapts itself to your hardware.
Two styles: **full**, i2HARD style, and a **compact single line**, Steam overlay style, with native FPS under frame generation.

> **Inspired by [i2HARD](https://www.youtube.com/@i2hard)** — this is how they set up the overlay in their hardware tests. Not an
> official i2HARD project, just a preset in their style, made with respect for their work.

| In game (Uncharted, Vulkan, 2560×1440, Bahnschrift font) | In the RTSS overlay editor |
|:---:|:---:|
| <img src="docs/images/in-game.jpg" width="400" alt="Overlay in game"> | <img src="docs/images/overlay.png" width="400" alt="Overlay in the RTSS editor"> |

**Compact line** in the style of Steam Performance Monitor:

<img src="docs/images/compact.png" alt="Compact Steam-style overlay">

## Highlights

- **Only RTSS is required.** No HWiNFO, AIDA64 or MSI Afterburner: sensors come from the LibreHardwareMonitor provider
  built into RTSS and the PawnIO driver (bundled, installed automatically).
- **Adapts to your PC.** The installer detects your CPU, GPU, motherboard and memory. Sensors your hardware does not
  have (memory temperature, Hot Spot, …) are left out; there is one load bar per CPU thread; labels use vendor colors:
  Intel — light blue, AMD — red, NVIDIA — green, Intel Arc — blue.
- **Live DRAM timings** straight from the memory controller: Intel Core 6th–14th gen, AMD Ryzen (Zen 2–5, DDR4 and DDR5).
- **Nothing overflows its box** — even 1000+ FPS, 28000 MHz memory clock or 100 °C.
- **Warning colors:** overheating and low FPS turn yellow and red.
- **Two fonts:** Unispace (classic) and Bahnschrift.
- **Two styles:** full and a compact Steam-style line. Both are installed; the installer asks which one to enable.
- **Native FPS under frame generation** (compact style): like Steam, it shows the game's real frame rate and the total
  with DLSS FG / FSR FG / AFMF / Smooth Motion — see [below](#frame-generation).
- Installer and documentation in Russian and English.

## Install

1. Install **RTSS 7.3.7 or newer** — standalone, [from Guru3D](https://www.guru3d.com/download/rtss-rivatuner-statistics-server-download/).
   MSI Afterburner is not needed.
2. Download the archive (**Code → Download ZIP** or the latest release) and unpack it.
3. Run **`install.bat`** and confirm the administrator prompt.
4. Pick the language, font, overlay style and hotkeys — the installer does the rest.

Details, including a **manual install** without the installer: [docs/INSTALL.en.md](docs/INSTALL.en.md).
**Customizing the overlay:** [docs/CUSTOMIZE.en.md](docs/CUSTOMIZE.en.md).

Uninstall — `uninstall.bat` restores everything to how it was before the install.
After updating RTSS, run `install.bat` again.

## Hotkeys

Assigned during the install — just press the combination you want.

| Action | Default | What it does |
|---|---|---|
| Show / hide overlay | Ctrl+Alt+Num 0 | turns the overlay on and off in game |
| Reset statistics | Ctrl+Alt+Num 1 | resets average FPS, 1% and 0.1% low. They are counted from game start, and loading screens, cutscenes and menus skew them — press it after the level loads and the statistics restart from gameplay only. For the first seconds after a reset 1% and 0.1% show 0 — that is normal |
| Screenshot | Ctrl+Alt+Num 2 | captures the screen with the overlay into `Pictures\RTSS Screenshots` |

## MSI Afterburner

Afterburner is **not required** — RTSS installs and works without it. If you have it (for overclocking or fan control),
keep using it as usual. Afterburner has its own on-screen display that draws over this one; if it is enabled, the
installer turns off **only that** (sensor output to the OSD) — overclocking, fan curves and monitoring are untouched.

For overclocking and undervolting **NVIDIA RTX 20 / 30 / 40 / 50** cards we recommend
[NV-UV](https://github.com/christianp403-spec/NV-UV) and [NV-UV-Play](https://github.com/christianp403-spec/NV-UV-Play)
instead of Afterburner.

## What is shown

| Block | Data |
|---|---|
| Header | motherboard, RAM size, NVIDIA driver version |
| CPU | clock (P/E on hybrid Intel), Vcore, temperature, load (busiest thread / total), power |
| RAM | data rate, timings tCL-tRCD-tRP-tRAS-tRC-tRFC, used, module temperature, voltage |
| Threads | load of every thread (P- and E-cores as separate blocks) |
| GPU | clock, fan speed, temperature, memory clock / used / temperature, voltage, power, Hot Spot, load |
| FPS | average, 1% and 0.1% low, current, FPS and frametime graphs, API, resolution |

Compact line: `FPS current ↓1% low ↑max` · FPS graph · `CPU total/↑busiest thread` · per-thread load · CPU temperature ·
`average/↑max clock` · `GPU load, temperature, VRAM used/total` · `RAM used/total`.

### Frame generation

With frame generation RTSS shows the total FPS, not the real one: "120 FPS" with DLSS FG is 60 game frames plus
60 generated. Like the Steam overlay, the compact style tells them apart using **PresentMon** (bundled with RTSS and
started automatically): it takes the time between the starts of the game's own frames, which generated frames do not
affect. When the total FPS is 1.5× the real one or more, the line becomes `FPS 60 FG 120 ↓… ↑…` — the game's real FPS
first, then the total.

Tested without frame generation; not yet tested with DLSS FG, FSR FG or AFMF — if the numbers look wrong, please open
an [issue](../../issues).

### Supported hardware

| | |
|---|---|
| CPUs | Intel Core 6th gen and newer, Core Ultra; AMD Ryzen. Timings: Intel Core 6th–14th gen and Ryzen Zen 2–5 |
| GPUs | NVIDIA GeForce, AMD Radeon, Intel Arc and Intel / AMD integrated graphics |
| Motherboards | any where LibreHardwareMonitor sees the monitoring chip (Nuvoton, ITE, Fintek…); without it there is no Vcore and memory voltage |

## Something is wrong

Run `installer\Detect.ps1 -Export` (PowerShell as administrator) and attach the generated
`installer\hardware-report.json` to an [issue](../../issues).

## Licenses

Project files — MIT (`LICENSE`). Bundled third-party components (LibreHardwareMonitor, PawnIO, …) keep their own
licenses — see [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md) and the `licenses` folder.
