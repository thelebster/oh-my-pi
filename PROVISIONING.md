# Provisioning a New Pi

Step-by-step runbook: from a blank SD card to a Pi that is updated, hardened, reachable from anywhere, and ready for extras. Every command runs from this repo on your Mac unless stated otherwise.

The model is simple: **one minimal base playbook** (`./play`) that is safe to rerun on any Pi, plus **opt-in extras** (`./play extra <name>`) for everything else. Nothing gets installed that you did not ask for.

Building a remote **Tailscale exit node**? Follow **[TAILSCALE.md](TAILSCALE.md)** instead: it covers the same steps end to end, plus Tailscale.

---

## 0. Before you start

- Raspberry Pi Imager on the Mac.
- An SSH key pair for the Pi, e.g. `~/.ssh/mypi` (`ssh-keygen -t ed25519 -f ~/.ssh/mypi`).
- This repo cloned, with `.env` created from `.env.example`.

## 1. Flash the card

In Raspberry Pi Imager, choose the OS (Pi OS Lite for headless), then in **OS customisation**:

| Setting | Value |
|---|---|
| Hostname | the final name, e.g. `mypi` |
| Username | `pi` |
| Password | set one (needed once to restore sudo if an upgrade removes it, see Troubleshooting) |
| SSH | enabled, **public-key auth only**, paste the contents of `~/.ssh/mypi.pub` |
| Wi-Fi | only if the Pi will not be on ethernet |
| Raspberry Pi Connect | optional; the Imager key expires quickly, so expect to sign in again (section 5b) |

Boot the Pi and wait a minute for first boot to finish.

## 2. Point the repo at the Pi

Edit `.env`:

```
PI_HOST=mypi.local     # mDNS name = hostname + .local
PI_USER=pi
PI_HOSTNAME=mypi
SSH_KEY=~/.ssh/mypi
```

`SSH_KEY` must be the key you pasted into Imager. Ansible does **not** read `~/.ssh/config`, so a wrong value here fails even if `ssh` works.

Optional SSH alias in `~/.ssh/config`:

```
Host mypi-lan
    HostName mypi.local
    IdentityFile ~/.ssh/mypi
    User pi
```

**Locale warnings** (`setlocale: LC_CTYPE: cannot change locale (UTF-8)`): macOS Terminal sends `LC_CTYPE=UTF-8`, which interactive bash rejects even when `LANG`/`LC_ALL` are valid, so a client-side `SetEnv` does **not** fully fix it. `./play extra locale` (section 4) fixes it on the Pi for every client: it generates en_US.UTF-8 and adds an sshd `SetEnv` drop-in that overrides the bogus `LC_CTYPE` for all sessions. (To silence it for all hosts at once, untick *Terminal → Settings → Profiles → Advanced → Set locale environment variables on startup*.)

Test:

```bash
ssh mypi-lan hostname              # plain SSH
./cmd -m ping --limit mypi           # Ansible connection
./cmd -m command -a "id -u" --limit mypi   # must print 0 = passwordless sudo works
```

`mypi` is the Ansible inventory alias and stays `mypi` regardless of the hostname. Use `zeropi` or `pinas` for the other hosts.

## 3. Base setup

```bash
./play --limit mypi --check          # dry run (the ufw step fails in check mode on a fresh Pi, that is expected)
./play --limit mypi                  # apply
```

What the base does, by tag:

| Tag | What |
|---|---|
| `updates` | apt dist-upgrade, essentials (curl git vim htop ufw pv jq mc), UFW with 22/80/443 open |
| `sudo` | keeps `/etc/sudoers.d/010_pi-nopasswd` in place so Ansible can never be locked out |
| `ssh` | password auth off, root login off, fail2ban (5 tries, 1 h ban) |
| `fan` | Pi 5 only: fan curve in `/boot/firmware/config.txt` |
| `eeprom` | Pi 5 only: firmware update if available |

Run a single section with `./play --limit mypi --tags ssh`.

If the recap says a reboot is required (fan curve or EEPROM):

