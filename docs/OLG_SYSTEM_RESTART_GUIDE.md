# OLG System Restart Guide

**Purpose:** Standard Operating Procedure for starting up the OLG system after shutdown or reboot

**Last Updated:** 2026-02-04 (Version 1.1)

---

## System Architecture Quick Reference

```
OLG Host ($OLG_HOST_IP)
├── br-wan (bridge) ← connected to physical WAN port
│   └── VyOS br0 ($VYOS_WAN_IP) ← DHCP from upstream router
├── br-lan (bridge) ← connected to physical LAN port
│   └── VyOS br1 (192.168.1.1/24) + VLANs
└── ucentral-olg container ($CONTAINER_IP) ← on br-wan network
```

**Key Components:**
- **VyOS VM:** Router/gateway running as KVM guest
- **ucentral-olg container:** Docker container managing VyOS via REST API
- **Volume mounts:** All configs/templates persist at `/opt/ucentral-persistent/`

---

## Standard Startup Sequence

### Step 1: Boot OLG Host (Physical Power-On)

```bash
# From your Mac, SSH into OLG Host once it's running
ssh olgadm@$OLG_HOST_IP
# Password: [your password]
```

**Verify host networking:**
```bash
# Check bridges exist
ip link show br-wan
ip link show br-lan

# Should see both bridges in UP state
```

---

### Step 2: Start VyOS VM (5-10 seconds)

```bash
# Check if VyOS is already running
sudo virsh list --all

# If it shows "shut off", start it:
sudo virsh start vyos

# Wait for boot
sleep 15

# Verify VyOS is running
sudo virsh list --all
# Should show "running" state
```

**Verify VyOS network:**
```bash
# VyOS should get IP $VYOS_WAN_IP from DHCP Mac
# Ping from host (may take 30-60 seconds for full boot)
ping -c 3 $VYOS_WAN_IP
```

**If ping fails after 60 seconds:**
```bash
# Check VyOS console to see boot status
sudo virsh console vyos
# Login: vyos / vyos
# Check: show interfaces
# Should show br0 with $VYOS_WAN_IP
# Exit console: Ctrl+]
```

---

### Step 3: Start/Verify Container Networking (30 seconds)

```bash
cd /opt/staging_scripts

# Check if container is running
sudo docker ps | grep ucentral-olg

# If running, verify networking:
sudo docker exec ucentral-olg ip addr show eth0
# Should show $CONTAINER_IP

# If NOT running, or if networking is wrong, recreate it:
sudo ./ucentral-setup.sh setup

# This command:
# - Starts container if stopped
# - Creates veth pair for networking
# - Attaches to br-wan bridge
# - Assigns IP $CONTAINER_IP via DHCP
# - Does NOT destroy container (preserves volume mounts!)

# Wait for DHCP
sleep 10
```

**Verify container can reach VyOS:**
```bash
sudo docker exec ucentral-olg ping -c 3 $VYOS_WAN_IP
# Should succeed
```

---

### Step 4: Verify uCentral Process (10 seconds)

```bash
# Check if ucentral daemon is running with correct serial
sudo docker exec ucentral-olg ps w | grep ucentral | grep $SERIAL

# Should show process like:
# /usr/sbin/ucentral -i $SERIAL ...

# If NOT running:
sudo docker exec ucentral-olg /etc/init.d/ucentral restart

# Wait 5 seconds
sleep 5

# Verify again
sudo docker exec ucentral-olg ps w | grep ucentral | grep $SERIAL
```

---

### Step 5: Check VyOS Basic Configuration (30 seconds)

```bash
# SSH into VyOS from container (easiest path)
sudo docker exec -it ucentral-olg ssh vyos@$VYOS_WAN_IP
# Password: vyos
```

**Inside VyOS, check interfaces:**
```bash
show interfaces

# Expected output should include:
# br0  $VYOS_WAN_IP/24   ... WAN (DHCP)
# br1  192.168.1.1/24    ... LAN
# eth0 -                 ... (member of br0)
# eth1 -                 ... (member of br1)
# lo   127.0.0.1/8       ... Loopback

# VLAN interfaces may or may not be present yet
# br1.100, br1.101, br1.200, br1.1000
```

