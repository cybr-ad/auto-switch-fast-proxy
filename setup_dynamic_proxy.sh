#!/usr/bin/env bash
#
# setup_dynamic_proxy.sh
# Automated transparent proxy router with dynamic failover and speed benchmark.
# Supports Kali, Debian, and Ubuntu.
#

set -euo pipefail

VERSION="2.3.0"
LOG_FILE="/var/log/network_speed_monitor.log"
STATUS_FILE="/run/fastest_connection"
MONITOR_SCRIPT="/usr/local/bin/network_speed_monitor.sh"
SERVICE_FILE="/etc/systemd/system/network-speed-monitor.service"
TIMER_FILE="/etc/systemd/system/network-speed-monitor.timer"
REDSOCKS_CONF="/etc/redsocks.conf"
RESOLV_CONF="/etc/resolv.conf"

# CLI default options
CLI_IP=""
CLI_PORT=""
CLI_TYPE="socks5"
CLI_USER=""
CLI_PASS=""
CLI_LOCAL_PORT="12345"
CLI_ACTION="install"

show_help() {
    cat << 'EOF'
================================================================================
⚡ Dynamic Proxy Router & Speed Monitor - Setup & Management Utility
================================================================================

Usage:
  sudo bash setup_dynamic_proxy.sh [OPTIONS]

Configuration Options:
  --ip <IP|HOST>        Proxy server IP or hostname
  --port <PORT>         Proxy server port (e.g. 1080, 9169)
  --type <TYPE>         Proxy type: socks5 (default), socks4, http-connect
  --user <USERNAME>     Proxy authentication username (optional)
  --pass <PASSWORD>     Proxy authentication password (optional)
  --local-port <PORT>   Redsocks local listening port (default: 12345)

Management Actions:
  --status              Show current routing status, redsocks health, and logs
  --test                Run speed benchmark now and report results
  --force-proxy         Force enable transparent proxy routing immediately
  --force-direct        Force bypass proxy and route directly to internet
  --uninstall           Completely remove router, services, and restore defaults
  -h, --help            Show this help menu

Examples:
  # Interactive setup wizard (prompts for IP, port, user, pass, or edit via nano):
  sudo bash setup_dynamic_proxy.sh

  # One-liner setup with credentials:
  sudo bash setup_dynamic_proxy.sh --ip 114.130.99.148 --port 9169 --user myuser --pass mypass

  # Check active route and speed benchmark:
  sudo bash setup_dynamic_proxy.sh --status

  # Run speed test:
  sudo bash setup_dynamic_proxy.sh --test
================================================================================
EOF
    exit 0
}

# Parse CLI arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --ip)
            CLI_IP="$2"; shift 2 ;;
        --port)
            CLI_PORT="$2"; shift 2 ;;
        --type)
            CLI_TYPE="$2"; shift 2 ;;
        --user)
            CLI_USER="$2"; shift 2 ;;
        --pass|--password)
            CLI_PASS="$2"; shift 2 ;;
        --local-port)
            CLI_LOCAL_PORT="$2"; shift 2 ;;
        --status)
            CLI_ACTION="status"; shift ;;
        --test|--benchmark)
            CLI_ACTION="test"; shift ;;
        --force-proxy)
            CLI_ACTION="force-proxy"; shift ;;
        --force-direct)
            CLI_ACTION="force-direct"; shift ;;
        --uninstall)
            CLI_ACTION="uninstall"; shift ;;
        -h|--help)
            show_help ;;
        *)
            echo "[!] Unknown option: $1"
            echo "    Run 'sudo bash $0 --help' for options."
            exit 1 ;;
    esac
done

# Action: Status
if [ "${CLI_ACTION}" = "status" ]; then
    if [ -x "${MONITOR_SCRIPT}" ]; then
        exec "${MONITOR_SCRIPT}" --status
    else
        echo "[!] Network monitor script not installed yet. Run setup first."
        exit 1
    fi
fi

# Action: Test / Benchmark
if [ "${CLI_ACTION}" = "test" ]; then
    if [ -x "${MONITOR_SCRIPT}" ]; then
        exec "${MONITOR_SCRIPT}" --benchmark
    else
        echo "[!] Network monitor script not installed yet. Run setup first."
        exit 1
    fi
fi

# Action: Force Proxy
if [ "${CLI_ACTION}" = "force-proxy" ]; then
    if [ -x "${MONITOR_SCRIPT}" ]; then
        exec "${MONITOR_SCRIPT}" --force-proxy
    else
        echo "[!] Network monitor script not installed yet. Run setup first."
        exit 1
    fi
