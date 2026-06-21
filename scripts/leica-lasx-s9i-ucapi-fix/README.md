# Leica LAS X S9i UCAPI Fix

Conservative PowerShell fix for Leica LAS X 3.x + Leica S9i/UVC black-screen
failure modes.

This script is not an official Leica Microsystems tool.

## Symptoms

- LAS X detects `Leica S9I Stereozoom`, but Live view is black.
- Windows Camera can show the microscope image, but LAS X cannot.
- LAS X and Windows Camera are both black, but power-cycling the microscope
  restores video.
- LAS X only shows incorrect 4:3 resolution options.
- Normal 16:9 modes such as 1080p or 2160p are missing or unstable.
- Capture, white balance, brightness, or gain controls hang in LAS X.

## Tested Context

- Leica LAS X `3.4.2.18368`
- Leica S9i Stereozoom
- Windows 10
- S9i exposed to LAS X through UCAPI `ucDShow.dll` / UVC / DirectShow

## What It Changes

The script performs three recovery steps. Config files are backed up before any
edit.

### S9i USB/UVC Recovery

It first finds the present S9i camera interface by friendly name, reads its
parent USB device from Windows device properties, and restarts that parent USB
Composite Device. The default fallback USB device ID prefix is:

```text
USB\VID_1711&PID_3004
```

and then runs a hardware scan. By default the script first finds the S9i camera
by friendly name, then reads the camera interface's parent USB device from the
Windows device tree. The USB ID above is only the fallback prefix for Leica S9i.

This can recover the failure mode where Windows still sees the S9i as healthy,
but both LAS X and Windows Camera show black video until the microscope is
power-cycled.

### UCAPI DirectShow Compatibility

It edits:

```text
C:\ProgramData\Leica Microsystems\UCAPI\ucapi-ahmconfig.installed
```

and adds this line inside the `%{ ... }%` block if missing:

```text
UCDSHOW_ACCEPT_UNEXPECTED_FORMAT="1"
```

### LAS X Dynamic Hardware Tree Cleanup

It edits:

```text
C:\ProgramData\Leica Microsystems\LAS X\Calibration Data\DefaultDynamicWidefieldTree.xlhw
```

and removes duplicate UCAPI camera nodes while keeping the first occurrence of
each camera name.

## Usage

```powershell
powershell -ExecutionPolicy Bypass -File .\Fix-LASX-S9i-UCAPI.ps1
```

Optional:

```powershell
powershell -ExecutionPolicy Bypass -File .\Fix-LASX-S9i-UCAPI.ps1 -NoRestart
powershell -ExecutionPolicy Bypass -File .\Fix-LASX-S9i-UCAPI.ps1 -NoPause
powershell -ExecutionPolicy Bypass -File .\Fix-LASX-S9i-UCAPI.ps1 -SkipUsbReset
powershell -ExecutionPolicy Bypass -File .\Fix-LASX-S9i-UCAPI.ps1 -S9iCameraNamePattern "*Leica*S9*" -S9iUsbDeviceIdPrefix "USB\VID_1711&PID_3004"
```

The script requests administrator rights if needed.

## Backup And Restore

Backups are written to:

```text
Documents\Leica-LASX-Repair-Backups\yyyyMMdd-HHmmss\
```

The same files are also copied next to the originals with a timestamped `.bak`
suffix.

See [docs/restore.md](docs/restore.md).

## Technical Notes

See [docs/what-happened.md](docs/what-happened.md).

## License

MIT License. See the repository-level [LICENSE](../../LICENSE).

