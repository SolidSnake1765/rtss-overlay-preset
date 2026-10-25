# Third-party components

The `payload/` folder redistributes the following unmodified third-party files.
Each keeps its own license; full license texts are in `licenses/`.

| Files | Project | Version | License | Source code |
|---|---|---|---|---|
| `payload/lhm/LibreHardwareMonitorLib.dll` | LibreHardwareMonitor | 0.9.6 | MPL-2.0 (`licenses/MPL-2.0.txt`) | https://github.com/LibreHardwareMonitor/LibreHardwareMonitor |
| `payload/lhm/RAMSPDToolkit-NDD.dll` | RAMSPDToolkit | 1.4.2 | MPL-2.0 | https://github.com/Blacktempel/RAMSPDToolkit |
| `payload/lhm/DiskInfoToolkit.dll` | DiskInfoToolkit | 1.1.2 | MPL-2.0 | https://github.com/Blacktempel/DiskInfoToolkit |
| `payload/lhm/BlackSharp.Core.dll` | BlackSharp | 1.0.7 | MPL-2.0 | https://github.com/Blacktempel/BlackSharp |
| `payload/lhm/HidSharp.dll` | HIDSharp | 2.6.4 | Apache-2.0 (`licenses/HidSharp-LICENSE.txt`, `licenses/Apache-2.0.txt`) | https://github.com/IntergatedCircuits/HidSharp |
| `payload/lhm/System.Memory.dll`, `System.Buffers.dll`, `System.Numerics.Vectors.dll`, `System.Runtime.CompilerServices.Unsafe.dll` | .NET | — | MIT (`licenses/dotnet-runtime-MIT.txt`) | https://github.com/dotnet/runtime |
| `payload/pawnio/PawnIO_setup.exe` | PawnIO driver (official signed installer) | 2.2.0 | GPL-2.0 with IOCTL exception (`licenses/GPL-2.0.txt`) | https://github.com/namazso/PawnIO , releases: https://github.com/namazso/PawnIO.Setup |
| `payload/pawnio/IntelMCHBAR.bin`, `AMDFamily17.bin` | PawnIO.Modules (official signed modules) | 0.2.11 | LGPL-2.1 (`licenses/LGPL-2.1.txt`) | https://github.com/namazso/PawnIO.Modules |

The LibreHardwareMonitor files are taken from the official release archive
`LibreHardwareMonitor.zip` (v0.9.6, .NET Framework 4.7.2 build). The PawnIO
installer and modules are taken from the official releases and are signed by
their author.

`payload/exporter/Exporter.dll` is built from `src/Exporter` (this project, MIT).
It talks to the PawnIO driver only through its documented IOCTL interface
(PawnIOLib) and loads the unmodified official IntelMCHBAR / AMDFamily17 modules.
Memory-controller register offsets come from public Intel datasheets (Core 8th/9th, 11th, 12th gen vol. 2)
and the publicly documented AMD UMC register map; no third-party source code is included.

Not included and not redistributed: RivaTuner Statistics Server and its files
(LHMDataProvider.exe, Importer.dll, OverlayEditor.dll, the Unispace font) —
they come with RTSS itself. Bahnschrift is a Windows system font.
