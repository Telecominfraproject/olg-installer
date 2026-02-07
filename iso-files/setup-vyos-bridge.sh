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

# Make sure we have all the minimum required interfaces
for IFACE in "$WAN_IF" "$LAN_IF"; do
  if ! ip link show "$IFACE" >/dev/null 2>&1; then
    echo "Interface $IFACE not found. Adjust WAN_IF/LAN_IF in the script."; exit 1
  fi
done

echo ">>> Set the host hostname"
/opt/staging_scripts/set-hostname

echo ">>> Installing virtualization packages..."
apt-get update -y
apt-get install -y qemu-kvm libvirt-daemon-system libvirt-clients virtinst bridge-utils cloud-image-utils libguestfs-tools xorriso genisoimage syslinux-utils

echo ">>> Installing Docker..."
curl -fsSL https://get.docker.com -o get-docker.sh && sudo sh get-docker.sh
rm -f get-docker.sh

# Get VyOS ISO
# All Downloads/Updates should be done on stable network, before network configurations are changed
if [[ ! -f "$ISO_PATH" ]]; then
  echo ">>> Downloading VyOS ISO to $ISO_PATH"
  curl -fL $ISO_URL -o $ISO_PATH
else
  echo ">>> VyOS ISO already present at $ISO_PATH"
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
echo br_netfilter | sudo tee /etc/modules-load.d/br_netfilter.conf
sudo modprobe br_netfilter
sudo tee /etc/sysctl.d/99-bridge-nf-off.conf >/dev/null <<'EOF'
net.bridge.bridge-nf-call-iptables=0
net.bridge.bridge-nf-call-ip6tables=0
net.bridge.bridge-nf-call-arptables=0
EOF
sudo sysctl --system

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
  --cdrom "$ISO_PATH" \
  --os-variant debian12 \
  --network bridge="$BR_WAN",model=virtio \
  --network bridge="$BR_LAN",model=virtio \
  --graphics vnc \
  --hvm \
  --virt-type kvm \
  --disk path="$DISK_PATH",bus=virtio,size="$DISK_GB" \
  --disk /var/lib/libvirt/boot/vyos-configs.iso,device=cdrom \
  --noautoconsole

# Set the VM to autostart on host boot
virsh autostart $VM_NAME

echo ">>> Setting up uCentral persistent directories..."
mkdir -p /opt/ucentral-persistent/{vyos/templates,config,config-shadow,ucentral}

echo ">>> Copying uCentral customizations..."
if [ -d "/opt/staging_scripts/iso-files/ucentral-customizations" ]; then
  cp /opt/staging_scripts/iso-files/ucentral-customizations/capabilities.uc \
     /opt/ucentral-persistent/ 2>/dev/null || echo "Warning: capabilities.uc not found"

  cp -r /opt/staging_scripts/iso-files/ucentral-customizations/vyos/* \
        /opt/ucentral-persistent/vyos/ 2>/dev/null || echo "Warning: vyos files not found"

  echo ">>> Setting permissions..."
  chown -R root:root /opt/ucentral-persistent
  chmod -R 755 /opt/ucentral-persistent

  echo "[✓] uCentral customizations installed to /opt/ucentral-persistent/"
else
  echo "[!] Warning: uCentral customizations not found in /opt/staging_scripts/iso-files/"
  echo "    You may need to manually copy .uc files for VyOS integration."
fi

echo ""
echo "======================================================================"
echo "VyOS VM setup complete!"
echo "======================================================================"
echo ""
echo "Next steps:"
echo "  1. Reboot the host: sudo reboot"
echo "  2. After reboot, connect to VyOS console: sudo virsh console vyos"
echo "  3. Login with: vyos / vyos"
echo "  4. Install VyOS: install image (follow prompts, use defaults)"
echo "  5. Reboot VyOS: reboot"
echo "  6. If VM doesn't restart, manually start it: sudo virsh start vyos"
echo "  7. Load factory config (see README.md for details)"
echo ""
echo "For uCentral cloud management setup, see README-Ucentral.md"
echo "======================================================================"
