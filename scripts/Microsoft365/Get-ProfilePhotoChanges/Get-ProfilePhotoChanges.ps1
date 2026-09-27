# Example: .\Get-ProfilePhotoChanges.ps1 -DaysBack 7 -CsvPath .\photo-changes.csv
# Variables: -DaysBack sets the date range; -CsvPath and -RawJsonPath choose output files; -UserIds filters users.
# Purpose: Find profile-photo change events in the Unified Audit Log.
# Requires: ExchangeOnlineManagement and rights to search the audit log.
# Effect: Writes CSV and raw JSON with account identifiers; keep exports private.
#
<#
.SYNOPSIS
  Finds Microsoft 365 user profile photo changes in the Unified Audit Log and exports to CSV.

.PARAMETER DaysBack
  Days to search backward from now (default 7). Converted to UTC automatically.

.PARAMETER CsvPath
  CSV export path (default .\ProfilePhotoChanges.csv).

.PARAMETER RawJsonPath
  Raw JSON dump of AuditData for each hit (default .\ProfilePhotoChanges_raw.json).

.PARAMETER UserIds
  Optional array of specific users to scope the search (UPNs).

.NOTES
  Requires: ExchangeOnlineManagement module (Search-UnifiedAuditLog).
  Roles: Audit Logs or View-Only Audit Logs.
  UAL StartDate/EndDate are UTC; we convert automatically. 
#>

