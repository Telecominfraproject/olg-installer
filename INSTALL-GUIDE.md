# OLG Installation Guide

Complete step-by-step installation guide for Open LAN Gateway with VyOS and uCentral cloud management.

## Prerequisites

- Physical hardware with at least 3 network interfaces (WAN, LAN, Admin)
- Bootable USB drive with OLG ISO
- Network access for downloading VyOS ISO and Docker images

## Phase 1: Install OLG Host OS

### Step 1: Boot from USB and Install

1. Insert USB drive with OLG ISO
2. Boot from USB (system should auto-detect USB boot)
3. Wait for automated Ubuntu 24.04 installation to complete
4. System will automatically power off when installation is complete

### Step 2: First Boot and Login

1. Remove USB drive
2. Power on the system
3. Login as `olgadm` with password `olgadm`
4. Verify staging scripts are present:
   ```bash
   ls -la /opt/staging_scripts/
   ```

## Phase 2: Configure Network Interfaces

### Step 3: Identify Your Network Interfaces

1. List all network interfaces:
   ```bash
   ip link show
   ```

2. Note the names of your three interfaces:
   - **WAN interface**: External network/internet connection
   - **LAN interface**: Internal network for switches/APs
   - **Admin interface**: Management network (already configured for SSH)

### Step 4: Edit Setup Configuration

1. Edit the setup configuration file:
   ```bash
   sudo nano /opt/staging_scripts/setup-config
   ```

2. Update these variables with your interface names:
   ```bash
   WAN_IF="enp88s0"      # Your WAN interface name
   LAN_IF="enp2s0f1np1"  # Your LAN interface name
   ADMIN_IF="enp87s0"    # Your admin interface name
   ```

3. For VM testing, set platform to VM (enables DHCP on br-wan):
   ```bash
   OLG_ISO_PLATFORM="VM"  # Use "BAREMETAL" for production hardware
   ```

4. Save and exit (Ctrl+O, Enter, Ctrl+X)

## Phase 3: Setup VyOS VM and Bridges

### Step 5: Run VyOS Bridge Setup

This script will:
- Install Docker and virtualization packages
- Download and verify VyOS ISO
- Create network bridges (br-wan, br-lan)
- Create and start VyOS VM
- Set up uCentral persistent directories

Run the setup script:
```bash
sudo /opt/staging_scripts/setup-vyos-bridge.sh
```

**Important notes:**
- Script will bridge your WAN and LAN interfaces (temporary network disruption)
- Download may take several minutes depending on connection speed
- VyOS VM will be created but not yet installed

### Step 6: Reboot the Host (Optional)

**Note:** If `sudo virsh list` shows VyOS is already running, you can skip this reboot and proceed directly to Step 7.

```bash
sudo reboot
```

## Phase 4: Install VyOS Operating System

### Step 7: Connect to VyOS Console

After reboot, connect to the VyOS VM console:
```bash
sudo virsh console vyos
```

Login credentials:
- Username: `vyos`
- Password: `vyos`

### Step 8: Install VyOS to Disk

1. Run the VyOS installer:
   ```bash
   install image
   ```

2. Answer the prompts (use defaults):
   - Would you like to continue? **Yes**
   - Partition: **Auto** (uses entire disk)
   - Install the image: **Yes**
   - Configure password: Enter a password (e.g., `vyos`)
   - Which config file to use? **config.boot** (from ISO)

3. Installation will complete in 1-2 minutes

### Step 9: Reboot VyOS

1. Attempt to reboot VyOS:
   ```bash
   reboot
   ```

2. Exit the console (press `Ctrl+]`)

3. **Known issue:** VyOS may not reboot automatically
   - Wait 30 seconds
   - Manually start the VM:
     ```bash
     sudo virsh start vyos
     ```

4. Reconnect to console:
   ```bash
   sudo virsh console vyos
   ```

5. Login with `vyos` and the password you set

### Step 10: Load Factory Configuration

The factory configuration is on the second CD-ROM (`/dev/sr1`):