fi

# Action: Force Direct
if [ "${CLI_ACTION}" = "force-direct" ]; then
    if [ -x "${MONITOR_SCRIPT}" ]; then
        exec "${MONITOR_SCRIPT}" --force-direct
    else
        echo "[!] Network monitor script not installed yet. Run setup first."
        exit 1
    fi
fi

# Action: Uninstall
if [ "${CLI_ACTION}" = "uninstall" ]; then
    if [ "${EUID}" -ne 0 ]; then
        echo "[!] Please run as root: sudo bash $0 --uninstall"
        exit 1
    fi
    echo "[*] Uninstalling Dynamic Proxy Router..."
    systemctl disable --now network-speed-monitor.timer 2>/dev/null || true
    systemctl stop network-speed-monitor.service 2>/dev/null || true
    rm -f "${SERVICE_FILE}" "${TIMER_FILE}"
    systemctl daemon-reload 2>/dev/null || true

    # Flush iptables redirection
    echo "[*] Flushing iptables REDSOCKS rules..."
    while iptables -t nat -D OUTPUT -p tcp -j REDSOCKS 2>/dev/null; do :; done
    iptables -t nat -F REDSOCKS 2>/dev/null || true
    iptables -t nat -X REDSOCKS 2>/dev/null || true

    rm -f "${MONITOR_SCRIPT}" "${STATUS_FILE}" "${STATUS_FILE}.tmp" "${LOG_FILE}"
    echo "[✓] Successfully uninstalled. Factory routing restored."
    exit 0
fi

# Require root for installation
if [ "${EUID}" -ne 0 ]; then
    echo "[!] Please run as root: sudo bash $0"
    exit 1
fi

echo "=========================================================="
echo "⚡ Dynamic Proxy Router & Speed Monitor Setup (v${VERSION})"
echo "=========================================================="

# Wait for apt lock if held
wait_for_apt_lock() {
    local max_wait=60
    local waited=0
    while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do
        if [ $waited -ge $max_wait ]; then
            echo "[!] Timeout waiting for apt cache lock."
            break
        fi
        echo "    -> Waiting for apt cache lock to be released..."
        sleep 2
        waited=$((waited + 2))
    done
}

# Step 1: Install required packages
echo "[*] Step 1: Checking and installing required packages..."
wait_for_apt_lock

MISSING_PKGS=()
for pkg in redsocks iptables curl gawk procps nano; do
    if ! dpkg -s "$pkg" >/dev/null 2>&1 && ! command -v "$pkg" &>/dev/null; then
        MISSING_PKGS+=("$pkg")
    fi
done

