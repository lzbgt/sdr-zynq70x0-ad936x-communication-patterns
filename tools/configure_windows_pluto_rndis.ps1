param(
    [string]$InterfaceDescription = "PlutoSDR USB Ethernet/RNDIS Gadget",
    [string]$HostAddress = "192.168.2.10",
    [int]$PrefixLength = 24
)

$ErrorActionPreference = "Stop"

$adapter = Get-NetAdapter | Where-Object { $_.InterfaceDescription -eq $InterfaceDescription }
if (-not $adapter) {
    throw "Network adapter not found: $InterfaceDescription"
}

$existing = Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
foreach ($address in $existing) {
    if ($address.IPAddress -like "169.254.*" -or $address.IPAddress -eq $HostAddress) {
        Remove-NetIPAddress -InterfaceIndex $adapter.ifIndex -IPAddress $address.IPAddress -Confirm:$false -ErrorAction SilentlyContinue
    }
}

New-NetIPAddress -InterfaceIndex $adapter.ifIndex -IPAddress $HostAddress -PrefixLength $PrefixLength -ErrorAction SilentlyContinue | Out-Null

Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 |
    Format-Table InterfaceAlias,IPAddress,PrefixLength -Auto
