# Example: .\UserImport.ps1
# Variables: Copy ad-users.example.csv to userImport.csv beside this script, then replace every dummy value. OU and Maildomain determine the target account.
# Purpose: Create AD user accounts from a CSV.
# Requires: ActiveDirectory PowerShell module, rights to create users, and a filled userImport.csv beside the script.
# Effect: Creates enabled accounts using CSV passwords; protect the input file and review OU values.
#
# Windows administration tools are installed as OS features, not from PSGallery.
if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
    $answer = Read-Host "ActiveDirectory tools are missing. Install the Windows administration tools now? [y/N]"
    if ($answer -notmatch '^(?i:y|yes)$') {
        throw "ActiveDirectory tools are required. Install them through Windows optional features or Server Manager, then rerun."
    }
    $isAdministrator = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdministrator) {
        throw 'Installing Windows administration tools requires an elevated PowerShell session. Reopen PowerShell as administrator and rerun.'
    }
    $isServer = (Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).ProductType -ne 1
    if ($isServer) {
        if (-not (Get-Command Install-WindowsFeature -ErrorAction SilentlyContinue)) { throw 'Install-WindowsFeature is unavailable. Install the tools through Server Manager.' }
        $result = Install-WindowsFeature -Name 'RSAT-AD-PowerShell' -ErrorAction Stop
        if (-not $result.Success) { throw 'Windows reported that the feature installation did not succeed.' }
    } else {
        if (-not (Get-Command Add-WindowsCapability -ErrorAction SilentlyContinue)) { throw 'Add-WindowsCapability is unavailable. Install the tools through Windows optional features.' }
        $result = Add-WindowsCapability -Online -Name 'Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0' -ErrorAction Stop
        if ($result.RestartNeeded) { throw 'The tools need a restart before they can be used. Restart Windows, then rerun.' }
    }
}
Import-Module ActiveDirectory -ErrorAction Stop

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
 