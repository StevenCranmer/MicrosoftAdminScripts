# Example: .\Delete-TeamsFromCsv.ps1 -CsvPath .\teams.example.csv
# Variables: -CsvPath is a CSV with a TeamId column; replace the dummy ID before running.
#
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$CsvPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Read-ExactYesNo {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prompt
    )

    while ($true) {
        $answer = (Read-Host "$Prompt [Y/N]").Trim()

        switch -Regex ($answer) {
            '^[Yy]$' { return $true }
            '^[Nn]$' { return $false }
            default   { Write-Host 'Enter Y or N.' -ForegroundColor Yellow }
        }
    }
}

if (-not (Get-Module -ListAvailable -Name MicrosoftTeams)) {
    throw "The MicrosoftTeams PowerShell module is not installed. Install it with: Install-Module MicrosoftTeams -Scope CurrentUser"
}

Import-Module MicrosoftTeams

$csvRows = @(Import-Csv -LiteralPath $CsvPath)

if ($csvRows.Count -eq 0) {
    throw 'The CSV is empty.'
}

if (-not ($csvRows[0].PSObject.Properties.Name -contains 'TeamId')) {
    throw "The CSV must contain a column named 'TeamId'."
}

$teamIds = @(
    $csvRows |
        ForEach-Object { [string]$_.TeamId } |
        ForEach-Object { $_.Trim() } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Select-Object -Unique
)

if ($teamIds.Count -eq 0) {
    throw "The CSV contains no TeamId values."
}

$invalidIds = @()
foreach ($teamId in $teamIds) {
    $parsedGuid = [guid]::Empty
    if (-not [guid]::TryParse($teamId, [ref]$parsedGuid)) {
        $invalidIds += $teamId
    }
}

if ($invalidIds.Count -gt 0) {
    Write-Host 'Invalid TeamId values:' -ForegroundColor Red
    $invalidIds | ForEach-Object { Write-Host "  $_" }
    throw 'No teams were deleted. Correct the CSV and run the script again.'
}

Write-Host 'Connecting to Microsoft Teams...'
Connect-MicrosoftTeams | Out-Null

$teamsToDelete = [System.Collections.Generic.List[object]]::new()
$lookupFailures = [System.Collections.Generic.List[object]]::new()

foreach ($teamId in $teamIds) {
    try {
        $team = Get-Team -GroupId $teamId -ErrorAction Stop

        if ($null -eq $team) {
            throw 'No team was returned.'
        }

        $teamsToDelete.Add([pscustomobject]@{
            DisplayName = $team.DisplayName
            TeamId      = $teamId
        })
    }
    catch {
        $lookupFailures.Add([pscustomobject]@{
            TeamId = $teamId
            Error  = $_.Exception.Message
        })
    }
}

if ($lookupFailures.Count -gt 0) {
    Write-Host ''
    Write-Host 'The following Team IDs could not be resolved:' -ForegroundColor Red
    $lookupFailures | Format-Table -AutoSize | Out-Host
    throw 'No teams were deleted because not every TeamId could be resolved.'
}

Write-Host ''
Write-Host 'THE FOLLOWING TEAMS WILL BE DELETED:' -ForegroundColor Red
Write-Host ''
$teamsToDelete |
    Sort-Object DisplayName |
    Format-Table DisplayName, TeamId -AutoSize |
    Out-Host

Write-Host "Total: $($teamsToDelete.Count) team(s)" -ForegroundColor Yellow
Write-Host ''

$firstConfirmation = Read-ExactYesNo 'Are you absolutely sure about this?'
if (-not $firstConfirmation) {
    Write-Host 'Cancelled. No teams were deleted.'
    exit 0
}

$secondConfirmation = Read-ExactYesNo 'FINAL CONFIRMATION: delete every team listed above?'
if (-not $secondConfirmation) {
    Write-Host 'Cancelled. No teams were deleted.'
    exit 0
}

$results = foreach ($team in $teamsToDelete) {
    try {
        Remove-Team -GroupId $team.TeamId -ErrorAction Stop

        [pscustomobject]@{
            DisplayName = $team.DisplayName
            TeamId      = $team.TeamId
            Result      = 'Deleted'
            Error       = $null
        }
    }
    catch {
        [pscustomobject]@{
            DisplayName = $team.DisplayName
            TeamId      = $team.TeamId
            Result      = 'Failed'
            Error       = $_.Exception.Message
        }
    }
}

Write-Host ''
Write-Host 'Deletion results:'
$results | Format-Table DisplayName, TeamId, Result, Error -Wrap -AutoSize | Out-Host

$failed = @($results | Where-Object Result -eq 'Failed')
if ($failed.Count -gt 0) {
    throw "$($failed.Count) team(s) could not be deleted. Review the results above."
}

Write-Host "Deleted $($results.Count) team(s)." -ForegroundColor Green
