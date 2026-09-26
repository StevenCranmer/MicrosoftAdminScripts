# Example: .\UserImport.ps1
# Variables: Copy ad-users.example.csv to userImport.csv beside this script, then replace every dummy value. OU and Maildomain determine the target account.
#
$CsvPath = Join-Path $PSScriptRoot 'userImport.csv'
$Users = Import-Csv -Path $CsvPath            
foreach ($User in $Users)            
{            
    $Displayname = $User.'Displayname'           
    $UserFirstname = $User.'Firstname'            
    $UserLastname = $User.'Lastname'            
    $OU = $User.'OU'            
    $SAM = $User.'SAM'            
    $UPN = $User.'SAM' + "@" + $User.'Maildomain'            
    $Description = $User.'Description'            
    $Password = $User.'Password'            
    New-ADUser -Name "$Displayname" -DisplayName "$Displayname" -SamAccountName $SAM -UserPrincipalName $UPN -GivenName "$UserFirstname" -Surname "$UserLastname" -Description "$Description" -AccountPassword (ConvertTo-SecureString $Password -AsPlainText -Force) -Enabled $true -Path "$OU" -ChangePasswordAtLogon $false –PasswordNeverExpires $true            
}
 