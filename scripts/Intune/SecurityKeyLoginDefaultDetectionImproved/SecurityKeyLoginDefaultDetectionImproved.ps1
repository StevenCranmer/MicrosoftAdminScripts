# Example: .\SecurityKeyLoginDefaultDetectionImproved.ps1
# Variables: No user-supplied variables; this runs in the current account or device context.
# Purpose: Check whether the specified credential provider is disabled.
# Requires: Run in device context with access to the HKLM credential-provider key.
# Effect: Read-only: exit 0 when Disabled equals 1, 1 otherwise.
#
$Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\Credential Providers\{F8A1793B-7873-4046-B2A7-1F318747F427}"
$Name = "Disabled"
$Type = "DWORD"
$Value = 1

Try {
    $Registry = Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop | Select-Object -ExpandProperty $Name
    If ($Registry -eq $Value){
        Write-Output "Compliant"
        Exit 0
    } 
    Write-Warning "Not Compliant"
    Exit 1
} 
Catch {
    Write-Warning "Not Compliant"
    Exit 1
}
