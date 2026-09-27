# Example: .\detect-fastboot.ps1
# Variables: No user-supplied variables; this runs in the current account or device context.
# Purpose: Check whether Windows Fast Startup is disabled.
# Requires: Run in device context with access to the HKLM power setting.
# Effect: Read-only: exit 0 when HiberbootEnabled is 0, 1 otherwise.
#
$Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power"
$Name = "HiberbootEnabled"
$Type = "DWORD"
$Value = 0

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