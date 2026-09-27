# Example: .\Update-GroupJobTitleV4.ps1 -GroupId '<GROUP_ID>' -NewJobTitle 'Example Job Title'
# Variables: -GroupId selects the group; -NewJobTitle is the title to assign to its members.
# Purpose: Set JobTitle for direct user members of an Entra group.
# Requires: Microsoft.Graph commands and User.ReadWrite.All plus GroupMember.Read.All rights.
# Effect: Updates user profiles; failures are reported to the console.
#
# correct format for running script is:
# .\Update-GroupJobTitleV4.ps1 -GroupId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" -NewJobTitle "string"

param (
    [Parameter(Mandatory=$true)]
    [string]$GroupId,

    [Parameter(Mandatory=$true)]
    [string]$NewJobTitle
)

# Prompt user to connect if not already connected
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

# Track failures for actual users we tried to touch
$failed = [System.Collections.Generic.List[object]]::new()

function Normalize([string]$s) {
    if ($null -eq $s) { return "" }
    return $s.Trim()
}

# Get ONLY users in the group (fast: no per-member Get-MgUser lookups)
try {
    $users = Get-MgGroupMemberAsUser -GroupId $GroupId -All -Property Id,DisplayName,UserPrincipalName,JobTitle -ErrorAction Stop
}
catch {
    throw ("Failed to get user members for GroupId {0}: {1}" -f $GroupId, $_.Exception.Message)
}

foreach ($user in $users) {

    # Compare current vs new (trimmed, case-insensitive)
    $curr = Normalize $user.JobTitle
    $next = Normalize $NewJobTitle

    if ([string]::Equals($curr, $next, [System.StringComparison]::InvariantCultureIgnoreCase)) {
        # No change -> silent
        continue
    }

    # Update only when there's an actual change
    try {
        Update-MgUser -UserId $user.Id -JobTitle $NewJobTitle -ErrorAction Stop
        Write-Host "Updated $($user.DisplayName) ($($user.UserPrincipalName)) to job title '$NewJobTitle'"
    }
    catch {
        $failed.Add([pscustomobject]@{
            DisplayName       = $user.DisplayName
            UserPrincipalName = $user.UserPrincipalName
            Reason            = $_.Exception.Message
        }) | Out-Null

        Write-Warning "Failed to update $($user.DisplayName) ($($user.UserPrincipalName)): $($_.Exception.Message)"
    }
}

# After the loop: summarize failures (only actual user failures)
if ($failed.Count) {
    Write-Host "`nFailed DisplayNames:" -ForegroundColor Yellow
    $failed | ForEach-Object {
        $dn = if ($_.DisplayName) { $_.DisplayName } elseif ($_.UserPrincipalName) { $_.UserPrincipalName } else { "<unknown>" }
        " - $dn"
    }

    Write-Host "`nFailure details:" -ForegroundColor Yellow
    $failed | Select-Object DisplayName, UserPrincipalName, Reason | Format-Table -AutoSize
    # Optional: export to CSV for follow-up
    # $failed | Export-Csv -Path ".\Failed-JobTitle-Updates.csv" -NoTypeInformation -Encoding UTF8
}
