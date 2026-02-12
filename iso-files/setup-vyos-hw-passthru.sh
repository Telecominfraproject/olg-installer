#!/usr/bin/env bash

set -euo pipefail

# Source our configs
source /opt/staging_scripts/setup-config

# Some statis configs
VM_NAME="vyos"
IMAGES_DIR="/var/lib/libvirt/images"
ISO_PATH="$IMAGES_DIR/vyos.iso"
DISK_PATH="$IMAGES_DIR/${VM_NAME}.qcow2"

# Make sure we are running as root
if [[ $EUID -ne 0 ]]; then
  echo "Please run as root (sudo $0)"; exit 1
fi

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

echo ">>> Installing Docker..."
sh /opt/staging_scripts/get-docker.sh

mkdir -p "$IMAGES_DIR"

# Get PCI addresses for interfaces
echo ">>> Detecting PCI addresses for network interfaces..."
WAN_PCI=$(basename $(readlink -f /sys/class/net/$WAN_IF/device))
LAN_PCI=$(basename $(readlink -f /sys/class/net/$LAN_IF/device))

if [[ -z "$WAN_PCI" ]] || [[ -z "$LAN_PCI" ]]; then
  echo "ERROR: Could not determine PCI addresses for interfaces"
  echo "WAN_IF ($WAN_IF): $WAN_PCI"
  echo "LAN_IF ($LAN_IF): $LAN_PCI"
  exit 1
fi

echo "WAN interface $WAN_IF is at PCI address: $WAN_PCI"
echo "LAN interface $LAN_IF is at PCI address: $LAN_PCI"

# Parse PCI address (format: 0000:04:00.0 -> domain:bus:slot.function)
WAN_DOMAIN=$(echo $WAN_PCI | cut -d: -f1)
WAN_BUS=$(echo $WAN_PCI | cut -d: -f2)
WAN_SLOT=$(echo $WAN_PCI | cut -d: -f3 | cut -d. -f1)
WAN_FUNC=$(echo $WAN_PCI | cut -d. -f2)

LAN_DOMAIN=$(echo $LAN_PCI | cut -d: -f1)
LAN_BUS=$(echo $LAN_PCI | cut -d: -f2)
LAN_SLOT=$(echo $LAN_PCI | cut -d: -f3 | cut -d. -f1)
LAN_FUNC=$(echo $LAN_PCI | cut -d. -f2)

# Enable IOMMU and VFIO
echo ">>> Checking IOMMU support..."
if ! dmesg | grep -q "IOMMU enabled"; then
  echo "WARNING: IOMMU may not be enabled. You may need to:"
  echo "  1. Enable VT-d/AMD-Vi in BIOS"
  echo "  2. Add 'intel_iommu=on' or 'amd_iommu=on' to kernel parameters"
  echo "  3. Reboot the system"
  echo ""
  read -p "Continue anyway? (y/N) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
  fi
fi

echo ">>> Configuring VFIO for PCI passthrough..."

# Load VFIO modules
modprobe vfio
modprobe vfio_pci
modprobe vfio_iommu_type1

# Ensure modules load on boot
cat > /etc/modules-load.d/vfio.conf <<EOF
vfio
vfio_pci
vfio_iommu_type_1
EOF

# Get vendor and device IDs for the interfaces
WAN_VENDOR_DEVICE=$(lspci -n -s $WAN_PCI | awk '{print $3}')
LAN_VENDOR_DEVICE=$(lspci -n -s $LAN_PCI | awk '{print $3}')

echo "WAN device ID: $WAN_VENDOR_DEVICE"
echo "LAN device ID: $LAN_VENDOR_DEVICE"

# Unbind interfaces from current driver and bind to vfio-pci
echo ">>> Unbinding interfaces from host..."
for IFACE in "$WAN_IF" "$LAN_IF"; do
  if [[ -e "/sys/class/net/$IFACE" ]]; then
    ip link set $IFACE down
    DRIVER_PATH=$(readlink -f /sys/class/net/$IFACE/device/driver)
    if [[ -n "$DRIVER_PATH" ]]; then
      DRIVER_NAME=$(basename $DRIVER_PATH)
      PCI_ADDR=$(basename $(readlink -f /sys/class/net/$IFACE/device))
      echo "Unbinding $IFACE ($PCI_ADDR) from $DRIVER_NAME"
      echo "$PCI_ADDR" > /sys/bus/pci/drivers/$DRIVER_NAME/unbind 2>/dev/null || true
    fi
  fi
