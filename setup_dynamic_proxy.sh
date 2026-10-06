#!/usr/bin/env bash
#
# setup_dynamic_proxy.sh
# Final verified transparent proxy router.
# Leaves /etc/resolv.conf and /etc/redsocks.conf completely untouched.

set -euo pipefail

if [ "${EUID}" -ne 0 ]; then
    echo "[!] Please run as root: sudo bash $0"
    exit 1
fi

echo "[*] Step 1: Installing required packages..."
while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
    sleep 2
done
apt update -y
apt install -y redsocks iptables proxychains4 curl gawk

echo "[*] Step 2: Verifying /etc/redsocks.conf..."
if [ ! -f /etc/redsocks.conf ]; then
    echo "[!] Error: /etc/redsocks.conf not found. Please create it first."
    exit 1
fi

# Extract proxy IP directly from redsocks.conf to prevent routing loops
PROXY_IP=$(grep -E '^\s*ip\s*=' /etc/redsocks.conf | head -n 1 | awk '{print $3}' | tr -d ';')
echo "    -> Using Proxy IP from redsocks.conf: ${PROXY_IP}"

systemctl restart redsocks
systemctl enable redsocks

echo "[*] Step 3: Cleaning up old tool wrappers and aliases..."
rm -f /usr/local/bin/apt \
      /usr/local/bin/apt-get \
      /usr/local/bin/git \
      /usr/local/bin/curl \
      /usr/local/bin/wget \
      /usr/local/bin/pip \
      /usr/local/bin/pip3 \
      /usr/local/bin/go

for rc in /root/.bashrc /etc/bash.bashrc; do
    if [ -f "$rc" ]; then
        sed -i '/alias \(apt\|apt-get\|git\|curl\|wget\|pip\|pip3\|go\)=/d' "$rc"
    fi
done
hash -r 2>/dev/null || true

echo "[*] Step 4: Creating the dynamic monitor script (GitHub, Google, Cloudflare)..."
cat << 'EOF' > /usr/local/bin/network_speed_monitor.sh
#!/usr/bin/env bash

LOG_FILE="/var/log/network_speed_monitor.log"
STATUS_FILE="/run/fastest_connection"

# Extract proxy IP directly from redsocks.conf to prevent routing loops
PROXY_IP=$(grep -E '^\s*ip\s*=' /etc/redsocks.conf 2>/dev/null | head -n 1 | awk '{print $3}' | tr -d ';' || true)

# Verified, multi-megabyte download targets (GitHub, Google, Cloudflare)
CANDIDATE_URLS=(
    "https://codeload.github.com/six2dez/reconftw/tar.gz/refs/heads/main"
    "https://dl.google.com/android/repository/platform-tools-latest-linux.zip"
    "https://speed.cloudflare.com/__down?bytes=10485760"
)

enable_transparent_proxy() {
    iptables -t nat -N REDSOCKS 2>/dev/null || iptables -t nat -F REDSOCKS
    
    # Bypass local, private networks, and redsocks process itself
    iptables -t nat -A REDSOCKS -d 127.0.0.0/8 -j RETURN
    iptables -t nat -A REDSOCKS -d 192.168.0.0/16 -j RETURN
    iptables -t nat -A REDSOCKS -d 10.0.0.0/8 -j RETURN
    iptables -t nat -A REDSOCKS -m owner --uid-owner redsocks -j RETURN
    [ -n "${PROXY_IP}" ] && iptables -t nat -A REDSOCKS -d "${PROXY_IP}" -j RETURN

    # Redirect HTTP (80), HTTPS (443), and Git SSH (22) to redsocks
    iptables -t nat -A REDSOCKS -p tcp --dport 80 -j REDIRECT --to-ports 12345
    iptables -t nat -A REDSOCKS -p tcp --dport 443 -j REDIRECT --to-ports 12345
    iptables -t nat -A REDSOCKS -p tcp --dport 22 -j REDIRECT --to-ports 12345

    # Attach to OUTPUT chain
    iptables -t nat -C OUTPUT -p tcp -j REDSOCKS 2>/dev/null || iptables -t nat -I OUTPUT -p tcp -j REDSOCKS
}

