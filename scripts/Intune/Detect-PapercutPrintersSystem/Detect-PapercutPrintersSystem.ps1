# Example: .\Detect-PapercutPrintersSystem.ps1
# Variables: Set $TargetNames to the machine-wide printer queue names to detect.
#
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
