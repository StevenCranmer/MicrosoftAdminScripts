# Example: .\AudiescreenFirewall.ps1
# Variables: No user-supplied variables; this runs in the current account or device context.
# Purpose: Allow the configured AudieScreen executable through Windows Firewall.
# Requires: Windows Firewall cmdlets and administrative rights; verify the program path.
# Effect: Adds inbound and outbound allow rules for that executable.
#
if (-not (Get-Command New-NetFirewallRule -ErrorAction SilentlyContinue)) { throw 'Windows NetSecurity firewall cmdlets are unavailable on this device.' }
if (-not (Test-Path 'C:\Program Files\audiescreen\audiescreen.exe')) { throw 'AudieScreen executable not found at its configured path. Check where it is installed.' }

New-NetFirewallRule -DisplayName "Allow AudieScreen" -Direction Inbound -Program "C:\Program Files\audiescreen\audiescreen.exe" -Action Allow
New-NetFirewallRule -DisplayName "Allow AudieScreen" -Direction Outbound -Program "C:\Program Files\audiescreen\audiescreen.exe" -Action Allow