**Check NAT rules:**
```bash
show nat source rules

# Should show at minimum:
# Rule 101: 192.168.1.0/24 → masquerade via br0

# May show additional rules for VLANs 100, 101, 200, 1000
```

**Check REST API is enabled:**
```bash
show service https api

# Should show:
# rest: enabled
# key: [configured]
```

**Exit VyOS SSH:**
```bash
exit  # or Ctrl+D
```

---

### Step 6: Apply VLAN Configuration (2 minutes)

**Current Situation:**
- VyOS has basic config (br0, br1, NAT for 192.168.1.0/24)
- May be missing VLAN interfaces (br1.100, br1.101, br1.200, br1.1000)
- Container has automation to apply VLANs via REST API

**Solution: Use the VLAN Application Script**

```bash
# From OLG Host, run the persistent VLAN application script
sudo docker exec ucentral-olg ucode /usr/share/ucentral/vyos/apply_vlans_standalone.uc

# Expected output:
# Loaded config from /etc/ucentral/ucentral.cfg.XXXXXXX
# UUID: XXXXXXX
# Applying VLANs via /configure endpoint:
#   Bridge: br1
#   Members: eth1
#   VLANs: 1, 100, 101, 200, 1000
#   ✓ Applied VIF 100: 192.168.100.1/24
#   ✓ Applied VIF 101: 192.168.101.1/24
#   ✓ Applied VIF 200: 192.168.200.1/24
#   ✓ Applied VIF 1000: 172.20.0.1/20
# ✓ VLAN application completed
#
# Note: VLAN 1 appears in the list but is automatically skipped during
# application because it's the native/untagged VLAN (the bridge itself)
```

**Verify VLANs Were Applied to VyOS:**

```bash
# SSH into VyOS to verify configuration
sudo docker exec -it ucentral-olg ssh vyos@$VYOS_WAN_IP

# Enter configure mode to view the configuration
configure

# Check VIF interfaces were created
show interfaces bridge br1 vif

# Expected output:
# vif 100 {
#     address 192.168.100.1/24
#     description LAN-VLAN100
# }
# vif 101 {
#     address 192.168.101.1/24
#     description LAN-VLAN101
# }
# vif 200 {
#     address 192.168.200.1/24
#     description LAN-VLAN200
# }
# vif 1000 {
#     address 172.20.0.1/20
#     description LAN-VLAN1000
# }

# Also check bridge member allowed-vlans
show interfaces bridge br1

# Should show eth1 with allowed-vlan entries for 100, 101, 200, 1000
# Note: VLAN 1 is NOT in allowed-vlan list (it's the native VLAN)
```

**Save Configuration (Critical!):**

The VyOS API `/configure` endpoint automatically commits changes, but does NOT save them to disk. You must manually save to persist across reboots.

```bash
# Still in configure mode from above commands

# Try to commit (may show "No configuration changes to commit" - this is OK)
commit

# IMPORTANT: Save configuration to persist across reboots
save

# Exit configure mode
exit

# Exit VyOS SSH
exit
```

**⚠️ Important Notes:**
- The API auto-commits changes, so `commit` may show "No configuration changes to commit"
- `save` is REQUIRED to persist configuration across VyOS reboots
- Without `save`, all VLAN configuration will be lost on next VyOS restart
- This script is volume-mounted from `/opt/ucentral-persistent/vyos/` and persists across container restarts

---

### Step 7: Verify DHCP Server (10 seconds)

**Why:** DHCP server binds to interface IPs at startup. After adding VLANs, it may need restart to serve DHCP on new VLAN interfaces. However, the VyOS API often automatically restarts DHCP when interface changes are made.

**Check if DHCP is already serving on VLANs:**

```bash
# SSH to VyOS
sudo docker exec -it ucentral-olg ssh vyos@$VYOS_WAN_IP

# Check DHCP server statistics (operational mode)
show dhcp server statistics

# Expected output should show 5 pools:
# Pool          Size    Leases    Available    Usage
# LAN-VLAN1     90      X         XX           X%
# LAN-VLAN100   150     X         XX           X%
# LAN-VLAN101   150     X         XX           X%
# LAN-VLAN200   50      X         XX           X%
# LAN-VLAN1000  3800    X         XX           X%
```

