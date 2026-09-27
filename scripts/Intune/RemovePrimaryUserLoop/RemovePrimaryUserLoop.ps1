# Example: .\RemovePrimaryUserLoop.ps1
# Variables: Change the SHARED-* device name filter to select your devices.
# Purpose: Clear Intune primary users from devices matching SHARED-*.
# Requires: The Get-Win10IntuneManagedDevices and Delete-IntuneDevicePrimaryUser commands must already be available.
# Effect: Changes matching device relationships; this script has no preview switch.
#
$missingCommands = @('Get-Win10IntuneManagedDevices', 'Delete-IntuneDevicePrimaryUser') | Where-Object {
    -not (Get-Command $_ -ErrorAction SilentlyContinue)
}
if ($missingCommands) {
    throw "Required Intune commands are unavailable: $($missingCommands -join ', '). Their source is not included in this repository. Use RemoveDeviceGroupPrimaryUsers.ps1 in the neighbouring folder for a Microsoft Graph-based alternative."
}

$devices = Get-Win10IntuneManagedDevices

$targetdevices = $devices | Where-Object {$_.deviceName -like "SHARED-*"}

Foreach ($device in $targetdevices){

Write-Host "Removing Primary User for $($device.devicename)" -ForegroundColor green

Delete-IntuneDevicePrimaryUser -IntuneDeviceId $device.id -ErrorAction Continue

}