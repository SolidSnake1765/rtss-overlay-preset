@echo off
rem Builds payload\exporter\Exporter.dll with csc.exe from .NET Framework 4.x (C# 5, no SDK needed).
setlocal
set CSC=%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe
cd /d "%~dp0"
"%CSC%" /nologo /target:library /platform:anycpu /optimize+ /out:..\..\payload\exporter\Exporter.dll ^
  /r:..\..\payload\lhm\LibreHardwareMonitorLib.dll /r:System.Management.dll /r:System.Xml.dll /r:System.Core.dll Exporter.cs MemoryTimings.cs FrameGenProbe.cs RtssFramerate.cs OsdPosition.cs UpdateTimer.cs
if errorlevel 1 exit /b 1
echo OK: payload\exporter\Exporter.dll
