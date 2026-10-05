===============================================================================

&#x20;                      DYNAMIC PROXYCHAINS ROUTER

===============================================================================



An automated, lightweight background router for Kali, Debian, and Ubuntu that 

dynamically routes command-line downloads (git, apt, curl, wget) through 

proxychains4 whenever the proxy is faster, with automatic fallback to direct 

internet if the proxy slows down or disconnects.



\-------------------------------------------------------------------------------

FEATURES

\-------------------------------------------------------------------------------

\- Zero-Touch Execution: Run 'git clone', 'apt update', 'curl', or 'wget' 

&#x20; normally without typing 'proxychains4' every time.

\- Dynamic Server Benchmarking: Automatically probes high-speed endpoints 

&#x20; (Google, GitHub, Kali, Cloudflare) and selects the lowest-latency target.

\- Pure Wire-Speed Measurement: Measures pure sustained transfer throughput (MiB/s) 

&#x20; without connection handshake latency distorting results.

\- Automatic Failover: If the proxy server drops, commands immediately fall back 

&#x20; to direct internet with no interruption.

\- Background Daemon: A systemd timer benchmarks connections every 10 minutes.



\-------------------------------------------------------------------------------

SUPPORTED COMMANDS

\-------------------------------------------------------------------------------

\- git (clone, pull, fetch)

\- apt \& apt-get (update, upgrade, install)

\- curl

\- wget



\-------------------------------------------------------------------------------

STEP-BY-STEP SETUP

\-------------------------------------------------------------------------------



1\. INSTALL PREREQUISITES

&#x20;  Run in your terminal:

&#x20;  sudo apt update \&\& sudo apt install -y proxychains4 curl git wget



&#x20;  Ensure your proxy is configured in: /etc/proxychains4.conf





2\. CREATE THE MONITOR SCRIPT

&#x20;  Open the file:

&#x20;  sudo nano /usr/local/bin/network\_speed\_monitor.sh



&#x20;  Paste the following script:



\#!/usr/bin/env bash



STATUS\_FILE="/run/fastest\_connection"

LOG\_FILE="/var/log/network\_speed\_monitor.log"



\# Candidate endpoints (Google, GitHub, Kali, Cloudflare)

CANDIDATE\_URLS=(

&#x20;   "https://dl.google.com/linux/chrome/deb/dists/stable/main/binary-amd64/Packages.gz"

&#x20;   "https://codeload.github.com/six2dez/reconftw/tar.gz/refs/heads/main"

&#x20;   "http://http.kali.org/kali/dists/kali-rolling/InRelease"

&#x20;   "https://speed.cloudflare.com/\_\_down?bytes=5242880"

)



\# 1. Dynamically select the fastest responding server

BEST\_URL="${CANDIDATE\_URLS\[0]}"

BEST\_TIME=999



for url in "${CANDIDATE\_URLS\[@]}"; do

&#x20;   resp\_time=$(/usr/bin/curl -s -L -I -o /dev/null -w "%{time\_starttransfer}" --connect-timeout 2 --max-time 4 "${url}" 2>/dev/null || echo "999")

&#x20;   if \[\[ "$resp\_time" =\~ ^\[0-9]+(\\.\[0-9]+)?$ ]]; then

&#x20;       is\_faster=$(awk -v t="${resp\_time}" -v b="${BEST\_TIME}" 'BEGIN { if (t > 0 \&\& t < b) print 1; else print 0 }')

&#x20;       if \[ "$is\_faster" -eq 1 ]; then

&#x20;           BEST\_TIME="$resp\_time"

&#x20;           BEST\_URL="$url"

&#x20;       fi

&#x20;   fi

done



TEST\_URL="${BEST\_URL}"



\# 2. Measure sustained wire speed

measure\_wire\_speed() {

&#x20;   local use\_proxy="$1"

&#x20;   local curl\_cmd=(/usr/bin/curl -s -L -o /dev/null --connect-timeout 4 --max-time 12)



&#x20;   if \[ "$use\_proxy" = "true" ]; then

&#x20;       curl\_cmd=(proxychains4 -q /usr/bin/curl -s -L -o /dev/null --connect-timeout 4 --max-time 12)

&#x20;   fi



&#x20;   local stats

&#x20;   stats=$("${curl\_cmd\[@]}" -w "%{size\_download} %{time\_total} %{time\_starttransfer}" "${TEST\_URL}" 2>/dev/null || echo "0 0 0")



&#x20;   awk -v s="${stats}" 'BEGIN {

&#x20;       split(s, a, " ")

&#x20;       bytes = a\[1] + 0

&#x20;       total\_time = a\[2] + 0

&#x20;       start\_transfer = a\[3] + 0

&#x20;       transfer\_time = total\_time - start\_transfer



&#x20;       if (bytes > 0 \&\& transfer\_time > 0.001) {

&#x20;           printf "%.0f", bytes / transfer\_time

&#x20;       } else {

&#x20;           print "0"

&#x20;       }

&#x20;   }'

}



\# 3. Benchmark both connections

DIRECT\_SPEED=$(measure\_wire\_speed false)

PROXY\_SPEED=$(measure\_wire\_speed true)



\# 4. Compare speeds (proxy wins ties)

