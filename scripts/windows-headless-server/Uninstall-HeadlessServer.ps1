[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$RestoreBackups
)

$ErrorActionPreference = 'Stop'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run as Administrator.' }
$root = Join-Path $env:ProgramData 'HeadlessServer'
$backup = Join-Path $root 'backup'

if ($PSCmdlet.ShouldProcess('HeadlessServer scheduled tasks and firewall rules', 'Remove')) {
    Unregister-ScheduledTask -TaskPath '\HeadlessServer\' -TaskName Startup -Confirm:$false -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskPath '\HeadlessServer\' -TaskName Watchdog -Confirm:$false -ErrorAction SilentlyContinue
    Get-NetFirewallRule -DisplayName 'Headless Server -*' -ErrorAction SilentlyContinue | Remove-NetFirewallRule
}

if ($RestoreBackups -and $PSCmdlet.ShouldProcess('latest saved system configuration', 'Restore')) {
    $firewall = Get-ChildItem $backup -Filter 'firewall-*.wfw' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $terminal = Get-ChildItem $backup -Filter 'terminal-server-*.reg' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $policy = Get-ChildItem $backup -Filter 'terminal-services-policy-*.reg' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $power = Get-ChildItem $backup -Filter 'power-*.pow' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $ssh = Get-ChildItem $backup -Filter 'sshd_config-*' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($firewall) { & netsh.exe advfirewall import $firewall.FullName | Out-Null }
    if ($terminal) { & reg.exe import $terminal.FullName | Out-Null }
    if ($policy) { & reg.exe import $policy.FullName | Out-Null }
    if ($power) {
        $guid = [guid]::NewGuid().ToString()
        & powercfg.exe /import $power.FullName $guid | Out-Null
        & powercfg.exe /setactive $guid | Out-Null
    }
    if ($ssh) {
        Copy-Item $ssh.FullName (Join-Path $env:ProgramData 'ssh\sshd_config') -Force
        Restart-Service sshd -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "Automation removed. Logs and backups were retained at $root for manual review or deletion."
