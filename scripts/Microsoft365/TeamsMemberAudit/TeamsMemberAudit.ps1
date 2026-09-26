# Example: .\TeamsMemberAudit.ps1 -GroupName 'Example Team'
# Variables: -GroupName filters the audit; -OutputPath chooses the report; -ShowAllInConsole prints all rows.
#
#Requires -Version 5.1
<#
.SYNOPSIS
    Audits membership, owners, archive status and recent activity for one Team or every Team.

.EXAMPLE
    .\TeamsMemberAudit.ps1 -GroupName "10B/Dr1 (2024)"

.EXAMPLE
    .\TeamsMemberAudit.ps1

.EXAMPLE
    .\TeamsMemberAudit.ps1 -ShowAllInConsole

.NOTES
    Required Microsoft Graph delegated permissions:
      Group.Read.All
      Reports.Read.All
      Team.ReadBasic.All
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, Position = 0)]
    [AllowEmptyString()]
    [string]$GroupName,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath,

    [Parameter(Mandatory = $false)]
    [switch]$ShowAllInConsole
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-CleanCsvRows {
    param([Parameter(Mandatory)][string]$Path)
    foreach ($row in (Import-Csv -LiteralPath $Path)) {
        $clean = [ordered]@{}
        foreach ($property in $row.PSObject.Properties) {
            $clean[$property.Name.Trim([char]0xFEFF)] = $property.Value
        }
        [PSCustomObject]$clean
    }
}

function Get-CsvValue {
    param(
        [AllowNull()][object]$Row,
        [Parameter(Mandatory)][string[]]$ColumnName
    )
    if ($null -eq $Row) { return $null }
    foreach ($name in $ColumnName) {
        $property = $Row.PSObject.Properties[$name]
        if ($null -ne $property) { return $property.Value }
    }
    return $null
}

function Get-SafeFileName {
    param([Parameter(Mandatory)][string]$Name)
    $invalidChars = [IO.Path]::GetInvalidFileNameChars()
    return -join ($Name.ToCharArray() | ForEach-Object {
        if ($_ -in $invalidChars -or $_ -eq '/' -or $_ -eq '\') { '_' } else { $_ }
    })
}

$requiredModules = @(
    'Microsoft.Graph.Authentication',
    'Microsoft.Graph.Groups',
    'Microsoft.Graph.Reports'
)
$missingModules = @($requiredModules | Where-Object { -not (Get-Module -ListAvailable -Name $_) })
if ($missingModules.Count -gt 0) {
    throw "Missing Microsoft Graph modules: $($missingModules -join ', '). Install with: Install-Module Microsoft.Graph -Scope CurrentUser"
}
foreach ($module in $requiredModules) { Import-Module $module -ErrorAction Stop }

$allTeamsMode = [string]::IsNullOrWhiteSpace($GroupName)
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $fileName = if ($allTeamsMode) {
        'All-Teams-Member-Audit.csv'
    } else {
        "$(Get-SafeFileName -Name $GroupName)-Teams-Audit.csv"
    }
    $OutputPath = Join-Path (Get-Location) $fileName
}

$usagePath = Join-Path $env:TEMP ("TeamsUsage-{0}.csv" -f [guid]::NewGuid())

