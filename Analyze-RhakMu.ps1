param(
    [string]$InstallDir = "C:\Program Files (x86)\TriggerSoft\RhakMu",
    [string]$OutDir = ".\analysis"
)

$ErrorActionPreference = "Stop"

function Read-U16($b, [int]$o) { [BitConverter]::ToUInt16($b, $o) }
function Read-U32($b, [int]$o) { [BitConverter]::ToUInt32($b, $o) }
function Read-AsciiZ($b, [int]$o) {
    $end = $o
    while ($end -lt $b.Length -and $b[$end] -ne 0) { $end++ }
    if ($end -le $o) { return "" }
    return [Text.Encoding]::ASCII.GetString($b, $o, $end - $o)
}

function Get-Sections($b) {
    if ($b.Length -lt 0x100 -or (Read-U16 $b 0) -ne 0x5A4D) { return @() }
    $pe = Read-U32 $b 0x3C
    if ($pe + 0x18 -ge $b.Length -or (Read-U32 $b $pe) -ne 0x4550) { return @() }
    $numSections = Read-U16 $b ($pe + 6)
    $optSize = Read-U16 $b ($pe + 20)
    $secOff = $pe + 24 + $optSize
    $sections = @()
    for ($i = 0; $i -lt $numSections; $i++) {
        $o = $secOff + ($i * 40)
        if ($o + 40 -gt $b.Length) { break }
        $rawName = $b[$o..($o + 7)]
        $name = ([Text.Encoding]::ASCII.GetString($rawName)).Trim([char]0)
        $sections += [pscustomobject]@{
            Name = $name
            VirtualSize = Read-U32 $b ($o + 8)
            VirtualAddress = Read-U32 $b ($o + 12)
            RawSize = Read-U32 $b ($o + 16)
            RawPointer = Read-U32 $b ($o + 20)
            Characteristics = ("0x{0:X8}" -f (Read-U32 $b ($o + 36)))
        }
    }
    return $sections
}

function Convert-RvaToOffset($sections, [uint32]$rva) {
    foreach ($s in $sections) {
        $span = [Math]::Max([uint32]$s.VirtualSize, [uint32]$s.RawSize)
        if ($rva -ge [uint32]$s.VirtualAddress -and $rva -lt ([uint32]$s.VirtualAddress + $span)) {
            return [int64]([uint32]$s.RawPointer + ($rva - [uint32]$s.VirtualAddress))
        }
    }
    return [int64]$rva
}

function Get-PeSummary($path) {
    $b = [IO.File]::ReadAllBytes($path)
    $isPe = $b.Length -ge 0x40 -and (Read-U16 $b 0) -eq 0x5A4D
    if (-not $isPe) {
        return [pscustomobject]@{
            Path = $path
            IsPE = $false
            Machine = ""
            TimeDateStamp = ""
            Subsystem = ""
            EntryPointRva = ""
            ImageBase = ""
            Sections = @()
            ImportRva = 0
            ExportRva = 0
        }
    }

    $pe = Read-U32 $b 0x3C
    $opt = $pe + 24
    $magic = Read-U16 $b $opt
    $isPe32Plus = $magic -eq 0x20B
    $dataDir = if ($isPe32Plus) { $opt + 112 } else { $opt + 96 }
    $importRva = Read-U32 $b ($dataDir + 8)
    $exportRva = Read-U32 $b $dataDir
    $stamp = Read-U32 $b ($pe + 8)
    $dt = [DateTimeOffset]::FromUnixTimeSeconds([int64]$stamp).LocalDateTime

    return [pscustomobject]@{
        Path = $path
        IsPE = $true
        Machine = ("0x{0:X4}" -f (Read-U16 $b ($pe + 4)))
        TimeDateStamp = $dt.ToString("yyyy-MM-dd HH:mm:ss")
        Subsystem = ("0x{0:X4}" -f (Read-U16 $b ($opt + 68)))
        EntryPointRva = ("0x{0:X8}" -f (Read-U32 $b ($opt + 16)))
        ImageBase = ("0x{0:X8}" -f (Read-U32 $b ($opt + 28)))
        Sections = Get-Sections $b
        ImportRva = $importRva
        ExportRva = $exportRva
    }
}

