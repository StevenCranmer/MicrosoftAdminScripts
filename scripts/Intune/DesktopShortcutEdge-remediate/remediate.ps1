# Example: .\remediate.ps1
# Variables: No user-supplied variables; this runs in the current account or device context.
# Purpose: Remove Edge desktop shortcuts when duplicates are found.
# Requires: Run in the affected user context.
# Effect: Deletes every desktop shortcut whose name contains Edge when the count exceeds one.
#
$DesktopPath = [Environment]::GetFolderPath("Desktop")
$BadEdgeLnks = Get-ChildItem $DesktopPath | Where-Object {$_.Name -like "*Edge*.lnk"}
if ($BadEdgeLnks.Count -gt "1") {
foreach ($BadLnk in $BadEdgeLnks) {
Write-Host "Removing "$DesktopPath\$Badlnk""
Remove-Item "$DesktopPath\$Badlnk" -Force
}
}