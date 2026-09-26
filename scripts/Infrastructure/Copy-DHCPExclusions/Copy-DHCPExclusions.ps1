# Example: .\Copy-DHCPExclusions.ps1 -SourceServer 'SOURCE-DHCP' -TargetServer 'TARGET-DHCP'
# Variables: -SourceServer is the DHCP source; -TargetServer is the destination. Replace both example names.
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