function Get-PeImports($path) {
    $b = [IO.File]::ReadAllBytes($path)
    if ($b.Length -lt 0x40 -or (Read-U16 $b 0) -ne 0x5A4D) { return @() }
    $pe = Read-U32 $b 0x3C
    if ((Read-U32 $b $pe) -ne 0x4550) { return @() }
    $opt = $pe + 24
    $magic = Read-U16 $b $opt
    $dataDir = if ($magic -eq 0x20B) { $opt + 112 } else { $opt + 96 }
    $importRva = Read-U32 $b ($dataDir + 8)
    if ($importRva -eq 0) { return @() }
    $sections = Get-Sections $b
    $off = Convert-RvaToOffset $sections $importRva
    if ($off -lt 0 -or $off + 20 -gt $b.Length) { return @() }
    $rows = @()
    for ($i = 0; $i -lt 512; $i++) {
        $d = $off + ($i * 20)
        if ($d + 20 -gt $b.Length) { break }
        $origThunk = Read-U32 $b $d
        $nameRva = Read-U32 $b ($d + 12)
        $firstThunk = Read-U32 $b ($d + 16)
        if ($origThunk -eq 0 -and $nameRva -eq 0 -and $firstThunk -eq 0) { break }
        $nameOff = Convert-RvaToOffset $sections $nameRva
        if ($nameOff -lt 0 -or $nameOff -ge $b.Length) { break }
        $dll = Read-AsciiZ $b $nameOff
        $thunkRva = if ($origThunk -ne 0) { $origThunk } else { $firstThunk }
        $thunkOff = Convert-RvaToOffset $sections $thunkRva
        if ($thunkOff -lt 0 -or $thunkOff + 4 -gt $b.Length) {
            $rows += [pscustomobject]@{ Dll = $dll; Functions = @() }
            continue
        }
        $funcs = @()
        for ($j = 0; $j -lt 2048; $j++) {
            $to = $thunkOff + ($j * 4)
            if ($to + 4 -gt $b.Length) { break }
            $val = Read-U32 $b $to
            if ($val -eq 0) { break }
            if (($val -band 0x80000000) -ne 0) {
                $funcs += ("Ordinal_{0}" -f ($val -band 0xFFFF))
            } else {
                $no = Convert-RvaToOffset $sections $val
                if ($no + 2 -lt $b.Length) { $funcs += (Read-AsciiZ $b ($no + 2)) }
            }
        }
        $rows += [pscustomobject]@{ Dll = $dll; Functions = $funcs }
    }
    return $rows
}

function Get-PeExports($path) {
    $b = [IO.File]::ReadAllBytes($path)
    if ($b.Length -lt 0x40 -or (Read-U16 $b 0) -ne 0x5A4D) { return @() }
    $pe = Read-U32 $b 0x3C
    $opt = $pe + 24
    $magic = Read-U16 $b $opt
    $dataDir = if ($magic -eq 0x20B) { $opt + 112 } else { $opt + 96 }
    $exportRva = Read-U32 $b $dataDir
    if ($exportRva -eq 0) { return @() }
    $sections = Get-Sections $b
    $off = Convert-RvaToOffset $sections $exportRva
    if ($off + 40 -gt $b.Length) { return @() }
    $numNames = Read-U32 $b ($off + 24)
    $addrNames = Read-U32 $b ($off + 32)
    $namesOff = Convert-RvaToOffset $sections $addrNames
    if ($namesOff -lt 0 -or $namesOff + 4 -gt $b.Length) { return @() }
    $exports = @()
    for ($i = 0; $i -lt $numNames; $i++) {
        $nameRva = Read-U32 $b ($namesOff + ($i * 4))
        $nameOff = Convert-RvaToOffset $sections $nameRva
        if ($nameOff -ge 0 -and $nameOff -lt $b.Length) {
            $exports += (Read-AsciiZ $b $nameOff)
        }
    }
    return $exports
}

function Get-AsciiStrings($path, [int]$minLen = 4) {
    $b = [IO.File]::ReadAllBytes($path)
    $out = New-Object System.Collections.Generic.List[string]
    $buf = New-Object System.Collections.Generic.List[byte]
    foreach ($x in $b) {
        if ($x -ge 0x20 -and $x -le 0x7E) {
            $buf.Add($x)
        } else {
            if ($buf.Count -ge $minLen) { $out.Add([Text.Encoding]::ASCII.GetString($buf.ToArray())) }
            $buf.Clear()
        }
    }
    if ($buf.Count -ge $minLen) { $out.Add([Text.Encoding]::ASCII.GetString($buf.ToArray())) }
    return $out
}

