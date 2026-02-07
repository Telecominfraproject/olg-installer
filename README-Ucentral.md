# uCentral Client Setup for OLG

**Quick reference guide** for setting up the uCentral client container on OpenLAN Gateway.

📖 **For operational procedures, see:**
- **System restart guide:** [docs/OLG_SYSTEM_RESTART_GUIDE.md](docs/OLG_SYSTEM_RESTART_GUIDE.md)

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
sudo docker cp cert.pem ucentral-olg:/etc/ucentral/
sudo docker cp cas.pem ucentral-olg:/etc/ucentral/
sudo docker cp key.pem ucentral-olg:/etc/ucentral/
```

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

### 4. Enable VyOS HTTPS API (Optional)

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

### 5. Start the uCentral Client

Inside the uCentral container:
```bash
/usr/sbin/ucentral -S $SerialNum -s $URL -P 15002 -d
```

**Example:**
```bash
/usr/sbin/ucentral -S YOUR_DEVICE_SERIAL \
  -s your-gateway.example.com \
  -P 15002 -d
```

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
