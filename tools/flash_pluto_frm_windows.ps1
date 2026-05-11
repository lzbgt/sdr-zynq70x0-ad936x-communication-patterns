param(
    [Parameter(Mandatory = $true)]
    [string]$FrmPath,
    [string]$VolumeLabel = "PlutoSDR",
    [string]$Port = "COM5",
    [int]$Baud = 115200,
    [int]$SecondsAfterCopy = 180,
    [string]$OutFile = "serial-flash-capture.txt"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $FrmPath)) {
    throw "Firmware file not found: $FrmPath"
}

$disk = Get-CimInstance Win32_LogicalDisk |
    Where-Object { $_.VolumeName -eq $VolumeLabel } |
    Select-Object -First 1

if (-not $disk) {
    throw "No removable volume found with label $VolumeLabel"
}

$drive = $disk.DeviceID
$target = Join-Path "$drive\" "pluto.frm"
$frm = Get-Item $FrmPath

if ($disk.FreeSpace -lt $frm.Length) {
    throw "Not enough free space on ${drive}: need $($frm.Length), have $($disk.FreeSpace)"
}

$directory = Split-Path -Parent $OutFile
if ($directory -and -not (Test-Path $directory)) {
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
}

$serial = $null
$writer = [System.IO.StreamWriter]::new($OutFile, $false, [System.Text.Encoding]::UTF8)

function Write-Capture {
    param([string]$Text)
    if ($Text.Length -gt 0) {
        $writer.Write($Text)
        $writer.Flush()
        Write-Host -NoNewline $Text
    }
}

function Read-For {
    param([int]$Milliseconds)
    if (-not $serial -or -not $serial.IsOpen) {
        Start-Sleep -Milliseconds $Milliseconds
        return
    }
    $deadline = (Get-Date).AddMilliseconds($Milliseconds)
    while ((Get-Date) -lt $deadline) {
        $data = $serial.ReadExisting()
        if ($data.Length -gt 0) {
            Write-Capture $data
        } else {
            Start-Sleep -Milliseconds 100
        }
    }
}

try {
    $writer.WriteLine("# Pluto firmware flash capture")
    $writer.WriteLine("# Started: {0:o}" -f (Get-Date))
    $writer.WriteLine("# FrmPath: $FrmPath")
    $writer.WriteLine("# Target: $target")
    $writer.WriteLine("# Size: $($frm.Length)")
    $writer.Flush()

    if ($Port.Length -gt 0) {
        $serial = [System.IO.Ports.SerialPort]::new($Port, $Baud, "None", 8, "One")
        $serial.ReadTimeout = 200
        $serial.Open()
        Read-For 1000
    }

    Copy-Item -Force $FrmPath $target
    $writer.WriteLine("# Copied: {0:o}" -f (Get-Date))
    $writer.Flush()
    Write-Host "Copied $FrmPath to $target"

    Read-For ($SecondsAfterCopy * 1000)
} finally {
    $writer.WriteLine()
    $writer.WriteLine("# Stopped: {0:o}" -f (Get-Date))
    $writer.Dispose()
    if ($serial -and $serial.IsOpen) {
        $serial.Close()
    }
}
