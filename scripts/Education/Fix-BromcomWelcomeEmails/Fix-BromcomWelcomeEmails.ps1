# Example: .\Fix-BromcomWelcomeEmails.ps1
# Variables: Set $patternAddress to the unique address fragment to match; the sample fragment is a dummy.
#
<#
Bulk-disable the Microsoft 365 Group welcome email for any group where the
primary SMTP or any proxy address contains the exact substring "<ADDRESS_FRAGMENT>".

Examples matched:
  person1@example.com
  person2@example.com
  person3@example.com
  person4@example.com
#>

# --- 1) Connect to Exchange Online ---
try {
    if (-not (Get-Module ExchangeOnlineManagement -ListAvailable)) {
        Install-Module ExchangeOnlineManagement -Scope AllUsers -Force
    }
    Connect-ExchangeOnline
}
catch {
    Write-Error "Failed to connect to Exchange Online: $($_.Exception.Message)"
    break
}

# --- 2) Strict pattern for addresses only ---
$patternAddress = '<ADDRESS_FRAGMENT>'   # strict substring; no alias fallback

# --- 3) (Optional) detect alt parameter name in rare tenants ---
$suParams = (Get-Command Set-UnifiedGroup).Parameters.Keys
$useUnifiedParam = $suParams -contains 'UnifiedGroupWelcomeMessageEnabled'
$useSimpleParam  = $suParams -contains 'WelcomeMessageEnabled'

if (-not ($useUnifiedParam -or $useSimpleParam)) {
    throw "Neither UnifiedGroupWelcomeMessageEnabled nor WelcomeMessageEnabled is available on Set-UnifiedGroup."
}

# --- 4) Find candidates (Welcome ON + strict address match) ---
$all = Get-UnifiedGroup -ResultSize Unlimited

$target = $all | Where-Object {
    $_.WelcomeMessageEnabled -eq $true -and (
        $_.PrimarySmtpAddress.ToString().ToLower().Contains($patternAddress) -or
        ($_.EmailAddresses | ForEach-Object { $_.ToString().ToLower() }) -match [regex]::Escape($patternAddress)
    )
}

# --- 5) PREVIEW ---
$target |
  Select-Object DisplayName, PrimarySmtpAddress, WelcomeMessageEnabled |
  Sort-Object DisplayName | Format-Table -AutoSize

Write-Host "`nPreview: $($target.Count) group(s) would be updated." -ForegroundColor Cyan

# --- 6) APPLY (Uncomment to execute) ---
$log = @()
foreach ($g in $target) {
    Write-Host ("Disabling welcome email for: {0} ({1})" -f $g.DisplayName, $g.PrimarySmtpAddress) -ForegroundColor Yellow
    try {
        if ($useUnifiedParam) {
            Set-UnifiedGroup -Identity $g.Identity -UnifiedGroupWelcomeMessageEnabled:$false -ErrorAction Stop
        } elseif ($useSimpleParam) {
            Set-UnifiedGroup -Identity $g.Identity -WelcomeMessageEnabled:$false -ErrorAction Stop
        }
        $log += Get-UnifiedGroup -Identity $g.Identity | Select-Object DisplayName, PrimarySmtpAddress, WelcomeMessageEnabled
    }
    catch {
        Write-Warning ("Failed on {0}: {1}" -f $g.PrimarySmtpAddress, $_.Exception.Message)
        $log += [pscustomobject]@{
            DisplayName           = $g.DisplayName
            PrimarySmtpAddress    = $g.PrimarySmtpAddress
            WelcomeMessageEnabled = 'ERROR'
        }
    }
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$log | Sort-Object DisplayName | Export-Csv ".\Example-Groups-WelcomeDisabled-$timestamp.csv" -NoTypeInformation
Write-Host "Completed. Report saved to Example-Groups-WelcomeDisabled-$timestamp.csv" -ForegroundColor Green
#>

# Disconnect-ExchangeOnline
