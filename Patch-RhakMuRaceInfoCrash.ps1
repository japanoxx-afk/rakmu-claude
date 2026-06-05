param(
    [string]$ExePath = "C:\Program Files (x86)\TriggerSoft\RhakMu\Rhakmu.exe"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $ExePath)) {
    throw "File not found: $ExePath"
}

$bytes = [IO.File]::ReadAllBytes($ExePath)

# VA 0x0044545C in Rhakmu.exe, image base 0x00400000.
# File offset is RVA 0x0004545C for this PE layout.
$offset = 0x4545C

$expected = [byte[]]@(
    0x0F,0xBE,0x05,0x76,0x05,0x6E,0x00,
    0x83,0xF8,0x02,
    0x74,0x10,
    0x0F,0xBE,0x0D,0x76,0x05,0x6E,0x00,
    0x83,0xF9,0x03,
    0x0F,0x85,0xE7,0x00,0x00,0x00
)

$patch = [byte[]]@(
    # mov eax, [ebp-4]
    0x8B,0x45,0xFC,
    # cmp dword ptr [eax+4], 0
    0x83,0x78,0x04,0x00,
    # je 0x0044555F
    0x0F,0x84,0xF6,0x00,0x00,0x00,
    # pad remaining replaced bytes with NOP
    0x90,0x90,0x90,0x90,0x90,0x90,0x90,0x90,
    0x90,0x90,0x90,0x90,0x90,0x90,0x90
)

if ($patch.Length -ne $expected.Length) {
    throw "Internal patch length mismatch."
}

$current = New-Object byte[] $expected.Length
[Array]::Copy($bytes, $offset, $current, 0, $current.Length)

$alreadyPatched = $true
for ($i = 0; $i -lt $patch.Length; $i++) {
    if ($current[$i] -ne $patch[$i]) {
        $alreadyPatched = $false
        break
    }
}

if ($alreadyPatched) {
    Write-Host "Already patched: $ExePath" -ForegroundColor Yellow
    return
}

for ($i = 0; $i -lt $expected.Length; $i++) {
    if ($current[$i] -ne $expected[$i]) {
        $cur = ($current | ForEach-Object { "{0:X2}" -f $_ }) -join " "
        throw "Unexpected bytes at offset 0x$($offset.ToString('X')). Current: $cur"
    }
}

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backupPath = "$ExePath.bak_$stamp"
Copy-Item -LiteralPath $ExePath -Destination $backupPath

[Array]::Copy($patch, 0, $bytes, $offset, $patch.Length)
[IO.File]::WriteAllBytes($ExePath, $bytes)

Write-Host "Patched Rhakmu.exe race-info crash guard." -ForegroundColor Green
Write-Host "Backup: $backupPath"
