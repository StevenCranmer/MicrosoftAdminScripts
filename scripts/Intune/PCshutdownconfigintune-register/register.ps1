# Example: .\register.ps1
# Variables: Input: ShutdownPCat6PM.xml in the same folder defines the scheduled task.
#
Register-ScheduledTask -xml (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'ShutdownPCat6PM.xml') | Out-String) -TaskName "ShutdownPCat6PM" -Force