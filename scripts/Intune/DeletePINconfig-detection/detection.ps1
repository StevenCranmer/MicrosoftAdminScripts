# Example: .\detection.ps1
# Variables: No user-supplied variables; this runs in the current account or device context.
# Purpose: Detect the Windows Hello PIN configuration folder.
# Requires: Run in device context with access to the LocalService Ngc path.
# Effect: Exit 1 when the folder exists; exit 0 when absent or when detection errors.
#
# Set Variables
$Paths = @("C:\Windows\ServiceProfiles\LocalService\AppData\Local\Microsoft\Ngc")

# Check if paths exist, if so trigger remediation.
Try {
    ForEach ($Path in $Paths) {
        $PathTest = Test-Path $Path
        If (!($PathTest)){
            Write-host "$Path Not Found"
            Exit 0
        }
    }
    Write-host "All Paths Found"
    Exit 1
}
Catch {
    $ErrorMsg = $_.Exception.Message
    Write-host "Error $ErrorMsg"
    Exit 0
}