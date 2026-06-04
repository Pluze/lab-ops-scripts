# Data Privacy

Lab operations artifacts often contain private or sensitive information.

Do not commit:

- Vendor diagnostic ZIP files.
- Crash dumps.
- Raw application logs.
- License files.
- Serial numbers.
- Hostnames.
- Usernames.
- Screenshots containing paths, samples, project names, or license data.
- Configuration files copied directly from workstations unless sanitized.

Prefer:

- Short, sanitized log excerpts.
- Redacted paths such as `C:\Users\<user>\...`.
- Device model names without serial numbers.
- Reproducible commands instead of raw support bundles.
- Cropped or redacted screenshots.

