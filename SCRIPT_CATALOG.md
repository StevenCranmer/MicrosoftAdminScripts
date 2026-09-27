# Script catalog

Choose a script by task, then open it and read its first comment lines before running it. Each script documents its prerequisites, editable values, and effects. Example input files sit beside the scripts that use them.

## Deployment notes

- [RemovePrimaryUserLoop.ps1](scripts/Intune/RemovePrimaryUserLoop/RemovePrimaryUserLoop.ps1) calls two Intune commands that are not supplied in this repository. It stops with an explanation if they are unavailable; the neighbouring `RemoveDeviceGroupPrimaryUsers.ps1` uses Microsoft Graph instead.
- The Edge and Teams desktop shortcut detectors return exit 0 when duplicates exist. Their remediation scripts delete shortcuts when duplicates exist. Check the exit-code rule in your deployment platform before pairing them.
- The shutdown-task and OMA restart-task detectors query scheduled tasks without setting an explicit compliance exit code. Review that behaviour before using them as Intune detection scripts.


## ActiveDirectory

| Script | What it does | Effect or output |
| --- | --- | --- |
| [Remove-ADUsersFromCSV](scripts/ActiveDirectory/Remove-ADUsersFromCSV/Remove-ADUsersFromCSV.ps1) | Disable or delete AD users listed by UPN in a CSV. | Writes a transcript log; without -DisableOnly it can delete accounts. Use -WhatIf first. |
| [UpdateGroupOfficeLocationAD](scripts/ActiveDirectory/UpdateGroupOfficeLocationAD/UpdateGroupOfficeLocationAD.ps1) | Set the Office field for user members of an AD group. | Changes each matching user's AD Office field; no preview switch is provided. |
| [UserImport](scripts/ActiveDirectory/UserImport/UserImport.ps1) | Create AD user accounts from a CSV. | Creates enabled accounts using CSV passwords; protect the input file and review OU values. |

## Education

| Script | What it does | Effect or output |
| --- | --- | --- |
| [Detect_PreStage_CheckDetentions](scripts/Education/Detect_PreStage_CheckDetentions/Detect_PreStage_CheckDetentions.ps1) | Check whether the detention reminder files and startup shortcut are staged. | Read-only check; exit 0 means staged and exit 1 means remediation is needed. |
| [Detect_User_Tasks](scripts/Education/Detect_User_Tasks/Detect_User_Tasks.ps1) | Check the current user's detention reminder scheduled tasks. | Read-only check; reports compliance through its output and exit code. |
| [Export-Year12Year13AllCreatedDates-Fixed](scripts/Education/Export-Year12Year13AllCreatedDates-Fixed/Export-Year12Year13AllCreatedDates-Fixed.ps1) | Report account creation dates for two configured year-group IDs. | Writes a CSV containing user details; keep real exports outside this repository. |
| [Export-Year12Year13TutorGroupMemberships](scripts/Education/Export-Year12Year13TutorGroupMemberships/Export-Year12Year13TutorGroupMemberships.ps1) | Report membership of the configured tutor groups. | Writes a CSV containing user details; check the hard-coded year suffix before use. |
| [Fix-BromcomWelcomeEmails](scripts/Education/Fix-BromcomWelcomeEmails/Fix-BromcomWelcomeEmails.ps1) | Disable welcome messages for matching Microsoft 365 groups. | The preview is followed immediately by changes and a CSV report; there is no confirmation prompt. |
| [Register_Teacher_Tasks](scripts/Education/Register_Teacher_Tasks/Register_Teacher_Tasks.ps1) | Register detention reminder tasks for the current user. | Creates or repairs scheduled tasks for a 13:05 reminder and self-heal at logon. |
| [Remediate_PreStage_CheckDetentions](scripts/Education/Remediate_PreStage_CheckDetentions/Remediate_PreStage_CheckDetentions.ps1) | Stage detention reminder scripts, launchers, and startup registration. | Creates files and a startup shortcut; review the embedded Bromcom URL and schedule. |
| [Remediate_User_Tasks](scripts/Education/Remediate_User_Tasks/Remediate_User_Tasks.ps1) | Repair the current user's detention reminder tasks. | Creates or replaces reminder and self-heal scheduled tasks. |

