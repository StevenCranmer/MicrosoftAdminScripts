# Example: .\Remove-ADUsersFromCSV.ps1 -CsvPath .\ad-removals.example.csv -DisableOnly -WhatIf
# Variables: -CsvPath must have UserPrincipalName; -DisableOnly avoids deletion; -MoveToOU chooses the destination OU; -LogPath is the audit log.
# Purpose: Disable or delete AD users listed by UPN in a CSV.
# Requires: ActiveDirectory PowerShell module (RSAT), AD rights, and ad-removals.example.csv as a template.
# Effect: Writes a transcript log; without -DisableOnly it can delete accounts. Use -WhatIf first.
#

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $true)]
    [string]$CsvPath,

    [string]$UpnColumn = 'UserPrincipalName',

    # Safety flags
    [switch]$DisableOnly,          # Disable and/or move, but do not delete
    [string]$MoveToOU,             # e.g., "OU=Disabled Users,OU=Corp,DC=contoso,DC=com"

    # Logging
    [string]$LogPath = ".\Delete-AdUsers-$(Get-Date -Format yyyyMMdd_HHmmss).log"
)

$ErrorActionPreference = 'Stop'

# Windows administration tools are installed as OS features, not from PSGallery.
if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
    $answer = Read-Host "ActiveDirectory tools are missing. Install the Windows administration tools now? [y/N]"
    if ($answer -notmatch '^(?i:y|yes)$') {
        throw "ActiveDirectory tools are required. Install them through Windows optional features or Server Manager, then rerun."
    }
    $isAdministrator = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdministrator) {
        throw 'Installing Windows administration tools requires an elevated PowerShell session. Reopen PowerShell as administrator and rerun.'
    }
    $isServer = (Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).ProductType -ne 1
    if ($isServer) {
        if (-not (Get-Command Install-WindowsFeature -ErrorAction SilentlyContinue)) { throw 'Install-WindowsFeature is unavailable. Install the tools through Server Manager.' }
        $result = Install-WindowsFeature -Name 'RSAT-AD-PowerShell' -ErrorAction Stop
        if (-not $result.Success) { throw 'Windows reported that the feature installation did not succeed.' }
    } else {
        if (-not (Get-Command Add-WindowsCapability -ErrorAction SilentlyContinue)) { throw 'Add-WindowsCapability is unavailable. Install the tools through Windows optional features.' }
        $result = Add-WindowsCapability -Online -Name 'Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0' -ErrorAction Stop
        if ($result.RestartNeeded) { throw 'The tools need a restart before they can be used. Restart Windows, then rerun.' }
    }
}
Import-Module ActiveDirectory -ErrorAction Stop

if (-not (Test-Path -Path $CsvPath)) {
    Write-Error "CSV not found at: $CsvPath"
    return
}

Write-Host "Starting. CSV: $CsvPath | Column: $UpnColumn | DisableOnly: $($DisableOnly.IsPresent) | MoveToOU: $MoveToOU"
Start-Transcript -Path $LogPath -Append | Out-Null

$deleted = [System.Collections.Generic.List[string]]::new()
$disabled = [System.Collections.Generic.List[string]]::new()
$moved    = [System.Collections.Generic.List[string]]::new()
$skipped  = [System.Collections.Generic.List[string]]::new()
$notFound = [System.Collections.Generic.List[string]]::new()

try {
    $rows = Import-Csv -Path $CsvPath

    foreach ($row in $rows) {
        $upn = $row.$UpnColumn
        if ([string]::IsNullOrWhiteSpace($upn)) { continue }

        Write-Host "Processing: $upn"

        # Using -Identity with UPN is reliable and avoids quoting issues in -Filter
        $user = $null
        try {
            $user = Get-ADUser -Identity $upn -Properties MemberOf, DistinguishedName, Enabled -ErrorAction Stop
        } catch {
            # Fallback: try filter in case UPN wasn't recognized as identity
            $user = Get-ADUser -Filter "UserPrincipalName -eq '$upn'" -Properties MemberOf, DistinguishedName, Enabled -ErrorAction SilentlyContinue
        }

        if (-not $user) {
            Write-Warning "Not found in on-prem AD: $upn"
            $notFound.Add($upn)
            continue
        }

        # Basic protection: skip high-privilege accounts
        $isPrivileged = $false
        $privGroupsPattern = 'CN=Domain Admins,|CN=Enterprise Admins,|CN=Schema Admins,|CN=Administrators,'
        if ($user.MemberOf -match $privGroupsPattern) { $isPrivileged = $true }

        if ($isPrivileged) {
            Write-Warning "Skipping protected/high-privilege account: $upn ($($user.DistinguishedName))"
            $skipped.Add($upn)
            continue
        }

        if ($DisableOnly) {
            if ($user.Enabled) {
                if ($PSCmdlet.ShouldProcess($upn, "Disable AD account")) {
                    Disable-ADAccount -Identity $user -WhatIf:$WhatIfPreference
                }
                $disabled.Add($upn)
            } else {
                Write-Host "Already disabled: $upn"
            }
        }

        if ($MoveToOU) {
            if ($PSCmdlet.ShouldProcess($upn, "Move to $MoveToOU")) {
                Move-ADObject -Identity $user.DistinguishedName -TargetPath $MoveToOU -WhatIf:$WhatIfPreference
            }
            $moved.Add($upn)
        }

        if (-not $DisableOnly) {
            if ($PSCmdlet.ShouldProcess($upn, "Delete AD user")) {
                Remove-ADUser -Identity $user -Confirm:$false -WhatIf:$WhatIfPreference
            }
            $deleted.Add($upn)
        }
    }

    Write-Host ""
    Write-Host "==== Summary ===="
    Write-Host "Deleted : $($deleted.Count)"
    Write-Host "Disabled: $($disabled.Count)"
    Write-Host "Moved   : $($moved.Count)"
    Write-Host "Skipped : $($skipped.Count)"
    Write-Host "NotFound: $($notFound.Count)"
}
catch {
    Write-Error $_
}
finally {
    Stop-Transcript | Out-Null
    Write-Host "Log written to: $LogPath"
}