try {
    $requiredScopes = @('Group.Read.All', 'Reports.Read.All', 'Team.ReadBasic.All')
    $context = Get-MgContext
    $missingScopes = @()
    if ($null -ne $context) {
        $missingScopes = @($requiredScopes | Where-Object { $_ -notin $context.Scopes })
    }

    if ($null -eq $context -or $missingScopes.Count -gt 0) {
        Write-Host 'No suitable cached Microsoft Graph session was found. Authentication is required.'
        Connect-MgGraph -Scopes $requiredScopes -ContextScope CurrentUser -NoWelcome
        $context = Get-MgContext
    } else {
        Write-Host "Using cached Microsoft Graph session for $($context.Account)."
    }

    Write-Host 'Retrieving Team-backed Microsoft 365 groups...'
    $teams = @(Get-MgGroup `
        -Filter "resourceProvisioningOptions/Any(x:x eq 'Team')" `
        -ConsistencyLevel eventual `
        -All `
        -Property 'Id,DisplayName,Mail,CreatedDateTime,Visibility')

    if (-not $allTeamsMode) {
        $teams = @($teams | Where-Object { $_.DisplayName -ceq $GroupName })
        if ($teams.Count -eq 0) { throw "No Microsoft Team was found with the exact display name '$GroupName'." }
        if ($teams.Count -gt 1) { Write-Warning "Multiple Teams have that exact name. All matches will be audited." }
    }
    if ($teams.Count -eq 0) { throw 'No Microsoft Teams were returned from the tenant.' }

    Write-Host 'Downloading the 180-day Teams usage report...'
    Get-MgReportTeamActivityDetail -Period D180 -OutFile $usagePath
    $usageByTeamId = @{}
    foreach ($row in @(Get-CleanCsvRows -Path $usagePath)) {
        $id = Get-CsvValue -Row $row -ColumnName @('Team Id')
        if (-not [string]::IsNullOrWhiteSpace($id)) { $usageByTeamId[$id] = $row }
    }

    $results = [System.Collections.Generic.List[object]]::new()
    $number = 0
    foreach ($team in ($teams | Sort-Object DisplayName)) {
        $number++
        Write-Progress -Activity 'Auditing Microsoft Teams' -Status "$number of $($teams.Count): $($team.DisplayName)" -PercentComplete (($number / $teams.Count) * 100)
        try {
            $members = @(Get-MgGroupMember -GroupId $team.Id -All)
            $owners = @(Get-MgGroupOwner -GroupId $team.Id -All)
            $ownerIds = @($owners | ForEach-Object { $_.Id })
            $nonOwnerMembers = @($members | Where-Object { $_.Id -notin $ownerIds })

            $ownerResponse = Invoke-MgGraphRequest -Method GET `
                -Uri ("https://graph.microsoft.com/v1.0/groups/{0}/owners?`$select=id,displayName" -f $team.Id) `
                -OutputType PSObject
            $ownerDisplayNames = @($ownerResponse.value | ForEach-Object { $_.displayName } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)

            $teamDetails = Invoke-MgGraphRequest -Method GET `
                -Uri ("https://graph.microsoft.com/v1.0/teams/{0}?`$select=isArchived" -f $team.Id) `
                -OutputType PSObject
            $isArchived = [bool]$teamDetails.isArchived

            $usageRow = if ($usageByTeamId.ContainsKey($team.Id)) { $usageByTeamId[$team.Id] } else { $null }

            $results.Add([PSCustomObject][ordered]@{
                TeamName            = $team.DisplayName
                TeamId              = $team.Id
                Email               = $team.Mail
                Visibility          = $team.Visibility
                CreatedDate         = $team.CreatedDateTime
                IsArchived          = $isArchived
                TotalMemberCount    = $members.Count
                OwnerCount          = $owners.Count
                OwnerDisplayNames   = $ownerDisplayNames -join '; '
                NonOwnerMemberCount = $nonOwnerMembers.Count
                HasNoMembers        = ($members.Count -eq 0)
                HasNoOwners         = ($owners.Count -eq 0)
                LastActivityDate    = Get-CsvValue -Row $usageRow -ColumnName @('Last Activity Date')
                ActiveUserCount     = Get-CsvValue -Row $usageRow -ColumnName @('Active User Count','Active Users')
                ActiveChannelCount  = Get-CsvValue -Row $usageRow -ColumnName @('Active Channel Count','Active Channels')
                ReportRefreshDate   = Get-CsvValue -Row $usageRow -ColumnName @('Report Refresh Date')
                UsageReportMatch    = ($null -ne $usageRow)
                CheckStatus         = 'Success'
                Error               = $null
            })
        } catch {
            $results.Add([PSCustomObject][ordered]@{
                TeamName=$team.DisplayName; TeamId=$team.Id; Email=$team.Mail; Visibility=$team.Visibility
                CreatedDate=$team.CreatedDateTime; IsArchived=$null; TotalMemberCount=$null; OwnerCount=$null
                OwnerDisplayNames=$null; NonOwnerMemberCount=$null; HasNoMembers=$null; HasNoOwners=$null
                LastActivityDate=$null; ActiveUserCount=$null; ActiveChannelCount=$null; ReportRefreshDate=$null
                UsageReportMatch=$false; CheckStatus='Failed'; Error=$_.Exception.Message
            })
        }
    }
    Write-Progress -Activity 'Auditing Microsoft Teams' -Completed

    $results | Sort-Object @{Expression='HasNoMembers';Descending=$true}, LastActivityDate, TeamName |
        Export-Csv -LiteralPath $OutputPath -NoTypeInformation -Encoding UTF8

    if (-not $allTeamsMode -or $ShowAllInConsole) {
        $results | Select-Object TeamName, IsArchived, TotalMemberCount, OwnerCount, OwnerDisplayNames, HasNoMembers, HasNoOwners, LastActivityDate, CheckStatus |
            Format-Table -AutoSize | Out-Host
    }

    $successful = @($results | Where-Object CheckStatus -eq 'Success')
    $failed = @($results | Where-Object CheckStatus -eq 'Failed')
    $empty = @($successful | Where-Object HasNoMembers -eq $true)
    $ownerless = @($successful | Where-Object HasNoOwners -eq $true)
    $archived = @($successful | Where-Object IsArchived -eq $true)

    Write-Host ''
    Write-Host "Teams audited:         $($results.Count)"
    Write-Host "Archived Teams:        $($archived.Count)"
    Write-Host "Teams with no members: $($empty.Count)"
    Write-Host "Ownerless Teams:       $($ownerless.Count)"
    Write-Host "Failed checks:         $($failed.Count)"
    Write-Host "Audit exported to:     $OutputPath"
    if ($failed.Count -gt 0) { Write-Warning 'Some Teams could not be checked. Review the CheckStatus and Error columns in the CSV.' }
}
finally {
    if (Test-Path -LiteralPath $usagePath) { Remove-Item -LiteralPath $usagePath -Force -ErrorAction SilentlyContinue }
    # Retain the CurrentUser Graph context for later runs.
}
