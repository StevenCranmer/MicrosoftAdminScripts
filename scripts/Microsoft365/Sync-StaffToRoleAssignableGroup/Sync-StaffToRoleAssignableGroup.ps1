# Example: .\Sync-StaffToRoleAssignableGroup.ps1 -SourceGroupId '<SOURCE_GROUP_ID>' -TargetGroupId '<TARGET_GROUP_ID>' -DryRun
# Variables: -SourceGroupId and -TargetGroupId select groups; -DryRun previews; TenantId, ClientId and CertThumbprint are optional app authentication settings.
#
<#
.SYNOPSIS
  Sync a dynamic “All Staff” group to a role-assignable group (users only).

.DESCRIPTION
  - Reads direct user members from SOURCE (dynamic) group.
  - Ensures TARGET (role-assignable) group has the same users.
  - Adds missing users; optionally removes users no longer in SOURCE.
  - Skips non-user objects (devices, service principals, groups).

.PARAMETER SourceGroupId
  ObjectId (GUID) of the dynamic source group containing all staff.

.PARAMETER TargetGroupId
  ObjectId (GUID) of the role-assignable security group that will receive staff membership.

.PARAMETER RemoveExtraneous
  If set, users in TARGET but not in SOURCE will be removed from TARGET.

.PARAMETER DryRun
  If set, prints the plan without making changes.

# --- Authentication options (pick ONE) ---
.PARAMETER TenantId
  (App-only) Tenant GUID for Connect-MgGraph with certificate.

.PARAMETER ClientId
  (App-only) App registration (enterprise app) client ID.

.PARAMETER CertThumbprint
  (App-only) Local certificate thumbprint used for app-only auth.

.NOTES
  Requires Microsoft.Graph PowerShell SDK:
    Install-Module Microsoft.Graph -Scope CurrentUser
  Permissions:
    Delegated: Group.ReadWrite.All, GroupMember.ReadWrite.All, User.Read.All
    App-only : Application perms GroupMember.ReadWrite.All (+Group.Read.All/User.Read.All)
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory)] [string]$SourceGroupId,
  [Parameter(Mandatory)] [string]$TargetGroupId,
  [switch]$RemoveExtraneous,
  [switch]$DryRun,
  [string]$TenantId,
  [string]$ClientId,
  [string]$CertThumbprint
)

# ------------------------------
# 0) Connect to Microsoft Graph
# ------------------------------
if (-not (Get-Module Microsoft.Graph -ListAvailable)) {
  Write-Host "Installing Microsoft.Graph module..." -ForegroundColor Yellow
  Install-Module Microsoft.Graph -Scope CurrentUser -Force
}
Import-Module Microsoft.Graph.Authentication
Import-Module Microsoft.Graph.Groups
Import-Module Microsoft.Graph.Users


