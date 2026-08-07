# Windows Headless Server

Turns a Windows 10/11 Pro-class computer into a LAN-only, unattended RDP and
SSH host. One elevated installation creates SYSTEM startup/watchdog tasks; no
interactive sign-in or recurring UAC approval is required afterward.

## Use When

- A Windows workstation must run without a monitor or nearby operator.
- RDP and SSH must recover automatically after boot or a transient adapter fault.
- The host must not sleep while connected to AC power.
- Wired Wake-on-LAN or firmware-supported Wake-on-WLAN is desirable.

## Requirements

- Windows 10/11 Pro, Enterprise, Education, or Server for inbound RDP. Windows
  Home cannot act as a Microsoft RDP host. The installer stops on Home by
  default; set `RequireRdpHost = $false` only when an SSH-only host is intended.
- An administrator account for the initial installation only.
- An existing working LAN connection. For Wi-Fi, connect once and save the WLAN
  profile before installing.
- A strong password if SSH password authentication remains enabled.

## What It Changes

- Enables RDP with Network Level Authentication, TLS, strong encryption, and
  persistent disconnected sessions.
- Installs Windows OpenSSH Server, validates `sshd_config`, and starts `sshd`
  automatically.
- Opens RDP TCP/UDP, SSH TCP, and optional ICMP echo only on the Windows Private
  profile and only from `LocalSubnet` by default.
- Prevents AC sleep and disk timeout, disables hibernation/Fast Startup when
  configured, and enables automatic reboot after a system crash.
- Disables Wi-Fi MAC randomization on the selected adapter and can reconnect a
  named, already-saved WLAN profile.
- Arms wake-capable physical adapters when the driver exposes that capability.
- Installs SYSTEM tasks at startup and every few minutes to enforce critical
  settings, restart services, and recover the selected adapter after repeated
  failures.
- Saves power, firewall, RDP policy, and SSH configuration backups under
  `C:\ProgramData\HeadlessServer\backup`.
- Protects runtime files using the well-known Windows SIDs for SYSTEM,
  Administrators, and Users so ACL setup is independent of display language.

It does not store a Wi-Fi password, an SSH private key, a public IP address, or
any machine-specific identifier in this repository.

## Configure

Copy the example locally. `Config.psd1` is ignored by Git so site-specific
values are not accidentally committed.

```powershell
Copy-Item .\Config.example.psd1 .\Config.psd1
notepad .\Config.psd1
```

Most hosts can leave `PrimaryAdapterName` blank; the installer resolves the
adapter carrying the current default IPv4 route and stores that resolved name
in the protected runtime configuration. Set `WifiProfile` only for a Wi-Fi host
that should reconnect a particular saved profile. Do not put a password in the
file.

`SshAllowedUsers` defaults to the account running the installer. To use another
account, specify local names such as `@('serveradmin')` or qualified names such
as `@('DOMAIN\operator')`.

## Install

Open PowerShell **as Administrator** once, then run:

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
.\Install-HeadlessServer.ps1 -ConfigPath .\Config.psd1
```

The one UAC elevation is a Windows security boundary: installing services,
firewall rules, machine power policy, and SYSTEM tasks cannot be performed by a
standard process. Once installed, maintenance runs non-interactively as SYSTEM
at boot and on the watchdog schedule.

Before moving the machine out of reach, reboot it once and verify both paths
from a second LAN computer:

```powershell
Test-NetConnection <server-ip> -Port 3389
Test-NetConnection <server-ip> -Port 22
mstsc /v:<server-ip>
ssh <user>@<server-ip>
```

Status on the server:

```powershell
powershell -File C:\ProgramData\HeadlessServer\Get-Status.ps1
Get-Content C:\ProgramData\HeadlessServer\logs\maintain.log -Tail 50
```

## Prefer SSH Keys

First confirm key login works, then set
`EnableSshPasswordAuthentication = $false` and rerun the installer. A typical
Windows user key is placed in `%USERPROFILE%\.ssh\authorized_keys`. Accounts in
the local Administrators group may instead be governed by the
`administrators_authorized_keys` rule in the stock Windows OpenSSH config; check
the effective file before disabling passwords.

## Router And Addressing

Reserve a stable IPv4 address in the router's DHCP settings using the physical
MAC reported by `Get-NetAdapter`. A router reservation is preferred to a static
address on Windows because it keeps gateway and DNS settings centrally managed.

Router configuration is intentionally not automated: consumer-router APIs are
vendor-specific, often undocumented, and may expose administrator credentials.
Keep router management on the LAN and do not expose RDP (3389) or SSH (22)
through internet port forwarding. Use a VPN for access from outside the LAN.

## BIOS/UEFI And Wake Limitations

Windows scripts cannot generically change firmware settings. Physically verify
these once in BIOS/UEFI if available:

- **Restore on AC Power Loss** / **After Power Failure**: `Power On`.
- **Wake on LAN** / **Power on by PCI-E**: enabled.
- USB or network power in S4/S5: enabled if required by the platform.

Wired WoL is substantially more reliable than wireless wake. WoWLAN from sleep
or modern standby depends on the wireless card, driver, firmware, access point,
and power state; wake from a full S5 shutdown is uncommon. Test the exact power
state before placing a host out of reach. For maximum availability use wired
Ethernet, BIOS AC-restore, a DHCP reservation, and a controllable UPS/PDU.

## Recovery And Uninstall

To stop automation and remove only this package's scheduled tasks and firewall
rules:

```powershell
powershell -ExecutionPolicy Bypass -File C:\ProgramData\HeadlessServer\Uninstall.ps1
```

To also import the newest pre-install backups:

```powershell
powershell -ExecutionPolicy Bypass -File C:\ProgramData\HeadlessServer\Uninstall.ps1 -RestoreBackups
```

Backup restoration can overwrite legitimate changes made after installation,
especially the complete Windows Firewall policy. Review timestamps first.
Uninstall intentionally retains logs and backups for recovery; delete
`C:\ProgramData\HeadlessServer` manually only after verification.

## Security Notes

- Keep the network profile Private. Managed rules do not apply to Public.
- `LocalSubnet` follows Windows' local-subnet definition. For tighter control,
  replace it with explicit LAN CIDRs such as `192.0.2.0/24`.
- The package does not disable unrelated firewall rules; audit existing inbound
  rules separately.
- Do not enable automatic Windows logon. RDP and SSH operate before GUI logon.
- Protect local administrator accounts and test an alternate management route
  before changing authentication settings.

## License

MIT License. See the repository-level [LICENSE](../../LICENSE).