## FileUtilities

| Script | What it does | Effect or output |
| --- | --- | --- |
| [convert_msg_archive](scripts/FileUtilities/convert_msg_archive/convert_msg_archive.py) | Convert an Outlook MSG archive into browsable HTML pages. | Writes HTML pages, extracted attachments, indexes, and a log under DEST. |
| [msg_subfolders_to_pdf](scripts/FileUtilities/msg_subfolders_to_pdf/msg_subfolders_to_pdf.py) | Create a PDF per MSG subfolder from message content. | Writes PDFs and a log under DEST; attachments are not embedded by this variant. |
| [msg_subfolders_to_pdf_with_attachments](scripts/FileUtilities/msg_subfolders_to_pdf_with_attachments/msg_subfolders_to_pdf_with_attachments.py) | Create a PDF per MSG subfolder, including supported attachments. | Writes PDFs and a log under DEST; may create temporary work files. |

## Infrastructure

| Script | What it does | Effect or output |
| --- | --- | --- |
| [Copy-DHCPExclusions](scripts/Infrastructure/Copy-DHCPExclusions/Copy-DHCPExclusions.ps1) | Copy exclusion ranges across scopes shared by two DHCP servers. | Adds missing ranges on the target server; review both server names first. |
| [WSUSImport](scripts/Infrastructure/WSUSImport/WSUSImport.ps1) | Import one or more Microsoft Update Catalog IDs into WSUS. | Imports updates on the selected WSUS server; the example ID file contains only a dummy ID. |

## Intune

