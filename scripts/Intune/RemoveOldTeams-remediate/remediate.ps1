# Example: .\remediate.ps1
# Variables: No user-supplied variables; this runs in the current account or device context.
#
$product = Get-Package -Name 'Teams Machine-Wide Installer'
Start-Process msiexec.exe -Wait -ArgumentList "/x {$($product.TagID)} /qn /quiet"