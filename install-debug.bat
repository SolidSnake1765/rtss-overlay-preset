@echo off
rem RTSS Overlay Preset - the same installer plus debug lines next to the overlay (frame generation
rem signs, frame rates from PresentMon and RTSS, statistics). For bug reports: take a screenshot in the game
rem and attach it to a GitHub issue. install.bat brings back the normal view.
call "%~dp0install.bat" -FgDebug %*
