# Example: .\Export-Year12Year13TutorGroupMemberships.ps1 -OutputPath .\tutor-groups.csv
# Variables: Set $TutorGroups to your group names; -OutputPath selects the report file.
# Purpose: Report membership of the configured tutor groups.
# Requires: Microsoft.Graph PowerShell commands and permission to read groups and users.
# Effect: Writes a CSV containing user details; check the hard-coded year suffix before use.
#
[CmdletBinding()]
param(
    [Parameter()]
    [string]$OutputPath = ".\Year12Year13TutorGroupMemberships.csv"
)

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
$ErrorActionPreference = "Stop"

# Replace these dummy names with the tutor groups to export.
$TutorGroups = @(
    "Example Tutor Group 1"
    "Example Tutor Group 2"
)

if (-not (Get-Command Get-MgGroup -ErrorAction SilentlyContinue)) {
    throw "Get-MgGroup is not installed. Run: Install-Module Microsoft.Graph.Groups -Scope CurrentUser"
}

if (-not (Get-Command Get-MgGroupMemberAsUser -ErrorAction SilentlyContinue)) {
    throw "Get-MgGroupMemberAsUser is not installed. Run: Install-Module Microsoft.Graph.Groups -Scope CurrentUser"
}

Connect-MgGraph -Scopes "Group.Read.All", "GroupMember.Read.All", "User.Read.All" -NoWelcome

$Results = foreach ($TutorGroup in $TutorGroups) {
    $Office365Name = "$TutorGroup (2026)"
    $EscapedName = $Office365Name.Replace("'", "''")

    Write-Host "Finding group: $Office365Name"

    $Matches = @(
        Get-MgGroup `
            -Filter "displayName eq '$EscapedName'" `
            -Property "id,displayName"
    )

    if ($Matches.Count -eq 0) {
        Write-Warning "Group not found: $Office365Name"
        continue
    }

    if ($Matches.Count -gt 1) {
        Write-Warning "Multiple groups found with the exact name: $Office365Name. Skipped."
        continue
    }

    $Group = $Matches[0]
    Write-Host "Reading members: $($Group.DisplayName)"

    Get-MgGroupMemberAsUser `
        -GroupId $Group.Id `
        -All `
        -Property "id,displayName,userPrincipalName,mail" |
        ForEach-Object {
            [PSCustomObject]@{
                TutorGroup        = $TutorGroup
                Office365Group    = $Group.DisplayName
                DisplayName       = $_.DisplayName
                UserPrincipalName = $_.UserPrincipalName
                Email             = $_.Mail
                UserId            = $_.Id
            }
        }
}

$Results = @(
    $Results |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_.UserPrincipalName) } |
        Sort-Object TutorGroup, DisplayName
)

$Duplicates = @(
    $Results |
        Group-Object UserPrincipalName |
        Where-Object Count -gt 1
)

$Results | Export-Csv -LiteralPath $OutputPath -NoTypeInformation -Encoding UTF8

Write-Host ""
Write-Host "Exported $($Results.Count) memberships."
$Results |
    Group-Object TutorGroup |
    Sort-Object Name |
    Select-Object Name, Count |
    Format-Table -AutoSize

if ($Duplicates.Count -gt 0) {
    Write-Warning "$($Duplicates.Count) account(s) appear in more than one tutor group."
    $Duplicates | Select-Object Count, Name | Format-Table -AutoSize
}
else {
    Write-Host "No duplicate tutor-group memberships found."
}

Write-Host "Saved to: $((Resolve-Path -LiteralPath $OutputPath).Path)"
