# Restore Instructions

The repair script creates backups before editing any file. Use these backups if
LAS X behaves worse after the repair or if you want to return to the previous
configuration.

## Backup Locations

Each run creates a timestamped backup folder:

```text
Documents\Leica-LASX-Repair-Backups\yyyyMMdd-HHmmss\
```

The same files are also copied next to the originals with a timestamped suffix:

```text
.bak-yyyyMMdd-HHmmss
```

## Files That May Be Backed Up

UCAPI DirectShow config:

```text
C:\ProgramData\Leica Microsystems\UCAPI\ucapi-ahmconfig.installed
```

LAS X dynamic hardware tree:

```text
C:\ProgramData\Leica Microsystems\LAS X\Calibration Data\DefaultDynamicWidefieldTree.xlhw
```

## Manual Restore

1. Close LAS X.
2. Open Task Manager.
3. End `LCS.exe` if it is still running.
4. Open the timestamped backup folder from the script output.
5. Copy `ucapi-ahmconfig.installed` back to:

```text
C:\ProgramData\Leica Microsystems\UCAPI\ucapi-ahmconfig.installed
```

6. Copy `DefaultDynamicWidefieldTree.xlhw` back to:

```text
C:\ProgramData\Leica Microsystems\LAS X\Calibration Data\DefaultDynamicWidefieldTree.xlhw
```

7. Start LAS X again.

## Restore From Side-By-Side Backups

If you prefer to restore from the backups next to the original files, rename or
copy the timestamped `.bak-yyyyMMdd-HHmmss` file back to the original filename.

Example:

```text
DefaultDynamicWidefieldTree.xlhw.bak-20260604-121800
```

should be copied back as:

```text
DefaultDynamicWidefieldTree.xlhw
```

Do this only while LAS X and `LCS.exe` are closed.

