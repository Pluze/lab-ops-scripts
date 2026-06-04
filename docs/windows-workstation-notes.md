# Windows Workstation Notes

Useful commands and reminders for lab computers.

## Process Checks

List matching processes:

```powershell
Get-Process | Where-Object { $_.ProcessName -like '*name*' }
```

## Device Checks

List camera-like devices:

```powershell
Get-PnpDevice -Class Camera,Image
```

List present USB devices:

```powershell
Get-PnpDevice -PresentOnly | Where-Object { $_.InstanceId -like 'USB*' }
```

Inspect signed driver binding:

```powershell
Get-CimInstance Win32_PnPSignedDriver |
  Where-Object { $_.DeviceName -like '*DEVICE NAME*' } |
  Select-Object DeviceName, DriverProviderName, DriverVersion, InfName
```

## Event Logs

Find recent application hangs:

```powershell
Get-WinEvent -FilterHashtable @{ LogName='Application'; Id=1002 } -MaxEvents 20
```

## Reminder

If one app can use a camera or device and another cannot, the hardware may be
fine. The failure may be in the vendor SDK, DirectShow, TWAIN, GenICam, a service
process, or the application's saved configuration.

