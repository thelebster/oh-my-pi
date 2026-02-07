# Oh My Pi

Simple Ansible setup for Raspberry Pi 5.

## What it installs

- System updates + firewall (ufw)
- Docker
- Nginx
- Claude Code CLI
- Stress testing tools (stress-ng, sysbench, iperf3)
- Raspberry Pi Connect
- Cloudflare Tunnel (optional) — expose services without port forwarding
- Cloudflare DDNS (optional) — dynamic DNS via Cloudflare API
- SSH hardening (fail2ban, password auth disabled)

## Setup

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
make status     Show versions and service status.
make ping       Test connection to Pi.
make shell      SSH into Pi.
make ddns       Run Cloudflare DDNS update locally.
make verbose    Run playbook with verbose output.
make tags       List all available tags.
```

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
5. Run `make run` or `./play --tags tunnel`

The playbook installs `cloudflared`, starts the service, and configures ingress rules + DNS records automatically via the Cloudflare API.

To completely remove the tunnel (ingress, DNS, and service):
```bash
./play --tags tunnel-remove
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
3. Run `make run` or `./play --tags ddns`

To remove DDNS (cron, script, and env file):
```bash
./play --tags ddns-remove
```

## Extra Playbooks

Optional tool bundles that run separately from the main playbook:

```bash
./play extra                    # List available extras
./play extra network            # Install network tools
./play extra network --check    # Dry run
```

Available extras:
- **ai-camera** — AI HAT+ (Hailo-8) drivers + Camera Module 3 + rpicam-apps
- **network** — nmap, whois, dnsutils, netcat, ...
- **pihole** — Pi-hole DNS ad blocker (Docker)
- **tor** — Tor hidden service (.onion) with optional vanity address

## Running without Make

Use the wrapper scripts — they source `.env` automatically:

```bash
./play                          # Run full playbook
./play --tags "tunnel,ssh"      # Run specific tags
./play extra network            # Run an extra playbook
./cmd -m ping                # Ad-hoc: test connection
./cmd -m shell -a 'uptime'   # Ad-hoc: run command
```

Available tags: `updates`, `eeprom`, `locale`, `docker`, `nginx`, `claude`, `stress`, `connect`, `fan`, `ddns`, `tunnel`, `ssh`, `status`

Removal tags (explicit only): `ddns-remove`, `tunnel-remove`
