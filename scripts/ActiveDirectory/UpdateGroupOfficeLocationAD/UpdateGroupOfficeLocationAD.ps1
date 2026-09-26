# Example: .\UpdateGroupOfficeLocationAD.ps1 -GroupName 'Example Group' -NewOfficeLocation 'Example Office'
# Variables: -GroupName selects the AD group; -NewOfficeLocation is assigned to its members.
#
#.\UpdateGroupOfficeLocationAD.ps1 -GroupName "Group_00000000-0000-0000-0000-000000000000" -NewOfficeLocation "Example Student AD"

param (
    [Parameter(Mandatory=$true)]
    [string]$GroupName,

    [Parameter(Mandatory=$true)]
    [string]$NewOfficeLocation
)

# Ensure the Active Directory module is available
try {
    Import-Module ActiveDirectory -ErrorAction Stop
} catch {
    Write-Error "Failed to import Active Directory module. Make sure RSAT: Active Directory is installed."
    exit
}

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
