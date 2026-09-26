# Example: .\remediation.ps1
# Variables: No user-supplied variables; this runs in the current account or device context.
#
takeown /F "C:\Windows\ServiceProfiles\LocalService\AppData\Local\Microsoft\Ngc" /R /D Y
remove-item -recurse -force "C:\Windows\ServiceProfiles\LocalService\AppData\Local\Microsoft\Ngc"