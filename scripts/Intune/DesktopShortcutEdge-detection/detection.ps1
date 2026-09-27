# Example: .\detection.ps1
# Variables: No user-supplied variables; this runs in the current account or device context.
# Purpose: Count Edge shortcuts on the current user's desktop.
# Requires: Run in the affected user context.
# Effect: Exit 0 when more than one Edge shortcut exists, 1 otherwise; verify this matches your deployment rule.
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