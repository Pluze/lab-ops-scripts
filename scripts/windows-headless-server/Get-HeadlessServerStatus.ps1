[CmdletBinding()]
param()

$root = Join-Path $env:ProgramData 'HeadlessServer'
$statusPath = Join-Path $root 'status.json'
$result = [ordered]@{
    Installed = Test-Path (Join-Path $root 'config.clixml')
    Status = if (Test-Path $statusPath) { Get-Content $statusPath -Raw | ConvertFrom-Json } else { $null }
    StartupTask = Get-ScheduledTaskInfo -TaskPath '\HeadlessServer\' -TaskName Startup -ErrorAction SilentlyContinue
    WatchdogTask = Get-ScheduledTaskInfo -TaskPath '\HeadlessServer\' -TaskName Watchdog -ErrorAction SilentlyContinue
    Firmware = Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue | Select-Object Manufacturer, SMBIOSBIOSVersion
    WindowsEdition = (Get-ComputerInfo -Property WindowsProductName -ErrorAction SilentlyContinue).WindowsProductName
    RdpSupported = -not ((Get-ComputerInfo -Property WindowsProductName -ErrorAction SilentlyContinue).WindowsProductName -match '\bHome\b')
}
$result | ConvertTo-Json -Depth 6
