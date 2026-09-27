# Example: .\Configure_WindowsScanning.ps1 -accountNames 'EXAMPLE\ScanUsers'
# Variables: Replace example parameter values with your own. Run Get-Help for parameter details where available.
# Purpose: Grant a named account Windows scanning permissions for Lansweeper.
# Requires: Run elevated; supply -accountNames and optionally set logging parameters.
# Effect: Changes WMI, registry, and related access settings; test on a nonproduction device.
#
<#
.SYNOPSIS
    Grant the specified accounts permissions used by Lansweeper Windows scanning.
.DESCRIPTION
    Changes local scanning-related permissions. Run elevated and test on a nonproduction device first.
.PARAMETER accountNames
    One or more account or group names, separated by commas.
.PARAMETER logFile
    Log destination; defaults to C:\Windows\Temp\LansweeperScanningSetupLog.txt.
.PARAMETER logLevel
    0 = none, 1 = basic (default), 2 = verbose.
.PARAMETER noEventLog
    Do not write to the Windows Application event log.
.EXAMPLE
    .\Configure_WindowsScanning.ps1 -accountNames 'EXAMPLE\ScanUsers'
.EXAMPLE
    .\Configure_WindowsScanning.ps1 -accountNames 'EXAMPLE\ScanUsers,EXAMPLE\BackupScanUsers' -logLevel 2 -noEventLog
#>
param (
    [Parameter(Position = 0, Mandatory = $True)]
    [string]$accountNames,
    [string]$logFile = "C:\Windows\Temp\LansweeperScanningSetupLog.txt",
    [ValidateSet(0, 1, 2)]
    [int16]$logLevel = 1,
    [switch]$noEventLog
)

# Script configuration

# WMI permissions needed for scanning
$global:wmiPermissions = 'Enable', 'MethodExecute', 'ReadSecurity', 'RemoteAccess'

# WMI classes on which permissions are applied
$global:wmiNamespaces = 
'Root\CIMV2', 
'Root\DEFAULT', 
'Root\CIMV2\Security\MicrosoftTpm', 
'Root\WMI', 
'Root\CIMV2\Security\MicrosoftVolumeEncryption', 
'Root\securitycenter',
'Root\SecurityCenter2', 
'Root\MSCluster', 
'Root\Microsoft\sqlserver', #the script will enumerate through all sub classes (per sql version)
'Root\MSCluster', 
'Root\ccm',
'Root\ccm\ClientSDK',
'Root\SMS', #the script will enumerate through all sub classes (per ccm site)
'Root\virtualization',
'Root\virtualization\v2'

# appIds on which launch permissions are needed for scanning
$global:appIds = @(
    '{752073A2-23F2-4396-85F0-8FDB879ED0ED}' #Trusted installer 
) 

### Functions ###
# Function that initializes logging to a logfile
function Set-LogFile {
    try {
        If (Test-Path -Path $logFile) {
            Remove-Item -Path $logFile -ErrorAction 'Stop' -Force | Out-Null
        }

        New-Item $logFile -Type 'File' -ErrorAction 'Stop' | Out-Null
    }
    catch {
        Write-Error 'Something went wrong whilst creating the log file.'
        throw $_
    }

    Write-Log -Data "Logging to logfile `"$logFile`" started." -Type 'Basic'
}

# Function that handles logging
function Write-Log {
    param (
        [string]$data,
        [Parameter(Mandatory = $True)]
        [ValidateSet('Basic', 'Verbose')]
        [string]$type,
        [int16]$eventID,
        [string]$eventType = 'Information'
    )

    # Parse parameters
    if ($script:eventLog -and $eventID) {
        $writeToEventLog = $true
    }

    # Basic logging
    if ($logLevel -eq 1 -and $type -eq 'Basic') {
        Write-Host $data
        Add-Content -Path $logFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [BASIC] $data"

        if ($eventType -eq 'Error') {
            $data = "$data`nSee `"$logFile`" for more information."
        }

        if ($writeToEventLog) {
            Write-EventLog -LogName $script:eventLog -Source $script:eventSource -eventID $eventID -Message $data -EntryType $eventType -Category 0
        }

        return
    }

    # Verbose logging
    if ($logLevel -eq 2) {
        if ($type -eq 'Basic') {
            Write-Host $data
            Add-Content -Path $logFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [BASIC] $data"

            if ($eventType -eq 'Error') {
                $data = "$data`nSee `"$logFile`" for more information."
            }
        
            if ($writeToEventLog) {
                Write-EventLog -LogName $script:eventLog -Source $script:eventSource -eventID $eventID -Message $data -EntryType $eventType -Category 0
            }

            return
        }
        if ($type -eq 'Verbose') {
            Write-Host $data
            Add-Content -Path $logFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [VERBOSE] $data"

            if ($eventType -eq 'Error') {
                $data = "$data`nSee `"$logFile`" for more information."
            }
            
            if ($writeToEventLog) {
                Write-EventLog -LogName $script:eventLog -Source $script:eventSource -eventID $eventID -Message $data -EntryType $eventType -Category 0
            }

            return
        }
    }
}