if [ ${#MISSING_PKGS[@]} -gt 0 ]; then
    echo "    -> Installing missing packages: ${MISSING_PKGS[*]}"
    apt update -y
    apt install -y "${MISSING_PKGS[@]}"
else
    echo "    -> All required packages are already installed."
fi

# Ensure redsocks system user exists
if ! id -u redsocks >/dev/null 2>&1; then
    echo "    -> Creating system user 'redsocks'..."
    useradd -r -s /bin/false -M redsocks 2>/dev/null || true
fi
mkdir -p /run/redsocks
chown -R redsocks:redsocks /run/redsocks 2>/dev/null || true

# Step 2: Configure DNS in /etc/resolv.conf
echo "[*] Step 2: Configuring DNS in /etc/resolv.conf..."
configure_dns() {
    local resolv="${RESOLV_CONF}"
    local existing=""
    if [ -f "$resolv" ] || [ -L "$resolv" ]; then
        cp -L "$resolv" "${resolv}.bak" 2>/dev/null || true
        existing=$(cat "$resolv" 2>/dev/null || true)
        
        # Comment out all active lines, preserving any existing comments
        local commented
        commented=$(echo "$existing" | awk '{
            if ($0 ~ /^[[:space:]]*nameserver[[:space:]]+(1\.1\.1\.1|8\.8\.8\.8)/) {
                # Already target nameservers, skip
            } else if ($0 ~ /^[[:space:]]*#/ || $0 ~ /^[[:space:]]*$/) {
                print $0
            } else {
                print "# " $0
            }
        }')

        rm -f "$resolv"
        cat << EOF > "$resolv"
nameserver 1.1.1.1
nameserver 8.8.8.8

# Original DNS entries (commented out):
${commented}
EOF
    else
        cat << 'EOF' > "$resolv"
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF
    fi
    chmod 644 "$resolv"
    echo "    -> Set nameserver 1.1.1.1 and nameserver 8.8.8.8 in ${RESOLV_CONF}."
}
configure_dns

# Helper: Extract value from redsocks.conf
extract_redsocks_val() {
    local key="$1"
    local file="${REDSOCKS_CONF}"
    [ -f "$file" ] || return 0
    grep -v '^[[:space:]]*//' "$file" | grep -v '^[[:space:]]*/\*' | grep -v '^[[:space:]]*#' | \
    sed -n -E "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*[\"']?([^\"';]+)[\"']?[[:space:]]*;.*/\1/p" | head -n 1
}

# Helper: Check if an IP/host is placeholder or loopback
is_placeholder_host() {
    local h="$1"
    [[ -z "$h" || "$h" == "x.x.x.x" || "$h" == "0.0.0.0" || "$h" == "127.0.0.1" || "$h" == "localhost" || "$h" == *"example"* ]]
}

# Step 3: Configure redsocks
echo "[*] Step 3: Configuring redsocks (/etc/redsocks.conf)..."

read_existing_config() {
    EXISTING_IP="$(extract_redsocks_val 'ip')"
    EXISTING_PORT="$(extract_redsocks_val 'port')"
    EXISTING_TYPE="$(extract_redsocks_val 'type')"
    EXISTING_USER="$(extract_redsocks_val 'login')"
    EXISTING_PASS="$(extract_redsocks_val 'password')"
    EXISTING_LOCAL_PORT="$(extract_redsocks_val 'local_port')"
}
read_existing_config

TARGET_IP="${CLI_IP}"
TARGET_PORT="${CLI_PORT}"
TARGET_TYPE="${CLI_TYPE:-socks5}"
TARGET_USER="${CLI_USER}"
TARGET_PASS="${CLI_PASS}"
TARGET_LOCAL_PORT="${CLI_LOCAL_PORT:-12345}"

# If CLI options were not provided, handle interactive prompts
if [ -z "${TARGET_IP}" ]; then
    if [ -t 0 ]; then
        echo ""
        echo "=================================================="
        echo "⚡ Redsocks Proxy Configuration"
        echo "=================================================="
        echo "Current configuration in ${REDSOCKS_CONF}:"
        echo "  Proxy IP:       ${EXISTING_IP:-[Not set]}"
        echo "  Proxy Port:     ${EXISTING_PORT:-[Not set]}"
        echo "  Proxy User:     ${EXISTING_USER:-[None]}"
        echo "  Proxy Password: $([ -n "${EXISTING_PASS}" ] && echo '******' || echo '[None]')"
        echo "  Proxy Type:     ${EXISTING_TYPE:-socks5}"
        echo "--------------------------------------------------"
        echo "Options:"
        echo "  1) Enter / update IP, Port, Username & Password (Recommended)"
        echo "  2) Open /etc/redsocks.conf in nano to edit manually"
        echo "  3) Keep current settings as-is"
        read -r -p "Select option [1/2/3] (default: 1): " choice_opt
        choice_opt="${choice_opt:-1}"

        if [ "${choice_opt}" = "2" ]; then
            if [ ! -f "${REDSOCKS_CONF}" ]; then
                cat << 'EOF' > "${REDSOCKS_CONF}"
base {
    log_debug = off;
    log_info = on;
    log = "syslog:daemon";
    daemon = on;
    user = redsocks;
    group = redsocks;
    redirector = iptables;
}

redsocks {
    local_ip = 127.0.0.1;
    local_port = 12345;
    ip = 114.130.99.148;
    port = 9169;
    type = socks5;
    // login = "username";
    // password = "password";
}
EOF
            fi
            nano "${REDSOCKS_CONF}"
            read_existing_config
            TARGET_IP="${EXISTING_IP}"
            TARGET_PORT="${EXISTING_PORT:-9169}"
            TARGET_TYPE="${EXISTING_TYPE:-socks5}"
            TARGET_USER="${EXISTING_USER}"
            TARGET_PASS="${EXISTING_PASS}"
            TARGET_LOCAL_PORT="${EXISTING_LOCAL_PORT:-12345}"
        elif [ "${choice_opt}" = "3" ]; then
            TARGET_IP="${EXISTING_IP}"
            TARGET_PORT="${EXISTING_PORT:-9169}"
            TARGET_TYPE="${EXISTING_TYPE:-socks5}"
            TARGET_USER="${EXISTING_USER}"
            TARGET_PASS="${EXISTING_PASS}"
            TARGET_LOCAL_PORT="${EXISTING_LOCAL_PORT:-12345}"
        else
            # Option 1: Direct interactive prompt
            read -r -p "Enter Proxy IP or Host [${EXISTING_IP:-114.130.99.148}]: " in_ip
            TARGET_IP="${in_ip:-${EXISTING_IP:-114.130.99.148}}"

            read -r -p "Enter Proxy Port [${EXISTING_PORT:-9169}]: " in_port
            TARGET_PORT="${in_port:-${EXISTING_PORT:-9169}}"

            read -r -p "Enter Proxy Username (leave blank if none) [${EXISTING_USER:-}]: " in_user
            TARGET_USER="${in_user:-${EXISTING_USER:-}}"

            read -r -p "Enter Proxy Password (leave blank if none) [${EXISTING_PASS:-}]: " in_pass
            TARGET_PASS="${in_pass:-${EXISTING_PASS:-}}"

            read -r -p "Enter Proxy Type (socks5/socks4/http-connect) [${EXISTING_TYPE:-socks5}]: " in_type
            TARGET_TYPE="${in_type:-${EXISTING_TYPE:-socks5}}"
        fi
        echo "=================================================="
    else
        # Non-interactive mode
        if [ -n "${EXISTING_IP}" ] && ! is_placeholder_host "${EXISTING_IP}"; then
            TARGET_IP="${EXISTING_IP}"
            TARGET_PORT="${EXISTING_PORT:-9169}"
            TARGET_TYPE="${EXISTING_TYPE:-socks5}"
            TARGET_USER="${EXISTING_USER}"
            TARGET_PASS="${EXISTING_PASS}"
            TARGET_LOCAL_PORT="${EXISTING_LOCAL_PORT:-12345}"
        else
            echo "[!] No proxy IP specified. Please run:"
            echo "    sudo bash $0 --ip <PROXY_IP> --port <PORT> [--user <USER> --pass <PASS>]"
            exit 1
        fi
    fi
fi

# Validation
if is_placeholder_host "${TARGET_IP}"; then
    echo "[!] Error: Invalid proxy IP: '${TARGET_IP}'"
    exit 1
fi
if [[ -z "${TARGET_PORT}" || ! "${TARGET_PORT}" =~ ^[0-9]+$ ]]; then
    echo "[!] Error: Invalid proxy port: '${TARGET_PORT}'"
    exit 1
fi

# Write /etc/redsocks.conf
echo "    -> Writing redsocks configuration (${REDSOCKS_CONF})..."
cat << EOF > "${REDSOCKS_CONF}"
base {
    log_debug = off;
    log_info = on;
    log = "syslog:daemon";
    daemon = on;
    user = redsocks;
    group = redsocks;
    redirector = iptables;
}

redsocks {
    local_ip = 127.0.0.1;
    local_port = ${TARGET_LOCAL_PORT};
    ip = ${TARGET_IP};
    port = ${TARGET_PORT};
    type = ${TARGET_TYPE};
$([ -n "${TARGET_USER}" ] && echo "    login = \"${TARGET_USER}\";")
$([ -n "${TARGET_PASS}" ] && echo "    password = \"${TARGET_PASS}\";")
}
EOF
chmod 644 "${REDSOCKS_CONF}"

# Restart redsocks service
echo "    -> Restarting redsocks service..."
systemctl restart redsocks 2>/dev/null || /etc/init.d/redsocks restart 2>/dev/null || true
systemctl enable redsocks 2>/dev/null || true
sleep 1

if ! pgrep -x redsocks >/dev/null 2>&1 && ! systemctl is-active --quiet redsocks 2>/dev/null; then
    echo "[!] Warning: redsocks daemon did not start cleanly. Check 'systemctl status redsocks'."
else
    echo "    -> Redsocks is running (local_port=${TARGET_LOCAL_PORT})."
fi

# Step 4: Clean up old wrappers and bashrc aliases
echo "[*] Step 4: Cleaning up old tool wrappers and aliases..."
rm -f /usr/local/bin/apt \
      /usr/local/bin/apt-get \
      /usr/local/bin/git \
      /usr/local/bin/curl \
      /usr/local/bin/wget \
      /usr/local/bin/pip \
      /usr/local/bin/pip3 \
      /usr/local/bin/go

for rc in /root/.bashrc /etc/bash.bashrc /home/*/.bashrc; do
    if [ -f "$rc" ]; then
        sed -i '/alias \(apt\|apt-get\|git\|curl\|wget\|pip\|pip3\|go\)=/d' "$rc" 2>/dev/null || true
        sed -i '/Dynamic Proxychains Aliases/d' "$rc" 2>/dev/null || true
    fi
done
hash -r 2>/dev/null || true

# Step 5: Install the network speed monitor script
echo "[*] Step 5: Installing network speed monitor (/usr/local/bin/network_speed_monitor.sh)..."
cat << 'EOF' > "${MONITOR_SCRIPT}"
#!/usr/bin/env bash
#
# network_speed_monitor.sh
# Benchmarks direct vs proxy connection and manages kernel iptables transparent redirection.
#

set -uo pipefail

LOG_FILE="/var/log/network_speed_monitor.log"
STATUS_FILE="/run/fastest_connection"
REDSOCKS_CONF="/etc/redsocks.conf"

# Extract proxy configuration from redsocks.conf
get_conf_val() {
    local key="$1"
    [ -f "${REDSOCKS_CONF}" ] || return 0
    grep -v '^[[:space:]]*//' "${REDSOCKS_CONF}" | grep -v '^[[:space:]]*/\*' | grep -v '^[[:space:]]*#' | \
    sed -n -E "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*[\"']?([^\"';]+)[\"']?[[:space:]]*;.*/\1/p" | head -n 1
}

PROXY_HOST="$(get_conf_val 'ip')"
PROXY_PORT="$(get_conf_val 'port')"
PROXY_TYPE="$(get_conf_val 'type')"
PROXY_USER="$(get_conf_val 'login')"
PROXY_PASS="$(get_conf_val 'password')"
LOCAL_PORT="$(get_conf_val 'local_port')"
LOCAL_PORT="${LOCAL_PORT:-12345}"

# Resolve PROXY_HOST to IP if hostname
RESOLVED_PROXY_IPS="${PROXY_HOST}"
if [[ -n "${PROXY_HOST}" && ! "${PROXY_HOST}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    lookup_ips=$(getent ahostsv4 "${PROXY_HOST}" 2>/dev/null | awk '{print $1}' | sort -u || true)
    if [ -n "${lookup_ips}" ]; then
        RESOLVED_PROXY_IPS="${lookup_ips}"
    fi
fi

# Determine curl proxy protocol (socks5h resolves DNS remotely through the proxy)
CURL_PROXY_PROTO="socks5h"
case "${PROXY_TYPE}" in
    socks4) CURL_PROXY_PROTO="socks4a" ;;
    http-connect|http) CURL_PROXY_PROTO="http" ;;
    *) CURL_PROXY_PROTO="socks5h" ;;
