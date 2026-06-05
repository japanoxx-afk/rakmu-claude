@echo off
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Set-RhakMuNetworkPreference.ps1" %*
pause
