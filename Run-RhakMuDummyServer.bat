@echo off
cd /d "%~dp0"
echo Stopping existing RhakMu dummy server processes...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like '*Start-RhakMuDummyServer.ps1*' -and $_.ProcessId -ne $PID } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }"
echo Starting RhakMu dummy server with live terminal logging...
powershell -NoProfile -ExecutionPolicy Bypass -File ".\Start-RhakMuDummyServer.ps1" -AutoReply none -RoomJoinIdentityMode joiner
pause
