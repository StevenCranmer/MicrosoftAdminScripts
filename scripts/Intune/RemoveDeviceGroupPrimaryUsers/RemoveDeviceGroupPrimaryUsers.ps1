# Example: .\RemoveDeviceGroupPrimaryUsers.ps1 -GroupDisplayName 'Example Devices'
# Variables: Replace example parameter values with your own. Run Get-Help for parameter details where available.
#
<#
.SYNOPSIS
Removes the Intune primary user from all Intune managed devices that are members
of a specified Entra ID device group.

.EXAMPLE
.\RemoveDeviceGroupPrimaryUsers.ps1 -GroupId xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx

.DESCRIPTION
- Reads device members from an Entra ID group
- Matches those Entra device objects to Intune managed devices using azureADDeviceId
- Deletes the managedDevice/users/$ref relationship
- Supports -WhatIf

.NOTES
Required delegated Graph scopes:
- GroupMember.Read.All
- Device.Read.All
- DeviceManagementManagedDevices.ReadWrite.All

Run in PowerShell 7+ where possible.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $false)]
    [string]$GroupId,

    [Parameter(Mandatory = $false)]
    [string]$GroupDisplayName
)

if (-not $GroupId -and -not $GroupDisplayName) {
    throw "Specify either -GroupId or -GroupDisplayName."
}

if ($GroupId -and $GroupDisplayName) {
    throw "Specify only one of -GroupId or -GroupDisplayName."
}

# Install module if missing
if (-not (Get-Module Microsoft.Graph.Authentication -ListAvailable)) {
    Install-Module Microsoft.Graph -Scope CurrentUser -Force
}

Import-Module Microsoft.Graph.Authentication

$Scopes = @(
    "GroupMember.Read.All",
    "Device.Read.All",
    "DeviceManagementManagedDevices.ReadWrite.All"
)

Connect-MgGraph -Scopes $Scopes -NoWelcome

function Invoke-GraphPagedRequest {
    param(
        [Parameter(Mandatory)]
        [string]$Uri,

        [hashtable]$Headers = @{}
    )

    $Results = @()
    $NextUri = $Uri

    while ($NextUri) {
        $Response = Invoke-MgGraphRequest -Method GET -Uri $NextUri -Headers $Headers
        if ($Response.value) {
            $Results += $Response.value
        }
        $NextUri = $Response.'@odata.nextLink'
    }

    return $Results
}

# Resolve group if display name was supplied
if ($GroupDisplayName) {
    $EncodedName = $GroupDisplayName.Replace("'", "''")
    $GroupSearchUri = "https://graph.microsoft.com/v1.0/groups?`$filter=displayName eq '$EncodedName'&`$select=id,displayName"

    $Groups = Invoke-GraphPagedRequest -Uri $GroupSearchUri

    if ($Groups.Count -eq 0) {
        throw "No group found with displayName '$GroupDisplayName'."
    }

    if ($Groups.Count -gt 1) {
        $Groups | Select-Object id, displayName | Format-Table
        throw "Multiple groups found with displayName '$GroupDisplayName'. Use -GroupId instead."
    }

    $GroupId = $Groups[0].id
}

Write-Host "Using group id: $GroupId"

# Get device members from group, including nested group membership.
# The cast limits results to Entra device objects.
$DeviceMembersUri = "https://graph.microsoft.com/v1.0/groups/$GroupId/transitiveMembers/microsoft.graph.device?`$select=id,displayName,deviceId"

$GroupDevices = Invoke-GraphPagedRequest `
    -Uri $DeviceMembersUri `
    -Headers @{ "ConsistencyLevel" = "eventual" }

if (-not $GroupDevices -or $GroupDevices.Count -eq 0) {
    Write-Host "No device members found in the group."
    return
}

Write-Host "Group device objects found: $($GroupDevices.Count)"

# Get all Intune managed devices once, then match locally.
# azureADDeviceId on the Intune managedDevice maps to deviceId on the Entra device object.
$ManagedDevicesUri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$select=id,deviceName,azureADDeviceId,userPrincipalName,operatingSystem,managementAgent"

$ManagedDevices = Invoke-GraphPagedRequest -Uri $ManagedDevicesUri

if (-not $ManagedDevices -or $ManagedDevices.Count -eq 0) {
    Write-Host "No Intune managed devices found."
    return
}

$ManagedDeviceByAzureAdDeviceId = @{}

foreach ($ManagedDevice in $ManagedDevices) {
    if ($ManagedDevice.azureADDeviceId) {
        $ManagedDeviceByAzureAdDeviceId[$ManagedDevice.azureADDeviceId.ToLower()] = $ManagedDevice
    }
}

$Processed = 0
$SkippedNotManaged = 0
$SkippedNoPrimaryUser = 0
$Removed = 0
$Failed = 0

foreach ($GroupDevice in $GroupDevices) {
    $Processed++

    if (-not $GroupDevice.deviceId) {
        Write-Warning "Skipping group device '$($GroupDevice.displayName)' because it has no deviceId."
        $SkippedNotManaged++
        continue
    }

    $LookupKey = $GroupDevice.deviceId.ToLower()

    if (-not $ManagedDeviceByAzureAdDeviceId.ContainsKey($LookupKey)) {
        Write-Host "Skipping '$($GroupDevice.displayName)' - not found as an Intune managed device."
        $SkippedNotManaged++
        continue
    }

    $IntuneDevice = $ManagedDeviceByAzureAdDeviceId[$LookupKey]

    if (-not $IntuneDevice.userPrincipalName) {
        Write-Host "Skipping '$($IntuneDevice.deviceName)' - no primary user currently shown."
        $SkippedNoPrimaryUser++
        continue
    }

    $DeleteUri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices('$($IntuneDevice.id)')/users/`$ref"

    try {
        if ($PSCmdlet.ShouldProcess(
            "$($IntuneDevice.deviceName) / $($IntuneDevice.userPrincipalName)",
            "Remove Intune primary user"
        )) {
            Invoke-MgGraphRequest -Method DELETE -Uri $DeleteUri
            Write-Host "Removed primary user from '$($IntuneDevice.deviceName)' - was '$($IntuneDevice.userPrincipalName)'."
            $Removed++
        }
    }
    catch {
        Write-Warning "Failed to remove primary user from '$($IntuneDevice.deviceName)': $($_.Exception.Message)"
        $Failed++
    }
}

Write-Host ""
Write-Host "Summary"
Write-Host "-------"
Write-Host "Group devices processed: $Processed"
Write-Host "Primary users removed:   $Removed"
Write-Host "No primary user skipped: $SkippedNoPrimaryUser"
Write-Host "Not Intune managed:      $SkippedNotManaged"
Write-Host "Failed:                  $Failed"
