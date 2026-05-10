param(
    [string]$Port = "COM5",
    [int]$Baud = 115200,
    [string]$OutFile = "serial-command-capture.txt",
    [string]$CommandsFile = "",
    [string[]]$Commands = @(),
    [string]$LoginUser = "root",
    [string]$Password = "analog",
    [string[]]$PasswordCandidates = @("", "analog", "root", "pluto", "xilinx"),
    [int]$ReadAfterCommandMs = 1500
)

$ErrorActionPreference = "Stop"

$directory = Split-Path -Parent $OutFile
if ($directory -and -not (Test-Path $directory)) {
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
}

if ($CommandsFile.Length -gt 0) {
    $Commands = Get-Content -Path $CommandsFile
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
    $captured = [System.Text.StringBuilder]::new()
    $deadline = (Get-Date).AddMilliseconds($Milliseconds)
    while ((Get-Date) -lt $deadline) {
        $data = $serial.ReadExisting()
        if ($data.Length -gt 0) {
            [void]$captured.Append($data)
            Write-Capture $data
        } else {
            Start-Sleep -Milliseconds 100
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
    Start-Sleep -Milliseconds 250
    Read-For $ReadMs
}

try {
    $serial.Open()
    $writer.WriteLine("# Serial command capture")
    $writer.WriteLine("# Port: $Port")
    $writer.WriteLine("# Baud: $Baud")
    $writer.WriteLine("# Started: {0:o}" -f (Get-Date))
    $writer.Flush()

    [void](Read-For 1000)
    $loggedIn = $false
    $allPasswords = @($Password) + $PasswordCandidates | Select-Object -Unique
    foreach ($candidate in $allPasswords) {
        [void](Send-Line "" 1000)
        [void](Send-Line $LoginUser 1500)
        [void](Send-Line $candidate 2200)
        $probe = Send-Line "echo __SERIAL_LOGIN_READY__" 1500
        if ($probe -like "*__SERIAL_LOGIN_READY__*") {
            $loggedIn = $true
            break
        }
    }

    if (-not $loggedIn) {
        throw "Unable to reach shell prompt on $Port using configured login candidates"
    }

    foreach ($command in $Commands) {
        [void](Send-Line $command $ReadAfterCommandMs)
    }
} finally {
    $writer.WriteLine()
    $writer.WriteLine("# Stopped: {0:o}" -f (Get-Date))
    $writer.Dispose()
    if ($serial.IsOpen) {
        $serial.Close()
    }
}
