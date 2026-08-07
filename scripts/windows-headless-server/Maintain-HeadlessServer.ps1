[CmdletBinding()]
param(
    [ValidateSet('Install', 'Startup', 'Watchdog', 'Manual')]
    [string]$Mode = 'Watchdog'
)

$ErrorActionPreference = 'Stop'
$root = Join-Path $env:ProgramData 'HeadlessServer'
$configPath = Join-Path $root 'config.clixml'
if (-not (Test-Path $configPath)) { throw "Installed configuration is missing: $configPath" }
$config = Import-Clixml -LiteralPath $configPath
$logPath = Join-Path $root 'logs\maintain.log'
$failurePath = Join-Path $root 'network-failures.txt'
$statusPath = Join-Path $root 'status.json'

function Write-Log([string]$Level, [string]$Message) {
    Add-Content -LiteralPath $logPath -Encoding utf8 -Value ('{0} [{1}] [{2}] {3}' -f (Get-Date -Format s), $Mode, $Level, $Message)
}

function Set-ManagedFirewallRule([string]$Name, [string]$Protocol, [int]$Port) {
    $rule = Get-NetFirewallRule -DisplayName $Name -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $rule) {
        New-NetFirewallRule -DisplayName $Name -Direction Inbound -Action Allow -Profile Private -Protocol $Protocol -LocalPort $Port -RemoteAddress $config.FirewallRemoteAddress | Out-Null
    } else {
        $rule | Set-NetFirewallRule -Enabled True -Direction Inbound -Action Allow -Profile Private
        $rule | Get-NetFirewallAddressFilter | Set-NetFirewallAddressFilter -RemoteAddress $config.FirewallRemoteAddress
        $rule | Get-NetFirewallPortFilter | Set-NetFirewallPortFilter -Protocol $Protocol -LocalPort $Port
    }
}

function Test-AdministratorOrSystem {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) -or $identity.IsSystem
}

if (-not (Test-AdministratorOrSystem)) { throw 'Run elevated or through the installed SYSTEM scheduled task.' }
New-Item -ItemType Directory -Force -Path (Split-Path $logPath) | Out-Null
if ((Test-Path $logPath) -and (Get-Item $logPath).Length -gt 2MB) { Move-Item $logPath "$logPath.previous" -Force }
$mutex = [Threading.Mutex]::new($false, 'Global\HeadlessServerMaintain')
if (-not $mutex.WaitOne(0)) { exit 0 }

