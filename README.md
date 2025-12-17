# Installer for OpenLAN Gateway

Project aimed at building ISOs for OpenLAN Gateway

## Requirements

- Docker
- Linux or macOS operating system (sorry not sorry Windows)

## Building an ISO

1. Run `script/build`

The result of this will be an ISO in the project working folder.

## Installing OpenLAN Gateway

### Install from ISO and VyOS VM configuration
- Boot on the ISO, once the install is completed the server will power-off
- Power back the server
- Login to the Linux host with username `olgadm` and password `olgadm`
- Edit `/opt/staging_scripts/setup-config` and adgst the network interface names and if required the VyOS VM sizing parameters
    - You might need to adjust the VyOS rolling release path. Reference: https://github.com/vyos/vyos-nightly-build/releases
- Run the setup script:
    - `sudo /opt/staging_scripts/setup-vyos-bridge.sh` to use the network bridge method
    - `sudo /opt/staging_scripts/setup-vyos-hw-passthru.sh` to use the hardware passthru for the network interfaces (WIP)
- Reboot the host
- Connect to the VyOS console with `virsh console vyos`
- Login with username `vyos` and password `vyos`
- Type `install image` and press Enter.
- Follow the prompts (you can use all defaults)
- Once completed, type `reboot` to reboot the VM
- For some reason the VyOS VM does not reboot after this first `reboot` command. You must restart it manually with `virsh start vyos`

### Load the initial factory default configuration

The factory configuration consists of:

- `eth0` as the WAN interface in DHCP
- `eth1` as the LAN interface
- 3 VLANs:
    - VLAN 100 for the switches
    - VLAN 101 for the APs
    - VLAN 1000 for the guest devices
- Each VLAN has it's own DHCP scope

Here is how to load this configuration:

- Open a console to the VyOS console with `virsh console vyos`
- If required login with your credentials
- Mound the ISO containing the configs
    ```
    sudo mkdir /opt/vyos-configs ; sudo mount /dev/sr1 /opt/vyos-configs
    ```
- Go in config mode with `config`
- Load the factory config with:
    ```
    source /opt/olg-configs/vyos-factory-config
    commit
    save
    exit
    ```

## Testes platforms

- MinisForum MS-01

## Contributing

- Create an issue
- Create a branch and an assoiated PR
- Code
- Ask for review and get your changes merged

### Protip

Use the Shipit CLI (https://gitlab.com/intello/shipit-cli-go)

This allows you to create the branch and associated PR in one simple command. The branch and PR will use a standardized naming scheme.

![image](docs/shipit-screenshot.png)