**If DHCP pools are missing or not all 5 are shown, manually restart:**

```bash
# Still inside VyOS SSH (operational mode, NOT configure mode)
restart dhcp server

# Wait 5 seconds for restart to complete

# Verify all pools now appear
show dhcp server statistics

# Exit
exit
```

**Advanced verification (optional):**
```bash
sudo docker exec -it ucentral-olg ssh vyos@$VYOS_WAN_IP

# Check DHCP is listening on all VLAN IPs
sudo netstat -uln | grep :67

# Expected output (5 DHCP listeners):
# udp 0.0.0.0:67   0.0.0.0:67   192.168.1.1:67
# udp 0.0.0.0:67   0.0.0.0:67   192.168.100.1:67
# udp 0.0.0.0:67   0.0.0.0:67   192.168.101.1:67
# udp 0.0.0.0:67   0.0.0.0:67   192.168.200.1:67
# udp 0.0.0.0:67   0.0.0.0:67   172.20.0.1:67

exit
```

---

### Step 8: Verify Complete System Health (1 minute)

**Health Check Commands:**

```bash
# On OLG Host:

# 1. VyOS running and reachable
ping -c 2 $VYOS_WAN_IP

# 2. Container running with correct serial
sudo docker exec ucentral-olg ps w | grep $SERIAL

# 3. Volume mounts working
sudo docker exec ucentral-olg ls -la /usr/share/ucentral/templates/bridge.uc
sudo docker exec ucentral-olg ls -la /usr/share/ucentral/vyos/config_prepare.uc

# 4. Container can reach VyOS API
sudo docker exec ucentral-olg curl -k -X POST https://$VYOS_WAN_IP/retrieve \
  -H "Content-Type: application/json" \
  -d '{"op":"showConfig","path":["interfaces"],"key":"ucentral-secret-key"}' 2>/dev/null | head -c 100

# Should return JSON starting with: {"success": true, "data": ...

# 5. Verify ubus services registered
sudo docker exec ucentral-olg ubus list | grep -E "(state|ucentral)"
# Should show both "state" and "ucentral"

# 6. Verify cloud connection
sudo docker exec ucentral-olg ubus call ucentral status
# Should show "connected": [number] (seconds connected)

# 7. Verify telemetry reporting is active
sudo docker exec ucentral-olg sh -c 'logread | grep "state execute" | tail -3'
# Should show recent "state execute" logs (every 60 seconds)
```

**Check VyOS has all VLANs (operational mode view):**
```bash
sudo docker exec -it ucentral-olg ssh vyos@$VYOS_WAN_IP

# From operational mode, view active interfaces
show interfaces

# Should show all VLANs as u/u (up/up):
# br1       192.168.1.1/24    ... u/u  LAN
# br1.100   192.168.100.1/24  ... u/u  LAN-VLAN100
# br1.101   192.168.101.1/24  ... u/u  LAN-VLAN101
# br1.200   192.168.200.1/24  ... u/u  LAN-VLAN200
# br1.1000  172.20.0.1/20     ... u/u  LAN-VLAN1000

exit
```

**Note:** Use `show interfaces` in operational mode to see active interfaces with their state. Use `configure` mode with `show interfaces bridge br1` to see the configuration structure.

---

## System is Ready! ✅

At this point:
- ✅ VyOS is routing traffic with 5 VLANs
- ✅ Container is connected to cloud gateway
- ✅ DHCP is serving on all VLANs
- ✅ NAT is working for all networks
- ✅ REST API is enabled for config pushes

You can now connect devices to VLANs and they should get DHCP leases and internet access.

---

## Troubleshooting

### Problem: VyOS Not Getting IP

**Symptoms:**
```bash
ping -c 2 $VYOS_WAN_IP
# Destination Host Unreachable
```