try {
    Write-Log INFO 'Maintenance pass started.'
    foreach ($serviceName in @('Dhcp', 'NlaSvc', 'TermService', 'sshd')) {
        if (Get-Service $serviceName -ErrorAction SilentlyContinue) {
            Set-Service $serviceName -StartupType Automatic
            Start-Service $serviceName -ErrorAction SilentlyContinue
            & sc.exe failure $serviceName reset= 86400 actions= restart/5000/restart/10000/restart/30000 | Out-Null
        }
    }
    if ((Get-NetAdapter -Name $config.PrimaryAdapterName).NdisPhysicalMedium -eq 9 -and (Get-Service WlanSvc -ErrorAction SilentlyContinue)) {
        Set-Service WlanSvc -StartupType Automatic
        Start-Service WlanSvc
        & netsh.exe wlan set autoconfig enabled=yes interface="$($config.PrimaryAdapterName)" | Out-Null
        & netsh.exe wlan set randomization enabled=no interface="$($config.PrimaryAdapterName)" | Out-Null
        if (-not [string]::IsNullOrWhiteSpace([string]$config.WifiProfile)) {
            & netsh.exe wlan set profileparameter name="$($config.WifiProfile)" interface="$($config.PrimaryAdapterName)" ConnectionMode=auto Randomization=no | Out-Null
        }
    }

    Get-NetConnectionProfile -InterfaceAlias $config.PrimaryAdapterName -ErrorAction SilentlyContinue |
        Where-Object NetworkCategory -ne DomainAuthenticated |
        Set-NetConnectionProfile -NetworkCategory Private

    $tsRoot = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'
    $rdpTcp = Join-Path $tsRoot 'WinStations\RDP-Tcp'
    $tsPolicy = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services'
    New-Item $tsPolicy -Force | Out-Null
    Set-ItemProperty $tsRoot fDenyTSConnections 0 -Type DWord
    Set-ItemProperty $rdpTcp PortNumber ([int]$config.RdpPort) -Type DWord
    Set-ItemProperty $rdpTcp UserAuthentication 1 -Type DWord
    Set-ItemProperty $rdpTcp SecurityLayer 2 -Type DWord
    Set-ItemProperty $rdpTcp MinEncryptionLevel 3 -Type DWord
    New-ItemProperty $tsPolicy KeepAliveEnable -PropertyType DWord -Value 1 -Force | Out-Null
    New-ItemProperty $tsPolicy KeepAliveInterval -PropertyType DWord -Value 1 -Force | Out-Null
    New-ItemProperty $tsPolicy MaxIdleTime -PropertyType DWord -Value 0 -Force | Out-Null
    New-ItemProperty $tsPolicy MaxDisconnectionTime -PropertyType DWord -Value 0 -Force | Out-Null

    Set-ManagedFirewallRule 'Headless Server - RDP TCP' TCP ([int]$config.RdpPort)
    Set-ManagedFirewallRule 'Headless Server - RDP UDP' UDP ([int]$config.RdpPort)
    Set-ManagedFirewallRule 'Headless Server - SSH TCP' TCP ([int]$config.SshPort)
    if ($config.EnableIcmpEcho) {
        $icmpRule = Get-NetFirewallRule -DisplayName 'Headless Server - ICMPv4 Echo' -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $icmpRule) {
            New-NetFirewallRule -DisplayName 'Headless Server - ICMPv4 Echo' -Direction Inbound -Action Allow -Profile Private -Protocol ICMPv4 -IcmpType 8 -RemoteAddress $config.FirewallRemoteAddress | Out-Null
        } else {
            $icmpRule | Set-NetFirewallRule -Enabled True -Direction Inbound -Action Allow -Profile Private
            $icmpRule | Get-NetFirewallAddressFilter | Set-NetFirewallAddressFilter -RemoteAddress $config.FirewallRemoteAddress
        }
    } else {
        Get-NetFirewallRule -DisplayName 'Headless Server - ICMPv4 Echo' -ErrorAction SilentlyContinue | Disable-NetFirewallRule
    }

    if ($config.PreventAcSleep) {
        & powercfg.exe /change standby-timeout-ac 0 | Out-Null
        & powercfg.exe /change disk-timeout-ac 0 | Out-Null
        & powercfg.exe /setacvalueindex SCHEME_CURRENT SUB_PCIEXPRESS ASPM 0 | Out-Null
    }
    if ($config.DisableHibernate) { & powercfg.exe /hibernate off | Out-Null }
    if ($config.DisableFastStartup) {
        Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' HiberbootEnabled 0 -Type DWord
    }
    Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl' AutoReboot 1 -Type DWord

    if ($config.EnableWake -and $Mode -ne 'Watchdog') {
        $programmable = @(& powercfg.exe /devicequery wake_programmable)
        foreach ($adapter in Get-NetAdapter -Physical -ErrorAction SilentlyContinue) {
            foreach ($device in $programmable | Where-Object { $_ -like "*$($adapter.InterfaceDescription)*" -or $adapter.InterfaceDescription -like "*$_*" }) {
                & powercfg.exe /deviceenablewake $device | Out-Null
            }
            foreach ($keyword in @('*WakeOnMagicPacket', '*WakeOnPattern')) {
                if (Get-NetAdapterAdvancedProperty -Name $adapter.Name -RegistryKeyword $keyword -ErrorAction SilentlyContinue) {
                    Set-NetAdapterAdvancedProperty -Name $adapter.Name -RegistryKeyword $keyword -RegistryValue 1 -NoRestart -ErrorAction SilentlyContinue
                }
            }
        }
    }

    $ip = Get-NetIPConfiguration -InterfaceAlias $config.PrimaryAdapterName -ErrorAction SilentlyContinue
    $healthy = [bool]($ip.IPv4Address -and $ip.IPv4DefaultGateway)
    $failures = if (Test-Path $failurePath) { [int](Get-Content $failurePath | Select-Object -First 1) } else { 0 }
    if ($healthy) { $failures = 0 } else { $failures++ }
    if (-not $healthy -and $config.EnableNetworkRecovery) {
        Write-Log WARN "Network check failed ($failures/$($config.NetworkFailureThreshold))."
        if (-not [string]::IsNullOrWhiteSpace([string]$config.WifiProfile)) {
            & netsh.exe wlan connect name="$($config.WifiProfile)" interface="$($config.PrimaryAdapterName)" | Out-Null
        }
        if ($failures -ge [int]$config.NetworkFailureThreshold) {
            Restart-NetAdapter -Name $config.PrimaryAdapterName -Confirm:$false -ErrorAction SilentlyContinue
            $failures = 0
        }
    }
    Set-Content $failurePath $failures -Encoding ascii

    $adapter = Get-NetAdapter -Name $config.PrimaryAdapterName -ErrorAction SilentlyContinue
    $status = [ordered]@{
        Timestamp = (Get-Date).ToString('o'); Mode = $Mode
        Adapter = $config.PrimaryAdapterName; AdapterStatus = $adapter.Status.ToString()
        IPv4 = @($ip.IPv4Address.IPAddress); Gateway = @($ip.IPv4DefaultGateway.NextHop)
        NetworkHealthy = $healthy
        RdpService = (Get-Service TermService).Status.ToString()
        RdpListening = [bool](Get-NetTCPConnection -State Listen -LocalPort $config.RdpPort -ErrorAction SilentlyContinue)
        SshService = (Get-Service sshd -ErrorAction SilentlyContinue).Status.ToString()
        SshListening = [bool](Get-NetTCPConnection -State Listen -LocalPort $config.SshPort -ErrorAction SilentlyContinue)
        WakeArmed = @(& powercfg.exe /devicequery wake_armed)
    }
    $status | ConvertTo-Json -Depth 4 | Set-Content "$statusPath.tmp" -Encoding utf8
    Move-Item "$statusPath.tmp" $statusPath -Force
    Write-Log INFO "Maintenance pass completed; network=$healthy, RDP=$($status.RdpListening), SSH=$($status.SshListening)."
}
catch {
    Write-Log ERROR $_.Exception.ToString()
    throw
}
finally {
    try { $mutex.ReleaseMutex() } catch {}
    $mutex.Dispose()
}
