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
      dhcp4: false
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


# Get VyOS ISO
if [[ ! -f "$ISO_PATH" ]]; then
  echo ">>> Downloading VyOS ISO to $ISO_PATH"
  curl -fL $ISO_URL -o $ISO_PATH
else
  echo ">>> VyOS ISO already present at $ISO_PATH"
fi

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
  --disk path=/var/lib/libvirt/images/vyos.qcow2,bus=virtio,size=8 \
  --disk /var/lib/libvirt/boot/vyos-configs.iso,device=cdrom \
  --noautoconsole

# Set the VM o autostart on host boot
virsh autostart $VM_NAME