function Connect-GraphSmart {
  if ($TenantId -and $ClientId -and $CertThumbprint) {
    Write-Host "Connecting to Graph (app-only)..." -ForegroundColor Cyan
    Connect-MgGraph -TenantId $TenantId -ClientId $ClientId -CertificateThumbprint $CertThumbprint `
      -Scopes "https://graph.microsoft.com/.default" | Out-Null
  } else {
    Write-Host "Connecting to Graph (delegated interactive)..." -ForegroundColor Cyan
    Connect-MgGraph -Scopes @('Group.ReadWrite.All','GroupMember.ReadWrite.All','User.Read.All') | Out-Null
  }
  $ctx = Get-MgContext
  Write-Host ("Connected to tenant {0} as {1}" -f $ctx.TenantId, $ctx.Account) -ForegroundColor Green
}
Connect-GraphSmart

# ------------------------------
# 1) Helpers
# ------------------------------
function Invoke-WithRetry {
  param([scriptblock]$Action, [int]$MaxAttempts = 6)
  $attempt = 0
  while ($true) {
    try { $attempt++; return & $Action } catch {
      $msg = $_.Exception.Message
      $retry = $null
      if ($_.Exception.Response -and $_.Exception.Response.Headers['Retry-After']) {
        $retry = [int]$_.Exception.Response.Headers['Retry-After']
      }
      if ($attempt -ge $MaxAttempts) { throw "Failed after $MaxAttempts attempts. Last error: $msg" }
      if (-not $retry) { $retry = [math]::Min([math]::Pow(2,$attempt), 60) } # backoff
      Write-Warning ("Graph transient error/throttling. Retry in {0} sec. Error: {1}" -f $retry, $msg)
      Start-Sleep -Seconds $retry
    }
  }
}

function Get-UserMembers {
  param([string]$GroupId)

  try {
    # Prefer the typed navigation if available:
    if (Get-Command Get-MgGroupMemberAsUser -ErrorAction SilentlyContinue) {
      $members = Get-MgGroupMemberAsUser -GroupId $GroupId -All -PageSize 999 -ErrorAction Stop
      return @($members | Select-Object -ExpandProperty Id)
    }

    # Fallback: generic members endpoint; filter users locally
    $generic = Get-MgGroupMember -GroupId $GroupId -All -PageSize 999 -ErrorAction Stop
    $userIds = foreach ($m in $generic) {
      $t = $m.AdditionalProperties['@odata.type']
      if ($t -eq '#microsoft.graph.user') { $m.Id }
    }
    return @($userIds)
  }
  catch {
    Write-Warning ("Get-UserMembers failed for group {0}: {1}" -f $GroupId, $_.Exception.Message)
    return @()   # never return $null
  }
}



function Add-TargetMember {
  param([string]$UserId)
  # Build @odata.id without interpolation quirks
  $refUrl = "https://graph.microsoft.com/v1.0/directoryObjects/{0}" -f $UserId
  $body   = @{ '@odata.id' = $refUrl }
  Invoke-WithRetry { New-MgGroupMemberByRef -GroupId $TargetGroupId -BodyParameter $body -ErrorAction Stop | Out-Null }
}

function Remove-TargetMember {
  param([string]$UserId)
  Invoke-WithRetry { Remove-MgGroupMemberByRef -GroupId $TargetGroupId -DirectoryObjectId $UserId -ErrorAction Stop | Out-Null }
}

# ------------------------------
# 2) Optional: sanity check TARGET is role-assignable
# ------------------------------
try {
  $tg = Get-MgGroup -GroupId $TargetGroupId -Property "id,displayName,securityEnabled,isAssignableToRole" -ErrorAction Stop
  if ($tg.PSObject.Properties.Name -contains 'isAssignableToRole') {
    if (-not $tg.isAssignableToRole) {
      Write-Warning ("Target group '{0}' is not role-assignable (isAssignableToRole={1})." -f $tg.DisplayName, $tg.isAssignableToRole)
    }
  } else {
    Write-Host "isAssignableToRole not exposed by SDK; continuing..." -ForegroundColor DarkYellow
  }
} catch {
  Write-Warning ("Could not read target group properties: {0}" -f $_.Exception.Message)
}

# ------------------------------
# 3) Read members & compute deltas
# ------------------------------
Write-Host 'Fetching SOURCE (dynamic staff) users...' -ForegroundColor Cyan
$srcUsers = Get-UserMembers -GroupId $SourceGroupId
$srcUsers = @($srcUsers)   # force array, not $null
Write-Host ('Source users: {0}' -f $srcUsers.Count)

Write-Host 'Fetching TARGET (role-assignable) users...' -ForegroundColor Cyan
$tgtUsers = Get-UserMembers -GroupId $TargetGroupId
$tgtUsers = @($tgtUsers)   # force array, not $null
Write-Host ('Target users: {0}' -f $tgtUsers.Count)

# ---------- NEW: simple set logic ----------
$toAdd    = @($srcUsers | Where-Object   { $_ -notin $tgtUsers })
$toRemove = @()
if ($RemoveExtraneous) {
  $toRemove = @($tgtUsers | Where-Object { $_ -notin $srcUsers })
}
# ------------------------------------------


Write-Host ([Environment]::NewLine + 'Planned changes:') -ForegroundColor Yellow
Write-Host ('  Add   : {0}' -f $toAdd.Count)
Write-Host ('  Remove: {0}' -f $toRemove.Count)

if ($DryRun) {
  Write-Host ([Environment]::NewLine + 'DryRun mode—no changes will be made.') -ForegroundColor Yellow
  if ($toAdd)    { Write-Host ([Environment]::NewLine + 'Users to ADD (ids):');    $toAdd }
  if ($toRemove) { Write-Host ([Environment]::NewLine + 'Users to REMOVE (ids):'); $toRemove }
  return
}

# ------------------------------
# 4) Apply changes
# ------------------------------

if ($toAdd.Count -gt 0) {
  Write-Host ([Environment]::NewLine + ('Adding {0} users to target...' -f $toAdd.Count)) -ForegroundColor Green
  $i=0
  foreach ($id in $toAdd) {
    $i++
    try { Add-TargetMember -UserId $id } catch { Write-Warning ('Add failed for {0}: {1}' -f $id, $_.Exception.Message) }
    if ($i % 50 -eq 0) { Write-Host ('  Added {0}/{1}...' -f $i, $toAdd.Count) }
  }
}

if ($toRemove.Count -gt 0) {
  Write-Host ([Environment]::NewLine + ('Removing {0} users from target...' -f $toRemove.Count)) -ForegroundColor Green
  $i=0
  foreach ($id in $toRemove) {
    $i++
    try { Remove-TargetMember -UserId $id } catch { Write-Warning ('Remove failed for {0}: {1}' -f $id, $_.Exception.Message) }
    if ($i % 50 -eq 0) { Write-Host ('  Removed {0}/{1}...' -f $i, $toRemove.Count) }
  }
}

Write-Host ([Environment]::NewLine + 'Sync complete.') -ForegroundColor Cyan


