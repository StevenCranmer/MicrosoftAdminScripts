# Example: .\disableNetbios.ps1
# Variables: No user-supplied variables; this runs in the current account or device context.
# Purpose: Attempt to disable NetBIOS over TCP/IP on network interfaces.
# Requires: Administrative rights to change HKLM network settings.
# Effect: Sets NetbiosOptions to 2 for enumerated interfaces; verify the registry path on your system.
#
$regkey = "HKLM:SYSTEM\CurrentControlSet\services\NetBT\Parameters\Interfaces"
Get-ChildItem $regkey |foreach { Set-ItemProperty -Path "$regkey\$($_.pschildname)" -Name NetbiosOptions -Value 2 -Verbose}