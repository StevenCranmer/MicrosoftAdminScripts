# Example: .\detection.ps1
# Variables: No user-supplied variables; this runs in the current account or device context.
#
$DesktopPath = [Environment]::GetFolderPath("Desktop")
$BadEdgeLnks = Get-ChildItem $DesktopPath | Where-Object {$_.Name -like "*Edge*.lnk"}
if ($BadEdgeLnks.Count -gt "1") {
    write-output "Duplicate Edge found, exiting"
    exit 0
}
else {
    exit 1
}