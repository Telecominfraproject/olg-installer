#!/usr/bin/env bash

set -euo pipefail

# Source our configs
source /opt/staging_scripts/setup-config

# Some statis configs
VM_NAME="vyos"
IMAGES_DIR="/var/lib/libvirt/images"
ISO_PATH="$IMAGES_DIR/vyos.iso"
DISK_PATH="$IMAGES_DIR/${VM_NAME}.qcow2"
BR_WAN="br-wan"
BR_LAN="br-lan"
NETPLAN_FILE="/etc/netplan/99-vyos-bridges.yaml"
# Default: no DHCP on WAN bridge
BR_WAN_DHCP4="false"
# OLG_ISO_PLATFORM is where this ISO is running
# Valid values: BAREMETAL | VM . Extensible (later: CLOUD, etc)
if [[ "${OLG_ISO_PLATFORM}" == "VM" ]]; then
  BR_WAN_DHCP4="true"
fi

# Make sure we are running as root
if [[ $EUID -ne 0 ]]; then
  echo "Please run as root (sudo $0)"; exit 1
fi

# Make sure we have netplan available
command -v netplan >/dev/null 2>&1 || { echo "netplan not found. This script targets Ubuntu with netplan."; exit 1; }

# Validate network interface configuration
echo ">>> Validating network interface configuration..."
MISSING_IFACES=()
for IFACE in "$WAN_IF" "$LAN_IF" "$ADMIN_IF"; do
  if ! ip link show "$IFACE" >/dev/null 2>&1; then
    MISSING_IFACES+=("$IFACE")
  fi
done