| Script | What it does | Effect or output |
| --- | --- | --- |
| [AudiescreenFirewall](scripts/Intune/AudiescreenFirewall/AudiescreenFirewall.ps1) | Allow the configured AudieScreen executable through Windows Firewall. | Adds inbound and outbound allow rules for that executable. |
| [ChromeDetect](scripts/Intune/ChromeDetect/ChromeDetect.ps1) | Detect Chrome for a removal remediation. | Read-only: exit 1 when Chrome is installed, 0 when absent. |
| [ChromeRemediate](scripts/Intune/ChromeRemediate/ChromeRemediate.ps1) | Uninstall the detected system-level Chrome installation. | Runs Chrome's silent uninstaller for x64 or x86; review before deployment. |
| [ClearTeamsCacheOnLogoff](scripts/Intune/ClearTeamsCacheOnLogoff/ClearTeamsCacheOnLogoff.ps1) | Clear selected classic Teams cache folders for the current user. | Deletes cache folders and TXT files under the configured Teams profile path. |
| [DeletePINconfig-detection](scripts/Intune/DeletePINconfig-detection/detection.ps1) | Detect the Windows Hello PIN configuration folder. | Exit 1 when the folder exists; exit 0 when absent or when detection errors. |
| [DeletePINconfig-remediation](scripts/Intune/DeletePINconfig-remediation/remediation.ps1) | Remove the Windows Hello PIN configuration folder. | Takes ownership and deletes the Ngc folder, affecting enrolled PINs. |
| [DesktopShortcutEdge-detection](scripts/Intune/DesktopShortcutEdge-detection/detection.ps1) | Count Edge shortcuts on the current user's desktop. | Exit 0 when more than one Edge shortcut exists, 1 otherwise; verify this matches your deployment rule. |
| [DesktopShortcutEdge-remediate](scripts/Intune/DesktopShortcutEdge-remediate/remediate.ps1) | Remove Edge desktop shortcuts when duplicates are found. | Deletes every desktop shortcut whose name contains Edge when the count exceeds one. |
| [DesktopShortcutTeams-detection](scripts/Intune/DesktopShortcutTeams-detection/detection.ps1) | Count Teams shortcuts on the current user's desktop. | Exit 0 when more than one Teams shortcut exists, 1 otherwise; verify this matches your deployment rule. |
| [DesktopShortcutTeams-remediate](scripts/Intune/DesktopShortcutTeams-remediate/remediate.ps1) | Remove Teams desktop shortcuts when duplicates are found. | Deletes every desktop shortcut whose name contains Teams when the count exceeds one. |
| [Detect-BlockGuestWiFi](scripts/Intune/Detect-BlockGuestWiFi/Detect-BlockGuestWiFi.ps1) | Check whether a guest SSID is blocked and its saved profile removed. | Read-only: exit 0 when blocked with no saved profile, 1 otherwise. |
| [detect-fastboot](scripts/Intune/detect-fastboot/detect-fastboot.ps1) | Check whether Windows Fast Startup is disabled. | Read-only: exit 0 when HiberbootEnabled is 0, 1 otherwise. |
| [Detect-M365AppUpdate](scripts/Intune/Detect-M365AppUpdate/Detect-M365AppUpdate.ps1) | Compare installed Microsoft 365 Apps version with channel thresholds. | Read-only detection; its thresholds are hard-coded and must be reviewed before deployment. |
| [Detect-PapercutPrintersSystem](scripts/Intune/Detect-PapercutPrintersSystem/Detect-PapercutPrintersSystem.ps1) | Find the configured machine-wide printer queues. | Read-only: exit 1 if matching queues exist, 0 otherwise. |
| [detectOldTeams](scripts/Intune/detectOldTeams/detectOldTeams.ps1) | Check for new Teams when classic Teams is absent. | Read-only: exit 0 when classic is absent and new Teams is present, 1 otherwise. |
| [disableNetbios](scripts/Intune/disableNetbios/disableNetbios.ps1) | Attempt to disable NetBIOS over TCP/IP on network interfaces. | Sets NetbiosOptions to 2 for enumerated interfaces; verify the registry path on your system. |
| [GuestWiFiBlock](scripts/Intune/GuestWiFiBlock/GuestWiFiBlock.ps1) | Add a WLAN block filter for the configured guest SSID. | Adds a network block filter but does not delete saved profiles. |
| [PCshutdownconfigintune-detection](scripts/Intune/PCshutdownconfigintune-detection/detection.ps1) | Query whether the ShutdownPCat6PM task exists. | Read-only query; this script does not define an explicit compliance exit code. |
| [PCshutdownconfigintune-register](scripts/Intune/PCshutdownconfigintune-register/register.ps1) | Register the scheduled shutdown task from its XML file. | Registers a 18:00 shutdown task with a forced shutdown command; review the XML first. |
| [PCshutdownconfigintune-removal](scripts/Intune/PCshutdownconfigintune-removal/removal.ps1) | Remove the ShutdownPCat6PM scheduled task. | Unregisters that task without a confirmation prompt. |
| [Remediate-BlockGuestWiFi](scripts/Intune/Remediate-BlockGuestWiFi/Remediate-BlockGuestWiFi.ps1) | Block a guest SSID and remove its saved Wi-Fi profile. | May disconnect the current Wi-Fi connection and removes matching saved profiles. |
| [remediate-fastboot](scripts/Intune/remediate-fastboot/remediate-fastboot.ps1) | Disable Windows Fast Startup. | Sets HiberbootEnabled to 0. |
| [Remediate-M365AppUpdate](scripts/Intune/Remediate-M365AppUpdate/Remediate-M365AppUpdate.ps1) | Start a Microsoft 365 Apps Click-to-Run update. | Starts OfficeC2RClient.exe and waits for it to finish. |
| [Remediate-PapercutPrintersSystem](scripts/Intune/Remediate-PapercutPrintersSystem/Remediate-PapercutPrintersSystem.ps1) | Remove the configured machine-wide printer queues. | Deletes matching queues; this variant does not remove drivers. |
| [Remediate-PapercutPrintersSystemViolently](scripts/Intune/Remediate-PapercutPrintersSystemViolently/Remediate-PapercutPrintersSystemViolently.ps1) | Remove configured queues, per-user connections, and unused drivers. | Changes printer state across profiles and can delete drivers; use only when that scope is intended. |
| [RemoveDeviceGroupPrimaryUsers](scripts/Intune/RemoveDeviceGroupPrimaryUsers/RemoveDeviceGroupPrimaryUsers.ps1) | Clear Intune primary users for devices in an Entra device group. | Deletes primary-user relationships; use -WhatIf to inspect the target set first. |
| [RemoveOldTeams-remediate](scripts/Intune/RemoveOldTeams-remediate/remediate.ps1) | Uninstall the Teams Machine-Wide Installer package. | Runs msiexec silently; check that the package found is the intended legacy installer. |
| [RemoveOMARestarttask-detection](scripts/Intune/RemoveOMARestarttask-detection/detection.ps1) | Query whether the RebootCSP daily recurrent reboot task exists. | Read-only query; this script does not define an explicit compliance exit code. |
| [RemoveOMARestarttask-remediate](scripts/Intune/RemoveOMARestarttask-remediate/remediate.ps1) | Remove the RebootCSP daily recurrent reboot task. | Unregisters that task without a confirmation prompt. |
| [RemovePrimaryUserLoop](scripts/Intune/RemovePrimaryUserLoop/RemovePrimaryUserLoop.ps1) | Clear Intune primary users from devices matching SHARED-*. | Changes matching device relationships; this script has no preview switch. |
| [SecurityKeyLoginDefaultDetectionImproved](scripts/Intune/SecurityKeyLoginDefaultDetectionImproved/SecurityKeyLoginDefaultDetectionImproved.ps1) | Check whether the specified credential provider is disabled. | Read-only: exit 0 when Disabled equals 1, 1 otherwise. |
| [SecurityKeyLoginDefaultRemediationImproved](scripts/Intune/SecurityKeyLoginDefaultRemediationImproved/SecurityKeyLoginDefaultRemediationImproved.ps1) | Disable the specified credential provider through the registry. | Sets Disabled to 1; confirm this is the desired sign-in change before deployment. |

