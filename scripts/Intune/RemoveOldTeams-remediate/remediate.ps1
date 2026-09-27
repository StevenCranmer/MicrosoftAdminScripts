# Example: .\remediate.ps1
# Variables: No user-supplied variables; this runs in the current account or device context.
# Purpose: Uninstall the Teams Machine-Wide Installer package.
# Requires: Device context with Windows Installer rights.
# Effect: Runs msiexec silently; check that the package found is the intended legacy installer.
#
$product = Get-Package -Name 'Teams Machine-Wide Installer'
Start-Process msiexec.exe -Wait -ArgumentList "/x {$($product.TagID)} /qn /quiet"