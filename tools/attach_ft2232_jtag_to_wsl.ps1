param(
    [string]$Distro = "archlinux",
    [string]$VidPid = "0403:6010"
)

$ErrorActionPreference = "Stop"

$machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
$userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
$env:Path = "$machinePath;$userPath"

if (-not (Get-Command usbipd.exe -ErrorAction SilentlyContinue)) {
    throw "usbipd.exe not found. Install usbipd-win first."
}

$list = usbipd list
$line = $list | Where-Object { $_ -match "\s$VidPid\s" } | Select-Object -First 1
if (-not $line) {
    throw "No connected USB device with VID:PID $VidPid found."
}

$busid = ($line -split '\s+')[0]
Write-Host "Using FT2232/JTAG bus ID: $busid"

usbipd bind --busid $busid | Out-Host
usbipd attach --wsl $Distro --busid $busid | Out-Host
usbipd list | Out-Host
