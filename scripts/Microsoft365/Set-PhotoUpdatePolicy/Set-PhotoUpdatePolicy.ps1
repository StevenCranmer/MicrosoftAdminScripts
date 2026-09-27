# Example: .\Set-PhotoUpdatePolicy.ps1 -ShowCurrent
# Variables: Use -ShowCurrent to inspect; the Allow* switches select who may update profile photos.
# Purpose: Inspect or configure who may update Microsoft 365 profile photos.
# Requires: Microsoft.Graph.Authentication and PeopleSettings.ReadWrite.All rights.
# Effect: ShowCurrent is read-only; other modes change tenant-wide beta policy. Use -WhatIf to preview.
#
<#
.SYNOPSIS
  Configure tenant-wide photo update policy so ONLY selected built-in admin roles can change user profile photos,
  or revert to default where EVERYONE can edit their own photo. Shows role names next to IDs everywhere.
  Optional -ResolveNamesOnline will look up unknown role IDs via Graph.

.DESCRIPTION
  Uses Microsoft Graph (beta) photoUpdateSettings to control who can update profile photos:
   - source = "cloud"  -> updates allowed in cloud; behavior controlled by 'allowedRoles'
   - allowedRoles      -> accepted role *template IDs* for built-in roles:
       * People Administrator : 024906de-61e5-49c8-8572-40335f1e0e10
       * User Administrator   : fe930be7-5e62-47db-91af-98c3a49a38b1
       * Global Administrator : 62e90394-69f5-4237-9190-012177145e10

  Custom directory roles are NOT accepted by this setting today.
  API is under /beta; allow up to 24 hours for clients to honor the setting.
  Docs:
    - Manage photo settings & examples: https://learn.microsoft.com/graph/profilephoto-configure-settings
    - Update photoUpdateSettings (beta): https://learn.microsoft.com/graph/api/photoupdatesettings-update?view=graph-rest-beta
    - Connect-MgGraph reference: https://learn.microsoft.com/powershell/module/microsoft.graph.authentication/connect-mggraph

.PARAMETER AllowPeopleAdmin
  Include People Administrator in allowedRoles (default: $true)

.PARAMETER AllowUserAdmin
  Include User Administrator in allowedRoles (default: $false)

.PARAMETER AllowGlobalAdmin
  Include Global Administrator in allowedRoles (default: $false)

.PARAMETER AllowEveryone
  Revert to default: let ALL users edit their own profile photos (sets allowedRoles = @()).

.PARAMETER ShowCurrent
  Read-only: show current photoUpdateSettings and exit (no changes are made).

.PARAMETER ResolveNamesOnline
  If set, resolves any unknown role IDs to display names via Graph roleDefinitions (adds RoleManagement.Read.Directory to scopes).

.PARAMETER WhatIf
  Show what would change without applying it.

.EXAMPLE
  .\Set-PhotoUpdatePolicy.ps1 -ShowCurrent
  # => Prints current photoUpdateSettings with role names & IDs; exits.

.EXAMPLE
  .\Set-PhotoUpdatePolicy.ps1
  # => Only People Administrators can change profile photos (recommended minimal privilege), shows names+IDs everywhere.

.EXAMPLE
  .\Set-PhotoUpdatePolicy.ps1 -AllowEveryone
  # => Revert to default: everyone can update their own photo.

.NOTES
  Requires Microsoft.Graph.Authentication (SDK v2+).
  You’ll be prompted to sign in and consent PeopleSettings.ReadWrite.All (and RoleManagement.Read.Directory if -ResolveNamesOnline).
#>

[CmdletBinding(SupportsShouldProcess)]
param(
  [switch]$AllowPeopleAdmin = $true,
  [switch]$AllowUserAdmin   = $false,
  [switch]$AllowGlobalAdmin = $false,
  [switch]$AllowEveryone    = $false,
  [switch]$ShowCurrent      = $false,
  [switch]$ResolveNamesOnline = $false
)

# Optional: lift function cap on Windows PowerShell 5.1
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

# Minimal import
Import-Module Microsoft.Graph.Authentication -ErrorAction Stop

Write-Host 'Connecting to Microsoft Graph...' -ForegroundColor Cyan
$scopes = @('PeopleSettings.ReadWrite.All') # minimum to GET/PATCH photoUpdateSettings
if ($ResolveNamesOnline) { $scopes += 'RoleManagement.Read.Directory' } # needed to look up role display names
# Ref: Connect-MgGraph usage -> https://learn.microsoft.com/powershell/module/microsoft.graph.authentication/connect-mggraph
Connect-MgGraph -Scopes $scopes -UseDeviceCode -NoWelcome | Out-Null

# Supported built-in role template IDs for photoUpdateSettings (cloud)
# Source: Microsoft docs examples for this control
$RoleTemplates = @{
  'People Administrator' = '024906de-61e5-49c8-8572-40335f1e0e10'
  'User Administrator'   = 'fe930be7-5e62-47db-91af-98c3a49a38b1'
  'Global Administrator' = '62e90394-69f5-4237-9190-012177145e10'
}
# Reverse map for quick name lookup
$RoleNamesById = @{}
$RoleTemplates.GetEnumerator() | ForEach-Object { $RoleNamesById[$_.Value] = $_.Key }

function Get-PhotoUpdateSettings {
  Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/beta/admin/people/photoupdatesettings' -ErrorAction Stop
}

