# PiNAS - Raspberry Pi NAS

Raspberry Pi NAS with OpenMediaVault and RAID1 storage.

## Current Setup

Pinas runs **Trixie (Debian 13) + OMV 8.0.10** with RAID1 (2x NVMe SSDs).

## Clean Install

Step-by-step guide for a fresh install.

### Step 1: Flash Pi OS Lite

Open Raspberry Pi Imager:
1. Choose OS → **Raspberry Pi OS Lite (64-bit)** (Trixie is the current default)
2. Configure: hostname, SSH (public key), WiFi credentials, locale
3. Flash and boot

Verify SSH works:
```bash
ssh pi@pinas.local
```

### Step 2: Common Setup

Install essential packages, harden SSH, configure firewall:
```bash
./play --limit pinas
```

This runs the common play: apt updates, UFW, fail2ban, locale fix, hostname.

### Step 3: Migrate to systemd-networkd

**Do this before OMV.** OMV will remove NetworkManager and your WiFi creds with it. Migrating first puts the system in the state OMV expects.

```bash
./play extra pinas-networkd
```

What it does:
1. Reads WiFi SSID/password from existing netplan configs
2. Writes `/etc/wpa_supplicant/wpa_supplicant.conf`
3. Creates fallback netplan files (`99-ethernet-fallback.yaml`, `99-wifi-fallback.yaml`)
4. Enables systemd-networkd, applies netplan
5. Verifies connectivity (aborts if no network — safe to retry)
6. Purges NetworkManager

Verify:
```bash
./play extra pinas-networkd --tags verify
```

If you skip this step, the OMV playbook has a fallback that creates the same netplan files inline, but there's no connectivity check — riskier.

### Step 4: Set Up RAID

```bash
./play extra pinas-raid1
```

What it does:
1. Installs mdadm
2. Checks for existing array (assembles from superblocks if found)
3. Creates RAID1 array from `/dev/nvme0n1` + `/dev/nvme1n1` (only if no array exists)
4. Creates ext4 filesystem (only if not already formatted)
5. Saves mdadm config for boot persistence

