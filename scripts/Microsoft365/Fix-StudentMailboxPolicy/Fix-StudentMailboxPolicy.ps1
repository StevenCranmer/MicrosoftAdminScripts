# Example: .\Fix-StudentMailboxPolicy.ps1
# Variables: Set $groupName to the target M365 group and $policyName to the mailbox policy to apply.
# Purpose: Apply a named OWA mailbox policy to user members of a Microsoft 365 group.
# Requires: ExchangeOnlineManagement, Microsoft.Graph commands, and rights to update mailboxes.
# Effect: Changes mailbox policies for matching users; review $groupName and $policyName.
#
# Connect to Exchange Online
# Check installable prerequisites before making changes or connecting to a service.
function Assert-RequiredModules {
    param([Parameter(Mandatory)][string[]]$Names)
    $missing = @($Names | Where-Object { -not (Get-Module -ListAvailable -Name $_) })
    if ($missing.Count) {
        if (-not (Get-Command Install-Module -ErrorAction SilentlyContinue)) {
            throw "Missing modules: $($missing -join ', '). Install PowerShellGet, then install these modules and rerun."
        }
        $answer = Read-Host "Missing modules: $($missing -join ', '). Install for CurrentUser from PSGallery? (Y/N)"
        if ($answer -notmatch '^(?i:y|yes)$') { throw "Required modules were not installed: $($missing -join ', ')" }
        foreach ($name in $missing) {
            Install-Module -Name $name -Scope CurrentUser -Repository PSGallery -Force -AllowClobber -ErrorAction Stop
        }
    }
    foreach ($name in $Names) { Import-Module $name -ErrorAction Stop }
}
Assert-RequiredModules -Names @('ExchangeOnlineManagement','Microsoft.Graph.Authentication','Microsoft.Graph.Groups','Microsoft.Graph.Users')
Connect-ExchangeOnline

# Connect to Microsoft Graph
Connect-MgGraph -Scopes "GroupMember.Read.All", "User.Read.All"

# Define the Microsoft 365 group and the mailbox policy name
$groupName = "Example Student Group"
$policyName = "Example Mailbox Policy"

# Initialize tracking lists
$changedUsers = @()
$unchangedUsers = @()
$errors = @()

# Get the group object
$group = Get-MgGroup -Filter "displayName eq '$groupName'"

# Get members of the group
$members = Get-MgGroupMember -GroupId $group.Id -All

# Loop through members
foreach ($member in $members) {
    try {
        $user = Get-MgUser -UserId $member.Id
        $upn = $user.UserPrincipalName

        if ($upn) {
            $currentPolicy = (Get-CASMailbox -Identity $upn).OwaMailboxPolicy

            if ($currentPolicy -ne $policyName) {
                Write-Host "Updating policy for $upn (Current: $currentPolicy)"
                Set-CASMailbox -Identity $upn -OwaMailboxPolicy $policyName
                $changedUsers += $upn
            } else {
                $unchangedUsers += $upn
            }
        } else {
            throw "No UPN found for $($user.DisplayName)"
        }
    }
    catch {
        Write-Host "❌ Error processing $($user.DisplayName): $_"
        $errors += "$($user.DisplayName): $_"
    }
}

# Final summary
Write-Host "`n--- ✅ Summary ---"
Write-Host "Changed policies: $($changedUsers.Count)"
Write-Host "Unchanged policies: $($unchangedUsers.Count)"
Write-Host "Errors: $($errors.Count)"

if ($changedUsers.Count -gt 0) {
    Write-Host "`nUsers with updated policies:"
    $changedUsers | ForEach-Object { Write-Host $_ }
}

if ($errors.Count -gt 0) {
    Write-Host "`nErrors encountered:"
    $errors | ForEach-Object { Write-Host $_ }
}
