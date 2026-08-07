@{
    # Leave blank to select the physical adapter carrying the default IPv4 route.
    PrimaryAdapterName            = ''

    # Optional. Set only when Wi-Fi reconnection should target a known Windows
    # WLAN profile. This file must never contain a Wi-Fi password.
    WifiProfile                   = ''

    # Empty means the account running Install-HeadlessServer.ps1.
    SshAllowedUsers               = @()
    EnableSshPasswordAuthentication = $true
    SshDefaultShell               = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
    RequireRdpHost                = $true

    # Firewall exposure. LocalSubnet is the safe default for a LAN-only host.
    FirewallRemoteAddress         = 'LocalSubnet'
    RdpPort                       = 3389
    SshPort                       = 22
    EnableIcmpEcho                = $true

    EnableNetworkRecovery         = $true
    NetworkFailureThreshold       = 3
    WatchdogIntervalMinutes       = 5
    StartupDelaySeconds           = 30

    EnableWake                    = $true
    DisableHibernate              = $true
    DisableFastStartup            = $true
    PreventAcSleep                = $true
}
