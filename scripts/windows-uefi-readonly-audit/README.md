# Windows UEFI Read-Only Audit

Read-only first-stage probe for determining whether Windows can see firmware
variables that may contain BIOS Setup, power-loss recovery, wake, or ErP
settings.

## Safety Boundary

`Read-UefiVariableInventory.ps1`:

- Uses the Windows `NtEnumerateSystemEnvironmentValuesEx` API.
- Enables `SeSystemEnvironmentPrivilege` in the current elevated process.
- Does not install or load a kernel driver.
- Does not call a firmware-variable write/delete API.
- Does not read or write the SPI flash.
- Does not export raw UEFI variable contents.
- Returns candidate names, GUIDs, sizes, attributes, and SHA-256 hashes only.

The API is not a documented application contract and can be restricted by a
Windows release or firmware. Failure is a valid audit result, not a reason to
disable Secure Boot, VBS, HVCI, or driver-signature enforcement.

## Usage

Run once from an elevated Windows PowerShell 5.1 session:

```powershell
powershell -ExecutionPolicy Bypass -File .\Read-UefiVariableInventory.ps1 `
  -OutputPath .\uefi-variable-inventory.json
```

By default only names resembling Setup, power, wake, WoL, ErP, AC loss, or G3
variables are returned. To return metadata for every enumerated variable:

```powershell
.\Read-UefiVariableInventory.ps1 -IncludeAllVariableMetadata
```

Do not commit generated inventories. Even metadata can identify a particular
firmware build or platform.

## What A Successful Probe Means

Finding a `Setup`, `SaSetup`, `CpuSetup`, `PchSetup`, or similarly named
variable proves only that Windows can enumerate that variable. Mapping a byte
to a setting such as `Restore on AC Power Loss` requires the matching firmware
image and its Internal Forms Representation (IFR).

A conservative open-source mapping pipeline is:

1. Obtain the exact OEM firmware image, or make a separately authorized,
   read-only SPI dump.
2. Extract firmware volumes with
   [UEFITool/UEFIExtract](https://github.com/LongSoft/UEFITool).
3. Convert the Setup form package with
   [IFRExtractor-RS](https://github.com/LongSoft/IFRExtractor-RS).
4. Match the IFR VarStore name, GUID, offset, size, and option values to the
   live variable.
5. Report the decoded value without offering a write operation.

If Windows cannot enumerate the required variable, CHIPSEC can inspect UEFI
variables in a read-only SPI image. CHIPSEC on Windows may require a privileged
kernel driver and can conflict with Secure Boot, VBS, or HVCI. Do not weaken
those protections solely for this audit. Never use CHIPSEC `spi write`,
`spi erase`, `spi disable-wp`, or UEFI variable write/delete commands on a
remote-only machine.

`setup_var.efi` can read an already-known variable offset from a UEFI shell,
but it also supports writes and explicitly warns that an incorrect variable can
brick a computer. It is not part of this unattended Windows workflow.

## Interpretation

- Candidate found: obtain the matching firmware/IFR before interpreting bytes.
- No candidate found: Setup variables may lack Runtime Access or use unrelated
  names; do not guess.
- API denied: stop at this stage unless an owner separately authorizes a
  driver-backed or UEFI-shell audit.
- Exact BIOS image unavailable: behavioral testing and visible BIOS access are
  more reliable than applying offsets from another firmware revision.

## License

MIT License. See the repository-level [LICENSE](../../LICENSE).
