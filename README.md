## Replace the redsocks config file 
`nano /etc/redsocks.conf` and paste it change ip , port, user, passwd 

```
base {
    log_debug = off;
    log_info = off;
    log = "file:/var/log/redsocks.log";
    daemon = on;
    redirector = iptables;
}

redsocks {
    local_ip = 127.0.0.1;
    local_port = 12345;

    ip = x.x.x.x;
    port = yyyy;
    type = socks5;

    login = "username";
    password = "passwd";
}
```



 Dynamic Proxychains Router
Automatically routes all system traffic through redsocks and iptables transparently whenever the proxy is faster, capturing downloads and network connections from any tool or user across the entire operating system with seamless fallback to direct internet.
 Architectural Overview
 Routing & Performance Comparison
+-----------------------------------------------------------------------+
|                           System Applications                          |
|                  (curl, git, apt, wget, browser, etc.)                 |
+-----------------------------------------------------------------------+
                                    |                                    
                                    v                                    
                    +-------------------------------+                    
                    | iptables (NAT PREROUTING/OUT) |                    
                    +-------------------------------+                    
                                    |                                    
                 +------------------+------------------+                 
                 |                                     |                 
                 v (Proxy Active)                      v (Direct Fallback)
      +---------------------+               +---------------------+      
      | Redsocks (Port 12345) |               |  Direct Connection  |      
      +---------------------+               +---------------------+      
                 |                                     |                 
                 v                                     v                 
      +---------------------+               +---------------------+      
      |   Upstream Proxy    |               |  Internet Gateways  |      
      +---------------------+               +---------------------+      

 Quick Setup Guide
Feature
Transparent Proxy (Redsocks)
Standard Proxy Wrappers
Scope
System-wide (Kernel Level)
Application Level
Tool Compatibility
100% (No configuration needed)
Requires per-tool settings
Fallback Mechanism
Automatic direct routing
Manual disconnection
DNS Optimization
Dynamic multi-provider benchmark
Static local resolver


1. Prerequisites
Install the required packages:
2. Configure Proxy Settings
sudo apt update && sudo apt install -y redsocks iptables curl

Create or edit /etc/redsocks.conf with your upstream proxy credentials:
3. Install Monitoring Script
sudo tee /etc/redsocks.conf > /dev/null << 'EOF'
base {
  log_debug = off;
  log_info = on;
  log = "syslog:daemon";
  daemon = on;
  redirector = iptables;
}
redsocks {
  local_ip = 127.0.0.1;
  local_port = 12345;
  ip = 1.2.3.4;
  port = 1080;
  type = socks5;
  login = "your_username";
  password = "your_password";
}
EOF

Deploy the speed monitor script to system binaries and make it executable:
 Verification & Testing
sudo cp network_speed_monitor.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/network_speed_monitor.sh
sudo /usr/local/bin/network_speed_monitor.sh

Verify active routing state and system connection details:
 Uninstallation
# Check active proxy IP redirection
curl https://ifconfig.me

# Check monitoring logs and active connection state
tail -n 1 /var/log/network_speed_monitor.log
cat /run/fastest_connection

To cleanly remove firewall redirection rules, services, and restore system defaults:

sudo systemctl disable --now network-speed-monitor.timer 2>/dev/null || true
sudo rm -f /etc/systemd/system/network-speed-monitor.*
sudo systemctl daemon-reload

sudo iptables -t nat -F REDSOCKS 2>/dev/null || true
sudo iptables -t nat -D PREROUTING -p tcp -j REDSOCKS 2>/dev/null || true
sudo iptables -t nat -D OUTPUT -p tcp -j REDSOCKS 2>/dev/null || true
sudo systemctl stop redsocks
sudo rm -f /usr/local/bin/network_speed_monitor.sh
sudo rm -f /run/fastest_connection /var/log/network_speed_monitor.log








