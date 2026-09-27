# Example: .\Export-Year12Year13AllCreatedDates-Fixed.ps1 -OutputPath .\created-dates.csv
# Variables: Set $Groups to your year-group IDs; -OutputPath selects the report file.
# Purpose: Report account creation dates for two configured year-group IDs.
# Requires: Microsoft.Graph PowerShell commands and permission to read group members and users.
# Effect: Writes a CSV containing user details; keep real exports outside this repository.
#
[CmdletBinding()]
param(
    [Parameter()]
    [string]$OutputPath = ".\Year12Year13-AllCreatedDates.csv"
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
Assert-RequiredModules -Names @('Microsoft.Graph.Authentication','Microsoft.Graph.Groups','Microsoft.Graph.Users')
$ErrorActionPreference = "Stop"

$Groups = @(
    @{ YearGroup = "Year 12"; GroupId = "00000000-0000-0000-0000-000000000000" }
    @{ YearGroup = "Year 13"; GroupId = "00000000-0000-0000-0000-000000000000" }
)

if (-not (Get-Command Get-MgGroupMemberAsUser -ErrorAction SilentlyContinue)) {
    throw "Get-MgGroupMemberAsUser is not installed. Run: Install-Module Microsoft.Graph.Groups -Scope CurrentUser"
}

if (-not (Get-Command Get-MgUser -ErrorAction SilentlyContinue)) {
    throw "Get-MgUser is not installed. Run: Install-Module Microsoft.Graph.Users -Scope CurrentUser"
}

Connect-MgGraph -Scopes "GroupMember.Read.All", "User.Read.All" -NoWelcome

$Results = foreach ($Group in $Groups) {
    Write-Host "Reading $($Group.YearGroup) group members..."

    $Members = Get-MgGroupMemberAsUser `
        -GroupId $Group.GroupId `
        -All `
        -Property "id,displayName,userPrincipalName"

    foreach ($Member in $Members) {
        try {
            $User = Get-MgUser `
                -UserId $Member.Id `
                -Property "id,displayName,userPrincipalName,createdDateTime,accountEnabled" `
                -ErrorAction Stop

            $CreatedDate = $User.CreatedDateTime

            [PSCustomObject]@{
                YearGroup          = $Group.YearGroup
                DisplayName        = $User.DisplayName
                UserName           = $User.UserPrincipalName
                CreatedDateTimeUtc = if ($null -ne $CreatedDate) {
                    ([datetimeoffset]$CreatedDate).UtcDateTime.ToString("yyyy-MM-dd HH:mm:ss")
                }
                else {
                    ""
                }
                AccountEnabled     = $User.AccountEnabled
                UserId             = $User.Id
                ReadResult         = "Success"
                Error              = ""
            }
        }
        catch {
            [PSCustomObject]@{
                YearGroup          = $Group.YearGroup
                DisplayName        = $Member.DisplayName
                UserName           = $Member.UserPrincipalName
                CreatedDateTimeUtc = ""
                AccountEnabled     = ""
                UserId             = $Member.Id
                ReadResult         = "Failed"
                Error              = $_.Exception.Message
            }
        }
    }
}

$Results = @(
    $Results |
        Sort-Object @{ Expression = {
            if ($_.CreatedDateTimeUtc) {
                [datetime]$_.CreatedDateTimeUtc
            }
            else {
                [datetime]::MinValue
            }
        }; Descending = $true }, YearGroup, DisplayName
)

$Results | Export-Csv -LiteralPath $OutputPath -NoTypeInformation -Encoding UTF8

$WithDate = @($Results | Where-Object { $_.CreatedDateTimeUtc }).Count
$WithoutDate = $Results.Count - $WithDate
$Failed = @($Results | Where-Object { $_.ReadResult -eq "Failed" }).Count

Write-Host ""
Write-Host "Exported $($Results.Count) accounts."
Write-Host "With creation date: $WithDate"
Write-Host "Without creation date: $WithoutDate"
Write-Host "Failed reads: $Failed"
Write-Host "Saved to: $((Resolve-Path -LiteralPath $OutputPath).Path)"

Write-Host ""
Write-Host "Newest 20 accounts:"
$Results |
    Where-Object { $_.CreatedDateTimeUtc } |
    Select-Object -First 20 YearGroup, DisplayName, UserName, CreatedDateTimeUtc |
    Format-Table -AutoSize