1. Create mount point and mount the config ISO:
   ```bash
   sudo mkdir -p /mnt/config
   sudo mount /dev/sr1 /mnt/config
   ```

2. Load the factory configuration:
   ```bash
   configure
   source /mnt/config/vyos-factory-config
   commit
   save
   exit
   ```

3. Exit console (Ctrl+])

## Phase 5: Get VyOS Network Information

### Step 11: Determine VyOS WAN IP Address

VyOS should now have an IP address on the WAN network. Find it using one of these methods:

**Method A: From VyOS Console**
```bash
sudo virsh console vyos
show interfaces
# Note the IP address on eth0 (WAN interface)
# Example: 192.168.3.35/24
```

**Method B: Check libvirt DHCP leases** (may not work in all setups)
```bash
sudo virsh domifaddr vyos --source lease
```

**Method C: Check your router/gateway DHCP leases**
- Look for a device with MAC starting with `52:54:00`
- This is the VyOS VM's MAC prefix

### Step 12: Note on VyOS API Access

**Note:** The OLG host cannot directly reach the VyOS WAN IP due to network isolation (host is on admin network 192.168.2.x, VyOS WAN is on 192.168.3.x). VyOS API connectivity will be verified from the container in Step 18.

## Phase 6: Setup uCentral Container

### Step 13: Create vyos-info.json

Create the VyOS API configuration file with the IP from Step 11:

```bash
echo '{"host":"https://VYOS_WAN_IP","port":443,"key":"MY-HTTPS-API-PLAINTEXT-KEY"}' | sudo tee /opt/ucentral-persistent/ucentral/vyos-info.json
```

**Important:** Replace `VYOS_WAN_IP` with the actual IP address (e.g., `192.168.3.35`)

Verify the file was created correctly:
```bash
sudo cat /opt/ucentral-persistent/ucentral/vyos-info.json
```

### Step 14: Create uCentral Configuration Files

Before running the container, create the required configuration files:

**Create gateway.json (cloud controller configuration):**

For local testing without cloud connectivity:
```bash
echo '{"server":"localhost","port":443,"allow-self-signed":true}' | sudo tee /opt/ucentral-persistent/ucentral/gateway.json
```

**Note:** When you're ready for cloud connectivity (Phase 7), you'll update this file with your actual cloud controller URL.

Verify the file was created:
```bash
sudo cat /opt/ucentral-persistent/ucentral/gateway.json
```

### Step 15: Run uCentral Setup

This script will:
- Create and start the uCentral Docker container
- Set up networking (veth pair on br-wan)
- Obtain DHCP IP for container
- Fix state.uc symlink to point to VyOS version

Run the setup:
```bash
sudo /opt/staging_scripts/ucentral-setup.sh setup
```

Verify the container is running:
```bash
sudo docker ps
```

Should show: `ucentral-olg` container with status "Up"

### Step 16: Create uCentral Service Configuration

After the container is running, create the required service configuration files inside the container:

**Shell into the container:**
```bash
sudo docker exec -it ucentral-olg /bin/ash
```

**Inside the container, create /etc/config/ucentral using vi:**
```bash
vi /etc/config/ucentral
```

Press `i` to enter insert mode, then paste these lines:
```
config ucentral config
	option serial "00000000000000000001"
	option debug 1
	option insecure 1
```

Press `Esc`, then type `:wq` and press `Enter` to save and exit.

**Copy to shadow directory:**
```bash
cp /etc/config/ucentral /etc/config-shadow/ucentral
```

**Create /etc/config/state using vi:**
```bash
vi /etc/config/state
```

Press `i` to enter insert mode, then paste these lines:
```
config stats stats
	option interval 600

config health health
	option interval 120

config ui ui
	option offline_trigger 60
```

Press `Esc`, then type `:wq` and press `Enter` to save and exit.

**Create pstore file:**
```bash
echo '{"pstore":[{"boot_cause":"manual"}]}' > /tmp/pstore
```

