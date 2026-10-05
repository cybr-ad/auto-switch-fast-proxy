# ⚡ Dynamic Proxychains Router

> Automatically benchmark and route CLI traffic (`git`, `apt`, `curl`, `wget`) through `proxychains4` whenever the proxy is faster, with seamless fallback to direct internet.

---

## 🚀 Features

- **Zero-Touch Execution**: Run `git clone`, `apt update`, `curl`, or `wget` without typing `proxychains4` manually every time.
- **Dynamic Multi-Server Probing**: Measures latency against Google, GitHub, Kali, and Cloudflare to pick the best benchmark target.
- **Pure Wire-Speed Calculation**: Subtracts connection setup latency so logs reflect your real sustained download speed (e.g., 12+ MiB/s).
- **Instant Failover**: If the proxy drops or slows down, commands automatically fall back to direct internet without failing.
- **Background Daemon**: A lightweight `systemd` timer checks and updates the fastest connection every 10 minutes.

---

## 📦 Quick Setup

### 1. Requirements

```bash
sudo apt update && sudo apt install -y proxychains4 curl git wget
```
*Ensure your proxy is configured in `/etc/proxychains4.conf`.*

---

### 2. Install Monitor Script

Open the file:
```bash
sudo nano /usr/local/bin/network_speed_monitor.sh
```

Paste the following script:

```bash
#!/usr/bin/env bash

STATUS_FILE="/run/fastest_connection"
LOG_FILE="/var/log/network_speed_monitor.log"

CANDIDATE_URLS=(
    "https://dl.google.com/linux/chrome/deb/dists/stable/main/binary-amd64/Packages.gz"
    "https://codeload.github.com/six2dez/reconftw/tar.gz/refs/heads/main"
    "http://http.kali.org/kali/dists/kali-rolling/InRelease"
    "https://speed.cloudflare.com/__down?bytes=5242880"
)

# 1. Dynamically select the fastest responding server
BEST_URL="${CANDIDATE_URLS[0]}"
BEST_TIME=999

for url in "${CANDIDATE_URLS[@]}"; do
    resp_time=$(/usr/bin/curl -s -L -I -o /dev/null -w "%{time_starttransfer}" --connect-timeout 2 --max-time 4 "${url}" 2>/dev/null || echo "999")
    if [[ "$resp_time" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        is_faster=$(awk -v t="${resp_time}" -v b="${BEST_TIME}" 'BEGIN { if (t > 0 && t < b) print 1; else print 0 }')
        if [ "$is_faster" -eq 1 ]; then
            BEST_TIME="$resp_time"
            BEST_URL="$url"
        fi
    fi
done

TEST_URL="${BEST_URL}"

# 2. Measure sustained wire speed
measure_wire_speed() {
    local use_proxy="$1"
    local curl_cmd=(/usr/bin/curl -s -L -o /dev/null --connect-timeout 4 --max-time 12)

    if [ "$use_proxy" = "true" ]; then
        curl_cmd=(proxychains4 -q /usr/bin/curl -s -L -o /dev/null --connect-timeout 4 --max-time 12)
    fi

    local stats
    stats=$("${curl_cmd[@]}" -w "%{size_download} %{time_total} %{time_starttransfer}" "${TEST_URL}" 2>/dev/null || echo "0 0 0")

    awk -v s="${stats}" 'BEGIN {
        split(s, a, " ")
        bytes = a[1] + 0
        total_time = a[2] + 0
        start_transfer = a[3] + 0
        transfer_time = total_time - start_transfer

        if (bytes > 0 && transfer_time > 0.001) {
            printf "%.0f", bytes / transfer_time
        } else {
            print "0"
        }
    }'
}

# 3. Benchmark both connections
DIRECT_SPEED=$(measure_wire_speed false)
PROXY_SPEED=$(measure_wire_speed true)

# 4. Compare speeds (proxy wins ties)
DECISION=$(awk -v p="${PROXY_SPEED}" -v d="${DIRECT_SPEED}" 'BEGIN {
    if (p > 0 && p >= d) {
        print "proxy"
    } else {
        print "direct"
    }
}')

# 5. Atomically update the status file
echo -n "${DECISION}" > "${STATUS_FILE}.tmp"
mv -f "${STATUS_FILE}.tmp" "${STATUS_FILE}"

# 6. Format and log
DIRECT_MB=$(awk -v s="${DIRECT_SPEED}" 'BEGIN { printf "%.2f", s / 1048576 }')
PROXY_MB=$(awk -v s="${PROXY_SPEED}" 'BEGIN { printf "%.2f", s / 1048576 }')
TARGET_HOST=$(echo "${TEST_URL}" | awk -F[/:] '{print $4}')

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Target: ${TARGET_HOST} | Direct: ${DIRECT_MB} MiB/s | Proxy: ${PROXY_MB} MiB/s | Winner: ${DECISION}" >> "${LOG_FILE}"
```

