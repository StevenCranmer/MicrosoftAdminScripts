# Example: .\Win11Req.ps1
# Variables: No user-supplied variables; this runs in the current account or device context.
# Purpose: Set the Windows 11 unsupported TPM/CPU upgrade registry value.
# Requires: Administrative rights to write HKLM\SYSTEM\Setup\MoSetup.
# Effect: Changes upgrade eligibility policy; it does not check hardware compatibility.
#
reg add HKLM\SYSTEM\Setup\MoSetup /f /v AllowUpgradesWithUnsupportedTPMorCPU /d 1 /t reg_dword