**Solution:**
```bash
# Check VyOS console
sudo virsh console vyos
# Login: vyos / vyos

show interfaces

# If br0 doesn't have IP:
configure
set interfaces bridge br0 address dhcp
commit
save
exit

# Wait 10 seconds, check again:
show interfaces | grep br0
# Should show $VYOS_WAN_IP

# Exit console: Ctrl+]
```

---

### Problem: Container Not Getting IP or Wrong IP

**Symptoms:**
```bash
sudo docker exec ucentral-olg ip addr show eth0
# Shows wrong IP or no IP
```

**Solution:**
```bash
cd /opt/staging_scripts
sudo ./ucentral-setup.sh setup

# This recreates networking without destroying container
# Wait 15 seconds

# Verify:
sudo docker exec ucentral-olg ip addr show eth0
# Should show $CONTAINER_IP
```

---

### Problem: VLANs Missing After Restart

**Symptoms:**
```bash
sudo docker exec -it ucentral-olg ssh vyos@$VYOS_WAN_IP
show interfaces | grep br1
# Only shows br1, no br1.100, br1.101, etc.
exit
```

**Root Cause:** VyOS was shut down before VLANs were applied, or config wasn't saved

**Solution:** Re-run VLAN application (Step 6 above)

---

### Problem: VLAN Application Script Fails

**Symptoms:**
```bash
sudo docker exec -it ucentral-olg sh
ucode /tmp/test_vyos_apply_vlans.uc
# Error: Cannot open file
```

**Solution:** Recreate the script (see Appendix A)

---

### Problem: DHCP Not Working on VLANs

**Symptoms:**
- Devices on VLANs don't get IP addresses
- VyOS `show dhcp server leases` shows no leases for VLAN subnets

**Solution:**
```bash
# Restart DHCP server (Step 7)
sudo docker exec -it ucentral-olg ssh vyos@$VYOS_WAN_IP

restart dhcp server

# Verify listening:
sudo netstat -uln | grep :67
# Should show all 5 VLAN IPs

exit
```

---

### Problem: uCentral Process Not Running

**Symptoms:**
```bash
sudo docker exec ucentral-olg ps w | grep ucentral
# Shows nothing, or shows process without serial $SERIAL
```

**Solution:**
```bash
# Restart ucentral service (NOT container!)
sudo docker exec ucentral-olg /etc/init.d/ucentral restart

# Wait 5 seconds
sleep 5

# Verify:
sudo docker exec ucentral-olg ps w | grep $SERIAL
```

---

### Problem: Telemetry Not Being Sent to Cloud

**Symptoms:**
```bash
# ucentral daemon is connected to cloud
sudo docker exec ucentral-olg ubus call ucentral status
# Shows: "connected": [number]

# But no state messages are being sent
sudo docker exec ucentral-olg sh -c 'logread | grep "state execute" | tail -5'
# Shows no recent entries (should be every 60 seconds)

# Or ubus calls hang with no response
sudo docker exec ucentral-olg ubus call state reload
# Command hangs or returns "No response"
```

**Root Cause:** The `ucentral-state` process (which manages telemetry reporting) is hung. This can occur if the process's event loop becomes blocked.

**Solution:**
```bash
# Restart the ucentral-state process (it will auto-restart)
sudo docker exec ucentral-olg sh -c 'kill $(pidof ucentral-state)'

# Wait a few seconds
sleep 5

# Verify it restarted
sudo docker exec ucentral-olg ps w | grep ucentral-state
# Should show new PID

# Check logs for timer initialization
sudo docker exec ucentral-olg sh -c 'logread | grep state | tail -10'
# Should show:
#   "loading config"
#   "start state in 60 seconds"
#   "going online"

# Wait 65 seconds and verify state reporting is working
sleep 65
sudo docker exec ucentral-olg sh -c 'logread | grep "state execute" | tail -3'
# Should show recent executions
```

**Note:** With the fixed `ucentral-setup.sh` script (no dual ubusd bug), this hang should not occur during normal restarts. It was observed during development testing when network interfaces were manually deleted while services were running.

---

### Problem: REST API Returns 404

**Symptoms:**
```bash
sudo docker exec ucentral-olg curl -k https://$VYOS_WAN_IP/retrieve ...
# Returns: 404 Not Found
```

