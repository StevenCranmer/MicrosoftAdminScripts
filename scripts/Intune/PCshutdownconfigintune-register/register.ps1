# Example: .\register.ps1
# Variables: Input: ShutdownPCat6PM.xml in the same folder defines the scheduled task.
# Purpose: Register the scheduled shutdown task from its XML file.
# Requires: Windows ScheduledTasks cmdlets and ShutdownPCat6PM.xml beside this script.
# Effect: Registers a 18:00 shutdown task with a forced shutdown command; review the XML first.
#
if (-not (Get-Command Register-ScheduledTask -ErrorAction SilentlyContinue)) { throw 'Windows ScheduledTasks cmdlets are unavailable on this device.' }
if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'ShutdownPCat6PM.xml'))) { throw 'ShutdownPCat6PM.xml is missing from the script folder.' }

Register-ScheduledTask -xml (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'ShutdownPCat6PM.xml') | Out-String) -TaskName "ShutdownPCat6PM" -Force