@echo off
rem RTSS Overlay Preset - restore RTSS files from the installer backup (asks for administrator rights)
net session >nul 2>&1
if errorlevel 1 (
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0installer\Uninstall.ps1"
echo.
pause
