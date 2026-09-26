# Example: .\Reset-CloudUserPasswordsFromCsv.ps1 -CsvPath .\password-resets.example.csv
# Variables: -CsvPath needs UserName and UserPassword columns. Replace every dummy value; protect and delete real password files after use.
#
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string]$CsvPath
)

$ErrorActionPreference = "Stop"

# Resolve and validate the input file.
try {
    $CsvPath = (Resolve-Path -LiteralPath $CsvPath).Path
}
catch {
    throw "CSV file not found: $CsvPath"
}

if ([System.IO.Path]::GetExtension($CsvPath) -ne ".csv") {
    throw "The supplied file must be a .csv file."
}

# Confirm the required Microsoft Graph command is available.
if (-not (Get-Command Update-MgUser -ErrorAction SilentlyContinue)) {
    throw "Update-MgUser is not installed. Run: Install-Module Microsoft.Graph.Users -Scope CurrentUser"
}

$Users = @(Import-Csv -LiteralPath $CsvPath)

if ($Users.Count -eq 0) {
    throw "The CSV contains no user records."
}

$Headers = @($Users[0].PSObject.Properties.Name)
$MissingHeaders = @("UserName", "UserPassword") | Where-Object { $_ -notin $Headers }

if ($MissingHeaders) {
    throw "Missing required CSV column(s): $($MissingHeaders -join ', '). Required columns are UserName and UserPassword."
}

$BlankRows = @($Users | Where-Object {
    [string]::IsNullOrWhiteSpace($_.UserName) -or
    [string]::IsNullOrWhiteSpace($_.UserPassword)
})

if ($BlankRows.Count -gt 0) {
    throw "The CSV contains $($BlankRows.Count) row(s) with a blank UserName or UserPassword. No passwords were changed."
}

Write-Host "CSV: $CsvPath"
Write-Host "Users to process: $($Users.Count)"
Write-Host "Connecting to Microsoft Graph..."

Connect-MgGraph -Scopes "User.ReadWrite.All" -NoWelcome

$Results = foreach ($User in $Users) {
    $UserName = $User.UserName.Trim()

    try {
        Update-MgUser `
            -UserId $UserName `
            -PasswordProfile @{
                Password                      = $User.UserPassword
                ForceChangePasswordNextSignIn = $true
            } `
            -ErrorAction Stop

        Write-Host "SUCCESS  $UserName" -ForegroundColor Green

        [PSCustomObject]@{
            UserName = $UserName
            Result   = "Success"
            Error    = ""
        }
    }
    catch {
        Write-Host "FAILED   $UserName - $($_.Exception.Message)" -ForegroundColor Red

        [PSCustomObject]@{
            UserName = $UserName
            Result   = "Failed"
            Error    = $_.Exception.Message
        }
    }
}

$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$InputDirectory = Split-Path -Parent $CsvPath
$InputName = [System.IO.Path]::GetFileNameWithoutExtension($CsvPath)
$ResultsPath = Join-Path $InputDirectory "$InputName-reset-results-$Timestamp.csv"

$Results | Export-Csv -LiteralPath $ResultsPath -NoTypeInformation -Encoding UTF8

$Succeeded = @($Results | Where-Object Result -eq "Success").Count
$Failed = @($Results | Where-Object Result -eq "Failed").Count

Write-Host ""
Write-Host "Complete. Success: $Succeeded  Failed: $Failed"
Write-Host "Results: $ResultsPath"

if ($Failed -gt 0) {
    exit 1
}