**Note:** RAID1 initial sync can take a long time with large drives. The array works during sync but at reduced performance (see [RAID Levels](#raid-levels)).

Skip this step if not using RAID — OMV can manage individual drives directly.

### Step 5: Install OpenMediaVault

```bash
./play extra pinas
```

What it does:
1. Opens SMB port (445) in UFW
2. Network protection fallback (no-op if step 3 was done)
3. Downloads and runs the OMV install script with `-r` (skip reboot)
4. Fixes interface name in OMV config (`eth0` → `end0`)
5. Installs OMV RAID management plugin (`openmediavault-md`)
6. Reboots

The install takes 15-30 minutes. The `-r` flag prevents automatic reboot so the playbook can fix the interface name first.

### Step 6: Post-Install (OMV Web UI)

After reboot, access the web UI at `http://pinas.local` (default: admin / openmediavault).

1. **Change default admin password**
2. **Mount filesystem**: Storage → File Systems → select `/dev/md0` → Mount
3. **Create shared folder**: Storage → Shared Folders → Create → select md0, set name/path
4. **Create SMB user**: Users → Users → Create → set username/password
5. **Set permissions**: Storage → Shared Folders → select folder → Permissions → give user Read/Write
6. **Enable SMB**: Services → SMB/CIFS → toggle Enabled
7. **Create SMB share**: Services → SMB/CIFS → Shares → Create → select shared folder, set Public to "No"

### Step 7: Connect from Mac

Finder → Go → Connect to Server:
```
smb://pinas.local
```
Finder will prompt for the username and password created above.

## OMV Installation Issues

Known issues we hit during OMV installation and how the playbooks handle them.

### 1. NetworkManager Removal Kills WiFi

OMV removes NetworkManager and replaces it with systemd-networkd. WiFi credentials are managed by NM — when it's purged, they're gone.

**What happens during install:**

1. `apt purge network-manager` — removes NM entirely
2. Installs systemd-networkd + netplan as replacement
3. Deletes netplan files matching `*NetworkManager*` — **your WiFi creds lived here** (`90-NM-*.yaml`)
4. Registers `eth0` in its XML database — wrong name, Pi uses `end0`
5. Tries to reboot — you're locked out (no WiFi, broken ethernet)

On Pi OS, WiFi credentials live in netplan files (`90-NM-*.yaml`), not in `/etc/NetworkManager/system-connections/`. OMV's cleanup deletes files containing `*NetworkManager*` and `*openmediavault*` patterns — which nukes the WiFi config.

**Our fix** (`pinas-networkd.yml` — recommended, or inline fallback in `pinas.yml`):
1. Extract WiFi SSID and password from existing netplan files
2. Write `/etc/wpa_supplicant/wpa_supplicant.conf` (OMV install script parses this)
3. Create `99-ethernet-fallback.yaml` and `99-wifi-fallback.yaml`
4. Run OMV install with `-r` flag (skip reboot) to verify networking first

### 2. Interface Name Mismatch (eth0 → end0)

OMV's install script registers `eth0` in its XML database. But after it removes NetworkManager, the interface switches to predictable naming (`end0`). Networking breaks because OMV tries to configure a non-existent `eth0`.

**Our fix** (`pinas.yml`):
```yaml
- name: Fix ethernet interface name in OMV config (eth0 → end0)
  replace:
    path: /etc/openmediavault/config.xml
    regexp: '<devicename>eth0</devicename>'
    replace: '<devicename>end0</devicename>'
```
Then redeploy: `omv-salt deploy run systemd-networkd`

### 3. WiFi Blocked After Install

OMV install can leave WiFi in a blocked state via rfkill.

**Our fix** (`pinas.yml`): `rfkill unblock all`

### 4. Lessons Learned

- **Don't use Ansible `mount` or fstab** for OMV-managed filesystems — OMV manages mounts via its own database (`omv-confdbadm`)
- **Always use `-r` flag** on the OMV install script to skip automatic reboot and verify before rebooting

## Storage Layout

| Device | Size | Type | Purpose |
|--------|------|------|---------|
| mmcblk0 | 14.9G | SD card | OS (boot + root) |
| nvme0n1 | 931.5G | NVMe SSD | RAID1 member |
| nvme1n1 | 931.5G | NVMe SSD | RAID1 member |
| md0 | 931.5G | RAID1 | NAS storage (ext4) |

## RAID Levels

The playbook creates the array with `mdadm --create`. To change the RAID level, edit the `Create new RAID1 array` task in `ansible/extras/pinas-raid1.yml`:

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
./play extra pinas-raid1
```

**Important:** After recreating the array, you must reformat the filesystem:
```bash
sudo mkfs.ext4 /dev/md0
```
Without reformatting, mount will fail because the old ext4 superblock references the previous array size:
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

## Troubleshooting

**Can't SSH after OMV install:**
- Connect via ethernet if on WiFi
- If ethernet also fails, connect a monitor — check `ip addr` for assigned IPs
- Try `sudo netplan apply` or `sudo omv-firstaid` (option 1: configure network)

**OMV web UI shows 502 Bad Gateway:**
```bash
sudo apt-get install --reinstall php8.4-fpm
sudo omv-salt deploy run phpfpm
sudo omv-salt deploy run nginx
```

**RAID array not visible in OMV:**
- Ensure `openmediavault-md` plugin is installed: `sudo apt install openmediavault-md`
- Rescan: `sudo omv-mkconf mdadm && sudo monit restart omv-engined`
- Refresh the web UI

**WiFi lost after install:**
```bash
# If you can SSH via ethernet:
sudo rfkill unblock all
sudo netplan apply

# Check netplan files exist:
ls /etc/netplan/99-*.yaml

# If missing, recreate manually (replace SSID/PASSWORD):
sudo tee /etc/netplan/99-wifi-fallback.yaml << 'EOF'
network:
  version: 2
  renderer: networkd
  wifis:
    wlan0:
      optional: true
      dhcp4: true
      access-points:
        "YOUR_SSID":
          password: "YOUR_PASSWORD"
EOF
sudo chmod 600 /etc/netplan/99-wifi-fallback.yaml
sudo netplan apply
```

## Tags

```bash
./play extra pinas --tags omv              # OpenMediaVault only
./play extra pinas --tags smb              # SMB firewall only
./play extra pinas-networkd --tags check   # Check migration state
./play extra pinas-networkd --tags verify  # Verify post-migration
./play extra pinas-raid1 --tags check      # Check SSDs only
```

## References

### NetworkManager Removal / WiFi Loss

- [Fresh OMV8 on Pi 4: netplan error — installScript #150](https://github.com/OpenMediaVault-Plugin-Developers/installScript/issues/150) (Dec 2025, most recent)
- [Install script broke network interfaces — OMV #698](https://github.com/openmediavault/openmediavault/issues/698)
- [Fail to Connect to WiFi After Install on Pi 4 — installScript #7](https://github.com/OpenMediaVault-Plugin-Developers/installScript/issues/7) (Feb 2020, original report)
