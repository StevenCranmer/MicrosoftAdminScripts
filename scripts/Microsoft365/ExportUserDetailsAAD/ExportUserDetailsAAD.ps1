# Example: .\ExportUserDetailsAAD.ps1
# Variables: Set $OutputPath to the location for the user report CSV. The export contains personal data.
# Purpose: Export selected Azure AD user properties to CSV.
# Requires: AzureAD PowerShell module and an authenticated Azure AD session.
# Effect: Writes Microsoft365Users.csv beside the script; the report contains personal data.
#
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
Assert-RequiredModules -Names @('AzureAD')
Write-Host "Azure AD sign-in is required; a sign-in prompt will open."
Connect-AzureAD -ErrorAction Stop | Out-Null
$OutputPath = Join-Path $PSScriptRoot 'Microsoft365Users.csv'
$Result = @()
 
# Get all Azure AD Users with all properties
#$AllUsers = Get-AzureADUser -All $true
 
# Get all Azure AD Users with required properties
$AllUsers = Get-AzureADUser -All $true | Select DisplayName,UserPrincipalName,Mail,ProxyAddresses,JobTitle,physicalDeliveryOfficeName,Department,ObjectId
 
ForEach ($User in $AllUsers)
{
# Add user detail to $Result array one by one
$Result += New-Object PSObject -property $([ordered]@{
UserName = $User.DisplayName
UserPrincipalName = $User.UserPrincipalName
PrimarySmtpAddress = $User.Mail
AliasSmtpAddresses = ($User.ProxyAddresses | Where-Object {$_ -clike 'smtp:*'} | ForEach-Object {$_ -replace 'smtp:',''}) -join ','
UserId= $User.ObjectId
})
}
# Export M365 Users report to CSV file
$Result | Export-CSV $OutputPath -NoTypeInformation -Encoding UTF8
