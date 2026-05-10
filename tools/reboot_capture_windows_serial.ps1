param(
    [string]$Port = "COM5",
    [int]$Baud = 115200,
    [int]$SecondsAfterReboot = 150,
    [string]$OutFile = "serial-reboot-capture.txt",
    [string]$LoginUser = "root",
    [string]$Password = "analog"
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

function Send-Line {
    param([string]$Line)
    $writer.WriteLine()
    $writer.WriteLine("# >>> $Line")
    $writer.Flush()
    $serial.Write("$Line`r")
    Start-Sleep -Milliseconds 250
    Read-For 750
}

try {
    $serial.Open()
    $writer.WriteLine("# Serial reboot capture")
    $writer.WriteLine("# Port: $Port")
    $writer.WriteLine("# Baud: $Baud")
    $writer.WriteLine("# Started: {0:o}" -f (Get-Date))
    $writer.WriteLine("# SecondsAfterReboot: $SecondsAfterReboot")
    $writer.Flush()

    Read-For 1000
    Send-Line ""
    Send-Line $LoginUser
    Send-Line $Password
    Send-Line ""

    Send-Line "echo __SDR_Z203_PRE_REBOOT__"
    Send-Line "uname -a"
    Send-Line "cat /proc/cmdline"
    Send-Line "cat /proc/device-tree/model; echo"
    Send-Line "cat /proc/mtd"
    Send-Line "fw_printenv bootcmd 2>/dev/null || true"
    Send-Line "fw_printenv ipaddr 2>/dev/null || true"
    Send-Line "fw_printenv mode 2>/dev/null || true"
    Send-Line "echo __SDR_Z203_REBOOT_NOW__"
    Send-Line "reboot"

    Read-For ($SecondsAfterReboot * 1000)
} finally {
    $writer.WriteLine()
    $writer.WriteLine("# Stopped: {0:o}" -f (Get-Date))
    $writer.Dispose()
    if ($serial.IsOpen) {
        $serial.Close()
    }
}
