[Русский](README.md) | **English**

# RTSS Overlay Preset

A ready-made monitoring overlay for **RivaTuner Statistics Server**: CPU, memory with live timings, GPU, per-thread
load, FPS / 1% / 0.1% low / frametime. Installs with one file and adapts itself to your hardware.

> **Inspired by [i2HARD](https://www.youtube.com/@i2hard)** — this is how they set up the overlay in their hardware tests. Not an
> official i2HARD project, just a preset in their style, made with respect for their work.

<img src="docs/images/overlay.png" width="560" alt="Overlay">

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
- Installer and documentation in Russian and English.

## Install

1. Install **RTSS 7.3.7 or newer** — standalone, [from Guru3D](https://www.guru3d.com/download/rtss-rivatuner-statistics-server-download/).
   MSI Afterburner is not needed.
2. Download the archive (**Code → Download ZIP** or the latest release) and unpack it.
3. Run **`install.bat`** and confirm the administrator prompt.
4. Pick the language, font and hotkeys — the installer does the rest.

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
