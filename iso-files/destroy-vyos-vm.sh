#!/usr/bin/env bash

set -euo pipefail

VM_NAME="vyos"
IMAGES_DIR="/var/lib/libvirt/images"
ISO_PATH="$IMAGES_DIR/vyos.iso"
DISK_PATH="$IMAGES_DIR/${VM_NAME}.qcow2"
NETPLAN_FILE="/etc/netplan/99-vyos-bridges.yaml"

# ====== Preflight ======
if [[ $EUID -ne 0 ]]; then
  echo "Please run as root (sudo $0)"; exit 1
fi

echo "============================================"
echo "VyOS VM Destruction Script"
echo "============================================"
echo ""
echo "This script will:"
echo "  1. Stop and destroy the VyOS VM"
echo "  2. Undefine the VM from libvirt"
echo "  3. Remove VM disk image"
echo "  4. Optionally remove VyOS ISO"
echo "  5. Optionally remove bridge network configuration"
echo ""

# Check if VM exists
if ! virsh dominfo "$VM_NAME" >/dev/null 2>&1; then
  echo ">>> VM '$VM_NAME' does not exist or is not defined."
else
  # Check if VM is running
  if virsh list --state-running | grep -q "$VM_NAME"; then
    echo ">>> Stopping VM '$VM_NAME'..."
    virsh destroy "$VM_NAME"
    echo "    VM stopped."
  else
    echo ">>> VM '$VM_NAME' is not running."
  fi

  # Undefine the VM
  echo ">>> Undefining VM '$VM_NAME'..."
  virsh undefine "$VM_NAME" --nvram 2>/dev/null || virsh undefine "$VM_NAME"
  echo "    VM undefined."
fi

# Remove disk image
if [[ -f "$DISK_PATH" ]]; then
  echo ">>> Removing VM disk: $DISK_PATH"
  rm -f "$DISK_PATH"
  echo "    Disk removed."
else
  echo ">>> VM disk not found at $DISK_PATH (already removed or never created)."
fi

# Ask about ISO removal
if [[ -f "$ISO_PATH" ]]; then
  echo ""
  read -p "Remove VyOS ISO at $ISO_PATH? (y/N) " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ">>> Removing VyOS ISO: $ISO_PATH"
    rm -f "$ISO_PATH"
    echo "    ISO removed."
  else
    echo ">>> Keeping VyOS ISO at $ISO_PATH"
  fi
else
  echo ">>> VyOS ISO not found at $ISO_PATH (already removed or never downloaded)."
fi

# Ask about bridge network configuration removal
if [[ -f "$NETPLAN_FILE" ]]; then
  echo ""
  echo "WARNING: Removing the netplan bridge configuration will restore"
  echo "         the network interfaces to their previous state, but may"
  echo "         cause network disruption."
  echo ""
  read -p "Remove bridge network configuration at $NETPLAN_FILE? (y/N) " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ">>> Removing netplan bridge configuration: $NETPLAN_FILE"
    rm -f "$NETPLAN_FILE"
    echo "    Configuration file removed."
    echo ""
    read -p "Apply netplan changes now? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      echo ">>> Applying netplan..."
      netplan apply
      echo "    Netplan applied."
    else
      echo ">>> Skipping netplan apply. Run 'netplan apply' manually to restore interfaces."
    fi
  else
    echo ">>> Keeping bridge network configuration at $NETPLAN_FILE"
  fi
else
  echo ">>> Bridge network configuration not found at $NETPLAN_FILE"
fi

echo ""
echo "============================================"
echo "VyOS VM Cleanup Complete!"
echo "============================================"
echo ""
echo "Summary:"
echo "  - VM '$VM_NAME' has been destroyed and undefined"
echo "  - VM disk has been removed"
echo ""
echo "Note: If you used PCI passthrough (setup-vyos-hw-passthru.sh),"
echo "      the physical network interfaces should automatically return"
echo "      to the host when the VM is destroyed. You may need to reload"
echo "      the appropriate driver or reboot to fully restore them."
echo ""
