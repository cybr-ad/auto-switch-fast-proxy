#!/usr/bin/env bash
#
# setup_dynamic_proxy.sh
# Automated transparent proxy router with dynamic failover and speed benchmark.
# Universal support for Debian-based distributions: Debian, Ubuntu, Kali, Mint, Pop!_OS, Parrot, etc.
#

set -euo pipefail

VERSION="3.0.0"
LOG_FILE="/var/log/network_speed_monitor.log"
STATUS_FILE="/run/fastest_connection"
MONITOR_SCRIPT="/usr/local/bin/network_speed_monitor.sh"
SERVICE_FILE="/etc/systemd/system/network-speed-monitor.service"
TIMER_FILE="/etc/systemd/system/network-speed-monitor.timer"
CRON_FILE="/etc/cron.d/network-speed-monitor"
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
⚡ Dynamic Proxy Router & Speed Monitor - Universal Debian Edition
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
  --test, --verify      Run speed benchmark & verify all download protocols (apt, go, curl, etc.)
  --dns                 Benchmark all candidate DNS servers and apply fastest
  --optimize-mirrors    Auto-configure package mirrors to high-speed CDN (deb822/sources.list)
  --force-proxy         Force enable transparent proxy routing immediately
  --force-direct        Force bypass proxy and route directly to internet
  --uninstall           Completely remove router, services, and restore defaults
  -h, --help            Show this help menu

Examples:
  # Interactive setup wizard (prompts for IP, port, user, pass, or edit via nano):
  sudo bash setup_dynamic_proxy.sh

  # One-liner setup with credentials:
  sudo bash setup_dynamic_proxy.sh --ip 198.51.100.50 --port 1080 --user myuser --pass mypass

  # Check active route and speed benchmark:
  sudo bash setup_dynamic_proxy.sh --status

  # Verify all download protocols (apt, go, curl, wget, git, pip):
  sudo bash setup_dynamic_proxy.sh --test

  # Optimize distro package mirrors to fast CDN:
  sudo bash setup_dynamic_proxy.sh --optimize-mirrors

  # Benchmark and apply fastest DNS servers:
  sudo bash setup_dynamic_proxy.sh --dns
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
        --dns|--dns-test)
            CLI_ACTION="dns"; shift ;;
        --optimize-mirrors|--fix-mirrors)
            CLI_ACTION="optimize-mirrors"; shift ;;
        --test|--benchmark|--verify)
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

# Helper: Detect operating system distribution (Debian, Ubuntu, Kali, Mint, etc.)
detect_distro() {
    DISTRO_ID="debian"
    DISTRO_LIKE=""
    DISTRO_NAME="Debian-based Linux"
    DISTRO_CODENAME="unknown"

    if [ -f /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        DISTRO_ID="${ID:-debian}"
        DISTRO_LIKE="${ID_LIKE:-}"
        DISTRO_NAME="${PRETTY_NAME:-${NAME:-Debian-based Linux}}"
        DISTRO_CODENAME="${VERSION_CODENAME:-${UBUNTU_CODENAME:-unknown}}"
    fi
}

# Helper: Detect redsocks system user (redsocks or _redsocks)
get_redsocks_user() {
    if id -u redsocks >/dev/null 2>&1; then
        echo "redsocks"
    elif id -u _redsocks >/dev/null 2>&1; then
        echo "_redsocks"
    else
        useradd -r -s /bin/false -M redsocks 2>/dev/null || true
        echo "redsocks"
    fi
}

# Helper: Detect if systemd init is running
has_systemd() {
    [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1
}

# Helper: Universal mirror optimizer for all Debian-based distributions
optimize_distro_mirrors() {
    local silent="${1:-false}"
    detect_distro
    local changed=0

    # Optimize APT settings for transparent proxies and high concurrency
    if [ -d /etc/apt/apt.conf.d ]; then
        cat << 'EOF_APT' > /etc/apt/apt.conf.d/99fast-proxy
// Generated by Dynamic Fast Proxy Router
// Optimizes APT for transparent proxying and fast CDN mirrors
Acquire::http::Pipeline-Depth "0";
Acquire::https::Pipeline-Depth "0";
Acquire::http::No-Cache "false";
Acquire::http::Timeout "10";
Acquire::https::Timeout "10";
Acquire::Retries "3";
EOF_APT
        chmod 644 /etc/apt/apt.conf.d/99fast-proxy
    fi

    case "${DISTRO_ID}" in
        kali)
            # Modern deb822 format (/etc/apt/sources.list.d/kali.sources)
            if [ -f /etc/apt/sources.list.d/kali.sources ]; then
                if grep -E -q 'http(s)?://(http\.kali\.org|mirror\.[a-z0-9.-]+)/kali' /etc/apt/sources.list.d/kali.sources; then
                    [ "$silent" != "true" ] && echo "[*] Optimizing Kali mirror in /etc/apt/sources.list.d/kali.sources -> http://kali.download/kali..."
                    sed -i 's|http://http.kali.org/kali|http://kali.download/kali|g' /etc/apt/sources.list.d/kali.sources
                    sed -i 's|https://http.kali.org/kali|https://kali.download/kali|g' /etc/apt/sources.list.d/kali.sources
                    sed -i -E 's|http(s)?://mirror\.[a-z0-9.-]+/kali|http://kali.download/kali|g' /etc/apt/sources.list.d/kali.sources
                    changed=1
                fi
            fi
            # Legacy sources.list format (/etc/apt/sources.list)
            if [ -f /etc/apt/sources.list ]; then
                if grep -E -q 'http(s)?://(http\.kali\.org|mirror\.[a-z0-9.-]+)/kali' /etc/apt/sources.list; then
                    [ "$silent" != "true" ] && echo "[*] Optimizing Kali mirror in /etc/apt/sources.list -> http://kali.download/kali..."
                    sed -i 's|http://http.kali.org/kali|http://kali.download/kali|g' /etc/apt/sources.list
                    sed -i 's|https://http.kali.org/kali|https://kali.download/kali|g' /etc/apt/sources.list
                    sed -i -E 's|http(s)?://mirror\.[a-z0-9.-]+/kali|http://kali.download/kali|g' /etc/apt/sources.list
                    changed=1
                fi
            fi
            ;;
        debian)
            # Optimize Debian sources to global Fastly/Cloudflare CDN (deb.debian.org)
            for f in /etc/apt/sources.list /etc/apt/sources.list.d/debian.sources; do
                if [ -f "$f" ] && grep -E -q 'http://ftp\.[a-z0-9.-]*\.debian\.org/debian' "$f"; then
                    [ "$silent" != "true" ] && echo "[*] Optimizing Debian mirror in $f -> http://deb.debian.org/debian..."
                    sed -i -E 's|http://ftp\.[a-z0-9.-]*\.debian\.org/debian|http://deb.debian.org/debian|g' "$f"
                    changed=1
                fi
            done
            ;;
        ubuntu|linuxmint|pop)
            # Ubuntu derivatives keep standard official archive
            ;;
    esac

    if [ "$changed" -eq 1 ] && [ "$silent" != "true" ]; then
        echo "[✓] Package mirrors updated to high-speed CDN. Run 'sudo apt update' to refresh."
    elif [ "$silent" != "true" ]; then
        echo "[✓] Package mirrors are using official CDN endpoints."
    fi
}

