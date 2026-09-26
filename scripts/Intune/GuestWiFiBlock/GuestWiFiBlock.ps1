# Example: .\GuestWiFiBlock.ps1
# Variables: Replace Example-Guest with the SSID to block.
#
netsh wlan add filter permission=block ssid="Example-Guest" networktype=infrastructure

