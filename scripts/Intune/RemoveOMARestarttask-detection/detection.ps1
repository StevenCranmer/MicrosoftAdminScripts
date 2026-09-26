# Example: .\detection.ps1
# Variables: No user-supplied variables; this runs in the current account or device context.
#
Get-ScheduledTask -TaskName "RebootCSP daily recurrent reboot"
Write-Host "poggers?"