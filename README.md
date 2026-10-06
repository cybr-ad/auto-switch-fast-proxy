

# ⚡ Dynamic Proxychains & BDIX Router

An automated, lightweight background router for Kali, Debian, and Ubuntu that transparently routes all downloads and network connections through your BDIX/SOCKS proxy whenever it is faster, with seamless fallback to direct internet.

---

## 📊 Overview

- **Zero-Touch Execution**: No need to type `proxychains4` or wrap binaries.
- **Kernel-Level Redirection**: All TCP traffic on ports 80 (HTTP), 443 (HTTPS), and 22 (Git SSH) is handled directly by `iptables` and `redsocks`.
- **Works for Every Tool**: Works for `apt`, `git`, `pip`, `go`, `docker`, `curl`, `wget`, browsers, and Python scripts.
- **Dynamic Speed Benchmarks**: Tests Google, GitHub, and Kali every 10 minutes to pick the fastest connection.
- **Automatic Failover**: If the proxy drops, traffic instantly falls back to direct internet.
- **Safe**: Leaves your `/etc/resolv.conf` (DNS) and `/etc/redsocks.conf` completely untouched.

---

## ⚡ Feature Comparison

| Feature | Standard Manual Setup | Dynamic Proxy Router |
| :--- | :--- | :--- |
| **Prefixing Commands** | Must type `proxychains4` every time | **Zero-touch** (automatic) |
| **Supported Tools** | Only tools you manually prefix | **100% of all tools** (`apt`, `git`, `pip`, `go`, etc.) |
| **Failover** | Fails completely if proxy drops | **Instant fallback** to direct internet |
| **Routing Layer** | Application space (`LD_PRELOAD`) | **Kernel space** (transparent `iptables`) |
| **System Settings** | Modifies environment / DNS | **Leaves `/etc/resolv.conf` untouched** |

---

## 🚀 Quick Setup

### 1. Requirements

Install the required tools:
```bash
sudo apt update && sudo apt install -y redsocks iptables proxychains4 curl gawk
```

### 2. Configure Your Proxy

Edit `/etc/redsocks.conf`:
```bash
sudo nano /etc/redsocks.conf
```

Modify the redsocks config file 
`nano /etc/redsocks.conf` and Set your proxy IP, port, and credentials in the `redsocks { ... }` block:
```text
redsocks {
    local_ip = 127.0.0.1;
    local_port = 12345;
    ip = x.x.x.x;
    port = yyyy;
    type = socks5;
    login = "username";
    password = "password";
}
```
Save and exit (`Ctrl+O`, `Enter`, `Ctrl+X`).
Restart services `systemctl restart redsocks`

### 3. Run the Setup Script

Run the installer on your machine:
```bash
chmod +x setup_dynamic_proxy.sh
sudo bash setup_dynamic_proxy.sh
```

---

## 🔍 Verification

Run standard commands normally without typing `proxychains4`:

```bash
# 1. Check your public IP (shows proxy IP if proxy is winning)
curl https://ifconfig.me

# 2. Test high-speed git clone (routes through proxy automatically)
git clone https://github.com/six2dez/reconftw.git /tmp/test-repo --depth=1
rm -rf /tmp/test-repo

# 3. Check current route winner and speed log
cat /run/fastest_connection
tail -n 1 /var/log/network_speed_monitor.log
```

---

## 🗑️ Uninstallation (Restore Default)

To remove all background monitoring and restore factory default routing:

```bash
sudo systemctl disable --now network-speed-monitor.timer 2>/dev/null || true
sudo rm -f /etc/systemd/system/network-speed-monitor.*
sudo systemctl daemon-reload

# Flush iptables redirection
sudo iptables -t nat -D OUTPUT -p tcp -j REDSOCKS 2>/dev/null || true
sudo iptables -t nat -F REDSOCKS 2>/dev/null || true
sudo iptables -t nat -X REDSOCKS 2>/dev/null || true

sudo rm -f /usr/local/bin/network_speed_monitor.sh /run/fastest_connection /var/log/network_speed_monitor.log
```

---

*This project ensures maximum speed from BDIX proxies with zero manual switching. Add your proxy credentials in `/etc/redsocks.conf` and enjoy faster internet 🚀.*








