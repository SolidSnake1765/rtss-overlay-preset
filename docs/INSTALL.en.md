[Русский](INSTALL.md) | **English**

# Installation

Only **RivaTuner Statistics Server 7.3.7 or newer** is required —
[standalone, from Guru3D](https://www.guru3d.com/download/rtss-rivatuner-statistics-server-download/).
MSI Afterburner, HWiNFO and AIDA64 are not needed.

## Automatic (recommended)

1. Download the archive: **Code → Download ZIP** on the repository page (or the latest release) and unpack it anywhere.
2. Run **`install.bat`** and confirm the administrator prompt.
3. Answer the questions:
   - installer **language** — Russian or English;
   - **font** — `1` Unispace or `2` Bahnschrift;
   - **hotkeys** — a window opens: click a field and press the combination, "Clear" leaves it unassigned.
4. Wait for "Done". RTSS restarts with the overlay.

### What the installer does

| Step | What happens |
|---|---|
| Find RTSS | via the registry; version ≥ 7.3.7 is checked |
| Backup | `%ProgramData%\RTSS-Overlay-Preset\backup\<date>` — everything that will be changed |
| PawnIO driver | installed silently if missing (needed for motherboard, CPU and memory timing sensors) |
| Files | into `RTSS\Plugins\Client\LHMDataProvider\`: LibreHardwareMonitor 0.9.6, `Exporter.dll`, PawnIO modules |
| Hardware | CPU, GPU, motherboard, memory; every sensor is matched by name, no hardcoded indexes |
| Overlay | `RTSS\Plugins\Client\Overlays\rtss-overlay-preset.ovl`, built for your PC |
| RTSS settings | see below |
| MSI Afterburner | if its own OSD is enabled, only that is turned off |

### Which RTSS settings change and why

| Setting | Value | Why |
|---|---|---|
| Show On-Screen Display | on | otherwise nothing is shown |
| On-Screen Display rendering mode | **Raster 3D** | only in this mode RTSS uses the preset's font |
| Show integer framerate | on | "61.3"-style FPS does not fit its box |
| OverlayEditor and HotkeyHandler plugins | on | the first draws the overlay, the second handles hotkeys |
| Start with Windows | on, if it was off | no running RTSS — no overlay in games |
| Start minimized | on | RTSS starts in the tray, no window pops up at sign-in |

Everything else (frame limiter, Reflex, stealth mode, application detection) is left as is.

### Hotkeys

| Action | Default | What it does |
|---|---|---|
| Show / hide overlay | Ctrl+Alt+Num 0 | turns the overlay on and off |
| Reset statistics | Ctrl+Alt+Num 1 | resets average FPS, 1% and 0.1% low. RTSS counts them from game start, so loading screens, cutscenes and menus drag them down. Press it after the level loads — the statistics restart from gameplay only |
| Screenshot | Ctrl+Alt+Num 2 | screen capture with the overlay into `Pictures\RTSS Screenshots` (PNG) |

To change them later: RTSS → **Setup** → **Plugins** → **HotkeyHandler.dll** → **Setup**, or simply run
`install.bat` again.

### MSI Afterburner

Afterburner is optional. If you have it, keep using it for overclocking and fans as usual. But it has its own OSD
("Show in On-Screen Display" checkboxes on the monitoring tab) that overlaps this one. The installer clears only
those checkboxes and restarts Afterburner if it was running. `uninstall.bat` puts them back.

For **NVIDIA RTX 20 / 30 / 40 / 50** cards we recommend [NV-UV](https://github.com/christianp403-spec/NV-UV) and
[NV-UV-Play](https://github.com/christianp403-spec/NV-UV-Play) for overclocking and undervolting.

### Logs and re-running

- Install log: `%ProgramData%\RTSS-Overlay-Preset\install.log`.
- Hardware report: `%ProgramData%\RTSS-Overlay-Preset\hardware-report.json`.
- **After updating RTSS** run `install.bat` again: an RTSS update brings back its old LibreHardwareMonitor files
  (with the old WinRing0 driver that antiviruses block).
- **Uninstall:** `uninstall.bat` restores RTSS (and Afterburner) files and settings to their state before the first
  install. The PawnIO driver stays (other programs use it too); remove it in "Settings → Apps" if you want.

Unattended: `install.bat -Lang en -Font Bahnschrift -Defaults`.

## Manual

The same steps by hand.

1. **PawnIO driver.** Run `payload\pawnio\PawnIO_setup.exe` and install it (the official signed installer, same as on
   [pawnio.eu](https://pawnio.eu)).
2. **Close RTSS** (tray icon → Exit).
3. **Copy files** into `C:\Program Files (x86)\RivaTuner Statistics Server\Plugins\Client\LHMDataProvider\`,
   replacing existing ones (keep a copy of the old files):
   - everything from `payload\lhm\`
   - `payload\exporter\Exporter.dll`
   - `payload\pawnio\IntelMCHBAR.bin` and `payload\pawnio\AMDFamily17.bin`
4. **Build the overlay for your PC** — PowerShell **as administrator**, in the archive folder:
   ```powershell
   powershell -ExecutionPolicy Bypass -File installer\Make-Overlay.ps1 -Font Unispace
   ```
   This creates `Documents\rtss-overlay-preset.ovl`. The script changes nothing in the system, it only reads sensors.
   Copy the file into `RTSS\Plugins\Client\Overlays\`.
5. **Enable the overlay:** start RTSS → **Setup** → **Plugins** tab → tick **OverlayEditor.dll** and
   **HotkeyHandler.dll** → select OverlayEditor → **Setup** → **Overlays → Load** → `rtss-overlay-preset.ovl`.
6. **RTSS settings:** main window — **On-Screen Display rendering mode: Raster 3D**; Setup → General —
   **Show integer framerate** and **Start minimized**.
7. **Hotkeys:** Setup → Plugins → HotkeyHandler.dll → Setup.
8. **Afterburner** (if installed): on the Monitoring tab untick "Show in On-Screen Display" for every sensor.

## Check

Start any game (or `DesktopOverlayHost.exe` from the RTSS folder). If the RAM row shows the data rate without
timings, your CPU is not supported for timings yet — everything else works. If half the cells are empty, check that
PawnIO is installed.

Something wrong? Run `installer\Detect.ps1 -Export` (PowerShell as administrator) and attach
`installer\hardware-report.json` to an issue.
