# Example: .\VS2026-Diagnostics.ps1
# Variables: Set $OutRoot and $ZipPath to the desired output locations.
# Purpose: Collect Visual Studio and system diagnostics into a ZIP.
# Requires: Windows PowerShell with access to system logs and the configured C:\Temp output paths.
# Effect: Replaces existing output folder and ZIP; archive can include user and machine data.
#
$OutRoot = 'C:\Temp\VS2026-Diagnostics'
$ZipPath = 'C:\Temp\VS2026-Diagnostics.zip'

Remove-Item $OutRoot -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $ZipPath -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $OutRoot -Force | Out-Null

# Basic system information
Get-ComputerInfo |
    Out-File "$OutRoot\ComputerInfo.txt" -Width 300

Get-Date |
    Out-File "$OutRoot\CollectionTime.txt"

whoami /all |
    Out-File "$OutRoot\WhoAmI.txt" -Width 300

# Visual Studio Installer and instance information
$VsWhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"

if (Test-Path $VsWhere) {
    & $VsWhere -all -prerelease -products * -format json |
        Out-File "$OutRoot\VSWhere-All.json" -Width 500

    & $VsWhere `
        -products Microsoft.VisualStudio.Product.Community `
        -version '[18.0,19.0)' `
        -latest `
        -property installationPath |
        Out-File "$OutRoot\VSWhere-VS2026-Path.txt"

    & $VsWhere `
        -products Microsoft.VisualStudio.Product.Community `
        -version '[18.0,19.0)' `
        -latest `
        -format json |
        Out-File "$OutRoot\VSWhere-VS2026.json" -Width 500
}
else {
    'vswhere.exe not found' |
        Out-File "$OutRoot\VSWhere-NotFound.txt"
}

# Expected files and directories
$PathsToCheck = @(
    'C:\Program Files\Microsoft Visual Studio\2026\Community'
    'C:\Program Files\Microsoft Visual Studio\2026\Community\Common7\IDE\devenv.exe'
    'C:\Program Files (x86)\Microsoft Visual Studio\Installer'
    'C:\ProgramData\Microsoft\VisualStudio\Packages'
)

$PathChecks = foreach ($Path in $PathsToCheck) {
    [pscustomobject]@{
        Path       = $Path
        Exists     = Test-Path -LiteralPath $Path
        ItemType   = if (Test-Path -LiteralPath $Path) {
            (Get-Item -LiteralPath $Path).GetType().Name
        } else {
            $null
        }
    }
}
$PathChecks | Export-Csv "$OutRoot\PathChecks.csv" -NoTypeInformation

# devenv.exe version
$Devenv = 'C:\Program Files\Microsoft Visual Studio\2026\Community\Common7\IDE\devenv.exe'

if (Test-Path $Devenv) {
    Get-Item $Devenv |
        Select-Object FullName, Length, CreationTime, LastWriteTime,
            @{Name='FileVersion'; Expression={$_.VersionInfo.FileVersion}},
            @{Name='ProductVersion'; Expression={$_.VersionInfo.ProductVersion}} |
        Export-Csv "$OutRoot\Devenv-Version.csv" -NoTypeInformation
}

# Running installer processes
Get-Process -ErrorAction SilentlyContinue |
    Where-Object {
        $_.ProcessName -match 'devenv|setup|vs_|vsinstaller|MicrosoftServiceHub'
    } |
    Select-Object ProcessName, Id, StartTime, Path |
    Export-Csv "$OutRoot\VisualStudio-Processes.csv" -NoTypeInformation

# Pending reboot indicators
$PendingReboot = [ordered]@{
    CBSRebootPending = Test-Path `
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'

    WindowsUpdateRebootRequired = Test-Path `
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'

    PendingFileRenameOperations = Get-ItemProperty `
            'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' `
            -Name PendingFileRenameOperations `
            -ErrorAction SilentlyContinue
    
}

[pscustomobject]$PendingReboot |
    Export-Csv "$OutRoot\PendingReboot.csv" -NoTypeInformation

# Disk space
Get-Volume |
    Select-Object DriveLetter, FileSystemLabel, FileSystem,
        @{Name='SizeGB'; Expression={[math]::Round($_.Size / 1GB, 2)}},
        @{Name='FreeGB'; Expression={[math]::Round($_.SizeRemaining / 1GB, 2)}} |
    Export-Csv "$OutRoot\DiskSpace.csv" -NoTypeInformation

# Intune Management Extension logs
$ImeLogPath = 'C:\ProgramData\Microsoft\IntuneManagementExtension\Logs'

if (Test-Path $ImeLogPath) {
    $ImeDestination = Join-Path $OutRoot 'IntuneManagementExtension-Logs'
    New-Item -ItemType Directory -Path $ImeDestination -Force | Out-Null

    Get-ChildItem $ImeLogPath -File |
        Where-Object {
            $_.Name -match 'IntuneManagementExtension|AppWorkload|AgentExecutor|AppActionProcessor'
        } |
        Copy-Item -Destination $ImeDestination -Force
}

# Visual Studio setup logs from Windows Temp
$VsLogDestination = Join-Path $OutRoot 'VisualStudio-Setup-Logs'
New-Item -ItemType Directory -Path $VsLogDestination -Force | Out-Null

Get-ChildItem 'C:\Windows\Temp' -File -ErrorAction SilentlyContinue |
    Where-Object {
        $_.Name -match '^dd_|VisualStudio|vs_|dd_setup|dd_bootstrapper'
    } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 100 |
    Copy-Item -Destination $VsLogDestination -Force

# Visual Studio Installer logs under ProgramData, if present
$ProgramDataLogs = @(
    'C:\ProgramData\Microsoft\VisualStudio\Packages\_bootstrapper'
    'C:\ProgramData\Microsoft\VisualStudio\Setup'
)

foreach ($LogPath in $ProgramDataLogs) {
    if (Test-Path $LogPath) {
        $SafeName = ($LogPath -replace '[:\\ ]', '_').Trim('_')
        Copy-Item $LogPath `
            -Destination "$OutRoot\$SafeName" `
            -Recurse `
            -Force `
            -ErrorAction SilentlyContinue
    }
}

# Relevant event log entries from the last seven days
$StartTime = (Get-Date).AddDays(-7)

Get-WinEvent -FilterHashtable @{
    LogName   = 'Application'
    StartTime = $StartTime
} -ErrorAction SilentlyContinue |
    Where-Object {
        $_.ProviderName -match 'MsiInstaller|Visual Studio|Application Error' -or
        $_.Message -match 'Visual Studio|devenv|vs_Community'
    } |
    Select-Object TimeCreated, ProviderName, Id, LevelDisplayName, Message |
    Export-Csv "$OutRoot\ApplicationEvents.csv" -NoTypeInformation

# Compress everything
Compress-Archive -Path "$OutRoot\*" -DestinationPath $ZipPath -Force

Write-Output "Created: $ZipPath"
``
