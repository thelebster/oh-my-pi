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
ss -tulpn                      # Listening ports
ping -c 3 google.com           # Test connectivity
```

## Updates

```bash
sudo apt update && sudo apt upgrade -y
sudo apt autoremove -y
sudo reboot
```
