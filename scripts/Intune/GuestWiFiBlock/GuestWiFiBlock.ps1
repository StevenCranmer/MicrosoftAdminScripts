# Example: .\GuestWiFiBlock.ps1
# Variables: Replace Example-Guest with the SSID to block.
# Purpose: Add a WLAN block filter for the configured guest SSID.
# Requires: Windows wireless service; replace Example-Guest with your SSID.
# Effect: Adds a network block filter but does not delete saved profiles.
#
netsh wlan add filter permission=block ssid="Example-Guest" networktype=infrastructure

