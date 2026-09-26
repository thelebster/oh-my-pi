# Oh My Pi

Simple Ansible setup for Raspberry Pi 5.

## What the base playbook installs

The main playbook (`./play`) is a minimal base that is safe to rerun on any Pi:

- System updates + essentials + firewall (ufw: 22, 80, 443) — `updates`
- SSH hardening (fail2ban, password auth and root login disabled) — `ssh`
- Pi 5 only: fan curve — `fan`, EEPROM firmware update — `eeprom`

Everything else (Docker, Nginx, Claude Code, tunnel, DDNS, ...) is an extra playbook you run on demand. See [Extra Playbooks](#extra-playbooks).

## Setup

Guides:
- **[PROVISIONING.md](PROVISIONING.md)** — any Pi, from flashing to remote access and extras.
- **[TAILSCALE.md](TAILSCALE.md)** — a remote Tailscale exit node Pi, start to finish (flash, base, Tailscale, two SSH paths, checklist).

1. Copy `.env.example` to `.env` and fill in your values
2. Run:

```bash
make run
```

## Make Commands

```
make help       Print commands help.
make run        Run the playbook.
make check      Dry run (check mode).
make status     Show versions and service status (status extra).
make ping       Test connection to Pi.
make shell      SSH into Pi.
make ddns       Run Cloudflare DDNS update locally.
make verbose    Run playbook with verbose output.
make tags       List all available tags.
make claude     Run Claude on Pi (JSON output + session ID).
make claude-resume  Resume Claude session (SESSION=<id>).
```

## Raspberry Pi Connect

Remote access via [connect.raspberrypi.com](https://connect.raspberrypi.com).

```bash
./play extra connect-headless --limit mypi   # Pi OS Lite: remote shell only
./play extra connect-desktop --limit mypi    # Pi OS Desktop: shell + screen sharing
```

The extra installs the package, enables the user service (with lingering so it runs without a login), and signs in.

**Non-interactive sign-in:** create an auth key at connect.raspberrypi.com → Settings → Auth keys, put it in `.env` as `RPI_CONNECT_AUTH_KEY`, and rerun the extra.

**Interactive sign-in** (no auth key): the extra prints a hint, then run:

```bash
ssh -t mypi.local rpi-connect signin       # outputs a URL — open in browser to link
rpi-connect status                          # verify on the Pi
```

Then visit https://connect.raspberrypi.com/devices to manage the device.

## Optional: Cloudflare Tunnel

Exposes services (SSH, HTTP, etc.) through Cloudflare without port forwarding. The Pi opens an outbound connection to Cloudflare's edge — no inbound ports needed.

SSH and HTTP cannot share the same hostname — use separate subdomains (e.g. `ssh-mypi.example.com` for SSH, `mypi.example.com` for HTTP).

1. Go to [Cloudflare Zero Trust](https://one.dash.cloudflare.com/) → Networks → Tunnels → Create
2. Name your tunnel and copy the token
3. Create a [Cloudflare API token](https://dash.cloudflare.com/profile/api-tokens) with **Zone DNS Edit** + **Account Cloudflare Tunnel Edit** permissions
4. Add to `.env`:
   ```
   CF_API_TOKEN=your-token
   CF_ZONE_ID=your-zone-id
   CF_TUNNEL_TOKEN=eyJ...
   CF_TUNNEL_SSH_HOST=ssh-mypi
   CF_TUNNEL_HTTP_HOST=mypi
   ```
5. Run `./play extra mypi-tunnel`

The playbook installs `cloudflared`, starts the service, and configures ingress rules + DNS records automatically via the Cloudflare API.

To completely remove the tunnel (ingress, DNS, and service):
```bash
./play extra mypi-tunnel --tags tunnel-remove
```

**Local SSH config** — install `cloudflared` locally and add to `~/.ssh/config`:
```
Host mypi-tunnel
    ProxyCommand cloudflared access ssh --hostname ssh-mypi.example.com
    User pi
    IdentityFile ~/.ssh/mypi
```

## Optional: Cloudflare DDNS

Updates a Cloudflare DNS A record with the Pi's public IP every 5 minutes. Useful when your ISP allows port forwarding but assigns a dynamic IP.

1. Create a Cloudflare API token with Zone DNS edit permissions
2. Add to `.env`:
   ```
   CF_API_TOKEN=your-token
   CF_ZONE_ID=your-zone-id
   CF_DOMAIN=mypi.example.com
   ```
3. Run `./play extra ddns`

To remove DDNS (cron, script, and env file):
```bash
./play extra ddns --tags ddns-remove
```

## Extra Playbooks

Everything beyond the base runs as a separate playbook, so each Pi gets only what it needs:

```bash
./play extra                          # List available extras
./play extra docker --limit mypi      # Install one extra on one host
./play extra docker --check           # Dry run
```

System:
- **hostname** — set hostname from the per-host env var
- **locale** — en_US.UTF-8 for macOS SSH sessions
- **docker** — Docker CE
- **nginx** — Nginx web server
- **claude** — Claude Code CLI + settings + `claude-cmd` wrapper
- **stress** — stress-ng, sysbench, iperf3
- **status** — versions, services, temperature (read-only)
- **tools** — CLI tools (aria2, transmission-cli)
- **network** — nmap, whois, dnsutils, netcat, ...
- **connect-desktop** / **connect-headless** — Raspberry Pi Connect

Network:
- **tailscale** — Tailscale exit node (+ optional Tailscale SSH), auth key from `.env`. Two SSH paths from anywhere: key-based sshd on tailnet port 2222 (main, Ansible via `PI_SSH_PORT=2222`) and Tailscale SSH on 22 (backup). Full guide incl. the SSH policy: **[TAILSCALE.md](TAILSCALE.md)**

Cloudflare:
- **ddns** — Cloudflare DDNS cron (mypi)
- **mypi-tunnel** / **zeropi-tunnel** / **pinas-tunnel** — Cloudflare Tunnel per host (env-var based)
- **tunnel-config** — Cloudflare Tunnel from `ansible/files/cloudflared/<host>/*.yml`

Services (Docker):
- **pihole** — Pi-hole DNS ad blocker
- **jellyfin** — Jellyfin media server
- **home-assistant** — Home Assistant
- **telegram-bot** — Telegram bot with Claude integration, system monitoring

Hardware / host specific:
- **ai-camera** — AI HAT+ (Hailo-8) drivers + Camera Module 3 + rpicam-apps
- **zeropi-camera** / **zeropi-stream** / **zeropi-nginx** — Zero Pi camera stream + HLS cache
- **pinas** / **pinas-networkd** / **pinas-raid1** — Pi NAS (OpenMediaVault, RAID1)
- **tor** — Tor hidden service (.onion) with optional vanity address

## Running without Make

Use the wrapper scripts — they source `.env` automatically:

```bash
./play                          # Run base playbook on all hosts
./play --limit mypi             # Base playbook on one host
./play --tags "ssh"             # Run specific base sections
./play extra docker             # Run an extra playbook
./cmd -m ping                # Ad-hoc: test connection
./cmd -m shell -a 'uptime'   # Ad-hoc: run command
```

Base tags: `updates`, `ssh`, `fan`, `eeprom`

Removal tags (explicit only): `./play extra ddns --tags ddns-remove`, `./play extra mypi-tunnel --tags tunnel-remove`
