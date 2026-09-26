# Example: .\Remediate-PapercutPrintersSystem.ps1
# Variables: Set $TargetNames to the machine-wide printer queue names to remove.
#
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