**Solution:**
```bash
# Enable REST API in VyOS
sudo docker exec -it ucentral-olg ssh vyos@$VYOS_WAN_IP

configure
set service https api rest
commit
save
exit

# Exit SSH
exit
```

---

### Understanding VyOS Configuration Modes

**VyOS has two distinct modes:**

**1. Operational Mode (default login state):**
- Prompt shows: `vyos@vyos:~$`
- Used for viewing live system state and running commands
- Commands: `show interfaces`, `show dhcp server`, `restart dhcp server`, `ping`, etc.
- Cannot modify configuration in this mode

**2. Configure Mode:**
- Prompt shows: `[edit] vyos@vyos#`
- Enter with: `configure` command
- Used for viewing and modifying configuration structure
- Commands: `show interfaces bridge br1`, `set ...`, `commit`, `save`
- Exit with: `exit` command (returns to operational mode)

**Key Differences:**

| Task | Mode | Command |
|------|------|---------|
| View active interface IPs/state | Operational | `show interfaces` |
| View configuration structure | Configure | `configure` then `show interfaces bridge br1` |
| View VIF configuration | Configure | `configure` then `show interfaces bridge br1 vif` |
| Check DHCP statistics | Operational | `show dhcp server statistics` |
| Restart services | Operational | `restart dhcp server` |
| Modify configuration | Configure | `set ...` then `commit` then `save` |
| Save configuration | Configure | `save` |

**Important:** When SSH'ing into VyOS, you start in operational mode. Many configuration details (like VIF structure) can only be viewed in configure mode with `show` commands.

---

## Quick Commands Reference

```bash
# Start VyOS
sudo virsh start vyos

# Restart container networking
cd /opt/staging_scripts && sudo ./ucentral-setup.sh setup

# Restart ucentral process
sudo docker exec ucentral-olg /etc/init.d/ucentral restart

# Apply VLANs (persistent script)
sudo docker exec ucentral-olg ucode /usr/share/ucentral/vyos/apply_vlans_standalone.uc

# Restart DHCP (must do interactively)
sudo docker exec -it ucentral-olg ssh vyos@$VYOS_WAN_IP
# Then inside VyOS: restart dhcp server

# Full health check
ping -c 2 $VYOS_WAN_IP && \
sudo docker exec ucentral-olg ps w | grep $SERIAL
```

---

## Appendix A: VLAN Application Script Details

**Script Location:** `/usr/share/ucentral/vyos/apply_vlans_standalone.uc` (volume-mounted, persistent)

**Purpose:** Applies VLAN interfaces to VyOS using the `/configure` REST API endpoint.