```bash
make reboot                          # or: ./cmd -m shell -a "systemctl reboot" --limit mypi
./cmd -m ping --limit mypi           # ~20 s later
```

Check the result at any time:

```bash
./play extra status --limit mypi
```

## 4. Hostname and locale (optional)

Both used to be part of the base. Run them only if needed.

```bash
./play extra locale --limit mypi                             # en_US.UTF-8 + sshd SetEnv drop-in; stops macOS SSH locale warnings
./play extra hostname --limit mypi                           # sets hostname from PI_HOSTNAME
./play extra hostname --limit mypi -e pi_hostname=new-name   # rename: run this FIRST, then update .env + ssh config
```

The hostname extra also fixes `/etc/hosts` and restarts avahi, so the new `<name>.local` works without a reboot. The old name stops resolving immediately, so update `PI_HOST` in `.env` right after.

## 5. Remote access from anywhere

Pick what fits. For a Pi that lives somewhere you cannot walk to, set up at least two.

### 5a. Tailscale

VPN access from anywhere, optional exit node and Tailscale SSH, no public IP needed. Full guide: **[TAILSCALE.md](TAILSCALE.md)**.

### 5b. Raspberry Pi Connect (browser shell, break-glass)

The remote shell does not go through sshd at all, so it survives an SSH lock-out.

1. Create an auth key at https://connect.raspberrypi.com, **Settings**, **Auth keys**.
2. In `.env`: `RPI_CONNECT_AUTH_KEY=...`
3. Run one of:
   ```bash
   ./play extra connect-headless --limit mypi    # Pi OS Lite: remote shell only
   ./play extra connect-desktop --limit mypi     # Pi OS Desktop: shell + screen sharing
   ```
   Without a key the extra prints the interactive fallback: `ssh -t mypi.local rpi-connect signin`.
4. Check https://connect.raspberrypi.com/devices. The device name is captured at sign-in; rename it there if you renamed the Pi later.

### 5c. Cloudflare Tunnel (optional, real SSH/HTTP without port forwarding)

Only if you want public hostnames. See README, then `./play extra mypi-tunnel`.

## 6. Extras, pick what this Pi is for

```bash
./play extra                          # list
./play extra docker --limit mypi      # Docker CE
./play extra nginx --limit mypi
./play extra claude --limit mypi      # Claude Code CLI + claude-cmd wrapper
./play extra stress --limit mypi      # stress-ng, sysbench, iperf3
./play extra tools --limit mypi       # aria2, transmission-cli
./play extra network --limit mypi     # nmap, whois, dnsutils, ...
./play extra pihole --limit mypi      # needs docker
./play extra home-assistant --limit mypi
./play extra jellyfin --limit mypi
./play extra telegram-bot --limit mypi
./play extra ddns --limit mypi        # Cloudflare DDNS cron
```

Every extra is idempotent: rerun it after editing `.env` or the playbook. Extras with a removal path take `--tags <name>-remove` (`ddns-remove`, `tunnel-remove`, `tailscale-remove`).

## 7. Final checklist before the Pi leaves the building

