# Example: .\ExportUserDetailsAAD.ps1
# Variables: Set $OutputPath to the location for the user report CSV. The export contains personal data.
#
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
