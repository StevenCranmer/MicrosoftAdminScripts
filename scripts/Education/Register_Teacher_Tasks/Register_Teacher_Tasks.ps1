# Example: .\Register_Teacher_Tasks.ps1
# Variables: No user-supplied variables; this runs in the current account or device context.
#
# Register_Teacher_Tasks.ps1 (fixed)
# Creates (or repairs) the per-user 13:05 task and the per-user SelfHeal-at-logon task.
$ErrorActionPreference = 'Stop'

$Dir        = 'C:\ProgramData\CheckDetentions'
$RegMain    = Join-Path $Dir 'RegisterMainTask.ps1'
$RunHealVbs = Join-Path $Dir 'RunSelfHeal.vbs'

# Wait up to 5 minutes for pre-stage (avoids race condition where script runs "too early")
$deadline = (Get-Date).AddMinutes(5)
while ((Get-Date) -lt $deadline) {
    if ((Test-Path $RegMain) -and (Test-Path $RunHealVbs)) { break }
    Start-Sleep -Seconds 10
}
if (-not (Test-Path $RegMain) -or -not (Test-Path $RunHealVbs)) {
    Write-Output "Pre-stage not ready; exiting (will rely on User Remediation / next run)."
    exit 1
}

# Migrate away from old folder path
$OldTaskPath = '\School\Reminders\'
$NewTaskPath = '\'

$MainTaskName = 'Check-Detentions-1305'
$HealTaskName = 'Check-Detentions-SelfHeal'

foreach ($tp in @($OldTaskPath)) {
    foreach ($tn in @($MainTaskName, $HealTaskName)) {
        try { Unregister-ScheduledTask -TaskPath $tp -TaskName $tn -Confirm:$false -ErrorAction SilentlyContinue } catch {}
    }
}

# 1) Create (or repair) the 13:05 weekdays task in ROOT
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $RegMain -TaskPath $NewTaskPath -TaskName $MainTaskName

# 2) Create (or repair) the per-user SelfHeal logon task in ROOT
$Sid = ([System.Security.Principal.WindowsIdentity]::GetCurrent()).User.Value

$xml = @"
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>Self-heal: ensures 13:05 reminder task exists for the current user on every login.</Description>
    <Author>$env:USERNAME</Author>
  </RegistrationInfo>
  <Triggers>
    <LogonTrigger>
      <Enabled>true</Enabled>
      <UserId>$Sid</UserId>
    </LogonTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>$Sid</UserId>
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>LeastPrivilege</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>false</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <IdleSettings>
      <StopOnIdleEnd>false</StopOnIdleEnd>
      <RestartOnIdle>false</RestartOnIdle>
    </IdleSettings>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <UseUnifiedSchedulingEngine>true</UseUnifiedSchedulingEngine>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT5M</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>%SystemRoot%\System32\wscript.exe</Command>
      <Arguments>//nologo "C:\ProgramData\CheckDetentions\RunSelfHeal.vbs"</Arguments>
    </Exec>
  </Actions>
</Task>
"@

try { Unregister-ScheduledTask -TaskName $HealTaskName -TaskPath $NewTaskPath -Confirm:$false -ErrorAction SilentlyContinue } catch {}
Register-ScheduledTask -TaskName $HealTaskName -TaskPath $NewTaskPath -Xml $xml | Out-Null

exit 0