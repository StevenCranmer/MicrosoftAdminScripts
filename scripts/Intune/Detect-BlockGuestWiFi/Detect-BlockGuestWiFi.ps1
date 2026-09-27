# Example: .\Detect-BlockGuestWiFi.ps1
# Variables: Set $ssid to the SSID to check; Example-Guest is a dummy.
# Purpose: Check whether a guest SSID is blocked and its saved profile removed.
# Requires: Windows wireless interface; replace the example SSID before deployment.
# Effect: Read-only: exit 0 when blocked with no saved profile, 1 otherwise.
#
# Detect if Example-Guest is blocked and if any profile exists
$ssid = "Example-Guest"

# Is SSID on block filter?
$filters = (netsh wlan show filters) 2>$null
$blocked = $filters -match ("SSID\s*:\s*""?$ssid""?\s*,\s*Type\s*:\s*Infrastructure")

# Is there any saved profile for this SSID?
$profilesRaw = (netsh wlan show profiles) 2>$null
$profiles = ($profilesRaw | Select-String -Pattern 'All User Profile\s*:\s*(.+)$') |
    ForEach-Object { $_.Matches[0].Groups[1].Value.Trim() }
$hasProfile = $profiles -contains $ssid

# Exit codes: 0 = compliant; 1 = needs remediation
if ($blocked -and -not $hasProfile) { exit 0 } else { exit 1 }
