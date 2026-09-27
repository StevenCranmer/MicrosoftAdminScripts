# Example: .\remediation.ps1
# Variables: No user-supplied variables; this runs in the current account or device context.
# Purpose: Remove the Windows Hello PIN configuration folder.
# Requires: Administrative or SYSTEM context; use with the matching detection script.
# Effect: Takes ownership and deletes the Ngc folder, affecting enrolled PINs.
#
takeown /F "C:\Windows\ServiceProfiles\LocalService\AppData\Local\Microsoft\Ngc" /R /D Y
remove-item -recurse -force "C:\Windows\ServiceProfiles\LocalService\AppData\Local\Microsoft\Ngc"