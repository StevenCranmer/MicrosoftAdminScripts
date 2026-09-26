# Example: .\Update-PasswordsCSV.ps1
# Variables: Copy password-resets.example.csv to password-resets.csv beside this script and replace every dummy value.
#
Connect-AzureAD
Connect-AzAccount
Connect-MgGraph -Scopes "User.ReadWrite.All", "Directory.AccessAsUser.All"

$CsvPath = Join-Path $PSScriptRoot 'password-resets.csv'
Import-Csv -LiteralPath $CsvPath | ForEach-Object {
    $userId = $_.UserName
    $newPassword = $_.UserPassword

    Update-MgUser -UserId $userId -PasswordProfile @{
        Password = $newPassword
        ForceChangePasswordNextSignIn = $true
    }
}
