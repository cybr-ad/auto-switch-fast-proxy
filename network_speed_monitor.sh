#!/usr/bin/env bash
set -euo pipefail

STATUS_FILE="/run/fastest_connection"
LOG_FILE="/var/log/network_speed_monitor.log"
TEST_URL="https://github.com"

# Check if proxychains can reach the internet
if proxychains4 -q /usr/bin/curl -s -I --connect-timeout 5 --max-time 10 "${TEST_URL}" >/dev/null 2>&1; then
    DECISION="proxy"
else
    DECISION="direct"
fi

echo "${DECISION}" > "${STATUS_FILE}.tmp"
mv "${STATUS_FILE}.tmp" "${STATUS_FILE}"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Connection status: ${DECISION} (Proxy preferred)" >> "${LOG_FILE}"