# Function that initializes logging to event log
function Set-EventLog {
    $script:eventLog = 'Application'
    $script:eventSource = 'Lansweeper Scanning Setup'

    # Create the event log source if it doesn't exist yet
    $sourceExistsInEventLog = [System.Diagnostics.EventLog]::LogNameFromSourceName($script:eventSource, $env:COMPUTERNAME)

    if (-not $sourceExistsInEventLog) {
        Write-Log -Data "Creating event log source `"$script:eventSource`" in event log `"$script:eventLog`"..." -Type 'Basic'
        try {
            New-EventLog -LogName $script:eventLog -Source $script:eventSource -ErrorAction 'Stop'
        }
        catch {
            Write-Log -Data "An error occurred whilst creating the event log source `"$script:eventSource`" in event log `"$script:eventLog`". Skipping event logging for this run." -Type 'Basic'
            $script:eventLog = $null
            $script:eventSource = $null
        }
    }
    # Recreate the event log source if it exists in another event log (reboot required!)
    elseif ($sourceExistsInEventLog -ne $script:eventLog) {
        try {
            Write-Log -Data "The event log source `"$script:eventSource`" already exists in event log `"$sourceExistsInEventLog`". Removing this source..." -Type 'Verbose'
            Remove-EventLog -Source $script:eventSource -ErrorAction 'Stop'

            Write-Log -Data "Creating event log source `"$script:eventSource`" in event log `"$script:eventLog`"..." -Type 'Verbose'
            New-EventLog -LogName $script:eventLog -Source $script:eventSource -ErrorAction 'Stop'
            Write-Log -Data "Because the event log source changed from event log location `"$sourceExistsInEventLog`" to `"$script:eventLog`", a reboot is required to see logs in event viewer. Skipping event logging for this run." -Type 'Basic'
        }
        catch {
            Write-Log -Data "An error occurred whilst recreating the event log source in `"$script:eventSource`". Error:`n$_" -Type 'Basic'
        }

        $script:eventLog = $null
        $script:eventSource = $null
    }

    if ($script:eventLog) {
        Write-Log -Data "Logging to event log `"$script:eventLog`" started." -Type 'Basic'
    }
}

# Function that reformats an account name to SAMAccountName
function Format-AccountName {
    param (
        [Parameter(Mandatory = $True)]
        [String]$accountName
    )

    Write-Log -Data "Parsing account `"$accountName`"" -Type 'Verbose'
    # Parse SAMAccountName format
    if ($accountName.Contains('\')) {
        $splittedAccountName = $accountName.Split('\')
        $domain = $splittedAccountName[0]
        if (($domain -eq '.') -or ($domain -eq 'BUILTIN')) {
            $domain = $env:COMPUTERNAME
        }

        $formattedAccountName = "$domain\$($splittedAccountName[1])"
        Write-Log -Data "Reformatted account name to `"$formattedAccountName`"" -Type 'Basic'
        return $formattedAccountName
    }

    # Parse local user format
    $formattedAccountName = "$($env:COMPUTERNAME)\$accountName"
    Write-Log -Data "Reformatted account name to `"$formattedAccountName`"" -Type 'Basic'
    return $formattedAccountName
}

# Function that retrieves the SID corresponding to the given account
function Get-AccountSID {
    param (
        [Parameter(Mandatory = $True)]
        [String]$accountName
    )

    $accountObject = New-Object System.Security.Principal.NTAccount($accountName) 

    try {
        $sid = $accountObject.Translate([System.Security.Principal.SecurityIdentifier])
    }
    catch {
        Write-Log -Data "The SID for account/group `"$accountName`" could not be found. Most likely the account/group does not exist." -Type 'Basic' -EventType 'Error' -EventID 41
        exit 4
    }

    Write-Log -Data "Retrieved SID `"$($sid.Value)`" for object `"$accountName`"." -Type 'Basic'
    return $sid.Value
}

# Function that adds an object to an Active Directory group
function Add-ObjectToADGroup {
    param (
        [parameter(Mandatory = $true, Position = 0)]
        [string]$objectName,
        [parameter(Mandatory = $true, Position = 1)]
        [string]$groupName
    )
    
    # Get the AD group members
    try {
        $adGroupMembers = (Get-ADGroupMember -Identity $groupName | Where-Object { $_.Name -eq $objectName })
    }
    catch {
        Write-Log -Data "Get-ADGroupMember failed on group `"$groupName`". This happens if the group contains users of a one-way incoming trust. You should manually add `"$objectName`" to the `"$groupName`" Active Directory group if this isn't done already. Skipping this group membership check..." -Type 'Basic' -eventType 'Warning' -eventID 2
        return
    }

    if (-not $adGroupMembers) {
        Write-Log -Data "Adding `"$objectName`" to the `"$groupName`" Active Directory group..." -Type 'Basic' -eventType 'Information' -eventID 3
        try {
            Add-ADGroupMember -Identity $groupName -Members $objectName
        }
        catch {
            Write-Log -Data "An error occured whilst adding `"$objectName`" to Active Directory group `"$groupName`". If `"$objectName`" exists in another domain, you'll need to do this manually. Error message:`n$_" -Type 'Basic' -eventType 'Error' -eventID 4
        }
    }
    else {
        Write-Log -Data "`"$objectName`" was already in the `"$groupName`" group, skipping." -Type 'Basic' -eventType 'Information' -eventID 5
    }
}

# Function that adds an object to a local group
function Add-ObjectToLocalGroup {
    param (
        [parameter(Mandatory = $true, Position = 0)]
        [string]$objectName,
        [parameter(Mandatory = $true, Position = 1)]
        [string]$groupName
    )

    # Add the object if it isn't already in the group
    if (-not (Get-LocalGroupMember -Group $groupName | Where-Object { $_.Name -eq $objectName })) {
        Write-Log -Data "Adding `"$objectName`" to the `"$groupName`" group..." -Type 'Basic' -eventType 'Information' -eventID 6
        try {
            Add-LocalGroupMember -Group $groupName -Member $objectName
        }
        catch {
            Write-Log -Data "An error occured whilst adding `"$objectName`" to local group `"$groupName`". Error message:`n$_" -Type 'Basic' -eventType 'Information' -eventID 7
        }
    }
    else {
        Write-Log -Data "`"$objectName`" was already in the `"$groupName`" group, skipping." -Type 'Basic' -eventType 'Information' -eventID 8
    }
}

# Function that maps the WMI permissions input to the corresponding AccessMask integer code 
function Get-AccessMaskFromWMIPermissions {
    param (
        [parameter(Mandatory = $true, Position = 0)]
        [String[]]$permissions
    )

    Write-Log -Data 'Determining requested WMI access mask...' -Type 'Verbose'
    $accessMask = 0
    foreach ($permission in $permissions) {
        Write-Log -Data "Parsing WMI permission `"$permission`"..." -Type 'Verbose'
        switch ($permission) {
            'Enable' { $accessMask += 1 }
            'MethodExecute' { $accessMask += 2 }
            'FullWrite' { $accessMask += 4 }
            'PartialWrite' { $accessMask += 8 }
            'ProviderWrite' { $accessMask += 0x10 }
            'RemoteAccess' { $accessMask += 0x20 }
            'ReadSecurity' { $accessMask += 0x20000 }
            'WriteSecurity' { $accessMask += 0x40000 }
            default { Write-Log -Data "Unknown WMI permission: `"$permission`"`n, skipping." -Type 'Basic' -eventType 'Warning' -eventID 9 }
        }

        Write-Log -Data "New WMI access mask value: $accessMask" -Type 'Verbose'
    }

    Write-Log -Data "Final WMI access mask value: $accessMask" -Type 'Verbose'
    return $accessMask
}

# Function that checks if a WMI namespace exists
function Find-WMINamespace {
    param (
        [parameter(Mandatory = $true, Position = 0)]
        [String]$namespace,
        [parameter(Position = 1)]
        [Int16]$index = 0
    )

    $splitNamespace = $namespace.Split('\')

    # Check index 0 (must be "root")
    if ($index -eq 0 -and $splitNamespace[0] -ne 'root') {
        Write-Log -Data "The path of a WMI namespace must always begin with `"root\`". Entered path: `"$namespace`"" -Type 'Basic' -eventType 'Error' -eventID 10
        return $false
    }
    # Check intermediate indices
    elseif (($index -ne 0) `
            -and ($index -lt $splitNamespace.Length) `
            -and (-not (Get-WmiObject -Class '__Namespace' -Namespace ($splitNamespace[0..($index - 1)] -join '\') | Where-Object { $_.Name -eq $splitNamespace[$index] }))) {
        return $false # This is the case when the child namespace is not found in the list of namespaces on the parent
    }
    # $index > split namespace array means that the last child object is successfully found
    elseif ($index -ge $splitNamespace.Length) {
        return $true
    }

    return Find-WMINamespace -namespace $namespace -index (++$index)
}

# Function that adds permissions to a WMI namespace
function Add-WMIPermissions {
    param (
        [parameter(Mandatory = $true, Position = 0)]
        [string]$namespace,
        [parameter(Mandatory = $true, Position = 1)]
        [string]$accountName,
        [parameter(Mandatory = $true, Position = 2)]
        [System.Security.Principal.SecurityIdentifier]$accountSid,
        [parameter(Mandatory = $true, Position = 3)]
        [string[]]$permissions,
        [switch]$enableInherit,
        [switch]$deny
    )

    # Check if the requested namespace exists
    if (-not (Find-WMINamespace -namespace $namespace)) {
        Write-Log -Data "WMI Namespace `"$namespace`" not found. Skipping permissions change." -Type 'Basic' -eventType 'Information' -eventID 11
        return
    }

    # Get the security descriptor of the WMI namespace
    Write-Log -Data "Retrieving current security descriptor from WMI namespace `"$namespace`"..." -Type 'Verbose'
    try {
        $getSDOutput = Invoke-WmiMethod -Namespace $namespace -Path '__systemsecurity=@' -Name GetSecurityDescriptor -ErrorAction 'Stop'
    }
    catch {
        Write-Log -Data "An error occured whilst retrieving the WMI permissions on namespace `"$namespace`". Error message:`n$_" -Type 'Basic'
    }

    if ($getSDOutput.ReturnValue -ne 0) {
        Write-Log -Data "WMI Method `"GetSecurityDescriptor`" on namespace `"$namespace`" failed, return code: $($output.ReturnValue)" -Type 'Basic' -eventType 'Error' -eventID 12
        exit 2
    }

    # Put the security descriptor in a seperate object
    $sd = $getSDOutput.Descriptor
 
    # Check if the account already has permissions defined
    Write-Log -Data "Checking if `"$accountName`" already has the requested permissions on WMI namespace `"$namespace`"..." -Type 'Verbose'
    $requestedAccessMask = Get-AccessMaskFromWMIPermissions -permissions $permissions
    if ($sd.DACL | Where-Object { $_.Trustee.SidString -eq $accountSid -and $_.AccessMask -eq $requestedAccessMask }) {
        Write-Log -Data "`"$accountName`" already has the requested permissions on WMI namespace `"$namespace`", skipping." -Type 'Basic' -eventType 'Information' -eventID 13
        return
    }

    # Create the ACE
    Write-Log -Data "Creating the ACE for `"$accountName`"..." -Type 'Verbose'
    Write-Log -Data "Permissions that this ACE will contain: $permissions" -Type 'Verbose'
    $ace = (New-Object System.Management.ManagementClass('win32_Ace')).CreateInstance()
    $ace.AccessMask = $requestedAccessMask
    if ($enableInherit) {
        $ace.AceFlags = 0x2
    }
    else {
        $ace.AceFlags = 0
    }
    Write-Log -Data "New ACE's AceFlags: $($ace.AceFlags)" -Type 'Verbose'
                       
    $trustee = (New-Object System.Management.ManagementClass('win32_Trustee')).CreateInstance()
    $trustee.SidString = $accountSid
    $ace.Trustee = $trustee
 
    if ($deny) {
        $ace.AceType = 0x1
    }
    else {
        $ace.AceType = 0x0
    }
    Write-Log -Data "New ACE's AceType: $($ace.AceType)" -Type 'Verbose'

    # Add the ACE to the DACL
    $sd.DACL += $ace.psobject.immediateBaseObject
  
    # Set the new Security Descriptor to the namespace
    Write-Log -Data "Setting the new security descriptor to WMI namespace `"$namespace`"..." -Type 'Verbose'
    try {
        $setSDOutput = Invoke-WmiMethod -Namespace $namespace -Path '__systemsecurity=@' -ArgumentList $sd.psobject.immediateBaseObject -Name 'SetSecurityDescriptor' -ErrorAction 'Stop'
    }
    catch {
        Write-Log -Data "An error occured whilst setting the updated WMI permissions on namespace `"$namespace`". Error message:`n$_" -Type 'Basic' -eventType 'Error' -eventID 14
    }

    if ($setSDOutput.ReturnValue -ne 0) {
        Write-Log -Data "WMI Method `"SetSecurityDescriptor`" on namespace `"$namespace`" failed, return code: $($setSDOutput.ReturnValue)" -Type 'Basic'
        exit 3
    }
    Write-Log -Data "Updated security descriptor on WMI namespace `"$namespace`". Added permissions: $permissions" -Type 'Basic' -eventType 'Information' -eventID 15
}

# Function that gives permissions to change ownership on a registry key
function Set-RegistryKeyOwnershipPrivileges {
    param(
        [parameter(Mandatory = $true, Position = 0)]
        [string]$rootKey,
        [parameter(Mandatory = $true, Position = 1)]
        [string]$key
    )

    switch -regex ($rootKey) {
        'HKCU|HKEY_CURRENT_USER' { $rootKey = 'CurrentUser' }
        'HKLM|HKEY_LOCAL_MACHINE' { $rootKey = 'LocalMachine' }
        'HKCR|HKEY_CLASSES_ROOT' { $rootKey = 'ClassesRoot' }
        'HKCC|HKEY_CURRENT_CONFIG' { $rootKey = 'CurrentConfig' }
        'HKU|HKEY_USERS' { $rootKey = 'Users' }
    }

    # Give ourself the privileges to take ownership
    Write-Log -Data "Taking privileges to change ownership of registry key `"$rootKey\$key`"..." -Type 'Verbose'
    $import = '[DllImport("ntdll.dll")] public static extern int RtlAdjustPrivilege(ulong a, bool b, bool c, ref bool d);'
    $privileges = @{ SeTakeOwnership = 9; SeBackup = 17; SeRestore = 18 }
    foreach ($value in $privileges.Values) {
        $null = (Add-Type -Member $import -Name NtDll -PassThru)::RtlAdjustPrivilege($value, 1, 0, [ref]0)
    }
}

# Function that sets full control permissions on registry keys and takes ownership (recursively with -recurse)
function Set-RegistryKeyOwnerPermissions {
    param(
        [parameter(Mandatory = $true, Position = 0)]
        [string]$rootKey,
        [parameter(Mandatory = $true, Position = 1)]
        [string]$key,
        [parameter(Mandatory = $true, Position = 2)]
        [string]$accountName,
        [parameter(Mandatory = $true, Position = 3)]
        [System.Security.Principal.SecurityIdentifier]$accountSid,
        [switch]$recurse
    )

    switch -regex ($rootKey) {
        'HKCU|HKEY_CURRENT_USER' { $rootKey = 'CurrentUser' }
        'HKLM|HKEY_LOCAL_MACHINE' { $rootKey = 'LocalMachine' }
        'HKCR|HKEY_CLASSES_ROOT' { $rootKey = 'ClassesRoot' }
        'HKCC|HKEY_CURRENT_CONFIG' { $rootKey = 'CurrentConfig' }
        'HKU|HKEY_USERS' { $rootKey = 'Users' }
    }

    # Retrieve the current ACL of the registry key
    $regKey = [Microsoft.Win32.Registry]::$rootKey.OpenSubKey($key, 'ReadWriteSubTree', 'TakeOwnership')
    $acl = New-Object System.Security.AccessControl.RegistrySecurity
    $acl.SetOwner($accountSid)
    $regKey.SetAccessControl($acl)
    $acl.SetAccessRuleProtection($false, $false) # Enables inheritance
    $identityReferenceInAcls = $acl.Owner # This is used to transform the SID to the identity reference used in ACL's

    # Check if the user already has ownership of the key
    Write-Log -Data "Checking if `"$accountName`" is already owner of registry key `"$rootKey\$key`"..." -Type 'Verbose'
    if ($regKey.GetAccessControl().Owner -eq $identityReferenceInAcls) {
        Write-Log -Data "`"$accountName`" is already owner of registry key `"$rootKey\$key`", skipping." -Type 'Basic' -eventType 'Information' -eventID 16
    }
    else {
        # Set ownership on key
        Write-Log -Data "Changing ownership of registry key `"$rootKey\$key`" to `"$accountName`"..." -Type 'Basic' -eventType 'Information' -eventID 17
        $regKey.SetAccessControl($acl)
    }

    # Check if the user already has Full Control permissions on the key
    Write-Log -Data "Checking if `"$accountName`" already has full control permissions on registry key `"$rootKey\$key`"..." -Type 'Verbose'
    $regKey = [Microsoft.Win32.Registry]::$rootKey.OpenSubKey($key, 'ReadWriteSubTree', 'ChangePermissions')
    $ExistingAcl = $regkey.GetAccessControl().Access | Where-Object {
        $_.IdentityReference -eq $identityReferenceInAcls -and $_.RegistryRights -eq 'FullControl' -and $_.AccessControlType -eq 'Allow' 
    }

    if ($ExistingAcl) {
        Write-Log -Data "`"$accountName`" already has full control permissions on registry key `"$rootKey\$key`", skipping." -Type 'Basic' -eventType 'Information' -eventID 18
    }
    else {
        Write-Log -Data "`Setting full control permissions for `"$accountName`" on registry key `"$rootKey\$key`"..." -Type 'Basic' -eventType 'Information' -eventID 19
        $regKey = [Microsoft.Win32.Registry]::$rootKey.OpenSubKey($key, 'ReadWriteSubTree', 'ChangePermissions')
        $rule = New-Object System.Security.AccessControl.RegistryAccessRule($sid, 'FullControl', 'ContainerInherit', 'None', 'Allow')
        $acl.ResetAccessRule($rule)
        $regKey.SetAccessControl($acl)
    }

    # Recursively repeat
    if ($recurse) {
        foreach ($subKey in $regKey.OpenSubKey('').GetSubKeyNames()) {
            Set-RegistryKeyFullControlPermissions -rootKey $rootKey -key ($key + '\' + $subKey) -accountName $accountName -accountSid $accountSid -recurse:$recurse
        }
    }
}
 
# Function that maps the DCOM access permissions to the corresponding AccessMask integer code 
function Get-AccessMaskFromDCOMAccessPermission {
    param (
        [parameter(Mandatory = $true, Position = 0)]
        [String[]]$permissions
    )

    Write-Log -Data 'Determining requesting DCOM access mask...' -Type 'Verbose'
    $accessMask = 1

    foreach ($permission in $permissions) {
        Write-Log -Data "Parsing DCOM permission `"$permission`"..." -Type 'Verbose'
        switch ($permission) {
            'LocalAccess' { $accessMask += 2 }
            'RemoteAccess' { $accessMask += 4 }
            default { Write-Log -Data "Unknown DCOM access permission: `"$permission`"`n, skipping." -Type 'Basic' -eventType 'Warning' -eventID 20 }
        }

        Write-Log -Data "New DCOM access mask value: $accessMask" -Type 'Verbose'
    }

    Write-Log -Data "Final DCOM access mask value: $accessMask" -Type 'Verbose'
    return $accessMask
}

# Function that maps the DCOM launch permissions to the corresponding AccessMask integer code 
function Get-AccessMaskFromDCOMLaunchPermission {
    param (
        [parameter(Mandatory = $true, Position = 0)]
        [String[]]$permissions
    )
    
    Write-Log -Data 'Determining requested DCOM launch mask...' -Type 'Verbose'
    $accessMask = 1

    foreach ($permission in $permissions) {
        Write-Log -Data "Parsing DCOM permission `"$permission`"..." -Type 'Verbose'
        switch ($permission) {
            'LocalLaunch' { $accessMask += 2 }
            'RemoteLaunch' { $accessMask += 4 }
            'LocalActivation' { $accessMask += 8 }
            'RemoteActivation' { $accessMask += 16 }
            default { Write-Log -Data "Unknown DCOM launch permission: `"$permission`"`n, skipping." -Type 'Basic' -eventType 'Information' -eventID 21 }
        }

        Write-Log -Data "New DCOM launch mask value: $accessMask" -Type 'Verbose'
    }

    Write-Log -Data "Final DCOM launch mask value: $accessMask" -Type 'Verbose'
    return $accessMask
}

# Function that adds permissions on a DCOM component
function Add-DCOMPermissions {
    param (
        [parameter(Mandatory = $true, Position = 0)]
        [string]$dcomAppId,
        [parameter(Mandatory = $true, Position = 1)]
        [string]$accountName,
        [parameter(Mandatory = $true, Position = 2)]
        [System.Security.Principal.SecurityIdentifier]$accountSid,
        [string[]]$accessPermissions,
        [string[]]$launchPermissions
    )

    # Input validation (make sure -accessPermissions or -launchPermissions is specified)
    if (-not $accessPermissions -and -not $launchPermissions) {
        Write-Log -Data 'You have to either specify -accessPermissions or -launchPermissions permissions.' -Type 'Basic'
        return
    }

    # Get the app object
    Write-Log -Data "Retrieving the DCOM app with App ID `"$dcomAppId`"..." -Type 'Verbose'
    $app = Get-WmiObject -query ("SELECT * FROM Win32_DCOMApplicationSetting WHERE AppId = `"$dcomAppId`"") -EnableAllPrivileges
    if (-not $app) {
        Write-Log -Data "The DCOM app with app ID `"$dcomAppId`" could not be retrieved." -Type 'Basic' -eventType 'Error' -eventID 22
        return
    }

    if ($accessPermissions) {
        # Retrieve the current Security Descriptor
        $sd = $app.GetAccessSecurityDescriptor().Descriptor

        # Check if the account already has the requested permissions on the DCOM app 
        Write-Log -Data "Checking if `"$accountName`" already has the requested access permissions on the DCOM app with app ID `"$dcomAppId`"..." -Type 'Verbose'
        $requestedAccessAccessMask = Get-AccessMaskFromDCOMAccessPermission -permissions $accessPermissions
        if ($sd.DACL | Where-Object { $_.Trustee.SidString -eq $accountSid -and $_.AccessMask -eq $requestedAccessAccessMask }) {
            Write-Log -Data "`"$accountName`" already has the requested access permissions on the DCOM app with app ID `"$dcomAppId`", skipping." -Type 'Basic' -eventType 'Information' -eventID 23
        }
        else {
            # Create the ACE
            Write-Log -Data "Creating the requested access permissions ACE for user `"$accountName`"..." -Type 'Verbose'
            $ace = (New-Object System.Management.ManagementClass('win32_Ace')).CreateInstance()
            $ace.AccessMask = $requestedAccessAccessMask
            $ace.AceFlags = 0
                       
            $trustee = (New-Object System.Management.ManagementClass('win32_Trustee')).CreateInstance()
            $trustee.SidString = $accountSid
            $ace.Trustee = $trustee
            $ace.AceType = 0x0
 
            # Add the ACE to the DACL
            $sd.DACL += $ace.psobject.immediateBaseObject

            # Set the modified access security descriptor to the DCOM App
            Write-Log -Data "Setting the modified access security descriptor on the DCOM app with app ID `"$dcomAppId`"..." -Type 'Verbose'
            $output = $app.SetAccessSecurityDescriptor($sd.psobject.immediateBaseObject)
            if ($output.ReturnValue -ne 0) {
                Write-Log -Data "The SetAccessSecurityDescriptor method on the DCOM app with app ID `"$dcomAppId`" failed, return code: $($output.ReturnValue)" -Type 'Basic' -eventType 'Error' -eventID 24
            }
            else {
                Write-Log -Data "Successfully set the modified access security descriptor on DCOM app with app ID `"$dcomAppId`"" -Type 'Verbose'
            }
        }
    }

    if ($launchPermissions) {
        # Retrieve the current Security Descriptor
        $sd = $app.GetLaunchSecurityDescriptor().Descriptor

        # Check if the account already has the requested permissions on the DCOM app 
        Write-Log -Data "Checking if `"$accountName`" already has the requested launch permissions on the DCOM app with app ID `"$dcomAppId`"..." -Type 'Verbose'
        $requestedLaunchAccessMask = Get-AccessMaskFromDCOMLaunchPermission -permissions $launchPermissions
        if ($sd.DACL | Where-Object { $_.Trustee.SidString -eq $accountSid -and $_.AccessMask -eq $requestedLaunchAccessMask }) {
            Write-Log -Data "`"$accountName`" already has the requested launch permissions on the DCOM app with app ID `"$dcomAppId`", skipping." -Type 'Basic' -eventType 'Information' -eventID 25
        }
        else {
            # Create the ACE
            Write-Log -Data "Creating the requested launch permissions ACE for user `"$accountName`"..." -Type 'Verbose'
            $ace = (New-Object System.Management.ManagementClass('win32_Ace')).CreateInstance()
            $ace.AccessMask = $requestedLaunchAccessMask
            $ace.AceFlags = 0
                       
            $trustee = (New-Object System.Management.ManagementClass('win32_Trustee')).CreateInstance()
            $trustee.SidString = $accountSid
            $ace.Trustee = $trustee
            $ace.AceType = 0x0
 
            # Add the ACE to the DACL
            $sd.DACL += $ace.psobject.immediateBaseObject

            # Set the modified launch security descriptor to the DCOM App
            Write-Log -Data "Setting the modified launch security descriptor on the DCOM app with app ID `"$dcomAppId`"..." -Type 'Verbose'
            $output = $app.SetLaunchSecurityDescriptor($sd.psobject.immediateBaseObject)
            if ($output.ReturnValue -ne 0) {
                Write-Log -Data "The SetLaunchSecurityDescriptor method on the DCOM app with app ID `"$dcomAppId`" failed, return code: $($output.ReturnValue)" -Type 'Basic' -eventType 'Error' -eventID 26
            }
            else {
                Write-Log -Data "Successfully set the modified launch security descriptor on DCOM app with app ID `"$dcomAppId`"" -Type 'Verbose'
            }
        }
    }
}

# Function that adds a read clause to the security descriptor of a service
function Add-SDReadClause {
    param (
        [parameter(Mandatory = $true, Position = 0)]
        [string]$service,
        [parameter(Mandatory = $true, Position = 1)]
        [string]$accountName,
        [parameter(Mandatory = $true, Position = 2)]
        [System.Security.Principal.SecurityIdentifier]$accountSid
    )

    # Get the current security descriptor
    Write-Log -Data "Getting current security descriptor of service `"$service`"" -Type 'Verbose'
    $sd = & sc.exe sdshow $service
    if ($sd[1].substring(0, 3) -ne 'D:(') {
        Write-Log -Data "The security descriptor for service `"$service`" could not be retrieved." -Type 'Basic' -eventType 'Error' -eventID 27
        return
    }

    # Check if the object already has permissions defined
    Write-Log -Data "Checking if the account already has permissions defined on service `"$service`"..." -Type 'Verbose'
    if ($sd[1].contains($accountSid)) {
        Write-Log -Data "Account `"$accountSid`" already has permissions defined on service `"$service`", skipping." -Type 'Basic' -eventType 'Information' -eventID 28
        Write-Log -Data "Current SDDL: $($sd[1])" -Type 'Verbose'
        return 
    }

    # Add the read clause to the current SDDL
    Write-Log -Data "Current security descriptor for service `"$service`": $($sd[1])" -Type 'Verbose'
    Write-Log -Data "Adding read permission for `"$accountName`" to the security descriptor of the `"$service`" service..." -Type 'Basic'
    $sd = "$($sd[1].substring(0,2))(A;;CCLCRPRC;;;$($accountSid))$($sd[1].substring(2,$sd[1].length-2))"
    Write-Log "New security descriptor for service `"$service`": $($sd)" -Type 'Verbose'

    # Set the changed SDDL
    Write-Log -Data "Setting the modified security descriptor on service `"$service`"..." -Type 'Verbose'
    $sdSetOutput = sc.exe sdset $service "$sd"

    if ($sdSetOutput.Contains('SUCCESS')) {
        Write-Log -Data "Successfully modified the security descriptor for service `"$service`"" -Type 'Basic' -eventType 'Information' -eventID 29
    }
    else {
        Write-Log -Data "An error occurred whilst setting the security descriptor for service `"$service`", sdset output: $sdSetOutput" -Type 'Basic' -eventType 'Error' -eventID 30
    }
}

# Function that adds/updates a property in registry
function Set-RegistryProperty {
    param (
        [parameter(Mandatory = $true, Position = 0)]
        [string]$path,
        [parameter(Mandatory = $true, Position = 1)]
        [string]$name,
        [parameter(Mandatory = $true, Position = 2)]
        [String]$type,
        [parameter(Mandatory = $true, Position = 3)]
        [String]$value
    )

    # Create the parent key if it doesn't exist
    Write-Log -Data "Checking if registry key `"$path`" exists..." -Type 'Verbose'
    if (-not (Test-Path $path)) {
        try {
            Write-Log -Data "Creating registry key `"$path`"..." -Type 'Basic'
            New-Item -Path $path -Type Directory -Force -ErrorAction 'Stop' | Out-Null
        }
        catch {
            Write-Log -Data "An error occured whilst creating the registry key `"$path`". Error:`n$_" -Type 'Basic' -eventType 'Error' -eventID 31
            return
        }
    }

    # Check if the property already exists
    Write-Log -Data "Checking if registry property `"$name`" in `"$path`" already has value `"$value`"..." -Type 'Verbose'
    if ((Get-Item -LiteralPath $path).GetValue($name, $null) -eq $value) {
        Write-Log -Data "Registry property `"$name`" in `"$path`" already has value `"$value`", skipping." -Type 'Basic' -eventType 'Information' -eventID 32
        return
    }

    # Add/update the property
    Write-Log -Data "Creating/Updating registry property `"$name`" in `"$path`" with value `"$value`"..." -Type 'Basic'
    try {
        New-ItemProperty -Path $path -Name $name -Value $value -PropertyType $type -Force -ErrorAction 'Stop' | Out-Null
    }
    catch {
        Write-Log -Data "An error occured whilst creating the registry property `"$name`" in `"$path`". Error:`n$_" -Type 'Basic' -eventType 'Error' -eventID 33
    }
}

# Function that configures Windows scanning
function Add-WindowsScanning {
    param (
        [parameter(Mandatory = $true, Position = 0)]
        [string]$accountName,
        [parameter(Mandatory = $true, Position = 1)]
        [System.Security.Principal.SecurityIdentifier]$accountSid
    )

    # Check if the computer is a domain controller. If this is the case, the user should be added to the corresponding BUILTIN AD groups
    if ((Get-WmiObject -Class Win32_ComputerSystem | Select-Object -ExpandProperty DomainRole) -in (4, 5)) {
        # Add-ADGroupMember uses the samAccountName to identify the object in AD.
        $objectSamAccountName = $accountName.Split('\')[1]

        # Add the account to the AD "Distributed COM Users" group (needed for access to DCOM on the DC's)
        Add-ObjectToADGroup -objectName $objectSamAccountName -groupName 'Distributed COM Users'

        # Add the account to the AD "Event Log Readers" group (needed for event log scanning on the DC's)
        Add-ObjectToADGroup -objectName $objectSamAccountName -groupName 'Event Log Readers'
    }
    else {
        # Add the account to the local "Distributed COM Users" group (needed for access to DCOM on the local computer)
        Add-ObjectToLocalGroup -objectName $accountName -groupName 'Distributed COM Users'

        # Add the account to the local "Event Log Readers" group (needed for event log scanning on the local computer)
        Add-ObjectToLocalGroup -objectName $accountName -groupName 'Event Log Readers'
    }

    # Give the user access to the required WMI namespaces (needed for access to WMI classes used for basic windows scanning)

    foreach ($wmiNamespace in $wmiNamespaces) {
        if ($wmiNamespace -eq 'Root\SMS') {
            Add-SccmScanning -accountName $formattedAccountName -accountSid $accountSid  
        } 
        elseif ($wmiNamespace -eq 'Root\Microsoft\sqlserver') {
            Add-SQLScanning -accountName $formattedAccountName -accountSid $accountSid    
        }
        else {
            Add-WMIPermissions -namespace $wmiNamespace -accountName $formattedAccountName -accountSid $accountSid -permissions $wmiPermissions -enableInherit
        }
    }

    # Give the user full control permissions on the DCOM components in registry (needed for changing DCOM access & launch permissions)
    foreach ($appId in $appIds) {
        Set-RegistryKeyOwnershipPrivileges -rootKey 'HKCR' -key "AppID\$appId"
        Set-RegistryKeyOwnerPermissions -rootKey 'HKCR' -key "AppID\$appId" -accountName 'BUILTIN\Administrators' -accountSid 'S-1-5-32-544' -recurse

        # Give the user LocalAccess, LocalLaunch and LocalActivation permissions on the DCOM component (needed for scanning features)
        Add-DCOMPermissions -dcomAppId $appId -accountName $formattedAccountName -accountSid $accountSid -accessPermissions 'LocalAccess' -launchPermissions 'LocalLaunch', 'LocalActivation'
    }

    # Give the user permissions to read services (needed for scanning services)
    Add-SDReadClause -service 'scmanager' -accountName $formattedAccountName -accountSid $accountSid

    # Allow access to netBIOS from other networks (required if your scanning server is in another subnet)
    Set-RegistryProperty -path 'HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters' -name 'AllowNBToInternet' -Type 'DWORD' -value 34

    # Enable WMI/DCOM through firewall
    Write-Log -Data 'Checking if WMI/DCOM is allowed through the firewall...' -Type 'Verbose'
    if (Get-NetFirewallRule -DisplayGroup 'Windows Management Instrumentation (WMI)' | Where-Object { $_.Enabled -ne 'True' }) {
        Write-Log -Data 'WMI/DCOM is not allowed through the firewall, enabling the rules...' -Type 'Basic' -eventType 'Information' -eventID 35
        Set-NetFirewallRule -DisplayGroup 'Windows Management Instrumentation (WMI)' -Enabled True
    }
    else {
        Write-Log -Data 'WMI/DCOM is allowed through the firewall, skipping.' -Type 'Basic' -eventType 'Information' -eventID 36
    }

    # Enable WinRM rules in the firewall
    Write-Log -Data 'Checking if WinRM firewall rules are enabled...' -Type 'Verbose'

    if ((Get-NetFirewallRule -DisplayName 'Windows Remote Management (HTTP-In)').Enabled -eq 'False') {
        Write-Log -Data 'WinRM HTTP firewall rule is not enabled, enabling the firewall rules...' -Type 'Basic' -eventType 'Information' -eventID 37
        Set-NetFirewallRule -DisplayName 'Windows Remote Management (HTTP-In)' -Enabled True
    }
    else {
        Write-Log -Data 'WinRM HTTP firewall rules are already enabled, skipping.' -Type 'Basic' -eventType 'Information' -eventID 38
    }

    if ((Get-NetFirewallRule -DisplayName 'Windows Remote Management (HTTPS-In)').Enabled -eq 'False') {
        Write-Log -Data 'WinRM HTTP firewall rule is not enabled, enabling the firewall rules...' -Type 'Basic' -eventType 'Information' -eventID 37
        Set-NetFirewallRule -DisplayName 'Windows Remote Management (HTTPS-In)' -Enabled True
    }
    else {
        Write-Log -Data 'WinRM HTTPS firewall rules are already enabled, skipping.' -Type 'Basic' -eventType 'Information' -eventID 42
    }

    # Allow ICMPv4 Ping in the firewall
    Write-Log -Data 'Checking if echo request firewall rules are enabled...' -Type 'Verbose'
    try {
        $icmpv4PingEnabled = (Get-NetFirewallRule -DisplayName 'Allow echo request (ICMPv4-IN)' -ErrorAction Stop).Enabled
    }
    catch {
        $icmpv4PingEnabled = $True
        Write-Log -Data 'ICMPv4 echo request firewall rule does not exist, creating the firewall rule...' -Type 'Basic' -eventType 'Information' -eventID 43

        New-NetFirewallRule -DisplayName 'Allow echo request (ICMPv4-IN)' -Direction Inbound -Protocol ICMPv4 -IcmpType 8 -Action Allow
    }

    if (-not $icmpv4PingEnabled) {
        Write-Log -Data 'ICMPv4 echo request firewall rule is not enabled, enabling the firewall rule...' -Type 'Basic' -eventType 'Information' -eventID 44
        Set-NetFirewallRule -DisplayName 'Allow echo request (ICMPv4-IN)' -Enabled True
    }

    # Allow ICMPv6 Ping in the firewall
    try {
        $icmpv6PingEnabled = (Get-NetFirewallRule -DisplayName 'Allow echo request (ICMPv6-IN)' -ErrorAction Stop).Enabled
    }
    catch {
        $icmpv6PingEnabled = $True
        Write-Log -Data 'ICMPv6 echo request firewall rule does not exist, creating the firewall rule...' -Type 'Basic' -eventType 'Information' -eventID 45
    
        New-NetFirewallRule -DisplayName 'Allow echo request (ICMPv6-IN)' -Direction Inbound -Protocol ICMPv6 -IcmpType 8 -Action Allow
    }
    
    if (-not $icmpv6PingEnabled) {
        Write-Log -Data 'ICMPv6 echo request firewall rule is not enabled, enabling the firewall rule...' -Type 'Basic' -eventType 'Information' -eventID 46
        Set-NetFirewallRule -DisplayName 'Allow echo request (ICMPv6-IN)' -Enabled True
    }
}

# Function that configures SQL scanning
function Add-SQLScanning {
    param (
        [parameter(Mandatory = $true, Position = 0)]
        [string]$accountName,
        [parameter(Mandatory = $true, Position = 1)]
        [System.Security.Principal.SecurityIdentifier]$accountSid
    )

    $sqlWmiNamespaces = @('Root\Microsoft\SqlServer')

    # Check if the parent namespace exists
    Write-Log -Data 'Checking if the WMI namespace for SQL server ("Root\Microsoft\SqlServer") exists...' -Type 'Verbose'

    if (-not (Find-WMINamespace -namespace 'Root\Microsoft\SqlServer')) {
        Write-Log -Data 'No WMI namespaces for SQL could be found, skipping SQL scanning permissions.' -Type 'Verbose' -eventType 'Information' -eventID 39
        return
    }

    Write-Log -Data 'SQL WMI namespace "Root\Microsoft\SqlServer" found.' -Type 'Verbose'

    # Get SQL service namespaces
    $sqlWmiNamespaces += Get-WmiObject -Class '__Namespace' -Namespace 'Root\Microsoft\SqlServer' | 
    Where-Object { $_.Name -match 'ComputerManagement[0-9]{1,2}' } | 
    ForEach-Object { "Root\Microsoft\SqlServer\$($_.Name)" }

    foreach ($wmiNamespace in $sqlWmiNamespaces) {
        Add-WMIPermissions -namespace $wmiNamespace -accountName $accountName -accountSid $accountSid -permissions $wmiPermissions -enableInherit
    }
}

function Add-SccmScanning {
    param (
        [parameter(Mandatory = $true, Position = 0)]
        [string]$accountName,
        [parameter(Mandatory = $true, Position = 1)]
        [System.Security.Principal.SecurityIdentifier]$accountSid
    )

    $sccmWmiNamespaces = @('Root\SMS')

    # Check if the parent namespace exists
    Write-Log -Data 'Checking if the WMI namespace for SCCM ("Root\SMS") exists...' -Type 'Verbose'

    if (-not (Find-WMINamespace -namespace 'Root\SMS')) {
        Write-Log -Data 'No WMI namespaces for SCCM could be found, skipping SMS scanning permissions.' -Type 'Verbose' -eventType 'Information' -eventID 40
        return
    }

    Write-Log -Data 'SCCM WMI namespace "Root\SMS" found.' -Type 'Verbose'

    # Get SCCM site namespaces
    $sccmWmiNamespaces += Get-WmiObject -Class '__Namespace' -Namespace 'Root\SMS' | 
    Where-Object { $_.Name -match 'site_' } | 
    ForEach-Object { "Root\SMS\$($_.Name)" }

    foreach ($wmiNamespace in $sccmWmiNamespaces) {
        Add-WMIPermissions -namespace $wmiNamespace -accountName $accountName -accountSid $accountSid -permissions $wmiPermissions -enableInherit
    }
}

### Initialization ###
$ErrorActionPreference = 'Continue'

# Initialize log file
if ($logLevel -ne 0) {
    Set-LogFile
}

if (-not $noEventLog) {
    Set-EventLog
}

# Split on , if multiple accounts are specified + trim them to avoid trailing/leading whitespaces
$parsedAccountNames = ForEach-Object -InputObject $accountNames.Split(',') { $_.Trim() }

foreach ($accountName in $parsedAccountNames) {
    # For later comparison of accounts, use SAMAccountName
    $formattedAccountName = Format-AccountName -accountName $accountName

    # Get the SID of the account
    $accountSid = Get-AccountSID -AccountName $formattedAccountName

    ### Windows scanning ###
    Add-WindowsScanning -accountName $formattedAccountName -accountSid $accountSid
}