if [ ${#MISSING_IFACES[@]} -gt 0 ]; then
  echo ""
  echo "============================================================================"
  echo "ERROR: Interface(s) not found: ${MISSING_IFACES[*]}"
  echo "============================================================================"
  echo ""
  echo "Please edit /opt/staging_scripts/setup-config and set correct interface names."
  echo ""
  echo "Available interfaces on this system:"
  ip link show | grep '^[0-9]' | awk '{print "  - " $2}' | sed 's/:$//'
  echo ""
  echo "To find interface details, run: ip link show"
  echo ""
  exit 1
fi

echo "[✓] All required interfaces found: WAN=$WAN_IF, LAN=$LAN_IF, ADMIN=$ADMIN_IF"

echo ">>> Set the host hostname"
/opt/staging_scripts/set-hostname

echo ">>> Installing virtualization packages..."
apt-get update -y
apt-get install -y qemu-kvm libvirt-daemon-system libvirt-clients virtinst bridge-utils cloud-image-utils libguestfs-tools xorriso genisoimage syslinux-utils

echo ">>> Installing Docker..."
sh /opt/staging_scripts/get-docker.sh

# Get VyOS ISO
# All Downloads/Updates should be done on stable network, before network configurations are changed
if [[ ! -f "$ISO_PATH" ]]; then
  echo ">>> Downloading VyOS ISO to $ISO_PATH"
  echo -e "#!/bin/bash\ncurl -fL $ISO_URL -o $ISO_PATH" >download_iso.sh
  chmod +x download_iso.sh
  ./download_iso.sh
  rm -f download_iso.sh

  # Verify SHA256 checksum
  echo ">>> Verifying SHA256 checksum..."
  ACTUAL_SHA256=$(sha256sum "$ISO_PATH" | awk '{print $1}')
  if [[ "$ACTUAL_SHA256" != "$ISO_SHA256" ]]; then
    echo "ERROR: SHA256 checksum mismatch!"
    echo "Expected: $ISO_SHA256"
    echo "Actual:   $ACTUAL_SHA256"
    echo "Removing corrupted ISO file..."
    rm -f "$ISO_PATH"
    exit 1
  fi
  echo ">>> SHA256 checksum verified successfully"
else
  echo ">>> VyOS ISO already present at $ISO_PATH"
  # Verify SHA256 checksum of existing file
  echo ">>> Verifying SHA256 checksum of existing ISO..."
  ACTUAL_SHA256=$(sha256sum "$ISO_PATH" | awk '{print $1}')
  if [[ "$ACTUAL_SHA256" != "$ISO_SHA256" ]]; then
    echo "WARNING: SHA256 checksum mismatch for existing ISO!"
    echo "Expected: $ISO_SHA256"
    echo "Actual:   $ACTUAL_SHA256"
    echo "Removing existing ISO and re-downloading..."
    rm -f "$ISO_PATH"
    echo -e "#!/bin/bash\ncurl -fL $ISO_URL -o $ISO_PATH" >download_iso.sh
    chmod +x download_iso.sh
    ./download_iso.sh
    rm -f download_iso.sh

    # Verify SHA256 checksum of new download
    echo ">>> Verifying SHA256 checksum..."
    ACTUAL_SHA256=$(sha256sum "$ISO_PATH" | awk '{print $1}')
    if [[ "$ACTUAL_SHA256" != "$ISO_SHA256" ]]; then
      echo "ERROR: SHA256 checksum mismatch!"
      echo "Expected: $ISO_SHA256"
      echo "Actual:   $ACTUAL_SHA256"
      echo "Removing corrupted ISO file..."
      rm -f "$ISO_PATH"
      exit 1
    fi
    echo ">>> SHA256 checksum verified successfully"
  else
    echo ">>> SHA256 checksum verified successfully"
  fi
fi

echo ">>> Ensuring libvirtd is running..."
systemctl enable --now libvirtd
mkdir -p "$IMAGES_DIR"

# Configure host bridges via netplan
echo ">>> Writing netplan to create $BR_WAN (via $WAN_IF) and $BR_LAN (via $LAN_IF): $NETPLAN_FILE"
cat > "$NETPLAN_FILE" <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    ${WAN_IF}:
      dhcp4: false
      dhcp6: false
    ${LAN_IF}:
      dhcp4: false
      dhcp6: false
  bridges:
    ${BR_WAN}:
      interfaces: [${WAN_IF}]
      dhcp4: ${BR_WAN_DHCP4}
      dhcp6: false
      parameters:
        stp: false
        forward-delay: 0
    ${BR_LAN}:
      interfaces: [${LAN_IF}]
      dhcp4: false
      dhcp6: false
      parameters:
        stp: false
        forward-delay: 0
EOF
chmod 600 /etc/netplan/*.yaml

echo ">>> Applying netplan (this may momentarily disrupt links on $WAN_IF/$LAN_IF)..."
netplan apply

# System settings
echo br_netfilter | tee /etc/modules-load.d/br_netfilter.conf
modprobe br_netfilter
tee /etc/sysctl.d/99-bridge-nf-off.conf >/dev/null <<'EOF'
net.bridge.bridge-nf-call-iptables=0
net.bridge.bridge-nf-call-ip6tables=0
net.bridge.bridge-nf-call-arptables=0
EOF
sysctl --system

# Create an ISO with out example config files
mkisofs -joliet -rock -volid "cidata" -output /var/lib/libvirt/boot/vyos-configs.iso /opt/staging_scripts/vyos-configs/vyos-factory-config

# Create VM disk
if [[ ! -f "$DISK_PATH" ]]; then
  echo ">>> Creating disk $DISK_PATH (${DISK_GB}G)"
  qemu-img create -f qcow2 "$DISK_PATH" "${DISK_GB}G"
else
  echo ">>> Disk already exists at $DISK_PATH"
fi

# If a previous domain with the same name exists, define a new one will fail.
if virsh dominfo "$VM_NAME" >/dev/null 2>&1; then
  echo ">>> A VM named '$VM_NAME' already exists. Skipping creation."
  echo "You can start it with: virsh start $VM_NAME && virsh console $VM_NAME"
  exit 0
fi

# Create & start VM
echo ">>> Creating VyOS VM '$VM_NAME'..."
virt-install -n "$VM_NAME" \
  --cpu host --ram "$RAM_MB" \
  --vcpus "$VCPUS" \
  --boot cdrom,hd \
  --disk path="$ISO_PATH",device=cdrom,bus=sata,readonly=on \
  --os-variant debian12 \
  --network bridge="$BR_WAN",model=virtio \
  --network bridge="$BR_LAN",model=virtio \
  --graphics vnc \
  --hvm \
  --virt-type kvm \
  --disk path="$DISK_PATH",bus=virtio,size="$DISK_GB" \
  --disk path=/var/lib/libvirt/boot/vyos-configs.iso,device=cdrom,bus=sata,readonly=on \
  --noautoconsole

# Set the VM to autostart on host boot
virsh autostart $VM_NAME

echo ">>> Setting up uCentral persistent directories..."
# Note: Only config directories needed - .uc files are now in Docker image (ucentral-client:olgV6)
mkdir -p /opt/ucentral-persistent/{config,config-shadow,ucentral}

echo ">>> Setting permissions..."
chown -R root:root /opt/ucentral-persistent
chmod -R 755 /opt/ucentral-persistent

echo "[✓] uCentral persistent directories created"
echo "    Note: .uc integration files are now in Docker image ucentral-client:olgV6"

echo ">>> VyOS API configuration setup..."
echo ""
if [[ "${OLG_ISO_PLATFORM}" == "VM" ]]; then
  echo "NOTE: Running in VM mode - br-wan has DHCP enabled and will get an IP."
  echo "      VyOS will also get an IP via DHCP on the same network."
  echo "      You can find VyOS IP with: ip neigh show dev br-wan"
  echo "      Or use: sudo tcpdump -i br-wan -n to watch for VyOS traffic"
else
  echo "NOTE: VyOS IP auto-detection cannot run from the OLG host because the host"
  echo "      does not have an IP on br-wan (it's just a bridge)."
fi
echo ""
echo "You must manually create vyos-info.json BEFORE running ucentral-setup.sh:"
echo ""
echo "Steps to create vyos-info.json:"
if [[ "${OLG_ISO_PLATFORM}" == "VM" ]]; then
  echo "  1. After VyOS installation, find VyOS IP: ip neigh show dev br-wan"
  echo "  2. SSH to VyOS: ssh vyos@<VYOS_IP> (password: vyos)"
  echo "  3. Check interfaces: show interfaces"
  echo "  4. Create vyos-info.json with the VyOS IP:"
else
  echo "  1. After VyOS installation, connect to console: sudo virsh console vyos"
  echo "  2. Check VyOS WAN IP with: show interfaces"
  echo "  3. Create vyos-info.json with the VyOS IP:"
fi
echo ""
echo "     echo '{\"host\":\"https://VYOS_WAN_IP\",\"port\":443,\"key\":\"MY-HTTPS-API-PLAINTEXT-KEY\"}' | sudo tee /opt/ucentral-persistent/ucentral/vyos-info.json"
echo ""

echo ""
echo "======================================================================"
echo "VyOS VM setup complete!"
echo "======================================================================"
echo ""
if [[ "${OLG_ISO_PLATFORM}" == "VM" ]]; then
  echo "Next steps (VM mode):"
  echo "  1. Wait for VyOS to boot (~30 seconds)"
  echo "  2. Find VyOS IP: ip neigh show dev br-wan"
  echo "  3. SSH to VyOS: ssh vyos@<VYOS_IP> (password: vyos)"
  echo "  4. Install VyOS to disk: install image"
  echo "     - Choose 'S' for Serial console when prompted"
  echo "     - Use option '2' (default config) for boot config"
  echo "  5. Reboot VyOS: reboot"
  echo "  6. If VM doesn't restart, manually start: sudo virsh start vyos"
  echo "  7. Connect via serial console: sudo virsh console vyos"
  echo "  8. Load factory config (see README.md for details)"
else
  echo "Next steps (BAREMETAL mode):"
  echo "  1. Reboot the host: sudo reboot"
  echo "  2. After reboot, connect to VyOS console: sudo virsh console vyos"
  echo "  3. Login with: vyos / vyos"
  echo "  4. Install VyOS: install image"
  echo "     - Choose 'S' for Serial console when prompted"
  echo "     - Use option '2' (default config) for boot config"
  echo "  5. Reboot VyOS: reboot"
  echo "  6. If VM doesn't restart, manually start it: sudo virsh start vyos"
  echo "  7. Load factory config (see README.md for details)"
fi
echo ""
echo "For uCentral cloud management setup, see README-Ucentral.md"
echo "======================================================================"
