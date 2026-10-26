@echo off
rem RTSS Overlay Preset - installer launcher (asks for administrator rights)
net session >nul 2>&1
rem parameters such as -Lang, -Font, -FgDebug are passed on to the elevated copy
if errorlevel 1 (
    if "%~1"=="" (
        powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    ) else (
        powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList '%*' -Verb RunAs"
    )
    exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0installer\Install.ps1" %*
echo.
pause