done

# Bind to vfio-pci
echo ">>> Binding interfaces to vfio-pci..."
for PCI_ADDR in "$WAN_PCI" "$LAN_PCI"; do
  if [[ ! -e "/sys/bus/pci/drivers/vfio-pci/$PCI_ADDR" ]]; then
    echo "$PCI_ADDR" > /sys/bus/pci/drivers/vfio-pci/bind 2>/dev/null || {
      # If bind fails, try adding the device ID first
      VENDOR_DEVICE=$(lspci -n -s $PCI_ADDR | awk '{print $3}')
      echo "$VENDOR_DEVICE" > /sys/bus/pci/drivers/vfio-pci/new_id 2>/dev/null || true
      echo "$PCI_ADDR" > /sys/bus/pci/drivers/vfio-pci/bind 2>/dev/null || true
    }
  fi
  echo "Bound $PCI_ADDR to vfio-pci"
done

# Get VyOS ISO
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

# Create & start VM with PCI passthrough and host CPU
echo ">>> Creating VyOS VM '$VM_NAME' with host CPU type and PCI passthrough..."

# Create a temporary XML file for the VM
TEMP_XML=$(mktemp)
cat > "$TEMP_XML" <<EOF
<domain type='kvm'>
  <name>$VM_NAME</name>
  <memory unit='MiB'>$RAM_MB</memory>
  <vcpu placement='static'>$VCPUS</vcpu>
  <os>
    <type arch='x86_64' machine='pc'>hvm</type>
    <boot dev='cdrom'/>
    <boot dev='hd'/>
  </os>
  <features>
    <acpi/>
    <apic/>
  </features>
  <cpu mode='host-passthrough' check='none'>
    <topology sockets='1' cores='$VCPUS' threads='1'/>
  </cpu>
  <clock offset='utc'>
    <timer name='rtc' tickpolicy='catchup'/>
    <timer name='pit' tickpolicy='delay'/>
    <timer name='hpet' present='no'/>
  </clock>
  <on_poweroff>destroy</on_poweroff>
  <on_reboot>restart</on_reboot>
  <on_crash>destroy</on_crash>
  <devices>
    <emulator>/usr/bin/qemu-system-x86_64</emulator>
    <disk type='file' device='disk'>
      <driver name='qemu' type='qcow2'/>
      <source file='$DISK_PATH'/>
      <target dev='vda' bus='virtio'/>
    </disk>
    <disk type='file' device='cdrom'>
      <driver name='qemu' type='raw'/>
      <source file='$ISO_PATH'/>
      <target dev='hdc' bus='ide'/>
      <readonly/>
    </disk>
    <disk type='file' device='cdrom'>
      <driver name='qemu' type='raw'/>
      <source file='/var/lib/libvirt/boot/vyos-configs.iso'/>
      <target dev='sdb' bus='sata'/>
      <readonly/>
    </disk>
    <hostdev mode='subsystem' type='pci' managed='yes'>
      <source>
        <address domain='0x$WAN_DOMAIN' bus='0x$WAN_BUS' slot='0x$WAN_SLOT' function='0x$WAN_FUNC'/>
      </source>
    </hostdev>
    <hostdev mode='subsystem' type='pci' managed='yes'>
      <source>
        <address domain='0x$LAN_DOMAIN' bus='0x$LAN_BUS' slot='0x$LAN_SLOT' function='0x$LAN_FUNC'/>
      </source>
    </hostdev>
    <controller type='usb' index='0' model='ich9-ehci1'/>
    <controller type='pci' index='0' model='pci-root'/>
    <serial type='pty'>
      <target type='isa-serial' port='0'>
        <model name='isa-serial'/>
      </target>
    </serial>
    <console type='pty'>
      <target type='serial' port='0'/>
    </console>
    <graphics type='vnc' port='-1' autoport='yes' listen='127.0.0.1'>
      <listen type='address' address='127.0.0.1'/>
    </graphics>
    <video>
      <model type='cirrus'/>
    </video>
  </devices>
</domain>
EOF

echo ">>> Defining VM from XML..."
virsh define "$TEMP_XML"
rm "$TEMP_XML"

# Set the VM o autostart on host boot
virsh autostart $VM_NAME

