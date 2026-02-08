# PiNAS - Raspberry Pi NAS

Raspberry Pi NAS with OpenMediaVault and RAID1 storage.

## Hardware

- Raspberry Pi (pinas.local)
- 2x Crucial CT1000P310SSD2 NVMe SSDs (931.5G each)
- OS: Raspberry Pi OS Lite (64-bit) - **must be Lite, OMV does not support Desktop**

## Provisioning

```bash
# Common setup (packages, locale, SSH hardening)
./play --limit pinas

# NAS setup (OMV + RAID1)
./play extra pinas
```

### What the playbook automates

- WiFi/ethernet network protection (survives OMV's NetworkManager removal)
- mdadm installation
- OpenMediaVault + MD (RAID) plugin
- RAID1 array creation (`/dev/md0` from `/dev/nvme0n1` + `/dev/nvme1n1`)
- ext4 filesystem on the array
- mdadm config persistence (survives reboots)

### Network protection

OMV removes NetworkManager and replaces it with systemd-networkd + netplan. This kills WiFi (and sometimes ethernet) because the WiFi credentials are lost in the transition.

The playbook handles this by:
1. Reading WiFi SSID/password from NetworkManager connection files
2. Writing `/etc/wpa_supplicant/wpa_supplicant.conf` (the format the OMV install script parses)
3. Creating fallback netplan files (`99-ethernet-fallback.yaml`, `99-wifi-fallback.yaml`) that OMV's cleanup won't delete (it only targets files with "openmediavault" in the name)

The OMV install runs with `-r` (skip reboot) so we can verify networking before rebooting.

### What requires manual setup (OMV web UI)

Mounting and sharing must be done through the OMV web UI because OMV manages its own database for filesystems and shares.

## Post-Setup (OMV Web UI)

Access: `http://pinas.local` (default login: admin / openmediavault)

1. **Change default admin password**
2. **Mount filesystem**: Storage → File Systems → select `/dev/md0` → click Mount (play button)
3. **Create shared folder**: Storage → Shared Folders → Create → select md0 filesystem, set name/path
4. **Enable SMB**: Services → SMB/CIFS → toggle Enabled
5. **Create SMB share**: Services → SMB/CIFS → Shares → Create → select shared folder

## SMB User Access

1. **Create user**: Users → Users → Create — set username and password (this is the SMB login)
2. **Set permissions**: Storage → Shared Folders → select folder → Permissions (key icon) → give the user Read/Write
3. **Verify share is not public**: Services → SMB/CIFS → Shares → ensure Public is set to "No"

## Connecting from Mac

Finder → Go → Connect to Server:
```
smb://pinas.local
```
Finder will prompt for the username and password created above.

## Storage Layout

| Device | Size | Type | Purpose |
|--------|------|------|---------|
| mmcblk0 | 14.9G | SD card | OS (boot + root) |
| nvme0n1 | 931.5G | NVMe SSD | RAID1 member |
| nvme1n1 | 931.5G | NVMe SSD | RAID1 member |
| md0 | 931.5G | RAID1 | NAS storage (ext4) |

## RAID Levels

The playbook creates the array with `mdadm --create`. To change the RAID level, edit the `Create new RAID1 array` task in `ansible/extras/pinas.yml`:

| | RAID0 (striping) | RAID1 (mirroring) |
|---|---|---|
| **Speed** | 2x read/write (both disks in parallel) | 1x write, 2x read |
| **Capacity** | Full (both disks combined) | Half (data duplicated) |
| **Redundancy** | None — one disk fails, all data lost | Survives one disk failure |
| **Use case** | Max performance/capacity, data is replaceable | Data safety matters |
| **mdadm flag** | `--level=0` | `--level=1` |

Current playbook uses **RAID1**. To switch to RAID0, change `--level=1` to `--level=0` before first run.

**Note:** RAID1 mirrors both disks on creation, which triggers a full resync. With large drives (e.g. 2x 931GB) this can take a long time. The array cannot be mounted in OMV until the resync completes.

Monitor progress:
```bash
watch cat /proc/mdstat
```

### Destroying and recreating an existing array

If you need to change the RAID level on an existing array, **back up all data first** — this destroys everything on the array.

```bash
# 1. Unmount the array (if mounted)
sudo umount /dev/md0

# 2. Stop the array
sudo mdadm --stop /dev/md0

# 3. Clear RAID superblocks from both drives
sudo mdadm --zero-superblock /dev/nvme0n1 /dev/nvme1n1
```

If `umount` fails, check what's using it with `lsblk` or `mount | grep md0`.

After destroying, run the playbook to recreate with the new RAID level:
```bash
./play extra pinas --tags raid
```

**Important:** After recreating the array, you must reformat the filesystem:
```bash
sudo mkfs.ext4 /dev/md0
```
The old ext4 superblock still references the previous array size (e.g. RAID0's ~1.86 TiB), which won't match the new array size (e.g. RAID1's ~931 GiB). Without reformatting, mount will fail with:
```
EXT4-fs (md0): bad geometry: block count XXXXX exceeds size of device (XXXXX blocks)
```

Then clean up the stale OMV mount entry (the UUID changed after reformat):
```bash
# Remove old mount from OMV database (use the old UUID)
sudo omv-confdbadm delete "conf.system.filesystem.mountpoint" --filter '{"operator":"stringEquals","arg0":"fsname","arg1":"/dev/disk/by-uuid/OLD-UUID-HERE"}'

# Refresh fstab
sudo omv-salt deploy run fstab
```

Then mount the new filesystem through the OMV web UI (Storage → File Systems → md0 → Mount).

If OMV still shows the old array entry and won't let you delete/mount via the UI:
```bash
# Remove stale mount entry from OMV database
sudo omv-confdbadm delete "conf.system.filesystem.mountpoint" --filter '{"operator":"stringEquals","arg0":"fsname","arg1":"/dev/md0"}'

# Refresh fstab
sudo omv-salt deploy run fstab

# Rescan and restart OMV engine
sudo omv-mkconf mdadm
sudo monit restart omv-engined
```

Then refresh the OMV web UI — the new array should appear under Storage → File Systems.

Check array health:
```bash
sudo mdadm --detail /dev/md0
```

## Tags

```bash
./play extra pinas --tags raid    # RAID setup only
./play extra pinas --tags omv     # OpenMediaVault only
./play extra pinas --tags check   # Check SSDs
```