Make it executable:
```bash
sudo chmod +x /usr/local/bin/network_speed_monitor.sh
```

---

### 3. Create Command Wrappers

Run this loop in your terminal to wrap `apt`, `git`, `curl`, and `wget`:

```bash
for cmd in apt apt-get git curl wget; do
    target="/usr/bin/${cmd}"
    wrapper="/usr/local/bin/${cmd}"

    sudo tee "${wrapper}" > /dev/null << EOF
#!/usr/bin/env bash
STATUS="direct"
[ -f /run/fastest_connection ] && STATUS=\$(cat /run/fastest_connection 2>/dev/null || echo "direct")

if [ "\$STATUS" = "proxy" ] && command -v proxychains4 &>/dev/null; then
    exec proxychains4 -q ${target} "\$@"
else
    exec ${target} "\$@"
fi
EOF
    sudo chmod +x "${wrapper}"
done
```

---

### 4. Enable Background Service (`systemd`)

Create the service and timer:

```bash
sudo tee /etc/systemd/system/network-speed-monitor.service > /dev/null << 'EOF'
[Unit]
Description=Network Speed Benchmark Monitor
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/network_speed_monitor.sh
EOF

sudo tee /etc/systemd/system/network-speed-monitor.timer > /dev/null << 'EOF'
[Unit]
Description=Periodic check for proxychains connectivity

[Timer]
OnBootSec=20s
OnUnitActiveSec=10min
AccuracySec=1min

[Install]
WantedBy=timers.target
EOF
```

Enable and start:
```bash
sudo systemctl daemon-reload
sudo systemctl enable --now network-speed-monitor.timer
```

---

## 🔍 Verification

```bash
# 1. Check current route winner
cat /run/fastest_connection

# 2. Check recent speed logs
tail -n 3 /var/log/network_speed_monitor.log

# 3. Test git clone (runs through proxy automatically)
git clone https://github.com/six2dez/reconftw.git /tmp/test-repo --depth=1
rm -rf /tmp/test-repo
```

---

## 🛠 Manual Override

| Action | Command |
|---|---|
| **Force Direct (System-wide)** | `echo "direct" \| sudo tee /run/fastest_connection` |
| **Force Proxy (System-wide)** | `echo "proxy" \| sudo tee /run/fastest_connection` |
| **Bypass Wrapper (Single run)** | `/usr/bin/git clone <url>` or `/usr/bin/curl <url>` |

---

## 🗑️ Uninstallation

To completely remove the setup:

```bash
sudo systemctl disable --now network-speed-monitor.timer 2>/dev/null || true
sudo rm -f /etc/systemd/system/network-speed-monitor.*
sudo systemctl daemon-reload

sudo rm -f /usr/local/bin/apt \
           /usr/local/bin/apt-get \
           /usr/local/bin/git \
           /usr/local/bin/curl \
           /usr/local/bin/wget \
           /usr/local/bin/network_speed_monitor.sh

sudo rm -f /run/fastest_connection /var/log/network_speed_monitor.log
```