esac

is_redsocks_alive() {
    if pgrep -x redsocks >/dev/null 2>&1; then
        return 0
    fi
    if systemctl is-active --quiet redsocks 2>/dev/null; then
        return 0
    fi
    return 1
}

enable_transparent_proxy() {
    if ! is_redsocks_alive; then
        systemctl restart redsocks 2>/dev/null || true
        sleep 1
    fi
    if ! is_redsocks_alive; then
        echo "[!] Cannot enable transparent proxy: redsocks daemon is not running!" >> "${LOG_FILE}"
        return 1
    fi

    # Create REDSOCKS chain or flush it
    iptables -t nat -N REDSOCKS 2>/dev/null || iptables -t nat -F REDSOCKS

    # 1. Bypass localhost, loopback, private networks, Docker, LAN (RFC 1918 & RFC 6598)
    iptables -t nat -A REDSOCKS -d 0.0.0.0/8 -j RETURN
    iptables -t nat -A REDSOCKS -d 127.0.0.0/8 -j RETURN
    iptables -t nat -A REDSOCKS -d 10.0.0.0/8 -j RETURN
    iptables -t nat -A REDSOCKS -d 100.64.0.0/10 -j RETURN
    iptables -t nat -A REDSOCKS -d 169.254.0.0/16 -j RETURN
    iptables -t nat -A REDSOCKS -d 172.16.0.0/12 -j RETURN
    iptables -t nat -A REDSOCKS -d 192.168.0.0/16 -j RETURN
    iptables -t nat -A REDSOCKS -d 198.18.0.0/15 -j RETURN
    iptables -t nat -A REDSOCKS -d 224.0.0.0/4 -j RETURN
    iptables -t nat -A REDSOCKS -d 240.0.0.0/4 -j RETURN

    # 2. Bypass redsocks process itself to prevent infinite loop
    if id -u redsocks >/dev/null 2>&1; then
        iptables -t nat -A REDSOCKS -m owner --uid-owner redsocks -j RETURN
    fi

    # 3. Bypass upstream proxy server IPs
    if [ -n "${RESOLVED_PROXY_IPS}" ]; then
        for ip in ${RESOLVED_PROXY_IPS}; do
            iptables -t nat -A REDSOCKS -d "${ip}" -j RETURN
        done
    fi

    # 4. Redirect TCP traffic on ports 80, 443, 22 to redsocks local port
    iptables -t nat -A REDSOCKS -p tcp --dport 80 -j REDIRECT --to-ports "${LOCAL_PORT}"
    iptables -t nat -A REDSOCKS -p tcp --dport 443 -j REDIRECT --to-ports "${LOCAL_PORT}"
    iptables -t nat -A REDSOCKS -p tcp --dport 22 -j REDIRECT --to-ports "${LOCAL_PORT}"

    # 5. Attach REDSOCKS to OUTPUT chain (idempotent)
    iptables -t nat -C OUTPUT -p tcp -j REDSOCKS 2>/dev/null || iptables -t nat -I OUTPUT -p tcp -j REDSOCKS
}