# Attempts to resolve a role template ID to its display name via Graph (if not known)
function Resolve-RoleNameOnline {
  param([Parameter(Mandatory)] [string]$Id)
  if (-not $ResolveNamesOnline) { return $null }
  try {
    $u = "https://graph.microsoft.com/v1.0/roleManagement/directory/roleDefinitions?`$filter=id eq '$Id'&`$select=id,displayName"
    $r = Invoke-MgGraphRequest -Method GET -Uri $u -ErrorAction Stop
    if ($r.value -and $r.value.Count -gt 0 -and $r.value[0].displayName) {
      return [string]$r.value[0].displayName
    }
  } catch {
    # ignore lookup failures; we'll show Unknown
  }
  return $null
}

# Formats a list of role template IDs into "Display Name (Id)" items, comma-separated.
function Format-RoleList {
  param([string[]]$Ids)
  if (-not $Ids -or $Ids.Count -eq 0) { return 'Everyone (allowedRoles empty)' }
  $items = foreach ($id in $Ids) {
    $name = $null
    if ($RoleNamesById.ContainsKey($id)) { $name = $RoleNamesById[$id] }
    if (-not $name) { $name = Resolve-RoleNameOnline -Id $id }
    if (-not $name) { $name = 'Unknown role' }
    "$name ($id)"
  }
  return ($items -join ', ')
}

# Build the allowlist according to switches
$allowed = New-Object System.Collections.Generic.List[string]

if ($AllowEveryone) {
  Write-Host "Mode: AllowEveryone (default behavior) — allowedRoles will be empty." -ForegroundColor Yellow
} else {
  if ($AllowPeopleAdmin) { [void]$allowed.Add($RoleTemplates['People Administrator']) }
  if ($AllowUserAdmin)   { [void]$allowed.Add($RoleTemplates['User Administrator']) }
  if ($AllowGlobalAdmin) { [void]$allowed.Add($RoleTemplates['Global Administrator']) }

  if ($allowed.Count -eq 0) {
    Write-Warning "No roles selected. If you intended to allow everyone, use -AllowEveryone. Otherwise select at least one role switch."
    return
  }
}

# Quick read-only mode
if ($ShowCurrent) {
  Write-Host "Reading current photoUpdateSettings (beta)..." -ForegroundColor Cyan
  $current = Get-PhotoUpdateSettings
  $currentAllowed = @()
  if ($current.allowedRoles) { $currentAllowed = $current.allowedRoles }
  Write-Host "`nCurrent settings (friendly):" -ForegroundColor Green
  [pscustomobject]@{
    Source             = $current.source
    AllowedRoles       = Format-RoleList -Ids $currentAllowed
    AllowedRoleIdsRaw  = if ($currentAllowed.Count) { $currentAllowed -join ', ' } else { '(empty)' }
  } | Format-List
  Write-Host "`nRaw JSON from Graph:" -ForegroundColor DarkCyan
  $current | ConvertTo-Json -Depth 5
  Write-Host "`nNo changes made (ShowCurrent)." -ForegroundColor Yellow
  return
}

# Fetch current settings
$current = Get-PhotoUpdateSettings
$currentAllowed = @()
if ($current.allowedRoles) { $currentAllowed = $current.allowedRoles }

# Target state
$target = [ordered]@{
  source       = 'cloud'
  allowedRoles = if ($AllowEveryone) { @() } else { $allowed.ToArray() }
}

# Compare (order-insensitive for allowedRoles)
function Compare-Arrays([string[]]$A,[string[]]$B) {
  if ($null -eq $A -and $null -eq $B) { return $true }
  if ($A.Count -ne $B.Count) { return $false }
  return @(Compare-Object -ReferenceObject $A -DifferenceObject $B -SyncWindow 0).Count -eq 0
}

$needsSourceChange = ($current.source -ne $target.source)
$needsRolesChange  = -not (Compare-Arrays $currentAllowed $target.allowedRoles)

if (-not $needsSourceChange -and -not $needsRolesChange) {
  Write-Host "No change needed. Current settings already match target." -ForegroundColor Green
  [pscustomobject]@{
    Source       = $current.source
    AllowedRoles = Format-RoleList -Ids $currentAllowed
  } | Format-List
  return
}

Write-Host "Planned change:" -ForegroundColor Yellow
[pscustomobject]@{
  CurrentSource = $current.source
  TargetSource  = $target.source
  CurrentRoles  = Format-RoleList -Ids $currentAllowed
  TargetRoles   = Format-RoleList -Ids $target.allowedRoles
} | Format-List

if ($PSCmdlet.ShouldProcess("photoUpdateSettings","PATCH to source='$($target.source)' with allowedRoles=[$([string]::Join(', ',$target.allowedRoles))]")) {
  $bodyJson = $target | ConvertTo-Json -Depth 5
  Write-Host "Applying photoUpdateSettings (beta)..." -ForegroundColor Cyan
  Invoke-MgGraphRequest -Method PATCH `
    -Uri 'https://graph.microsoft.com/beta/admin/people/photoupdatesettings' `
    -ContentType 'application/json' -Body $bodyJson -ErrorAction Stop

  Start-Sleep -Seconds 2
  $verify = Get-PhotoUpdateSettings
  $verifyAllowed = @()
  if ($verify.allowedRoles) { $verifyAllowed = $verify.allowedRoles }

  Write-Host 'photoUpdateSettings updated:' -ForegroundColor Green
  [pscustomobject]@{
    Source       = $verify.source
    AllowedRoles = Format-RoleList -Ids $verifyAllowed
  } | Format-List

  Write-Host "`nReminder: It can take up to 24 hours to fully apply across clients (Teams/OWA/MyAccount)." -ForegroundColor Yellow
}
