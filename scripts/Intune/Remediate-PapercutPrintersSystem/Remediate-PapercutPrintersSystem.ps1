# Example: .\Remediate-PapercutPrintersSystem.ps1
# Variables: Set $TargetNames to the machine-wide printer queue names to remove.
# Purpose: Remove the configured machine-wide printer queues.
# Requires: PrintManagement cmdlets and rights to remove printers; set $TargetNames.
# Effect: Deletes matching queues; this variant does not remove drivers.
#
foreach ($command in @('Get-Printer', 'Remove-Printer')) {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) { throw "Windows PrintManagement command $command is unavailable on this device." }
}

# Remove machine-wide printers and clean related drivers if unused
$TargetNames = @("ExamplePrinter_Mono","ExamplePrinter_Colour")

# Remove the printers
Get-Printer -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -in $TargetNames } |
    ForEach-Object {
        try {
            Write-Output "Removing printer: $($_.Name)"
            Remove-Printer -Name $_.Name -ErrorAction Stop
        } catch {
            Write-Output "Failed to remove printer $($_.Name): $($_.Exception.Message)"
        }
    }