disable_transparent_proxy() {
    while iptables -t nat -D OUTPUT -p tcp -j REDSOCKS 2>/dev/null; do :; done
    iptables -t nat -F REDSOCKS 2>/dev/null || true
    iptables -t nat -X REDSOCKS 2>/dev/null || true
}

is_proxy_routed() {
    iptables -t nat -C OUTPUT -p tcp -j REDSOCKS 2>/dev/null
}

show_status() {
    local cur="direct"
    [ -f "${STATUS_FILE}" ] && cur="$(cat "${STATUS_FILE}" 2>/dev/null || echo "direct")"
    local ipt_status="INACTIVE (Direct)"
    if is_proxy_routed; then
        ipt_status="ACTIVE (Transparent Proxying)"
    fi

    local redsocks_status="DOWN"
    if is_redsocks_alive; then
        redsocks_status="UP (listening on ${LOCAL_PORT})"
    fi

    echo "=========================================================="
    echo "⚡ Network Proxy Status"
    echo "=========================================================="
    echo "Active Decision:  ${cur}"
    echo "Iptables NAT:     ${ipt_status}"
    echo "Redsocks Daemon:  ${redsocks_status}"
    echo "Target Proxy:     ${PROXY_TYPE}://${PROXY_HOST}:${PROXY_PORT}"
    echo "Auth Configured:  $([ -n "${PROXY_USER}" ] && echo "YES (${PROXY_USER})" || echo "NO (anonymous)")"
    echo "----------------------------------------------------------"
    echo "Last Log Entry:"
    if [ -f "${LOG_FILE}" ]; then
        tail -n 1 "${LOG_FILE}"
    else
        echo "  (No logs recorded yet)"
    fi
    echo "=========================================================="
}