function Get-Utf16LeStrings($path, [int]$minLen = 4) {
    $b = [IO.File]::ReadAllBytes($path)
    $out = New-Object System.Collections.Generic.List[string]
    $chars = New-Object System.Collections.Generic.List[byte]
    for ($i = 0; $i + 1 -lt $b.Length; $i += 2) {
        if ($b[$i + 1] -eq 0 -and $b[$i] -ge 0x20 -and $b[$i] -le 0x7E) {
            $chars.Add($b[$i])
        } else {
            if ($chars.Count -ge $minLen) { $out.Add([Text.Encoding]::ASCII.GetString($chars.ToArray())) }
            $chars.Clear()
        }
    }
    if ($chars.Count -ge $minLen) { $out.Add([Text.Encoding]::ASCII.GetString($chars.ToArray())) }
    return $out
}

function Select-InterestingStrings($strings) {
    $pat = '([0-9]{1,3}\.){3}[0-9]{1,3}|[A-Za-z0-9_-]+(\.[A-Za-z0-9_-]+)+|http|ftp|server|patch|login|account|password|channel|room|rank|socket|connect|port|packet|version|TGNet|Trigger|Rhak|RHAK|Battle|DirectPlay|IPX|UDP|TCP'
    $strings | Where-Object { $_ -match $pat } | Sort-Object -Unique
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$targets = @(
    "Launcher.exe",
    "Rhakmu.exe",
    "Rhakmu.000",
    "TG_Net.dll",
    "TG_Net.BGF",
    "GameCtrl.dll",
    "WG_IPX.dll",
    "wsock32.dll",
    "dpwsockx.dll",
    "ipxwrapper.dll"
)

$report = New-Object System.Collections.Generic.List[string]
$report.Add("# RhakMu Static Analysis")
$report.Add("")
$report.Add("InstallDir: $InstallDir")
$report.Add("Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$report.Add("")

foreach ($name in $targets) {
    $path = Join-Path $InstallDir $name
    if (-not (Test-Path -LiteralPath $path)) { continue }
    $item = Get-Item -LiteralPath $path
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash
    $summary = Get-PeSummary $path
    $imports = Get-PeImports $path
    $exports = Get-PeExports $path
    $ascii = Get-AsciiStrings $path 4
    $wide = Get-Utf16LeStrings $path 4
    $interesting = Select-InterestingStrings ($ascii + $wide)

    $safe = $name -replace '[^\w.-]', '_'
    $stringsFile = Join-Path $OutDir "$safe.interesting_strings.txt"
    $importsFile = Join-Path $OutDir "$safe.imports.txt"
    $exportsFile = Join-Path $OutDir "$safe.exports.txt"

    "" | Set-Content -LiteralPath $importsFile -Encoding UTF8
    $interesting | Set-Content -LiteralPath $stringsFile -Encoding UTF8
    foreach ($imp in $imports) {
        "[$($imp.Dll)]" | Add-Content -LiteralPath $importsFile -Encoding UTF8
        $imp.Functions | ForEach-Object { "  $_" } | Add-Content -LiteralPath $importsFile -Encoding UTF8
    }
    $exports | Set-Content -LiteralPath $exportsFile -Encoding UTF8

    $report.Add("## $name")
    $report.Add("")
    $report.Add("- Size: $($item.Length)")
    $report.Add("- LastWriteTime: $($item.LastWriteTime)")
    $report.Add("- SHA256: $hash")
    $report.Add("- PE: $($summary.IsPE)")
    if ($summary.IsPE) {
        $report.Add("- Machine: $($summary.Machine)")
        $report.Add("- Timestamp: $($summary.TimeDateStamp)")
        $report.Add("- ImageBase: $($summary.ImageBase)")
        $report.Add("- EntryPointRva: $($summary.EntryPointRva)")
        $report.Add("- ImportRva: 0x{0:X8}" -f $summary.ImportRva)
        $report.Add("- ExportRva: 0x{0:X8}" -f $summary.ExportRva)
        $report.Add("")
        $report.Add("Sections:")
        foreach ($s in $summary.Sections) {
            $line = "- {0}: VA=0x{1:X8} VSz=0x{2:X8} Raw=0x{3:X8} RawSz=0x{4:X8} Ch={5}" -f $s.Name, $s.VirtualAddress, $s.VirtualSize, $s.RawPointer, $s.RawSize, $s.Characteristics
            $report.Add($line)
        }
    }
    $report.Add("")
    $report.Add("Imports: $($imports.Count) DLLs -> analysis/$safe.imports.txt")
    $report.Add("Exports: $($exports.Count) names -> analysis/$safe.exports.txt")
    $report.Add("Interesting strings: $($interesting.Count) -> analysis/$safe.interesting_strings.txt")
    $report.Add("")
}

$reportPath = Join-Path $OutDir "rhakmu_static_report.md"
$report | Set-Content -LiteralPath $reportPath -Encoding UTF8
Write-Output (Resolve-Path -LiteralPath $reportPath)
