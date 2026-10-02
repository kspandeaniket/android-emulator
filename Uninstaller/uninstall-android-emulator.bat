@echo off
rem Double-click wrapper: keep this file in the same folder as uninstall-android-emulator.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall-android-emulator.ps1" %*
echo.
pause
