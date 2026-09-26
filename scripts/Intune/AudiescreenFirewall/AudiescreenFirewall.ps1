# Example: .\AudiescreenFirewall.ps1
# Variables: No user-supplied variables; this runs in the current account or device context.
#
New-NetFirewallRule -DisplayName "Allow AudieScreen" -Direction Inbound -Program "C:\Program Files\audiescreen\audiescreen.exe" -Action Allow
New-NetFirewallRule -DisplayName "Allow AudieScreen" -Direction Outbound -Program "C:\Program Files\audiescreen\audiescreen.exe" -Action Allow
