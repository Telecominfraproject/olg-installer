# uCentral Customizations for OLG

**Last Updated:** 2026-02-05

---

## Purpose

This directory contains the **23 OLG-specific uCentral files** that enable VyOS router integration with the TIP OpenLAN Gateway (OLG) platform. These files extend the standard uCentral client SDK to support VyOS configuration and state reporting via API instead of traditional OpenWrt UCI rendering used by APs and switches.

## Why These Files Are Separate from Standard Templates

The standard uCentral SDK (from TIP) includes **70+ template files** for OpenWrt-based devices (APs, switches). Those files render configurations to UCI format for devices that use OpenWrt's native configuration system.

**OLG is different:** It uses VyOS as a virtualized router, which has its own configuration system and REST API. These 17 files provide:
1. VyOS capability detection
2. VyOS API integration
3. VyOS-specific configuration templates
4. Router/gateway functionality instead of AP/switch functionality

The OLG uses a custom uCentral client (routerarchitect123/ucentral-client:olgV5) that has been modified to support VyOS router configuration.

---

## File Inventory (23 files)

### Configuration Entry Point (1 file)
- **ucentral.uc** - Main configuration application script (see detailed section below)

### Capability Detection (1 file)
- **capabilities.uc** - Detects VyOS platform and available features (see detailed section below)

### VyOS Core (8 files)
- **vyos/config_prepare.uc** - Main entry point for VyOS config generation (see detailed section below)
- **vyos/https_server_api.uc** - VyOS REST API client library (see detailed section below)
- **vyos/test_mode_detection.uc** - Detects if running in test/standalone mode
- **vyos/state.uc** - VyOS state reporter for uCentral (see detailed section below)
- **vyos/parsers.uc** - Helper library for parsing VyOS data structures (see detailed section below)
- **vyos/vyos-system-stats.py** - Python helper for collecting VyOS system statistics
- **vyos/vyos-system-stats.sh** - Wrapper script for VyOS operational command
- **vyos/node.def** - VyOS operational command template for `show system stats`

### VyOS Templates - Top Level (6 files)
- **vyos/templates/interface.uc** - Main interface configuration orchestrator
- **vyos/templates/nat.uc** - NAT/firewall rules
- **vyos/templates/pki.uc** - PKI/certificate management
- **vyos/templates/service.uc** - Services orchestrator
- **vyos/templates/system.uc** - System-level config (hostname, DNS, etc.)
- **vyos/templates/version.uc** - VyOS version detection

### VyOS Templates - Interface Types (3 files)
- **vyos/templates/interface/bridge.uc** - Bridge interface config
- **vyos/templates/interface/ethernet.uc** - Ethernet interface config
- **vyos/templates/interface/router.uc** - Router-specific interface config

### VyOS Templates - Services (4 files)
- **vyos/templates/services/dhcp-server.uc** - DHCP server configuration
- **vyos/templates/services/dns-forwarding.uc** - DNS forwarding configuration
- **vyos/templates/services/https.uc** - HTTPS server configuration
- **vyos/templates/services/ssh.uc** - SSH server configuration

---

## Deployment Location

When deployed on the MS-01 host, these files are installed to:
```
/opt/ucentral-persistent/
├── capabilities.uc
└── vyos/
    ├── config_prepare.uc
    ├── https_server_api.uc
    ├── test_mode_detection.uc
    └── templates/
        └── [14 template files]
```

The uCentral Docker container mounts this directory as read-only volumes:

```bash
-v /opt/ucentral-persistent/capabilities.uc:/usr/share/ucentral/capabilities.uc
-v /opt/ucentral-persistent/vyos:/usr/share/ucentral/vyos
-v /opt/ucentral-persistent/templates:/usr/share/ucentral/templates
```

---

## Source of Truth & Development Workflow

### Source Repository
These files are synchronized from the **working SDK** located at:
```
/Volumes/OpenWRT-Build/olg-ucentral-client-sdk/
└── feeds/ucentral/ucentral-schema/files/usr/share/ucentral/
```

The working SDK is built from the `ra-olg-ucentral-sdk` branch and contains:
- 38 baseline uCentral files (from TIP upstream)
- 15 OLG-specific additions (these 17 files minus 2 that overlap with baseline)

