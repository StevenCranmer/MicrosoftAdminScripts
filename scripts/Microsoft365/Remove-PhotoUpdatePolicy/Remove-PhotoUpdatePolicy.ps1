# Example: .\Remove-PhotoUpdatePolicy.ps1
# Variables: No user-supplied variables; this runs in the current account or device context.
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

if ($PSVersionTable.PSEdition -eq 'Desktop') { $MaximumFunctionCount = 32768 }

Import-Module Microsoft.Graph.Authentication -ErrorAction SilentlyContinue
Connect-MgGraph -Scopes @('PeopleSettings.ReadWrite.All') | Out-Null

$token = Get-MgGraphAccessToken -Scopes "PeopleSettings.ReadWrite.All"
if (-not $token) { throw "Failed to acquire Graph access token." }

$headers = @{ Authorization = "Bearer $token" }

try {
  Invoke-RestMethod -Method DELETE -Uri 'https://graph.microsoft.com/beta/admin/people/photoUpdateSettings' -Headers $headers -ErrorAction Stop
  Write-Host 'photoUpdateSettings deleted. Tenant is back to default behavior.' -ForegroundColor Green

  # Check current state
  try {
    $now = Invoke-RestMethod -Method GET -Uri 'https://graph.microsoft.com/beta/admin/people/photoUpdateSettings' -Headers $headers -ErrorAction Stop
    Write-Host 'A photoUpdateSettings object still exists:' -ForegroundColor Yellow
    $now | ConvertTo-Json -Depth 5
  } catch {
    Write-Host 'Verified: no active photoUpdateSettings object found.' -ForegroundColor Cyan
  }
} catch {
  Write-Error ("Failed to delete photoUpdateSettings: {0}" -f $_.Exception.Message)
  throw
}
