# DVSwitch ASL Mode-Switch Repair

Repository: <https://github.com/ke2hni/DVSwitch-Mods-ASL-Mode-Switch>

This repository contains a standalone repair for the ASL mode-switch routing
problem in `dvswitch.sh` versions 1.6.2 and 1.6.3.

## What the repair changes

The repair updates `/opt/MMDVM_Bridge/dvswitch.sh` to send Analog_Bridge
remote-control commands to a live TLV UDP listener. When leaving ASL mode, it
selects the ASL listener when needed; for subsequent commands, it detects the
active listener from the configured mode ports. This addresses stale listener
port information in ABInfo.

The repair changes only `/opt/MMDVM_Bridge/dvswitch.sh`. It does not modify
Analog_Bridge configuration, ASL node connections, dashboard files, or radio
settings. No service restart or reboot is needed because `dvswitch.sh` is read
when each command runs.

## Download and run

### Clone the repository

```sh
git clone https://github.com/ke2hni/DVSwitch-Mods-ASL-Mode-Switch.git && cd DVSwitch-Mods-ASL-Mode-Switch
```

### Or download the GitHub source ZIP

Download the ZIP from the repository's **Code** button, extract it, then enter
the extracted `DVSwitch-Mods-ASL-Mode-Switch-main` directory. GitHub names its
source ZIP folder with the `-main` suffix; a `git clone` uses the directory
without that suffix, as shown above.

### Check, then install

Run the check first. It does not change files or restart services:

```sh
sudo ./repair-dvswitch-asl-mode-switch.sh --check
```

If the check passes on a supported `dvswitch.sh`, install the repair:

```sh
sudo ./repair-dvswitch-asl-mode-switch.sh --install
```

The installer creates a protected, timestamped backup before changing the
script, validates the installed result, and rolls back if installation fails.
It is safe to rerun. Backups are stored under
`/var/backups/dvswitch-mods/asl-mode-switch/`.

## Verify mode switching

For example, switch to P25 and read the active mode:

```sh
sudo /opt/MMDVM_Bridge/dvswitch.sh mode P25
sudo /opt/MMDVM_Bridge/dvswitch.sh mode
```

Repeat with the other modes configured on the node: DMR, D-Star, NXDN, YSF,
and STFU. The repair does not add ASL node tuning, favorites, or RX Monitor
features.

## Restore a backup

Use the exact backup directory name printed by the installer:

```sh
sudo ./repair-dvswitch-asl-mode-switch.sh --restore install-YYYYMMDD-HHMMSS
```

## Compatibility

- Supported target versions: `dvswitch.sh` 1.6.2 and 1.6.3.
- Unexpected script versions or layouts are rejected without installation.
- Test on non-production nodes first.