### When Modifying These Files

1. **Edit in working SDK:**
   ```bash
   cd /Volumes/OpenWRT-Build/olg-ucentral-client-sdk
   # Edit files in feeds/ucentral/ucentral-schema/files/usr/share/ucentral/
   ```

2. **Test on OLG host:**
   ```bash
   scp -O <edited-file> olgadm@<OLG_HOST_IP>:~/
   ssh olgadm@<OLG_HOST_IP>
   sudo cp ~/<edited-file> /opt/ucentral-persistent/<path>
   sudo docker exec ucentral-olg /etc/init.d/ucentral restart
   ```

3. **Sync back to repo when stable:**
   ```bash
   cd ~/git/TIP/OLG/olg-installer
   cp /Volumes/OpenWRT-Build/olg-ucentral-client-sdk/feeds/ucentral/ucentral-schema/files/usr/share/ucentral/<file> \
      iso-files/ucentral-customizations/<path>/
   ```

### Audit Scripts

Use these scripts to verify file synchronization:
```bash
cd ~/git/TIP/OLG/olg-installer

# Compare MS-01 vs Working SDK
./script/audit-uc-files-optimized.sh

# Compare MS-01 vs Pristine SDK baseline
./script/audit-uc-files-pristine.sh
```

---

## ucentral.uc

### Purpose
Main configuration application script that receives JSON configurations from the cloud controller and applies them to the VyOS router or OpenWrt device based on platform detection.

### How It Works

1. **Platform Detection**: Reads `/etc/ucentral/capabilities.json` to determine if platform is "olg" (VyOS) or standard OpenWrt
2. **VyOS Path** (platform == "olg"):
   - Validates JSON configuration against uCentral schema
   - Renders VyOS configuration commands via `vyos.vyos_render()`
   - Applies configuration to VyOS via REST API `/configure/load` endpoint
   - Applies VLANs via `/configure/set` endpoint
   - Updates UCI state config (`/etc/config/state`) with metrics intervals from JSON config
   - Reloads state daemon to pick up new intervals
   - Updates `/etc/ucentral/ucentral.active` symlink to point to successfully applied config
   - Cleans up old config files (keeps 5 most recent)
3. **OpenWrt Path** (standard APs/switches):
   - Validates and renders UCI commands
   - Applies via standard OpenWrt UCI system
   - Updates symlink and cleans up old configs

### Key Features

- **Symlink Management**: Maintains `/etc/ucentral/ucentral.active` symlink pointing to currently applied configuration (with protection against symlink loops)
- **Interval Management**: Reads `metrics.statistics.interval` and `metrics.health.interval` from JSON config, enforces 60-second minimum, writes to UCI, and reloads daemon
- **Config History**: Keeps 5 most recent configuration files, removes older ones
- **Error Handling**: Returns appropriate error codes (0=success, 1=warnings/applied with issues, 2=failed)
- **State Tracking**: Symlink enables state reporter and other components to know which config is active

### Return Codes

- **0 (Success)**: Configuration applied cleanly without warnings
- **1 (Rejects)**: Configuration applied but with non-fatal warnings/issues
- **2 (Failed)**: Configuration validation or application failed completely

Symlink is updated for both error codes 0 and 1 (config was applied), but not for error code 2 (complete failure).

---

## capabilities.uc

### Purpose
This script generates the `/etc/ucentral/capabilities.json` file that informs the uCentral controller about the gateway's hardware and software capabilities.

### How It Works

1. **Initialization**: Loads version/schema files and sets fallback values from previous capabilities.json
2. **VyOS Integration** (uses `/show` endpoint only):
   - Reads connection info from `/etc/ucentral/vyos-info.json`
   - Calls `show configuration json` → gets structured JSON config (interfaces, services, hostname)
   - Calls `show interfaces ethernet <ifname>` → parses MAC addresses from text output
3. **Fallback Handling**: If VyOS API fails, uses values from previous capabilities.json
4. **Output**: Writes `/etc/ucentral/capabilities.json` with discovered capabilities

