Add-Type @"
using System;
using System.Runtime.InteropServices;
public class SleepUtil {
    [DllImport("kernel32.dll")]
    public static extern uint SetThreadExecutionState(uint esFlags);
}
"@

Write-Host "Keeping system awake... Press Ctrl+C to stop."

# Build flags using decimal to avoid Int32->UInt32 casting issues
$ES_CONTINUOUS       = [uint32]2147483648   # 0x80000000
$ES_DISPLAY_REQUIRED = [uint32]2            # 0x00000002
$flags = $ES_CONTINUOUS -bor $ES_DISPLAY_REQUIRED

while ($true) {
    [SleepUtil]::SetThreadExecutionState($flags) | Out-Null
    Start-Sleep -Seconds 30
}