- Wi-Fi needed at the destination? Save the profile now: `./cmd -m shell -a "nmcli device wifi connect 'SSID' password 'PASS'" --limit mypi`
- Every remote access path from section 5 you set up works from outside the LAN (Tailscale: see the [TAILSCALE.md checklist](TAILSCALE.md#11-final-checklist-before-the-pi-leaves-the-building)).

```bash
./play --limit mypi                                   # base converged, 0 changed
./play extra status --limit mypi                      # fail2ban active
ssh mypi-lan hostname                                 # SSH works
```

If you set up Raspberry Pi Connect, open https://connect.raspberrypi.com/devices, the Pi must show as online.

---

## TODO

- **RTC battery for the Pi 5.** Buy the official Raspberry Pi RTC Battery (rechargeable Panasonic ML2020 with JST plug, ~5 EUR). Power off, plug into the 2-pin **BAT** socket between USB-C and the first micro-HDMI port, stick the cell down. Then enable charging in `/boot/firmware/config.txt`:
  ```
  dtparam=rtc_bbat_vchg=3000000
  ```
  reboot and check `cat /sys/devices/platform/soc/soc:rpi_rtc/rtc/rtc0/charging_voltage` prints `3000000`. Once fitted, move the dtparam into the Pi 5 block of the base playbook. Never use a non-rechargeable CR2032.

---

## Ad-hoc commands

```bash
./cmd -m ping --limit mypi
./cmd -m shell -a "uptime" --limit mypi                          # as root
./cmd -m shell -a "whoami" --limit mypi -e "ansible_become=false" # as pi
make sh                                                           # SSH in (uses PI_HOST from .env)
make reboot
```

## Temperature and throttling

```bash
ssh mypi-lan vcgencmd measure_temp    # current CPU temp
ssh mypi-lan vcgencmd get_throttled   # 0x0 = never throttled/undervolted
ssh mypi-lan 'watch -n1 vcgencmd measure_temp'   # live, e.g. during a stress test
./play extra status --limit mypi        # temp is in the summary
```

Pi 5 throttles around 80-85 °C; idle with the fan curve is typically 40-50 °C. `get_throttled` bits: `0x1` undervoltage now, `0x50000` undervoltage since boot, `0x20000` throttling since boot.

## Power off / reboot

Always shut down cleanly; do not just pull power (SD-card corruption).

```bash
make poweroff                           # or: ssh mypi-lan sudo poweroff
make reboot                             # or: ssh mypi-lan sudo reboot
```

Wait for the green activity LED to stop blinking (~10 s) before cutting power. There is no soft power-on: replug power or press the Pi 5 onboard power button. Never power off remotely unless someone can reach the plug/button.

## Troubleshooting

**"Missing sudo password" / Ansible suddenly cannot escalate.**
A Pi OS package upgrade (raspberrypi-sys-mods, Sept 2026) removed the stock NOPASSWD rule. Restore it once with the password you set in Imager:

```bash
ssh -t mypi.local "echo 'pi ALL=(ALL) NOPASSWD: ALL' | sudo tee /etc/sudoers.d/010_pi-nopasswd >/dev/null && sudo chmod 440 /etc/sudoers.d/010_pi-nopasswd"
```

The base playbook now maintains this file (`--tags sudo`), so it cannot happen again after the first base run.

**"Permission denied (publickey)" from Ansible but `ssh` works.**
`SSH_KEY` in `.env` points at the wrong key. Ansible ignores `~/.ssh/config`.

**A task that should run as `pi` runs as root.**
The inventory sets `ansible_become: true`, which overrides `become: false` on a task. Use
```yaml
vars:
  ansible_become: false
```
on the task instead. User-session tools (`rpi-connect`, `systemctl --user`) also need `XDG_RUNTIME_DIR` and `DBUS_SESSION_BUS_ADDRESS`; see `ansible/extras/tasks/rpi-connect-signin.yml`.

**Raspberry Pi Connect shows "Signed in: no" after Imager set it up.**
The Imager auth key is short-lived and was already expired by the time the Pi first reached the network. Sign in again with section 5b.

**`<name>.local` does not resolve after a rename.**
Wait a few seconds for avahi, then `dns-sd -G v4 <name>.local` on the Mac. If still nothing: `./cmd -m shell -a "systemctl restart avahi-daemon" --limit mypi` using the IP as `PI_HOST`.

**`--check` fails on a fresh Pi at the UFW or Tailscale step.**
Expected: check mode cannot install the package the next task needs. Run for real.

**Tailscale problems** (Ansible hangs at "Gathering Facts", port 2222, exit node).
See [TAILSCALE.md, Troubleshooting](TAILSCALE.md#troubleshooting).

**Locked out of SSH entirely.**
Use another remote access path from section 5 (Tailscale SSH or the Connect remote shell), then fix `sshd_config`, `ufw status`, or `fail2ban-client unban <ip>`.
