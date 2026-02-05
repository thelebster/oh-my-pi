# Oh My Pi

Simple Ansible setup for Raspberry Pi 5.

## What it installs

- System updates + firewall (ufw)
- Docker
- Nginx
- Claude Code CLI
- Stress testing tools (stress-ng, sysbench, iperf3)

## Usage

1. Edit `ansible/inventory.ini` with your Pi's IP
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
make verbose    Run playbook with verbose output.
make tags       List all available tags.
make shell      Run shell command on Pi. Usage: make shell "ls -la"
```
