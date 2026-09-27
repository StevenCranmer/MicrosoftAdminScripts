# Example: .\WSUSImport.ps1 -UpdateIdFilePath .\wsus-update-ids.example.txt
# Variables: Use -UpdateId for one catalog ID or -UpdateIdFilePath for a text file with one ID per line; see .\wsus-update-ids.example.txt.
# Purpose: Import one or more Microsoft Update Catalog IDs into WSUS.
# Requires: UpdateServices PowerShell commands and WSUS administration rights.
# Effect: Imports updates on the selected WSUS server; the example ID file contains only a dummy ID.
#
<#
.SYNOPSIS
Powershell script to import an update, or multiple updates into WSUS based on the UpdateID from the catalog.

.DESCRIPTION
This script takes user input and attempts to connect to the WSUS server.
Then it tries to import the update using the provided UpdateID from the catalog.

.INPUTS
The script takes WSUS server Name/IP, WSUS server port, SSL configuration option and UpdateID as input. UpdateID can be viewed and copied from the update details page for any update in the catalog, https://catalog.update.microsoft.com.

.OUTPUTS
Writes logging information to standard output.

.EXAMPLE
# Use with remote server IP, port and SSL
.\WSUSImport.ps1 -WsusServer 127.0.0.1 -PortNumber 8531 -UseSsl -UpdateId 12345678-90ab-cdef-1234-567890abcdef

.EXAMPLE
# Use with remote server Name, port and SSL
.\WSUSImport.ps1 -WsusServer WSUSServer1.us.contoso.com -PortNumber 8531 -UseSsl -UpdateId 12345678-90ab-cdef-1234-567890abcdef

.EXAMPLE
# Use with remote server IP, defaultport and no SSL
.\WSUSImport.ps1 -WsusServer 127.0.0.1  -UpdateId 12345678-90ab-cdef-1234-567890abcdef

.EXAMPLE
# Use with localhost default port
.\WSUSImport.ps1 -UpdateId 12345678-90ab-cdef-1234-567890abcdef

.EXAMPLE
# Use with localhost default port, file with updateID's
.\WSUSImport.ps1 -UpdateIdFilePath .\wsus-update-ids.example.txt

.NOTES  
# On error, try enabling TLS: https://learn.microsoft.com/mem/configmgr/core/plan-design/security/enable-tls-1-2-client

# Sample registry add for the WSUS server from command line. Restarts the WSUSService and IIS after adding:
reg add HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\.NETFramework\v4.0.30319 /V SchUseStrongCrypto /T REG_DWORD /D 1

## Sample registry add for the WSUS server from PowerShell. Restarts WSUSService and IIS after adding:
$registryPath = "HKLM:\Software\Microsoft\.NETFramework\v4.0.30319"
$Name = "SchUseStrongCrypto"
$value = "1" 
if (!(Test-Path $registryPath)) {
    New-Item -Path $registryPath -Force | Out-Null
}
New-ItemProperty -Path $registryPath -Name $name -Value $value -PropertyType DWORD -Force | Out-Null
Restart-Service WsusService, w3svc

# Update import logs/errors are under %ProgramFiles%\Update Services\LogFiles\SoftwareDistribution.log

#>

param(
    [Parameter(Mandatory = $false, HelpMessage = "Specifies the name of a WSUS server, if not specified connects to localhost")]
    # Specifies the name of a WSUS server, if not specified connects to localhost.
    [string]$WsusServer,

[Parameter(Mandatory = $false, HelpMessage = "Specifies the port number to use to communicate with the upstream WSUS server, default is 8530")]
    # Specifies the port number to use to communicate with the upstream WSUS server, default is 8530.
    [ValidateSet("80", "443", "8530", "8531")]
    [int32]$PortNumber = 8530,

[Parameter(Mandatory = $false, HelpMessage = "Specifies that the WSUS server should use Secure Sockets Layer (SSL) via HTTPS to communicate with an upstream server")]
    # Specifies that the WSUS server should use Secure Sockets Layer (SSL) via HTTPS to communicate with an upstream server.  
    [Switch]$UseSsl,

[Parameter(Mandatory = $true, HelpMessage = "Specifies the update Id we should import to WSUS", ParameterSetName = "Single")]
    # Specifies the update Id we should import to WSUS
    [ValidateNotNullOrEmpty()]
    [String]$UpdateId,

[Parameter(Mandatory = $true, HelpMessage = "Specifies path to a text file containing a list of update ID's on each line", ParameterSetName = "Multiple")]
    # Specifies path to a text file containing a list of update ID's on each line.
    [ValidateNotNullOrEmpty()]
    [String]$UpdateIdFilePath
)

Set-StrictMode -Version Latest

# set server options
# Windows administration tools are installed as OS features, not from PSGallery.
if (-not (Get-Module -ListAvailable -Name UpdateServices)) {
    $answer = Read-Host "UpdateServices tools are missing. Install the Windows administration tools now? [y/N]"
    if ($answer -notmatch '^(?i:y|yes)$') {
        throw "UpdateServices tools are required. Install them through Windows optional features or Server Manager, then rerun."
    }
    $isAdministrator = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdministrator) {
        throw 'Installing Windows administration tools requires an elevated PowerShell session. Reopen PowerShell as administrator and rerun.'
    }
    $isServer = (Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).ProductType -ne 1
    if ($isServer) {
        if (-not (Get-Command Install-WindowsFeature -ErrorAction SilentlyContinue)) { throw 'Install-WindowsFeature is unavailable. Install the tools through Server Manager.' }
        $result = Install-WindowsFeature -Name 'UpdateServices-RSAT' -ErrorAction Stop
        if (-not $result.Success) { throw 'Windows reported that the feature installation did not succeed.' }
    } else {
        if (-not (Get-Command Add-WindowsCapability -ErrorAction SilentlyContinue)) { throw 'Add-WindowsCapability is unavailable. Install the tools through Windows optional features.' }
        $result = Add-WindowsCapability -Online -Name 'Rsat.WSUS.Tools~~~~0.0.1.0' -ErrorAction Stop
        if ($result.RestartNeeded) { throw 'The tools need a restart before they can be used. Restart Windows, then rerun.' }
    }
}
Import-Module UpdateServices -ErrorAction Stop

$serverOptions = "Get-WsusServer"
if ($psBoundParameters.containsKey('WsusServer')) { $serverOptions += " -Name $WsusServer -PortNumber $PortNumber" }
if ($UseSsl) { $serverOptions += " -UseSsl" }

# empty updateID list
$updateList = @()

# get update id's
if ($UpdateIdFilePath) {
    if (Test-Path $UpdateIdFilePath) {
        foreach ($id in (Get-Content $UpdateIdFilePath)) {
            $updateList += $id.Trim()
        }
    }
    else {
        Write-Error "[$UpdateIdFilePath]: File not found"
		return
    }
}
else {
    $updateList = @($UpdateId)
}

# get WSUS server
Try {
    Write-Host "Attempting WSUS Connection using $serverOptions... " -NoNewline
    $server = invoke-expression $serverOptions
    Write-Host "Connection Successful"
}
Catch {
    Write-Error $_
    return
}

# empty file list
$FileList = @()

# call ImportUpdateFromCatalogSite on WSUS
foreach ($uid in $updateList) {
    Try {
        Write-Host "Attempting WSUS update import for Update ID: $uid... " -NoNewline
        $server.ImportUpdateFromCatalogSite($uid, $FileList)
        Write-Host "Import Successful"
    }
    Catch {
        Write-Error "Failed. $_"
    }
}