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

1. Go to [Cloudflare Zero Trust](https://one.dash.cloudflare.com/) → Networks → Tunnels → Create
2. Name your tunnel and copy the token
3. Add to `.env`:
   ```
   CF_TUNNEL_TOKEN=eyJ...
   ```
4. Configure public hostnames in the dashboard (e.g. `ssh.example.com → ssh://localhost:22`)
5. Run `make run` or `ansible-playbook ansible/playbook.yml --tags tunnel`

Removing `CF_TUNNEL_TOKEN` from `.env` and re-running will stop and uninstall the tunnel service.

## Optional: Cloudflare DDNS

Updates a Cloudflare DNS A record with the Pi's public IP every 5 minutes. Useful when your ISP allows port forwarding but assigns a dynamic IP.

1. Create a Cloudflare API token with Zone DNS edit permissions
2. Add to `.env`:
   ```
   CF_API_TOKEN=your-token
   CF_ZONE_ID=your-zone-id
   CF_DOMAIN=pi.example.com
   ```
3. Run `make run` or `ansible-playbook ansible/playbook.yml --tags ddns`

Removing `CF_API_TOKEN` from `.env` and re-running will remove the cron job and scripts from the Pi.

## Running without Make

Source `.env` first to load env vars:

```bash
source .env && ansible-playbook ansible/playbook.yml --tags "tunnel,ssh"
```

Available tags: `updates`, `eeprom`, `locale`, `docker`, `nginx`, `claude`, `stress`, `connect`, `fan`, `ddns`, `tunnel`, `ssh`, `status`
