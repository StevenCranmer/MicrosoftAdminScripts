# Example: .\SecurityKeyLoginDefaultRemediationImproved.ps1
# Variables: No user-supplied variables; this runs in the current account or device context.
#
New-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\Credential Providers\{F8A1793B-7873-4046-B2A7-1F318747F427}" -Name "Disabled" -Value 1 -PropertyType DWord -Force -ea SilentlyContinue;
