# Example: .\Copy-DHCPExclusions.ps1 -SourceServer 'SOURCE-DHCP' -TargetServer 'TARGET-DHCP'
# Variables: -SourceServer is the DHCP source; -TargetServer is the destination. Replace both example names.
# Purpose: Copy exclusion ranges across scopes shared by two DHCP servers.
# Requires: DhcpServer PowerShell commands and rights on source and target DHCP servers.
# Effect: Adds missing ranges on the target server; review both server names first.
#

<#
.SYNOPSIS
    One-off: Copy IPv4 DHCP scope exclusion ranges from SOURCE-DHCP to TARGET-DHCP.

.DESCRIPTION
    Reads all IPv4 scopes on the source DHCP server and copies their exclusion ranges
    to the target server for scopes that exist on both servers. Adds only missing
    exclusions on the target. Does not remove anything.

.PARAMETERS
    -SourceServer (default: SOURCE-DHCP)
    -TargetServer (default: TARGET-DHCP)

.EXAMPLE
    # Dry run
    .\Copy-DhcpExclusions.ps1 -WhatIf

.EXAMPLE
    # Execute with verbose output
    .\Copy-DhcpExclusions.ps1 -Verbose
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$SourceServer = 'SOURCE-DHCP',
    [string]$TargetServer = 'TARGET-DHCP'
)

# Windows administration tools are installed as OS features, not from PSGallery.
if (-not (Get-Module -ListAvailable -Name DhcpServer)) {
    $answer = Read-Host "DhcpServer tools are missing. Install the Windows administration tools now? [y/N]"
    if ($answer -notmatch '^(?i:y|yes)$') {
        throw "DhcpServer tools are required. Install them through Windows optional features or Server Manager, then rerun."
    }
    $isAdministrator = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdministrator) {
        throw 'Installing Windows administration tools requires an elevated PowerShell session. Reopen PowerShell as administrator and rerun.'
    }
    $isServer = (Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).ProductType -ne 1
    if ($isServer) {
        if (-not (Get-Command Install-WindowsFeature -ErrorAction SilentlyContinue)) { throw 'Install-WindowsFeature is unavailable. Install the tools through Server Manager.' }
        $result = Install-WindowsFeature -Name 'RSAT-DHCP' -ErrorAction Stop
        if (-not $result.Success) { throw 'Windows reported that the feature installation did not succeed.' }
    } else {
        if (-not (Get-Command Add-WindowsCapability -ErrorAction SilentlyContinue)) { throw 'Add-WindowsCapability is unavailable. Install the tools through Windows optional features.' }
        $result = Add-WindowsCapability -Online -Name 'Rsat.DHCP.Tools~~~~0.0.1.0' -ErrorAction Stop
        if ($result.RestartNeeded) { throw 'The tools need a restart before they can be used. Restart Windows, then rerun.' }
    }
}
Import-Module DhcpServer -ErrorAction Stop

function Get-Scopes {
    param([string]$Server)
    try {
        Get-DhcpServerv4Scope -ComputerName $Server -ErrorAction Stop |
            Select-Object -ExpandProperty ScopeId
    } catch {
        throw "Failed to query scopes on $Server. $_"
    }
}

function Get-Exclusions {
    param([string]$Server, [string]$Scope)
    try {
        Get-DhcpServerv4ExclusionRange -ComputerName $Server -ScopeId $Scope -ErrorAction Stop |
            Select-Object @{
                n='ScopeId'; e={ $Scope }
            }, @{
                n='Start';   e={ $_.StartRange }
            }, @{
                n='End';     e={ $_.EndRange }
            }
    } catch {
        # If none exist or the call fails, return empty and warn for real errors
        if ($_.Exception.Message -notmatch 'No items found' -and
            $_.Exception.Message -notmatch 'The specified option does not exist') {
            Write-Warning "Failed to query exclusions on $Server (scope $Scope): $($_.Exception.Message)"
        }
        @()
    }
}

function Add-Exclusion {
    param([string]$Server, [string]$Scope, [string]$Start, [string]$End)
    if ($PSCmdlet.ShouldProcess("$Server scope $Scope", "Add exclusion $Start - $End")) {
        Add-DhcpServerv4ExclusionRange -ComputerName $Server -ScopeId $Scope -StartRange $Start -EndRange $End -ErrorAction Stop
    }
}

Write-Host "Source: $SourceServer  Target: $TargetServer" -ForegroundColor Cyan

# Discover scopes
$srcScopes = Get-Scopes -Server $SourceServer
$tgtScopes = Get-Scopes -Server $TargetServer

# Only process scopes present on both servers
$commonScopes = @($srcScopes) | Where-Object { $_ -in $tgtScopes }

if (-not $commonScopes -or $commonScopes.Count -eq 0) {
    throw "No common IPv4 scopes found between $SourceServer and $TargetServer."
}

Write-Host "Common scopes: $($commonScopes -join ', ')" -ForegroundColor Yellow

foreach ($scope in $commonScopes) {
    Write-Host "----- Scope $scope -----" -ForegroundColor Cyan

    $srcEx = Get-Exclusions -Server $SourceServer -Scope $scope
    $tgtEx = Get-Exclusions -Server $TargetServer -Scope $scope

    # Build pair sets for quick comparison
    $srcPairs = $srcEx | ForEach-Object { "$($_.Start)|$($_.End)" }
    $tgtPairs = $tgtEx | ForEach-Object { "$($_.Start)|$($_.End)" }

    # Add missing exclusions to target
    foreach ($r in $srcEx) {
        $pair = "$($r.Start)|$($r.End)"
        if ($pair -notin $tgtPairs) {
            Write-Verbose "Target missing $($r.Start)-$($r.End); adding"
            try {
                Add-Exclusion -Server $TargetServer -Scope $scope -Start $r.Start -End $r.End
            } catch {
                Write-Warning "Failed to add $($r.Start)-$($r.End) to $TargetServer (scope $scope): $($_.Exception.Message)"
            }
        } else {
            Write-Verbose "Target already has $($r.Start)-$($r.End)"
        }
    }
}

Write-Host "Completed copying DHCP exclusions Source -> Target." -ForegroundColor Green
