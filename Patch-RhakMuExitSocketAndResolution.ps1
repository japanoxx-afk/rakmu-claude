$ErrorActionPreference = "Stop"

$gameDir = "C:\Program Files (x86)\TriggerSoft\RhakMu"
$exePath = Join-Path $gameDir "Rhakmu.exe"
$configPath = Join-Path $gameDir "DDrawCompat-Rhakmu.ini"

if (-not (Test-Path -LiteralPath $exePath)) {
    throw "Rhakmu.exe not found: $exePath"
}

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backupPath = Join-Path $gameDir "Rhakmu.exe.bak_exitsocket_$timestamp"
Copy-Item -LiteralPath $exePath -Destination $backupPath -Force

$bytes = [System.IO.File]::ReadAllBytes($exePath)

# classNETMANAGER::Init_ClientSocket failure path:
#   push 0; push caption; push "ClientSocket Create Error!"; push hwnd; call MessageBoxA
# Keep the failed return value/log path intact, but suppress the modal popup during game exit.
$offset = 0x2342F
$expected = [byte[]]@(
    0x6A,0x00,
    0x68,0xF0,0xC8,0x4E,0x00,
    0x68,0x4C,0xC9,0x4E,0x00,
    0x8B,0x4D,0xF0,
    0x8B,0x91,0x0C,0x03,0x00,0x00,
    0x52,
    0xFF,0x15,0x30,0xB3,0x4E,0x00
)

for ($i = 0; $i -lt $expected.Length; $i++) {
    if ($bytes[$offset + $i] -ne $expected[$i]) {
        $actual = ($bytes[$offset..($offset + $expected.Length - 1)] | ForEach-Object { $_.ToString("X2") }) -join " "
        $want = ($expected | ForEach-Object { $_.ToString("X2") }) -join " "
        throw "Unexpected bytes at 0x$($offset.ToString('X')).`nExpected: $want`nActual:   $actual"
    }
}

for ($i = 0; $i -lt $expected.Length; $i++) {
    $bytes[$offset + $i] = 0x90
}

[System.IO.File]::WriteAllBytes($exePath, $bytes)

# DDrawCompat default is borderless + desktop resolution. That prevents RhakMu's
# in-game resolution option from changing the actual display mode.
$config = @"
# RhakMu DirectDraw compatibility overrides
# Stable startup mode. Exclusive/app mode can black-screen and exit on this setup.
FullscreenMode = borderless
DisplayResolution = desktop
DesktopResolution = desktop
ResolutionScale = app(1)
SupportedResolutions = native, 640x480, 800x600, 1024x768
"@

[System.IO.File]::WriteAllText($configPath, $config, [System.Text.Encoding]::ASCII)

Write-Host "Patched Rhakmu.exe"
Write-Host "Backup: $backupPath"
Write-Host "Wrote DDrawCompat config: $configPath"
