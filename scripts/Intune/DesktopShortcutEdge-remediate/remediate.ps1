# Example: .\remediate.ps1
# Variables: No user-supplied variables; this runs in the current account or device context.
#
$DesktopPath = [Environment]::GetFolderPath("Desktop")
$BadEdgeLnks = Get-ChildItem $DesktopPath | Where-Object {$_.Name -like "*Edge*.lnk"}
if ($BadEdgeLnks.Count -gt "1") {
foreach ($BadLnk in $BadEdgeLnks) {
Write-Host "Removing "$DesktopPath\$Badlnk""
Remove-Item "$DesktopPath\$Badlnk" -Force
}
}