# OLG VM Mode Setup Guide

This guide explains how to set up the OpenLAN Gateway (OLG) in **VM mode** for testing and development environments.

## What is VM Mode?

The OLG installer supports two platform modes:

- **BAREMETAL**: For production deployment on dedicated hardware
  - br-wan bridge has NO IP address (pure bridge)
  - VyOS handles all IP addressing
  - Host cannot directly access VyOS network

- **VM**: For testing in nested VM environments or development setups
  - br-wan bridge gets DHCP IP address
  - Creates management network (e.g., 192.168.3.x)
  - VyOS, host, and uCentral container all on same network
  - Easy SSH access for debugging

## When to Use VM Mode

Use VM mode when:
- Testing OLG in a virtualized environment (nested VMs)
- Developing/debugging uCentral integrations
- Need SSH access to VyOS from OLG host
- Upstream network provides DHCP (e.g., Mac Internet Sharing)

## Installation Steps

### 1. Configure Platform Mode

Edit `/opt/staging_scripts/setup-config`:

```bash
sudo nano /opt/staging_scripts/setup-config
# Change: OLG_ISO_PLATFORM="VM"
```

### 2. Run VyOS Setup Script

```bash
sudo /opt/staging_scripts/setup-vyos-bridge.sh
```

The script will automatically:
- Create br-wan with DHCP enabled
- Create VyOS VM with proper boot order
- VyOS ISO will be persistently attached

### 3. Find VyOS IP

After the script completes, wait 30 seconds for VyOS to boot:

```bash
# Find VyOS IP address
ip neigh show dev br-wan

# Or watch for VyOS traffic
sudo tcpdump -i br-wan -n -c 20
```

### 4. SSH to VyOS and Install

```bash
ssh vyos@<VYOS_IP>  # Password: vyos
install image
```

Answer prompts:
- Continue? **y**
- Image name: Press **Enter**
- Password: Press **Enter** (keeps default)
- Console type: **S** (Serial - enables virsh console)
- Install disk: Press **Enter**
- Continue? **y**
- Use all space? **Y**
- Boot config: **2** (default config)

### 5. Reboot and Restart

```bash
reboot
```

**Known Issue:** VM doesn't restart automatically after first reboot.

**Workaround:**
```bash
# From OLG host, wait 10 seconds then:
sudo virsh start vyos
sudo virsh console vyos  # Serial console now works!
```

### 6. Load Factory Configuration

From VyOS console or SSH:

```bash
configure
load /dev/sr1/config.boot
compare
commit
save
exit
```

### 7. Create vyos-info.json

On OLG host (use actual VyOS IP):

```bash
echo '{"host":"https://192.168.3.42","port":443,"key":"MY-HTTPS-API-PLAINTEXT-KEY"}' | \
  sudo tee /opt/ucentral-persistent/ucentral/vyos-info.json
```

## Troubleshooting

### VyOS Not Getting IP

```bash
# Check if VM is running
sudo virsh list --all

# Check DHCP requests
sudo tcpdump -i br-wan -n port 67 or port 68

# Check VM logs
sudo tail -100 /var/log/libvirt/qemu/vyos.log
```

### Cannot SSH to VyOS

```bash
# Verify VyOS IP
ip neigh show dev br-wan

# Try serial console
sudo virsh console vyos
```

### br-wan Not Getting DHCP IP

```bash
# Verify VM mode setting
grep OLG_ISO_PLATFORM /opt/staging_scripts/setup-config

# Check netplan config
cat /etc/netplan/99-vyos-bridges.yaml
# br-wan should have: dhcp4: true

# Apply if needed
sudo netplan apply
```

## Converting from BAREMETAL to VM Mode

1. Update setup-config: `OLG_ISO_PLATFORM="VM"`
2. Update netplan: br-wan `dhcp4: true`
3. Apply: `sudo netplan apply`
4. Destroy and recreate VM:
   ```bash
   sudo virsh destroy vyos
   sudo virsh undefine vyos
   sudo rm -f /var/lib/libvirt/images/vyos.qcow2
   sudo /opt/staging_scripts/setup-vyos-bridge.sh
   ```

## Network Topology in VM Mode

```
Build Mac (192.168.3.1 DHCP Server)
  ↓ Internet Sharing
OLG Host br-wan (192.168.3.41 DHCP)
  ├─ VyOS WAN (192.168.3.42 DHCP)
  └─ uCentral container (192.168.3.13)
```

All three on same 192.168.3.x network = easy SSH debugging!

## References

- Main installation guide: `README.md`
- uCentral setup: `README-Ucentral.md`
- System operations: `docs/OLG_SYSTEM_RESTART_GUIDE.md`
