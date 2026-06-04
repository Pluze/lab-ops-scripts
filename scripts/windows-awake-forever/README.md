# Windows Awake Forever

Small PowerShell script that keeps a Windows workstation display awake by
periodically calling `SetThreadExecutionState`.

Useful during:

- Long instrument runs.
- Camera monitoring.
- Large data transfers.
- Remote observation sessions.
- Any workflow where display sleep interrupts visibility.

## What It Does

The script sets:

```text
ES_CONTINUOUS | ES_DISPLAY_REQUIRED
```

every 30 seconds. This asks Windows to keep the display awake while the script is
running.

## What It Does Not Do

- It does not change Windows power-plan settings permanently.
- It does not install anything.
- It does not require administrator rights.
- It does not prevent all forms of lock screen or domain policy enforcement.

## Usage

Run in PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File .\awake_forever.ps1
```

Stop with:

```text
Ctrl+C
```

Closing the PowerShell window also stops it.

## Notes

This is intentionally simple. For shared lab computers, make sure keeping the
display awake does not conflict with local security or energy policies.

## License

MIT License. See the repository-level [LICENSE](../../LICENSE).