# CLI command handling
case "${1:-}" in
    --status)
        show_status
        exit 0 ;;
    --force-proxy)
        echo "[*] Forcing transparent proxy routing ON..."
        enable_transparent_proxy
        echo -n "proxy" > "${STATUS_FILE}"
        echo "[✓] Transparent proxy is now ACTIVE."
        exit 0 ;;
    --force-direct)
        echo "[*] Forcing direct routing ON (disabling proxy)..."
        disable_transparent_proxy
        echo -n "direct" > "${STATUS_FILE}"
        echo "[✓] Direct routing is now ACTIVE."
        exit 0 ;;
    --enable)
        enable_transparent_proxy
        echo -n "proxy" > "${STATUS_FILE}"
        exit 0 ;;
    --disable)
        disable_transparent_proxy
        echo -n "direct" > "${STATUS_FILE}"
        exit 0 ;;
esac

# ----------------- BENCHMARK WORKFLOW -----------------

# Verified candidate targets (BDIX / Kali official CDN, Cloudflare, Google)
CANDIDATE_URLS=(
    "http://kali.download/kali/dists/kali-rolling/Contents-amd64.gz"
    "https://speed.cloudflare.com/__down?bytes=10485760"
    "https://dl.google.com/linux/chrome/deb/dists/stable/main/binary-amd64/Packages.gz"
    "http://http.kali.org/kali/dists/kali-rolling/Contents-amd64.gz"
)

