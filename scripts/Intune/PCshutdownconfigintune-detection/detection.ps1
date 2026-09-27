# Example: .\detection.ps1
# Variables: No user-supplied variables; this runs in the current account or device context.
# Purpose: Query whether the ShutdownPCat6PM task exists.
# Requires: Windows ScheduledTasks cmdlets in device context.
# Effect: Read-only query; this script does not define an explicit compliance exit code.
#
if (-not (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue)) { throw 'Windows ScheduledTasks cmdlets are unavailable on this device.' }

Get-ScheduledTask -TaskName "ShutdownPCat6PM"
Write-Host "poggers?"