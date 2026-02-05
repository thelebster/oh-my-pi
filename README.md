# Oh My Pi

Simple Ansible setup for Raspberry Pi 5.

## What it installs

- System updates + firewall (ufw)
- Docker
- Nginx
- Claude Code CLI
- Stress testing tools (stress-ng, sysbench, iperf3)
- Raspberry Pi Connect
- Cloudflare DDNS
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

## Running without Make

Source `.env` first to load env vars:

```bash
source .env && ansible-playbook ansible/playbook.yml --tags "ddns,ssh"
```

Available tags: `updates`, `eeprom`, `locale`, `docker`, `nginx`, `claude`, `stress`, `connect`, `fan`, `ddns`, `ssh`, `status`
