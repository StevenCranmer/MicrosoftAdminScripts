# Example: .\Detect-PapercutPrintersSystem.ps1
# Variables: Set $TargetNames to the machine-wide printer queue names to detect.
# Purpose: Find the configured machine-wide printer queues.
# Requires: PrintManagement cmdlets; replace example queue names in $TargetNames.
# Effect: Read-only: exit 1 if matching queues exist, 0 otherwise.
#
if (-not (Get-Command Get-Printer -ErrorAction SilentlyContinue)) { throw 'Windows PrintManagement cmdlets are unavailable on this device.' }

# Detect machine-wide printers
$TargetNames = @("ExamplePrinter_Mono","ExamplePrinter_Colour")
$found = Get-Printer -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -in $TargetNames }

if ($found) {
    Write-Output "Found machine printers: $($found.Name -join ', ')"
    exit 1
}
Write-Output "No machine printers found"
exit 0
