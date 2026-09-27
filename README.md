# Public scripts

> **Use at your own risk.** These scripts are provided as examples, without warranty or support. Some change or permanently delete users, devices, files, Teams, or configuration. Read the entire script, replace every example value, confirm the target and permissions, and test in a safe environment before using it in production. Keep backups where appropriate. You are responsible for the results in your environment and for protecting any input files or reports containing personal data or credentials. See the [LICENSE](LICENSE) file for the applicable legal terms.

Small administration scripts for Microsoft 365, Intune, Windows, Active Directory, and related tasks. Each script has its own folder. Any sample input or configuration file needed to try it is in that folder.

Browse the [script catalog](SCRIPT_CATALOG.md) to find a task and see what each script changes or produces.

| Folder | Contents |
| --- | --- |
| `scripts/ActiveDirectory` | AD user and group tasks |
| `scripts/Education` | Education system tasks and reports |
| `scripts/FileUtilities` | Outlook message conversion tools |
| `scripts/Infrastructure` | DHCP and WSUS tasks |
| `scripts/Intune` | Device scripts, detection, and remediation |
| `scripts/Microsoft365` | Entra ID, Exchange, Teams, and OneDrive tasks |
| `scripts/Windows` | Windows configuration and diagnostics |

## Using a script

1. Open the script's folder and read the opening comments for a sample command, prerequisites, editable values, and effects. Read the rest of the script before running it, especially for changes or deletions.
2. If the folder has an `.example.csv` or other example file, copy it to a new file and replace all dummy values. Keep files containing real accounts, passwords, or tenant data outside this repository.
3. Run the script from its own folder so relative paths in the example commands resolve there. PowerShell scripts use `./ScriptName.ps1` in PowerShell; Python scripts use `python ./script_name.py`.
4. Run an interactive script. If it needs a missing PowerShell Gallery module, Python package, or Windows administration feature, it will offer to install it and then request the relevant sign-in. Windows feature installation requires an elevated PowerShell session. You can decline and install the prerequisite yourself. Intune detection and remediation scripts run unattended, so they report missing prerequisites without asking questions.

Scripts can change or remove users, devices, teams, files, and settings. Review the target values and use a preview or `-WhatIf` option when the script provides one.

## Contributions and data

This repository is for maintainer-authored scripts. See [REPOSITORY_POLICY.md](REPOSITORY_POLICY.md). Do not add real exports, credentials, tenant identifiers, or third-party scripts. The root `.gitignore` excludes common generated outputs and allows synthetic example CSVs.

## License

These scripts are released under the [GNU General Public License, version 3](LICENSE).