**Note:** This version uses ONLY the VyOS `/show` endpoint. The `/retrieve` endpoint (showConfig) is broken, but `show configuration json` works perfectly via `/show` and returns identical structured data.

### Key Capabilities Discovered

From VyOS configuration, the script discovers:

- **Network Interfaces**: List of ethernet interfaces (eth0, eth1, etc.)
- **MAC Addresses**: Hardware addresses for WAN and LAN interfaces
- **Hostname**: Router's configured hostname
- **Hardware Offload**: GRO, GSO, SG, TSO capabilities
- **Services**:
  - HTTPS API status
  - SSH server status
  - NTP server status
  - DNS forwarding status
  - DHCP server status

### Dependencies

- **https_server_api.uc**: uCode module for VyOS API communication (see below)
- **vyos-info.json**: Contains VyOS host IP and API key
- **Network Connectivity**: Container must be able to reach VyOS VM (typically on same virtual network as container)

### Testing

Use the test script to verify VyOS integration:

```bash
# From Mac: copy to OLG host
scp -O /tmp/test-capabilities.sh olgadm@<OLG_IP>:~/

# From OLG host: SSH in and run
ssh olgadm@<OLG_IP>
cd ~
chmod +x test-capabilities.sh
sudo ./test-capabilities.sh
```

The test script will:
1. Verify all prerequisites (vyos-info.json, vyos.so, connectivity)
2. Run a debug version of capabilities.uc with extensive logging
3. Compare old vs new capabilities.json
4. Report whether VyOS API calls succeeded

### Manual Execution

To manually regenerate capabilities:

```bash
# From OLG host
sudo docker exec ucentral-olg /usr/share/ucentral/capabilities.uc

# View result
sudo docker exec ucentral-olg cat /etc/ucentral/capabilities.json
```

### Troubleshooting

**Problem**: VyOS API calls fail
- **Check**: Can container ping VyOS? `docker exec ucentral-olg ping <VYOS_IP>`
- **Check**: Is VyOS API configured? `virsh console vyos` → `show service https` (in configure mode)
- **Check**: Is vyos-info.json correct? `docker exec ucentral-olg cat /etc/ucentral/vyos-info.json`

**Problem**: Empty ethernet interfaces or MAC addresses
- **Check**: VyOS configuration exists: `virsh console vyos` → `show interfaces ethernet`
- **Check**: API is returning data (run test script with debug version)

**Problem**: Services all showing false
- **Check**: VyOS has services configured: `virsh console vyos` → `show service` (in configure mode)
- **Note**: Some services (like https-api) may legitimately be disabled

### Known Issues

**VyOS `/retrieve` Endpoint Failure:**

The VyOS HTTPS API `/retrieve` endpoint (used for `showConfig`) returns an internal error:
```json
{"success": false, "error": "An internal error occured. Check the logs for details.", "data": null}
```

This is a VyOS bug, not an issue with our code. The VyOS CLI command `show configuration json pretty` works correctly, but the API endpoint fails.

**Workaround:** The current capabilities.uc uses `show configuration json` via the `/show` endpoint which works reliably:
- ✅ `show configuration json` - gets full structured config (interfaces, services, hostname)
- ✅ `show interfaces ethernet <ifname>` - gets MAC addresses (operational data)

**Impact:** **NONE!** The `show configuration json` command returns identical structured data to what `/retrieve` would return, so all capabilities are discovered correctly.

**Testing the Bug:**
```bash
# This fails:
curl -skL -X POST "https://<VYOS_IP>/retrieve" \
  --form-string data='{"op":"showConfig","path":[]}' \
  --form key="<VYOS_API_KEY>"

# This works:
curl -skL -X POST "https://<VYOS_IP>/show" \
  -H "Content-Type: application/json" \
  -d '{"op": "show", "path": ["interfaces", "ethernet"], "key": "<VYOS_API_KEY>"}'
```

---

## https_server_api.uc

### Purpose
This uCode module provides a wrapper for calling VyOS HTTPS API endpoints. It handles authentication, endpoint selection, and payload formatting for different operation types.

### Supported Operations