DECISION=$(awk -v p="${PROXY\_SPEED}" -v d="${DIRECT\_SPEED}" 'BEGIN {

&#x20;   if (p > 0 \&\& p >= d) {

&#x20;       print "proxy"

&#x20;   } else {

&#x20;       print "direct"

&#x20;   }

}')



\# 5. Atomically update the status file

echo -n "${DECISION}" > "${STATUS\_FILE}.tmp"

mv -f "${STATUS\_FILE}.tmp" "${STATUS\_FILE}"



\# 6. Format and log

DIRECT\_MB=$(awk -v s="${DIRECT\_SPEED}" 'BEGIN { printf "%.2f", s / 1048576 }')

PROXY\_MB=$(awk -v s="${PROXY\_SPEED}" 'BEGIN { printf "%.2f", s / 1048576 }')

TARGET\_HOST=$(echo "${TEST\_URL}" | awk -F\[/:] '{print $4}')



echo "\[$(date '+%Y-%m-%d %H:%M:%S')] Target: ${TARGET\_HOST} | Direct: ${DIRECT\_MB} MiB/s | Proxy: ${PROXY\_MB} MiB/s | Winner: ${DECISION}" >> "${LOG\_FILE}"





&#x20;  Save in nano: Ctrl+O, Enter, Ctrl+X.

&#x20;  Make it executable:

&#x20;  sudo chmod +x /usr/local/bin/network\_speed\_monitor.sh





3\. CREATE COMMAND WRAPPERS

&#x20;  Run this single command in your terminal to create the wrappers:



for cmd in apt apt-get git curl wget; do

&#x20;   target="/usr/bin/${cmd}"

&#x20;   wrapper="/usr/local/bin/${cmd}"



&#x20;   sudo tee "${wrapper}" > /dev/null << EOF

\#!/usr/bin/env bash

STATUS="direct"

\[ -f /run/fastest\_connection ] \&\& STATUS=\\$(cat /run/fastest\_connection 2>/dev/null || echo "direct")



if \[ "\\$STATUS" = "proxy" ] \&\& command -v proxychains4 \&>/dev/null; then

&#x20;   exec proxychains4 -q ${target} "\\$@"

else

&#x20;   exec ${target} "\\$@"

fi

EOF

&#x20;   sudo chmod +x "${wrapper}"

done





4\. ENABLE BACKGROUND MONITOR (SYSTEMD)

&#x20;  Create the systemd service:



sudo tee /etc/systemd/system/network-speed-monitor.service > /dev/null << 'EOF'

\[Unit]

Description=Network Speed Benchmark Monitor

After=network-online.target

Wants=network-online.target



\[Service]

Type=oneshot

ExecStart=/usr/local/bin/network\_speed\_monitor.sh

EOF



&#x20;  Create the systemd timer:



sudo tee /etc/systemd/system/network-speed-monitor.timer > /dev/null << 'EOF'

\[Unit]

Description=Periodic check for proxychains connectivity



\[Timer]

OnBootSec=20s

OnUnitActiveSec=10min

AccuracySec=1min



\[Install]

WantedBy=timers.target

EOF



&#x20;  Enable and start the timer:

&#x20;  sudo systemctl daemon-reload

&#x20;  sudo systemctl enable --now network-speed-monitor.timer





\-------------------------------------------------------------------------------

VERIFICATION \& TESTING

\-------------------------------------------------------------------------------



1\. Run an immediate benchmark:

&#x20;  sudo /usr/local/bin/network\_speed\_monitor.sh

&#x20;  tail -n 1 /var/log/network\_speed\_monitor.log



2\. Check current active route:

&#x20;  cat /run/fastest\_connection



3\. Verify IP routing (shows proxy IP if proxy is winning):

&#x20;  curl https://ifconfig.me



4\. Test git clone (runs at full proxy speed automatically):

&#x20;  git clone https://github.com/six2dez/reconftw.git /tmp/test-repo --depth=1

&#x20;  rm -rf /tmp/test-repo



\-------------------------------------------------------------------------------

HOW TO OVERRIDE / FORCE DIRECT CONNECTION

\-------------------------------------------------------------------------------

\- To force direct connection system-wide:

&#x20; echo "direct" | sudo tee /run/fastest\_connection



\- To bypass the wrapper for a single command:

&#x20; /usr/bin/git clone <url>

&#x20; /usr/bin/apt update

&#x20; /usr/bin/curl <url>



\-------------------------------------------------------------------------------

UNINSTALLATION

\-------------------------------------------------------------------------------

To remove all wrappers and background services:



sudo systemctl disable --now network-speed-monitor.timer 2>/dev/null || true

sudo rm -f /etc/systemd/system/network-speed-monitor.\*

sudo systemctl daemon-reload



sudo rm -f /usr/local/bin/apt \\

&#x20;          /usr/local/bin/apt-get \\

&#x20;          /usr/local/bin/git \\

&#x20;          /usr/local/bin/curl \\

&#x20;          /usr/local/bin/wget \\

&#x20;          /usr/local/bin/network\_speed\_monitor.sh



sudo rm -f /run/fastest\_connection /var/log/network\_speed\_monitor.log



===============================================================================

