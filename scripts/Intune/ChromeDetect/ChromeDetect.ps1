# Example: .\ChromeDetect.ps1
# Variables: No user-supplied variables; this runs in the current account or device context.
# Purpose: Detect Chrome for a removal remediation.
# Requires: Run in the device context used by your Intune remediation package.
# Effect: Read-only: exit 1 when Chrome is installed, 0 when absent.
#
try
{  

$chromeInstalled = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe'

if ($chromeInstalled -eq 'True') {
    Write-Host "Google Chrome is installed"
    exit 1
    }
    else {
        #No remediation required    
        Write-Host "Google Chrome is not installed"
        exit 0
    }  
}
catch {
    $errMsg = $_.Exception.Message
    Write-Error $errMsg
    exit 1
}