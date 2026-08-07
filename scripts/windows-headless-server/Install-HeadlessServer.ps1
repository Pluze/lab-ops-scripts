[CmdletBinding()]
param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'Config.example.psd1')
)

$ErrorActionPreference = 'Stop'
$InstallRoot = Join-Path $env:ProgramData 'HeadlessServer'
$TaskPath = '\HeadlessServer\'

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Run this installer once from an elevated PowerShell session.'
    }
}

function Get-DefaultAdapterName {
    $route = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object State -eq 'Alive' | Sort-Object RouteMetric, InterfaceMetric | Select-Object -First 1
    if (-not $route) { throw 'No active default IPv4 route was found.' }
    (Get-NetAdapter -InterfaceIndex $route.InterfaceIndex -ErrorAction Stop).Name
}

function Assert-Config([hashtable]$Config) {
    foreach ($port in @('RdpPort', 'SshPort')) {
        if ([int]$Config[$port] -lt 1 -or [int]$Config[$port] -gt 65535) { throw "$port must be between 1 and 65535." }
    }
    if ([int]$Config.WatchdogIntervalMinutes -lt 1) { throw 'WatchdogIntervalMinutes must be at least 1.' }
    if ([int]$Config.NetworkFailureThreshold -lt 1) { throw 'NetworkFailureThreshold must be at least 1.' }
    if ($Config.FirewallRemoteAddress -ne 'LocalSubnet') {
        $Config.FirewallRemoteAddress -split ',' | ForEach-Object {
            if ($_ -notmatch '^\s*(?:\d{1,3}\.){3}\d{1,3}(?:/\d{1,2})?\s*$') {
                throw 'FirewallRemoteAddress must be LocalSubnet or a comma-separated IPv4/CIDR list.'
            }
        }
    }
}

Assert-Administrator
if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Configuration file not found: $ConfigPath" }
$config = Import-PowerShellDataFile -LiteralPath $ConfigPath
Assert-Config $config

$windowsProductName = (Get-ComputerInfo -Property WindowsProductName -ErrorAction SilentlyContinue).WindowsProductName
if ($config.RequireRdpHost -and $windowsProductName -match '\bHome\b') {
    throw "Inbound Microsoft RDP is not supported by $windowsProductName. Use Pro/Enterprise/Education/Server, or set RequireRdpHost to false for SSH-only installation."
}
if (-not (Test-Path -LiteralPath $config.SshDefaultShell -PathType Leaf)) {
    throw "SSH default shell was not found: $($config.SshDefaultShell)"
}

if ([string]::IsNullOrWhiteSpace([string]$config.PrimaryAdapterName)) {
    $config.PrimaryAdapterName = Get-DefaultAdapterName
}
if (-not (Get-NetAdapter -Name $config.PrimaryAdapterName -Physical -ErrorAction SilentlyContinue)) {
    throw "Physical network adapter not found: $($config.PrimaryAdapterName)"
}
if (@($config.SshAllowedUsers).Count -eq 0) {
    $config.SshAllowedUsers = @($env:USERNAME)
}
foreach ($user in @($config.SshAllowedUsers)) {
    if ($user -notmatch '^[A-Za-z0-9_.@\\-]+$') { throw "Unsafe SSH account name: $user" }
}

