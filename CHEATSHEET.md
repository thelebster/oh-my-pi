# Raspberry Pi Cheatsheet

## Temperature & Throttling

```bash
vcgencmd measure_temp          # CPU temperature
vcgencmd get_throttled         # Throttle status (0x0 = good)
vcgencmd measure_volts         # Core voltage
vcgencmd measure_clock arm     # CPU frequency
```

Throttle flags: `0x50000` = throttled, `0x50005` = under-voltage

## Hardware Info

```bash
cat /proc/cpuinfo              # CPU details
cat /proc/meminfo              # Memory info
lscpu                          # CPU architecture
free -h                        # Memory usage
df -h                          # Disk usage
lsblk                          # Block devices
pinout                         # GPIO pinout diagram
```

## System

```bash
uptime                         # Uptime and load
hostnamectl                    # Hostname and OS info
uname -a                       # Kernel version
cat /etc/os-release            # OS version
```

## Services

```bash
systemctl status <service>     # Service status
systemctl restart <service>    # Restart service
systemctl enable <service>     # Enable on boot
journalctl -u <service> -f     # Follow service logs
```

## Network

```bash
ip addr                        # IP addresses
hostname -I                    # Just the IPs
curl -s ifconfig.me            # External/public IP
ss -tulpn                      # Listening ports
ping -c 3 google.com           # Test connectivity
```

## Docker

```bash
docker ps                          # running containers
docker logs -f <container>         # follow logs
docker stats                       # resource usage
docker system prune -a             # clean up everything
```

## Nginx

```bash
nginx -t                           # test config
systemctl reload nginx             # reload config
journalctl -u nginx -f             # follow logs
```

## Claude Code

```bash
claude                             # interactive mode
claude -p "prompt"                 # one-shot
claude /login                      # authenticate
```

Requires `USE_BUILTIN_RIPGREP=0` on Pi 5 (16KB page size).

## Stress Testing

```bash
stress-ng --cpu 4 --timeout 60s   # CPU stress (test fan)
sysbench cpu run                   # CPU benchmark
sysbench memory run                # memory benchmark
iperf3 -s                          # network server
iperf3 -c <server-ip>              # network client
```

## AI HAT+ & Camera

| Component | Model | Details |
|-----------|-------|---------|
| AI accelerator | [Raspberry Pi AI HAT+](https://www.raspberrypi.com/products/ai-hat-plus/) | Hailo-8, 26 TOPS |
| Camera | [Camera Module 3](https://www.raspberrypi.com/products/camera-module-3/) | IMX708, 12MP |

```bash
hailortcli fw-control identify     # Hailo device info
rpicam-hello --list-cameras        # camera detection
rpicam-hello -t 5000               # camera preview (5s)
rpicam-still -o photo.jpg          # photo
rpicam-vid -t 10000 -o video.h264  # video (10s)
dmesg | grep -i hailo              # kernel logs
lspci | grep -i hailo              # PCIe detection
```

AI demo scripts (installed to `~/scripts/`, Ctrl+C to stop):

```bash
~/scripts/ai-demo-detect.sh        # object detection (YOLOv8)
~/scripts/ai-demo-pose.sh          # pose estimation (YOLOv8)
~/scripts/ai-demo-faces.sh         # person & face detection (YOLOv5)
~/scripts/ai-demo-segment.sh       # image segmentation (YOLOv5)
```

- [AI HAT+ docs](https://www.raspberrypi.com/documentation/accessories/ai-hat-plus.html)
- [AI software guide](https://www.raspberrypi.com/documentation/computers/ai.html)
- [Hailo RPi5 examples](https://github.com/hailo-ai/hailo-rpi5-examples)
- [Hailo Model Explorer](https://hailo.ai/products/hailo-software/model-explorer/)

## Cloudflare Tunnel

On the Pi (managed by playbook):

```bash
systemctl status cloudflared     # Tunnel service status
journalctl -u cloudflared -f     # Follow tunnel logs
cloudflared version              # Installed version
```

On local machine — install `cloudflared` and add to `~/.ssh/config`:

```
Host mypi-tunnel
    ProxyCommand cloudflared access ssh --hostname ssh.example.com
    User pi
    IdentityFile ~/.ssh/mypi
```

Then connect with `ssh mypi-tunnel`.

**Note:** SSH and HTTP cannot share the same hostname — use separate subdomains (e.g. `ssh.example.com` for SSH, `mypi.example.com` for HTTP). This is a Cloudflare Tunnel routing limitation.

References:
- [Many services, one cloudflared](https://blog.cloudflare.com/many-services-one-cloudflared/)
- [Expose multiple services on single host](https://community.cloudflare.com/t/expose-multiple-services-on-single-host-in-cloudflare-tunnels/486973)
- [Multiple services on multiple subdomains through 1 tunnel](https://community.cloudflare.com/t/multiple-services-on-multiple-subdomains-through-1-tunnel/772328)

## Cloudflare DDNS

```bash
crontab -l | grep cloudflare       # check cron
cat /etc/cloudflare-ddns.env       # check config
/usr/local/bin/cloudflare-ddns.sh  # manual update
```

## SSH & Security

```bash
fail2ban-client status sshd        # banned IPs and stats
fail2ban-client set sshd unbanip <ip>  # unban an IP
journalctl -u fail2ban -f          # follow logs
```

## Troubleshooting

**DNS not resolving after tunnel setup/removal:**

Your local DNS may cache negative responses. Verify the record exists on Cloudflare:
```bash
dig @1.1.1.1 ssh-mypi.example.com +short
```

If it resolves there but not locally, flush your DNS cache:
```bash
# macOS
sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder
```

If still not resolving, your router may be caching. Reboot the router or temporarily switch DNS to `1.1.1.1` in System Settings → Network → Wi-Fi → DNS.

**SSH "no such host":**

Ensure the hostname in `~/.ssh/config` ProxyCommand matches the actual DNS record. Check with:
```bash
dig @1.1.1.1 <your-ssh-hostname> +short
```

## Tor Hidden Service

```bash
systemctl status tor               # service status
journalctl -u tor -f               # follow logs
cat /var/lib/tor/hidden_service/hostname  # .onion address
```

### Vanity .onion Address

Generate a custom-prefix .onion address using [mkp224o](https://github.com/cathugger/mkp224o). Run on your Mac for faster generation (Pi 5 works too, just slower).

**Install mkp224o (macOS):**

```bash
brew install autoconf libsodium
git clone https://github.com/cathugger/mkp224o
cd mkp224o
./autogen.sh && ./configure && make
```

**Generate:**

```bash
./mkp224o -d output -n 1 mypi     # find 1 address starting with "mypi"
```

Approximate times (per character of prefix):
- 3 chars: seconds
- 4 chars: minutes
- 5 chars: tens of minutes
- 6+ chars: hours to days

**Deploy to Pi:**

Place generated keys in `.tor/` at the project root, then set in `.env`:

```bash
TOR_VANITY_KEYS_DIR=.tor/mypixxxxxxx.onion
```

Run the playbook:

```bash
./play extra tor
```

Alternatively, set `TOR_VANITY_PREFIX=mypi` to generate directly on the Pi (no `TOR_VANITY_KEYS_DIR` needed).

## Updates

```bash
sudo apt update && sudo apt upgrade -y
sudo apt autoremove -y
sudo reboot
```
