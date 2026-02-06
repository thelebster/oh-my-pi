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

## Updates

```bash
sudo apt update && sudo apt upgrade -y
sudo apt autoremove -y
sudo reboot
```
