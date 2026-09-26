# Example: .\Detect_User_Tasks.ps1
# Variables: No user-supplied variables; this runs in the current account or device context.
#
# Detect_User_Tasks.ps1
$ErrorActionPreference = 'SilentlyContinue'

$Dir = 'C:\ProgramData\CheckDetentions'
$RegMain = Join-Path $Dir 'RegisterMainTask.ps1'
$RunHealVbs = Join-Path $Dir 'RunSelfHeal.vbs'
$LaunchVbs = Join-Path $Dir 'LaunchToast.vbs'

$MainTaskName = 'Check-Detentions-1305'
$HealTaskName = 'Check-Detentions-SelfHeal'
$OldTaskPath = '\School\Reminders\'
$NewTaskPath = '\'

# Pre-stage must exist (device PR lays this down)
if (-not (Test-Path $RegMain) -or -not (Test-Path $RunHealVbs) -or -not (Test-Path $LaunchVbs)) {
    Write-Output "Pre-stage missing."
    exit 1
}

function Test-TaskExists {
    param([string]$TaskPath,[string]$TaskName)
    try { Get-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction Stop | Out-Null; return $true }
    catch { return $false }
}

# If old tasks exist, mark non-compliant (forces cleanup)
if (Test-TaskExists -TaskPath $OldTaskPath -TaskName $MainTaskName) { exit 1 }
if (Test-TaskExists -TaskPath $OldTaskPath -TaskName $HealTaskName) { exit 1 }

# New tasks must exist
if (-not (Test-TaskExists -TaskPath $NewTaskPath -TaskName $MainTaskName)) { exit 1 }
if (-not (Test-TaskExists -TaskPath $NewTaskPath -TaskName $HealTaskName)) { exit 1 }

# Light validation: main task should call wscript + LaunchToast.vbs
try {
    [xml]$x = Export-ScheduledTask -TaskPath $NewTaskPath -TaskName $MainTaskName
    $cmdOk = ($x.Task.Actions.Exec.Command -match 'wscript\.exe')
    $argOk = ($x.Task.Actions.Exec.Arguments -match 'LaunchToast\.vbs')
    if (-not ($cmdOk -and $argOk)) { exit 1 }
} catch { exit 1 }

# Light validation: selfheal should call wscript + RunSelfHeal.vbs
try {
    [xml]$y = Export-ScheduledTask -TaskPath $NewTaskPath -TaskName $HealTaskName
    $cmdOk = ($y.Task.Actions.Exec.Command -match 'wscript\.exe')
    $argOk = ($y.Task.Actions.Exec.Arguments -match 'RunSelfHeal\.vbs')
    if (-not ($cmdOk -and $argOk)) { exit 1 }
} catch { exit 1 }

Write-Output "Compliant."
exit 0