# Measure sustained wire transfer speed (bytes / transfer_time)
measure_wire_speed() {
    local is_proxy="$1"
    local target_url="$2"
    local curl_proto="$3"
    local raw_stats=""
    local curl_opts=(
        "-s"
        "-L"
        "-o" "/dev/null"
        "-w" "%{size_download} %{time_total} %{time_starttransfer} %{speed_download}"
        "--connect-timeout" "4"
        "--max-time" "6"
    )

    if [ "$is_proxy" = "true" ]; then
        if [ -n "${PROXY_HOST}" ] && [ -n "${PROXY_PORT}" ]; then
            local auth_args=()
            if [ -n "${PROXY_USER}" ] || [ -n "${PROXY_PASS}" ]; then
                auth_args=("--proxy-user" "${PROXY_USER}:${PROXY_PASS}")
            fi
            raw_stats=$(/usr/bin/curl "${curl_opts[@]}" --proxy "${curl_proto}://${PROXY_HOST}:${PROXY_PORT}" "${auth_args[@]}" "${target_url}" 2>/dev/null) || true
        fi
    else
        raw_stats=$(/usr/bin/curl "${curl_opts[@]}" "${target_url}" 2>/dev/null) || true
    fi

    # Calculate actual wire transfer rate: size_download / (time_total - time_starttransfer)
    awk -v s="${raw_stats}" 'BEGIN {
        split(s, a, " ")
        bytes = a[1] + 0
        total_time = a[2] + 0
        start_time = a[3] + 0
        avg_speed = a[4] + 0
        transfer_time = total_time - start_time

        if (bytes > 0 && transfer_time > 0.05) {
            printf "%.0f", bytes / transfer_time
        } else if (avg_speed > 0) {
            printf "%.0f", avg_speed
        } else {
            print "0"
        }
    }'
}

# Temporarily disable redirection during measurement
disable_transparent_proxy

# Diagnostic pre-check: Test proxy handshake and connectivity
PROXY_HANDSHAKE_OK="false"
PROXY_HANDSHAKE_ERR=""

if [ -n "${PROXY_HOST}" ] && [ -n "${PROXY_PORT}" ]; then
    auth_args=()
    if [ -n "${PROXY_USER}" ] || [ -n "${PROXY_PASS}" ]; then
        auth_args=("--proxy-user" "${PROXY_USER}:${PROXY_PASS}")
    fi

    # Check with curl and capture error output
    check_err=$(/usr/bin/curl -s -S -o /dev/null --connect-timeout 4 --max-time 5 \
        --proxy "${CURL_PROXY_PROTO}://${PROXY_HOST}:${PROXY_PORT}" "${auth_args[@]}" \
        "http://kali.download/kali/dists/kali-rolling/InRelease" 2>&1 || true)

    if [ -z "${check_err}" ]; then
        PROXY_HANDSHAKE_OK="true"
    else
        PROXY_HANDSHAKE_ERR="${check_err}"
        # If socks5h failed, test socks5 as fallback
        check_err_s5=$(/usr/bin/curl -s -S -o /dev/null --connect-timeout 4 --max-time 5 \
            --proxy "socks5://${PROXY_HOST}:${PROXY_PORT}" "${auth_args[@]}" \
            "http://kali.download/kali/dists/kali-rolling/InRelease" 2>&1 || true)
        if [ -z "${check_err_s5}" ]; then
            CURL_PROXY_PROTO="socks5"
            PROXY_HANDSHAKE_OK="true"
            PROXY_HANDSHAKE_ERR=""
        fi
    fi
fi

# Find the best target endpoint that works on both or proxy
CHOSEN_URL=""
DIRECT_SPEED=0
PROXY_SPEED=0

for test_target in "${CANDIDATE_URLS[@]}"; do
    p_cur=$(measure_wire_speed true "${test_target}" "${CURL_PROXY_PROTO}")
    d_cur=$(measure_wire_speed false "${test_target}" "${CURL_PROXY_PROTO}")

    if [ "${p_cur}" -gt 0 ]; then
        CHOSEN_URL="${test_target}"
        PROXY_SPEED="${p_cur}"
        DIRECT_SPEED="${d_cur}"
        break
    fi

    if [ -z "${CHOSEN_URL}" ] && [ "${d_cur}" -gt 0 ]; then
        CHOSEN_URL="${test_target}"
        DIRECT_SPEED="${d_cur}"
        PROXY_SPEED=0
    fi
done

if [ -z "${CHOSEN_URL}" ]; then
    CHOSEN_URL="${CANDIDATE_URLS[0]}"
fi
TEST_URL="${CHOSEN_URL}"

# Compare speeds (proxy wins ties as long as proxy is delivering throughput)
DECISION=$(awk -v p="${PROXY_SPEED}" -v d="${DIRECT_SPEED}" 'BEGIN {
    if (p > 0 && p >= d) {
        print "proxy"
    } else {
        print "direct"
    }
}')

