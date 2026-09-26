# Example: .\Remove-EntraDeviceOwnership.ps1 -ServiceAccountUpn 'service@example.com' -DryRun
# Variables: -ServiceAccountUpn selects the account; -DryRun previews changes; -OutputCsv chooses the report file.
#
param(
    [Parameter(Mandatory = $true)]
    [string]$ServiceAccountUpn,

    [switch]$DryRun,

    [string]$OutputCsv = ".\OwnershipRemovals_$(Get-Date -Format yyyyMMdd_HHmmss).csv"
)

# Ensure Microsoft.Entra is available
if (-not (Get-Module -ListAvailable -Name Microsoft.Entra)) {
    Write-Host "Microsoft.Entra module not found. Installing for CurrentUser..." -ForegroundColor Yellow
    Install-Module Microsoft.Entra -Scope CurrentUser -Force -AllowClobber
}
Import-Module Microsoft.Entra -Force

# Connect with required delegated scopes
$scopes = @('Directory.AccessAsUser.All','Device.ReadWrite.All')
Write-Host "Connecting to Microsoft Entra..." -ForegroundColor Cyan
Connect-Entra -Scopes $scopes

# Resolve service account
$user = Get-EntraUser -Filter "userPrincipalName eq '$ServiceAccountUpn'"
if (-not $user) { throw "User '$ServiceAccountUpn' not found." }
Write-Host "Resolved user: $($user.DisplayName)  ObjectId: $($user.Id)" -ForegroundColor Green

# Enumerate Entra devices
Write-Host "Enumerating Entra devices..." -ForegroundColor Cyan
$allDevices = Get-EntraDevice -All

# Prepare log
$log = New-Object System.Collections.Generic.List[pscustomobject]
[int]$processed = 0
[int]$removed   = 0

foreach ($d in $allDevices) {
    $processed++
    Write-Progress -Activity "Scanning devices" -Status $d.DisplayName -PercentComplete (($processed/$allDevices.Count)*100)

    try {
        $owners = Get-EntraDeviceRegisteredOwner -DeviceId $d.Id -ErrorAction Stop
    } catch {
        Write-Warning "Failed to list owners for $($d.DisplayName): $($_.Exception.Message)"
        continue
    }

    if (-not $owners) { continue }

    $targetOwners = $owners | Where-Object {
        $_.UserPrincipalName -eq $ServiceAccountUpn -or $_.Id -eq $user.Id
    }

    foreach ($owner in $targetOwners) {
        $log.Add([pscustomobject]@{
            Timestamp         = Get-Date
            DeviceDisplayName = $d.DisplayName
            DeviceId          = $d.Id
            JoinType          = $d.JoinType
            ServiceAccountUPN = $ServiceAccountUpn
            Action            = $(if ($DryRun) { "DryRun-RemoveOwner" } else { "RemoveOwner" })
        })

        if ($DryRun) {
            Write-Host "[DryRun] Would remove owner from device: $($d.DisplayName) ($($d.Id))" -ForegroundColor Yellow
        } else {
            try {
                Remove-EntraDeviceRegisteredOwner -DeviceId $d.Id -OwnerId $owner.Id -ErrorAction Stop
                $removed++
                Write-Host "Removed owner from device: $($d.DisplayName)" -ForegroundColor Green
            } catch {
                Write-Warning "Failed to remove owner on $($d.DisplayName): $($_.Exception.Message)"
            }
        }
    }
}

$log | Export-Csv -NoTypeInformation -Path $OutputCsv
Write-Host "Done. Processed: $processed, Owner links removed: $removed. Log: $OutputCsv" -ForegroundColor Cyan