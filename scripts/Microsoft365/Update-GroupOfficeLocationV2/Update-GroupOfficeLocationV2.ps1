# Example: .\Update-GroupOfficeLocationV2.ps1 -GroupId '<GROUP_ID>' -NewOfficeLocation 'Example Office'
# Variables: -GroupId selects the group; -NewOfficeLocation is the office value to assign.
#
# correct format for running script is:
# .\Update-GroupOfficeLocationV2.ps1 -GroupId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" -NewOfficeLocation "string"

param (
    [Parameter(Mandatory=$true)]
    [string]$GroupId,

    [Parameter(Mandatory=$true)]
    [string]$NewOfficeLocation
)

# Gentle reminder to connect with required scopes
Write-Host "Make sure you're connected to Microsoft Graph with the right scopes before running this script." -ForegroundColor Yellow
Write-Host "Use: Connect-MgGraph -Scopes 'User.ReadWrite.All','GroupMember.Read.All'" -ForegroundColor Yellow

# Best-effort check for a connected context
try { $null = Get-MgContext -ErrorAction Stop } catch {
    Write-Warning "Not connected to Microsoft Graph. Run: Connect-MgGraph -Scopes 'User.ReadWrite.All','GroupMember.Read.All'"
}

# Track failures (only real failures against users)
$failed = [System.Collections.Generic.List[psobject]]::new()

function Normalize([string]$s) {
    if ($null -eq $s) { return "" }
    return $s.Trim()
}

try {
    # Get ONLY users in the group (typed cast endpoint)
    # NOTE: Requires Microsoft.Graph SDK v2+
    $users = Get-MgGroupMemberAsUser -GroupId $GroupId -All -Property Id,DisplayName,UserPrincipalName,OfficeLocation -ErrorAction Stop
}
catch {
	throw ("Failed to get members for GroupId {0}: {1}" -f $GroupId, $_.Exception.Message)
}

foreach ($u in $users) {
    # Compare current vs new (trimmed, case-insensitive)
    $curr = Normalize $u.OfficeLocation
    $next = Normalize $NewOfficeLocation

    if ([string]::Equals($curr, $next, [System.StringComparison]::InvariantCultureIgnoreCase)) {
        # No change -> no output
        continue
    }

    # Update only when different
    try {
        Update-MgUser -UserId $u.Id -OfficeLocation $NewOfficeLocation -ErrorAction Stop
        Write-Host "Updated $($u.DisplayName) ($($u.UserPrincipalName)) to office location '$NewOfficeLocation'"
    }
    catch {
        $failed.Add([pscustomobject]@{
            DisplayName       = $u.DisplayName
            UserPrincipalName = $u.UserPrincipalName
            Reason            = $_.Exception.Message
        }) | Out-Null
        Write-Warning "Failed to update $($u.DisplayName) ($($u.UserPrincipalName)): $($_.Exception.Message)"
    }
}

# Summarize real failures, if any
if ($failed.Count) {
    Write-Host "`nFailed DisplayNames:" -ForegroundColor Yellow
    $failed | ForEach-Object {
        $dn = if ($_.DisplayName) { $_.DisplayName } elseif ($_.UserPrincipalName) { $_.UserPrincipalName } else { "<unknown>" }
        " - $dn"
    }

    Write-Host "`nFailure details:" -ForegroundColor Yellow
    $failed | Select-Object DisplayName, UserPrincipalName, Reason | Format-Table -AutoSize

    # Optional: export to CSV
    # $failed | Export-Csv -Path ".\Failed-OfficeLocation-Updates.csv" -NoTypeInformation -Encoding UTF8
}