1. **showConfig** - Retrieve configuration data (structured JSON)
   - Endpoint: `/retrieve`
   - Returns: JSON representation of VyOS configuration
   - Use: Get configured settings (interfaces, services, system config)

2. **show** - Retrieve operational data (text output)
   - Endpoint: `/show`
   - Returns: Plain text output (same as CLI commands)
   - Use: Get runtime state (MAC addresses, link status, statistics)

3. **load/merge** - Upload configuration files
   - Endpoint: `/config-file`
   - Returns: Success/failure status

4. **set/delete** - Modify configuration
   - Endpoint: `/configure`
   - Returns: Success/failure status

### Usage Example

```javascript
let vyos_api = require("vyos.https_server_api");

// Get full configuration
let config_response = vyos_api.vyos_api_call(
    { path: [] },
    "showConfig",
    "https://<VYOS_IP>",
    "<VYOS_API_KEY>"
);

// Get operational interface data
let show_response = vyos_api.vyos_api_call(
    { path: ["interfaces", "ethernet", "eth0"] },
    "show",
    "https://<VYOS_IP>",
    "<VYOS_API_KEY>"
);
```

### Key Features

- **Automatic endpoint selection**: Based on operation type
- **Shell-safe quoting**: Prevents command injection in curl calls
- **Timeout handling**: 3s connect timeout, 5s total timeout
- **Flexible payload**: Supports both JSON body and form-encoded data
- **Error handling**: Returns null on failure with stderr warnings

### Technical Details

The module uses `curl` via `fs.popen()` to make HTTPS requests. The `-skL` flags disable certificate verification (required for self-signed certs) and follow redirects.

For `showConfig`, the response is structured JSON that can be parsed and traversed. For `show`, the response is plain text that must be parsed with regex or string matching.

---

## config_prepare.uc

**Modifications from SDK baseline:**
- Added `vyos_apply_vlans()` function to apply VLAN configuration via VyOS REST API `/configure` endpoint
- Skips VLAN 1 when building allowed-vlan lists (VLAN 1 is the native/untagged VLAN, cannot be explicitly configured)
- Skips VLAN 1 when creating VIF sub-interfaces
- Creates bridge member allowed-vlan configurations
- Applies VIF (VLAN sub-interface) addresses and descriptions

---

## state.uc

**New file - VyOS state reporter for uCentral cloud integration**

Collects VyOS system state and reports to uCentral cloud controller:
- System info: uptime, load average, memory usage, temperature, CPU load
- Interface statistics: traffic counters, link state, addresses
- Delta counter calculations for traffic monitoring
- Reads configured intervals from `/etc/ucentral/ucentral.active` (enforces 60-second minimum)
- Outputs state to `/tmp/ucentral.state` (for daemon) and `/tmp/vyos-state.json` (for delta tracking)

**Key implementation details:**
- Restructured to avoid nested function calls (uCode limitation: calling user functions from inside other user functions fails)
- Inlined delta calculation logic instead of using helper functions
- Calls VyOS REST API `/show` endpoint with path `["system", "stats"]`
- Parses JSON response from vyos-system-stats helper script

**Dependencies:**
- vyos-system-stats.py - Python script for data collection via netlink
- vyos-system-stats.sh - Wrapper script for VyOS operational command
- node.def - VyOS operational command template
- parsers.uc - Helper library for data structure parsing

---

## parsers.uc

**New file - Helper library for parsing VyOS data**

Provides utility functions for processing VyOS configuration and operational data:
- `get_interface_roles_from_config()` - Determines upstream/downstream interface classification
- Data structure parsing helpers used by state.uc

**Design:** All functions return data structures; no nested function calls to maintain uCode compatibility.

---

## vyos-system-stats.py

**New file - Python helper for VyOS system statistics**

Collects system statistics using Linux netlink API and outputs JSON:
- System: uptime, load average, memory stats
- Interfaces: all network interfaces with traffic counters
- Addresses: IPv4/IPv6 address assignments

**Installation location on VyOS:** `/config/scripts/vyos-system-stats.py`

---

## vyos-system-stats.sh

**New file - Wrapper script for VyOS operational command integration**

Simple wrapper that calls the Python helper script. Enables the script to be called via VyOS CLI and REST API.

