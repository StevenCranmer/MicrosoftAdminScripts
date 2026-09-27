# Example: .\SecurityKeyLoginDefaultRemediationImproved.ps1
# Variables: No user-supplied variables; this runs in the current account or device context.
# Purpose: Disable the specified credential provider through the registry.
# Requires: Administrative rights to write the HKLM credential-provider key.
# Effect: Sets Disabled to 1; confirm this is the desired sign-in change before deployment.
#
New-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\Credential Providers\{F8A1793B-7873-4046-B2A7-1F318747F427}" -Name "Disabled" -Value 1 -PropertyType DWord -Force -ea SilentlyContinue;
