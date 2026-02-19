# uCentral Client Setup for OLG

**Quick reference guide** for setting up the uCentral client container on OpenLAN Gateway.

---

## Prerequisites

1. **VyOS VM must be running** - Follow [README.md](README.md) installation instructions first
2. **Docker is installed** - Automatically installed by `setup-vyos-*.sh` scripts
3. **For VM installations:** Set `OLG_ISO_PLATFORM="VM"` in `/opt/staging_scripts/setup-config`
4. **VyOS ISO version:** Update `ISO_URL` in setup-config if needed (see Releases section below)

---

## Quick Setup Steps

### 1. Create the uCentral Container

From the OLG host (as `olgadm` user):

```bash
# Setup the container and network
sudo /opt/staging_scripts/ucentral-setup.sh setup

# Access the container shell
sudo /opt/staging_scripts/ucentral-setup.sh shell
```

**Cleanup command (if needed):**
```bash
sudo /opt/staging_scripts/ucentral-setup.sh cleanup
```

### 2. Install Certificates

Copy your SSL certificates to the container (from OLG host):

```bash
# Certificate files must be named exactly as shown:
# - operational.pem (client certificate)
# - operational.ca (CA certificate chain)
# - key.pem (private key)

sudo docker cp operational.pem ucentral-olg:/etc/ucentral/
sudo docker cp operational.ca ucentral-olg:/etc/ucentral/
sudo docker cp key.pem ucentral-olg:/etc/ucentral/
```

**Certificate file naming:**
- `operational.pem` - Client certificate for this device
- `operational.ca` - CA certificate chain (trusted root CAs)
- `key.pem` - Private key matching the client certificate

### 3. Configure VyOS API Connection

**Get VyOS WAN IP first** (from OLG host):
```bash
sudo virsh console vyos
# In VyOS: show interfaces ethernet eth0
# Note the IP address (e.g., 192.168.3.8)
```

**Create vyos-info.json** (inside uCentral container):
```bash
echo '{"host":"https://192.168.3.8","key":"ucentral-secret-key"}' > /etc/ucentral/vyos-info.json
```

⚠️ **Important:** Replace `192.168.3.8` with your actual VyOS WAN IP address

### 4. Create uCentral Configuration Files

**Inside the uCentral container**, create the following configuration files:

#### 4a. Create `/etc/config/ucentral`

This is the main configuration file in UCI format:

```bash
cat > /etc/config/ucentral << 'EOF'
config ucentral 'config'
    option serial 'YOUR_DEVICE_SERIAL'
    option debug '1'
    option server 'your-gateway.example.com'
    option port '15002'
    option insecure '1'
EOF
```

**Configuration parameters:**
- `serial` - Device serial number (must match certificate CN)
- `debug` - Enable debug logging (1=enabled, 0=disabled)
- `server` - Cloud controller hostname or IP
- `port` - Cloud controller port (typically 15002)
- `insecure` - Skip TLS verification (1=skip, 0=verify)

⚠️ **Important:** Replace `YOUR_DEVICE_SERIAL` with your device's serial number and `your-gateway.example.com` with your cloud controller hostname.

#### 4b. Create shadow copy

```bash
mkdir -p /etc/config-shadow
cp /etc/config/ucentral /etc/config-shadow/ucentral
```

#### 4c. Create `/etc/ucentral/gateway.json`

```bash
cat > /etc/ucentral/gateway.json << 'EOF'
{
  "uuid": 1,
  "serial": "YOUR_DEVICE_SERIAL",
  "firmware": "OLG-v0.0.5",
  "config": {}
}
EOF
```

**Gateway JSON parameters:**
- `uuid` - Configuration version number (increment on changes)
- `serial` - Device serial number (must match /etc/config/ucentral)
- `firmware` - Firmware version string
- `config` - Current applied configuration (initially empty)

⚠️ **Important:** Replace `YOUR_DEVICE_SERIAL` with your device's serial number.

#### 4d. Create `/tmp/pstore` directory

```bash
mkdir -p /tmp/pstore
cat > /tmp/pstore/boot_cause.json << 'EOF'
{
  "timestamp": 0,
  "cause": "manual"
}
EOF
```

### 5. Enable VyOS HTTPS API (Optional)

From VyOS console:
```bash
configure
set service https
set service https listen-address 0.0.0.0
set service https api keys id ucentral key 'ucentral-secret-key'
commit
save
exit
```

### 6. Start the uCentral Client

Inside the uCentral container:

```bash
# Start ubusd first (required by uCentral)
/sbin/ubusd &

# Wait a moment for ubusd to initialize
sleep 2

# Start uCentral client (reads config from /etc/config/ucentral)
/usr/sbin/ucentral -d
```

**Notes:**
- The `-d` flag enables debug mode
- Configuration is read from `/etc/config/ucentral` (not command-line args)
- Serial number, server, and port are taken from the config file
- ubusd must be running before starting uCentral

## Important Notes

⚠️ **VyOS must be running** before starting the uCentral client

⚠️ **If VyOS WAN IP changes:** Update `/etc/ucentral/vyos-info.json` in the container and restart the uCentral client

## Troubleshooting

### Common Issues

**SSL Certificate Errors:**
- Check certificate chain includes gateway CA
- Verify gateway truststore trusts client CA
- Ensure certificates are copied to `/etc/ucentral/` in container

**Connection Problems:**
- Verify `/etc/ucentral/vyos-info.json` format is correct (see step 3 above)
- Check VyOS WAN IP is accessible from container
- Ensure gateway URL resolves correctly

**vyos-info.json Format:**
✅ **Correct format:**
```json
{"host":"https://192.168.3.8","key":"any-value"}
```

❌ **Wrong format:**
```json
{"host":"192.168.3.8","port":443,"username":"vyos","password":"vyos"}
```

📖 **For operational procedures, see:**
- [docs/OLG_SYSTEM_RESTART_GUIDE.md](docs/OLG_SYSTEM_RESTART_GUIDE.md)

---

## Releases
| Release    | Description |   Link |
| -------- | ------- | ------- |
| VYOS ISO  | This ISO supports configuration from OpenWifi Cloud Controller | https://drive.usercontent.google.com/download?id=14W0hnFhM64b8_jn1CwDWiPybntIrBzlh&confirm=t |
| OLG Installer ISO | This ISO supports ucentral-client and vyos integration and configuration from the cloud | https://drive.usercontent.google.com/download?id=1RK5dDQmFQX1l32719r0I7d88NVVyNKOl&confirm=t  |