# Apply decision
if [ "${DECISION}" = "proxy" ]; then
    if enable_transparent_proxy; then
        echo -n "proxy" > "${STATUS_FILE}.tmp"
        mv -f "${STATUS_FILE}.tmp" "${STATUS_FILE}"
    else
        DECISION="direct"
        disable_transparent_proxy
        echo -n "direct" > "${STATUS_FILE}.tmp"
        mv -f "${STATUS_FILE}.tmp" "${STATUS_FILE}"
    fi
else
    disable_transparent_proxy
    echo -n "direct" > "${STATUS_FILE}.tmp"
    mv -f "${STATUS_FILE}.tmp" "${STATUS_FILE}"
fi

# Format and log in MiB/s
DIRECT_MB=$(awk -v s="${DIRECT_SPEED}" 'BEGIN { printf "%.2f", s / 1048576 }')
PROXY_MB=$(awk -v s="${PROXY_SPEED}" 'BEGIN { printf "%.2f", s / 1048576 }')
TARGET_HOST=$(echo "${TEST_URL}" | awk -F[/:] '{print $4}')

mkdir -p "$(dirname "${LOG_FILE}")"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Target: ${TARGET_HOST} | Direct: ${DIRECT_MB} MiB/s | Proxy: ${PROXY_MB} MiB/s | Winner: ${DECISION}" >> "${LOG_FILE}"

if [ "${1:-}" = "--benchmark" ]; then
    echo "=========================================================="
    echo "⚡ Benchmark Complete"
    echo "=========================================================="
    echo "Target:  ${TARGET_HOST}"
    echo "Direct:  ${DIRECT_MB} MiB/s"
    echo "Proxy:   ${PROXY_MB} MiB/s"
    echo "Winner:  ${DECISION}"
    echo "Route:   $(is_proxy_routed && echo 'Transparent Proxy (ACTIVE)' || echo 'Direct (ACTIVE)')"
    if [ "${PROXY_SPEED}" -eq 0 ] && [ "${PROXY_HANDSHAKE_OK}" = "false" ]; then
        echo "----------------------------------------------------------"
        echo "[!] PROXY DIAGNOSTIC WARNING:"
        if echo "${PROXY_HANDSHAKE_ERR}" | grep -q -i "authentication"; then
            echo "    -> SOCKS5 Authentication Failed!"
            echo "    -> Your proxy requires valid credentials."
            echo "    -> Run: sudo bash ./setup_dynamic_proxy.sh to enter username and password."
        elif echo "${PROXY_HANDSHAKE_ERR}" | grep -q -i "Connection refused"; then
            echo "    -> Connection refused on ${PROXY_HOST}:${PROXY_PORT}."
            echo "    -> Please check if proxy server port is correct and open."
        else
            echo "    -> Error: ${PROXY_HANDSHAKE_ERR}"
            echo "    -> Check proxy IP, port, and credentials in /etc/redsocks.conf."
        fi
    fi
    echo "=========================================================="
fi
EOF

chmod +x "${MONITOR_SCRIPT}"

# Step 6: Configure systemd service and timer
echo "[*] Step 6: Configuring background systemd timer..."
cat << EOF > "${SERVICE_FILE}"
[Unit]
Description=Network Speed Benchmark & Dynamic Proxy Router
After=network-online.target redsocks.service
Wants=network-online.target redsocks.service

[Service]
Type=oneshot
ExecStart=${MONITOR_SCRIPT}
EOF

cat << EOF > "${TIMER_FILE}"
[Unit]
Description=Periodic check for proxy vs direct speed

[Timer]
OnBootSec=20s
OnUnitActiveSec=10min
AccuracySec=30s

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now network-speed-monitor.timer

# Step 7: Run initial benchmark
echo "[*] Step 7: Running initial connection benchmark..."
"${MONITOR_SCRIPT}"

CURRENT_STATUS="$(cat "${STATUS_FILE}" 2>/dev/null || echo 'unknown')"
echo "=========================================================="
echo "[✓] Setup successfully completed!"
echo "Active Route: ${CURRENT_STATUS}"
if [ -f "${LOG_FILE}" ]; then
    tail -n 1 "${LOG_FILE}"
fi
echo "=========================================================="
echo "Tips:"
echo "  - Check status anytime:  sudo bash $0 --status"
echo "  - Run benchmark anytime: sudo bash $0 --test"
echo "  - Force proxy mode:      sudo bash $0 --force-proxy"
echo "  - Force direct mode:     sudo bash $0 --force-direct"
echo "  - Uninstall:             sudo bash $0 --uninstall"
echo "=========================================================="
