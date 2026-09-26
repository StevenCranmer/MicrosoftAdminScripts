# Example: .\RemovePrimaryUserLoop.ps1
# Variables: Change the SHARED-* device name filter to select your devices.
#
$devices = Get-Win10IntuneManagedDevices

$targetdevices = $devices | Where-Object {$_.deviceName -like "SHARED-*"}

Foreach ($device in $targetdevices){

Write-Host "Removing Primary User for $($device.devicename)" -ForegroundColor green

Delete-IntuneDevicePrimaryUser -IntuneDeviceId $device.id -ErrorAction Continue

}