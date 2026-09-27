# Example: .\Remove-EntraDeviceOwnership.ps1 -ServiceAccountUpn 'service@example.com' -DryRun
# Variables: -ServiceAccountUpn selects the account; -DryRun previews changes; -OutputCsv chooses the report file.
# Purpose: Remove a named account from Entra device registered-owner links.
# Requires: Microsoft.Entra module and scopes in $scopes; installation is offered if needed.
# Effect: Writes an audit CSV; use -DryRun first, since live mode removes owner links.
#
param(
    [Parameter(Mandatory = $true)]
    [string]$ServiceAccountUpn,

    [switch]$DryRun,

    [string]$OutputCsv = ".\OwnershipRemovals_$(Get-Date -Format yyyyMMdd_HHmmss).csv"
)

# Ensure Microsoft.Entra is available
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
Assert-RequiredModules -Names @('Microsoft.Entra')
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