# Example: .\Remediate_User_Tasks.ps1
# Variables: No user-supplied variables; this runs in the current account or device context.
# Purpose: Repair the current user's detention reminder tasks.
# Requires: Run in user context after pre-stage files exist in C:\ProgramData\CheckDetentions.
# Effect: Creates or replaces reminder and self-heal scheduled tasks.
#
foreach ($command in @('Register-ScheduledTask', 'Unregister-ScheduledTask')) {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) { throw "Windows ScheduledTasks command $command is unavailable on this device." }
}

# Remediate_User_Tasks.ps1
$ErrorActionPreference = 'Stop'

$Dir = 'C:\ProgramData\CheckDetentions'
$RegMain = Join-Path $Dir 'RegisterMainTask.ps1'
$RunHealVbs = Join-Path $Dir 'RunSelfHeal.vbs'

$MainTaskName = 'Check-Detentions-1305'
$HealTaskName = 'Check-Detentions-SelfHeal'
$OldTaskPath = '\School\Reminders\'
$NewTaskPath = '\'

if (-not (Test-Path $RegMain) -or -not (Test-Path $RunHealVbs)) {
    Write-Output "Pre-stage not ready - cannot remediate yet."
    exit 1
}

# Remove old tasks to prevent duplicates
foreach ($tn in @($MainTaskName, $HealTaskName)) {
    try { Unregister-ScheduledTask -TaskPath $OldTaskPath -TaskName $tn -Confirm:$false -ErrorAction SilentlyContinue } catch {}
}

# (Re)create main 13:05 task in ROOT
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $RegMain -TaskPath $NewTaskPath -TaskName $MainTaskName

# (Re)create SelfHeal logon task in ROOT
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

Write-Output "Remediation complete."
exit 0