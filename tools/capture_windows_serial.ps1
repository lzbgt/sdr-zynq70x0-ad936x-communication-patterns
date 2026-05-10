param(
    [string]$Port = "COM5",
    [int]$Baud = 115200,
    [int]$Seconds = 180,
    [string]$OutFile = "serial-capture.txt"
)

$ErrorActionPreference = "Stop"

$directory = Split-Path -Parent $OutFile
if ($directory -and -not (Test-Path $directory)) {
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
}

$serial = [System.IO.Ports.SerialPort]::new($Port, $Baud, "None", 8, "One")
$serial.ReadTimeout = 200
$writer = [System.IO.StreamWriter]::new($OutFile, $false, [System.Text.Encoding]::UTF8)

function Write-Capture {
    param([string]$Text)
    if ($Text.Length -gt 0) {
        $writer.Write($Text)
        $writer.Flush()
        Write-Host -NoNewline $Text
    }
}

try {
    $serial.Open()
    $writer.WriteLine("# Serial passive capture")
    $writer.WriteLine("# Port: $Port")
    $writer.WriteLine("# Baud: $Baud")
    $writer.WriteLine("# Started: {0:o}" -f (Get-Date))
    $writer.WriteLine("# Seconds: $Seconds")
    $writer.Flush()

    $deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $deadline) {
        $data = $serial.ReadExisting()
        if ($data.Length -gt 0) {
            Write-Capture $data
        } else {
            Start-Sleep -Milliseconds 100
        }
    }
} finally {
    $writer.WriteLine()
    $writer.WriteLine("# Stopped: {0:o}" -f (Get-Date))
    $writer.Dispose()
    if ($serial.IsOpen) {
        $serial.Close()
    }
}
