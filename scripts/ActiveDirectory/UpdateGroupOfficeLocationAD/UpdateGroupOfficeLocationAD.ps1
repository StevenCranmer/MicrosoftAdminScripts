# Example: .\UpdateGroupOfficeLocationAD.ps1 -GroupName 'Example Group' -NewOfficeLocation 'Example Office'
# Variables: -GroupName selects the AD group; -NewOfficeLocation is assigned to its members.
# Purpose: Set the Office field for user members of an AD group.
# Requires: ActiveDirectory PowerShell module (RSAT) and permission to update user objects.
# Effect: Changes each matching user's AD Office field; no preview switch is provided.
#
#.\UpdateGroupOfficeLocationAD.ps1 -GroupName "Group_00000000-0000-0000-0000-000000000000" -NewOfficeLocation "Example Student AD"

param (
    [Parameter(Mandatory=$true)]
    [string]$GroupName,

    [Parameter(Mandatory=$true)]
    [string]$NewOfficeLocation
)

# Windows administration tools are installed as OS features, not from PSGallery.
if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
    $answer = Read-Host "ActiveDirectory tools are missing. Install the Windows administration tools now? [y/N]"
    if ($answer -notmatch '^(?i:y|yes)$') {
        throw "ActiveDirectory tools are required. Install them through Windows optional features or Server Manager, then rerun."
    }
    $isAdministrator = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdministrator) {
        throw 'Installing Windows administration tools requires an elevated PowerShell session. Reopen PowerShell as administrator and rerun.'
    }
    $isServer = (Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).ProductType -ne 1
    if ($isServer) {
        if (-not (Get-Command Install-WindowsFeature -ErrorAction SilentlyContinue)) { throw 'Install-WindowsFeature is unavailable. Install the tools through Server Manager.' }
        $result = Install-WindowsFeature -Name 'RSAT-AD-PowerShell' -ErrorAction Stop
        if (-not $result.Success) { throw 'Windows reported that the feature installation did not succeed.' }
    } else {
        if (-not (Get-Command Add-WindowsCapability -ErrorAction SilentlyContinue)) { throw 'Add-WindowsCapability is unavailable. Install the tools through Windows optional features.' }
        $result = Add-WindowsCapability -Online -Name 'Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0' -ErrorAction Stop
        if ($result.RestartNeeded) { throw 'The tools need a restart before they can be used. Restart Windows, then rerun.' }
    }
}
Import-Module ActiveDirectory -ErrorAction Stop

# Get all members of the group
try {
    $members = Get-ADGroupMember -Identity $GroupName -Recursive -ErrorAction Stop | Where-Object { $_.objectClass -eq 'user' }
} catch {
    Write-Error "Failed to retrieve members of group '$GroupName'. Ensure the group exists and you have permission."
    exit
}

foreach ($user in $members) {
    try {
        $userDetails = Get-ADUser -Identity $user.SamAccountName -Properties Office -ErrorAction Stop
        Write-Host "Updating $($userDetails.Name) ($($userDetails.SamAccountName)) to office location '$NewOfficeLocation'"

        Set-ADUser -Identity $userDetails.SamAccountName -Office $NewOfficeLocation -ErrorAction Stop
    } catch {
        Write-Warning "Failed to update user '$($user.SamAccountName)'. Error: $_"
    }
}

Write-Host "Script completed." -ForegroundColor Green
