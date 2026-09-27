# Example: .\detectOldTeams.ps1
# Variables: No user-supplied variables; this runs in the current account or device context.
# Purpose: Check for new Teams when classic Teams is absent.
# Requires: Run in the intended user/device context with access to WindowsApps.
# Effect: Read-only: exit 0 when classic is absent and new Teams is present, 1 otherwise.
#
$TeamsClassic = Test-Path (Join-Path $env:LOCALAPPDATA 'Microsoft\Teams\current\Teams.exe')
$TeamsNew = Get-ChildItem "C:\Program Files\WindowsApps" -Filter "MSTeams_*"

if(!$TeamsClassic -and $TeamsNew){
    Write-Host "Found it!"
    exit 0
}else{
    exit 1
}