## Microsoft365

| Script | What it does | Effect or output |
| --- | --- | --- |
| [Archive-TeamsFromCsv](scripts/Microsoft365/Archive-TeamsFromCsv/Archive-TeamsFromCsv.ps1) | Archive Teams listed by TeamId in the CSV. | Shows a target summary and asks for confirmation before archiving. |
| [Delete-TeamsFromCsv](scripts/Microsoft365/Delete-TeamsFromCsv/Delete-TeamsFromCsv.ps1) | Delete Teams listed by TeamId in the CSV. | Shows a target summary and asks for confirmation before deleting Teams. |
| [ExportUserDetailsAAD](scripts/Microsoft365/ExportUserDetailsAAD/ExportUserDetailsAAD.ps1) | Export selected Azure AD user properties to CSV. | Writes Microsoft365Users.csv beside the script; the report contains personal data. |
| [Fix-StudentMailboxPolicy](scripts/Microsoft365/Fix-StudentMailboxPolicy/Fix-StudentMailboxPolicy.ps1) | Apply a named OWA mailbox policy to user members of a Microsoft 365 group. | Changes mailbox policies for matching users; review $groupName and $policyName. |
| [Get-ProfilePhotoChanges](scripts/Microsoft365/Get-ProfilePhotoChanges/Get-ProfilePhotoChanges.ps1) | Find profile-photo change events in the Unified Audit Log. | Writes CSV and raw JSON with account identifiers; keep exports private. |
| [GroupCreators](scripts/Microsoft365/GroupCreators/GroupCreators.ps1) | Set which group may create Microsoft 365 groups. | Changes tenant-wide Group.Unified settings; verify $GroupName and $AllowGroupCreation. |
| [Remove-EntraDeviceOwnership](scripts/Microsoft365/Remove-EntraDeviceOwnership/Remove-EntraDeviceOwnership.ps1) | Remove a named account from Entra device registered-owner links. | Writes an audit CSV; use -DryRun first, since live mode removes owner links. |
| [Remove-PhotoUpdatePolicy](scripts/Microsoft365/Remove-PhotoUpdatePolicy/Remove-PhotoUpdatePolicy.ps1) | Delete the tenant photo-update policy object to restore defaults. | Changes tenant-wide photo settings; users may regain photo-editing ability. |
| [Reset-CloudUserPasswordsFromCsv](scripts/Microsoft365/Reset-CloudUserPasswordsFromCsv/Reset-CloudUserPasswordsFromCsv.ps1) | Reset cloud user passwords from a CSV. | Changes passwords and writes a results CSV beside the input; protect both files. |
| [Set-PhotoUpdatePolicy](scripts/Microsoft365/Set-PhotoUpdatePolicy/Set-PhotoUpdatePolicy.ps1) | Inspect or configure who may update Microsoft 365 profile photos. | ShowCurrent is read-only; other modes change tenant-wide beta policy. Use -WhatIf to preview. |
| [StaffLicensedAccountsExport](scripts/Microsoft365/StaffLicensedAccountsExport/StaffLicensedAccountsExport.ps1) | Export licensed staff account details. | Writes C:\Temp\StaffLicensedAccounts.csv with personal/account data. |
| [Sync-StaffToRoleAssignableGroup](scripts/Microsoft365/Sync-StaffToRoleAssignableGroup/Sync-StaffToRoleAssignableGroup.ps1) | Sync direct user membership from a source group to a role-assignable target. | Adds missing members; optional removal mode deletes extras. Start with -DryRun. |
| [TeamsMemberAudit](scripts/Microsoft365/TeamsMemberAudit/TeamsMemberAudit.ps1) | Audit Team membership, ownership, archive status, and activity. | Writes a CSV report; it may contain names and account identifiers. |
| [Update-GroupJobTitleV4](scripts/Microsoft365/Update-GroupJobTitleV4/Update-GroupJobTitleV4.ps1) | Set JobTitle for direct user members of an Entra group. | Updates user profiles; failures are reported to the console. |
| [Update-GroupOfficeLocationV2](scripts/Microsoft365/Update-GroupOfficeLocationV2/Update-GroupOfficeLocationV2.ps1) | Set OfficeLocation for direct user members of an Entra group. | Updates user profiles; failures are reported to the console. |
| [Update-PasswordsCSV](scripts/Microsoft365/Update-PasswordsCSV/Update-PasswordsCSV.ps1) | Set user passwords from password-resets.csv beside the script. | Changes passwords and forces a change at next sign-in; protect the input CSV. |
| [Wipe-ExamOneDrives](scripts/Microsoft365/Wipe-ExamOneDrives/Wipe-ExamOneDrives.ps1) | Delete root OneDrive items for users in a specified group. | Use -WhatIf first; -PermanentDelete bypasses the recycle bin. |

## Windows

| Script | What it does | Effect or output |
| --- | --- | --- |
| [Configure_WindowsScanning](scripts/Windows/Configure_WindowsScanning/Configure_WindowsScanning.ps1) | Grant a named account Windows scanning permissions for Lansweeper. | Changes WMI, registry, and related access settings; test on a nonproduction device. |
| [VS2026-Diagnostics](scripts/Windows/VS2026-Diagnostics/VS2026-Diagnostics.ps1) | Collect Visual Studio and system diagnostics into a ZIP. | Replaces existing output folder and ZIP; archive can include user and machine data. |
| [Win11Req](scripts/Windows/Win11Req/Win11Req.ps1) | Set the Windows 11 unsupported TPM/CPU upgrade registry value. | Changes upgrade eligibility policy; it does not check hardware compatibility. |

