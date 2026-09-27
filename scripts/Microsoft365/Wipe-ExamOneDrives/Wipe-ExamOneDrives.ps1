# Example: .\Wipe-ExamOneDrives.ps1 -GroupId '<GROUP_ID>' -WhatIf
# Variables: -GroupId selects users; -WhatIf previews. -PermanentDelete makes the deletion permanent.
# Purpose: Delete root OneDrive items for users in a specified group.
# Requires: Microsoft.Graph.Authentication; the script prompts for delegated sign-in if no session exists.
# Effect: Use -WhatIf first; -PermanentDelete bypasses the recycle bin.
#
# .\Wipe-ExamOneDrives.ps1 -GroupId "00000000-0000-0000-0000-000000000000" -PermanentDelete -WhatIf
# .\Wipe-ExamOneDrives.ps1 -GroupId "00000000-0000-0000-0000-000000000000" -PermanentDelete

param(
    [Parameter(Mandatory = $true)]
    [string]$GroupId,

    [switch]$PermanentDelete,

    [switch]$WhatIf
)

# -----------------------------
# AUTH
# -----------------------------
# Option 1: Interactive test run
# Connect-MgGraph -Scopes "GroupMember.Read.All","Files.ReadWrite.All","User.Read.All" -NoWelcome

# Option 2: Unattended app-only run (recommended for scheduling)
# Connect-MgGraph -TenantId "<tenant-id>" -ClientId "<app-id>" -CertificateThumbprint "<thumbprint>" -NoWelcome

# -----------------------------
# HELPERS
# -----------------------------
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
Assert-RequiredModules -Names @('Microsoft.Graph.Authentication')
$requiredScopes = @('GroupMember.Read.All','Files.ReadWrite.All','User.Read.All')
$graphContext = Get-MgContext
$missingScopes = if ($graphContext -and $graphContext.AuthType -ne "AppOnly") {
    @($requiredScopes | Where-Object { $_ -notin @($graphContext.Scopes) })
} else { @() }
if (-not $graphContext -or $missingScopes.Count) {
    Write-Host "Microsoft Graph sign-in is required; a sign-in prompt will open."
    Connect-MgGraph -Scopes $requiredScopes -NoWelcome -ErrorAction Stop | Out-Null
}
function Convert-GraphResponse {
    param($Response)
    if ($Response -is [string]) {
        return ($Response | ConvertFrom-Json)
    }
    return $Response
}

function Invoke-GraphGetAll {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri
    )

    $allItems = @()

    do {
        $response = Invoke-MgGraphRequest -Method GET -Uri $Uri
        $response = Convert-GraphResponse $response

        if ($null -ne $response.value) {
            $allItems += $response.value
        }

        $Uri = $response.'@odata.nextLink'
    }
    while ($Uri)

    return $allItems
}

function Remove-OneDriveRootContent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$UserId,

        [switch]$PermanentDelete,

        [switch]$WhatIf
    )

    try {
        $drive = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/users/$UserId/drive"
        $drive = Convert-GraphResponse $drive
    }
    catch {
        Write-Warning "Skipping user $UserId - no OneDrive provisioned or not accessible."
        return
    }

    $driveId = $drive.id

    $items = Invoke-GraphGetAll -Uri "https://graph.microsoft.com/v1.0/users/$UserId/drive/root/children?`$select=id,name"

    if (-not $items -or $items.Count -eq 0) {
        Write-Host "User $UserId - OneDrive already empty."
        return
    }

    foreach ($item in $items) {
        if ($WhatIf) {
            if ($PermanentDelete) {
                Write-Host "[WhatIf] Would permanently delete '$($item.name)' for user $UserId"
            }
            else {
                Write-Host "[WhatIf] Would delete '$($item.name)' to recycle bin for user $UserId"
            }
            continue
        }

        try {
            if ($PermanentDelete) {
                Invoke-MgGraphRequest `
                    -Method POST `
                    -Uri "https://graph.microsoft.com/v1.0/drives/$driveId/items/$($item.id)/permanentDelete"
                Write-Host "Permanently deleted '$($item.name)' for user $UserId"
            }
            else {
                Invoke-MgGraphRequest `
                    -Method DELETE `
                    -Uri "https://graph.microsoft.com/v1.0/users/$UserId/drive/items/$($item.id)"
                Write-Host "Deleted '$($item.name)' to recycle bin for user $UserId"
            }
        }
        catch {
            Write-Warning "Failed deleting '$($item.name)' for user $UserId : $($_.Exception.Message)"
        }
    }
}

# -----------------------------
# MAIN
# -----------------------------
# Pull direct group members and filter to user objects only
$members = Invoke-GraphGetAll -Uri "https://graph.microsoft.com/v1.0/groups/$GroupId/members"

$userMembers = $members | Where-Object {
    $_.'@odata.type' -eq '#microsoft.graph.user'
}

if (-not $userMembers -or $userMembers.Count -eq 0) {
    Write-Warning "No user members found in group $GroupId"
    return
}

Write-Host "Found $($userMembers.Count) user(s) in group $GroupId"

foreach ($user in $userMembers) {
    Remove-OneDriveRootContent -UserId $user.id -PermanentDelete:$PermanentDelete -WhatIf:$WhatIf
}

Write-Host "Done."