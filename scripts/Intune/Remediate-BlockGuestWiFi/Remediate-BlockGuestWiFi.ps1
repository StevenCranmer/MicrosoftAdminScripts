# Example: .\Remediate-BlockGuestWiFi.ps1
# Variables: Set $ssid to the SSID to block and remove; Example-Guest is a dummy.
#
# Block and remove Example-Guest
$ssid = "Example-Guest"

# 1) Add block filter (hides/removes from Available networks and prevents connection)
netsh wlan add filter permission=block ssid="$ssid" networktype=infrastructure | Out-Null

# 2) If currently connected to Example-Guest, disconnect
$interface = (netsh wlan show interfaces) 2>$null
if ($interface -match "SSID\s*:\s*$ssid") {
    netsh wlan disconnect | Out-Null
}

# 3) Remove any saved profile for Example-Guest (works across interfaces)
# Loop profiles and remove those matching the SSID exactly
$profilesRaw = (netsh wlan show profiles) 2>$null
$profiles = ($profilesRaw | Select-String -Pattern 'All User Profile\s*:\s*(.+)$') |
    ForEach-Object { $_.Matches[0].Groups[1].Value.Trim() }

foreach ($p in $profiles) {
    if ($p -eq $ssid) {
        netsh wlan delete profile name="$p" | Out-Null
    }
}

# Optional: Verify filter is present
netsh wlan show filters | Out-String | Write-Output
