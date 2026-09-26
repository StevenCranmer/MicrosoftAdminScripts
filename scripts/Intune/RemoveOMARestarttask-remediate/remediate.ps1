# Example: .\remediate.ps1
# Variables: No user-supplied variables; this runs in the current account or device context.
#
unregister-scheduledtask -taskname "RebootCSP daily recurrent reboot" -confirm:$false
