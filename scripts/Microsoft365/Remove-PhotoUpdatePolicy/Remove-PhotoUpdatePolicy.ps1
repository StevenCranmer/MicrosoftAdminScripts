# Example: .\Remove-PhotoUpdatePolicy.ps1
# Variables: No user-supplied variables; this runs in the current account or device context.
# Purpose: Delete the tenant photo-update policy object to restore defaults.
# Requires: Microsoft.Graph.Authentication and PeopleSettings.ReadWrite.All; sign-in is prompted.
# Effect: Changes tenant-wide photo settings; users may regain photo-editing ability.
#
<#
Deletes photoUpdateSettings to restore default behavior (users can change photos unless blocked elsewhere).

Requires:
  - Microsoft.Graph.Authentication
  - Delegated: PeopleSettings.ReadWrite.All
Refs:
  - GET photoUpdateSettings (beta): https://learn.microsoft.com/graph/api/photoupdatesettings-get?view=graph-rest-beta
  - Manage photo settings & propagation: https://learn.microsoft.com/graph/profilephoto-configure-settings
#>

[CmdletBinding()]
param()

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
if ($PSVersionTable.PSEdition -eq 'Desktop') { $MaximumFunctionCount = 32768 }

Import-Module Microsoft.Graph.Authentication -ErrorAction SilentlyContinue
Connect-MgGraph -Scopes @('PeopleSettings.ReadWrite.All') | Out-Null

try {
  Invoke-MgGraphRequest -Method DELETE -Uri 'https://graph.microsoft.com/beta/admin/people/photoUpdateSettings' -ErrorAction Stop
  Write-Host 'photoUpdateSettings deleted. Tenant is back to default behavior.' -ForegroundColor Green

  # Check current state
  try {
    $now = Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/beta/admin/people/photoUpdateSettings' -ErrorAction Stop
    Write-Host 'A photoUpdateSettings object still exists:' -ForegroundColor Yellow
    $now | ConvertTo-Json -Depth 5
  } catch {
    Write-Host 'Verified: no active photoUpdateSettings object found.' -ForegroundColor Cyan
  }
} catch {
  Write-Error ("Failed to delete photoUpdateSettings: {0}" -f $_.Exception.Message)
  throw
}
