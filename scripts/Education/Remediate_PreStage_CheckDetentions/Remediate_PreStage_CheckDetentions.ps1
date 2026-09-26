# Example: .\Remediate_PreStage_CheckDetentions.ps1
# Variables: No user-supplied variables; this runs in the current account or device context.
#
# Remediate_PreStage_CheckDetentions.ps1
$ErrorActionPreference = 'Stop'

$Dir        = 'C:\ProgramData\CheckDetentions'
$Ps1Path    = Join-Path $Dir 'ShowToast.ps1'
$VbsPath    = Join-Path $Dir 'LaunchToast.vbs'
$RegPath    = Join-Path $Dir 'RegisterMainTask.ps1'
$HealPath   = Join-Path $Dir 'SelfHeal.ps1'
$RunHealVbs = Join-Path $Dir 'RunSelfHeal.vbs'

if (-not (Test-Path $Dir)) {
    New-Item -ItemType Directory -Path $Dir -Force | Out-Null
}

# -------------------------
# ShowToast.ps1
# -------------------------
$toastPs1 = @'
param(
  [switch]$EnableFirstDaySafeguard = $false,
  [string]$StartTime = "13:05",
  [int]$WindowMinutes = 15
)
# Version: 1.2 (2026-02-09)
$ErrorActionPreference = "SilentlyContinue"

function Test-WithinWindow {
  param([string]$hhmm,[int]$mins)
  try {
    $anchor = [DateTime]::ParseExact($hhmm,'HH:mm',$null)
    $today  = Get-Date
    $start  = (Get-Date -Hour $anchor.Hour -Minute $anchor.Minute -Second 0)
    $end    = $start.AddMinutes($mins)
    return ($today -ge $start -and $today -le $end)
  } catch { return $false }
}

[Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null
[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null

$AppId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'

$flagDir = Join-Path $env:APPDATA 'CheckDetentions'
$null = New-Item $flagDir -ItemType Directory -Force -ErrorAction SilentlyContinue
$flag = Join-Path $flagDir ('shown-' + (Get-Date).ToString('yyyyMMdd') + '.flag')

$calledAtLogon = $env:__CALLED_AT_LOGON -eq '1'
if ($EnableFirstDaySafeguard -and $calledAtLogon -and -not (Test-WithinWindow -hhmm $StartTime -mins $WindowMinutes)) { return }
if (Test-Path $flag) { return }

$xml = @"
<toast scenario="reminder">
  <visual>
    <binding template="ToastGeneric">
      <text>Reminder: Check detention lists</text>
      <text>Please review today's detentions in Bromcom.</text>
    </binding>
  </visual>
  <audio silent="true"/>
  <actions>
    <action content="Open Bromcom" activationType="protocol"
      arguments="https://cloudmis.bromcom.com/Nucleus/UI/Areas/Framework/Routines.aspx?page=BHVDETN" />
  </actions>
</toast>
"@

$doc = [Windows.Data.Xml.Dom.XmlDocument]::new()
$doc.LoadXml($xml)
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($AppId).Show($doc)

New-Item $flag -ItemType File -Force | Out-Null
'@

if (-not (Test-Path $Ps1Path) -or (Get-Content $Ps1Path -Raw) -ne $toastPs1) {
    $toastPs1 | Out-File $Ps1Path -Encoding UTF8 -Force
}

# -------------------------
# LaunchToast.vbs
# -------------------------
$vbs = @'
Set oShell = CreateObject("Wscript.Shell")
oShell.Environment("PROCESS")("__CALLED_AT_LOGON") = "0"
oShell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -File ""C:\ProgramData\CheckDetentions\ShowToast.ps1""", 0, False
'@
$vbs | Out-File $VbsPath -Encoding ASCII -Force

# -------------------------
# RegisterMainTask.ps1 (defaults to ROOT "\" and removes old folder tasks)
# -------------------------
$registerMain = @'
param(
  [string]$TaskPath = '\',
  [string]$TaskName = 'Check-Detentions-1305'
)

$VbsPath = 'C:\ProgramData\CheckDetentions\LaunchToast.vbs'
if (-not (Test-Path $VbsPath)) { return }

# Clean up old location to prevent duplicates
$OldTaskPath = '\School\Reminders\'
try { Unregister-ScheduledTask -TaskName $TaskName -TaskPath $OldTaskPath -Confirm:$false -ErrorAction SilentlyContinue } catch {}

$Sid   = ([System.Security.Principal.WindowsIdentity]::GetCurrent()).User.Value
$start = [DateTime]::Today.AddHours(13).AddMinutes(5).ToString('s')

$xml = @"
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>Daily reminder toast for detention check at 13:05 (user-scoped).</Description>
    <Author>$env:USERNAME</Author>
  </RegistrationInfo>
  <Triggers>
    <CalendarTrigger>
      <StartBoundary>$start</StartBoundary>
      <Enabled>true</Enabled>
      <ScheduleByWeek>
        <DaysOfWeek><Monday /><Tuesday /><Wednesday /><Thursday /><Friday /></DaysOfWeek>
        <WeeksInterval>1</WeeksInterval>
      </ScheduleByWeek>
    </CalendarTrigger>
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
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <UseUnifiedSchedulingEngine>true</UseUnifiedSchedulingEngine>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT30M</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>%SystemRoot%\System32\wscript.exe</Command>
      <Arguments>//nologo "C:\ProgramData\CheckDetentions\LaunchToast.vbs"</Arguments>
    </Exec>
  </Actions>
</Task>
"@

try { Unregister-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -Confirm:$false -ErrorAction SilentlyContinue } catch {}
Register-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -Xml $xml | Out-Null
'@
$registerMain | Out-File $RegPath -Encoding UTF8 -Force

# -------------------------
# SelfHeal.ps1 (defaults to ROOT "\" and repairs main task)
# -------------------------
$selfHeal = @'
param(
  [string]$TaskPath = '\',
  [string]$TaskName = 'Check-Detentions-1305'
)

$ErrorActionPreference = 'SilentlyContinue'
$RegMain = 'C:\ProgramData\CheckDetentions\RegisterMainTask.ps1'
if (-not (Test-Path $RegMain)) { return }

function Test-MainTask {
  param([string]$TaskPath,[string]$TaskName)

  try { [xml]$x = Export-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName } catch { return $false }

  $Sid = ([System.Security.Principal.WindowsIdentity]::GetCurrent()).User.Value
  $okPrincipal = ($x.Task.Principals.Principal.UserId -eq $Sid)
  $okAction    = ($x.Task.Actions.Exec.Command -match 'wscript\.exe') -and ($x.Task.Actions.Exec.Arguments -match 'LaunchToast\.vbs')

  $okTime = $false
  foreach ($cal in $x.Task.Triggers.CalendarTrigger) {
    if ($cal.StartBoundary) {
      if (([DateTime]$cal.StartBoundary).ToString('HH:mm') -eq '13:05') { $okTime = $true }
    }
  }

  return ($okPrincipal -and $okAction -and $okTime)
}

if (-not (Test-MainTask -TaskPath $TaskPath -TaskName $TaskName)) {
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $RegMain -TaskPath $TaskPath -TaskName $TaskName
}
'@
$selfHeal | Out-File $HealPath -Encoding UTF8 -Force

# -------------------------
# RunSelfHeal.vbs
# -------------------------
$runHeal = @'
Set oShell = CreateObject("Wscript.Shell")
oShell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -File ""C:\ProgramData\CheckDetentions\SelfHeal.ps1""", 0, False
'@
$runHeal | Out-File $RunHealVbs -Encoding ASCII -Force

# =============================================================================
# Instant Logon Bootstrap (All Users Startup) - NO GATING
# =============================================================================
$StartupDir = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup"
$UserRegPs1 = Join-Path $Dir 'Register_Teacher_Tasks.ps1'
$UserRegVbs = Join-Path $Dir 'RunUserRegister.vbs'
$Shortcut   = Join-Path $StartupDir 'BromcomDetentions-RegisterTasks.lnk'

# Script that runs at logon (user context)
$registerUser = @'
$ErrorActionPreference = 'SilentlyContinue'

$Dir = 'C:\ProgramData\CheckDetentions'
$RegMain = Join-Path $Dir 'RegisterMainTask.ps1'
$RunHealVbs = Join-Path $Dir 'RunSelfHeal.vbs'
if (-not (Test-Path $RegMain) -or -not (Test-Path $RunHealVbs)) { exit 0 }

# Migrate away from old folder tasks to root
$OldTaskPath   = '\School\Reminders\'
$NewTaskPath   = '\'
$MainTaskName  = 'Check-Detentions-1305'
$HealTaskName  = 'Check-Detentions-SelfHeal'

foreach ($tn in @($MainTaskName,$HealTaskName)) {
  try { Unregister-ScheduledTask -TaskPath $OldTaskPath -TaskName $tn -Confirm:$false -ErrorAction SilentlyContinue } catch {}
}

# Create/repair main task
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $RegMain -TaskPath $NewTaskPath -TaskName $MainTaskName

# Create/repair self-heal logon task (root)
$Sid = ([System.Security.Principal.WindowsIdentity]::GetCurrent()).User.Value
$xml = @"
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>Self-heal: ensures 13:05 reminder task exists for the current user on every login.</Description>
    <Author>$env:USERNAME</Author>
  </RegistrationInfo>
  <Triggers>
    <LogonTrigger><Enabled>true</Enabled><UserId>$Sid</UserId></LogonTrigger>
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
    <StartWhenAvailable>false</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <UseUnifiedSchedulingEngine>true</UseUnifiedSchedulingEngine>
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
'@
$registerUser | Out-File $UserRegPs1 -Encoding UTF8 -Force

# Hidden VBS launcher for the per-user registration script
$runUserReg = @'
Set oShell = CreateObject("Wscript.Shell")
oShell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -File ""C:\ProgramData\CheckDetentions\Register_Teacher_Tasks.ps1""", 0, False
'@
$runUserReg | Out-File $UserRegVbs -Encoding ASCII -Force

# Create Startup shortcut
if (-not (Test-Path $StartupDir)) { New-Item -ItemType Directory -Path $StartupDir -Force | Out-Null }

$WshShell = New-Object -ComObject WScript.Shell
$lnk = $WshShell.CreateShortcut($Shortcut)
$lnk.TargetPath = "$env:SystemRoot\System32\wscript.exe"
$lnk.Arguments  = "//nologo ""C:\ProgramData\CheckDetentions\RunUserRegister.vbs"""
$lnk.WindowStyle = 7
$lnk.Description = "Registers Bromcom Detention reminder tasks for the current user."
$lnk.Save()

Write-Output "Pre-stage remediation complete."