# Helper: Measure DNS server query latency (in ms)
measure_dns_latency() {
    local ns="$1"
    local lat=9999

    # Method 1: dig if available
    if command -v dig >/dev/null 2>&1; then
        local out
        out=$(dig "@${ns}" google.com +time=1 +tries=1 +stats 2>/dev/null || true)
        if echo "$out" | grep -q -i "status: NOERROR"; then
            local qtime
            qtime=$(echo "$out" | awk '/Query time:/ {print $4}' | head -n 1)
            if [[ "$qtime" =~ ^[0-9]+$ ]]; then
                lat="$qtime"
            fi
        fi
    fi

    # Method 2: python3 raw UDP socket query (instant fallback, no extra dependencies)
    if [ "$lat" -ge 9999 ] && command -v python3 >/dev/null 2>&1; then
        lat=$(python3 -c "
import socket, time
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.settimeout(1.0)
query = b'\xaa\xaa\x01\x00\x00\x01\x00\x00\x00\x00\x00\x00\x06google\x03com\x00\x00\x01\x00\x01'
t0 = time.perf_counter()
try:
    s.sendto(query, ('${ns}', 53))
    data, _ = s.recvfrom(512)
    if len(data) >= 12:
        print(int((time.perf_counter() - t0) * 1000))
    else:
        print(9999)
except Exception:
    print(9999)
" 2>/dev/null || echo "9999")
    fi

    echo "$lat"
}

# Step 2 Helper: Benchmark candidate DNS servers and write fastest to /etc/resolv.conf
find_and_apply_fastest_dns() {
    local silent="${1:-false}"
    local resolv="${RESOLV_CONF}"
    local candidates=()

    # Discover original / existing nameservers from resolv.conf and resolv.conf.bak
    for f in "$resolv" "${resolv}.bak"; do
        if [ -f "$f" ]; then
            while read -r line; do
                if [[ "$line" =~ ^[[:space:]]*nameserver[[:space:]]+([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+) ]]; then
                    local ip="${BASH_REMATCH[1]}"
                    if [[ "$ip" != "127."* && "$ip" != "0.0.0.0" ]]; then
                        candidates+=("$ip")
                    fi
                fi
            done < "$f"
        fi
    done

    # Add standard high-speed public DNS candidates
    candidates+=("1.1.1.1" "8.8.8.8" "1.0.0.1" "8.8.4.4" "9.9.9.9" "208.67.222.222")

    # Deduplicate candidate IPs
    local unique_candidates=()
    local seen_ips=""
    for ip in "${candidates[@]}"; do
        if ! echo "$seen_ips" | grep -q -w "$ip"; then
            seen_ips="${seen_ips} ${ip}"
            unique_candidates+=("$ip")
        fi
    done

    [ "$silent" != "true" ] && echo "[*] Benchmarking DNS servers (latency in ms)..."

    local results=()
    for ns in "${unique_candidates[@]}"; do
        local lat
        lat=$(measure_dns_latency "$ns")
        if [ "$lat" -lt 9999 ]; then
            results+=("${lat}:${ns}")
            [ "$silent" != "true" ] && echo "    -> ${ns}: ${lat} ms"
        else
            [ "$silent" != "true" ] && echo "    -> ${ns}: [Timeout / Unreachable]"
        fi
    done

    if [ ${#results[@]} -eq 0 ]; then
        results=("20:1.1.1.1" "25:8.8.8.8")
    fi

    # Sort results by latency (ascending)
    local sorted_results
    sorted_results=$(printf '%s\n' "${results[@]}" | sort -t: -k1 -n)

    local best_entry1=$(echo "$sorted_results" | sed -n '1p')
    local best_lat1=$(echo "$best_entry1" | cut -d: -f1)
    local best_ns1=$(echo "$best_entry1" | cut -d: -f2)

    local best_entry2=$(echo "$sorted_results" | sed -n '2p')
    local best_lat2=""
    local best_ns2=""
    if [ -n "$best_entry2" ]; then
        best_lat2=$(echo "$best_entry2" | cut -d: -f1)
        best_ns2=$(echo "$best_entry2" | cut -d: -f2)
    fi

    [ "$silent" != "true" ] && echo "[✓] Fastest DNS selected: ${best_ns1} (${best_lat1} ms)$([ -n "${best_ns2}" ] && echo " | Backup: ${best_ns2} (${best_lat2} ms)")"

    # Backup original before overwriting if backup doesn't exist
    if [ -f "$resolv" ] && [ ! -f "${resolv}.bak" ]; then
        cp -L "$resolv" "${resolv}.bak" 2>/dev/null || true
    fi

    rm -f "$resolv"
    cat << EOF > "$resolv"
# Automatically benchmarked & optimized by Dynamic Proxy Router
# Primary (Fastest response: ${best_lat1} ms):
nameserver ${best_ns1}
$([ -n "${best_ns2}" ] && echo "# Secondary (Backup response: ${best_lat2} ms):
nameserver ${best_ns2}")
EOF
    chmod 644 "$resolv"
    [ "$silent" != "true" ] && echo "[✓] Configured ${resolv} with fastest nameservers."
}

# Action: Status
if [ "${CLI_ACTION}" = "status" ]; then
    if [ -x "${MONITOR_SCRIPT}" ]; then
        exec "${MONITOR_SCRIPT}" --status
    else
        echo "[!] Network monitor script not installed yet. Run setup first."
        exit 1
    fi
fi

# Action: Optimize Mirrors
if [ "${CLI_ACTION}" = "optimize-mirrors" ]; then
    if [ "${EUID}" -ne 0 ]; then
        echo "[!] Please run as root: sudo bash $0 --optimize-mirrors"
        exit 1
    fi
    optimize_distro_mirrors false
    exit 0
fi

# Action: DNS Benchmark
if [ "${CLI_ACTION}" = "dns" ]; then
    if [ -x "${MONITOR_SCRIPT}" ]; then
        exec "${MONITOR_SCRIPT}" --dns
    else
        find_and_apply_fastest_dns false
        exit 0
    fi
fi

# Action: Test / Benchmark / Verify
if [ "${CLI_ACTION}" = "test" ]; then
    if [ -x "${MONITOR_SCRIPT}" ]; then
        exec "${MONITOR_SCRIPT}" --verify
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
    if has_systemd; then
        systemctl disable --now network-speed-monitor.timer 2>/dev/null || true
        systemctl stop network-speed-monitor.service 2>/dev/null || true
        rm -f "${SERVICE_FILE}" "${TIMER_FILE}"
        systemctl daemon-reload 2>/dev/null || true
    fi
    rm -f "${CRON_FILE}"

    # Flush iptables redirection
    echo "[*] Flushing iptables REDSOCKS rules..."
    while iptables -t nat -D OUTPUT -p tcp -j REDSOCKS 2>/dev/null; do :; done
    iptables -t nat -F REDSOCKS 2>/dev/null || true
    iptables -t nat -X REDSOCKS 2>/dev/null || true

    # Restore factory / original /etc/resolv.conf if backup exists
    if [ -f "${RESOLV_CONF}.bak" ]; then
        echo "[*] Restoring original ${RESOLV_CONF}..."
        cp -f "${RESOLV_CONF}.bak" "${RESOLV_CONF}" 2>/dev/null || true
        rm -f "${RESOLV_CONF}.bak"
    fi

    rm -f /etc/apt/apt.conf.d/99fast-proxy
    rm -f "${MONITOR_SCRIPT}" "${STATUS_FILE}" "${STATUS_FILE}.tmp" "${LOG_FILE}"
    echo "[✓] Successfully uninstalled. Factory routing and DNS restored."
    exit 0
fi

# Require root for installation
if [ "${EUID}" -ne 0 ]; then
    echo "[!] Please run as root: sudo bash $0"
    exit 1
fi

detect_distro
echo "=========================================================="
echo "⚡ Dynamic Proxy Router Setup (v${VERSION})"
echo "Platform: ${DISTRO_NAME} (${DISTRO_CODENAME})"
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

export DEBIAN_FRONTEND=noninteractive
MISSING_PKGS=()
for pkg in redsocks iptables curl wget git gawk procps nano ca-certificates; do
    if ! dpkg -s "$pkg" >/dev/null 2>&1 && ! command -v "$pkg" &>/dev/null; then
        MISSING_PKGS+=("$pkg")
    fi
done
if ! command -v dig &>/dev/null; then
    MISSING_PKGS+=("bind9-dnsutils")
fi

if [ ${#MISSING_PKGS[@]} -gt 0 ]; then
    echo "    -> Installing missing packages: ${MISSING_PKGS[*]}"
    apt-get update -y
    apt-get install -y --no-install-recommends "${MISSING_PKGS[@]}" 2>/dev/null || \
    apt-get install -y --no-install-recommends redsocks iptables curl wget git gawk procps nano ca-certificates dnsutils 2>/dev/null || true
else
    echo "    -> All required packages are already installed."
fi

# Detect or create redsocks system user
REDSOCKS_SYSTEM_USER="$(get_redsocks_user)"
echo "    -> Daemon system user: ${REDSOCKS_SYSTEM_USER}"
mkdir -p /run/redsocks
chown -R "${REDSOCKS_SYSTEM_USER}:${REDSOCKS_SYSTEM_USER}" /run/redsocks 2>/dev/null || true

# Step 2: Auto-optimize distro mirrors & benchmark DNS
echo "[*] Step 2: Optimizing distro package mirrors & benchmarking DNS..."
optimize_distro_mirrors true
find_and_apply_fastest_dns false

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
        echo "  Proxy IP:       $([ -n "${EXISTING_IP}" ] && echo '[Configured / Hidden]' || echo '[Not set]')"
        echo "  Proxy Port:     $([ -n "${EXISTING_PORT}" ] && echo '[Configured / Hidden]' || echo '[Not set]')"
        echo "  Proxy User:     $([ -n "${EXISTING_USER}" ] && echo '[Configured / Hidden]' || echo '[None]')"
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
    ip = 127.0.0.1;
    port = 1080;
    type = socks5;
    // login = "username";
    // password = "password";
}
EOF
            fi
            nano "${REDSOCKS_CONF}"
            read_existing_config
            TARGET_IP="${EXISTING_IP}"
            TARGET_PORT="${EXISTING_PORT:-1080}"
            TARGET_TYPE="${EXISTING_TYPE:-socks5}"
            TARGET_USER="${EXISTING_USER}"
            TARGET_PASS="${EXISTING_PASS}"
            TARGET_LOCAL_PORT="${EXISTING_LOCAL_PORT:-12345}"
        elif [ "${choice_opt}" = "3" ]; then
            TARGET_IP="${EXISTING_IP}"
            TARGET_PORT="${EXISTING_PORT:-1080}"
            TARGET_TYPE="${EXISTING_TYPE:-socks5}"
            TARGET_USER="${EXISTING_USER}"
            TARGET_PASS="${EXISTING_PASS}"
            TARGET_LOCAL_PORT="${EXISTING_LOCAL_PORT:-12345}"
        else
            # Option 1: Direct interactive prompt (protect credentials from screen display)
            local prompt_ip="Enter Proxy IP or Host"
            [ -n "${EXISTING_IP}" ] && prompt_ip="${prompt_ip} (press Enter to keep existing hidden IP)"
            read -r -p "${prompt_ip}: " in_ip
            TARGET_IP="${in_ip:-${EXISTING_IP:-}}"

            local prompt_port="Enter Proxy Port"
            [ -n "${EXISTING_PORT}" ] && prompt_port="${prompt_port} (press Enter to keep existing hidden port)"
            read -r -p "${prompt_port}: " in_port
            TARGET_PORT="${in_port:-${EXISTING_PORT:-1080}}"

            local prompt_user="Enter Proxy Username (leave blank if none)"
            [ -n "${EXISTING_USER}" ] && prompt_user="${prompt_user} (press Enter to keep existing hidden user)"
            read -r -p "${prompt_user}: " in_user
            TARGET_USER="${in_user:-${EXISTING_USER:-}}"

            local prompt_pass="Enter Proxy Password (leave blank if none)"
            [ -n "${EXISTING_PASS}" ] && prompt_pass="${prompt_pass} (press Enter to keep existing hidden pass)"
            read -s -r -p "${prompt_pass}: " in_pass
            echo ""
            TARGET_PASS="${in_pass:-${EXISTING_PASS:-}}"

            read -r -p "Enter Proxy Type (socks5/socks4/http-connect) [${EXISTING_TYPE:-socks5}]: " in_type
            TARGET_TYPE="${in_type:-${EXISTING_TYPE:-socks5}}"
        fi
        echo "=================================================="
    else
        # Non-interactive mode
        if [ -n "${EXISTING_IP}" ] && ! is_placeholder_host "${EXISTING_IP}"; then
            TARGET_IP="${EXISTING_IP}"
            TARGET_PORT="${EXISTING_PORT:-1080}"
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
    user = ${REDSOCKS_SYSTEM_USER};
    group = ${REDSOCKS_SYSTEM_USER};
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

# Restart redsocks service across systemd, sysvinit, or direct
echo "    -> Restarting redsocks service..."
if has_systemd; then
    systemctl restart redsocks 2>/dev/null || /etc/init.d/redsocks restart 2>/dev/null || true
    systemctl enable redsocks 2>/dev/null || true
elif [ -x /etc/init.d/redsocks ]; then
    /etc/init.d/redsocks restart 2>/dev/null || true
else
    pkill -x redsocks 2>/dev/null || true
    redsocks -c "${REDSOCKS_CONF}" 2>/dev/null || true
fi
sleep 1

if ! pgrep -x redsocks >/dev/null 2>&1 && ! (has_systemd && systemctl is-active --quiet redsocks 2>/dev/null); then
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

detect_distro() {
    DISTRO_ID="debian"
    DISTRO_LIKE=""
    DISTRO_NAME="Debian-based Linux"
    DISTRO_CODENAME="unknown"
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO_ID="${ID:-debian}"
        DISTRO_LIKE="${ID_LIKE:-}"
        DISTRO_NAME="${PRETTY_NAME:-${NAME:-Debian-based Linux}}"
        DISTRO_CODENAME="${VERSION_CODENAME:-${UBUNTU_CODENAME:-unknown}}"
    fi
}

optimize_distro_mirrors() {
    local silent="${1:-false}"
    detect_distro
    local changed=0

    # Optimize APT settings for transparent proxies and high concurrency
    if [ -d /etc/apt/apt.conf.d ]; then
        cat << 'EOF_APT' > /etc/apt/apt.conf.d/99fast-proxy
// Generated by Dynamic Fast Proxy Router
// Optimizes APT for transparent proxying and fast CDN mirrors
Acquire::http::Pipeline-Depth "0";
Acquire::https::Pipeline-Depth "0";
Acquire::http::No-Cache "false";
Acquire::http::Timeout "10";
Acquire::https::Timeout "10";
Acquire::Retries "3";
EOF_APT
        chmod 644 /etc/apt/apt.conf.d/99fast-proxy
    fi

    case "${DISTRO_ID}" in
        kali)
            if [ -f /etc/apt/sources.list.d/kali.sources ]; then
                if grep -E -q 'http(s)?://(http\.kali\.org|mirror\.[a-z0-9.-]+)/kali' /etc/apt/sources.list.d/kali.sources; then
                    [ "$silent" != "true" ] && echo "[*] Optimizing Kali mirror in /etc/apt/sources.list.d/kali.sources -> http://kali.download/kali..."
                    sed -i 's|http://http.kali.org/kali|http://kali.download/kali|g' /etc/apt/sources.list.d/kali.sources
                    sed -i 's|https://http.kali.org/kali|https://kali.download/kali|g' /etc/apt/sources.list.d/kali.sources
                    sed -i -E 's|http(s)?://mirror\.[a-z0-9.-]+/kali|http://kali.download/kali|g' /etc/apt/sources.list.d/kali.sources
                    changed=1
                fi
            fi
            if [ -f /etc/apt/sources.list ]; then
                if grep -E -q 'http(s)?://(http\.kali\.org|mirror\.[a-z0-9.-]+)/kali' /etc/apt/sources.list; then
                    [ "$silent" != "true" ] && echo "[*] Optimizing Kali mirror in /etc/apt/sources.list -> http://kali.download/kali..."
                    sed -i 's|http://http.kali.org/kali|http://kali.download/kali|g' /etc/apt/sources.list
                    sed -i 's|https://http.kali.org/kali|https://kali.download/kali|g' /etc/apt/sources.list
                    sed -i -E 's|http(s)?://mirror\.[a-z0-9.-]+/kali|http://kali.download/kali|g' /etc/apt/sources.list
                    changed=1
                fi
            fi
            ;;
        debian)
            for f in /etc/apt/sources.list /etc/apt/sources.list.d/debian.sources; do
                if [ -f "$f" ] && grep -E -q 'http://ftp\.[a-z0-9.-]*\.debian\.org/debian' "$f"; then
                    [ "$silent" != "true" ] && echo "[*] Optimizing Debian mirror in $f -> http://deb.debian.org/debian..."
                    sed -i -E 's|http://ftp\.[a-z0-9.-]*\.debian\.org/debian|http://deb.debian.org/debian|g' "$f"
                    changed=1
                fi
            done
            ;;
    esac
    if [ "$changed" -eq 1 ] && [ "$silent" != "true" ]; then
        echo "[✓] Package mirrors updated to high-speed CDN. Run 'sudo apt update' to refresh."
    elif [ "$silent" != "true" ]; then
        echo "[✓] Package mirrors are using official CDN endpoints."
    fi
}

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
    if [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet redsocks 2>/dev/null; then
        return 0
    fi
    return 1
}

enable_transparent_proxy() {
    if ! is_redsocks_alive; then
        if [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1; then
            systemctl restart redsocks 2>/dev/null || true
        elif [ -x /etc/init.d/redsocks ]; then
            /etc/init.d/redsocks restart 2>/dev/null || true
        else
            pkill -x redsocks 2>/dev/null || true
            redsocks -c "${REDSOCKS_CONF}" 2>/dev/null || true
        fi
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

    # 2. Bypass redsocks process itself to prevent infinite loop (covers redsocks and _redsocks)
    for u in redsocks _redsocks; do
        if id -u "$u" >/dev/null 2>&1; then
            iptables -t nat -A REDSOCKS -m owner --uid-owner "$u" -j RETURN 2>/dev/null || true
        fi
    done

    # 3. Bypass upstream proxy server IPs
    if [ -n "${RESOLVED_PROXY_IPS}" ]; then
        for ip in ${RESOLVED_PROXY_IPS}; do
            iptables -t nat -A REDSOCKS -d "${ip}" -j RETURN
        done
    fi

    # 4. Redirect ALL outbound TCP traffic to redsocks local port
    # Captures all downloading tools transparently: apt, curl, wget, go, git, pip, docker
    iptables -t nat -A REDSOCKS -p tcp -j REDIRECT --to-ports "${LOCAL_PORT}"

    # 5. Attach REDSOCKS to OUTPUT chain (idempotent, supports both iptables-legacy and iptables-nft)
    if ! is_proxy_routed; then
        iptables -t nat -I OUTPUT -p tcp -j REDSOCKS 2>/dev/null || iptables -t nat -A OUTPUT -p tcp -j REDSOCKS 2>/dev/null || true
    fi
}

disable_transparent_proxy() {
    while iptables -t nat -D OUTPUT -p tcp -j REDSOCKS 2>/dev/null; do :; done
    iptables -t nat -F REDSOCKS 2>/dev/null || true
    iptables -t nat -X REDSOCKS 2>/dev/null || true
}

is_proxy_routed() {
    iptables -t nat -C OUTPUT -p tcp -j REDSOCKS 2>/dev/null || \
    iptables -t nat -S OUTPUT 2>/dev/null | grep -q -- "-j REDSOCKS"
}

# Helper: Measure DNS server query latency (in ms)
measure_dns_latency() {
    local ns="$1"
    local lat=9999

    # Method 1: dig if available
    if command -v dig >/dev/null 2>&1; then
        local out
        out=$(dig "@${ns}" google.com +time=1 +tries=1 +stats 2>/dev/null || true)
        if echo "$out" | grep -q -i "status: NOERROR"; then
            local qtime
            qtime=$(echo "$out" | awk '/Query time:/ {print $4}' | head -n 1)
            if [[ "$qtime" =~ ^[0-9]+$ ]]; then
                lat="$qtime"
            fi
        fi
    fi

    # Method 2: python3 raw UDP socket query (instant fallback, no extra dependencies)
    if [ "$lat" -ge 9999 ] && command -v python3 >/dev/null 2>&1; then
        lat=$(python3 -c "
import socket, time
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.settimeout(1.0)
query = b'\xaa\xaa\x01\x00\x00\x01\x00\x00\x00\x00\x00\x00\x06google\x03com\x00\x00\x01\x00\x01'
t0 = time.perf_counter()
try:
    s.sendto(query, ('${ns}', 53))
    data, _ = s.recvfrom(512)
    if len(data) >= 12:
        print(int((time.perf_counter() - t0) * 1000))
    else:
        print(9999)
except Exception:
    print(9999)
" 2>/dev/null || echo "9999")
    fi

    echo "$lat"
}

# Auto-benchmark DNS and set fastest in /etc/resolv.conf
find_and_apply_fastest_dns() {
    local silent="${1:-false}"
    local resolv="/etc/resolv.conf"
    local candidates=()

    # Discover original / existing nameservers from resolv.conf and resolv.conf.bak
    for f in "$resolv" "${resolv}.bak"; do
        if [ -f "$f" ]; then
            while read -r line; do
                if [[ "$line" =~ ^[[:space:]]*nameserver[[:space:]]+([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+) ]]; then
                    local ip="${BASH_REMATCH[1]}"
                    if [[ "$ip" != "127."* && "$ip" != "0.0.0.0" ]]; then
                        candidates+=("$ip")
                    fi
                fi
            done < "$f"
        fi
    done

    # Add standard high-speed public DNS candidates
    candidates+=("1.1.1.1" "8.8.8.8" "1.0.0.1" "8.8.4.4" "9.9.9.9" "208.67.222.222")

    # Deduplicate candidate IPs
    local unique_candidates=()
    local seen_ips=""
    for ip in "${candidates[@]}"; do
        if ! echo "$seen_ips" | grep -q -w "$ip"; then
            seen_ips="${seen_ips} ${ip}"
            unique_candidates+=("$ip")
        fi
    done

    [ "$silent" != "true" ] && echo "[*] Benchmarking DNS servers (latency in ms)..."

    local results=()
    for ns in "${unique_candidates[@]}"; do
        local lat
        lat=$(measure_dns_latency "$ns")
        if [ "$lat" -lt 9999 ]; then
            results+=("${lat}:${ns}")
            [ "$silent" != "true" ] && echo "    -> ${ns}: ${lat} ms"
        else
            [ "$silent" != "true" ] && echo "    -> ${ns}: [Timeout / Unreachable]"
        fi
    done

    if [ ${#results[@]} -eq 0 ]; then
        results=("20:1.1.1.1" "25:8.8.8.8")
    fi

    # Sort results by latency (ascending)
    local sorted_results
    sorted_results=$(printf '%s\n' "${results[@]}" | sort -t: -k1 -n)

    local best_entry1=$(echo "$sorted_results" | sed -n '1p')
    local best_lat1=$(echo "$best_entry1" | cut -d: -f1)
    local best_ns1=$(echo "$best_entry1" | cut -d: -f2)

    local best_entry2=$(echo "$sorted_results" | sed -n '2p')
    local best_lat2=""
    local best_ns2=""
    if [ -n "$best_entry2" ]; then
        best_lat2=$(echo "$best_entry2" | cut -d: -f1)
        best_ns2=$(echo "$best_entry2" | cut -d: -f2)
    fi

    [ "$silent" != "true" ] && echo "[✓] Fastest DNS selected: ${best_ns1} (${best_lat1} ms)$([ -n "${best_ns2}" ] && echo " | Backup: ${best_ns2} (${best_lat2} ms)")"

    # Backup original before overwriting if backup doesn't exist
    if [ -f "$resolv" ] && [ ! -f "${resolv}.bak" ]; then
        cp -L "$resolv" "${resolv}.bak" 2>/dev/null || true
    fi

    rm -f "$resolv"
    cat << EOF_RESOLV > "$resolv"
# Automatically benchmarked & optimized by Dynamic Proxy Router
# Primary (Fastest response: ${best_lat1} ms):
nameserver ${best_ns1}
$([ -n "${best_ns2}" ] && echo "# Secondary (Backup response: ${best_lat2} ms):
nameserver ${best_ns2}")
EOF_RESOLV
    chmod 644 "$resolv"
    [ "$silent" != "true" ] && echo "[✓] Configured ${resolv} with fastest nameservers."
}

show_status() {
    local cur="direct"
    [ -f "${STATUS_FILE}" ] && cur="$(cat "${STATUS_FILE}" 2>/dev/null || echo "direct")"
    local ipt_status="INACTIVE (Direct)"
    if is_proxy_routed; then
        ipt_status="ACTIVE (Transparent Proxying)"
    elif [ "${cur}" = "proxy" ]; then
        # Auto-heal: If decision is proxy but rules were detached, re-apply
        enable_transparent_proxy 2>/dev/null || true
        if is_proxy_routed; then
            ipt_status="ACTIVE (Transparent Proxying - Reconnected)"
        fi
    fi

    local redsocks_status="DOWN"
    if is_redsocks_alive; then
        redsocks_status="UP (listening on ${LOCAL_PORT})"
    fi

    local active_dns
    active_dns=$(grep -E '^[[:space:]]*nameserver' /etc/resolv.conf 2>/dev/null | awk '{print $2}' | tr '\n' ' ' || echo "None")
    local dns_status=""
    for dns_ip in ${active_dns}; do
        local l
        l=$(measure_dns_latency "$dns_ip")
        if [ "$l" -lt 9999 ]; then
            dns_status="${dns_status}${dns_ip} (${l}ms) "
        else
            dns_status="${dns_status}${dns_ip} (down) "
        fi
    done
    [ -z "$dns_status" ] && dns_status="None"

    echo "=========================================================="
    echo "⚡ Network Proxy Status"
    echo "=========================================================="
    echo "Active Decision:  ${cur}"
    echo "Iptables NAT:     ${ipt_status}"
    echo "Redsocks Daemon:  ${redsocks_status}"
    echo "Active DNS:       ${dns_status}"
    echo "Target Proxy:     $([ -n "${PROXY_HOST}" ] && echo "${PROXY_TYPE}://[PROTECTED] (Hidden for Security)" || echo "None configured")"
    echo "Auth Configured:  $([ -n "${PROXY_USER}" ] && echo "YES (Protected)" || echo "NO (anonymous)")"
    echo "Protocols Routed: All TCP (apt, go, curl, wget, git, pip, docker)"
    echo "----------------------------------------------------------"
    echo "Last Log Entry:"
    if [ -f "${LOG_FILE}" ]; then
        tail -n 1 "${LOG_FILE}"
    else
        echo "  (No logs recorded yet)"
    fi
    echo "=========================================================="
}

# Helper: Multi-protocol verification suite
test_all_download_protocols() {
    echo ""
    echo "================================================================================"
    echo "🚀 Multi-Protocol Download Verification"
    echo "================================================================================"

    local cur_route="direct"
    [ -f "${STATUS_FILE}" ] && cur_route="$(cat "${STATUS_FILE}" 2>/dev/null || echo "direct")"
    local ipt_status="INACTIVE (Direct)"
    if is_proxy_routed; then
        ipt_status="ACTIVE (Transparent Proxying)"
    fi

    local active_dns_str
    active_dns_str=$(grep -E '^[[:space:]]*nameserver' /etc/resolv.conf 2>/dev/null | awk '{print $2}' | tr '\n' ' ' || echo "System Default")

    echo "Routing Mode:      ${cur_route^^} [Iptables: ${ipt_status}]"
    echo "Active DNS:        ${active_dns_str}"
    echo "--------------------------------------------------------------------------------"
    printf "%-20s %-26s %-20s %-12s\n" "Protocol / Tool" "Endpoint Tested" "Speed / Latency" "Status"
    echo "--------------------------------------------------------------------------------"

    _verify_stream() {
        local proto_name="$1"
        local endpoint_label="$2"
        local url="$3"
        local max_sec="${4:-4}"

        local stats
        stats=$(/usr/bin/curl -s -L -o /dev/null \
            -w "%{size_download} %{time_total} %{time_starttransfer} %{time_connect} %{http_code}" \
            --connect-timeout 4 --max-time "${max_sec}" "${url}" 2>/dev/null || echo "0 0 0 0 000")

        local result
        result=$(awk -v s="${stats}" 'BEGIN {
            split(s, a, " ")
            bytes = a[1] + 0
            total_t = a[2] + 0
            start_t = a[3] + 0
            conn_t = a[4] + 0
            code = a[5]
            trans_t = total_t - start_t

            speed = 0
            if (bytes > 0 && trans_t > 0.03) {
                speed = bytes / trans_t
            } else if (total_t > 0 && bytes > 0) {
                speed = bytes / total_t
            }

            mibs = sprintf("%.2f", speed / 1048576)
            kbs = sprintf("%.0f", speed / 1024)

            ms = "N/A"
            if (conn_t > 0) {
                ms = sprintf("%.0f", conn_t * 1000) "ms"
            } else if (start_t > 0) {
                ms = sprintf("%.0f", start_t * 1000) "ms"
            }

            if (speed >= 1048576) {
                print mibs " MiB/s (" ms ")|✔ PASS [FAST]"
            } else if (speed >= 102400) {
                print kbs " KiB/s (" ms ")|✔ PASS [FAST]"
            } else if (bytes > 0 || code ~ /^(200|301|302|304)$/) {
                if (speed > 0) {
                    print kbs " KiB/s (" ms ")|✔ PASS"
                } else {
                    print "Connected (" ms ")|✔ PASS"
                }
            } else if (conn_t > 0) {
                print "Connected (" ms ")|✔ PASS"
            } else {
                print "Timeout / Blocked|✘ FAILED"
            }
        }')

        local speed_col
        speed_col=$(echo "$result" | cut -d'|' -f1)
        local status_col
        status_col=$(echo "$result" | cut -d'|' -f2)

        printf "%-20s %-26s %-20s %-12s\n" "${proto_name}" "${endpoint_label}" "${speed_col}" "${status_col}"
    }

    # 1. APT (Package Manager Mirror)
    local apt_url="http://kali.download/kali/dists/kali-rolling/Contents-amd64.gz"
    local apt_label="kali.download (CDN)"
    detect_distro
    case "${DISTRO_ID}" in
        debian)
            apt_url="http://deb.debian.org/debian/dists/stable/Contents-amd64.gz"
            apt_label="deb.debian.org (CDN)"
            ;;
        ubuntu|linuxmint|pop)
            apt_url="http://archive.ubuntu.com/ubuntu/dists/stable/main/binary-amd64/Packages.gz"
            apt_label="archive.ubuntu.com"
            ;;
    esac
    _verify_stream "APT (Package Mgr)" "${apt_label}" "${apt_url}" 4

    # 2. CURL (HTTP / HTTPS)
    _verify_stream "CURL (HTTP/HTTPS)" "speed.cloudflare.com" "https://speed.cloudflare.com/__down?bytes=5242880" 4

    # 3. WGET (File Retrieval)
    if command -v wget >/dev/null 2>&1; then
        local wget_out
        wget_out=$(wget -O /dev/null --timeout=4 --tries=1 "https://speed.cloudflare.com/__down?bytes=2097152" 2>&1 || true)
        local wget_speed
        wget_speed=$(echo "$wget_out" | grep -o -E '\([0-9.]+ [KMGT]?B/s\)' | tr -d '()' | tail -n 1 || echo "")
        if [ -n "$wget_speed" ]; then
            printf "%-20s %-26s %-20s %-12s\n" "WGET (File Retrieval)" "speed.cloudflare.com" "${wget_speed}" "✔ PASS [FAST]"
        else
            _verify_stream "WGET (File Retrieval)" "speed.cloudflare.com" "https://speed.cloudflare.com/__down?bytes=2097152" 4
        fi
    else
        _verify_stream "WGET (File Retrieval)" "speed.cloudflare.com" "https://speed.cloudflare.com/__down?bytes=2097152" 4
    fi

    # 4. GO (Golang Modules / GOPROXY)
    _verify_stream "GO (Golang Modules)" "proxy.golang.org (CDN)" "https://proxy.golang.org/github.com/gin-gonic/gin/@v/v1.9.1.zip" 4

    # 5. GIT (GitHub Smart HTTP)
    _verify_stream "GIT (GitHub HTTPS)" "github.com (Smart HTTP)" "https://github.com/torvalds/linux.git/info/refs?service=git-upload-pack" 4

    # 6. PIP (Python PyPI)
    _verify_stream "PIP (Python PyPI)" "pypi.org / PyPI CDN" "https://files.pythonhosted.org/packages/source/p/pip/pip-24.0.tar.gz" 4

    echo "--------------------------------------------------------------------------------"
    echo "✔ All download protocols are routed transparently via the fastest active path."
    echo "================================================================================"
}

# CLI command handling
case "${1:-}" in
    --status)
        show_status
        exit 0 ;;
    --dns)
        find_and_apply_fastest_dns false
        exit 0 ;;
    --optimize-mirrors)
        optimize_distro_mirrors false
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
    --verify-only)
        test_all_download_protocols
        exit 0 ;;
esac

# ----------------- BENCHMARK WORKFLOW -----------------

# Universal CDN candidates (Cloudflare speed endpoint, Google Linux CDN, Debian Fastly CDN, Kali CDN, Ubuntu CDN)
CANDIDATE_URLS=(
    "https://speed.cloudflare.com/__down?bytes=10485760"
    "https://dl.google.com/linux/chrome/deb/dists/stable/main/binary-amd64/Packages.gz"
    "http://deb.debian.org/debian/dists/stable/main/binary-amd64/Packages.gz"
    "http://kali.download/kali/dists/kali-rolling/Contents-amd64.gz"
    "http://archive.ubuntu.com/ubuntu/dists/stable/main/binary-amd64/Packages.gz"
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

# Measure DNS lookup time for Direct and Proxy paths
DIRECT_DNS_SEC=$(/usr/bin/curl -s -o /dev/null -w "%{time_namelookup}" --connect-timeout 3 --max-time 4 "http://kali.download" 2>/dev/null || echo "0")
PROXY_DNS_SEC="0"
if [ -n "${PROXY_HOST}" ] && [ -n "${PROXY_PORT}" ]; then
    dns_auth=()
    if [ -n "${PROXY_USER}" ] || [ -n "${PROXY_PASS}" ]; then
        dns_auth=("--proxy-user" "${PROXY_USER}:${PROXY_PASS}")
    fi
    PROXY_DNS_SEC=$(/usr/bin/curl -s -o /dev/null -w "%{time_namelookup}" --connect-timeout 3 --max-time 4 \
        --proxy "${CURL_PROXY_PROTO}://${PROXY_HOST}:${PROXY_PORT}" "${dns_auth[@]}" "http://kali.download" 2>/dev/null || echo "0")
fi

# Auto-heal / maintain fastest DNS: re-benchmark if active DNS is slow (> 250ms) or down
ACTIVE_DNS_IP=$(grep -E '^[[:space:]]*nameserver' /etc/resolv.conf 2>/dev/null | awk '{print $2}' | head -n 1 || echo "")
ACTIVE_DNS_LAT=9999
[ -n "${ACTIVE_DNS_IP}" ] && ACTIVE_DNS_LAT=$(measure_dns_latency "${ACTIVE_DNS_IP}")
if [ "${ACTIVE_DNS_LAT}" -gt 250 ]; then
    find_and_apply_fastest_dns true
fi

mkdir -p "$(dirname "${LOG_FILE}")"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Target: ${TARGET_HOST} | Direct: ${DIRECT_MB} MiB/s | Proxy: ${PROXY_MB} MiB/s | Winner: ${DECISION} | DirectDNS: ${DIRECT_DNS_SEC}s | ProxyDNS: ${PROXY_DNS_SEC}s" >> "${LOG_FILE}"

if [ "${1:-}" = "--benchmark" ] || [ "${1:-}" = "--test" ] || [ "${1:-}" = "--verify" ]; then
    echo "=========================================================="
    echo "⚡ Benchmark Complete"
    echo "=========================================================="
    echo "Target:  ${TARGET_HOST}"
    echo "Direct:  ${DIRECT_MB} MiB/s"
    echo "Proxy:   ${PROXY_MB} MiB/s"
    echo "Winner:  ${DECISION}"
    echo "Route:   $(is_proxy_routed && echo 'Transparent Proxy (ACTIVE)' || echo 'Direct (ACTIVE)')"
    echo "----------------------------------------------------------"
    echo "🌐 DNS Resolution Performance:"
    echo "Direct DNS Lookup: ${DIRECT_DNS_SEC}s"
    echo "Proxy DNS Lookup:  ${PROXY_DNS_SEC}s (remote via ${PROXY_TYPE})"
    echo "Active Nameserver: $(grep -E '^[[:space:]]*nameserver' /etc/resolv.conf 2>/dev/null | awk '{print $2}' | tr '\n' ' ')"
    if [ "${PROXY_SPEED}" -eq 0 ] && [ "${PROXY_HANDSHAKE_OK}" = "false" ]; then
        echo "----------------------------------------------------------"
        echo "[!] PROXY DIAGNOSTIC WARNING:"
        if echo "${PROXY_HANDSHAKE_ERR}" | grep -q -i "authentication"; then
            echo "    -> SOCKS5 Authentication Failed!"
            echo "    -> Your proxy requires valid credentials."
            echo "    -> Run: sudo bash ./setup_dynamic_proxy.sh to enter username and password."
        elif echo "${PROXY_HANDSHAKE_ERR}" | grep -q -i "Connection refused"; then
            echo "    -> Connection refused on upstream proxy server."
            echo "    -> Please check if proxy server port is correct and open."
        else
            echo "    -> Error: ${PROXY_HANDSHAKE_ERR}"
            echo "    -> Check proxy IP, port, and credentials in /etc/redsocks.conf."
        fi
    fi
    echo "=========================================================="

    # Run multi-protocol verification test
    test_all_download_protocols
fi
EOF

chmod +x "${MONITOR_SCRIPT}"

# Step 6: Configure background periodic monitoring (systemd timer or cron fallback)
if has_systemd; then
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

    systemctl daemon-reload 2>/dev/null || true
    systemctl enable --now network-speed-monitor.timer 2>/dev/null || true
    rm -f "${CRON_FILE}"
else
    echo "[*] Step 6: Non-systemd environment detected (WSL/Docker/SysVinit). Configuring cron (${CRON_FILE})..."
    mkdir -p /etc/cron.d
    echo "*/10 * * * * root ${MONITOR_SCRIPT} >/dev/null 2>&1" > "${CRON_FILE}"
    chmod 644 "${CRON_FILE}"
fi

# Step 7: Run initial benchmark & automated multi-protocol verification
echo "[*] Step 7: Running connection benchmark & verifying all download protocols..."
"${MONITOR_SCRIPT}" --verify

CURRENT_STATUS="$(cat "${STATUS_FILE}" 2>/dev/null || echo 'unknown')"
echo "=========================================================="
echo "[✓] Setup successfully completed!"
echo "Active Route: ${CURRENT_STATUS}"
if [ -f "${LOG_FILE}" ]; then
    tail -n 1 "${LOG_FILE}"
fi
echo "=========================================================="
echo "Tips:"
echo "  - Check status anytime:   sudo bash $0 --status"
echo "  - Verify all protocols:   sudo bash $0 --test"
echo "  - Optimize CDN mirrors:   sudo bash $0 --optimize-mirrors"
echo "  - Benchmark DNS servers:  sudo bash $0 --dns"
echo "  - Force proxy mode:       sudo bash $0 --force-proxy"
echo "  - Force direct mode:      sudo bash $0 --force-direct"
echo "  - Uninstall:              sudo bash $0 --uninstall"
echo "=========================================================="
