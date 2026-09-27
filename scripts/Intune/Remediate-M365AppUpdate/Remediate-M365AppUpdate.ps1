# Example: .\Remediate-M365AppUpdate.ps1
# Variables: No user-supplied variables; this runs in the current account or device context.
# Purpose: Start a Microsoft 365 Apps Click-to-Run update.
# Requires: Microsoft 365 Apps Click-to-Run client installed.
# Effect: Starts OfficeC2RClient.exe and waits for it to finish.
#
$processArgs = @{
    'FilePath'     = "$env:ProgramFiles\Common Files\microsoft shared\ClickToRun\OfficeC2RClient.exe"
    'ArgumentList' = "/update user"
    'Wait'         = $true
}

if (-not (Test-Path $processArgs['FilePath'])) { throw "OfficeC2RClient.exe not found!" }
Start-Process @processArgs