**Verify the files were created:**
```bash
cat /etc/config/ucentral
cat /etc/config/state
```

**Exit the container:**
```bash
exit
```

### Step 17: Start uCentral Services

Now start the uCentral client and state reporting services:

```bash
# Start uCentral main service
sudo docker exec ucentral-olg /etc/init.d/ucentral start

# Start state reporting service
sudo docker exec ucentral-olg /etc/init.d/ucentral-state start

# Wait a few seconds for services to initialize
sleep 5

# Verify services are running
sudo docker exec ucentral-olg ps w | grep ucentral
```

You should see two processes:
- `{ucentral}` - Main uCentral daemon
- `{ucentral-state}` - State reporting daemon

Check logs to verify successful startup:
```bash
sudo docker exec ucentral-olg logread | tail -30
```

**Expected messages:**
- `state: start healthcheck in 120 seconds`
- `state: start state in 600 seconds`
- `ucentral: failed to start LWS context` (normal without cloud connectivity)
- `state: going offline` (normal without cloud connectivity)

**Important:** The "failed to start LWS context" and "going offline" messages are EXPECTED when not connected to a cloud controller. These are not errors.

### Step 18: Verify Container Networking

Check that the container can reach VyOS:

```bash
# Check container IP address
sudo docker exec ucentral-olg ip addr show eth0

# Ping VyOS from container (use IP from Step 11)
sudo docker exec ucentral-olg ping -c 2 VYOS_WAN_IP
```

Both commands should succeed.

## Phase 7: Configure Cloud Management (Optional)

If you want to connect to OpenWiFi Cloud Controller:

### Step 19: Copy Certificates

Copy your TIP certificates to the container persistent storage:

**If you have a tar file with certificates:**
```bash
# From your Mac, copy the tar to OLG host
scp -O /path/to/certs/YOUR_SERIAL.tar olgadm@OLG_IP:~/

# On OLG host, extract certificates
sudo mkdir -p /opt/ucentral-persistent/ucentral/certs
sudo tar -xf ~/YOUR_SERIAL.tar -C /opt/ucentral-persistent/ucentral/certs/
```

**If you have individual certificate files:**
```bash
# From your Mac, copy individual files
scp -O /path/to/certs/*.pem olgadm@OLG_IP:~/

# On OLG host, copy to persistent storage
sudo mkdir -p /opt/ucentral-persistent/ucentral/certs
sudo cp ~/*.pem /opt/ucentral-persistent/ucentral/certs/
```

**Rename certificates to the format uCentral expects:**
```bash
# uCentral expects specific naming: operational.pem, operational.ca, key.pem
sudo docker exec ucentral-olg cp /etc/ucentral/certs/cert.pem /etc/ucentral/operational.pem
sudo docker exec ucentral-olg cp /etc/ucentral/certs/cas.pem /etc/ucentral/operational.ca
sudo docker exec ucentral-olg cp /etc/ucentral/certs/key.pem /etc/ucentral/key.pem
```

Verify files are in place:
```bash
sudo docker exec ucentral-olg ls -la /etc/ucentral/ | grep -E "operational|key"
```

Should show:
- `operational.pem` - Client certificate
- `operational.ca` - CA certificate bundle
- `key.pem` - Private key

### Step 20: Update Gateway Configuration

Update gateway.json with your cloud controller information:

```bash
# Edit gateway.json with correct certificate paths
sudo docker exec -it ucentral-olg vi /etc/ucentral/gateway.json
```

**Important:** Use the `operational.*` naming, not `cert.*`. Example:
```json
{"server":"YOUR.CLOUD.CONTROLLER.COM","port":15002,"allow-self-signed":true,"cert":"/etc/ucentral/operational.pem","ca":"/etc/ucentral/operational.ca"}
```

**Note:** Set `"allow-self-signed":true` if your cloud controller uses self-signed certificates.

Verify the configuration:
```bash
sudo docker exec ucentral-olg cat /etc/ucentral/gateway.json
```