[CmdletBinding()]
param(
    [int]$DaysBack = 7,
    [string]$CsvPath = ".\ProfilePhotoChanges.csv",
    [string]$RawJsonPath = ".\ProfilePhotoChanges_raw.json",
    [string[]]$UserIds
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
Assert-RequiredModules -Names @('ExchangeOnlineManagement')
$ErrorActionPreference = 'Continue'

# ---------------------------
# 0) Module + Connection
# ---------------------------
if (-not (Get-Module -ListAvailable -Name ExchangeOnlineManagement)) {
    Write-Error "ExchangeOnlineManagement module not found. Install-Module ExchangeOnlineManagement"
    return
}

Import-Module ExchangeOnlineManagement -ErrorAction Stop

$connected = $false
try {
    if (Get-Command Get-ConnectionInformation -ErrorAction SilentlyContinue) {
        $info = Get-ConnectionInformation
        $connected = ($null -ne $info) -and ($info | Where-Object { $_.State -eq 'Connected' })
    }
} catch { $connected = $false }

if (-not $connected) {
    Connect-ExchangeOnline -ShowBanner:$false | Out-Null
}

# Check UAL ingestion in EXO PS (note: in Sec&Compliance PS it always shows False per MS docs)
try {
    $auditCfg = Get-AdminAuditLogConfig -ErrorAction Stop
    if (-not $auditCfg.UnifiedAuditLogIngestionEnabled) {
        Write-Warning "Unified Audit Log ingestion appears to be OFF. Turn it on in the Purview portal before running searches."
    }
} catch {
    Write-Warning "Could not read AdminAuditLogConfig. Ensure you have permissions. Continuing..."
}

# ---------------------------
# 1) Time window (UTC)
# ---------------------------
$end   = (Get-Date).ToUniversalTime()
$start = $end.AddDays(-[math]::Abs($DaysBack))

Write-Host "Searching (UTC) from $($start.ToString('u')) to $($end.ToString('u'))..." -ForegroundColor Cyan

# ---------------------------
# 2) Query strategy
# ---------------------------
$operationsToTry = @(
    "Set-UserPhoto"         # Exchange admin audit (cmdlet operation name)
) | Select-Object -Unique

$freeTextToTry = @(
    "thumbnailPhoto",       # AAD attribute
    "user photo",
    "profile photo",
    "UserPhoto",
    "Set-UserPhoto"
) | Select-Object -Unique

# Mandatory result page size per MS docs (default 100; max 5000)
$PageSize = 5000  # returns up to 5000 per iteration. Max per session is 50,000 with ReturnLargeSet.
$SessionCap = 50000

function Invoke-UalQuery {
    [CmdletBinding()]
    param(
        [datetime]$StartDateUtc,
        [datetime]$EndDateUtc,
        [string[]]$Operations,
        [string]$FreeText,
        [string[]]$UserIds
    )

    $sessionId = [guid]::NewGuid().ToString()
    $pageCount = 0
    $all = New-Object System.Collections.Generic.List[object]

    do {
        try {
            $args = @{
                StartDate     = $StartDateUtc
                EndDate       = $EndDateUtc
                ResultSize    = $PageSize
                SessionId     = $sessionId
                SessionCommand= 'ReturnLargeSet'
            }
            if ($Operations) { $args['Operations'] = $Operations }
            if ($FreeText)   { $args['FreeText']   = $FreeText }
            if ($UserIds)    { $args['UserIds']    = $UserIds }

            $page = Search-UnifiedAuditLog @args -ErrorAction Stop
            $count = ($page | Measure-Object).Count
            if ($count -gt 0) {
                # Normalize objects a bit (remove Identity noise)
                $page | ForEach-Object { $_.PSObject.Properties.Remove("Identity") | Out-Null }
                [void]$all.AddRange($page)
            }

            $pageCount += $count

            if ($pageCount -ge $SessionCap) {
                Write-Warning "Reached the 50,000 record session cap. Consider slicing the time window into smaller chunks."
                break
            }

        } catch {
            Write-Warning "Audit search failed: $($_.Exception.Message)"
            break
        }

        # Keep looping until the cmdlet returns 0 for this session.
        # With ReturnLargeSet, repeating the command using the same SessionId pages through results.
    } while ($count -gt 0)

    return $all
}

$records = New-Object System.Collections.Generic.List[object]

# 2a) Exact operation searches first (tends to return fewer, higher-signal results)
if ($operationsToTry.Count -gt 0) {
    $opResults = Invoke-UalQuery -StartDateUtc $start -EndDateUtc $end -Operations $operationsToTry -UserIds $UserIds
    if ($opResults) { [void]$records.AddRange($opResults) }
}

# 2b) Free-text sweeps to catch UI/Graph/Directory paths
foreach ($term in $freeTextToTry) {
    $ftResults = Invoke-UalQuery -StartDateUtc $start -EndDateUtc $end -FreeText $term -UserIds $UserIds
    if ($ftResults) { [void]$records.AddRange($ftResults) }
}

if ($records.Count -eq 0) {
    Write-Host "No candidate audit events found in the selected window." -ForegroundColor Yellow
    Disconnect-ExchangeOnline -Confirm:$false
    return
}

# Deduplicate by ExternalId when present; fall back to a composite key
$records = $records | ForEach-Object {
    $key = if ($_.ExternalId) { $_.ExternalId } else { "$($_.CreationDate.Ticks)|$($_.Operation)|$($_.UserIds -join ';')" }
    [pscustomobject]@{ Key=$key; Row=$_ }
} | Group-Object Key | ForEach-Object { $_.Group[0].Row }

# ---------------------------
# 3) Parse AuditData JSON robustly
# ---------------------------
function Parse-AuditRow {
    param([object]$row)

    $audit = $null
    try { $audit = $row.AuditData | ConvertFrom-Json -ErrorAction Stop } catch {}

    # Defaults
    $actor   = ($row.UserIds -join '; ')
    $target  = $row.ObjectId
    $details = $null

    if ($audit) {
        # Prefer explicit UserId when available
        if ($audit.UserId) { $actor = $audit.UserId }

        # Or Actor array -> join Ids
        if (-not $actor -and $audit.Actor) {
            try {
                $actorIds = @($audit.Actor) | ForEach-Object { $_.Id }
                if ($actorIds) { $actor = ($actorIds -join '; ') }
            } catch {}
        }

        # Targets from common schemas
        if ($audit.Target) {
            try {
                if ($audit.Target -is [string]) { $target = $audit.Target }
                else {
                    $tIds = @($audit.Target) | ForEach-Object { $_.Id }
                    if ($tIds) { $target = ($tIds -join '; ') }
                }
            } catch {}
        }

        # Exchange Admin cmdlet shape
        if ($audit.CmdletName -or $audit.Parameters) {
            $cmdlet = $audit.CmdletName
            $idParam = $audit.Parameters | Where-Object { $_.Name -match '^(Identity|User|Recipient|Mailbox)$' } | Select-Object -First 1
            if ($idParam) { $target = $idParam.Value }
            $details = "Cmdlet=$cmdlet; Parameters=" + (($audit.Parameters | ForEach-Object {"$($_.Name)=$($_.Value)"}) -join '; ')
        }

        # Directory-style ModifiedProperties
        if ($audit.ModifiedProperties) {
            $photoMods = $audit.ModifiedProperties | Where-Object {
                $_.Name -match 'thumbnailPhoto|photo|UserPhoto|ProfilePicture'
            }
            if ($photoMods) {
                $propNames = ($photoMods | ForEach-Object { $_.Name } | Sort-Object -Unique) -join ','
                if ($details) { $details += '; ' }
                $details += "ModifiedProperties=$propNames"
            }
        }
    }

    [pscustomobject]@{
        TimeGenerated = [datetime]$row.CreationDate
        Operation     = $row.Operation
        Workload      = $row.Workload
        RecordType    = $row.RecordType
        Actor         = $actor
        Target        = $target
        Result        = $row.ResultStatus
        ClientIP      = $row.ClientIP
        Details       = $details
        RawAuditData  = $row.AuditData
    }
}

$parsed = $records | ForEach-Object { Parse-AuditRow $_ }

# Filter to strongest matches (keep exact photo ops or entries that mention photo in details/raw)
$parsed = $parsed | Where-Object {
    $_.Operation -match 'Set-UserPhoto' -or
    $_.Details   -match 'thumbnailPhoto|photo|UserPhoto|ProfilePicture' -or
    $_.RawAuditData -match 'thumbnailPhoto|photo|UserPhoto|ProfilePicture|Set-UserPhoto'
}

# ---------------------------
# 4) Export
# ---------------------------
$parsed | Sort-Object TimeGenerated |
    Select-Object TimeGenerated, Operation, Workload, RecordType, Actor, Target, Result, ClientIP, Details |
    Export-Csv -NoTypeInformation -Encoding UTF8 -Path $CsvPath

$parsed |
    Select-Object TimeGenerated, Operation, Actor, Target, RawAuditData |
    ConvertTo-Json -Depth 6 |
    Out-File -FilePath $RawJsonPath -Encoding UTF8

Write-Host ""
Write-Host ("Exported {0} events to:" -f $parsed.Count) -ForegroundColor Green
Write-Host "  CSV : $CsvPath"
Write-Host "  JSON: $RawJsonPath"
Write-Host ""

Disconnect-ExchangeOnline -Confirm:$false
