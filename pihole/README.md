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
