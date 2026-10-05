# auto-switch-fast-proxy


# Dynamic Proxychains Router

A lightweight, automated background router for Kali, Debian, and Ubuntu that transparently runs command-line tools (`git`, `apt`, `curl`, `wget`) through `proxychains4` whenever your proxy is active, with automatic fallback to direct internet if the proxy goes offline.

---

## Features

- **No Manual Prefixing**: Run `git clone`, `apt update`, `curl`, and `wget` normally. You do not need to type `proxychains4` before every command.
- **Proxy-Preferred with Failover**: Always routes through your high-speed proxy by default. If the proxy fails or times out, commands automatically execute over your direct internet connection.
- **Background Health Checks**: A lightweight `systemd` timer checks proxy connectivity periodically in the background.
- **Safe & Non-Intrusive**: Uses standard `/usr/local/bin` wrappers calling `/usr/bin/` system binaries directly. No iptables or kernel modifications required.

---

## Supported Tools

Out of the box, the following commands are automatically routed:
- `git` (including `git clone`, `pull`, `fetch`)
- `apt` & `apt-get`
- `curl`
- `wget`

---

## Quick Setup

### 1. Requirements

Ensure `proxychains4` and `curl` are installed:
```bash
sudo apt update && sudo apt install -y proxychains4 curl git wget

nano /usr/local/bin/network_speed_monitor.sh

chmod +x /usr/local/bin/network_speed_monitor.sh

./usr/local/bin/network_speed_monitor.sh