**Installation location on VyOS:** `/opt/vyatta/bin/vyos-system-stats`

---

## node.def

**New file - VyOS operational command template**

Registers `show system stats` as a valid VyOS operational command. Required for VyOS REST API to recognize and execute the custom command.

**Installation location on VyOS:** `/opt/vyatta/share/vyatta-op/templates/show/system/stats/node.def`

**Content:**
```
help: Show system statistics
run: /opt/vyatta/bin/vyos-system-stats
allowed: echo ""
```

---

## Relationship to Standard Templates

**Files NOT included here:** The standard uCentral SDK includes 70+ template files for OpenWrt devices:
```
templates/admin_ui.uc
templates/radio.uc
templates/wifi-*.uc
... (67 more files)
```

These standard templates are **not stored here** because they:
1. Come automatically with the Docker image build
2. Are not modified for OLG
3. Are not used by VyOS (they target OpenWrt devices)

---

## Critical Warnings

⚠️ **NEVER delete these files without backups!**
Without these files, the uCentral client cannot communicate with VyOS, and the OLG becomes non-functional.

⚠️ **Volume mounts are critical!**
The Docker container must mount `/opt/ucentral-persistent/` as a volume. If you recreate the container without proper volume mounts, all OLG functionality will be lost.

⚠️ **NEVER use `docker restart ucentral-olg`!**
- ✅ ONLY restart the ucentral process: `sudo docker exec ucentral-olg /etc/init.d/ucentral restart`
- ✅ If container stops, re-run: `sudo ./ucentral-setup.sh setup` (doesn't destroy container, just recreates networking)

⚠️ **Test before deploying!**
Always test file changes on the MS-01 development system before incorporating into production ISOs.

---

## Future Enhancements

Possible improvements to consider:

1. **VLAN Discovery**: Query VyOS for VLAN interfaces and add to capabilities
2. **Bridge Discovery**: Include bridge interfaces in capabilities
3. **Firewall Rules**: Discover firewall zones/rules as capabilities
4. **VPN Capabilities**: Detect configured VPN endpoints
5. **Bandwidth Capabilities**: Query interface speed/duplex settings
6. **Automatic Regeneration**: Hook into VyOS configuration changes to auto-update
7. **Deployment Automation**: Phase 3 - automate file deployment via ISO and setup scripts

---

## References

- **Complete Manifest:** `docs/UCENTRAL_FILES_MANIFEST.md`
- **Action Plan:** `docs/UCENTRAL_FILE_SYNC_ACTION_PLAN.md`
- **Phase 1 Restore Point:** `docs/reference/2026-02-03_PHASE1_COMPLETE_RESTORE_POINT.md`
- **Production Config:** `docs/OLG_PRODUCTION_CONFIG.md`
- **Architecture:** `docs/UCENTRAL_ARCHITECTURE.md`

---

## Version History

- **2026-02-05**:
  - Added state.uc - VyOS state reporter for uCentral cloud integration
  - Added parsers.uc - Helper library for parsing VyOS data structures
  - Added vyos-system-stats.py - Python helper for system statistics collection
  - Added vyos-system-stats.sh - Wrapper script for VyOS operational command
  - Added node.def - VyOS operational command template for `show system stats`
  - Fixed VLAN 1 bug in config_prepare.uc (skip VLAN 1 in allowed-vlan lists)
  - Restructured state.uc to avoid nested function calls (uCode limitation)
  - Total file count: 22 files (was 17)
- **2026-02-03**:
  - Organized all 17 files into repository structure
  - Consolidated file inventory with complete documentation
  - Created audit scripts for verifying synchronization
  - Identified that 70+ template files come from Docker build (not custom)
  - Initial version with VyOS API integration for dynamic capability discovery
  - Added `show` operation support to https_server_api.uc for querying operational data
  - Enhanced capabilities.uc to retrieve MAC addresses from VyOS operational state
  - Workaround for VyOS `/retrieve` endpoint bug: use `show configuration json` via `/show` endpoint
  - Successfully retrieves all data: interfaces, services, hostname (structured JSON)
  - MAC addresses retrieved via `show interfaces ethernet <ifname>` (text parsing)
