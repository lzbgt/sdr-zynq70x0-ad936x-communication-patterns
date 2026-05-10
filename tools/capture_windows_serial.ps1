param(
    [string]$Port = "COM3",
    [int]$Baud = 115200,
    [int]$Seconds = 120,
    [string]$OutFile = "serial-capture.txt"
)

$ErrorActionPreference = "Stop"

$directory = Split-Path -Parent $OutFile
if ($directory -and -not (Test-Path $directory)) {
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
}

$serial = [System.IO.Ports.SerialPort]::new($Port, $Baud, "None", 8, "One")
$serial.ReadTimeout = 200
$serial.NewLine = "`n"

$writer = [System.IO.StreamWriter]::new($OutFile, $false, [System.Text.Encoding]::UTF8)
$deadline = (Get-Date).AddSeconds($Seconds)

try {
    $serial.Open()
    $writer.WriteLine("# Serial capture")
    $writer.WriteLine("# Port: $Port")
    $writer.WriteLine("# Baud: $Baud")
    $writer.WriteLine("# Started: {0:o}" -f (Get-Date))
    $writer.WriteLine("# Duration seconds: $Seconds")
    $writer.Flush()

    while ((Get-Date) -lt $deadline) {
        try {
            $data = $serial.ReadExisting()
            if ($data.Length -gt 0) {
                $writer.Write($data)
                $writer.Flush()
                Write-Host -NoNewline $data
            } else {
                Start-Sleep -Milliseconds 100
            }
        } catch [System.TimeoutException] {
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
