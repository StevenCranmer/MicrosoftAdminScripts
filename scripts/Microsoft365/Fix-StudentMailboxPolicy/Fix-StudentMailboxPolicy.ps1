# Example: .\Fix-StudentMailboxPolicy.ps1
# Variables: Set $groupName to the target M365 group and $policyName to the mailbox policy to apply.
#
# Connect to Exchange Online
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
