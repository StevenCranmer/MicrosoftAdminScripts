# Example: .\detectOldTeams.ps1
# Variables: No user-supplied variables; this runs in the current account or device context.
#
$TeamsClassic = Test-Path (Join-Path $env:LOCALAPPDATA 'Microsoft\Teams\current\Teams.exe')
$TeamsNew = Get-ChildItem "C:\Program Files\WindowsApps" -Filter "MSTeams_*"

if(!$TeamsClassic -and $TeamsNew){
    Write-Host "Found it!"
    exit 0
}else{
    exit 1
}
