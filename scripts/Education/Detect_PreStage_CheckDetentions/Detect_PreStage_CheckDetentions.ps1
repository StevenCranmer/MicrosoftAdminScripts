# Example: .\Detect_PreStage_CheckDetentions.ps1
# Variables: No user-supplied variables; this runs in the current account or device context.
# Purpose: Check whether the detention reminder files and startup shortcut are staged.
# Requires: Windows device context with access to C:\ProgramData\CheckDetentions.
# Effect: Read-only check; exit 0 means staged and exit 1 means remediation is needed.
#
# Detect_PreStage_CheckDetentions.ps1
# Exit 0 = compliant, Exit 1 = not compliant (trigger remediation)

$ErrorActionPreference = 'SilentlyContinue'

$Dir = 'C:\ProgramData\CheckDetentions'

# Core payload
$RequiredFiles = @(
    'ShowToast.ps1',
    'LaunchToast.vbs',
    'RegisterMainTask.ps1',
    'SelfHeal.ps1',
    'RunSelfHeal.vbs',

    # Bootstrap payload (instant logon)
    'Register_Teacher_Tasks.ps1',
    'RunUserRegister.vbs'
)

# Startup shortcut deployed by remediation
$StartupDir = Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\Startup'
$ShortcutName = 'BromcomDetentions-RegisterTasks.lnk'
$ShortcutPath = Join-Path $StartupDir $ShortcutName

# 1) Folder exists
if (-not (Test-Path $Dir)) { exit 1 }

# 2) All required files exist
foreach ($f in $RequiredFiles) {
    if (-not (Test-Path (Join-Path $Dir $f))) { exit 1 }
}

# 3) ShowToast.ps1 version check
$ShowToast = Join-Path $Dir 'ShowToast.ps1'
$content = Get-Content $ShowToast -Raw
if ($content -notmatch 'Version:\s*1\.2') { exit 1 }

# 4) Startup shortcut exists
if (-not (Test-Path $ShortcutPath)) { exit 1 }

# 5) Validate shortcut target/args (helps ensure "instant logon" really works)
try {
    $WshShell = New-Object -ComObject WScript.Shell
    $lnk = $WshShell.CreateShortcut($ShortcutPath)

    # Target should be wscript.exe
    $targetOk = ($lnk.TargetPath -match 'wscript\.exe$')

    # Args should reference RunUserRegister.vbs in ProgramData payload folder
    $argsOk = ($lnk.Arguments -match 'RunUserRegister\.vbs') -and ($lnk.Arguments -match 'C:\\ProgramData\\CheckDetentions')

    if (-not ($targetOk -and $argsOk)) { exit 1 }
}
catch {
    # If COM fails or shortcut can't be read, treat as non-compliant
    exit 1
}

exit 0