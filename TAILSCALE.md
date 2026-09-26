# Tailscale Exit Node Pi

Complete guide, from a blank SD card to a Pi that works as a Tailscale **exit node** (route your Mac or phone through the Pi's internet connection from anywhere) and stays reachable over **two independent SSH paths**, even when nobody can walk up to it.

Self-contained on purpose: it repeats the generic steps from [PROVISIONING.md](PROVISIONING.md), so you never have to switch files. Examples use the inventory host `mypi` with the device hostname `mypi`; put your real names in `.env`.

## Quick reference

```bash
./play extra status --limit mypi                               # status summary
./play extra tailscale --limit mypi                            # install / update
./play extra tailscale --limit mypi --tags status              # Tailscale status
./play extra tailscale --limit mypi --tags config              # re-apply settings
./play extra tailscale --limit mypi --tags tailscale-remove    # remove
./cmd -m ping --limit mypi                                     # test connection

ssh -p 2222 -i ~/.ssh/mypi pi@mypi                             # SSH main: key-based sshd
ssh pi@mypi                                                    # SSH backup: Tailscale SSH

tailscale set --exit-node=mypi                                 # Mac: route traffic through the Pi
tailscale set --exit-node=                                     # Mac: stop
```

---

## What you get

| Path | Command | Auth | Handled by | Survives |
|------|---------|------|------------|----------|
| **Main** | `ssh -p 2222 pi@mypi` (Ansible via `PI_SSH_PORT=2222`) | `~/.ssh/mypi` key | sshd | Tailscale SSH or policy problems |
| **Backup** | `ssh pi@mypi` (port 22) | tailnet login + [policy](#6-tailscale-ssh-policy) | tailscaled | broken `sshd_config`, lost key, fail2ban, UFW |
| **Last resort** | browser shell at https://connect.raspberrypi.com | Raspberry Pi ID | rpi-connect | anything SSH-related |
| LAN | `ssh pi@mypi.local` (port 22) | `~/.ssh/mypi` key | sshd | only at home |

- With Tailscale SSH on, tailscaled owns **port 22 on the tailnet IP**. The tailscale extra therefore makes sshd also listen on **2222** (`/etc/ssh/sshd_config.d/60-tailnet-port.conf`). Port 22 stays on sshd for the LAN.
- UFW allows all of `tailscale0`, so 2222 is reachable over the tailnet only, never from the LAN or internet.
- The Pi needs no public IP and no port forwarding: everything rides the Tailscale tunnel.

---

## 1. Before you start

- Raspberry Pi Imager on the Mac.
- An SSH key pair for the Pi: `ssh-keygen -t ed25519 -f ~/.ssh/mypi`
- This repo cloned, `.env` created from `.env.example`.
- A Tailscale account, and the Tailscale app on the Mac (and phone).
- A Tailscale auth key: https://login.tailscale.com/admin/settings/keys, **reusable**, **pre-authorized**, not ephemeral.
- Optional, for the last-resort shell: a Raspberry Pi Connect auth key, https://connect.raspberrypi.com, **Settings**, **Auth keys**.

## 2. Flash the card

In Raspberry Pi Imager, choose Pi OS Lite, then in **OS customisation**:

| Setting | Value |
|---|---|
| Hostname | e.g. `mypi` (also becomes the Tailscale name) |
| Username | `pi` |
| Password | set one (needed once to restore sudo if an upgrade removes it, see Troubleshooting) |
| SSH | enabled, **public-key auth only**, paste the contents of `~/.ssh/mypi.pub` |
| Wi-Fi | only if the Pi will not be on ethernet |

Boot the Pi on your LAN and wait a minute for first boot to finish.

## 3. `.env`

```
# Pi (LAN for now; switched to the tailnet in step 9)
PI_HOST=mypi.local
PI_USER=pi
PI_HOSTNAME=mypi
SSH_KEY=~/.ssh/mypi

# Tailscale
TAILSCALE_AUTH_KEY=tskey-auth-...
TAILSCALE_SSH=true

# Raspberry Pi Connect (optional)
RPI_CONNECT_AUTH_KEY=...
```

| Variable | Purpose |
|----------|---------|
| `PI_HOST` | Where Ansible connects: `mypi.local` (LAN only) or the MagicDNS name `mypi` (anywhere). |
| `PI_SSH_PORT` | Ansible SSH port. Empty = 22. `2222` = main path over the tailnet (step 9). |
| `SSH_KEY` | Key for sshd (main and LAN paths). Must be the key pasted into Imager. Not used by Tailscale SSH. |
| `TAILSCALE_AUTH_KEY` | Joins the Pi to the tailnet. Only used for the first join. |
| `TAILSCALE_SSH` | `true` = Tailscale SSH (backup path) plus sshd on the tailnet port. |
| `TAILSCALE_SSHD_PORT` | sshd port on the tailnet while Tailscale SSH owns 22. Default `2222`. |
| `RPI_CONNECT_AUTH_KEY` | Non-interactive Raspberry Pi Connect sign-in. |

Ansible does **not** read `~/.ssh/config`, only `.env`.

Test the LAN connection:

```bash
ssh -i ~/.ssh/mypi pi@mypi.local hostname
./cmd -m ping --limit mypi
./cmd -m command -a "id -u" --limit mypi     # must print 0 = passwordless sudo works
```

## 4. Base setup

```bash
./play --limit mypi --check     # dry run (the ufw step fails in check mode on a fresh Pi, that is expected)
./play --limit mypi             # apply: updates, UFW, sudo guard, SSH hardening, fail2ban, Pi 5 fan + EEPROM
```

If the recap says a reboot is required, do it now, while the Pi is still next to you:

```bash
./cmd -m shell -a "systemctl reboot" --limit mypi
./cmd -m ping --limit mypi      # ~20 s later
```

## 5. Locale (optional)

Stops the `setlocale: LC_CTYPE` warnings from macOS Terminal:

```bash
./play extra locale --limit mypi
```

## 6. Tailscale SSH policy

Do this **before** the tailscale extra. The default tailnet policy runs Tailscale SSH in **check** mode: a browser login every 12 h. Ansible hides the login URL, so any `./play` / `./cmd` over Tailscale SSH just hangs at "Gathering Facts". Switch it to **accept**:

1. Open https://login.tailscale.com/admin/acls.
2. Either **visual editor**: **Tailscale SSH** tab, the `autogroup:member → autogroup:self` rule, **⋯**, **Edit**, turn **check mode** off, save. The "with check mode" column is then empty.

   Or **JSON editor**: change `"action": "check"` to `"action": "accept"` in that rule (drop any `checkPeriod`), so the `"ssh"` section reads:
   ```json
   "ssh": [
     {
       // Tailnet members may SSH into their own devices, no browser check.
       "action": "accept",
       "src":    ["autogroup:member"],
       "dst":    ["autogroup:self"],
       "users":  ["autogroup:nonroot", "root"]
     }
   ],
   ```
3. **Save**. It applies to the next connection, nothing changes on the Pi.

| Field | Meaning |
|-------|---------|
| `action` | `accept` = no re-auth. `check` = browser login every `checkPeriod` (default `12h`, e.g. `"checkPeriod": "168h"` for weekly) |
| `src` | Who connects: `autogroup:member` = any user signed in to the tailnet |
| `dst` | Which devices: `autogroup:self` = devices owned by the connecting user (a Pi joined with your auth key is yours; use `"tag:<name>"` for tagged devices) |
| `users` | Which Linux users: `autogroup:nonroot` = any non-root user (`pi`), `root` = root too (drop it to forbid) |

Trade-off: with `accept`, any device signed in to your tailnet gets a shell on the Pi without re-authenticating. Fine for a personal tailnet. Keep `check` if other people share it.

## 7. Install Tailscale

```bash
./play extra tailscale --limit mypi
```

Installs Tailscale, enables IP forwarding, opens UFW for `tailscale0`, adds sshd port 2222 (validated before reload, rolled back on failure), joins the tailnet and advertises the exit node.

Then in the admin console, https://login.tailscale.com/admin/machines, the Pi, **⋯**:

1. **Edit route settings**, tick **Use as exit node**.
2. **Disable key expiry**. Otherwise the node key expires after 180 days and the Pi drops off the tailnet until someone re-authenticates on it locally.

## 8. Verify both SSH paths

```bash
./play extra tailscale --limit mypi --tags status    # "exit node: advertised + approved", "sshd ports: 22,2222"
ssh -p 2222 -i ~/.ssh/mypi pi@mypi true              # main: key-based sshd
ssh pi@mypi true                                     # backup: Tailscale SSH, no login URL
```

## 9. Switch Ansible to the main path

Only after step 8's `ssh -p 2222` works. In `.env`:

```
PI_HOST=mypi
PI_SSH_PORT=2222
```

```bash
./cmd -m ping --limit mypi
./play extra status --limit mypi     # no browser login
```

From now on Ansible works from anywhere, with your key, independent of the Tailscale SSH policy.

## 10. Raspberry Pi Connect (last resort)

A browser shell that does not go through sshd or Tailscale at all.

```bash
./play extra connect-headless --limit mypi
```

Without `RPI_CONNECT_AUTH_KEY` the extra prints the interactive fallback: `ssh -t pi@mypi.local rpi-connect signin`. Then check https://connect.raspberrypi.com/devices.

## 11. Final checklist before the Pi leaves the building

- Wi-Fi needed at the destination? Save the profile now:
  ```bash
  ./cmd -m shell -a "nmcli device wifi connect 'SSID' password 'PASS'" --limit mypi
  ```
- Admin console shows **Expiry disabled** and **Exit Node** on the machine.
- https://connect.raspberrypi.com/devices shows the Pi online.

```bash
./play --limit mypi                                  # base converged, 0 changed
./play extra status --limit mypi                     # fail2ban active, tailscaled active
./play extra tailscale --limit mypi --tags status    # advertised + approved, sshd ports 22,2222
ssh -p 2222 -i ~/.ssh/mypi pi@mypi hostname          # main
ssh pi@mypi hostname                                 # backup
```

---

## Using the exit node

**Mac** (Tailscale app or CLI):

```bash
tailscale exit-node list                   # the Pi should be listed
tailscale set --exit-node=mypi             # route all traffic through the Pi
curl -s https://ifconfig.me                # shows the Pi's public IP
tailscale set --exit-node=                 # stop
```

Add `--exit-node-allow-lan-access` to keep reaching your local network (printer, NAS) while routed.

**iPhone / Android**: Tailscale app, **Exit Node**, pick `mypi`. Pick **None** to stop.

While the Mac routes through the Pi, a reboot of the Pi also cuts the Mac's internet until the Pi is back (or the exit node is turned off).

## SSH aliases (optional)

`~/.ssh/config`. Do **not** add a `Host mypi` block: it would also catch `ssh pi@mypi` and send the Tailscale SSH backup to port 2222.

```
Host mypi-remote                     # main: key-based sshd over the tailnet, works anywhere
    HostName mypi
    Port 2222
    IdentityFile ~/.ssh/mypi
    User pi

Host mypi-lan                        # LAN only
    HostName mypi.local
    IdentityFile ~/.ssh/mypi
    User pi
```

Backup needs no alias: `ssh pi@mypi`.

## Tailscale SSH details

From any device signed in to the tailnet (Mac, phone, or the web SSH console under **Machines**):

```bash
ssh pi@mypi               # MagicDNS name
ssh pi@100.x.y.z          # or the tailnet IP (tailscale ip -4 mypi)
```

- No key and no password: tailscaled proves your identity from the tailnet login.
- Accepted by tailscaled, not sshd, and only on the tailnet IP port 22. A broken `sshd_config`, a lost key, fail2ban or UFW do not affect it.
- Who may log in is decided by the [policy](#6-tailscale-ssh-policy).
- `scp` and `rsync` work over it too.
- The first connection stores a host key under `mypi`, separate from the `mypi.local` entry.

---

## Status and removal

```bash
./play extra tailscale --limit mypi --tags status             # state, IP, exit node, SSH, sshd ports, health
./play extra tailscale --limit mypi --tags tailscale-remove   # leave tailnet, uninstall, remove UFW rules + sshd port
```

Remove only from the LAN (`PI_HOST=mypi.local`, `PI_SSH_PORT=` in `.env`): leaving the tailnet cuts every tailnet connection.

---

## Troubleshooting

**Ansible hangs at "Gathering Facts" over Tailscale.**
It is connecting through Tailscale SSH (port 22) in **check** mode and waiting for a browser login whose URL it does not print. Either set the [policy](#6-tailscale-ssh-policy) to accept, use the main path (`PI_SSH_PORT=2222`), or run `ssh pi@mypi true` once to get the URL (valid ~12 h).

**`ssh -p 2222` times out.**
Check over the backup path that sshd listens on 2222 (`sshd ports` must list `2222`):
```bash
./play extra tailscale --limit mypi --tags status
```
If not, rerun `./play extra tailscale --limit mypi --tags config`. UFW must allow `tailscale0`:
```bash
./cmd -m shell -a "ufw status | grep tailscale0" --limit mypi
```

**Exit node listed but not usable.**
Status says "AWAITING APPROVAL": approve it in the admin console (step 7).

**Pi dropped off the tailnet after months.**
Node key expired. Disable key expiry (step 7); to recover, open the Raspberry Pi Connect shell and run:
```bash
sudo tailscale up --advertise-exit-node --ssh --hostname=mypi
```

**"Missing sudo password" / Ansible suddenly cannot escalate.**
A Pi OS package upgrade (raspberrypi-sys-mods, Sept 2026) removed the stock NOPASSWD rule. The base playbook restores it on every run (`--tags sudo`); if it is already gone, restore it once with the Imager password:
```bash
ssh -t -i ~/.ssh/mypi pi@mypi.local "echo 'pi ALL=(ALL) NOPASSWD: ALL' | sudo tee /etc/sudoers.d/010_pi-nopasswd >/dev/null && sudo chmod 440 /etc/sudoers.d/010_pi-nopasswd"
```

**"Permission denied (publickey)" from Ansible but `ssh` works.**
`SSH_KEY` in `.env` points at the wrong key. Ansible ignores `~/.ssh/config`.

**Locked out of SSH entirely.**
Try the other path first: main `ssh -p 2222 pi@mypi` (sshd) or backup `ssh pi@mypi` (Tailscale SSH, independent of sshd). Last resort: the Raspberry Pi Connect shell. Then, on the Pi:
```bash
sudo sshd -t                           # validate sshd_config
sudo ufw status verbose                # 22 and tailscale0 allowed?
sudo fail2ban-client status sshd       # banned IPs
sudo fail2ban-client set sshd unbanip <ip>
```
