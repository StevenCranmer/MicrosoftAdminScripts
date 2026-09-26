# Example: .\StaffLicensedAccountsExport.ps1
# Variables: Set $OutputPath to the destination CSV before running.
#
# Staff-licensed account review export
# Run in PowerShell after Connect-MgGraph.

$OutputPath = "C:\Temp\StaffLicensedAccounts.csv"
New-Item -Path "C:\Temp" -ItemType Directory -Force | Out-Null

# Build lookup of licence SKU IDs to readable SKU names.
$skuLookup = @{}
Get-MgSubscribedSku -All | ForEach-Object {
    $skuLookup[$_.SkuId.ToString()] = $_.SkuPartNumber
}

# Get the account and licensing fields required for the report.
$users = Get-MgUser -All -Property Id,DisplayName,UserPrincipalName,Mail,AccountEnabled,UserType,JobTitle,Department,CompanyName,EmployeeId,CreatedDateTime,AssignedLicenses,LicenseAssignmentStates

$report = foreach ($user in $users) {
    $allLicenceNames = @(
        foreach ($licence in $user.AssignedLicenses) {
            $skuId = $licence.SkuId.ToString()
            if ($skuLookup.ContainsKey($skuId)) {
                $skuLookup[$skuId]
            }
            else {
                $skuId
            }
        }
    )

    # Staff-related licences in this tenant use FACULTY in the SKU name.
    $facultyLicenceNames = @(
        $allLicenceNames | Where-Object { $_ -match 'FACULTY' }
    )

    if ($facultyLicenceNames.Count -gt 0) {
        $assignmentTypes = @()
        $assigningGroupIds = @()
        $licenceStates = @()
        $licenceErrors = @()

        foreach ($state in $user.LicenseAssignmentStates) {
            $stateSkuId = $state.SkuId.ToString()
            $stateSkuName = $skuLookup[$stateSkuId]

            if ($stateSkuName -match 'FACULTY') {
                if ($null -eq $state.AssignedByGroup -or $state.AssignedByGroup -eq '') {
                    $assignmentTypes += 'Direct'
                }
                else {
                    $assignmentTypes += 'Group'
                    $assigningGroupIds += $state.AssignedByGroup
                }

                if ($null -ne $state.State -and $state.State -ne '') {
                    $licenceStates += $state.State
                }

                if ($null -ne $state.Error -and $state.Error -ne '') {
                    $licenceErrors += $state.Error
                }
            }
        }

        $nonStoreFacultyLicences = @(
            $facultyLicenceNames | Where-Object { $_ -notmatch '^WSFB_' }
        )

        [PSCustomObject]@{
            DisplayName                   = $user.DisplayName
            UserPrincipalName             = $user.UserPrincipalName
            Mail                          = $user.Mail
            AccountEnabled                = $user.AccountEnabled
            UserType                      = $user.UserType
            JobTitle                      = $user.JobTitle
            Department                    = $user.Department
            CompanyName                   = $user.CompanyName
            EmployeeId                    = $user.EmployeeId
            CreatedDate                   = $user.CreatedDateTime
            FacultyLicences               = (($facultyLicenceNames | Sort-Object -Unique) -join '; ')
            AllLicences                   = (($allLicenceNames | Sort-Object -Unique) -join '; ')
            AssignmentType                = (($assignmentTypes | Sort-Object -Unique) -join '; ')
            AssigningGroupIds             = (($assigningGroupIds | Sort-Object -Unique) -join '; ')
            LicenceState                  = (($licenceStates | Sort-Object -Unique) -join '; ')
            LicenceErrors                 = (($licenceErrors | Sort-Object -Unique) -join '; ')
            HasNonStoreFacultyLicence     = ($nonStoreFacultyLicences.Count -gt 0)
            ReviewNotes                   = ''
            ProposedAction                = ''
        }
    }
}

if ($report.Count -eq 0) {
    Write-Warning 'No accounts matched a licence SKU containing FACULTY. No CSV was written.'
}
else {
    $report |
        Sort-Object Department,DisplayName |
        Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8

    Write-Host "Exported $($report.Count) accounts to $OutputPath"
    Get-Item $OutputPath | Select-Object FullName,Length
}
