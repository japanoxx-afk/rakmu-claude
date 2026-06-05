param(
    [int]$DurationSeconds = 120,
    [int]$IntervalMs = 500,
    [string]$OutputPath = ""
)

$ErrorActionPreference = "SilentlyContinue"

function Get-NowStamp {
    return (Get-Date).ToString("yyyy-MM-dd HH:mm:ss.fff")
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $stamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
    $OutputPath = Join-Path (Get-Location) "rhakmu_network_watch_$stamp.log"
}

$fullPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
$dir = Split-Path -Parent $fullPath
if (-not [string]::IsNullOrWhiteSpace($dir)) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
}

function Write-WatchLine([string]$Text) {
    $Text | Tee-Object -FilePath $fullPath -Append
}

Write-WatchLine "RhakMu network watch"
Write-WatchLine "Started: $(Get-NowStamp)"
Write-WatchLine "Computer: $env:COMPUTERNAME"
Write-WatchLine "DurationSeconds: $DurationSeconds"
Write-WatchLine "IntervalMs: $IntervalMs"
Write-WatchLine "OutputPath: $fullPath"
Write-WatchLine ""

Write-WatchLine "Local IPv4 addresses:"
Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object { $_.IPAddress -notlike "169.254.*" } |
    Sort-Object InterfaceAlias,IPAddress |
    ForEach-Object {
        Write-WatchLine ("  {0,-28} {1}" -f $_.InterfaceAlias, $_.IPAddress)
    }
Write-WatchLine ""

$stopAt = (Get-Date).AddSeconds($DurationSeconds)
$lastSnapshot = ""

while ((Get-Date) -lt $stopAt) {
    $procs = @(Get-Process | Where-Object {
        $_.ProcessName -match "Rhak|Launcher|python|powershell"
    } | Sort-Object ProcessName,Id)

    $ids = @($procs | ForEach-Object { $_.Id })
    $udpRows = @()
    $tcpRows = @()

    if ($ids.Count -gt 0) {
        $udpRows = @(Get-NetUDPEndpoint | Where-Object { $ids -contains $_.OwningProcess } |
            Sort-Object OwningProcess,LocalAddress,LocalPort)
        $tcpRows = @(Get-NetTCPConnection | Where-Object { $ids -contains $_.OwningProcess } |
            Sort-Object OwningProcess,LocalAddress,LocalPort,RemoteAddress,RemotePort)
    }

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("[$(Get-NowStamp)]")
    $lines.Add("Processes:")
    if ($procs.Count -eq 0) {
        $lines.Add("  (none)")
    } else {
        foreach ($p in $procs) {
            $lines.Add(("  pid={0,-6} name={1,-20} path={2}" -f $p.Id, $p.ProcessName, $p.Path))
        }
    }

    $lines.Add("UDP endpoints:")
    if ($udpRows.Count -eq 0) {
        $lines.Add("  (none)")
    } else {
        foreach ($u in $udpRows) {
            $owner = ($procs | Where-Object { $_.Id -eq $u.OwningProcess } | Select-Object -First 1).ProcessName
            $lines.Add(("  pid={0,-6} name={1,-20} local={2}:{3}" -f $u.OwningProcess, $owner, $u.LocalAddress, $u.LocalPort))
        }
    }

    $lines.Add("TCP connections:")
    if ($tcpRows.Count -eq 0) {
        $lines.Add("  (none)")
    } else {
        foreach ($t in $tcpRows) {
            $owner = ($procs | Where-Object { $_.Id -eq $t.OwningProcess } | Select-Object -First 1).ProcessName
            $lines.Add(("  pid={0,-6} name={1,-20} local={2}:{3} remote={4}:{5} state={6}" -f $t.OwningProcess, $owner, $t.LocalAddress, $t.LocalPort, $t.RemoteAddress, $t.RemotePort, $t.State))
        }
    }
    $lines.Add("")

    $snapshot = $lines -join "`n"
    if ($snapshot -ne $lastSnapshot) {
        Write-WatchLine $snapshot
        $lastSnapshot = $snapshot
    }

    Start-Sleep -Milliseconds $IntervalMs
}

Write-WatchLine "Finished: $(Get-NowStamp)"
Write-WatchLine "Saved: $fullPath"
