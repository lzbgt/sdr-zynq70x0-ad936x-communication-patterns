param(
    [string]$Port = "COM5",
    [int]$Baud = 115200,
    [string]$OutFile = "z203-uboot-command-capture.txt",
    [string[]]$Commands = @(),
    [string]$CommandsFile = "",
    [string]$LoginUser = "root",
    [string]$Password = "analog",
    [int]$InterruptSeconds = 14,
    [int]$ReadAfterCommandMs = 1500,
    [int]$ReadAfterFinalCommandSeconds = 90
)

$ErrorActionPreference = "Stop"

if ($CommandsFile.Length -gt 0) {
    $Commands = Get-Content -Path $CommandsFile
}
if ($Commands.Count -eq 0) {
    throw "No U-Boot commands were provided"
}

$directory = Split-Path -Parent $OutFile
if ($directory -and -not (Test-Path $directory)) {
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
}

$serial = [System.IO.Ports.SerialPort]::new($Port, $Baud, "None", 8, "One")
$serial.ReadTimeout = 100
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
    $captured = [System.Text.StringBuilder]::new()
    $deadline = (Get-Date).AddMilliseconds($Milliseconds)
    while ((Get-Date) -lt $deadline) {
        $data = $serial.ReadExisting()
        if ($data.Length -gt 0) {
            [void]$captured.Append($data)
            Write-Capture $data
        } else {
            Start-Sleep -Milliseconds 50
        }
    }
    return $captured.ToString()
}

function Send-Line {
    param(
        [string]$Line,
        [int]$ReadMs = $ReadAfterCommandMs
    )
    $writer.WriteLine()
    $writer.WriteLine("# >>> $Line")
    $writer.Flush()
    $serial.Write("$Line`r")
    Start-Sleep -Milliseconds 200
    [void](Read-For $ReadMs)
}

try {
    $serial.Open()
    $writer.WriteLine("# Z203 serial U-Boot command capture")
    $writer.WriteLine("# Port: $Port")
    $writer.WriteLine("# Baud: $Baud")
    $writer.WriteLine("# Started: {0:o}" -f (Get-Date))
    $writer.WriteLine("# InterruptSeconds: $InterruptSeconds")
    $writer.Flush()

    [void](Read-For 1000)
    Send-Line ""
    Send-Line $LoginUser
    Send-Line $Password
    Send-Line ""
    Send-Line "echo __FIELDMESH_PRE_UBOOT_REBOOT__"
    Send-Line "sync"
    Send-Line "reboot" 250

    $interruptDeadline = (Get-Date).AddSeconds($InterruptSeconds)
    $interruptCapture = [System.Text.StringBuilder]::new()
    while ((Get-Date) -lt $interruptDeadline) {
        $serial.Write(" `r")
        Start-Sleep -Milliseconds 100
        $chunk = Read-For 150
        [void]$interruptCapture.Append($chunk)
        if ($interruptCapture.ToString() -match "(Zynq|Pluto)>") {
            break
        }
    }

    if ($interruptCapture.ToString() -notmatch "(Zynq|Pluto)>") {
        $writer.WriteLine()
        $writer.WriteLine("# Warning: U-Boot prompt was not detected before commands were sent.")
        $writer.Flush()
    }

    foreach ($command in $Commands) {
        Send-Line $command
    }
    [void](Read-For ($ReadAfterFinalCommandSeconds * 1000))
} finally {
    $writer.WriteLine()
    $writer.WriteLine("# Stopped: {0:o}" -f (Get-Date))
    $writer.Dispose()
    if ($serial.IsOpen) {
        $serial.Close()
    }
}
