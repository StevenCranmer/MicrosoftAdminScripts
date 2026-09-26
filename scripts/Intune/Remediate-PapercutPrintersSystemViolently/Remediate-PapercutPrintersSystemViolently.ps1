# Example: .\Remediate-PapercutPrintersSystemViolently.ps1
# Variables: Set $TargetNames to the printer queue names to remove. Review the driver cleanup before running.
#
# ===========================
# Intune Remediation Script
# ===========================
$TargetNames = @("ExamplePrinter_Mono","ExamplePrinter_Colour")
$driversToRemove = @("Papercut Global PostScript","Papercut Universal Driver") # Adjust as needed

Write-Output "Starting remediation for example printer queues..."

# ---------------------------
# Remove machine-wide printers
# ---------------------------
Get-Printer -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -in $TargetNames } |
    ForEach-Object {
        try {
            Write-Output "Removing machine printer: $($_.Name)"
            Remove-Printer -Name $_.Name -ErrorAction Stop
        } catch {
            Write-Output "Failed to remove machine printer $($_.Name): $($_.Exception.Message)"
        }
    }

# ---------------------------
# Remove from all user profiles
# ---------------------------
$UserProfiles = Get-ChildItem 'C:\Users' -Directory | Where-Object { $_.Name -notin @('Public','Default') }
foreach ($profile in $UserProfiles) {
    $ntuser = Join-Path $profile.FullName 'NTUSER.DAT'
    if (Test-Path $ntuser) {
        try {
            reg load HKU\TempHive $ntuser | Out-Null
            $connPath = "HKU\TempHive\Printers\Connections"
            if (Test-Path $connPath) {
                Get-ChildItem $connPath | ForEach-Object {
                    $printerName = (Get-ItemProperty $_.PSPath).PrinterName
                    if ($TargetNames -contains $printerName) {
                        Write-Output "Removing $printerName from profile $($profile.Name)"
                        Remove-Item $_.PSPath -Recurse -Force
                    }
                }
            }
        } catch {
            Write-Output "Failed to process profile $($profile.Name): $($_.Exception.Message)"
        } finally {
            reg unload HKU\TempHive | Out-Null
        }
    }
}

# ---------------------------
# Remove unused drivers
# ---------------------------
foreach ($drv in $driversToRemove) {
    $stillUsed = Get-Printer | Where-Object { $_.DriverName -eq $drv }
    if (-not $stillUsed) {
        try {
            Write-Output "Removing unused driver: $drv"
            Remove-PrinterDriver -Name $drv -ErrorAction Stop
        } catch {
            Write-Output "Failed to remove driver ${drv}: $($_.Exception.Message)"
        }
    } else {
        Write-Output "Driver $drv still in use—skipping."
    }
}

Write-Output "Remediation complete."
