# Lab Ops Scripts

Small, unofficial scripts and notes for day-to-day lab operations: instrument
workstations, acquisition software, Windows IT chores, device quirks, and
repeatable troubleshooting tasks.

This is not a vendor support package. It is a practical lab notebook for scripts
that are useful enough to keep, document, and reuse.

## Principles

- Keep scripts narrow and understandable.
- Back up before changing configuration.
- Prefer reversible changes.
- Document what each script does, what it does not do, and how to undo it.
- Do not commit private logs, crash dumps, serial numbers, license files, or
  screenshots with sensitive details.
- Keep device-specific fixes under their own folders.

## Scripts

| Script | Purpose | Platform |
| --- | --- | --- |
| [Leica LAS X S9i UCAPI Fix](scripts/leica-lasx-s9i-ucapi-fix/) | One-click recovery for Leica S9i black video in LAS X or Windows Camera, including USB/UVC reset, UCAPI DirectShow compatibility, and duplicate hardware-tree camera cleanup. | Windows / PowerShell |
| [Windows Headless Server](scripts/windows-headless-server/) | Configures a Windows host for unattended LAN-only RDP and SSH, boot-time self-healing, no AC sleep, and supported network wake features. | Windows Pro-class / PowerShell |
| [Windows UEFI Read-Only Audit](scripts/windows-uefi-readonly-audit/) | Inventories runtime-visible UEFI metadata and maps offline IFR questions to extracted variable bodies without a firmware write path. | Windows / PowerShell |
| [Windows Awake Forever](scripts/windows-awake-forever/) | Keeps a Windows workstation display awake during long lab runs, monitoring, transfers, or instrument sessions. | Windows / PowerShell |

## Layout

```text
lab-ops-scripts/
  README.md
  LICENSE
  .gitignore

  scripts/
    leica-lasx-s9i-ucapi-fix/
      Fix-LASX-S9i-UCAPI.ps1
      README.md
      docs/
        restore.md
        what-happened.md

    windows-awake-forever/
      awake_forever.ps1
      README.md

    windows-headless-server/
      Config.example.psd1
      Install-HeadlessServer.ps1
      Maintain-HeadlessServer.ps1
      Get-HeadlessServerStatus.ps1
      Uninstall-HeadlessServer.ps1
      README.md

  docs/
    lab-ops-principles.md
    windows-workstation-notes.md
    data-privacy.md

  templates/
    script-README-template.md
    incident-note-template.md
    restore-guide-template.md
```

## Adding A Script

1. Create a folder under `scripts/`.
2. Add a README using `templates/script-README-template.md`.
3. Document required permissions, expected behavior, and stop/restore steps.
4. Update the Scripts table above.
5. Check that no private diagnostic artifacts were added.

## Disclaimer

Use these scripts at your own risk. Read each script and its README before
running it on an instrument workstation or shared lab computer.

## License

MIT License. See [LICENSE](LICENSE).

