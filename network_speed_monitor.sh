#!/usr/bin/env bash

STATUS_FILE="/run/fastest_connection"
LOG_FILE="/var/log/network_speed_monitor.log"

# Candidate high-speed endpoints (Google, GitHub, Kali, Cloudflare)
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

# 3. Benchmark both connections against the selected fastest target
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

# 6. Format and log with target server info
DIRECT_MB=$(awk -v s="${DIRECT_SPEED}" 'BEGIN { printf "%.2f", s / 1048576 }')
PROXY_MB=$(awk -v s="${PROXY_SPEED}" 'BEGIN { printf "%.2f", s / 1048576 }')
TARGET_HOST=$(echo "${TEST_URL}" | awk -F[/:] '{print $4}')

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Target: ${TARGET_HOST} | Direct: ${DIRECT_MB} MiB/s | Proxy: ${PROXY_MB} MiB/s | Winner: ${DECISION}" >> "${LOG_FILE}"
