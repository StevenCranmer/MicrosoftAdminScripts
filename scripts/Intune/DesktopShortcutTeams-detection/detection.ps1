# Example: .\detection.ps1
# Variables: No user-supplied variables; this runs in the current account or device context.
#
$DesktopPath = [Environment]::GetFolderPath("Desktop")
$BadTeamsLnks = Get-ChildItem $DesktopPath | Where-Object {$_.Name -like "*Teams*.lnk"}
if ($BadTeamsLnks.Count -gt "1") {
    write-output "Duplicate Teams found, exiting"
    exit 0
}
else {
    exit 1
}