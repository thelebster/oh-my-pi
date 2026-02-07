# Pi-hole on Raspberry Pi

Network-wide ad blocker running as a Docker container on the Pi.

## Quick Start

1. Set your Pi-hole variables in `.env`:

```bash
PIHOLE_PASSWORD=your-secure-password
PIHOLE_IP=192.168.1.100        # Pi's static IP on your network
PIHOLE_TZ=Asia/Jerusalem       # Your timezone
```

2. Deploy:

```bash
./play extra pihole
```

3. Open the admin UI at `http://<PIHOLE_IP>:8080/admin`

## How It Works

- Pi-hole runs in Docker on port 53 (DNS) and 8080 (web admin)
- Port 8080 is used instead of 80 to avoid conflicts with Nginx
- `systemd-resolved` is stopped to free port 53
- Data is persisted in Docker named volumes (`pihole_data`, `dnsmasq_data`)

## Testing

**From your Mac:**

```bash
# Should resolve normally
dig google.com @mypi.local +short

# Should return 0.0.0.0 (blocked)
dig ads.google.com @mypi.local +short

# Check admin API
curl http://mypi.local:8080/admin/api.php?summary
```

**From the Pi:**

```bash
# Test locally
./cmd -m shell -a "dig google.com @127.0.0.1 +short"

# Check container health
./cmd -m shell -a "docker ps --filter name=pihole"

# Pi-hole built-in status
./cmd -m shell -a "docker exec pihole pihole status"
```

## Troubleshooting

**DNS queries timeout from other devices**

Check UFW allows port 53:

```bash
./cmd -m shell -a "ufw status | grep 53"
```

If missing, redeploy with `./play extra pihole` — it adds the rule automatically.

**"ignoring query from non-local network" in logs**

Pi-hole rejects queries that appear to come from outside its Docker network. The `FTLCONF_dns_listeningMode=all` env var in `docker-compose.yml` fixes this. If you see this error, make sure that variable is set and redeploy.

**Container is running but DNS doesn't resolve**

```bash
# Check Pi-hole logs for errors
./cmd -m shell -a "docker logs pihole --tail 30"

# Check nothing else is using port 53
./cmd -m shell -a "ss -tulnp | grep :53"

# Restart the container
./cmd -m shell -a "docker restart pihole"
```

**Port 53 conflict with systemd-resolved**

The playbook stops `systemd-resolved` automatically. If it gets re-enabled after a reboot:

```bash
./cmd -m shell -a "systemctl stop systemd-resolved && systemctl disable systemd-resolved"
```

## Configure Devices to Use Pi-hole

### Option A: Router-level (recommended)

Set your router's DNS server to the Pi's IP address. All devices on the network will use Pi-hole automatically.

### Option B: Per-device

Set individual device DNS to the Pi's IP address.

## Management

**SSH into the Pi and use Docker commands:**

```bash
# View logs
docker logs pihole

# Restart
docker restart pihole

# Update Pi-hole
cd /opt/pihole && docker compose pull && docker compose up -d

# Access Pi-hole CLI inside the container
docker exec -it pihole pihole
```

**Or use the `cmd` wrapper from your machine:**

```bash
./cmd -m shell -a "docker logs pihole --tail 20"
```

## Redeploy

To redeploy after changing config:

```bash
./play extra pihole
```

## Uninstall

```bash
./cmd -m shell -a "cd /opt/pihole && docker compose down -v"
```

This stops Pi-hole and removes its data volumes. Re-enable `systemd-resolved` if needed:

```bash
./cmd -m shell -a "systemctl enable --now systemd-resolved"
```