**Features:**
- Auto-detects latest config file (highest UUID)
- Validates config using schema
- Creates VLAN sub-interfaces (br1.100, br1.101, etc.)
- Skips VLAN 1 (it's the bridge itself)
- Provides detailed output

**If script is missing or needs recreation:**

```bash
# From OLG Host
sudo docker exec -it ucentral-olg sh

# Inside container, create script in persistent location:
cat > /usr/share/ucentral/vyos/apply_vlans_standalone.uc << 'EOF'
push(REQUIRE_SEARCH_PATH,
    "/usr/lib/ucode/*.so",
    "/usr/share/ucentral/*.uc");

let fs = require("fs");
let vyos = require("vyos.config_prepare");
let schemareader = require("schemareader");

// Find latest config file (prefer highest UUID)
let config_file = null;
let max_uuid = 0;
let files = fs.lsdir("/etc/ucentral");
for (let fname in files) {
    if (index(fname, "ucentral.cfg.") == 0) {
        let this_file = "/etc/ucentral/" + fname;
        let f = fs.open(this_file, "r");
        let cfg = json(f.read("all"));
        f.close();

        if (cfg && cfg.uuid && cfg.uuid > max_uuid) {
            max_uuid = cfg.uuid;
            config_file = this_file;
        }
    }
}

if (!config_file) {
    printf("ERROR: No config file found in /etc/ucentral/\n");
    exit(1);
}

printf("Loaded config from %s\n", config_file);

let inputfile = fs.open(config_file, "r");
let inputjson = json(inputfile.read("all"));
inputfile.close();

printf("UUID: %s\n", inputjson.uuid);
if (inputjson.description) {
    printf("Description: %s\n\n", inputjson.description);
}

let logs = [];
let state = schemareader.validate(inputjson, logs);

if (state) {
    let result = vyos.vyos_apply_vlans(state);
    if (result) {
        printf("\n✓ VLAN application completed\n");
    } else {
        printf("\n✗ VLAN application failed\n");
        exit(1);
    }
} else {
    printf("Validation failed!\n");
    for (let log in logs) {
        printf("%s\n", log);
    }
    exit(1);
}
EOF

# Test it:
ucode /usr/share/ucentral/vyos/apply_vlans_standalone.uc

exit
```

**Note:** This script is stored in a volume-mounted directory, so it persists across container restarts.

---

## Appendix B: Understanding Volume Mounts

**Why volume mounts matter:**
- Container can be destroyed/recreated without losing data
- All template fixes persist across restarts
- Certificates and configs are safe

**Volume mount locations:**
```
Host Path                              → Container Path
/opt/ucentral-persistent/templates     → /usr/share/ucentral/templates
/opt/ucentral-persistent/vyos          → /usr/share/ucentral/vyos
/opt/ucentral-persistent/config        → /etc/config
/opt/ucentral-persistent/config-shadow → /etc/config-shadow
/opt/ucentral-persistent/ucentral      → /etc/ucentral
```

**Verify volume mounts:**
```bash
sudo docker inspect ucentral-olg | grep -A 20 "Mounts"
```

---

## Appendix C: Network Topology

```
┌─────────────────────────────────────────────────────────┐
│ OLG Host ($OLG_HOST_IP)                              │
│                                                           │
│  ┌──────────────┐                                        │
│  │ br-wan       │                                        │
│  │ (bridge)     │──────┐                                 │
│  └──────────────┘      │                                 │
│         │              │                                  │
│         │              │   ┌──────────────────────┐      │
│         │              └───│ VyOS VM              │      │
│    Physical WAN           │ br0: $VYOS_WAN_IP    │      │
│    Port ($WAN_IF)         │ br1: 192.168.1.1     │      │
│                           │  ├─ br1.100: .100.1  │      │
│  ┌──────────────┐         │  ├─ br1.101: .101.1  │      │
│  │ br-lan       │─────────│  ├─ br1.200: .200.1  │      │
│  │ (bridge)     │  ┌──────│  └─ br1.1000: 172... │      │
│  └──────────────┘  │      └──────────────────────┘      │
│         │          │                                     │
│         │          │                                     │
│    Physical LAN    │      ┌──────────────────────┐      │
│    Port ($ADMIN_IF)  └──────│ ucentral-olg         │      │
│                           │ Container            │      │
│                           │ IP: $CONTAINER_IP     │      │
│                           └──────────────────────┘      │
│                                                           │
└─────────────────────────────────────────────────────────┘
         │                            │
         │                            │
         ▼                            ▼
    Switch/APs                   DHCP Mac
    (on VLANs)                   UPSTREAM_ROUTER_IP
                                 (serves 192.168.3.0/24)
```

---

## Changelog

### Version 1.3 - 2026-02-06
- Added telemetry verification steps to Step 8 (health checks)
- Added troubleshooting section for ucentral-state process hang
- Added verification of ubus service registration
- Added cloud connection status check
- Documented fix for telemetry reporting issues

### Version 1.2 - 2026-02-05
- Clarified that VLAN 1 is automatically skipped during VLAN application
- Updated expected output examples to note VLAN 1 behavior
- Corrected allowed-vlan list expectations (VLAN 1 not included)

### Version 1.1 - 2026-02-04
- Added VyOS configuration verification steps in Step 6
- Added `save` requirement to persist configuration across reboots
- Updated Step 7 to note DHCP may auto-restart
- Added "Understanding VyOS Configuration Modes" troubleshooting section
- Clarified configure mode vs operational mode usage

### Version 1.0 - 2026-02-03
- Initial document creation

---

**Document Version:** 1.3
**Last Tested:** 2026-02-06
