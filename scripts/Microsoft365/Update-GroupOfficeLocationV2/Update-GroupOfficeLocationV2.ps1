# Example: .\Update-GroupOfficeLocationV2.ps1 -GroupId '<GROUP_ID>' -NewOfficeLocation 'Example Office'
# Variables: -GroupId selects the group; -NewOfficeLocation is the office value to assign.
# Purpose: Set OfficeLocation for direct user members of an Entra group.
# Requires: Microsoft.Graph commands and User.ReadWrite.All plus GroupMember.Read.All rights.
# Effect: Updates user profiles; failures are reported to the console.
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
Assert-RequiredModules -Names @('Microsoft.Graph.Authentication','Microsoft.Graph.Groups','Microsoft.Graph.Users')
$requiredScopes = @('User.ReadWrite.All','GroupMember.Read.All')
$graphContext = Get-MgContext
$missingScopes = if ($graphContext -and $graphContext.AuthType -ne "AppOnly") {
    @($requiredScopes | Where-Object { $_ -notin @($graphContext.Scopes) })
} else { @() }
if (-not $graphContext -or $missingScopes.Count) {
    Write-Host "Microsoft Graph sign-in is required; a sign-in prompt will open."
    Connect-MgGraph -Scopes $requiredScopes -NoWelcome -ErrorAction Stop | Out-Null
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
