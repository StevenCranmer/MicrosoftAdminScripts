# Example: .\remediate.ps1
# Variables: No user-supplied variables; this runs in the current account or device context.
# Purpose: Remove Teams desktop shortcuts when duplicates are found.
# Requires: Run in the affected user context.
# Effect: Deletes every desktop shortcut whose name contains Teams when the count exceeds one.
#
$DesktopPath = [Environment]::GetFolderPath("Desktop")
$BadTeamsLnks = Get-ChildItem $DesktopPath | Where-Object {$_.Name -like "*Teams*.lnk"}
if ($BadTeamsLnks.Count -gt "1") {
foreach ($BadTeamsLnk in $BadTeamsLnks) {
Write-Host "Removing "$DesktopPath\$BadTeamsLnk""
Remove-Item "$DesktopPath\$BadTeamsLnk" -Force
}
}