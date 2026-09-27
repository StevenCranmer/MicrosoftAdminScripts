# Example: .\Update-PasswordsCSV.ps1
# Variables: Copy password-resets.example.csv to password-resets.csv beside this script and replace every dummy value.
# Purpose: Set user passwords from password-resets.csv beside the script.
# Requires: Microsoft.Graph.Authentication and Microsoft.Graph.Users; copy and fill the example CSV.
# Effect: Changes passwords and forces a change at next sign-in; protect the input CSV.
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
Assert-RequiredModules -Names @('Microsoft.Graph.Authentication','Microsoft.Graph.Users')
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
