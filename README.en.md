[Русский](README.md) | **English**

# RTSS Overlay Preset

A ready-made monitoring overlay for **RivaTuner Statistics Server**: CPU, memory with live timings, GPU, per-thread
load, FPS / 1% / 0.1% low / frametime. Installs with one file and adapts itself to your hardware.
Two styles: **full**, i2HARD style, and a **compact single line**, Steam overlay style, with native FPS under frame generation.

> **Inspired by [i2HARD](https://www.youtube.com/@i2hard)** — this is how they set up the overlay in their hardware tests. Not an
> official i2HARD project, just a preset in their style, made with respect for their work.

| In game (Black Myth: Wukong, FSR 3 frame generation, 2560×1440) | Close-up |
|:---:|:---:|
| <img src="docs/images/in-game.jpg" width="400" alt="Overlay in game"> | <img src="docs/images/overlay.png" width="400" alt="Full style close-up"> |

**Compact line** in the style of Steam Performance Monitor — in game (real FPS 51, 103 total with frame generation) and close-up:

<img src="docs/images/compact-in-game.jpg" alt="Compact line in game">

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
- **Two fonts:** Bahnschrift (default) and Unispace (classic).
- **Two styles:** full and a compact Steam-style line. Both are installed at once; one key (Scroll Lock) cycles between them right in game.
- **Native FPS under frame generation** (both styles): like Steam, it shows the game's real frame rate and the total
  with DLSS FG / FSR FG / AFMF / Smooth Motion, the multiplier (`FG≈×3`, ×2 to ×8), and AVG / 1% / 0.1% low from the
  real frames — see [below](#frame-generation).
- **Present Mode** — how the game's frames reach the screen: green — directly, with the lowest latency; yellow and
  red — through the Windows desktop, with an extra frame of latency. Shown in the full style after the resolution —
  see [below](#present-mode).
- Installer and documentation in Russian and English.

## Install

1. Install **RTSS 7.3.7 or newer** — standalone, [from Guru3D](https://www.guru3d.com/download/rtss-rivatuner-statistics-server-download/).
   MSI Afterburner is not needed.
2. Download the archive (**Code → Download ZIP** or the latest release) and unpack it.
3. Run **`install.bat`** and confirm the administrator prompt.
4. Pick the language, font, main style and hotkeys — the installer does the rest. Both overlay styles are installed.

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
| Overlay: left ↔ right edge | Ctrl+Alt+Num 4 | moves the overlay to the opposite screen edge |
| Overlay: top ↕ bottom | Ctrl+Alt+Num 8 | moves the overlay to the top or bottom edge; together with the previous one — to any corner |
| Switch style | Scroll Lock | cycles: full → compact line → full. A single key only, no Ctrl/Alt — that is how RTSS counts presses; any key games do not use works (Scroll Lock, Pause) |

The installer asks which style is the main one — shown after RTSS starts (the full one by default).
How switching works and how to change the key by hand — [docs/CUSTOMIZE.en.md](docs/CUSTOMIZE.en.md#how-style-switching-works).

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
| FPS | average, 1% and 0.1% low, current, FPS and frametime graphs, API, resolution, Present Mode |

Compact line: `FPS current ↓1% low ↑max` · FPS graph · `CPU total/↑busiest thread` · per-thread load · CPU temperature ·
`average/↑max clock` · `GPU load, temperature, VRAM used/total` · `RAM used/total`.
Its FPS graph has one point per update (twice a second), about 40 seconds of history (like Steam); thread bars turn yellow from 70 %
and red from 90 % load.

### Frame generation

With frame generation RTSS shows the total FPS, not the real one: "90 FPS" with frame generation is 45 game frames
plus 45 generated. The overlay tells them apart in three ways:

1. **Driver-level generation** (AMD AFMF, NVIDIA Smooth Motion) — more frames reach the screen than the game presents;
   **PresentMon** (bundled with RTSS) sees this, so the real FPS is measured exactly.
2. **In-game generation** (FSR, DLSS, XeSS) — PresentMon does not mark it, so two signs are needed at once: the game
   has a frame generation library (checked by the preset's `Exporter.dll`: an FG DLL or FSR 3 built into the game
   itself; if an anti-cheat hides the game's module list, like BattlEye in GTA V, an FG DLL in the game folder)
   **and** the frame rhythm — a real frame is heavy for the GPU, generated ones are light, and the pattern repeats:
   every other frame at ×2, every 3rd, 4th or more with multi frame generation (DLSS 4 MFG, OptiScaler). `Exporter.dll`
   computes the rhythm from the last ~240 frames of PresentMon data and finds the multiplier from ×2 to ×8. The real FPS
   is the total divided by the multiplier; it is an estimate, so it is marked **`FG≈`**.
3. The sign must hold for most of the last 5 seconds — short spikes do not switch it on.

On screen:
- **full overlay** — the big number under the graph becomes the game's real FPS, the caption above the graph becomes
  `Native Framerate  FG≈×2 90` (the multiplier and the total FPS with generation);
- **compact line** — `FPS 45 FG≈×2 90 ↓… ↑…`. With driver-level generation the multiplier is measured exactly and shown without `≈`: `FG×2`;
- **AVG / 1% / 0.1% low** and the compact line's `↓` / `↑` — from the game's real frames. RTSS counts generated frames
  too: its AVG is the total FPS and its lows come from the gaps between real and generated frames, so they do not fit
  together (e.g. AVG 224 and 1% low 80 at a real ~75). `Exporter.dll` sums RTSS frame times by the multiplier (at ×3
  three in a row are one real frame) and computes the same numbers by RTSS's rules; they reset together with RTSS
  statistics (Ctrl+Alt+Num 1). Without frame generation they match RTSS's own numbers (verified).

Under FSR frame generation (OptiScaler included) the full style's FPS and frametime graphs look like a "comb": RTSS
measures the time between present calls, and such frame generation makes them in a burst (10, 1, 1 ms), while the frames
reach the screen evenly (4, 4, 4 ms). So the frametime number on the right is computed from the total FPS under frame
generation. DLSS FG on RTX 40/50 paces frames at present time already, and the RTSS graphs are flat there. Graphs from the
display changes (PresentMon `msBetweenDisplayChange`) were tried: PresentMon delivers the data in batches every ~70 ms
about 2.5 s late, and the graphs stutter even with a display delay, so the RTSS graphs stay.

Tested on an RTX 3080 Ti: Black Myth: Wukong (built-in FSR 3) and The Witcher 3 with OptiScaler (DLSS frame generation
→ FSR 3.1) at ×2, ×3, ×4, ×5 and ×6 — the multiplier is detected correctly and the real FPS is the total divided by it;
no false positives without frame generation; the total and real FPS match the Steam overlay. AFMF and Smooth Motion
are not tested yet. Steam detects frame generation differently — it hooks the DLSS and FSR 3.1+ library calls inside
the game; FSR 3.0 built into the game (as in Wukong) is invisible to it.

How it works and how to change the thresholds — [docs/CUSTOMIZE.en.md](docs/CUSTOMIZE.en.md#frame-generation).

### Present Mode

Present Mode is the path a game's frame takes to the screen (PresentMon data, bundled with RTSS). The full style shows
it in colour after the resolution:

| In the overlay | PresentMon mode | Meaning |
|---|---|---|
| 🟢 `iFlip` | Hardware: Independent Flip | the game window covers the screen and Windows hands its frames straight to the display, skipping desktop composition (DWM). Latency as in exclusive fullscreen |
| 🟢 `iFlip MPO` | Hardware Composed: Independent Flip | the same through a dedicated GPU hardware plane (Multi-Plane Overlay): works even with windows and overlays on top of the game |
| 🟢 `Legacy Flip` / `Legacy Copy` | Hardware: Legacy Flip / Copy to front buffer | old-style exclusive fullscreen — lowest latency too |
| 🟡 `Composed` | Composed: Flip | frames go through DWM: +1 frame of latency, G-Sync / FreeSync may work worse |
| 🔴 `Composed Copy` | Composed: Copy with GPU / CPU GDI | windowed mode with the old frame copy (BitBlt): +1 frame and an extra copy |

**If it shows yellow or red instead of green**, the usual suspects are a window or overlay on top of the game
(Discord overlay, Overwolf), desktop recording in NVIDIA App / AMD Adrenaline, the NIS driver upscaler, (DL)DSR,
or Windows' "Optimizations for windowed games" and "fullscreen optimizations" turned off. The best window mode in
modern games is borderless or fullscreen windowed; old DirectX 9 games can be moved to Flip with DXVK or dgVoodoo2.

A detailed write-up with pictures, MPO checks and fixes: ["Presentation Model in Windows"](https://andrilaz.github.io/presentation-model) by Andrilaz (in Russian).

### Supported hardware

| | |
|---|---|
| CPUs | Intel Core 6th gen and newer, Core Ultra; AMD Ryzen. Timings: Intel Core 6th–14th gen and Ryzen Zen 2–5 |
| GPUs | NVIDIA GeForce, AMD Radeon, Intel Arc and Intel / AMD integrated graphics |
| Motherboards | any where LibreHardwareMonitor sees the monitoring chip (Nuvoton, ITE, Fintek…); without it there is no Vcore and memory voltage |

## Something is wrong

**"RivaTuner Statistics Server not found".** The installer looks for RTSS in the registry, among running processes
and in its autostart. If RTSS was copied to its own folder without the installer and is not running now, start RTSS and
run the installer again, or pick the folder with `RTSS.exe` in the window the installer opens (unattended:
`install.bat -RtssDir "D:\Games\RTSS"`).

**Debug version — for a problem report.** If frame generation is not detected, the FPS does not match other overlays
or something else looks wrong, install the preset with **`install-debug.bat`** instead of `install.bat`. It is the same
installer, but three lines with raw data appear to the right of the overlay:

```
lib 1 how 1  rhythm 1.62 mul 3 x3  fg 1 game 1 drv 0  pm 3
RTSS Overlay Preset 1.1 debug   fps: rtss 224 pres 210 disp 208 total 224 native 75
stats real 76/52/41 max 78   rtss 224/80/56
```

- `lib` — the game has a frame generation library, `how` — how it was found (1 — loaded, 12 — file in the game folder, anti-cheat);
- `rhythm` — frame rhythm (usually 1.3–2 with frame generation, about 0.1 without), `mul` and `x` — multiplier;
- `fg`, `game`, `drv` — whether the frame generation sign is on; `pm` — Present Mode;
- `fps` — frame rate from RTSS and PresentMon, total and real;
- `stats` — AVG/1%/0.1% low from the real frames and RTSS's own.

Start the game with the problem, take a screenshot (Ctrl+Alt+Num 2) and attach it to an [issue](../../issues) with the
game, GPU and frame generation mode. Running `install.bat` again brings back the normal view.

If the hardware or sensors were detected wrong, run `installer\Detect.ps1 -Export` (PowerShell as administrator) and
attach the generated `installer\hardware-report.json` to an [issue](../../issues).

**Frame generation is no longer detected, or "FG" flickers with a wrong FPS.** Frame data comes from Windows event
tracing (via PresentMon). If Windows has not been restarted for a long time and frame monitoring tools were started
and closed many times, tracing can start losing events: PresentMon sees fewer frames than RTSS and the GPU time stops
making sense. Restarting the PC helps.

## Licenses

Project files — MIT (`LICENSE`). Bundled third-party components (LibreHardwareMonitor, PawnIO, …) keep their own
licenses — see [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md) and the `licenses` folder.

---

## My other projects

- **[Nilesoft Shell Preset](https://github.com/SolidSnake1765/nilesoft-shell-preset)**: FFmpeg in the Windows right-click
  menu: convert, compress and trim video, audio and images (NVIDIA, AMD, Intel GPUs). A Nilesoft Shell preset.
- **[Local VOT](https://github.com/SolidSnake1765/local-vot)**: Russian voice-over for your own videos with Yandex voices
  (via Yandex Disk or Google Drive), a Windows app.
- **Snake VPN**: my personal VPN service for users in Russia:
  - [Telegram bot](https://t.me/SnakeVPNServiceBot).
  - [snakeservice.tech](https://snakeservice.tech): the service website. Use it instead of the bot or together with it:
    subscription, devices, payment, support. You can sign up with Google or Discord, Telegram is not required.
  - [free.snakeservice.tech](https://free.snakeservice.tech): free proxies for Telegram. They used to be inside the bot,
    now they have their own site. No subscription needed, so save the link and share it with friends:
    it helps when Telegram does not open.
