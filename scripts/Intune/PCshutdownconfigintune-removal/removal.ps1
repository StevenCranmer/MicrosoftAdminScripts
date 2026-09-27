# Example: .\removal.ps1
# Variables: No user-supplied variables; this runs in the current account or device context.
# Purpose: Remove the ShutdownPCat6PM scheduled task.
# Requires: Windows ScheduledTasks cmdlets and permission to unregister system tasks.
# Effect: Unregisters that task without a confirmation prompt.
#
unregister-scheduledtask -taskname ShutdownPCat6PM -confirm:$false
