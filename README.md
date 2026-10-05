# Dynamic Proxychains Router
After setting this script you don't need to manually put `proxychains4` every command when you are downloading. It completely depends on your proxy speed.
Automatically routes CLI downloads (`git`, `apt`, `curl`, `wget`) through `proxychains4` whenever the proxy is faster, with seamless fallback to direct internet. After installing proxychains4 , `nano /etc/proxychains4.conf` and remove hash before `strict_chain` then save it and exit .

## Quick Setup
### 1. Requirements
Ensure `proxychains4` and `curl` are installed:
```bash
sudo apt update && sudo apt install -y proxychains4 curl git wget
```
*Ensure your proxy is configured in `/etc/proxychains4.conf` and setup fast proxy.*
---
### 2. Main Setup
Run the script `setup_dynamic_proxy.sh` and it will make a `network_speed_monitor.sh` in `/usr/local/bin` directory.

Make it executable and run an initial test:
```bash
sudo chmod +x network_speed_monitor.sh
sudo ./network_speed_monitor.sh
```
Verify connection status:
```bash
tail -n 1 /var/log/network_speed_monitor.log
cat /run/fastest_connection
```
---
### 3. Verification
Check this file should here `/usr/local/bin/` :
`apt`, `apt-get`, `wget`, `curl`, `git`, `network_speed_monitor.sh`
Test that commands route through the proxy automatically:
```bash
# Check your IP (should show proxy IP)
curl https://ifconfig.me

# Test git clone (runs through proxy)
git clone https://github.com/six2dez/reconftw.git /tmp/test-repo --depth=1
rm -rf /tmp/test-repo
```
---
If you find any problem just reboot your system. Make sure `proxychains4` giving you proper speed before installation.

## Uninstallation (Restore Default)
To remove all wrappers and restore original system defaults:
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
This project is to bypass BDIX proxy and ensure full speed from BDIX, just you have add proxy and credentials in `/etc/proxychains4.conf` file and you are good to enjoy faster internet 🚀.