New-Item -ItemType Directory -Force -Path $InstallRoot, (Join-Path $InstallRoot 'backup'), (Join-Path $InstallRoot 'logs') | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$transcript = Join-Path $InstallRoot "install-$stamp.log"
Start-Transcript -Path $transcript -Force | Out-Null
try {
    $backupRoot = Join-Path $InstallRoot 'backup'
    & powercfg.exe /export (Join-Path $backupRoot "power-$stamp.pow") SCHEME_CURRENT | Out-Null
    & netsh.exe advfirewall export (Join-Path $backupRoot "firewall-$stamp.wfw") | Out-Null
    & reg.exe export 'HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server' (Join-Path $backupRoot "terminal-server-$stamp.reg") /y | Out-Null
    & reg.exe export 'HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services' (Join-Path $backupRoot "terminal-services-policy-$stamp.reg") /y 2>$null

    $sshConfig = Join-Path $env:ProgramData 'ssh\sshd_config'
    if (Test-Path $sshConfig) { Copy-Item $sshConfig (Join-Path $backupRoot "sshd_config-$stamp") -Force }

    $config | Export-Clixml -LiteralPath (Join-Path $InstallRoot 'config.clixml') -Force
    Copy-Item (Join-Path $PSScriptRoot 'Maintain-HeadlessServer.ps1') (Join-Path $InstallRoot 'Maintain.ps1') -Force
    Copy-Item (Join-Path $PSScriptRoot 'Get-HeadlessServerStatus.ps1') (Join-Path $InstallRoot 'Get-Status.ps1') -Force
    Copy-Item (Join-Path $PSScriptRoot 'Uninstall-HeadlessServer.ps1') (Join-Path $InstallRoot 'Uninstall.ps1') -Force

    $capability = Get-WindowsCapability -Online | Where-Object Name -Like 'OpenSSH.Server*' | Select-Object -First 1
    if (-not $capability) { throw 'Windows OpenSSH Server capability is unavailable.' }
    if ($capability.State -ne 'Installed') { Add-WindowsCapability -Online -Name $capability.Name | Out-Null }

    if (-not (Test-Path $sshConfig)) {
        Copy-Item (Join-Path $env:WINDIR 'System32\OpenSSH\sshd_config_default') $sshConfig -Force
    }
    $sshText = Get-Content -LiteralPath $sshConfig -Raw
    $sshText = [regex]::Replace($sshText, '(?ms)^# BEGIN HEADLESS SERVER MANAGED SETTINGS.*?^# END HEADLESS SERVER MANAGED SETTINGS\s*', '')
    # sshd uses the first obtained value. Comment conflicting global directives
    # and insert our block before the first Match section so it applies globally.
    $matchSection = ''
    $firstMatch = [regex]::Match($sshText, '(?im)^Match\s')
    if ($firstMatch.Success) {
        $matchSection = $sshText.Substring($firstMatch.Index)
        $sshText = $sshText.Substring(0, $firstMatch.Index)
    }
    $sshText = [regex]::Replace(
        $sshText,
        '(?im)^(\s*)(PubkeyAuthentication|PasswordAuthentication|PermitEmptyPasswords|AllowUsers|Port)\s+(.+)$',
        '$1# superseded by Headless Server: $2 $3'
    )
    $passwordSetting = if ($config.EnableSshPasswordAuthentication) { 'yes' } else { 'no' }
    $managedSsh = @"

# BEGIN HEADLESS SERVER MANAGED SETTINGS
PubkeyAuthentication yes
PasswordAuthentication $passwordSetting
PermitEmptyPasswords no
AllowUsers $(@($config.SshAllowedUsers) -join ' ')
Port $($config.SshPort)
# END HEADLESS SERVER MANAGED SETTINGS
"@
    Set-Content -LiteralPath $sshConfig -Value ($sshText.TrimEnd() + "`r`n" + $managedSsh + "`r`n" + $matchSection.TrimStart()) -Encoding ascii
    New-Item -Path 'HKLM:\SOFTWARE\OpenSSH' -Force | Out-Null
    New-ItemProperty -Path 'HKLM:\SOFTWARE\OpenSSH' -Name DefaultShell -PropertyType String -Value $config.SshDefaultShell -Force | Out-Null
    & (Join-Path $env:WINDIR 'System32\OpenSSH\ssh-keygen.exe') -A
    & (Join-Path $env:WINDIR 'System32\OpenSSH\sshd.exe') -t
    if ($LASTEXITCODE -ne 0) { throw 'OpenSSH configuration validation failed.' }
    Set-Service sshd -StartupType Automatic
    if ((Get-Service sshd).Status -eq 'Running') { Restart-Service sshd -Force } else { Start-Service sshd }

    & (Join-Path $InstallRoot 'Maintain.ps1') -Mode Install

    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable `
        -MultipleInstances IgnoreNew -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
    $taskPrincipal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $startupAction = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "C:\ProgramData\HeadlessServer\Maintain.ps1" -Mode Startup'
    $startupTrigger = New-ScheduledTaskTrigger -AtStartup
    $startupTrigger.Delay = "PT$([int]$config.StartupDelaySeconds)S"
    Register-ScheduledTask -TaskPath $TaskPath -TaskName Startup -Action $startupAction -Trigger $startupTrigger -Settings $settings -Principal $taskPrincipal -Force | Out-Null

    $watchAction = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "C:\ProgramData\HeadlessServer\Maintain.ps1" -Mode Watchdog'
    $watchTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes ([int]$config.WatchdogIntervalMinutes))
    Register-ScheduledTask -TaskPath $TaskPath -TaskName Watchdog -Action $watchAction -Trigger $watchTrigger -Settings $settings -Principal $taskPrincipal -Force | Out-Null

    & icacls.exe $InstallRoot /inheritance:r /grant:r 'SYSTEM:(OI)(CI)F' 'Administrators:(OI)(CI)F' 'Users:(OI)(CI)RX' | Out-Null
    & (Join-Path $InstallRoot 'Get-Status.ps1')
    Write-Host "Installed. Runtime files and audit output: $InstallRoot"
}
finally {
    Stop-Transcript | Out-Null
}
