# DVSwitch ASL Mode-Switch Repair

A standalone repair for the ASL mode-switch routing problem in `dvswitch.sh`
versions 1.6.2 and 1.6.3. It does not require or integrate with the
DVSwitch-Mods manager.

## What it changes

The repair updates `/opt/MMDVM_Bridge/dvswitch.sh` so remote-control
commands are sent to an active Analog_Bridge TLV UDP listener. During a mode
change from ASL, it accounts for the ASL listener and then routes subsequent
commands using the listener that is actually active. This avoids relying on a
stale TLV port in ABInfo.

It changes only `dvswitch.sh`. It does not change Analog_Bridge configuration,
ASL node connections, dashboard files, or radio settings. No service restart or
reboot is needed because `dvswitch.sh` is read each time the command runs.

## Files

- `repair-dvswitch-asl-mode-switch.sh` — standalone check, install, and restore
  command.
- `lib/patch_dvswitch_asl_mode_switch.py` — patch helper used by that script.
- `tests/test-dvswitch-asl-mode-switch-patcher.py` — local patcher tests.
- `TESTING.txt` — test-node procedure.

The other files carried in this archive are not part of the ASL repair and are
not installed by it.

## Install on a test node

Extract the archive, enter its top-level directory, and run the check first:

```sh
cd ~/DVSwitch-Mods-ASL-Mode-Switch-main
sudo ./repair-dvswitch-asl-mode-switch.sh --check
```

If the check passes and identifies a supported `dvswitch.sh`, install the
repair:

```sh
sudo ./repair-dvswitch-asl-mode-switch.sh --install
```

The script makes a protected, timestamped backup before replacing the target
file, validates the installed result, and rolls back if installation fails.
Running `--install` again is safe. To see the backup names, list:

```sh
sudo ls -1 /var/backups/dvswitch-mods/asl-mode-switch
```

Restore one backup by passing its directory name (for example,
`install-20261025-143000`):

```sh
sudo ./repair-dvswitch-asl-mode-switch.sh --restore install-YYYYMMDD-HHMMSS
```

## Verify mode switching

After installation, switch from ASL to the modes configured on the node, then
check the reported mode with the existing DVSwitch command:

```sh
sudo /opt/MMDVM_Bridge/dvswitch.sh mode P25
sudo /opt/MMDVM_Bridge/dvswitch.sh mode
```

Repeat with DMR, D-Star, NXDN, YSF, and STFU as applicable. This package does
not add ASL node tuning, favorites, or RX Monitor features.

## Compatibility and safety

- Supported target versions: `dvswitch.sh` 1.6.2 and 1.6.3.
- `--check` does not modify files or restart services.
- Unsupported versions or unexpected script layouts are rejected without
  installation.
- Install on test nodes first.
- The repair is independent of `manage-dvswitch-mods.sh`; there is no manager
  installer in this package.