disable_transparent_proxy() {
    while iptables -t nat -D OUTPUT -p tcp -j REDSOCKS 2>/dev/null; do :; done
    iptables -t nat -F REDSOCKS 2>/dev/null || true
}

# 1. Dynamically select the fastest responding server of the real targets
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

# 2. Benchmark sustained download throughput
measure_speed() {
    local use_proxy="$1"
    local speed=0

    if [ "$use_proxy" = "true" ]; then
        speed=$(proxychains4 -q /usr/bin/curl -s -L -o /dev/null -w "%{speed_download}" --connect-timeout 4 --max-time 5 "${TEST_URL}" 2>/dev/null || echo 0)
    else
        speed=$(/usr/bin/curl -s -L -o /dev/null -w "%{speed_download}" --connect-timeout 4 --max-time 5 "${TEST_URL}" 2>/dev/null || echo 0)
    fi

    speed=$(echo "${speed}" | tr -dc '0-9.' | tail -n 1)
    [[ -z "${speed}" || ! "${speed}" =~ ^[0-9]+(\.[0-9]+)?$ ]] && speed=0
    echo "${speed}"
}

# 3. Benchmark both connections
disable_transparent_proxy
DIRECT_SPEED=$(measure_speed false)
PROXY_SPEED=$(measure_speed true)

# 4. Compare speeds (proxy wins ties)
DECISION=$(awk -v p="${PROXY_SPEED}" -v d="${DIRECT_SPEED}" 'BEGIN {
    if (p > 0 && p >= d) {
        print "proxy"
    } else {
        print "direct"
    }
}')

# 5. Apply transparent redirection if proxy won
if [ "${DECISION}" = "proxy" ]; then
    enable_transparent_proxy
else
    disable_transparent_proxy
fi

echo -n "${DECISION}" > "${STATUS_FILE}.tmp"
mv -f "${STATUS_FILE}.tmp" "${STATUS_FILE}"

# 6. Format and log in MiB/s
DIRECT_MB=$(awk -v s="${DIRECT_SPEED}" 'BEGIN { printf "%.2f", s / 1048576 }')
PROXY_MB=$(awk -v s="${PROXY_SPEED}" 'BEGIN { printf "%.2f", s / 1048576 }')
TARGET_HOST=$(echo "${TEST_URL}" | awk -F[/:] '{print $4}')

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Target: ${TARGET_HOST} | Direct: ${DIRECT_MB} MiB/s | Proxy: ${PROXY_MB} MiB/s | Winner: ${DECISION}" >> "${LOG_FILE}"
EOF

chmod +x /usr/local/bin/network_speed_monitor.sh

echo "[*] Step 5: Configuring background systemd timer..."
cat << 'EOF' > /etc/systemd/system/network-speed-monitor.service
[Unit]
Description=Network Speed Benchmark Monitor
After=network-online.target redsocks.service
Wants=network-online.target redsocks.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/network_speed_monitor.sh
EOF

cat << 'EOF' > /etc/systemd/system/network-speed-monitor.timer
[Unit]
Description=Periodic check for proxychains connectivity

[Timer]
OnBootSec=20s
OnUnitActiveSec=10min
AccuracySec=1min

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now network-speed-monitor.timer

echo "[*] Step 6: Running initial benchmark..."
/usr/local/bin/network_speed_monitor.sh

CURRENT_STATUS=$(cat /run/fastest_connection)
echo "=========================================================="
echo "Setup successfully completed!"
echo "Active Route: ${CURRENT_STATUS}"
tail -n 1 /var/log/network_speed_monitor.log
echo "=========================================================="