### Step 21: Configure uCentral Client Serial Number

Update the serial number in the uCentral configuration:

**IMPORTANT:** The uCentral init script uses a "shadow file" pattern where `/etc/config-shadow/ucentral` is the source of truth. On service restart, the init script automatically copies the shadow file to `/etc/config/ucentral`. Therefore, you must edit the **shadow file** to make permanent changes.

```bash
# Edit the shadow file (source of truth)
sudo docker exec -it ucentral-olg vi /etc/config-shadow/ucentral
```

Change the serial number line:
```
option serial "YOUR_ACTUAL_SERIAL_NUMBER"
```

**Note:** You do NOT need to manually copy from shadow to config - the init script does this automatically on restart.

### Step 22: Recreate pstore and Restart uCentral Client

**Important:** The uCentral init script requires `/tmp/pstore` but doesn't create it automatically (this is a bug in the init script). You must recreate it before each restart:

```bash
# Recreate pstore file (workaround for init script bug)
sudo docker exec ucentral-olg sh -c 'echo "{\"pstore\":[{\"boot_cause\":\"manual\"}]}" > /tmp/pstore'

# Now restart uCentral
sudo docker exec ucentral-olg /etc/init.d/ucentral restart
```

Check logs for cloud connection:
```bash
sudo docker exec ucentral-olg logread | tail -40
```

**Expected success messages:**
- `cloud_discover: Connected to cloud`
- `ucentral: connection established`
- `state: state offline -> online`
- `TX: {"jsonrpc":"2.0","method":"connect"...` (sending capabilities to cloud)

**Note:** The "failed to start LWS context" messages should disappear once connected. If they persist, check:
1. Certificate naming is correct (operational.pem, operational.ca, key.pem)
2. Gateway serial number matches the certificate
3. Gateway is registered in the cloud controller
4. Network connectivity to cloud controller (test with curl)

## Verification Checklist

Before considering the installation complete, verify:

- [ ] OLG host is accessible via SSH on admin interface
- [ ] VyOS VM is running: `sudo virsh list --all`
- [ ] VyOS has WAN and LAN IP addresses
- [ ] VyOS API is accessible (check vyos-info.json IP)
- [ ] uCentral container is running: `sudo docker ps`
- [ ] Container can ping VyOS WAN IP
- [ ] Certificates are in place (if using cloud management)
- [ ] uCentral client connects to cloud (if configured)

## Troubleshooting

### Container Can't Reach VyOS

Check that vyos-info.json has the correct IP:
```bash
sudo cat /opt/ucentral-persistent/ucentral/vyos-info.json
```

If VyOS IP changed, update the file and restart the container:
```bash
sudo /opt/staging_scripts/ucentral-setup.sh cleanup
sudo /opt/staging_scripts/ucentral-setup.sh setup
```

### VyOS Not Responding

Verify VyOS is running:
```bash
sudo virsh list --all
```

If status is "shut off", start it:
```bash
sudo virsh start vyos
```

### Can't Access OLG Host

Verify admin interface has correct IP:
```bash
ip addr show ADMIN_IF
```

Check that admin interface was NOT bridged (should still have its original IP).

### Container Logs Not Showing

Use logread (not docker logs):
```bash
sudo docker exec ucentral-olg logread
sudo docker exec ucentral-olg logread -f  # Follow mode
```

## Next Steps

Once installation is complete:

1. **Test Configuration Push**: Push a test config from cloud controller
2. **Monitor Logs**: Watch `sudo docker exec ucentral-olg logread -f`
3. **Verify VyOS Config**: Connect to VyOS console and run `show configuration`
4. **Connect Devices**: Connect switches/APs to LAN interface
5. **Verify DHCP**: Check that devices get IPs in configured VLANs

## Support

For issues or questions:
- Review `README.md` for detailed technical information
- Check `README-Ucentral.md` for cloud management details
- Review `docs/OLG_SYSTEM_RESTART_GUIDE.md` for operational procedures
