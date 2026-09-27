# Example: .\remediate-fastboot.ps1
# Variables: No user-supplied variables; this runs in the current account or device context.
# Purpose: Disable Windows Fast Startup.
# Requires: Administrative rights to write the HKLM power setting.
# Effect: Sets HiberbootEnabled to 0.
#
New-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name 'HiberbootEnabled' -Value 0 -PropertyType DWord -Force -ea SilentlyContinue;