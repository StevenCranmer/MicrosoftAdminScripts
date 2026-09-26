# Example: .\Win11Req.ps1
# Variables: No user-supplied variables; this runs in the current account or device context.
#
reg add HKLM\SYSTEM\Setup\MoSetup /f /v AllowUpgradesWithUnsupportedTPMorCPU /d 1 /t reg_dword