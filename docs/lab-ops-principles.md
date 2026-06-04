# Lab Ops Principles

This repository is for small scripts that solve recurring lab operations
problems without turning every fix into a one-off mystery.

## Good Scripts

Good scripts in this repo should:

- Solve one clear problem.
- Explain when to use them.
- Explain when not to use them.
- Print enough output to know what happened.
- Avoid irreversible changes.
- Create backups before editing configuration.

## Device And IT Work Often Overlap

Lab issues often sit between instrument hardware, vendor software, Windows
drivers, USB devices, network shares, and user settings. Scripts should be
explicit about which layer they touch.

## Stop At Stable

Once a workstation or instrument behaves correctly, avoid speculative cleanup.
Document the fix, keep the backup path, and move on.

