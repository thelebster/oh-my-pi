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
| md0 | 1.82 TiB | RAID1 | NAS storage (ext4) |

## RAID Levels

The playbook creates the array with `mdadm --create`. To change the RAID level, edit the `Create new RAID1 array` task in `ansible/extras/pinas.yml`:

| | RAID1 (striping) | RAID1 (mirroring) |
|---|---|---|
| **Speed** | 2x read/write (both disks in parallel) | 1x write, 2x read |
| **Capacity** | Full (both disks combined) | Half (data duplicated) |
| **Redundancy** | None — one disk fails, all data lost | Survives one disk failure |
| **Use case** | Max performance/capacity, data is replaceable | Data safety matters |
| **mdadm flag** | `--level=0` | `--level=1` |

Current playbook uses **RAID1**. To switch to RAID0, change `--level=1` to `--level=0` before first run.

**Warning:** Changing RAID level requires destroying and recreating the array. Back up data first.

## Tags

```bash
./play extra pinas --tags raid    # RAID setup only
./play extra pinas --tags omv     # OpenMediaVault only
./play extra pinas --tags check   # Check SSDs
```
